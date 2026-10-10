part of 'main.dart';

// Presentation of the existing forecast and trace only. Never change a score,
// label, coefficient, selected aspect, or the stored Japanese explanation.
String _englishPlanet(String key) => switch (key) {
  'ascendant' => 'ASC',
  'midheaven' => 'MC',
  _ => key.isEmpty ? key : key[0].toUpperCase() + key.substring(1),
};

String _englishAspectRow(Map row, {String natalKey = 'natal_planet'}) =>
    '${_englishPlanet(row['transit_planet'] as String)} × natal '
    '${_englishPlanet(row[natalKey] as String)} '
    '${row['aspect_type']} ${(row['orb_degrees'] as num).toStringAsFixed(1)}°';

String _englishPredictionDetail(NineAreaPrediction p) {
  if (p.key != NineAreaKey.felt) {
    final description = switch (p.key) {
      NineAreaKey.overall =>
        'The six categories of love, work, money, mental well-being, physical well-being and relationships are averaged before rounding. Activity, felt experience and additional return bonuses are excluded.',
      NineAreaKey.love =>
        'Harmony and tension to natal Venus and the Moon are considered separately. This experimental value concerns intimacy; everyday interaction belongs to Relationships.',
      NineAreaKey.work =>
        'Harmony and tension to the natal Sun and Saturn are considered. Mercury aspects are excluded from direct work bonuses, separating activity from results.',
      NineAreaKey.money =>
        'Harmony and tension to natal Venus, Jupiter and Saturn are considered. Its relationship to income and spending is unverified; it does not guarantee profit.',
      NineAreaKey.mental =>
        'Harmony and tension to the natal Moon, Mercury and Neptune are considered. This is an experimental value for mood and concentration.',
      NineAreaKey.health =>
        'Harmony and tension to the natal Sun, Moon and Mars are considered. Give priority to your actual physical condition.',
      NineAreaKey.people =>
        'Harmony and tension to natal Mercury, Venus and the Moon are considered. This experimental value concerns family, friends and cooperation.',
      NineAreaKey.actionDecision =>
        'Stimulation of natal Mercury and Mars is considered. Harmonious, tense and conjunction aspects all contribute to activity; this is separate from success or correctness of a decision.',
      NineAreaKey.felt => '',
    };
    return '$description\nThe provisional general model limits duplicated contributions from the same transiting planet and uses at most three planet groups. Personal diary adjustments are not applied. Correspondence with actual outcomes remains unverified.';
  }
  final forecast = p.feltForecast;
  final label = const AppStrings(AppLanguage.en).feltLabelText(forecast?.label);
  final trace = forecast?.trace;
  final sections = <String>[];
  if (label == null || trace == null) {
    sections.add(
      'Felt experience is unavailable because the required placements or aspects are missing or invalid. It is not filled in as Normal. Reason: ${trace?['unavailable_reason'] ?? 'not available'}.',
    );
  } else {
    String n(String key) => trace[key] is num
        ? (trace[key] as num).toStringAsFixed(2)
        : 'unavailable';
    final sensitivity = trace['natal_sensitivity'];
    final selected = trace['selected_aspects'];
    final reasons = selected is List
        ? selected.whereType<Map>().map(_englishAspectRow).join(', ')
        : '';
    sections.add(
      'Five-level candidate: $label (experimental and unverified). This is a hypothesis about how the day may feel, not a conversion of the overall, mental or physical well-being scores.\n\n'
      'Natal Moon sensitivity: ${sensitivity is Map ? sensitivity['value'] : 'unavailable'}/100. Stimulation ${n('day_stimulus')}, harmony ${n('harmony')}, tension ${n('tension')} and neutral ${n('neutral')} are calculated separately. '
      'Harmony minus tension ${n('signed_balance')} × sensitivity multiplier ${n('sensitivity_multiplier')} = internal index ${n('label_index_value')}. This is neither a score nor a probability.\n'
      'Selected aspects (at most six): ${reasons.isEmpty ? 'none' : reasons}.\n\n'
      'Unrounded thresholds: ≤−3 Very bad; >−3 and ≤−1 Bad; >−1 and <1 Normal; ≥1 and <3 Good; ≥3 Excellent. Stimulation alone does not determine whether the experience is positive. Moon phases and void periods are reference information with no adjustment here.\n'
      'Compare against always predicting Normal using future dates saved before observation. This does not predict symptoms, accidents or illness, and predictive performance has not been established. Candidate model: ${FeltForecastCandidate.modelVersion}.',
    );
  }
  final comparison = p.feltComparison;
  if (comparison?.label == null) {
    sections.add(
      'Pleasure and longer-term background comparison candidate: not predicted.',
    );
  } else {
    final t = comparison!.trace;
    String n(String key) =>
        t[key] is num ? (t[key] as num).toStringAsFixed(2) : 'unavailable';
    sections.add(
      'Separate comparison candidate including pleasure and longer-term background: ${const AppStrings(AppLanguage.en).feltLabelText(comparison.label)}.\n'
      'Moon ${n('lunar_component')} / pleasure ${n('pleasure_component')} / background ${n('background_component')}.\n'
      'This unverified candidate is stored separately from short-term felt experience, to compare physical strain and satisfaction separately.',
    );
  }
  final background = p.longTermContext;
  if (background == null || background['status'] == 'not_available') {
    sections.add(
      'Longer-term placements: the required astronomical data is unavailable.',
    );
  } else {
    final signs = background['transit_signs'] as Map;
    final jupiter = signs['jupiter'] as Map;
    final sign = ZodiacSign.values[jupiter['sign_index'] as int].name;
    final rows = (background['aspects'] as List).cast<Map>();
    final jupiterRows = rows.where((r) => r['transit_planet'] == 'jupiter');
    final otherRows = rows
        .where((r) => r['transit_planet'] != 'jupiter')
        .take(5);
    String list(Iterable<Map> values) => values.isEmpty
        ? 'no major aspects within 8°'
        : values
              .map((r) => _englishAspectRow(r, natalKey: 'natal_point'))
              .join(', ');
    sections.add(
      'Longer-term placements (reference)\nJupiter: ${_englishPlanet(sign)} ${(jupiter['degree'] as num).toStringAsFixed(1)}°.\n'
      'Jupiter aspects to the natal chart: ${list(jupiterRows)}.\nOther slow planets: ${list(otherRows)}.\n'
      'The short-term Moon candidate may not explain all sustained fulfillment or happiness. A tiring day can still feel satisfying.\n'
      'Sign ingress, natal aspects and returns are separate conditions. This reference panel adds no blanket bonus to scores or the felt candidate. Exact peaks and duration require separate checks.',
    );
  }
  return sections.join('\n\n');
}
