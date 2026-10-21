// The first test uses fresh calculations for a fictional profile and compares
// every forecast with the canonical daily-v4 export. Widget fixtures below are
// deliberately synthetic clock/identity fixtures, not astronomical evidence.
import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pancyo_ai_astrology/app_language.dart';
import 'package:pancyo_ai_astrology/app_language_settings.dart';
import 'package:pancyo_ai_astrology/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'period_seven_test_fixture.dart';

class _HalfJob implements PeriodSevenDisplayOperation {
  final completion = Completer<PeriodSevenDisplayResult>();
  bool cancelled = false;
  @override
  Future<PeriodSevenDisplayResult> get result => completion.future;
  @override
  void cancel() => cancelled = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SyntheticSevenPeriodFixture fixture;
  late HouseSystem oldHouse;
  late AppLanguage oldLanguage;
  late List<_HalfJob> jobs;
  late List<PeriodSevenDisplayRequest> requests;
  late List<void Function(int, int)> progressCallbacks;
  late PeriodSevenDisplayStarter starter;

  setUpAll(() {
    final house = HouseSystemSettings.current.value;
    HouseSystemSettings.current.value = HouseSystem.placidus;
    fixture = SyntheticSevenPeriodFixture();
    HouseSystemSettings.current.value = house;
  });
  setUp(() {
    oldHouse = HouseSystemSettings.current.value;
    oldLanguage = AppLanguageSettings.current.value;
    HouseSystemSettings.current.value = HouseSystem.placidus;
    AppLanguageSettings.current.value = AppLanguage.ja;
    PeriodSevenDisplaySessionCache.clear();
    SharedPreferences.setMockInitialValues({
      'synthetic.saved_prediction': 'retain',
      'astrology.calendar_text_size': 19.0,
    });
    jobs = [];
    requests = [];
    progressCallbacks = [];
    starter = (request, progress) {
      requests.add(request);
      progressCallbacks.add(progress);
      final job = _HalfJob();
      jobs.add(job);
      return job;
    };
  });
  tearDown(() {
    HouseSystemSettings.current.value = oldHouse;
    AppLanguageSettings.current.value = oldLanguage;
    PeriodSevenDisplaySessionCache.clear();
  });

  PeriodSevenDisplayRequest range(DateTime first, DateTime last) =>
      PeriodSevenDisplayRequest(
        startDateJst: first,
        endDateJst: last,
        profile: sevenFixtureProfile,
        details: sevenFixtureDetails,
        requestedHouseSystem: HouseSystem.placidus,
        sourceName: AstrologyDataSources.current.sourceName,
        requireHighPrecision:
            AstrologyDataSources.current.usesHighPrecisionAstroData,
        generatedAt: sevenFixtureGeneratedAt,
      );

  PeriodSevenSummary summarize(
    PeriodSevenDisplayRequest request,
    List<Map<String, Object?>> days,
  ) => PeriodSevenSummary.fromDisplayRange(
    startDateJst: request.startDateJst,
    endDateJst: request.endDateJst,
    days: days,
    profile: request.profile,
    details: request.details,
    requestedHouseSystem: request.requestedHouseSystem,
    sourceName: request.sourceName,
    requireHighPrecision: request.requireHighPrecision,
  );

  String digest(Object data) =>
      sha256.convert(utf8.encode(jsonEncode(data))).toString();

  List<Map<String, Object?>> reread(List<Map<String, Object?>> days) =>
      (jsonDecode(jsonEncode(days)) as List)
          .map((day) => Map<String, Object?>.from(day as Map))
          .toList();

