part of 'main.dart';

/// 日予測の試作期間集計。旧4点を使う経路は外から受け取り再計算しない。
class NineAreaPeriodSummary {
  NineAreaPeriodSummary._(
    this.mode,
    this.dates,
    this.areas,
    this.feltCounts,
    this.feltUnavailableCount,
    this.feltModes,
    this.legacySourcePrefix,
    this.useGeneralModel,
  );

  static const modelVersion = 'nine-area-period-trial-20261001-1';
  static const generalModelVersion =
      'nine-area-period-general-trial-20261003-1';
  final LongRangeMode mode;
  final List<DateTime> dates;
  final List<NineAreaPeriodEntry> areas;
  final Map<String, int> feltCounts;
  final int feltUnavailableCount;
  final List<String> feltModes;
  final String legacySourcePrefix;
  final bool useGeneralModel;

  static List<DateTime> sampleDates(
    LongRangeMode mode,
    DateTime month,
    int year, {
    DateTime? weekStart,
  }) {
    if (mode == LongRangeMode.week && weekStart == null) {
      throw ArgumentError('週集計の開始日が必要です。');
    }
    return List.unmodifiable(switch (mode) {
      LongRangeMode.week => _weekSampleDates(weekStart!),
      LongRangeMode.month => [
        for (final day in [
          1,
          8,
          15,
          22,
          DateTime(month.year, month.month + 1, 0).day,
        ])
          DateTime.utc(month.year, month.month, day, 3),
      ],
      LongRangeMode.year => [
        for (var m = 1; m <= 12; m++)
          for (final day in const [1, 15]) DateTime.utc(year, m, day, 3),
      ],
    });
  }

  static List<DateTime> _weekSampleDates(DateTime start) => [
    for (var day = 0; day < 7; day++)
      DateTime.utc(start.year, start.month, start.day + day, 3),
  ];

  static String dateLabel(DateTime date) {
    final jst = date.toUtc().add(const Duration(hours: 9));
    return '${jst.year.toString().padLeft(4, '0')}-${jst.month.toString().padLeft(2, '0')}-${jst.day.toString().padLeft(2, '0')}';
  }

  static NineAreaPeriodSummary build({
    required LongRangeMode mode,
    required DateTime month,
    required int year,
    DateTime? weekStart,
    required Map<NineAreaKey, int> legacyScores,
    required List<NineAreaPrediction> Function(DateTime) dailyFor,
    Map<NineAreaKey, LongFortuneData> legacyCards = const {},
    String legacySourcePrefix = 'period_scores',
    bool useGeneralModel = false,
  }) {
    if (mode == LongRangeMode.week && !useGeneralModel) {
      throw ArgumentError('週の9項目は一般向け日モデルで集計します。');
    }
    const legacyKeys = [
      NineAreaKey.overall,
      NineAreaKey.love,
      NineAreaKey.work,
      NineAreaKey.money,
    ];
    if ((mode != LongRangeMode.week || legacyScores.isNotEmpty) &&
        (legacyScores.length != 4 ||
            legacyKeys.any(
              (key) =>
                  !legacyScores.containsKey(key) ||
                  legacyScores[key]! < 50 ||
                  legacyScores[key]! > 99,
            ))) {
      throw ArgumentError('旧期間4点がそろっていません。');
    }
    final dates = sampleDates(mode, month, year, weekStart: weekStart);
    final samples = [
      for (final date in dates) List<NineAreaPrediction>.of(dailyFor(date)),
    ];
    for (final sample in samples) {
      if (sample.length != 9 || sample.map((p) => p.key).toSet().length != 9) {
        throw StateError('期間確認日の9項目がそろっていません。');
      }
      for (final p in sample) {
        if (p.key == NineAreaKey.felt) {
          if (p.score != null ||
              (p.feltForecast?.label != null &&
                  !FeltForecastCandidate.labels.contains(
                    p.feltForecast!.label,
                  ))) {
            throw StateError('体感候補を数値や未知の文字で集計できません。');
          }
        } else if (p.score == null || p.score! < 50 || p.score! > 99) {
          throw StateError('期間の数値サンプルが不足または範囲外です。');
        }
      }
    }
    final counts = {for (final label in FeltForecastCandidate.labels) label: 0};
    var missing = 0;
    for (final sample in samples) {
      final label = sample
          .singleWhere((p) => p.key == NineAreaKey.felt)
          .feltForecast
          ?.label;
      if (label == null) {
        missing++;
      } else {
        counts[label] = counts[label]! + 1;
      }
    }
    final maximum = counts.values.reduce(math.max);
    final modes = [
      if (maximum > 0)
        for (final label in FeltForecastCandidate.labels)
          if (counts[label] == maximum) label,
    ];
    final entries = <NineAreaPeriodEntry>[];
    for (final key in NineAreaKey.values) {
      final template = samples.first.singleWhere((p) => p.key == key);
      final values = [
        if (key != NineAreaKey.felt)
          for (final sample in samples)
            sample.singleWhere((p) => p.key == key).score!,
      ];
      final legacy = !useGeneralModel && legacyKeys.contains(key);
      final score = key == NineAreaKey.felt
          ? null
          : legacy
          ? legacyScores[key]
          : (values.reduce((a, b) => a + b) / values.length).round();
      entries.add(
        NineAreaPeriodEntry(
          key: key,
          title: template.title,
          icon: template.icon,
          score: score,
          samples: List.unmodifiable(values),
          inherited: legacy,
          legacyCard: legacy ? legacyCards[key] : null,
        ),
      );
    }
    return NineAreaPeriodSummary._(
      mode,
      dates,
      List.unmodifiable(entries),
      Map.unmodifiable(counts),
      missing,
      List.unmodifiable(modes),
      legacySourcePrefix,
      useGeneralModel,
    );
  }

