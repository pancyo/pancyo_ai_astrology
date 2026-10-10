part of 'main.dart';

/// Birth-chart transits, not a relocated or instantaneous observer chart.
class DailyIntradayPositionsExport {
  DailyIntradayPositionsExport.checked({
    required this.request,
    required DailyStarTimelineResult result,
    required List<List<PlanetPlacement>> comparisonPlacements,
  }) : points = result.points,
       comparisonPlacements = List.unmodifiable([
         for (final values in comparisonPlacements)
           List<PlanetPlacement>.unmodifiable(values),
       ]) {
    if (result.requestIdentity != request.identity ||
        comparisonPlacements.length != 7) {
      throw StateError('日内JSONの計算条件が一致しません。');
    }
    // Recheck completeness/noon/order even for results supplied by a worker.
    DailyStarTimelineResult.checked(
      request: request,
      points: points,
      elapsedMilliseconds: result.elapsedMilliseconds,
      workerName: result.workerName,
    );
    for (final values in this.comparisonPlacements) {
      _timelineValidatePlacements(values, natal: false);
      for (final p in values) {
        if (request.houseFrame.houseForLongitude(
              p.sign.index * 30 + p.degree,
            ) !=
            p.house) {
          throw StateError('比較配置の出生図ハウスが一致しません。');
        }
      }
    }
    // The next 00:00 is both the first sample's +24h and the last sample.
    if (!_timelinePlacementsMatch(
      this.comparisonPlacements[0],
      points[6].placements,
    )) {
      throw StateError('翌日境界の配置が一致しません。');
    }
  }

  final DailyStarTimelineRequest request;
  final List<DailyStarTimelinePoint> points;
  final List<List<PlanetPlacement>> comparisonPlacements;
  static const schema = 'pancyo_daily_intraday_positions_v1';

  Map<String, Object?> toJson() => {
    'schema': schema,
    'purpose': 'positions_for_ai_consultation_not_hourly_fortune_scores',
    'target_date_jst': request.plan.targetDateJst,
    'time_zone': 'Asia/Tokyo',
    'fixed_utc_offset': '+09:00',
    'ephemeris_time_contract': 'instant_to_utc_v1',
    'chart_reference': 'natal_chart_transits',
    'current_location_required': false,
    'instantaneous_observer_chart': {
      'status': 'not_in_scope',
      'note': '出生図のASC／MCとハウスを固定。現在地の瞬間ASC／MCは計算しない。',
    },
    'house_calculation': {
      'reference': 'natal_chart',
      'requested_system': request.requestedHouseSystem.name,
      'resolved_system': request.resolvedHouseSystem.name,
      'natal_cusps_longitude': request.cusps.toList(),
      'natal_angles': [
        for (final p in request.natal)
          if (p.planet == AstroPlanet.ascendant ||
              p.planet == AstroPlanet.midheaven)
            _intradayPlacement(p),
      ],
      'natal_angles_status':
          request.natal
                  .where(
                    (p) =>
                        p.planet == AstroPlanet.ascendant ||
                        p.planet == AstroPlanet.midheaven,
                  )
                  .length ==
              2
          ? 'available_from_existing_birth_chart'
          : 'not_available_in_existing_birth_chart',
      'birth_input_quality_reference': 'birth_input_quality',
      'birth_facts_verified_by_exporter': false,
    },
    'calculation_source': {
      'provider': request.sourceName,
      'provider_uses_high_precision': request.requireHighPrecision,
      'inherited_noon_individual_provenance': 'not_tracked',
      'note': '全体の計算元フラグは、出生値の事実確認や個別計算の独立精度保証ではない。',
    },
    'completeness': {
      'status': 'complete',
      'point_count': 7,
      'required_planets_per_point': 10,
    },
    'day_interval': {
      'start_utc': request.plan.dayStartUtc.toIso8601String(),
      'end_utc': request.plan.dayEndUtc.toIso8601String(),
      'start_inclusive': true,
      'end_inclusive': false,
    },
    'daily_fortune_reference': {
      'field': 'nine_area_daily',
      'instant_utc': request.plan.primaryNoon.instantUtc.toIso8601String(),
      'reference_count': 1,
      'hourly_scores_generated': false,
      'daily_scores_averaged_from_samples': false,
    },
    'boundary_note':
        '24:00は翌日00:00と同じ瞬間。日内は[00:00,翌日00:00)。7点を7日・独立7観測として数えない。',
    'motion_comparison': {
      'method': 'existing_engine_forward_24h_longitude_difference',
      'note': '逆行・接近／分離は既存の翌日差分判定。瞬間速度や正確なピーク時刻ではない。',
      'near_exact_orb_threshold_degrees': 0.7,
      'transit_pair_orb_limit_degrees': 6.0,
    },
    'event_coverage': {
      'raw_intervals': ['void_moon_from_existing_noon_context'],
      'legacy_event_fields': [
        'station_events_jst',
        'daily_events_jst',
        'lunar_phase',
      ],
      'all_events_and_exact_aspect_peaks_complete': false,
      'void_membership_scope': 'existing_noon_context_interval_only',
      'note': '既存イベント欄は維持。4時間刻みから正確なピークや全ボイド区間を推測しない。',
    },
    'void_moon_interval': _voidInterval(),
    'points': [for (var i = 0; i < 7; i++) _point(i)],
  };

