part of 'main.dart';

void _validateIntradayJstDayStart(DateTime dayStartUtc) {
  final jst = dayStartUtc.toUtc().add(DailySevenTimepointPlan.jstOffset);
  if (!dayStartUtc.isUtc ||
      jst.hour != 0 ||
      jst.minute != 0 ||
      jst.second != 0 ||
      jst.millisecond != 0 ||
      jst.microsecond != 0) {
    throw ArgumentError('Fixed JST midnight in UTC required');
  }
}

DateTime _intradayScoreDayStart(DateTime instant) {
  final jst = instant.toUtc().add(DailySevenTimepointPlan.jstOffset);
  return DateTime.utc(
    jst.year,
    jst.month,
    jst.day,
  ).subtract(DailySevenTimepointPlan.jstOffset);
}

typedef IntradayVoidDayReader = VoidMoonPeriod? Function(DateTime dayStartUtc);

VoidMoonPeriod? _intradayVoidForUtcDay(
  EphemerisProvider source,
  DateTime dayStartUtc,
) {
  final raw = switch (source) {
    SwissEphemerisProvider provider => provider.voidMoonForUtcDay(dayStartUtc),
    SimpleEphemeris provider => provider.voidMoonForUtcDay(dayStartUtc),
    _ => throw StateError('時刻別点数のJSTボイド取得に未対応の計算元です。'),
  };
  if (raw == null) return null;
  return VoidMoonPeriod(
    start: _intradayJst(raw.startTime).substring(11, 16),
    end: _intradayJst(raw.endTime).substring(11, 16),
    startTime: raw.startTime,
    endTime: raw.endTime,
    guidance: raw.guidance,
  );
}

