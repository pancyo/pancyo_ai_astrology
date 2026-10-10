import 'dart:convert';

import '../daily_seven_timepoint_plan.dart';
import '../nine_area_reading_catalog.dart';
import 'felt_forecast_candidate.dart';

class ResearchPreviewError extends FormatException {
  const ResearchPreviewError(this.code) : super(code);
  final String code;
}

class ResearchPreviewOptions {
  ResearchPreviewOptions({required this.previewGeneratedAt, required this.resultSource}) {
    if (!previewGeneratedAt.isUtc ||
        !RegExp(r'^[a-z0-9][a-z0-9_-]{0,95}$').hasMatch(resultSource)) {
      throw const ResearchPreviewError('invalid_preview_provenance');
    }
  }
  final DateTime previewGeneratedAt;
  final String resultSource;
}

/// Proposed bands only; the legacy display threshold remains unchanged.
class ResearchNumericReading {
  static const contract = 'numeric-band-research-v1';
  static Map<String, Object?> select({
    required String areaKey,
    required Object? score,
    List<String>? readings,
  }) {
    if (areaKey == 'felt') throw const ResearchPreviewError('felt_is_not_numeric');
    final catalog = readings ?? NineAreaReadingCatalog.entries[areaKey];
    if (catalog == null || catalog.length != 3) {
      throw const ResearchPreviewError('unknown_numeric_area');
    }
    String? band, reading, error;
    if (score == null) {
      error = 'missing_score';
    } else if (score is! int || score < 50 || score > 99) {
      error = 'invalid_score';
    } else {
      final index = score <= 65 ? 0 : score < 80 ? 1 : 2;
      band = ['low', 'mid', 'high'][index];
      reading = catalog[index];
    }
    return {'numeric_band': band, 'band_contract_version': contract,
      'reading': reading, 'validation_error': error};
  }
}

/// Describes recorded eligibility/input evidence, never confidence or accuracy.
class ResearchLunarEvidence {
  static Map<String, Object?> build(Map<String, Object?> input) {
    final status = input['inputs_status'];
    final completed = input['eligibility_evaluation_completed'];
    final count = input['candidate_aspect_count'];
    final selected = input['selected_aspects'];
    final index = input['index'];
    final label = input['raw_label'];
    if (!['complete', 'incomplete', 'unknown'].contains(status) ||
        (completed != null && completed is! bool) ||
        (count != null && (count is! int || count < 0)) ||
        (selected != null && selected is! List) ||
        (index != null && (index is! num || !index.isFinite)) ||
        (label != null && !FeltForecastCandidate.labels.contains(label))) {
      throw const ResearchPreviewError('invalid_aspect_evidence');
    }
    if (selected is List && selected.length > 6) {
      throw const ResearchPreviewError('inconsistent_aspect_evidence');
    }
    if (count is int && selected is List &&
        (selected.length > count || selected.length > 6 ||
         (status == 'complete' && completed == true &&
          selected.length != (count < 6 ? count : 6)))) {
      throw const ResearchPreviewError('inconsistent_aspect_evidence');
    }
    if (status == 'incomplete' && completed == true) {
      throw const ResearchPreviewError('inconsistent_aspect_evidence');
    }
    late final String state, note;
    if (status == 'incomplete') {
      state = 'missing_inputs';
      note = '必須入力の不足が確認されているため、対象角度なしとは判断できません。';
    } else if (status == 'complete' && completed == true && count is int && count > 0) {
      state = 'eligible_aspects_present';
      note = '対象となる角度は存在し、既存計算結果のラベルは${label ?? "未記録"}です。';
    } else if (status == 'complete' && completed == true && count == 0 &&
               selected is List && selected.isEmpty) {
      state = 'no_eligible_lunar_aspects';
      note = '対象となる月の角度がなく、既存処理は普通を返しています。';
      if (label != '普通' || index != 0) {
        throw const ResearchPreviewError('inconsistent_aspect_evidence');
      }
    } else {
      state = 'unknown';
      note = status == 'complete' && count == null
          ? '候補件数が記録されていないため、0件とは判断できません。'
          : '元結果に入力状態や候補件数の記録がなく、根拠状態を判定できません。';
    }
    return {'evidence_state': state, 'research_note': note,
      'raw_label': label, 'index': index,
      'inputs_status': status, 'eligibility_evaluation_completed': completed,
      'candidate_aspect_count': count, 'selected_aspects': selected,
      'validation_error': null};
  }

