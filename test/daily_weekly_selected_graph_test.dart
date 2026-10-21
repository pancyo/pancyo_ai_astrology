import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pancyo_ai_astrology/app_language.dart';
import 'package:pancyo_ai_astrology/app_language_settings.dart';
import 'package:pancyo_ai_astrology/main.dart';

import 'period_seven_test_fixture.dart';

class _Positions implements DailyStarTimelineOperation {
  final completion = Completer<DailyStarTimelineResult>();
  bool cancelled = false;
  @override
  Future<DailyStarTimelineResult> get result => completion.future;
  @override
  void cancel() => cancelled = true;
}

class _Scores implements DailyTimepointForecastOperation {
  final completion = Completer<DailyTimepointForecastResult>();
  bool cancelled = false;
  @override
  Future<DailyTimepointForecastResult> get result => completion.future;
  @override
  void cancel() => cancelled = true;
}

class _Week implements WeeklyDailyConsultExportOperation {
  final completion = Completer<WeeklyDailyConsultExportResult>();
  @override
  Future<WeeklyDailyConsultExportResult> get result => completion.future;
  @override
  void cancel() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SyntheticSevenPeriodFixture fixture;
  late HoroscopeReadingContext noon;
  late DailyStarTimelineRequest timeline;
  late DailyStarTimelineResult positions;
  late HouseSystem oldHouse;
  late AppLanguage oldLanguage;
  final date = DateTime.utc(2026, 12, 28, 3);

  setUpAll(() {
    final previous = HouseSystemSettings.current.value;
    HouseSystemSettings.current.value = HouseSystem.placidus;
    fixture = SyntheticSevenPeriodFixture();
    noon = const AstrologyEngine().buildPreviewContext(
      profile: sevenFixtureProfile,
      date: date,
    );
    timeline = DailyStarTimelineRequest.fromContext(
      date: date,
      contextData: noon,
      profile: sevenFixtureProfile,
    );
    positions = calculateDailyStarTimeline(timeline);
    HouseSystemSettings.current.value = previous;
  });
  setUp(() {
    oldHouse = HouseSystemSettings.current.value;
    oldLanguage = AppLanguageSettings.current.value;
    HouseSystemSettings.current.value = HouseSystem.placidus;
    AppLanguageSettings.current.value = AppLanguage.ja;
    PeriodSevenDisplaySessionCache.clear();
  });
  tearDown(() {
    HouseSystemSettings.current.value = oldHouse;
    AppLanguageSettings.current.value = oldLanguage;
    PeriodSevenDisplaySessionCache.clear();
  });