  String? get feltLabel => feltModes.length == 1 ? feltModes.single : null;
  String get feltDisplayLabel => feltModes.isEmpty
      ? '未予測'
      : feltModes.length > 1
      ? '混在'
      : feltModes.single;
  String get samplingText => switch (mode) {
    LongRangeMode.week => 'この週の7日すべての代表7時点（各日12:00 JST・全時刻の集計ではない）',
    LongRangeMode.month => '月内1・8・15・22・末日の5時点（12:00 JST）',
    LongRangeMode.year => '各月1日・15日の24時点（12:00 JST）',
  };
  String get _periodLabel => switch (mode) {
    LongRangeMode.week => 'この週',
    LongRangeMode.month => 'この月',
    LongRangeMode.year => 'この年',
  };
  String get feltDistribution => [
    for (final label in FeltForecastCandidate.labels)
      '$label ${feltCounts[label]}件',
    '未予測 $feltUnavailableCount件',
  ].join(' / ');

  Map<String, Object?> toJson() => {
    'schema': 'pancyo_nine_area_period_summary_v1',
    'model_version': useGeneralModel ? generalModelVersion : modelVersion,
    'daily_model_version': NineAreaDailyForecast.modelVersion,
    'provisional': true,
    'sampling': {
      'basis': switch (mode) {
        LongRangeMode.week => 'each_calendar_day',
        LongRangeMode.month => 'first_eighth_fifteenth_twenty_second_last',
        LongRangeMode.year => 'first_and_fifteenth_each_month',
      },
      'dates_jst': dates.map(dateLabel).toList(),
      'sample_count': dates.length,
      'calculation_time': '12:00 JST',
      'all_calendar_days_included': mode == LongRangeMode.week,
    },
    'overall_basis': useGeneralModel
        ? '各日の6分野平均による総合点を確認日で集計。活動性・体感・期間追加ボーナスは含めない。'
        : '旧合算心身点を含む従来4分野の期間点を維持。新しい8数値項目や表示5項目の平均ではない。',
    'areas': [
      for (final area in areas)
        {
          'key': area.key.name,
          'title': area.title,
          'score': area.score,
          'provisional': !area.inherited,
          'reading': reading(area),
          'aggregation': area.key == NineAreaKey.felt
              ? 'categorical_frequency_no_numeric_average'
              : area.inherited
              ? 'inherited_legacy_period_score'
              : 'mean_of_rounded_daily_trial_scores_then_round_once',
          if (area.inherited)
            'legacy_source': '$legacySourcePrefix.${area.title}',
          if (!area.inherited && area.score != null) ...{
            'daily_scores': area.samples,
            'sum': area.samples.reduce((a, b) => a + b),
            'count': area.samples.length,
            'mean_before_rounding':
                area.samples.reduce((a, b) => a + b) / area.samples.length,
            'additional_period_bonus': 0,
          },
          if (area.key == NineAreaKey.felt) ...{
            'label': feltLabel,
            'display_label': feltDisplayLabel,
            'counts': feltCounts,
            'unavailable_count': feltUnavailableCount,
            'mode_labels': feltModes,
            'tie_rule': 'display_mixed_without_selecting_a_label',
          },
        },
    ],
    'notice': mode == LongRangeMode.week
        ? '試作・未検証。この週の日代表7時点の集計であり全時刻の平均や的中率ではない。期間追加ボーナスは加えない。体感は数値化せず、未予測を補完しない。'
        : '試作・未検証。確認日の集計であり全日の平均や的中率ではない。新分離項目に年専用・期間ピーク補正は加えない。体感は数値化せず、未予測を補完しない。',
  };

