part of 'main.dart';

/// In-memory display calculation, deliberately not a formal daily/period JSON.
/// Civil JST dates are inclusive. No prediction, preference or file is saved.
class PeriodSevenDisplayRequest {
  PeriodSevenDisplayRequest({
    required DateTime startDateJst,
    required DateTime endDateJst,
    required this.profile,
    required this.details,
    required this.requestedHouseSystem,
    required this.sourceName,
    required this.requireHighPrecision,
    required this.generatedAt,
  }) : startDateJst = DateTime.utc(
         startDateJst.year,
         startDateJst.month,
         startDateJst.day,
       ),
       endDateJst = DateTime.utc(
         endDateJst.year,
         endDateJst.month,
         endDateJst.day,
       ) {
    dayCount = this.endDateJst.difference(this.startDateJst).inDays + 1;
    if (dayCount < 1 || dayCount > 31 || sourceName.isEmpty) {
      throw ArgumentError(
        'Display calculation requires 1–31 consecutive days.',
      );
    }
    dayPlans = List.unmodifiable([
      for (var i = 0; i < dayCount; i++)
        DailySevenTimepointPlan.forJstDate(
          _monthlyDateLabel(this.startDateJst.add(Duration(days: i))),
        ),
    ]);
  }

  final DateTime startDateJst, endDateJst, generatedAt;
  final AstroProfile profile;
  final UserProfileDetails details;
  final HouseSystem requestedHouseSystem;
  final String sourceName;
  final bool requireHighPrecision;
  late final int dayCount;
  late final List<DailySevenTimepointPlan> dayPlans;
  int get listedPointCount => dayCount * 7;
  int get uniqueInstantCount => dayCount * 6 + 1;

  /// Private input token. It contains no readable profile information.
  String get inputIdentity => _periodSevenDisplayInputIdentity(
    profile: profile,
    details: details,
    requestedHouseSystem: requestedHouseSystem,
    sourceName: sourceName,
    requireHighPrecision: requireHighPrecision,
  );

  String get identity => sha256
      .convert(
        utf8.encode(
          jsonEncode([
            'pancyo_period_display_range_v1',
            inputIdentity,
            dayPlans.first.targetDateJst,
            dayPlans.last.targetDateJst,
            generatedAt.toIso8601String(),
          ]),
        ),
      )
      .toString();

  DailyConsultExportRequest dailyRequestAt(int index) {
    RangeError.checkValidIndex(index, dayPlans, 'index');
    return DailyConsultExportRequest(
      date: dayPlans[index].primaryNoon.instantUtc,
      profile: profile,
      details: details,
      requestedHouseSystem: requestedHouseSystem,
      sourceName: sourceName,
      requireHighPrecision: requireHighPrecision,
      generatedAt: generatedAt,
    );
  }
}

String _periodSevenDisplayInputIdentity({
  required AstroProfile profile,
  required UserProfileDetails details,
  required HouseSystem requestedHouseSystem,
  required String sourceName,
  required bool requireHighPrecision,
}) => sha256
    .convert(
      utf8.encode(
        jsonEncode([
          'pancyo_period_display_inputs_v1',
          profile.name,
          profile.birthDate,
          profile.birthClock?.cacheIdentity,
          profile.birthTime,
          profile.birthPlace,
          profile.theme,
          profile.savedProfileId,
          details.toJson(),
          requestedHouseSystem.name,
          sourceName,
          requireHighPrecision,
          NineAreaDailyForecast.modelVersion,
        ]),
      ),
    )
    .toString();

