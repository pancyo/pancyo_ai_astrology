part of 'main.dart';

/// Period readings use daily-v4 snapshots; JSON creation stays in Profile.
class PeriodSevenPointPanel extends StatelessWidget {
  const PeriodSevenPointPanel({
    super.key,
    required this.mode,
    required this.startDateJst,
    required this.profile,
    required this.details,
    this.depth = ReadingDepth.simple,
    this.startWeeklyJob,
    this.startMonthlyJob,
  }) : assert(mode != LongRangeMode.year);

  final LongRangeMode mode;

  /// Civil JST fields, not a device-local instant.
  final DateTime startDateJst;
  final AstroProfile profile;
  final UserProfileDetails details;
  final ReadingDepth depth;
  final WeeklyDailyConsultExportStarter? startWeeklyJob;
  final MonthlyDailyConsultExportStarter? startMonthlyJob;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('period-seven-point-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (mode == LongRangeMode.month && startMonthlyJob == null)
          MonthHalfOverview(
            startDateJst: startDateJst,
            profile: profile,
            details: details,
            depth: depth,
          )
        else
          PeriodSevenOverview(
            showRangeHeader: false,
            mode: mode,
            startDateJst: startDateJst,
            profile: profile,
            details: details,
            depth: depth,
            startWeeklyJob: startWeeklyJob,
            startMonthlyJob: startMonthlyJob,
          ),
      ],
    );
  }
}
