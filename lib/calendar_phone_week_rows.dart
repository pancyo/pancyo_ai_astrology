part of 'main.dart';

/// Civil calendar dates, in the existing Monday-through-Sunday order.
List<DateTime> astrologyCalendarPhoneWeekDates(DateTime civil) {
  final day = DateTime.utc(civil.year, civil.month, civil.day);
  final monday = day.subtract(Duration(days: day.weekday - 1));
  return [for (var i = 0; i < 7; i++) monday.add(Duration(days: i))];
}

class AstrologyCalendarPhoneDay {
  const AstrologyCalendarPhoneDay({
    required this.date,
    this.data,
    this.loading = false,
    this.failed = false,
    this.supported = true,
  });
  final DateTime date;
  final AstrologyCalendarDay? data;
  final bool loading, failed, supported;
}

class AstrologyCalendarPhoneWeekRows extends StatelessWidget {
  const AstrologyCalendarPhoneWeekRows({
    super.key,
    required this.days,
    required this.english,
    required this.fontSize,
    required this.selected,
    required this.onOpenDay,
  });
  final List<AstrologyCalendarPhoneDay> days;
  final bool english;
  final double fontSize;
  final DateTime selected;
  final ValueChanged<DateTime> onOpenDay;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: fontSize, height: 1.35);
    Widget cell(List<String> lines, Color color, {bool moon = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var line in lines)
                Builder(
                  builder: (context) {
                    if (moon) {
                      line = line.replaceFirst(RegExp(r'^(Moon|月)[：:]\s*'), '');
                      if (english) {
                        for (final sign in ZodiacSign.values) {
                          line = line.replaceAll(
                            _astrologyCalendarZodiacLabel(sign),
                            _astrologyCalendarShortSign(sign.label, true),
                          );
                        }
                      }
                    }
                    final tokens = line
                        .replaceAll('〜', ' 〜 ')
                        .replaceAll('–', ' – ')
                        .split(RegExp(r'\s+'))
                        .where((s) => s.isNotEmpty);
                    return Wrap(
                      spacing: 4,
                      runSpacing: 2,
                      children: [
                        for (final token in tokens)
                          Text(
                            token,
                            softWrap: false,
                            style: style.copyWith(color: color),
                          ),
                      ],
                    );
                  },
                ),
            ],
          ),
        );
    String status(AstrologyCalendarPhoneDay day) => !day.supported
        ? (english ? 'Out of range' : '対象外')
        : day.loading
        ? (english ? 'Loading…' : '取得中…')
        : day.failed
        ? (english ? 'Failed · tap to retry' : '取得失敗・再試行')
        : (english ? 'Not loaded' : '未取得');
    Widget row(List<Widget> cells) => IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        SizedBox(width: 90, child: cells[0]),
          Expanded(flex: 46, child: cells[1]),
          Expanded(flex: 54, child: cells[2]),
        ],
      ),
    );
    return Column(
      key: const ValueKey('astrology-calendar-phone-week-rows'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row([
          for (final heading in [
            english ? 'Date' : '日付',
            english ? 'Moon sign' : '月星座',
            english ? 'Void' : 'ボイド',
          ])
            Padding(
              padding: const EdgeInsets.all(7),
              child: Text(
                heading,
                style: style.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
        ]),
        for (final day in days)
          Semantics(
            label:
                '${day.date.month}/${day.date.day}\n${day.data == null ? status(day) : [...AstrologyCalendarDayPresentation.fromDay(day.data!, english: english).moonLines, ...AstrologyCalendarDayPresentation.fromDay(day.data!, english: english).voidLines].join('\n')}',
            child: Material(
              key: ValueKey(
                'astrology-calendar-day-${day.date.toIso8601String().substring(0, 10)}',
              ),
              color: day.date == selected
                  ? const Color(0xFF443D70)
                  : const Color(0xFF191A30),
              child: InkWell(
                onTap: day.supported ? () => onOpenDay(day.date) : null,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: const Color(0xFF48455F),
                      width: .6,
                    ),
                  ),
                  child: row([
                    cell(
                      [
                        '${day.date.month}/${day.date.day}',
                        english
                              ? const ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'][day.date.weekday - 1]
                            : _japaneseWeekdays[day.date.weekday - 1],
                      ],
                      day.date.weekday == 7
                          ? const Color(0xFFFFAAA8)
                          : day.date.weekday == 6
                          ? const Color(0xFF9BCBFF)
                          : Colors.white,
                    ),
                    cell(
                      day.data == null
                          ? [status(day)]
                          : AstrologyCalendarDayPresentation.fromDay(
                              day.data!,
                              english: english,
                            ).moonLines,
                      const Color(0xFFCAE6FF),
                      moon: true,
                    ),
                    cell(
                      day.data == null
                          ? [status(day)]
                          : AstrologyCalendarDayPresentation.fromDay(
                              day.data!,
                              english: english,
                            ).voidLines,
                      const Color(0xFFFFD987),
                    ),
                  ]),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
