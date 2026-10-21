part of 'main.dart';

/// Presents one already-calculated canonical seven-point snapshot. This widget
/// never calls an ephemeris, scoring engine, period average or JSON writer.
class PeriodSevenReadingCards extends StatelessWidget {
  const PeriodSevenReadingCards({
    super.key,
    required this.snapshot,
    required this.targetDate,
    required this.displayTime,
    required this.details,
    this.depth = ReadingDepth.simple,
  });

  final Map<String, Object?> snapshot;

  /// The selected point's real UTC instant, including the next day at 24:00.
  final DateTime targetDate;
  final String displayTime;
  final UserProfileDetails details;
  final ReadingDepth depth;

  static const _times = {
    '00:00',
    '04:00',
    '08:00',
    '12:00',
    '16:00',
    '20:00',
    '24:00',
  };

  static String _date(DateTime civil) =>
      '${civil.year.toString().padLeft(4, '0')}-'
      '${civil.month.toString().padLeft(2, '0')}-'
      '${civil.day.toString().padLeft(2, '0')}';

  String _birthInputNotice(bool english) {
    final assumptions = <String>[
      if (!details.hasBirthTime)
        english
            ? 'Birth time is missing (existing assumption: 12:00).'
            : '出生時刻は未入力です（既存の仮置き：12:00）。',
      if (!details.hasBirthPlace)
        english
            ? 'Birthplace is missing (existing assumption: Sapporo, Hokkaido).'
            : '出生地は未入力です（既存の仮置き：北海道札幌市）。',
    ];
    if (assumptions.isEmpty) return '';
    return '${assumptions.join(' ')} ${english ? 'Moon and house readings that depend on these inputs use the assumed conditions.' : '月・ハウスなど、これらの入力に依存する読みは仮置き条件によります。'}';
  }

  String _calculationNotice(bool english) {
    // This flag is recorded with the selected snapshot. Do not infer the
    // historical provider from the currently selected global data source.
    final highPrecision = snapshot['uses_high_precision_astro_data'];
    final precision = highPrecision == true
        ? (english ? 'used' : '使用')
        : highPrecision == false
        ? (english ? 'not used' : '未使用')
        : (english ? 'not recorded' : '未記録');
    return english
        ? 'Recorded high-precision astronomical data: $precision.'
        : '記録された高精度天文データ：$precision。';
  }

