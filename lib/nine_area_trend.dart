part of 'main.dart';

/// 表示専用。固定済みの日予測／期間集計から取り出し、別の点数式を持たない。
class AdditionalFortuneTrendData {
  AdditionalFortuneTrendData._(this.labels, this.series, this.felt);

  final List<String> labels;
  final List<FortuneFlowSeries> series;
  final List<FeltTrendPoint> felt;

  static const numericKeys = [
    NineAreaKey.health,
    NineAreaKey.people,
    NineAreaKey.actionDecision,
  ];
  static const numericLabels = ['健康', '対人', '行動／決断'];
  static const colors = [
    Color(0xFF70B7FF),
    Color(0xFFFFBA7A),
    Color(0xFF67E0C0),
  ];

  static AdditionalFortuneTrendData daily({
    required List<DateTime> dates,
    required List<NineAreaPrediction> Function(DateTime) dailyFor,
  }) {
    final samples = dates.map(dailyFor).toList();
    final labels = dates.map(_monthDayWithWeekday).toList();
    for (final sample in samples) {
      if (sample.length != 9 || sample.map((p) => p.key).toSet().length != 9) {
        throw StateError('グラフの9項目がそろっていません。');
      }
      final felt = sample.singleWhere((p) => p.key == NineAreaKey.felt);
      if (felt.score != null ||
          (felt.feltForecast?.label != null &&
              !FeltForecastCandidate.labels.contains(
                felt.feltForecast!.label,
              ))) {
        throw StateError('体感を点数や未知の候補として表示できません。');
      }
    }
    return _build(
      labels,
      [
        for (final key in numericKeys)
          [
            for (final sample in samples)
              sample.singleWhere((p) => p.key == key).score,
          ],
      ],
      [
        for (final sample in samples)
          FeltTrendPoint(
            label:
                sample
                    .singleWhere((p) => p.key == NineAreaKey.felt)
                    .feltForecast
                    ?.label ??
                '未予測',
            detail: sample
                .singleWhere((p) => p.key == NineAreaKey.felt)
                .reading,
          ),
      ],
    );
  }

  static AdditionalFortuneTrendData period({
    required LongRangeMode mode,
    required List<DateTime> dates,
    required NineAreaPeriodSummary Function(DateTime) summaryFor,
  }) {
    final summaries = dates.map(summaryFor).toList();
    if (summaries.any((s) => s.mode != mode)) throw StateError('集計期間が一致しません。');
    if (mode == LongRangeMode.week &&
        summaries.any((s) => !s.useGeneralModel)) {
      throw StateError('週の追加グラフには一般向け日モデルの集計が必要です。');
    }
    final feltNotice = mode == LongRangeMode.week
        ? '最多同数は混在、全欠測は未予測。日代表7時点の件数であり、全時刻の割合や的中率ではありません。'
        : '最多同数は混在、全欠測は未予測。確認時点の件数であり、全日の割合や的中率ではありません。';
    return _build(
      [
        for (final date in dates)
          switch (mode) {
            LongRangeMode.week => _monthDayWithWeekday(date),
            LongRangeMode.month => '${date.month}月',
            LongRangeMode.year => '${date.year}',
          },
      ],
      [
        for (final key in numericKeys)
          [
            for (final summary in summaries)
              summary.areas.singleWhere((p) => p.key == key).score,
          ],
      ],
      [
        for (final summary in summaries)
          FeltTrendPoint(
            label: summary.feltDisplayLabel,
            periodSummary: summary,
            detail:
                '${summary.samplingText}\n${summary.feltDistribution}\n$feltNotice',
          ),
      ],
    );
  }

  static AdditionalFortuneTrendData _build(
    List<String> labels,
    List<List<int?>> values,
    List<FeltTrendPoint> felt,
  ) {
    if (labels.length < 2 ||
        felt.length != labels.length ||
        values.length != 3 ||
        values.any(
          (v) =>
              v.length != labels.length ||
              v.any((score) => score == null || score < 50 || score > 99),
        )) {
      throw StateError('追加グラフの点数・時点が不足または範囲外です。');
    }
    return AdditionalFortuneTrendData._(
      List.unmodifiable(labels),
      List.unmodifiable([
        for (var i = 0; i < 3; i++)
          FortuneFlowSeries(
            label: numericLabels[i],
            color: colors[i],
            values: List.unmodifiable(values[i].cast<int>()),
          ),
      ]),
      List.unmodifiable(felt),
    );
  }

