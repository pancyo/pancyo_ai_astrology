part of 'main.dart';

/// A complete week/month reading, calculated in memory from canonical daily-v4
/// data. No predictions, profiles, exports or sharing state are written here.
class PeriodSevenOverview extends StatefulWidget {
  const PeriodSevenOverview({
    super.key,
    required this.mode,
    required this.startDateJst,
    required this.profile,
    required this.details,
    this.depth = ReadingDepth.simple,
    this.active = true,
    this.showRangeHeader = true,
    this.startWeeklyJob,
    this.startMonthlyJob,
    this.startDisplayJob,
  }) : assert(mode != LongRangeMode.year);

  final LongRangeMode mode;
  final DateTime startDateJst;
  final AstroProfile profile;
  final UserProfileDetails details;
  final ReadingDepth depth;
  final bool active;
  final bool showRangeHeader;
  final WeeklyDailyConsultExportStarter? startWeeklyJob;
  final MonthlyDailyConsultExportStarter? startMonthlyJob;
  final PeriodSevenDisplayStarter? startDisplayJob;

  @override
  State<PeriodSevenOverview> createState() => _PeriodSevenOverviewState();
}

class _PeriodSevenOverviewState extends State<PeriodSevenOverview>
    with WidgetsBindingObserver {
  late Object _scope;
  VoidCallback? _cancelOperation;
  int _generation = 0;
  int? _queuedGeneration;
  int _completed = 0;
  int? _monthPart;
  bool _working = false;
  bool _failed = false;
  bool _cancelled = false;
  bool _scopeResetQueued = false;
  PeriodSevenSummary? _summary;
  String? _sourceName;
  bool? _highPrecision;
  Object? _explanationIdentity;
  Map<NineAreaKey, ForecastExplanationResult> _explanations = const {};
  PeriodSevenSummary? _highlightSummary;
  List<PeriodSevenSummary> _highlightDays = const [];

  static DateTime _firstDay(PeriodSevenOverview input) => DateTime.utc(
    input.startDateJst.year,
    input.startDateJst.month,
    input.mode == LongRangeMode.month ? 1 : input.startDateJst.day,
  );

  DateTime get _first => _firstDay(widget);
  int get _dayCount => widget.mode == LongRangeMode.month
      ? DateTime.utc(_first.year, _first.month + 1, 0).day
      : 7;
  int get _total => _dayCount * 7;

  Object get _inputScope => (
    widget.mode,
    _first,
    PeriodReadingContextRequest.profileIdentity(widget.profile),
    jsonEncode(widget.details.toJson()),
    widget.startWeeklyJob,
    widget.startMonthlyJob,
    widget.startDisplayJob,
    HouseSystemSettings.current.value,
    AstrologyDataSources.current.sourceName,
    AstrologyDataSources.current.usesHighPrecisionAstroData,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HouseSystemSettings.current.addListener(_environmentChanged);
    _scope = _inputScope;
    _queueLoad();
  }

  @override
  void didUpdateWidget(covariant PeriodSevenOverview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_scope != _inputScope || oldWidget.active != widget.active) _reset();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _environmentChanged();
  }

  void _environmentChanged() {
    if (mounted && _scope != _inputScope) setState(_reset);
  }

  void _stop() {
    ++_generation;
    _queuedGeneration = null;
    final cancel = _cancelOperation;
    _cancelOperation = null;
    _working = false;
    cancel?.call();
  }

  void _reset() {
    _stop();
    _scope = _inputScope;
    _summary = null;
    _sourceName = null;
    _highPrecision = null;
    _explanationIdentity = null;
    _explanations = const {};
    _highlightSummary = null;
    _highlightDays = const [];
    _completed = 0;
    _monthPart = null;
    _failed = false;
    _cancelled = false;
    _queueLoad();
  }

  void _queueLoad() {
    if (!widget.active) return;
    final token = _generation;
    _queuedGeneration = token;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.active || token != _generation) return;
      _queuedGeneration = null;
      unawaited(_load());
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  bool _current(int token, Object scope) =>
      mounted &&
      widget.active &&
      token == _generation &&
      scope == _scope &&
      scope == _inputScope;

  Future<void> _load() async {
    if (!mounted || !widget.active || _working || _scope != _inputScope) return;
    final token = ++_generation;
    final scope = _scope;
    final source = AstrologyDataSources.current;
    setState(() {
      _working = true;
      _completed = 0;
      _monthPart = null;
      _failed = false;
      _cancelled = false;
    });
    try {
      final summary = await _loadPeriodSevenDisplay(
        mode: widget.mode,
        first: _first,
        profile: widget.profile,
        details: widget.details,
        houseSystem: HouseSystemSettings.current.value,
        sourceName: source.sourceName,
        highPrecision: source.usesHighPrecisionAstroData,
        startWeeklyJob: widget.startWeeklyJob,
        startMonthlyJob: widget.startMonthlyJob,
        startDisplayJob: widget.startDisplayJob,
        isCurrent: () => _current(token, scope),
        onCancel: (cancel) {
          if (_current(token, scope)) _cancelOperation = cancel;
        },
        onProgress: (done, total, monthPart) {
          if (_current(token, scope) && total == _total) {
            setState(() {
              _completed = done.clamp(0, total);
              _monthPart = monthPart;
            });
          }
        },
      );
      if (!_current(token, scope) || summary == null) return;
      _cancelOperation = null;
      setState(() {
        _summary = summary;
        _sourceName = source.sourceName;
        _highPrecision = source.usesHighPrecisionAstroData;
        _working = false;
        _completed = _total;
        _explanationIdentity = null;
      });
    } catch (error) {
      if (!_current(token, scope)) return;
      _cancelOperation?.call();
      _cancelOperation = null;
      setState(() {
        _working = false;
        _cancelled = _periodSevenDisplayWasCancelled(error);
        _failed = !_cancelled;
        _summary = null;
      });
    }
  }

  void _cancel() => setState(() {
    _stop();
    _cancelled = true;
    _failed = false;
  });

  void _retry() => setState(() {
    _stop();
    _cancelled = false;
    _failed = false;
    _queueLoad();
  });

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HouseSystemSettings.current.removeListener(_environmentChanged);
    _stop();
    super.dispose();
  }

  Map<NineAreaKey, ForecastExplanationResult> _readings(
    PeriodSevenSummary summary,
    AppStrings strings,
  ) {
    final identity = (summary, strings.language, widget.depth);
    if (identity != _explanationIdentity) {
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
      _explanationIdentity = identity;
    }
    return _explanations;
  }

  List<PeriodSevenSummary> _dailyHighlights(PeriodSevenSummary summary) {
    if (!identical(_highlightSummary, summary)) {
      _highlightDays = List.unmodifiable([
        for (var index = 0; index < summary.dayCount; index++)
          summary.daySummaryAt(index),
      ]);
      _highlightSummary = summary;
    }
    return _highlightDays;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return const SizedBox.shrink();
    final currentScope = _scope == _inputScope;
    if (!currentScope && !_scopeResetQueued) {
      _scopeResetQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scopeResetQueued = false;
        if (mounted && _scope != _inputScope) setState(_reset);
      });
      WidgetsBinding.instance.scheduleFrame();
    }
    final strings = AppLanguageScope.stringsOf(context);
    final english = strings.language == AppLanguage.en;
    final summary = currentScope ? _summary : null;
    final loading = _working || _queuedGeneration != null || !currentScope;
    final end = _first.add(Duration(days: _dayCount - 1));
    final title = widget.mode == LongRangeMode.week
        ? (english ? 'Weekly reading' : '週間の占い')
        : (english ? 'Monthly reading' : '月間の占い');
    final explanations = summary == null ? null : _readings(summary, strings);
    return Column(
      key: const ValueKey('period-overview'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showRangeHeader) ...[
          Text(
            '$title\n${_monthlyDateLabel(_first)} – ${_monthlyDateLabel(end)} JST',
            key: const ValueKey('period-overview-range'),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
        ],
        if (loading) ...[
          LinearProgressIndicator(
            key: const ValueKey('period-overview-progress'),
            value: _working ? _completed / _total : null,
          ),
          const SizedBox(height: 8),
          Text(
            _monthPart == null
                ? (english
                      ? 'Calculating the whole period… $_completed/$_total'
                      : '期間全体の占いを計算中… $_completed/$_total')
                : (english
                      ? 'Reading ${_monthPart == 1 ? 'days 1–15' : 'days 16–$_dayCount'}… $_completed/$_total. The complete month appears after both parts are ready.'
                      : '${_monthPart == 1 ? '前半（1〜15日）' : '後半（16〜$_dayCount日）'}を読んでいます… $_completed/$_total。両方そろうと月全体を表示します。'),
            key: const ValueKey('period-overview-loading-status'),
            style: const TextStyle(fontSize: 16),
          ),
          TextButton(
            key: const ValueKey('period-overview-cancel'),
            onPressed: _cancel,
            child: Text(english ? 'Cancel' : '中止'),
          ),
        ] else if (_failed || _cancelled) ...[
          Text(
            english
                ? (_cancelled
                      ? 'Calculation cancelled. The period reading is not ready.'
                      : 'The complete period could not be verified. No partial result is shown as a complete reading.')
                : (_cancelled
                      ? '計算を中止しました。期間の占いは未作成です。'
                      : '期間全体のデータを確認できませんでした。不完全な結果は期間の占いとして表示しません。'),
            key: const ValueKey('period-overview-status'),
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const ValueKey('period-overview-retry'),
            onPressed: _retry,
            icon: const Icon(Icons.refresh),
            label: Text(english ? 'Retry' : '再試行'),
          ),
          if (widget.mode == LongRangeMode.month)
            Text(
              english
                  ? 'Verified parts are reused during this app session when the reading inputs are unchanged.'
                  : '同じ入力条件で完了した前半・後半は、このアプリ起動中の再試行で再利用します。',
              style: const TextStyle(fontSize: 16),
            ),
        ],
        if (summary == null)
          Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              for (final area in NineAreaKey.values)
                Text(
                  strings.nineAreaTitle(area.name),
                  key: ValueKey('period-overview-placeholder-${area.name}'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          )
        else ...[
          if (widget.mode == LongRangeMode.week)
            MonthHalfDailyTrend(
              summary: summary,
              dailySummaries: _dailyHighlights(summary),
              weekly: true,
            )
          else
            PeriodSevenTrend(
              summary: summary,
              profile: widget.profile,
              details: widget.details,
              startWeeklyJob: widget.startWeeklyJob,
              startMonthlyJob: widget.startMonthlyJob,
              startDisplayJob: widget.startDisplayJob,
            ),
          const SizedBox(height: 16),
          if (widget.depth == ReadingDepth.simple &&
              MediaQuery.sizeOf(context).shortestSide >= 600)
            SimpleNineAreaDashboard(
              items: [
                for (final area in summary.areas)
                  SimpleNineAreaItem(
                    area: area.key,
                    title: strings.nineAreaTitle(area.key.name),
                    icon: area.icon,
                    narrative: explanations![area.key]!.narrativeText,
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
              mainFiveKey: ValueKey(
                widget.mode == LongRangeMode.week
                    ? 'weekly-main-five'
                    : 'monthly-main-five',
              ),
              additionalFourKey: ValueKey(
                widget.mode == LongRangeMode.week
                    ? 'weekly-additional-four'
                    : 'monthly-additional-four',
              ),
              cardKeyPrefix: 'period-overview-card',
              valueKeyPrefix: 'period-overview-value',
              narrativeKeyPrefix: 'period-overview-narrative',
              shareSummaryKey: const ValueKey('weekly-share-reading'),
              shareOverallKey: const ValueKey('period-overview-share-overall'),
              onShareSummary: () =>
                  _shareReading(summary, explanations!, strings),
              onShareOverall: () => _shareReading(
                summary,
                explanations!,
                strings,
                selectedArea: summary.areas.firstWhere(
                  (area) => area.key == NineAreaKey.overall,
                ),
              ),
            )
          else ...[
            if (widget.depth == ReadingDepth.simple) ...[
              SimpleReadingShareActions(
                shareSummaryKey: const ValueKey('weekly-share-reading'),
                shareOverallKey: const ValueKey(
                  'period-overview-share-overall',
                ),
                onShareSummary: () =>
                    _shareReading(summary, explanations!, strings),
                onShareOverall: () => _shareReading(
                  summary,
                  explanations!,
                  strings,
                  selectedArea: summary.areas.firstWhere(
                    (area) => area.key == NineAreaKey.overall,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.hasBoundedWidth
                    ? constraints.maxWidth
                    : 390.0;
                final minimum = MediaQuery.textScalerOf(context).scale(350);
                final columns = math.max(
                  1,
                  math.min(3, (width / minimum).floor()),
                );
                const gap = 16.0;
                final cardWidth = (width - gap * (columns - 1)) / columns;
                Widget cards(Iterable<NineAreaPeriodEntry> areas) => Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final area in areas)
                      SizedBox(
                        width: cardWidth,
                        child: _PeriodSevenOverviewCard(
                          key: ValueKey(
                            'period-overview-card-${area.key.name}',
                          ),
                          area: area,
                          summary: summary,
                          explanation: explanations![area.key]!,
                          strings: strings,
                          bodySize: width >= 700 ? 18 : 16,
                        ),
                      ),
                  ],
                );
                if (widget.mode != LongRangeMode.week)
                  return cards(summary.areas);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      english ? 'Five main categories' : '主要5項目',
                      key: const ValueKey('weekly-main-five'),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    cards(
                      summary.areas.where(
                        (area) => PeriodSevenGroupedTrendData.mainKeys.contains(
                          area.key,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      english ? 'Four additional categories' : '追加4項目',
                      key: const ValueKey('weekly-additional-four'),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    cards(
                      summary.areas.where(
                        (area) => !PeriodSevenGroupedTrendData.mainKeys
                            .contains(area.key),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
          const SizedBox(height: 16),
          _settings(summary, strings),
        ],
      ],
    );
  }

  Future<void> _shareReading(
    PeriodSevenSummary summary,
    Map<NineAreaKey, ForecastExplanationResult> explanations,
    AppStrings strings, {
    NineAreaPeriodEntry? selectedArea,
  }) {
    final selected = selectedArea ?? summary.areas.first;
    return showNineAreaReadingShareComposer(
      context,
      periodLabel: nineAreaPeriodShareLabel(summary, strings),
      areaHighlightsText: OverallAreaHighlights.fromSummary(
        summary,
      ).text(strings),
      areas: [
        for (final area in selectedArea == null ? summary.areas : [selected])
          FortuneShareArea(
            key: area.key,
            title: strings.nineAreaTitle(area.key.name),
            score: area.score,
            feltLabel: area.key == NineAreaKey.felt
                ? summary.feltDisplayLabel
                : null,
          ),
      ],
      body: explanations[selected.key]!.narrativeText,
    );
  }

  Widget _settings(PeriodSevenSummary summary, AppStrings strings) {
    final english = strings.language == AppLanguage.en;
    final source = english && _sourceName == 'アプリ内簡易計算'
        ? 'Built-in simplified calculation'
        : _sourceName;
    final assumptions = [
      if (!widget.details.hasBirthTime)
        english
            ? 'Birth time missing: existing 12:00 assumption.'
            : '出生時刻未入力：既存の12:00仮置き。',
      if (!widget.details.hasBirthPlace)
        english
            ? 'Birthplace missing: existing Sapporo, Hokkaido assumption.'
            : '出生地未入力：既存の北海道札幌市仮置き。',
    ];
    return Material(
      color: Colors.transparent,
      child: ExpansionTile(
        key: const ValueKey('period-overview-settings'),
        tilePadding: EdgeInsets.zero,
        title: Text(
          english ? 'Reading settings' : 'この占いの条件',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              [
                summary.displaySamplingText(strings),
                summary.displaySampleLimitation(strings),
                english
                    ? 'Eight numeric areas: arithmetic mean across unique time points, rounded once at the end. Felt experience: most frequent category; ties remain Mixed. It is never averaged numerically.'
                    : '数値8項目は、重複を除いた全時点を算術平均し、最後に1回四捨五入します。体感は最頻候補で、最多同数は混在のままです。体感は数値平均しません。',
                english
                    ? 'Daily 24:00 equals the next day’s 00:00; that boundary is counted once. The final endpoint is included. JST (UTC+09:00).'
                    : '各日24時＝翌日00時の境界は1回だけ集計し、期間末の終端も含めます。時刻はJST（UTC+09:00）です。',
                english
                    ? 'Calculation source: $source. High-precision data: ${_highPrecision == true ? 'used' : 'not used'}.'
                    : '計算元：$source。高精度データ：${_highPrecision == true ? '使用' : '未使用'}。',
                ...assumptions,
                english
                    ? 'Experimental and unvalidated. Existing calculations and coefficients are unchanged.'
                    : '試作・未検証です。元の計算と係数は変えていません。',
              ].join('\n\n'),
              style: const TextStyle(fontSize: 16, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

String nineAreaPeriodShareLabel(
  NineAreaPeriodSummary summary,
  AppStrings strings,
) {
  final en = strings.language == AppLanguage.en;
  if (summary is LongRangeDisplaySummary) {
    return switch (summary.displayMode) {
      LongRangeDisplayMode.month =>
        '${summary.dates.first.year}-${summary.dates.first.month.toString().padLeft(2, '0')} · ${en ? 'Monthly reading' : '月間占い'}',
      LongRangeDisplayMode.year =>
        '${summary.startYear} · ${en ? 'Yearly reading' : '年間占い'}',
      LongRangeDisplayMode.fiveYear =>
        '${summary.startYear}–${summary.endYear} · ${en ? 'Five-year reading' : '5年運'}',
      LongRangeDisplayMode.week => throw StateError(
        'Weekly display summaries use the seven-point route.',
      ),
    };
  }
  if (summary is PeriodSevenSummary) {
    return '${summary.startDateJst} – ${summary.endDateJst} · ${en ? 'Period reading' : '期間の占い'}';
  }
  return '${NineAreaPeriodSummary.dateLabel(summary.dates.first)} – ${NineAreaPeriodSummary.dateLabel(summary.dates.last)} · ${en ? 'Period reading' : '期間の占い'}';
}

Future<void> showNineAreaReadingShareComposer(
  BuildContext context, {
  required String periodLabel,
  required List<FortuneShareArea> areas,
  required String body,
  String areaHighlightsText = '',
}) {
  final primary = areas.length == 1
      ? areas.single
      : areas.singleWhere((area) => area.key == NineAreaKey.overall);
  return showFortuneShareComposer(
    context,
    periodLabel: periodLabel,
    score: primary.score,
    metricLabel: primary.title,
    areas: areas,
    body: body,
    areaHighlightsText: areaHighlightsText,
  );
}

/// The same header, badge, full-width prose and evidence layout for daily and
/// weekly readings. This widget only presents already calculated values.
class NineAreaReadingCard extends StatelessWidget {
  const NineAreaReadingCard({
    super.key,
    required this.badge,
    required this.title,
    required this.narrative,
    required this.evidence,
    required this.bodySize,
    required this.valueKey,
    required this.narrativeKey,
    required this.evidenceKey,
    required this.ledgerKey,
    required this.shareKey,
    this.beforeNarrative,
    this.onShare,
    this.showEvidence = true,
    this.phoneSimpleLayout = false,
    this.titleIcon,
  });
  final Widget badge;
  final Widget? beforeNarrative;
  final String title, narrative, evidence;
  final double bodySize;
  final Key valueKey, narrativeKey, evidenceKey, ledgerKey, shareKey;
  final VoidCallback? onShare;
  final bool showEvidence;
  final bool phoneSimpleLayout;
  final IconData? titleIcon;

  @override
  Widget build(BuildContext context) {
    final en = AppLanguageScope.stringsOf(context).language == AppLanguage.en;
    final style = TextStyle(fontSize: bodySize, height: 1.45);
    if (phoneSimpleLayout) {
      return GlassPanel(
        padding: const EdgeInsets.all(18),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scaler = MediaQuery.textScalerOf(context);
            final horizontal =
                constraints.maxWidth >=
                scaler.scale(dailyOverallFortuneBadgeSize + 150) + 14;
            final value = KeyedSubtree(key: valueKey, child: badge);
            final reading = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (titleIcon != null) ...[
                      Icon(titleIcon, size: 20, color: const Color(0xFFF6D77A)),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: bodySize + 1,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (beforeNarrative != null) ...[
                  beforeNarrative!,
                  const SizedBox(height: 12),
                ],
                Text(narrative, key: narrativeKey, style: style),
              ],
            );
            return horizontal
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      value,
                      const SizedBox(width: 14),
                      Expanded(child: reading),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [value, const SizedBox(height: 14), reading],
                  );
          },
        ),
      );
    }
    return GlassPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              KeyedSubtree(key: valueKey, child: badge),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: bodySize + 4,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (beforeNarrative != null) ...[
            beforeNarrative!,
            const SizedBox(height: 12),
          ],
          Text(narrative, key: narrativeKey, style: style),
          if (onShare != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: shareKey,
              onPressed: onShare,
              icon: const Icon(Icons.ios_share_outlined, size: 20),
              label: Text(en ? 'Share overall only' : '総合運のみ共有'),
            ),
          ],
          if (showEvidence) ...[
            const SizedBox(height: 12),
            Material(
              color: Colors.transparent,
              child: ExpansionTile(
                key: evidenceKey,
                tilePadding: EdgeInsets.zero,
                title: Text(
                  en ? 'Why and evidence' : '理由・根拠を見る',
                  style: style.copyWith(fontWeight: FontWeight.w700),
                ),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(evidence, key: ledgerKey, style: style),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PeriodSevenOverviewCard extends StatelessWidget {
  const _PeriodSevenOverviewCard({
    super.key,
    required this.area,
    required this.summary,
    required this.explanation,
    required this.strings,
    ReadingDepth? depth,
    required this.bodySize,
    this.onShare,
  });
  final NineAreaPeriodEntry area;
  final PeriodSevenSummary summary;
  final ForecastExplanationResult explanation;
  final AppStrings strings;
  final double bodySize;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    final english = strings.language == AppLanguage.en;
    final style = TextStyle(fontSize: bodySize, height: 1.45);
    final felt = area.key == NineAreaKey.felt;
    final mixed = felt && summary.feltModes.length > 1;
    final scaler = MediaQuery.textScalerOf(context);
    final badgeSize = scaler.scale(dailyFortuneBadgeSize);
    final badge = felt
        ? mixed
              ? Tooltip(
                  message: english
                      ? 'Tied most frequent: ${summary.feltModes.map(strings.feltLabelText).join(' / ')}. No numeric conversion.'
                      : '最多同数：${summary.feltModes.join('・')}。数値には変換しません。',
                  child: Container(
                    width: badgeSize,
                    height: badgeSize,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xEE121528),
                      border: Border.all(color: Colors.white70, width: 2),
                    ),
                    child: Text(
                      english ? 'Mixed\nFelt' : '混在\n体感',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                )
              : FeltFortuneBadge(label: summary.feltLabel, fixedSize: badgeSize)
        : area.score != null
        ? FortuneNumber(
            score: area.score!,
            fixedSize: area.key == NineAreaKey.overall
                ? scaler.scale(dailyOverallFortuneBadgeSize)
                : badgeSize,
            shortLabel: area.key == NineAreaKey.actionDecision
                ? (english ? 'Activity' : '活動性')
                : null,
            label: area.key == NineAreaKey.actionDecision
                ? (english
                      ? 'Experimental activity level; not success or decision correctness.'
                      : '活動性の試作値。成功や判断の正しさではありません')
                : null,
          )
        : SizedBox(
            width: badgeSize,
            child: Text(english ? 'Not predicted' : '未予測', style: style),
          );
    return NineAreaReadingCard(
      badge: badge,
      title: strings.nineAreaTitle(area.key.name),
      narrative: explanation.narrativeText,
      beforeNarrative: area.key == NineAreaKey.overall
          ? OverallAreaHighlightsBlock(
              highlights: OverallAreaHighlights.fromSummary(summary),
              strings: strings,
              style: style,
            )
          : null,
      evidence: explanation.numericLedgerText,
      showEvidence: explanation.depth == ReadingDepth.detailed,
      phoneSimpleLayout:
          explanation.depth == ReadingDepth.simple &&
          MediaQuery.sizeOf(context).shortestSide < 600,
      titleIcon: area.icon,
      bodySize: bodySize,
      valueKey: ValueKey('period-overview-value-${area.key.name}'),
      narrativeKey: ValueKey('period-overview-narrative-${area.key.name}'),
      evidenceKey: ValueKey('period-overview-evidence-${area.key.name}'),
      ledgerKey: ValueKey('period-overview-ledger-${area.key.name}'),
      shareKey: ValueKey('period-overview-share-${area.key.name}'),
      onShare: onShare,
    );
  }
}
