part of 'main.dart';

/// Returns the selected civil day at noon JST, represented as UTC 03:00.
/// [instant] is an instant, so the device's local zone is normalized first.
DateTime dailyFeatureJstNoon(DateTime instant) {
  final jst = instant.toUtc().add(const Duration(hours: 9));
  return DateTime.utc(jst.year, jst.month, jst.day, 3);
}

/// Keeps the earlier one-person consultation reachable after the tab changes.
void openLegacyReadingNavigator(
  BuildContext context, {
  required AstroProfile profile,
  required UserProfileDetails details,
  required HoroscopeReadingContext contextData,
  DateTime? initialDate,
  String initialQuestion = '',
}) {
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => StarScaffold(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            title: const EnglishUiText('一人用の鑑定ナビ'),
          ),
          body: SafeArea(
            child: CustomReading(
              profile: profile,
              details: details,
              contextData: contextData,
              initialDate: initialDate ?? contextData.transit.date,
              initialQuestion: initialQuestion,
            ),
          ),
        ),
      ),
    ),
  );
}

class DailyFeatureLinks extends StatelessWidget {
  const DailyFeatureLinks({
    super.key,
    required this.profile,
    required this.details,
    required this.date,
  });

  final AstroProfile profile;
  final UserProfileDetails details;
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      margin: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const EnglishUiText(
            '星をもう少し詳しく読む',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              TextButton.icon(
                key: const ValueKey('open-astrology-calendar'),
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => AstrologyCalendarView(initialDate: date),
                  ),
                ),
                icon: const Icon(Icons.calendar_month_outlined),
                label: const EnglishUiText('星のカレンダー'),
              ),
              TextButton.icon(
                key: const ValueKey('open-legacy-reading-navigator'),
                onPressed: () => openLegacyReadingNavigator(
                  context,
                  profile: profile,
                  details: details,
                  contextData: const AstrologyEngine().buildPreviewContext(
                    profile: profile,
                    date: DateTime.utc(date.year, date.month, date.day, 3),
                  ),
                  initialDate: DateTime.utc(date.year, date.month, date.day, 3),
                ),
                icon: const Icon(Icons.chat_bubble_outline),
                label: const EnglishUiText('一人用の鑑定ナビ'),
              ),
            ],
          ),
          const EnglishUiText(
            'カレンダーは選んだ日の星の動きを表示します。鑑定ナビは日付を選べる日ごとの注意点や期間別の相談に使えます。期間相談は今日を起点にします。',
            style: TextStyle(fontSize: 12, color: Color(0xFFB8C6E0)),
          ),
        ],
      ),
    );
  }
}
