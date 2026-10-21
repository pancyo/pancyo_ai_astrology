part of 'main.dart';

/// Builds seven independent daily-v4 consultation records for consecutive
/// JST dates. Each daily record keeps its existing seven-point shape intact.
class WeeklyDailyConsultExportRequest {
  WeeklyDailyConsultExportRequest({
    required DateTime startDate,
    required this.profile,
    required this.details,
    required this.requestedHouseSystem,
    required this.sourceName,
    required this.requireHighPrecision,
    required this.generatedAt,
  }) : startDate = startDate.toUtc() {
    final firstPlan = DailySevenTimepointPlan.forJstDate(startDateJst);
    if (firstPlan.primaryNoon.instantUtc != this.startDate) {
      throw StateError('週JSONは選択日の12:00 JSTを基準にしてください。');
    }
    final lastDate = firstPlan.dayStartUtc
        .add(const Duration(days: 6))
        .add(DailySevenTimepointPlan.jstOffset);
    if (lastDate.year > 9999) {
      throw FormatException('週JSONの日付範囲が対応する暦を超えています。');
    }
    dayPlans = List.unmodifiable([
      for (var i = 0; i < 7; i++)
        DailySevenTimepointPlan.forJstDate(
          _weeklyDateLabel(
            firstPlan.dayStartUtc
                .add(Duration(days: i))
                .add(DailySevenTimepointPlan.jstOffset),
          ),
        ),
    ]);
  }

  final DateTime startDate;
  final AstroProfile profile;
  final UserProfileDetails details;
  final HouseSystem requestedHouseSystem;
  final String sourceName;
  final bool requireHighPrecision;
  final DateTime generatedAt;
  late final List<DailySevenTimepointPlan> dayPlans;

  String get startDateJst =>
      _weeklyDateLabel(startDate.add(DailySevenTimepointPlan.jstOffset));
  String get endDateJst => dayPlans.last.targetDateJst;

  /// Stable token for UI lifecycle comparisons; profile contents stay private
  /// to this in-memory calculation and are not copied into diagnostics.
  String get identity => sha256
      .convert(
        utf8.encode(
          jsonEncode([
            'pancyo_astrology_weekly_daily_consult_v1',
            startDate.toIso8601String(),
            generatedAt.toIso8601String(),
            profile.name,
            profile.birthDate,
            profile.birthTime,
            profile.birthPlace,
            profile.theme,
            profile.savedProfileId,
            details.toJson(),
            requestedHouseSystem.name,
            sourceName,
            requireHighPrecision,
          ]),
        ),
      )
      .toString();