  String pointDetail(int index) =>
      '${labels[index]}\n'
      '${series.map((s) => '${s.label} ${s.values[index]}点').join('／')}\n'
      '体感 ${felt[index].label}\n${felt[index].detail}';

  String displayPointDetail(BuildContext context, int index) {
    final strings = AppLanguageScope.stringsOf(context);
    if (strings.language == AppLanguage.ja) return pointDetail(index);
    final point = felt[index];
    final summary = point.periodSummary;
    final detail = summary == null
        ? localizedKnownReading(context, point.detail)
        : summary.displayDetail(
            summary.areas.singleWhere((a) => a.key == NineAreaKey.felt),
            strings,
          );
    return '${periodTrendAxisLabel(labels[index], strings)}\n'
        '${[for (var i = 0; i < series.length; i++) '${strings.nineAreaTitle(numericKeys[i].name)} ${series[i].values[index]}'].join(' / ')}\n'
        'Felt experience: ${periodFeltDisplayLabel(point.label, strings)}\n$detail';
  }
}

/// Application-authored axis labels only; no DateTime/TZ conversion.
String periodTrendAxisLabel(String source, AppStrings strings) {
  if (strings.language == AppLanguage.ja) return source;
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final month = RegExp(r'^(\d{1,2})月$').firstMatch(source);
  if (month != null) {
    final number = int.parse(month[1]!);
    return number >= 1 && number <= 12 ? months[number - 1] : source;
  }
  final date = RegExp(
    r'^(\d{1,2})/(\d{1,2})\(([月火水木金土日])\)(週)?$',
  ).firstMatch(source);
  if (date == null) return source;
  const weekdays = {
    '月': 'Mon',
    '火': 'Tue',
    '水': 'Wed',
    '木': 'Thu',
    '金': 'Fri',
    '土': 'Sat',
    '日': 'Sun',
  };
  return '${date[1]!.padLeft(2, '0')}-${date[2]!.padLeft(2, '0')} (${weekdays[date[3]]})${date[4] == null ? '' : ' week'}';
}

String periodFeltDisplayLabel(String source, AppStrings strings) =>
    strings.language == AppLanguage.ja
    ? source
    : strings.feltLabelText(source) ??
          switch (source) {
            '混在' => 'Mixed',
            '未予測' => 'Not predicted',
            _ => source,
          };

class FeltTrendPoint {
  const FeltTrendPoint({
    required this.label,
    required this.detail,
    this.periodSummary,
  });
  final String label;
  final String detail;
  final NineAreaPeriodSummary? periodSummary;
  Color get color => switch (label) {
    '最高' || '良い' => const Color(0xFFF6D77A),
    '普通' => const Color(0xFFB58CFF),
    '悪い' => const Color(0xFFFF2D8F),
    '最悪' => const Color(0xFF57D6D1),
    _ => Colors.white70,
  };
}

/// 開閉するのは追加グラフだけ。本文カードや前半5系列は所有しない。
class AdditionalFortuneTrendChart extends StatefulWidget {
  const AdditionalFortuneTrendChart({
    super.key,
    required this.dataIdentity,
    required this.dataFor,
    required this.basis,
    this.diagnosticRequest,
  });
  final Object dataIdentity;
  final AdditionalFortuneTrendData Function() dataFor;
  final String basis;
  final PeriodTrendRequest? diagnosticRequest;

  @override
  State<AdditionalFortuneTrendChart> createState() =>
      _AdditionalFortuneTrendChartState();
}

class _AdditionalFortuneTrendChartState
    extends State<AdditionalFortuneTrendChart> {
  bool _open = false;
  bool _busy = false;
  bool _failed = false;
  int _generation = 0;
  AdditionalFortuneTrendData? _data;

  @override
  void didUpdateWidget(covariant AdditionalFortuneTrendChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dataIdentity != widget.dataIdentity) {
      _generation++;
      _open = _busy = _failed = false;
      _data = null;
    }
  }

  Future<void> _toggle() async {
    if (_busy) return;
    if (_open) {
      setState(() => _open = false);
      return;
    }
    if (_data != null) {
      setState(() => _open = true);
      return;
    }
    final generation = ++_generation;
    final load = widget.dataFor;
    setState(() {
      _open = true;
      _busy = true;
      _failed = false;
    });
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 16));
    if (!mounted || generation != _generation) return;
    try {
      final data = load();
      if (!mounted || generation != _generation) return;
      setState(() {
        _data = data;
        _busy = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _busy = false;
        _failed = true;
        _open = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        OutlinedButton.icon(
          key: const ValueKey('additional-trend-toggle'),
          onPressed: _busy ? null : _toggle,
          icon: Icon(_open ? Icons.expand_less : Icons.expand_more, size: 20),
          label: Text(
            _periodDisplayCopy(
              context,
              _open ? '追加4項目のグラフを閉じる' : '追加4項目のグラフを見る',
              _open
                  ? 'Close the four additional trends'
                  : 'Show the four additional trends',
            ),
          ),
        ),
        if (_busy)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _periodDisplayCopy(
                      context,
                      '追加グラフを読み込み中…',
                      'Loading additional trends…',
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (_failed)
          Text(
            _periodDisplayCopy(
              context,
              '追加グラフを読み込めませんでした。もう一度ボタンを押すと再試行できます。',
              'Could not load additional trends. Press the button to try again.',
            ),
          ),
        if (_open && _data != null)
          AdditionalFortuneTrendView(
            data: _data!,
            basis: widget.basis,
            diagnosticRequest: widget.diagnosticRequest,
          ),
      ],
    );
  }
}

