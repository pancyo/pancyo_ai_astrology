part of 'main.dart';

/// One presentation model for the interactive grid and saved images.
/// All values come from the calendar's existing sky calculation, never a profile.
class AstrologyCalendarDayPresentation {
  AstrologyCalendarDayPresentation._(this.moonLines, this.voidLines, this.supplementalEvents);

  factory AstrologyCalendarDayPresentation.fromDay(
    AstrologyCalendarDay day, {required bool english}) {
    final moonEvents = day.events.where((event) =>
      event.kind == AstrologyCalendarEventKind.signIngress &&
      (event.ingressPlanet == AstroPlanet.moon || event.title.startsWith('月が'))).toList()
      ..sort((a, b) => a.sortTimeUtc.compareTo(b.sortTimeUtc));
    String sign(ZodiacSign value) => english ? _astrologyCalendarZodiacLabel(value) : value.label;
    final moonLines = <String>[];
    for (final event in moonEvents) {
      final before = event.fromSign;
      final after = event.toSign;
      moonLines.add(before == null || after == null || event.startUtc == null
          ? (english ? 'Moon: ingress details unavailable' : '月：移動前後の情報未確認')
          : '${english ? 'Moon' : '月'}：${sign(before)} → ${sign(after)} ${_astrologyCalendarCellTime(event.startUtc!)}');
    }
    if (moonLines.isEmpty) {
      moonLines.add(day.moonSignAtNoon == null
          ? (english ? 'Moon: not checked' : '月：未確認')
          : '${english ? 'Moon' : '月'}：${sign(day.moonSignAtNoon!)}');
    }
    final voidEvents = day.events.where((event) => event.kind == AstrologyCalendarEventKind.voidMoon).toList()
      ..sort((a,b) => a.sortTimeUtc.compareTo(b.sortTimeUtc));
    final voidLines = <String>[
      if (voidEvents.isEmpty) english ? 'None' : 'なし',
      for (final event in voidEvents) astrologyCalendarVoidLabel(event, day.targetDateJst, english: english),
    ];
    final supplemental = day.events.where((event) =>
      event.kind != AstrologyCalendarEventKind.voidMoon && !moonEvents.contains(event)).toList()
      ..sort((a,b) {
        final priority = _calendarEventPriority(a).compareTo(_calendarEventPriority(b));
        return priority != 0 ? priority : a.sortTimeUtc.compareTo(b.sortTimeUtc);
      });
    return AstrologyCalendarDayPresentation._(List.unmodifiable(moonLines), List.unmodifiable(voidLines), List.unmodifiable(supplemental));
  }
  final List<String> moonLines;
  final List<String> voidLines;
  final List<AstrologyCalendarEvent> supplementalEvents;
}

int _calendarEventPriority(AstrologyCalendarEvent event) => switch(event.kind) {
  AstrologyCalendarEventKind.majorLunarPhase => event.title == '新月' || event.title == '満月' ? 0 : 3,
  AstrologyCalendarEventKind.retrogradeStation => 1,
  AstrologyCalendarEventKind.signIngress => 2,
  AstrologyCalendarEventKind.specialConfiguration => 4,
  AstrologyCalendarEventKind.voidMoon => -1,
};

String astrologyCalendarVoidLabel(AstrologyCalendarEvent event, String date, {required bool english}) {
  final start = event.startUtc;
  final end = event.endUtc;
  if (start == null || end == null || !end.isAfter(start)) {
    return english ? 'Interval not confirmed' : '区間未確認';
  }
  final plan = DailySevenTimepointPlan.forJstDate(date);
  if (!start.isAfter(plan.dayStartUtc) && !end.isBefore(plan.dayEndUtc)) {
    return english ? 'All day' : '終日';
  }
  final startLabel = start.isBefore(plan.dayStartUtc)
      ? (english ? 'Previous day' : '前日') : _astrologyCalendarCellTime(start);
  final endLabel = end.isAfter(plan.dayEndUtc)
      ? (english ? 'Next day' : '翌日')
      : end == plan.dayEndUtc ? '24:00' : _astrologyCalendarCellTime(end);
  return '$startLabel${english ? '–' : '〜'}$endLabel';
}

