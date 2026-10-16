part of 'main.dart';

/// Builds a calendar month of independent daily-v4 consultation records for consecutive
/// JST dates. Each daily record keeps its existing seven-point shape intact.
class MonthlyDailyConsultExportRequest {
  MonthlyDailyConsultExportRequest({
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
      throw StateError('月間7点JSONは選択日の12:00 JSTを基準にしてください。');
    }
    if (firstPlan.targetDateJst.substring(8) != '01') {
      throw FormatException('月間7点JSONは対象月の1日を指定してください。');
    }
    final civil = this.startDate.add(DailySevenTimepointPlan.jstOffset);
    dayCount = DateTime.utc(civil.year, civil.month + 1, 0).day;
    final lastDate = firstPlan.dayStartUtc
        .add(Duration(days: dayCount - 1))
        .add(DailySevenTimepointPlan.jstOffset);
    if (lastDate.year > 9999) {
      throw FormatException('月間7点JSONの日付範囲が対応する暦を超えています。');
    }
    dayPlans = List.unmodifiable([
      for (var i = 0; i < dayCount; i++)
        DailySevenTimepointPlan.forJstDate(
          _monthlyDateLabel(
            firstPlan.dayStartUtc
                .add(Duration(days: i))
                .add(DailySevenTimepointPlan.jstOffset),
          ),
        ),
    ]);
  }

  late final int dayCount;
  int get listedPointCount => dayCount * 7;
  int get uniqueInstantCount => dayCount * 6 + 1;
  final DateTime startDate;
  final AstroProfile profile;
  final UserProfileDetails details;
  final HouseSystem requestedHouseSystem;
  final String sourceName;
  final bool requireHighPrecision;
  final DateTime generatedAt;
  late final List<DailySevenTimepointPlan> dayPlans;

  String get startDateJst =>
      _monthlyDateLabel(startDate.add(DailySevenTimepointPlan.jstOffset));
  String get endDateJst => dayPlans.last.targetDateJst;

