import 'nine_area_score_audit.dart';
import 'felt_forecast_candidate.dart';
import 'nine_area_model_contract.dart';

/// 9項目予測と、後日別ファイルへ記録した結果を照合するための研究用判定。
/// 記録の事前性・本人評価の真偽は、このコードだけでは証明できない。
class NineAreaValidation {
  const NineAreaValidation._();

  static const forecastSchema = 'pancyo_nine_area_forecast_v1';
  static const outcomeSchema = 'pancyo_nine_area_outcome_v1';
  static const areaKeys = <String>[
    'overall',
    'love',
    'work',
    'money',
    'mental',
    'health',
    'people',
    'actionDecision',
    'felt',
  ];
  static const _bands = <String>['low', 'middle', 'high'];
  static const _feltLabels = FeltForecastCandidate.labels;
  static const _states = <String>{
    'observed',
    'explicit_no_event',
    'missing',
    'external_unassessable',
  };

  static Map<String, Object?> evaluate(
    Map<String, dynamic> forecast,
    Map<String, dynamic> outcome,
  ) {
    if (forecast['schema'] != forecastSchema ||
        outcome['schema'] != outcomeSchema) {
      throw const FormatException('予測または結果ファイルのスキーマが違います。');
    }
    if (forecast['forecast_only'] != true ||
        forecast['outcome_included'] != false) {
      throw const FormatException('予測ファイルに結果が混ざっている可能性があります。');
    }
    final modelVersion = _requiredString(forecast, 'model_version');
    if ((modelVersion == FeltForecastCandidate.nineAreaModelVersion ||
            modelVersion == NineAreaModelContract.modelVersion) &&
        forecast['ephemeris_time_contract'] != 'instant_to_utc_v1') {
      throw const FormatException('現モデルの星計算の時刻契約がありません。');
    }
    final rawBands = forecast['score_bands'];
    if (rawBands is! Map ||
        rawBands['low'] != '50-65' ||
        rawBands['middle'] != '66-79' ||
        rawBands['high'] != '80-99') {
      throw const FormatException('予測ファイルの点数帯定義が違います。');
    }
    final targetDate = _requiredString(forecast, 'target_date_jst');
    if (outcome['target_date_jst'] != targetDate) {
      throw const FormatException('予測日と結果日が一致しません。');
    }
    final target = _targetDay(targetDate);
    final targetMidnightUtc = target.subtract(const Duration(hours: 9));
    final targetNoonUtc = target.add(const Duration(hours: 3));
    final issuedAt = _jstTimestamp(forecast, 'issued_at_jst_device_clock');
    final referenceAt = _jstTimestamp(forecast, 'calculation_reference_jst');
    final recordedAt = _jstTimestamp(outcome, 'recorded_at_jst_device_clock');
    if (!issuedAt.isBefore(targetMidnightUtc)) {
      throw const FormatException('予測の発行時刻が対象日の開始以降です。');
    }
    if (referenceAt != targetNoonUtc) {
      throw const FormatException('予測の計算基準が対象日の12:00 JSTではありません。');
    }
    if (recordedAt.isBefore(targetMidnightUtc.add(const Duration(days: 1))) ||
        !recordedAt.isAfter(issuedAt)) {
      throw const FormatException('1日分の結果は対象日の翌日以降に記録してください。');
    }

    final forecastAreas = _areas(forecast);
    final outcomeAreas = _areas(outcome);
    final counts = <String, int>{
      'match': 0,
      'partial_match': 0,
      'mismatch': 0,
      'not_predicted': 0,
      'missing': 0,
      'explicit_no_event': 0,
      'external_unassessable': 0,
    };
    final results = <Map<String, Object?>>[];
    var eligibleNumericAreas = 0;
    var eligibleFeltAreas = 0;
    for (final key in areaKeys) {
      final prediction = forecastAreas[key]!;
      final observation = outcomeAreas[key]!;
      final state = _requiredString(observation, 'observation_state');
      if (!_states.contains(state)) {
        throw FormatException('$key の観測状態が未定義です。');
      }
      final evidence = observation['evidence'];
      if (evidence is! String ||
          (state != 'missing' && evidence.trim().isEmpty)) {
        throw FormatException('$key の観測根拠がありません。');
      }
      final rating = observation['rating_1_to_5'];
      final feltLabel = observation['felt_label'];
      if (observation['observed_band'] != null) {
        throw FormatException('$key は直接の結果帯ではなく1〜5の原評価を記録してください。');
      }
      if (state == 'observed') {
        if (key == 'felt') {
          if (!_feltLabels.contains(feltLabel) || rating != null) {
            throw const FormatException('体感は5段階の本人評価だけを記録してください。');
          }
        } else if (rating is! int ||
            rating < 1 ||
            rating > 5 ||
            feltLabel != null) {
          throw FormatException('$key の本人評価は1〜5の整数で指定してください。');
        }
      } else if (rating != null || feltLabel != null) {
        throw FormatException('$key の未観測状態に結果ラベルを入れないでください。');
      }
      final observedBand = rating is int
          ? rating <= 2
                ? 'low'
                : rating >= 4
                ? 'high'
                : 'middle'
          : null;

      final status = _requiredString(prediction, 'status');
      final score = prediction['score'];
      final predictedBand = prediction['predicted_band'];
      final breakdown = prediction['score_breakdown'];
      final predictedFeltLabel = prediction['predicted_felt_label'];
      final feltTrace = prediction['felt_prediction'];
      final comparison = prediction['felt_comparison'];
      if (key == 'felt') {
        if (score != null || predictedBand != null || breakdown != null) {
          throw const FormatException('体感の5段階候補を数値点・3段階帯へ混ぜないでください。');
        }
        if (status == 'not_predicted') {
          if (predictedFeltLabel != null) {
            throw const FormatException('未予測の体感にラベルを入れないでください。');
          }
        } else if (status != 'trial_unvalidated' ||
            !_feltLabels.contains(predictedFeltLabel) ||
            feltTrace is! Map) {
          throw const FormatException('体感の候補ラベル・計算根拠が不正です。');
        }
        if (feltTrace != null) {
          if (feltTrace is! Map || (comparison != null && comparison is! Map)) {
            throw const FormatException('体感候補と9項目のモデル版が一致しません。');
          }
          NineAreaModelContract.validateFelt(
            nineAreaModelVersion: modelVersion,
            primaryTrace: Map<String, Object?>.from(feltTrace),
            primaryLabel: predictedFeltLabel as String?,
            comparison: comparison == null
                ? null
                : Map<String, Object?>.from(comparison as Map),
          );
        } else if (comparison != null) {
          throw const FormatException('正規体感のない比較候補は扱えません。');
        }
      } else {
        if (predictedFeltLabel != null ||
            feltTrace != null ||
            comparison != null) {
          throw FormatException('$key に体感の候補を入れないでください。');
        }
        if (modelVersion == NineAreaModelContract.modelVersion) {
          if ((score != null && score is! int) || (breakdown != null && breakdown is! Map)) {
            throw FormatException('$key の一般式の数値形式が不正です。');
          }
          NineAreaModelContract.validateNumeric(status, score as int?,
              breakdown == null ? null : Map<String, Object?>.from(breakdown as Map));
        }
        if (status == 'not_predicted' &&
            modelVersion == NineAreaModelContract.modelVersion) {
          if (score != null || predictedBand != null || breakdown != null) {
            throw FormatException('$key の未予測値を補完できません。');
          }
        } else {
          if (!{'trial_unvalidated', 'inherited_existing'}.contains(status) ||
              score is! int ||
              score < 50 ||
              score > 99 ||
              predictedBand != _bandForScore(score)) {
            throw FormatException('$key の予測値または点数帯が不正です。');
          }
          if (prediction.containsKey('score_breakdown')) {
            if (breakdown is! Map) {
              throw FormatException('$key の点数内訳の形式が不正です。');
            }
            NineAreaScoreAudit.validate(
              Map<String, dynamic>.from(breakdown),
              score,
            );
          }
        }
      }

      final String judgement;
      if (status == 'not_predicted') {
        judgement = 'not_predicted';
      } else if (state != 'observed') {
        judgement = state;
      } else {
        final distance = key == 'felt'
            ? (_feltLabels.indexOf(predictedFeltLabel as String) -
                      _feltLabels.indexOf(feltLabel as String))
                  .abs()
            : (_bands.indexOf(predictedBand as String) -
                      _bands.indexOf(observedBand as String))
                  .abs();
        if (key == 'felt') {
          eligibleFeltAreas++;
        } else {
          eligibleNumericAreas++;
        }
        judgement = switch (distance) {
          0 => 'match',
          1 => 'partial_match',
          _ => 'mismatch',
        };
      }
      counts[judgement] = counts[judgement]! + 1;
      results.add({
        'key': key,
        'prediction_status': status,
        'observation_state': state,
        'predicted_band': predictedBand,
        'rating_1_to_5': rating,
        'observed_band': observedBand,
        if (key == 'felt') ...{
          'predicted_felt_label': predictedFeltLabel,
          'observed_felt_label': feltLabel,
          if (feltTrace is Map)
            'felt_model_version': feltTrace['model_version'],
        },
        'judgement': judgement,
      });
    }
    return {
      'schema': 'pancyo_nine_area_validation_v1',
      'target_date_jst': targetDate,
      'model_version': modelVersion,
      'issued_at_jst_device_clock': forecast['issued_at_jst_device_clock'],
      'recorded_at_jst_device_clock': outcome['recorded_at_jst_device_clock'],
      'counts': counts,
      'eligible_numeric_areas': eligibleNumericAreas,
      'eligible_felt_areas': eligibleFeltAreas,
      'results': results,
      'limitation': '端末時計と手入力の結果だけでは、予測の事前性・結果ラベルの正しさを証明できません。',
    };
  }

