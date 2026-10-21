// Real calculations for a fictional profile, using the available provider.
// Timings below are single host measurements, not Android speed claims.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pancyo_ai_astrology/app_language.dart';
import 'package:pancyo_ai_astrology/main.dart';

import 'period_seven_test_fixture.dart';

class _WrongIdentity implements PeriodSevenDisplayResult {
  _WrongIdentity(this.original);
  final PeriodSevenDisplayResult original;
  @override
  String get requestIdentity => 'another operation';
  @override
  List<Map<String, Object?>> get days => original.days;
  @override
  int get elapsedMilliseconds => original.elapsedMilliseconds;
  @override
  String? get workerName => original.workerName;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HouseSystem originalHouse;
  late PeriodSevenDisplayRequest request;
  late List<Map<String, Object?>> canonical, display;
  String digest(Object value) =>
      sha256.convert(utf8.encode(jsonEncode(value))).toString();
  PeriodSevenDisplayRequest range(
    DateTime first,
    DateTime last, {
    AstroProfile profile = sevenFixtureProfile,
    String? sourceName,
  }) => PeriodSevenDisplayRequest(
    startDateJst: first,
    endDateJst: last,
    profile: profile,
    details: sevenFixtureDetails,
    requestedHouseSystem: HouseSystem.placidus,
    sourceName: sourceName ?? AstrologyDataSources.current.sourceName,
    requireHighPrecision:
        AstrologyDataSources.current.usesHighPrecisionAstroData,
    generatedAt: sevenFixtureGeneratedAt,
  );
  List<Map<String, Object?>> readBack(List<Map<String, Object?>> values) =>
      (jsonDecode(jsonEncode(values)) as List)
          .map((v) => Map<String, Object?>.from(v as Map))
          .toList();

  setUpAll(() {
    originalHouse = HouseSystemSettings.current.value;
    HouseSystemSettings.current.value = HouseSystem.placidus;
    request = range(DateTime.utc(2026, 1, 12), DateTime.utc(2026, 1, 18));
    final watch = Stopwatch()..start();
    canonical = [
      for (var i = 0; i < request.dayCount; i++)
        buildDailyConsultDataV4(request.dailyRequestAt(i)),
    ];
    final canonicalMs = watch.elapsedMilliseconds;
    watch
      ..reset()
      ..start();
    display = buildPeriodSevenDisplayData(request);
    final displayMs = watch.elapsedMilliseconds;
    watch.stop();
    print(
      'PERIOD_DISPLAY_MEASUREMENT ${jsonEncode({'subject': 'fictional fixture only', 'provider': request.sourceName, 'high_precision': request.requireHighPrecision, 'days': request.dayCount, 'canonical_ms': canonicalMs, 'display_ms': displayMs, 'canonical_json_bytes': utf8.encode(jsonEncode(canonical)).length, 'display_json_bytes': utf8.encode(jsonEncode(display)).length, 'order': 'canonical first; display second; single host run; no speed threshold'})}',
    );
  });
  tearDownAll(() => HouseSystemSettings.current.value = originalHouse);