  /// Stable token for UI lifecycle comparisons; profile contents stay private
  /// to this in-memory calculation and are not copied into diagnostics.
  String get identity => sha256
      .convert(
        utf8.encode(
          jsonEncode([
            'pancyo_astrology_monthly_daily_consult_v1',
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

  /// Creates one independent daily-v4 request; monthly context is never reused.
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

String _monthlyDateLabel(DateTime jstDate) =>
    '${jstDate.year.toString().padLeft(4, '0')}-'
    '${jstDate.month.toString().padLeft(2, '0')}-'
    '${jstDate.day.toString().padLeft(2, '0')}';

const _monthlyDailyTimesJst = [
  '00:00',
  '04:00',
  '08:00',
  '12:00',
  '16:00',
  '20:00',
  '24:00',
];

const _monthlyDailyHours = [0, 4, 8, 12, 16, 20, 24];

Map<String, Object?> _monthlyMap(Object? value, String label) {
  if (value is! Map) throw StateError('$labelが不足しています。');
  return <String, Object?>{
    for (final entry in value.entries) entry.key.toString(): entry.value,
  };
}

List<Object?> _monthlyList(Object? value, String label) {
  if (value is! List) throw StateError('$labelが不足しています。');
  return value.cast<Object?>();
}

void _monthlyValidatePointList({
  required Object? rawPoints,
  required DailySevenTimepointPlan plan,
  required String label,
}) {
  final points = _monthlyList(rawPoints, label);
  if (points.length != 7) throw StateError('$labelが7時点そろっていません。');
  for (var i = 0; i < 7; i++) {
    final point = _monthlyMap(points[i], '$label[$i]');
    final expected = plan.points[i];
    if (point['hour_from_day_start'] != _monthlyDailyHours[i] ||
        point['display_time'] != _monthlyDailyTimesJst[i] ||
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

String _monthlyResolvedHouseSystem(
  Map<String, Object?> daily, {
  String? expectedRequestedSystem,
}) {
  final topHouse = _monthlyMap(daily['house_calculation'], '日次v4の解決ハウス方式');
  final positions = _monthlyMap(daily['intraday_positions'], '日次v4の日内配置');
  final positionHouse = _monthlyMap(
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

void _monthlyValidateForecastHouseSystem(
  Object? rawPoints,
  String resolvedSystem,
) {
  for (final rawPoint in _monthlyList(rawPoints, '日次v4の予測時点')) {
    final point = _monthlyMap(rawPoint, '日次v4の予測時点');
    final rawSnapshot = point['nine_area_forecast'];
    final snapshot = _monthlyMap(rawSnapshot, '日次v4の予測ハウス方式');
    if (snapshot['house_system'] != resolvedSystem) {
      throw StateError('日次v4の時刻別予測ハウス方式が一致しません。');
    }
    final areas = _monthlyList(snapshot['areas'], '9項目');
    final keys = <String>{};
    if (areas.length != 9 ||
        snapshot['model_version'] != NineAreaDailyForecast.modelVersion) {
      throw StateError('9項目・モデルが不完全です。');
    }
    for (final raw in areas) {
      final area = _monthlyMap(raw, '予測項目');
      if (!keys.add(area['key'] as String) ||
          !NineAreaKey.values.any((key) => key.name == area['key'])) {
        throw StateError('予測項目が重複または不正です。');
      }
      if (area['key'] == 'felt') {
        if (area['score'] != null || area['predicted_felt_label'] is! String) {
          throw StateError('非数値体感が不足しています。');
        }
      } else if (area['score'] is! num || !(area['score'] as num).isFinite) {
        throw StateError('数値予測に欠測があります。');
      }
    }
  }
}

void _monthlyValidateDailyV4(
  Map<String, Object?> daily, {
  required MonthlyDailyConsultExportRequest request,
  required DailySevenTimepointPlan plan,
}) {
  final expectedDateTime = '${plan.targetDateJst} 12:00:00+09:00';
  if (daily['schema'] != 'pancyo_astrology_daily_consult_v4' ||
      daily['generated_at'] != request.generatedAt.toIso8601String() ||
      daily['date_time_jst'] != expectedDateTime) {
    throw StateError('月間7点JSONの日次v4条件が一致しません。');
  }

  final profile = _monthlyMap(daily['profile'], '日次v4のプロフィール');
  if (profile['name'] != request.profile.name ||
      profile['birth_date'] != request.profile.birthDate ||
      profile['birth_time'] != request.profile.birthTime ||
      profile['birth_place'] != request.profile.birthPlace ||
      profile['theme'] != request.profile.theme ||
      profile['concerns'] != request.details.concerns ||
      profile['reading_style'] != request.details.readingStyle) {
    throw StateError('月間7点JSONの日次v4プロフィールが一致しません。');
  }

  final resolvedHouseSystem = _monthlyResolvedHouseSystem(
    daily,
    expectedRequestedSystem: request.requestedHouseSystem.name,
  );

  final positions = _monthlyMap(daily['intraday_positions'], '日次v4の日内配置');
  final positionSource = _monthlyMap(
    positions['calculation_source'],
    '日次v4の配置計算元',
  );
  final positionCompleteness = _monthlyMap(
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
    throw StateError('月間7点JSONの日次v4配置が完全ではありません。');
  }
  _monthlyValidatePointList(
    rawPoints: positions['points'],
    plan: plan,
    label: '日次v4の配置時点',
  );

  final forecasts = _monthlyMap(daily['intraday_forecasts'], '日次v4の時刻別予測');
  final forecastCompleteness = _monthlyMap(
    forecasts['completeness'],
    '日次v4の予測完全性',
  );
  if (forecasts['schema'] != 'pancyo_daily_intraday_forecasts_v1' ||
      forecasts['target_date_jst'] != plan.targetDateJst ||
      forecasts['time_zone'] != 'Asia/Tokyo' ||
      forecasts['fixed_utc_offset'] != '+09:00' ||
      forecastCompleteness['status'] != 'complete' ||
      forecastCompleteness['point_count'] != 7) {
    throw StateError('月間7点JSONの日次v4予測が完全ではありません。');
  }
  _monthlyValidatePointList(
    rawPoints: forecasts['points'],
    plan: plan,
    label: '日次v4の予測時点',
  );
  _monthlyValidateForecastHouseSystem(forecasts['points'], resolvedHouseSystem);
}

void _monthlyValidateRuntime(MonthlyDailyConsultExportRequest request) {
  final source = AstrologyDataSources.current;
  if (HouseSystemSettings.current.value != request.requestedHouseSystem ||
      source.sourceName != request.sourceName ||
      source.usesHighPrecisionAstroData != request.requireHighPrecision) {
    throw StateError('月間7点JSONのハウス方式・計算元・精度が一致しません。');
  }
}

void _monthlyValidateWrapper(Map<String, Object?> data) {
  if (data['schema'] != 'pancyo_astrology_monthly_daily_consult_v1') {
    throw StateError('月間7点JSONのschemaが一致しません。');
  }
  final week = _monthlyMap(data['month'], '月間7点JSONの対象期間');
  final startDate = week['start_date_jst'];
  if (startDate is! String ||
      week['calculation_reference_time_jst'] != '12:00' ||
      week['day_count'] is! int) {
    throw StateError('月間7点JSONの対象期間が不完全です。');
  }
  final firstPlan = DailySevenTimepointPlan.forJstDate(startDate);
  if (startDate.substring(8) != '01') throw StateError('月初ではありません。');
  final civil = firstPlan.dayStartUtc.add(DailySevenTimepointPlan.jstOffset);
  final dayCount = DateTime.utc(civil.year, civil.month + 1, 0).day;
  if (week['day_count'] != dayCount) throw StateError('月の日数が不正です。');
  final finalJst = firstPlan.dayStartUtc
      .add(Duration(days: dayCount - 1))
      .add(DailySevenTimepointPlan.jstOffset);
  final endDate = _monthlyDateLabel(finalJst);
  if (week['end_date_jst'] != endDate) {
    throw StateError('月間7点JSONの終了日が一致しません。');
  }
  final contract = _monthlyMap(data['timepoint_contract'], '月間7点JSONの時点契約');
  final contractTimes = _monthlyList(contract['times_jst'], '月間7点JSONの時点時刻');
  if (contract['time_zone'] != 'Asia/Tokyo' ||
      contract['fixed_utc_offset'] != '+09:00' ||
      contractTimes.length != 7 ||
      contractTimes.asMap().entries.any(
        (entry) => entry.value != _monthlyDailyTimesJst[entry.key],
      ) ||
      contract['counted_series'] != 'days[].intraday_forecasts.points' ||
      contract['parallel_position_series'] !=
          'days[].intraday_positions.points has the same clocks and is not counted again' ||
      contract['points_per_day'] != 7 ||
      contract['listed_point_count'] != dayCount * 7 ||
      contract['unique_instant_count'] != dayCount * 6 + 1) {
    throw StateError('月間7点JSONの時点契約が不完全です。');
  }
  final completeness = _monthlyMap(data['completeness'], '月間7点JSONの完全性');
  if (completeness['status'] != 'complete' ||
      completeness['day_count'] != dayCount ||
      completeness['listed_point_count'] != dayCount * 7 ||
      completeness['unique_instant_count'] != dayCount * 6 + 1) {
    throw StateError('月間7点JSONが完全ではありません。');
  }
  final days = _monthlyList(data['days'], '月間7点JSONの日次配列');
  if (days.length != dayCount) throw StateError('月間7点JSONが月の全日分そろっていません。');
  final generatedAt = data['generated_at'];
  if (generatedAt is! String || generatedAt.isEmpty) {
    throw StateError('月間7点JSONの発行時刻がありません。');
  }
  final instantIds = <String>{};
  Map<String, Object?>? previousForecast;
  for (var i = 0; i < dayCount; i++) {
    final plan = DailySevenTimepointPlan.forJstDate(
      _monthlyDateLabel(
        firstPlan.dayStartUtc
            .add(Duration(days: i))
            .add(DailySevenTimepointPlan.jstOffset),
      ),
    );
    final daily = _monthlyMap(days[i], '月間7点JSONの日次[$i]');
    if (daily['schema'] != 'pancyo_astrology_daily_consult_v4' ||
        daily['generated_at'] != generatedAt ||
        daily['date_time_jst'] != '${plan.targetDateJst} 12:00:00+09:00') {
      throw StateError('月間7点JSONの日次v4が不完全です。');
    }
    final resolvedHouseSystem = _monthlyResolvedHouseSystem(daily);
    for (final field in ['intraday_positions', 'intraday_forecasts']) {
      final group = _monthlyMap(daily[field], '月間7点JSONの日次時点群');
      final expectedSchema = field == 'intraday_positions'
          ? 'pancyo_daily_intraday_positions_v1'
          : 'pancyo_daily_intraday_forecasts_v1';
      final complete = _monthlyMap(group['completeness'], '月間7点JSONの日次完全性');
      if (group['schema'] != expectedSchema ||
          group['target_date_jst'] != plan.targetDateJst ||
          complete['status'] != 'complete' ||
          complete['point_count'] != 7) {
        throw StateError('月間7点JSONの日次時点群が完全ではありません。');
      }
      _monthlyValidatePointList(
        rawPoints: group['points'],
        plan: plan,
        label: '月間7点JSONの日次時点群',
      );
      if (field == 'intraday_forecasts') {
        _monthlyValidateForecastHouseSystem(
          group['points'],
          resolvedHouseSystem,
        );
        for (final raw in _monthlyList(group['points'], '月間7点JSONの予測時点')) {
          instantIds.add(
            _monthlyMap(raw, '月間7点JSONの予測時点')['clock_instant_id'] as String,
          );
        }
        final points = _monthlyList(group['points'], '予測時点');
        final noon = _monthlyMap(_monthlyMap(points[3], '正午時点')['nine_area_forecast'], '正午予測');
        final dailyNoon = _monthlyMap(daily['nine_area_daily'], '既存正午予測');
        if (jsonEncode(noon['areas']) != jsonEncode(dailyNoon['areas'])) {
          throw StateError('日次正午予測が一致しません。');
        }
        final first = _monthlyMap(_monthlyMap(points.first, '00時')['nine_area_forecast'], '00時予測');
        if (previousForecast != null && jsonEncode(previousForecast) != jsonEncode(first)) {
          throw StateError('24時と翌00時の予測が一致しません。');
        }
        previousForecast = _monthlyMap(_monthlyMap(points.last, '24時')['nine_area_forecast'], '24時予測');
      }
    }
  }
  if (instantIds.length != dayCount * 6 + 1) {
    throw StateError('月間7点JSONの境界重複を含む時点数が不正です。');
  }
}

/// Synchronously builds a complete calendar-month wrapper around unchanged daily v4
/// maps. Progress reports completed timepoints as completed points, total days × 7.
Map<String, Object?> buildMonthlyDailyConsultData(
  MonthlyDailyConsultExportRequest request, {
  void Function(int, int)? onProgress,
}) {
  _monthlyValidateRuntime(request);
  final dayCount = request.dayCount;
  final days = <Map<String, Object?>>[];
  final instantIds = <String>{};
  for (var dayIndex = 0; dayIndex < dayCount; dayIndex++) {
    _monthlyValidateRuntime(request);
    final dailyRequest = request.dailyRequestAt(dayIndex);
    var completedForDay = 0;
    final daily = buildDailyConsultDataV4(
      dailyRequest,
      onProgress: (done, total) {
        if (total != 7 || done != completedForDay + 1 || done > 7) {
          throw StateError('日次v4の進捗時点が不完全です。');
        }
        completedForDay = done;
        onProgress?.call(dayIndex * 7 + done, dayCount * 7);
      },
    );
    if (completedForDay != 7) {
      throw StateError('日次v4の7時点計算が完了していません。');
    }
    _monthlyValidateRuntime(request);
    _monthlyValidateDailyV4(
      daily,
      request: request,
      plan: request.dayPlans[dayIndex],
    );
    final forecasts = _monthlyMap(daily['intraday_forecasts'], '日次v4の時刻別予測');
    for (final rawPoint in _monthlyList(forecasts['points'], '日次v4の時刻別予測時点')) {
      instantIds.add(
        _monthlyMap(rawPoint, '日次v4の時点')['clock_instant_id'] as String,
      );
    }
    days.add(daily);
  }
  _monthlyValidateRuntime(request);
  if (days.length != dayCount || instantIds.length != dayCount * 6 + 1) {
    throw StateError('月間7点JSONの全日・時点数が完全ではありません。');
  }

  return {
    'schema': 'pancyo_astrology_monthly_daily_consult_v1',
    'generated_at': request.generatedAt.toIso8601String(),
    'month': {
      'start_date_jst': request.startDateJst,
      'end_date_jst': request.endDateJst,
      'calculation_reference_time_jst': '12:00',
      'day_count': dayCount,
    },
    'timepoint_contract': {
      'time_zone': 'Asia/Tokyo',
      'fixed_utc_offset': '+09:00',
      'times_jst': List<String>.unmodifiable(_monthlyDailyTimesJst),
      'points_per_day': 7,
      'counted_series': 'days[].intraday_forecasts.points',
      'parallel_position_series':
          'days[].intraday_positions.points has the same clocks and is not counted again',
      'listed_point_count': dayCount * 7,
      'unique_instant_count': dayCount * 6 + 1,
      'boundary_rule':
          '各日の24:00は翌日の00:00と同じ瞬間。日次v4の両方の行を保持し、'
          '掲載行を独立瞬間とは数えない。',
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

class MonthlyDailyConsultExportResult {
  MonthlyDailyConsultExportResult._(
    this.requestIdentity,
    this.json,
    this.elapsedMilliseconds,
    this.workerName,
  );

  /// Public pure-data factory for lifecycle and UI tests.
  factory MonthlyDailyConsultExportResult.fromData({
    required String requestIdentity,
    required Map<String, Object?> data,
    int elapsedMilliseconds = 0,
    String? workerName,
  }) {
    _monthlyValidateWrapper(data);
    return MonthlyDailyConsultExportResult._(
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

MonthlyDailyConsultExportResult calculateMonthlyDailyConsultExport(
  MonthlyDailyConsultExportRequest request, {
  void Function(int, int)? onProgress,
}) {
  final watch = Stopwatch()..start();
  final data = buildMonthlyDailyConsultData(request, onProgress: onProgress);
  _monthlyValidateWrapper(data);
  final encoded = jsonEncode(data);
  return MonthlyDailyConsultExportResult._(
    request.identity,
    encoded,
    watch.elapsedMilliseconds,
    Isolate.current.debugName,
  );
}

class MonthlyDailyConsultExportCancelled implements Exception {
  const MonthlyDailyConsultExportCancelled();
}

abstract class MonthlyDailyConsultExportOperation {
  Future<MonthlyDailyConsultExportResult> get result;
  void cancel();
}

typedef MonthlyDailyConsultExportStarter =
    MonthlyDailyConsultExportOperation Function(
      MonthlyDailyConsultExportRequest request,
      void Function(int, int) onProgress,
    );

class MonthlyDailyConsultExportJob
    implements MonthlyDailyConsultExportOperation {
  MonthlyDailyConsultExportJob.start(
    MonthlyDailyConsultExportRequest request,
    void Function(int, int) onProgress,
  ) {
    _port.listen((message) {
      if (_finished) return;
      if (message is MonthlyDailyConsultExportResult) {
        _finish();
        _result.complete(message);
      } else if (message is List &&
          message.length == 3 &&
          message.first == 'progress') {
        onProgress(message[1] as int, message[2] as int);
      } else {
        _finish();
        _result.completeError(StateError('月間7点JSONを作成できませんでした。'));
      }
    });
    unawaited(_spawn(request));
  }

  final _port = ReceivePort();
  final _result = Completer<MonthlyDailyConsultExportResult>();
  Isolate? _isolate;
  bool _finished = false;

  @override
  Future<MonthlyDailyConsultExportResult> get result => _result.future;

  Future<void> _spawn(MonthlyDailyConsultExportRequest request) async {
    try {
      final isolate = await Isolate.spawn(
        _monthlyDailyConsultWorker,
        (request, _port.sendPort),
        debugName: 'pancyo-monthly-daily-consult-export',
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
        _result.completeError(StateError('月間7点JSONの別処理を開始できませんでした。'));
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
    _result.completeError(const MonthlyDailyConsultExportCancelled());
  }
}

void _monthlyDailyConsultWorker(
  (MonthlyDailyConsultExportRequest, SendPort) input,
) {
  try {
    // Applies only inside this worker; no preference is read or persisted.
    HouseSystemSettings.current.value = input.$1.requestedHouseSystem;
    final result = calculateMonthlyDailyConsultExport(
      input.$1,
      onProgress: (done, total) => input.$2.send(['progress', done, total]),
    );
    Isolate.exit(input.$2, result);
  } catch (_) {
    input.$2.send('failed');
  }
}
