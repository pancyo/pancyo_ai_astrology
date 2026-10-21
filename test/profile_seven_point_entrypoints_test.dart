import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pancyo_ai_astrology/app_language.dart';
import 'package:pancyo_ai_astrology/app_language_settings.dart';
import 'package:pancyo_ai_astrology/main.dart';

class _MonthJob implements MonthlyDailyConsultExportOperation {
  final completer = Completer<MonthlyDailyConsultExportResult>();
  bool cancelled = false;
  @override
  Future<MonthlyDailyConsultExportResult> get result => completer.future;
  @override
  void cancel() => cancelled = true;
}

class _WeekJob implements WeeklyDailyConsultExportOperation {
  final completer = Completer<WeeklyDailyConsultExportResult>();
  bool cancelled = false;
  @override
  Future<WeeklyDailyConsultExportResult> get result => completer.future;
  @override
  void cancel() => cancelled = true;
}

class _YearJob implements PeriodConsultExportOperation {
  final completer = Completer<PeriodConsultExportCalculation>();
  bool cancelled = false;
  @override
  Future<PeriodConsultExportCalculation> get result => completer.future;
  @override
  void cancel() => cancelled = true;
}

// Synthetic UI input; no personal profile or native ephemeris is read.
const _profile = AstroProfile(
  name: 'SevenEntryFixture',
  birthDate: '1990/1/2',
  birthTime: '12:00',
  birthPlace: '北海道札幌市',
  theme: '表示テスト',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppLanguage originalLanguage;
  late List<MonthlyDailyConsultExportRequest> months;
  late List<WeeklyDailyConsultExportRequest> weeks;
  late List<PeriodConsultExportRequest> years;
  late List<_MonthJob> monthJobs;
  late List<_WeekJob> weekJobs;
  late List<_YearJob> yearJobs;
  var storageOrShareCalls = 0;
  const path = MethodChannel('plugins.flutter.io/path_provider');
  const share = MethodChannel('dev.fluttercommunity.plus/share');

  setUp(() {
    originalLanguage = AppLanguageSettings.current.value;
    months = [];
    weeks = [];
    years = [];
    monthJobs = [];
    weekJobs = [];
    yearJobs = [];
    storageOrShareCalls = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in [path, share]) {
      messenger.setMockMethodCallHandler(channel, (_) async {
        storageOrShareCalls++;
        throw StateError('Cancelled UI work must not save or share.');
      });
    }
  });

  tearDown(() {
    AppLanguageSettings.current.value = originalLanguage;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(path, null);
    messenger.setMockMethodCallHandler(share, null);
    expect(storageOrShareCalls, 0);
  });

  Future<void> pumpProfile(WidgetTester tester, AppLanguage language) async {
    AppLanguageSettings.current.value = language;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: AppLanguageScope(
          child: Scaffold(
            body: SingleChildScrollView(
              child: ProfileAstroJsonExportCard(
                profile: _profile,
                details: const UserProfileDetails.empty(),
                startMonthlyDailyJob: (request, _) {
                  months.add(request);
                  final job = _MonthJob();
                  monthJobs.add(job);
                  return job;
                },
                startWeeklyJob: (request, _) {
                  weeks.add(request);
                  final job = _WeekJob();
                  weekJobs.add(job);
                  return job;
                },
                startYearJob: (request) {
                  years.add(request);
                  final job = _YearJob();
                  yearJobs.add(job);
                  return job;
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
  }

  Future<void> open(WidgetTester tester, String key) async {
    final button = find.byKey(ValueKey(key));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  Future<void> cancel(WidgetTester tester, AppLanguage language) async {
    await tester.tap(find.text(language == AppLanguage.ja ? '中止' : 'Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  for (final language in AppLanguage.values) {
    testWidgets(
      '${language.code}: month has one seven-point entry; week and year remain',
      (tester) async {
        await pumpProfile(tester, language);
        for (final period in ['month', 'week', 'year']) {
          expect(
            find.descendant(
              of: find.byKey(ValueKey('consult-json-$period-row')),
              matching: find.byType(FilledButton),
            ),
            findsOneWidget,
          );
        }
        expect(
          find.byKey(const ValueKey('consult-json-month-seven')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('consult-json-week-seven')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('consult-json-year')), findsOneWidget);
        expect(find.text('この月の毎日占いデータを作る'), findsNothing);
        expect(
          find.text('Create daily reading data for this month'),
          findsNothing,
        );
        final description = AppStrings(
          language,
        ).text(AppText.consultJsonDescription);
        expect(find.text(description), findsOneWidget);
        expect(
          description,
          contains(language == AppLanguage.ja ? '49時点' : '49 listed points'),
        );
        expect(
          description,
          contains(
            language == AppLanguage.ja
                ? '月は選んだ月の全日'
                : 'every day of the selected month',
          ),
        );
        expect(
          description,
          isNot(
            contains(
              language == AppLanguage.ja ? '月5時点' : 'five dates per month',
            ),
          ),
        );
        expect(months, isEmpty);
        expect(weeks, isEmpty);
        expect(years, isEmpty);
      },
    );

    testWidgets(
      '${language.code}: buttons dispatch monthly seven, weekly 49, and unchanged annual modes',
      (tester) async {
        await pumpProfile(tester, language);
        await open(tester, 'consult-json-month-seven');
        expect(
          months,
          isEmpty,
          reason: 'Monthly preflight must precede calculation.',
        );
        await tester.tap(
          find.text(language == AppLanguage.ja ? '開始' : 'Start'),
        );
        await tester.pump();
        expect(months, hasLength(1));
        final month = months.single;
        expect(month.startDate.day, 1);
        expect(month.startDate.hour, 3);
        expect(month.listedPointCount, month.dayCount * 7);
        expect(month.dayPlans, hasLength(month.dayCount));
        for (final day in month.dayPlans) {
          expect(day.points.map((point) => point.hourFromDayStart), [
            0,
            4,
            8,
            12,
            16,
            20,
            24,
          ]);
        }
        expect(weeks, isEmpty);
        expect(years, isEmpty);
        await cancel(tester, language);
        expect(monthJobs.single.cancelled, true);
        monthJobs.single.completer.completeError(
          const MonthlyDailyConsultExportCancelled(),
        );
        await tester.pump();

        await open(tester, 'consult-json-week-seven');
        expect(weeks, hasLength(1));
        final week = weeks.single;
        expect(week.startDate.hour, 3);
        expect(week.dayPlans, hasLength(7));
        expect(week.dayPlans.expand((day) => day.points), hasLength(49));
        for (var i = 0; i < 7; i++) {
          expect(
            week.dayPlans[i].points.map((point) => point.hourFromDayStart),
            [0, 4, 8, 12, 16, 20, 24],
          );
          if (i > 0) {
            expect(
              week.dayPlans[i - 1].points.last.instantUtc,
              week.dayPlans[i].points.first.instantUtc,
            );
          }
        }
        expect(months, hasLength(1));
        expect(years, isEmpty);
        await cancel(tester, language);
        expect(weekJobs.single.cancelled, true);
        weekJobs.single.completer.completeError(
          const WeeklyDailyConsultExportCancelled(),
        );
        await tester.pump();

        await open(tester, 'consult-json-year');
        expect(years, hasLength(1));
        final year = years.single;
        expect(year.mode, LongRangeMode.year);
        expect(year.month, DateTime(year.year, 1, 1, 12));
        expect(year.weekStart, year.month);
        expect(months, hasLength(1));
        expect(weeks, hasLength(1));
        await cancel(tester, language);
        expect(yearJobs.single.cancelled, true);
        yearJobs.single.completer.completeError(
          const PeriodConsultExportCancelled(),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
