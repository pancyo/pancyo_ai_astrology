import 'daily_lunar_event_search.dart';
import 'daily_seven_timepoint_plan.dart';
import 'lunar_event_uncertainty.dart';
import 'lunar_unwrapped_tracks.dart';
import 'quantized_event_scan.dart';

enum DailyLunarCoverageGap {
  missingExteriorTimeWitnesses,
  scanEndpointEventUnresolved,
  missingSurroundingSignBoundaries,
  missingSignStayExteriorWitnesses,
}

/// Only these coverage gaps permit bounded exterior acquisition. Other
/// StateErrors (reader, source, ordering, budgets) must not trigger a retry.
class DailyLunarCoverageException extends StateError {
  DailyLunarCoverageException(this.gap, String message) : super(message);
  final DailyLunarCoverageGap gap;
}

class DailyQuantizedLunarEvent {
  DailyQuantizedLunarEvent(this.kind, this.otherBody, this.targetDegrees, this.range);
  final String kind;
  final String? otherBody;
  final double targetDegrees;
  final LunarEventTimeRange range;
  Map<String, Object?> toJson(DailySevenTimepointPlan plan) => {
    'kind': kind, 'other_body': otherBody, 'target_degrees': targetDegrees,
    'range': range.toJson(),
    'day_relation': range.relationToDay(plan.dayStartUtc, plan.dayEndUtc).name,
  };
}

class DailyQuantizedVoidSegment {
  DailyQuantizedVoidSegment(this.entry, this.exit, List<DailyQuantizedLunarEvent> aspects,
      this.voidInterval) : aspects = List.unmodifiable(aspects);
  final DailyQuantizedLunarEvent entry, exit;
  final List<DailyQuantizedLunarEvent> aspects;
  final LunarVoidUncertainty voidInterval;
}

class DailyQuantizedLunarResult {
  DailyQuantizedLunarResult._(this.plan, List<DailyQuantizedLunarEvent> events,
      List<DailyQuantizedVoidSegment> segments, this.physicalEvaluationCount,
      List<QuantizedEventScanResult> evidence)
    : events = List.unmodifiable(events), segments = List.unmodifiable(segments),
      scanEvidence = List.unmodifiable(evidence);
  final DailySevenTimepointPlan plan;
  final List<DailyQuantizedLunarEvent> events;
  final List<DailyQuantizedVoidSegment> segments;
  final int physicalEvaluationCount;
  final List<QuantizedEventScanResult> scanEvidence;
  bool get allVoidSegmentsResolvedUnderAssumptions =>
      segments.every((segment) => segment.voidInterval.isReady);
  Map<String, Object?> toJson() => {
    'artifact_type': 'pancyo_daily_quantized_lunar_events_experiment_v1',
    'active_runtime_model': false,
    'target_date_jst': plan.targetDateJst,
    'day_start_utc': plan.dayStartUtc.toIso8601String(),
    'day_end_utc': plan.dayEndUtc.toIso8601String(),
    'day_end_inclusive': false,
    'all_void_segments_resolved_under_caller_assumptions':
      allVoidSegmentsResolvedUnderAssumptions,
    'independent_astronomical_accuracy_verified': false,
    'all_planetary_events_and_peaks_complete': false,
    'physical_evaluation_count': physicalEvaluationCount,
    'events_including_surrounding_witnesses': [for (final event in events) event.toJson(plan)],
    'sign_segments_overlapping_day': [for (final segment in segments) {
      'entry': segment.entry.toJson(plan), 'exit': segment.exit.toJson(plan),
      'aspects': [for (final aspect in segment.aspects) aspect.toJson(plan)],
      'void_interval': segment.voidInterval.toJson(),
      'day_overlap': segment.voidInterval.clipToDay(plan.dayStartUtc, plan.dayEndUtc),
    }],
    'scan_evidence': [for (final evidence in scanEvidence) evidence.toJson()],
  };
}