String astrologyCalendarSupplementLabel(AstrologyCalendarEvent event, {required bool english}) {
  final title = _astrologyCalendarEventTitle(event, english);
  if (event.kind == AstrologyCalendarEventKind.retrogradeStation) {
    return '${title.replaceAll('（留）', '').replaceAll(' (station)', '')} ${event.startUtc == null ? '' : _astrologyCalendarCellTime(event.startUtc!)}'.trim();
  }
  if (event.kind == AstrologyCalendarEventKind.specialConfiguration) {
    return '$title (${english ? 'noon' : '正午'})';
  }
  return '$title${event.startUtc == null ? '' : ' ${_astrologyCalendarCellTime(event.startUtc!)}'}';
}

class AstrologyCalendarDayContent extends StatelessWidget {
  const AstrologyCalendarDayContent({super.key, required this.data, required this.english, this.supplementalLimit = 2, this.fontSize = 14});
  final AstrologyCalendarDay data;
  final bool english;
  final int supplementalLimit;
  /// Screen callers may enlarge text; existing exported images retain 14.
  final double fontSize;
  @override
  Widget build(BuildContext context) {
    final summary = AstrologyCalendarDayPresentation.fromDay(data, english: english);
    final shown = summary.supplementalEvents.take(supplementalLimit);
    Widget line(String value, Color color, {FontWeight weight = FontWeight.w600}) =>
      Text(value, softWrap: true, style: TextStyle(fontSize: math.max(14.0, fontSize), height: 1.35, color: color, fontWeight: weight));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      for (final value in summary.moonLines) line(value, const Color(0xFFCAE6FF)),
      const SizedBox(height: 5),
      line(english ? 'Void-of-course' : 'ボイド', const Color(0xFFFFD987), weight: FontWeight.w800),
      for (final value in summary.voidLines) line(value, const Color(0xFFFFD987)),
      if (shown.isNotEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Divider(height: 1, color: Color(0xFF515165))),
      for (final event in shown) line(astrologyCalendarSupplementLabel(event, english: english), const Color(0xFFE6E1EF)),
      if (summary.supplementalEvents.length > shown.length)
        line(english ? '+${summary.supplementalEvents.length-shown.length} in details' : 'ほか${summary.supplementalEvents.length-shown.length}件・詳細へ', const Color(0xFFC7C1D5)),
    ]);
  }
}

/// Screen-only rows for a bounded month grid. Export formatting above stays
/// unchanged. Required Moon/void rows never have a line-count or size cutoff.
class _AstrologyCalendarCompactLine {
  const _AstrologyCalendarCompactLine(this.text, this.color, {this.dayNumber});
  final String text;
  final Color color;
  final int? dayNumber;

