import 'daily_lunar_event_search.dart';
import 'daily_quantized_lunar_events.dart';
import 'daily_seven_timepoint_plan.dart';
import 'lunar_unwrapped_tracks.dart';

class DailyLunarAcquisitionAttempt {
  DailyLunarAcquisitionAttempt(this.startUtc, this.endUtc, this.outcome,
      this.physicalInvocationCount, this.acceptedSampleCount);
  final DateTime startUtc, endUtc;
  final String outcome;
  final int physicalInvocationCount, acceptedSampleCount;
  Map<String, Object?> toJson() => {
    'start_utc': startUtc.toIso8601String(), 'end_utc': endUtc.toIso8601String(),
    'outcome': outcome, 'cumulative_physical_invocations': physicalInvocationCount,
    'cumulative_accepted_samples': acceptedSampleCount,
  };
}

class BoundedDailyLunarResult {
  BoundedDailyLunarResult._(this.daily, List<DailyLunarAcquisitionAttempt> attempts,
      this.physicalInvocationCount, this.acceptedSampleCount, this.maximumPadding,
      this.maximumAttempts, this.maximumPhysicalEvaluations, this.maximumScanEvaluations)
      : attempts = List.unmodifiable(attempts);
  final DailyQuantizedLunarResult daily;
  final List<DailyLunarAcquisitionAttempt> attempts;
  final int physicalInvocationCount, acceptedSampleCount;
  final Duration maximumPadding;
  final int maximumAttempts, maximumPhysicalEvaluations, maximumScanEvaluations;
  Map<String, Object?> toJson() => {
    'artifact_type': 'pancyo_bounded_daily_lunar_acquisition_experiment_v1',
    'active_runtime_model': false,
    'independent_astronomical_accuracy_verified': false,
    'bounds_and_interread_monotonicity_verification': 'caller_assumptions',
    'maximum_padding_microseconds': maximumPadding.inMicroseconds,
    'maximum_attempts': maximumAttempts,
    'maximum_physical_evaluations': maximumPhysicalEvaluations,
    'maximum_scan_evaluations': maximumScanEvaluations,
    'physical_invocation_count': physicalInvocationCount,
    'accepted_sample_count': acceptedSampleCount,
    'last_attempt_referenced_samples': daily.physicalEvaluationCount,
    'attempts': [for (final attempt in attempts) attempt.toJson()],
    'daily': daily.toJson(),
  };
}

/// An unsuccessful operation retains bounded acquisition evidence, never a
/// partial daily result. The original terminal failure is available locally.
class BoundedDailyLunarAcquisitionFailure extends StateError {
  BoundedDailyLunarAcquisitionFailure(this.code, this.cause,
      List<DailyLunarAcquisitionAttempt> attempts, this.physicalInvocationCount,
      this.acceptedSampleCount) : attempts = List.unmodifiable(attempts), super(code);
  final String code;
  final Object? cause;
  final List<DailyLunarAcquisitionAttempt> attempts;
  final int physicalInvocationCount, acceptedSampleCount;
}

class _AcquisitionCancelled extends StateError {
  _AcquisitionCancelled() : super('acquisition_cancelled');
}
class _PhysicalBudgetExhausted extends StateError {
  _PhysicalBudgetExhausted() : super('physical_budget_exhausted');
}
class _RawReaderFailure implements Exception {
  _RawReaderFailure(this.cause);
  final Object cause;
}

