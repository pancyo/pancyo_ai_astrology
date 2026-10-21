package com.pancyo.aiastrology;

import java.time.DateTimeException;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;
import java.time.zone.ZoneRules;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.NavigableMap;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Pure civil-time conversion using the runtime's region rules.
 *
 * <p>No default zone, fixed-offset fallback, automatic gap correction, or overlap
 * selection is used. The caller owns explicit candidate selection and storage.
 * Rules come from this runtime; a saved UTC instant must not be silently
 * re-resolved after a time-zone database update.
 */
public final class CivilTimeResolver {
    private static final Pattern DATE = Pattern.compile("([0-9]{4})-([0-9]{2})-([0-9]{2})");
    private static final Pattern TIME = Pattern.compile("([0-9]{2}):([0-9]{2}):([0-9]{2})");
    // UTC edge years permit round trips for local years 0001..9999.
    private static final Pattern UTC = Pattern.compile(
            "([0-9]{4}|\\+0?10000)-([0-9]{2})-([0-9]{2})T"
                    + "([0-9]{2}):([0-9]{2}):([0-9]{2})(?:\\.([0-9]{1,9}))?Z");
    private static final DateTimeFormatter LOCAL =
            DateTimeFormatter.ofPattern("uuuu-MM-dd'T'HH:mm:ss", java.util.Locale.ROOT);

    private CivilTimeResolver() {}

    /** Resolves a strict region-local second without choosing an overlap candidate. */
    public static Map<String, Object> resolveLocal(
            String zoneId, String localDate, String localTime) {
        ZoneId zone = requireRegion(zoneId);
        LocalDateTime local = LocalDateTime.of(requireDate(localDate), requireTime(localTime));
        List<ZoneOffset> offsets = new ArrayList<>(zone.getRules().getValidOffsets(local));
        if (offsets.size() > 2) {
            throw new IllegalArgumentException("Unsupported number of valid offsets");
        }
        offsets.sort(Comparator.comparing(offset -> local.toInstant(offset)));

        List<Map<String, Object>> candidates = new ArrayList<>();
        for (ZoneOffset offset : offsets) {
            Map<String, Object> candidate = new LinkedHashMap<>();
            candidate.put("instantUtc", local.toInstant(offset).toString());
            candidate.put("offsetSeconds", offset.getTotalSeconds());
            candidates.add(candidate);
        }

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("zoneId", zone.getId());
        result.put("localDateTime", LOCAL.format(local));
        result.put("status", offsets.isEmpty() ? "gap" : offsets.size() == 1 ? "unique" : "overlap");
        result.put("tzdbVersion", availableVersion(zone));
        result.put("candidates", candidates);
        return result;
    }

    /**
     * Formats a UTC second in an explicit region. Zero-valued ISO fractions are
     * accepted; nonzero fractions are rejected instead of being truncated by the
     * second-precision localDateTime contract.
     */
    public static Map<String, Object> formatInstant(String zoneId, String instantUtc) {
        ZoneId zone = requireRegion(zoneId);
        Instant instant = requireUtcSecond(instantUtc);
        ZonedDateTime local = instant.atZone(zone);
        if (local.getYear() < 1 || local.getYear() > 9999) {
            throw new IllegalArgumentException("Local year must be between 0001 and 9999");
        }
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("zoneId", zone.getId());
        result.put("localDateTime", LOCAL.format(local));
        result.put("instantUtc", instant.toString());
        result.put("offsetSeconds", local.getOffset().getTotalSeconds());
        result.put("tzdbVersion", availableVersion(zone));
        return result;
    }

    private static ZoneId requireRegion(String zoneId) {
        if (zoneId == null || !ZoneId.getAvailableZoneIds().contains(zoneId)) {
            throw new IllegalArgumentException("Unknown region time-zone ID");
        }
        return ZoneId.of(zoneId);
    }

    private static LocalDate requireDate(String value) {
        Matcher match = match(DATE, value, "Expected local date YYYY-MM-DD");
        int year = Integer.parseInt(match.group(1));
        if (year < 1) {
            throw new IllegalArgumentException("Local year must be between 0001 and 9999");
        }
        try {
            return LocalDate.of(year, Integer.parseInt(match.group(2)), Integer.parseInt(match.group(3)));
        } catch (DateTimeException error) {
            throw new IllegalArgumentException("Invalid Gregorian local date", error);
        }
    }

    private static LocalTime requireTime(String value) {
        Matcher match = match(TIME, value, "Expected local time HH:mm:ss");
        try {
            return LocalTime.of(Integer.parseInt(match.group(1)),
                    Integer.parseInt(match.group(2)), Integer.parseInt(match.group(3)));
        } catch (DateTimeException error) {
            throw new IllegalArgumentException("Invalid local time", error);
        }
    }

    private static Instant requireUtcSecond(String value) {
        Matcher match = match(UTC, value, "Expected a strict UTC ISO second ending in Z");
        String fraction = match.group(7);
        if (fraction != null && !fraction.matches("0+")) {
            throw new IllegalArgumentException("Subsecond precision is outside this contract");
        }
        try {
            return LocalDateTime.of(Integer.parseInt(match.group(1)),
                    Integer.parseInt(match.group(2)), Integer.parseInt(match.group(3)),
                    Integer.parseInt(match.group(4)), Integer.parseInt(match.group(5)),
                    Integer.parseInt(match.group(6))).toInstant(ZoneOffset.UTC);
        } catch (DateTimeException error) {
            throw new IllegalArgumentException("Invalid UTC Gregorian date or time", error);
        }
    }

    private static Matcher match(Pattern pattern, String value, String message) {
        if (value == null) {
            throw new IllegalArgumentException(message);
        }
        Matcher match = pattern.matcher(value);
        if (!match.matches()) {
            throw new IllegalArgumentException(message);
        }
        return match;
    }

    private static String availableVersion(ZoneId zone) {
        try {
            // Optional JVM diagnostic. ZoneRulesProvider is not in Android's
            // public SDK; calculation itself only uses the public ZoneRules.
            Object result = Class.forName("java.time.zone.ZoneRulesProvider")
                    .getMethod("getVersions", String.class).invoke(null, zone.getId());
            if (!(result instanceof NavigableMap)) return null;
            NavigableMap<?, ?> versions = (NavigableMap<?, ?>) result;
            Object version = versions.isEmpty() ? null : versions.lastKey();
            return version instanceof String ? (String) version : null;
        } catch (ReflectiveOperationException | RuntimeException | LinkageError error) {
            // Absence of diagnostics does not invent a database version.
            return null;
        }
    }
}
