part of 'main.dart';

/// Reuses the established daily-v4/monthly validation contract without saving
/// or modifying any prediction. The request/result token remains in memory.
void validatePeriodSevenReadingData({
  required Map<String, Object?> data,
  required DailyConsultExportRequest request,
  required String resultRequestIdentity,
}) {
  if (resultRequestIdentity != request.identity) {
    throw StateError('The reading belongs to different inputs.');
  }
  final civil = request.date.toUtc().add(DailySevenTimepointPlan.jstOffset);
  final monthlyRequest = MonthlyDailyConsultExportRequest(
    startDate: DateTime.utc(civil.year, civil.month, 1, 3),
    profile: request.profile,
    details: request.details,
    requestedHouseSystem: request.requestedHouseSystem,
    sourceName: request.sourceName,
    requireHighPrecision: request.requireHighPrecision,
    generatedAt: request.generatedAt,
  );
  _monthlyValidateDailyV4(data, request: monthlyRequest, plan: request.plan);
  final forecasts = _monthlyMap(data['intraday_forecasts'], '日内予測');
  final points = _monthlyList(forecasts['points'], '7時点');
  for (var index = 0; index < points.length; index++) {
    final point = _monthlyMap(points[index], '時点');
    final snapshot = _monthlyMap(point['nine_area_forecast'], '9項目');
    final expected = request.plan.points[index];
    final expectedDate = _monthlyDateLabel(
      expected.instantUtc.add(DailySevenTimepointPlan.jstOffset),
    );
    if (snapshot['target_date_jst'] != expectedDate ||
        snapshot['calculation_reference_jst'] !=
            NineAreaForecastSnapshot._issuedAtJst(expected.instantUtc) ||
        snapshot['uses_high_precision_astro_data'] !=
            request.requireHighPrecision) {
      throw StateError(
        'The reading time or calculation source does not match.',
      );
    }
    for (final rawArea in _monthlyList(snapshot['areas'], '9項目')) {
      final area = _monthlyMap(rawArea, '項目');
      for (final field in ['name', 'summary', 'explanation']) {
        final text = area[field];
        if (text is! String || text.trim().isEmpty) {
          throw StateError('The reading explanation is incomplete.');
        }
      }
      if (area['key'] != 'felt' && area['score'] is! int) {
        throw StateError('The reading score is not a canonical integer.');
      }
    }
  }
  if (jsonEncode(_monthlyMap(points[3], '正午')['nine_area_forecast']) !=
      jsonEncode(data['nine_area_daily'])) {
    throw StateError('The noon reading does not match the daily reference.');
  }
}

/// Reads one canonical daily-v4 result at a time. At most seven completed days
/// are cached in memory; this widget never writes a file or launches sharing.
class PeriodSevenReadingView extends StatefulWidget {
  const PeriodSevenReadingView({
    super.key,
    required this.mode,
    required this.startDateJst,
    required this.profile,
    required this.details,
    this.depth = ReadingDepth.simple,
    this.startJob,
    this.active = true,
  }) : assert(mode != LongRangeMode.year);

  final LongRangeMode mode;

  /// Civil JST fields, independent of the device's timezone.
  final DateTime startDateJst;
  final AstroProfile profile;
  final UserProfileDetails details;
  final ReadingDepth depth;
  final DailyConsultExportStarter? startJob;
  final bool active;

  @override
  State<PeriodSevenReadingView> createState() => _PeriodSevenReadingViewState();
}

