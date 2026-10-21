// Deliberately synthetic contract fixtures: this file tests session caching,
// cancellation and identity isolation, not astronomical accuracy.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pancyo_ai_astrology/app_language.dart';
import 'package:pancyo_ai_astrology/app_language_settings.dart';
import 'package:pancyo_ai_astrology/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'period_seven_test_fixture.dart';

class _DisplayJob implements PeriodSevenDisplayOperation {
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
  late HouseSystem originalHouse;
  late AppLanguage originalLanguage;
  late List<_DisplayJob> jobs;
  late List<PeriodSevenDisplayRequest> requests;
  late PeriodSevenDisplayStarter starter;
  late int fileCalls;
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  setUpAll(() {
    final saved = HouseSystemSettings.current.value;
    HouseSystemSettings.current.value = HouseSystem.placidus;
    fixture = SyntheticSevenPeriodFixture();
    HouseSystemSettings.current.value = saved;
  });
  setUp(() {
    PeriodSevenDisplaySessionCache.clear();
    originalHouse = HouseSystemSettings.current.value;
    originalLanguage = AppLanguageSettings.current.value;
    HouseSystemSettings.current.value = HouseSystem.placidus;
    AppLanguageSettings.current.value = AppLanguage.ja;
    SharedPreferences.setMockInitialValues({
      'synthetic.older_json': 'unchanged',
      'synthetic.font': 19,
    });
    fileCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, (_) async {
          fileCalls++;
          throw StateError('Display cache must not access files.');
        });
    jobs = [];
    requests = [];
    starter = (request, progress) {
      requests.add(request);
      final job = _DisplayJob();
      jobs.add(job);
      return job;
    };
  });
  tearDown(() {
    PeriodSevenDisplaySessionCache.clear();
    HouseSystemSettings.current.value = originalHouse;
    AppLanguageSettings.current.value = originalLanguage;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, null);
  });

  Object cacheKey({
    LongRangeMode mode = LongRangeMode.month,
    DateTime? date,
    AstroProfile profile = sevenFixtureProfile,
    UserProfileDetails details = sevenFixtureDetails,
    HouseSystem house = HouseSystem.placidus,
    String source = 'synthetic source',
    bool precise = false,
    PeriodSevenDisplayStarter? start,
  }) => periodSevenDisplayCacheKey(
    mode: mode,
    first: date ?? DateTime.utc(2026, 1),
    profile: profile,
    details: details,
    houseSystem: house,
    sourceName: source,
    highPrecision: precise,
    startDisplayJob: start ?? starter,
  );

  test(
    'cache identity isolates source, precision, profile, details, house, period and worker',
    () {
      final key = cacheKey();
      expect(cacheKey(), key);
      expect(
        cacheKey(date: DateTime.utc(2026, 1, 1, 23)),
        key,
        reason: 'A period key uses civil date fields, not an arbitrary hour.',
      );
      final alternateStarter =
          (
            PeriodSevenDisplayRequest request,
            void Function(int, int) progress,
          ) => _DisplayJob();
      for (final changed in [
        cacheKey(source: 'another source'),
        cacheKey(precise: true),
        cacheKey(
          profile: sevenFixtureProfile.copyWith(
            name: 'Another fictional profile',
          ),
        ),
        cacheKey(
          details: const UserProfileDetails(
            birthTime: '',
            birthPlace: '',
            personality: '',
            concerns: 'Synthetic changed question',
            readingStyle: '',
          ),
        ),
        cacheKey(house: HouseSystem.wholeSign),
        cacheKey(mode: LongRangeMode.week),
        cacheKey(date: DateTime.utc(2026, 2)),
        cacheKey(start: alternateStarter),
      ]) {
        expect(changed, isNot(key));
      }
    },
  );

  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 6; i++)
      await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> pump(
    WidgetTester tester, {
    LongRangeMode mode = LongRangeMode.month,
    DateTime? first,
    AstroProfile profile = sevenFixtureProfile,
    ReadingDepth depth = ReadingDepth.simple,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: AppLanguageScope(
          child: Scaffold(
            body: SingleChildScrollView(
              child: PeriodSevenOverview(
                mode: mode,
                startDateJst: first ?? DateTime.utc(2026, 1),
                profile: profile,
                details: sevenFixtureDetails,
                depth: depth,
                startDisplayJob: starter,
              ),
            ),
          ),
        ),
      ),
    );
    await frames(tester);
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final target = find.byKey(ValueKey(key));
    await tester.ensureVisible(target);
    await tester.tap(target);
    await frames(tester);
  }

  PeriodSevenSummary shownSummary(WidgetTester tester) =>
      tester.widget<PeriodSevenTrend>(find.byType(PeriodSevenTrend)).summary;

  List<Map<String, Object?>> syntheticDays(PeriodSevenDisplayRequest request) {
    // Keep the internally consistent seed score audits and felt traces. Only
    // clock/identity metadata is synthetic; no astronomical equivalence is
    // claimed here. The worker test separately compares real calculations.
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

  void complete({int? index}) {
    final at = index ?? jobs.length - 1;
    final request = requests[at];
    final days = syntheticDays(request);
    // Exercise serialization on every fake worker return; do not alias maps
    // shared with the canonical contract fixture.
    final reread = (jsonDecode(jsonEncode(days)) as List)
        .map((d) => Map<String, Object?>.from(d as Map))
        .toList();
    jobs[at].completion.complete(
      PeriodSevenDisplayResult.fromData(request: request, days: reread),
    );
  }

  testWidgets(
    'month waits for both halves; cancel and retry preserve first half without recomputation',
    (tester) async {
      await pump(tester);
      expect(requests.length, 1);
      expect(requests[0].dayPlans.first.targetDateJst, '2026-01-01');
      expect(requests[0].dayPlans.last.targetDateJst, '2026-01-15');
      complete();
      await frames(tester);
      expect(requests.length, 2);
      expect(requests[1].dayPlans.first.targetDateJst, '2026-01-16');
      expect(requests[1].dayPlans.last.targetDateJst, '2026-01-31');
      expect(requests[1].generatedAt, requests[0].generatedAt);
      expect(find.byType(FortuneNumber), findsNothing);
      expect(PeriodSevenDisplaySessionCache.completedCount, 0);
      expect(PeriodSevenDisplaySessionCache.pendingCount, 1);
      await tap(tester, 'period-overview-cancel');
      expect(jobs[1].cancelled, true);
      complete(index: 1);
      await frames(tester);
      expect(find.byType(FortuneNumber), findsNothing);
      await tap(tester, 'period-overview-retry');
      expect(requests.length, 3);
      expect(requests[2].dayPlans.first.targetDateJst, '2026-01-16');
      expect(requests[2].generatedAt, requests[0].generatedAt);
      complete();
      await frames(tester);
      expect(find.byType(FortuneNumber), findsNWidgets(8));
      final summary = shownSummary(tester);
      expect(summary.dayCount, 31);
      expect(summary.uniqueInstantCount, 187);
      expect(PeriodSevenDisplaySessionCache.completedCount, 1);
      expect(PeriodSevenDisplaySessionCache.pendingCount, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await pump(tester, depth: ReadingDepth.detailed);
      expect(jobs.length, 3);
      expect(shownSummary(tester), same(summary));
      expect(fileCalls, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), {'synthetic.older_json', 'synthetic.font'});
      expect(prefs.getString('synthetic.older_json'), 'unchanged');
      expect(prefs.getInt('synthetic.font'), 19);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pending halves are bounded to two periods and a different profile cannot reuse a completed half',
    (tester) async {
      for (var month = 1; month <= 3; month++) {
        await pump(tester, first: DateTime.utc(2026, month));
        complete();
        await frames(tester);
        expect(find.byType(FortuneNumber), findsNothing);
      }
      expect(PeriodSevenDisplaySessionCache.pendingCount, 2);
      expect(PeriodSevenDisplaySessionCache.completedCount, 0);
      final before = jobs.length;
      await pump(tester, first: DateTime.utc(2026, 1));
      expect(jobs.length, before + 1);
      expect(requests.last.dayPlans.first.targetDateJst, '2026-01-01');
      complete();
      await frames(tester);
      await pump(
        tester,
        first: DateTime.utc(2026, 1),
        profile: sevenFixtureProfile.copyWith(
          name: 'Another fictional profile',
        ),
      );
      expect(requests.last.dayPlans.first.targetDateJst, '2026-01-01');
      expect(requests.last.profile.name, 'Another fictional profile');
      expect(PeriodSevenDisplaySessionCache.pendingCount, 2);
      expect(find.byType(FortuneNumber), findsNothing);
      expect(fileCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'completed cache is bounded to twelve and uses LRU while preserving summary identity',
    (tester) async {
      final summaries = <PeriodSevenSummary>[];
      final first = DateTime.utc(2026, 1, 1);
      for (var week = 0; week < 12; week++) {
        await pump(
          tester,
          mode: LongRangeMode.week,
          first: first.add(Duration(days: week * 7)),
        );
        complete();
        await frames(tester);
        summaries.add(shownSummary(tester));
      }
      expect(PeriodSevenDisplaySessionCache.maximumSummaries, 12);
      expect(PeriodSevenDisplaySessionCache.completedCount, 12);
      expect(jobs.length, 12);
      await pump(tester, mode: LongRangeMode.week, first: first);
      expect(shownSummary(tester), same(summaries.first));
      expect(jobs.length, 12);
      final reusedGraph = tester.widget<PeriodSevenGroupedTrendView>(
        find.byType(PeriodSevenGroupedTrendView),
      );
      expect(reusedGraph.summaries.length, 4);
      for (var week = 0; week < 4; week++) {
        expect(reusedGraph.summaries[week], same(summaries[week]));
      }
      await pump(
        tester,
        mode: LongRangeMode.week,
        first: first.add(const Duration(days: 84)),
      );
      complete();
      await frames(tester);
      expect(PeriodSevenDisplaySessionCache.completedCount, 12);
      await pump(tester, mode: LongRangeMode.week, first: first);
      expect(shownSummary(tester), same(summaries.first));
      expect(jobs.length, 13);
      await pump(
        tester,
        mode: LongRangeMode.week,
        first: first.add(const Duration(days: 28)),
      );
      expect(
        jobs.length,
        14,
        reason:
            'Reopening the first week reused its complete four-week graph, '
            'so the fifth week became least recently used.',
      );
      expect(find.byType(FortuneNumber), findsNothing);
      complete();
      await frames(tester);
      expect(PeriodSevenDisplaySessionCache.completedCount, 12);
      expect(PeriodSevenDisplaySessionCache.pendingCount, 0);
      expect(fileCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