  Map<String, Object?>? _voidInterval() {
    final value = request.voidMoon;
    if (value == null) return null;
    final start = value.startTime.toUtc(), end = value.endTime.toUtc();
    return {
      'start_utc': start.toIso8601String(),
      'end_utc': end.toIso8601String(),
      'start_jst': _intradayJst(start),
      'end_jst': _intradayJst(end),
      'start_inclusive': true,
      'end_inclusive': false,
      'start_inside_target_day': request.plan.containsInstant(start),
      'end_inside_target_day': request.plan.containsInstant(end),
      'overlaps_target_day':
          start.isBefore(request.plan.dayEndUtc) &&
          end.isAfter(request.plan.dayStartUtc),
      'source': 'existing_noon_context',
      'timestamps_preserve_input_precision': true,
      'astronomical_timing_precision_independently_verified': false,
    };
  }

  Map<String, Object?> _point(int index) {
    final p = points[index], next = comparisonPlacements[index];
    final retro = <AstroPlanet>{
      for (final planet in AstroPlanet.values.skip(2).take(8))
        if (const AstrologyEngine()._isRetrograde(planet, p.placements, next))
          planet,
      ...DailyAstroEventsCard.verifiedRetrogradesAt(p.clock.instantUtc),
    };
    final pairs = FortuneScoreCalculator.transitPairAspects(
      current: p.placements,
      next: next,
    );
    return {
      ...p.clock.toJson(),
      'calculation_origin': p.clock.isPrimaryNoon
          ? 'existing_noon_context'
          : 'calculated_at_sample_instant',
      'house_reference': 'natal_chart',
      'placements': [
        for (final value in p.placements) _intradayPlacement(value),
      ],
      'natal_aspects': [
        for (final a in p.fullNatalAspects)
          {
            'transit_planet': a.transitPlanet.name,
            'natal_planet': a.natalPlanet.name,
            'aspect': a.type.name,
            'orb_degrees': a.orb,
            'legacy_area': a.area.name,
            'meaning': a.meaning,
          },
      ],
      'transit_pair_aspects': [
        for (final a in pairs)
          {
            'first_planet': a.firstPlanet.name,
            'second_planet': a.secondPlanet.name,
            'aspect': a.type.name,
            'orb_degrees': a.orb,
            'phase': a.phase == AspectPhase.exact
                ? 'near_exact_by_orb'
                : a.phase.name,
          },
      ],
      'comparison_instant_utc': p.clock.instantUtc
          .add(const Duration(days: 1))
          .toIso8601String(),
      'comparison_placements': [
        for (final value in next) _intradayPlacement(value),
      ],
      'retrograde_planets': [for (final planet in retro) planet.name],
      'retrograde_sources': [
        'forward_24h_difference',
        'existing_verified_windows_when_available',
      ],
      'in_void_moon_interval': request.voidMoon == null ? null : p.isVoid,
    };
  }
}

