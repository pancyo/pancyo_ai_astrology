part of 'main.dart';

/// Values already calculated by the daily or period reading, for display only.
class SimpleNineAreaItem {
  const SimpleNineAreaItem({
    required this.area,
    required this.title,
    required this.icon,
    required this.narrative,
    this.score,
    this.feltLabel,
    this.feltModes = const [],
  });

  final NineAreaKey area;
  final String title;
  final IconData icon;
  final String narrative;
  final int? score;
  final String? feltLabel;
  final List<String> feltModes;
}

/// The same two Simple-only actions above phone cards and tablet dashboards.
class SimpleReadingShareActions extends StatelessWidget {
  const SimpleReadingShareActions({
    super.key,
    required this.shareSummaryKey,
    required this.shareOverallKey,
    this.onShareSummary,
    this.onShareOverall,
  });

  final Key shareSummaryKey, shareOverallKey;
  final VoidCallback? onShareSummary, onShareOverall;

  @override
  Widget build(BuildContext context) {
    final english =
        AppLanguageScope.stringsOf(context).language == AppLanguage.en;
    return Wrap(
      key: const ValueKey('simple-reading-share-actions'),
      spacing: 12,
      runSpacing: 8,
      children: [
        if (onShareSummary != null)
          OutlinedButton.icon(
            key: shareSummaryKey,
            onPressed: onShareSummary,
            icon: const Icon(Icons.ios_share_outlined, size: 20),
            label: Text(english ? 'Share summary (all 9)' : 'まとめ（全9項目）を共有'),
          ),
        if (onShareOverall != null)
          OutlinedButton.icon(
            key: shareOverallKey,
            onPressed: onShareOverall,
            icon: const Icon(Icons.ios_share_outlined, size: 20),
            label: Text(english ? 'Share overall only' : '総合運のみ共有'),
          ),
      ],
    );
  }
}

/// The spacious tablet Simple view shared by all five reading periods.
/// It has no evidence affordance and does not construct detailed explanations.
class SimpleNineAreaDashboard extends StatelessWidget {
  const SimpleNineAreaDashboard({
    super.key,
    required this.items,
    required this.highlights,
    required this.mainFiveKey,
    required this.additionalFourKey,
    required this.cardKeyPrefix,
    required this.valueKeyPrefix,
    required this.narrativeKeyPrefix,
    required this.shareSummaryKey,
    required this.shareOverallKey,
    this.onShareSummary,
    this.onShareOverall,
  });

  final List<SimpleNineAreaItem> items;
  final OverallAreaHighlights highlights;
  final Key mainFiveKey, additionalFourKey;
  final String cardKeyPrefix, valueKeyPrefix, narrativeKeyPrefix;
  final Key shareSummaryKey, shareOverallKey;
  final VoidCallback? onShareSummary, onShareOverall;

  static const mainAreas = [
    NineAreaKey.overall,
    NineAreaKey.love,
    NineAreaKey.work,
    NineAreaKey.money,
    NineAreaKey.mental,
  ];

