/// Independent native-event contract. Existing placements and scores do not use
/// it. A successful synthetic implementation is never native execution evidence.
enum SwissEventExecutionKind { nativeLibrary, syntheticFixture }

abstract interface class SwissEventNativeApi {
  SwissEventExecutionKind get executionKind;
  SwissEventNativeSample readUtc(DateTime utc);
}

class SwissEventBodyDiagnostic {
  const SwissEventBodyDiagnostic({
    required this.planetIndex,
    required this.returnedFlags,
    required this.longitude,
    required this.longitudeSpeedDegreesPerDay,
    required this.message,
  });
  final int planetIndex, returnedFlags;
  final double longitude, longitudeSpeedDegreesPerDay;
  final String message;
}

class SwissEventNativeSample {
  SwissEventNativeSample({
    required this.utcRequested,
    required this.abiVersion,
    required this.timeStatus,
    required this.requestedFlags,
    required this.julianDayTt,
    required this.julianDayUt1,
    required this.julianDayUt1SpacingSeconds,
    required this.ephemerisVersion,
    required this.timeMessage,
    required List<SwissEventBodyDiagnostic> bodies,
  }) : bodies = List.unmodifiable(bodies);
  final int abiVersion, timeStatus, requestedFlags;
  final DateTime utcRequested;
  final double julianDayTt, julianDayUt1, julianDayUt1SpacingSeconds;
  final String ephemerisVersion, timeMessage;
  final List<SwissEventBodyDiagnostic> bodies;
}

class SwissEventReadFailure extends StateError {
  SwissEventReadFailure(this.code, String detail, {this.utc, this.body})
    : super('$code: $detail');
  final String code;
  final DateTime? utc;
  final String? body;
}
