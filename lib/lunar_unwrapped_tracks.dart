import 'daily_lunar_event_search.dart';
import 'quantized_event_bracket.dart';

/// A caller-provided physical sample. No native execution/accuracy is implied.
class TimedLunarLongitudes {
  TimedLunarLongitudes({required this.utc, required this.coordinate,
      required this.source, required this.inputTimeRadius,
      required Map<String, double> longitudes})
      : longitudes = Map.unmodifiable(longitudes);
  final DateTime utc;
  final double coordinate;
  final String source;
  final Duration inputTimeRadius;
  final Map<String, double> longitudes;
}

typedef TimedLunarReader = TimedLunarLongitudes Function(DateTime utc);

class LunarUnwrappedTracks {
  LunarUnwrappedTracks._(this._read, this.startUtc, this.endUtc,
      this.maximumInputTimeRadius, this._maximumEvaluations, this._isCancelled,
      this.maximumStepTravelDegrees);
  final TimedLunarReader _read;
  final DateTime startUtc, endUtc;
  final Duration maximumInputTimeRadius;
  final double maximumStepTravelDegrees;
  final int _maximumEvaluations;
  final bool Function()? _isCancelled;
  final _cache = <DateTime, TimedLunarLongitudes>{};
  final _nodes = <DateTime>[];
  final _tracks = <String, List<double>>{};
  final _refinements = <String, Map<DateTime, double>>{};
  String? _source;
  int get evaluationCount => _cache.length;
  List<DateTime> get scanNodes => List.unmodifiable(_nodes);
  String get source => _source!;

  /// Necessary exterior time evidence under a caller-declared displacement
  /// bound. This alone does not certify event enumeration or ephemeris accuracy.
  bool hasStrictOuterTimeWitnesses(DateTime requestedStart, DateTime requestedEnd) {
    if (!requestedStart.isUtc || !requestedEnd.isUtc ||
        !requestedStart.isBefore(requestedEnd)) throw ArgumentError('Invalid UTC interval');
    return startUtc.add(maximumInputTimeRadius).isBefore(requestedStart) &&
      endUtc.subtract(maximumInputTimeRadius).isAfter(requestedEnd);
  }

  TimedLunarLongitudes _acquire(DateTime utc) {
    if (_isCancelled?.call() == true) throw StateError('track_cancelled');
    if (!utc.isUtc || utc.isBefore(startUtc) || utc.isAfter(endUtc)) {
      throw ArgumentError('Read outside prepared UTC range');
    }
    final old = _cache[utc];
    if (old != null) return old;
    if (_cache.length >= _maximumEvaluations) throw StateError('track_budget_exhausted');
    final value = _read(utc);
    if (!value.utc.isUtc || value.utc != utc || !value.coordinate.isFinite ||
        value.source.trim().isEmpty || value.inputTimeRadius.inMicroseconds < 1 ||
        value.inputTimeRadius > maximumInputTimeRadius ||
        value.longitudes.length != LunarLongitudeSample.bodies.length ||
        LunarLongitudeSample.bodies.any((body) {
          final v = value.longitudes[body];
          return v == null || !v.isFinite || v < 0 || v >= 360;
        })) throw StateError('invalid_physical_sample');
    if (_source != null && value.source != _source) throw StateError('source_changed');
    for (final previous in _cache.values) {
      final earlier = previous.utc.isBefore(utc) ? previous : value;
      final later = previous.utc.isBefore(utc) ? value : previous;
      if (earlier.coordinate > later.coordinate) throw StateError('coordinate_reversed');
      if (earlier.coordinate == later.coordinate &&
          LunarLongitudeSample.bodies.any((b) => earlier.longitudes[b] != later.longitudes[b])) {
        throw StateError('same_coordinate_different_longitudes');
      }
    }
    _source = value.source;
    _cache[utc] = value;
    return value;
  }

  double _phase(TimedLunarLongitudes sample, String track) {
    final moon = sample.longitudes['moon']!;
    return track == 'moon' ? moon : (moon - sample.longitudes[track]!) % 360;
  }

