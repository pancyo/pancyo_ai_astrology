// Synthetic reference scores test aggregation and UI lifecycle, not astronomy.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pancyo_ai_astrology/app_language.dart';
import 'package:pancyo_ai_astrology/app_language_settings.dart';
import 'package:pancyo_ai_astrology/main.dart';
import 'package:pancyo_ai_astrology/research/felt_forecast_candidate.dart';

const profile = AstroProfile(
  name: 'LongRangeSynthetic',
  birthDate: '1990/1/2',
  birthTime: '12:00',
  birthPlace: '北海道札幌市',
  theme: 'fixture',
);

LongRangeDisplayRequest request(
  LongRangeDisplayMode mode, {
  int year = 2028,
  int month = 2,
  AstroProfile subject = profile,
}) => LongRangeDisplayRequest(
  mode: mode,
  month: DateTime.utc(year, month),
  startYear: year,
  profile: subject,
  houseSystem: HouseSystemSettings.current.value,
);

List<NineAreaPrediction> predictions(int score, {String? felt = '普通'}) => [
  for (final key in NineAreaKey.values)
    NineAreaPrediction(
      key: key,
      title: key.name,
      icon: Icons.star,
      summary: 'synthetic',
      detail: 'synthetic',
      score: key == NineAreaKey.felt ? null : score,
      feltForecast: key == NineAreaKey.felt
          ? FeltForecastResult(felt, const {})
          : null,
    ),
];

Map<DateTime, List<NineAreaPrediction>> raw(
  LongRangeDisplayRequest r,
  int Function(int index) score, {
  String? Function(int)? felt,
}) => {
  for (var i = 0; i < r.dates.length; i++)
    r.dates[i]: predictions(score(i), felt: felt == null ? '普通' : felt(i)),
};

Map<DateTime, LongRangeDisplaySample> recorded(
  LongRangeDisplayRequest r,
  Map<DateTime, List<NineAreaPrediction>> values,
) => {
  for (final entry in values.entries)
    entry.key: LongRangeDisplaySample(
      inputIdentity: r.inputIdentity,
      date: entry.key,
      sourceName: r.sourceName,
      precisionNotice: 'synthetic',
      usesHighPrecision: r.requireHighPrecision,
      resolvedHouseSystem: r.houseSystem,
      houseCusps: [for (var i = 0; i < 12; i++) i * 30.0],
      predictions: entry.value,
      displayOnlyPositions: !r.fullContext,
    ),
};

LongRangeDisplayResult completed(
  LongRangeDisplayRequest r,
  Map<DateTime, List<NineAreaPrediction>> values,
) => LongRangeDisplayResult(
  requestIdentity: r.identity,
  samples: recorded(r, values),
  summary: LongRangeDisplaySummary.fromSamples(request: r, samples: values),
  trend: LongRangeDisplayTrendData.fromSamples(request: r, samples: values),
  computedSampleCount: values.length,
);

class Pending implements LongRangeDisplayOperation {
  final completer = Completer<LongRangeDisplayResult>();
  bool cancelled = false;
  @override
  Future<LongRangeDisplayResult> get result => completer.future;
  @override
  void cancel() {
    cancelled = true;
  }
}

class PendingWeek implements WeeklyDailyConsultExportOperation {
  final completer = Completer<WeeklyDailyConsultExportResult>();
  @override
  Future<WeeklyDailyConsultExportResult> get result => completer.future;
  @override
  void cancel() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('only five, twenty-four and one hundred twenty exact UTC03 samples', () {
    for (final row in [
      (2026, 2, 28),
      (2028, 2, 29),
      (2026, 4, 30),
      (2026, 12, 31),
    ]) {
      final r = request(
        LongRangeDisplayMode.month,
        year: row.$1,
        month: row.$2,
      );
      expect(r.fullContext, true);
      expect(r.dates.map((d) => d.day), [1, 8, 15, 22, row.$3]);
      expect(r.dates.every((d) => d.isUtc && d.hour == 3), true);
      final values = raw(r, (i) => [50, 60, 70, 80, 99][i]);
      final trend = LongRangeDisplayTrendData.fromSamples(
        request: r,
        samples: values,
      );
      expect(trend.labels, ['1–7', '8–14', '15–21', '22–${row.$3}']);
      expect(trend.series.first.values, [50, 60, 70, 90]);
      expect(trend.additional.series.first.values, [50, 60, 70, 90]);
    }
    final year = request(LongRangeDisplayMode.year);
    expect(year.fullContext, true);
    expect(year.dates, hasLength(24));
    final values = raw(year, (i) => 50 + i);
    final trend = LongRangeDisplayTrendData.fromSamples(
      request: year,
      samples: values,
    );
    expect(trend.series.first.values, [
      for (var i = 0; i < 12; i++) 51 + i * 2,
    ]);
    expect(trend.additional.series.first.values, trend.series.first.values);
    final five = request(LongRangeDisplayMode.fiveYear, year: 2028);
    expect(five.fullContext, true);
    expect(five.dates, hasLength(120));
    expect(five.dates.map((d) => d.year).toSet(), {
      2028,
      2029,
      2030,
      2031,
      2032,
    });
    expect(five.dates.toSet(), hasLength(120));
  });

