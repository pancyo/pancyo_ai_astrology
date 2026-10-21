// Synthetic contract fixtures only. Astronomical calculation and canonical
// aggregation are covered separately by period_seven_summary_test.dart.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pancyo_ai_astrology/app_language.dart';
import 'package:pancyo_ai_astrology/app_language_settings.dart';
import 'package:pancyo_ai_astrology/main.dart';

import 'period_seven_test_fixture.dart';

class _WeeklyJob implements WeeklyDailyConsultExportOperation {
  final completion = Completer<WeeklyDailyConsultExportResult>();
  bool cancelled = false;
  @override
  Future<WeeklyDailyConsultExportResult> get result => completion.future;
  @override
  void cancel() => cancelled = true;
}

class _MonthlyJob implements MonthlyDailyConsultExportOperation {
  final completion = Completer<MonthlyDailyConsultExportResult>();
  bool cancelled = false;
  @override
  Future<MonthlyDailyConsultExportResult> get result => completion.future;
  @override
  void cancel() => cancelled = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SyntheticSevenPeriodFixture fixture;
  late List<PeriodSevenSummary> fourWeeks, twelveMonths;
  late HouseSystem originalHouse;
  late AppLanguage originalLanguage;
  late List<WeeklyDailyConsultExportRequest> weekRequests;
  late List<MonthlyDailyConsultExportRequest> monthRequests;
  late List<_WeeklyJob> weekJobs;
  late List<_MonthlyJob> monthJobs;
  late WeeklyDailyConsultExportStarter weekStarter;
  late MonthlyDailyConsultExportStarter monthStarter;

  PeriodSevenSummary summarize(
    Map<String, Object?> wrapper,
    LongRangeMode mode,
  ) {
    final period =
        wrapper[mode == LongRangeMode.week ? 'week' : 'month'] as Map;
    return PeriodSevenSummary.fromDailyV4(
      mode: mode,
      startDateJst: DateTime.parse(period['start_date_jst'] as String),
      days: (wrapper['days'] as List)
          .map((day) => Map<String, Object?>.from(day as Map))
          .toList(),
      profile: sevenFixtureProfile,
      details: sevenFixtureDetails,
      requestedHouseSystem: HouseSystem.placidus,
      sourceName: AstrologyDataSources.current.sourceName,
      requireHighPrecision:
          AstrologyDataSources.current.usesHighPrecisionAstroData,
    );
  }

  setUpAll(() {
    final oldHouse = HouseSystemSettings.current.value;
    HouseSystemSettings.current.value = HouseSystem.placidus;
    fixture = SyntheticSevenPeriodFixture();
    fourWeeks = [
      for (var i = 0; i < 4; i++)
        summarize(
          fixture.week(
            fixtureWeekRequest(DateTime.utc(2026, 12, 28 + i * 7)),
            score: (point, area) =>
                50 +
                (point + i * 7 + NineAreaKey.values.byName(area).index) % 50,
            felt: i == 0 ? null : (_) => '良い',
          ),
          LongRangeMode.week,
        ),
    ];
    twelveMonths = [
      for (var month = 1; month <= 12; month++)
        summarize(
          fixture.month(
            fixtureMonthRequest(DateTime.utc(2026, month)),
            score: (point, area) =>
                50 +
                (point + month + NineAreaKey.values.byName(area).index) % 50,
            felt: (_) => month.isEven ? '良い' : '普通',
          ),
          LongRangeMode.month,
        ),
    ];
    HouseSystemSettings.current.value = oldHouse;
  });
  setUp(() {
    PeriodSevenDisplaySessionCache.clear();
    originalHouse = HouseSystemSettings.current.value;
    originalLanguage = AppLanguageSettings.current.value;
    HouseSystemSettings.current.value = HouseSystem.placidus;
    AppLanguageSettings.current.value = AppLanguage.ja;
    weekRequests = [];
    monthRequests = [];
    weekJobs = [];
    monthJobs = [];
    weekStarter = (request, progress) {
      weekRequests.add(request);
      final job = _WeeklyJob();
      weekJobs.add(job);
      return job;
    };
    monthStarter = (request, progress) {
      monthRequests.add(request);
      final job = _MonthlyJob();
      monthJobs.add(job);
      return job;
    };
  });
  tearDown(() {
    PeriodSevenDisplaySessionCache.clear();
    HouseSystemSettings.current.value = originalHouse;
    AppLanguageSettings.current.value = originalLanguage;
  });