  String reading(NineAreaPeriodEntry area) {
    if (area.inherited) {
      final period = _periodLabel;
      final tone = area.score! >= 82
          ? '追い風を使いつつ確認も大切にしたい期間。'
          : area.score! <= 65
          ? '広げるより確認と調整を大切にしたい期間。'
          : '予定を整え、一つずつ積み重ねたい期間。';
      final action = switch (area.key) {
        NineAreaKey.overall => '優先順位を絞り、動く時間と整える時間を分けましょう。',
        NineAreaKey.love => '相手の都合を確かめ、無理のない会話や連絡を大切にして。',
        NineAreaKey.work => '作業・確認・提出の区切りを決めて進めましょう。',
        NineAreaKey.money => '必要性と予算を確認して選びましょう。利益の保証ではありません。',
        _ => throw StateError('従来期間項目のキーが不正です。'),
      };
      return '$periodは$tone$action';
    }
    if (area.key == NineAreaKey.felt) {
      final first = feltModes.isEmpty
          ? '確認日の体感はすべて未予測です。'
          : feltModes.length > 1
          ? '確認日の体感候補は最多同数で混在しています。'
          : '確認日では「$feltLabel」が最多の候補です。';
      return mode == LongRangeMode.week
          ? 'この週の$first $feltDistribution。日代表7時点の候補であり、全時刻の体感や的中率ではありません。'
          : '$first $feltDistribution。期間全日の体感や的中率ではありません。';
    }
    final period = _periodLabel;
    return switch (area.key) {
      NineAreaKey.overall => '$periodの確認日の総合点を集計した試作値です。活動性と体感は含めません。',
      NineAreaKey.love => '$periodの確認日を集計した親密な関係の試作値です。相手の都合も確かめましょう。',
      NineAreaKey.work => '$periodの確認日を集計した仕事の成果・進展の試作値です。活動性と成功を分けます。',
      NineAreaKey.money => '$periodの確認日を集計した収支の試作値です。必要性と予算を確かめましょう。',
      NineAreaKey.mental =>
        '$periodの確認日を集計した気分・集中の試作値です。点数だけで決めず、実際の気持ちと休む余裕を優先しましょう。',
      NineAreaKey.health =>
        '$periodの確認日を集計した身体の負荷の試作値です。体調や病気の診断ではありません。実際の体調に合わせて予定を調整しましょう。',
      NineAreaKey.people =>
        '$periodの確認日を集計した交流の試作値です。相手の都合を確認し、無理のない連絡や協力を一つずつ試しましょう。',
      NineAreaKey.actionDecision =>
        '$periodの確認日を集計した活動性の試作値です。高い点数でも成功や判断の正しさを保証しません。着手前の確認を大切にして。',
      _ => throw StateError('期間項目が不正です。'),
    };
  }

