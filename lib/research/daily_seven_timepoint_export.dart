import 'dart:convert';

import '../daily_seven_timepoint_plan.dart';
import '../main.dart';
import 'felt_forecast_candidate.dart';
import 'felt_layered_candidate.dart';
import 'nine_area_model_contract.dart';
import 'json_research_preview.dart';

/// Research-only adapter for a fictional pipeline sample. Does not calculate,
/// average, relabel or replace any existing forecast/model output.
class FictionalDailyResearchExport {
  const FictionalDailyResearchExport._();

  static Map<String, Object?> build({
    required Map<String, Object?> consultation,
    required String fictionalParticipantId,
    ResearchPreviewOptions? researchPreview,
  }) {
    if (!RegExp(r'^fictional-[a-z0-9-]+$').hasMatch(fictionalParticipantId) ||
        consultation['schema'] != 'pancyo_astrology_daily_consult_v4') {
      throw const FormatException('A fictional ID and existing v4 export are required.');
    }
    // Detach the sample from the original consultation and its named profile.
    final input = jsonDecode(jsonEncode(consultation)) as Map;
    final forecasts = input['intraday_forecasts'] as Map;
    final positions = input['intraday_positions'] as Map;
    final date = forecasts['target_date_jst'] as String;
    final plan = DailySevenTimepointPlan.forJstDate(date);
    final model = forecasts['model_version'];
    final points = forecasts['points'] as List;
    if (model != NineAreaModelContract.modelVersion ||
        forecasts['time_zone'] != 'Asia/Tokyo' ||
        forecasts['fixed_utc_offset'] != '+09:00' ||
        positions['target_date_jst'] != date ||
        forecasts['daily_scores_averaged_from_samples'] != false ||
        forecasts['felt_has_numeric_score'] != false ||
        forecasts['daily_primary_reference_count'] != 1 ||
        points.length != 7) {
      throw const FormatException('The existing seven-point/model contract does not match.');
    }
    final expectedKeys = NineAreaKey.values.map((key) => key.name).toSet();
    for (var i = 0; i < points.length; i++) {
      final point = points[i] as Map;
      final clock = plan.points[i];
      for (final entry in clock.toJson().entries) {
        if (point[entry.key] != entry.value) {
          throw FormatException('Clock mismatch at point $i: ${entry.key}');
        }
      }
      final civil = clock.instantUtc.add(DailySevenTimepointPlan.jstOffset);
      final dayStart = DateTime.utc(civil.year, civil.month, civil.day)
          .subtract(DailySevenTimepointPlan.jstOffset);
      final forecast = point['nine_area_forecast'] as Map;
      if (point['score_day_start_utc'] != dayStart.toIso8601String() ||
          point['score_day_end_utc'] !=
              dayStart.add(const Duration(days: 1)).toIso8601String() ||
          forecast['model_version'] != model ||
          forecast['calculation_reference_jst'] != clock.instantJst ||
          forecast['target_date_jst'] != clock.instantJst.substring(0, 10)) {
        throw FormatException('Forecast date/model mismatch at point $i.');
      }
      final areas = (forecast['areas'] as List).cast<Map>();
      if (areas.length != 9 ||
          areas.map((area) => area['key']).toSet().difference(expectedKeys).isNotEmpty ||
          expectedKeys.difference(areas.map((area) => area['key']).toSet()).isNotEmpty) {
        throw const FormatException('Exactly nine distinct areas are required.');
      }
      for (final area in areas) {
        for (final key in ['name', 'display_reading', 'summary', 'explanation', 'meaning']) {
          if (area[key] is! String || (area[key] as String).trim().isEmpty) {
            throw FormatException('Missing existing display field: $key');
          }
        }
        if (area['key'] == 'felt') {
          if (area['score'] != null || area.containsKey('score_breakdown')) {
            throw const FormatException('Felt classification cannot have a numeric score.');
          }
          NineAreaModelContract.validateFelt(
            nineAreaModelVersion: model as String,
            primaryTrace: Map<String, Object?>.from(area['felt_prediction'] as Map),
            primaryLabel: area['predicted_felt_label'] as String?,
            comparison: area['felt_comparison'] == null ? null :
                Map<String, Object?>.from(area['felt_comparison'] as Map),
          );
        } else {
          NineAreaModelContract.validateNumeric(
            area['status'] as String,
            area['score'] as int?,
            area['score_breakdown'] == null ? null :
                Map<String, Object?>.from(area['score_breakdown'] as Map),
          );
        }
      }
    }
    if (jsonEncode((points[3] as Map)['nine_area_forecast']) !=
        jsonEncode(input['nine_area_daily'])) {
      throw const FormatException('The noon forecast must remain the original daily reference.');
    }
    final sourceGeneratedAt = input['generated_at'];
    DateTime? generatedAt;
    if (sourceGeneratedAt == null && researchPreview == null) {
      throw const FormatException('Sample generation time is required.');
    }
    if (sourceGeneratedAt != null) {
      if (sourceGeneratedAt is! String) {
        throw const FormatException('Sample generation time must explicitly use UTC.');
      }
      generatedAt = DateTime.parse(sourceGeneratedAt);
      if (!generatedAt.isUtc) {
        throw const FormatException('Sample generation time must explicitly use UTC.');
      }
    }
    final daily = <String, Object?>{
      'schema': 'pancyo_research_daily_seven_timepoint_provisional_v1',
      'purpose': 'fictional_export_pipeline_sample_not_prospective_validation',
      'provisional': true,
      'generated_at_utc': generatedAt?.toIso8601String(),
      'participant': {'id': fictionalParticipantId, 'synthetic': true},
      'source_export_schema': input['schema'],
      'target_date_jst': date,
      'time_zone': 'Asia/Tokyo',
      'fixed_utc_offset': '+09:00',
      'day_interval': {
        'start_utc': plan.dayStartUtc.toIso8601String(),
        'end_utc': plan.dayEndUtc.toIso8601String(),
        'start_inclusive': true,
        'end_inclusive': false,
      },
      'model_versions': {
        'nine_area': model,
        'numeric': NineAreaModelContract.numericModelVersion,
        'felt_primary': FeltForecastCandidate.modelVersion,
        'felt_comparison_only': FeltLayeredCandidate.modelVersion,
      },
      'calculation_source': positions['calculation_source'],
      'house_calculation': {
        'requested_system': (positions['house_calculation'] as Map)['requested_system'],
        'resolved_system': (positions['house_calculation'] as Map)['resolved_system'],
        'reference': 'natal_chart',
      },
      'interpretation': {
        'boundary_24h': '24:00は翌日00:00。同一の実時刻で、対象日の半開区間には含めない。',
        'nine_areas': '数値8項目と、数値なしの体感分類1項目。説明と内訳は既存出力を保持。',
        'time_samples': '既存の日モデルを7時点の配置に適用した比較値。正午が日予測の基準で、7点平均ではない。',
        'felt': '正規の月短期体感と比較候補を分離。時点値を観測済みの一日体感や確率として扱わない。',
        'validation': '架空人物のLinux出力検査。独立暦、Android native、実機、予測精度は未確認。',
      },
      'intraday_forecasts': forecasts,
    };
    if (researchPreview == null) return daily;
    // Evaluate evidence from the same complete v4 result before anonymizing.
    final preview = ResearchJsonPreview.build(consultation, researchPreview);
    return {
      for (final entry in daily.entries)
        if (entry.key != 'intraday_forecasts') entry.key: entry.value,
      'schema': 'pancyo_research_daily_seven_timepoint_integrated_v1',
      'source_schema': preview['source_schema'],
      // Keep only documented provider metadata in the shareable result.
      'calculation_source': positions['calculation_source'] is Map ? {
        for (final key in ['provider', 'provider_uses_high_precision',
          'inherited_noon_individual_provenance', 'note'])
          if ((positions['calculation_source'] as Map).containsKey(key))
            key: (positions['calculation_source'] as Map)[key],
      } : null,
      'source_snapshot': preview['source_snapshot'],
      'research_extension': preview['research_extension'],
    };
  }
}