  /// Creates one independent daily-v4 request; weekly context is never reused.
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

String _weeklyDateLabel(DateTime jstDate) =>
    '${jstDate.year.toString().padLeft(4, '0')}-'
    '${jstDate.month.toString().padLeft(2, '0')}-'
    '${jstDate.day.toString().padLeft(2, '0')}';

const _weeklyDailyTimesJst = [
  '00:00',
  '04:00',
  '08:00',
  '12:00',
  '16:00',
  '20:00',
  '24:00',
];

const _weeklyDailyHours = [0, 4, 8, 12, 16, 20, 24];

Map<String, Object?> _weeklyMap(Object? value, String label) {
  if (value is! Map) throw StateError('$labelが不足しています。');
  return <String, Object?>{
    for (final entry in value.entries) entry.key.toString(): entry.value,
  };
}

List<Object?> _weeklyList(Object? value, String label) {
  if (value is! List) throw StateError('$labelが不足しています。');
  return value.cast<Object?>();
}

void _weeklyValidatePointList({
  required Object? rawPoints,
  required DailySevenTimepointPlan plan,
  required String label,
}) {
  final points = _weeklyList(rawPoints, label);
  if (points.length != 7) throw StateError('$labelが7時点そろっていません。');
  for (var i = 0; i < 7; i++) {
    final point = _weeklyMap(points[i], '$label[$i]');
    final expected = plan.points[i];
    if (point['hour_from_day_start'] != _weeklyDailyHours[i] ||
        point['display_time'] != _weeklyDailyTimesJst[i] ||
        point['inside_day_interval'] != expected.isInsideDayInterval ||
        point['role'] !=
            (expected.isDayEndBoundary ? 'day_end_boundary' : 'day_sample') ||
        point['instant_utc'] != expected.instantUtc.toIso8601String() ||
        point['instant_jst'] != expected.instantJst ||
        point['clock_instant_id'] != expected.clockInstantId) {
      throw StateError('$labelの時点または日境界が一致しません。');
    }
  }
}

String _weeklyResolvedHouseSystem(
  Map<String, Object?> daily, {
  String? expectedRequestedSystem,
}) {
  final topHouse = _weeklyMap(daily['house_calculation'], '日次v4の解決ハウス方式');
  final positions = _weeklyMap(
    daily['intraday_positions'],
    '日次v4の日内配置',
  );
  final positionHouse = _weeklyMap(
    positions['house_calculation'],
    '日次v4の要求・解決ハウス方式',
  );
  final requested = positionHouse['requested_system'];
  final resolved = positionHouse['resolved_system'];
  final knownSystems = HouseSystem.values.map((value) => value.name).toSet();
  if (requested is! String ||
      resolved is! String ||
      !knownSystems.contains(requested) ||
      !knownSystems.contains(resolved) ||
      (expectedRequestedSystem != null &&
          requested != expectedRequestedSystem) ||
      topHouse['house_system'] != resolved) {
    throw StateError('日次v4の要求・解決ハウス方式が一致しません。');
  }
  return resolved;
}

void _weeklyValidateForecastHouseSystem(
  Object? rawPoints,
  String resolvedSystem,
) {
  for (final rawPoint in _weeklyList(rawPoints, '日次v4の予測時点')) {
    final point = _weeklyMap(rawPoint, '日次v4の予測時点');
    final rawSnapshot = point['nine_area_forecast'];
    if (rawSnapshot == null) continue;
    final snapshot = _weeklyMap(rawSnapshot, '日次v4の予測ハウス方式');
    if (snapshot['house_system'] != resolvedSystem) {
      throw StateError('日次v4の時刻別予測ハウス方式が一致しません。');
    }
  }
}

void _weeklyValidateDailyV4(
  Map<String, Object?> daily, {
  required WeeklyDailyConsultExportRequest request,
  required DailySevenTimepointPlan plan,
}) {
  final expectedDateTime = '${plan.targetDateJst} 12:00:00+09:00';
  if (daily['schema'] != 'pancyo_astrology_daily_consult_v4' ||
      daily['generated_at'] != request.generatedAt.toIso8601String() ||
      daily['date_time_jst'] != expectedDateTime) {
    throw StateError('週JSONの日次v4条件が一致しません。');
  }

  final profile = _weeklyMap(daily['profile'], '日次v4のプロフィール');
  if (profile['name'] != request.profile.name ||
      profile['birth_date'] != request.profile.birthDate ||
      profile['birth_time'] != request.profile.birthTime ||
      profile['birth_place'] != request.profile.birthPlace ||
      profile['theme'] != request.profile.theme ||
      profile['concerns'] != request.details.concerns ||
      profile['reading_style'] != request.details.readingStyle) {
    throw StateError('週JSONの日次v4プロフィールが一致しません。');
  }

  final resolvedHouseSystem = _weeklyResolvedHouseSystem(
    daily,
    expectedRequestedSystem: request.requestedHouseSystem.name,
  );

  final positions = _weeklyMap(daily['intraday_positions'], '日次v4の日内配置');
  final positionSource = _weeklyMap(
    positions['calculation_source'],
    '日次v4の配置計算元',
  );
  final positionCompleteness = _weeklyMap(
    positions['completeness'],
    '日次v4の配置完全性',
  );
  if (positions['schema'] != 'pancyo_daily_intraday_positions_v1' ||
      positions['target_date_jst'] != plan.targetDateJst ||
      positionSource['provider'] != request.sourceName ||
      positionSource['provider_uses_high_precision'] !=
          request.requireHighPrecision ||
      positionCompleteness['status'] != 'complete' ||
      positionCompleteness['point_count'] != 7) {
    throw StateError('週JSONの日次v4配置が完全ではありません。');
  }
  _weeklyValidatePointList(
    rawPoints: positions['points'],
    plan: plan,
    label: '日次v4の配置時点',
  );

  final forecasts = _weeklyMap(daily['intraday_forecasts'], '日次v4の時刻別予測');
  final forecastCompleteness = _weeklyMap(
    forecasts['completeness'],
    '日次v4の予測完全性',
  );
  if (forecasts['schema'] != 'pancyo_daily_intraday_forecasts_v1' ||
      forecasts['target_date_jst'] != plan.targetDateJst ||
      forecasts['time_zone'] != 'Asia/Tokyo' ||
      forecasts['fixed_utc_offset'] != '+09:00' ||
      forecastCompleteness['status'] != 'complete' ||
      forecastCompleteness['point_count'] != 7) {
    throw StateError('週JSONの日次v4予測が完全ではありません。');
  }
  _weeklyValidatePointList(
    rawPoints: forecasts['points'],
    plan: plan,
    label: '日次v4の予測時点',
  );
  _weeklyValidateForecastHouseSystem(
    forecasts['points'],
    resolvedHouseSystem,
  );
}

void _weeklyValidateRuntime(WeeklyDailyConsultExportRequest request) {
  final source = AstrologyDataSources.current;
  if (HouseSystemSettings.current.value != request.requestedHouseSystem ||
      source.sourceName != request.sourceName ||
      source.usesHighPrecisionAstroData != request.requireHighPrecision) {
    throw StateError('週JSONのハウス方式・計算元・精度が一致しません。');
  }
}

void _weeklyValidateWrapper(Map<String, Object?> data) {
  if (data['schema'] != 'pancyo_astrology_weekly_daily_consult_v1') {
    throw StateError('週JSONのschemaが一致しません。');
  }
  final week = _weeklyMap(data['week'], '週JSONの対象期間');
  final startDate = week['start_date_jst'];
  if (startDate is! String ||
      week['calculation_reference_time_jst'] != '12:00' ||
      week['day_count'] != 7) {
    throw StateError('週JSONの対象期間が不完全です。');
  }
  final firstPlan = DailySevenTimepointPlan.forJstDate(startDate);
  final finalJst = firstPlan.dayStartUtc
      .add(const Duration(days: 6))
      .add(DailySevenTimepointPlan.jstOffset);
  final endDate = _weeklyDateLabel(finalJst);
  if (week['end_date_jst'] != endDate) {
    throw StateError('週JSONの終了日が一致しません。');
  }
  final contract = _weeklyMap(data['timepoint_contract'], '週JSONの時点契約');
  final contractTimes = _weeklyList(contract['times_jst'], '週JSONの時点時刻');
  if (contract['time_zone'] != 'Asia/Tokyo' ||
      contract['fixed_utc_offset'] != '+09:00' ||
      contractTimes.length != 7 ||
      contractTimes.asMap().entries.any(
        (entry) => entry.value != _weeklyDailyTimesJst[entry.key],
      ) ||
      contract['counted_series'] != 'days[].intraday_forecasts.points' ||
      contract['parallel_position_series'] !=
          'days[].intraday_positions.points has the same clocks and is not counted again' ||
      contract['points_per_day'] != 7 ||
      contract['listed_point_count'] != 49 ||
      contract['unique_instant_count'] != 43) {
    throw StateError('週JSONの時点契約が不完全です。');
  }
  final completeness = _weeklyMap(data['completeness'], '週JSONの完全性');
  if (completeness['status'] != 'complete' ||
      completeness['day_count'] != 7 ||
      completeness['listed_point_count'] != 49 ||
      completeness['unique_instant_count'] != 43) {
    throw StateError('週JSONが完全ではありません。');
  }
  final days = _weeklyList(data['days'], '週JSONの日次配列');
  if (days.length != 7) throw StateError('週JSONの日が7日そろっていません。');
  final generatedAt = data['generated_at'];
  if (generatedAt is! String || generatedAt.isEmpty) {
    throw StateError('週JSONの発行時刻がありません。');
  }
  final instantIds = <String>{};
  for (var i = 0; i < 7; i++) {
    final plan = DailySevenTimepointPlan.forJstDate(
      _weeklyDateLabel(
        firstPlan.dayStartUtc
            .add(Duration(days: i))
            .add(DailySevenTimepointPlan.jstOffset),
      ),
    );
    final daily = _weeklyMap(days[i], '週JSONの日次[$i]');
    if (daily['schema'] != 'pancyo_astrology_daily_consult_v4' ||
        daily['generated_at'] != generatedAt ||
        daily['date_time_jst'] != '${plan.targetDateJst} 12:00:00+09:00') {
      throw StateError('週JSONの日次v4が不完全です。');
    }
    final resolvedHouseSystem = _weeklyResolvedHouseSystem(daily);
    for (final field in ['intraday_positions', 'intraday_forecasts']) {
      final group = _weeklyMap(daily[field], '週JSONの日次時点群');
      final expectedSchema = field == 'intraday_positions'
          ? 'pancyo_daily_intraday_positions_v1'
          : 'pancyo_daily_intraday_forecasts_v1';
      final complete = _weeklyMap(group['completeness'], '週JSONの日次完全性');
      if (group['schema'] != expectedSchema ||
          group['target_date_jst'] != plan.targetDateJst ||
          complete['status'] != 'complete' ||
          complete['point_count'] != 7) {
        throw StateError('週JSONの日次時点群が完全ではありません。');
      }
      _weeklyValidatePointList(
        rawPoints: group['points'],
        plan: plan,
        label: '週JSONの日次時点群',
      );
      if (field == 'intraday_forecasts') {
        _weeklyValidateForecastHouseSystem(
          group['points'],
          resolvedHouseSystem,
        );
        for (final raw in _weeklyList(group['points'], '週JSONの予測時点')) {
          instantIds.add(
            _weeklyMap(raw, '週JSONの予測時点')['clock_instant_id'] as String,
          );
        }
      }
    }
  }
  if (instantIds.length != 43) {
    throw StateError('週JSONの境界重複を含む時点数が不正です。');
  }
}

/// Synchronously builds a complete 7-day wrapper around unchanged daily v4
/// maps. Progress reports completed timepoints as 1..49, total 49.
Map<String, Object?> buildWeeklyDailyConsultData(
  WeeklyDailyConsultExportRequest request, {
  void Function(int, int)? onProgress,
}) {
  _weeklyValidateRuntime(request);
  final days = <Map<String, Object?>>[];
  final instantIds = <String>{};
  for (var dayIndex = 0; dayIndex < 7; dayIndex++) {
    _weeklyValidateRuntime(request);
    final dailyRequest = request.dailyRequestAt(dayIndex);
    var completedForDay = 0;
    final daily = buildDailyConsultDataV4(
      dailyRequest,
      onProgress: (done, total) {
        if (total != 7 || done != completedForDay + 1 || done > 7) {
          throw StateError('日次v4の進捗時点が不完全です。');
        }
        completedForDay = done;
        onProgress?.call(dayIndex * 7 + done, 49);
      },
    );
    if (completedForDay != 7) {
      throw StateError('日次v4の7時点計算が完了していません。');
    }
    _weeklyValidateRuntime(request);
    _weeklyValidateDailyV4(
      daily,
      request: request,
      plan: request.dayPlans[dayIndex],
    );
    final forecasts = _weeklyMap(daily['intraday_forecasts'], '日次v4の時刻別予測');
    for (final rawPoint in _weeklyList(forecasts['points'], '日次v4の時刻別予測時点')) {
      instantIds.add(
        _weeklyMap(rawPoint, '日次v4の時点')['clock_instant_id'] as String,
      );
    }
    days.add(daily);
  }
  _weeklyValidateRuntime(request);
  if (days.length != 7 || instantIds.length != 43) {
    throw StateError('週JSONの7日・時点数が完全ではありません。');
  }

  return {
    'schema': 'pancyo_astrology_weekly_daily_consult_v1',
    'generated_at': request.generatedAt.toIso8601String(),
    'week': {
      'start_date_jst': request.startDateJst,
      'end_date_jst': request.endDateJst,
      'calculation_reference_time_jst': '12:00',
      'day_count': 7,
    },
    'timepoint_contract': {
      'time_zone': 'Asia/Tokyo',
      'fixed_utc_offset': '+09:00',
      'times_jst': List<String>.unmodifiable(_weeklyDailyTimesJst),
      'points_per_day': 7,
      'counted_series': 'days[].intraday_forecasts.points',
      'parallel_position_series':
          'days[].intraday_positions.points has the same clocks and is not counted again',
      'listed_point_count': 49,
      'unique_instant_count': 43,
      'boundary_rule':
          '各日の24:00は翌日の00:00と同じ瞬間。日次v4の両方の行を保持し、'
          '49個の掲載行を49個の独立瞬間とは数えない。',
    },
    'completeness': {
      'status': 'complete',
      'day_count': days.length,
      'listed_point_count': days.length * 7,
      'unique_instant_count': instantIds.length,
    },
    'days': days,
  };
}

class WeeklyDailyConsultExportResult {
  WeeklyDailyConsultExportResult._(
    this.requestIdentity,
    this.json,
    this.elapsedMilliseconds,
    this.workerName,
  );