  Map<String, Object?> forecasts() => Map<String, Object?>.from(
    jsonDecode(jsonEncode(fixture.seed['intraday_forecasts'])) as Map,
  );
  DailyTimepointForecastResult result(
    String identity, {
    Map<String, Object?>? values,
  }) => DailyTimepointForecastResult.checked(
    scoreIdentity: identity,
    request: timeline,
    positions: positions,
    forecasts: values ?? forecasts(),
    elapsedMilliseconds: 1,
    workerName: 'test',
  );
  Widget shell(Widget child, {double scale = 1}) => MaterialApp(
    theme: ThemeData.dark(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: AppLanguageScope(
      child: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  test(
    'daily graph keeps all seven exact scores, noon, colors and categorical felt',
    () {
      final raw = forecasts();
      final before = jsonEncode(raw);
      final data = DailySevenPointTrendData.fromResult(
        request: timeline,
        result: result('display', values: raw),
        noonContext: noon,
      );
      expect(data.labels, [
        '00:00',
        '04:00',
        '08:00',
        '12:00',
        '16:00',
        '20:00',
        '24:00',
      ]);
      final points = raw['points'] as List;
      List<int> scores(NineAreaKey key) => [
        for (final point in points)
          (point['nine_area_forecast']['areas'] as List).singleWhere(
                (area) => area['key'] == key.name,
              )['score']
              as int,
      ];
      for (var i = 0; i < 5; i++) {
        expect(
          data.series[i].values,
          scores(PeriodSevenGroupedTrendData.mainKeys[i]),
        );
        expect(data.series[i].color, PeriodSevenGroupedTrendData.mainColors[i]);
      }
      for (var i = 0; i < 3; i++) {
        expect(
          data.additional.series[i].values,
          scores(AdditionalFortuneTrendData.numericKeys[i]),
        );
        expect(
          data.additional.series[i].color,
          AdditionalFortuneTrendData.colors[i],
        );
      }
      expect(data.additional.felt.map((point) => point.label), [
        for (final point in points)
          (point['nine_area_forecast']['areas'] as List).singleWhere(
            (area) => area['key'] == 'felt',
          )['predicted_felt_label'],
      ]);
      expect(jsonEncode(raw), before);
      expect(
        timeline.plan.points.last.instantUtc,
        timeline.plan.dayStartUtc.add(const Duration(days: 1)),
      );
    },
  );

  test('daily graph rejects missing numeric points and a changed noon', () {
    for (final index in [0, 3]) {
      final raw = forecasts();
      final areas =
          (raw['points'] as List)[index]['nine_area_forecast']['areas'] as List;
      final overall =
          areas.singleWhere((area) => area['key'] == 'overall') as Map;
      overall['score'] = index == 0 ? null : (overall['score'] as int) + 1;
      if (index == 0) overall['score_breakdown'] = null;
      final value = result('display', values: raw);
      expect(
        () => DailySevenPointTrendData.fromResult(
          request: timeline,
          result: value,
          noonContext: noon,
        ),
        throwsStateError,
      );
    }
  });

  testWidgets(
    'daily graph starts one worker pair and detail mode switching reuses all results',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final positionJob = _Positions();
      final scoreJob = _Scores();
      var positionCalls = 0, scoreCalls = 0;
      String? identity;
      final DailyStarTimelineStarter startPositions = (request, progress) {
        positionCalls++;
        return positionJob;
      };
      final DailyTimepointForecastStarter startScores =
          (id, request, timeline, positions, progress) {
            scoreCalls++;
            identity = id;
            return scoreJob;
          };
      var showDetails = false;
      Widget card() => DailyTimeFlowCard(
        date: date,
        contextData: noon,
        profile: sevenFixtureProfile,
        details: sevenFixtureDetails,
        showTrend: true,
        showDetails: showDetails,
        startJob: startPositions,
        startForecastJob: startScores,
        nowUtc: () => DateTime.utc(2026, 12, 27),
      );
      await tester.pumpWidget(shell(card(), scale: 2));
      await frames(tester);
      expect(positionCalls, 1);
      positionJob.completion.complete(positions);
      await frames(tester);
      expect(scoreCalls, 1);
      scoreJob.completion.complete(result(identity!));
      await frames(tester);
      final painter =
          tester
                  .widget<CustomPaint>(
                    find.byKey(const ValueKey('daily-seven-point-chart')),
                  )
                  .painter
              as FortuneFlowPainter;
      expect(painter.labels, hasLength(7));
      expect(painter.series, hasLength(5));
      expect(painter.textScaler.scale(16), 32);
      await tester.pumpWidget(shell(card(), scale: 2));
      await frames(tester);
      expect(
        find.byKey(const ValueKey('daily-seven-point-details')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('daily-seven-point-chart')),
        findsOneWidget,
      );
      showDetails = true;
      await tester.pumpWidget(shell(card(), scale: 2));
      await frames(tester);
      final detail = find.byKey(const ValueKey('daily-seven-point-details'));
      await tester.ensureVisible(detail);
      await tester.tap(detail);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('daily-star-timeline')), findsOneWidget);
      expect(positionCalls, 1);
      expect(scoreCalls, 1);
      showDetails = false;
      await tester.pumpWidget(shell(card(), scale: 2));
      await frames(tester);
      expect(
        find.byKey(const ValueKey('daily-seven-point-details')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('daily-seven-point-chart')),
        findsOneWidget,
      );
      expect(positionCalls, 1);
      expect(scoreCalls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'daily timeline showShare false hides sharing and restoring it keeps existing seven-point workers',
    (tester) async {
      final positionJob = _Positions();
      final scoreJob = _Scores();
      var positionCalls = 0, scoreCalls = 0;
      String? identity;
      var showShare = false;
      late StateSetter rebuild;
      final raw = forecasts();
      final before = jsonEncode(raw);
      final DailyStarTimelineStarter startPositions = (request, progress) {
        positionCalls++;
        return positionJob;
      };
      final DailyTimepointForecastStarter startScores =
          (id, request, timeline, positions, progress) {
            scoreCalls++;
            identity = id;
            return scoreJob;
          };
      await tester.pumpWidget(
        shell(
          StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return DailyTimeFlowCard(
                date: date,
                contextData: noon,
                profile: sevenFixtureProfile,
                details: sevenFixtureDetails,
                showTrend: true,
                showShare: showShare,
                startJob: startPositions,
                startForecastJob: startScores,
                nowUtc: () => DateTime.utc(2026, 12, 27),
              );
            },
          ),
        ),
      );
      await frames(tester);
      positionJob.completion.complete(positions);
      await frames(tester);
      scoreJob.completion.complete(result(identity!, values: raw));
      await frames(tester);
      expect(
        find.byKey(const ValueKey('daily-seven-point-chart')),
        findsOneWidget,
      );
      final detail = find.byKey(const ValueKey('daily-seven-point-details'));
      await tester.ensureVisible(detail);
      await tester.tap(detail);
      await tester.pumpAndSettle();
      for (final key in [
        'daily-star-share',
        'daily-star-share-retry',
        'daily-star-share-status',
      ]) {
        expect(find.byKey(ValueKey(key)), findsNothing);
      }
      rebuild(() => showShare = true);
      await frames(tester);
      final share = find.byKey(const ValueKey('daily-star-share'));
      expect(share, findsOneWidget);
      final staleShare = tester.widget<OutlinedButton>(share).onPressed!;
      rebuild(() => showShare = false);
      await frames(tester);
      // A callback retained by a prior frame must also respect the new mode.
      staleShare();
      await frames(tester);
      expect(find.byType(DailyStarTimelineShareSheet), findsNothing);
      expect(find.byKey(const ValueKey('daily-star-share')), findsNothing);
      expect(
        find.byKey(const ValueKey('daily-seven-point-chart')),
        findsOneWidget,
      );
      expect(positionCalls, 1);
      expect(scoreCalls, 1);
      expect(positionJob.cancelled, false);
      expect(scoreJob.cancelled, false);
      expect(jsonEncode(raw), before);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'daily timeline sharing disabled by mode change withdraws pending share before late scores and re-enable',
    (tester) async {
      final positionJob = _Positions();
      final scoreJob = _Scores();
      var showShare = true;
      late StateSetter rebuild;
      var positionCalls = 0, scoreCalls = 0;
      String? identity;
      final DailyStarTimelineStarter startPositions = (request, progress) {
        positionCalls++;
        return positionJob;
      };
      final DailyTimepointForecastStarter startScores =
          (id, request, timeline, positions, progress) {
            scoreCalls++;
            identity = id;
            return scoreJob;
          };
      await tester.pumpWidget(
        shell(
          StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return DailyTimeFlowCard(
                date: date,
                contextData: noon,
                profile: sevenFixtureProfile,
                details: sevenFixtureDetails,
                showTrend: true,
                showShare: showShare,
                startJob: startPositions,
                startForecastJob: startScores,
                nowUtc: () => DateTime.utc(2026, 12, 27),
              );
            },
          ),
        ),
      );
      await frames(tester);
      positionJob.completion.complete(positions);
      await frames(tester);
      final detail = find.byKey(const ValueKey('daily-seven-point-details'));
      await tester.ensureVisible(detail);
      await tester.tap(detail);
      await frames(tester);
      final share = find.byKey(const ValueKey('daily-star-share'));
      // Finish the expansion before measuring its bottom-most button. The
      // pending score progress indicator prevents using pumpAndSettle here.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      await Scrollable.ensureVisible(tester.element(share), alignment: 0.5);
      await tester.pump();
      expect(share.hitTestable(), findsOneWidget);
      await tester.tap(share);
      await frames(tester);
      expect(
        find.byKey(const ValueKey('daily-star-share-status')),
        findsOneWidget,
      );
      rebuild(() => showShare = false);
      await frames(tester);
      expect(find.byKey(const ValueKey('daily-star-share')), findsNothing);
      expect(
        find.byKey(const ValueKey('daily-star-share-status')),
        findsNothing,
      );
      expect(positionJob.cancelled, false);
      expect(scoreJob.cancelled, false);
      // Return to Simple before completion: the withdrawn intent stays gone.
      rebuild(() => showShare = true);
      await frames(tester);
      expect(
        find.byKey(const ValueKey('daily-star-share-status')),
        findsNothing,
      );
      scoreJob.completion.complete(result(identity!));
      await frames(tester);
      expect(
        find.byKey(const ValueKey('daily-seven-point-chart')),
        findsOneWidget,
      );
      expect(find.byType(DailyStarTimelineShareSheet), findsNothing);
      expect(find.byKey(const ValueKey('daily-star-share')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('daily-star-share-status')),
        findsNothing,
      );
      expect(positionCalls, 1);
      expect(scoreCalls, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'disabled daily timeline sharing clears failed-share retry and status without restarting calculation',
    (tester) async {
      final positionJob = _Positions();
      final scoreJob = _Scores();
      var showShare = true;
      late StateSetter rebuild;
      var scoreCalls = 0;
      final DailyStarTimelineStarter startPositions = (request, progress) =>
          positionJob;
      final DailyTimepointForecastStarter startScores =
          (id, request, timeline, positions, progress) {
            scoreCalls++;
            return scoreJob;
          };
      await tester.pumpWidget(
        shell(
          StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return DailyTimeFlowCard(
                date: date,
                contextData: noon,
                profile: sevenFixtureProfile,
                details: sevenFixtureDetails,
                showShare: showShare,
                startJob: startPositions,
                startForecastJob: startScores,
                nowUtc: () => DateTime.utc(2026, 12, 27),
              );
            },
          ),
        ),
      );
      final load = find.byKey(const ValueKey('daily-star-load'));
      await tester.ensureVisible(load);
      await tester.tap(load);
      await frames(tester);
      positionJob.completion.complete(positions);
      await frames(tester);
      final share = find.byKey(const ValueKey('daily-star-share'));
      await tester.ensureVisible(share);
      await tester.tap(share);
      await frames(tester);
      scoreJob.completion.completeError(StateError('Synthetic score failure'));
      await frames(tester);
      expect(
        find.byKey(const ValueKey('daily-star-share-retry')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('daily-star-share-status')),
        findsOneWidget,
      );
      rebuild(() => showShare = false);
      await frames(tester);
      for (final key in [
        'daily-star-share',
        'daily-star-share-retry',
        'daily-star-share-status',
      ]) {
        expect(find.byKey(ValueKey(key)), findsNothing);
      }
      rebuild(() => showShare = true);
      await frames(tester);
      expect(find.byKey(const ValueKey('daily-star-share')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('daily-star-share-retry')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('daily-star-share-status')),
        findsNothing,
      );
      expect(scoreCalls, 1);
      expect(find.byType(DailyStarTimelineShareSheet), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'cancelled daily scores cannot reappear and explicit retry reuses positions',
    (tester) async {
      final positionJob = _Positions();
      final scoreJobs = <_Scores>[];
      final identities = <String>[];
      await tester.pumpWidget(
        shell(
          DailyTimeFlowCard(
            date: date,
            contextData: noon,
            profile: sevenFixtureProfile,
            details: sevenFixtureDetails,
            showTrend: true,
            startJob: (request, progress) => positionJob,
            startForecastJob:
                (identity, request, timeline, positions, progress) {
                  identities.add(identity);
                  final job = _Scores();
                  scoreJobs.add(job);
                  return job;
                },
          ),
        ),
      );
      await frames(tester);
      positionJob.completion.complete(positions);
      await frames(tester);
      await tester.tap(find.byKey(const ValueKey('daily-seven-point-cancel')));
      await frames(tester);
      expect(scoreJobs.single.cancelled, true);
      scoreJobs.single.completion.complete(result(identities.single));
      await frames(tester);
      expect(
        find.byKey(const ValueKey('daily-seven-point-chart')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('daily-seven-point-retry')));
      await frames(tester);
      expect(scoreJobs, hasLength(2));
      scoreJobs.last.completion.complete(result(identities.last));
      await frames(tester);
      expect(
        find.byKey(const ValueKey('daily-seven-point-chart')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'changing the date cancels old work and ignores its delayed score result',
    (tester) async {
      final positionJobs = <_Positions>[];
      final scoreJobs = <_Scores>[];
      final identities = <String>[];
      final DailyStarTimelineStarter startPositions = (request, progress) {
        final job = _Positions();
        positionJobs.add(job);
        return job;
      };
      final DailyTimepointForecastStarter startScores =
          (identity, request, timeline, positions, progress) {
            identities.add(identity);
            final job = _Scores();
            scoreJobs.add(job);
            return job;
          };
      Widget card(DateTime selected, HoroscopeReadingContext context) =>
          DailyTimeFlowCard(
            date: selected,
            contextData: context,
            profile: sevenFixtureProfile,
            details: sevenFixtureDetails,
            showTrend: true,
            startJob: startPositions,
            startForecastJob: startScores,
          );
      await tester.pumpWidget(shell(card(date, noon)));
      await frames(tester);
      positionJobs.single.completion.complete(positions);
      await frames(tester);
      final nextDate = date.add(const Duration(days: 1));
      final nextNoon = const AstrologyEngine().buildPreviewContext(
        profile: sevenFixtureProfile,
        date: nextDate,
      );
      await tester.pumpWidget(shell(card(nextDate, nextNoon)));
      await frames(tester);
      expect(scoreJobs.single.cancelled, true);
      expect(positionJobs, hasLength(2));
      scoreJobs.single.completion.complete(result(identities.single));
      await frames(tester);
      expect(
        find.byKey(const ValueKey('daily-seven-point-chart')),
        findsNothing,
      );
      expect(scoreJobs, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
      expect(positionJobs.last.cancelled, true);
    },
  );

  testWidgets(
    'selected week has seven daily means, all nine cards and no comparison-week job',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final requests = <WeeklyDailyConsultExportRequest>[];
      final jobs = <_Week>[];
      await tester.pumpWidget(
        shell(
          PeriodSevenOverview(
            mode: LongRangeMode.week,
            startDateJst: DateTime.utc(2026, 12, 28),
            profile: sevenFixtureProfile,
            details: sevenFixtureDetails,
            depth: ReadingDepth.detailed,
            startWeeklyJob: (request, progress) {
              requests.add(request);
              final job = _Week();
              jobs.add(job);
              return job;
            },
          ),
          scale: 2,
        ),
      );
      await frames(tester);
      final raw = fixture.week(requests.single);
      jobs.single.completion.complete(
        WeeklyDailyConsultExportResult.fromData(
          requestIdentity: requests.single.identity,
          data: raw,
        ),
      );
      await frames(tester);
      expect(requests, hasLength(1));
      expect(find.byType(PeriodSevenTrend), findsNothing);
      final trend = tester.widget<MonthHalfDailyTrend>(
        find.byType(MonthHalfDailyTrend),
      );
      expect(trend.weekly, true);
      expect(trend.dailySummaries, hasLength(7));
      final painter =
          tester
                  .widget<CustomPaint>(
                    find.byKey(const ValueKey('weekly-daily-chart')),
                  )
                  .painter
              as FortuneFlowPainter;
      expect(painter.labels, hasLength(7));
      expect(painter.textScaler.scale(16), 32);
      for (var i = 0; i < 5; i++) {
        expect(painter.series[i].values, [
          for (final day in trend.dailySummaries)
            day.areas
                .singleWhere(
                  (area) => area.key == PeriodSevenGroupedTrendData.mainKeys[i],
                )
                .score,
        ]);
      }
      expect(find.byType(FortuneNumber), findsNWidgets(8));
      final overallBadge = tester.widget<FortuneNumber>(
        find.descendant(
          of: find.byKey(const ValueKey('period-overview-value-overall')),
          matching: find.byType(FortuneNumber),
        ),
      );
      expect(overallBadge.fixedSize, dailyOverallFortuneBadgeSize * 2);
      expect(find.byKey(const ValueKey('weekly-main-five')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('weekly-additional-four')),
        findsOneWidget,
      );
      for (final key in NineAreaKey.values) {
        expect(
          find.byKey(ValueKey('period-overview-card-${key.name}')),
          findsOneWidget,
        );
        final shown = tester
            .widget<Text>(
              find.byKey(ValueKey('period-overview-narrative-${key.name}')),
            )
            .data!;
        final expected = ForecastExplanation.forPeriod(
          summary: trend.summary,
          area: trend.summary.areas.singleWhere((area) => area.key == key),
          strings: const AppStrings(AppLanguage.ja),
          depth: ReadingDepth.detailed,
          supplement: sevenFixtureDetails,
          dailySamples: trend.summary.predictionsByInstant,
        ).narrativeText;
        expect(shown, expected);
        expect(shown, isNot(contains('試作値を集計')));
        if (key != NineAreaKey.felt) expect(shown.split('\n\n'), hasLength(3));
      }
      expect(find.byType(PeriodScoreDayHighlights), findsNothing);
      expect(trend.summary.uniqueInstantCount, 43);
      expect(requests, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
}
