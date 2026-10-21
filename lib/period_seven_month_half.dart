part of 'main.dart';

/// Click-selected half-month display. No job is started for the other half,
/// another month, exports, or the annual comparison graph.
class MonthHalfOverview extends StatefulWidget {
  const MonthHalfOverview({
    super.key,
    required this.startDateJst,
    required this.profile,
    required this.details,
    this.depth = ReadingDepth.simple,
    this.active = true,
    this.showRangeHeader = true,
    this.startDisplayJob,
  });
  final DateTime startDateJst;
  final AstroProfile profile;
  final UserProfileDetails details;
  final ReadingDepth depth;
  final bool active;
  final bool showRangeHeader;
  final PeriodSevenDisplayStarter? startDisplayJob;

  @override
  State<MonthHalfOverview> createState() => _MonthHalfOverviewState();
}

class _MonthHalfReading {
  const _MonthHalfReading(this.summary, this.daily);
  final PeriodSevenSummary summary;
  final List<PeriodSevenSummary> daily;
}

/// Relative high/low days from existing daily seven-point means only.
/// One pass reads all eight numeric areas; no scoring or ephemeris is run.
class HalfMonthDayHighlightData {
  const HalfMonthDayHighlightData._({
    required this.area,
    required this.maxScore,
    required this.minScore,
    required this.highDates,
    required this.lowDates,
  });
  final NineAreaKey area;
  final int maxScore;
  final int minScore;
  final List<String> highDates;
  final List<String> lowDates;
  bool get hasVariation => maxScore != minScore;

  factory HalfMonthDayHighlightData.fromDaily({
    required List<PeriodSevenSummary> daily,
    required NineAreaKey area,
  }) {
    if (area == NineAreaKey.felt) {
      throw ArgumentError('Felt experience cannot have numeric high/low days.');
    }
    return allFromDaily(daily)[area]!;
  }

  static Map<NineAreaKey, HalfMonthDayHighlightData> allFromDaily(
    List<PeriodSevenSummary> daily,
  ) {
    if (daily.isEmpty) throw ArgumentError('Daily summaries are required.');
    final numeric = NineAreaKey.values.where((key) => key != NineAreaKey.felt);
    final maximum = {for (final key in numeric) key: -1};
    final minimum = {for (final key in numeric) key: 100};
    final highs = {for (final key in numeric) key: <String>[]};
    final lows = {for (final key in numeric) key: <String>[]};
    DateTime? previous;
    final seenDates = <String>{};
    for (final day in daily) {
      final date = DateTime.tryParse(day.startDateJst);
      if (date == null ||
          _monthlyDateLabel(date) != day.startDateJst ||
          !seenDates.add(day.startDateJst) ||
          !day.isSingleDay ||
          day.dayCount != 1 ||
          day.endDateJst != day.startDateJst ||
          day.dates.length != 7 ||
          day.sourceName != daily.first.sourceName ||
          day.requestedHouseSystem != daily.first.requestedHouseSystem ||
          day.usesHighPrecisionAstroData !=
              daily.first.usesHighPrecisionAstroData ||
          (previous != null &&
              date.difference(previous) != const Duration(days: 1))) {
        throw StateError(
          'Daily highlights require distinct consecutive days with the same calculation inputs.',
        );
      }
      previous = date;
      final seenAreas = <NineAreaKey>{};
      for (final entry in day.areas) {
        if (!seenAreas.add(entry.key))
          throw StateError('Duplicate daily area.');
        if (entry.key == NineAreaKey.felt) {
          if (entry.score != null)
            throw StateError('Felt must remain categorical.');
          continue;
        }
        final score = entry.score;
        if (score == null || score < 50 || score > 99) {
          throw StateError(
            'Daily numeric scores must be present and in range.',
          );
        }
        if (score > maximum[entry.key]!) {
          maximum[entry.key] = score;
          highs[entry.key]!.clear();
        }
        if (score == maximum[entry.key])
          highs[entry.key]!.add(day.startDateJst);
        if (score < minimum[entry.key]!) {
          minimum[entry.key] = score;
          lows[entry.key]!.clear();
        }
        if (score == minimum[entry.key]) lows[entry.key]!.add(day.startDateJst);
      }
      if (seenAreas.length != NineAreaKey.values.length) {
        throw StateError('All nine daily areas are required.');
      }
    }
    return Map.unmodifiable({
      for (final key in numeric)
        key: HalfMonthDayHighlightData._(
          area: key,
          maxScore: maximum[key]!,
          minScore: minimum[key]!,
          highDates: List.unmodifiable(highs[key]!),
          lowDates: List.unmodifiable(lows[key]!),
        ),
    });
  }
}