  /// Public pure-data factory for lifecycle and UI tests.
  factory WeeklyDailyConsultExportResult.fromData({
    required String requestIdentity,
    required Map<String, Object?> data,
    int elapsedMilliseconds = 0,
    String? workerName,
  }) {
    _weeklyValidateWrapper(data);
    return WeeklyDailyConsultExportResult._(
      requestIdentity,
      jsonEncode(data),
      elapsedMilliseconds,
      workerName,
    );
  }

  final String requestIdentity;
  final String json;
  final int elapsedMilliseconds;
  final String? workerName;

  Map<String, Object?> get data =>
      Map<String, Object?>.from(jsonDecode(json) as Map);
}

WeeklyDailyConsultExportResult calculateWeeklyDailyConsultExport(
  WeeklyDailyConsultExportRequest request, {
  void Function(int, int)? onProgress,
}) {
  final watch = Stopwatch()..start();
  final data = buildWeeklyDailyConsultData(request, onProgress: onProgress);
  _weeklyValidateWrapper(data);
  final encoded = jsonEncode(data);
  return WeeklyDailyConsultExportResult._(
    request.identity,
    encoded,
    watch.elapsedMilliseconds,
    Isolate.current.debugName,
  );
}

class WeeklyDailyConsultExportCancelled implements Exception {
  const WeeklyDailyConsultExportCancelled();
}

abstract class WeeklyDailyConsultExportOperation {
  Future<WeeklyDailyConsultExportResult> get result;
  void cancel();
}

typedef WeeklyDailyConsultExportStarter =
    WeeklyDailyConsultExportOperation Function(
      WeeklyDailyConsultExportRequest request,
      void Function(int, int) onProgress,
    );

class WeeklyDailyConsultExportJob implements WeeklyDailyConsultExportOperation {
  WeeklyDailyConsultExportJob.start(
    WeeklyDailyConsultExportRequest request,
    void Function(int, int) onProgress,
  ) {
    _port.listen((message) {
      if (_finished) return;
      if (message is WeeklyDailyConsultExportResult) {
        _finish();
        _result.complete(message);
      } else if (message is List &&
          message.length == 3 &&
          message.first == 'progress') {
        onProgress(message[1] as int, message[2] as int);
      } else {
        _finish();
        _result.completeError(StateError('週JSONを作成できませんでした。'));
      }
    });
    unawaited(_spawn(request));
  }

  final _port = ReceivePort();
  final _result = Completer<WeeklyDailyConsultExportResult>();
  Isolate? _isolate;
  bool _finished = false;

  @override
  Future<WeeklyDailyConsultExportResult> get result => _result.future;

  Future<void> _spawn(WeeklyDailyConsultExportRequest request) async {
    try {
      final isolate = await Isolate.spawn(
        _weeklyDailyConsultWorker,
        (request, _port.sendPort),
        debugName: 'pancyo-weekly-daily-consult-export',
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
        _result.completeError(StateError('週JSONの別処理を開始できませんでした。'));
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
    _result.completeError(const WeeklyDailyConsultExportCancelled());
  }
}

void _weeklyDailyConsultWorker(
  (WeeklyDailyConsultExportRequest, SendPort) input,
) {
  try {
    // Applies only inside this worker; no preference is read or persisted.
    HouseSystemSettings.current.value = input.$1.requestedHouseSystem;
    final result = calculateWeeklyDailyConsultExport(
      input.$1,
      onProgress: (done, total) => input.$2.send(['progress', done, total]),
    );
    Isolate.exit(input.$2, result);
  } catch (_) {
    input.$2.send('failed');
  }
}
