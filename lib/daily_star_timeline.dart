part of 'main.dart';

/// Frozen inputs for a positions-only display. No score or settings writes.
class DailyStarTimelineRequest {
  DailyStarTimelineRequest._({
    required this.plan,
    required this.profile,
    required List<PlanetPlacement> natal,
    required List<PlanetPlacement> noonPlacements,
    required List<TransitAspect> noonAspects,
    required List<double> cusps,
    required this.requestedHouseSystem,
    required this.resolvedHouseSystem,
    required this.sourceName,
    required this.requireHighPrecision,
    required this.voidMoon,
  }) : natal = List.unmodifiable(natal),
       noonPlacements = List.unmodifiable(noonPlacements),
       noonAspects = List.unmodifiable(noonAspects),
       cusps = List.unmodifiable(cusps);

  factory DailyStarTimelineRequest.fromContext({
    required DateTime date,
    required HoroscopeReadingContext contextData,
    AstroProfile? profile,
    HouseSystem? requestedHouseSystem,
  }) {
    final jst = date.toUtc().add(DailySevenTimepointPlan.jstOffset);
    final plan = DailySevenTimepointPlan.forJstDate(
      jst.year.toString().padLeft(4, '0') +
          '-' +
          jst.month.toString().padLeft(2, '0') +
          '-' +
          jst.day.toString().padLeft(2, '0'),
    );
    if (date.toUtc() != plan.primaryNoon.instantUtc ||
        contextData.transit.date.toUtc() != date.toUtc()) {
      throw StateError('日内表示の正午基準が一致しません。');
    }
    final subject = profile ?? contextData.natal.profile;
    final original = contextData.natal.profile;
    if (subject.birthClock?.cacheIdentity !=
            original.birthClock?.cacheIdentity ||
        subject.birthDate != original.birthDate ||
        subject.birthTime != original.birthTime ||
        subject.birthPlace != original.birthPlace) {
      throw StateError('出生図の入力が一致しません。');
    }
    _timelineValidatePlacements(contextData.natal.placements, natal: true);
    _timelineValidateCusps(contextData.houseCusps);
    final voidMoon = contextData.transit.voidMoon;
    if (voidMoon != null && !voidMoon.endTime.isAfter(voidMoon.startTime)) {
      throw StateError('ボイド区間が不正です。');
    }
    final request = DailyStarTimelineRequest._(
      plan: plan,
      profile: subject,
      natal: contextData.natal.placements,
      noonPlacements: contextData.transit.placements,
      noonAspects: contextData.fullAspects,
      cusps: contextData.houseCusps,
      requestedHouseSystem:
          requestedHouseSystem ?? HouseSystemSettings.current.value,
      resolvedHouseSystem: contextData.houseSystem,
      sourceName: contextData.ephemerisSourceName,
      requireHighPrecision: contextData.usesHighPrecisionAstroData,
      voidMoon: voidMoon,
    );
    for (final p in request.natal) {
      if (request.houseFrame.houseForLongitude(p.sign.index * 30 + p.degree) !=
          p.house) {
        throw StateError('出生配置とハウス基準が一致しません。');
      }
    }
    request.noonSnapshot; // Check all geometry before starting a worker.
    return request;
  }

  final DailySevenTimepointPlan plan;
  final AstroProfile profile;
  final List<PlanetPlacement> natal, noonPlacements;
  final List<TransitAspect> noonAspects;
  final List<double> cusps;
  final HouseSystem requestedHouseSystem, resolvedHouseSystem;
  final String sourceName;
  final bool requireHighPrecision;
  final VoidMoonPeriod? voidMoon;
  HouseFrame get houseFrame =>
      HouseFrame(system: resolvedHouseSystem, cusps: cusps);

  /// Private-input digest, never logged or sent externally.
  String get identity => sha256
      .convert(
        utf8.encode(
          jsonEncode([
            plan.targetDateJst,
            profile.name,
            profile.birthDate,
            profile.birthClock?.cacheIdentity,
            profile.birthTime,
            profile.birthPlace,
            profile.theme,
            profile.savedProfileId,
            requestedHouseSystem.name,
            resolvedHouseSystem.name,
            sourceName,
            requireHighPrecision,
            cusps,
            _timelinePlacementValues(natal),
            _timelinePlacementValues(noonPlacements),
            _timelineAspectValues(noonAspects),
            voidMoon?.startTime.toUtc().toIso8601String(),
            voidMoon?.endTime.toUtc().toIso8601String(),
          ]),
        ),
      )
      .toString();

  DailyStarTimelinePoint get noonSnapshot => DailyStarTimelinePoint.checked(
    request: this,
    clock: plan.primaryNoon,
    calculatedAtUtc: plan.primaryNoon.instantUtc,
    placements: noonPlacements,
    fullNatalAspects: noonAspects,
  );
}

List<Object> _timelinePlacementValues(List<PlanetPlacement> values) => [
  for (final p in values) [p.planet.name, p.sign.name, p.degree, p.house],
];
List<Object> _timelineAspectValues(List<TransitAspect> values) => [
  for (final a in values)
    [
      a.transitPlanet.name,
      a.natalPlanet.name,
      a.type.name,
      a.orb,
      a.area.name,
      a.meaning,
    ],
];
String _timelineAspectId(TransitAspect a) =>
    a.transitPlanet.name + '/' + a.natalPlanet.name + '/' + a.type.name;

void _timelineValidatePlacements(
  List<PlanetPlacement> values, {
  required bool natal,
}) {
  final planets = <AstroPlanet>{};
  for (final p in values) {
    if (!planets.add(p.planet) ||
        !p.degree.isFinite ||
        p.degree < 0 ||
        p.degree >= 30 ||
        p.house < 1 ||
        p.house > 12 ||
        (!natal && p.planet.index >= 10)) {
      throw StateError('日内配置に欠落・重複・範囲外があります。');
    }
  }
  if (!planets.containsAll(AstroPlanet.values.take(10))) {
    throw StateError('必須10天体が不足しています。');
  }
}

void _timelineValidateCusps(List<double> cusps) {
  if (cusps.length != 12 ||
      cusps.any((v) => !v.isFinite || v < 0 || v >= 360)) {
    throw StateError('出生図ハウスが不足しています。');
  }
  var sum = 0.0;
  for (var i = 0; i < 12; i++) {
    final span = (cusps[(i + 1) % 12] - cusps[i]) % 360;
    if (span <= 0) throw StateError('出生図カスプが不正です。');
    sum += span;
  }
  if ((sum - 360).abs() > 1e-7) throw StateError('出生図カスプの順序が不正です。');
}

