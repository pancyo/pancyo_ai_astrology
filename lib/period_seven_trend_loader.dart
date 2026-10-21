part of 'main.dart';

/// Loads the original comparison span using unchanged canonical period jobs.
/// The displayed period is reused; other periods run sequentially. Only fully
/// validated summaries remain in memory, never files or retained JSON wrappers.
class PeriodSevenTrend extends StatefulWidget {
  const PeriodSevenTrend({
    super.key,
    required this.summary,
    required this.profile,
    required this.details,
    this.startWeeklyJob,
    this.startMonthlyJob,
    this.startDisplayJob,
  });

  final PeriodSevenSummary summary;
  final AstroProfile profile;
  final UserProfileDetails details;
  final WeeklyDailyConsultExportStarter? startWeeklyJob;
  final MonthlyDailyConsultExportStarter? startMonthlyJob;
  final PeriodSevenDisplayStarter? startDisplayJob;

  @override
  State<PeriodSevenTrend> createState() => _PeriodSevenTrendState();
}

class _PeriodSevenTrendState extends State<PeriodSevenTrend>
    with WidgetsBindingObserver {
  late Object _scope;
  late Object _currentSummaryInputs;
  VoidCallback? _cancelOperation;
  int _generation = 0;
  int _activeStep = 0;
  int _completed = 0;
  int _total = 0;
  int _completedPeriods = 0;
  int? _monthPart;
  bool _working = false;
  bool _failed = false;
  bool _cancelled = false;
  bool _scopeResetQueued = false;
  List<PeriodSevenSummary> _summaries = const [];

  Object get _inputs => (
    PeriodReadingContextRequest.profileIdentity(widget.profile),
    jsonEncode(widget.details.toJson()),
    HouseSystemSettings.current.value,
    AstrologyDataSources.current.sourceName,
    AstrologyDataSources.current.usesHighPrecisionAstroData,
  );

  Object get _inputScope => (
    widget.summary,
    _inputs,
    widget.startWeeklyJob,
    widget.startMonthlyJob,
    widget.startDisplayJob,
  );

  bool get _canReuseCurrent =>
      _currentSummaryInputs == _inputs &&
      widget.summary.requestedHouseSystem ==
          HouseSystemSettings.current.value &&
      widget.summary.sourceName == AstrologyDataSources.current.sourceName &&
      widget.summary.usesHighPrecisionAstroData ==
          AstrologyDataSources.current.usesHighPrecisionAstroData;

  DateTime get _first {
    final parsed = DateTime.parse(widget.summary.startDateJst);
    return DateTime.utc(parsed.year, parsed.month, parsed.day);
  }

  List<DateTime> get _targets => List.unmodifiable(
    widget.summary.mode == LongRangeMode.week
        ? [
            for (var week = 0; week < 4; week++)
              _first.add(Duration(days: week * 7)),
          ]
        : [
            for (var month = 1; month <= 12; month++)
              DateTime.utc(_first.year, month),
          ],
  );

  int _pointCount(DateTime start) => widget.summary.mode == LongRangeMode.week
      ? 49
      : DateTime.utc(start.year, start.month + 1, 0).day * 7;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HouseSystemSettings.current.addListener(_environmentChanged);
    _currentSummaryInputs = _inputs;
    _scope = _inputScope;
    _restoreCompleted();
  }

  @override
  void didUpdateWidget(covariant PeriodSevenTrend oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new summary is the parent's acknowledgement that its current-period
    // result was calculated for these inputs. Changing inputs alone must never
    // relabel the old summary as a new person's or house system's result.
    if (oldWidget.summary != widget.summary) _currentSummaryInputs = _inputs;
    if (_scope != _inputScope) _reset();
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
    ++_activeStep;
    final cancel = _cancelOperation;
    _cancelOperation = null;
    _working = false;
    cancel?.call();
  }

  void _reset() {
    _stop();
    _scope = _inputScope;
    _completed = 0;
    _total = 0;
    _completedPeriods = 0;
    _failed = false;
    _cancelled = false;
    _summaries = const [];
    _monthPart = null;
    _restoreCompleted();
  }

  bool _current(int token, Object scope) =>
      mounted &&
      token == _generation &&
      scope == _scope &&
      scope == _inputScope &&
      _canReuseCurrent;

  Object _keyFor(DateTime first) => periodSevenDisplayCacheKey(
    mode: widget.summary.mode,
    first: first,
    profile: widget.profile,
    details: widget.details,
    houseSystem: HouseSystemSettings.current.value,
    sourceName: AstrologyDataSources.current.sourceName,
    highPrecision: AstrologyDataSources.current.usesHighPrecisionAstroData,
    startWeeklyJob: widget.startWeeklyJob,
    startMonthlyJob: widget.startMonthlyJob,
    startDisplayJob: widget.startDisplayJob,
  );

  Map<String, PeriodSevenSummary> _completedForTargets() {
    if (!_canReuseCurrent) return {};
    final complete = <String, PeriodSevenSummary>{};
    for (final target in _targets) {
      final value = PeriodSevenDisplaySessionCache._read(_keyFor(target));
      if (value != null) complete[value.startDateJst] = value;
    }
    // The parent's validated summary is reused directly; it is not relabelled
    // or inserted as another profile's cache entry.
    complete[widget.summary.startDateJst] = widget.summary;
    return complete;
  }

  void _restoreCompleted() {
    if (!_canReuseCurrent) return;
    final targets = _targets;
    final complete = _completedForTargets();
    _completedPeriods = complete.length;
    if (complete.length == targets.length &&
        targets.every(
          (target) => complete.containsKey(_monthlyDateLabel(target)),
        )) {
      _summaries = List.unmodifiable([
        for (final target in targets) complete[_monthlyDateLabel(target)]!,
      ]);
    }
  }

  Future<PeriodSevenSummary?> _calculate(
    DateTime first, {
    required int token,
    required Object scope,
    required int completedBefore,
  }) async {
    if (!_current(token, scope)) return null;
    final source = AstrologyDataSources.current;
    final count = _pointCount(first);
    final step = ++_activeStep;
    final summary = await _loadPeriodSevenDisplay(
      mode: widget.summary.mode,
      first: first,
      profile: widget.profile,
      details: widget.details,
      houseSystem: HouseSystemSettings.current.value,
      sourceName: source.sourceName,
      highPrecision: source.usesHighPrecisionAstroData,
      startWeeklyJob: widget.startWeeklyJob,
      startMonthlyJob: widget.startMonthlyJob,
      startDisplayJob: widget.startDisplayJob,
      isCurrent: () => _current(token, scope) && step == _activeStep,
      onCancel: (cancel) {
        if (_current(token, scope) && step == _activeStep) {
          _cancelOperation = cancel;
        }
      },
      onProgress: (done, total, monthPart) {
        if (_current(token, scope) && step == _activeStep && total == count) {
          setState(() {
            _completed = completedBefore + done.clamp(0, count);
            _monthPart = monthPart;
          });
        }
      },
    );
    if (!_current(token, scope)) return null;
    ++_activeStep;
    _cancelOperation = null;
    return summary;
  }

  Future<void> _load() async {
    if (!mounted || _working || _scope != _inputScope || !_canReuseCurrent) {
      return;
    }
    final targets = _targets;
    final complete = _completedForTargets();
    final missing = targets
        .where((date) => !complete.containsKey(_monthlyDateLabel(date)))
        .toList();
    if (!targets.any(
      (date) => _monthlyDateLabel(date) == widget.summary.startDateJst,
    )) {
      setState(() => _failed = true);
      return;
    }
    final token = ++_generation;
    final scope = _scope;
    setState(() {
      _working = true;
      _failed = false;
      _cancelled = false;
      _completed = 0;
      _monthPart = null;
      _completedPeriods = complete.length;
      _total = missing.fold(0, (sum, date) => sum + _pointCount(date));
      _summaries = const [];
    });
    var completedBefore = 0;
    try {
      for (final date in missing) {
        final result = await _calculate(
          date,
          token: token,
          scope: scope,
          completedBefore: completedBefore,
        );
        if (!_current(token, scope) || result == null) return;
        complete[_monthlyDateLabel(date)] = result;
        completedBefore += _pointCount(date);
        setState(() {
          _completed = completedBefore;
          _completedPeriods = complete.length;
        });
      }
      if (!_current(token, scope)) return;
      if (complete.length != targets.length) {
        throw StateError('The complete comparison span is required.');
      }
      setState(() {
        _summaries = List.unmodifiable([
          for (final target in targets) complete[_monthlyDateLabel(target)]!,
        ]);
        _working = false;
        _cancelOperation = null;
      });
    } catch (error) {
      if (!_current(token, scope)) return;
      _cancelOperation?.call();
      _cancelOperation = null;
      ++_activeStep;
      setState(() {
        _working = false;
        _summaries = const [];
        _cancelled = _periodSevenDisplayWasCancelled(error);
        _failed = !_cancelled;
      });
    }
  }

  void _cancel() => setState(() {
    _stop();
    _cancelled = true;
    _failed = false;
    _summaries = const [];
  });

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HouseSystemSettings.current.removeListener(_environmentChanged);
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matchingScope = _scope == _inputScope;
    if (!matchingScope && !_scopeResetQueued) {
      _scopeResetQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scopeResetQueued = false;
        if (mounted && _scope != _inputScope) setState(_reset);
      });
      WidgetsBinding.instance.scheduleFrame();
    }
    final english =
        AppLanguageScope.stringsOf(context).language == AppLanguage.en;
    final canUse = matchingScope && _canReuseCurrent;
    final count = widget.summary.mode == LongRangeMode.week ? 4 : 12;
    return Column(
      key: const ValueKey('period-seven-trend-loader'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (canUse && _summaries.length == count)
          PeriodSevenGroupedTrendView(summaries: _summaries)
        else ...[
          Text(
            widget.summary.mode == LongRangeMode.week
                ? (english ? 'Four-week comparison' : '4週間の比較')
                : (english
                      ? '${_first.year}: twelve-month comparison'
                      : '${_first.year}年・12か月の比較'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (!canUse)
            Text(
              english
                  ? 'Waiting for the current period reading for these inputs.'
                  : '現在の条件による期間の占いが整うまで、グラフは表示しません。',
              key: const ValueKey('period-trend-status'),
              style: const TextStyle(fontSize: 16),
            )
          else if (_working) ...[
            LinearProgressIndicator(
              key: const ValueKey('period-trend-progress'),
              value: _total == 0 ? null : _completed / _total,
            ),
            const SizedBox(height: 8),
            Text(
              english
                  ? 'Reading the comparison… $_completedPeriods/$count periods. Additional time points: $_completed/$_total. The current period is reused.'
                  : '比較グラフを読んでいます… $_completedPeriods/$count期間。追加計算：$_completed/$_total時点。表示中の期間は計算済みの結果を再利用します。',
              key: const ValueKey('period-trend-status'),
              style: const TextStyle(fontSize: 16, height: 1.4),
            ),
            if (_monthPart != null)
              Text(
                english
                    ? 'Current month: ${_monthPart == 1 ? 'first half (days 1–15)' : 'second half (day 16 onward)'}. Verified parts are retained for retry.'
                    : '計算中の月：${_monthPart == 1 ? '前半（1〜15日）' : '後半（16日〜月末）'}。完了した範囲は再試行に引き継ぎます。',
                key: const ValueKey('period-trend-part-status'),
                style: const TextStyle(fontSize: 16, height: 1.4),
              ),
            TextButton(
              key: const ValueKey('period-trend-cancel'),
              onPressed: _cancel,
              child: Text(english ? 'Cancel' : '中止'),
            ),
          ] else ...[
            if (_failed || _cancelled)
              Text(
                english
                    ? (_cancelled
                          ? 'Comparison calculation cancelled.'
                          : 'The complete comparison could not be verified. No partial graph is shown.')
                    : (_cancelled
                          ? '比較グラフの計算を中止しました。'
                          : '比較範囲の全データを確認できませんでした。不完全なグラフは表示しません。'),
                key: const ValueKey('period-trend-status'),
                style: const TextStyle(fontSize: 16, height: 1.4),
              ),
            if (_failed || _cancelled)
              Text(
                english
                    ? 'Completed periods: $_completedPeriods/$count. Verified results with the same inputs are reused on retry.'
                    : '完了済み：$_completedPeriods/$count期間。同じ入力条件の確認済み結果を再試行で再利用します。',
                key: const ValueKey('period-trend-retained-status'),
                style: const TextStyle(fontSize: 16, height: 1.4),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                key: ValueKey(
                  _failed || _cancelled
                      ? 'period-trend-retry'
                      : 'period-trend-load',
                ),
                onPressed: _load,
                icon: const Icon(Icons.show_chart),
                label: Text(
                  _failed || _cancelled
                      ? (english ? 'Retry graph' : 'グラフを再試行')
                      : (english ? 'Read graph' : 'グラフを読む'),
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }
}
