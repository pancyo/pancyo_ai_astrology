import 'dart:convert';

import 'felt_forecast_candidate.dart';
import 'json_research_preview.dart';
import 'nine_area_model_contract.dart';

/// Comparison text derived solely from a saved forecast, never from outcomes.
/// This does not fit, improve, or replace the numeric or canonical felt model.
class DailyExplanationCandidate {
  const DailyExplanationCandidate._();

  static const schema = 'pancyo_research_daily_explanation_candidate_v1';
  static const candidateVersion = 'daily-explanation-candidate-20261009-1';
  static const _six = ['love', 'work', 'money', 'mental', 'health', 'people'];
  static const _rootKeys = {
    'schema',
    'purpose',
    'model_version',
    'ephemeris_time_contract',
    'target_date_jst',
    'calculation_reference_jst',
    'house_system',
    'uses_high_precision_astro_data',
    'interpretation_note',
    'areas',
    'reassembled_context',
  };
  static const _areaKeys = {
    'key',
    'name',
    'status',
    'score',
    'display_reading',
    'summary',
    'explanation',
    'meaning',
    'score_breakdown',
    'predicted_felt_label',
    'felt_prediction',
    'felt_comparison',
    'long_term_context',
  };
  static const _forbiddenKeys = {
    'profile',
    'birth_date',
    'birth_time',
    'birth_place',
    'birthday',
    'address',
    'url',
    'diary',
    'diary_raw',
    'diary_raw_markdown',
    'outcome',
    'outcomes',
    'outcome_input',
    'observed_outcomes',
    'observed_results',
    'self_hit_judgement',
    'chappy_judgement',
    'direct_events',
    'direct_felt',
    'reported_facts',
    'primary_properties',
  };

  static Map<String, Object?> build({
    required Map<String, Object?> dailySnapshot,
    required String sourceSha256,
    required DateTime generatedAt,
  }) {
    if (!_sha(sourceSha256) || !generatedAt.isUtc) {
      throw const FormatException('invalid_candidate_provenance');
    }
    _checkJson(dailySnapshot);
    _allowed(dailySnapshot, _rootKeys);
    final model = dailySnapshot['model_version'];
    if (model != NineAreaModelContract.modelVersion &&
        model != NineAreaModelContract.numericModelVersion) {
      throw const FormatException('unsupported_source_model');
    }
    final reassembled = model == NineAreaModelContract.numericModelVersion;
    _composition(dailySnapshot, reassembled);
    final scope = _timeScope(dailySnapshot);
    final rawAreas = dailySnapshot['areas'];
    if (rawAreas is! List || rawAreas.length != 9) {
      throw const FormatException('nine_areas_required');
    }
    final areas = <String, Map<String, Object?>>{};
    for (final raw in rawAreas) {
      if (raw is! Map) throw const FormatException('invalid_area');
      final area = Map<String, Object?>.from(raw);
      _allowed(area, _areaKeys);
      final key = area['key'];
      if (key is! String ||
          !{'overall', ..._six, 'actionDecision', 'felt'}.contains(key) ||
          areas.containsKey(key)) {
        throw const FormatException('nine_distinct_areas_required');
      }
      if (!area.containsKey('score')) {
        throw const FormatException('explicit_score_or_null_required');
      }
      areas[key] = area;
      if (key != 'felt') _validateNumeric(key, area);
    }
    _validateOverall(areas);
    final candidateAreas = <Map<String, Object?>>[];
    for (final area in areas.values) {
      candidateAreas.add(
        area['key'] == 'felt' ? _felt(area, reassembled) : _numeric(area),
      );
    }
    return _clone({
      'schema': schema,
      'source_snapshot': dailySnapshot,
      'candidate_extension': {
        'candidate_version': candidateVersion,
        'role': 'comparison_only_not_primary',
        'status': 'unvalidated_explanation_candidate',
        'source_artifact_sha256': sourceSha256,
        'generated_at_utc': generatedAt.toIso8601String(),
        'target_date_jst': dailySnapshot['target_date_jst'],
        'calculation_reference_jst': dailySnapshot['calculation_reference_jst'],
        'source_model_version': model,
        'source_composition': reassembled
            ? 'reassembled_numeric_v1_and_canonical_lunar'
            : 'original_combined_snapshot',
        'scope': scope,
        'band_contract_version': ResearchNumericReading.contract,
        'score_policy': {
          'additional_correction': 0,
          'coefficient_status': 'HOLD_insufficient_independent_evidence',
          'canonical_scores_unchanged': true,
          'observed_outcomes_used': false,
          'general_coefficients_changed': false,
        },
        'daily_scores_averaged_from_samples': false,
        'old_fixed_text_replaced': false,
        'old_judgements_transfer_to_candidate': false,
        'predictive_improvement_established': false,
        'areas': candidateAreas,
      },
    });
  }

