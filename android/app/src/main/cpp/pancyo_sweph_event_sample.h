#ifndef PANCYO_SWEPH_EVENT_SAMPLE_H
#define PANCYO_SWEPH_EVENT_SAMPLE_H

#include <stdint.h>

#if defined(_WIN32)
#define PANCYO_EVENT_EXPORT __declspec(dllexport)
#else
#define PANCYO_EVENT_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// ABI 1 uses an owned opaque handle; callers never depend on struct packing.
// All text pointers are borrowed, NUL-terminated, at most 255 bytes, and valid
// only until free. Copy them before freeing the handle. NULL create means OOM.
typedef struct PancyoSwissEventSample PancyoSwissEventSample;
enum PancyoSwissEventIntField {
  PANCYO_EVENT_ABI = 0,
  PANCYO_EVENT_TIME_STATUS = 1,
  PANCYO_EVENT_REQUESTED_FLAGS = 2,
  PANCYO_EVENT_PLANET_INDEX = 3,
  PANCYO_EVENT_RETURNED_FLAGS = 4,
  PANCYO_EVENT_YEAR = 5,
  PANCYO_EVENT_MONTH = 6,
  PANCYO_EVENT_DAY = 7,
  PANCYO_EVENT_HOUR = 8,
  PANCYO_EVENT_MINUTE = 9
};
enum PancyoSwissEventDoubleField {
  PANCYO_EVENT_JD_TT = 0,
  PANCYO_EVENT_JD_UT1 = 1,
  PANCYO_EVENT_JD_UT1_SPACING_SECONDS = 2,
  PANCYO_EVENT_LONGITUDE = 3,
  PANCYO_EVENT_LONGITUDE_SPEED = 4,
  PANCYO_EVENT_SECOND = 5
};
enum PancyoSwissEventTextField {
  PANCYO_EVENT_VERSION_TEXT = 0,
  PANCYO_EVENT_TIME_TEXT = 1,
  PANCYO_EVENT_PLANET_TEXT = 2
};

// Gregorian years 1..9999, ordinary decimal seconds [0,60).
// Invalid inputs return an owned failed sample, never a partial success.
PANCYO_EVENT_EXPORT PancyoSwissEventSample *pancyo_swe_event_sample_create(
    int32_t year, int32_t month, int32_t day, int32_t hour, int32_t minute,
    double second);
PANCYO_EVENT_EXPORT void pancyo_swe_event_sample_free(PancyoSwissEventSample *sample);
PANCYO_EVENT_EXPORT int32_t pancyo_swe_event_sample_int(
    const PancyoSwissEventSample *sample, int32_t field, int32_t planet);
PANCYO_EVENT_EXPORT double pancyo_swe_event_sample_double(
    const PancyoSwissEventSample *sample, int32_t field, int32_t planet);
PANCYO_EVENT_EXPORT const char *pancyo_swe_event_sample_text(
    const PancyoSwissEventSample *sample, int32_t field, int32_t planet);

#ifdef __cplusplus
}
#endif

#endif