String _intradayJst(DateTime utc) => utc
    .toUtc()
    .add(DailySevenTimepointPlan.jstOffset)
    .toIso8601String()
    .replaceFirst(RegExp(r'Z$'), '+09:00');
Map<String, Object?> _intradayPlacement(PlanetPlacement p) => {
  'planet': p.planet.name,
  'planet_label': p.planet.label,
  'sign': p.sign.name,
  'sign_label': p.sign.label,
  'degree': p.degree,
  'longitude': p.sign.index * 30.0 + p.degree,
  'house': p.house,
};

/// No location lookup beyond the existing birth chart; noon and its +24h reused.
DailyIntradayPositionsExport calculateDailyIntradayPositions({
  required DailyStarTimelineRequest request,
  required List<PlanetPlacement> nextNoonPlacements,
  EphemerisProvider? provider,
  void Function(int, int)? onProgress,
}) {
  final source = provider ?? AstrologyDataSources.current;
  if (source.sourceName != request.sourceName ||
      source.usesHighPrecisionAstroData != request.requireHighPrecision) {
    throw StateError('日内JSONの計算元が一致しません。');
  }
  final before = SwissEphemerisProvider._placementFallbackCount;
  final cache = <DateTime, List<PlanetPlacement>>{
    request.plan.primaryNoon.instantUtc: request.noonPlacements,
    request.plan.primaryNoon.instantUtc.add(const Duration(days: 1)):
        nextNoonPlacements,
  };
  List<PlanetPlacement> positions(DateTime instant) {
    final values = cache.putIfAbsent(
      instant,
      () => source.placementsFor(instant, houseFrame: request.houseFrame),
    );
    _timelineValidatePlacements(values, natal: false);
    if (request.requireHighPrecision &&
        before != SwissEphemerisProvider._placementFallbackCount) {
      throw StateError('日内JSONの配置が簡易計算へ戻りました。');
    }
    return values;
  }

  final points = <DailyStarTimelinePoint>[];
  final comparisons = <List<PlanetPlacement>>[];
  for (final clock in request.plan.points) {
    points.add(
      clock.isPrimaryNoon
          ? request.noonSnapshot
          : DailyStarTimelinePoint.checked(
              request: request,
              clock: clock,
              calculatedAtUtc: clock.instantUtc,
              placements: positions(clock.instantUtc),
              fullNatalAspects: source.aspects(
                transit: positions(clock.instantUtc),
                natal: request.natal,
              ),
            ),
    );
    comparisons.add(positions(clock.instantUtc.add(const Duration(days: 1))));
    onProgress?.call(points.length, 7);
  }
  return DailyIntradayPositionsExport.checked(
    request: request,
    result: DailyStarTimelineResult.checked(
      request: request,
      points: points,
      elapsedMilliseconds: 0,
      workerName: Isolate.current.debugName,
    ),
    comparisonPlacements: comparisons,
  );
}

