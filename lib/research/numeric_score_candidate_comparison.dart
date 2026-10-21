import 'dart:convert';

import 'nine_area_general_candidate.dart';
import 'nine_area_model_contract.dart';

/// Frozen structural alternatives, defined without observed personal outcomes.
/// Neither candidate is an adopted general formula or a validated predictor.
class NumericScoreCandidateComparison {
  const NumericScoreCandidateComparison._();

  static const candidateA = 'numeric-direction-material-top3-20261010-1';
  static const candidateB =
      'numeric-all-direction-groups-normalized3-20261010-1';
  static const schema = 'pancyo_research_numeric_score_comparison_v1';
  static const _six = ['love', 'work', 'money', 'mental', 'health', 'people'];
  static const _keys = ['overall', ..._six, 'actionDecision'];
  static const _numericKeys = {'score', 'status', 'score_breakdown'};
  static const _personalAliases = {
    'profile',
    'profiletext',
    'birthdate',
    'birthtime',
    'birthplace',
    'birthday',
    'address',
    'diary',
    'diaryraw',
    'diarytext',
    'diaryrawmarkdown',
    'outcome',
    'outcomes',
    'outcomeinput',
    'observedoutcomes',
    'observedresults',
    'actualresults',
    'actualresult',
    'actualevents',
    'directevents',
    'directfelt',
    'reportedfacts',
    'factualobservations',
    'selfhitjudgement',
    'selfhitjudgment',
    'chappyjudgement',
    'chappyjudgment',
    'chappycompletedjudgement',
    'chappycompletedjudgment',
    'persontodayeventraw',
    'primaryproperties',
  };

  /// Accepts GeneralNineAreaForecast.numeric, including saved numeric v1.
  /// Calendar/source provenance belongs to the enclosing private JSON wrapper.
  static Map<String, Object?> compare({
    required Map<String, Map<String, Object?>> numericAreas,
  }) {
    _checkJson(numericAreas);
    if (numericAreas.length != 8 || !_keys.every(numericAreas.containsKey)) {
      throw const FormatException('eight_distinct_numeric_areas_required');
    }
    final evidence = <String, _AreaEvidence>{};
    for (final key in _keys) {
      final a = numericAreas[key]!;
      if (a.keys.any((key) => !_numericKeys.contains(key)) ||
          !a.containsKey('score') ||
          !a.containsKey('status')) {
        throw const FormatException('numeric_forecast_fields_only');
      }
      evidence[key] = _validateArea(key, a);
    }
    _validateMean(numericAreas, evidence);
    final candidates = <Map<String, Object?>>[];
    for (final version in [candidateA, candidateB]) {
      final areas = <String, Map<String, Object?>>{};
      for (final key in _six) {
        final e = evidence[key]!;
        areas[key] = e.holdReason == null
            ? _calculate(key, numericAreas[key]!, e.groups!, version)
            : _hold(numericAreas[key]!['score'], e.holdReason!);
      }
      final overall = evidence['overall']!;
      final allAvailable = _six.every(
        (key) => areas[key]!['candidate_score'] != null,
      );
      if (overall.holdReason != null || !allAvailable) {
        areas['overall'] = _hold(
          numericAreas['overall']!['score'],
          overall.holdReason ?? 'missing_six_area_candidate_evidence',
        );
      } else {
        final values = {
          for (final key in _six)
            key: (areas[key]!['trace'] as Map)['continuous_score'],
        };
        final average =
            values.values.fold<double>(
              0,
              (sum, value) => sum + _finite(value),
            ) /
            6;
        final score = average.round().clamp(50, 99).toInt();
        final baseline = numericAreas['overall']!['score'] as int;
        areas['overall'] = {
          'baseline_score': baseline,
          'candidate_score': score,
          'score_delta': score - baseline,
          'status': 'candidate_unvalidated',
          'hold_reason': null,
          'trace': {
            'formula':
                'mean_of_six_clamped_continuous_outcome_scores_then_round_once',
            'source_area_continuous_scores': values,
            'continuous_score': average,
            'excluded_areas': ['actionDecision', 'felt'],
            'additional_return_bonus': 0,
          },
        };
      }
      final activity = numericAreas['actionDecision']!;
      areas['actionDecision'] = evidence['actionDecision']!.holdReason == null
          ? {
              'baseline_score': activity['score'],
              'candidate_score': activity['score'],
              'score_delta': 0,
              'status': 'candidate_unvalidated',
              'hold_reason': null,
              'trace': {
                'preserved_from_baseline': true,
                'meaning': 'activity_not_success_or_decision_correctness',
              },
            }
          : _hold(activity['score'], evidence['actionDecision']!.holdReason!);
      candidates.add({
        'candidate_version': version,
        'selection_rule': version == candidateA
            ? 'top3_by_support_plus_tension_then_planet_order'
            : 'all_directional_groups_scaled_by_min_1_3_over_N',
        'status': 'comparison_only_unvalidated',
        'parameter_status': 'research_proposal_not_empirically_fitted',
        'normalization_group_budget': NineAreaCandidateDesign.maximumGroups,
        'group_budget_basis':
            'reused_existing_maximumGroups_not_estimated_from_outcomes',
        'areas': {for (final key in _keys) key: areas[key]},
      });
    }
    return _clone({
      'schema': schema,
      'status': 'comparison_only_unvalidated',
      'baseline_numeric_areas': numericAreas,
      'candidate_versions': [candidateA, candidateB],
      'panel_initial_candidate_version': candidateB,
      'panel_initial_selection_basis':
          'all_directional_groups_preserved_before_evaluation',
      'precision_adoption_status': 'HOLD_unvalidated',
      'observed_outcomes_used': false,
      'empirically_fitted': false,
      'rules_tuned_after_evaluation': false,
      'canonical_numeric_model_replaced': false,
      'canonical_felt_changed': false,
      'canonical_activity_changed': false,
      'special_jupiter_bonus': 0,
      'candidates': candidates,
    });
  }

