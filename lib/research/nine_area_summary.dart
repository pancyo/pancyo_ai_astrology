import 'nine_area_validation.dart';
import 'felt_forecast_candidate.dart';
import 'nine_area_model_contract.dart';

/// 事前予測と後日の結果を照合済みのレポートだけを、モデル版ごとに集計する。
/// 一致件数は予測力の証明ではなく、同じ対象日の単純な「常に中」基準と並べる。
class NineAreaSummary {
  const NineAreaSummary._();

  static const schema = 'pancyo_nine_area_summary_v1';

  static Map<String, Object?> summarize(
    Iterable<Map<String, Object?>> evaluations,
  ) {
    final byVersion = <String, _VersionSummary>{};
    for (final report in evaluations) {
      if (report['schema'] != 'pancyo_nine_area_validation_v1') {
        throw const FormatException('9項目の照合結果ではありません。');
      }
      final version = report['model_version'];
      final date = report['target_date_jst'];
      if (version is! String ||
          version.isEmpty ||
          date is! String ||
          date.isEmpty) {
        throw const FormatException('モデル版または対象日がありません。');
      }
      byVersion
          .putIfAbsent(version, () => _VersionSummary(version))
          .add(date, report);
    }
    if (byVersion.isEmpty) {
      throw const FormatException('集計する照合結果がありません。');
    }
    final versions = byVersion.keys.toList()..sort();
    return {
      'schema': schema,
      'comparison':
          '同じ評価対象日の完全一致件数を比較。数値8項目は「常に中」、体感5段階は「常に普通」が基準。隣接一致は完全一致に含めない。',
      'models': [for (final version in versions) byVersion[version]!.toJson()],
      'limitations':
          '端末時計と本人の結果記録だけでは事前性や予測力を証明できません。プロフィールを識別しないため、異なる人の記録を混ぜないでください。',
    };
  }
}

class _VersionSummary {
  _VersionSummary(this.version);

  final String version;
  final Set<String> dates = {};
  final Map<String, _AreaSummary> areas = {
    for (final key in NineAreaValidation.areaKeys) key: _AreaSummary(key),
  };

  void add(String date, Map<String, Object?> report) {
    if (!dates.add(date)) {
      throw FormatException('モデル版 $version の $date が重複しています。');
    }
    final raw = report['results'];
    if (raw is! List || raw.length != NineAreaValidation.areaKeys.length) {
      throw const FormatException('照合結果の9項目がそろっていません。');
    }
    final seen = <String>{};
    for (final item in raw) {
      if (item is! Map) throw const FormatException('照合項目の形式が不正です。');
      final result = Map<String, Object?>.from(item);
      final key = result['key'];
      if (key is! String || !areas.containsKey(key) || !seen.add(key)) {
        throw const FormatException('照合項目が重複または未定義です。');
      }
      if (key == 'felt' &&
          result['felt_model_version'] != null &&
          version != NineAreaModelContract.modelVersion &&
          !FeltForecastCandidate.supportedNineAreaModelVersions.contains(
            version,
          )) {
        throw const FormatException('体感候補と集計の9項目モデル版が一致しません。');
      }
      areas[key]!.add(result);
    }
  }

  Map<String, Object?> toJson() {
    final orderedDates = dates.toList()..sort();
    return {
      'model_version': version,
      'days': orderedDates.length,
      'first_date_jst': orderedDates.first,
      'last_date_jst': orderedDates.last,
      'areas': [
        for (final key in NineAreaValidation.areaKeys) areas[key]!.toJson(),
      ],
    };
  }
}

class _AreaSummary {
  _AreaSummary(this.key);

  final String key;
  int eligibleDays = 0;
  int exactMatchDays = 0;
  int baselineMiddleExactDays = 0;
  int baselineOrdinaryExactDays = 0;
  final Map<String, int> predictionBands = {'low': 0, 'middle': 0, 'high': 0};
  final Map<String, int> observedBands = {'low': 0, 'middle': 0, 'high': 0};
  final Map<String, int> observationStates = {
    'observed': 0,
    'explicit_no_event': 0,
    'missing': 0,
    'external_unassessable': 0,
  };
  final Map<String, int> judgements = {
    'match': 0,
    'partial_match': 0,
    'mismatch': 0,
    'not_predicted': 0,
    'missing': 0,
    'explicit_no_event': 0,
    'external_unassessable': 0,
  };
  final Map<String, int> feltLabels = {
    '最悪': 0,
    '悪い': 0,
    '普通': 0,
    '良い': 0,
    '最高': 0,
  };
  final Map<String, int> feltPredictionLabels = {
    for (final label in FeltForecastCandidate.labels) label: 0,
  };
  final Map<String, Map<String, int>> feltConfusion = {
    for (final prediction in FeltForecastCandidate.labels)
      prediction: {
        for (final observation in FeltForecastCandidate.labels) observation: 0,
      },
  };