class DailyConsultExportRequest {
  DailyConsultExportRequest({
    required this.date,
    required this.profile,
    required this.details,
    required this.requestedHouseSystem,
    required this.sourceName,
    required this.requireHighPrecision,
    required this.generatedAt,
    HoroscopeReadingContext? contextData,
  }) : contextData = contextData == null
           ? null
           : _freezeDailyConsultContext(contextData) {
    final jst = date.toUtc().add(DailySevenTimepointPlan.jstOffset);
    plan = DailySevenTimepointPlan.forJstDate(
      '${jst.year.toString().padLeft(4, '0')}-${jst.month.toString().padLeft(2, '0')}-${jst.day.toString().padLeft(2, '0')}',
    );
    if (plan.primaryNoon.instantUtc != date.toUtc())
      throw StateError('日JSONはJST正午の基準が必要です。');
    final c = this.contextData;
    if (c != null) {
      DailyStarTimelineRequest.fromContext(
        date: date,
        contextData: c,
        profile: profile,
        requestedHouseSystem: requestedHouseSystem,
      );
      if (c.ephemerisSourceName != sourceName ||
          c.usesHighPrecisionAstroData != requireHighPrecision)
        throw StateError('正午の計算元が一致しません。');
    }
  }
  final DateTime date, generatedAt;
  final AstroProfile profile;
  final UserProfileDetails details;
  final HouseSystem requestedHouseSystem;
  final String sourceName;
  final bool requireHighPrecision;
  final HoroscopeReadingContext? contextData;
  late final DailySevenTimepointPlan plan;
  // Private matching token, never part of the JSON or diagnostic logs.
  String get identity => sha256
      .convert(
        utf8.encode(
          jsonEncode([
            'pancyo_astrology_daily_consult_v4',
            date.toUtc().toIso8601String(),
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
            contextData == null
                ? null
                : DailyStarTimelineRequest.fromContext(
                    date: date,
                    contextData: contextData!,
                    profile: profile,
                    requestedHouseSystem: requestedHouseSystem,
                  ).identity,
            if (contextData != null)
              DailyAstroDataExportCard(
                date: date,
                profile: profile,
                details: details,
                contextData: contextData!,
              ).buildData(generatedAt: generatedAt),
          ]),
        ),
      )
      .toString();
}

HoroscopeReadingContext _freezeDailyConsultContext(HoroscopeReadingContext c) =>
    HoroscopeReadingContext(
      natal: NatalChart(
        profile: c.natal.profile,
        placements: List.unmodifiable(c.natal.placements),
        stelliums: List.unmodifiable([
          for (final s in c.natal.stelliums)
            HouseEmphasis(
              house: s.house,
              planets: List.unmodifiable(s.planets),
              theme: s.theme,
            ),
        ]),
        retrogradePlanets: Set.unmodifiable(c.natal.retrogradePlanets),
      ),
      transit: TransitChart(
        date: c.transit.date,
        placements: List.unmodifiable(c.transit.placements),
        voidMoon: c.transit.voidMoon,
      ),
      nextTransitPlacements: List.unmodifiable(c.nextTransitPlacements),
      aspects: List.unmodifiable(c.aspects),
      fullAspects: List.unmodifiable(c.fullAspects),
      nextAspects: List.unmodifiable(c.nextAspects),
      transitPairAspects: List.unmodifiable(c.transitPairAspects),
      retrogradePlanets: Set.unmodifiable(c.retrogradePlanets),
      houseTransits: List.unmodifiable(c.houseTransits),
      returns: List.unmodifiable(c.returns),
      birthPlace: c.birthPlace,
      ephemerisSourceName: c.ephemerisSourceName,
      ephemerisPrecisionNotice: c.ephemerisPrecisionNotice,
      usesHighPrecisionAstroData: c.usesHighPrecisionAstroData,
      houseSystem: c.houseSystem,
      houseCusps: List.unmodifiable(c.houseCusps),
      scoreDayStartUtc: c.scoreDayStartUtc,
    );

