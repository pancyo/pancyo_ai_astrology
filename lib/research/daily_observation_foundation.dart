import 'dart:convert';

/// A private, daily research attachment. This joins normalized evidence by date;
/// it never calculates scores, infers outcomes, or registers old predictions.
class DailyObservationFoundation {
  const DailyObservationFoundation._();

  static const schema = 'pancyo_private_daily_observation_foundation_v1';
  static const sections = <String>[
    'numeric_forecast',
    'fixed_text_forecast',
    'direct_events',
    'direct_felt',
    'self_hit_judgement',
    'chappy_judgement',
  ];
  static const areaKeys = <String>{
    'overall',
    'love',
    'work',
    'money',
    'mental',
    'health',
    'people',
    'actionDecision',
    'felt',
  };
  static const _observationStates = <String>{
    'observed',
    'explicit_no_event',
    'missing',
    'external_unassessable',
  };
  static const _temporalStatuses = <String>{
    'retrospective_reconstructed',
    'fixed_prospective',
    'unverified',
  };
  static const _offset = Duration(hours: 9);

  /// [sources] contain opaque IDs, hashes and quality, never original diaries,
  /// birth data, URLs or local paths. Reported facts may retain private text;
  /// the caller minimizes that text and retains the raw files separately.
  /// Known fields are allowlisted at every level. This is data minimization,
  /// not a proof that allowed free text has been anonymized.
  ///
  /// Malformed/unknown fields, duplicate dates and invalid dates are rejected.
  /// Chronology/source coverage conflicts are retained as issues and put the
  /// whole day on hold. Original entries and declared quality remain unchanged.
  static Map<String, Object?> build({
    required String participantId,
    required List<Map<String, dynamic>> records,
    required List<Map<String, dynamic>> sources,
    required DateTime generatedAt,
  }) {
    _id(participantId, 'participant_id');
    if (!generatedAt.isUtc) {
      throw const FormatException('generatedAt must explicitly be UTC');
    }
    final sourceById = <String, Map<String, dynamic>>{};
    for (final raw in sources) {
      final source = _copy(raw);
      _keys(source, {
        'source_id',
        'sha256',
        'kind',
        'observation_period',
        'quality',
      }, 'source');
      final id = _id(source['source_id'], 'source_id');
      if (sourceById.containsKey(id)) {
        throw const FormatException('Duplicate source_id');
      }
      if (source['sha256'] is! String ||
          !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(source['sha256'] as String)) {
        throw const FormatException('Source SHA256 is required');
      }
      _id(source['kind'], 'source kind');
      final period = _map(source['observation_period'], 'observation_period');
      _keys(period, {'start_date_jst', 'end_date_jst'}, 'observation_period');
      final start = _day(period['start_date_jst']);
      final end = _day(period['end_date_jst']);
      if (end.isBefore(start)) {
        throw const FormatException('Reversed source observation period');
      }
      final quality = _map(source['quality'], 'source quality');
      _keys(quality, {'status', 'limitations'}, 'source quality');
      _id(quality['status'], 'quality status');
      _strings(quality['limitations'], 'quality limitations');
      sourceById[id] = source;
    }

    final days = <Map<String, Object?>>[];
    final seenDays = <String>{};
    final entryCounts = {for (final section in sections) section: 0};
    var heldDays = 0;
    var assessableHitValues = 0;
    var unassessableHitValues = 0;
    var unansweredValues = 0;
    for (final raw in records) {
      final row = _copy(raw);
      _keys(row, {
        'target_date_jst',
        'source_refs',
        'quality',
        'conflicts',
        ...sections,
      }, 'day');
      final day = _day(row['target_date_jst']);
      final date = row['target_date_jst'] as String;
      if (!seenDays.add(date)) {
        throw const FormatException('Duplicate participant/date');
      }
      final quality = _map(row['quality'], 'day quality');
      _keys(quality, {'eligible', 'exclusion_reasons'}, 'day quality');
      if (quality['eligible'] is! bool) {
        throw const FormatException('Day eligibility must be explicit');
      }
      final declaredReasons = _strings(
        quality['exclusion_reasons'],
        'day exclusion reasons',
      );
      if (quality['eligible'] == false && declaredReasons.isEmpty) {
        throw const FormatException('Excluded days require a reason');
      }
      if (quality['eligible'] == true && declaredReasons.isNotEmpty) {
        throw const FormatException('Eligible day has exclusion reasons');
      }
      final conflicts = row.containsKey('conflicts')
          ? _strings(row['conflicts'], 'conflicts')
          : <String>[];
      final issues = <String>{};
      final refs = <String>{};
      final dayStart = day.subtract(_offset);
      final dayEnd = dayStart.add(const Duration(days: 1));
      if (dayEnd.isAfter(generatedAt)) {
        issues.add('target_day_not_complete_at_generation');
      }
      if (conflicts.isNotEmpty) issues.add('declared_source_conflicts');

      void reference(Object? value) {
        final id = _id(value, 'entry source_id');
        final source = sourceById[id];
        if (source == null) throw const FormatException('Unknown source_id');
        refs.add(id);
        final period = source['observation_period'] as Map;
        if (day.isBefore(_day(period['start_date_jst'])) ||
            day.isAfter(_day(period['end_date_jst']))) {
          issues.add('source_period_does_not_cover_day');
        }
      }

      if (row.containsKey('source_refs')) {
        for (final id in _strings(row['source_refs'], 'source_refs')) {
          reference(id);
        }
      }
      final normalizedSections = <String, Object?>{};
      final observedFeltValues = <String>{};
      for (final section in sections) {
        final values = row.containsKey(section) ? row[section] : <dynamic>[];
        if (values is! List) throw FormatException('$section must be a list');
        final entries = <Map<String, dynamic>>[];
        for (final value in values) {
          final entry = _map(value, section);
          reference(entry['source_id']);
          if (section == 'numeric_forecast' ||
              section == 'fixed_text_forecast') {
            _forecast(
              entry,
              numeric: section == 'numeric_forecast',
              day: day,
              generatedAt: generatedAt,
              issues: issues,
            );
          } else if (section == 'direct_events' || section == 'direct_felt') {
            _observation(
              entry,
              felt: section == 'direct_felt',
              dayStart: dayStart,
              generatedAt: generatedAt,
              issues: issues,
            );
            if (section == 'direct_felt' &&
                entry['observation_state'] == 'observed') {
              observedFeltValues.add(entry['value'] as String);
            }
          } else {
            _judgement(
              entry,
              generatedAt: generatedAt,
              dayEnd: dayEnd,
              issues: issues,
            );
            for (final value in (entry['values'] as Map).values) {
              if (value == null || value == '') {
                unansweredValues++;
              } else if (entry['scale'] == 'hit_0_to_3') {
                if (value == 0) {
                  unassessableHitValues++;
                } else {
                  assessableHitValues++;
                }
              }
            }
          }
          entries.add(entry);
        }
        normalizedSections[section] = entries;
        entryCounts[section] = entryCounts[section]! + entries.length;
      }
      if (observedFeltValues.length > 1)
        issues.add('conflicting_direct_felt_values');
      if (refs.isEmpty) issues.add('no_source_evidence');
      if (normalizedSections.values.every(
        (values) => (values as List).isEmpty,
      )) {
        issues.add('no_day_observation_or_forecast_entries');
      }
      final eligible = quality['eligible'] == true && issues.isEmpty;
      if (!eligible) heldDays++;
      days.add({
        'target_date_jst': date,
        'source_refs': refs.toList()..sort(),
        'section_presence': {
          for (final section in sections) section: row.containsKey(section),
        },
        ...normalizedSections,
        'quality': quality,
        'conflicts': conflicts,
        'issues': issues.toList()..sort(),
        'effective_eligibility': {
          'eligible': eligible,
          'status': eligible
              ? 'available_for_separate_research_review'
              : 'hold',
          'exclusion_reasons': <String>{...declaredReasons, ...issues}.toList()
            ..sort(),
        },
      });
    }
    days.sort(
      (a, b) => (a['target_date_jst'] as String).compareTo(
        b['target_date_jst'] as String,
      ),
    );
    return {
      'schema': schema,
      'purpose':
          'private_daily_evidence_join_not_prediction_accuracy_validation',
      'generated_at_utc': generatedAt.toIso8601String(),
      'participant_id': participantId,
      'time_zone': 'Asia/Tokyo',
      'fixed_utc_offset': '+09:00',
      'contracts': {
        'daily_reference': '12:00_JST_existing_daily_forecast',
        'daily_scores_averaged_from_samples': false,
        'intraday_analysis_added': false,
        'missing_is_zero': false,
        'observation_scales_converted': false,
        'hit_zero_meaning': 'unassessable_not_wrong_or_missing',
        'unanswered_meaning': 'null_or_empty_string_preserved',
        'prospective_status_inferred_or_upgraded': false,
        'declared_prospective_status_is_independently_proven': false,
        'scores_coefficients_models_changed': false,
        'comparison_candidates_are_primary': false,
        'research_numeric_band_contract': 'numeric-band-research-v1',
        'research_numeric_bands': {
          'low': '50-65',
          'mid': '66-79',
          'high': '80-99',
        },
        'normal_display_thresholds_replaced': false,
        'missing_evidence_state_inferred': false,
        'hit_rate_computed': false,
        'privacy': 'allowlisted_normalized_fields_not_anonymization_proof',
      },
      'summary': {
        'participant_count': 1,
        'day_count': days.length,
        'day_count_is_independent_participant_count': false,
        'days_available_for_separate_research_review': days.length - heldDays,
        'held_days': heldDays,
        'days_with_issues': days
            .where((day) => (day['issues'] as List).isNotEmpty)
            .length,
        'section_entry_counts': entryCounts,
        'recorded_assessable_hit_values_not_accuracy': assessableHitValues,
        'recorded_unassessable_hit_values': unassessableHitValues,
        'recorded_unanswered_judgement_values': unansweredValues,
      },
      'sources': sourceById.values.toList(),
      'records': days,
    };
  }