  static Map<String, Object?> fromArea(Map area) {
    final value = area['felt_prediction'];
    final trace = value is Map ? value : const <String, Object?>{};
    final label = area['predicted_felt_label'];
    if (trace.containsKey('predicted_felt_label') && trace['predicted_felt_label'] != label) {
      throw const ResearchPreviewError('inconsistent_aspect_evidence');
    }
    final inputs = trace['inputs'];
    if (inputs != null && inputs is! Map) {
      throw const ResearchPreviewError('invalid_lunar_inputs');
    }
    var status = 'unknown';
    if (inputs is Map) {
      const required = ['natal_moon_sign','natal_moon_house','moon_in_stellium',
        'moon_related_aspects','lunar_elongation_degrees'];
      if (required.any((key) => !inputs.containsKey(key) || inputs[key] == null)) {
        status = 'incomplete';
      } else {
        final sign = inputs['natal_moon_sign'], house = inputs['natal_moon_house'];
        final phase = inputs['lunar_elongation_degrees'], share = inputs['void_day_share'];
        if (!FeltForecastCandidate.signs.contains(sign) || house is! int || house < 1 || house > 12 ||
            inputs['moon_in_stellium'] is! bool || inputs['moon_related_aspects'] is! List ||
            phase is! num || !phase.isFinite || phase < 0 || phase >= 360 ||
            (share != null && (share is! num || !share.isFinite || share < 0 || share > 1))) {
          throw const ResearchPreviewError('invalid_lunar_inputs');
        }
        status = 'complete';
      }
    }
    final recognized = trace['model_version'] == FeltForecastCandidate.modelVersion &&
        trace['status'] == 'trial_unvalidated';
    final selected = trace['selected_aspects'];
    if (selected != null && selected is! List) {
      throw const ResearchPreviewError('invalid_selected_aspect');
    }
    final minimal = selected is List ? selected.map((item) {
      if (item is! Map) throw const ResearchPreviewError('invalid_selected_aspect');
      return {for (final key in ['transit_planet','natal_planet','aspect_type','orb_degrees'])
        if (item.containsKey(key)) key: item[key]};
    }).toList() : null;
    // Selected evidence must be valid even when the original inputs are absent.
    if (minimal != null) {
      final selectedIdentities = <String>{};
      for (final item in minimal) {
        final t=item['transit_planet'], n=item['natal_planet'], a=item['aspect_type'], o=item['orb_degrees'];
        if (!FeltForecastCandidate.planets.contains(t) || !FeltForecastCandidate.planets.contains(n) ||
            (t!='moon' && n!='moon') || !FeltForecastCandidate.aspectTypes.contains(a) ||
            o is! num || !o.isFinite || o<0 || o>=4 || !selectedIdentities.add('$t/$n/$a')) {
          throw const ResearchPreviewError('inconsistent_aspect_evidence');
        }
      }
    }
    if (status == 'complete') {
      var observedCount = 0;
      final identities = <String>{};
      final eligibleOrbs = <String, num>{};
      for (final value in (inputs as Map)['moon_related_aspects'] as List) {
        if (value is! Map) throw const ResearchPreviewError('invalid_lunar_inputs');
        final t=value['transit_planet'], n=value['natal_planet'], a=value['aspect_type'], o=value['orb_degrees'];
        if (!FeltForecastCandidate.planets.contains(t) || !FeltForecastCandidate.planets.contains(n) ||
            (t!='moon' && n!='moon') || !FeltForecastCandidate.aspectTypes.contains(a) ||
            o is! num || !o.isFinite || o<0 || o>180 || !identities.add('$t/$n/$a')) {
          throw const ResearchPreviewError('invalid_lunar_inputs');
        }
        if (o<4) { observedCount++; eligibleOrbs['$t/$n/$a']=o; }
      }
      // Validate the recorded count; never replace a missing count with this count.
      if (trace['candidate_aspect_count'] != null && trace['candidate_aspect_count'] != observedCount) {
        throw const ResearchPreviewError('inconsistent_aspect_evidence');
      }
      if (minimal != null) {
        for (final item in minimal) {
          final identity='${item['transit_planet']}/${item['natal_planet']}/${item['aspect_type']}';
          if (eligibleOrbs[identity]!=item['orb_degrees']) {
            throw const ResearchPreviewError('inconsistent_aspect_evidence');
          }
        }
      }
    }
    final evidence = build({'inputs_status': status,
      'eligibility_evaluation_completed': recognized && status=='complete' ? true : null,
      'candidate_aspect_count': trace['candidate_aspect_count'], 'selected_aspects': minimal,
      'index': trace['label_index_value'], 'raw_label': label});
    return {...evidence, 'model_id': trace['model_version'],
      'input_state_basis': inputs is Map ? 'recorded_required_input_fields' : 'input_state_not_recorded',
      // Old unavailable reasons combine missing/invalid; do not invent missingness.
      'source_unavailable_reason': trace['unavailable_reason'],
      'eligibility_definition': 'moon-related aspects; orb < 4 degrees; select up to 6'};
  }
}