Map<String, Object?> buildDailyConsultDataV3(
  DailyConsultExportRequest request, {
  void Function(int, int)? onProgress,
}) {
  final source = AstrologyDataSources.current;
  if (request.contextData == null &&
      HouseSystemSettings.current.value != request.requestedHouseSystem) {
    throw StateError('日JSONの要求ハウス方式が一致しません。');
  }
  if (source.sourceName != request.sourceName ||
      source.usesHighPrecisionAstroData != request.requireHighPrecision) {
    throw StateError('日JSONの計算元を利用できません。');
  }
  final contextData =
      request.contextData ??
      const AstrologyEngine().buildPreviewContext(
        profile: request.profile,
        date: request.date,
      );
  final timelineRequest = DailyStarTimelineRequest.fromContext(
    date: request.date,
    profile: request.profile,
    contextData: contextData,
    requestedHouseSystem: request.requestedHouseSystem,
  );
  final intraday = calculateDailyIntradayPositions(
    request: timelineRequest,
    nextNoonPlacements: contextData.nextTransitPlacements,
    onProgress: onProgress,
  );
  // Keep the legacy synchronous v2 builder as an explicit compatibility baseline.
  final legacy = DailyAstroDataExportCard(
    date: request.date,
    profile: request.profile,
    details: request.details,
    contextData: contextData,
  ).buildData(generatedAt: request.generatedAt);
  return {
    ...legacy,
    'schema': 'pancyo_astrology_daily_consult_v3',
    'intraday_positions': intraday.toJson(),
  };
}

const _presentationExplanationSchema = 'pancyo_presentation_explanation_v1';

/// Serialize the same presentation service used by the UI from an already
/// serialized daily snapshot. This avoids another ephemeris or score pass.
Map<String, Object?> _dailyPresentationExplanation(
  Map<String, Object?> snapshot, {
  UserProfileDetails? supplement,
}) {
  final target = snapshot['target_date_jst'];
  final rawAreas = snapshot['areas'];
  if (target is! String || rawAreas is! List || rawAreas.length != 9) {
    throw StateError('説明別添に必要な日付または9項目がありません。');
  }
  final targetDate = DateTime.parse('${target}T03:00:00.000Z');
  final predictions = <NineAreaPrediction>[];
  final seen = <NineAreaKey>{};
  for (final raw in rawAreas) {
    if (raw is! Map) throw StateError('説明別添の項目形式が不正です。');
    final area = Map<String, Object?>.from(raw);
    final keyRaw = area['key'];
    if (keyRaw is! String) throw StateError('説明別添の項目キーがありません。');
    final key = NineAreaKey.values.byName(keyRaw);
    if (!seen.add(key)) throw StateError('説明別添の項目が重複しています。');
    final score = area['score'];
    if (score != null && score is! int) {
      throw StateError('説明別添の数値点が整数ではありません。');
    }
    Map<String, Object?>? object(Object? value) =>
        value is Map ? Map<String, Object?>.from(value) : null;
    FeltForecastResult? felt(Map<String, Object?>? rawFelt) {
      if (rawFelt == null) return null;
      final label = rawFelt['predicted_felt_label'];
      final trace = object(rawFelt['felt_prediction']);
      if ((label != null && label is! String) || trace == null) {
        throw StateError('説明別添の体感候補が不正です。');
      }
      return FeltForecastResult(label as String?, trace);
    }

    final primaryTrace = object(area['felt_prediction']);
    final primaryLabel = area['predicted_felt_label'];
    if (primaryLabel != null && primaryLabel is! String) {
      throw StateError('説明別添の正規体感ラベルが不正です。');
    }
    final feltForecast = primaryTrace == null
        ? null
        : FeltForecastResult(primaryLabel as String?, primaryTrace);
    predictions.add(
      NineAreaPrediction(
        key: key,
        title: area['name'] as String,
        // Icons are not serialized by the explanation API. The canonical key
        // and stored reading are the relevant inputs to the explanation.
        icon: Icons.auto_awesome,
        summary: area['summary'] as String,
        detail: area['explanation'] as String,
        score: score as int?,
        provisional: area['status'] == 'trial_unvalidated',
        scoreBreakdown: object(area['score_breakdown']),
        feltForecast: feltForecast,
        feltComparison: felt(object(area['felt_comparison'])),
        longTermContext: object(area['long_term_context']),
      ),
    );
  }
  if (seen.length != NineAreaKey.values.length) {
    throw StateError('説明別添の9項目がそろっていません。');
  }
  const strings = AppStrings(AppLanguage.ja);
  return {
    'schema': _presentationExplanationSchema,
    'language': 'ja',
    'areas': [
      for (final prediction in predictions)
        ForecastExplanation.forDaily(
          prediction: prediction,
          targetDate: targetDate,
          strings: strings,
          depth: ReadingDepth.detailed,
          supplement: supplement,
        ).toJson(),
    ],
  };
}

