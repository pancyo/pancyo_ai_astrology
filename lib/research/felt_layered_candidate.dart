import 'felt_forecast_candidate.dart';

/// General, unfitted hypothesis. The three paths use disjoint aspect inputs.
/// No diary, observed event, name, Sun-sign bonus, or personal offset is read.
class FeltLayeredCandidate {
  const FeltLayeredCandidate._();

  static const modelVersion = 'felt-three-path-20261003-1';
  static const parameters = <String, Object?>{
    'lunar_model_version': FeltForecastCandidate.modelVersion,
    'path_weights': {'lunar': 1.0, 'pleasure': 1.0, 'background': 1.0},
    'pleasure_orb_limit_exclusive': 4.0,
    'background_orb_limit_exclusive': 6.0,
    'maximum_background_transit_groups': 3,
    'background_limits': [-2.0, 2.0],
    'pleasure_receivers': {'sun': 1.0, 'venus': 1.0, 'mercury': 0.5},
    'background_receivers': {'sun': 1.0, 'venus': 1.0, 'jupiter': 0.5},
    'worst_at_or_below': -3.0,
    'bad_at_or_below': -1.0,
    'good_at_or_above': 1.0,
    'best_at_or_above': 3.0,
    'personal_calibration_applied': false,
    'personal_calibration_offset': 0.0,
  };
  static const _slow = {'jupiter', 'saturn', 'uranus', 'neptune', 'pluto'};
  static const _pleasure = {'sun': 1.0, 'venus': 1.0, 'mercury': 0.5};
  static const _background = {'sun': 1.0, 'venus': 1.0, 'jupiter': 0.5};

  static FeltForecastResult unavailable(String reason) =>
      FeltForecastResult(null, {
        'model_version': modelVersion,
        'status': 'not_predicted',
        'unavailable_reason': reason,
      });

  static FeltForecastResult predict({
    required String? natalMoonSign,
    required int? natalMoonHouse,
    required bool? moonInStellium,
    required List<FeltAspect>? allAspects,
    required double? lunarElongationDegrees,
    double? voidDayShare,
  }) {
    if (allAspects == null) return unavailable('missing_or_invalid_aspects');
    final seen = <String>{}, pairs = <String>{};
    for (final a in allAspects) {
      if (!FeltForecastCandidate.planets.contains(a.transitPlanet) ||
          !FeltForecastCandidate.planets.contains(a.natalPlanet) ||
          !FeltForecastCandidate.aspectTypes.contains(a.type) ||
          !a.orb.isFinite ||
          a.orb < 0 ||
          a.orb > 180 ||
          !seen.add(a.identity) ||
          !pairs.add('${a.transitPlanet}/${a.natalPlanet}')) {
        return unavailable('missing_or_invalid_aspects');
      }
    }
    final ordered = allAspects.toList()..sort(_compare);
    final lunar = FeltForecastCandidate.predict(
      natalMoonSign: natalMoonSign,
      natalMoonHouse: natalMoonHouse,
      moonInStellium: moonInStellium,
      aspects: ordered
          .where((a) => a.transitPlanet == 'moon' || a.natalPlanet == 'moon')
          .toList(),
      lunarElongationDegrees: lunarElongationDegrees,
      voidDayShare: voidDayShare,
    );
    if (lunar.label == null) {
      return unavailable(lunar.trace['unavailable_reason'] as String);
    }
    final pleasure = _path(
      ordered.where((a) => a.transitPlanet == 'venus').toList(),
      _pleasure,
      4.0,
      1,
      1.0,
    );
    final background = _path(
      ordered.where((a) => _slow.contains(a.transitPlanet)).toList(),
      _background,
      6.0,
      3,
      2.0,
    );
    final lunarValue = (lunar.trace['label_index_value'] as num).toDouble();
    final value = lunarValue + pleasure.value + background.value;
    final label = FeltForecastCandidate.labelForValue(value);
    return FeltForecastResult(label, {
      'model_version': modelVersion,
      'status': 'trial_unvalidated',
      'inputs': {
        'natal_moon_sign': natalMoonSign,
        'natal_moon_house': natalMoonHouse,
        'moon_in_stellium': moonInStellium,
        'all_major_planet_aspects': [for (final a in ordered) a.toJson()],
        'lunar_elongation_degrees': lunarElongationDegrees,
        'void_day_share': voidDayShare,
      },
      'parameters': parameters,
      'lunar_path': lunar.trace,
      'lunar_predicted_felt_label': lunar.label,
      'pleasure_path': pleasure.trace,
      'background_path': background.trace,
      'lunar_component': lunarValue,
      'pleasure_component': pleasure.value,
      'background_component': background.value,
      'label_index_value': value,
      'predicted_felt_label': label,
      'baseline_felt_label': '普通',
      'natal_sensitivity': lunar.trace['natal_sensitivity'],
      'natal_sensitivity_applied_to': 'lunar_path_only',
      'interpretation': 'whole_day_felt_hypothesis_not_health_or_success',
      'observed_results_used': false,
      'empirically_fitted': false,
      'prospectively_validated': false,
    });
  }