class HalfMonthDayHighlights extends StatelessWidget {
  const HalfMonthDayHighlights({
    super.key,
    required this.data,
    this.periodLabel,
    this.evidence,
  });
  final HalfMonthDayHighlightData data;
  final String? periodLabel;
  final Widget? evidence;

  @override
  Widget build(BuildContext context) {
    final english =
        AppLanguageScope.stringsOf(context).language == AppLanguage.en;
    final period = periodLabel ?? (english ? 'this half' : 'この半月');
    final activity = data.area == NineAreaKey.actionDecision;
    String dates(List<String> values) => values
        .map((value) {
          final date = DateTime.parse(value);
          return '${date.month}/${date.day}';
        })
        .join(english ? ', ' : '・');
    const style = TextStyle(fontSize: 16, height: 1.45);
    return GlassPanel(
      key: ValueKey('half-highlights-${data.area.name}'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (data.hasVariation) ...[
            Text(
              english
                  ? '${activity ? 'Higher-activity days' : 'Stronger days'} in $period: ${dates(data.highDates)} · ${data.maxScore}'
                  : '$periodで${activity ? '活動性が高い日' : '好調な日'}：${dates(data.highDates)}（${data.maxScore}点）',
              key: ValueKey('half-highlights-high-${data.area.name}'),
              style: style,
            ),
            const SizedBox(height: 8),
            Text(
              english
                  ? '${activity ? 'Lower-activity days' : 'Days to take more gently'}: ${dates(data.lowDates)} · ${data.minScore}'
                  : '${activity ? '活動性が低い日' : '控えめに進めたい日'}：${dates(data.lowDates)}（${data.minScore}点）',
              key: ValueKey('half-highlights-low-${data.area.name}'),
              style: style,
            ),
          ] else
            Text(
              english
                  ? 'No day-to-day score difference · ${data.maxScore}'
                  : '日ごとの点数差なし（${data.maxScore}点）',
              key: ValueKey('half-highlights-equal-${data.area.name}'),
              style: style,
            ),
          const SizedBox(height: 8),
          Text(
            english
                ? (activity
                      ? 'Relative activity levels in $period, based on daily seven-point means; not success or decision correctness.'
                      : 'Relative to the daily seven-point means in $period; not an absolute good/bad-day verdict.')
                : (activity
                      ? '各日7点平均の$period内での相対比較です。活動性の強弱であり、成功や判断の正しさではありません。'
                      : '各日7点平均の$period内での相対比較です。絶対的な良い日・悪い日を示すものではありません。'),
            key: ValueKey('half-highlights-note-${data.area.name}'),
            style: style,
          ),
          if (evidence != null) ...[const SizedBox(height: 12), evidence!],
        ],
      ),
    );
  }
}

class _PeriodScoreHighlightCache {
  _PeriodScoreHighlightCache(
    PeriodSevenSummary summary,
    List<PeriodSevenSummary>? supplied,
  ) : daily = List.unmodifiable(
        supplied ??
            [
              for (var index = 0; index < summary.dayCount; index++)
                summary.daySummaryAt(index),
            ],
      ) {
    if (daily.length != summary.dayCount ||
        daily.first.startDateJst != summary.startDateJst ||
        daily.last.endDateJst != summary.endDateJst) {
      throw StateError('Highlight days do not match the selected period.');
    }
    highlights = HalfMonthDayHighlightData.allFromDaily(daily);
  }
  final List<PeriodSevenSummary> daily;
  late final Map<NineAreaKey, HalfMonthDayHighlightData> highlights;
  static final bySummary = Expando<_PeriodScoreHighlightCache>();
}

