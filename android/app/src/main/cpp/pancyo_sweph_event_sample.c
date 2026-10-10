#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "swephexp.h"
#include "pancyo_sweph_event_sample.h"

#define PANCYO_EVENT_TEXT_CAPACITY 256
#if AS_MAXCH != PANCYO_EVENT_TEXT_CAPACITY
#error Swiss Ephemeris message capacity changed: review detail ABI 1
#endif

struct PancyoSwissEventBody {
  int32_t planet_index, returned_flags;
  double longitude, speed;
  char message[PANCYO_EVENT_TEXT_CAPACITY];
};

struct PancyoSwissEventSample {
  int32_t time_status, requested_flags;
  int32_t year, month, day, hour, minute;
  double second, jd_tt, jd_ut1, jd_ut1_spacing_seconds;
  char version[PANCYO_EVENT_TEXT_CAPACITY];
  char time_message[PANCYO_EVENT_TEXT_CAPACITY];
  struct PancyoSwissEventBody bodies[10];
};

PANCYO_EVENT_EXPORT PancyoSwissEventSample *pancyo_swe_event_sample_create(
    int32_t year, int32_t month, int32_t day, int32_t hour, int32_t minute,
    double second) {
  PancyoSwissEventSample *sample = calloc(1, sizeof(*sample));
  if (sample == NULL) return NULL;
  sample->year = year;
  sample->month = month;
  sample->day = day;
  sample->hour = hour;
  sample->minute = minute;
  sample->second = second;
  sample->time_status = -1;
  sample->requested_flags = SEFLG_MOSEPH | SEFLG_SPEED;
  sample->jd_tt = sample->jd_ut1 = sample->jd_ut1_spacing_seconds = NAN;
  swe_version(sample->version);
  sample->version[PANCYO_EVENT_TEXT_CAPACITY - 1] = '\0';
  for (int i = 0; i < 10; ++i) {
    sample->bodies[i].planet_index = i;
    sample->bodies[i].returned_flags = -1;
    sample->bodies[i].longitude = sample->bodies[i].speed = NAN;
  }
  if (year < 1 || year > 9999 || month < 1 || month > 12 || day < 1 || day > 31 ||
      hour < 0 || hour > 23 || minute < 0 || minute > 59 ||
      !isfinite(second) || second < 0 || second >= 60) {
    const char message[] = "invalid Gregorian UTC input";
    memcpy(sample->time_message, message, sizeof(message));
    return sample;
  }
  double jd[2] = {NAN, NAN};
  sample->time_status = swe_utc_to_jd(
      year, month, day, hour, minute, second, SE_GREG_CAL, jd,
      sample->time_message);
  sample->time_message[PANCYO_EVENT_TEXT_CAPACITY - 1] = '\0';
  if (sample->time_status != 0 || !isfinite(jd[0]) || !isfinite(jd[1])) {
    return sample;
  }
  sample->jd_tt = jd[0];
  sample->jd_ut1 = jd[1];
  sample->jd_ut1_spacing_seconds = (nextafter(jd[1], INFINITY) - jd[1]) * 86400.0;
  for (int i = 0; i < 10; ++i) {
    double result[6] = {NAN, NAN, NAN, NAN, NAN, NAN};
    struct PancyoSwissEventBody *body = &sample->bodies[i];
    body->returned_flags = swe_calc_ut(
        jd[1], i, sample->requested_flags, result, body->message);
    body->message[PANCYO_EVENT_TEXT_CAPACITY - 1] = '\0';
    if (body->returned_flags >= 0) {
      body->longitude = fmod(result[0], 360.0);
      if (body->longitude < 0) body->longitude += 360.0;
      body->speed = result[3]; // Ecliptic longitude speed, degrees per day.
    }
  }
  return sample;
}

PANCYO_EVENT_EXPORT void pancyo_swe_event_sample_free(PancyoSwissEventSample *sample) {
  free(sample);
}

PANCYO_EVENT_EXPORT int32_t pancyo_swe_event_sample_int(
    const PancyoSwissEventSample *sample, int32_t field, int32_t planet) {
  if (sample == NULL) return INT32_MIN;
  switch (field) {
    case PANCYO_EVENT_ABI: return 1;
    case PANCYO_EVENT_TIME_STATUS: return sample->time_status;
    case PANCYO_EVENT_REQUESTED_FLAGS: return sample->requested_flags;
    case PANCYO_EVENT_YEAR: return sample->year;
    case PANCYO_EVENT_MONTH: return sample->month;
    case PANCYO_EVENT_DAY: return sample->day;
    case PANCYO_EVENT_HOUR: return sample->hour;
    case PANCYO_EVENT_MINUTE: return sample->minute;
    default: break;
  }
  if (planet < 0 || planet > 9) return INT32_MIN;
  if (field == PANCYO_EVENT_PLANET_INDEX) return sample->bodies[planet].planet_index;
  if (field == PANCYO_EVENT_RETURNED_FLAGS) return sample->bodies[planet].returned_flags;
  return INT32_MIN;
}

PANCYO_EVENT_EXPORT double pancyo_swe_event_sample_double(
    const PancyoSwissEventSample *sample, int32_t field, int32_t planet) {
  if (sample == NULL) return NAN;
  switch (field) {
    case PANCYO_EVENT_JD_TT: return sample->jd_tt;
    case PANCYO_EVENT_JD_UT1: return sample->jd_ut1;
    case PANCYO_EVENT_JD_UT1_SPACING_SECONDS: return sample->jd_ut1_spacing_seconds;
    case PANCYO_EVENT_SECOND: return sample->second;
    default: break;
  }
  if (planet < 0 || planet > 9) return NAN;
  if (field == PANCYO_EVENT_LONGITUDE) return sample->bodies[planet].longitude;
  if (field == PANCYO_EVENT_LONGITUDE_SPEED) return sample->bodies[planet].speed;
  return NAN;
}

PANCYO_EVENT_EXPORT const char *pancyo_swe_event_sample_text(
    const PancyoSwissEventSample *sample, int32_t field, int32_t planet) {
  if (sample == NULL) return NULL;
  if (field == PANCYO_EVENT_VERSION_TEXT) return sample->version;
  if (field == PANCYO_EVENT_TIME_TEXT) return sample->time_message;
  if (field == PANCYO_EVENT_PLANET_TEXT && planet >= 0 && planet < 10) {
    return sample->bodies[planet].message;
  }
  return NULL;
}