  static void _forecast(
    Map<String, dynamic> entry, {
    required bool numeric,
    required DateTime day,
    required DateTime generatedAt,
    required Set<String> issues,
  }) {
    _keys(
      entry,
      numeric
          ? {
              'source_id',
              'temporal_status',
              'model_version',
              'calculation_reference_jst',
              'issued_at_jst',
              'registered_at_jst',
              'values',
              'primary_felt_label',
              'role',
              'evidence_state',
            }
          : {
              'source_id',
              'temporal_status',
              'version',
              'issued_at_jst',
              'registered_at_jst',
              'values',
            },
      'forecast',
    );
    if (!_temporalStatuses.contains(entry['temporal_status'])) {
      throw const FormatException('Unknown forecast temporal status');
    }
    _text(entry[numeric ? 'model_version' : 'version'], 'forecast version');
    final issued = _optionalTimestamp(entry['issued_at_jst']);
    final registered = _optionalTimestamp(entry['registered_at_jst']);
    if (issued != null && issued.isAfter(generatedAt) ||
        registered != null && registered.isAfter(generatedAt)) {
      issues.add('forecast_timestamp_after_generation');
    }
    if (issued != null && registered != null && issued.isAfter(registered)) {
      issues.add('forecast_issue_after_registration');
    }
    if (entry['temporal_status'] == 'fixed_prospective') {
      final start = day.subtract(_offset);
      if (issued == null && registered == null)
        issues.add('prospective_timing_unverified');
      if (issued != null && !issued.isBefore(start) ||
          registered != null && !registered.isBefore(start)) {
        issues.add('prospective_timestamp_not_before_day');
      }
    }
    final values = _map(entry['values'], 'forecast values');
    _keys(values, areaKeys, 'forecast area');
    if (numeric) {
      if (!{'primary', 'comparison_only'}.contains(entry['role'])) {
        throw const FormatException('Numeric forecast role must be explicit');
      }
      if (entry.containsKey('evidence_state') &&
          !{
            'missing_inputs',
            'eligible_aspects_present',
            'no_eligible_lunar_aspects',
            'unknown',
          }.contains(entry['evidence_state'])) {
        throw const FormatException('Unknown recorded lunar evidence state');
      }
      final reference = _optionalTimestamp(entry['calculation_reference_jst']);
      if (reference == null || reference != day.add(const Duration(hours: 3))) {
        issues.add('numeric_reference_not_daily_noon');
      }
      if (entry['primary_felt_label'] != null) {
        _text(entry['primary_felt_label'], 'forecast felt label');
      }
      for (final field in values.entries) {
        if (field.key == 'felt') {
          if (field.value != null)
            throw const FormatException('Felt cannot have a numeric score');
        } else if (field.value != null &&
            (field.value is! int ||
                (field.value as int) < 50 ||
                (field.value as int) > 99)) {
          throw const FormatException(
            'Numeric forecast must preserve an integer score 50..99 or null',
          );
        }
      }
    } else {
      for (final value in values.values) {
        final text = _map(value, 'fixed text area');
        _keys(text, {'prediction', 'advice'}, 'fixed text area');
        _text(text['prediction'], 'fixed prediction');
        if (text.containsKey('advice') && text['advice'] != null) {
          _text(text['advice'], 'fixed advice', allowEmpty: true);
        }
      }
    }
  }