  static Map<String, Object?> _calculate(
    String key,
    Map<String, Object?> baseline,
    List<_Group> groups,
    String version,
  ) {
    final directional = groups.where((g) => g.support + g.tension > 0).toList();
    final ranked = [...directional]
      ..sort((a, b) {
        final delta = (b.support + b.tension).compareTo(a.support + a.tension);
        return delta != 0 ? delta : a.order.compareTo(b.order);
      });
    final selected = version == candidateA
        ? ranked.take(NineAreaCandidateDesign.maximumGroups).toList()
        : directional;
    final normalization = version == candidateB && directional.length > 3
        ? NineAreaCandidateDesign.maximumGroups / directional.length
        : 1.0;
    final selectedNames = selected.map((g) => g.planet).toSet();
    final sum = selected.fold<double>(0, (sum, g) => sum + g.balance);
    final rawAdjustment =
        NineAreaCandidateDesign.pointScale * sum * normalization;
    final applied = rawAdjustment.clamp(-25.0, 24.0).toDouble();
    final continuous = NineAreaCandidateDesign.base + applied;
    final score = continuous.round().clamp(50, 99).toInt();
    final oldScore = baseline['score'] as int;
    return {
      'baseline_score': oldScore,
      'candidate_score': score,
      'score_delta': score - oldScore,
      'status': 'candidate_unvalidated',
      'hold_reason': null,
      'trace': {
        'area': key,
        'base': NineAreaCandidateDesign.base,
        'point_scale': NineAreaCandidateDesign.pointScale,
        'orb_limit_exclusive': NineAreaCandidateDesign.orbLimit,
        'directional_group_count': directional.length,
        'normalization_factor': normalization,
        'selected_transit_planets': selected.map((g) => g.planet).toList(),
        'baseline_selected_transit_planets':
            (_breakdown(baseline)['design_trace']
                as Map)['selected_transit_planets'],
        'unscaled_balance_sum': sum,
        'unclamped_adjustment': rawAdjustment,
        'adjustment_limits': {'min': -25.0, 'max': 24.0},
        'adjustment': applied,
        'adjustment_clamp_delta': applied - rawAdjustment,
        'continuous_score': continuous,
        'rounding_and_clamp': 'round_once_then_clamp_50_99',
        'groups': [
          for (final g in groups)
            {
              'transit_planet': g.planet,
              'support': g.support,
              'tension': g.tension,
              'balance': g.balance,
              'stimulus': g.stimulus,
              'directional_material': g.support + g.tension,
              'baseline_selected': g.baselineSelected,
              'candidate_selected': selectedNames.contains(g.planet),
              'exclusion_reason': selectedNames.contains(g.planet)
                  ? null
                  : g.support + g.tension == 0
                  ? 'no_directional_material'
                  : 'candidate_top3_limit',
              'candidate_contribution': selectedNames.contains(g.planet)
                  ? g.balance *
                        NineAreaCandidateDesign.pointScale *
                        normalization
                  : 0.0,
            },
        ],
      },
    };
  }

