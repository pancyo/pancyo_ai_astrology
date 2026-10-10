/// Fixed, versioned by-value ABI for the ten legacy Swiss planet calls.
/// This contract does not change dates, Swiss flags, or longitude arithmetic.
class SwissEphemerisLongitudeBatchContract {
  const SwissEphemerisLongitudeBatchContract._();

  static const version = 1;
  static const planetCount = 10;

  static bool validLongitudes(List<double>? values) =>
      values != null &&
      values.length == planetCount &&
      values.every((value) => value.isFinite);

  static List<double>? decode({
    required int abiVersion,
    required int count,
    required int status,
    required int reserved,
    required List<double> longitudes,
  }) {
    if (abiVersion != version ||
        count != planetCount ||
        status != 0 ||
        reserved != 0 ||
        !validLongitudes(longitudes)) {
      return null;
    }
    return List<double>.unmodifiable(longitudes);
  }
}