bool _timelinePlacementsMatch(
  List<PlanetPlacement> a,
  List<PlanetPlacement> b,
) {
  if (a.length != b.length) return false;
  final map = {for (final p in b) p.planet: p};
  return a.every((p) {
    final other = map[p.planet];
    return other != null &&
        p.sign == other.sign &&
        p.house == other.house &&
        (p.degree - other.degree).abs() <= 1e-7;
  });
}

bool _timelineAspectsMatch(List<TransitAspect> a, List<TransitAspect> b) {
  final map = {for (final aspect in b) _timelineAspectId(aspect): aspect};
  final seen = <String>{};
  if (a.length != b.length || map.length != b.length) return false;
  return a.every((aspect) {
    final id = _timelineAspectId(aspect);
    final other = map[id];
    return seen.add(id) &&
        other != null &&
        aspect.orb.isFinite &&
        (aspect.orb - other.orb).abs() <= 1e-7 &&
        aspect.area == other.area &&
        aspect.meaning == other.meaning;
  });
}

class DailyStarTimelinePoint {
  DailyStarTimelinePoint._(
    this.clock,
    List<PlanetPlacement> placements,
    List<TransitAspect> fullNatalAspects,
    this.isVoid,
    this.requestIdentity,
  ) : placements = List.unmodifiable(placements),
      fullNatalAspects = List.unmodifiable(fullNatalAspects);

  factory DailyStarTimelinePoint.checked({
    required DailyStarTimelineRequest request,
    required DailySevenTimepoint clock,
    required DateTime calculatedAtUtc,
    required List<PlanetPlacement> placements,
    required List<TransitAspect> fullNatalAspects,
  }) {
    if (!calculatedAtUtc.isUtc ||
        calculatedAtUtc != clock.instantUtc ||
        !request.plan.points.any(
          (p) =>
              p.instantUtc == clock.instantUtc &&
              p.hourFromDayStart == clock.hourFromDayStart,
        )) {
      throw StateError('配置の計算時刻が一致しません。');
    }
    _timelineValidatePlacements(placements, natal: false);
    for (final p in placements) {
      if (request.houseFrame.houseForLongitude(p.sign.index * 30 + p.degree) !=
          p.house) {
        throw StateError('出生図基準のハウスが一致しません。');
      }
    }
    final expected = const SimpleEphemeris().aspects(
      transit: placements,
      natal: request.natal,
    );
    if (!_timelineAspectsMatch(fullNatalAspects, expected)) {
      throw StateError('全角度と天体位置が一致しません。');
    }
    return DailyStarTimelinePoint._(
      clock,
      placements,
      fullNatalAspects,
      request.voidMoon?.contains(calculatedAtUtc) ?? false,
      request.identity,
    );
  }
  final DailySevenTimepoint clock;
  final List<PlanetPlacement> placements;
  final List<TransitAspect> fullNatalAspects;
  final bool isVoid;
  final String requestIdentity;
  PlanetPlacement get moon =>
      placements.singleWhere((p) => p.planet == AstroPlanet.moon);
  List<TransitAspect> get moonAspects {
    final values = fullNatalAspects
        .where((a) => a.transitPlanet == AstroPlanet.moon)
        .toList();
    values.sort((a, b) {
      final comparison = a.orb.compareTo(b.orb);
      return comparison != 0
          ? comparison
          : _timelineAspectId(a).compareTo(_timelineAspectId(b));
    });
    return List.unmodifiable(values);
  }
}

class DailyStarTimelineResult {
  DailyStarTimelineResult.checked({
    required DailyStarTimelineRequest request,
    required List<DailyStarTimelinePoint> points,
    required this.elapsedMilliseconds,
    required this.workerName,
  }) : requestIdentity = request.identity,
       points = List.unmodifiable(points) {
    if (points.length != 7) throw StateError('7時点が揃っていません。');
    for (var i = 0; i < 7; i++) {
      if (points[i].requestIdentity != requestIdentity ||
          points[i].clock.instantUtc != request.plan.points[i].instantUtc ||
          points[i].clock.hourFromDayStart !=
              request.plan.points[i].hourFromDayStart) {
        throw StateError('時点の順序が一致しません。');
      }
    }
    if (!_timelinePlacementsMatch(
          points[3].placements,
          request.noonPlacements,
        ) ||
        !_timelineAspectsMatch(
          points[3].fullNatalAspects,
          request.noonAspects,
        )) {
      throw StateError('正午の既存配置と一致しません。');
    }
  }
  final String requestIdentity;
  final List<DailyStarTimelinePoint> points;
  final int elapsedMilliseconds;
  final String? workerName;
}