  test(
    'display week retains every canonical forecast and noon, including the 15/16 boundary, through JSON readback',
    () {
      expect(request.dayCount, 7);
      expect(request.listedPointCount, 49);
      expect(request.uniqueInstantCount, 43);
      final before = digest(canonical);
      final reread = readBack(display);
      final result = PeriodSevenDisplayResult.fromData(
        request: request,
        days: reread,
      );
      expect(result.requestIdentity, request.identity);
      expect(result.days.length, 7);
      for (var i = 0; i < 7; i++) {
        validatePeriodSevenDisplayDay(
          data: reread[i],
          request: request.dailyRequestAt(i),
        );
        expect(reread[i]['schema'], 'pancyo_period_display_day_v1');
        expect(
          jsonEncode(reread[i]['intraday_forecasts']),
          jsonEncode(canonical[i]['intraday_forecasts']),
        );
        expect(
          jsonEncode(reread[i]['nine_area_daily']),
          jsonEncode(canonical[i]['nine_area_daily']),
        );
        expect(reread[i].containsKey('intraday_positions'), false);
        expect(reread[i].containsKey('events'), false);
        if (i > 0) {
          expect(
            jsonEncode(fixtureSnapshot(reread[i - 1], 6)),
            jsonEncode(fixtureSnapshot(reread[i], 0)),
          );
        }
      }
      expect(reread[3]['target_date_jst'], '2026-01-15');
      expect(reread[4]['target_date_jst'], '2026-01-16');
      expect(digest(canonical), before);
      expect(digest(result.days), digest(reread));
      expect(
        () => result.days.first['schema'] = 'mutated',
        throwsUnsupportedError,
      );
      expect(
        () => fixturePoints(result.days.first).clear(),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'display and canonical summaries retain identical samples, eight scores, felt and all JA/EN depth explanations',
    () {
      PeriodSevenSummary summarize(bool lightweight) {
        final argsDays = lightweight ? display : canonical;
        return lightweight
            ? PeriodSevenSummary.fromDisplayDays(
                mode: LongRangeMode.week,
                startDateJst: request.startDateJst,
                days: argsDays,
                profile: request.profile,
                details: request.details,
                requestedHouseSystem: request.requestedHouseSystem,
                sourceName: request.sourceName,
                requireHighPrecision: request.requireHighPrecision,
              )
            : PeriodSevenSummary.fromDailyV4(
                mode: LongRangeMode.week,
                startDateJst: request.startDateJst,
                days: argsDays,
                profile: request.profile,
                details: request.details,
                requestedHouseSystem: request.requestedHouseSystem,
                sourceName: request.sourceName,
                requireHighPrecision: request.requireHighPrecision,
              );
      }

      final full = summarize(false), light = summarize(true);
      expect(jsonEncode(light.toJson()), jsonEncode(full.toJson()));
      expect(light.dates, full.dates);
      expect(light.feltCounts, full.feltCounts);
      for (final key in NineAreaKey.values) {
        final a = light.areas.singleWhere((e) => e.key == key);
        final b = full.areas.singleWhere((e) => e.key == key);
        expect(a.score, b.score);
        expect(a.samples, b.samples);
        for (final language in AppLanguage.values) {
          for (final depth in ReadingDepth.values) {
            Map<String, Object?> explanation(PeriodSevenSummary summary) =>
                ForecastExplanation.forPeriod(
                  summary: summary,
                  area: summary.areas.singleWhere((e) => e.key == key),
                  strings: AppStrings(language),
                  depth: depth,
                  supplement: sevenFixtureDetails,
                  dailySamples: summary.predictionsByInstant,
                ).toJson();
            expect(
              jsonEncode(explanation(light)),
              jsonEncode(explanation(full)),
            );
          }
        }
      }
      expect(light.areas.where((e) => e.score != null).length, 8);
      expect(
        light.areas.singleWhere((e) => e.key == NineAreaKey.felt).score,
        isNull,
      );
      expect(
        () => PeriodSevenSummary.fromDisplayDays(
          mode: LongRangeMode.month,
          startDateJst: DateTime.utc(2026, 1),
          days: display,
          profile: request.profile,
          details: request.details,
          requestedHouseSystem: request.requestedHouseSystem,
          sourceName: request.sourceName,
          requireHighPrecision: request.requireHighPrecision,
        ),
        throwsA(anything),
        reason: 'A week or half-month must not become a full-month summary.',
      );
    },
  );

  test(
    'newly calculated month-boundary pair retains canonical 24:00 equals next 00:00 and progress',
    () {
      final pair = range(DateTime.utc(2026, 1, 31), DateTime.utc(2026, 2, 1));
      final progress = <(int, int)>[];
      final calculated = buildPeriodSevenDisplayData(
        pair,
        onProgress: (done, total) => progress.add((done, total)),
      );
      expect(calculated.length, 2);
      for (var i = 0; i < 2; i++) {
        final old = buildDailyConsultDataV4(pair.dailyRequestAt(i));
        expect(
          jsonEncode(calculated[i]['intraday_forecasts']),
          jsonEncode(old['intraday_forecasts']),
        );
        expect(
          jsonEncode(calculated[i]['nine_area_daily']),
          jsonEncode(old['nine_area_daily']),
        );
      }
      expect(
        jsonEncode(fixtureSnapshot(calculated[0], 6)),
        jsonEncode(fixtureSnapshot(calculated[1], 0)),
      );
      expect(progress.last, (14, 14));
      expect(
        progress.every((p) => p.$1 >= 0 && p.$1 <= p.$2 && p.$2 == 14),
        true,
      );
      for (var i = 1; i < progress.length; i++) {
        expect(progress[i].$1, greaterThanOrEqualTo(progress[i - 1].$1));
      }
    },
  );

  test(
    'readback rejects wrong identity, profile, source, clock, noon, precision, missing or duplicate data',
    () {
      final changes = <String, void Function(List<Map<String, Object?>>)>{
        'identity': (days) => days[0]['input_identity'] = 'wrong-input',
        'source': (days) => (days[0]['calculation_source'] as Map)['provider'] =
            'different-provider',
        'precision': (days) =>
            (days[0]['calculation_source']
                    as Map)['provider_uses_high_precision'] =
                !request.requireHighPrecision,
        'date': (days) => days[0]['target_date_jst'] = '2026-01-11',
        'UTC': (days) => fixturePoints(days[0])[1]['instant_utc'] =
            '2026-01-12T00:00:00.000Z',
        'JST': (days) => fixturePoints(days[0])[1]['instant_jst'] =
            '2026-01-12T04:00:00.000Z',
        'noon': (days) =>
            (days[0]['nine_area_daily'] as Map)['target_date_jst'] =
                '2026-01-13',
        'point': (days) => fixturePoints(days[0]).removeLast(),
        'day': (days) => days.removeLast(),
        'duplicate': (days) => days[1] = days[0],
      };
      for (final change in changes.entries) {
        final altered = readBack(display);
        change.value(altered);
        expect(
          () => PeriodSevenDisplayResult.fromData(
            request: request,
            days: altered,
          ),
          throwsA(anything),
          reason: change.key,
        );
      }
      final other = range(
        DateTime.utc(2026, 1, 12),
        DateTime.utc(2026, 1, 18),
        profile: sevenFixtureProfile.copyWith(
          name: 'Another fictional fixture',
        ),
      );
      expect(
        () => PeriodSevenDisplayResult.fromData(
          request: other,
          days: readBack(display),
        ),
        throwsA(anything),
      );
      final valid = PeriodSevenDisplayResult.fromData(
        request: request,
        days: display,
      );
      expect(
        () => validatePeriodSevenDisplayResult(
          result: _WrongIdentity(valid),
          request: request,
        ),
        throwsA(anything),
      );
      expect(
        () => buildPeriodSevenDisplayData(
          range(
            DateTime.utc(2026, 1, 12),
            DateTime.utc(2026, 1, 12),
            sourceName: 'unavailable source',
          ),
        ),
        throwsA(anything),
      );
    },
  );
}