  String detail(NineAreaPeriodEntry area) {
    final old = area.legacyCard;
    if (old != null)
      return '${old.detailedText}\n\n${old.sign}\n${old.transitHouse}\n${old.natalHouse}\n${old.aspectBasis}\n${old.chartBasis}\n\n${old.evidence.join('\n')}\n\n総合の材料は従来の合算心身点を含む4分野です。新しい表示5項目の平均ではありません。';
    if (area.inherited)
      return '${area.title}: ${area.score}点。旧period_scoresの期間点を維持しています。日別の単純平均や新8数値の平均に置き換えていません。総合の材料には従来の合算心身点を含みます。';
    if (area.key == NineAreaKey.felt)
      return '$samplingText\n$feltDistribution\n最多候補: ${feltModes.join('・')}\n同数は混在、全欠測は未予測です。良い方へ寄せず、普通で穴埋めせず、数値平均しません。試作・未検証です。'
          '${mode == LongRangeMode.week ? '\n日代表7時点の候補であり、全時刻の体感ではありません。' : ''}';
    final notice = mode == LongRangeMode.week
        ? '試作・未検証。日代表7時点の集計であり、全時刻の平均ではありません。'
        : '試作・未検証。全日平均ではありません。';
    return '$samplingText\n${[for (var i = 0; i < dates.length; i++) '${dateLabel(dates[i])}: ${area.samples[i]}点'].join('\n')}\n\n算術平均 → 最後に1回四捨五入: ${area.score}点。年専用・期間ピーク補正は追加しません。日別モデル: ${NineAreaDailyForecast.modelVersion}\n期間モデル: ${useGeneralModel ? generalModelVersion : modelVersion}\n$notice';
  }

  // Presentation only: canonical getters and toJson never call these methods.
  String displaySamplingText(AppStrings strings) {
    if (strings.language == AppLanguage.ja) return samplingText;
    return switch (mode) {
      LongRangeMode.week =>
        'Seven daily reference samples, one at 12:00 JST on each day of this week; not all hours',
      LongRangeMode.month =>
        'Five samples: the 1st, 8th, 15th, 22nd and last day of the month, at 12:00 JST',
      LongRangeMode.year =>
        '24 samples: the 1st and 15th of each month, at 12:00 JST',
    };
  }

  String displayFeltLabel(AppStrings strings) =>
      strings.language == AppLanguage.ja
      ? feltDisplayLabel
      : feltModes.isEmpty
      ? 'Not predicted'
      : feltModes.length > 1
      ? 'Mixed'
      : strings.feltLabelText(feltLabel) ?? feltDisplayLabel;

  String displayFeltDistribution(AppStrings strings) =>
      strings.language == AppLanguage.ja
      ? feltDistribution
      : [
          for (final label in FeltForecastCandidate.labels)
            '${strings.feltLabelText(label) ?? label} ${feltCounts[label]}',
          'Not predicted $feltUnavailableCount',
        ].join(' / ');

