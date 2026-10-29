part of 'main.dart';

/// A display interval, clipped from verified calendar events to the selected JST day.
class GraphVoidBand {
  const GraphVoidBand({
    required this.startFraction,
    required this.endFraction,
    required this.startUtc,
    required this.endUtc,
    required this.continuesFromPreviousDay,
    required this.continuesIntoNextDay,
  });
  final double startFraction, endFraction;
  final DateTime startUtc, endUtc;
  final bool continuesFromPreviousDay, continuesIntoNextDay;

  static List<GraphVoidBand> forDay(
    String dateJst,
    Iterable<AstrologyCalendarEvent> events,
  ) {
    final plan = DailySevenTimepointPlan.forJstDate(dateJst);
    final result = <GraphVoidBand>[];
    final periods = events
        .where((e) => e.kind == AstrologyCalendarEventKind.voidMoon)
        .toList();
    if (periods.any((e) => e.startUtc == null || e.endUtc == null)) {
      throw StateError('Void interval is incomplete.');
    }
    periods.sort((a, b) => a.startUtc!.compareTo(b.startUtc!));
    DateTime? previousEnd;
    for (final event in periods) {
      final actualStart = event.startUtc, actualEnd = event.endUtc;
      if (actualStart == null ||
          actualEnd == null ||
          !actualEnd.isAfter(actualStart)) {
        throw StateError('Void interval is incomplete.');
      }
      final start = actualStart.isAfter(plan.dayStartUtc)
          ? actualStart
          : plan.dayStartUtc;
      final end = actualEnd.isBefore(plan.dayEndUtc)
          ? actualEnd
          : plan.dayEndUtc;
      if (!end.isAfter(start)) continue;
      if (event.overlapStartUtc != start ||
          event.overlapEndUtc != end ||
          (previousEnd != null && start.isBefore(previousEnd))) {
        throw StateError('Void intervals do not match the calendar day.');
      }
      previousEnd = end;
      final duration = const Duration(days: 1).inMicroseconds;
      result.add(
        GraphVoidBand(
          startFraction:
              start.difference(plan.dayStartUtc).inMicroseconds / duration,
          endFraction:
              end.difference(plan.dayStartUtc).inMicroseconds / duration,
          startUtc: start,
          endUtc: end,
          continuesFromPreviousDay: actualStart.isBefore(plan.dayStartUtc),
          continuesIntoNextDay: actualEnd.isAfter(plan.dayEndUtc),
        ),
      );
    }
    return List.unmodifiable(result);
  }

  String label(bool english) {
    String clock(DateTime utc, {bool end = false}) {
      if (end && endFraction == 1) return '24:00';
      final jst = utc.toUtc().add(const Duration(hours: 9));
      return '${jst.hour.toString().padLeft(2, '0')}:${jst.minute.toString().padLeft(2, '0')}';
    }

    return '${english ? 'Void' : 'ボイド'} ${clock(startUtc)}–${clock(endUtc, end: true)}'
        '${continuesFromPreviousDay ? (english ? ' (from previous day)' : '（前日から）') : ''}'
        '${continuesIntoNextDay ? (english ? ' (into next day)' : '（翌日へ）') : ''} · JST';
  }
}

enum DailyGraphVoidStatus { idle, loading, ready, failed }

class DailyGraphVoidData {
  const DailyGraphVoidData(this.status, [this.bands = const []]);
  final DailyGraphVoidStatus status;
  final List<GraphVoidBand> bands;
}

/// Reuses the calendar's strict, cancellable event worker and bounded read cache.
/// Scores and stored forecasts are never read or changed by this loader.
class DailyGraphVoidLayer extends StatefulWidget {
  const DailyGraphVoidLayer({
    super.key,
    required this.dateJst,
    required this.enabled,
    required this.sourceName,
    required this.requireHighPrecision,
    required this.builder,
    this.startJob,
  });
  final String dateJst, sourceName;
  final bool enabled, requireHighPrecision;
  final AstrologyCalendarStarter? startJob;
  final Widget Function(BuildContext, DailyGraphVoidData, VoidCallback) builder;
  @override
  State<DailyGraphVoidLayer> createState() => _DailyGraphVoidLayerState();
}

