part of 'main.dart';

/// Optional, invocation-local work counts. Never retains dates or event data.
class AstroEventWorkCounts {
  int _stationCalls = 0;
  int _lunarPhaseCalls = 0;

  Map<String, int> get safeSnapshot => Map.unmodifiable({
    'station_calls': _stationCalls,
    'lunar_phase_calls': _lunarPhaseCalls,
  });
}

/// Used only while one period snapshot is constructed. No global cache.
class _PeriodEventLunarCapture {
  DateTime? reference;
  Map<String, Object?>? snapshot;

  bool matches(DateTime candidate) =>
      reference != null &&
      reference == candidate &&
      reference!.isUtc == candidate.isUtc;
}

/// Reuses only identical searches within one period JSON event snapshot.
/// The false switch preserves the old path for independent regression checks.
class PeriodAstroEventSnapshot {
  const PeriodAstroEventSnapshot._();

  static Map<String, Object?> build({
    required DateTime reference,
    required HoroscopeReadingContext contextData,
    EphemerisProvider? ephemeris,
    bool reuseIdenticalSearches = true,
    AstroEventWorkCounts? workCounts,
  }) {
    final provider = ephemeris ?? AstrologyDataSources.current;
    final start = DateTime(reference.year, reference.month, reference.day);
    final end = start.add(const Duration(days: 1));
    final card = DailyAstroEventsCard(
      date: reference,
      contextData: contextData,
    );
    final stationEvents = card._stationEvents(
      start,
      end,
      provider,
      workCounts: workCounts,
    );
    final capture = reuseIdenticalSearches ? _PeriodEventLunarCapture() : null;
    final dailyEvents = card._dailyEvents(
      start,
      end,
      provider,
      workCounts: workCounts,
      stationEvents: reuseIdenticalSearches ? stationEvents : null,
      lunarCapture: capture,
    );
    // Preserve the old reference time, including UTC/local representation.
    // A date-only key or silently replacing a non-noon time would be unsafe.
    final lunarPhase = capture?.matches(reference) == true
        ? capture!.snapshot!
        : card._lunarPhaseSnapshot(reference, provider, workCounts: workCounts);
    return {
      'station_events_jst': stationEvents,
      'daily_events_jst': dailyEvents,
      'lunar_phase': lunarPhase,
    };
  }
}