  static _AreaEvidence _validateArea(String key, Map<String, Object?> area) {
    final score = area['score'],
        status = area['status'],
        b = area['score_breakdown'];
    if (status == 'inherited_existing') {
      if (score != null && (score is! int || score < 50 || score > 99)) {
        throw const FormatException('invalid_inherited_baseline_score');
      }
      if (b != null && b is! Map) {
        throw const FormatException('invalid_score_breakdown');
      }
      return const _AreaEvidence.hold(
        'inherited_baseline_not_general_model_evidence',
      );
    }
    if (score == null) {
      if (status != 'not_predicted' || b != null) {
        throw const FormatException('inconsistent_unavailable_numeric_area');
      }
      return const _AreaEvidence.hold('missing_baseline_prediction');
    }
    if (score is! int ||
        score < 50 ||
        score > 99 ||
        status != 'trial_unvalidated') {
      throw const FormatException('invalid_baseline_score_or_status');
    }
    if (b == null) return const _AreaEvidence.hold('missing_score_breakdown');
    if (b is! Map) throw const FormatException('invalid_score_breakdown');
    final breakdown = Map<String, Object?>.from(b);
    NineAreaModelContract.validateNumeric(status as String, score, breakdown);
    final overall = key == 'overall', activity = key == 'actionDecision';
    if (b['calculation_kind'] !=
        (overall
            ? 'general_six_area_mean_v1'
            : activity
            ? 'general_activity_groups_v1'
            : 'general_outcome_groups_v1')) {
      throw const FormatException('unexpected_baseline_calculation_kind');
    }
    if (activity) return const _AreaEvidence.available();
    final d = b['design_trace'];
    if (d == null) return const _AreaEvidence.hold('missing_design_trace');
    if (d is! Map) throw const FormatException('invalid_design_trace');
    if (overall) return const _AreaEvidence.available();
    if (d['groups'] == null || d['factors'] == null) {
      return const _AreaEvidence.hold('missing_full_group_or_factor_evidence');
    }
    return _AreaEvidence.groups(_validateGroups(key, breakdown, d));
  }

