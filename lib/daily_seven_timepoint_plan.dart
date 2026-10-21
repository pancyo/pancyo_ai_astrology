/// Fixed-JST clock/calendar plan shared by the day timeline and offline tests.
/// This contains no positions, houses, events, scores, or hourly predictions.
class DailySevenTimepointPlan {
  DailySevenTimepointPlan._(this.targetDateJst, this.dayStartUtc)
    : dayEndUtc = dayStartUtc.add(const Duration(days: 1)),
      points = List.unmodifiable([
        for (final hour in sampleHours)
          DailySevenTimepoint._(hour, dayStartUtc.add(Duration(hours: hour))),
      ]);

  static const planId = 'daily-seven-timepoint-clock-experiment-20261002-1';
  static const artifactType =
      'pancyo_daily_seven_timepoint_schedule_experiment_v0';
  static const jstOffset = Duration(hours: 9);
  static const sampleHours = [0, 4, 8, 12, 16, 20, 24];

  /// Input is a Gregorian civil JST date, not a host-local DateTime.
  /// The experimental input grammar is exactly YYYY-MM-DD, years 0001..9999.
  /// This is not a decision about the application's supported birth dates.
  factory DailySevenTimepointPlan.forJstDate(String targetDateJst) {
    final match = RegExp(
      r'([0-9]{4})-([0-9]{2})-([0-9]{2})',
    ).matchAsPrefix(targetDateJst);
    if (match == null || match.end != targetDateJst.length) {
      throw FormatException('Expected an exact YYYY-MM-DD civil JST date.');
    }
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    if (year == 0 || month < 1 || month > 12 || day < 1 || day > 31) {
      throw FormatException('Invalid Gregorian civil JST date.');
    }
    // Dart normalizes impossible dates; compare all fields before accepting.
    final civilMidnight = DateTime.utc(year, month, day);
    if (civilMidnight.year != year ||
        civilMidnight.month != month ||
        civilMidnight.day != day) {
      throw FormatException('Invalid Gregorian civil JST date.');
    }
    return DailySevenTimepointPlan._(
      targetDateJst,
      civilMidnight.subtract(jstOffset),
    );
  }

  final String targetDateJst;
  final DateTime dayStartUtc, dayEndUtc;
  final List<DailySevenTimepoint> points;

  /// Only noon remains the existing daily prediction's reference instant.
  DailySevenTimepoint get primaryNoon => points[3];

  /// The day is half-open: [00:00 JST, next 00:00 JST).
  /// This selects instants, not a new daily-score aggregation rule.
  bool containsInstant(DateTime instant) {
    final utc = instant.toUtc();
    return !utc.isBefore(dayStartUtc) && utc.isBefore(dayEndUtc);
  }

  Map<String, Object?> toJson() => {
    'artifact_type': artifactType,
    'plan_id': planId,
    'active_runtime_model': false,
    'contains_astronomical_positions': false,
    'contains_events': false,
    'contains_predictions': false,
    'target_date_jst': targetDateJst,
    'time_zone': 'Asia/Tokyo',
    'fixed_utc_offset': '+09:00',
    'day_interval': {
      'start_utc': dayStartUtc.toIso8601String(),
      'end_utc': dayEndUtc.toIso8601String(),
      'start_inclusive': true,
      'end_inclusive': false,
    },
    'display_point_count': points.length,
    'daily_primary_reference_count': 1,
    'primary_reference_utc': primaryNoon.instantUtc.toIso8601String(),
    'boundary_note':
        '24:00 is the next civil day at 00:00; exclude it from this day\'s '
        'interval counts. UTC identity alone does not identify a subject, '
        'location, house configuration, or prediction model.',
    'points': [for (final point in points) point.toJson()],
  };
}

class DailySevenTimepoint {
  const DailySevenTimepoint._(this.hourFromDayStart, this.instantUtc);

  final int hourFromDayStart;
  final DateTime instantUtc;
  bool get isDayEndBoundary => hourFromDayStart == 24;
  bool get isPrimaryNoon => hourFromDayStart == 12;
  bool get isInsideDayInterval => !isDayEndBoundary;
  String get displayTime => hourFromDayStart.toString().padLeft(2, '0') + ':00';

  /// Canonical identity for this clock instant only; NOT a forecast/cache key.
  String get clockInstantId => instantUtc.toIso8601String();

  /// A machine-readable real civil date/time; never target-date T24:00.
  /// Retains Dart's extended year at the 9999-12-31 end boundary.
  String get instantJst => instantUtc
      .add(DailySevenTimepointPlan.jstOffset)
      .toIso8601String()
      .replaceFirst(RegExp(r'Z$'), '+09:00');

  Map<String, Object?> toJson() => {
    'hour_from_day_start': hourFromDayStart,
    'display_time': displayTime,
    'instant_utc': instantUtc.toIso8601String(),
    'instant_jst': instantJst,
    'clock_instant_id': clockInstantId,
    'role': isDayEndBoundary ? 'day_end_boundary' : 'day_sample',
    'inside_day_interval': isInsideDayInterval,
    'is_existing_daily_primary_reference': isPrimaryNoon,
  };
}
