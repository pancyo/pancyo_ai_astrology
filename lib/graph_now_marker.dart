part of 'main.dart';

enum GraphNowUnit { time, day, week, month, year }

/// Display coordinates only. Neither the clock nor this axis calculates scores.
class GraphNowAxis {
  GraphNowAxis._(this.unit, this.startsUtc, this.endsUtc);
  final GraphNowUnit unit;
  final List<DateTime> startsUtc;
  final List<DateTime> endsUtc;
  String get identity =>
      '${unit.name}|${startsUtc.map((d) => d.microsecondsSinceEpoch).join(',')}|${endsUtc.map((d) => d.microsecondsSinceEpoch).join(',')}';

  static DateTime _midnight(DateTime civil) => DateTime.utc(
    civil.year,
    civil.month,
    civil.day,
  ).subtract(const Duration(hours: 9));

  factory GraphNowAxis.daily(DateTime civil) {
    final start = _midnight(civil);
    return GraphNowAxis._(
      GraphNowUnit.time,
      [start],
      [start.add(const Duration(days: 1))],
    );
  }

  factory GraphNowAxis.days(Iterable<DateTime> civilDates) {
    final starts = civilDates.map(_midnight).toList(growable: false);
    return GraphNowAxis._(
      GraphNowUnit.day,
      starts,
      starts.map((d) => d.add(const Duration(days: 1))).toList(growable: false),
    );
  }

  factory GraphNowAxis.weeks(Iterable<DateTime> civilStarts) {
    final starts = civilStarts.map(_midnight).toList(growable: false);
    return GraphNowAxis._(
      GraphNowUnit.week,
      starts,
      starts.map((d) => d.add(const Duration(days: 7))).toList(growable: false),
    );
  }

  factory GraphNowAxis.months(Iterable<DateTime> civilMonths) {
    final months = civilMonths.toList(growable: false);
    return GraphNowAxis._(
      GraphNowUnit.month,
      [for (final d in months) _midnight(DateTime.utc(d.year, d.month))],
      [for (final d in months) _midnight(DateTime.utc(d.year, d.month + 1))],
    );
  }

  factory GraphNowAxis.years(Iterable<int> years) {
    final values = years.toList(growable: false);
    return GraphNowAxis._(
      GraphNowUnit.year,
      [for (final y in values) _midnight(DateTime.utc(y))],
      [for (final y in values) _midnight(DateTime.utc(y + 1))],
    );
  }

  GraphNowMarker? markerAt(DateTime instant, {bool english = false}) {
    final utc = instant.toUtc();
    final index = startsUtc.indexWhere((start) {
      final i = startsUtc.indexOf(start);
      return !utc.isBefore(start) && utc.isBefore(endsUtc[i]);
    });
    if (index < 0) return null;
    final jst = utc.add(const Duration(hours: 9));
    final time =
        '${jst.hour.toString().padLeft(2, '0')}:${jst.minute.toString().padLeft(2, '0')}';
    final position = unit == GraphNowUnit.time
        ? utc.difference(startsUtc.single).inMicroseconds /
              const Duration(days: 1).inMicroseconds
        : index / math.max(1, startsUtc.length - 1);
    final label = switch (unit) {
      GraphNowUnit.time => '${english ? 'Now' : '今'} $time',
      GraphNowUnit.day => '${english ? 'Today' : '今日'} ${jst.month}/${jst.day}',
      GraphNowUnit.week => english ? 'This week' : '今週',
      GraphNowUnit.month => english ? 'This month' : '今月 ${jst.month}月',
      GraphNowUnit.year => '${english ? 'This year' : '今年'} ${jst.year}',
    };
    return GraphNowMarker(
      position: position,
      pointIndex: unit == GraphNowUnit.time ? (position * 6).round() : index,
      label: label,
      description:
          '$label · ${jst.year}-${jst.month.toString().padLeft(2, '0')}-${jst.day.toString().padLeft(2, '0')} $time JST',
      nearestSample: unit == GraphNowUnit.time,
    );
  }
}

class GraphNowMarker {
  const GraphNowMarker({
    required this.position,
    required this.pointIndex,
    required this.label,
    required this.description,
    this.nearestSample = false,
  });
  final double position;
  final int pointIndex;
  final String label, description;
  final bool nearestSample;
}

/// Updates only the displayed clock, including after returning to the app.
class CurrentGraphClock extends StatefulWidget {
  const CurrentGraphClock({
    super.key,
    required this.axis,
    required this.builder,
    this.nowUtc,
  });
  final GraphNowAxis? axis;
  final Widget Function(BuildContext, GraphNowMarker?) builder;
  final DateTime Function()? nowUtc;
  @override
  State<CurrentGraphClock> createState() => _CurrentGraphClockState();
}

