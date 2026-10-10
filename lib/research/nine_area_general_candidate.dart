import 'felt_forecast_candidate.dart';

/// Shared C1/C2 engine. Archived experiment IDs retain their meaning.
/// Normalized inputs are not independently verified astronomical positions.
enum DesignPlanet {
  sun,
  moon,
  mercury,
  venus,
  mars,
  jupiter,
  saturn,
  uranus,
  neptune,
  pluto,
}

enum DesignAspectType { conjunction, sextile, square, trine, opposition }

enum DesignArea {
  overall,
  love,
  work,
  money,
  mental,
  health,
  people,
  actionDecision,
}

class DesignAspect {
  const DesignAspect(this.transit, this.natal, this.type, this.orb);
  final DesignPlanet transit, natal;
  final DesignAspectType type;
  final double orb;
  String get pairId => transit.name + '/' + natal.name;
  String get id => pairId + '/' + type.name;
  int get direction => switch (type) {
    DesignAspectType.sextile || DesignAspectType.trine => 1,
    DesignAspectType.square || DesignAspectType.opposition => -1,
    DesignAspectType.conjunction => 0,
  };
  Map<String, Object?> toJson() => {
    'id': id,
    'transit_planet': transit.name,
    'natal_planet': natal.name,
    'aspect_type': type.name,
    'orb_degrees': orb,
  };
}

class DesignMaterial {
  DesignMaterial({
    required this.instantUtc,
    required Iterable<DesignPlanet> natalPlanets,
    required Iterable<DesignPlanet> transitPlanets,
    required List<DesignAspect>? aspects,
    this.natalMoonSign,
    this.natalMoonHouse,
    this.moonInStellium,
    this.lunarElongationDegrees,
    this.voidDayShare,
  }) : natalPlanets = Set.unmodifiable(natalPlanets),
       transitPlanets = Set.unmodifiable(transitPlanets),
       aspects = aspects == null ? null : List.unmodifiable(aspects);
  final DateTime instantUtc;
  final Set<DesignPlanet> natalPlanets, transitPlanets;
  final List<DesignAspect>? aspects;
  final String? natalMoonSign;
  final int? natalMoonHouse;
  final bool? moonInStellium;
  final double? lunarElongationDegrees, voidDayShare;
}

class DesignAreaResult {
  DesignAreaResult(this.continuousScore, this.trace)
    : score = continuousScore?.round();
  final double? continuousScore;
  final int? score;
  final Map<String, Object?> trace;
  Map<String, Object?> toJson() => {
    'score': score,
    'continuous_score': continuousScore,
    'predicted_band': score == null
        ? null
        : score! <= 65
        ? 'low'
        : score! < 80
        ? 'middle'
        : 'high',
    'status': score == null ? 'not_predicted' : 'candidate_unvalidated',
    'trace': trace,
  };
}

class NineAreaDesignResult {
  NineAreaDesignResult(
    this.areas,
    this.felt,
    this.materialTrace, {
    this.designId = NineAreaCandidateDesign.designId,
  });
  final Map<DesignArea, DesignAreaResult> areas;
  final FeltForecastResult felt;
  final Map<String, Object?> materialTrace;
  final String designId;
  Map<String, Object?> toJson() => {
    // Deliberately not a saved forecast or consultation JSON schema.
    'artifact_type': 'pancyo_nine_area_design_experiment_v0',
    'design_id': designId,
    'active_runtime_model': false,
    'ephemeris_verified_here': false,
    'material': materialTrace,
    'areas': {
      for (final area in DesignArea.values) area.name: areas[area]!.toJson(),
      'felt': {
        'score': null,
        'predicted_band': null,
        'predicted_felt_label': felt.label,
        'trace': felt.trace,
      },
    },
  };
}

class NineAreaCandidateDesign {
  const NineAreaCandidateDesign._();
  static const designId = 'nine-area-candidate-design-20261002-1';
  static const base = 75.0;
  static const orbLimit = 4.0;
  static const pointScale = 9.0;
  static const maximumGroups = 3;
  static const outcomeAreas = [
    DesignArea.love,
    DesignArea.work,
    DesignArea.money,
    DesignArea.mental,
    DesignArea.health,
    DesignArea.people,
  ];