/// Validates display provenance plus the same seven exact-time forecasts and
/// independent noon snapshot used by the formal daily-v4 calculation.
void validatePeriodSevenDisplayDay({
  required Map<String, Object?> data,
  required DailyConsultExportRequest request,
}) {
  final plan = request.plan;
  final expectedInput = _periodSevenDisplayInputIdentity(
    profile: request.profile,
    details: request.details,
    requestedHouseSystem: request.requestedHouseSystem,
    sourceName: request.sourceName,
    requireHighPrecision: request.requireHighPrecision,
  );
  if (data['schema'] != 'pancyo_period_display_day_v1' ||
      data['generated_at'] != request.generatedAt.toIso8601String() ||
      data['target_date_jst'] != plan.targetDateJst ||
      data['input_identity'] != expectedInput ||
      data['time_zone'] != 'Asia/Tokyo' ||
      data['fixed_utc_offset'] != '+09:00') {
    throw StateError('表示用の日付・入力条件が一致しません。');
  }
  final source = _monthlyMap(data['calculation_source'], '表示用計算元');
  final house = _monthlyMap(data['house_calculation'], '表示用ハウス');
  final resolved = house['resolved_system'];
  if (source['provider'] != request.sourceName ||
      source['provider_uses_high_precision'] != request.requireHighPrecision ||
      house['requested_system'] != request.requestedHouseSystem.name ||
      resolved is! String ||
      !HouseSystem.values.any((value) => value.name == resolved)) {
    throw StateError('表示用の計算元・精度・ハウス方式が一致しません。');
  }
  final forecasts = _monthlyMap(data['intraday_forecasts'], '表示用7時点');
  final complete = _monthlyMap(forecasts['completeness'], '表示用完全性');
  if (forecasts['schema'] != 'pancyo_daily_intraday_forecasts_v1' ||
      forecasts['target_date_jst'] != plan.targetDateJst ||
      forecasts['time_zone'] != 'Asia/Tokyo' ||
      forecasts['fixed_utc_offset'] != '+09:00' ||
      forecasts['model_version'] != NineAreaDailyForecast.modelVersion ||
      complete['status'] != 'complete' ||
      complete['point_count'] != 7 ||
      complete['areas_per_point'] != 9 ||
      forecasts['felt_has_numeric_score'] != false ||
      forecasts['daily_scores_averaged_from_samples'] != false) {
    throw StateError('表示用の7時点・9項目が不完全です。');
  }
  _monthlyValidatePointList(
    rawPoints: forecasts['points'],
    plan: plan,
    label: '表示用予測時点',
  );
  _monthlyValidateForecastHouseSystem(forecasts['points'], resolved);
  final points = _monthlyList(forecasts['points'], '表示用予測時点');
  for (var index = 0; index < 7; index++) {
    final point = _monthlyMap(points[index], '表示用時点');
    final snapshot = _monthlyMap(point['nine_area_forecast'], '表示用9項目');
    final clock = plan.points[index];
    final dayStart = _intradayScoreDayStart(clock.instantUtc);
    if (snapshot['target_date_jst'] !=
            _monthlyDateLabel(
              clock.instantUtc.add(DailySevenTimepointPlan.jstOffset),
            ) ||
        snapshot['calculation_reference_jst'] !=
            NineAreaForecastSnapshot._issuedAtJst(clock.instantUtc) ||
        snapshot['uses_high_precision_astro_data'] !=
            request.requireHighPrecision ||
        point['score_day_start_utc'] != dayStart.toIso8601String() ||
        point['score_day_end_utc'] !=
            dayStart.add(const Duration(days: 1)).toIso8601String() ||
        point['calculation_origin'] !=
            (clock.isPrimaryNoon
                ? 'existing_noon_context'
                : 'sample_instant_context') ||
        point['void_penalty_rule'] != 'reference_only_zero_score_adjustment' ||
        point['void_interval_scope'] !=
            'existing_first_daily_interval_over_five_minutes') {
      throw StateError('表示用予測の時刻または日別ボイド参照範囲が不正です。');
    }
    for (final raw in _monthlyList(snapshot['areas'], '表示用9項目')) {
      final area = _monthlyMap(raw, '表示用項目');
      for (final field in ['name', 'summary', 'explanation']) {
        final text = area[field];
        if (text is! String || text.trim().isEmpty) {
          throw StateError('表示用予測の説明が不足しています。');
        }
      }
      if (area['key'] == 'felt') {
        final label = area['predicted_felt_label'];
        if (area['score'] != null ||
            label is! String ||
            !FeltForecastCandidate.labels.contains(label)) {
          throw StateError('表示用の非数値体感が不正です。');
        }
        NineAreaModelContract.validateFelt(
          nineAreaModelVersion: NineAreaDailyForecast.modelVersion,
          primaryTrace: _monthlyMap(area['felt_prediction'], '体感の根拠'),
          primaryLabel: label,
          comparison: area['felt_comparison'] == null
              ? null
              : _monthlyMap(area['felt_comparison'], '比較体感の根拠'),
        );
      } else {
        final score = area['score'];
        if (score is! int || score < 50 || score > 99) {
          throw StateError('表示用の数値点が不正です。');
        }
        NineAreaScoreAudit.validate(
          _monthlyMap(area['score_breakdown'], '数値点の根拠'),
          score,
        );
      }
    }
    final explanation = _monthlyMap(
      snapshot['presentation_explanation'],
      '説明別添',
    );
    if (explanation['schema'] != _presentationExplanationSchema ||
        _monthlyList(explanation['areas'], '9項目の説明別添').length != 9) {
      throw StateError('表示用の説明別添が不完全です。');
    }
  }
  if (!_periodSevenDisplayEqual(
    _monthlyMap(points[3], '正午')['nine_area_forecast'],
    data['nine_area_daily'],
  )) {
    throw StateError('表示用正午と既存の日予測が一致しません。');
  }
}