  test(
    'five-year body rounds 120 raw scores once; graph uses annual summaries',
    () {
      final r = request(LongRangeDisplayMode.fiveYear);
      final values = raw(
        r,
        (i) => i < 72 && i % 24 >= 12 ? 51 : 50,
        felt: (i) => i < 60 ? '良い' : '悪い',
      );
      final summary = LongRangeDisplaySummary.fromSamples(
        request: r,
        samples: values,
      );
      final trend = LongRangeDisplayTrendData.fromSamples(
        request: r,
        samples: values,
      );
      expect(summary.isFiveYear, true);
      expect(summary.startYear, 2028);
      expect(summary.endYear, 2032);
      expect(summary.areas.take(8).map((a) => a.score), everyElement(50));
      expect(summary.areas.first.samples, hasLength(120));
      expect(trend.series.first.values, [51, 51, 51, 50, 50]);
      expect(summary.feltDisplayLabel, '混在');
      expect(summary.feltCounts['良い'], 60);
      expect(summary.feltCounts['悪い'], 60);
      expect(summary.areas.last.score, isNull);
      expect(() => summary.toJson(), throwsUnsupportedError);
      final missing = LongRangeDisplaySummary.fromSamples(
        request: r,
        samples: raw(r, (_) => 65, felt: (_) => null),
      );
      expect(missing.feltDisplayLabel, '未予測');
      expect(missing.feltUnavailableCount, 120);
    },
  );

  test(
    'missing references, invalid numeric values and felt scoring are rejected',
    () {
      final r = request(LongRangeDisplayMode.year);
      final missing = raw(r, (_) => 70)..remove(r.dates.first);
      expect(
        () => LongRangeDisplaySummary.fromSamples(request: r, samples: missing),
        throwsStateError,
      );
      expect(
        () => LongRangeDisplaySummary.fromSamples(
          request: r,
          samples: raw(r, (_) => 100),
        ),
        throwsStateError,
      );
      final invalid = raw(r, (_) => 70);
      invalid[r.dates.first]![8] = const NineAreaPrediction(
        key: NineAreaKey.felt,
        title: 'felt',
        icon: Icons.star,
        summary: '',
        detail: '',
        score: 70,
      );
      expect(
        () => LongRangeDisplaySummary.fromSamples(request: r, samples: invalid),
        throwsStateError,
      );
    },
  );

  test(
    'complete years are reusable by year mode and cache is bounded and input scoped',
    () {
      final cache = LongRangeDisplayCache(maxSamples: 120);
      final five = request(LongRangeDisplayMode.fiveYear);
      final all = recorded(five, raw(five, (_) => 70));
      expect(cache.seeds(five), isEmpty);
      // A partial year is never published; a complete year survives cancellation.
      cache.publishCompletedYear(five, {all.keys.first: all.values.first});
      expect(cache.retainedSampleCount, 0);
      final firstYear = {
        for (final e in all.entries)
          if (e.key.year == 2028) e.key: e.value,
      };
      cache.publishCompletedYear(five, firstYear);
      expect(cache.seeds(request(LongRangeDisplayMode.year)), hasLength(24));
      cache.publish(five, completed(five, raw(five, (_) => 70)));
      expect(cache.retainedSampleCount, 120);
      final next = request(LongRangeDisplayMode.fiveYear, year: 2029);
      expect(cache.seeds(next), hasLength(96));
      cache.publish(next, completed(next, raw(next, (_) => 70)));
      expect(cache.retainedSampleCount, 120);
      const other = AstroProfile(
        name: 'AnotherSynthetic',
        birthDate: '1990/1/2',
        birthTime: '12:00',
        birthPlace: '北海道札幌市',
        theme: 'fixture',
      );
      expect(
        cache.seeds(request(LongRangeDisplayMode.year, subject: other)),
        isEmpty,
      );
    },
  );