  /// Hypothesized receiver roles, not learned/proven coefficients.
  /// A natal receiver is not interchangeable with a transit planet.
  static const receiverWeights = {
    DesignArea.love: {DesignPlanet.venus: 1.0, DesignPlanet.moon: 0.5},
    DesignArea.work: {
      DesignPlanet.mercury: 1.0,
      DesignPlanet.sun: 0.5,
      DesignPlanet.saturn: 0.5,
    },
    DesignArea.money: {
      DesignPlanet.venus: 1.0,
      DesignPlanet.jupiter: 0.5,
      DesignPlanet.saturn: 0.5,
    },
    DesignArea.mental: {
      DesignPlanet.moon: 1.0,
      DesignPlanet.mercury: 0.5,
      DesignPlanet.neptune: 0.5,
    },
    DesignArea.health: {
      DesignPlanet.sun: 1.0,
      DesignPlanet.moon: 0.5,
      DesignPlanet.mars: 0.5,
    },
    DesignArea.people: {
      DesignPlanet.mercury: 1.0,
      DesignPlanet.venus: 0.5,
      DesignPlanet.moon: 0.5,
    },
    DesignArea.actionDecision: {
      DesignPlanet.mercury: 1.0,
      DesignPlanet.mars: 1.0,
    },
  };

  static NineAreaDesignResult calculate(DesignMaterial input) => _calculate(
    input,
    weightsByArea: receiverWeights,
    resultDesignId: designId,
  );

  static NineAreaDesignResult _calculate(
    DesignMaterial input, {
    required Map<DesignArea, Map<DesignPlanet, double>> weightsByArea,
    required String resultDesignId,
    Map<DesignArea, Set<DesignPlanet>> excludedTransits = const {},
  }) {
    final raw = input.aspects;
    final materialTrace = <String, Object?>{
      'instant_utc': input.instantUtc.toIso8601String(),
      'input_aspect_count': raw?.length,
      'missing_natal_planets': [
        for (final p in DesignPlanet.values)
          if (!input.natalPlanets.contains(p)) p.name,
      ],
      'missing_transit_planets': [
        for (final p in DesignPlanet.values)
          if (!input.transitPlanets.contains(p)) p.name,
      ],
    };
    String? error;
    if (!input.instantUtc.isUtc) {
      error = 'instant_must_be_utc';
    } else if (input.natalPlanets.length != DesignPlanet.values.length ||
        input.transitPlanets.length != DesignPlanet.values.length) {
      error = 'incomplete_positions';
    } else if (raw == null) {
      error = 'missing_aspects';
    }
    final unique = <String, DesignAspect>{};
    final pairs = <String, DesignAspectType>{};
    if (error == null) {
      for (final a in raw!) {
        if (!a.orb.isFinite || a.orb < 0 || a.orb > 180) {
          error = 'invalid_orb';
          break;
        }
        if (unique.containsKey(a.id) && unique[a.id]!.orb != a.orb) {
          error = 'conflicting_duplicate';
          break;
        }
        if (pairs.containsKey(a.pairId) && pairs[a.pairId] != a.type) {
          error = 'conflicting_pair';
          break;
        }
        unique[a.id] = a;
        pairs[a.pairId] = a.type;
      }
    }
    if (error != null) {
      materialTrace['unavailable_reason'] = error;
      return NineAreaDesignResult(
        Map.unmodifiable({
          for (final area in DesignArea.values)
            area: DesignAreaResult(null, {'unavailable_reason': error}),
        }),
        FeltForecastCandidate.unavailable(
          {
                'missing_aspects',
                'invalid_orb',
                'conflicting_duplicate',
                'conflicting_pair',
              }.contains(error)
              ? 'missing_or_invalid_aspects'
              : 'missing_or_invalid_positions',
        ),
        materialTrace,
        designId: resultDesignId,
      );
    }
    final normalized = unique.values.toList()..sort(_compareAspect);
    materialTrace.addAll({
      'unique_aspect_count': normalized.length,
      'collapsed_identical_duplicate_count': raw!.length - normalized.length,
      'normalized_aspects': [for (final a in normalized) a.toJson()],
    });
    final areas = <DesignArea, DesignAreaResult>{
      for (final area in weightsByArea.keys)
        area: _calculateArea(
          area,
          normalized,
          weights: weightsByArea[area]!,
          excludedTransits: excludedTransits[area] ?? const {},
        ),
    };
    // No activity/felt term or second return bonus in overall.
    final average =
        outcomeAreas.fold(
          0.0,
          (sum, area) => sum + areas[area]!.continuousScore!,
        ) /
        outcomeAreas.length;
    areas[DesignArea.overall] = DesignAreaResult(average, {
      'formula':
          'mean_of_six_clamped_continuous_outcome_scores_then_round_once',
      'source_area_scores': {
        for (final area in outcomeAreas)
          area.name: areas[area]!.continuousScore,
      },
      'excluded_areas': ['actionDecision', 'felt'],
      'additional_return_bonus': 0,
    });
    final felt = FeltForecastCandidate.predict(
      natalMoonSign: input.natalMoonSign,
      natalMoonHouse: input.natalMoonHouse,
      moonInStellium: input.moonInStellium,
      aspects: [
        for (final a in normalized)
          if (a.transit == DesignPlanet.moon || a.natal == DesignPlanet.moon)
            FeltAspect(a.transit.name, a.natal.name, a.type.name, a.orb),
      ],
      lunarElongationDegrees: input.lunarElongationDegrees,
      voidDayShare: input.voidDayShare,
    );
    return NineAreaDesignResult(
      Map.unmodifiable(areas),
      felt,
      materialTrace,
      designId: resultDesignId,
    );
  }

