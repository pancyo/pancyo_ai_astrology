import 'daily_seven_timepoint_plan.dart';

/// Independent search foundation. Not wired to scores, UI or consult exports.
/// A callback must be continuous, with strictly increasing Moon longitude and
/// Moon-minus-body phase, and less than 180 degrees travel in each scan step.
/// Endpoint validation cannot prove those assumptions between evaluations.
typedef LunarLongitudeReader = LunarLongitudeSample Function(DateTime utc);

class LunarLongitudeSample {
  LunarLongitudeSample({
    required Map<String, double> longitudes,
    required Map<String, String> sources,
  }) : longitudes = Map.unmodifiable(longitudes),
       sources = Map.unmodifiable(sources) {
    for (final body in bodies) {
      final value = this.longitudes[body];
      final source = this.sources[body];
      if (value == null ||
          !value.isFinite ||
          value < 0 ||
          value >= 360 ||
          source == null ||
          source.trim().isEmpty) {
        throw ArgumentError('Missing/invalid longitude or source for $body');
      }
    }
    if (this.longitudes.length != bodies.length ||
        this.sources.length != bodies.length) {
      throw ArgumentError('Exactly the ten physical bodies are required');
    }
  }
  static const bodies = [
    'sun',
    'moon',
    'mercury',
    'venus',
    'mars',
    'jupiter',
    'saturn',
    'uranus',
    'neptune',
    'pluto',
  ];
  final Map<String, double> longitudes;

  /// Caller declarations, not independent native backend verification.
  final Map<String, String> sources;
}

class LunarRootEvent {
  const LunarRootEvent({
    required this.kind,
    required this.timeUtc,
    required this.lowerUtc,
    required this.upperUtc,
    required this.targetDegrees,
    required this.residualDegrees,
    this.otherBody,
  });
  final String kind;
  final DateTime timeUtc, lowerUtc, upperUtc;
  final double targetDegrees, residualDegrees;
  final String? otherBody;
  Map<String, Object?> toJson() => {
    'kind': kind,
    'body': 'moon',
    'other_body': otherBody,
    'target_degrees': targetDegrees,
    'time_utc': timeUtc.toIso8601String(),
    'time_jst': _jst(timeUtc),
    'bracket_lower_utc': lowerUtc.toIso8601String(),
    'bracket_upper_utc': upperUtc.toIso8601String(),
    'bracket_width_microseconds': upperUtc.difference(lowerUtc).inMicroseconds,
    'angular_residual_degrees': residualDegrees,
    'timestamp_precision_is_not_astronomical_accuracy': true,
  };
}

class LunarVoidInterval {
  const LunarVoidInterval({
    required this.segmentStart,
    required this.segmentEnd,
    required this.startUtc,
    required this.endUtc,
    required this.overlapStartUtc,
    required this.overlapEndUtc,
    required this.lastAspect,
  });
  final LunarRootEvent segmentStart, segmentEnd;
  final DateTime startUtc, endUtc, overlapStartUtc, overlapEndUtc;
  final LunarRootEvent? lastAspect;
  bool contains(DateTime instant) =>
      !instant.toUtc().isBefore(startUtc) && instant.toUtc().isBefore(endUtc);
  Map<String, Object?> toJson() => {
    'start_utc': startUtc.toIso8601String(),
    'end_utc': endUtc.toIso8601String(),
    'start_jst': _jst(startUtc),
    'end_jst': _jst(endUtc),
    'overlap_start_utc': overlapStartUtc.toIso8601String(),
    'overlap_end_utc': overlapEndUtc.toIso8601String(),
    'overlap_start_jst': _jst(overlapStartUtc),
    'overlap_end_jst': _jst(overlapEndUtc),
    'start_inclusive': true,
    'end_inclusive': false,
    'moon_sign_entry': segmentStart.toJson(),
    'moon_sign_exit': segmentEnd.toJson(),
    'last_major_aspect': lastAspect?.toJson(),
    'start_reason': lastAspect == null
        ? 'no_major_aspect_in_sign'
        : 'last_major_aspect',
  };
}

class DailyLunarEventSearchResult {
  DailyLunarEventSearchResult._(
    this.plan,
    List<LunarRootEvent> events,
    List<LunarVoidInterval> intervals,
    this.scanStep,
    this.timeTolerance,
    Map<String, Set<String>> sources,
    this.evaluationCount,
  ) : events = List.unmodifiable(events),
      voidIntervals = List.unmodifiable(intervals),
      sources = Map.unmodifiable({
        for (final e in sources.entries)
          e.key: Set<String>.unmodifiable(e.value),
      });
  final DailySevenTimepointPlan plan;