  static List<_Group> _validateGroups(
    String key,
    Map<String, Object?> b,
    Map d,
  ) {
    _same(b['base'], NineAreaCandidateDesign.base);
    _same(d['base'], NineAreaCandidateDesign.base);
    _same(d['point_scale'], NineAreaCandidateDesign.pointScale);
    _same(d['orb_limit_exclusive'], NineAreaCandidateDesign.orbLimit);
    if (d['maximum_selected_transit_groups'] !=
        NineAreaCandidateDesign.maximumGroups) {
      throw const FormatException('baseline_group_budget_changed');
    }
    final limits = b['adjustment_limits'];
    if (limits is! Map || limits['min'] != -25 || limits['max'] != 24) {
      throw const FormatException('baseline_limits_changed');
    }
    final expectedWeights = NineAreaWorkSeparatedCandidate
        .receiverWeights[DesignArea.values.byName(key)]!;
    final weights = d['receiver_weights'];
    if (weights is! Map || weights.length != expectedWeights.length) {
      throw const FormatException('baseline_receiver_weights_changed');
    }
    for (final e in expectedWeights.entries) {
      _same(weights[e.key.name], e.value);
    }
    final excluded = d['excluded_transit_planets'];
    if (key == 'work'
        ? !_listEqual(excluded, ['mercury'])
        : excluded != null && !_listEqual(excluded, [])) {
      throw const FormatException('baseline_excluded_transits_changed');
    }
    if (d['factors'] is! List || d['groups'] is! List) {
      throw const FormatException('invalid_full_group_or_factor_evidence');
    }
    final factors = <String, _Factor>{};
    final pairs = <String>{};
    for (final raw in d['factors'] as List) {
      if (raw is! Map ||
          raw.keys.any(
            (k) => !{
              'id',
              'transit_planet',
              'natal_planet',
              'aspect_type',
              'orb_degrees',
              'receiver_weight',
              'strength',
              'direction',
            }.contains(k),
          ))
        throw const FormatException('invalid_direction_factor');
      final t = _planet(raw['transit_planet']),
          n = _planet(raw['natal_planet']);
      final type = raw['aspect_type'];
      if (!DesignAspectType.values.any((a) => a.name == type) ||
          !expectedWeights.containsKey(n) ||
          key == 'work' && t == DesignPlanet.mercury) {
        throw const FormatException('unexpected_direction_factor');
      }
      final orb = _finite(raw['orb_degrees']);
      if (orb < 0 || orb >= NineAreaCandidateDesign.orbLimit) {
        throw const FormatException('ineligible_factor_orb');
      }
      final id = '${t.name}/${n.name}/$type';
      if (raw['id'] != id ||
          factors.containsKey(id) ||
          !pairs.add('${t.name}/${n.name}')) {
        throw const FormatException(
          'duplicate_or_conflicting_direction_factor',
        );
      }
      final direction = switch (type) {
        'sextile' || 'trine' => 1,
        'square' || 'opposition' => -1,
        _ => 0,
      };
      _same(raw['receiver_weight'], expectedWeights[n]);
      _same(
        raw['strength'],
        (1 - orb / NineAreaCandidateDesign.orbLimit) * expectedWeights[n]!,
      );
      if (raw['direction'] != direction)
        throw const FormatException('factor_direction_changed');
      factors[id] = _Factor(
        id,
        t,
        n,
        DesignAspectType.values.byName(type as String),
        _finite(raw['strength']),
        direction,
      );
    }
    if (d['candidate_aspect_count'] != factors.length) {
      throw const FormatException('factor_count_mismatch');
    }
    final groups = <_Group>[];
    final seen = <String>{};
    for (final raw in d['groups'] as List) {
      if (raw is! Map) throw const FormatException('invalid_transit_group');
      final planet = _planet(raw['transit_planet']);
      if (!seen.add(planet.name))
        throw const FormatException('duplicate_transit_group');
      final members = factors.values.where((f) => f.transit == planet).toList()
        ..sort(_compareFactor);
      if (members.isEmpty ||
          !_listEqual(
            raw['member_factor_ids'],
            members.map((f) => f.id).toList(),
          )) {
        throw const FormatException('group_factor_membership_mismatch');
      }
      final positive = _strongest(members.where((f) => f.direction > 0));
      final negative = _strongest(members.where((f) => f.direction < 0));
      final stimulating = _strongest(members);
      if (raw['positive_factor_id'] != positive?.id ||
          raw['negative_factor_id'] != negative?.id ||
          raw['stimulus_factor_id'] != stimulating?.id ||
          raw['selected'] is! bool) {
        throw const FormatException('group_strongest_factor_mismatch');
      }
      _same(raw['support'], positive?.strength ?? 0);
      _same(raw['tension'], negative?.strength ?? 0);
      _same(raw['stimulus'], stimulating?.strength ?? 0);
      _same(raw['balance'], _finite(raw['support']) - _finite(raw['tension']));
      groups.add(
        _Group(
          planet,
          _finite(raw['support']),
          _finite(raw['tension']),
          _finite(raw['balance']),
          _finite(raw['stimulus']),
          raw['selected'] as bool,
          raw['exclusion_reason'],
        ),
      );
    }
    if (seen.length != factors.values.map((f) => f.transit).toSet().length) {
      throw const FormatException('full_transit_groups_required');
    }
    groups.sort((a, b) => a.order.compareTo(b.order));
    final selected = groups.where((g) => g.balance != 0).toList()
      ..sort((a, b) {
        final delta = b.balance.abs().compareTo(a.balance.abs());
        return delta != 0 ? delta : a.order.compareTo(b.order);
      });
    final selectedNames = selected.take(3).map((g) => g.planet).toList();
    if (!_listEqual(d['selected_transit_planets'], selectedNames)) {
      throw const FormatException('baseline_top3_selection_mismatch');
    }
    for (final g in groups) {
      final chosen = selectedNames.contains(g.planet);
      if (g.baselineSelected != chosen ||
          g.sourceExclusionReason !=
              (chosen
                  ? null
                  : g.balance == 0
                  ? 'neutral_or_balanced'
                  : 'group_limit')) {
        throw const FormatException('baseline_group_selection_mismatch');
      }
    }
    final active = groups.where((g) => g.baselineSelected).toList();
    final support = active.fold<double>(0, (sum, g) => sum + g.support);
    final tension = active.fold<double>(0, (sum, g) => sum + g.tension);
    _same(d['support_sum'], support);
    _same(d['tension_sum'], tension);
    _same(
      d['stimulus_sum'],
      active.fold<double>(0, (sum, g) => sum + g.stimulus),
    );
    final adjustment = NineAreaCandidateDesign.pointScale * (support - tension);
    _same(d['unclamped_adjustment'], adjustment);
    _same(b['unclamped_adjustment'], adjustment);
    _same(d['adjustment'], b['adjustment']);
    _same(d['adjustment_clamp_delta'], b['adjustment_clamp_delta']);
    _same(d['continuous_score'], b['raw_score']);
    final topFactors = b['factors'] as List;
    if (topFactors.length != active.length)
      throw const FormatException('selected_factor_count_mismatch');
    final topSeen = <String>{};
    for (final f in topFactors) {
      if (f is! Map ||
          f['kind'] != 'normalized_transit_group' ||
          f['transit_planet'] is! String ||
          !topSeen.add(f['transit_planet'] as String)) {
        throw const FormatException('invalid_selected_group_factor');
      }
      final matching = active
          .where((g) => g.planet == f['transit_planet'])
          .toList();
      if (matching.length != 1)
        throw const FormatException('selected_group_factor_mismatch');
      final g = matching.single;
      _same(f['support'], g.support);
      _same(f['tension'], g.tension);
      _same(f['stimulus'], g.stimulus);
      _same(f['value'], NineAreaCandidateDesign.pointScale * g.balance);
    }
    return groups;
  }

