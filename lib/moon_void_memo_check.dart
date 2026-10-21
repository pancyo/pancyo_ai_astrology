part of 'main.dart';

/// Opt-in, artificial native regression check. No preferences, files or sharing.
/// Called only by the explicitly enabled local rework entrypoint in an isolate.
class MoonVoidMemoCheck {
  const MoonVoidMemoCheck._();

  static Map<String, Object?> run() {
    if (!reworkTestBuild || !SwissEphemerisProvider.isAvailable) {
      throw StateError('人工実機比較は改修指定とネイティブ計算が必要です。');
    }
    const provider = SwissEphemerisProvider();
    const profile = AstroProfile(
      name: 'ReworkVoidFixture',
      birthDate: '1990/1/2',
      birthTime: '08:30',
      birthPlace: '東京都',
      theme: '今日の流れ',
    );
    final dates = [
      for (var offset = 0; offset < 28; offset++)
        DateTime(2026, 9, 7 + offset, 12),
      DateTime(2026, 10, 8, 12),
      DateTime(2026, 10, 15, 12),
      DateTime(2026, 10, 22, 12),
      DateTime(2026, 10, 31, 12),
      DateTime(2027, 1, 1, 12),
      DateTime(2028, 2, 28, 12),
      DateTime(2028, 2, 29, 12),
      DateTime(2028, 3, 1, 12),
    ];
    final originalHouse = HouseSystemSettings.current.value;
    SwissEphemerisProvider._voidMoonCache.clear();
    SwissEphemerisProvider._voidSegmentMemo.clear();
    final fallbacksBefore = SwissEphemerisProvider._placementFallbackCount;
    try {
      final oldWatch = Stopwatch()..start();
      final previous = [for (final date in dates) _legacyVoid(provider, date)];
      oldWatch.stop();
      final memoWatch = Stopwatch()..start();
      final current = [for (final date in dates) provider.voidMoonFor(date)];
      memoWatch.stop();
      var noVoidDays = 0;
      var completeJsonChecks = 0;
      for (var index = 0; index < dates.length; index++) {
        if (jsonEncode(_voidData(previous[index])) !=
            jsonEncode(_voidData(current[index]))) {
          throw StateError('旧探索と日ボイドの完全一致に失敗（人工検査番号$index）');
        }
        if (current[index] == null) noVoidDays++;
        for (final house in HouseSystem.values) {
          HouseSystemSettings.current.value = house;
          final context = const AstrologyEngine().buildPreviewContext(
            profile: profile,
            date: dates[index],
          );
          if (!context.usesHighPrecisionAstroData) {
            throw StateError('人工JSON比較が近似計算へ切り替わった');
          }
          Map<String, dynamic> export(HoroscopeReadingContext value) =>
              DailyAstroDataExportCard(
                date: dates[index],
                profile: profile,
                details: const UserProfileDetails.empty(),
                contextData: value,
              ).buildData(generatedAt: DateTime.utc(2026, 10, 1, 3));
          if (jsonEncode(export(context)) !=
              jsonEncode(export(_withVoid(context, previous[index])))) {
            throw StateError('旧ボイドを使った全日JSON・点数・根拠が不一致');
          }
          completeJsonChecks++;
        }
      }
      if (SwissEphemerisProvider._placementFallbackCount != fallbacksBefore) {
        throw StateError('人工比較中に配置の近似代用が発生した');
      }
      return {
        'passed': true,
        'day_count': dates.length,
        'no_void_day_count': noVoidDays,
        'full_daily_json_checks': completeJsonChecks,
        'house_system_count': HouseSystem.values.length,
        'legacy_void_us': oldWatch.elapsedMicroseconds,
        'memo_void_us': memoWatch.elapsedMicroseconds,
        'segment_hits': SwissEphemerisProvider._voidSegmentMemo.hits,
        'segment_misses': SwissEphemerisProvider._voidSegmentMemo.misses,
        'retained_segments': SwissEphemerisProvider._voidSegmentMemo.length,
        'placement_fallbacks': 0,
      };
    } finally {
      HouseSystemSettings.current.value = originalHouse;
      SwissEphemerisProvider._voidMoonCache.clear();
      SwissEphemerisProvider._voidSegmentMemo.clear();
    }
  }

