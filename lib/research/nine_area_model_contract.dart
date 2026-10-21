import 'felt_forecast_candidate.dart';
import 'felt_layered_candidate.dart';
import 'nine_area_general_forecast.dart';
import 'nine_area_score_audit.dart';

/// Runtime composition: general numeric model, lunar primary, separate trial.
/// The three-path sum must not silently replace the primary lunar label.
class NineAreaModelContract {
  const NineAreaModelContract._();
  static const modelVersion = 'nine-area-general-trial-20261003-2';
  static const numericModelVersion = GeneralNineAreaForecast.modelVersion;

  static FeltForecastResult primaryFromComparison(FeltForecastResult trial) {
    FeltLayeredCandidate.validateSnapshot(trial.trace, trial.label);
    final lunar = trial.trace['lunar_path'];
    final result = lunar is Map
        ? FeltForecastResult(
            trial.trace['lunar_predicted_felt_label'] as String?,
            Map<String, Object?>.from(lunar),
          )
        : FeltForecastCandidate.unavailable(
            trial.trace['unavailable_reason'] as String,
          );
    FeltForecastCandidate.validateSnapshot(result.trace, result.label);
    return result;
  }

  static void validateFelt({
    required String nineAreaModelVersion,
    required Map<String, Object?> primaryTrace,
    required String? primaryLabel,
    Map<String, Object?>? comparison,
  }) {
    if (nineAreaModelVersion != modelVersion &&
        !FeltForecastCandidate.supportedNineAreaModelVersions.contains(
          nineAreaModelVersion,
        )) {
      throw const FormatException('体感と9項目のモデル版が一致しません。');
    }
    FeltForecastCandidate.validateSnapshot(primaryTrace, primaryLabel);
    if (comparison == null) return;
    if (nineAreaModelVersion != modelVersion ||
        comparison['role'] != 'comparison_only_not_primary' ||
        comparison['status'] !=
            (comparison['predicted_felt_label'] == null
                ? 'not_predicted'
                : 'trial_unvalidated') ||
        comparison['felt_prediction'] is! Map) {
      throw const FormatException('比較候補を正規の体感や旧モデルへ混ぜられません。');
    }
    final label = comparison['predicted_felt_label'];
    if (label != null && label is! String) {
      throw const FormatException('比較候補の体感ラベルが不正です。');
    }
    final trial = FeltForecastResult(
      label as String?,
      Map<String, Object?>.from(comparison['felt_prediction'] as Map),
    );
    final expected = primaryFromComparison(trial);
    if (primaryLabel != expected.label ||
        !_equal(primaryTrace, expected.trace)) {
      throw const FormatException('月の正規候補と比較候補の月経路が一致しません。');
    }
  }

  static Map<String, Object?> comparisonJson(FeltForecastResult trial) => {
    'role': 'comparison_only_not_primary',
    'status': trial.label == null ? 'not_predicted' : 'trial_unvalidated',
    'predicted_felt_label': trial.label,
    'felt_prediction': trial.trace,
  };

  static void validateNumeric(
    String status,
    int? score,
    Map<String, Object?>? breakdown,
  ) {
    if (status == 'not_predicted') {
      if (score != null || breakdown != null) {
        throw const FormatException('一般式の未予測を基準点で補完できません。');
      }
      return;
    }
    if (status != 'trial_unvalidated' ||
        score == null ||
        breakdown == null ||
        breakdown['model_version'] != numericModelVersion ||
        breakdown['general_model'] != true ||
        breakdown['empirically_fitted'] != false) {
      throw const FormatException('一般式の数値根拠・モデル版が一致しません。');
    }
    final personal = breakdown['personal_calibration'];
    if (personal is! Map ||
        personal['status'] != 'not_applied' ||
        personal['offset'] != 0.0) {
      throw const FormatException('この一般式へ個人の日記補正を混ぜられません。');
    }
    NineAreaScoreAudit.validate(breakdown, score);
  }

  static bool _equal(Object? a, Object? b) {
    if (a is num && b is num) {
      return a.isFinite && b.isFinite && (a - b).abs() <= 1e-8;
    }
    if (a is Map && b is Map) {
      return a.length == b.length &&
          b.keys.every((k) => a.containsKey(k) && _equal(a[k], b[k]));
    }
    if (a is List && b is List) {
      return a.length == b.length &&
          List.generate(b.length, (i) => _equal(a[i], b[i])).every((v) => v);
    }
    return a == b;
  }
}