  void add(Map<String, Object?> item) {
    final state = item['observation_state'];
    final judgement = item['judgement'];
    final predictionBand = item['predicted_band'];
    final observedBand = item['observed_band'];
    if (state is! String ||
        !observationStates.containsKey(state) ||
        judgement is! String ||
        !judgements.containsKey(judgement) ||
        predictionBand != null &&
            !predictionBands.containsKey(predictionBand) ||
        observedBand != null && !observedBands.containsKey(observedBand)) {
      throw FormatException('$key の照合結果が不正です。');
    }
    if (key == 'felt') {
      _addFelt(item, state, judgement);
      return;
    }
    observationStates[state] = observationStates[state]! + 1;
    judgements[judgement] = judgements[judgement]! + 1;
    if (predictionBand is String) {
      predictionBands[predictionBand] = predictionBands[predictionBand]! + 1;
    }
    if (observedBand is String) {
      observedBands[observedBand] = observedBands[observedBand]! + 1;
    }
    if (const {'match', 'partial_match', 'mismatch'}.contains(judgement)) {
      if (predictionBand is! String || observedBand is! String) {
        throw FormatException('$key の比較対象の帯がありません。');
      }
      eligibleDays++;
      if (judgement == 'match') exactMatchDays++;
      if (observedBand == 'middle') baselineMiddleExactDays++;
    }
  }

  void _addFelt(Map<String, Object?> item, String state, String judgement) {
    final prediction = item['predicted_felt_label'];
    final observation = item['observed_felt_label'];
    if (item['predicted_band'] != null ||
        item['observed_band'] != null ||
        item['rating_1_to_5'] != null ||
        (prediction != null && !feltPredictionLabels.containsKey(prediction)) ||
        (state == 'observed'
            ? !feltLabels.containsKey(observation)
            : observation != null) ||
        (prediction != null &&
            item['felt_model_version'] != FeltForecastCandidate.modelVersion)) {
      throw const FormatException('体感の比較ラベル・候補式版が不正です。');
    }
    if (item['prediction_status'] !=
        (prediction == null ? 'not_predicted' : 'trial_unvalidated')) {
      throw const FormatException('体感の予測状態とラベルが一致しません。');
    }
    final eligible = prediction is String && state == 'observed';
    final distance = eligible
        ? (FeltForecastCandidate.labels.indexOf(prediction) -
                  FeltForecastCandidate.labels.indexOf(observation as String))
              .abs()
        : null;
    final expected = prediction == null
        ? 'not_predicted'
        : state != 'observed'
        ? state
        : distance == 0
        ? 'match'
        : distance == 1
        ? 'partial_match'
        : 'mismatch';
    if (judgement != expected) {
      throw const FormatException('体感のラベルと照合判定が一致しません。');
    }
    observationStates[state] = observationStates[state]! + 1;
    judgements[judgement] = judgements[judgement]! + 1;
    if (prediction is String)
      feltPredictionLabels[prediction] = feltPredictionLabels[prediction]! + 1;
    if (observation is String)
      feltLabels[observation] = feltLabels[observation]! + 1;
    if (eligible) {
      eligibleDays++;
      if (distance == 0) exactMatchDays++;
      if (observation == '普通') baselineOrdinaryExactDays++;
      final row = feltConfusion[prediction]!;
      row[observation as String] = row[observation]! + 1;
    }
  }

  Map<String, Object?> toJson() => {
    'key': key,
    'eligible_days': eligibleDays,
    'exact_match_days': exactMatchDays,
    if (key != 'felt') ...{
      'baseline_always_middle_exact_days': baselineMiddleExactDays,
      'predicted_band_counts': predictionBands,
      'observed_band_counts': observedBands,
    },
    'observation_state_counts': observationStates,
    'judgement_counts': judgements,
    if (key == 'felt') ...{
      'baseline_always_ordinary_exact_days': baselineOrdinaryExactDays,
      'adjacent_match_days': judgements['partial_match'],
      'nonadjacent_mismatch_days': judgements['mismatch'],
      'predicted_felt_label_counts': feltPredictionLabels,
      'observed_felt_label_counts': feltLabels,
      'confusion_label_order': FeltForecastCandidate.labels,
      'confusion_rows_prediction_columns_observation': feltConfusion,
    },
  };
}