  const mainKeys = [
    NineAreaKey.overall,
    NineAreaKey.love,
    NineAreaKey.work,
    NineAreaKey.money,
    NineAreaKey.mental,
  ];
  const mainColors = [
    Color(0xFFF6D77A),
    Color(0xFFFF82B2),
    Color(0xFF57D6D1),
    Color(0xFF9BE06D),
    Color(0xFFB58CFF),
  ];
  void expectSeries(
    PeriodSevenGroupedTrendData data,
    List<PeriodSevenSummary> sums,
  ) {
    expect(data.series.length, 5);
    expect(data.additional.series.length, 3);
    expect(data.summaries, sums);
    expect(data.labels.length, sums.length);
    expect(
      data.dates,
      sums.map((s) {
        final date = DateTime.parse(s.startDateJst);
        return DateTime.utc(date.year, date.month, date.day);
      }).toList(),
    );
    for (var i = 0; i < 5; i++) {
      expect(data.series[i].color, mainColors[i]);
      expect(data.series[i].values, [
        for (final summary in sums)
          summary.areas.singleWhere((area) => area.key == mainKeys[i]).score,
      ]);
    }
    for (var i = 0; i < 3; i++) {
      expect(
        data.additional.series[i].color,
        AdditionalFortuneTrendData.colors[i],
      );
      expect(data.additional.series[i].values, [
        for (final summary in sums)
          summary.areas
              .singleWhere(
                (area) => area.key == AdditionalFortuneTrendData.numericKeys[i],
              )
              .score,
      ]);
    }
    expect(
      data.additional.felt.map((f) => f.label).toList(),
      sums.map((s) => s.feltDisplayLabel).toList(),
    );
    for (var i = 0; i < sums.length; i++) {
      expect(data.additional.felt[i].periodSummary, same(sums[i]));
      expect(
        sums[i].areas.singleWhere((a) => a.key == NineAreaKey.felt).score,
        isNull,
      );
    }
  }

  test(
    'four weeks and twelve months retain exact 5+3 values, original colors and categorical felt',
    () {
      for (final sums in [fourWeeks, twelveMonths]) {
        final before = jsonEncode(sums.map((s) => s.toJson()).toList());
        final data = PeriodSevenGroupedTrendData.fromSummaries(sums);
        expectSeries(data, sums);
        expect(jsonEncode(sums.map((s) => s.toJson()).toList()), before);
      }
      expect(fourWeeks.first.feltDisplayLabel, '混在');
      expect(twelveMonths.first.startDateJst, '2026-01-01');
      expect(twelveMonths.last.endDateJst, '2026-12-31');
    },
  );

  test(
    'grouped data rejects missing, duplicate, reordered and mixed periods',
    () {
      for (final invalid in <List<PeriodSevenSummary>>[
        fourWeeks.take(3).toList(),
        [fourWeeks[0], fourWeeks[0], fourWeeks[2], fourWeeks[3]],
        fourWeeks.reversed.toList(),
        twelveMonths.take(11).toList(),
        [twelveMonths[1], twelveMonths[0], ...twelveMonths.skip(2)],
        [fourWeeks[0], fourWeeks[1], fourWeeks[2], twelveMonths[0]],
      ]) {
        expect(
          () => PeriodSevenGroupedTrendData.fromSummaries(invalid),
          throwsA(anything),
        );
      }
    },
  );