  static Map<String, Object?>? _voidData(VoidMoonPeriod? value) => value == null
      ? null
      : {
          'start': value.start,
          'end': value.end,
          'start_time': value.startTime?.toIso8601String(),
          'end_time': value.endTime?.toIso8601String(),
          'start_us': value.startTime?.microsecondsSinceEpoch,
          'end_us': value.endTime?.microsecondsSinceEpoch,
          'start_utc': value.startTime?.isUtc,
          'end_utc': value.endTime?.isUtc,
          'guidance': value.guidance,
        };

  static HoroscopeReadingContext _withVoid(
    HoroscopeReadingContext context,
    VoidMoonPeriod? previous,
  ) => HoroscopeReadingContext(
    natal: context.natal,
    transit: TransitChart(
      date: context.transit.date,
      placements: context.transit.placements,
      voidMoon: previous,
    ),
    nextTransitPlacements: context.nextTransitPlacements,
    aspects: context.aspects,
    fullAspects: context.fullAspects,
    nextAspects: context.nextAspects,
    transitPairAspects: context.transitPairAspects,
    retrogradePlanets: context.retrogradePlanets,
    houseTransits: context.houseTransits,
    returns: context.returns,
    birthPlace: context.birthPlace,
    ephemerisSourceName: context.ephemerisSourceName,
    ephemerisPrecisionNotice: context.ephemerisPrecisionNotice,
    usesHighPrecisionAstroData: context.usesHighPrecisionAstroData,
    houseSystem: context.houseSystem,
    houseCusps: context.houseCusps,
  );

  // Frozen pre-memo day/search/refinement algorithms from 2026-10-01.
  // The unchanged sign-boundary and error functions still use the same native
  // provider. This path deliberately never calls the new memoized search.
  static VoidMoonPeriod? _legacyVoid(
    SwissEphemerisProvider provider,
    DateTime date,
  ) {
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    var segmentStart = provider._moonSignSegmentStart(dayStart);
    while (segmentStart.isBefore(dayEnd)) {
      final segmentEnd = provider._moonSignSegmentEnd(segmentStart);
      final lastAspect = _legacyLast(provider, segmentStart, segmentEnd);
      final voidStart = lastAspect ?? segmentStart;
      final overlapStart = voidStart.isBefore(dayStart) ? dayStart : voidStart;
      final overlapEnd = segmentEnd.isAfter(dayEnd) ? dayEnd : segmentEnd;
      if (overlapEnd.isAfter(overlapStart.add(const Duration(minutes: 5)))) {
        return VoidMoonPeriod(
          start: SwissEphemerisProvider._fallback._timeLabel(overlapStart),
          end: SwissEphemerisProvider._fallback._timeLabel(overlapEnd),
          startTime: overlapStart,
          endTime: overlapEnd,
          guidance: '月が次の星座へ入る前の空白時間。新規決定より見直し、休息、準備向き。',
        );
      }
      segmentStart = segmentEnd.add(const Duration(minutes: 1));
    }
    return null;
  }

  static DateTime? _legacyLast(
    SwissEphemerisProvider provider,
    DateTime start,
    DateTime end,
  ) {
    DateTime? last;
    var previousTime = start;
    var previousError = provider._moonMajorAspectErrorScalar(previousTime);
    var currentTime = start.add(const Duration(minutes: 5));
    var currentError = provider._moonMajorAspectErrorScalar(currentTime);
    while (currentTime.isBefore(end)) {
      final nextTime = currentTime.add(const Duration(minutes: 5));
      final boundedNext = nextTime.isAfter(end) ? end : nextTime;
      final nextError = provider._moonMajorAspectErrorScalar(boundedNext);
      if (currentError <= previousError &&
          currentError <= nextError &&
          currentError <= 0.12) {
        final exact = _legacyRefine(provider, previousTime, boundedNext);
        if (provider._moonMajorAspectErrorScalar(exact) <= 0.01) last = exact;
      }
      previousTime = currentTime;
      previousError = currentError;
      currentTime = boundedNext;
      currentError = nextError;
    }
    return last;
  }

  static DateTime _legacyRefine(
    SwissEphemerisProvider provider,
    DateTime start,
    DateTime end,
  ) {
    var left = start;
    var right = end;
    for (var i = 0; i < 18; i++) {
      final span = right.difference(left).inMicroseconds;
      final first = left.add(Duration(microseconds: span ~/ 3));
      final second = left.add(Duration(microseconds: span * 2 ~/ 3));
      if (provider._moonMajorAspectErrorScalar(first) <=
          provider._moonMajorAspectErrorScalar(second)) {
        right = second;
      } else {
        left = first;
      }
    }
    return left.add(
      Duration(microseconds: right.difference(left).inMicroseconds ~/ 2),
    );
  }
}