  /// Includes surrounding sign-boundary witnesses needed for the target day.
  final List<LunarRootEvent> events;
  final List<LunarVoidInterval> voidIntervals;
  final Duration scanStep, timeTolerance;
  final Map<String, Set<String>> sources;
  final int evaluationCount;
  Map<String, Object?> toJson() => {
    'artifact_type': 'pancyo_daily_lunar_event_search_experiment_v1',
    'active_runtime_model': false,
    'target_date_jst': plan.targetDateJst,
    'time_zone': 'Asia/Tokyo',
    'day_start_utc': plan.dayStartUtc.toIso8601String(),
    'day_end_utc': plan.dayEndUtc.toIso8601String(),
    'day_end_inclusive': false,
    'coverage': 'lunar_intervals_under_continuous_monotonic_step_assumption',
    'all_events_and_exact_aspect_peaks_complete': false,
    'independent_astronomical_accuracy_verified': false,
    'source_verification': 'caller_declared_not_independently_verified',
    'scan_step_microseconds': scanStep.inMicroseconds,
    'root_time_tolerance_microseconds': timeTolerance.inMicroseconds,
    'ordering_resolution_microseconds': 1,
    'unresolved_boundary_order': 'reject_result_instead_of_guessing',
    'simultaneous_sign_boundary_contact': 'belongs_to_entered_sign',
    'longitude_evaluation_count': evaluationCount,
    'sources_by_body': {
      for (final e in sources.entries) e.key: e.value.toList(),
    },
    'void_definition':
        'last_major_aspect_to_nine_other_physical_bodies_before_sign_exit',
    'void_intervals': [for (final v in voidIntervals) v.toJson()],
    'events_inside_day': [
      for (final e in events)
        if (plan.containsInstant(e.timeUtc)) e.toJson(),
    ],
    'surrounding_events': [for (final e in events) e.toJson()],
  };
}