  static Map<String, Object?> _numeric(Map<String, Object?> area) {
    final key = area['key'] as String;
    final score = area['score'] as int?;
    final band = ResearchNumericReading.select(areaKey: key, score: score);
    if (score == null) {
      return {
        'key': key,
        'source_score': null,
        'candidate_score': null,
        'score_delta': null,
        'numeric_band': null,
        'evidence_state': 'missing_numeric_prediction',
        'forecast_tendency': '元予測が未算出のため、この分野の見通しは不明です。',
        'calculation_explanation': '欠損を0点や基準点へ置き換えず、そのまま保持します。',
        'advice': 'この候補から行動の良し悪しを判断せず、実際の状況を確認してください。',
      };
    }
    final b = Map<String, Object?>.from(area['score_breakdown'] as Map);
    final factors = b['factors'] as List;
    var positive = 0.0, negative = 0.0, support = 0.0, tension = 0.0;
    for (final raw in factors) {
      final f = raw as Map;
      final value = (f['value'] as num).toDouble();
      if (value > 0) positive += value;
      if (value < 0) negative += value;
      support += (f['support'] as num).toDouble();
      tension += (f['tension'] as num).toDouble();
    }
    final activity = key == 'actionDecision';
    final overall = key == 'overall';
    final mixed = !activity && !overall && support > 0 && tension > 0;
    final bandName = {
      'low': '低め',
      'mid': '中程度',
      'high': '高め',
    }[band['numeric_band']];
    final base = (b['base'] as num).toDouble();
    final adjustment = (b['adjustment'] as num).toDouble();
    final rawScore = (b['raw_score'] as num).toDouble();
    final calculation = overall
        ? '恋愛・仕事・金運・メンタル・健康・対人の6分野の上限処理後・丸め前の値を平均し、最後に1回丸めた値です。活動性・体感・リターン追加ボーナスは含めません。総合は幸福感や実際の達成度の実測ではありません。'
        : activity
        ? '基準50に、記録された活動刺激の補正${_n(adjustment)}を加え、上限処理と丸めを行った値です。調和・緊張・合はいずれも刺激の材料です。活動量は成果や判断の正しさを示しません。'
        : '基準75に、記録された天体群の加点${_n(positive)}と減点${_n(negative)}を合算し、補正上限と丸めを適用します。'
              '${mixed ? '調和と緊張の材料が併存し、数式内で相殺しています。基準付近の点数でも、出来事や負担が少ないとは判断できません。' : 'この値は実際の出来事の量や負担の実測ではありません。'}';
    return {
      'key': key,
      'source_score': score,
      'candidate_score': score,
      'score_delta': 0,
      'numeric_band': band['numeric_band'],
      'evidence_state': 'recorded_arithmetic_checked_not_predictive_validation',
      'forecast_tendency': overall
          ? '6分野をまとめた未検証の見通しは、研究区分で「$bandName」です。満足感とは別に読みます。'
          : activity
          ? '活動刺激の試作値は、研究区分で「$bandName」です。成功の見通しには換算しません。'
          : 'この分野の未検証の見通しは、研究区分で「$bandName」です。実際の結果との対応は確認されていません。',
      'calculation_explanation': calculation,
      'advice': activity
          ? '着手量と完了した成果を分けて確認し、負担に合わせて休憩や作業量を調整してください。'
          : overall
          ? '6分野の内訳と実際の状況を確認し、一日の満足感は別に振り返ってください。'
          : '進みやすかった点と負担のあった点を分けて確認し、実際の予定や体調に合わせてください。',
      'calculation_material': {
        'base': base,
        'positive_group_contribution': positive,
        'negative_group_contribution': negative,
        'support_material': overall ? null : support,
        'tension_material': overall ? null : tension,
        'coexisting_support_and_tension': mixed,
        'unclamped_adjustment': b['unclamped_adjustment'],
        'applied_adjustment': adjustment,
        'adjustment_clamp_delta': b['adjustment_clamp_delta'],
        'continuous_score_before_rounding': rawScore,
        if (overall) 'mean_source_areas': _six,
        if (overall)
          'mean_source_continuous_scores':
              (b['design_trace'] as Map)['source_area_scores'],
      },
    };
  }

