import 'daily_lunar_event_search.dart';
import 'swiss_event_sample.dart';

/// Direct measurements and diagnostics, separate from legacy minute-based
/// SimpleEphemeris. No fallback, interpolation, angles, houses or score changes.
class SwissLunarEphemeris {
  SwissLunarEphemeris({required SwissEventNativeApi native}) : _native = native;
  static const requestedFlags = 4 | 256; // SEFLG_MOSEPH | SEFLG_SPEED.
  final SwissEventNativeApi _native;
  String? _sourceIdentity;

  SwissLunarSample read(DateTime instant) {
    final utc = instant.toUtc();
    if (utc.year < 1 || utc.year > 9999) {
      throw SwissEventReadFailure(
        'unsupported_instant',
        'Gregorian year must be 1..9999',
        utc: utc,
      );
    }
    final kind = _native.executionKind;
    final raw = _native.readUtc(utc);
    Never fail(String code, String detail, [String? body]) =>
        throw SwissEventReadFailure(code, detail, utc: utc, body: body);
    if (raw.abiVersion != 1) fail('unsupported_abi', 'Expected detail ABI 1');
    if (!raw.utcRequested.isUtc || raw.utcRequested != utc) {
      fail(
        'instant_mismatch',
        'Native sample does not echo the requested UTC instant',
      );
    }
    if (raw.timeStatus != 0) {
      fail('time_conversion_failed', raw.timeMessage);
    }
    if (!raw.julianDayTt.isFinite ||
        !raw.julianDayUt1.isFinite ||
        !raw.julianDayUt1SpacingSeconds.isFinite ||
        raw.julianDayUt1SpacingSeconds <= 0) {
      fail(
        'invalid_time_sample',
        'Finite JD values and positive spacing required',
      );
    }
    if (raw.requestedFlags != requestedFlags) {
      fail('unexpected_requested_flags', '${raw.requestedFlags}');
    }
    if (raw.ephemerisVersion.trim().isEmpty) {
      fail('missing_ephemeris_version', 'Native version is required');
    }
    if (raw.bodies.length != LunarLongitudeSample.bodies.length) {
      fail('incomplete_bodies', 'Exactly ten physical bodies required');
    }
    final ordered = <SwissEventBodyDiagnostic>[];
    for (var i = 0; i < LunarLongitudeSample.bodies.length; i++) {
      final name = LunarLongitudeSample.bodies[i];
      final matches = raw.bodies.where((b) => b.planetIndex == i).toList();
      if (matches.length != 1) fail('invalid_body_identity', '$i', name);
      final b = matches.single;
      if (b.returnedFlags < 0)
        fail('planet_calculation_failed', b.message, name);
      // Reject fallback, missing speed or changed coordinate conventions.
      if (b.returnedFlags != requestedFlags) {
        fail(
          'unexpected_returned_flags',
          '${b.returnedFlags}: ${b.message}',
          name,
        );
      }
      if (!b.longitude.isFinite ||
          b.longitude < 0 ||
          b.longitude >= 360 ||
          !b.longitudeSpeedDegreesPerDay.isFinite) {
        fail(
          'invalid_planet_sample',
          'Finite normalized longitude and speed required',
          name,
        );
      }
      ordered.add(b);
    }
    final moonSpeed = ordered[1].longitudeSpeedDegreesPerDay;
    if (moonSpeed <= 0) fail('unsupported_lunar_speed', '$moonSpeed', 'moon');
    for (var i = 0; i < ordered.length; i++) {
      if (i != 1 && moonSpeed - ordered[i].longitudeSpeedDegreesPerDay <= 0) {
        fail(
          'unsupported_relative_speed',
          'Moon phase must increase at this evaluation',
          LunarLongitudeSample.bodies[i],
        );
      }
    }
    final source =
        '${kind.name}:swiss_moshier:${raw.ephemerisVersion}:'
        'flags=$requestedFlags:swe_utc_to_jd_gregorian';
    if (_sourceIdentity != null && _sourceIdentity != source) {
      fail(
        'source_changed',
        'Calculation identity changed between evaluations',
      );
    }
    final value = SwissLunarSample._(utc, raw, ordered, kind, source);
    _sourceIdentity = source; // Commit only a completely validated measurement.
    return value;
  }
}

class SwissLunarSample {
  SwissLunarSample._(
    this.utc,
    this.raw,
    List<SwissEventBodyDiagnostic> ordered,
    this.executionKind,
    this.sourceIdentity,
  ) : bodies = List.unmodifiable(ordered);
  final DateTime utc;
  final SwissEventNativeSample raw;
  final List<SwissEventBodyDiagnostic> bodies;
  final SwissEventExecutionKind executionKind;
  final String sourceIdentity;

  /// Native JD is a binary64 lattice, not a continuous one-microsecond clock.
  /// The existing root solver has not yet been adapted/verified on this source.
  LunarLongitudeSample get longitudeSample => LunarLongitudeSample(
    longitudes: {
      for (var i = 0; i < bodies.length; i++)
        LunarLongitudeSample.bodies[i]: bodies[i].longitude,
    },
    sources: {
      for (final name in LunarLongitudeSample.bodies) name: sourceIdentity,
    },
  );

  Map<String, Object?> toJson() => {
    'artifact_type': 'pancyo_swiss_lunar_measurement_experiment_v1',
    'active_runtime_model': false,
    'utc_requested': utc.toIso8601String(),
    'execution_kind': executionKind.name,
    'source_identity': sourceIdentity,
    'native_flags_reported':
        executionKind == SwissEventExecutionKind.nativeLibrary,
    'independent_astronomical_accuracy_verified': false,
    'native_root_solver_verified': false,
    'requested_flags': raw.requestedFlags,
    'ephemeris_version': raw.ephemerisVersion,
    'julian_day_tt': raw.julianDayTt,
    'julian_day_ut1': raw.julianDayUt1,
    'julian_day_ut1_spacing_seconds': raw.julianDayUt1SpacingSeconds,
    'timestamp_precision_is_not_astronomical_accuracy': true,
    'time_conversion':
        'swe_utc_to_jd_gregorian_builtin_leap_seconds_and_delta_t',
    'time_conversion_input_interpretation': utc.year < 1972
        ? 'pre_1972_input_treated_as_ut1'
        : 'utc_with_swiss_builtin_ut1_fallback_not_independently_excluded',
    'earth_orientation_and_leap_seconds_independently_verified': false,
    'time_message': raw.timeMessage,
    'bodies': [
      for (var i = 0; i < bodies.length; i++)
        {
          'body': LunarLongitudeSample.bodies[i],
          'planet_index': bodies[i].planetIndex,
          'longitude': bodies[i].longitude,
          'longitude_speed_degrees_per_day':
              bodies[i].longitudeSpeedDegreesPerDay,
          'returned_flags': bodies[i].returnedFlags,
          'message': bodies[i].message,
        },
    ],
    'monotonic_lunar_speed_checked_at_this_evaluation_only': true,
    'global_continuity_and_monotonicity_verified': false,
  };
}