class ResearchJsonPreview {
  static Map<String, Object?> build(Map<String, Object?> data, ResearchPreviewOptions options) {
    final forecasts = data['intraday_forecasts'];
    if (forecasts is! Map || forecasts['points'] is! List) {
      throw const ResearchPreviewError('complete_daily_points_required');
    }
    final plan = DailySevenTimepointPlan.forJstDate(forecasts['target_date_jst'] as String);
    final points = forecasts['points'] as List;
    if (points.length != 7 || forecasts['time_zone']!='Asia/Tokyo' || forecasts['fixed_utc_offset']!='+09:00') {
      throw const ResearchPreviewError('invalid_daily_time_contract');
    }
    final generatedAt = data['generated_at'];
    if (generatedAt != null && (generatedAt is! String || DateTime.tryParse(generatedAt)==null)) {
      throw const ResearchPreviewError('invalid_source_generated_at');
    }
    final positionData = data['intraday_positions'];
    final provider = positionData is Map ? positionData['calculation_source'] : null;
    final sourceType = provider is Map && provider['provider']=='アプリ内簡易計算' && provider['provider_uses_high_precision']==false
        ? 'simple' : provider is Map && provider['provider']=='Swiss Ephemeris Free Edition' && provider['provider_uses_high_precision']==true
        ? 'native' : data['synthetic']==true && data['calculation_source']=='mock' ? 'mock' : 'unknown';
    final snapshots = <Map<String,Object?>>[], extensions = <Map<String,Object?>>[];
    for (var i=0;i<7;i++) {
      final point = points[i];
      if (point is! Map) throw const ResearchPreviewError('invalid_daily_point');
      final clock = plan.points[i].toJson();
      for (final entry in clock.entries) {
        if (point[entry.key]!=entry.value) throw const ResearchPreviewError('invalid_daily_time_contract');
      }
      final snapshot = point['nine_area_forecast'];
      if (snapshot is! Map || snapshot['areas'] is! List ||
          snapshot['calculation_reference_jst']!=clock['instant_jst'] ||
          snapshot['target_date_jst']!=(clock['instant_jst'] as String).substring(0,10)) {
        throw const ResearchPreviewError('invalid_daily_snapshot');
      }
      final areas = (snapshot['areas'] as List).cast<Map>();
      final keys = {...NineAreaReadingCatalog.entries.keys,'felt'};
      if (areas.length!=9 || areas.map((a)=>a['key']).toSet().length!=9 ||
          areas.any((a)=>!keys.contains(a['key']))) throw const ResearchPreviewError('nine_areas_required');
      final originalAreas = <Map<String,Object?>>[], researchAreas = <Map<String,Object?>>[];
      for (final area in areas) {
        final key = area['key'] as String;
        final isFelt = key=='felt';
        if (isFelt && area['score'] != null) {
          throw const ResearchPreviewError('felt_must_have_no_numeric_score');
        }
        final evidence = isFelt ? ResearchLunarEvidence.fromArea(area) : null;
        final primary = area['felt_prediction'];
        final comparison = area['felt_comparison'];
        if (isFelt && comparison != null && comparison is! Map) {
          throw const ResearchPreviewError('invalid_felt_comparison');
        }
        final comparisonTrace = comparison is Map ? comparison['felt_prediction'] : null;
        if (isFelt && comparisonTrace != null && comparisonTrace is! Map) {
          throw const ResearchPreviewError('invalid_felt_comparison');
        }
        // Keep original text and each felt path without copying its full inputs.
        originalAreas.add({'key':key,'name':area['name'],'status':area['status'],
          'score':area['score'],'display_reading':area['display_reading'],
          'summary':area['summary'],'explanation':area['explanation'],'meaning':area['meaning'],
          if(isFelt) 'raw_label':area['predicted_felt_label'],
          if(isFelt) 'index':evidence!['index'],
          if(isFelt) 'model_id':primary is Map ? primary['model_version'] : null,
          if(isFelt) 'felt_comparison':comparison is Map ? {
            'role':comparison['role'],'status':comparison['status'],
            'raw_label':comparison['predicted_felt_label'],
            'index':comparisonTrace is Map ? comparisonTrace['label_index_value'] : null,
            'model_id':comparisonTrace is Map ? comparisonTrace['model_version'] : null,
          } : null});
        researchAreas.add(isFelt ? {'key':key,...evidence!} : {
          'key':key, ...ResearchNumericReading.select(areaKey:key,score:area['score']),
          'model_id':area['score_breakdown'] is Map ? (area['score_breakdown'] as Map)['model_version'] : null,
          if(key=='actionDecision') 'meaning':'活動量の区分。成功や判断の正しさではありません。',
        });
      }
      snapshots.add({...clock,'score_day_start_utc':point['score_day_start_utc'],
        'score_day_end_utc':point['score_day_end_utc'],
        'model_id':snapshot['model_version'],'areas':originalAreas});
      extensions.add({...clock,'target_datetime_jst':clock['instant_jst'],
        'model_id':snapshot['model_version'],'areas':researchAreas});
    }
    // Allowlisted fields only. No profile, birth, diary, full trace or arbitrary metadata.
    return Map<String,Object?>.from(jsonDecode(jsonEncode({
      'schema':'pancyo_astrology_research_preview_v1', 'source_schema':data['schema'],
      'target_date_jst':plan.targetDateJst,'time_zone':'Asia/Tokyo','fixed_utc_offset':'+09:00',
      'source_snapshot':{'points':snapshots},
      'research_extension':{'version':'research-json-preview-v1','prototype':true,
        'calculation_source':sourceType,'native_execution_verified_by_preview':false,
        'result_source':options.resultSource,'model_id':forecasts['model_version'],
        'source_generated_at':generatedAt,'preview_generated_at':options.previewGeneratedAt.toIso8601String(),
        'target_datetime_jst':plan.primaryNoon.instantJst,
        'evidence_is_confidence_probability_or_accuracy':false,
        'band_contract_version':ResearchNumericReading.contract,
        'daily_scores_averaged_from_samples':false,'points':extensions},
    })) as Map);
  }
}
