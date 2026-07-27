import 'dart:ffi' as ffi;

typedef _JulianDayNative = ffi.Double Function(
  ffi.Int32 year,
  ffi.Int32 month,
  ffi.Int32 day,
  ffi.Double hourUtc,
);
typedef _JulianDayDart = double Function(int year, int month, int day, double hourUtc);

typedef _PlanetLongitudeNative = ffi.Double Function(
  ffi.Double julianDayUt,
  ffi.Int32 planetIndex,
);
typedef _PlanetLongitudeDart = double Function(double julianDayUt, int planetIndex);

typedef _AngleNative = ffi.Double Function(
  ffi.Double julianDayUt,
  ffi.Double latitude,
  ffi.Double longitude,
);
typedef _AngleDart = double Function(double julianDayUt, double latitude, double longitude);

typedef _HouseCuspNative = ffi.Double Function(
  ffi.Double julianDayUt,
  ffi.Double latitude,
  ffi.Double longitude,
  ffi.Int32 house,
  ffi.Int32 system,
);
typedef _HouseCuspDart = double Function(
  double julianDayUt,
  double latitude,
  double longitude,
  int house,
  int system,
);

class SwissEphemerisBridge {
  const SwissEphemerisBridge._();

  static ffi.DynamicLibrary? _library;
  static _JulianDayDart? _julianDay;
  static _PlanetLongitudeDart? _planetLongitude;
  static _AngleDart? _ascendant;
  static _AngleDart? _midheaven;
  static _HouseCuspDart? _houseCusp;

  static bool get isAvailable {
    try {
      _ensureLoaded();
      return true;
    } on Object {
      return false;
    }
  }

  static double? julianDayUtc(int year, int month, int day, double hourUtc) {
    try {
      _ensureLoaded();
      final value = _julianDay!(year, month, day, hourUtc);
      return value.isFinite ? value : null;
    } on Object {
      return null;
    }
  }

  static double? planetLongitudeUtc(double julianDayUt, int planetIndex) {
    try {
      _ensureLoaded();
      final value = _planetLongitude!(julianDayUt, planetIndex);
      return value.isFinite ? value : null;
    } on Object {
      return null;
    }
  }

  static double? ascendantUtc(double julianDayUt, double latitude, double longitude) {
    try {
      _ensureLoaded();
      final value = _ascendant!(julianDayUt, latitude, longitude);
      return value.isFinite ? value : null;
    } on Object {
      return null;
    }
  }

  static double? midheavenUtc(double julianDayUt, double latitude, double longitude) {
    try {
      _ensureLoaded();
      final value = _midheaven!(julianDayUt, latitude, longitude);
      return value.isFinite ? value : null;
    } on Object {
      return null;
    }
  }

  static double? houseCuspUtc(
    double julianDayUt,
    double latitude,
    double longitude,
    int house,
    int system,
  ) {
    try {
      _ensureLoaded();
      final value = _houseCusp!(julianDayUt, latitude, longitude, house, system);
      return value.isFinite ? value : null;
    } on Object {
      return null;
    }
  }

  static void _ensureLoaded() {
    final existing = _library;
    if (existing != null) return;

    final library = ffi.DynamicLibrary.open('libpancyo_sweph.so');
    _julianDay = library
        .lookupFunction<_JulianDayNative, _JulianDayDart>('pancyo_swe_julday_ut');
    _planetLongitude = library.lookupFunction<_PlanetLongitudeNative, _PlanetLongitudeDart>(
      'pancyo_swe_planet_longitude_ut',
    );
    _ascendant = library.lookupFunction<_AngleNative, _AngleDart>('pancyo_swe_ascendant_ut');
    _midheaven = library.lookupFunction<_AngleNative, _AngleDart>('pancyo_swe_midheaven_ut');
    _houseCusp = library.lookupFunction<_HouseCuspNative, _HouseCuspDart>(
      'pancyo_swe_house_cusp_ut',
    );
    _library = library;
  }
}