class _DailyGraphVoidLayerState extends State<DailyGraphVoidLayer> {
  static final Map<String, AstrologyCalendarDay> _cache = {};
  AstrologyCalendarOperation? _job;
  var _generation = 0;
  var _value = const DailyGraphVoidData(DailyGraphVoidStatus.idle);
  String get _identity =>
      '${_astrologyCalendarProviderIdentity()}|${widget.sourceName}|${widget.requireHighPrecision}|${widget.dateJst}';
  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant DailyGraphVoidLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dateJst != widget.dateJst ||
        oldWidget.enabled != widget.enabled ||
        oldWidget.sourceName != widget.sourceName ||
        oldWidget.requireHighPrecision != widget.requireHighPrecision ||
        oldWidget.startJob != widget.startJob) {
      _generation++;
      _job?.cancel();
      _job = null;
      _value = const DailyGraphVoidData(DailyGraphVoidStatus.idle);
      _schedule();
    }
  }

  void _schedule() {
    final generation = _generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && generation == _generation && widget.enabled) _load();
    });
  }

  Future<void> _load() async {
    if (!widget.enabled) return;
    final generation = ++_generation;
    _job?.cancel();
    _job = null;
    final identity = _identity;
    final date = widget.dateJst;
    setState(
      () => _value = const DailyGraphVoidData(DailyGraphVoidStatus.loading),
    );
    try {
      final sharedKey = '${_astrologyCalendarProviderIdentity()}|$date';
      final cached = widget.startJob == null
          ? (_cache[identity] ??
                _AstrologyCalendarViewState._sharedReadCache[sharedKey])
          : null;
      final job = cached == null
          ? (widget.startJob ?? _AstrologyCalendarIsolateJob.start)(
              date,
              (_, _) {},
            )
          : null;
      _job = job;
      final day = cached ?? await job!.result;
      if (!mounted || generation != _generation || identity != _identity)
        return;
      if (day.targetDateJst != date ||
          day.providerName != widget.sourceName ||
          day.usesHighPrecisionAstroData != widget.requireHighPrecision) {
        throw StateError('Calendar void result belongs to different inputs.');
      }
      final bands = GraphVoidBand.forDay(date, day.events);
      if (widget.startJob == null) {
        _cache[identity] = day;
        while (_cache.length > 45) {
          _cache.remove(_cache.keys.first);
        }
      }
      _job = null;
      setState(
        () => _value = DailyGraphVoidData(DailyGraphVoidStatus.ready, bands),
      );
    } catch (_) {
      if (!mounted || generation != _generation) return;
      _job = null;
      setState(
        () => _value = const DailyGraphVoidData(DailyGraphVoidStatus.failed),
      );
    }
  }

  @override
  void dispose() {
    _generation++;
    _job?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _value, () => _load());
}

class DailyGraphVoidLegend extends StatelessWidget {
  const DailyGraphVoidLegend({super.key, required this.data, this.onRetry});
  final DailyGraphVoidData data;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) {
    final en = AppLanguageScope.stringsOf(context).language == AppLanguage.en;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: data.status == DailyGraphVoidStatus.failed
          ? Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  en ? 'Void intervals unavailable' : 'ボイド期間は未取得',
                  key: const ValueKey('daily-void-unavailable'),
                ),
                if (onRetry != null)
                  TextButton(
                    onPressed: onRetry,
                    child: Text(en ? 'Retry' : '再取得'),
                  ),
              ],
            )
          : data.status == DailyGraphVoidStatus.ready
          ? data.bands.isEmpty
                ? Text(
                    en
                        ? 'No void interval in this day (JST).'
                        : 'この日のボイド期間なし（JST）',
                    key: const ValueKey('daily-void-none'),
                  )
                : Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    children: [
                      for (final band in data.bands)
                        Text(
                          '▰ ${band.label(en)}',
                          style: const TextStyle(
                            color: Color(0xFFCFB6FF),
                            fontSize: 12,
                          ),
                        ),
                    ],
                  )
          : Text(
              en ? 'Loading void intervals…' : 'ボイド期間を読み込み中…',
              style: const TextStyle(color: Color(0xFFB8C6E0), fontSize: 12),
            ),
    );
  }
}

void paintGraphVoidBands(Canvas canvas, Rect chart, List<GraphVoidBand> bands) {
  for (final band in bands) {
    final rect = Rect.fromLTRB(
      chart.left + chart.width * band.startFraction,
      chart.top,
      chart.left + chart.width * band.endFraction,
      chart.bottom,
    );
    canvas.drawRect(
      rect,
      Paint()..color = const Color(0xFFB58CFF).withValues(alpha: 0.20),
    );
    final edge = Paint()
      ..color = const Color(0xFFCFB6FF).withValues(alpha: 0.5)
      ..strokeWidth = 1;
    canvas.drawLine(rect.topLeft, rect.bottomLeft, edge);
    canvas.drawLine(rect.topRight, rect.bottomRight, edge);
  }
}