  List<Map<String, Object?>> syntheticDays(PeriodSevenDisplayRequest request) {
    // Preserve the seed's internally valid score audits/felt trace. Only
    // clocks and request metadata are rewritten, explicitly as a UI fixture.
    return [
      for (final plan in request.dayPlans)
        (() {
          final forecasts = fixtureClone(
            Map<String, Object?>.from(
              fixture.seed['intraday_forecasts'] as Map,
            ),
          );
          forecasts['target_date_jst'] = plan.targetDateJst;
          final points = forecasts['points'] as List;
          for (var i = 0; i < 7; i++) {
            final point = points[i] as Map<String, Object?>;
            final clock = plan.points[i];
            point.addAll(clock.toJson());
            final civil = clock.instantUtc.add(const Duration(hours: 9));
            final scoreStart = DateTime.utc(
              civil.year,
              civil.month,
              civil.day,
              -9,
            );
            point['score_day_start_utc'] = scoreStart.toIso8601String();
            point['score_day_end_utc'] = scoreStart
                .add(const Duration(days: 1))
                .toIso8601String();
            final snapshot = fixtureClone(fixtureSnapshot(fixture.seed, 3));
            snapshot['target_date_jst'] = fixtureDate(civil);
            snapshot['calculation_reference_jst'] = clock.instantJst;
            snapshot['uses_high_precision_astro_data'] =
                request.requireHighPrecision;
            snapshot['house_system'] = request.requestedHouseSystem.name;
            snapshot['synthetic_contract_fixture'] = true;
            point['nine_area_forecast'] = snapshot;
          }
          return <String, Object?>{
            'schema': 'pancyo_period_display_day_v1',
            'generated_at': request.generatedAt.toIso8601String(),
            'target_date_jst': plan.targetDateJst,
            'input_identity': request.inputIdentity,
            'time_zone': 'Asia/Tokyo',
            'fixed_utc_offset': '+09:00',
            'calculation_source': <String, Object?>{
              'provider': request.sourceName,
              'provider_uses_high_precision': request.requireHighPrecision,
            },
            'house_calculation': <String, Object?>{
              'requested_system': request.requestedHouseSystem.name,
              'resolved_system': request.requestedHouseSystem.name,
            },
            'intraday_forecasts': forecasts,
            'nine_area_daily': fixtureClone(
              Map<String, Object?>.from(points[3]['nine_area_forecast'] as Map),
            ),
            'synthetic_contract_fixture': true,
          };
        })(),
    ];
  }

  void complete([int? index]) {
    final i = index ?? jobs.length - 1;
    jobs[i].completion.complete(
      PeriodSevenDisplayResult.fromData(
        request: requests[i],
        days: reread(syntheticDays(requests[i])),
      ),
    );
  }