  QuantizedEventReader reader({String? otherBody}) {
    final track = otherBody ?? 'moon';
    if (otherBody == 'moon' || !_tracks.containsKey(track)) {
      throw ArgumentError('Expected Moon longitude or Moon minus another physical body');
    }
    return (utc) {
      final sample = _acquire(utc);
      var index = _nodes.indexWhere((t) => t.isAfter(utc)) - 1;
      if (index == -2) index = _nodes.length - 1;
      final anchor = _cache[_nodes[index]]!;
      final delta = _signedForwardDelta(_phase(anchor, track), _phase(sample, track));
      final scalar = _tracks[track]![index] + delta;
      if (delta < 0 || delta > maximumStepTravelDegrees ||
          (index + 1 < _nodes.length && scalar > _tracks[track]![index + 1])) {
        throw StateError('refinement_outside_monotonic_track');
      }
      final observed = _refinements.putIfAbsent(track, () => {});
      for (final old in observed.entries) {
        if ((old.key.isBefore(utc) && old.value > scalar) ||
            (old.key.isAfter(utc) && old.value < scalar)) {
          throw StateError('refinement_reversed');
        }
      }
      observed[utc] = scalar;
      return QuantizedEventObservation(utc: utc, coordinate: sample.coordinate,
        residual: scalar, source: sample.source, inputTimeRadius: sample.inputTimeRadius);
    };
  }

  Map<String, Object?> toJson() => {
    'artifact_type': 'pancyo_lunar_unwrapped_tracks_experiment_v1',
    'active_runtime_model': false,
    'source': source,
    'start_utc': startUtc.toIso8601String(),
    'end_utc': endUtc.toIso8601String(),
    'maximum_input_time_radius_microseconds': maximumInputTimeRadius.inMicroseconds,
    'maximum_step_travel_degrees': maximumStepTravelDegrees,
    'evaluation_count': evaluationCount,
    'bound_and_interread_monotonicity_verification': 'caller_assumptions',
    'independent_astronomical_accuracy_verified': false,
    'whole_day_event_coverage_verified': false,
    'scan_nodes': [for (var i = 0; i < _nodes.length; i++) {
      'utc': _nodes[i].toIso8601String(),
      'unwrapped_degrees': {for (final body in _tracks.keys) body: _tracks[body]![i]},
    }],
  };
}

LunarUnwrappedTracks prepareLunarUnwrappedTracks({
  required TimedLunarReader read,
  required DateTime startUtc,
  required DateTime endUtc,
  required Duration scanStep,
  required Duration maximumInputTimeRadius,
  required double maximumStepTravelDegrees,
  int maximumEvaluations = 10000,
  bool Function()? isCancelled,
}) {
  if (!startUtc.isUtc || !endUtc.isUtc || !startUtc.isBefore(endUtc) ||
      scanStep.inMicroseconds < 1 || maximumInputTimeRadius.inMicroseconds < 1 ||
      !maximumStepTravelDegrees.isFinite || maximumStepTravelDegrees <= 0 ||
      maximumStepTravelDegrees >= 180 || maximumEvaluations < 2) {
    throw ArgumentError('Invalid unwrapped-track contract');
  }
  final result = LunarUnwrappedTracks._(read, startUtc, endUtc,
    maximumInputTimeRadius, maximumEvaluations, isCancelled, maximumStepTravelDegrees);
  for (final body in LunarLongitudeSample.bodies) result._tracks[body] = [];
  var utc = startUtc;
  TimedLunarLongitudes? previous;
  while (true) {
    final sample = result._acquire(utc);
    for (final body in LunarLongitudeSample.bodies) {
      final values = result._tracks[body]!;
      final phase = result._phase(sample, body);
      if (previous == null) {
        values.add(phase);
      } else {
        final delta = _signedForwardDelta(result._phase(previous, body), phase);
        if (delta < 0 || delta > maximumStepTravelDegrees) {
          throw StateError('unsupported_track_travel');
        }
        values.add(values.last + delta);
      }
    }
    result._nodes.add(utc);
    previous = sample;
    if (utc == endUtc) break;
    final remaining = endUtc.difference(utc);
    utc = utc.add(remaining < scanStep ? remaining : scanStep);
  }
  return result;
}

double _signedForwardDelta(double before, double after) =>
    (after - before + 540) % 360 - 180;