// Deep comparisons avoid encoding the entire period as a large JSON string.
bool _periodSevenDisplayEqual(Object? left, Object? right) {
  if (left is Map && right is Map) {
    return left.length == right.length &&
        left.keys.every(
          (key) =>
              right.containsKey(key) &&
              _periodSevenDisplayEqual(left[key], right[key]),
        );
  }
  if (left is List && right is List) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (!_periodSevenDisplayEqual(left[i], right[i])) return false;
    }
    return true;
  }
  return left == right;
}

void _validatePeriodSevenDisplayDays(
  List<Map<String, Object?>> days,
  PeriodSevenDisplayRequest request,
) {
  if (days.length != request.dayCount) {
    throw StateError('表示用の日数が不足しています。');
  }
  Object? previousBoundary;
  for (var index = 0; index < days.length; index++) {
    final day = days[index];
    validatePeriodSevenDisplayDay(
      data: day,
      request: request.dailyRequestAt(index),
    );
    final group = _monthlyMap(day['intraday_forecasts'], '表示用7時点');
    final points = _monthlyList(group['points'], '表示用7時点');
    final start = _monthlyMap(points.first, '00:00')['nine_area_forecast'];
    if (index > 0 && !_periodSevenDisplayEqual(previousBoundary, start)) {
      throw StateError('24:00と翌日00:00の表示用予測が一致しません。');
    }
    previousBoundary = _monthlyMap(points.last, '24:00')['nine_area_forecast'];
  }
}

void _periodSevenDisplayValidateRuntime(PeriodSevenDisplayRequest request) {
  final source = AstrologyDataSources.current;
  if (HouseSystemSettings.current.value != request.requestedHouseSystem ||
      source.sourceName != request.sourceName ||
      source.usesHighPrecisionAstroData != request.requireHighPrecision) {
    throw StateError('表示用のハウス方式・計算元・精度が一致しません。');
  }
}

/// Uses exactly the canonical context/positions/forecast functions. It omits
/// legacy five-area output, unused event scans and position JSON serialization.
List<Map<String, Object?>> buildPeriodSevenDisplayData(
  PeriodSevenDisplayRequest request, {
  void Function(int, int)? onProgress,
}) {
  _periodSevenDisplayValidateRuntime(request);
  final days = <Map<String, Object?>>[];
  for (var index = 0; index < request.dayCount; index++) {
    _periodSevenDisplayValidateRuntime(request);
    final fallbackBefore = SwissEphemerisProvider._placementFallbackCount;
    final houseFallbackBefore = SwissEphemerisProvider._houseFallbackCount;
    final daily = request.dailyRequestAt(index);
    final context = const AstrologyEngine().buildPreviewContext(
      profile: request.profile,
      date: daily.date,
    );
    final timeline = DailyStarTimelineRequest.fromContext(
      date: daily.date,
      profile: request.profile,
      contextData: context,
      requestedHouseSystem: request.requestedHouseSystem,
    );
    final positions = calculateDailyIntradayPositions(
      request: timeline,
      nextNoonPlacements: context.nextTransitPlacements,
    );
    final forecasts = calculateDailyIntradayForecasts(
      positions: positions,
      noonContext: context,
      details: request.details,
      onProgress: (done, _) =>
          onProgress?.call(index * 7 + done, request.listedPointCount),
    );
    final primary = NineAreaDailyConsultSnapshot.build(
      date: daily.date,
      contextData: context,
    );
    _periodSevenDisplayValidateRuntime(request);
    if (request.requireHighPrecision &&
        (fallbackBefore != SwissEphemerisProvider._placementFallbackCount ||
            houseFallbackBefore !=
                SwissEphemerisProvider._houseFallbackCount)) {
      throw StateError('表示用の精密計算が簡易計算へ戻りました。');
    }
    days.add({
      'schema': 'pancyo_period_display_day_v1',
      'generated_at': request.generatedAt.toIso8601String(),
      'target_date_jst': daily.plan.targetDateJst,
      'input_identity': request.inputIdentity,
      'time_zone': 'Asia/Tokyo',
      'fixed_utc_offset': '+09:00',
      'calculation_source': {
        'provider': timeline.sourceName,
        'provider_uses_high_precision': timeline.requireHighPrecision,
      },
      'house_calculation': {
        'requested_system': timeline.requestedHouseSystem.name,
        'resolved_system': timeline.resolvedHouseSystem.name,
      },
      'intraday_forecasts': forecasts,
      'nine_area_daily': {
        ...primary,
        'presentation_explanation': _dailyPresentationExplanation(
          primary,
          supplement: request.details,
        ),
      },
    });
  }
  _validatePeriodSevenDisplayDays(days, request);
  return days;
}

