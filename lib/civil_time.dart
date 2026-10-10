import 'package:flutter/services.dart';

/// A civil clock reading, independent of the computer's local time zone.
/// This is not an astronomical instant until a regional rule resolves it.
class CivilClockTime {
  CivilClockTime._(this.fields);

  factory CivilClockTime.parse(String date, String time) {
    final dateMatch = RegExp(r'^([0-9]{4})-([0-9]{2})-([0-9]{2})$').firstMatch(date);
    final timeMatch = RegExp(r'^([0-9]{2}):([0-9]{2}):([0-9]{2})$').firstMatch(time);
    if (dateMatch == null || timeMatch == null) {
      throw const FormatException('Expected a civil YYYY-MM-DD and HH:mm:ss.');
    }
    final year = int.parse(dateMatch.group(1)!);
    final month = int.parse(dateMatch.group(2)!);
    final day = int.parse(dateMatch.group(3)!);
    final hour = int.parse(timeMatch.group(1)!);
    final minute = int.parse(timeMatch.group(2)!);
    final second = int.parse(timeMatch.group(3)!);
    if (year < 1 || year > 9999 || month < 1 || month > 12 || day < 1 || day > 31 ||
        hour > 23 || minute > 59 || second > 59) {
      throw const FormatException('Invalid civil clock fields.');
    }
    final fields = DateTime.utc(year, month, day, hour, minute, second);
    if (fields.year != year || fields.month != month || fields.day != day) {
      throw const FormatException('Invalid civil calendar date.');
    }
    return CivilClockTime._(fields);
  }

  /// UTC is used here only as a container for Gregorian wall-clock fields.
  /// Never pass this value to the astrology engine as a resolved instant.
  final DateTime fields;
  String get date => '${fields.year.toString().padLeft(4, '0')}-'
      '${fields.month.toString().padLeft(2, '0')}-${fields.day.toString().padLeft(2, '0')}';
  String get time => '${fields.hour.toString().padLeft(2, '0')}:'
      '${fields.minute.toString().padLeft(2, '0')}:${fields.second.toString().padLeft(2, '0')}';
  String get label => '${date}T$time';
}

void _validateRegionName(String zoneId) {
  if (zoneId.length > 100 || !RegExp(r'^[A-Za-z][A-Za-z0-9_+.-]*(/[A-Za-z0-9_+.-]+)*$').hasMatch(zoneId)) {
    throw const FormatException('Expected an explicit regional time-zone ID.');
  }
  // Membership in the regional database is checked by the native resolver.
}

enum CivilResolutionStatus { unique, gap, overlap }

class CivilUtcCandidate {
  CivilUtcCandidate({required this.instantUtc, required this.offsetSeconds}) {
    if (!instantUtc.isUtc || instantUtc.millisecond != 0 || instantUtc.microsecond != 0 ||
        offsetSeconds.abs() > 18 * 3600) {
      throw const FormatException('Invalid whole-second UTC candidate.');
    }
  }

  final DateTime instantUtc;
  final int offsetSeconds;

  Map<String, Object?> toJson() => {
    'instant_utc': instantUtc.toIso8601String(),
    'utc_offset_seconds': offsetSeconds,
  };
}

/// No time-zone gap is shifted and no repeated clock time is chosen here.
class CivilTimeResolution {
  CivilTimeResolution({
    required this.zoneId,
    required this.local,
    required this.status,
    required List<CivilUtcCandidate> candidates,
    required this.tzdbVersion,
  }) : candidates = List.unmodifiable(candidates) {
    _validateRegionName(zoneId);
    if (tzdbVersion != null && (tzdbVersion!.isEmpty || tzdbVersion!.length > 80)) {
      throw const FormatException('Invalid regional-rule version metadata.');
    }
    final expected = switch (status) {
      CivilResolutionStatus.gap => 0,
      CivilResolutionStatus.unique => 1,
      CivilResolutionStatus.overlap => 2,
    };
    if (candidates.length != expected) {
      throw const FormatException('Clock status and UTC candidate count differ.');
    }
    for (var index = 0; index < candidates.length; index++) {
      final candidate = candidates[index];
      if (candidate.instantUtc.add(Duration(seconds: candidate.offsetSeconds)) != local.fields ||
          (index > 0 && !candidate.instantUtc.isAfter(candidates[index - 1].instantUtc))) {
        throw const FormatException('UTC candidate does not reproduce the requested civil clock.');
      }
    }
  }

  final String zoneId;
  final CivilClockTime local;
  final CivilResolutionStatus status;
  final List<CivilUtcCandidate> candidates;
  final String? tzdbVersion;

  CivilUtcCandidate requireUnique() {
    if (status != CivilResolutionStatus.unique) throw CivilClockSelectionRequired(this);
    return candidates.single;
  }