  String displayReading(NineAreaPeriodEntry area, AppStrings strings) {
    if (strings.language == AppLanguage.ja) return reading(area);
    final period = switch (mode) {
      LongRangeMode.week => 'this week',
      LongRangeMode.month => 'this month',
      LongRangeMode.year => 'this year',
    };
    if (area.inherited) {
      final tone = area.score! >= 82
          ? 'Use supportive influences while still checking the details.'
          : area.score! <= 65
          ? 'Prioritize checks and adjustments over expansion.'
          : 'Organize your schedule and build step by step.';
      final action = switch (area.key) {
        NineAreaKey.overall =>
          'Narrow your priorities and separate time for action from time for review.',
        NineAreaKey.love =>
          'Check the other person’s availability and keep conversation and contact manageable.',
        NineAreaKey.work => 'Set clear stages for work, review and submission.',
        NineAreaKey.money =>
          'Check needs and budget before choosing. This does not guarantee profit.',
        _ => throw StateError('Invalid inherited period area.'),
      };
      return 'For $period: $tone $action';
    }
    if (area.key == NineAreaKey.felt) {
      final first = feltModes.isEmpty
          ? 'Felt experience is not predicted for any sampled date.'
          : feltModes.length > 1
          ? 'The most frequent felt-experience candidates are tied (Mixed).'
          : 'The most frequent candidate is ${strings.feltLabelText(feltLabel) ?? feltLabel}.';
      return '$first ${displayFeltDistribution(strings)}. '
          '${mode == LongRangeMode.week ? 'These are seven daily reference samples, not all hours.' : 'These samples do not describe every day in the period.'} These counts are not prediction accuracy.';
    }
    final description = switch (area.key) {
      NineAreaKey.overall =>
        'overall daily scores; activity and felt experience are excluded',
      NineAreaKey.love =>
        'close relationships; check the other person’s circumstances too',
      NineAreaKey.work =>
        'work outcomes and progress; activity is separate from success',
      NineAreaKey.money => 'income and spending; check needs and budget',
      NineAreaKey.mental =>
        'mood and focus; prioritize your actual feelings and room to rest over the score',
      NineAreaKey.health =>
        'physical strain; this does not diagnose health or illness, and plans should fit your actual condition',
      NineAreaKey.people =>
        'social contact; check availability and try manageable communication or cooperation',
      NineAreaKey.actionDecision =>
        'activity; a high score does not guarantee success or a correct decision, so check before starting',
      _ => throw StateError('Invalid period area.'),
    };
    return 'A provisional value from the sampled dates in $period for $description.';
  }

  String displayDetail(NineAreaPeriodEntry area, AppStrings strings) {
    if (strings.language == AppLanguage.ja) return detail(area);
    if (area.legacyCard != null) {
      // Unknown legacy prose stays verbatim rather than translating user text.
      final old = area.legacyCard!;
      return '${old.detailedText}\n\n${old.sign}\n${old.transitHouse}\n${old.natalHouse}\n${old.aspectBasis}\n${old.chartBasis}\n\n${old.evidence.join('\n')}\n\nOverall uses the four legacy areas, including combined mind/body. It is not the average of the five displayed areas.';
    }
    if (area.inherited)
      return '${strings.nineAreaTitle(area.key.name)}: ${area.score}. The legacy period_scores value is retained, rather than replaced by a daily average or the average of eight numeric areas. Overall includes the legacy combined mind/body score.';
    if (area.key == NineAreaKey.felt)
      return '${displaySamplingText(strings)}\n${displayFeltDistribution(strings)}\nMost frequent: ${feltModes.map((v) => strings.feltLabelText(v) ?? v).join(' / ')}\nTies are Mixed; all missing is Not predicted. No favorable selection, Normal imputation or numeric average. Provisional and unvalidated.';
    return '${displaySamplingText(strings)}\n${[for (var i = 0; i < dates.length; i++) '${dateLabel(dates[i])}: ${area.samples[i]}'].join('\n')}\n\nArithmetic mean, rounded once at the end: ${area.score}. No yearly or period-peak adjustment is added.\nDaily model: ${NineAreaDailyForecast.modelVersion}\nPeriod model: ${useGeneralModel ? generalModelVersion : modelVersion}\nProvisional and unvalidated; not ${mode == LongRangeMode.week ? 'an average of all hours' : 'an average of every day'}.';
  }
}

String _periodDisplayCopy(
  BuildContext context,
  String japanese,
  String english,
) => AppLanguageScope.stringsOf(context).language == AppLanguage.en
    ? english
    : japanese;

String _periodAreaDisplayTitle(NineAreaPeriodEntry area, AppStrings strings) =>
    strings.language == AppLanguage.ja
    ? area.title
    : strings.nineAreaTitle(area.key.name);

class NineAreaPeriodEntry {
  const NineAreaPeriodEntry({
    required this.key,
    required this.title,
    required this.icon,
    required this.score,
    required this.samples,
    required this.inherited,
    this.legacyCard,
  });
  final NineAreaKey key;
  final String title;
  final IconData icon;
  final int? score;
  final List<int> samples;
  final bool inherited;
  final LongFortuneData? legacyCard;
}

