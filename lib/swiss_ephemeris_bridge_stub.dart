class SwissEphemerisBridge {
  const SwissEphemerisBridge._();

  static bool get isAvailable => false;

  static double? julianDayUtc(int year, int month, int day, double hourUtc) => null;

  static double? planetLongitudeUtc(double julianDayUt, int planetIndex) => null;

  static double? ascendantUtc(double julianDayUt, double latitude, double longitude) => null;

  static double? midheavenUtc(double julianDayUt, double latitude, double longitude) => null;

  static double? houseCuspUtc(
    double julianDayUt,
    double latitude,
    double longitude,
    int house,
    int system,
  ) =>
      null;
}