class _CurrentGraphClockState extends State<CurrentGraphClock>
    with WidgetsBindingObserver {
  Timer? _timer;
  DateTime _now() => (widget.nowUtc?.call() ?? DateTime.now()).toUtc();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _arm();
  }

  void _arm() {
    _timer?.cancel();
    if (widget.axis == null) return;
    final now = _now();
    final nextMinute = DateTime.utc(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute + 1,
    );
    _timer = Timer(nextMinute.difference(now), () {
      if (!mounted) return;
      setState(() {});
      _arm();
    });
  }

  @override
  void didUpdateWidget(covariant CurrentGraphClock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.axis != widget.axis || oldWidget.nowUtc != widget.nowUtc)
      _arm();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() {});
      _arm();
    } else {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final marker = widget.axis?.markerAt(
      _now(),
      english: AppLanguageScope.stringsOf(context).language == AppLanguage.en,
    );
    return GraphNowInitialReveal(
      axis: widget.axis,
      nowUtc: widget.nowUtc,
      child: Semantics(
        label: marker?.description,
        child: widget.builder(context, marker),
      ),
    );
  }
}

/// Initially reveals "now" on a narrow chart, then respects manual scrolling.
class GraphNowInitialReveal extends StatefulWidget {
  const GraphNowInitialReveal({
    super.key,
    required this.axis,
    required this.child,
    this.nowUtc,
  });
  final GraphNowAxis? axis;
  final DateTime Function()? nowUtc;
  final Widget child;
  @override
  State<GraphNowInitialReveal> createState() => _GraphNowInitialRevealState();
}

class _GraphNowInitialRevealState extends State<GraphNowInitialReveal> {
  void _schedule() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final marker = widget.axis?.markerAt(
        widget.nowUtc?.call() ?? DateTime.now().toUtc(),
      );
      final position = Scrollable.maybeOf(
        context,
        axis: Axis.horizontal,
      )?.position;
      if (marker == null ||
          position == null ||
          !position.hasContentDimensions ||
          position.maxScrollExtent <= 0)
        return;
      final scaler = MediaQuery.textScalerOf(context);
      final left = math.max(34.0, scaler.scale(34)),
          right = math.max(12.0, scaler.scale(12));
      final fullWidth = position.maxScrollExtent + position.viewportDimension;
      final x = left + (fullWidth - left - right) * marker.position;
      position.jumpTo(
        (x - position.viewportDimension / 2)
            .clamp(0.0, position.maxScrollExtent)
            .toDouble(),
      );
    });
  }

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant GraphNowInitialReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.axis?.identity != widget.axis?.identity) _schedule();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Reserve room for the end labels after their positions are clamped inwards.
double graphAxisMinimumWidth(List<String> labels, TextScaler scaler) {
  var widest = 0.0;
  for (final label in labels) {
    final painter = TextPainter(
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      text: TextSpan(
        text: label,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
      ),
    )..layout();
    widest = math.max(widest, painter.width);
    painter.dispose();
  }
  final spacing = math.max(scaler.scale(72), widest * 1.5 + scaler.scale(8));
  return spacing * math.max(1, labels.length - 1) + scaler.scale(46);
}

double graphAxisLabelLeft(double center, double width, double canvasWidth) =>
    (center - width / 2)
        .clamp(0.0, math.max(0.0, canvasWidth - width))
        .toDouble();

void paintGraphNowMarker(
  Canvas canvas,
  Size size,
  Rect chart,
  GraphNowMarker? marker,
  TextScaler scaler,
) {
  if (marker == null) return;
  final x = chart.left + chart.width * marker.position;
  const gold = Color(0xFFF6D77A);
  final paint = Paint()
    ..color = gold
    ..strokeWidth = 1.8;
  for (var y = chart.top; y < chart.bottom; y += 8) {
    canvas.drawLine(
      Offset(x, y),
      Offset(x, math.min(y + 4, chart.bottom)),
      paint,
    );
  }
  final pointer = Path()
    ..moveTo(x - 4, chart.top - 5)
    ..lineTo(x + 4, chart.top - 5)
    ..lineTo(x, chart.top + 1)
    ..close();
  canvas.drawPath(pointer, Paint()..color = gold);
  final label = TextPainter(
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    text: TextSpan(
      text: marker.label,
      style: const TextStyle(
        color: gold,
        fontSize: 11,
        fontWeight: FontWeight.w900,
      ),
    ),
  )..layout();
  final left = graphAxisLabelLeft(x, label.width + 8, size.width);
  final rect = Rect.fromLTWH(left, 0, label.width + 8, label.height + 4);
  canvas.drawRRect(
    RRect.fromRectAndRadius(rect, const Radius.circular(4)),
    Paint()..color = const Color(0xFF10182D),
  );
  label.paint(canvas, Offset(left + 4, 2));
}