  test(
    'host provider worker calculates 120 references and reuses completed samples',
    () async {
      // This exercises the real selected host provider without selecting a
      // replacement provider. It is separate from the synthetic fixtures above.
      final five = request(LongRangeDisplayMode.fiveYear);
      final cache = LongRangeDisplayCache();
      final progress = <(int, int)>[];
      final readyYears = <int>[];
      final initialSeeds = cache.seeds(five);
      expect(initialSeeds, isEmpty);
      final firstWatch = Stopwatch()..start();
      final first = await LongRangeDisplayJob.start(
        five,
        seeds: initialSeeds,
        onProgress: (done, total) => progress.add((done, total)),
        onCompletedYear: (samples) {
          expect(samples, hasLength(24));
          expect(samples.keys.map((d) => d.year).toSet(), hasLength(1));
          readyYears.add(samples.keys.first.year);
          cache.publishCompletedYear(five, samples);
        },
      ).result;
      firstWatch.stop();
      expect(first.matches(five), true);
      expect(first.computedSampleCount, 120);
      expect(first.samples, hasLength(120));
      expect(first.summary.dates, five.dates);
      expect(first.summary.dates.toSet(), hasLength(120));
      expect(
        first.summary.dates.every(
          (d) => d.isUtc && d.hour == 3 && d.minute == 0 && d.second == 0,
        ),
        true,
      );
      expect(progress, [for (var done = 1; done <= 120; done++) (done, 120)]);
      expect(readyYears, [2028, 2029, 2030, 2031, 2032]);
      expect(first.trend.labels, ['2028', '2029', '2030', '2031', '2032']);
      expect(first.trend.series, hasLength(5));
      expect(first.trend.series.every((s) => s.values.length == 5), true);
      expect(
        first.trend.additional.series.every((s) => s.values.length == 5),
        true,
      );
      expect(first.trend.additional.felt, hasLength(5));
      final retained = first.samples.values.first;
      expect(retained.sourceName, five.sourceName);
      expect(retained.usesHighPrecision, five.requireHighPrecision);
      expect(retained.precisionNotice, isNotEmpty);
      for (final index in [0, 6, 119]) {
        final date = five.dates[index];
        final context = const AstrologyEngine().buildPreviewContext(
          profile: five.profile,
          date: date,
        );
        final direct = NineAreaDailyForecast.fromContext(context);
        final actual = first.samples[date]!.predictions;
        expect(context.ephemerisSourceName, five.sourceName);
        expect(context.usesHighPrecisionAstroData, five.requireHighPrecision);
        for (final key in NineAreaKey.values) {
          final expected = direct.singleWhere((p) => p.key == key);
          final recorded = actual.singleWhere((p) => p.key == key);
          expect(
            recorded.score,
            expected.score,
            reason: 'Reference $index, ${key.name}',
          );
          if (key == NineAreaKey.felt) {
            expect(recorded.score, isNull);
            expect(recorded.feltForecast?.label, expected.feltForecast?.label);
          }
        }
      }
      // Summary values must be means of the actual 120 daily scores, rounded
      // once, while each plotted year must use its own actual 24 samples.
      for (final key in NineAreaKey.values.where(
        (k) => k != NineAreaKey.felt,
      )) {
        final values = [
          for (final date in five.dates)
            first.samples[date]!.predictions
                .singleWhere((p) => p.key == key)
                .score!,
        ];
        expect(
          first.summary.areas.singleWhere((a) => a.key == key).score,
          (values.reduce((a, b) => a + b) / 120).round(),
        );
        expect(
          first.summary.areas.singleWhere((a) => a.key == key).samples,
          values,
        );
        final graphSeries = key.index < 5
            ? first.trend.series[key.index]
            : first.trend.additional.series[key.index - 5];
        expect(graphSeries.values, [
          for (var yearIndex = 0; yearIndex < 5; yearIndex++)
            (values
                        .sublist(yearIndex * 24, yearIndex * 24 + 24)
                        .reduce((a, b) => a + b) /
                    24)
                .round(),
        ]);
      }
      cache.publish(five, first);
      final revisitWatch = Stopwatch()..start();
      final revisit = await LongRangeDisplayJob.start(
        five,
        seeds: cache.seeds(five),
      ).result;
      revisitWatch.stop();
      expect(revisit.computedSampleCount, 0);
      expect(
        revisit.summary.areas.map((a) => a.score),
        first.summary.areas.map((a) => a.score),
      );
      expect(revisit.summary.feltCounts, first.summary.feltCounts);
      final year = request(LongRangeDisplayMode.year);
      final yearSeeds = cache.seeds(year);
      expect(yearSeeds, hasLength(24));
      final yearWatch = Stopwatch()..start();
      final yearResult = await LongRangeDisplayJob.start(
        year,
        seeds: yearSeeds,
      ).result;
      yearWatch.stop();
      expect(yearResult.computedSampleCount, 0);
      expect(yearResult.summary.dates, five.dates.take(24));
      expect(yearResult.trend.labels, hasLength(12));
      expect(yearResult.summary.areas.take(8).map((a) => a.score), [
        for (var area = 0; area < 8; area++)
          (first.summary.areas[area].samples.take(24).reduce((a, b) => a + b) /
                  24)
              .round(),
      ]);
      // No personal fixture fields are written into this diagnostic line.
      // ignore: avoid_print
      print(
        'LONG_RANGE_HOST_BENCH fixture=anonymous provider=${five.sourceName} '
        'highprecision=${five.requireHighPrecision} total=120 '
        'computed_first=${first.computedSampleCount} elapsed_first_ms=${firstWatch.elapsedMilliseconds} '
        'computed_revisit=${revisit.computedSampleCount} elapsed_revisit_ms=${revisitWatch.elapsedMilliseconds} '
        'computed_year=${yearResult.computedSampleCount} elapsed_year_ms=${yearWatch.elapsedMilliseconds} '
        'completed_year_events=${readyYears.length} single_host_not_native_performance=true',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'period changes and disposal cancel workers; display changes do not recalculate',
    (tester) async {
      final pending = <Pending>[];
      LongRangeDisplayOperation start(
        LongRangeDisplayRequest r,
        void Function(int, int) progress,
      ) {
        final job = Pending();
        pending.add(job);
        return job;
      }

      Future<void> pump(
        LongRangeDisplayRequest r, {
        ReadingDepth depth = ReadingDepth.simple,
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: LongRangeOverviewPanel(
                  request: r,
                  details: const UserProfileDetails.empty(),
                  depth: depth,
                  startJob: start,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
      }

      final month = request(LongRangeDisplayMode.month);
      await pump(month);
      expect(pending, hasLength(1));
      await pump(month, depth: ReadingDepth.detailed);
      expect(pending, hasLength(1));
      final year = request(LongRangeDisplayMode.year);
      await pump(year);
      expect(pending.first.cancelled, true);
      expect(pending, hasLength(2));
      pending.first.completer.complete(completed(month, raw(month, (_) => 70)));
      await tester.pump();
      expect(find.byKey(const ValueKey('long-range-main-chart')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      expect(pending.last.cancelled, true);
    },
  );

  testWidgets(
    'partial five-year graph shows only completed years and labels uncomputed years',
    (tester) async {
      final r = request(LongRangeDisplayMode.fiveYear);
      final all = recorded(r, raw(r, (_) => 70));
      final ready = {
        2028: {
          for (final e in all.entries)
            if (e.key.year == 2028) e.key: e.value,
        },
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LongRangePartialYearView(
                request: r,
                completedYears: ready,
                depth: ReadingDepth.simple,
                details: const UserProfileDetails.empty(),
              ),
            ),
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey('five-year-partial-chart')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('five-year-ready-2028')),
        findsOneWidget,
      );
      for (var year = 2029; year <= 2032; year++) {
        expect(find.byKey(ValueKey('five-year-waiting-$year')), findsOneWidget);
      }
      expect(find.byType(NineAreaPeriodOverview), findsNothing);
      await tester.tap(find.byKey(const ValueKey('five-year-ready-2028')));
      await tester.pumpAndSettle();
      expect(find.byType(NineAreaPeriodOverview), findsOneWidget);
    },
  );

  testWidgets(
    '390-wide English selected Week and five years stay on one line at standard text scale',
    (tester) async {
      final originalLanguage = AppLanguageSettings.current.value;
      AppLanguageSettings.current.value = AppLanguage.en;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        AppLanguageSettings.current.value = originalLanguage;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      PeriodSevenDisplaySessionCache.clear();
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1)),
            child: AppLanguageScope(child: child!),
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: LongRangeReading(
                profile: profile,
                details: const UserProfileDetails.empty(),
                depth: ReadingDepth.simple,
                startWeeklyReadingJob: (_, __) => PendingWeek(),
                startLongRangeDisplayJob: (_, __) => Pending(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final week = find.text('Week'), month = find.text('Month');
      expect(week, findsOneWidget);
      expect(month, findsOneWidget);
      expect(
        find.byType(SegmentedButton<LongRangeDisplayMode>),
        findsNothing,
        reason:
            'The phone uses two rows instead of squeezing the selected label.',
      );
      expect(
        tester.getSize(week).height,
        tester.getSize(month).height,
        reason: 'Selected Week must not wrap into Wee / k.',
      );
      expect(tester.getSize(week).height, lessThan(24));
      await tester.tap(find.text('5 years'));
      await tester.pump();
      await tester.pump();
      expect(
        tester.getSize(find.text('5 years')).height,
        tester.getSize(month).height,
        reason: 'Selected 5 years must not break inside the word.',
      );
      expect(tester.getSize(find.text('5 years')).height, lessThan(24));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'ordinary month year and five-year UI requests the approved light path and displays matching results',
    (tester) async {
      final originalLanguage = AppLanguageSettings.current.value;
      AppLanguageSettings.current.value = AppLanguage.en;
      addTearDown(() => AppLanguageSettings.current.value = originalLanguage);
      PeriodSevenDisplaySessionCache.clear();
      final requests = <LongRangeDisplayRequest>[];
      final jobs = <Pending>[];
      await tester.pumpWidget(
        MaterialApp(
          home: AppLanguageScope(
            child: Scaffold(
              body: SingleChildScrollView(
                child: LongRangeReading(
                  profile: profile,
                  details: const UserProfileDetails.empty(),
                  depth: ReadingDepth.detailed,
                  startWeeklyReadingJob: (_, __) => PendingWeek(),
                  startLongRangeDisplayJob: (r, progress) {
                    requests.add(r);
                    final job = Pending();
                    jobs.add(job);
                    return job;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      for (final row in [
        ('Month', LongRangeDisplayMode.month, 5, 4),
        ('Year', LongRangeDisplayMode.year, 24, 12),
        ('5 years', LongRangeDisplayMode.fiveYear, 120, 5),
      ]) {
        final priorCount = requests.length;
        await tester.ensureVisible(find.text(row.$1));
        await tester.tap(find.text(row.$1));
        await tester.pump();
        await tester.pump();
        expect(requests, hasLength(priorCount + 1));
        final uiRequest = requests.last;
        expect(uiRequest.mode, row.$2);
        expect(uiRequest.fullContext, false);
        expect(uiRequest.dates, hasLength(row.$3));
        final fullRequest = LongRangeDisplayRequest(
          mode: uiRequest.mode,
          month: uiRequest.month,
          startYear: uiRequest.startYear,
          profile: uiRequest.profile,
          houseSystem: uiRequest.houseSystem,
          sourceName: uiRequest.sourceName,
          requireHighPrecision: uiRequest.requireHighPrecision,
          scalarVoid: uiRequest.scalarVoid,
        );
        expect(fullRequest.fullContext, true);
        expect(fullRequest.inputIdentity, isNot(uiRequest.inputIdentity));
        final fullResult = completed(fullRequest, raw(fullRequest, (_) => 71));
        final cache = LongRangeDisplayCache();
        expect(cache.seeds(fullRequest), isEmpty);
        cache.publish(fullRequest, fullResult);
        expect(
          cache.seeds(uiRequest),
          isEmpty,
          reason: 'Full-context evidence must not seed the light display.',
        );
        final result = completed(uiRequest, raw(uiRequest, (_) => 70));
        expect(result.matches(uiRequest), true);
        expect(result.matches(fullRequest), false);
        expect(
          result.samples.values.every((s) => s.displayOnlyPositions),
          true,
        );
        jobs.last.completer.complete(result);
        await tester.pumpAndSettle();
        expect(find.byType(NineAreaPeriodOverview), findsOneWidget);
        final overview = tester.widget<NineAreaPeriodOverview>(
          find.byType(NineAreaPeriodOverview),
        );
        expect(identical(overview.summary, result.summary), true);
        expect(
          find.byKey(const ValueKey('long-range-main-chart')),
          findsOneWidget,
        );
        final chart = tester.widget<CustomPaint>(
          find.byKey(const ValueKey('long-range-main-chart')),
        );
        expect(
          (chart.painter! as FortuneFlowPainter).labels,
          hasLength(row.$4),
        );
        final notice = longRangeSourceDisplayNotice(
          result.samples.values.first,
          const AppStrings(AppLanguage.en),
        );
        expect(find.text(notice), findsOneWidget);
        expect(notice, contains('Lunar void context was not requested.'));
        expect(
          notice,
          contains('does not mean no void period or a zero value'),
        );
        expect(RegExp(r'[\u3040-\u30ff\u3400-\u9fff]').hasMatch(notice), false);
        expect(
          find.text('Unable to prepare the reference positions.'),
          findsNothing,
        );
        expect(
          tester.takeException(),
          isNull,
          reason: '${row.$2.name} light UI result',
        );
      }
    },
  );

  testWidgets(
    '390-wide navigation, period charts and badges honor double text scale',
    (tester) async {
      final originalLanguage = AppLanguageSettings.current.value;
      AppLanguageSettings.current.value = AppLanguage.en;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        AppLanguageSettings.current.value = originalLanguage;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      Widget app(Widget child) => MaterialApp(
        builder: (context, content) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: AppLanguageScope(child: content!),
        ),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      );
      final jobs = <Pending>[];
      await tester.pumpWidget(
        app(
          LongRangeReading(
            profile: profile,
            details: const UserProfileDetails.empty(),
            depth: ReadingDepth.simple,
            startWeeklyReadingJob: (_, __) => PendingWeek(),
            startLongRangeDisplayJob: (r, progress) {
              final job = Pending();
              jobs.add(job);
              return job;
            },
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Week'), findsOneWidget);
      expect(find.text('Month'), findsOneWidget);
      expect(find.text('Year'), findsOneWidget);
      expect(find.text('5 years'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Month'));
      await tester.pump();
      await tester.pump();
      expect(jobs, hasLength(1));
      expect(tester.takeException(), isNull);
      // Re-selecting the active period must not discard a running calculation.
      await tester.tap(find.text('Month'));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('long-range-current')));
      await tester.pump();
      await tester.pump();
      expect(jobs, hasLength(1));
      for (final mode in [
        LongRangeDisplayMode.month,
        LongRangeDisplayMode.year,
        LongRangeDisplayMode.fiveYear,
      ]) {
        final r = request(mode);
        final result = completed(r, raw(r, (_) => 70));
        await tester.pumpWidget(
          app(
            Column(
              children: [
                LongRangeDisplayTrendView(data: result.trend, mode: mode),
                NineAreaPeriodOverview(
                  summary: result.summary,
                  dailySamples: result.dailySamples,
                  details: const UserProfileDetails.empty(),
                ),
              ],
            ),
          ),
        );
        await tester.pump();
        final chartFinder = find.byKey(const ValueKey('long-range-main-chart'));
        final painter =
            tester.widget<CustomPaint>(chartFinder).painter!
                as FortuneFlowPainter;
        final pointCount = mode == LongRangeDisplayMode.month
            ? 4
            : mode == LongRangeDisplayMode.year
            ? 12
            : 5;
        expect(painter.labels, hasLength(pointCount));
        expect(painter.textScaler.scale(10), 20);
        expect(
          tester.getSize(chartFinder).width,
          greaterThanOrEqualTo(112.0 * pointCount),
        );
        final numbers = tester
            .widgetList<FortuneNumber>(find.byType(FortuneNumber))
            .toList();
        expect(numbers.first.fixedSize, dailyOverallFortuneBadgeSize * 2);
        expect(
          numbers.skip(1).map((n) => n.fixedSize),
          everyElement(dailyFortuneBadgeSize * 2),
        );
        expect(
          tester
              .widget<FeltFortuneBadge>(find.byType(FeltFortuneBadge))
              .fixedSize,
          dailyFortuneBadgeSize * 2,
        );
        expect(
          tester.takeException(),
          isNull,
          reason: '${mode.name} at double text scale',
        );
      }
    },
  );
}
