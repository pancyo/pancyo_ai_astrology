// Real host-provider calculations for a fictional profile. Native precision,
// fallback counters and timing require the separate Android equivalence check.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pancyo_ai_astrology/app_language.dart';
import 'package:pancyo_ai_astrology/main.dart';

const _subject = AstroProfile(
  name: 'LightweightEquivalenceSynthetic',
  birthDate: '1990/1/2',
  birthTime: '12:00',
  birthPlace: '北海道札幌市',
  theme: 'fixture',
);

Map<String, dynamic> _clone(Map value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);

// Only these explicit zero-weight diagnostic fields may differ. Removing
// arbitrary keys recursively would conceal changes to scoring or geometry.
Map<String, dynamic> _primaryWithoutVoid(Map trace) {
  final result = _clone(trace);
  (result['inputs'] as Map).remove('void_day_share');
  result.remove('void_context');
  return result;
}

Map<String, dynamic> _comparisonWithoutVoid(Map trace) {
  final result = _clone(trace);
  (result['inputs'] as Map).remove('void_day_share');
  result['lunar_path'] = _primaryWithoutVoid(result['lunar_path'] as Map);
  return result;
}

void _expectSamePrediction(
  List<NineAreaPrediction> full,
  List<NineAreaPrediction> light, {
  required String reason,
}) {
  expect(full.map((p) => p.key), NineAreaKey.values, reason: reason);
  expect(light.map((p) => p.key), NineAreaKey.values, reason: reason);
  for (final key in NineAreaKey.values) {
    final old = full.singleWhere((p) => p.key == key);
    final next = light.singleWhere((p) => p.key == key);
    expect(next.title, old.title, reason: reason);
    expect(next.icon, old.icon, reason: reason);
    expect(next.summary, old.summary, reason: reason);
    expect(next.detail, old.detail, reason: reason);
    expect(next.reading, old.reading, reason: reason);
    expect(next.provisional, old.provisional, reason: reason);
    expect(next.score, old.score, reason: '$reason/${key.name}');
    expect(
      jsonEncode(next.scoreBreakdown),
      jsonEncode(old.scoreBreakdown),
      reason: '$reason/${key.name}/complete_breakdown',
    );
    expect(
      jsonEncode(next.longTermContext),
      jsonEncode(old.longTermContext),
      reason: '$reason/${key.name}/long_term_geometry_and_precision',
    );
    if (key == NineAreaKey.felt) {
      expect(next.score, isNull);
      expect(next.scoreBreakdown, isNull);
      expect(next.feltForecast!.label, old.feltForecast!.label, reason: reason);
      expect(
        next.feltComparison!.label,
        old.feltComparison!.label,
        reason: reason,
      );
      expect(
        jsonEncode(_primaryWithoutVoid(next.feltForecast!.trace)),
        jsonEncode(_primaryWithoutVoid(old.feltForecast!.trace)),
        reason: '$reason/primary_aspects_sensitivity_parameters_and_model',
      );
      expect(
        jsonEncode(_comparisonWithoutVoid(next.feltComparison!.trace)),
        jsonEncode(_comparisonWithoutVoid(old.feltComparison!.trace)),
        reason: '$reason/comparison_aspects_sensitivity_parameters_and_model',
      );
      expect(
        (next.feltForecast!.trace['inputs'] as Map)['void_day_share'],
        isNull,
      );
      expect(next.feltForecast!.trace['void_context'], 'period_not_provided');
      expect((next.feltForecast!.trace['parameters'] as Map)['void_weight'], 0);
      expect(
        (next.feltComparison!.trace['inputs'] as Map)['void_day_share'],
        isNull,
      );
    } else {
      expect(next.score, inInclusiveRange(50, 99));
      expect(next.scoreBreakdown, isNotNull);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HouseSystem previousHouse;
  final contexts = <(HouseSystem, DateTime), HoroscopeReadingContext>{};

  HoroscopeReadingContext contextFor(DateTime date) => contexts.putIfAbsent(
    (HouseSystemSettings.current.value, date),
    () => const AstrologyEngine().buildPreviewContext(
      profile: _subject,
      date: date,
    ),
  );
  LongRangeDisplayRequest request(
    LongRangeDisplayMode mode, {
    bool fullContext = true,
    int year = 2028,
    int month = 2,
    String? sourceName,
    bool? highPrecision,
    HouseSystem? house,
  }) => LongRangeDisplayRequest(
    mode: mode,
    month: DateTime.utc(year, month),
    startYear: year,
    profile: _subject,
    houseSystem: house ?? HouseSystemSettings.current.value,
    sourceName: sourceName,
    requireHighPrecision: highPrecision,
    fullContext: fullContext,
  );

  setUp(() {
    previousHouse = HouseSystemSettings.current.value;
    HouseSystemSettings.current.value = HouseSystem.placidus;
    expect(
      AstrologyDataSources.current,
      isA<SimpleEphemeris>(),
      reason: 'This suite does not claim native ephemeris equivalence.',
    );
  });
  tearDown(() => HouseSystemSettings.current.value = previousHouse);

  for (final row in [
    (LongRangeDisplayMode.month, 5),
    (LongRangeDisplayMode.year, 24),
    (LongRangeDisplayMode.fiveYear, 120),
  ]) {
    test(
      '${row.$1.name}: exact host-provider scores, traces and raw aggregation for all ${row.$2} samples',
      () async {
        final fullRequest = request(row.$1);
        final lightRequest = request(row.$1, fullContext: false);
        expect(fullRequest.fullContext, true);
        expect(lightRequest.fullContext, false);
        expect(fullRequest.dates, lightRequest.dates);
        expect(lightRequest.dates.length, row.$2);
        expect(lightRequest.inputIdentity, isNot(fullRequest.inputIdentity));
        expect(
          lightRequest.dates.every(
            (d) => d.isUtc && d.hour == 3 && d.minute == 0,
          ),
          true,
        );
        final baseline = <DateTime, List<NineAreaPrediction>>{};
        for (final date in lightRequest.dates) {
          final context = contextFor(date);
          final full = NineAreaDailyForecast.fromContext(context);
          baseline[date] = full;
          final light = NineAreaDailyForecast.fromDisplayPositions(
            natal: context.natal,
            instantUtc: date,
            transitPlacements: context.transit.placements,
            usesHighPrecisionAstroData: context.usesHighPrecisionAstroData,
          );
          _expectSamePrediction(full, light, reason: date.toIso8601String());
        }
        final progress = <int>[];
        final operation = LongRangeDisplayJob.start(
          lightRequest,
          onProgress: (done, total) {
            expect(total, row.$2);
            progress.add(done);
          },
        );
        addTearDown(operation.cancel);
        final result = await operation.result;
        expect(result.matches(lightRequest), true);
        expect(result.matches(fullRequest), false);
        expect(result.samples.length, row.$2);
        expect(result.computedSampleCount, row.$2);
        expect(progress, List.generate(row.$2, (i) => i + 1));
        for (final date in lightRequest.dates) {
          final sample = result.samples[date]!;
          final context = contextFor(date);
          expect(sample.date, date);
          expect(sample.inputIdentity, lightRequest.inputIdentity);
          expect(sample.sourceName, context.ephemerisSourceName);
          expect(sample.precisionNotice, context.ephemerisPrecisionNotice);
          expect(sample.usesHighPrecision, context.usesHighPrecisionAstroData);
          expect(sample.resolvedHouseSystem, context.houseSystem);
          expect(sample.houseCusps, context.houseCusps);
          expect(sample.displayOnlyPositions, true);
          expect(sample.displayCalculation, {
            'display_only_positions': true,
            'void_period_status': 'not_requested',
            'void_day_share': null,
            'not_requested_void_is_not_zero': true,
          });
          _expectSamePrediction(
            baseline[date]!,
            sample.predictions,
            reason: '${row.$1.name}/worker/${date.toIso8601String()}',
          );
        }
        for (final area in result.summary.areas) {
          if (area.key == NineAreaKey.felt) {
            expect(area.score, isNull);
            final counts = <String, int>{};
            for (final daily in baseline.values) {
              final label = daily
                  .singleWhere((p) => p.key == NineAreaKey.felt)
                  .feltForecast!
                  .label!;
              counts.update(label, (v) => v + 1, ifAbsent: () => 1);
            }
            expect(
              result.summary.feltCounts,
              containsPair(counts.keys.first, counts.values.first),
            );
            for (final entry in counts.entries) {
              expect(result.summary.feltCounts[entry.key], entry.value);
            }
          } else {
            final raw = [
              for (final values in baseline.values)
                values.singleWhere((p) => p.key == area.key).score!,
            ];
            expect(area.samples, raw);
            expect(
              area.score,
              (raw.reduce((a, b) => a + b) / row.$2).round(),
              reason:
                  'One rounding of all ${row.$2} raw values, including the complete 120-point five-year population.',
            );
          }
        }
        final oldTrend = LongRangeDisplayTrendData.fromSamples(
          request: fullRequest,
          samples: baseline,
        );
        for (var i = 0; i < 5; i++) {
          expect(result.trend.series[i].values, oldTrend.series[i].values);
        }
        for (var i = 0; i < 3; i++) {
          expect(
            result.trend.additional.series[i].values,
            oldTrend.additional.series[i].values,
          );
        }
        expect(
          result.trend.additional.felt.map((p) => p.label),
          oldTrend.additional.felt.map((p) => p.label),
        );
        expect(
          result.matches(
            request(row.$1, fullContext: false, sourceName: 'different source'),
          ),
          false,
        );
        expect(
          result.matches(
            request(row.$1, fullContext: false, highPrecision: true),
          ),
          false,
        );
        expect(
          result.matches(
            request(row.$1, fullContext: false, house: HouseSystem.wholeSign),
          ),
          false,
        );
        final incomplete = LongRangeDisplayResult(
          requestIdentity: lightRequest.identity,
          samples: Map.of(result.samples)..remove(lightRequest.dates.last),
          summary: result.summary,
          trend: result.trend,
          computedSampleCount: row.$2 - 1,
        );
        expect(incomplete.matches(lightRequest), false);
        final cache = LongRangeDisplayCache();
        expect(cache.seeds(lightRequest), isEmpty);
        cache.publish(lightRequest, result);
        expect(cache.seeds(lightRequest).length, row.$2);
        expect(
          cache.seeds(fullRequest),
          isEmpty,
          reason:
              'Unrequested void diagnostics cannot masquerade as a complete context.',
        );
        expect(
          () => LongRangeDisplaySummary.fromSamples(
            request: lightRequest,
            samples: Map.of(baseline)..remove(lightRequest.dates.last),
          ),
          throwsStateError,
        );
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }

  test(
    'only explicit void diagnostics differ when a provided interval has nonzero day share',
    () {
      final date = DateTime.utc(2028, 2, 29, 3);
      final original = contextFor(date);
      final start = DateTime.utc(2028, 2, 28, 15);
      // Artificial diagnostic only; the geometry remains the real host-provider
      // result. This guarantees that the permitted nonzero-to-unrequested
      // diagnostic difference is exercised even on a naturally void-free date.
      final withVoid = HoroscopeReadingContext(
        natal: original.natal,
        transit: TransitChart(
          date: date,
          placements: original.transit.placements,
          voidMoon: VoidMoonPeriod(
            start: '00:00',
            end: '24:00',
            startTime: start,
            endTime: start.add(const Duration(days: 1)),
            guidance: 'Artificial zero-weight diagnostic fixture',
          ),
        ),
        nextTransitPlacements: original.nextTransitPlacements,
        aspects: original.aspects,
        fullAspects: original.fullAspects,
        nextAspects: original.nextAspects,
        transitPairAspects: original.transitPairAspects,
        retrogradePlanets: original.retrogradePlanets,
        houseTransits: original.houseTransits,
        returns: original.returns,
        birthPlace: original.birthPlace,
        ephemerisSourceName: original.ephemerisSourceName,
        ephemerisPrecisionNotice: original.ephemerisPrecisionNotice,
        usesHighPrecisionAstroData: original.usesHighPrecisionAstroData,
        houseSystem: original.houseSystem,
        houseCusps: original.houseCusps,
        scoreDayStartUtc: original.scoreDayStartUtc,
      );
      final full = NineAreaDailyForecast.fromContext(withVoid);
      final light = NineAreaDailyForecast.fromDisplayPositions(
        natal: original.natal,
        instantUtc: date,
        transitPlacements: original.transit.placements,
        usesHighPrecisionAstroData: original.usesHighPrecisionAstroData,
      );
      final felt = full
          .singleWhere((p) => p.key == NineAreaKey.felt)
          .feltForecast!;
      expect((felt.trace['inputs'] as Map)['void_day_share'], 1);
      expect(felt.trace['void_context'], 'one_provided_period');
      _expectSamePrediction(
        full,
        light,
        reason: 'nonzero void diagnostic is never a score input',
      );
    },
  );

  test(
    'worker rejects incorrect source and precision before calculating display samples',
    () async {
      for (final badRequest in [
        request(
          LongRangeDisplayMode.month,
          fullContext: false,
          sourceName: 'unavailable source',
        ),
        request(
          LongRangeDisplayMode.month,
          fullContext: false,
          highPrecision: true,
        ),
      ]) {
        final operation = LongRangeDisplayJob.start(badRequest);
        addTearDown(operation.cancel);
        await expectLater(operation.result, throwsStateError);
      }
    },
  );

  test(
    'source notices distinguish full and unrequested void context in Japanese and English',
    () {
      final date = DateTime.utc(2028, 2, 29, 3);
      final context = contextFor(date);
      final values = NineAreaDailyForecast.fromContext(context);
      // Metadata fixtures exercise wording only, not native precision.
      for (final source in [
        ('アプリ内簡易計算', false),
        ('Swiss Ephemeris Free Edition', true),
      ]) {
        for (final light in [false, true]) {
          final sample = LongRangeDisplaySample(
            inputIdentity: 'source-wording-fixture',
            date: date,
            sourceName: source.$1,
            usesHighPrecision: source.$2,
            precisionNotice: '未翻訳の内部診断を画面へ流用しない',
            resolvedHouseSystem: context.houseSystem,
            houseCusps: context.houseCusps,
            predictions: values,
            displayOnlyPositions: light,
          );
          for (final language in AppLanguage.values) {
            final text = longRangeSourceDisplayNotice(
              sample,
              AppStrings(language),
            );
            expect(text, isNot(contains(sample.precisionNotice)));
            if (language == AppLanguage.en) {
              expect(
                RegExp(r'[\u3040-\u30ff\u3400-\u9fff]').hasMatch(text),
                false,
              );
              expect(
                text,
                contains(
                  source.$2
                      ? 'Swiss Ephemeris Free Edition'
                      : 'Built-in simplified calculation',
                ),
              );
              if (light) {
                expect(text, contains('not requested'));
                expect(
                  text,
                  contains('does not mean no void period or a zero value'),
                );
                expect(
                  text,
                  isNot(contains('Lunar void context is calculated')),
                );
              } else {
                expect(
                  text,
                  contains(
                    'Lunar void context is calculated through the existing full route',
                  ),
                );
                if (source.$2) expect(text, contains('Android native Moshier'));
              }
            } else if (light) {
              expect(text, contains('取得していません'));
              expect(text, contains('未取得は無ボイドや0を意味しません'));
            } else {
              expect(text, contains('従来の経路で計算'));
            }
          }
          expect(sample.precisionNotice, '未翻訳の内部診断を画面へ流用しない');
        }
      }
    },
  );

  test(
    'display API keeps whole-sign material exact and does not fill missing or duplicate positions',
    () {
      HouseSystemSettings.current.value = HouseSystem.wholeSign;
      final date = DateTime.utc(2028, 2, 29, 3);
      final context = contextFor(date);
      List<NineAreaPrediction> calculate(
        List<PlanetPlacement> positions, {
        DateTime? instant,
      }) => NineAreaDailyForecast.fromDisplayPositions(
        natal: context.natal,
        instantUtc: instant ?? date,
        transitPlacements: positions,
        usesHighPrecisionAstroData: context.usesHighPrecisionAstroData,
      );
      _expectSamePrediction(
        NineAreaDailyForecast.fromContext(context),
        calculate(context.transit.placements),
        reason: 'whole-sign leap day',
      );
      final missing = context.transit.placements
          .where((p) => p.planet != AstroPlanet.moon)
          .toList();
      final duplicate = [
        ...context.transit.placements,
        context.transit.placements.first,
      ];
      final invalid = [
        for (final p in context.transit.placements)
          PlanetPlacement(
            planet: p.planet,
            sign: p.sign,
            degree: p.planet == AstroPlanet.moon ? double.nan : p.degree,
            house: p.house,
          ),
      ];
      for (final values in [missing, duplicate, invalid]) {
        final predictions = calculate(values);
        expect(predictions.where((p) => p.score != null), isEmpty);
        expect(
          predictions
              .singleWhere((p) => p.key == NineAreaKey.felt)
              .feltForecast!
              .label,
          isNull,
        );
      }
      expect(
        () => calculate(
          context.transit.placements,
          instant: DateTime(2028, 2, 29, 3),
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'display calculations leave complete formal snapshot JSON unchanged',
    () {
      final date = DateTime.utc(2028, 2, 29, 3);
      final context = contextFor(date);
      String formal() => jsonEncode(
        NineAreaForecastSnapshot.build(
          targetDate: date,
          generatedAt: DateTime.utc(2025, 1, 1),
          predictions: NineAreaDailyForecast.fromContext(context),
          houseSystem: context.houseSystem.name,
          usesHighPrecisionAstroData: context.usesHighPrecisionAstroData,
        ),
      );
      final before = formal();
      NineAreaDailyForecast.fromDisplayPositions(
        natal: context.natal,
        instantUtc: date,
        transitPlacements: context.transit.placements,
        usesHighPrecisionAstroData: context.usesHighPrecisionAstroData,
      );
      expect(formal(), before);
      final data = jsonDecode(before) as Map;
      expect(data['model_version'], NineAreaDailyForecast.modelVersion);
      expect(before, isNot(contains('display_only_positions')));
    },
  );

  test(
    'all 72 frozen formal explanation JSON records remain byte-equivalent',
    () {
      const profile = AstroProfile(
        name: 'ExplanationRegressionSynthetic',
        birthDate: '1990/1/2',
        birthTime: '12:00',
        birthPlace: '札幌市',
        theme: 'fixture',
      );
      final cache = <DateTime, List<NineAreaPrediction>>{};
      List<NineAreaPrediction> daily(DateTime date) => cache.putIfAbsent(
        date,
        () => NineAreaDailyForecast.fromContext(
          const AstrologyEngine().buildPreviewContext(
            profile: profile,
            date: date,
          ),
        ),
      );
      final date = DateTime.utc(2026, 10, 18, 3);
      final year = NineAreaPeriodSummary.build(
        mode: LongRangeMode.year,
        month: DateTime.utc(2026),
        year: 2026,
        legacyScores: {
          NineAreaKey.overall: 60,
          NineAreaKey.love: 60,
          NineAreaKey.work: 60,
          NineAreaKey.money: 60,
        },
        useGeneralModel: true,
        dailyFor: daily,
      );
      final samples = {
        for (final instant in year.dates)
          NineAreaPeriodSummary.dateLabel(instant): daily(instant),
      };
      final actual = <String, Object?>{};
      for (final language in AppLanguage.values) {
        for (final depth in ReadingDepth.values) {
          for (final area in daily(date)) {
            actual['day/${language.name}/${depth.name}/${area.key.name}'] =
                ForecastExplanation.forDaily(
                  prediction: area,
                  targetDate: date,
                  strings: AppStrings(language),
                  depth: depth,
                ).toJson();
          }
          for (final area in year.areas) {
            actual['year/${language.name}/${depth.name}/${area.key.name}'] =
                ForecastExplanation.forPeriod(
                  summary: year,
                  area: area,
                  strings: AppStrings(language),
                  depth: depth,
                  dailySamples: samples,
                ).toJson();
          }
        }
      }
      expect(actual.length, 72);
      expect(
        jsonEncode(actual),
        File(
          'test/fixtures/seven_r1_daily_annual_explanations.json',
        ).readAsStringSync(),
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