  static void _validateMean(
    Map<String, Map<String, Object?>> areas,
    Map<String, _AreaEvidence> evidence,
  ) {
    if (evidence['overall']!.holdReason != null) return;
    final b = _breakdown(areas['overall']!), d = b['design_trace'] as Map;
    if (d['formula'] !=
            'mean_of_six_clamped_continuous_outcome_scores_then_round_once' ||
        d['additional_return_bonus'] != 0 ||
        !_listEqual(d['excluded_areas'], ['actionDecision', 'felt']) ||
        (b['factors'] as List).isNotEmpty) {
      throw const FormatException('invalid_baseline_six_area_mean');
    }
    final values = d['source_area_scores'];
    if (values == null) {
      evidence['overall'] = const _AreaEvidence.hold(
        'missing_six_area_mean_evidence',
      );
      return;
    }
    if (values is! Map ||
        values.length != 6 ||
        !_six.every(values.containsKey)) {
      throw const FormatException('invalid_baseline_mean_sources');
    }
    var sum = 0.0;
    for (final key in _six) {
      final source = areas[key]!['score_breakdown'];
      if (source == null) {
        evidence['overall'] = const _AreaEvidence.hold(
          'missing_six_area_mean_evidence',
        );
        return;
      }
      _same(values[key], (source as Map)['raw_score']);
      sum += _finite(values[key]);
    }
    _same(b['base'], sum / 6);
    _same(b['raw_score'], sum / 6);
  }

