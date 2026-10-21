part of 'main.dart';

/// One unchanged numeric value in the canonical, boundary-deduplicated series.
class PeriodSevenTrendPoint {
  const PeriodSevenTrendPoint({required this.instantUtc, required this.score});
  final DateTime instantUtc;
  final int score;
}

/// Reads existing results only. Categorical felt experience is never converted
/// into graph coordinates, and missing values are never filled or interpolated.
List<PeriodSevenTrendPoint> periodSevenTrendPoints(
  PeriodSevenSummary summary,
  NineAreaKey area,
) {
  if (area == NineAreaKey.felt) {
    throw ArgumentError('Felt experience has no numeric trend.');
  }
  return List.unmodifiable([
    for (final instant in summary.dates)
      PeriodSevenTrendPoint(
        instantUtc: instant,
        score: summary.predictionsByInstant[summary.sampleKey(instant)]!
            .singleWhere((prediction) => prediction.key == area)
            .score!,
      ),
  ]);
}

/// The original five-line plus three-line presentation, fed only with approved
/// seven-point period means. No ephemeris or score calculation occurs here.
class PeriodSevenGroupedTrendData {
  PeriodSevenGroupedTrendData._({
    required this.mode,
    required this.summaries,
    required this.dates,
    required this.labels,
    required this.series,
    required this.additional,
  });

  final LongRangeMode mode;
  final List<PeriodSevenSummary> summaries;
  final List<DateTime> dates;
  final List<String> labels;
  final List<FortuneFlowSeries> series;
  final AdditionalFortuneTrendData additional;

  static const mainKeys = [
    NineAreaKey.overall,
    NineAreaKey.love,
    NineAreaKey.work,
    NineAreaKey.money,
    NineAreaKey.mental,
  ];
  static const mainLabels = ['総合', '恋愛', '仕事', '金運', 'メンタル'];
  static const mainColors = [
    Color(0xFFF6D77A),
    Color(0xFFFF82B2),
    Color(0xFF57D6D1),
    Color(0xFF9BE06D),
    Color(0xFFB58CFF),
  ];

  factory PeriodSevenGroupedTrendData.fromSummaries(
    List<PeriodSevenSummary> summaries,
  ) {
    if (summaries.isEmpty) {
      throw ArgumentError('Complete periods are required.');
    }
    final mode = summaries.first.mode;
    final count = mode == LongRangeMode.week ? 4 : 12;
    if (mode == LongRangeMode.year ||
        summaries.length != count ||
        summaries.any((summary) => summary.mode != mode)) {
      throw ArgumentError(
        'The original graph requires four weeks or twelve months.',
      );
    }
    DateTime civil(String label) {
      final parsed = DateTime.parse(label);
      return DateTime.utc(parsed.year, parsed.month, parsed.day);
    }

    final dates = summaries
        .map((summary) => civil(summary.startDateJst))
        .toList();
    final first = dates.first;
    for (var index = 0; index < count; index++) {
      final expected = mode == LongRangeMode.week
          ? first.add(Duration(days: index * 7))
          : DateTime.utc(first.year, index + 1, 1);
      final summary = summaries[index];
      if (dates[index] != expected ||
          summary.sourceName != summaries.first.sourceName ||
          summary.usesHighPrecisionAstroData !=
              summaries.first.usesHighPrecisionAstroData ||
          summary.requestedHouseSystem !=
              summaries.first.requestedHouseSystem ||
          summary.areas.length != NineAreaKey.values.length ||
          summary.areas.map((area) => area.key).toSet().length !=
              NineAreaKey.values.length) {
        throw StateError(
          'The graph periods, calculation conditions or areas do not match.',
        );
      }
      for (final area in summary.areas) {
        if (area.key == NineAreaKey.felt) {
          if (area.score != null) {
            throw StateError('Felt experience must remain categorical.');
          }
        } else if (area.score == null || area.score! < 50 || area.score! > 99) {
          throw StateError('A period score is missing or out of range.');
        }
      }
    }
    final labels = [
      for (final date in dates)
        mode == LongRangeMode.week
            ? '${_monthDayWithWeekday(date)}週'
            : '${date.month}月',
    ];
    final additionalLabels = [
      for (final date in dates)
        mode == LongRangeMode.week
            ? _monthDayWithWeekday(date)
            : '${date.month}月',
    ];
    List<int> values(NineAreaKey key) => List.unmodifiable([
      for (final summary in summaries)
        summary.areas.singleWhere((area) => area.key == key).score!,
    ]);
    final series = [
      for (var index = 0; index < mainKeys.length; index++)
        FortuneFlowSeries(
          label: mainLabels[index],
          color: mainColors[index],
          values: values(mainKeys[index]),
        ),
    ];
    // Build from the unchanged representative scores. The legacy .period()
    // constructor's noon/five-sample notice does not describe seven-point data.
    final additional = AdditionalFortuneTrendData._build(
      additionalLabels,
      [for (final key in AdditionalFortuneTrendData.numericKeys) values(key)],
      [
        for (final summary in summaries)
          FeltTrendPoint(
            label: summary.feltDisplayLabel,
            periodSummary: summary,
            detail: summary.displayDetail(
              summary.areas.singleWhere((area) => area.key == NineAreaKey.felt),
              const AppStrings(AppLanguage.ja),
            ),
          ),
      ],
    );
    return PeriodSevenGroupedTrendData._(
      mode: mode,
      summaries: List.unmodifiable(summaries),
      dates: List.unmodifiable(dates),
      labels: List.unmodifiable(labels),
      series: List.unmodifiable(series),
      additional: additional,
    );
  }
}

