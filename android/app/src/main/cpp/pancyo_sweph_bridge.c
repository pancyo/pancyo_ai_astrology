#include <math.h>
#include <stdint.h>

#include "swephexp.h"

#if defined(_WIN32)
#define PANCYO_EXPORT __declspec(dllexport)
#else
#define PANCYO_EXPORT __attribute__((visibility("default")))
#endif

static double pancyo_norm360(double value) {
  double normalized = fmod(value, 360.0);
  if (normalized < 0.0) {
    normalized += 360.0;
  }
  return normalized;
}

PANCYO_EXPORT double pancyo_swe_julday_ut(int year, int month, int day, double hour_utc) {
  return swe_julday(year, month, day, hour_utc, SE_GREG_CAL);
}

PANCYO_EXPORT double pancyo_swe_planet_longitude_ut(double julian_day_ut, int planet_index) {
  if (planet_index < SE_SUN || planet_index > SE_PLUTO) {
    return NAN;
  }

  double result[6];
  char error[AS_MAXCH];
  const int flags = SEFLG_MOSEPH | SEFLG_SPEED;
  const int status = swe_calc_ut(julian_day_ut, planet_index, flags, result, error);
  if (status < 0) {
    return NAN;
  }
  return pancyo_norm360(result[0]);
}

// v1 is an owned return-by-value result. The ten calls below are deliberately
// the existing scalar wrapper in its original order, flags and normalization.
typedef struct {
  uint32_t abi_version;
  uint32_t count;
  uint32_t status;
  uint32_t reserved;
  double longitudes[10];
} PancyoPlanetLongitudesV1;

PANCYO_EXPORT uint32_t pancyo_swe_planet_longitudes_v1_result_size(void) {
  return (uint32_t)sizeof(PancyoPlanetLongitudesV1);
}

PANCYO_EXPORT PancyoPlanetLongitudesV1 pancyo_swe_planet_longitudes_v1_ut(
    double julian_day_ut) {
  PancyoPlanetLongitudesV1 result = {1, 0, 0, 0, {0}};
  for (int index = 0; index < 10; index++) {
    result.longitudes[index] = NAN;
  }
  if (!isfinite(julian_day_ut)) {
    result.status = 11;
    return result;
  }
  for (int index = 0; index < 10; index++) {
    const double value = pancyo_swe_planet_longitude_ut(julian_day_ut, index);
    if (!isfinite(value)) {
      result.status = (uint32_t)index + 1;
      return result;
    }
    result.longitudes[index] = value;
    result.count = (uint32_t)index + 1;
  }
  return result;
}

PANCYO_EXPORT double pancyo_swe_ascendant_ut(
    double julian_day_ut,
    double latitude,
    double longitude) {
  double cusps[13];
  double ascmc[10];
  const int status = swe_houses(julian_day_ut, latitude, longitude, 'W', cusps, ascmc);
  if (status < 0) {
    return NAN;
  }
  return pancyo_norm360(ascmc[0]);
}

PANCYO_EXPORT double pancyo_swe_midheaven_ut(
    double julian_day_ut,
    double latitude,
    double longitude) {
  double cusps[13];
  double ascmc[10];
  const int status = swe_houses(julian_day_ut, latitude, longitude, 'W', cusps, ascmc);
  if (status < 0) {
    return NAN;
  }
  return pancyo_norm360(ascmc[1]);
}

PANCYO_EXPORT double pancyo_swe_house_cusp_ut(
    double julian_day_ut,
    double latitude,
    double longitude,
    int house,
    int system) {
  if (house < 1 || house > 12) {
    return NAN;
  }
  double cusps[13];
  double ascmc[10];
  const char house_system = system == 1 ? 'P' : 'W';
  const int status = swe_houses(
      julian_day_ut,
      latitude,
      longitude,
      house_system,
      cusps,
      ascmc);
  if (status < 0) {
    return NAN;
  }
  return pancyo_norm360(cusps[house]);
}