  static Map<String, Object?> _hold(Object? baseline, String reason) => {
    'baseline_score': baseline,
    'candidate_score': null,
    'score_delta': null,
    'status': 'HOLD_missing_evidence',
    'hold_reason': reason,
    'trace': null,
  };
  static Map _breakdown(Map area) => area['score_breakdown'] as Map;
  static _Factor? _strongest(Iterable<_Factor> source) {
    final items = source.toList()
      ..sort((a, b) {
        final delta = b.strength.compareTo(a.strength);
        return delta != 0 ? delta : _compareFactor(a, b);
      });
    return items.isEmpty ? null : items.first;
  }

  static int _compareFactor(_Factor a, _Factor b) {
    final transit = a.transit.index.compareTo(b.transit.index);
    if (transit != 0) return transit;
    final natal = a.natal.index.compareTo(b.natal.index);
    return natal != 0 ? natal : a.type.index.compareTo(b.type.index);
  }

  static DesignPlanet _planet(Object? value) {
    if (!DesignPlanet.values.any((p) => p.name == value)) {
      throw const FormatException('unknown_planet');
    }
    return DesignPlanet.values.byName(value as String);
  }

  static void _checkJson(Object? value) {
    if (value is Map) {
      for (final entry in value.entries) {
        if (entry.key is! String) {
          throw const FormatException('personal_observation_input_rejected');
        }
        // Legacy personal fields append an area-count/version suffix (e.g. 9).
        final normalizedKey = (entry.key as String)
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]'), '')
            .replaceFirst(RegExp(r'[0-9]+$'), '');
        if (_personalAliases.contains(normalizedKey)) {
          throw const FormatException('personal_observation_input_rejected');
        }
        _checkJson(entry.value);
      }
    } else if (value is List) {
      for (final item in value) {
        _checkJson(item);
      }
    } else if (!(value == null ||
        value is String ||
        value is bool ||
        value is num && value.isFinite)) {
      throw const FormatException('finite_json_forecast_input_required');
    }
  }

  static bool _listEqual(Object? value, List expected) =>
      value is List &&
      value.length == expected.length &&
      List.generate(
        expected.length,
        (i) => value[i] == expected[i],
      ).every((v) => v);
  static double _finite(Object? value) {
    if (value is! num || !value.isFinite)
      throw const FormatException('finite_numeric_evidence_required');
    return value.toDouble();
  }

  static void _same(Object? actual, Object? expected) {
    if ((_finite(actual) - _finite(expected)).abs() > 1e-8) {
      throw const FormatException('inconsistent_baseline_evidence');
    }
  }

  static Map<String, Object?> _clone(Map<String, Object?> value) =>
      Map<String, Object?>.from(jsonDecode(jsonEncode(value)) as Map);
}

class _AreaEvidence {
  const _AreaEvidence.hold(this.holdReason) : groups = null;
  const _AreaEvidence.available() : holdReason = null, groups = null;
  const _AreaEvidence.groups(this.groups) : holdReason = null;
  final String? holdReason;
  final List<_Group>? groups;
}

class _Factor {
  const _Factor(
    this.id,
    this.transit,
    this.natal,
    this.type,
    this.strength,
    this.direction,
  );
  final String id;
  final DesignPlanet transit, natal;
  final DesignAspectType type;
  final double strength;
  final int direction;
}

class _Group {
  const _Group(
    this.planetValue,
    this.support,
    this.tension,
    this.balance,
    this.stimulus,
    this.baselineSelected,
    this.sourceExclusionReason,
  );
  final DesignPlanet planetValue;
  String get planet => planetValue.name;
  int get order => planetValue.index;
  final double support, tension, balance, stimulus;
  final bool baselineSelected;
  final Object? sourceExclusionReason;
}