class NineAreaPeriodOverview extends StatelessWidget {
  const NineAreaPeriodOverview({
    super.key,
    required this.summary,
    this.onShare,
    this.depth = ReadingDepth.simple,
    this.details,
    this.dailySamples = const {},
  });
  final NineAreaPeriodSummary summary;
  final ReadingDepth depth;
  final UserProfileDetails? details;
  final Map<String, List<NineAreaPrediction>> dailySamples;
  final VoidCallback? onShare;

  Future<void> _share(BuildContext context, {NineAreaPeriodEntry? selected}) {
    final strings = AppLanguageScope.stringsOf(context);
    final primary = selected ?? summary.areas.first;
    return showNineAreaReadingShareComposer(
      context,
      periodLabel: nineAreaPeriodShareLabel(summary, strings),
      areaHighlightsText: OverallAreaHighlights.fromSummary(
        summary,
      ).text(strings),
      areas: [
        for (final area in selected == null ? summary.areas : [primary])
          FortuneShareArea(
            key: area.key,
            title: _periodAreaDisplayTitle(area, strings),
            score: area.score,
            feltLabel: area.key == NineAreaKey.felt
                ? summary.displayFeltLabel(strings)
                : null,
          ),
      ],
      body: ForecastExplanation.forPeriod(
        summary: summary,
        area: primary,
        strings: strings,
        depth: depth,
        supplement: details,
        dailySamples: dailySamples,
        includeEvidence: false,
      ).narrativeText,
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        _periodDisplayCopy(context, '期間の9項目', 'Nine areas for this period'),
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
      ),
      const SizedBox(height: 6),
      Text(
        _periodDisplayCopy(
          context,
          '${summary.samplingText}。メンタル・追加4項目は試作・未検証。${depth == ReadingDepth.detailed ? '根拠は項目をタップ。' : ''}',
          '${summary.displaySamplingText(AppLanguageScope.stringsOf(context))}. Mental well-being and the four additional areas are provisional and unvalidated.${depth == ReadingDepth.detailed ? ' Tap an area for evidence.' : ''}',
        ),
        style: const TextStyle(fontSize: 12, color: Color(0xFFB8C6E0)),
      ),
      const SizedBox(height: 10),
      if (depth == ReadingDepth.simple &&
          MediaQuery.sizeOf(context).shortestSide >= 600)
        SimpleNineAreaDashboard(
          items: [
            for (final area in summary.areas)
              SimpleNineAreaItem(
                area: area.key,
                icon: area.icon,
                title: _periodAreaDisplayTitle(
                  area,
                  AppLanguageScope.stringsOf(context),
                ),
                narrative: ForecastExplanation.forPeriod(
                  summary: summary,
                  area: area,
                  strings: AppLanguageScope.stringsOf(context),
                  depth: ReadingDepth.simple,
                  supplement: details,
                  dailySamples: dailySamples,
                  includeEvidence: false,
                ).narrativeText,
                score: area.score,
                feltLabel: area.key == NineAreaKey.felt
                    ? summary.feltLabel
                    : null,
                feltModes: area.key == NineAreaKey.felt
                    ? summary.feltModes
                    : const [],
              ),
          ],
          highlights: OverallAreaHighlights.fromSummary(summary),
          mainFiveKey: const ValueKey('period-nine-front-five'),
          additionalFourKey: const ValueKey('period-nine-additional-four'),
          cardKeyPrefix: 'period-nine',
          valueKeyPrefix: 'period-nine-value',
          narrativeKeyPrefix: 'period-nine-narrative',
          shareSummaryKey: const ValueKey('period-share-reading'),
          shareOverallKey: const ValueKey('period-share-overall'),
          onShareSummary: onShare ?? () => _share(context),
          onShareOverall: () => _share(
            context,
            selected: summary.areas.firstWhere(
              (area) => area.key == NineAreaKey.overall,
            ),
          ),
        )
      else ...[
        if (depth == ReadingDepth.simple) ...[
          SimpleReadingShareActions(
            shareSummaryKey: const ValueKey('period-share-reading'),
            shareOverallKey: const ValueKey('period-share-overall'),
            onShareSummary: onShare ?? () => _share(context),
            onShareOverall: () => _share(
              context,
              selected: summary.areas.firstWhere(
                (area) => area.key == NineAreaKey.overall,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 14.0;
            final two =
                constraints.maxWidth >=
                MediaQuery.textScalerOf(context).scale(300) * 2 + gap;
            Widget tile(NineAreaPeriodEntry area) => _NineAreaPeriodTile(
              key: ValueKey('period-nine-${area.key.name}'),
              summary: summary,
              area: area,
              depth: depth,
              details: details,
              dailySamples: dailySamples,
            );
            List<Widget> rows(List<NineAreaPeriodEntry> entries) => [
              for (var i = 0; i < entries.length; i += two ? 2 : 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: gap),
                  child: two && i + 1 < entries.length
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: tile(entries[i])),
                            const SizedBox(width: gap),
                            Expanded(child: tile(entries[i + 1])),
                          ],
                        )
                      : tile(entries[i]),
                ),
            ];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Column(
                  key: const ValueKey('period-nine-front-five'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _periodDisplayCopy(context, '前半・5項目', 'First five areas'),
                      style: TextStyle(fontSize: 12, color: Color(0xFFB8C6E0)),
                    ),
                    const SizedBox(height: 6),
                    tile(summary.areas.first),
                    const SizedBox(height: gap),
                    ...rows(summary.areas.sublist(1, 5)),
                  ],
                ),
                Text(
                  _periodDisplayCopy(
                    context,
                    '後半・追加4項目',
                    'Four additional areas',
                  ),
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                ...rows(summary.areas.sublist(5)),
              ],
            );
          },
        ),
      ],
    ],
  );
}