class DailyConsultExportResult {
  DailyConsultExportResult._(
    this.requestIdentity,
    this.json,
    this.elapsedMilliseconds,
    this.workerName,
  );
  final String requestIdentity, json;
  final int elapsedMilliseconds;
  final String? workerName;
  Map<String, Object?> get data =>
      Map<String, Object?>.from(jsonDecode(json) as Map);
}

DailyConsultExportResult calculateDailyConsultExport(
  DailyConsultExportRequest request, {
  void Function(int, int)? onProgress,
}) {
  final watch = Stopwatch()..start();
  final data = buildDailyConsultDataV4(request, onProgress: onProgress);
  return DailyConsultExportResult._(
    request.identity,
    jsonEncode(data),
    watch.elapsedMilliseconds,
    Isolate.current.debugName,
  );
}

class DailyConsultExportCancelled implements Exception {
  const DailyConsultExportCancelled();
}

abstract class DailyConsultExportOperation {
  Future<DailyConsultExportResult> get result;
  void cancel();
}

typedef DailyConsultExportStarter =
    DailyConsultExportOperation Function(
      DailyConsultExportRequest request,
      void Function(int, int) onProgress,
    );

class DailyConsultExportJob implements DailyConsultExportOperation {
  DailyConsultExportJob.start(
    DailyConsultExportRequest request,
    void Function(int, int) onProgress,
  ) {
    _port.listen((message) {
      if (_finished) return;
      if (message is DailyConsultExportResult) {
        _finish();
        _result.complete(message);
      } else if (message is List &&
          message.length == 3 &&
          message.first == 'progress') {
        onProgress(message[1] as int, message[2] as int);
      } else {
        _finish();
        _result.completeError(StateError('日JSONを作成できませんでした。'));
      }
    });
    unawaited(_spawn(request));
  }
  final _port = ReceivePort();
  final _result = Completer<DailyConsultExportResult>();
  Isolate? _isolate;
  bool _finished = false;
  @override
  Future<DailyConsultExportResult> get result => _result.future;
  Future<void> _spawn(DailyConsultExportRequest request) async {
    try {
      final isolate = await Isolate.spawn(
        _dailyConsultWorker,
        (request, _port.sendPort),
        debugName: 'pancyo-daily-consult-export',
        onError: _port.sendPort,
        onExit: _port.sendPort,
      );
      if (_finished)
        isolate.kill(priority: Isolate.immediate);
      else
        _isolate = isolate;
    } catch (_) {
      if (!_finished) {
        _finish();
        _result.completeError(StateError('日JSONの別処理を開始できませんでした。'));
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
    _result.completeError(const DailyConsultExportCancelled());
  }
}

void _dailyConsultWorker((DailyConsultExportRequest, SendPort) input) {
  try {
    // Worker-only setting, never persisted and never applied to the UI isolate.
    HouseSystemSettings.current.value = input.$1.requestedHouseSystem;
    final result = calculateDailyConsultExport(
      input.$1,
      onProgress: (done, total) => input.$2.send(['progress', done, total]),
    );
    Isolate.exit(input.$2, result);
  } catch (_) {
    input.$2.send('failed');
  }
}