/// The selected-time scores reuse the timeline worker's seven positions. The
/// daily V4 formula is applied at each sample only for this comparison view;
/// this result is not the day's primary forecast and is never serialized.
class DailyTimepointForecastResult {
  DailyTimepointForecastResult.checked({
    required this.scoreIdentity,
    required DailyStarTimelineRequest request,
    required DailyStarTimelineResult positions,
    required Map<String, Object?> forecasts,
    required this.elapsedMilliseconds,
    required this.workerName,
  }) : timelineIdentity = request.identity,
       targetDateJst = request.plan.targetDateJst,
       forecasts = Map.unmodifiable(forecasts) {
    if (scoreIdentity.isEmpty ||
        positions.requestIdentity != request.identity) {
      throw StateError('時刻別点数の入力が一致しません。');
    }
    if (forecasts['schema'] != 'pancyo_daily_intraday_forecasts_v1' ||
        forecasts['target_date_jst'] != request.plan.targetDateJst ||
        forecasts['time_zone'] != 'Asia/Tokyo' ||
        forecasts['fixed_utc_offset'] != '+09:00' ||
        forecasts['model_version'] != NineAreaDailyForecast.modelVersion ||
        forecasts['formula_policy'] !=
            'existing_nine_area_daily_formula_at_each_instant' ||
        forecasts['daily_primary_reference_count'] != 1 ||
        forecasts['daily_scores_averaged_from_samples'] != false ||
        forecasts['felt_has_numeric_score'] != false) {
      throw StateError('時刻別点数の基準が一致しません。');
    }
    final completeness = _timelineMap(forecasts['completeness']);
    final rawPoints = forecasts['points'];
    if (completeness['status'] != 'complete' ||
        completeness['point_count'] != 7 ||
        completeness['areas_per_point'] != 9 ||
        rawPoints is! List ||
        rawPoints.length != 7) {
      throw StateError('時刻別点数が7点揃っていません。');
    }
    final expectedAreaKeys = NineAreaKey.values.map((key) => key.name).toSet();
    const feltLabels = {'最高', '良い', '普通', '悪い', '最悪'};
    for (var index = 0; index < 7; index++) {
      final clock = request.plan.points[index];
      final point = _timelineMap(rawPoints[index]);
      if (point['instant_utc'] != clock.instantUtc.toIso8601String() ||
          point['hour_from_day_start'] != clock.hourFromDayStart ||
          point['is_existing_daily_primary_reference'] != clock.isPrimaryNoon ||
          point['inside_day_interval'] != clock.isInsideDayInterval ||
          point['role'] !=
              (clock.isDayEndBoundary ? 'day_end_boundary' : 'day_sample')) {
        throw StateError('時刻別点数の日時・役割が一致しません。');
      }
      final snapshot = _timelineMap(point['nine_area_forecast']);
      final expectedSnapshotDate = _timelineJstDate(clock.instantUtc);
      final expectedSchema = clock.isPrimaryNoon
          ? 'pancyo_nine_area_daily_consult_v1'
          : 'pancyo_nine_area_instant_consult_v1';
      if (snapshot['target_date_jst'] != expectedSnapshotDate ||
          snapshot['schema'] != expectedSchema ||
          snapshot['model_version'] != NineAreaDailyForecast.modelVersion) {
        throw StateError('時刻別点数の対象日・モデルが一致しません。');
      }
      final areas = snapshot['areas'];
      if (areas is! List || areas.length != 9) {
        throw StateError('時刻別点数の9項目が揃っていません。');
      }
      final seen = <String>{};
      for (final rawArea in areas) {
        final area = _timelineMap(rawArea);
        final key = area['key'];
        if (key is! String ||
            !expectedAreaKeys.contains(key) ||
            !seen.add(key)) {
          throw StateError('時刻別点数の項目キーが不正です。');
        }
        final score = area['score'];
        if (key == NineAreaKey.felt.name) {
          final label = area['predicted_felt_label'];
          if (score != null ||
              area['score_breakdown'] != null ||
              (label != null &&
                  (label is! String || !feltLabels.contains(label)))) {
            throw StateError('体感項目に数値点または不正なラベルがあります。');
          }
        } else if (score != null && score is! int) {
          throw StateError('数値項目の型が一致しません。');
        }
      }
      if (seen.length != expectedAreaKeys.length) {
        throw StateError('時刻別点数の項目が不足しています。');
      }
      final expectedOrigin = clock.isPrimaryNoon
          ? 'existing_noon_context'
          : 'sample_instant_context';
      if (point['calculation_origin'] != expectedOrigin) {
        throw StateError('正午の既存基準が保持されていません。');
      }
    }
  }

  final String scoreIdentity, timelineIdentity, targetDateJst;
  final Map<String, Object?> forecasts;
  final int elapsedMilliseconds;
  final String? workerName;
}

Map<String, Object?> _timelineMap(Object? value) {
  if (value is! Map) throw StateError('時刻別点数の形式が不正です。');
  try {
    return Map<String, Object?>.from(value);
  } catch (_) {
    throw StateError('時刻別点数の項目名が不正です。');
  }
}

String _timelineJstDate(DateTime utc) {
  final jst = utc.toUtc().add(DailySevenTimepointPlan.jstOffset);
  return '${jst.year.toString().padLeft(4, '0')}-'
      '${jst.month.toString().padLeft(2, '0')}-'
      '${jst.day.toString().padLeft(2, '0')}';
}

/// Runs only the comparison placements and the existing V4 intraday formula
/// after the positions-only timeline job has completed. No UI-isolate scoring.
DailyTimepointForecastResult calculateDailyTimepointForecasts({
  required String scoreIdentity,
  required DailyConsultExportRequest exportRequest,
  required DailyStarTimelineRequest timelineRequest,
  required DailyStarTimelineResult timelineResult,
  EphemerisProvider? provider,
  void Function(int, int)? onProgress,
}) {
  final contextData = exportRequest.contextData;
  if (contextData == null ||
      exportRequest.date.toUtc() !=
          timelineRequest.plan.primaryNoon.instantUtc ||
      exportRequest.requestedHouseSystem !=
          timelineRequest.requestedHouseSystem ||
      timelineResult.requestIdentity != timelineRequest.identity) {
    throw StateError('時刻別点数の正午・出生図・入力が一致しません。');
  }
  final contextRequest = DailyStarTimelineRequest.fromContext(
    date: exportRequest.date,
    contextData: contextData,
    profile: exportRequest.profile,
    requestedHouseSystem: exportRequest.requestedHouseSystem,
  );
  if (contextRequest.identity != timelineRequest.identity) {
    throw StateError('時刻別点数の入力世代が一致しません。');
  }
  final source = provider ?? AstrologyDataSources.current;
  if (source.sourceName != timelineRequest.sourceName ||
      source.usesHighPrecisionAstroData !=
          timelineRequest.requireHighPrecision) {
    throw StateError('時刻別点数の計算元が一致しません。');
  }
  final fallbackBefore = SwissEphemerisProvider._placementFallbackCount;
  final comparisons = <List<PlanetPlacement>>[];
  for (var index = 0; index < timelineResult.points.length; index++) {
    final point = timelineResult.points[index];
    final nextInstant = point.clock.instantUtc.add(const Duration(days: 1));
    final placements = index == 0
        ? timelineResult.points[6].placements
        : source.placementsFor(
            nextInstant,
            houseFrame: timelineRequest.houseFrame,
          );
    _timelineValidatePlacements(placements, natal: false);
    comparisons.add(placements);
  }
  if (timelineRequest.requireHighPrecision &&
      fallbackBefore != SwissEphemerisProvider._placementFallbackCount) {
    throw StateError('時刻別点数の比較配置が簡易計算へ戻りました。');
  }
  final positions = DailyIntradayPositionsExport.checked(
    request: timelineRequest,
    result: timelineResult,
    comparisonPlacements: comparisons,
  );
  final watch = Stopwatch()..start();
  final forecasts = calculateDailyIntradayForecasts(
    positions: positions,
    noonContext: contextData,
    provider: source,
    onProgress: onProgress,
  );
  return DailyTimepointForecastResult.checked(
    scoreIdentity: scoreIdentity,
    request: timelineRequest,
    positions: timelineResult,
    forecasts: forecasts,
    elapsedMilliseconds: watch.elapsedMilliseconds,
    workerName: Isolate.current.debugName,
  );
}

abstract class DailyTimepointForecastOperation {
  Future<DailyTimepointForecastResult> get result;
  void cancel();
}

typedef DailyTimepointForecastStarter =
    DailyTimepointForecastOperation Function(
      String scoreIdentity,
      DailyConsultExportRequest exportRequest,
      DailyStarTimelineRequest timelineRequest,
      DailyStarTimelineResult timelineResult,
      void Function(int, int) onProgress,
    );