/// Independent fixed-JST assembly with no score/JSON/UI/native connection.
/// The caller prepares sufficient exterior physical samples and declares the
/// monotonicity/travel/time-displacement assumptions. No automatic fallback.
DailyQuantizedLunarResult buildDailyQuantizedLunarEvents({
  required DailySevenTimepointPlan plan,
  required LunarUnwrappedTracks tracks,
  required Duration scanStep,
  int maximumScanEvaluations = 10000,
  bool Function()? isCancelled,
}) {
  if (!tracks.hasStrictOuterTimeWitnesses(plan.dayStartUtc, plan.dayEndUtc)) {
    throw DailyLunarCoverageException(DailyLunarCoverageGap.missingExteriorTimeWitnesses,
      'missing_exterior_time_witnesses');
  }
  final evidence = <QuantizedEventScanResult>[];
  QuantizedEventScanResult scan(String? body) {
    final result = scanQuantizedEvents(readUnwrapped: tracks.reader(otherBody: body),
      startUtc: tracks.startUtc, endUtc: tracks.endUtc, scanStep: scanStep,
      maximumInputTimeRadius: tracks.maximumInputTimeRadius,
      maximumStepTravelDegrees: tracks.maximumStepTravelDegrees,
      periodDegrees: body == null ? 30 : 360,
      targetOffsetsDegrees: body == null ? [0] : [0, 60, 90, 120, 180, 240, 270, 300],
      maximumEvaluations: maximumScanEvaluations, isCancelled: isCancelled);
    if (!result.completeMeasuredSpanUnderAssumptions) {
      throw DailyLunarCoverageException(DailyLunarCoverageGap.scanEndpointEventUnresolved,
        'scan_endpoint_event_unresolved');
    }
    evidence.add(result);
    return result;
  }
  List<DailyQuantizedLunarEvent> convert(QuantizedEventScanResult result, String? body) =>
    [for (final event in result.events) DailyQuantizedLunarEvent(
      body == null ? 'moon_sign_boundary' : 'moon_major_aspect', body,
      event.targetDegrees, LunarEventTimeRange.fromBracket(event.bracket))];
  final signs = convert(scan(null), null);
  if (signs.length < 2 || !signs.first.range.upperUtc.isBefore(plan.dayStartUtc) ||
      !signs.last.range.lowerUtc.isAfter(plan.dayEndUtc)) {
    throw DailyLunarCoverageException(DailyLunarCoverageGap.missingSurroundingSignBoundaries,
      'missing_surrounding_sign_boundaries');
  }
  final aspects = <DailyQuantizedLunarEvent>[];
  for (final body in LunarLongitudeSample.bodies.where((body) => body != 'moon')) {
    aspects.addAll(convert(scan(body), body));
  }
  final segments = <DailyQuantizedVoidSegment>[];
  for (var i = 0; i + 1 < signs.length; i++) {
    final entry = signs[i], exit = signs[i + 1];
    if (exit.targetDegrees - entry.targetDegrees != 30) {
      throw StateError('missing_sign_boundary');
    }
    if (exit.range.upperUtc.isBefore(plan.dayStartUtc) ||
        !entry.range.lowerUtc.isBefore(plan.dayEndUtc)) continue;
    if (!tracks.hasStrictOuterTimeWitnesses(entry.range.lowerUtc, exit.range.upperUtc)) {
      throw DailyLunarCoverageException(DailyLunarCoverageGap.missingSignStayExteriorWitnesses,
        'missing_sign_stay_exterior_witnesses');
    }
    // Every aspect whose closed time range might touch this sign stay is kept.
    // Ambiguous sign membership is passed to the resolver, never silently dropped.
    final relevant = aspects.where((aspect) =>
      !aspect.range.upperUtc.isBefore(entry.range.lowerUtc) &&
      !aspect.range.lowerUtc.isAfter(exit.range.upperUtc)).toList();
    final interval = resolveLunarVoidUncertainty(signEntry: entry.range,
      signExit: exit.range, majorAspects: relevant.map((event) => event.range).toList(),
      completeAspectCoverage: true); // All nine scans with exterior evidence above.
    segments.add(DailyQuantizedVoidSegment(entry, exit, relevant, interval));
  }
  final events = [...signs, ...aspects]
    ..sort((a, b) => a.range.lowerUtc.compareTo(b.range.lowerUtc));
  // List order is only by range lower bound, not a proved order of exact events.
  return DailyQuantizedLunarResult._(plan, events, segments,
      tracks.evaluationCount, evidence);
}