  TextSpan span(TextStyle style) => TextSpan(
    style: style.copyWith(color: color),
    children: [
      if (dayNumber != null)
        TextSpan(
          text: '$dayNumber ',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
      TextSpan(text: text),
    ],
  );
}

TextStyle _astrologyCalendarCompactStyle(double fontSize, TextStyle? base) =>
    (base ?? const TextStyle()).copyWith(
      fontSize: math.max(14.0, fontSize),
      height: 1.15,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
      wordSpacing: 0,
    );

double _astrologyCalendarCompactLineHeight(
  _AstrologyCalendarCompactLine line,
  double width,
  TextStyle style,
  TextScaler scaler,
) {
  final painter = TextPainter(
    text: line.span(style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
  );
  try {
    painter.layout(maxWidth: math.max(1.0, width));
    return painter.height.ceilToDouble();
  } finally {
    painter.dispose();
  }
}

bool _astrologyCalendarCompactFitsOneLine(
  _AstrologyCalendarCompactLine line,
  double width,
  TextStyle style,
  TextScaler scaler,
) {
  final painter = TextPainter(
    text: line.span(style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
  );
  try {
    painter.layout(maxWidth: math.max(1.0, width));
    return painter.computeLineMetrics().length == 1;
  } finally {
    painter.dispose();
  }
}

List<_AstrologyCalendarCompactLine> _astrologyCalendarCompactRequiredLines({
  required AstrologyCalendarDay data,
  required bool english,
  required double width,
  required TextStyle style,
  required TextScaler textScaler,
  int? dayNumber,
}) {
  const moonColor = Color(0xFFCAE6FF);
  const voidColor = Color(0xFFFFD987);
  final lines = <_AstrologyCalendarCompactLine>[];
  final moonEvents = data.events.where((event) =>
    event.kind == AstrologyCalendarEventKind.signIngress &&
    (event.ingressPlanet == AstroPlanet.moon || event.title.startsWith('月が'))).toList()
    ..sort((a, b) => a.sortTimeUtc.compareTo(b.sortTimeUtc));
  String sign(ZodiacSign value) => english
      ? _astrologyCalendarShortSign(value.label, true)
      : value.label;
  final moonLabel = english ? 'Moon' : '月';
  for (final event in moonEvents) {
    final number = lines.isEmpty ? dayNumber : null;
    if (event.fromSign == null || event.toSign == null || event.startUtc == null) {
      lines.add(_AstrologyCalendarCompactLine(
        english ? 'Moon: not confirmed' : '月:移動前後未確認', moonColor, dayNumber: number));
      continue;
    }
    final signs = '$moonLabel:${sign(event.fromSign!)}→${sign(event.toSign!)}';
    final clock = _astrologyCalendarCellTime(event.startUtc!);
    final together = _AstrologyCalendarCompactLine('$signs $clock', moonColor, dayNumber: number);
    if (_astrologyCalendarCompactFitsOneLine(together, width, style, textScaler)) {
      lines.add(together);
    } else {
      final signsLine = _AstrologyCalendarCompactLine(signs, moonColor, dayNumber: number);
      if (_astrologyCalendarCompactFitsOneLine(signsLine, width, style, textScaler)) {
        lines.add(signsLine);
      } else {
        // Keep both Japanese sign names and English abbreviations intact.
        // Explicit arrow/heading boundaries also drive the height estimator.
        final before = sign(event.fromSign!);
        final after = sign(event.toSign!);
        final pair = _AstrologyCalendarCompactLine('$before→$after', moonColor);
        if (_astrologyCalendarCompactFitsOneLine(pair, width, style, textScaler)) {
          lines.add(_AstrologyCalendarCompactLine('$moonLabel:', moonColor, dayNumber: number));
          lines.add(pair);
        } else {
          final headedBefore = _AstrologyCalendarCompactLine('$moonLabel:$before', moonColor, dayNumber: number);
          final arrowAfter = _AstrologyCalendarCompactLine('→$after', moonColor);
          if (_astrologyCalendarCompactFitsOneLine(headedBefore, width, style, textScaler) &&
              _astrologyCalendarCompactFitsOneLine(arrowAfter, width, style, textScaler)) {
            lines.add(headedBefore);
            lines.add(arrowAfter);
          } else {
            lines.add(_AstrologyCalendarCompactLine('$moonLabel:', moonColor, dayNumber: number));
            final beforeArrow = _AstrologyCalendarCompactLine('$before→', moonColor);
            if (_astrologyCalendarCompactFitsOneLine(beforeArrow, width, style, textScaler)) {
              lines.add(beforeArrow);
            } else {
              lines.add(_AstrologyCalendarCompactLine(before, moonColor));
              lines.add(const _AstrologyCalendarCompactLine('→', moonColor));
            }
            lines.add(_AstrologyCalendarCompactLine(after, moonColor));
          }
        }
      }
      lines.add(_AstrologyCalendarCompactLine(clock, moonColor));
    }
  }
  if (moonEvents.isEmpty) {
    final value = data.moonSignAtNoon;
    final moonLine = _AstrologyCalendarCompactLine(
      '$moonLabel:${value == null ? (english ? 'not confirmed' : '未確認') : sign(value)}',
      moonColor, dayNumber: dayNumber);
    if (value != null &&
        !_astrologyCalendarCompactFitsOneLine(moonLine, width, style, textScaler)) {
      lines.add(_AstrologyCalendarCompactLine('$moonLabel:', moonColor, dayNumber: dayNumber));
      lines.add(_AstrologyCalendarCompactLine(sign(value), moonColor));
    } else {
      lines.add(moonLine);
    }
  }
  final voidEvents = data.events.where((event) => event.kind == AstrologyCalendarEventKind.voidMoon).toList()
    ..sort((a, b) => a.sortTimeUtc.compareTo(b.sortTimeUtc));
  final voidLabel = english ? 'Void' : 'ボイド';
  if (voidEvents.isEmpty) {
    lines.add(_AstrologyCalendarCompactLine('$voidLabel ${english ? 'none' : 'なし'}', voidColor));
  } else {
    for (final event in voidEvents) {
      var interval = astrologyCalendarVoidLabel(event, data.targetDateJst, english: english);
      if (english) {
        interval = interval.replaceAll('Previous day', 'prev day').replaceAll('Next day', 'next day');
      }
      lines.add(_AstrologyCalendarCompactLine('$voidLabel $interval', voidColor));
    }
  }
  return lines;
}

/// Height of every mandatory row, including a date on the first Moon row.
/// Pass the same inherited text style/scaler used by the screen for exact
/// layout planning; supplemental events are deliberately excluded.
double astrologyCalendarCompactRequiredHeight({
  required AstrologyCalendarDay data,
  required bool english,
  required double width,
  TextScaler textScaler = TextScaler.noScaling,
  int? dayNumber,
  double fontSize = 14,
  TextStyle? textStyle,
}) {
  final style = _astrologyCalendarCompactStyle(fontSize, textStyle);
  return _astrologyCalendarCompactRequiredLines(
    data: data, english: english, width: width, style: style,
    textScaler: textScaler, dayNumber: dayNumber,
  ).fold(0.0, (height, line) => height +
    _astrologyCalendarCompactLineHeight(line, width, style, textScaler));
}

String _astrologyCalendarCompactSupplementLabel(AstrologyCalendarEvent event, bool english) {
  final clock = event.startUtc == null ? '' : ' ${_astrologyCalendarCellTime(event.startUtc!)}';
  if (event.kind == AstrologyCalendarEventKind.signIngress &&
      event.ingressPlanet != null && event.toSign != null) {
    final planet = english ? _astrologyCalendarPlanetLabel(event.ingressPlanet!) : event.ingressPlanet!.label;
    final sign = english ? _astrologyCalendarShortSign(event.toSign!.label, true) : event.toSign!.label;
    return '$planet→$sign$clock';
  }
  if (event.kind == AstrologyCalendarEventKind.retrogradeStation) {
    final match = RegExp(r'^(.+?)が逆行(開始|終了)（留）$').firstMatch(event.title);
    if (match != null) {
      final planet = english
          ? _astrologyCalendarShortPlanet(match.group(1)!, true)
          : match.group(1)!;
      final direction = match.group(2) == '開始'
          ? (english ? 'retrograde' : '逆行') : (english ? 'direct' : '順行');
      return '$planet $direction$clock';
    }
  }
  return astrologyCalendarSupplementLabel(event, english: english);
}

class AstrologyCalendarCompactDayContent extends StatelessWidget {
  const AstrologyCalendarCompactDayContent({
    super.key,
    required this.data,
    required this.english,
    this.dayNumber,
    this.fontSize = 14,
    this.maxHeight,
    this.supplementalLimit = 1,
  });
  final AstrologyCalendarDay data;
  final bool english;
  final int? dayNumber;
  final double fontSize;
  final double? maxHeight;
  final int supplementalLimit;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    final width = constraints.maxWidth;
    final scaler = MediaQuery.textScalerOf(context);
    final style = _astrologyCalendarCompactStyle(fontSize, DefaultTextStyle.of(context).style);
    final rows = _astrologyCalendarCompactRequiredLines(
      data: data, english: english, width: width, style: style,
      textScaler: scaler, dayNumber: dayNumber,
    );
    var used = rows.fold(0.0, (height, line) => height +
      _astrologyCalendarCompactLineHeight(line, width, style, scaler));
    final budget = maxHeight ?? (constraints.hasBoundedHeight ? constraints.maxHeight : null);
    final summary = AstrologyCalendarDayPresentation.fromDay(data, english: english);
    final supplements = summary.supplementalEvents.where((event) =>
      event.kind == AstrologyCalendarEventKind.signIngress ||
      event.kind == AstrologyCalendarEventKind.majorLunarPhase ||
      event.kind == AstrologyCalendarEventKind.retrogradeStation);
    final shown = <AstrologyCalendarEvent>[];
    if (budget != null && supplementalLimit > 0) {
      for (final event in supplements.take(supplementalLimit)) {
        final line = _AstrologyCalendarCompactLine(
          _astrologyCalendarCompactSupplementLabel(event, english), const Color(0xFFE6E1EF));
        final height = _astrologyCalendarCompactLineHeight(line, width, style, scaler);
        if (used + height > budget) break;
        rows.add(line);
        shown.add(event);
        used += height;
      }
    }
    final fullLabel = [
      if (dayNumber != null) '$dayNumber',
      ...summary.moonLines,
      '${english ? 'Void-of-course' : 'ボイド'} ${summary.voidLines.join(' / ')}',
      for (final event in shown) astrologyCalendarSupplementLabel(event, english: english),
    ].join('\n');
    return Semantics(
      label: fullLabel,
      excludeSemantics: true,
      child: Tooltip(
        message: fullLabel,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < rows.length; index++)
              Text.rich(
                rows[index].span(style),
                key: ValueKey('calendar-compact-${data.targetDateJst}-$index'),
                textScaler: scaler,
                softWrap: true,
                textDirection: TextDirection.ltr,
              ),
          ],
        ),
      ),
    );
  });
}