  bool _matchesInstant() {
    if (!targetDate.isUtc || !_times.contains(displayTime)) return false;
    final jst = targetDate.add(const Duration(hours: 9));
    final hour = displayTime == '24:00'
        ? 0
        : int.parse(displayTime.substring(0, 2));
    if (jst.hour != hour ||
        jst.minute != 0 ||
        jst.second != 0 ||
        jst.millisecond != 0 ||
        jst.microsecond != 0 ||
        snapshot['target_date_jst'] != _date(jst)) {
      return false;
    }
    final reference = snapshot['calculation_reference_jst'];
    if (reference is! String || !reference.endsWith('+09:00')) return false;
    return DateTime.tryParse(reference)?.toUtc() == targetDate;
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLanguageScope.stringsOf(context);
    final english = strings.language == AppLanguage.en;
    final validTime = _matchesInstant();
    final raw = snapshot['areas'];
    final rows = <NineAreaKey, List<Map<String, Object?>>>{};
    var invalidStructure = raw is! List;
    if (raw is List) {
      invalidStructure = raw.length != NineAreaKey.values.length;
      for (final value in raw) {
        try {
          if (value is! Map || value['key'] is! String) {
            invalidStructure = true;
            continue;
          }
          final area = Map<String, Object?>.from(value);
          final key = NineAreaKey.values.byName(area['key'] as String);
          rows.putIfAbsent(key, () => []).add(area);
        } catch (_) {
          invalidStructure = true;
        }
      }
    }
    final relatedPredictions = <NineAreaPrediction>[];
    for (final key in NineAreaKey.values) {
      final candidates = rows[key];
      if (!validTime || candidates == null || candidates.length != 1) continue;
      try {
        relatedPredictions.add(_prediction(candidates.single, key));
      } catch (_) {
        invalidStructure = true;
      }
    }
    final readings = <NineAreaKey, ForecastExplanationResult?>{};
    for (final key in NineAreaKey.values) {
      final candidates = rows[key];
      if (!validTime || candidates == null || candidates.length != 1) {
        readings[key] = null;
        invalidStructure = true;
        continue;
      }
      try {
        readings[key] = ForecastExplanation.forDaily(
          prediction: relatedPredictions.singleWhere(
            (value) => value.key == key,
          ),
          targetDate: targetDate,
          strings: strings,
          depth: depth,
          supplement: details,
          relatedPredictions: relatedPredictions,
        );
      } catch (_) {
        // Corrupt or incomplete input stays unavailable. Never infer a score,
        // reuse another time, or insert a presumed Normal felt candidate.
        readings[key] = null;
        invalidStructure = true;
      }
    }
    final incomplete =
        invalidStructure ||
        readings.values.any(
          (value) => value == null || value.status == 'not_predicted',
        );
    final jst = targetDate.toUtc().add(const Duration(hours: 9));
    final displayedDay = displayTime == '24:00'
        ? jst.subtract(const Duration(days: 1))
        : jst;
    final birthInputNotice = _birthInputNotice(english);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : 390.0;
        final columns = math.max(1, math.min(3, (width / 350).floor()));
        const spacing = 16.0;
        final cardWidth = (width - spacing * (columns - 1)) / columns;
        final bodySize = width >= 700 ? 18.0 : 16.0;
        final targetLabel = Text(
          validTime
              ? '${_date(displayedDay)} $displayTime'
                    '${displayTime == '24:00' ? ' = ${_date(jst)} 00:00' : ''}'
                    ' JST (UTC+09:00)'
              : (english ? 'Selected time unavailable' : '選択時刻を確認できません'),
          key: const ValueKey('seven-reading-target'),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (validTime && displayTime == '24:00')
              KeyedSubtree(
                key: const ValueKey('seven-reading-boundary'),
                child: targetLabel,
              )
            else
              targetLabel,
            if (incomplete) ...[
              const SizedBox(height: 12),
              Text(
                !validTime
                    ? (english
                          ? 'The snapshot and selected time do not match. Readings are unavailable for this selection.'
                          : '保存された時刻と選択時刻が一致しないため、この選択の占いは未予測として表示します。')
                    : (english
                          ? 'Some required data is missing or invalid. Affected areas remain Not predicted.'
                          : '必要なデータに不足または不整合があります。該当する項目は未予測のまま表示します。'),
                key: const ValueKey('seven-reading-partial-warning'),
                style: TextStyle(
                  fontSize: bodySize,
                  height: 1.4,
                  color: const Color(0xFFFFD987),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final key in NineAreaKey.values)
                  SizedBox(
                    width: cardWidth,
                    child: _PeriodSevenReadingCard(
                      key: ValueKey('seven-reading-card-${key.name}'),
                      area: key,
                      explanation: readings[key],
                      strings: strings,
                      bodySize: bodySize,
                      depth: depth,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Material(
              color: Colors.transparent,
              child: ExpansionTile(
                key: const ValueKey('seven-reading-settings'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 12),
                title: Text(
                  english ? 'Reading settings' : 'この占いの条件',
                  style: TextStyle(
                    fontSize: bodySize,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          english
                              ? 'Experimental readings for this selected time. Eight numeric areas and a non-numeric felt candidate; no new weekly or monthly average score. Choose from 00:00, 04:00, 08:00, 12:00, 16:00, 20:00 and 24:00 JST. Noon is one of these seven points; 24:00 is the next day’s 00:00.'
                              : '選んだ時刻の試作値による占いです。8項目の点数と、数値化しない体感候補を表示します。新しい週・月の平均点ではありません。JSTの00・04・08・12・16・20・24時から選びます。正午は7点のうちの1点で、24時は翌日00時です。',
                          style: TextStyle(
                            fontSize: bodySize,
                            height: 1.4,
                            color: const Color(0xFFB8C6E0),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _calculationNotice(english),
                          key: const ValueKey(
                            'seven-reading-calculation-source',
                          ),
                          style: TextStyle(
                            fontSize: bodySize,
                            height: 1.4,
                            color: const Color(0xFFB8C6E0),
                          ),
                        ),
                        if (birthInputNotice.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            birthInputNotice,
                            key: const ValueKey(
                              'seven-reading-birth-assumptions',
                            ),
                            style: TextStyle(
                              fontSize: bodySize,
                              height: 1.4,
                              color: const Color(0xFFFFD987),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// Same canonical reconstruction as _dailyPresentationExplanation; only
  /// validation and presentation are performed, never a calculation pass.
  static NineAreaPrediction _prediction(
    Map<String, Object?> area,
    NineAreaKey key,
  ) {
    Map<String, Object?>? object(Object? value) => value == null
        ? null
        : value is Map
        ? Map<String, Object?>.from(value)
        : throw const FormatException('Invalid explanation object.');
    FeltForecastResult? felt(Map<String, Object?>? value) {
      if (value == null) return null;
      final label = value['predicted_felt_label'];
      final trace = object(value['felt_prediction']);
      if ((label != null && label is! String) || trace == null) {
        throw const FormatException('Invalid felt comparison.');
      }
      return FeltForecastResult(label as String?, trace);
    }

    final score = area['score'];
    final label = area['predicted_felt_label'];
    if ((score != null && score is! int) ||
        (label != null && label is! String) ||
        area['name'] is! String ||
        area['summary'] is! String ||
        area['explanation'] is! String ||
        (area['status'] == 'not_predicted' &&
            (score != null || label != null))) {
      throw const FormatException('Invalid canonical forecast area.');
    }
    final trace = object(area['felt_prediction']);
    return NineAreaPrediction(
      key: key,
      title: area['name'] as String,
      icon: Icons.auto_awesome,
      summary: area['summary'] as String,
      detail: area['explanation'] as String,
      score: score as int?,
      provisional: area['status'] == 'trial_unvalidated',
      scoreBreakdown: object(area['score_breakdown']),
      feltForecast: trace == null
          ? null
          : FeltForecastResult(label as String?, trace),
      feltComparison: felt(object(area['felt_comparison'])),
      longTermContext: object(area['long_term_context']),
    );
  }
}

class _PeriodSevenReadingCard extends StatelessWidget {
  const _PeriodSevenReadingCard({
    super.key,
    required this.area,
    required this.explanation,
    required this.strings,
    required this.bodySize,
    required this.depth,
  });
  final NineAreaKey area;
  final ForecastExplanationResult? explanation;
  final AppStrings strings;
  final double bodySize;
  final ReadingDepth depth;

  @override
  Widget build(BuildContext context) {
    final english = strings.language == AppLanguage.en;
    final result = explanation;
    final available = result != null && result.status != 'not_predicted';
    final detailed = depth == ReadingDepth.detailed;
    final unavailable = english ? 'Not predicted' : '未予測';
    final bodyStyle = TextStyle(fontSize: bodySize, height: 1.45);
    final missing = english
        ? 'Required data for this area is unavailable. No value from another time is substituted.'
        : 'この項目に必要なデータを確認できません。別の時刻の値で補いません。';
    return GlassPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              KeyedSubtree(
                key: ValueKey('seven-reading-value-${area.name}'),
                child: area == NineAreaKey.felt
                    ? FeltFortuneBadge(
                        label: available ? result.feltLabel : null,
                      )
                    : available
                    ? FortuneNumber(
                        score: result.score!,
                        fixedSize: area == NineAreaKey.overall
                            ? dailyOverallFortuneBadgeSize
                            : dailyFortuneBadgeSize,
                        label: area == NineAreaKey.actionDecision
                            ? (english
                                  ? 'Experimental activity level; not success or decision correctness.'
                                  : '活動性の試作値。成功や判断の正しさではありません')
                            : null,
                        shortLabel: area == NineAreaKey.actionDecision
                            ? (english ? 'Activity' : '活動性')
                            : null,
                      )
                    : SizedBox(
                        width: dailyFortuneBadgeSize,
                        child: Text(
                          unavailable,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: bodySize,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFFB8C6E0),
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  strings.nineAreaTitle(area.name),
                  style: TextStyle(
                    fontSize: bodySize + 4,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (area == NineAreaKey.felt ||
              area == NineAreaKey.actionDecision) ...[
            const SizedBox(height: 8),
            Text(
              area == NineAreaKey.felt
                  ? (english
                        ? 'Categorical felt candidate · no numeric score'
                        : '体感の候補・数値点は付けません')
                  : (english
                        ? 'Experimental activity level, not success or decision correctness.'
                        : '活動性の試作値です。成功や判断の正しさではありません。'),
              style: bodyStyle.copyWith(color: const Color(0xFFB8C6E0)),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            available
                ? (detailed
                      ? result.narrativeText
                      // Use the existing simple explanation's first sentence;
                      // do not introduce a second summary/scoring algorithm.
                      : result.text.split('\n').skip(1).first)
                : missing,
            key: ValueKey('seven-reading-narrative-${area.name}'),
            style: bodyStyle,
          ),
          if (available && !detailed) ...[
            const SizedBox(height: 12),
            Text(
              '${english ? 'Try' : '行動のヒント'}: ${result.advice}',
              key: ValueKey('seven-reading-advice-${area.name}'),
              style: bodyStyle,
            ),
          ],
          const SizedBox(height: 12),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: Material(
              color: Colors.transparent,
              child: ExpansionTile(
                key: ValueKey('seven-reading-evidence-${area.name}'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                title: Text(
                  english ? 'Why and evidence' : '理由・根拠を見る',
                  style: bodyStyle.copyWith(fontWeight: FontWeight.w700),
                ),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      result == null
                          ? missing
                          : detailed
                          ? result.numericLedgerText
                          : '${result.interpretation}\n\n${result.numericLedgerText}',
                      key: ValueKey('seven-reading-ledger-${area.name}'),
                      style: bodyStyle,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