class PeriodSevenGroupedTrendView extends StatefulWidget {
  const PeriodSevenGroupedTrendView({super.key, required this.summaries});
  final List<PeriodSevenSummary> summaries;

  @override
  State<PeriodSevenGroupedTrendView> createState() =>
      _PeriodSevenGroupedTrendViewState();
}

class _PeriodSevenGroupedTrendViewState
    extends State<PeriodSevenGroupedTrendView> {
  late PeriodSevenGroupedTrendData _data;

  @override
  void initState() {
    super.initState();
    _data = PeriodSevenGroupedTrendData.fromSummaries(widget.summaries);
  }

  @override
  void didUpdateWidget(covariant PeriodSevenGroupedTrendView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.summaries != widget.summaries) {
      _data = PeriodSevenGroupedTrendData.fromSummaries(widget.summaries);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLanguageScope.stringsOf(context);
    final english = strings.language == AppLanguage.en;
    final weekly = _data.mode == LongRangeMode.week;
    final subtitle = weekly
        ? (english ? 'Four weeks, one point per week' : '1週間ごとの4週間')
        : (english
              ? 'Monthly trend in ${_data.dates.first.year}'
              : '${_data.dates.first.year}年の月ごとの推移');
    final basis = weekly
        ? (english
              ? 'Each point is the mean for a complete week of seven-point daily readings. Felt experience uses the most frequent label; ties remain Mixed.'
              : '各点は、各週の全日7点式から集計した期間平均です。体感は最頻候補で、最多同数は混在のままです。')
        : (english
              ? 'Each point is the mean for a complete month of seven-point daily readings. Felt experience uses the most frequent label; ties remain Mixed.'
              : '各点は、各月の全日7点式から集計した期間平均です。体感は最頻候補で、最多同数は混在のままです。');
    return GlassPanel(
      key: const ValueKey('period-seven-grouped-trend'),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 18,
            runSpacing: 8,
            children: [
              Text(
                english ? 'Fortune trends' : '運勢の流れ',
                key: const ValueKey('period-grouped-trend-title'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 16,
                  color: Color(0xFFF6D77A),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            english
                ? 'Period scores · 50–99 · JST (UTC+09:00)'
                : '期間の点数・50〜99点・JST（UTC+09:00）',
            style: const TextStyle(fontSize: 16),
          ),
          if (!weekly) ...[
            const SizedBox(height: 8),
            Text(
              english
                  ? 'The twelve monthly readings from the same year are compared.'
                  : '選択した月と同じ年の12か月の月間占いを比べます。',
              style: const TextStyle(fontSize: 16, height: 1.35),
            ),
          ],
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              // Keep the existing painter, colors and line shapes. As in the
              // original additional graph, horizontal scrolling protects labels.
              final minimumWidth =
                  MediaQuery.textScalerOf(context).scale(72) *
                      (_data.labels.length - 1) +
                  46;
              return SingleChildScrollView(
                key: const ValueKey('period-grouped-trend-scroll'),
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: math.max(constraints.maxWidth, minimumWidth),
                  height: FortuneFlowPainter.chartHeight(MediaQuery.textScalerOf(context)),
                  child: Semantics(
                    label: english
                        ? '$subtitle. Five lines: overall, love, work, money and mental well-being.'
                        : '$subtitle。総合・恋愛・仕事・金運・メンタルの5本の線。',
                    child: CustomPaint(
                      key: const ValueKey('period-grouped-trend-chart'),
                      painter: FortuneFlowPainter(
                        textScaler: MediaQuery.textScalerOf(context),
                        series: _data.series,
                        labels: _data.labels
                            .map(
                              (label) => periodTrendAxisLabel(label, strings),
                            )
                            .toList(),
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            key: const ValueKey('period-grouped-trend-legend'),
            spacing: 12,
            runSpacing: 8,
            children: [
              for (final series in _data.series)
                _FlowLegend(label: series.label, color: series.color),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            english
                ? 'Additional chart: three numeric lines plus categorical felt labels.'
                : '追加グラフは3本の数値の線と、体感の文字候補です。',
            style: const TextStyle(fontSize: 16, height: 1.35),
          ),
          AdditionalFortuneTrendChart(
            key: const ValueKey('period-grouped-trend-additional'),
            dataIdentity: _data,
            basis: basis,
            dataFor: () => _data.additional,
          ),
        ],
      ),
    );
  }
}