  Widget shell(Widget child) => MaterialApp(
    theme: ThemeData.dark(),
    home: AppLanguageScope(
      child: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await frames(tester);
  }

  Future<void> loader(
    WidgetTester tester,
    PeriodSevenSummary current, {
    AstroProfile profile = sevenFixtureProfile,
  }) async {
    await tester.pumpWidget(
      shell(
        PeriodSevenTrend(
          summary: current,
          profile: profile,
          details: sevenFixtureDetails,
          startWeeklyJob: weekStarter,
          startMonthlyJob: monthStarter,
        ),
      ),
    );
    await frames(tester);
  }

  void completeWeek() {
    final request = weekRequests.last;
    weekJobs.last.completion.complete(
      WeeklyDailyConsultExportResult.fromData(
        requestIdentity: request.identity,
        data: fixture.week(request),
      ),
    );
  }

  void completeMonth() {
    final request = monthRequests.last;
    monthJobs.last.completion.complete(
      MonthlyDailyConsultExportResult.fromData(
        requestIdentity: request.identity,
        data: fixture.month(request),
      ),
    );
  }

  for (final language in AppLanguage.values) {
    for (final size in [const Size(390, 844), const Size(1181, 738)]) {
      testWidgets(
        '${language.name} ${size.width}: original five lines and expandable three lines plus felt fit',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          AppLanguageSettings.current.value = language;
          // Both screen sizes exercise the wider twelve-month case, including
          // the existing horizontal scrolling in the additional chart.
          await tester.pumpWidget(
            shell(PeriodSevenGroupedTrendView(summaries: twelveMonths)),
          );
          await frames(tester);
          expect(
            find.byKey(const ValueKey('period-trend-area-dropdown')),
            findsNothing,
          );
          final painter =
              tester
                      .widget<CustomPaint>(
                        find.byKey(
                          const ValueKey('period-grouped-trend-chart'),
                        ),
                      )
                      .painter
                  as FortuneFlowPainter;
          expect(painter.series.length, 5);
          expect(painter.labels.length, 12);
          final toggle = tester.widget<AdditionalFortuneTrendChart>(
            find.byType(AdditionalFortuneTrendChart),
          );
          expectSeries(
            PeriodSevenGroupedTrendData.fromSummaries(twelveMonths),
            twelveMonths,
          );
          expect(toggle.dataFor().series.length, 3);
          await tap(tester, 'additional-trend-toggle');
          final additional = tester.widget<AdditionalFortuneTrendView>(
            find.byType(AdditionalFortuneTrendView),
          );
          expect(additional.data.series.length, 3);
          expect(additional.data.felt.length, 12);
          final additionalPainter =
              tester
                      .widget<CustomPaint>(
                        find.descendant(
                          of: find.byType(AdditionalFortuneTrendView),
                          matching: find.byType(CustomPaint),
                        ),
                      )
                      .painter
                  as FortuneFlowPainter;
          expect(additionalPainter.series.length, 3);
          expect(additionalPainter.labels.length, 12);
          expect(find.byKey(const ValueKey('felt-trend-0')), findsOneWidget);
          expect(find.byKey(const ValueKey('felt-trend-11')), findsOneWidget);
          expect(find.byType(FortuneNumber), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final mode in [LongRangeMode.week, LongRangeMode.month]) {
    testWidgets(
      '${mode.name}: explicit sequential load reuses current period and fills only missing comparisons',
      (tester) async {
        final current = mode == LongRangeMode.week
            ? fourWeeks.first
            : twelveMonths[4];
        await loader(tester, current);
        expect(weekJobs, isEmpty);
        expect(monthJobs, isEmpty);
        await tap(tester, 'period-trend-load');
        final count = mode == LongRangeMode.week ? 3 : 11;
        for (var i = 0; i < count; i++) {
          expect(find.byType(PeriodSevenGroupedTrendView), findsNothing);
          if (mode == LongRangeMode.week) {
            expect(weekJobs.length, i + 1);
            completeWeek();
          } else {
            expect(monthJobs.length, i + 1);
            completeMonth();
          }
          await frames(tester);
        }
        final view = tester.widget<PeriodSevenGroupedTrendView>(
          find.byType(PeriodSevenGroupedTrendView),
        );
        final data = PeriodSevenGroupedTrendData.fromSummaries(view.summaries);
        expectSeries(data, view.summaries);
        expect(
          view.summaries[mode == LongRangeMode.week ? 0 : 4],
          same(current),
        );
        if (mode == LongRangeMode.week) {
          expect(weekRequests.map((r) => r.startDateJst).toList(), [
            '2027-01-04',
            '2027-01-11',
            '2027-01-18',
          ]);
          expect(monthJobs, isEmpty);
        } else {
          expect(monthRequests.map((r) => r.startDateJst).toList(), [
            for (var m = 1; m <= 12; m++)
              if (m != 5) '2026-${m.toString().padLeft(2, '0')}-01',
          ]);
          expect(weekJobs, isEmpty);
        }
        await loader(tester, current);
        expect(weekJobs.length + monthJobs.length, count);
        expect(find.byType(PeriodSevenGroupedTrendView), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'cancel discards late comparison, retry starts a fresh sequence, and current changes discard old work',
    (tester) async {
      await loader(tester, fourWeeks.first);
      await tap(tester, 'period-trend-load');
      expect(weekJobs.length, 1);
      await tap(tester, 'period-trend-cancel');
      expect(weekJobs.single.cancelled, true);
      completeWeek();
      await frames(tester);
      expect(weekJobs.length, 1);
      expect(find.byType(PeriodSevenGroupedTrendView), findsNothing);
      await tap(tester, 'period-trend-retry');
      expect(weekJobs.length, 2);
      expect(weekRequests[1].startDateJst, weekRequests[0].startDateJst);
      await loader(tester, fourWeeks[1]);
      expect(weekJobs[1].cancelled, true);
      completeWeek();
      await frames(tester);
      expect(weekJobs.length, 2);
      expect(find.byType(PeriodSevenGroupedTrendView), findsNothing);
      await tap(tester, 'period-trend-load');
      expect(weekRequests.last.startDateJst, '2027-01-11');
      await tester.pumpWidget(const SizedBox.shrink());
      expect(weekJobs.last.cancelled, true);
      completeWeek();
      await frames(tester);
      expect(weekJobs.length, 3);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'changed house with stale current summary cannot load or expose old comparisons',
    (tester) async {
      await loader(tester, fourWeeks.first);
      await tap(tester, 'period-trend-load');
      HouseSystemSettings.current.value = HouseSystem.wholeSign;
      await frames(tester);
      expect(weekJobs.single.cancelled, true);
      completeWeek();
      await frames(tester);
      expect(weekJobs.length, 1);
      expect(find.byType(PeriodSevenGroupedTrendView), findsNothing);
      expect(find.byKey(const ValueKey('period-trend-load')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
