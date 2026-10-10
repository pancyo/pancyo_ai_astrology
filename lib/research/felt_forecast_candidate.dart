/// 事前固定した体感5段階の仮説。運勢点・確率・診断ではない。
/// Flutterや本人の結果記録に依存せず、予測JSONの根拠も再計算できる。
class FeltForecastCandidate {
  const FeltForecastCandidate._();

  static const nineAreaModelVersion = 'nine-area-trial-20260930-2';
  // UTC入力の星計算を修正する前の予測も、差し替えず別版として照合できる。
  static const supportedNineAreaModelVersions = {
    'nine-area-trial-20260930-1',
    nineAreaModelVersion,
  };
  static const modelVersion = 'felt-lunar-balance-20260930-1';
  static const labels = ['最悪', '悪い', '普通', '良い', '最高'];
  static const planets = [
    'sun',
    'moon',
    'mercury',
    'venus',
    'mars',
    'jupiter',
    'saturn',
    'uranus',
    'neptune',
    'pluto',
  ];
  static const signs = [
    'aries',
    'taurus',
    'gemini',
    'cancer',
    'leo',
    'virgo',
    'libra',
    'scorpio',
    'sagittarius',
    'capricorn',
    'aquarius',
    'pisces',
  ];
  static const aspectTypes = [
    'conjunction',
    'sextile',
    'square',
    'trine',
    'opposition',
  ];
  static const _unavailableReasons = {
    'missing_or_invalid_positions',
    'missing_or_invalid_sensitivity',
    'missing_or_invalid_aspects',
    'missing_or_invalid_lunar_phase',
    'invalid_void_day_share',
  };

  static FeltForecastResult unavailable(String reason) {
    if (!_unavailableReasons.contains(reason)) {
      throw ArgumentError.value(reason, 'reason');
    }
    return FeltForecastResult(null, {
      'model_version': modelVersion,
      'status': 'not_predicted',
      'unavailable_reason': reason,
    });
  }

  static FeltForecastResult predict({
    required String? natalMoonSign,
    required int? natalMoonHouse,
    required bool? moonInStellium,
    required List<FeltAspect>? aspects,
    required double? lunarElongationDegrees,
    double? voidDayShare,
  }) {
    if (!signs.contains(natalMoonSign) ||
        natalMoonHouse == null ||
        natalMoonHouse < 1 ||
        natalMoonHouse > 12 ||
        moonInStellium == null) {
      return unavailable('missing_or_invalid_sensitivity');
    }
    if (aspects == null) return unavailable('missing_or_invalid_aspects');
    final seen = <String>{};
    for (final aspect in aspects) {
      if (!planets.contains(aspect.transitPlanet) ||
          !planets.contains(aspect.natalPlanet) ||
          (aspect.transitPlanet != 'moon' && aspect.natalPlanet != 'moon') ||
          !aspectTypes.contains(aspect.type) ||
          !aspect.orb.isFinite ||
          aspect.orb < 0 ||
          aspect.orb > 180 ||
          !seen.add(aspect.identity)) {
        return unavailable('missing_or_invalid_aspects');
      }
    }
    if (lunarElongationDegrees == null ||
        !lunarElongationDegrees.isFinite ||
        lunarElongationDegrees < 0 ||
        lunarElongationDegrees >= 360) {
      return unavailable('missing_or_invalid_lunar_phase');
    }
    if (voidDayShare != null &&
        (!voidDayShare.isFinite || voidDayShare < 0 || voidDayShare > 1)) {
      return unavailable('invalid_void_day_share');
    }
    final ordered = aspects.toList()..sort(_compare);
    final candidates = ordered.where((aspect) => aspect.orb < 4).toList();
    final selected = candidates.take(6).toList();
    final sensitivityFactors = <String, int>{
      'angular_house': {1, 4, 7, 10}.contains(natalMoonHouse) ? 15 : 0,
      'house_8_or_12': {8, 12}.contains(natalMoonHouse) ? 10 : 0,
      'water_sign': {'cancer', 'scorpio', 'pisces'}.contains(natalMoonSign)
          ? 10
          : 0,
      'cancer': natalMoonSign == 'cancer' ? 8 : 0,
      'moon_stellium': moonInStellium ? 8 : 0,
    };
    final sensitivityRaw =
        52 + sensitivityFactors.values.fold(0, (a, b) => a + b);
    final sensitivity = sensitivityRaw.clamp(38, 95).toInt();
    var harmony = 0.0, tension = 0.0, neutral = 0.0;
    final factors = <Map<String, Object?>>[];
    for (final aspect in selected) {
      final strength = 1 - aspect.orb / 4;
      final direction = switch (aspect.type) {
        'trine' || 'sextile' => 1,
        'square' || 'opposition' => -1,
        _ => 0,
      };
      if (direction > 0) harmony += strength;
      if (direction < 0) tension += strength;
      if (direction == 0) neutral += strength;
      factors.add({
        ...aspect.toJson(),
        'strength': strength,
        'direction': direction,
        'signed_value': strength * direction,
      });
    }
    final multiplier = 0.75 + sensitivity / 100 * 0.5;
    final balance = harmony - tension;
    final value = balance * multiplier;
    final label = labelForValue(value);
    return FeltForecastResult(label, {
      'model_version': modelVersion,
      'status': 'trial_unvalidated',
      'inputs': {
        'natal_moon_sign': natalMoonSign,
        'natal_moon_house': natalMoonHouse,
        'moon_in_stellium': moonInStellium,
        'moon_related_aspects': [for (final aspect in ordered) aspect.toJson()],
        'lunar_elongation_degrees': lunarElongationDegrees,
        'void_day_share': voidDayShare,
      },
      'parameters': {
        'orb_limit_exclusive': 4,
        'maximum_selected_aspects': 6,
        'sensitivity_base': 52,
        'sensitivity_limits': [38, 95],
        'multiplier_base': 0.75,
        'multiplier_sensitivity_weight': 0.5,
        'worst_at_or_below': -3,
        'bad_at_or_below': -1,
        'good_at_or_above': 1,
        'best_at_or_above': 3,
        'lunar_phase_weight': 0,
        'void_weight': 0,
      },
      'natal_sensitivity': {
        'factors': sensitivityFactors,
        'raw': sensitivityRaw,
        'value': sensitivity,
      },
      'candidate_aspect_count': candidates.length,
      'selected_aspects': factors,
      'day_stimulus': harmony + tension + neutral,
      'harmony': harmony,
      'tension': tension,
      'neutral': neutral,
      'signed_balance': balance,
      'sensitivity_multiplier': multiplier,
      'label_index_value': value,
      'predicted_felt_label': label,
      'baseline_felt_label': '普通',
      'void_context': voidDayShare == null
          ? 'period_not_provided'
          : 'one_provided_period',
    });
  }