  static String _requiredString(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('$key がありません。');
    }
    return value;
  }

  static DateTime _targetDay(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      throw const FormatException('対象日は YYYY-MM-DD で指定してください。');
    }
    final year = int.parse(value.substring(0, 4));
    final month = int.parse(value.substring(5, 7));
    final day = int.parse(value.substring(8, 10));
    final date = DateTime.utc(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      throw const FormatException('対象日が存在しません。');
    }
    return date;
  }

  static DateTime _jstTimestamp(Map<String, dynamic> data, String key) {
    final value = _requiredString(data, key);
    if (!RegExp(
      r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?\+09:00$',
    ).hasMatch(value)) {
      throw FormatException('$key はJSTの日時で指定してください。');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) throw FormatException('$key の日時が不正です。');
    final normalizedJst = parsed.toUtc().add(const Duration(hours: 9));
    if (normalizedJst.year != int.parse(value.substring(0, 4)) ||
        normalizedJst.month != int.parse(value.substring(5, 7)) ||
        normalizedJst.day != int.parse(value.substring(8, 10)) ||
        normalizedJst.hour != int.parse(value.substring(11, 13)) ||
        normalizedJst.minute != int.parse(value.substring(14, 16)) ||
        normalizedJst.second != int.parse(value.substring(17, 19))) {
      throw FormatException('$key の日時が存在しません。');
    }
    return parsed.toUtc();
  }

  static Map<String, Map<String, dynamic>> _areas(Map<String, dynamic> data) {
    final raw = data['areas'];
    if (raw is! List || raw.length != areaKeys.length) {
      throw const FormatException('9項目がそろっていません。');
    }
    final areas = <String, Map<String, dynamic>>{};
    for (final item in raw) {
      if (item is! Map) throw const FormatException('項目の形式が不正です。');
      final area = Map<String, dynamic>.from(item);
      final key = _requiredString(area, 'key');
      if (!areaKeys.contains(key) || areas.containsKey(key)) {
        throw FormatException('項目 $key が重複または未定義です。');
      }
      areas[key] = area;
    }
    return areas;
  }

  static String _bandForScore(int score) => score <= 65
      ? 'low'
      : score >= 80
      ? 'high'
      : 'middle';
}