Object? _freezePeriodSevenDisplayValue(Object? value) {
  if (value is Map)
    return Map<String, Object?>.unmodifiable({
      for (final entry in value.entries)
        entry.key as String: _freezePeriodSevenDisplayValue(entry.value),
    });
  if (value is List)
    return List<Object?>.unmodifiable(
      value.map(_freezePeriodSevenDisplayValue),
    );
  if (value == null || value is String || value is num || value is bool)
    return value;
  throw StateError('表示用資料に未対応の値があります。');
}

class PeriodSevenDisplayResult {
  PeriodSevenDisplayResult._(
    this.requestIdentity,
    this.days,
    this.elapsedMilliseconds,
    this.workerName,
  );

  factory PeriodSevenDisplayResult.fromData({
    required PeriodSevenDisplayRequest request,
    required List<Map<String, Object?>> days,
    int elapsedMilliseconds = 0,
    String? workerName,
  }) {
    _validatePeriodSevenDisplayDays(days, request);
    return PeriodSevenDisplayResult._(
      request.identity,
      List<Map<String, Object?>>.unmodifiable([
        for (final day in days)
          _freezePeriodSevenDisplayValue(day) as Map<String, Object?>,
      ]),
      elapsedMilliseconds,
      workerName,
    );
  }

  final String requestIdentity;
  final List<Map<String, Object?>> days;
  final int elapsedMilliseconds;
  final String? workerName;
}

void validatePeriodSevenDisplayResult({
  required PeriodSevenDisplayResult result,
  required PeriodSevenDisplayRequest request,
}) {
  if (result.requestIdentity != request.identity) {
    throw StateError('表示用の計算結果が別の入力に属しています。');
  }
  _validatePeriodSevenDisplayDays(result.days, request);
}

PeriodSevenDisplayResult calculatePeriodSevenDisplay(
  PeriodSevenDisplayRequest request, {
  void Function(int, int)? onProgress,
}) {
  final watch = Stopwatch()..start();
  final days = buildPeriodSevenDisplayData(request, onProgress: onProgress);
  final result = PeriodSevenDisplayResult.fromData(
    request: request,
    days: days,
  );
  return PeriodSevenDisplayResult._(
    result.requestIdentity,
    result.days,
    watch.elapsedMilliseconds,
    Isolate.current.debugName,
  );
}

class PeriodSevenDisplayCancelled implements Exception {
  const PeriodSevenDisplayCancelled();
}

abstract class PeriodSevenDisplayOperation {
  Future<PeriodSevenDisplayResult> get result;
  void cancel();
}

typedef PeriodSevenDisplayStarter =
    PeriodSevenDisplayOperation Function(
      PeriodSevenDisplayRequest request,
      void Function(int, int) onProgress,
    );

class PeriodSevenDisplayJob implements PeriodSevenDisplayOperation {
  PeriodSevenDisplayJob.start(
    PeriodSevenDisplayRequest request,
    void Function(int, int) onProgress,
  ) {
    _port.listen((message) {
      if (_finished) return;
      if (message is PeriodSevenDisplayResult) {
        _finish();
        _result.complete(message);
      } else if (message is List &&
          message.length == 3 &&
          message.first == 'progress') {
        onProgress(message[1] as int, message[2] as int);
      } else {
        _finish();
        _result.completeError(StateError('期間の占いを計算できませんでした。'));
      }
    });
    unawaited(_spawn(request));
  }

  final _port = ReceivePort();
  final _result = Completer<PeriodSevenDisplayResult>();
  Isolate? _isolate;
  bool _finished = false;

  @override
  Future<PeriodSevenDisplayResult> get result => _result.future;

  Future<void> _spawn(PeriodSevenDisplayRequest request) async {
    try {
      final isolate = await Isolate.spawn(
        _periodSevenDisplayWorker,
        (request, _port.sendPort),
        debugName: 'pancyo-period-seven-display',
        onError: _port.sendPort,
        onExit: _port.sendPort,
      );
      if (_finished) {
        isolate.kill(priority: Isolate.immediate);
      } else {
        _isolate = isolate;
      }
    } catch (_) {
      if (!_finished) {
        _finish();
        _result.completeError(StateError('期間の占いの別処理を開始できませんでした。'));
      }
    }
  }

  void _finish() {
    _finished = true;
    _port.close();
    _isolate?.kill(priority: Isolate.immediate);
  }

  @override
  void cancel() {
    if (_finished) return;
    _finish();
    _result.completeError(const PeriodSevenDisplayCancelled());
  }
}

void _periodSevenDisplayWorker((PeriodSevenDisplayRequest, SendPort) input) {
  try {
    // Same isolate-local bootstrap as the canonical week/month export worker.
    HouseSystemSettings.current.value = input.$1.requestedHouseSystem;
    final result = calculatePeriodSevenDisplay(
      input.$1,
      onProgress: (done, total) => input.$2.send(['progress', done, total]),
    );
    Isolate.exit(input.$2, result);
  } catch (_) {
    input.$2.send('failed');
  }
}