class _PeriodSevenReadingViewState extends State<PeriodSevenReadingView>
    with WidgetsBindingObserver {
  final _cache = <String, Map<String, Object?>>{};
  DailyConsultExportOperation? _job;
  late List<DateTime> _days;
  late String _selectedDay;
  late Object _scope;
  int _selectedPoint = 3;
  int _generation = 0;
  int? _queuedGeneration;
  int _completed = 0;
  bool _working = false;
  bool _cancelled = false;
  bool _failed = false;
  bool _scopeResetQueued = false;

  Object get _inputScope => (
    widget.mode,
    _firstDay(widget),
    PeriodReadingContextRequest.profileIdentity(widget.profile),
    jsonEncode(widget.details.toJson()),
    widget.startJob,
    HouseSystemSettings.current.value,
    AstrologyDataSources.current.sourceName,
    AstrologyDataSources.current.usesHighPrecisionAstroData,
  );

  static DateTime _firstDay(PeriodSevenReadingView input) => DateTime.utc(
    input.startDateJst.year,
    input.startDateJst.month,
    input.mode == LongRangeMode.month ? 1 : input.startDateJst.day,
  );

  List<DateTime> _periodDays() {
    final first = _firstDay(widget);
    final count = widget.mode == LongRangeMode.month
        ? DateTime.utc(first.year, first.month + 1, 0).day
        : 7;
    return List.unmodifiable([
      for (var index = 0; index < count; index++)
        first.add(Duration(days: index)),
    ]);
  }

  String _defaultDay() {
    final today = DateTime.now().toUtc().add(DailySevenTimepointPlan.jstOffset);
    final todayLabel = _monthlyDateLabel(today);
    return _days.any((day) => _monthlyDateLabel(day) == todayLabel)
        ? todayLabel
        : _monthlyDateLabel(_days.first);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HouseSystemSettings.current.addListener(_environmentChanged);
    _scope = _inputScope;
    _days = _periodDays();
    _selectedDay = _defaultDay();
    _queueLoad();
  }

  @override
  void didUpdateWidget(covariant PeriodSevenReadingView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final periodChanged =
        oldWidget.mode != widget.mode ||
        _firstDay(oldWidget) != _firstDay(widget);
    if (_scope != _inputScope || oldWidget.active != widget.active) {
      _reset(periodChanged: periodChanged);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _environmentChanged();
  }

  void _environmentChanged() {
    if (!mounted || _scope == _inputScope) return;
    setState(() => _reset());
  }

  void _stopJob() {
    ++_generation;
    _queuedGeneration = null;
    _job?.cancel();
    _job = null;
    _working = false;
  }

  void _reset({bool periodChanged = false}) {
    _stopJob();
    _cache.clear();
    _scope = _inputScope;
    _days = _periodDays();
    if (periodChanged ||
        !_days.any((day) => _monthlyDateLabel(day) == _selectedDay)) {
      _selectedDay = _defaultDay();
      _selectedPoint = 3;
    }
    _completed = 0;
    _cancelled = false;
    _failed = false;
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

  bool _current(int token, Object scope, DailyConsultExportRequest request) =>
      mounted &&
      widget.active &&
      token == _generation &&
      scope == _scope &&
      scope == _inputScope &&
      request.plan.targetDateJst == _selectedDay;

  Future<void> _load() async {
    if (!mounted || !widget.active || _working || _scope != _inputScope) return;
    final cached = _cache.remove(_selectedDay);
    if (cached != null) {
      setState(() {
        _cache[_selectedDay] = cached;
        _cancelled = false;
        _failed = false;
        _completed = 7;
      });
      return;
    }
    final token = ++_generation;
    final scope = _scope;
    final plan = DailySevenTimepointPlan.forJstDate(_selectedDay);
    final source = AstrologyDataSources.current;
    final request = DailyConsultExportRequest(
      date: plan.primaryNoon.instantUtc,
      profile: widget.profile,
      details: widget.details,
      requestedHouseSystem: HouseSystemSettings.current.value,
      sourceName: source.sourceName,
      requireHighPrecision: source.usesHighPrecisionAstroData,
      generatedAt: DateTime.now(),
    );
    setState(() {
      _working = true;
      _completed = 0;
      _cancelled = false;
      _failed = false;
    });
    try {
      final operation = (widget.startJob ?? DailyConsultExportJob.start)(
        request,
        (done, total) {
          if (_current(token, scope, request) && total == 7) {
            setState(() => _completed = done.clamp(0, 7));
          }
        },
      );
      _job = operation;
      final result = await operation.result;
      if (!_current(token, scope, request)) return;
      _job = null;
      final data = result.data;
      validatePeriodSevenReadingData(
        data: data,
        request: request,
        resultRequestIdentity: result.requestIdentity,
      );
      if (!_current(token, scope, request)) return;
      setState(() {
        _cache.remove(_selectedDay);
        _cache[_selectedDay] = data;
        while (_cache.length > 7) {
          _cache.remove(_cache.keys.first);
        }
        _working = false;
        _completed = 7;
      });
    } catch (error) {
      if (!_current(token, scope, request)) return;
      _job = null;
      setState(() {
        _working = false;
        _cancelled = error is DailyConsultExportCancelled;
        _failed = !_cancelled;
      });
    }
  }

  void _selectDay(String? selected) {
    if (selected == null ||
        selected == _selectedDay ||
        !_days.any((day) => _monthlyDateLabel(day) == selected)) {
      return;
    }
    setState(() {
      _stopJob();
      _selectedDay = selected;
      _completed = 0;
      _cancelled = false;
      _failed = false;
      _queueLoad();
    });
  }

  void _cancel() => setState(() {
    _stopJob();
    _cancelled = true;
    _failed = false;
  });

  void _retry() => setState(() {
    _stopJob();
    _cancelled = false;
    _failed = false;
    _queueLoad();
  });

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HouseSystemSettings.current.removeListener(_environmentChanged);
    _stopJob();
    _cache.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return const SizedBox.shrink();
    final currentScope = _scope == _inputScope;
    if (!currentScope && !_scopeResetQueued) {
      _scopeResetQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scopeResetQueued = false;
        if (mounted && _scope != _inputScope) setState(() => _reset());
      });
      WidgetsBinding.instance.scheduleFrame();
    }
    final strings = AppLanguageScope.stringsOf(context);
    final english = strings.language == AppLanguage.en;
    final index = _days.indexWhere(
      (day) => _monthlyDateLabel(day) == _selectedDay,
    );
    final plan = DailySevenTimepointPlan.forJstDate(_selectedDay);
    final point = plan.points[_selectedPoint];
    final data = currentScope ? _cache[_selectedDay] : null;
    final forecasts = data == null
        ? null
        : _monthlyMap(data['intraday_forecasts'], '日内予測');
    final snapshot = forecasts == null
        ? null
        : _monthlyMap(
            _monthlyMap(
              (forecasts['points'] as List)[_selectedPoint],
              '時点',
            )['nine_area_forecast'],
            '9項目',
          );
    final loading = _working || _queuedGeneration != null || !currentScope;
    return Column(
      key: const ValueKey('period-seven-reading-view'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassPanel(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    key: const ValueKey('period-reading-previous-day'),
                    tooltip: english ? 'Previous day' : '前の日',
                    onPressed: index <= 0
                        ? null
                        : () => _selectDay(_monthlyDateLabel(_days[index - 1])),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: DropdownButton<String>(
                      key: const ValueKey('period-reading-date-dropdown'),
                      value: _selectedDay,
                      isExpanded: true,
                      items: [
                        for (final day in _days)
                          DropdownMenuItem(
                            value: _monthlyDateLabel(day),
                            child: Text(_monthlyDateLabel(day)),
                          ),
                      ],
                      onChanged: _selectDay,
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('period-reading-next-day'),
                    tooltip: english ? 'Next day' : '翌日',
                    onPressed: index >= _days.length - 1
                        ? null
                        : () => _selectDay(_monthlyDateLabel(_days[index + 1])),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < plan.points.length; i++)
                    ChoiceChip(
                      key: ValueKey(
                        'period-reading-time-${plan.points[i].hourFromDayStart}',
                      ),
                      label: Text(plan.points[i].displayTime),
                      selected: _selectedPoint == i,
                      onSelected: (_) => setState(() => _selectedPoint = i),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              if (snapshot == null)
                Text(
                  '$_selectedDay ${point.displayTime} JST (UTC+09:00)',
                  key: const ValueKey('period-reading-selected-time'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              if (snapshot == null && point.isDayEndBoundary)
                Text(
                  english
                      ? '24:00 is ${_monthlyDateLabel(plan.dayEndUtc.add(DailySevenTimepointPlan.jstOffset))} 00:00.'
                      : '24時は${_monthlyDateLabel(plan.dayEndUtc.add(DailySevenTimepointPlan.jstOffset))} 00時です。',
                ),
              if (loading) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  key: const ValueKey('period-reading-progress'),
                  value: _working ? _completed / 7 : null,
                ),
                const SizedBox(height: 8),
                Text(
                  english
                      ? 'Calculating seven time points… $_completed/7'
                      : '7時点の占いを計算中… $_completed/7',
                ),
                TextButton(
                  key: const ValueKey('period-reading-cancel'),
                  onPressed: _cancel,
                  child: Text(english ? 'Cancel' : '中止'),
                ),
              ] else if (_cancelled || _failed) ...[
                const SizedBox(height: 12),
                Text(
                  english
                      ? (_cancelled
                            ? 'Calculation cancelled. You can try again.'
                            : 'Could not complete this day’s seven readings. Please try again.')
                      : (_cancelled
                            ? '計算を中止しました。もう一度読み込めます。'
                            : 'この日の7時点を読み込めませんでした。再試行できます。'),
                  key: const ValueKey('period-reading-status'),
                ),
                FilledButton.icon(
                  key: const ValueKey('period-reading-retry'),
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh),
                  label: Text(english ? 'Retry' : '再試行'),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (snapshot != null)
          PeriodSevenReadingCards(
            snapshot: snapshot,
            targetDate: point.instantUtc,
            displayTime: point.displayTime,
            details: widget.details,
            depth: widget.depth,
          )
        else
          GlassPanel(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [
                for (final key in NineAreaKey.values)
                  Text(
                    strings.nineAreaTitle(key.name),
                    key: ValueKey('period-reading-placeholder-${key.name}'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