/// Seven exact-time applications of the existing daily formulas. No model
/// coefficients, daily aggregation, C1 adoption or categorical felt conversion.
Map<String, Object?> calculateDailyIntradayForecasts({
  required DailyIntradayPositionsExport positions,
  required HoroscopeReadingContext noonContext,
  UserProfileDetails? details,
  EphemerisProvider? provider,
  IntradayVoidDayReader? readVoidDay,
  void Function(int, int)? onProgress,
}) {
  final request = positions.request;
  final source = provider ?? AstrologyDataSources.current;
  final engine = const AstrologyEngine();
  if (source.sourceName != request.sourceName ||
      source.usesHighPrecisionAstroData != request.requireHighPrecision ||
      noonContext.transit.date.toUtc() != request.plan.primaryNoon.instantUtc ||
      DailyStarTimelineRequest.fromContext(
            date: request.plan.primaryNoon.instantUtc,
            contextData: noonContext,
            profile: request.profile,
            requestedHouseSystem: request.requestedHouseSystem,
          ).identity !=
          request.identity) {
    throw StateError('7時点点数の出生図・正午・計算元が一致しません。');
  }
  final fallbackBefore = SwissEphemerisProvider._placementFallbackCount;
  final voidDays = <DateTime, VoidMoonPeriod?>{};
  final values = <Map<String, Object?>>[];
  for (var i = 0; i < request.plan.points.length; i++) {
    final point = positions.points[i], clock = point.clock;
    final next = positions.comparisonPlacements[i];
    final dayStart = _intradayScoreDayStart(clock.instantUtc);
    late final HoroscopeReadingContext contextData;
    if (clock.isPrimaryNoon) {
      contextData =
          noonContext; // Preserve the displayed primary forecast exactly.
    } else {
      final voidMoon = voidDays.putIfAbsent(
        dayStart,
        () => (readVoidDay ?? (day) => _intradayVoidForUtcDay(source, day))(
          dayStart,
        ),
      );
      if (voidMoon != null &&
          (!voidMoon.endTime.isAfter(voidMoon.startTime) ||
              voidMoon.startTime.toUtc().isBefore(dayStart) ||
              voidMoon.endTime.toUtc().isAfter(
                dayStart.add(const Duration(days: 1)),
              ))) {
        throw StateError('時刻別点数のJSTボイド区間が不正です。');
      }
      final returns = source
          .returns(transit: point.placements, natal: request.natal)
          .map(
            (event) => engine._withReturnPhase(
              event,
              current: point.placements,
              next: next,
              natal: request.natal,
            ),
          )
          .toList();
      contextData = HoroscopeReadingContext(
        natal: noonContext.natal,
        transit: TransitChart(
          date: clock.instantUtc,
          placements: point.placements,
          voidMoon: voidMoon,
        ),
        nextTransitPlacements: next,
        aspects: point.fullNatalAspects.take(8).toList(),
        fullAspects: point.fullNatalAspects,
        nextAspects: source.aspects(transit: next, natal: request.natal),
        transitPairAspects: FortuneScoreCalculator.transitPairAspects(
          current: point.placements,
          next: next,
        ),
        retrogradePlanets: {
          for (final planet in AstroPlanet.values.skip(2).take(8))
            if (engine._isRetrograde(planet, point.placements, next)) planet,
          ...DailyAstroEventsCard.verifiedRetrogradesAt(clock.instantUtc),
        },
        houseTransits: source.houseTransits(point.placements),
        returns: returns,
        birthPlace: noonContext.birthPlace,
        ephemerisSourceName: source.sourceName,
        ephemerisPrecisionNotice: source.precisionNotice,
        usesHighPrecisionAstroData: source.usesHighPrecisionAstroData,
        houseSystem: request.resolvedHouseSystem,
        houseCusps: request.cusps,
        scoreDayStartUtc: dayStart,
      );
    }
    if (source.sourceName != request.sourceName ||
        source.usesHighPrecisionAstroData != request.requireHighPrecision) {
      throw StateError('時刻別点数の計算元が途中で変わりました。');
    }
    if (request.requireHighPrecision &&
        fallbackBefore != SwissEphemerisProvider._placementFallbackCount) {
      throw StateError('時刻別点数の計算が簡易計算へ戻りました。');
    }
    final snapshot = clock.isPrimaryNoon
        ? NineAreaDailyConsultSnapshot.build(
            date: clock.instantUtc,
            contextData: contextData,
          )
        : NineAreaDailyConsultSnapshot.buildAtInstant(
            instantUtc: clock.instantUtc,
            contextData: contextData,
          );
    final snapshotWithExplanation = <String, Object?>{
      ...snapshot,
      'presentation_explanation': _dailyPresentationExplanation(
        snapshot,
        supplement: details,
      ),
    };
    values.add({
      ...clock.toJson(),
      'nine_area_forecast': snapshotWithExplanation,
      'score_day_start_utc': dayStart.toIso8601String(),
      'score_day_end_utc': dayStart
          .add(const Duration(days: 1))
          .toIso8601String(),
      'calculation_origin': clock.isPrimaryNoon
          ? 'existing_noon_context'
          : 'sample_instant_context',
      'void_penalty_rule': 'reference_only_zero_score_adjustment',
      'void_interval_scope': 'existing_first_daily_interval_over_five_minutes',
      'void_moon_interval': contextData.transit.voidMoon == null
          ? null
          : {
              'start_utc': contextData.transit.voidMoon!.startTime
                  .toUtc()
                  .toIso8601String(),
              'end_utc': contextData.transit.voidMoon!.endTime
                  .toUtc()
                  .toIso8601String(),
            },
    });
    onProgress?.call(i + 1, 7);
  }
  return {
    'schema': 'pancyo_daily_intraday_forecasts_v1',
    'target_date_jst': request.plan.targetDateJst,
    'time_zone': 'Asia/Tokyo',
    'fixed_utc_offset': '+09:00',
    'model_version': NineAreaDailyForecast.modelVersion,
    'formula_policy': 'existing_nine_area_daily_formula_at_each_instant',
    'completeness': {
      'status': 'complete',
      'point_count': 7,
      'areas_per_point': 9,
    },
    'daily_primary_reference_count': 1,
    'daily_scores_averaged_from_samples': false,
    'felt_has_numeric_score': false,
    'exact_optimal_time_search_complete': false,
    'independent_astronomical_accuracy_verified': false,
    'points': values,
  };
}

Map<String, Object?> buildDailyConsultDataV4(
  DailyConsultExportRequest request, {
  void Function(int, int)? onProgress,
}) {
  final source = AstrologyDataSources.current;
  if ((request.contextData == null &&
          HouseSystemSettings.current.value != request.requestedHouseSystem) ||
      source.sourceName != request.sourceName ||
      source.usesHighPrecisionAstroData != request.requireHighPrecision) {
    throw StateError('日JSONの要求ハウス方式・計算元が一致しません。');
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
  final positions = calculateDailyIntradayPositions(
    request: timelineRequest,
    nextNoonPlacements: contextData.nextTransitPlacements,
  );
  final forecasts = calculateDailyIntradayForecasts(
    positions: positions,
    noonContext: contextData,
    details: request.details,
    onProgress: onProgress,
  );
  final legacy = DailyAstroDataExportCard(
    date: request.date,
    profile: request.profile,
    details: request.details,
    contextData: contextData,
  ).buildData(generatedAt: request.generatedAt);
  final primary = Map<String, Object?>.from(legacy['nine_area_daily'] as Map);
  return {
    ...legacy,
    'schema': 'pancyo_astrology_daily_consult_v4',
    'nine_area_daily': {
      ...primary,
      'presentation_explanation': _dailyPresentationExplanation(
        primary,
        supplement: request.details,
      ),
    },
    'intraday_positions': positions.toJson(),
    'intraday_forecasts': forecasts,
  };
}
