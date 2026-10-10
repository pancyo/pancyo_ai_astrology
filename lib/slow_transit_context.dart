/// Describes longer lasting configurations without fitting personal diary data.
/// It never returns a score, a felt label, or a probability.
class SlowTransitContext {
  const SlowTransitContext._();

  static const version = 'slow-transit-context-20261003-1';
  static const planets = [
    'sun', 'moon', 'mercury', 'venus', 'mars', 'jupiter',
    'saturn', 'uranus', 'neptune', 'pluto',
  ];
  static const slowPlanets = ['jupiter', 'saturn', 'uranus', 'neptune', 'pluto'];
  static const angles = {
    'conjunction': 0.0, 'sextile': 60.0, 'square': 90.0,
    'trine': 120.0, 'opposition': 180.0,
  };
  static const orbLimit = 8.0;

  static Map<String, Object?> unavailable() => {
    'context_version': version,
    'status': 'not_available',
    'reason': 'missing_or_invalid_positions',
    'score_effect': 0,
    'predicts_felt_label': false,
  };

  static Map<String, Object?> describe({
    required Map<String, double> natalLongitudes,
    required Map<String, double> transitLongitudes,
    required bool usesHighPrecisionAstroData,
  }) {
    bool valid(Map<String, double> source, Set<String> allowed) =>
        source.entries.every((entry) => allowed.contains(entry.key) &&
            entry.value.isFinite && entry.value >= 0 && entry.value < 360);
    if (!valid(natalLongitudes, {...planets, 'ascendant', 'midheaven'}) ||
        !valid(transitLongitudes, planets.toSet()) ||
        !planets.every(natalLongitudes.containsKey) ||
        !slowPlanets.every(transitLongitudes.containsKey)) {
      return unavailable();
    }
    final aspects = <Map<String, Object?>>[];
    final targets = [...planets, 'ascendant', 'midheaven'];
    for (final planet in slowPlanets) {
      final longitude = transitLongitudes[planet]!;
      for (final target in targets) {
        final natal = natalLongitudes[target];
        if (natal == null) continue;
        final separation = ((longitude - natal + 180) % 360 - 180).abs();
        for (final angle in angles.entries) {
          final orb = (separation - angle.value).abs();
          if (orb > orbLimit) continue;
          aspects.add({
            'transit_planet': planet,
            'natal_point': target,
            'aspect_type': angle.key,
            'orb_degrees': orb,
            'configuration_kind': switch (angle.key) {
              'trine' || 'sextile' => 'harmonious',
              'square' || 'opposition' => 'tense',
              _ => 'conjunction',
            },
          });
        }
      }
    }
    aspects.sort((a, b) {
      final planet = slowPlanets.indexOf(a['transit_planet'] as String)
          .compareTo(slowPlanets.indexOf(b['transit_planet'] as String));
      if (planet != 0) return planet;
      final orb = (a['orb_degrees'] as double).compareTo(b['orb_degrees'] as double);
      if (orb != 0) return orb;
      return targets.indexOf(a['natal_point'] as String)
          .compareTo(targets.indexOf(b['natal_point'] as String));
    });
    return {
      'context_version': version,
      'status': 'configuration_only_unvalidated',
      'uses_high_precision_astro_data': usesHighPrecisionAstroData,
      'reference': 'provided_transit_positions_against_natal_chart',
      'score_effect': 0,
      'predicts_felt_label': false,
      'orb_limit_inclusive_degrees': orbLimit,
      'transit_signs': {
        for (final planet in slowPlanets)
          planet: {
            'sign_index': (transitLongitudes[planet]! / 30).floor(),
            'degree': transitLongitudes[planet]! % 30,
          },
      },
      'natal_angles_available': [
        for (final target in ['ascendant', 'midheaven'])
          if (natalLongitudes.containsKey(target)) target,
      ],
      'aspects': aspects,
      'interpretation': '月から見る短期体感候補とは別の、木星など遅い星の配置。調和と緊張を併記する。満足感・体調・活動の成否を同一視しない。',
      'limitations': [
        '配置の持続期間や正確なピークをこの一時点だけで確定しない',
        '星座入り・出生図との角度・リターンはそれぞれ別の条件',
        '良い体感と疲労・トラブルは同じ日に共存し得る',
        '個人日記から一般利用者の加点係数を決めたものではない',
      ],
    };
  }
}