  static DesignAreaResult _calculateArea(
    DesignArea area,
    List<DesignAspect> aspects, {
    required Map<DesignPlanet, double> weights,
    required Set<DesignPlanet> excludedTransits,
  }) {
    final activation = area == DesignArea.actionDecision;
    final factors = <_WeightedAspect>[
      for (final a in aspects)
        if (a.orb < orbLimit &&
            weights.containsKey(a.natal) &&
            !excludedTransits.contains(a.transit))
          _WeightedAspect(a, weights[a.natal]!),
    ];
    final groups = <_TransitGroup>[
      for (final planet in DesignPlanet.values)
        if (factors.any((f) => f.aspect.transit == planet))
          _TransitGroup(
            planet,
            factors.where((f) => f.aspect.transit == planet).toList(),
          ),
    ];
    final eligible =
        groups
            .where((g) => activation ? g.stimulus > 0 : g.balance != 0)
            .toList()
          ..sort((a, b) {
            final diff = (activation ? b.stimulus : b.balance.abs()).compareTo(
              activation ? a.stimulus : a.balance.abs(),
            );
            return diff != 0 ? diff : a.planet.index.compareTo(b.planet.index);
          });
    final selected = eligible.take(maximumGroups).toList();
    final support = selected.fold(0.0, (v, g) => v + g.support);
    final tension = selected.fold(0.0, (v, g) => v + g.tension);
    final stimulus = selected.fold(0.0, (v, g) => v + g.stimulus);
    final adjustment = pointScale * (support - tension);
    final clampedAdjustment = adjustment.clamp(-25.0, 24.0).toDouble();
    final value = activation
        ? (50 + 49 / maximumGroups * stimulus).clamp(50.0, 99.0).toDouble()
        : base + clampedAdjustment;
    return DesignAreaResult(value, {
      'interpretation': activation
          ? 'activity_not_success'
          : 'outcome_direction_hypothesis',
      'base': activation ? 50 : base,
      'point_scale': activation ? 49 / maximumGroups : pointScale,
      'maximum_selected_transit_groups': maximumGroups,
      'orb_limit_exclusive': orbLimit,
      'receiver_weights': {
        for (final e in weights.entries) e.key.name: e.value,
      },
      if (excludedTransits.isNotEmpty)
        'excluded_transit_planets': [
          for (final p in DesignPlanet.values)
            if (excludedTransits.contains(p)) p.name,
        ],
      'candidate_aspect_count': factors.length,
      'support_sum': support,
      'tension_sum': tension,
      'stimulus_sum': stimulus,
      'unclamped_adjustment': activation ? value - 50 : adjustment,
      'adjustment': activation ? value - 50 : clampedAdjustment,
      'adjustment_clamp_delta': activation ? 0 : clampedAdjustment - adjustment,
      'continuous_score': value,
      'selected_transit_planets': [for (final g in selected) g.planet.name],
      'factors': [for (final f in factors) f.toJson()],
      'groups': [
        for (final g in groups)
          {
            ...g.toJson(),
            'selected': selected.contains(g),
            'exclusion_reason': selected.contains(g)
                ? null
                : !activation && g.balance == 0
                ? 'neutral_or_balanced'
                : 'group_limit',
          },
      ],
      'zero_weight_context': [
        'houses',
        'sign_dignity',
        'retrograde',
        'returns_extra_bonus',
        'rare_patterns_extra_bonus',
        'lunar_phase',
        'void',
        'profile_text',
        'observed_results',
        'personal_history_calibration',
      ],
    });
  }