  test(
    'real 15/16-day halves preserve every canonical point/noon, means, felt and explanation after readback',
    () {
      Map<String, Object?>? firstHalfEnd;
      for (final bounds in [(1, 15), (16, 31)]) {
        final request = range(
          DateTime.utc(2026, 1, bounds.$1),
          DateTime.utc(2026, 1, bounds.$2),
        );
        final watch = Stopwatch()..start();
        final display = buildPeriodSevenDisplayData(request);
        final displayMs = watch.elapsedMilliseconds;
        final canonicalBridge = <Map<String, Object?>>[];
        final before = digest(display);
        watch.reset();
        for (var i = 0; i < request.dayCount; i++) {
          final canonical = buildDailyConsultDataV4(request.dailyRequestAt(i));
          expect(
            jsonEncode(display[i]['intraday_forecasts']),
            jsonEncode(canonical['intraday_forecasts']),
          );
          expect(
            jsonEncode(display[i]['nine_area_daily']),
            jsonEncode(canonical['nine_area_daily']),
          );
          canonicalBridge.add({
            ...display[i],
            'intraday_forecasts': canonical['intraday_forecasts'],
            'nine_area_daily': canonical['nine_area_daily'],
          });
        }
        final canonicalMs = watch.elapsedMilliseconds;
        watch.stop();
        final readback = PeriodSevenDisplayResult.fromData(
          request: request,
          days: reread(display),
        );
        final summary = summarize(request, readback.days);
        final canonicalSummary = summarize(request, canonicalBridge);
        expect(summary.dayCount, bounds.$1 == 1 ? 15 : 16);
        expect(summary.listedPointCount, bounds.$1 == 1 ? 105 : 112);
        expect(summary.uniqueInstantCount, bounds.$1 == 1 ? 91 : 97);
        expect(summary.isDisplayRange, true);
        expect(summary.isSingleDay, false);
        expect(
          jsonEncode(summary.toJson()),
          jsonEncode(canonicalSummary.toJson()),
        );
        final unique = <Map<String, Object?>>[
          for (var day = 0; day < request.dayCount; day++)
            for (var point = day == 0 ? 0 : 1; point < 7; point++)
              fixtureSnapshot(display[day], point),
        ];
        expect(unique.length, summary.uniqueInstantCount);
        final feltCounts = <String, int>{};
        for (final snapshot in unique) {
          final felt = (snapshot['areas'] as List).cast<Map>().singleWhere(
            (a) => a['key'] == 'felt',
          );
          final label = felt['predicted_felt_label'] as String;
          feltCounts.update(label, (n) => n + 1, ifAbsent: () => 1);
        }
        for (final count in summary.feltCounts.entries) {
          expect(count.value, feltCounts[count.key] ?? 0);
        }
        for (final area in summary.areas) {
          if (area.key == NineAreaKey.felt) {
            expect(area.score, isNull);
          } else {
            final values = [
              for (final snapshot in unique)
                ((snapshot['areas'] as List).cast<Map>().singleWhere(
                          (a) => a['key'] == area.key.name,
                        )['score']
                        as num)
                    .toInt(),
            ];
            expect(
              area.score,
              (values.reduce((a, b) => a + b) / values.length).round(),
            );
          }
          for (final language in AppLanguage.values) {
            for (final depth in ReadingDepth.values) {
              Object explanation(PeriodSevenSummary value) =>
                  ForecastExplanation.forPeriod(
                    summary: value,
                    area: value.areas.singleWhere((a) => a.key == area.key),
                    strings: AppStrings(language),
                    depth: depth,
                    supplement: request.details,
                    dailySamples: value.predictionsByInstant,
                  ).toJson();
              expect(
                jsonEncode(explanation(summary)),
                jsonEncode(explanation(canonicalSummary)),
              );
            }
          }
        }
        for (var i = 0; i < request.dayCount; i++) {
          final day = summary.daySummaryAt(i);
          expect(day.dayCount, 1);
          expect(day.listedPointCount, 7);
          expect(day.uniqueInstantCount, 7);
          expect(day.isSingleDay, true);
          for (final area in day.areas.where(
            (a) => a.key != NineAreaKey.felt,
          )) {
            final values = [
              for (var p = 0; p < 7; p++)
                ((fixtureSnapshot(display[i], p)['areas'] as List)
                            .cast<Map>()
                            .singleWhere(
                              (a) => a['key'] == area.key.name,
                            )['score']
                        as num)
                    .toInt(),
            ];
            expect(area.score, (values.reduce((a, b) => a + b) / 7).round());
          }
          for (final entry in day.predictionsByInstant.entries) {
            expect(entry.value, summary.predictionsByInstant[entry.key]);
          }
        }
        if (firstHalfEnd != null) {
          expect(
            jsonEncode(firstHalfEnd),
            jsonEncode(fixtureSnapshot(display.first, 0)),
          );
        }
        firstHalfEnd = fixtureSnapshot(display.last, 6);
        expect(digest(display), before);
        print(
          'HALF_DISPLAY_MEASUREMENT ${jsonEncode({'subject': 'fictional fixture only', 'provider': request.sourceName, 'high_precision': request.requireHighPrecision, 'days': request.dayCount, 'listed': request.listedPointCount, 'unique': request.uniqueInstantCount, 'display_ms': displayMs, 'canonical_ms': canonicalMs, 'order': 'display first, canonical second; host run, no Android speed claim'})}',
        );
      }
    },
  );

