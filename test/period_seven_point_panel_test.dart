import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pancyo_ai_astrology/app_language.dart';
import 'package:pancyo_ai_astrology/app_language_settings.dart';
import 'package:pancyo_ai_astrology/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'period_seven_test_fixture.dart';

abstract class _PendingPeriod {
  bool cancelled = false;
  void cancel() => cancelled = true;
}

class _PendingWeek extends _PendingPeriod
    implements WeeklyDailyConsultExportOperation {
  final completer = Completer<WeeklyDailyConsultExportResult>();
  @override
  Future<WeeklyDailyConsultExportResult> get result => completer.future;
}

class _PendingMonth extends _PendingPeriod
    implements MonthlyDailyConsultExportOperation {
  final completer = Completer<MonthlyDailyConsultExportResult>();
  @override
  Future<MonthlyDailyConsultExportResult> get result => completer.future;
}

class _PendingDisplay extends _PendingPeriod
    implements LongRangeDisplayOperation {
  final completer = Completer<LongRangeDisplayResult>();
  @override
  Future<LongRangeDisplayResult> get result => completer.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
  late AppLanguage originalLanguage;
  late int legacyStarts, pathCalls, shareCalls;
  late List<_PendingPeriod> jobs;
  late List<(LongRangeMode, String, String, int)> periods;
  late WeeklyDailyConsultExportStarter weekStarter;
  late MonthlyDailyConsultExportStarter monthStarter;
  setUp(() {
    PeriodSevenDisplaySessionCache.clear();
    originalLanguage = AppLanguageSettings.current.value;
    AppLanguageSettings.current.value = AppLanguage.ja;
    SharedPreferences.setMockInitialValues({
      'unrelated.old_json': '{ "keep": true }',
    });
    legacyStarts = 0;
    pathCalls = 0;
    shareCalls = 0;
    jobs = [];
    periods = [];
    weekStarter = (request, progress) {
      periods.add((
        LongRangeMode.week,
        request.startDateJst,
        request.endDateJst,
        7,
      ));
      final job = _PendingWeek();
      jobs.add(job);
      return job;
    };
    monthStarter = (request, progress) {
      periods.add((
        LongRangeMode.month,
        request.startDateJst,
        request.endDateJst,
        request.dayCount,
      ));
      final job = _PendingMonth();
      jobs.add(job);
      return job;
    };
    PeriodReadingContextTestHooks.starter = (request, progress) {
      legacyStarts++;
      throw StateError('Week/month must not start the legacy period job.');
    };
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(pathChannel, (_) async {
      pathCalls++;
      throw StateError('No JSON writing from reading.');
    });
    messenger.setMockMethodCallHandler(shareChannel, (_) async {
      shareCalls++;
      return 'unavailable';
    });
  });
  tearDown(() {
    PeriodSevenDisplaySessionCache.clear();
    PeriodReadingContextTestHooks.starter = null;
    AppLanguageSettings.current.value = originalLanguage;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(pathChannel, null);
    messenger.setMockMethodCallHandler(shareChannel, null);
  });
  Widget shell(Widget child) => MaterialApp(
    theme: ThemeData.dark(),
    home: AppLanguageScope(
      child: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 8; i++)
      await tester.pump(const Duration(milliseconds: 50));
  }

  void noDailyOrExportUi() {
    for (final key in [
      'period-export-month-seven',
      'period-export-week-seven',
      'consult-json-month-seven',
      'consult-json-week-seven',
      'consult-json-year',
      'period-reading-date-dropdown',
      'period-overview-day',
      'period-overview-details',
    ]) {
      expect(find.byKey(ValueKey(key)), findsNothing);
    }
    for (final hour in [0, 4, 8, 12, 16, 20, 24]) {
      expect(find.byKey(ValueKey('period-reading-time-$hour')), findsNothing);
      expect(find.byKey(ValueKey('period-overview-time-$hour')), findsNothing);
    }
    expect(find.byType(PeriodSevenReadingView), findsNothing);
    expect(find.byType(PeriodSevenReadingCards), findsNothing);
    expect(find.byType(ProfileAstroJsonExportCard), findsNothing);
    expect(find.byType(DailyConsultJsonExportDialog), findsNothing);
    expect(find.byType(WeeklyDailyConsultExportDialog), findsNothing);
    expect(find.byType(MonthlyDailyConsultExportDialog), findsNothing);
    expect(pathCalls, 0);
    expect(shareCalls, 0);
  }

  for (final language in AppLanguage.values) {
    testWidgets(
      '${language.name}: canonical period panels exclude calendar, daily and export UI',
      (tester) async {
        AppLanguageSettings.current.value = language;
        for (final row in [
          (
            LongRangeMode.month,
            DateTime.utc(2026, 12, 18),
            31,
            '2026-12-01',
            '2026-12-31',
          ),
          (
            LongRangeMode.month,
            DateTime.utc(2024, 2, 18),
            29,
            '2024-02-01',
            '2024-02-29',
          ),
          (
            LongRangeMode.week,
            DateTime.utc(2026, 12, 28),
            7,
            '2026-12-28',
            '2027-01-03',
          ),
        ]) {
          await tester.pumpWidget(
            shell(
              PeriodSevenPointPanel(
                mode: row.$1,
                startDateJst: row.$2,
                profile: sevenFixtureProfile,
                details: sevenFixtureDetails,
                startWeeklyJob: weekStarter,
                startMonthlyJob: monthStarter,
              ),
            ),
          );
          await frames(tester);
          expect(find.byType(PeriodSevenOverview), findsOneWidget);
          expect(periods.last, (row.$1, row.$4, row.$5, row.$3));
          expect(
            tester
                .widget<PeriodSevenOverview>(find.byType(PeriodSevenOverview))
                .showRangeHeader,
            false,
          );
          expect(
            find.byKey(const ValueKey('period-overview-range')),
            findsNothing,
            reason:
                'The surrounding period navigation already shows the range.',
          );
          for (final key in NineAreaKey.values) {
            expect(
              find.byKey(ValueKey('period-overview-placeholder-${key.name}')),
              findsOneWidget,
            );
          }
          expect(
            find.byKey(const ValueKey('period-open-calendar')),
            findsNothing,
          );
          expect(find.byType(NineAreaPeriodOverview), findsNothing);
          expect(find.byType(LongRangeChart), findsNothing);
          noDailyOrExportUi();
        }
        expect(legacyStarts, 0);
        expect(jobs.length, 3);
        expect(jobs.take(2).every((job) => job.cancelled), true);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'week/month switch cancels stale jobs and uses only five monthly reference dates',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: AppLanguageScope(
            child: Scaffold(
              body: LongRangeReading(
                profile: sevenFixtureProfile,
                details: sevenFixtureDetails,
                depth: ReadingDepth.detailed,
                startWeeklyReadingJob: weekStarter,
                startMonthlyReadingJob: monthStarter,
                startLongRangeDisplayJob: (request, progress) {
                  expect(request.mode, LongRangeDisplayMode.month);
                  expect(request.summaryDates.length, 5);
                  expect(request.monthWeeks.length, 5);
                  final job = _PendingDisplay();
                  jobs.add(job);
                  return job;
                },
              ),
            ),
          ),
        ),
      );
      await frames(tester);
      expect(
        tester
            .widget<PeriodSevenOverview>(find.byType(PeriodSevenOverview))
            .mode,
        LongRangeMode.week,
      );
      await tester.tap(find.text('月'));
      await frames(tester);
      expect(
        tester
            .widget<LongRangeOverviewPanel>(find.byType(LongRangeOverviewPanel))
            .request
            .mode,
        LongRangeDisplayMode.month,
      );
      expect(find.byType(PeriodSevenOverview), findsNothing);
      await tester.tap(find.text('週'));
      await frames(tester);
      expect(
        tester
            .widget<PeriodSevenOverview>(find.byType(PeriodSevenOverview))
            .mode,
        LongRangeMode.week,
      );
      expect(jobs.length, 3);
      expect(jobs.take(2).every((job) => job.cancelled), true);
      expect(legacyStarts, 0);
      expect(
        find.byKey(const ValueKey('period-context-preparation')),
        findsNothing,
      );
      expect(find.byType(NineAreaPeriodOverview), findsNothing);
      expect(find.byType(LongRangeChart), findsNothing);
      noDailyOrExportUi();
      expect(tester.takeException(), isNull);
    },
  );
}