  static int _compareAspect(DesignAspect a, DesignAspect b) {
    var diff = a.transit.index.compareTo(b.transit.index);
    if (diff != 0) return diff;
    diff = a.natal.index.compareTo(b.natal.index);
    return diff != 0 ? diff : a.type.index.compareTo(b.type.index);
  }
}

/// C2 changes only the hypothesized work pathway and its overall contribution.
/// This is a falsifiable comparison candidate, not an empirically fitted model.
/// Work progress can coexist with friction; activity is not success.
class NineAreaWorkSeparatedCandidate {
  const NineAreaWorkSeparatedCandidate._();
  static const designId = 'nine-area-work-separated-candidate-20261003-1';
  static final receiverWeights =
      Map<DesignArea, Map<DesignPlanet, double>>.unmodifiable({
        ...NineAreaCandidateDesign.receiverWeights,
        DesignArea.work: const {
          DesignPlanet.sun: 1.0,
          DesignPlanet.saturn: 1.0,
        },
      });

  static NineAreaDesignResult calculate(DesignMaterial input) {
    final result = NineAreaCandidateDesign._calculate(
      input,
      weightsByArea: receiverWeights,
      resultDesignId: designId,
      excludedTransits: const {
        DesignArea.work: {DesignPlanet.mercury},
      },
    );
    result.materialTrace['work_role_hypothesis'] = {
      'outcome_receivers': ['sun', 'saturn'],
      'mercury_direct_work_weight': 0,
      'activity_pathway': 'unchanged_C1_mercury_mars_receivers',
      'empirically_fitted': false,
      'prospectively_validated': false,
      'other_areas': 'unchanged_C1_hypotheses',
      'angles_and_houses': 'not_scored_in_this_candidate',
    };
    return result;
  }
}

class _WeightedAspect {
  const _WeightedAspect(this.aspect, this.receiverWeight);
  final DesignAspect aspect;
  final double receiverWeight;
  double get strength =>
      (1 - aspect.orb / NineAreaCandidateDesign.orbLimit) * receiverWeight;
  Map<String, Object?> toJson() => {
    ...aspect.toJson(),
    'receiver_weight': receiverWeight,
    'strength': strength,
    'direction': aspect.direction,
  };
}

class _TransitGroup {
  _TransitGroup(this.planet, this.factors);
  final DesignPlanet planet;
  final List<_WeightedAspect> factors;
  _WeightedAspect? _strongest(bool Function(_WeightedAspect) keep) {
    final candidates = factors.where(keep).toList()
      ..sort((a, b) {
        final diff = b.strength.compareTo(a.strength);
        return diff != 0
            ? diff
            : NineAreaCandidateDesign._compareAspect(a.aspect, b.aspect);
      });
    return candidates.isEmpty ? null : candidates.first;
  }

  _WeightedAspect? get positive => _strongest((f) => f.aspect.direction > 0);
  _WeightedAspect? get negative => _strongest((f) => f.aspect.direction < 0);
  _WeightedAspect? get stimulating => _strongest((_) => true);
  double get support => positive?.strength ?? 0;
  double get tension => negative?.strength ?? 0;
  double get balance => support - tension;
  double get stimulus => stimulating?.strength ?? 0;
  Map<String, Object?> toJson() => {
    'transit_planet': planet.name,
    'positive_factor_id': positive?.aspect.id,
    'negative_factor_id': negative?.aspect.id,
    'stimulus_factor_id': stimulating?.aspect.id,
    'support': support,
    'tension': tension,
    'balance': balance,
    'stimulus': stimulus,
    'member_factor_ids': [for (final f in factors) f.aspect.id],
  };
}