  static Map<String, Object?> _felt(
    Map<String, Object?> area,
    bool reassembled,
  ) {
    if (area['score'] != null || area['score_breakdown'] != null) {
      throw const FormatException('felt_is_not_numeric');
    }
    final label = area['predicted_felt_label'];
    if ((label != null && !FeltForecastCandidate.labels.contains(label)) ||
        area['status'] !=
            (label == null ? 'not_predicted' : 'trial_unvalidated')) {
      throw const FormatException('invalid_felt_status');
    }
    final evidence = ResearchLunarEvidence.fromArea(area);
    final trace = area['felt_prediction'];
    final comparison = area['felt_comparison'];
    if (trace != null && trace is! Map ||
        comparison != null && comparison is! Map) {
      throw const FormatException('invalid_felt_trace');
    }
    if (reassembled && comparison != null) {
      throw const FormatException(
        'numeric_v1_must_not_impersonate_combined_v2',
      );
    }
    final complete = {
      'eligible_aspects_present',
      'no_eligible_lunar_aspects',
    }.contains(evidence['evidence_state']);
    if (complete || label == null && trace is Map && trace['inputs'] == null) {
      if (trace is! Map) throw const FormatException('missing_felt_trace');
      if (reassembled) {
        FeltForecastCandidate.validateSnapshot(
          Map<String, Object?>.from(trace),
          label as String?,
        );
      } else {
        NineAreaModelContract.validateFelt(
          nineAreaModelVersion: NineAreaModelContract.modelVersion,
          primaryTrace: Map<String, Object?>.from(trace),
          primaryLabel: label as String?,
          comparison: comparison is Map
              ? Map<String, Object?>.from(comparison)
              : null,
        );
      }
    } else if (comparison != null) {
      // Partial evidence cannot substantiate a combined comparison pathway.
      throw const FormatException(
        'partial_felt_evidence_requires_separate_source',
      );
    }
    return {
      'key': 'felt',
      'source_score': null,
      'candidate_score': null,
      'score_delta': null,
      'numeric_band': null,
      'evidence_state': evidence['evidence_state'],
      'source_primary_label': label,
      'source_comparison_label': comparison is Map
          ? comparison['predicted_felt_label']
          : null,
      'primary_label_changed': false,
      'evidence': evidence,
      'forecast_tendency': complete
          ? '正規の月短期体感は「$label」という未検証の候補です。総合・メンタル・健康点から換算したラベルではありません。'
          : '元の体感ラベルは保存しますが、根拠の不足・未記録を埋めて体感を判定しません。',
      'calculation_explanation':
          '${evidence['research_note']} '
          '一時的な負担と一日全体の満足感は併存し得ます。長期の配置や別の比較候補を、本人の好調・不調の原因と断定する裏付けはありません。',
      'advice': '体調、作業の負担、一日の満足感を分けて確認し、実際の体調を優先してください。',
    };
  }

  static void _validateNumeric(String key, Map<String, Object?> area) {
    final score = area['score'];
    final status = area['status'];
    final raw = area['score_breakdown'];
    if (status is! String ||
        score != null && score is! int ||
        raw != null && raw is! Map) {
      throw const FormatException('invalid_numeric_area');
    }
    final b = raw is Map ? Map<String, Object?>.from(raw) : null;
    NineAreaModelContract.validateNumeric(status, score as int?, b);
    if (b == null) return;
    if (score! < 50 || score > 99)
      throw const FormatException('invalid_numeric_range');
    final overall = key == 'overall', activity = key == 'actionDecision';
    final kind = overall
        ? 'general_six_area_mean_v1'
        : activity
        ? 'general_activity_groups_v1'
        : 'general_outcome_groups_v1';
    if (b['calculation_kind'] != kind)
      throw const FormatException('invalid_calculation_kind');
    final limits = b['adjustment_limits'];
    if (limits is! Map ||
        limits['min'] != (overall || activity ? 0 : -25) ||
        limits['max'] !=
            (overall
                ? 0
                : activity
                ? 49
                : 24)) {
      throw const FormatException('general_limits_changed');
    }
    if (!overall) {
      _same(b['base'], activity ? 50 : 75);
      final d = b['design_trace'];
      if (d is! Map) throw const FormatException('missing_numeric_design');
      _same(d['point_scale'], activity ? 49 / 3 : 9);
      _same(d['continuous_score'], b['raw_score']);
      final factors = b['factors'] as List;
      if (factors.length > 3)
        throw const FormatException('too_many_transit_groups');
      final planets = <Object?>{};
      for (final f in factors.cast<Map>()) {
        if (f['kind'] != 'normalized_transit_group' ||
            !FeltForecastCandidate.planets.contains(f['transit_planet']) ||
            !planets.add(f['transit_planet'])) {
          throw const FormatException('invalid_transit_group');
        }
        final support = _finite(f['support']), tension = _finite(f['tension']);
        final stimulus = _finite(f['stimulus']);
        if (support < 0 || tension < 0 || stimulus < 0) {
          throw const FormatException('invalid_group_material');
        }
        _same(
          f['value'],
          activity ? stimulus * 49 / 3 : (support - tension) * 9,
        );
      }
    }
  }

