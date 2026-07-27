#include <math.h>

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