/// Detailed week/half-month guidance from already-calculated daily summaries.
/// Numeric extrema and each representative day's explanation stay separate.
class PeriodScoreDayHighlights extends StatefulWidget {
  const PeriodScoreDayHighlights({
    super.key,
    required this.summary,
    required this.area,
    required this.details,
    this.dailySummaries,
  });
  final PeriodSevenSummary summary;
  final NineAreaKey area;
  final UserProfileDetails details;
  final List<PeriodSevenSummary>? dailySummaries;

  @override
  State<PeriodScoreDayHighlights> createState() =>
      _PeriodScoreDayHighlightsState();
}

class _PeriodScoreDayHighlightsState extends State<PeriodScoreDayHighlights> {
  Object? _identity;
  late HalfMonthDayHighlightData _data;
  late ForecastExplanationResult _high;
  ForecastExplanationResult? _low;

  @override
  Widget build(BuildContext context) {
    if (widget.area == NineAreaKey.felt) return const SizedBox.shrink();
    final strings = AppLanguageScope.stringsOf(context);
    final english = strings.language == AppLanguage.en;
    final identity = (
      widget.summary,
      widget.area,
      strings.language,
      jsonEncode(widget.details.toJson()),
      ReadingDepth.detailed,
    );
    if (identity != _identity) {
      final cache = _PeriodScoreHighlightCache.bySummary[widget.summary] ??=
          _PeriodScoreHighlightCache(widget.summary, widget.dailySummaries);
      _data = cache.highlights[widget.area]!;
      ForecastExplanationResult explain(String date) {
        final day = cache.daily.singleWhere(
          (item) => item.startDateJst == date,
        );
        return ForecastExplanation.forPeriod(
          summary: day,
          area: day.areas.singleWhere((item) => item.key == widget.area),
          strings: strings,
          depth: ReadingDepth.detailed,
          supplement: widget.details,
          dailySamples: day.predictionsByInstant,
        );
      }

      _high = explain(_data.highDates.first);
      _low = _data.hasVariation ? explain(_data.lowDates.first) : null;
      _identity = identity;
    }
    Widget example(
      String role,
      String date,
      ForecastExplanationResult explanation,
    ) {
      final parsed = DateTime.parse(date);
      final label = '${parsed.month}/${parsed.day}';
      final materials = [
        if (explanation.positiveMaterials.isNotEmpty)
          '${english ? 'Support' : '正の材料'}: ${explanation.positiveMaterials.first}',
        if (explanation.negativeMaterials.isNotEmpty)
          '${english ? 'Tension' : '負の材料'}: ${explanation.negativeMaterials.first}',
        if (explanation.neutralMaterials.isNotEmpty)
          '${english ? 'Activity / neutral' : '活動・中立の材料'}: ${explanation.neutralMaterials.first}',
      ];
      const style = TextStyle(fontSize: 16, height: 1.45);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            english
                ? 'Representative example: $label (evidence for this day only)'
                : '代表例 $label の根拠（この日のみ）',
            key: ValueKey('half-highlights-example-$role-${widget.area.name}'),
            style: style.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            explanation.interpretation,
            key: ValueKey(
              'half-highlights-interpretation-$role-${widget.area.name}',
            ),
            style: style,
          ),
          const SizedBox(height: 8),
          Text(
            materials.isEmpty
                ? (english
                      ? 'No verified selected astronomical material supplied.'
                      : '確認できる選択済み天文材料は未提供です。')
                : '${english ? 'Evidence excerpts (first recorded item in each category)' : '根拠の抜粋（各区分の記録先頭1件）'}\n${materials.join('\n')}',
            key: ValueKey('half-highlights-material-$role-${widget.area.name}'),
            style: style,
          ),
          const SizedBox(height: 8),
          Text(
            '${english ? 'Try' : '行動のヒント'}: ${explanation.advice}',
            key: ValueKey('half-highlights-advice-$role-${widget.area.name}'),
            style: style,
          ),
          Material(
            color: Colors.transparent,
            child: ExpansionTile(
              key: ValueKey('half-highlights-ledger-$role-${widget.area.name}'),
              tilePadding: EdgeInsets.zero,
              title: Text(
                english ? 'Full evidence for $label' : '$label の根拠をすべて見る',
                style: style,
              ),
              children: [Text(explanation.numericLedgerText, style: style)],
            ),
          ),
        ],
      );
    }

    return HalfMonthDayHighlights(
      data: _data,
      periodLabel: widget.summary.displayRangeLabel(strings),
      evidence: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          example('high', _data.highDates.first, _high),
          if (_low != null) ...[
            const SizedBox(height: 14),
            example('low', _data.lowDates.first, _low!),
          ],
        ],
      ),
    );
  }
}