  static void _validateOverall(Map<String, Map<String, Object?>> areas) {
    final overall = areas['overall']!;
    if (overall['score'] == null) return;
    final b = overall['score_breakdown'] as Map;
    final d = b['design_trace'];
    if (d is! Map ||
        d['formula'] !=
            'mean_of_six_clamped_continuous_outcome_scores_then_round_once' ||
        d['additional_return_bonus'] != 0 ||
        !_sameJson(d['excluded_areas'], ['actionDecision', 'felt']) ||
        (b['factors'] as List).isNotEmpty) {
      throw const FormatException('invalid_six_area_mean_contract');
    }
    final values = d['source_area_scores'];
    if (values is! Map ||
        values.length != 6 ||
        !_six.every(values.containsKey)) {
      throw const FormatException('six_continuous_scores_required');
    }
    var sum = 0.0;
    for (final key in _six) {
      final raw = areas[key]!['score_breakdown'];
      if (raw is! Map) throw const FormatException('mean_source_missing');
      _same(values[key], raw['raw_score']);
      sum += _finite(values[key]);
    }
    _same(b['base'], sum / 6);
    _same(b['raw_score'], sum / 6);
  }

  static void _composition(Map<String, Object?> snapshot, bool reassembled) {
    final c = snapshot['reassembled_context'];
    if (!reassembled) {
      if (c != null)
        throw const FormatException('unexpected_reassembled_context');
      return;
    }
    if (c is! Map ||
        c.length != 4 ||
        c['kind'] != 'saved_numeric_v1_with_separate_canonical_lunar_source' ||
        c['is_original_combined_snapshot'] != false ||
        !_sha(c['numeric_source_sha256']) ||
        !_sha(c['canonical_felt_source_sha256'])) {
      throw const FormatException(
        'separate_numeric_and_felt_provenance_required',
      );
    }
  }

  static String _timeScope(Map<String, Object?> snapshot) {
    final schema = snapshot['schema'];
    final day = snapshot['target_date_jst'],
        reference = snapshot['calculation_reference_jst'];
    if (day is! String ||
        reference is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day) ||
        !RegExp(
          r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?\+09:00$',
        ).hasMatch(reference)) {
      throw const FormatException('invalid_explicit_jst_reference');
    }
    final parsed = DateTime.tryParse(reference);
    if (parsed == null ||
        parsed
                .add(const Duration(hours: 9))
                .toIso8601String()
                .substring(0, 19) !=
            reference.substring(0, 19) ||
        reference.substring(0, 10) != day) {
      throw const FormatException('invalid_or_inconsistent_target_date');
    }
    if (schema == 'pancyo_nine_area_daily_consult_v1' &&
        RegExp(
          r'^\d{4}-\d{2}-\d{2}T12:00:00(?:\.0{1,6})?\+09:00$',
        ).hasMatch(reference))
      return 'daily_noon_reference';
    if (schema == 'pancyo_nine_area_instant_consult_v1') {
      return 'sample_instant_comparison_not_new_intraday_model';
    }
    throw const FormatException(
      'daily_requires_noon_or_explicit_instant_schema',
    );
  }

  static void _checkJson(Object? value) {
    if (value is Map) {
      for (final entry in value.entries) {
        if (entry.key is! String || _forbiddenKeys.contains(entry.key)) {
          throw const FormatException(
            'personal_outcome_or_non_json_input_rejected',
          );
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
      throw const FormatException('finite_json_values_required');
    }
  }

  static void _allowed(Map<String, Object?> value, Set<String> keys) {
    if (value.keys.any((key) => !keys.contains(key))) {
      throw const FormatException('unrecognized_snapshot_field');
    }
  }

  static bool _sha(Object? value) =>
      value is String && RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(value);
  static double _finite(Object? value) {
    if (value is! num || !value.isFinite)
      throw const FormatException('finite_numeric_material_required');
    return value.toDouble();
  }

  static void _same(Object? actual, Object? expected) {
    if ((_finite(actual) - _finite(expected)).abs() > 1e-8) {
      throw const FormatException('inconsistent_recorded_arithmetic');
    }
  }

  static bool _sameJson(Object? a, Object? b) => jsonEncode(a) == jsonEncode(b);
  static String _n(double value) => value.toStringAsFixed(2);
  static Map<String, Object?> _clone(Map<String, Object?> value) =>
      Map<String, Object?>.from(jsonDecode(jsonEncode(value)) as Map);
}