  static void _observation(
    Map<String, dynamic> entry, {
    required bool felt,
    required DateTime dayStart,
    required DateTime generatedAt,
    required Set<String> issues,
  }) {
    _keys(entry, {
      'source_id',
      'observation_state',
      'value',
      'eligible',
      'exclusion_reasons',
      'recorded_at_jst',
    }, 'observation');
    if (!_observationStates.contains(entry['observation_state']) ||
        entry['eligible'] is! bool) {
      throw const FormatException(
        'Explicit observation state and eligibility are required',
      );
    }
    final reasons = _strings(
      entry['exclusion_reasons'],
      'observation exclusion reasons',
    );
    if (entry['eligible'] == false && reasons.isEmpty ||
        entry['eligible'] == true && reasons.isNotEmpty) {
      throw const FormatException(
        'Observation eligibility and reasons disagree',
      );
    }
    if (entry['observation_state'] == 'observed') {
      if (felt) {
        _text(entry['value'], 'direct felt');
      } else {
        final facts = _map(entry['value'], 'direct event value');
        _keys(facts, {
          'event_tags',
          'documented_domains',
          'progress',
          'friction',
          'reported_facts',
        }, 'direct event value');
        for (final key in ['event_tags', 'documented_domains']) {
          if (facts.containsKey(key)) _strings(facts[key], key);
        }
        for (final key in ['progress', 'friction']) {
          if (facts[key] != null && facts[key] is! bool) {
            throw const FormatException(
              'Progress/friction must be bool or null',
            );
          }
        }
        if (facts.containsKey('reported_facts')) {
          final reported = facts['reported_facts'];
          if (reported is! List) {
            throw const FormatException('reported_facts must be a list');
          }
          for (final value in reported) {
            final fact = _map(value, 'reported fact');
            _keys(fact, {'text', 'domains', 'evidence_type'}, 'reported fact');
            _text(fact['text'], 'reported fact text');
            _strings(fact['domains'], 'reported fact domains');
            _text(fact['evidence_type'], 'reported fact evidence type');
          }
        }
        if (facts.isEmpty ||
            facts.values.every((v) => v == null || v is List && v.isEmpty)) {
          throw const FormatException(
            'Observed events need documented content',
          );
        }
      }
    } else if (entry['value'] != null) {
      throw const FormatException(
        'Non-observed states must not carry an outcome value',
      );
    }
    if (entry['observation_state'] == 'missing' ||
        entry['observation_state'] == 'external_unassessable') {
      if (entry['eligible'] == true) {
        throw const FormatException(
          'Missing/unassessable observations cannot be eligible',
        );
      }
    }
    final recorded = _optionalTimestamp(entry['recorded_at_jst']);
    if (recorded != null &&
        (recorded.isBefore(dayStart) || recorded.isAfter(generatedAt))) {
      issues.add('observation_timestamp_outside_recording_window');
    }
  }