  static String labelForValue(double value) {
    if (!value.isFinite) throw const FormatException('体感の内部指標は有限値に限ります。');
    return switch (value) {
      <= -3 => '最悪',
      <= -1 => '悪い',
      < 1 => '普通',
      < 3 => '良い',
      _ => '最高',
    };
  }

  /// 値・ラベル・入力・係数の整合性を検査する。真正性や事前性の証明ではない。
  static void validateSnapshot(Map<String, Object?> trace, String? label) {
    if (trace['model_version'] != modelVersion) {
      throw const FormatException('体感の候補式版が違います。');
    }
    if (label == null) {
      final reason = trace['unavailable_reason'];
      if (reason is! String ||
          !_unavailableReasons.contains(reason) ||
          !_equal(trace, unavailable(reason).trace)) {
        throw const FormatException('体感の未予測理由が不正です。');
      }
      return;
    }
    final raw = trace['inputs'];
    if (raw is! Map) throw const FormatException('体感の計算入力がありません。');
    final input = Map<String, Object?>.from(raw);
    final sign = input['natal_moon_sign'];
    final house = input['natal_moon_house'];
    final stellium = input['moon_in_stellium'];
    final phase = input['lunar_elongation_degrees'];
    final voidShare = input['void_day_share'];
    final rawAspects = input['moon_related_aspects'];
    if (sign is! String ||
        house is! int ||
        stellium is! bool ||
        phase is! num ||
        (voidShare != null && voidShare is! num) ||
        rawAspects is! List) {
      throw const FormatException('体感の計算入力の形式が不正です。');
    }
    final aspects = <FeltAspect>[];
    for (final rawAspect in rawAspects) {
      if (rawAspect is! Map ||
          rawAspect['transit_planet'] is! String ||
          rawAspect['natal_planet'] is! String ||
          rawAspect['aspect_type'] is! String ||
          rawAspect['orb_degrees'] is! num) {
        throw const FormatException('体感の角度入力が不正です。');
      }
      aspects.add(
        FeltAspect(
          rawAspect['transit_planet'] as String,
          rawAspect['natal_planet'] as String,
          rawAspect['aspect_type'] as String,
          (rawAspect['orb_degrees'] as num).toDouble(),
        ),
      );
    }
    final expected = predict(
      natalMoonSign: sign,
      natalMoonHouse: house,
      moonInStellium: stellium,
      aspects: aspects,
      lunarElongationDegrees: phase.toDouble(),
      voidDayShare: (voidShare as num?)?.toDouble(),
    );
    if (expected.label != label || !_equal(trace, expected.trace)) {
      throw const FormatException('体感の入力・係数・計算内訳・5段階ラベルが一致しません。');
    }
  }

  static int _compare(FeltAspect a, FeltAspect b) {
    var difference = a.orb.compareTo(b.orb);
    if (difference != 0) return difference;
    difference = planets
        .indexOf(a.transitPlanet)
        .compareTo(planets.indexOf(b.transitPlanet));
    if (difference != 0) return difference;
    difference = planets
        .indexOf(a.natalPlanet)
        .compareTo(planets.indexOf(b.natalPlanet));
    return difference != 0
        ? difference
        : aspectTypes.indexOf(a.type).compareTo(aspectTypes.indexOf(b.type));
  }

  static bool _equal(Object? a, Object? b) {
    if (a is num && b is num)
      return a.isFinite && b.isFinite && (a - b).abs() <= 1e-8;
    if (a is Map && b is Map)
      return a.length == b.length &&
          b.keys.every((key) => a.containsKey(key) && _equal(a[key], b[key]));
    if (a is List && b is List)
      return a.length == b.length &&
          List.generate(
            b.length,
            (i) => _equal(a[i], b[i]),
          ).every((value) => value);
    return a == b;
  }
}

class FeltAspect {
  const FeltAspect(this.transitPlanet, this.natalPlanet, this.type, this.orb);
  final String transitPlanet, natalPlanet, type;
  final double orb;
  String get identity => '$transitPlanet/$natalPlanet/$type';
  Map<String, Object?> toJson() => {
    'transit_planet': transitPlanet,
    'natal_planet': natalPlanet,
    'aspect_type': type,
    'orb_degrees': orb,
  };
}

class FeltForecastResult {
  const FeltForecastResult(this.label, this.trace);
  final String? label;
  final Map<String, Object?> trace;
}