  test(
    'half ranges cover 28/29/30/31-day months and reject missing/duplicate/full-month substitution',
    () {
      for (final month in [
        DateTime.utc(2026, 2),
        DateTime.utc(2028, 2),
        DateTime.utc(2026, 4),
        DateTime.utc(2026, 1),
      ]) {
        final end = DateTime.utc(month.year, month.month + 1, 0);
        for (final first in [1, 16]) {
          final request = range(
            DateTime.utc(month.year, month.month, first),
            first == 1 ? DateTime.utc(month.year, month.month, 15) : end,
          );
          final days = syntheticDays(request);
          final summary = summarize(request, days);
          final count = first == 1 ? 15 : end.day - 15;
          expect(summary.dayCount, count);
          expect(summary.listedPointCount, count * 7);
          expect(summary.uniqueInstantCount, count * 6 + 1);
          expect(summary.startDateJst, fixtureDate(request.startDateJst));
          expect(summary.endDateJst, fixtureDate(request.endDateJst));
          expect(
            summary.dates.last,
            DateTime.utc(
              request.endDateJst.year,
              request.endDateJst.month,
              request.endDateJst.day + 1,
              -9,
            ),
          );
          expect(
            () => summarize(request, days.take(days.length - 1).toList()),
            throwsA(anything),
          );
          expect(
            () => summarize(request, [days.first, days.first, ...days.skip(2)]),
            throwsA(anything),
          );
          expect(() => summary.daySummaryAt(-1), throwsA(anything));
          expect(() => summary.daySummaryAt(count), throwsA(anything));
          expect(
            () => PeriodSevenSummary.fromDisplayDays(
              mode: LongRangeMode.month,
              startDateJst: month,
              days: days,
              profile: request.profile,
              details: request.details,
              requestedHouseSystem: request.requestedHouseSystem,
              sourceName: request.sourceName,
              requireHighPrecision: request.requireHighPrecision,
            ),
            throwsA(anything),
          );
        }
      }
      final invalid = range(
        DateTime.utc(2026, 1, 2),
        DateTime.utc(2026, 1, 15),
      );
      expect(
        () => summarize(invalid, syntheticDays(invalid)),
        throwsA(anything),
      );
    },
  );

  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pump(
    WidgetTester tester, {
    DateTime? month,
    AstroProfile profile = sevenFixtureProfile,
    UserProfileDetails details = sevenFixtureDetails,
    ReadingDepth depth = ReadingDepth.simple,
    bool active = true,
    PeriodSevenDisplayStarter? useStarter,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: AppLanguageScope(
          child: Scaffold(
            body: SingleChildScrollView(
              child: MonthHalfOverview(
                startDateJst: month ?? DateTime.utc(2026, 1),
                profile: profile,
                details: details,
                depth: depth,
                active: active,
                startDisplayJob: useStarter ?? starter,
              ),
            ),
          ),
        ),
      ),
    );
    await frames(tester);
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await frames(tester);
  }

  MonthHalfDailyTrend trend(WidgetTester tester) =>
      tester.widget<MonthHalfDailyTrend>(find.byType(MonthHalfDailyTrend));

  void expectCardsAndGraph(WidgetTester tester) {
    final shown = trend(tester);
    expect(shown.dailySummaries.length, shown.summary.dayCount);
    expect(find.byType(FortuneNumber), findsNWidgets(8));
    expect(find.byType(FeltFortuneBadge), findsOneWidget);
    for (final area in shown.summary.areas) {
      expect(
        find.byKey(ValueKey('period-overview-card-${area.key.name}')),
        findsOneWidget,
      );
      if (area.key != NineAreaKey.felt) {
        final badge = tester.widget<FortuneNumber>(
          find.descendant(
            of: find.byKey(ValueKey('period-overview-value-${area.key.name}')),
            matching: find.byType(FortuneNumber),
          ),
        );
        expect(badge.score, area.score);
      } else {
        expect(area.score, isNull);
        expect(
          tester.widget<FeltFortuneBadge>(find.byType(FeltFortuneBadge)).label,
          shown.summary.feltLabel,
        );
      }
    }
    final painter =
        tester
                .widget<CustomPaint>(
                  find.byKey(const ValueKey('half-month-chart')),
                )
                .painter!
            as FortuneFlowPainter;
    expect(painter.series.length, 5);
    for (var i = 0; i < 5; i++) {
      expect(
        painter.series[i].color,
        PeriodSevenGroupedTrendData.mainColors[i],
      );
      expect(painter.series[i].values, [
        for (final day in shown.dailySummaries)
          day.areas
              .singleWhere(
                (a) => a.key == PeriodSevenGroupedTrendData.mainKeys[i],
              )
              .score,
      ]);
    }
    final extra = tester.widget<AdditionalFortuneTrendChart>(
      find.byKey(const ValueKey('half-month-additional')),
    );
    expect(extra.dataIdentity, same(shown.summary));
    final data = extra.dataFor();
    expect(data.series.length, 3);
    for (var i = 0; i < 3; i++) {
      expect(data.series[i].values, [
        for (final day in shown.dailySummaries)
          day.areas
              .singleWhere(
                (a) => a.key == AdditionalFortuneTrendData.numericKeys[i],
              )
              .score,
      ]);
    }
    expect(
      data.felt.map((point) => point.label),
      shown.dailySummaries.map((day) => day.feltDisplayLabel),
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('half-month-graph'))).dy,
      lessThan(
        tester
            .getTopLeft(
              find.byKey(const ValueKey('period-overview-card-overall')),
            )
            .dy,
      ),
    );
    expect(find.byType(PeriodSevenTrend), findsNothing);
    expect(find.byType(DropdownButton<String>), findsNothing);
    expect(find.textContaining('JSON'), findsNothing);
  }

  testWidgets(
    'only selected half runs: 105/112 points, same data produces nine circles and 5+3 graph, cached switch runs zero jobs',
    (tester) async {
      await pump(tester);
      expect(requests.length, 1);
      expect(requests.single.startDateJst, DateTime.utc(2026, 1));
      expect(requests.single.endDateJst, DateTime.utc(2026, 1, 15));
      expect(requests.single.listedPointCount, 105);
      complete();
      await frames(tester);
      expectCardsAndGraph(tester);
      final first = trend(tester).summary;
      await tap(tester, 'additional-trend-toggle');
      expect(
        find.byKey(const ValueKey('additional-trend-content')),
        findsOneWidget,
      );
      expect(requests.length, 1);
      await tap(tester, 'half-month-second');
      expect(requests.length, 2);
      expect(find.byType(FortuneNumber), findsNothing);
      expect(requests.last.startDateJst, DateTime.utc(2026, 1, 16));
      expect(requests.last.endDateJst, DateTime.utc(2026, 1, 31));
      expect(requests.last.listedPointCount, 112);
      complete();
      await frames(tester);
      expectCardsAndGraph(tester);
      final second = trend(tester).summary;
      await tap(tester, 'half-month-first');
      expect(trend(tester).summary, same(first));
      await tap(tester, 'half-month-second');
      expect(trend(tester).summary, same(second));
      expect(requests.length, 2);
      expect(
        requests.fold<int>(0, (sum, request) => sum + request.listedPointCount),
        217,
      );
      // Work-count comparison only, not a benchmark or implied background job.
      expect(31 * 7 + (365 - 31) * 7, 2555);
      expect((365 - 31) * 7, 2338);
      expect(requests.first.listedPointCount, lessThan(2555));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('synthetic.saved_prediction'), 'retain');
      expect(prefs.getDouble('astrology.calendar_text_size'), 19.0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cancel, late result and retry never show incomplete or cancelled half as completed',
    (tester) async {
      await pump(tester);
      progressCallbacks.single(21, 105);
      await frames(tester);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(const ValueKey('half-month-progress')),
            )
            .value,
        0.2,
      );
      await tap(tester, 'half-month-cancel');
      expect(jobs.first.cancelled, true);
      complete(0);
      await frames(tester);
      expect(find.byType(MonthHalfDailyTrend), findsNothing);
      expect(find.byType(FortuneNumber), findsNothing);
      await tap(tester, 'half-month-retry');
      expect(requests.length, 2);
      complete(1);
      await frames(tester);
      final first = trend(tester).summary;
      await tap(tester, 'half-month-second');
      expect(requests.length, 3);
      await tap(tester, 'half-month-first');
      expect(jobs[2].cancelled, true);
      complete(2);
      await frames(tester);
      expect(trend(tester).summary, same(first));
      await tap(tester, 'half-month-second');
      expect(
        requests.length,
        4,
        reason: 'Cancelled late data must not enter the second-half cache.',
      );
      complete(3);
      await frames(tester);
      expect(trend(tester).summary.dayCount, 16);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'worker error is explicit and retry recomputes only the selected half',
    (tester) async {
      await pump(tester);
      jobs.first.completion.completeError(
        StateError('Synthetic worker failure'),
      );
      await frames(tester);
      expect(find.byKey(const ValueKey('half-month-retry')), findsOneWidget);
      expect(find.byType(FortuneNumber), findsNothing);
      await tap(tester, 'half-month-retry');
      expect(requests.length, 2);
      expect(requests.last.endDateJst.day, 15);
      complete();
      await frames(tester);
      expectCardsAndGraph(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'profile, details, month and house invalidate two-half cache and reject stale callbacks',
    (tester) async {
      await pump(tester);
      complete(0);
      await frames(tester);
      await tap(tester, 'half-month-second');
      final alternate = sevenFixtureProfile.copyWith(
        name: 'Another fictional half-test profile',
      );
      await pump(tester, profile: alternate);
      expect(jobs[1].cancelled, true);
      expect(requests.length, 3);
      complete(1);
      progressCallbacks[1](112, 112);
      await frames(tester);
      expect(find.byType(FortuneNumber), findsNothing);
      complete(2);
      await frames(tester);
      await tap(tester, 'half-month-first');
      expect(
        requests.length,
        4,
        reason: 'The old profile first-half cache must not survive.',
      );
      complete(3);
      await frames(tester);
      const otherDetails = UserProfileDetails(
        birthTime: '',
        birthPlace: '',
        personality: '',
        concerns: 'Synthetic changed concerns',
        readingStyle: '',
      );
      await pump(tester, profile: alternate, details: otherDetails);
      expect(requests.length, 5);
      await pump(
        tester,
        month: DateTime.utc(2028, 2),
        profile: alternate,
        details: otherDetails,
      );
      expect(jobs[4].cancelled, true);
      expect(requests.length, 6);
      complete(4);
      await frames(tester);
      expect(find.byType(FortuneNumber), findsNothing);
      complete(5);
      await frames(tester);
      await tap(tester, 'half-month-second');
      expect(requests.last.dayCount, 14);
      expect(requests.last.listedPointCount, 98);
      complete(6);
      await frames(tester);
      HouseSystemSettings.current.value = HouseSystem.wholeSign;
      await frames(tester);
      expect(requests.length, 8);
      expect(requests.last.requestedHouseSystem, HouseSystem.wholeSign);
      expect(find.byType(FortuneNumber), findsNothing);
      complete(7);
      await frames(tester);
      expect(trend(tester).summary.requestedHouseSystem, HouseSystem.wholeSign);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'inactive, changed worker and disposal cancel jobs and prevent late UI updates',
    (tester) async {
      await pump(tester);
      await pump(tester, active: false);
      expect(jobs[0].cancelled, true);
      complete(0);
      await frames(tester);
      expect(find.byType(MonthHalfDailyTrend), findsNothing);
      await pump(tester);
      expect(requests.length, 2);
      final PeriodSevenDisplayStarter anotherStarter = (request, progress) =>
          starter(request, progress);
      await pump(tester, useStarter: anotherStarter);
      expect(jobs[1].cancelled, true);
      expect(requests.length, 3);
      complete(1);
      await frames(tester);
      expect(find.byType(FortuneNumber), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(jobs[2].cancelled, true);
      complete(2);
      await frames(tester);
      expect(tester.takeException(), isNull);
    },
  );

  for (final language in AppLanguage.values) {
    testWidgets(
      '${language.name} phone/tablet preserves circles and data across depth, with graph above cards and no overflow',
      (tester) async {
        AppLanguageSettings.current.value = language;
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 844);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await pump(tester);
        complete();
        await frames(tester);
        expectCardsAndGraph(tester);
        final summary = trend(tester).summary;
        final simpleText = tester
            .widget<Text>(
              find.byKey(const ValueKey('period-overview-narrative-overall')),
            )
            .data;
        await tap(tester, 'additional-trend-toggle');
        expect(find.byType(AdditionalFortuneTrendView), findsOneWidget);
        expect(tester.takeException(), isNull);
        tester.view.physicalSize = const Size(1181, 738);
        await pump(tester, depth: ReadingDepth.detailed);
        expect(trend(tester).summary, same(summary));
        expectCardsAndGraph(tester);
        final detailedText = tester
            .widget<Text>(
              find.byKey(const ValueKey('period-overview-narrative-overall')),
            )
            .data;
        expect(detailedText, isNot(simpleText));
        expect(requests.length, 1);
        await tap(tester, 'half-month-settings');
        expect(find.textContaining('UTC+09:00'), findsWidgets);
        expect(tester.takeException(), isNull);
        AppLanguageSettings.current.value = language == AppLanguage.ja
            ? AppLanguage.en
            : AppLanguage.ja;
        await frames(tester);
        expect(trend(tester).summary, same(summary));
        expect(requests.length, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