  static void _judgement(
    Map<String, dynamic> entry, {
    required DateTime generatedAt,
    required DateTime dayEnd,
    required Set<String> issues,
  }) {
    _keys(entry, {
      'source_id',
      'scale',
      'values',
      'recorded_at_jst',
    }, 'judgement');
    final scale = entry['scale'];
    if (!{'hit_0_to_3', 'direct_rating_1_to_5', 'textual'}.contains(scale)) {
      throw const FormatException('Judgement scale must be explicit');
    }
    final values = _map(entry['values'], 'judgement values');
    _keys(values, areaKeys, 'judgement area');
    for (final value in values.values) {
      if (value == null || value == '') continue;
      if (scale == 'textual') {
        _text(value, 'textual judgement');
      } else if (value is! int ||
          value < (scale == 'hit_0_to_3' ? 0 : 1) ||
          value > (scale == 'hit_0_to_3' ? 3 : 5)) {
        throw const FormatException(
          'Judgement value does not match its recorded scale',
        );
      }
    }
    final recorded = _optionalTimestamp(entry['recorded_at_jst']);
    if (recorded != null &&
        (recorded.isBefore(dayEnd) || recorded.isAfter(generatedAt))) {
      issues.add('judgement_timestamp_outside_completed_day_window');
    }
  }

