import 'felt_forecast_candidate.dart';
import 'felt_layered_candidate.dart';
import 'nine_area_general_candidate.dart';
import 'nine_area_score_audit.dart';

/// General provisional model. Geometry is derived from complete positions.
/// Historical personal observations and Sun-sign bonuses are not inputs.
class GeneralNineAreaForecast {
  const GeneralNineAreaForecast._();
  static const modelVersion = 'nine-area-general-trial-20261003-1';
  static const _angles = <DesignAspectType, double>{
    DesignAspectType.conjunction: 0,
    DesignAspectType.sextile: 60,
    DesignAspectType.square: 90,
    DesignAspectType.trine: 120,
    DesignAspectType.opposition: 180,
  };
  static const _planetLabels = {
    'sun': '太陽',
    'moon': '月',
    'mercury': '水星',
    'venus': '金星',
    'mars': '火星',
    'jupiter': '木星',
    'saturn': '土星',
    'uranus': '天王星',
    'neptune': '海王星',
    'pluto': '冥王星',
  };

  static GeneralNineAreaResult calculate({
    required DateTime instantUtc,
    required Map<String, double>? natalLongitudes,
    required Map<String, double>? transitLongitudes,
    required int? natalMoonHouse,
    required bool? moonInStellium,
    double? voidDayShare,
  }) {
    if (!instantUtc.isUtc)
      return GeneralNineAreaResult.unavailable('instant_must_be_utc');
    bool valid(Map<String, double>? values) =>
        values != null &&
        values.length == DesignPlanet.values.length &&
        DesignPlanet.values.every(
          (p) =>
              values.containsKey(p.name) &&
              values[p.name]!.isFinite &&
              values[p.name]! >= 0 &&
              values[p.name]! < 360,
        );
    if (!valid(natalLongitudes) || !valid(transitLongitudes)) {
      return GeneralNineAreaResult.unavailable(
        'incomplete_or_invalid_positions',
      );
    }
    final natal = natalLongitudes!, transit = transitLongitudes!;
    final aspects = <DesignAspect>[];
    for (final t in DesignPlanet.values) {
      for (final n in DesignPlanet.values) {
        final separation = (transit[t.name]! - natal[n.name]!).abs();
        final distance = separation <= 180 ? separation : 360 - separation;
        for (final entry in _angles.entries) {
          final orb = (distance - entry.value).abs();
          if (orb <= 8) aspects.add(DesignAspect(t, n, entry.key, orb));
        }
      }
    }
    final moonSign = FeltForecastCandidate.signs[(natal['moon']! / 30).floor()];
    final phase = (transit['moon']! - transit['sun']! + 360) % 360;
    final material = DesignMaterial(
      instantUtc: instantUtc,
      natalPlanets: DesignPlanet.values,
      transitPlanets: DesignPlanet.values,
      aspects: aspects,
      natalMoonSign: moonSign,
      natalMoonHouse: natalMoonHouse,
      moonInStellium: moonInStellium,
      lunarElongationDegrees: phase,
      voidDayShare: voidDayShare,
    );
    final design = NineAreaWorkSeparatedCandidate.calculate(material);
    final numeric = <String, Map<String, Object?>>{};
    for (final area in DesignArea.values) {
      final result = design.areas[area]!;
      if (result.score == null)
        return GeneralNineAreaResult.unavailable('invalid_candidate_material');
      final trace = result.trace;
      final overall = area == DesignArea.overall;
      final activity = area == DesignArea.actionDecision;
      final groups = overall
          ? const <Map>[]
          : (trace['groups'] as List).cast<Map>();
      final factors = <Map<String, Object?>>[
        for (final group in groups)
          if (group['selected'] == true)
            {
              'kind': 'normalized_transit_group',
              'label':
                  '${_planetLabels[group['transit_planet']]}の${activity ? '活動刺激' : '調和・緊張差'}',
              'transit_planet': group['transit_planet'],
              'support': group['support'],
              'tension': group['tension'],
              'stimulus': group['stimulus'],
              'value':
                  (activity
                          ? (group['stimulus'] as num) * 49 / 3
                          : (group['balance'] as num) * 9)
                      .toDouble(),
              'formula': activity
                  ? 'stimulus × 49 / 3'
                  : '(support - tension) × 9',
            },
      ];
      final base = overall
          ? result.continuousScore!
          : activity
          ? 50.0
          : 75.0;
      final rawAdjustment = factors.fold(
        0.0,
        (v, f) => v + (f['value'] as double),
      );
      final minimum = overall || activity ? 0.0 : -25.0;
      final maximum = overall
          ? 0.0
          : activity
          ? 49.0
          : 24.0;
      final adjustment = rawAdjustment.clamp(minimum, maximum).toDouble();
      final breakdown = <String, Object?>{
        'calculation_kind': overall
            ? 'general_six_area_mean_v1'
            : activity
            ? 'general_activity_groups_v1'
            : 'general_outcome_groups_v1',
        'model_version': modelVersion,
        'base': base,
        'factors': factors,
        'unclamped_adjustment': rawAdjustment,
        'adjustment_limits': {'min': minimum, 'max': maximum},
        'adjustment': adjustment,
        'adjustment_clamp_delta': adjustment - rawAdjustment,
        'raw_score': base + adjustment,
        'final_score': result.score,
        'rounding_and_clamp': '丸め前の材料を計算 → 補正上限 → 四捨五入（50〜99点）',
        'design_trace': trace,
        'general_model': true,
        'empirically_fitted': false,
        'personal_calibration': {'status': 'not_applied', 'offset': 0.0},
      };
      NineAreaScoreAudit.validate(breakdown, result.score!);
      numeric[area.name] = {
        'score': result.score,
        'status': 'trial_unvalidated',
        'score_breakdown': breakdown,
      };
    }
    final felt = FeltLayeredCandidate.predict(
      natalMoonSign: moonSign,
      natalMoonHouse: natalMoonHouse,
      moonInStellium: moonInStellium,
      allAspects: [
        for (final a in aspects)
          FeltAspect(a.transit.name, a.natal.name, a.type.name, a.orb),
      ],
      lunarElongationDegrees: phase,
      voidDayShare: voidDayShare,
    );
    return GeneralNineAreaResult(Map.unmodifiable(numeric), felt, {
      'instant_utc': instantUtc.toIso8601String(),
      'geometry_source': 'complete_major_planet_longitudes',
      'aspect_count': aspects.length,
      'general_model': true,
      'personal_calibration': {'status': 'not_applied', 'offset': 0.0},
      'sun_sign_specific_bonus': 0,
      'observation_inputs_used': false,
    });
  }
}

class GeneralNineAreaResult {
  const GeneralNineAreaResult(this.numeric, this.felt, this.materialTrace);
  final Map<String, Map<String, Object?>> numeric;
  final FeltForecastResult felt;
  final Map<String, Object?> materialTrace;

  factory GeneralNineAreaResult.unavailable(String reason) =>
      GeneralNineAreaResult(
        Map.unmodifiable({
          for (final a in DesignArea.values)
            a.name: <String, Object?>{
              'score': null,
              'status': 'not_predicted',
              'score_breakdown': null,
            },
        }),
        FeltLayeredCandidate.unavailable('missing_or_invalid_positions'),
        {
          'unavailable_reason': reason,
          'general_model': true,
          'observation_inputs_used': false,
        },
      );

  Map<String, Object?> toJson() => {
    'artifact_type': 'pancyo_general_model_research_trial_v1',
    'model_version': GeneralNineAreaForecast.modelVersion,
    'status': 'trial_unvalidated',
    'material': materialTrace,
    'numeric_areas': numeric,
    'felt': {'predicted_felt_label': felt.label, 'felt_prediction': felt.trace},
  };
}
