import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pancyo_ai_astrology/app_language.dart';
import 'package:pancyo_ai_astrology/main.dart';

import 'period_seven_test_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SyntheticSevenPeriodFixture fixture;
  late HouseSystem originalHouse;
  setUpAll(() {
    originalHouse = HouseSystemSettings.current.value;
    HouseSystemSettings.current.value = HouseSystem.placidus;
    fixture = SyntheticSevenPeriodFixture();
  });
  tearDownAll(() => HouseSystemSettings.current.value = originalHouse);

  List<Map<String, Object?>> daysOf(Map<String, Object?> wrapper) =>
      (wrapper['days'] as List)
          .map((day) => Map<String, Object?>.from(day as Map))
          .toList();
  PeriodSevenSummary aggregate(
    Map<String, Object?> wrapper,
    LongRangeMode mode,
  ) {
    final period =
        wrapper[mode == LongRangeMode.week ? 'week' : 'month'] as Map;
    return PeriodSevenSummary.fromDailyV4(
      mode: mode,
      startDateJst: DateTime.parse(period['start_date_jst'] as String),
      days: daysOf(wrapper),
      profile: sevenFixtureProfile,
      details: sevenFixtureDetails,
      requestedHouseSystem: HouseSystem.placidus,
      sourceName: AstrologyDataSources.current.sourceName,
      requireHighPrecision:
          AstrologyDataSources.current.usesHighPrecisionAstroData,
    );
  }

  String digest(Object value) =>
      sha256.convert(utf8.encode(jsonEncode(value))).toString();

  test(
    'one actually calculated fictional week: 49/43, exact unique means, end boundary and unchanged daily-v4 bytes',
    () {
      final request = fixtureWeekRequest(DateTime.utc(2026, 12, 28));
      final wrapper = buildWeeklyDailyConsultData(request);
      final before = digest(wrapper);
      final dayHashes = daysOf(wrapper).map(digest).toList();
      final independent = <String, Map<String, Object?>>{};
      for (final day in daysOf(wrapper)) {
        for (final point in fixturePoints(day)) {
          final key = point['instant_utc'] as String;
          final snap = Map<String, Object?>.from(
            point['nine_area_forecast'] as Map,
          );
          if (independent.containsKey(key)) {
            expect(jsonEncode(snap), jsonEncode(independent[key]));
          } else {
            independent[key] = snap;
          }
        }
      }
      final summary = aggregate(wrapper, LongRangeMode.week);
      expect(summary.dayCount, 7);
      expect(summary.listedPointCount, 49);
      expect(summary.uniqueInstantCount, 43);
      expect(
        summary.dates.map((d) => d.toIso8601String()).toList(),
        independent.keys.toList(),
      );
      for (final entry in summary.areas) {
        if (entry.key == NineAreaKey.felt) {
          expect(entry.score, isNull);
          continue;
        }
        final values = [
          for (final snap in independent.values)
            ((snap['areas'] as List).singleWhere(
                  (area) => area['key'] == entry.key.name,
                )['score']
                as int),
        ];
        expect(entry.samples, values);
        expect(
          entry.score,
          (values.reduce((a, b) => a + b) / values.length).round(),
        );
        expect(entry.inherited, false);
      }
      expect(summary.dates.first, DateTime.utc(2026, 12, 27, 15));
      expect(summary.dates.last, DateTime.utc(2027, 1, 3, 15));
      expect(summary.startDateJst, '2026-12-28');
      expect(summary.endDateJst, '2027-01-03');
      expect(digest(wrapper), before);
      expect(daysOf(wrapper).map(digest).toList(), dayHashes);
      expect(jsonDecode(jsonEncode(wrapper)), wrapper);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'synthetic contract months include every day for 28/29/30/31 with 6N+1 unique instants',
    () {
      for (final row in [
        (2026, 2, 28),
        (2024, 2, 29),
        (2026, 4, 30),
        (2026, 12, 31),
      ]) {
        final request = fixtureMonthRequest(DateTime.utc(row.$1, row.$2));
        final wrapper = fixture.month(request);
        // The existing official wrapper validator is exercised before aggregation.
        MonthlyDailyConsultExportResult.fromData(
          requestIdentity: request.identity,
          data: wrapper,
        );
        final before = digest(wrapper);
        final summary = aggregate(wrapper, LongRangeMode.month);
        expect(summary.dayCount, row.$3);
        expect(summary.listedPointCount, row.$3 * 7);
        expect(summary.uniqueInstantCount, row.$3 * 6 + 1);
        expect(summary.predictionsByInstant.length, row.$3 * 6 + 1);
        expect(summary.startDateJst, request.startDateJst);
        expect(summary.endDateJst, request.endDateJst);
        expect(summary.dates.first, DateTime.utc(row.$1, row.$2, 1, -9));
        expect(summary.dates.last, DateTime.utc(row.$1, row.$2 + 1, 1, -9));
        expect(summary.dates.toSet().length, summary.dates.length);
        for (var i = 1; i < summary.dates.length; i++) {
          expect(
            summary.dates[i].difference(summary.dates[i - 1]),
            const Duration(hours: 4),
          );
        }
        expect(digest(wrapper), before);
      }
    },
  );

  test(
    'synthetic contract mean counts each boundary once, rounds only final mean and keeps felt Mixed',
    () {
      final request = fixtureWeekRequest(DateTime.utc(2026, 12, 28));
      final wrapper = fixture.week(request);
      WeeklyDailyConsultExportResult.fromData(
        requestIdentity: request.identity,
        data: wrapper,
      );
      final summary = aggregate(wrapper, LongRangeMode.week);
      for (final entry in summary.areas.where(
        (e) => e.key != NineAreaKey.felt,
      )) {
        final uniqueValues = List.generate(
          43,
          (i) => SyntheticSevenPeriodFixture.scoreAt(i, entry.key.name),
        );
        final duplicatedValues = [
          for (var d = 0; d < 7; d++)
            for (var h = 0; h < 7; h++)
              SyntheticSevenPeriodFixture.scoreAt(d * 6 + h, entry.key.name),
        ];
        final expected = (uniqueValues.reduce((a, b) => a + b) / 43).round();
        expect(entry.samples, uniqueValues);
        expect(entry.score, expected);
        expect(
          entry.score,
          isNot((duplicatedValues.reduce((a, b) => a + b) / 49).round()),
          reason:
              'This adversarial fixture detects counting interior midnight twice.',
        );
      }
      expect(summary.feltCounts['良い'], 21);
      expect(summary.feltCounts['悪い'], 21);
      expect(summary.feltCounts['普通'], 1);
      expect(summary.feltModes.toSet(), {'良い', '悪い'});
      expect(summary.feltLabel, isNull);
      expect(summary.feltDisplayLabel, '混在');
      expect(
        summary.areas.singleWhere((e) => e.key == NineAreaKey.felt).score,
        isNull,
      );
      final encoded = summary.toJson();
      final sampling = encoded['sampling'] as Map;
      expect(sampling['final_boundary_included'], true);
      expect(sampling['unique_instant_count'], 43);
      expect(
        (encoded['areas'] as List).where((a) => a['score'] is int).length,
        8,
      );
    },
  );

  test(
    'graph series preserves all unique instants and every numeric sample without resampling or felt scoring',
    () {
      final periods = [
        (
          LongRangeMode.week,
          fixture.week(fixtureWeekRequest(DateTime.utc(2026, 12, 28))),
        ),
        (
          LongRangeMode.month,
          fixture.month(fixtureMonthRequest(DateTime.utc(2026, 2))),
        ),
        (
          LongRangeMode.month,
          fixture.month(fixtureMonthRequest(DateTime.utc(2024, 2))),
        ),
        (
          LongRangeMode.month,
          fixture.month(fixtureMonthRequest(DateTime.utc(2026, 4))),
        ),
        (
          LongRangeMode.month,
          fixture.month(fixtureMonthRequest(DateTime.utc(2026, 12))),
        ),
      ];
      for (final period in periods) {
        final summary = aggregate(period.$2, period.$1);
        final before = digest(summary.toJson());
        for (final area in summary.areas.where(
          (entry) => entry.key != NineAreaKey.felt,
        )) {
          final series = periodSevenTrendPoints(summary, area.key);
          expect(series.length, summary.uniqueInstantCount);
          expect(
            series.map((point) => point.instantUtc).toList(),
            summary.dates,
          );
          expect(series.map((point) => point.score).toList(), area.samples);
          expect(series.first.instantUtc, summary.dates.first);
          expect(series.last.instantUtc, summary.dates.last);
        }
        expect(
          () => periodSevenTrendPoints(summary, NineAreaKey.felt),
          throwsArgumentError,
        );
        expect(digest(summary.toJson()), before);
      }
    },
  );

  test(
    'synthetic contract rejects missing, duplicate, altered boundary, noon, profile, precision and invalid values',
    () {
      final original = fixture.week(
        fixtureWeekRequest(DateTime.utc(2026, 12, 28)),
      );
      final damageCases = <String, void Function(Map<String, Object?>)>{
        'missing day': (w) => (w['days'] as List).removeLast(),
        'duplicate day': (w) => (w['days'] as List)[1] = (w['days'] as List)[0],
        'missing time': (w) => fixturePoints(daysOf(w).first).removeLast(),
        'wrong UTC': (w) => fixturePoints(daysOf(w).first)[1]['instant_utc'] =
            '2026-12-28T00:00:00.000Z',
        'changed boundary explanation': (w) =>
            ((fixturePoints(daysOf(w)[1])[0]['nine_area_forecast']['areas']
                            as List)
                        .first
                    as Map)['explanation'] =
                'different boundary trace',
        'changed noon': (w) =>
            (daysOf(w).first['nine_area_daily'] as Map)['target_date_jst'] =
                '2000-01-01',
        'wrong profile': (w) => (daysOf(w).first['profile'] as Map)['name'] =
            'Another fictional person',
        'wrong precision': (w) =>
            fixturePoints(
                  daysOf(w).first,
                )[1]['nine_area_forecast']['uses_high_precision_astro_data'] =
                !AstrologyDataSources.current.usesHighPrecisionAstroData,
        'missing score': (w) =>
            (fixturePoints(daysOf(w).first)[1]['nine_area_forecast']['areas']
                        as List)
                    .first['score'] =
                null,
        'fractional score': (w) =>
            (fixturePoints(daysOf(w).first)[1]['nine_area_forecast']['areas']
                        as List)
                    .first['score'] =
                70.5,
        'out of range': (w) =>
            (fixturePoints(daysOf(w).first)[1]['nine_area_forecast']['areas']
                        as List)
                    .first['score'] =
                100,
        'missing felt': (w) =>
            (fixturePoints(daysOf(w).first)[1]['nine_area_forecast']['areas']
                        as List)
                    .singleWhere(
                      (a) => a['key'] == 'felt',
                    )['predicted_felt_label'] =
                null,
        'unknown felt': (w) =>
            (fixturePoints(daysOf(w).first)[1]['nine_area_forecast']['areas']
                        as List)
                    .singleWhere(
                      (a) => a['key'] == 'felt',
                    )['predicted_felt_label'] =
                'Unregistered category',
        'different generation': (w) =>
            (w['days'] as List)[1]['generated_at'] = '2026-10-19T03:00:00.000Z',
      };
      for (final damage in damageCases.entries) {
        final invalid = fixtureClone(original);
        damage.value(invalid);
        expect(
          () => aggregate(invalid, LongRangeMode.week),
          throwsA(anything),
          reason: damage.key,
        );
      }
    },
  );

  test(
    'seven-point explanation labels the selected period, includes unique samples, and does not claim every instant',
    () {
      final summary = aggregate(
        fixture.week(fixtureWeekRequest(DateTime.utc(2026, 12, 28))),
        LongRangeMode.week,
      );
      for (final language in AppLanguage.values) {
        for (final depth in ReadingDepth.values) {
          final text = ForecastExplanation.forPeriod(
            summary: summary,
            area: summary.areas.singleWhere((e) => e.key == NineAreaKey.work),
            strings: AppStrings(language),
            depth: depth,
            dailySamples: summary.predictionsByInstant,
          );
          expect(text.title, contains('2026-12-28'));
          expect(text.title, contains('2027-01-03'));
          expect(text.title, isNot(contains('2027-01-04')));
          expect(text.basis, contains('43'));
          expect(text.basis, contains('49'));
          expect(
            text.limitations.join(' '),
            contains(language == AppLanguage.ja ? '全時刻' : 'not every'),
          );
          expect(
            text.score,
            summary.areas.singleWhere((e) => e.key == NineAreaKey.work).score,
          );
          if (language == AppLanguage.en) {
            expect(
              RegExp(r'[\u3040-\u30ff\u3400-\u9fff]').hasMatch(text.text),
              false,
            );
          }
        }
      }
    },
  );

  test(
    'period aggregation has no side effects on existing daily and annual explanation serialization',
    () {
      final week = aggregate(
        fixture.week(fixtureWeekRequest(DateTime.utc(2026, 12, 28))),
        LongRangeMode.week,
      );
      final sample = week.predictionsByInstant.values.first;
      final annual = NineAreaPeriodSummary.build(
        mode: LongRangeMode.year,
        month: DateTime.utc(2026),
        year: 2026,
        legacyScores: {
          NineAreaKey.overall: 77,
          NineAreaKey.love: 78,
          NineAreaKey.work: 79,
          NineAreaKey.money: 80,
        },
        dailyFor: (_) => sample,
      );
      final annualSamples = {
        for (final date in annual.dates)
          NineAreaPeriodSummary.dateLabel(date): sample,
      };
      for (final language in AppLanguage.values) {
        for (final depth in ReadingDepth.values) {
          final strings = AppStrings(language);
          Map<String, Object?> daily() => ForecastExplanation.forDaily(
            prediction: sample.singleWhere((p) => p.key == NineAreaKey.work),
            targetDate: week.dates.first,
            strings: strings,
            depth: depth,
          ).toJson();
          Map<String, Object?> year() => ForecastExplanation.forPeriod(
            summary: annual,
            area: annual.areas.singleWhere((a) => a.key == NineAreaKey.work),
            strings: strings,
            depth: depth,
            dailySamples: annualSamples,
          ).toJson();
          final beforeDay = digest(daily()), beforeYear = digest(year());
          ForecastExplanation.forPeriod(
            summary: week,
            area: week.areas.singleWhere((a) => a.key == NineAreaKey.work),
            strings: strings,
            depth: depth,
            dailySamples: week.predictionsByInstant,
          );
          expect(digest(daily()), beforeDay);
          expect(digest(year()), beforeYear);
          expect(year()['model_version'], NineAreaPeriodSummary.modelVersion);
          expect(annual.dates.length, 24);
        }
      }
    },
  );
}