  static Map<String, dynamic> _copy(Map<String, dynamic> input) {
    try {
      return _map(jsonDecode(jsonEncode(input)), 'JSON record');
    } on JsonUnsupportedObjectError {
      throw const FormatException('Only finite JSON data is accepted');
    }
  }

  static Map<String, dynamic> _map(Object? value, String field) {
    if (value is! Map || value.keys.any((key) => key is! String)) {
      throw FormatException('$field must be an object');
    }
    return Map<String, dynamic>.from(value);
  }

  static void _keys(
    Map<String, dynamic> value,
    Set<String> allowed,
    String field,
  ) {
    if (value.keys.any((key) => !allowed.contains(key))) {
      // Do not echo unexpected keys or their possibly identifying values.
      throw FormatException('Unexpected field in $field');
    }
  }

  static String _text(Object? value, String field, {bool allowEmpty = false}) {
    if (value is! String || (!allowEmpty && value.trim().isEmpty)) {
      throw FormatException('$field must be a string');
    }
    return value;
  }

  static String _id(Object? value, String field) {
    final text = _text(value, field);
    if (!RegExp(r'^[a-z][a-z0-9_-]{0,95}$').hasMatch(text)) {
      throw FormatException('$field must be an opaque lowercase ID');
    }
    return text;
  }

  static List<String> _strings(Object? value, String field) {
    if (value is! List || value.any((v) => v is! String || v.trim().isEmpty)) {
      throw FormatException('$field must be a list of nonempty strings');
    }
    return List<String>.from(value);
  }

  static DateTime _day(Object? value) {
    if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      throw const FormatException('Expected a JST calendar date YYYY-MM-DD');
    }
    final year = int.parse(value.substring(0, 4));
    final month = int.parse(value.substring(5, 7));
    final day = int.parse(value.substring(8, 10));
    final result = DateTime.utc(year, month, day);
    if (year < 1 ||
        result.year != year ||
        result.month != month ||
        result.day != day) {
      throw const FormatException('Invalid calendar date');
    }
    return result;
  }

  static DateTime? _optionalTimestamp(Object? value) {
    if (value == null) return null;
    if (value is! String ||
        !RegExp(
          r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?\+09:00$',
        ).hasMatch(value)) {
      throw const FormatException('Timestamp must explicitly use +09:00');
    }
    _day(value.substring(0, 10));
    final result = DateTime.tryParse(value)?.toUtc();
    if (result == null) throw const FormatException('Invalid timestamp');
    final local = result.add(_offset);
    if (local.hour != int.parse(value.substring(11, 13)) ||
        local.minute != int.parse(value.substring(14, 16)) ||
        local.second != int.parse(value.substring(17, 19))) {
      throw const FormatException('Invalid timestamp clock');
    }
    return result;
  }
}
