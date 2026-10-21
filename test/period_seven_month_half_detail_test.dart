// Tie/sorting tests use explicitly synthetic weekly contracts. The half-month
// UI tests perform real calculations for the existing fictional test profile.
// Representative-day text is compared with the existing detailed explanation.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pancyo_ai_astrology/app_language.dart';
import 'package:pancyo_ai_astrology/app_language_settings.dart';
import 'package:pancyo_ai_astrology/main.dart';

import 'period_seven_test_fixture.dart';

class _DetailDisplayJob implements PeriodSevenDisplayOperation {
  final completion = Completer<PeriodSevenDisplayResult>();
  @override
  Future<PeriodSevenDisplayResult> get result => completion.future;
  @override
  void cancel() {}
}

class _DetailWeekJob implements WeeklyDailyConsultExportOperation {
  final completion = Completer<WeeklyDailyConsultExportResult>();
  @override
  Future<WeeklyDailyConsultExportResult> get result => completion.future;
  @override
  void cancel() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SyntheticSevenPeriodFixture fixture;
  late PeriodSevenSummary varying, constant;
  late List<PeriodSevenSummary> varyingDays, constantDays;
  late AppLanguage oldLanguage;
  late HouseSystem oldHouse;

  PeriodSevenSummary summarize(Map<String, Object?> wrapper) =>
      PeriodSevenSummary.fromDailyV4(
        mode: LongRangeMode.week,
        startDateJst: DateTime.utc(2026, 12, 28),
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

  setUpAll(() {
    final house = HouseSystemSettings.current.value;
    HouseSystemSettings.current.value = HouseSystem.placidus;
    fixture = SyntheticSevenPeriodFixture();
    final request = fixtureWeekRequest(DateTime.utc(2026, 12, 28));
    varying = summarize(
      fixture.week(
        request,
        score: (index, area) =>
            (index % 12 < 6 ? 90 : 50) +
            NineAreaKey.values.byName(area).index % 5,
        felt: (_) => '普通',
      ),
    );
    constant = summarize(
      fixture.week(request, score: (_, _) => 71, felt: (_) => '普通'),
    );
    varyingDays = List.generate(7, varying.daySummaryAt);
    constantDays = List.generate(7, constant.daySummaryAt);
    HouseSystemSettings.current.value = house;
  });
  setUp(() {
    oldLanguage = AppLanguageSettings.current.value;
    oldHouse = HouseSystemSettings.current.value;
    AppLanguageSettings.current.value = AppLanguage.ja;
    HouseSystemSettings.current.value = HouseSystem.placidus;
    PeriodSevenDisplaySessionCache.clear();
  });
  tearDown(() {
    AppLanguageSettings.current.value = oldLanguage;
    HouseSystemSettings.current.value = oldHouse;
    PeriodSevenDisplaySessionCache.clear();
  });

  test(
    'all eight numeric extrema retain every tied day in chronological JST order across the year boundary',
    () {
      final before = jsonEncode(varying.toJson());
      final data = HalfMonthDayHighlightData.allFromDaily(varyingDays);
      expect(data.length, 8);
      expect(data.containsKey(NineAreaKey.felt), false);
      for (final key in NineAreaKey.values.where(
        (key) => key != NineAreaKey.felt,
      )) {
        final item = data[key]!;
        expect(item.area, key);
        expect(item.hasVariation, true);
        expect(item.maxScore, 84 + key.index % 5);
        expect(item.minScore, 56 + key.index % 5);
        expect(item.highDates, [
          '2026-12-28',
          '2026-12-30',
          '2027-01-01',
          '2027-01-03',
        ]);
        expect(item.lowDates, ['2026-12-29', '2026-12-31', '2027-01-02']);
        expect(() => item.highDates.add('2027-01-04'), throwsUnsupportedError);
        expect(() => item.lowDates.clear(), throwsUnsupportedError);
      }
      expect(() => data.clear(), throwsUnsupportedError);
      expect(jsonEncode(varying.toJson()), before);
    },
  );

  test(
    'constant scores remain no-difference; felt and incomplete/nonconsecutive daily evidence are rejected',
    () {
      final data = HalfMonthDayHighlightData.allFromDaily(constantDays);
      for (final item in data.values) {
        expect(item.hasVariation, false);
        expect(item.maxScore, 71);
        expect(item.minScore, 71);
        expect(item.highDates, constantDays.map((day) => day.startDateJst));
        expect(item.lowDates, item.highDates);
      }
      expect(
        () => HalfMonthDayHighlightData.fromDaily(
          daily: constantDays,
          area: NineAreaKey.felt,
        ),
        throwsArgumentError,
      );
      for (final bad in <List<PeriodSevenSummary>>[
        [],
        [varying],
        [varyingDays.first, varyingDays.first],
        [varyingDays.first, varyingDays[2]],
        varyingDays.reversed.toList(),
      ]) {
        expect(
          () => HalfMonthDayHighlightData.allFromDaily(bad),
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
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  String textAt(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(ValueKey(key))).data!;
  Future<void> tap(WidgetTester tester, String key) async {
    final target = find.byKey(ValueKey(key));
    await tester.ensureVisible(target);
    await tester.tap(target);
    await frames(tester);
  }

  void expectRepresentative(
    WidgetTester tester,
    PeriodSevenSummary summary,
    List<PeriodSevenSummary> days,
    NineAreaKey area,
    AppLanguage language,
  ) {
    final highLow = HalfMonthDayHighlightData.fromDaily(
      daily: days,
      area: area,
    );
    for (final role in ['high', if (highLow.hasVariation) 'low']) {
      final date =
          (role == 'high' ? highLow.highDates : highLow.lowDates).first;
      final day = days.singleWhere((value) => value.startDateJst == date);
      final parsed = DateTime.parse(date);
      final expected = ForecastExplanation.forPeriod(
        summary: day,
        area: day.areas.singleWhere((value) => value.key == area),
        strings: AppStrings(language),
        depth: ReadingDepth.detailed,
        supplement: sevenFixtureDetails,
        dailySamples: day.predictionsByInstant,
      );
      expect(
        textAt(tester, 'half-highlights-example-$role-${area.name}'),
        contains('${parsed.month}/${parsed.day}'),
      );
      expect(
        textAt(tester, 'half-highlights-example-$role-${area.name}'),
        contains(language == AppLanguage.en ? 'this day only' : 'この日のみ'),
      );
      expect(
        textAt(tester, 'half-highlights-interpretation-$role-${area.name}'),
        expected.interpretation,
      );
      expect(
        textAt(tester, 'half-highlights-advice-$role-${area.name}'),
        '${language == AppLanguage.en ? 'Try' : '行動のヒント'}: ${expected.advice}',
      );
      final materials = textAt(
        tester,
        'half-highlights-material-$role-${area.name}',
      );
      for (final group in [
        expected.positiveMaterials,
        expected.negativeMaterials,
        expected.neutralMaterials,
      ]) {
        if (group.isNotEmpty) expect(materials, contains(group.first));
      }
      if ([
        expected.positiveMaterials,
        expected.negativeMaterials,
        expected.neutralMaterials,
      ].any((group) => group.isNotEmpty)) {
        expect(
          materials,
          contains(language == AppLanguage.en ? 'excerpts' : '抜粋'),
        );
      }
      if (language == AppLanguage.en) {
        expect(
          RegExp(r'[\u3040-\u30ff\u3400-\u9fff]').hasMatch(materials),
          false,
        );
      }
    }
    expect(
      summary.areas.singleWhere((area) => area.key == NineAreaKey.felt).score,
      isNull,
    );
  }

  testWidgets(
    'representative tied-day examples are explicitly limited to the first tied day and preserve the full existing ledger',
    (tester) async {
      for (final language in AppLanguage.values) {
        AppLanguageSettings.current.value = language;
        await tester.pumpWidget(
          shell(
            PeriodScoreDayHighlights(
              summary: varying,
              area: NineAreaKey.work,
              details: sevenFixtureDetails,
              dailySummaries: varyingDays,
            ),
          ),
        );
        await frames(tester);
        expectRepresentative(
          tester,
          varying,
          varyingDays,
          NineAreaKey.work,
          language,
        );
        final high = textAt(tester, 'half-highlights-high-work');
        for (final date in ['12/28', '12/30', '1/1', '1/3']) {
          expect(high, contains(date));
        }
        for (final role in ['high', 'low']) {
          await tap(tester, 'half-highlights-ledger-$role-work');
          final day = varyingDays[role == 'high' ? 0 : 1];
          final expected = ForecastExplanation.forPeriod(
            summary: day,
            area: day.areas.singleWhere((a) => a.key == NineAreaKey.work),
            strings: AppStrings(language),
            depth: ReadingDepth.detailed,
            supplement: sevenFixtureDetails,
            dailySamples: day.predictionsByInstant,
          );
          expect(
            find.descendant(
              of: find.byKey(ValueKey('half-highlights-ledger-$role-work')),
              matching: find.text(expected.numericLedgerText),
            ),
            findsOneWidget,
          );
          await tap(tester, 'half-highlights-ledger-$role-work');
        }
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'constant-day UI shows no difference and only one explicitly dated example; felt has no numeric highlights',
    (tester) async {
      for (final language in AppLanguage.values) {
        AppLanguageSettings.current.value = language;
        await tester.pumpWidget(
          shell(
            PeriodScoreDayHighlights(
              summary: constant,
              area: NineAreaKey.work,
              details: sevenFixtureDetails,
              dailySummaries: constantDays,
            ),
          ),
        );
        await frames(tester);
        expect(
          find.byKey(const ValueKey('half-highlights-equal-work')),
          findsOneWidget,
        );
        expect(textAt(tester, 'half-highlights-equal-work'), contains('71'));
        expect(
          find.byKey(const ValueKey('half-highlights-high-work')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('half-highlights-low-work')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('half-highlights-example-high-work')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('half-highlights-example-low-work')),
          findsNothing,
        );
        await tester.pumpWidget(
          shell(
            PeriodScoreDayHighlights(
              summary: constant,
              area: NineAreaKey.felt,
              details: sevenFixtureDetails,
              dailySummaries: constantDays,
            ),
          ),
        );
        await frames(tester);
        expect(find.byType(HalfMonthDayHighlights), findsNothing);
        expect(tester.takeException(), isNull);
      }
    },
  );

  for (final language in AppLanguage.values) {
    testWidgets(
      '${language.name} real half-month detailed guidance matches existing daily explanations; depth/language/viewport changes add zero jobs',
      (tester) async {
        AppLanguageSettings.current.value = language;
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 844);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final requests = <PeriodSevenDisplayRequest>[];
        final jobs = <_DetailDisplayJob>[];
        final PeriodSevenDisplayStarter starter = (request, _) {
          requests.add(request);
          final job = _DetailDisplayJob();
          jobs.add(job);
          return job;
        };
        Widget view(ReadingDepth depth) => shell(
          MonthHalfOverview(
            startDateJst: DateTime.utc(2026, 1),
            profile: sevenFixtureProfile,
            details: sevenFixtureDetails,
            depth: depth,
            startDisplayJob: starter,
          ),
        );
        await tester.pumpWidget(view(ReadingDepth.simple));
        await frames(tester);
        expect(requests.length, 1);
        final request = requests.single;
        final days = buildPeriodSevenDisplayData(request);
        jobs.single.completion.complete(
          PeriodSevenDisplayResult.fromData(request: request, days: days),
        );
        await frames(tester);
        expect(find.byType(PeriodScoreDayHighlights), findsNothing);
        final trend = tester.widget<MonthHalfDailyTrend>(
          find.byType(MonthHalfDailyTrend),
        );
        final before = jsonEncode(trend.summary.toJson());
        final scores = tester
            .widgetList<FortuneNumber>(find.byType(FortuneNumber))
            .map((badge) => badge.score)
            .toList();
        await tester.pumpWidget(view(ReadingDepth.detailed));
        await frames(tester);
        expect(find.byType(PeriodScoreDayHighlights), findsNWidgets(8));
        expect(
          find.byKey(const ValueKey('half-highlights-felt')),
          findsNothing,
        );
        expect(
          tester
              .widgetList<FortuneNumber>(find.byType(FortuneNumber))
              .map((badge) => badge.score),
          scores,
        );
        for (final area in NineAreaKey.values.where(
          (area) => area != NineAreaKey.felt,
        )) {
          expectRepresentative(
            tester,
            trend.summary,
            trend.dailySummaries,
            area,
            language,
          );
        }
        expect(tester.takeException(), isNull);
        tester.view.physicalSize = const Size(1181, 738);
        await tester.pumpWidget(view(ReadingDepth.detailed));
        await frames(tester);
        expect(tester.takeException(), isNull);
        final otherLanguage = language == AppLanguage.ja
            ? AppLanguage.en
            : AppLanguage.ja;
        AppLanguageSettings.current.value = otherLanguage;
        await frames(tester);
        expectRepresentative(
          tester,
          trend.summary,
          trend.dailySummaries,
          NineAreaKey.work,
          otherLanguage,
        );
        expect(jsonEncode(trend.summary.toJson()), before);
        expect(
          tester
              .widget<MonthHalfDailyTrend>(find.byType(MonthHalfDailyTrend))
              .summary,
          same(trend.summary),
        );
        expect(requests.length, 1);
        expect(requests.single.listedPointCount, 105);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'weekly detailed narrative includes timing without duplicate highlight cards or another calculation',
    (tester) async {
      var calls = 0;
      late WeeklyDailyConsultExportRequest request;
      final job = _DetailWeekJob();
      final WeeklyDailyConsultExportStarter starter = (value, _) {
        calls++;
        request = value;
        return job;
      };
      Widget view(ReadingDepth depth) => shell(
        PeriodSevenOverview(
          mode: LongRangeMode.week,
          startDateJst: DateTime.utc(2026, 12, 28),
          profile: sevenFixtureProfile,
          details: sevenFixtureDetails,
          depth: depth,
          startWeeklyJob: starter,
        ),
      );
      await tester.pumpWidget(view(ReadingDepth.simple));
      await frames(tester);
      job.completion.complete(
        WeeklyDailyConsultExportResult.fromData(
          requestIdentity: request.identity,
          data: fixture.week(
            request,
            score: (index, _) => index % 12 < 6 ? 90 : 50,
            felt: (_) => '普通',
          ),
        ),
      );
      await frames(tester);
      final summary = tester
          .widget<MonthHalfDailyTrend>(find.byType(MonthHalfDailyTrend))
          .summary;
      String expectedNarrative(AppLanguage language) =>
          ForecastExplanation.forPeriod(
            summary: summary,
            area: summary.areas.singleWhere(
              (area) => area.key == NineAreaKey.work,
            ),
            strings: AppStrings(language),
            depth: ReadingDepth.detailed,
            supplement: sevenFixtureDetails,
            dailySamples: summary.predictionsByInstant,
          ).narrativeText;
      final before = jsonEncode(summary.toJson());
      expect(find.byType(PeriodScoreDayHighlights), findsNothing);
      await tester.pumpWidget(view(ReadingDepth.detailed));
      await frames(tester);
      expect(find.byType(PeriodScoreDayHighlights), findsNothing);
      expect(
        textAt(tester, 'period-overview-narrative-work'),
        expectedNarrative(AppLanguage.ja),
      );
      expect(textAt(tester, 'period-overview-narrative-work'), contains('1/3'));
      expect(find.byKey(const ValueKey('half-highlights-felt')), findsNothing);
      expect(find.byType(FortuneNumber), findsNWidgets(8));
      expect(find.byType(FeltFortuneBadge), findsOneWidget);
      expect(jsonEncode(summary.toJson()), before);
      AppLanguageSettings.current.value = AppLanguage.en;
      await frames(tester);
      expect(
        textAt(tester, 'period-overview-narrative-work'),
        expectedNarrative(AppLanguage.en),
      );
      expect(calls, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