  @override
  Widget build(BuildContext context) {
    final strings = AppLanguageScope.stringsOf(context);
    final english = strings.language == AppLanguage.en;
    final main = [
      for (final area in mainAreas) ...items.where((item) => item.area == area),
    ];
    final additional = items
        .where((item) => !mainAreas.contains(item.area))
        .toList();
    Widget tile(SimpleNineAreaItem item) => _SimpleNineAreaTile(
      key: ValueKey('$cardKeyPrefix-${item.area.name}'),
      item: item,
      valueKey: ValueKey('$valueKeyPrefix-${item.area.name}'),
      narrativeKey: ValueKey('$narrativeKeyPrefix-${item.area.name}'),
      highlights: item.area == NineAreaKey.overall ? highlights : null,
    );
    Widget pairs(List<SimpleNineAreaItem> group) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < group.length; index += 2) ...[
          if (index > 0) const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: tile(group[index])),
              if (index + 1 < group.length) ...[
                const SizedBox(width: 14),
                Expanded(child: tile(group[index + 1])),
              ] else
                const Expanded(child: SizedBox.shrink()),
            ],
          ),
        ],
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (onShareSummary != null || onShareOverall != null) ...[
          SimpleReadingShareActions(
            shareSummaryKey: shareSummaryKey,
            shareOverallKey: shareOverallKey,
            onShareSummary: onShareSummary,
            onShareOverall: onShareOverall,
          ),
          const SizedBox(height: 12),
        ],
        Column(
          key: mainFiveKey,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              english ? 'Five main categories' : '主要5項目',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            if (main.isNotEmpty) tile(main.first),
            if (main.length > 1) ...[
              const SizedBox(height: 14),
              pairs(main.skip(1).toList()),
            ],
          ],
        ),
        if (additional.isNotEmpty) ...[
          const SizedBox(height: 20),
          Column(
            key: additionalFourKey,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                english ? 'Four additional categories' : '追加4項目',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              pairs(additional),
              const SizedBox(height: 12),
              Text(
                english
                    ? 'All nine categories are experimental and unvalidated.'
                    : '9項目すべて一般向け暫定式・未検証です。',
                style: const TextStyle(fontSize: 16, color: Color(0xFFB8C6E0)),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SimpleNineAreaTile extends StatelessWidget {
  const _SimpleNineAreaTile({
    super.key,
    required this.item,
    required this.valueKey,
    required this.narrativeKey,
    this.highlights,
  });

  final SimpleNineAreaItem item;
  final Key valueKey, narrativeKey;
  final OverallAreaHighlights? highlights;

  Widget _badge(BuildContext context, double size) {
    final strings = AppLanguageScope.stringsOf(context);
    final english = strings.language == AppLanguage.en;
    if (item.area == NineAreaKey.felt) {
      if (item.feltModes.length > 1) {
        return Tooltip(
          message: english
              ? 'Tied most frequent: ${item.feltModes.map(strings.feltLabelText).join(' / ')}. No numeric conversion.'
              : '最多同数：${item.feltModes.join('・')}。数値には変換しません。',
          child: Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xEE121528),
              border: Border.all(color: Colors.white70, width: 2),
            ),
            child: Text(
              english ? 'Mixed\nFelt' : '混在\n体感',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
          ),
        );
      }
      return FeltFortuneBadge(label: item.feltLabel, fixedSize: size);
    }
    if (item.score == null) {
      return SizedBox(
        width: size,
        child: Text(
          english ? 'Not predicted' : '未予測',
          style: const TextStyle(fontSize: 16),
        ),
      );
    }
    return FortuneNumber(
      score: item.score!,
      fixedSize: size,
      shortLabel: item.area == NineAreaKey.actionDecision
          ? (english ? 'Activity' : '活動性')
          : null,
      label: item.area == NineAreaKey.actionDecision
          ? (english
                ? 'Experimental activity level; not success or decision correctness.'
                : '活動性の試作値。成功や判断の正しさではありません')
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLanguageScope.stringsOf(context);
    final english = strings.language == AppLanguage.en;
    final overall = item.area == NineAreaKey.overall;
    final scaler = MediaQuery.textScalerOf(context);
    final preferredBadgeSize = scaler.scale(
      overall ? dailyOverallFortuneBadgeSize : dailyFortuneBadgeSize,
    );
    const body = TextStyle(fontSize: 14, height: 1.45);
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(item.icon, size: 20, color: const Color(0xFFF6D77A)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                item.title,
                style: TextStyle(
                  fontSize: overall ? 20 : 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(item.narrative, key: narrativeKey, style: body),
        if (item.area == NineAreaKey.felt && item.feltModes.length > 1) ...[
          const SizedBox(height: 12),
          Text(
            item.feltModes
                .map((label) => english ? strings.feltLabelText(label) : label)
                .join(english ? ' / ' : '・'),
            style: body,
          ),
        ],
      ],
    );
    return GlassPanel(
      padding: const EdgeInsets.all(18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final badgeSize = math.min(preferredBadgeSize, constraints.maxWidth);
          final badge = KeyedSubtree(
            key: valueKey,
            child: _badge(context, badgeSize),
          );
          final highlightBlock = highlights == null
              ? null
              : OverallAreaHighlightsBlock(
                  highlights: highlights!,
                  strings: strings,
                  style: body,
                );
          if (overall &&
              highlightBlock != null &&
              constraints.maxWidth >= scaler.scale(600)) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                badge,
                const SizedBox(width: 14),
                Expanded(flex: 3, child: copy),
                const SizedBox(width: 20),
                Expanded(flex: 2, child: highlightBlock),
              ],
            );
          }
          final horizontal =
              constraints.maxWidth >= badgeSize + 14 + scaler.scale(150);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (horizontal)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    badge,
                    const SizedBox(width: 14),
                    Expanded(child: copy),
                  ],
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [badge, const SizedBox(height: 14), copy],
                ),
              if (highlightBlock != null) ...[
                const SizedBox(height: 14),
                highlightBlock,
              ],
            ],
          );
        },
      ),
    );
  }
}