/// Expands both exterior margins only for typed coverage gaps, under explicit
/// UTC/read/attempt limits. No native, score, UI or formal daily JSON connection.
/// A completed result with ambiguous void boundaries is returned as ambiguous;
/// widening is not an excuse to turn it into a claimed exact event.
BoundedDailyLunarResult acquireBoundedDailyLunarEvents({
  required DailySevenTimepointPlan plan,
  required TimedLunarReader read,
  required Duration initialPadding,
  required Duration paddingIncrement,
  required Duration maximumPadding,
  required Duration scanStep,
  required Duration maximumInputTimeRadius,
  required double maximumStepTravelDegrees,
  int maximumAttempts = 16,
  int maximumPhysicalEvaluations = 10000,
  int maximumScanEvaluations = 10000,
  bool Function()? isCancelled,
}) {
  if (initialPadding.isNegative || maximumPadding < initialPadding ||
      paddingIncrement.inMicroseconds < 1 || scanStep.inMicroseconds < 1 ||
      maximumInputTimeRadius.inMicroseconds < 1 || maximumAttempts < 1 ||
      maximumPhysicalEvaluations < 2 || maximumScanEvaluations < 2 ||
      !maximumStepTravelDegrees.isFinite || maximumStepTravelDegrees <= 0 ||
      maximumStepTravelDegrees >= 180) {
    throw ArgumentError('Invalid bounded acquisition contract');
  }
  // Reject unsupported UTC arithmetic before any physical acquisition occurs.
  try {
    plan.dayStartUtc.subtract(maximumPadding).add(maximumInputTimeRadius);
    plan.dayEndUtc.add(maximumPadding).subtract(maximumInputTimeRadius);
  } catch (_) {
    throw ArgumentError('Unsupported bounded UTC endpoints');
  }
  final cache = <DateTime, TimedLunarLongitudes>{};
  final attempts = <DailyLunarAcquisitionAttempt>[];
  var invocations = 0;
  String? source;
  void checkCancelled() {
    late final bool cancelled;
    try { cancelled = isCancelled?.call() == true; }
    catch (error) { throw _RawReaderFailure(error); }
    if (cancelled) throw _AcquisitionCancelled();
  }
  TimedLunarLongitudes sharedRead(DateTime utc) {
    checkCancelled(); // Also before an existing cache hit.
    final old = cache[utc];
    if (old != null) return old;
    if (invocations >= maximumPhysicalEvaluations) throw _PhysicalBudgetExhausted();
    invocations++; // Failed invocations consume budget too.
    late final TimedLunarLongitudes value;
    try {
      value = read(utc);
    } catch (error) {
      // A provider throwing a coverage exception is still a terminal read failure.
      throw _RawReaderFailure(error);
    }
    if (!value.utc.isUtc || value.utc != utc || !value.coordinate.isFinite ||
        value.source.trim().isEmpty || value.inputTimeRadius.inMicroseconds < 1 ||
        value.inputTimeRadius > maximumInputTimeRadius ||
        value.longitudes.length != LunarLongitudeSample.bodies.length ||
        LunarLongitudeSample.bodies.any((body) {
          final longitude = value.longitudes[body];
          return longitude == null || !longitude.isFinite || longitude < 0 || longitude >= 360;
        })) throw StateError('invalid_shared_physical_sample');
    if (source != null && source != value.source) throw StateError('shared_source_changed');
    // Retain consistency with every sample from every previous attempt,
    // including refinements that a newly prepared track would not reference.
    for (final previous in cache.values) {
      final earlier = previous.utc.isBefore(utc) ? previous : value;
      final later = previous.utc.isBefore(utc) ? value : previous;
      if (earlier.coordinate > later.coordinate) throw StateError('shared_coordinate_reversed');
      if (earlier.coordinate == later.coordinate && LunarLongitudeSample.bodies.any(
          (body) => earlier.longitudes[body] != later.longitudes[body])) {
        throw StateError('shared_coordinate_longitudes_changed');
      }
    }
    source = value.source;
    cache[utc] = value;
    return value;
  }
  BoundedDailyLunarAcquisitionFailure fail(String code, Object? cause) =>
    BoundedDailyLunarAcquisitionFailure(code, cause, attempts, invocations, cache.length);
  var padding = initialPadding;
  for (var attempt = 1; attempt <= maximumAttempts; attempt++) {
    final start = plan.dayStartUtc.subtract(padding);
    final end = plan.dayEndUtc.add(padding);
    DailyLunarCoverageException? gap;
    try {
      checkCancelled();
      final tracks = prepareLunarUnwrappedTracks(read: sharedRead,
        startUtc: start, endUtc: end, scanStep: scanStep,
        maximumInputTimeRadius: maximumInputTimeRadius,
        maximumStepTravelDegrees: maximumStepTravelDegrees,
        maximumEvaluations: maximumPhysicalEvaluations + 1);
      // A shifted coarse grid must also agree with retained refinement samples.
      for (final body in LunarLongitudeSample.bodies) {
        final validate = tracks.reader(otherBody: body == 'moon' ? null : body);
        for (final utc in cache.keys.toList()) { validate(utc); }
      }
      final daily = buildDailyQuantizedLunarEvents(plan: plan, tracks: tracks,
        scanStep: scanStep, maximumScanEvaluations: maximumScanEvaluations,
        isCancelled: () { checkCancelled(); return false; });
      checkCancelled(); // No successful return after cancellation was observed.
      attempts.add(DailyLunarAcquisitionAttempt(start, end, 'complete_under_assumptions',
        invocations, cache.length));
      return BoundedDailyLunarResult._(daily, attempts, invocations, cache.length,
        maximumPadding, maximumAttempts, maximumPhysicalEvaluations, maximumScanEvaluations);
    } on DailyLunarCoverageException catch (error) {
      gap = error;
      attempts.add(DailyLunarAcquisitionAttempt(start, end, error.gap.name,
        invocations, cache.length));
    } catch (error) {
      final code = error is _AcquisitionCancelled ? 'cancelled' :
        error is _PhysicalBudgetExhausted ? 'physical_budget_exhausted' : 'terminal_failure';
      attempts.add(DailyLunarAcquisitionAttempt(start, end, code, invocations, cache.length));
      throw fail(code, error is _RawReaderFailure ? error.cause : error);
    }
    if (attempt == maximumAttempts) throw fail('attempt_limit_exhausted', gap);
    if (padding == maximumPadding) throw fail('padding_limit_exhausted', gap);
    final remaining = maximumPadding - padding;
    padding += remaining < paddingIncrement ? remaining : paddingIncrement;
  }
  throw StateError('unreachable_bounded_acquisition');
}