class _MonthHalfOverviewState extends State<MonthHalfOverview>
    with WidgetsBindingObserver {
  late Object _scope;
  final _halves = <bool, _MonthHalfReading>{};
  bool _second = false;
  int _generation = 0;
  int _done = 0;
  bool _working = false;
  bool _queued = false;
  bool _failed = false;
  bool _cancelled = false;
  bool _resetQueued = false;
  VoidCallback? _cancelJob;
  Object? _explanationKey;
  Map<NineAreaKey, ForecastExplanationResult> _explanations = const {};

  DateTime get _month =>
      DateTime.utc(widget.startDateJst.year, widget.startDateJst.month);
  DateTime get _first =>
      DateTime.utc(_month.year, _month.month, _second ? 16 : 1);
  DateTime get _last => _second
      ? DateTime.utc(_month.year, _month.month + 1, 0)
      : DateTime.utc(_month.year, _month.month, 15);
  int get _total => (_last.difference(_first).inDays + 1) * 7;
  Object get _inputs => (
    _month,
    PeriodReadingContextRequest.profileIdentity(widget.profile),
    jsonEncode(widget.details.toJson()),
    HouseSystemSettings.current.value,
    AstrologyDataSources.current.sourceName,
    AstrologyDataSources.current.usesHighPrecisionAstroData,
    widget.startDisplayJob,
  );

  @override
  void initState() {
    super.initState();
    _scope = _inputs;
    WidgetsBinding.instance.addObserver(this);
    HouseSystemSettings.current.addListener(_environmentChanged);
    _queue();
  }

  @override
  void didUpdateWidget(covariant MonthHalfOverview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_scope != _inputs) {
      _reset();
    } else if (oldWidget.active != widget.active) {
      _stop();
      if (widget.active && !_halves.containsKey(_second)) _queue();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _environmentChanged();
  }

  void _environmentChanged() {
    if (mounted && _scope != _inputs) setState(_reset);
  }

  void _stop() {
    ++_generation;
    _queued = false;
    _working = false;
    final cancel = _cancelJob;
    _cancelJob = null;
    cancel?.call();
  }

  void _reset() {
    _stop();
    _scope = _inputs;
    _halves.clear();
    _explanations = const {};
    _explanationKey = null;
    _failed = _cancelled = false;
    _done = 0;
    _queue();
  }

  void _queue() {
    if (!widget.active || _halves.containsKey(_second)) return;
    final generation = _generation;
    _queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _generation || !widget.active) return;
      _queued = false;
      unawaited(_load());
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  bool _current(int token, Object scope, bool second) =>
      mounted &&
      widget.active &&
      token == _generation &&
      scope == _scope &&
      scope == _inputs &&
      second == _second;

  void _choose(bool second) {
    if (_second == second) return;
    setState(() {
      _stop();
      _second = second;
      _done = 0;
      _failed = _cancelled = false;
      _explanationKey = null;
      _queue();
    });
  }

  Future<void> _load() async {
    if (!mounted ||
        !widget.active ||
        _working ||
        _scope != _inputs ||
        _halves.containsKey(_second))
      return;
    final token = ++_generation;
    final scope = _scope;
    final second = _second;
    final first = _first;
    final last = _last;
    final request = PeriodSevenDisplayRequest(
      startDateJst: first,
      endDateJst: last,
      profile: widget.profile,
      details: widget.details,
      requestedHouseSystem: HouseSystemSettings.current.value,
      sourceName: AstrologyDataSources.current.sourceName,
      requireHighPrecision:
          AstrologyDataSources.current.usesHighPrecisionAstroData,
      generatedAt: DateTime.now().toUtc(),
    );
    setState(() {
      _working = true;
      _failed = _cancelled = false;
      _done = 0;
    });
    try {
      final job = (widget.startDisplayJob ?? PeriodSevenDisplayJob.start)(
        request,
        (done, total) {
          if (_current(token, scope, second) && total == _total) {
            setState(() => _done = done.clamp(0, total));
          }
        },
      );
      final future = job.result;
      if (!_current(token, scope, second)) {
        job.cancel();
        await future;
        return;
      }
      _cancelJob = job.cancel;
      final result = await future;
      if (!_current(token, scope, second)) return;
      validatePeriodSevenDisplayResult(result: result, request: request);
      PeriodSevenSummary aggregate(
        DateTime from,
        DateTime to,
        List<Map<String, Object?>> days,
      ) => PeriodSevenSummary.fromDisplayRange(
        startDateJst: from,
        endDateJst: to,
        days: days,
        profile: widget.profile,
        details: widget.details,
        requestedHouseSystem: request.requestedHouseSystem,
        sourceName: request.sourceName,
        requireHighPrecision: request.requireHighPrecision,
      );
      final summary = aggregate(first, last, result.days);
      final daily = List<PeriodSevenSummary>.unmodifiable([
        for (var index = 0; index < result.days.length; index++)
          summary.daySummaryAt(index),
      ]);
      if (!_current(token, scope, second)) return;
      setState(() {
        _halves[second] = _MonthHalfReading(summary, daily);
        _cancelJob = null;
        _working = false;
        _done = _total;
        _explanationKey = null;
      });
    } catch (error) {
      if (!_current(token, scope, second)) return;
      _cancelJob?.call();
      _cancelJob = null;
      setState(() {
        _working = false;
        _cancelled = error is PeriodSevenDisplayCancelled;
        _failed = !_cancelled;
      });
    }
  }

  Map<NineAreaKey, ForecastExplanationResult> _readings(
    PeriodSevenSummary summary,
    AppStrings strings,
  ) {
    final identity = (summary, strings.language, widget.depth);
    if (identity != _explanationKey) {
      _explanations = {
        for (final area in summary.areas)
          area.key: ForecastExplanation.forPeriod(
            summary: summary,
            area: area,
            strings: strings,
            depth: widget.depth,
            supplement: widget.details,
            dailySamples: summary.predictionsByInstant,
          ),
      };
      _explanationKey = identity;
    }
    return _explanations;
  }

  @override
  void dispose() {
    HouseSystemSettings.current.removeListener(_environmentChanged);
    WidgetsBinding.instance.removeObserver(this);
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return const SizedBox.shrink();
    final matching = _scope == _inputs;
    if (!matching && !_resetQueued) {
      _resetQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _resetQueued = false;
        if (mounted && _scope != _inputs) setState(_reset);
      });
    }
    final strings = AppLanguageScope.stringsOf(context);
    final english = strings.language == AppLanguage.en;
    final result = matching ? _halves[_second] : null;
    final busy = _working || _queued || !matching;
    final title = _second
        ? (english ? 'Second half' : '後半')
        : (english ? 'First half' : '前半');
    final explanations = result == null
        ? null
        : _readings(result.summary, strings);
    return Column(
      key: const ValueKey('half-month-overview'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            ChoiceChip(
              key: const ValueKey('half-month-first'),
              label: Text(
                english ? 'First half · 1–15' : '前半 · 1〜15日',
                style: const TextStyle(fontSize: 17),
              ),
              selected: !_second,
              onSelected: (_) => _choose(false),
            ),
            ChoiceChip(
              key: const ValueKey('half-month-second'),
              label: Text(
                english ? 'Second half · 16–end' : '後半 · 16日〜月末',
                style: const TextStyle(fontSize: 17),
              ),
              selected: _second,
              onSelected: (_) => _choose(true),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '$title  ${_monthlyDateLabel(_first)} – ${_monthlyDateLabel(_last)} JST',
          key: const ValueKey('half-month-range'),
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        if (busy) ...[
          LinearProgressIndicator(
            key: const ValueKey('half-month-progress'),
            value: _working ? _done / _total : null,
          ),
          const SizedBox(height: 8),
          Text(
            english
                ? 'Reading this half only… $_done/$_total'
                : '選択した$titleだけを計算中… $_done/$_total',
            key: const ValueKey('half-month-status'),
            style: const TextStyle(fontSize: 16),
          ),
          TextButton(
            key: const ValueKey('half-month-cancel'),
            onPressed: () => setState(() {
              _stop();
              _cancelled = true;
              _failed = false;
            }),
            child: Text(english ? 'Cancel' : '中止'),
          ),
        ] else if (result == null && (_failed || _cancelled)) ...[
          Text(
            english
                ? (_cancelled
                      ? 'Calculation cancelled.'
                      : 'This half could not be verified.')
                : (_cancelled ? '計算を中止しました。' : '選択した半月のデータを確認できませんでした。'),
            key: const ValueKey('half-month-status'),
            style: const TextStyle(fontSize: 16),
          ),
          FilledButton.icon(
            key: const ValueKey('half-month-retry'),
            onPressed: () => setState(() {
              _stop();
              _queue();
            }),
            icon: const Icon(Icons.refresh),
            label: Text(english ? 'Retry this half' : 'この半月を再試行'),
          ),
        ],
        if (result != null) ...[
          MonthHalfDailyTrend(
            summary: result.summary,
            dailySummaries: result.daily,
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.hasBoundedWidth
                  ? constraints.maxWidth
                  : 390.0;
              final columns = math.max(
                1,
                math.min(
                  3,
                  (width / MediaQuery.textScalerOf(context).scale(350)).floor(),
                ),
              );
              final cardWidth = (width - 16 * (columns - 1)) / columns;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final area in result.summary.areas)
                    SizedBox(
                      width: cardWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _PeriodSevenOverviewCard(
                            key: ValueKey(
                              'period-overview-card-${area.key.name}',
                            ),
                            area: area,
                            summary: result.summary,
                            explanation: explanations![area.key]!,
                            strings: strings,
                            depth: widget.depth,
                            bodySize: width >= 700 ? 18 : 16,
                          ),
                          if (widget.depth == ReadingDepth.detailed &&
                              area.key != NineAreaKey.felt) ...[
                            const SizedBox(height: 8),
                            PeriodScoreDayHighlights(
                              summary: result.summary,
                              area: area.key,
                              details: widget.details,
                              dailySummaries: result.daily,
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Material(
            color: Colors.transparent,
            child: ExpansionTile(
              key: const ValueKey('half-month-settings'),
              title: Text(english ? 'Reading settings' : 'この占いの条件'),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    [
                      result.summary.displaySamplingText(strings),
                      english
                          ? 'Circles: this half’s unique time points, averaged once. Graph: each day’s seven-point mean. Felt labels remain categorical. The other half is calculated only when selected.'
                          : '丸は選択した半月の重複を除いた時点の平均、グラフは各日の7点平均です。体感は数値化しません。もう片方は選んだときだけ計算します。',
                      english
                          ? 'JST (UTC+09:00). High-precision data: ${result.summary.usesHighPrecisionAstroData ? 'used' : 'not used'}.'
                          : 'JST（UTC+09:00）。高精度データ：${result.summary.usesHighPrecisionAstroData ? '使用' : '未使用'}。',
                      if (!widget.details.hasBirthTime)
                        english
                            ? 'Birth time missing: existing 12:00 assumption.'
                            : '出生時刻未入力：既存の12:00仮置き。',
                      if (!widget.details.hasBirthPlace)
                        english
                            ? 'Birthplace missing: existing Sapporo assumption.'
                            : '出生地未入力：既存の札幌市仮置き。',
                    ].join('\n\n'),
                    style: const TextStyle(fontSize: 16, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ] else
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              for (final area in NineAreaKey.values)
                Text(
                  strings.nineAreaTitle(area.name),
                  style: const TextStyle(fontSize: 16),
                ),
            ],
          ),
      ],
    );
  }
}

class MonthHalfDailyTrend extends StatelessWidget {
  const MonthHalfDailyTrend({
    super.key,
    required this.summary,
    required this.dailySummaries,
    this.weekly = false,
  });
  final PeriodSevenSummary summary;
  final List<PeriodSevenSummary> dailySummaries;
  final bool weekly;

  @override
  Widget build(BuildContext context) {
    final strings = AppLanguageScope.stringsOf(context);
    final english = strings.language == AppLanguage.en;
    final days = dailySummaries;
    final labels = [
      for (final day in days)
        _monthDayWithWeekday(DateTime.parse(day.startDateJst)),
    ];
    List<int> values(NineAreaKey key) => [
      for (final day in days)
        day.areas.singleWhere((area) => area.key == key).score!,
    ];
    final series = [
      for (var index = 0; index < 5; index++)
        FortuneFlowSeries(
          label: PeriodSevenGroupedTrendData.mainLabels[index],
          color: PeriodSevenGroupedTrendData.mainColors[index],
          values: values(PeriodSevenGroupedTrendData.mainKeys[index]),
        ),
    ];
    final additional = AdditionalFortuneTrendData._build(
      labels,
      [for (final key in AdditionalFortuneTrendData.numericKeys) values(key)],
      [
        for (final day in days)
          FeltTrendPoint(
            label: day.feltDisplayLabel,
            periodSummary: day,
            detail: day.displayDetail(
              day.areas.singleWhere((area) => area.key == NineAreaKey.felt),
              strings,
            ),
          ),
      ],
    );
    final basis = english
        ? 'Each point is that day’s seven-point mean. Felt experience uses the most frequent label; ties remain Mixed.'
        : '各点はその日の7点平均です。体感は最頻候補、最多同数は混在です。';
    return GlassPanel(
      key: ValueKey(weekly ? 'weekly-daily-graph' : 'half-month-graph'),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            weekly
                ? (english ? 'Daily trends this week' : 'この週の日ごとの流れ')
                : (english ? 'Daily trends in this half' : 'この半月の日ごとの流れ'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            english
                ? 'Daily seven-point mean · 50–99 · JST'
                : '各日7点の平均・50〜99点・JST',
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: math.max(
                  constraints.maxWidth,
                  MediaQuery.textScalerOf(context).scale(72) *
                          (labels.length - 1) +
                      46,
                ),
                height: FortuneFlowPainter.chartHeight(
                  MediaQuery.textScalerOf(context),
                ),
                child: Semantics(
                  label: english
                      ? 'Five lines: overall, love, work, money and mental well-being.'
                      : '総合・恋愛・仕事・金運・メンタルの5本の線。',
                  child: CustomPaint(
                    key: ValueKey(
                      weekly ? 'weekly-daily-chart' : 'half-month-chart',
                    ),
                    painter: FortuneFlowPainter(
                      textScaler: MediaQuery.textScalerOf(context),
                      series: series,
                      labels: labels
                          .map((label) => periodTrendAxisLabel(label, strings))
                          .toList(),
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              for (final item in series)
                _FlowLegend(label: item.label, color: item.color),
            ],
          ),
          AdditionalFortuneTrendChart(
            key: ValueKey(
              weekly ? 'weekly-daily-additional' : 'half-month-additional',
            ),
            dataIdentity: summary,
            basis: basis,
            dataFor: () => additional,
          ),
        ],
      ),
    );
  }
}