  static ({double value, Map<String, Object?> trace}) _path(
    List<FeltAspect> source,
    Map<String, double> receivers,
    double orbLimit,
    int maximumGroups,
    double limit,
  ) {
    final factors = <Map<String, Object?>>[];
    for (final a in source) {
      final weight = receivers[a.natalPlanet];
      if (weight == null || a.orb >= orbLimit) continue;
      final direction = switch (a.type) {
        'trine' || 'sextile' => 1,
        'square' || 'opposition' => -1,
        'conjunction' when {'venus', 'jupiter'}.contains(a.transitPlanet) => 1,
        _ => 0,
      };
      factors.add({
        ...a.toJson(),
        'id': a.identity,
        'receiver_weight': weight,
        'strength': (1 - a.orb / orbLimit) * weight,
        'direction': direction,
      });
    }
    final groups = <Map<String, Object?>>[];
    for (final planet in FeltForecastCandidate.planets) {
      final members = factors
          .where((f) => f['transit_planet'] == planet)
          .toList();
      if (members.isEmpty) continue;
      Map<String, Object?>? strongest(int? direction) {
        final found =
            members
                .where((f) => direction == null || f['direction'] == direction)
                .toList()
              ..sort((a, b) {
                final d = (b['strength'] as double).compareTo(
                  a['strength'] as double,
                );
                return d != 0
                    ? d
                    : (a['id'] as String).compareTo(b['id'] as String);
              });
        return found.isEmpty ? null : found.first;
      }

      final support = strongest(1),
          tension = strongest(-1),
          stimulus = strongest(null);
      final s = support?['strength'] as double? ?? 0.0;
      final t = tension?['strength'] as double? ?? 0.0;
      groups.add({
        'transit_planet': planet,
        'support': s,
        'tension': t,
        'balance': s - t,
        'stimulus': stimulus!['strength'],
        'support_factor_id': support?['id'],
        'tension_factor_id': tension?['id'],
        'member_factor_ids': [for (final f in members) f['id']],
      });
    }
    final eligible = groups.where((g) => g['balance'] != 0.0).toList()
      ..sort((a, b) {
        final d = (b['balance'] as double).abs().compareTo(
          (a['balance'] as double).abs(),
        );
        return d != 0
            ? d
            : FeltForecastCandidate.planets
                  .indexOf(a['transit_planet'] as String)
                  .compareTo(
                    FeltForecastCandidate.planets.indexOf(
                      b['transit_planet'] as String,
                    ),
                  );
      });
    final selected = eligible.take(maximumGroups).toList();
    final raw = selected.fold(0.0, (v, g) => v + (g['balance'] as double));
    final value = raw.clamp(-limit, limit).toDouble();
    return (
      value: value,
      trace: {
        'orb_limit_exclusive': orbLimit,
        'receiver_weights': receivers,
        'maximum_selected_transit_groups': maximumGroups,
        'limits': [-limit, limit],
        'unclamped_value': raw,
        'value': value,
        'clamp_delta': value - raw,
        'factors': factors,
        'groups': [
          for (final g in groups) {...g, 'selected': selected.contains(g)},
        ],
        'selected_transit_planets': [
          for (final g in selected) g['transit_planet'],
        ],
        'excluded_duplicate_pathway': 'natal_moon_already_in_lunar_path',
      },
    );
  }

  static void validateSnapshot(Map<String, Object?> trace, String? label) {
    if (trace['model_version'] != modelVersion) {
      throw const FormatException('3経路体感のモデル版が違います。');
    }
    if (label == null) {
      final reason = trace['unavailable_reason'];
      if (reason is! String ||
          !{
            'missing_or_invalid_positions',
            'missing_or_invalid_sensitivity',
            'missing_or_invalid_aspects',
            'missing_or_invalid_lunar_phase',
            'invalid_void_day_share',
          }.contains(reason) ||
          !_equal(trace, unavailable(reason).trace)) {
        throw const FormatException('3経路体感の未予測理由が不正です。');
      }
      return;
    }
    final input = trace['inputs'];
    if (input is! Map || input['all_major_planet_aspects'] is! List) {
      throw const FormatException('3経路体感の入力がありません。');
    }
    final aspects = <FeltAspect>[];
    for (final row in input['all_major_planet_aspects'] as List) {
      if (row is! Map ||
          row['transit_planet'] is! String ||
          row['natal_planet'] is! String ||
          row['aspect_type'] is! String ||
          row['orb_degrees'] is! num) {
        throw const FormatException('3経路体感の角度入力が不正です。');
      }
      aspects.add(
        FeltAspect(
          row['transit_planet'] as String,
          row['natal_planet'] as String,
          row['aspect_type'] as String,
          (row['orb_degrees'] as num).toDouble(),
        ),
      );
    }
    final sign = input['natal_moon_sign'],
        house = input['natal_moon_house'],
        stellium = input['moon_in_stellium'],
        phase = input['lunar_elongation_degrees'],
        voidShare = input['void_day_share'];
    if (sign is! String ||
        house is! int ||
        stellium is! bool ||
        phase is! num ||
        (voidShare != null && voidShare is! num)) {
      throw const FormatException('3経路体感の感受性入力が不正です。');
    }
    final expected = predict(
      natalMoonSign: sign,
      natalMoonHouse: house,
      moonInStellium: stellium,
      allAspects: aspects,
      lunarElongationDegrees: phase.toDouble(),
      voidDayShare: (voidShare as num?)?.toDouble(),
    );
    if (label != expected.label || !_equal(trace, expected.trace)) {
      throw const FormatException('3経路体感の内訳・入力・ラベルが一致しません。');
    }
  }

  static int _compare(FeltAspect a, FeltAspect b) =>
      a.identity.compareTo(b.identity);
  static bool _equal(Object? a, Object? b) {
    if (a is num && b is num)
      return a.isFinite && b.isFinite && (a - b).abs() <= 1e-8;
    if (a is Map && b is Map)
      return a.length == b.length &&
          b.keys.every((k) => a.containsKey(k) && _equal(a[k], b[k]));
    if (a is List && b is List)
      return a.length == b.length &&
          List.generate(b.length, (i) => _equal(a[i], b[i])).every((v) => v);
    return a == b;
  }
}