class _NineAreaPeriodTile extends StatelessWidget {
  const _NineAreaPeriodTile({
    super.key,
    required this.summary,
    required this.area,
    this.onShare,
    this.depth = ReadingDepth.simple,
    this.details,
    this.dailySamples = const {},
  });
  final NineAreaPeriodSummary summary;
  final ReadingDepth depth;
  final UserProfileDetails? details;
  final Map<String, List<NineAreaPrediction>> dailySamples;
  final NineAreaPeriodEntry area;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final badgeSize = scaler.scale(
      area.key == NineAreaKey.overall
          ? dailyOverallFortuneBadgeSize
          : dailyFortuneBadgeSize,
    );
    final explanation = ForecastExplanation.forPeriod(
      summary: summary,
      area: area,
      strings: AppLanguageScope.stringsOf(context),
      depth: depth,
      supplement: details,
      dailySamples: dailySamples,
      includeEvidence: summary is! LongRangeDisplaySummary,
    );
    return GlassPanel(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: depth == ReadingDepth.detailed
              ? () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(
                      _periodAreaDisplayTitle(
                        area,
                        AppLanguageScope.stringsOf(context),
                      ),
                    ),
                    content: SingleChildScrollView(
                      child: Text(
                        depth == ReadingDepth.detailed
                            ? ForecastExplanation.forPeriod(
                                summary: summary,
                                area: area,
                                strings: AppLanguageScope.stringsOf(context),
                                depth: ReadingDepth.detailed,
                                supplement: details,
                                dailySamples: dailySamples,
                              ).numericLedgerText
                            : ForecastExplanation.forPeriod(
                                summary: summary,
                                area: area,
                                strings: AppLanguageScope.stringsOf(context),
                                depth: ReadingDepth.detailed,
                                supplement: details,
                                dailySamples: dailySamples,
                              ).text,
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(
                          AppLanguageScope.stringsOf(
                            context,
                          ).text(AppText.close),
                        ),
                      ),
                    ],
                  ),
                )
              : null,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final simplePhone =
                    depth == ReadingDepth.simple &&
                    MediaQuery.sizeOf(context).shortestSide < 600;
                final vertical =
                    constraints.maxWidth <
                    badgeSize + 14 + scaler.scale(simplePhone ? 150 : 220);
                return Flex(
                  direction: vertical ? Axis.vertical : Axis.horizontal,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    KeyedSubtree(
                      key: ValueKey('period-nine-value-${area.key.name}'),
                      child: area.score != null
                          ? FortuneNumber(
                              score: area.score!,
                              fixedSize: badgeSize,
                              shortLabel: area.key == NineAreaKey.actionDecision
                                  ? _periodDisplayCopy(
                                      context,
                                      '活動性',
                                      'Activity',
                                    )
                                  : null,
                              label: area.key == NineAreaKey.actionDecision
                                  ? _periodDisplayCopy(
                                      context,
                                      '活動性の試作値。成功や判断の正しさではありません',
                                      'Provisional activity value; not success or decision correctness',
                                    )
                                  : null,
                            )
                          : summary.feltModes.length <= 1
                          ? FeltFortuneBadge(
                              label: summary.feltLabel,
                              fixedSize: badgeSize,
                            )
                          : Tooltip(
                              message: _periodDisplayCopy(
                                context,
                                '最多同数: ${summary.feltModes.join('・')}。点数には変換しません。',
                                'Tied most frequent: ${summary.feltModes.map((v) => AppLanguageScope.stringsOf(context).feltLabelText(v) ?? v).join(' / ')}. No numeric conversion.',
                              ),
                              child: Container(
                                width: badgeSize,
                                height: badgeSize,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xEE121528),
                                  border: Border.all(
                                    color: Colors.white70,
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.white.withValues(
                                        alpha: 0.21,
                                      ),
                                      blurRadius: 14,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                                child: Text(
                                  _periodDisplayCopy(
                                    context,
                                    '混在\n体感',
                                    'Mixed\nFelt',
                                  ),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                    ),
                    SizedBox(
                      width: vertical ? 0 : 14,
                      height: vertical ? 14 : 0,
                    ),
                    Flexible(
                      flex: vertical ? 0 : 1,
                      fit: FlexFit.tight,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                area.icon,
                                size: 20,
                                color: const Color(0xFFF6D77A),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _periodAreaDisplayTitle(
                                    area,
                                    AppLanguageScope.stringsOf(context),
                                  ),
                                  style: TextStyle(
                                    fontSize: area.key == NineAreaKey.overall
                                        ? 20
                                        : 17,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              if (depth == ReadingDepth.detailed)
                                Tooltip(
                                  message: _periodDisplayCopy(
                                    context,
                                    '計算根拠を見る',
                                    'View calculation evidence',
                                  ),
                                  child: Icon(
                                    Icons.chevron_right,
                                    size: 16,
                                    color: Color(0xFF8FDAD9),
                                  ),
                                ),
                            ],
                          ),
                          if (!area.inherited)
                            Text(
                              _periodDisplayCopy(
                                context,
                                '試作・未検証',
                                'Provisional · Unvalidated',
                              ),
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFFB8C6E0),
                              ),
                            ),
                          const SizedBox(height: 12),
                          if (area.key == NineAreaKey.overall) ...[
                            OverallAreaHighlightsBlock(
                              highlights: OverallAreaHighlights.fromSummary(
                                summary,
                              ),
                              strings: AppLanguageScope.stringsOf(context),
                              style: const TextStyle(
                                fontSize: 16,
                                height: 1.45,
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          Text(
                            explanation.narrativeText,
                            key: ValueKey(
                              'period-nine-narrative-${area.key.name}',
                            ),
                            style: TextStyle(
                              fontSize: simplePhone ? 16 : null,
                              height: 1.45,
                              color: Colors.white.withValues(alpha: 0.76),
                            ),
                          ),
                          if (onShare != null) ...[
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              key: ValueKey('period-share-${area.key.name}'),
                              onPressed: onShare,
                              icon: const Icon(
                                Icons.ios_share_outlined,
                                size: 20,
                              ),
                              label: Text(
                                _periodDisplayCopy(
                                  context,
                                  '総合運のみ共有',
                                  'Share overall only',
                                ),
                              ),
                            ),
                          ],
                          if (depth == ReadingDepth.detailed) ...[
                            const SizedBox(height: 8),
                            Text(
                              _periodDisplayCopy(
                                context,
                                'タップして点数の内訳・計算根拠を開く',
                                'Tap to view the score breakdown and calculation evidence',
                              ),
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF8FDAD9),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
