import 'dart:convert';

import 'civil_time.dart';

enum BirthClockSelectionKind {
  uniqueRule('unique_rule'),
  explicitOverlapChoice('explicit_overlap_choice');

  const BirthClockSelectionKind(this.code);
  final String code;
}

/// An immutable, resolved birth-clock identity. This class never reads the host
/// zone, calls a platform resolver, chooses an overlap, or changes a saved UTC.
/// Region membership comes from the resolver that produced [CivilTimeResolution];
/// this data contract validates its syntax and arithmetic, not an invented TZDB.
class ResolvedBirthClock {
  ResolvedBirthClock._(this._resolution, this.candidate, this.resolverSource);

  static const schema = 'pancyo_resolved_birth_clock_v1';
  static const _keys = {
    'schema',
    'local_date',
    'local_time',
    'time_zone',
    'instant_utc',
    'utc_offset_seconds',
    'resolution_status',
    'selection_kind',
    'resolver_source',
    'tzdb_version',
    'candidates',
  };
  static const _candidateKeys = {'instant_utc', 'utc_offset_seconds'};

  factory ResolvedBirthClock.fromResolution({
    required CivilTimeResolution resolution,
    required String resolverSource,
    DateTime? explicitUtc,
  }) {
    _validateSource(resolverSource);
    _validateVersion(resolution.tzdbVersion);
    // Revalidate and copy the complete candidate set rather than trusting a
    // mutable caller collection or retaining only its chosen row.
    final frozen = CivilTimeResolution(
      zoneId: resolution.zoneId,
      local: resolution.local,
      status: resolution.status,
      candidates: [
        for (final row in resolution.candidates)
          CivilUtcCandidate(
            instantUtc: row.instantUtc,
            offsetSeconds: row.offsetSeconds,
          ),
      ],
      tzdbVersion: resolution.tzdbVersion,
    );
    if (frozen.status == CivilResolutionStatus.gap ||
        (frozen.status == CivilResolutionStatus.overlap &&
            explicitUtc == null)) {
      throw CivilClockSelectionRequired(frozen);
    }
    final chosen = explicitUtc == null
        ? frozen.requireUnique()
        : frozen.choose(explicitUtc);
    return ResolvedBirthClock._(frozen, chosen, resolverSource);
  }

  /// Decode only this class's exact persistence format. Canonical UTC seconds
  /// ensure invalid/overflowing dates and subsecond truncation cannot normalize
  /// silently. No regional re-resolution takes place after a TZDB update.
  factory ResolvedBirthClock.fromJson(Object? value) {
    final map = _map(value, _keys);
    if (map['schema'] != schema) {
      throw const FormatException('Unknown resolved birth-clock schema.');
    }
    final local = CivilClockTime.parse(
      _string(map['local_date']),
      _string(map['local_time']),
    );
    final status = switch (map['resolution_status']) {
      'unique' => CivilResolutionStatus.unique,
      'overlap' => CivilResolutionStatus.overlap,
      _ => throw const FormatException('A saved birth clock must be resolved.'),
    };
    final version = map['tzdb_version'];
    if (version != null && version is! String) {
      throw const FormatException('Invalid birth-clock rule version type.');
    }
    final rows = map['candidates'];
    if (rows is! List) {
      throw const FormatException('Birth-clock candidates must be a list.');
    }
    final resolution = CivilTimeResolution(
      zoneId: _string(map['time_zone']),
      local: local,
      status: status,
      candidates: [for (final row in rows) _candidate(row)],
      tzdbVersion: version as String?,
    );
    final selected = _candidate({
      'instant_utc': map['instant_utc'],
      'utc_offset_seconds': map['utc_offset_seconds'],
    });
    final decoded = ResolvedBirthClock.fromResolution(
      resolution: resolution,
      resolverSource: _string(map['resolver_source']),
      explicitUtc: selected.instantUtc,
    );
    if (selected.offsetSeconds != decoded.offsetSeconds ||
        map['selection_kind'] != decoded.selectionKind.code) {
      throw const FormatException('Saved birth-clock selection differs.');
    }
    return decoded;
  }

  final CivilTimeResolution _resolution;
  final CivilUtcCandidate candidate;
  final String resolverSource;

  CivilClockTime get local => _resolution.local;
  String get zoneId => _resolution.zoneId;
  DateTime get instantUtc => candidate.instantUtc;
  int get offsetSeconds => candidate.offsetSeconds;
  CivilResolutionStatus get resolutionStatus => _resolution.status;
  String? get tzdbVersion => _resolution.tzdbVersion;
  List<CivilUtcCandidate> get candidates => _resolution.candidates;
  BirthClockSelectionKind get selectionKind =>
      resolutionStatus == CivilResolutionStatus.unique
      ? BirthClockSelectionKind.uniqueRule
      : BirthClockSelectionKind.explicitOverlapChoice;

  /// Private in-memory cache identity, including source and selection evidence.
  /// It contains birth information and must not be included in diagnostic logs.
  String get cacheIdentity => jsonEncode(toJson());

  Map<String, Object?> toJson() => {
    'schema': schema,
    'local_date': local.date,
    'local_time': local.time,
    'time_zone': zoneId,
    'instant_utc': instantUtc.toIso8601String(),
    'utc_offset_seconds': offsetSeconds,
    'resolution_status': resolutionStatus.name,
    'selection_kind': selectionKind.code,
    'resolver_source': resolverSource,
    'tzdb_version': tzdbVersion,
    'candidates': [for (final row in candidates) row.toJson()],
  };

  static Map<Object?, Object?> _map(Object? value, Set<String> keys) {
    if (value is! Map ||
        value.length != keys.length ||
        value.keys.any((key) => key is! String || !keys.contains(key))) {
      throw const FormatException('Unexpected resolved birth-clock fields.');
    }
    return Map<Object?, Object?>.from(value);
  }

  static String _string(Object? value) {
    if (value is! String) {
      throw const FormatException('Expected a birth-clock string.');
    }
    return value;
  }

  static CivilUtcCandidate _candidate(Object? value) {
    final row = _map(value, _candidateKeys);
    final text = _string(row['instant_utc']);
    final offset = row['utc_offset_seconds'];
    final instant = DateTime.tryParse(text);
    if (offset is! int ||
        instant == null ||
        !instant.isUtc ||
        instant.millisecond != 0 ||
        instant.microsecond != 0 ||
        instant.toIso8601String() != text) {
      throw const FormatException(
        'Expected canonical whole-second UTC and offset.',
      );
    }
    return CivilUtcCandidate(instantUtc: instant, offsetSeconds: offset);
  }

  static void _validateSource(String source) {
    if (!RegExp(r'^[A-Za-z][A-Za-z0-9_.:/+\-]{0,119}$').hasMatch(source)) {
      throw const FormatException('Invalid birth-clock resolver source.');
    }
  }

  static void _validateVersion(String? version) {
    if (version != null &&
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.:+\-]{0,79}$').hasMatch(version)) {
      throw const FormatException('Invalid birth-clock rule version.');
    }
  }
}