class DailyTimepointForecastJob implements DailyTimepointForecastOperation {
  DailyTimepointForecastJob.start(
    String scoreIdentity,
    DailyConsultExportRequest exportRequest,
    DailyStarTimelineRequest timelineRequest,
    DailyStarTimelineResult timelineResult,
    void Function(int, int) onProgress,
  ) {
    _port.listen((message) {
      if (_finished) return;
      if (message is DailyTimepointForecastResult) {
        _finish();
        _result.complete(message);
      } else if (message is List &&
          message.length == 3 &&
          message.first == 'progress') {
        onProgress(message[1] as int, message[2] as int);
      } else {
        _finish();
        _result.completeError(StateError('時刻別点数を読み取れませんでした。'));
      }
    });
    unawaited(
      _spawn(scoreIdentity, exportRequest, timelineRequest, timelineResult),
    );
  }

  final _port = ReceivePort();
  final _result = Completer<DailyTimepointForecastResult>();
  Isolate? _isolate;
  bool _finished = false;
  @override
  Future<DailyTimepointForecastResult> get result => _result.future;

  Future<void> _spawn(
    String scoreIdentity,
    DailyConsultExportRequest exportRequest,
    DailyStarTimelineRequest timelineRequest,
    DailyStarTimelineResult timelineResult,
  ) async {
    try {
      final isolate = await Isolate.spawn(
        _dailyTimepointForecastWorker,
        (
          scoreIdentity,
          exportRequest,
          timelineRequest,
          timelineResult,
          _port.sendPort,
        ),
        debugName: 'pancyo-daily-timepoint-forecast',
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
        _result.completeError(StateError('時刻別点数を開始できませんでした。'));
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
    _result.completeError(const DailyTimepointForecastCancelled());
  }
}

class DailyTimepointForecastCancelled implements Exception {
  const DailyTimepointForecastCancelled();
}

void _dailyTimepointForecastWorker(
  (
    String,
    DailyConsultExportRequest,
    DailyStarTimelineRequest,
    DailyStarTimelineResult,
    SendPort,
  )
  input,
) {
  try {
    Isolate.exit(
      input.$5,
      calculateDailyTimepointForecasts(
        scoreIdentity: input.$1,
        exportRequest: input.$2,
        timelineRequest: input.$3,
        timelineResult: input.$4,
        onProgress: (done, total) => input.$5.send(['progress', done, total]),
      ),
    );
  } catch (_) {
    input.$5.send('failed');
  }
}

/// Position calls only: no repeated natal/void/return searches, no scores.
DailyStarTimelineResult calculateDailyStarTimeline(
  DailyStarTimelineRequest request, {
  EphemerisProvider? provider,
  void Function(int, int)? onProgress,
}) {
  final watch = Stopwatch()..start();
  final source = provider ?? AstrologyDataSources.current;
  if (source.sourceName != request.sourceName ||
      source.usesHighPrecisionAstroData != request.requireHighPrecision) {
    throw StateError('表示と計算の出所が一致しません。');
  }
  final fallbackBefore = SwissEphemerisProvider._placementFallbackCount;
  final points = <DailyStarTimelinePoint>[];
  for (final clock in request.plan.points) {
    final placements = source.placementsFor(
      clock.instantUtc,
      houseFrame: request.houseFrame,
    );
    if (request.requireHighPrecision &&
        SwissEphemerisProvider._placementFallbackCount != fallbackBefore) {
      throw StateError('日内配置が簡易計算へ戻りました。');
    }
    points.add(
      DailyStarTimelinePoint.checked(
        request: request,
        clock: clock,
        calculatedAtUtc: clock.instantUtc,
        placements: placements,
        fullNatalAspects: source.aspects(
          transit: placements,
          natal: request.natal,
        ),
      ),
    );
    onProgress?.call(points.length, 7);
  }
  return DailyStarTimelineResult.checked(
    request: request,
    points: points,
    elapsedMilliseconds: watch.elapsedMilliseconds,
    workerName: Isolate.current.debugName,
  );
}

class DailyStarTimelineCancelled implements Exception {
  const DailyStarTimelineCancelled();
}

abstract class DailyStarTimelineOperation {
  Future<DailyStarTimelineResult> get result;
  void cancel();
}

typedef DailyStarTimelineStarter =
    DailyStarTimelineOperation Function(
      DailyStarTimelineRequest request,
      void Function(int, int) onProgress,
    );

class DailyStarTimelineJob implements DailyStarTimelineOperation {
  DailyStarTimelineJob.start(
    DailyStarTimelineRequest request,
    void Function(int, int) onProgress,
  ) {
    _port.listen((message) {
      if (_finished) return;
      if (message is DailyStarTimelineResult) {
        _finish();
        _result.complete(message);
      } else if (message is List &&
          message.length == 3 &&
          message.first == 'progress') {
        onProgress(message[1] as int, message[2] as int);
      } else {
        _finish();
        _result.completeError(StateError('7時点の配置を読み取れませんでした。'));
      }
    });
    unawaited(_spawn(request));
  }
  final _port = ReceivePort();
  final _result = Completer<DailyStarTimelineResult>();
  Isolate? _isolate;
  bool _finished = false;
  @override
  Future<DailyStarTimelineResult> get result => _result.future;
  Future<void> _spawn(DailyStarTimelineRequest request) async {
    try {
      final isolate = await Isolate.spawn(
        _dailyStarTimelineWorker,
        (request, _port.sendPort),
        debugName: 'pancyo-daily-star-timeline',
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
        _result.completeError(StateError('日内配置を開始できませんでした。'));
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
    _result.completeError(const DailyStarTimelineCancelled());
  }
}

void _dailyStarTimelineWorker((DailyStarTimelineRequest, SendPort) input) {
  try {
    Isolate.exit(
      input.$2,
      calculateDailyStarTimeline(
        input.$1,
        onProgress: (done, total) => input.$2.send(['progress', done, total]),
      ),
    );
  } catch (_) {
    input.$2.send('failed');
  }
}

/// Same card identity as the previous four-line flow, now below the 5+4.
class DailyTimeFlowCard extends StatefulWidget {
  const DailyTimeFlowCard({
    super.key,
    required this.date,
    required this.contextData,
    this.profile,
    this.details,
    this.startJob,
    this.startForecastJob,
    this.nowUtc,
  });
  final DateTime date;
  final HoroscopeReadingContext contextData;
  final AstroProfile? profile;
  final UserProfileDetails? details;
  final DailyStarTimelineStarter? startJob;
  final DailyTimepointForecastStarter? startForecastJob;
  final DateTime Function()? nowUtc;
  @override
  State<DailyTimeFlowCard> createState() => _DailyTimeFlowCardState();
}

class _DailyTimeFlowCardState extends State<DailyTimeFlowCard> {
  DailyStarTimelineRequest? _request;
  DailyStarTimelineResult? _data;
  DailyStarTimelineOperation? _job;
  DailyConsultExportRequest? _forecastRequest;
  DailyTimepointForecastResult? _forecastData;
  DailyTimepointForecastOperation? _forecastJob;
  String? _forecastIdentity;
  AppText? _message;
  String? _shareStatus;
  bool _forecastFailed = false;
  bool _sharePendingAfterForecast = false;
  int _generation = 0,
      _forecastGeneration = 0,
      _selected = 3,
      _completed = 0,
      _forecastCompleted = 0;
  @override
  void initState() {
    super.initState();
    HouseSystemSettings.current.addListener(_onHouseSystemChanged);
    _readRequest();
    _selected = _initialSelectedIndex();
    if (_selected != 3) _load();
  }

  int _initialSelectedIndex() {
    final request = _request;
    if (request == null) return 3;
    final instantUtc = (widget.nowUtc?.call() ?? DateTime.now().toUtc())
        .toUtc();
    final jst = instantUtc.add(DailySevenTimepointPlan.jstOffset);
    final currentDate =
        '${jst.year.toString().padLeft(4, '0')}-'
        '${jst.month.toString().padLeft(2, '0')}-'
        '${jst.day.toString().padLeft(2, '0')}';
    if (currentDate != request.plan.targetDateJst) return 3;
    return (jst.hour ~/ 4).clamp(0, 5).toInt();
  }

  void _readRequest() {
    try {
      final timelineRequest = DailyStarTimelineRequest.fromContext(
        date: widget.date,
        contextData: widget.contextData,
        profile: widget.profile,
      );
      final details = widget.details;
      _request = timelineRequest;
      _message = null;
      // Legacy positions-only callers do not request a score worker. The real
      // reading screen supplies details, including an explicitly empty profile.
      if (details == null) {
        _forecastRequest = null;
        _forecastIdentity = null;
        return;
      }
      final forecastRequest = DailyConsultExportRequest(
        date: timelineRequest.plan.primaryNoon.instantUtc,
        profile: timelineRequest.profile,
        details: details,
        requestedHouseSystem: timelineRequest.requestedHouseSystem,
        sourceName: timelineRequest.sourceName,
        requireHighPrecision: timelineRequest.requireHighPrecision,
        // This is an in-memory display calculation, not an export timestamp.
        // Keeping it stable also keeps the forecast request identity stable.
        generatedAt: timelineRequest.plan.primaryNoon.instantUtc,
        contextData: widget.contextData,
      );
      _request = timelineRequest;
      _forecastRequest = forecastRequest;
      _forecastIdentity = _timepointScoreIdentity(timelineRequest, details);
      _message = null;
    } catch (_) {
      _request = null;
      _forecastRequest = null;
      _forecastIdentity = null;
      _message = AppText.timelineInvalidNoon;
    }
  }

  String _timepointScoreIdentity(
    DailyStarTimelineRequest request,
    UserProfileDetails details,
  ) => sha256
      .convert(
        utf8.encode(
          jsonEncode([
            'daily-timepoint-score-display-v1',
            request.identity,
            details.toJson(),
          ]),
        ),
      )
      .toString();

  void _onHouseSystemChanged() {
    if (!mounted) return;
    _generation++;
    _forecastGeneration++;
    _job?.cancel();
    _forecastJob?.cancel();
    setState(() {
      _request = null;
      _data = null;
      _job = null;
      _forecastRequest = null;
      _forecastData = null;
      _forecastJob = null;
      _forecastIdentity = null;
      _forecastFailed = false;
      _sharePendingAfterForecast = false;
      _shareStatus = null;
      _completed = 0;
      _forecastCompleted = 0;
      _selected = 3;
      _message = AppText.timelineChangedInput;
    });
  }

  @override
  void didUpdateWidget(covariant DailyTimeFlowCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldTimelineIdentity = _request?.identity;
    final oldForecastIdentity = _forecastIdentity;
    _readRequest();
    final timelineChanged = oldTimelineIdentity != _request?.identity;
    final forecastChanged = oldForecastIdentity != _forecastIdentity;
    final positionStarterChanged = oldWidget.startJob != widget.startJob;
    final forecastStarterChanged =
        oldWidget.startForecastJob != widget.startForecastJob;
    if (timelineChanged || positionStarterChanged) {
      _generation++;
      _job?.cancel();
      _job = null;
      _data = null;
      _completed = 0;
    }
    if (timelineChanged || forecastChanged || forecastStarterChanged) {
      _forecastGeneration++;
      _forecastJob?.cancel();
      _forecastJob = null;
      _forecastData = null;
      _forecastFailed = false;
      _forecastCompleted = 0;
      _sharePendingAfterForecast = false;
      _shareStatus = null;
    }
    if (timelineChanged) _selected = _initialSelectedIndex();
    if (timelineChanged ||
        positionStarterChanged ||
        forecastChanged ||
        forecastStarterChanged) {
      if (_selected != 3) _load();
    }
  }

  @override
  void dispose() {
    _generation++;
    _forecastGeneration++;
    HouseSystemSettings.current.removeListener(_onHouseSystemChanged);
    _job?.cancel();
    _forecastJob?.cancel();
    super.dispose();
  }

  void _select(int index) {
    setState(() {
      _selected = index;
    });
    if (index != 3) _load();
  }

  void _load() {
    final request = _request;
    if (request == null) return;
    if (_selected != 3 && _data != null && _forecastData == null) {
      _loadForecast();
    }
    if (_job != null || _data != null) return;
    final generation = ++_generation;
    try {
      final job = (widget.startJob ?? DailyStarTimelineJob.start)(request, (
        done,
        total,
      ) {
        if (mounted && generation == _generation)
          setState(() {
            _completed = done;
          });
      });
      setState(() {
        _job = job;
        _message = null;
        _completed = 0;
      });
      job.result.then(
        (result) {
          if (!mounted || generation != _generation) return;
          if (result.requestIdentity != request.identity) {
            setState(() {
              _job = null;
              _message = AppText.timelineChangedInput;
            });
            return;
          }
          setState(() {
            _data = result;
            _job = null;
            _message = null;
          });
          if (_selected != 3) _loadForecast();
        },
        onError: (Object error) {
          if (!mounted || generation != _generation) return;
          setState(() {
            _job = null;
            _selected = 3;
            _message = error is DailyStarTimelineCancelled
                ? AppText.timelineCancelled
                : AppText.timelineFailed;
          });
        },
      );
    } catch (_) {
      setState(() {
        _job = null;
        _selected = 3;
        _message = AppText.timelineStartFailed;
      });
    }
  }

  void _loadForecast({bool force = false}) {
    final request = _request;
    final exportRequest = _forecastRequest;
    final identity = _forecastIdentity;
    final positions = _data;
    if ((!force && _selected == 3) ||
        request == null ||
        exportRequest == null ||
        identity == null ||
        positions == null ||
        _forecastJob != null ||
        _forecastData != null) {
      return;
    }
    final generation = ++_forecastGeneration;
    try {
      final job = (widget.startForecastJob ?? DailyTimepointForecastJob.start)(
        identity,
        exportRequest,
        request,
        positions,
        (done, total) {
          if (mounted && generation == _forecastGeneration) {
            setState(() => _forecastCompleted = done);
          }
        },
      );
      setState(() {
        _forecastJob = job;
        _forecastFailed = false;
        _forecastCompleted = 0;
        _shareStatus = _sharePendingAfterForecast
            ? '共有カード用の時刻別点数を計算しています。'
            : null;
      });
      job.result.then(
        (result) {
          if (!mounted || generation != _forecastGeneration) return;
          if (result.scoreIdentity != identity ||
              result.timelineIdentity != request.identity ||
              result.targetDateJst != request.plan.targetDateJst) {
            setState(() {
              _forecastJob = null;
              _forecastData = null;
              _forecastFailed = true;
              _shareStatus = _sharePendingAfterForecast
                  ? '時刻別点数を用意できませんでした。再試行できます。'
                  : null;
            });
            return;
          }
          final openPendingShare = _sharePendingAfterForecast;
          setState(() {
            _forecastData = result;
            _forecastJob = null;
            _forecastFailed = false;
            _sharePendingAfterForecast = false;
            _shareStatus = null;
          });
          if (openPendingShare) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _openShareComposer(request, positions, result);
            });
          }
        },
        onError: (Object error) {
          if (!mounted || generation != _forecastGeneration) return;
          setState(() {
            _forecastJob = null;
            _forecastData = null;
            _forecastFailed = true;
            _shareStatus = _sharePendingAfterForecast
                ? '時刻別点数を用意できませんでした。再試行できます。'
                : null;
          });
        },
      );
    } catch (_) {
      setState(() {
        _forecastJob = null;
        _forecastData = null;
        _forecastFailed = true;
        _shareStatus = _sharePendingAfterForecast
            ? '時刻別点数を用意できませんでした。再試行できます。'
            : null;
      });
    }
  }

  void _cancel() {
    _generation++;
    _forecastGeneration++;
    final job = _job;
    final forecastJob = _forecastJob;
    setState(() {
      _job = null;
      _forecastJob = null;
      _selected = 3;
      _completed = 0;
      _forecastCompleted = 0;
      _forecastFailed = false;
      _forecastData = null;
      _sharePendingAfterForecast = false;
      _shareStatus = null;
      _message = AppText.timelineCancelled;
    });
    job?.cancel();
    forecastJob?.cancel();
  }

  void _shareFlow() {
    final request = _request;
    final data = _data;
    if (request == null || data == null || _job != null) return;
    final forecast = _forecastData;
    final hasCurrentForecast =
        forecast != null &&
        forecast.scoreIdentity == _forecastIdentity &&
        forecast.timelineIdentity == request.identity &&
        forecast.targetDateJst == request.plan.targetDateJst;
    if (hasCurrentForecast) {
      setState(() {
        _sharePendingAfterForecast = false;
        _shareStatus = null;
      });
      _openShareComposer(request, data, forecast);
      return;
    }
    setState(() {
      _sharePendingAfterForecast = true;
      _shareStatus = '共有カード用の時刻別点数を計算しています。';
      if (forecast != null) _forecastData = null;
    });
    if (_forecastJob == null) {
      _loadForecast(force: true);
      if (_forecastJob == null && _forecastData == null) {
        setState(() {
          _forecastFailed = true;
          _shareStatus = '時刻別点数を用意できませんでした。再試行できます。';
        });
      }
    }
  }

  void _openShareComposer(
    DailyStarTimelineRequest request,
    DailyStarTimelineResult data,
    DailyTimepointForecastResult forecast,
  ) {
    if (!mounted ||
        _request?.identity != request.identity ||
        _data?.requestIdentity != request.identity ||
        forecast.scoreIdentity != _forecastIdentity ||
        forecast.timelineIdentity != request.identity ||
        forecast.targetDateJst != request.plan.targetDateJst) {
      return;
    }
    showDailyStarTimelineShareComposer(
      context,
      data: DailyStarTimelineShareData.checked(
        request: request,
        result: data,
        scoreResult: forecast,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLanguageScope.stringsOf(context);
    final request = _request;
    final point =
        _data?.points[_selected] ??
        (_selected == 3 ? request?.noonSnapshot : null);
    return GlassPanel(
      key: const ValueKey('daily-star-timeline'),
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Icon(
                Icons.schedule_outlined,
                color: Color(0xFF57D6D1),
                size: 18,
              ),
              Text(
                strings.text(AppText.dailyStarTimeline),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            strings.text(AppText.timelineTapHint),
            style: const TextStyle(fontSize: 12),
          ),
          if (request != null) ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
                final minimum = 7 * 64.0 * scale.clamp(1.0, 1.6);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (constraints.maxWidth < minimum)
                      Text(
                        strings.text(AppText.timelineScrollHint),
                        style: const TextStyle(fontSize: 11),
                      ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: math.max(constraints.maxWidth, minimum),
                        child: Column(
                          children: [
                            SizedBox(
                              height: 40,
                              width: double.infinity,
                              child: CustomPaint(
                                painter: DailyStarTimeBarPainter(
                                  plan: request.plan,
                                  voidMoon: request.voidMoon,
                                  selected: _selected,
                                ),
                              ),
                            ),
                            Row(
                              children: [
                                for (var i = 0; i < 7; i++)
                                  Expanded(
                                    child: Semantics(
                                      selected: i == _selected,
                                      label:
                                          request.plan.points[i].displayTime +
                                          (i == 6
                                              ? ' ' +
                                                    strings.text(
                                                      AppText
                                                          .timelineNextMidnight,
                                                    )
                                              : ''),
                                      child: TextButton(
                                        key: ValueKey(
                                          'daily-star-point-' +
                                              request
                                                  .plan
                                                  .points[i]
                                                  .hourFromDayStart
                                                  .toString(),
                                        ),
                                        onPressed: () => _select(i),
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 2,
                                            vertical: 8,
                                          ),
                                          backgroundColor: i == _selected
                                              ? const Color(
                                                  0xFF57D6D1,
                                                ).withValues(alpha: 0.17)
                                              : null,
                                        ),
                                        child: Text(
                                          request.plan.points[i].displayTime +
                                              (i == 6
                                                  ? '\n' +
                                                        strings.text(
                                                          AppText
                                                              .timelineNextMidnight,
                                                        )
                                                  : ''),
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            if (request.voidMoon != null)
              Text(
                strings.text(AppText.timelineVoidBand) +
                    _timelineTimeLabel(request.voidMoon!.startTime) +
                    '〜' +
                    _timelineTimeLabel(request.voidMoon!.endTime),
                style: const TextStyle(fontSize: 12, color: Color(0xFFF6D77A)),
              )
            else
              Text(
                strings.text(AppText.timelineNoVoidInfo),
                style: const TextStyle(fontSize: 12),
              ),
            const SizedBox(height: 10),
            if (_job != null) ...[
              Text(
                strings.timelineProgress(_completed),
                key: const ValueKey('daily-star-progress'),
              ),
              const LinearProgressIndicator(),
            ],
            if (_forecastJob != null) ...[
              Text(
                _localized(
                  strings,
                  '選択時刻の点数を計算中… ($_forecastCompleted/7)',
                  'Calculating selected-time scores… ($_forecastCompleted/7)',
                ),
                key: const ValueKey('daily-star-score-progress'),
              ),
              const LinearProgressIndicator(),
            ],
            if (_job != null || _forecastJob != null)
              TextButton(
                key: const ValueKey('daily-star-cancel'),
                onPressed: _cancel,
                child: Text(strings.text(AppText.cancel)),
              ),
            if (widget.details != null) _selectedScoreCard(strings),
            if (point != null) _detail(point, strings),
            if (_data == null && _job == null && _forecastJob == null)
              TextButton.icon(
                key: const ValueKey('daily-star-load'),
                onPressed: _load,
                icon: const Icon(Icons.read_more),
                label: Text(
                  strings.text(
                    _message == null ? AppText.timelineLoad : AppText.retry,
                  ),
                ),
              ),
            if (_data != null && _job == null)
              OutlinedButton.icon(
                key: const ValueKey('daily-star-share'),
                onPressed: _shareFlow,
                icon: const Icon(Icons.ios_share_outlined, size: 18),
                label: Text(strings.text(AppText.timelineShareImage)),
              ),
            if (_shareStatus != null)
              _scoreStatus(
                strings,
                _timelineShareMessage(context, _shareStatus!),
                key: const ValueKey('daily-star-share-status'),
                loading: _forecastJob != null,
              ),
            if (_sharePendingAfterForecast && _forecastFailed)
              TextButton.icon(
                key: const ValueKey('daily-star-share-retry'),
                onPressed: _shareFlow,
                icon: const Icon(Icons.refresh),
                label: Text(
                  _localized(strings, '点数を再試行して共有', 'Retry scores and share'),
                ),
              ),
            Text(
              strings.text(
                request.requireHighPrecision
                    ? AppText.timelineScope
                    : AppText.timelineApproximateScope,
              ),
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
          ],
          if (_message != null)
            Text(
              strings.text(_message!),
              key: const ValueKey('daily-star-message'),
            ),
        ],
      ),
    );
  }

  String _localized(AppStrings strings, String japanese, String english) =>
      strings.language == AppLanguage.en ? english : japanese;

  Widget _selectedScoreCard(AppStrings strings) {
    final request = _request;
    if (request == null) return const SizedBox.shrink();
    final index = _selected;
    if (index == 3) {
      try {
        final noon = NineAreaDailyConsultSnapshot.build(
          date: request.plan.primaryNoon.instantUtc,
          contextData: widget.contextData,
        );
        return _scoreCard(noon, strings, index, isNoon: true);
      } catch (_) {
        return _scoreStatus(
          strings,
          _localized(
            strings,
            '正午の点数を表示できません。日付を確認してください。',
            'Could not display the noon scores. Check the date.',
          ),
          key: const ValueKey('daily-star-score-error'),
        );
      }
    }
    if (_forecastJob != null) {
      return _scoreStatus(
        strings,
        _localized(
          strings,
          '選択時刻の比較用点数を計算しています。',
          'Calculating comparison scores for the selected time.',
        ),
        key: const ValueKey('daily-star-score-loading'),
        loading: true,
      );
    }
    if (_forecastFailed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _scoreStatus(
            strings,
            _localized(
              strings,
              '選択時刻の点数を読み取れませんでした。再試行できます。',
              'Could not read the selected-time scores. You can retry.',
            ),
            key: const ValueKey('daily-star-score-error'),
          ),
          TextButton.icon(
            key: const ValueKey('daily-star-score-retry'),
            onPressed: _loadForecast,
            icon: const Icon(Icons.refresh),
            label: Text(strings.text(AppText.retry)),
          ),
        ],
      );
    }
    final result = _forecastData;
    if (result == null ||
        result.scoreIdentity != _forecastIdentity ||
        result.timelineIdentity != request.identity ||
        result.targetDateJst != request.plan.targetDateJst) {
      return _scoreStatus(
        strings,
        _localized(
          strings,
          '選択時刻の点数を準備しています。',
          'Preparing scores for the selected time.',
        ),
        key: const ValueKey('daily-star-score-loading'),
        loading: true,
      );
    }
    try {
      final points = result.forecasts['points'] as List;
      final point = _timelineMap(points[index]);
      final snapshot = _timelineMap(point['nine_area_forecast']);
      return _scoreCard(snapshot, strings, index, isNoon: false);
    } catch (_) {
      return _scoreStatus(
        strings,
        _localized(
          strings,
          '選択時刻の点数を読み取れませんでした。再試行できます。',
          'Could not read the selected-time scores. You can retry.',
        ),
        key: const ValueKey('daily-star-score-error'),
      );
    }
  }

  Widget _scoreStatus(
    AppStrings strings,
    String message, {
    required Key key,
    bool loading = false,
  }) => Container(
    key: key,
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.055),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (loading) ...[
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(child: Text(message, style: const TextStyle(fontSize: 12))),
      ],
    ),
  );

  Widget _scoreCard(
    Map<String, Object?> snapshot,
    AppStrings strings,
    int index, {
    required bool isNoon,
  }) {
    final areas = snapshot['areas'] as List;
    final areaByKey = <String, Map<String, Object?>>{
      for (final value in areas)
        if (value is Map)
          Map<String, Object?>.from(value)['key'] as String:
              Map<String, Object?>.from(value),
    };
    final request = _request!;
    final clock = request.plan.points[index];
    final timeLabel =
        clock.displayTime +
        (clock.isDayEndBoundary
            ? strings.text(AppText.timelineEndBoundary)
            : '');
    final felt = areaByKey[NineAreaKey.felt.name];
    final feltLabel = felt?['predicted_felt_label'];
    final unavailable = _localized(strings, '未予測', 'Unavailable');
    final feltValue = feltLabel is String
        ? strings.feltLabelText(feltLabel) ?? unavailable
        : unavailable;
    return Container(
      key: const ValueKey('daily-timepoint-score-card'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _localized(
              strings,
              '選択時刻の9項目（比較表示）',
              'Nine categories at the selected time (comparison)',
            ),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 3),
          Text(
            _localized(strings, '時刻：', 'Time: ') + timeLabel,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.76),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isNoon
                ? _localized(
                    strings,
                    '正午は日全体の既存基準です。',
                    'Noon is the existing reference for the daily outlook.',
                  )
                : _localized(
                    strings,
                    '既存の日モデルをこの時刻へ適用した比較用の試作値です。日全体の見通しは正午基準で、7時点平均や検証済みの時間帯予測ではありません。',
                    'Experimental comparison values from applying the existing daily model at this time. The daily outlook remains noon-based; the seven samples are not averaged or validated time-of-day forecasts.',
                  ),
            style: TextStyle(
              fontSize: 11,
              height: 1.45,
              color: Colors.white.withValues(alpha: 0.72),
            ),
          ),
          const SizedBox(height: 8),
          for (final key in NineAreaKey.values)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      strings.nineAreaTitle(key.name),
                      key: ValueKey('daily-timepoint-area-${key.name}-label'),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    key == NineAreaKey.felt
                        ? feltValue
                        : (areaByKey[key.name]?['score'] is int
                              ? (areaByKey[key.name]!['score'] as int)
                                    .toString()
                              : unavailable),
                    key: ValueKey('daily-timepoint-area-${key.name}-value'),
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 2),
          Text(
            isNoon
                ? _localized(
                    strings,
                    '体感は数値点ではありません。',
                    'Felt experience has no numeric score.',
                  )
                : _localized(
                    strings,
                    '体感は数値点ではなく、ラベル候補です。',
                    'Felt experience is a label candidate, not a numeric score.',
                  ),
            style: TextStyle(
              fontSize: 10,
              color: Colors.white.withValues(alpha: 0.62),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detail(DailyStarTimelinePoint point, AppStrings strings) {
    final moon = point.moon;
    final aspects = point.moonAspects.take(2).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.timelineMoonDetail(
            time: point.clock.displayTime,
            endBoundary: point.clock.isDayEndBoundary,
            signKey: moon.sign.name,
            canonicalJapaneseSign: moon.sign.label,
            degree: moon.degree.toStringAsFixed(1),
          ),
          key: const ValueKey('daily-star-detail'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        Text(
          strings.timelineNatalHouse(moon.house),
          style: const TextStyle(fontSize: 12),
        ),
        for (final aspect in aspects)
          Text(
            strings.timelineAspect(
              canonicalJapaneseLabel: aspect.label,
              transitKey: aspect.transitPlanet.name,
              natalKey: aspect.natalPlanet.name,
              aspectKey: aspect.type.name,
              orb: aspect.orb.toStringAsFixed(1),
            ),
            style: const TextStyle(fontSize: 12),
          ),
        if (aspects.isEmpty)
          Text(
            strings.text(AppText.timelineNoMoonAspects),
            style: const TextStyle(fontSize: 12),
          ),
        Text(
          strings.text(AppText.timelineHintTitle) +
              strings.timelineHint(
                signKey: moon.sign.name,
                isVoid: point.isVoid,
                canonicalJapaneseHint: dailyStarTimelinePointHint(point),
              ),
          key: const ValueKey('daily-star-hint'),
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}

String dailyStarTimelinePointHint(DailyStarTimelinePoint point) => point.isVoid
    ? '月ボイド中。新しい決定より、見直し・休息・準備を。'
    : moonSignTimeActionHint(point.moon.sign);

String _timelineTimeLabel(DateTime value) {
  final jst = value.toUtc().add(DailySevenTimepointPlan.jstOffset);
  final label =
      jst.hour.toString().padLeft(2, '0') +
      ':' +
      jst.minute.toString().padLeft(2, '0');
  return jst.second == 0 && jst.microsecond == 0 && jst.millisecond == 0
      ? label
      : label + ':' + jst.second.toString().padLeft(2, '0');
}

class DailyStarTimeBarPainter extends CustomPainter {
  const DailyStarTimeBarPainter({
    required this.plan,
    required this.voidMoon,
    required this.selected,
    this.trackColor = const Color(0xFF57D6D1),
    this.voidColor = const Color(0xFFF6D77A),
  });
  final DailySevenTimepointPlan plan;
  final VoidMoonPeriod? voidMoon;
  final int selected;
  final Color trackColor, voidColor;

  /// Visual clipping only; source event instants remain unchanged.
  (double, double)? get voidFractions {
    final period = voidMoon;
    if (period == null) return null;
    final total = plan.dayEndUtc.difference(plan.dayStartUtc).inMicroseconds;
    final start =
        period.startTime.toUtc().difference(plan.dayStartUtc).inMicroseconds /
        total;
    final end =
        period.endTime.toUtc().difference(plan.dayStartUtc).inMicroseconds /
        total;
    final clippedStart = start.clamp(0.0, 1.0).toDouble();
    final clippedEnd = end.clamp(0.0, 1.0).toDouble();
    return clippedEnd > clippedStart ? (clippedStart, clippedEnd) : null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final left = size.width / 14;
    final width = size.width - left * 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, 15, width, 10),
        const Radius.circular(5),
      ),
      Paint()..color = trackColor.withValues(alpha: 0.15),
    );
    final fractions = voidFractions;
    if (fractions != null)
      canvas.drawRect(
        Rect.fromLTWH(
          left + width * fractions.$1,
          13,
          width * (fractions.$2 - fractions.$1),
          14,
        ),
        Paint()..color = voidColor.withValues(alpha: 0.7),
      );
    for (var i = 0; i < 7; i++) {
      final offset = Offset(left + width * i / 6, 20);
      canvas.drawCircle(
        offset,
        i == selected ? 6 : 3,
        Paint()..color = trackColor,
      );
    }
  }

  @override
  bool shouldRepaint(covariant DailyStarTimeBarPainter oldDelegate) =>
      oldDelegate.selected != selected ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.voidColor != voidColor ||
      oldDelegate.plan.targetDateJst != plan.targetDateJst ||
      oldDelegate.voidMoon?.startTime != voidMoon?.startTime ||
      oldDelegate.voidMoon?.endTime != voidMoon?.endTime;
}