/// Solves roots from fresh longitude evaluations, never from the seven display
/// samples. Whole sign segments are searched to find the last aspect before exit.
DailyLunarEventSearchResult searchDailyLunarEvents({
  required DailySevenTimepointPlan plan,
  required LunarLongitudeReader readLongitudes,
  Duration scanStep = const Duration(minutes: 5),
  Duration timeTolerance = const Duration(seconds: 1),
  bool Function()? isCancelled,
  String? requiredSource,
}) {
  if (scanStep.inMicroseconds <= 0 ||
      scanStep > const Duration(minutes: 5) ||
      timeTolerance.inMicroseconds <= 0 ||
      timeTolerance > const Duration(seconds: 1) ||
      timeTolerance >= scanStep) {
    throw ArgumentError('Invalid search step or root tolerance');
  }
  final cache = <DateTime, LunarLongitudeSample>{};
  final sources = {for (final b in LunarLongitudeSample.bodies) b: <String>{}};
  LunarLongitudeSample sample(DateTime at) {
    if (isCancelled?.call() ?? false)
      throw StateError('Lunar search cancelled');
    return cache.putIfAbsent(at, () {
      final value = readLongitudes(at);
      for (final b in LunarLongitudeSample.bodies) {
        final source = value.sources[b]!;
        if (requiredSource != null && source != requiredSource) {
          throw StateError('Unexpected calculation source for $b');
        }
        if (sources[b]!.isNotEmpty && !sources[b]!.contains(source)) {
          throw StateError('Calculation source changed during search for $b');
        }
        sources[b]!.add(source);
      }
      return value;
    });
  }

  double phase(DateTime at, String? other) {
    final v = sample(at).longitudes;
    return _norm(v['moon']! - (other == null ? 0 : v[other]!));
  }

  double forward(double left, double right) {
    final delta = _signed(right - left);
    if (delta <= 0 || delta >= 180) {
      throw StateError('Non-increasing or ambiguous lunar phase step');
    }
    return delta;
  }

  LunarRootEvent root(
    DateTime left,
    DateTime right,
    double startPhase,
    double distance,
    double target,
    String? other,
  ) {
    var lo = left, hi = right;
    if (distance == 0) hi = lo;
    if (distance != 0 && _signed(phase(right, other) - target) == 0) {
      lo = hi;
    }
    // Refine to the DateTime lattice as well as the requested maximum width.
    // This avoids moving a contact just before midnight into the next day.
    var lowerMovement = 0.0;
    var upperMovement = _signed(phase(right, other) - startPhase);
    while (hi.difference(lo).inMicroseconds > 1) {
      final mid = lo.add(
        Duration(microseconds: hi.difference(lo).inMicroseconds ~/ 2),
      );
      final movement = _signed(phase(mid, other) - startPhase);
      if (movement < lowerMovement ||
          movement > upperMovement ||
          movement < 0 ||
          movement >= 180) {
        throw StateError('Invalid lunar phase during root refinement');
      }
      if (movement == distance) {
        lo = mid;
        hi = mid;
      } else if (movement < distance) {
        lo = mid;
        lowerMovement = movement;
      } else {
        hi = mid;
        upperMovement = movement;
      }
    }
    final estimate = lo.add(
      Duration(microseconds: hi.difference(lo).inMicroseconds ~/ 2),
    );
    final residual = _signed(phase(estimate, other) - target).abs();
    if (residual > 0.000001) {
      throw StateError(
        'Longitude callback does not resolve an exact lunar root',
      );
    }
    return LunarRootEvent(
      kind: other == null ? 'moon_sign_ingress' : 'moon_major_aspect',
      timeUtc: estimate,
      lowerUtc: lo,
      upperUtc: hi,
      targetDegrees: target,
      residualDegrees: residual,
      otherBody: other,
    );
  }

  final scanStart = plan.dayStartUtc.subtract(const Duration(days: 4));
  final scanEnd = plan.dayEndUtc.add(const Duration(days: 4));
  final entries = <LunarRootEvent>[];
  const targets = [0.0, 60.0, 90.0, 120.0, 180.0, 240.0, 270.0, 300.0];
  final contacts = <LunarRootEvent>[];
  void scan(DateTime start, DateTime end, {required bool signs}) {
    var left = start;
    while (left.isBefore(end)) {
      var right = left.add(scanStep);
      if (right.isAfter(end)) right = end;
      final others = signs
          ? <String?>[null]
          : LunarLongitudeSample.bodies
                .where((b) => b != 'moon')
                .cast<String?>();
      for (final other in others) {
        final p0 = phase(left, other), p1 = phase(right, other);
        final delta = forward(p0, p1);
        final angles = signs
            ? [for (var n = 0; n < 12; n++) n * 30.0]
            : targets;
        for (final target in angles) {
          final distance = _norm(target - p0);
          if (distance <= delta) {
            final value = root(left, right, p0, distance, target, other);
            if (!value.timeUtc.isBefore(end)) continue;
            final output = signs ? entries : contacts;
            if (!output.any(
              (e) =>
                  e.otherBody == other &&
                  e.targetDegrees == target &&
                  e.timeUtc == value.timeUtc,
            )) {
              output.add(value);
            }
          }
        }
      }
      left = right;
    }
  }

  scan(scanStart, scanEnd, signs: true);
  entries.sort((a, b) => a.timeUtc.compareTo(b.timeUtc));
  final previous = entries
      .where((e) => !e.timeUtc.isAfter(plan.dayStartUtc))
      .toList();
  final following = entries
      .where((e) => !e.timeUtc.isBefore(plan.dayEndUtc))
      .toList();
  if (previous.isEmpty || following.isEmpty) {
    throw StateError('Moon sign boundaries not found within bounded search');
  }
  final segments = entries
      .where(
        (e) =>
            !e.timeUtc.isBefore(previous.last.timeUtc) &&
            !e.timeUtc.isAfter(following.first.timeUtc),
      )
      .toList();
  scan(segments.first.timeUtc, segments.last.timeUtc, signs: false);
  contacts.sort((a, b) => a.timeUtc.compareTo(b.timeUtc));
  for (final c in contacts) {
    for (final s in segments) {
      if (!c.upperUtc.isBefore(s.lowerUtc) &&
          !c.lowerUtc.isAfter(s.upperUtc) &&
          !(c.lowerUtc == c.upperUtc && s.lowerUtc == s.upperUtc)) {
        throw StateError('Lunar contact order unresolved at sign boundary');
      }
    }
  }
  final intervals = <LunarVoidInterval>[];
  for (var i = 0; i < segments.length - 1; i++) {
    final entry = segments[i], exit = segments[i + 1];
    final found = contacts
        .where(
          (e) =>
              !e.timeUtc.isBefore(entry.timeUtc) &&
              e.timeUtc.isBefore(exit.timeUtc),
        )
        .toList();
    final last = found.isEmpty ? null : found.last;
    final rawStart = last?.timeUtc ?? entry.timeUtc;
    final overlapStart = rawStart.isBefore(plan.dayStartUtc)
        ? plan.dayStartUtc
        : rawStart;
    final overlapEnd = exit.timeUtc.isAfter(plan.dayEndUtc)
        ? plan.dayEndUtc
        : exit.timeUtc;
    if (overlapEnd.isAfter(overlapStart)) {
      intervals.add(
        LunarVoidInterval(
          segmentStart: entry,
          segmentEnd: exit,
          startUtc: rawStart,
          endUtc: exit.timeUtc,
          overlapStartUtc: overlapStart,
          overlapEndUtc: overlapEnd,
          lastAspect: last,
        ),
      );
    }
  }
  final events = [...segments, ...contacts]
    ..sort((a, b) => a.timeUtc.compareTo(b.timeUtc));
  return DailyLunarEventSearchResult._(
    plan,
    events,
    intervals,
    scanStep,
    timeTolerance,
    sources,
    cache.length,
  );
}

double _norm(double value) => (value % 360 + 360) % 360;
double _signed(double value) => _norm(value + 180) - 180;
String _jst(DateTime utc) => utc
    .add(DailySevenTimepointPlan.jstOffset)
    .toIso8601String()
    .replaceFirst(RegExp(r'Z$'), '+09:00');
