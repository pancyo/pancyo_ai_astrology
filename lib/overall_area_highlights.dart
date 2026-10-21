part of 'main.dart';

/// Display groups for seven numeric areas, including activity.
/// These thresholds never calculate, adjust, average, or serialize a score.
class OverallAreaHighlights {
  OverallAreaHighlights._(
    Map<NineAreaKey, int> scores,
    List<NineAreaKey> missing,
  ) : scores = Map.unmodifiable(scores),
      missing = List.unmodifiable(missing);

  /// Highlight scope only: the six outcome areas plus activity. This does not
  /// define or alter the overall score's existing six-outcome-area average.
  static const highlightKeys = <NineAreaKey>[
    NineAreaKey.love,
    NineAreaKey.work,
    NineAreaKey.money,
    NineAreaKey.mental,
    NineAreaKey.health,
    NineAreaKey.people,
    NineAreaKey.actionDecision,
  ];

  /// Available final displayed values, in the usual seven-area display order.
  final Map<NineAreaKey, int> scores;
  final List<NineAreaKey> missing;

  factory OverallAreaHighlights.fromPredictions(
    List<NineAreaPrediction> predictions,
  ) => OverallAreaHighlights._fromValues([
    for (final prediction in predictions)
      MapEntry(prediction.key, prediction.score),
  ]);

  /// Uses each entry's final displayed score, including inherited period
  /// values. Raw samples and graph points are deliberately not averaged here.
  factory OverallAreaHighlights.fromSummary(NineAreaPeriodSummary summary) =>
      OverallAreaHighlights._fromValues([
        for (final area in summary.areas) MapEntry(area.key, area.score),
      ]);

  factory OverallAreaHighlights._fromValues(
    List<MapEntry<NineAreaKey, int?>> values,
  ) {
    final scores = <NineAreaKey, int>{};
    final missing = <NineAreaKey>[];
    for (final key in highlightKeys) {
      final matches = values.where((entry) => entry.key == key).toList();
      final score = matches.length == 1 ? matches.single.value : null;
      // Incomplete, ambiguous or out-of-contract input remains unavailable.
      // It must never become a zero-valued caution item.
      if (score == null || score < 50 || score > 99) {
        missing.add(key);
      } else {
        scores[key] = score;
      }
    }
    return OverallAreaHighlights._(scores, missing);
  }

  Map<NineAreaKey, int> get higher => Map.unmodifiable({
    for (final entry in scores.entries)
      if (entry.value >= 80) entry.key: entry.value,
  });

  Map<NineAreaKey, int> get careNeeded => Map.unmodifiable({
    for (final entry in scores.entries)
      if (entry.value <= 70) entry.key: entry.value,
  });

  /// Two ordinary lines, plus one shared missing-data line when necessary.
  /// Callers may put [text] in a separate share-card Text so its lines do not
  /// pass through the narrative's 120/240-rune preview limit.
  List<String> lines(AppStrings strings) {
    final english = strings.language == AppLanguage.en;
    final separator = english ? ': ' : '：';
    String group(Map<NineAreaKey, int> entries) {
      if (entries.isNotEmpty) {
        return entries.entries
            .map(
              (entry) =>
                  '${strings.nineAreaTitle(entry.key.name)}${english ? ' ' : ''}${entry.value}',
            )
            .join(english ? ', ' : '・');
      }
      if (scores.isEmpty) return english ? 'Unavailable' : '未予測';
      if (missing.isNotEmpty) {
        return english ? 'None among available areas' : '確認済みでは該当なし';
      }
      return english ? 'None' : '該当なし';
    }

    return [
      '${english ? 'Higher (80+)' : '高め（80点以上）'}$separator${group(higher)}',
      '${english ? 'Care needed (70 or below)' : '注意（70点以下）'}$separator${group(careNeeded)}',
      if (missing.isNotEmpty)
        '${english ? 'Unavailable: ' : '未取得：'}${missing.length == highlightKeys.length ? (english ? 'all 7 areas' : '全7項目') : missing.map((key) => strings.nineAreaTitle(key.name)).join(english ? ', ' : '・')}',
    ];
  }

  String text(AppStrings strings) => lines(strings).join('\n');
}

/// Body-sized text with ordinary wrapping; text scaling is inherited.
class OverallAreaHighlightsBlock extends StatelessWidget {
  const OverallAreaHighlightsBlock({
    super.key,
    required this.highlights,
    required this.strings,
    this.style,
  });

  final OverallAreaHighlights highlights;
  final AppStrings strings;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final line in highlights.lines(strings))
        Text(
          line,
          style: Theme.of(context).textTheme.bodyMedium?.merge(style) ?? style,
          softWrap: true,
        ),
    ],
  );
}