class AdditionalFortuneTrendView extends StatelessWidget {
  const AdditionalFortuneTrendView({
    super.key,
    required this.data,
    required this.basis,
    this.diagnosticRequest,
  });
  final AdditionalFortuneTrendData data;
  final String basis;
  final PeriodTrendRequest? diagnosticRequest;

  void _showPoint(BuildContext context, int i) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(
        _periodDisplayCopy(
          context,
          '${data.labels[i]}の追加4項目',
          '${periodTrendAxisLabel(data.labels[i], AppLanguageScope.stringsOf(context))} · Four additional areas',
        ),
      ),
      content: SingleChildScrollView(
        child: Text(
          '${data.displayPointDetail(context, i)}\n${_periodDisplayCopy(context, '試作・未検証です。', 'Provisional and unvalidated.')}',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(AppLanguageScope.stringsOf(context).text(AppText.close)),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('additional-trend-content'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(
          _periodDisplayCopy(
            context,
            '健康・対人・行動／決断の流れ',
            'Health, relationships and activity trends',
          ),
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(
          localizedUiText(context, basis),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.62),
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final minWidth =
                MediaQuery.textScalerOf(context).scale(72) *
                    (data.labels.length - 1) +
                46;
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: math.max(constraints.maxWidth, minWidth),
                height: 220,
                child: CustomPaint(
                  painter: FortuneFlowPainter(
                    series: data.series,
                    labels: data.labels
                        .map(
                          (v) => periodTrendAxisLabel(
                            v,
                            AppLanguageScope.stringsOf(context),
                          ),
                        )
                        .toList(),
                    diagnosticRequest: AdditionalTrendPointCheck.enabled
                        ? diagnosticRequest
                        : null,
                    diagnosticAdditionalData: AdditionalTrendPointCheck.enabled
                        ? data
                        : null,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            for (final series in data.series)
              _FlowLegend(
                label:
                    AppLanguageScope.stringsOf(context).language ==
                        AppLanguage.ja
                    ? series.label
                    : AppLanguageScope.stringsOf(context).nineAreaTitle(
                        AdditionalFortuneTrendData
                            .numericKeys[data.series.indexOf(series)]
                            .name,
                      ),
                color: series.color,
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          _periodDisplayCopy(
            context,
            '体感の流れ（文字候補）',
            'Felt-experience trend (candidate labels)',
          ),
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(
          _periodDisplayCopy(
            context,
            '体感は点数にせず文字と色で表示。各時点を押すと3項目の点数と体感の内訳を確認できます。狭い画面の折れ線は横にスクロールできます。',
            'Felt experience uses labels and colors, not a score. Tap a point for the three numeric areas and felt details. Scroll the line chart horizontally on narrow screens.',
          ),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.62),
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < data.labels.length; i++)
              Semantics(
                label: data.displayPointDetail(context, i),
                button: true,
                excludeSemantics: true,
                onTap: () => _showPoint(context, i),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: ValueKey('felt-trend-$i'),
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _showPoint(context, i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: data.felt[i].color.withValues(alpha: 0.08),
                        border: Border.all(
                          color: data.felt[i].color.withValues(alpha: 0.75),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            periodTrendAxisLabel(
                              data.labels[i],
                              AppLanguageScope.stringsOf(context),
                            ),
                            style: const TextStyle(fontSize: 11),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            periodFeltDisplayLabel(
                              data.felt[i].label,
                              AppLanguageScope.stringsOf(context),
                            ),
                            style: TextStyle(
                              color: data.felt[i].color,
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