  /// The caller must supply an actual returned candidate's UTC identity.
  /// A gap has no candidate and cannot be repaired by selecting an offset.
  CivilUtcCandidate choose(DateTime explicitUtc) {
    if (!explicitUtc.isUtc) throw const FormatException('Selection must be an explicit UTC instant.');
    for (final candidate in candidates) {
      if (candidate.instantUtc == explicitUtc) return candidate;
    }
    throw const FormatException('Selection is not a returned UTC candidate.');
  }
}

class CivilClockSelectionRequired implements Exception {
  const CivilClockSelectionRequired(this.resolution);
  final CivilTimeResolution resolution;
  @override
  String toString() => 'Civil clock requires an explicit valid time selection.';
}

class RegionalInstant {
  RegionalInstant({
    required this.zoneId,
    required this.local,
    required this.candidate,
    required this.tzdbVersion,
  }) {
    // Share the arithmetic and metadata checks with a unique resolution.
    CivilTimeResolution(zoneId: zoneId, local: local, status: CivilResolutionStatus.unique,
      candidates: [candidate], tzdbVersion: tzdbVersion);
  }
  final String zoneId;
  final CivilClockTime local;
  final CivilUtcCandidate candidate;
  final String? tzdbVersion;
}

abstract class RegionalTimeResolver {
  String get source;
  Future<CivilTimeResolution> resolveLocal({required String zoneId, required CivilClockTime local});
  Future<RegionalInstant> formatInstant({required String zoneId, required DateTime instantUtc});
}

/// Android API 26+ regional rules. Unavailable/invalid responses fail closed;
/// the host's local zone and a fixed JST offset are never a fallback.
class AndroidRegionalTimeResolver implements RegionalTimeResolver {
  const AndroidRegionalTimeResolver({this.channel = const MethodChannel(channelName)});
  static const channelName = 'com.pancyo.aiastrology/civil_time';
  final MethodChannel channel;
  @override
  String get source => 'android-java-time-zone-rules';

  @override
  Future<CivilTimeResolution> resolveLocal({required String zoneId, required CivilClockTime local}) async {
    _validateRegionName(zoneId);
    final response = _map(await channel.invokeMethod<Object?>('resolveLocal', {
      'zoneId': zoneId, 'localDate': local.date, 'localTime': local.time,
    }));
    final rows = response['candidates'];
    if (response['zoneId'] != zoneId || response['localDateTime'] != local.label || rows is! List) {
      throw const FormatException('Regional resolver did not echo the requested civil clock.');
    }
    final status = switch (response['status']) {
      'unique' => CivilResolutionStatus.unique,
      'gap' => CivilResolutionStatus.gap,
      'overlap' => CivilResolutionStatus.overlap,
      _ => throw const FormatException('Unknown regional clock status.'),
    };
    return CivilTimeResolution(zoneId: zoneId, local: local, status: status,
      candidates: [for (final row in rows) _candidate(_map(row))],
      tzdbVersion: _version(response['tzdbVersion']));
  }

  @override
  Future<RegionalInstant> formatInstant({required String zoneId, required DateTime instantUtc}) async {
    _validateRegionName(zoneId);
    final requested = CivilUtcCandidate(instantUtc: instantUtc, offsetSeconds: 0);
    final response = _map(await channel.invokeMethod<Object?>('formatInstant', {
      'zoneId': zoneId, 'instantUtc': requested.instantUtc.toIso8601String(),
    }));
    final localLabel = response['localDateTime'];
    if (response['zoneId'] != zoneId || localLabel is! String || localLabel.length != 19 || localLabel[10] != 'T') {
      throw const FormatException('Invalid regional instant response.');
    }
    final candidate = _candidate(response);
    if (candidate.instantUtc != instantUtc) {
      throw const FormatException('Regional formatting changed the requested instant.');
    }
    return RegionalInstant(zoneId: zoneId,
      local: CivilClockTime.parse(localLabel.substring(0, 10), localLabel.substring(11)),
      candidate: candidate, tzdbVersion: _version(response['tzdbVersion']));
  }

  static Map<Object?, Object?> _map(Object? value) {
    if (value is! Map) throw const FormatException('Expected a regional resolver map.');
    return Map<Object?, Object?>.from(value);
  }
  static String? _version(Object? value) {
    if (value == null || value is String) return value as String?;
    throw const FormatException('Invalid regional-rule version type.');
  }
  static CivilUtcCandidate _candidate(Map<Object?, Object?> row) {
    final iso = row['instantUtc'];
    final offset = row['offsetSeconds'];
    if (iso is! String || !iso.endsWith('Z') || offset is! int) {
      throw const FormatException('Invalid UTC candidate types.');
    }
    final match = RegExp(r'^([0-9]{4}|\+[0-9]{5,6})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})(?:\.0{1,9})?Z$').firstMatch(iso);
    if (match == null) throw const FormatException('Expected a whole-second UTC ISO instant.');
    final fields = [for (var group = 1; group <= 6; group++) int.parse(match.group(group)!)];
    final instant = DateTime.tryParse(iso);
    if (instant == null || !instant.isUtc || fields[0] > 10000 ||
        instant.year != fields[0] || instant.month != fields[1] || instant.day != fields[2] ||
        instant.hour != fields[3] || instant.minute != fields[4] || instant.second != fields[5]) {
      throw const FormatException('Invalid UTC candidate calendar or clock.');
    }
    return CivilUtcCandidate(instantUtc: instant, offsetSeconds: offset);
  }
}

class RegionalDailyTimepoint {
  const RegionalDailyTimepoint({required this.civilHour, required this.resolution});
  final int civilHour;
  final CivilTimeResolution resolution;
  CivilUtcCandidate get candidate => resolution.requireUnique();
  bool get isDayEndBoundary => civilHour == 24;
  Map<String, Object?> toJson() => {
    'civil_hour': civilHour,
    'display_time': '${civilHour.toString().padLeft(2, '0')}:00',
    'local_date_time': resolution.local.label,
    ...candidate.toJson(),
    'role': isDayEndBoundary ? 'day_end_boundary' : 'day_sample',
    'inside_day_interval': !isDayEndBoundary,
    'is_daily_primary_reference': civilHour == 12,
  };
}

/// An independent clock plan, not a replacement for the active fixed-JST v4.
/// Every wall-clock sample is resolved separately: a civil day can be 23/25h.
class RegionalDailyTimepointPlan {
  RegionalDailyTimepointPlan._(this.zoneId, this.targetDate, this.resolverSource,
    this.tzdbVersion, List<RegionalDailyTimepoint> points) : points = List.unmodifiable(points);

  static const sampleHours = [0, 4, 8, 12, 16, 20, 24];
  static Future<RegionalDailyTimepointPlan> build({
    required String zoneId,
    required String targetDate,
    required RegionalTimeResolver resolver,
  }) async {
    _validateRegionName(zoneId);
    final midnight = CivilClockTime.parse(targetDate, '00:00:00');
    final source = resolver.source;
    if (source.isEmpty) throw const FormatException('Regional resolver source is required.');
    // Reject a calendar boundary unsupported by this independent contract
    // before making any platform calls or assembling partial evidence.
    final localSamples = <CivilClockTime>[];
    for (final hour in sampleHours) {
      final fields = midnight.fields.add(Duration(hours: hour));
      final date = '${fields.year.toString().padLeft(4, '0')}-'
        '${fields.month.toString().padLeft(2, '0')}-${fields.day.toString().padLeft(2, '0')}';
      localSamples.add(CivilClockTime.parse(date, '${fields.hour.toString().padLeft(2, '0')}:00:00'));
    }
    final points = <RegionalDailyTimepoint>[];
    String? version;
    for (var index = 0; index < sampleHours.length; index++) {
      final hour = sampleHours[index];
      final local = localSamples[index];
      final resolution = await resolver.resolveLocal(zoneId: zoneId, local: local);
      if (resolution.zoneId != zoneId || resolution.local.label != local.label ||
          resolver.source != source || (points.isNotEmpty && resolution.tzdbVersion != version)) {
        throw const FormatException('Regional day clock or rule source changed.');
      }
      final candidate = resolution.requireUnique();
      if (points.isNotEmpty && !candidate.instantUtc.isAfter(points.last.candidate.instantUtc)) {
        throw const FormatException('Regional day samples are not strictly ordered.');
      }
      version = resolution.tzdbVersion;
      points.add(RegionalDailyTimepoint(civilHour: hour, resolution: resolution));
    }
    return RegionalDailyTimepointPlan._(zoneId, targetDate, source, version, points);
  }

  final String zoneId, targetDate, resolverSource;
  final String? tzdbVersion;
  final List<RegionalDailyTimepoint> points;
  DateTime get dayStartUtc => points.first.candidate.instantUtc;
  DateTime get dayEndUtc => points.last.candidate.instantUtc;
  DateTime get primaryNoonUtc => points[3].candidate.instantUtc;
  bool containsInstant(DateTime instantUtc) {
    if (!instantUtc.isUtc) throw const FormatException('Expected an explicit UTC instant.');
    return !instantUtc.isBefore(dayStartUtc) && instantUtc.isBefore(dayEndUtc);
  }
  Map<String, Object?> toJson() => {
    'artifact_type': 'pancyo_regional_daily_clock_experiment_v1',
    'active_runtime_model': false,
    'contains_predictions': false,
    'time_zone': zoneId,
    'target_local_date': targetDate,
    'time_zone_source': resolverSource,
    'tzdb_version': tzdbVersion,
    'day_interval': {
      'start_utc': dayStartUtc.toIso8601String(), 'end_utc': dayEndUtc.toIso8601String(),
      'start_inclusive': true, 'end_inclusive': false,
      'elapsed_seconds': dayEndUtc.difference(dayStartUtc).inSeconds,
    },
    'primary_reference_utc': primaryNoonUtc.toIso8601String(),
    'points': [for (final point in points) point.toJson()],
  };
}
