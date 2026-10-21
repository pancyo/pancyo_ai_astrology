// Synthetic display examples, never evidence of forecast accuracy.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pancyo_ai_astrology/app_language.dart';
import 'package:pancyo_ai_astrology/app_language_settings.dart';
import 'package:pancyo_ai_astrology/main.dart';
import 'package:pancyo_ai_astrology/research/felt_forecast_candidate.dart';

import 'period_seven_test_fixture.dart';

const _profile = AstroProfile(
  name: 'NarrativeSynthetic',
  birthDate: '1990/1/2',
  birthTime: '12:00',
  birthPlace: '札幌市',
  theme: 'fixture',
);

List<NineAreaPrediction> _predictions(int score, {String? felt = '普通'}) => [
  for (final key in NineAreaKey.values)
    NineAreaPrediction(
      key: key,
      title: key.name,
      icon: Icons.circle,
      summary: 'Synthetic',
      detail: 'Synthetic',
      score: key == NineAreaKey.felt ? null : score,
      feltForecast: key == NineAreaKey.felt
          ? FeltForecastResult(felt, const {})
          : null,
    ),
];

NineAreaPeriodSummary _year(
  List<NineAreaPrediction> Function(DateTime) daily,
) => NineAreaPeriodSummary.build(
  mode: LongRangeMode.year,
  month: DateTime.utc(2026),
  year: 2026,
  legacyScores: const {
    NineAreaKey.overall: 70,
    NineAreaKey.love: 70,
    NineAreaKey.work: 70,
    NineAreaKey.money: 70,
  },
  dailyFor: daily,
  useGeneralModel: true,
);

ForecastExplanationResult _explain(
  NineAreaPeriodSummary summary,
  NineAreaKey key,
  AppLanguage language, {
  Map<String, List<NineAreaPrediction>> samples = const {},
  bool evidence = true,
}) => ForecastExplanation.forPeriod(
  summary: summary,
  area: summary.areas.singleWhere((a) => a.key == key),
  strings: AppStrings(language),
  depth: ReadingDepth.detailed,
  dailySamples: samples,
  includeEvidence: evidence,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HouseSystem originalHouse;
  late AppLanguage originalLanguage;
  setUpAll(() {
    originalHouse = HouseSystemSettings.current.value;
    originalLanguage = AppLanguageSettings.current.value;
    HouseSystemSettings.current.value = HouseSystem.placidus;
  });
  tearDownAll(() {
    HouseSystemSettings.current.value = originalHouse;
    AppLanguageSettings.current.value = originalLanguage;
  });

  testWidgets('month year and five-year cards render the replacement reading', (
    tester,
  ) async {
    for (final language in AppLanguage.values) {
      AppLanguageSettings.current.value = language;
      for (final mode in [
        LongRangeDisplayMode.month,
        LongRangeDisplayMode.year,
        LongRangeDisplayMode.fiveYear,
      ]) {
        final request = LongRangeDisplayRequest(
          mode: mode,
          month: DateTime.utc(2026, 10),
          startYear: 2026,
          profile: _profile,
          houseSystem: HouseSystem.placidus,
        );
        final raw = {
          for (final date in request.dates)
            date: _predictions(
              date.month == 1
                  ? 55
                  : date.month == 9
                  ? 90
                  : 73,
            ),
        };
        final summary = LongRangeDisplaySummary.fromSamples(
          request: request,
          samples: raw,
        );
        final samples = {
          for (final entry in raw.entries)
            NineAreaPeriodSummary.dateLabel(entry.key): entry.value,
        };
        await tester.pumpWidget(
          MaterialApp(
            home: AppLanguageScope(
              child: Scaffold(
                body: SingleChildScrollView(
                  child: NineAreaPeriodOverview(
                    summary: summary,
                    depth: ReadingDepth.detailed,
                    dailySamples: samples,
                  ),
                ),
              ),
            ),
          ),
        );
        final expected = _explain(
          summary,
          NineAreaKey.work,
          language,
          samples: samples,
          evidence: false,
        );
        expect(find.text(expected.narrativeText), findsOneWidget);
        expect(find.text(expected.conclusion), findsNothing);
        expect(find.textContaining('24標本がそろっていません'), findsNothing);
        if (mode == LongRangeDisplayMode.fiveYear) {
          expect(
            expected.narrativeText,
            contains(language == AppLanguage.ja ? 'この5年間' : 'These five years'),
          );
          expect(
            expected.narrativeText,
            isNot(contains(language == AppLanguage.ja ? 'この年は' : 'This year:')),
          );
        }
        expect(tester.takeException(), isNull);
      }
    }
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'actual synthetic annual readings stay concise and readable in both languages',
    () {
      final cache = <DateTime, List<NineAreaPrediction>>{};
      List<NineAreaPrediction> daily(DateTime date) => cache.putIfAbsent(
        date,
        () => NineAreaDailyForecast.fromContext(
          const AstrologyEngine().buildPreviewContext(
            profile: _profile,
            date: date,
          ),
        ),
      );
      final summary = _year(daily);
      final samples = {
        for (final date in summary.dates)
          NineAreaPeriodSummary.dateLabel(date): daily(date),
      };
      for (final language in AppLanguage.values) {
        for (final key in NineAreaKey.values) {
          final result = _explain(
            summary,
            key,
            language,
            samples: samples,
            evidence: false,
          );
          final text = result.narrativeText;
          expect(text, isNot(contains('24標本')));
          expect(text, isNot(contains('算術平均')));
          expect(text, isNot(contains('No verified selected material')));
          if (language == AppLanguage.ja) {
            // Two dated, selected aspect interpretations now accompany the
            // reading. This is a bounded body, never the full evidence ledger.
            expect(text.length, inInclusiveRange(100, 600), reason: key.name);
          } else {
            expect(
              RegExp(r'[\u3040-\u30ff\u3400-\u9fff]').hasMatch(text),
              false,
            );
          }
          if (const bool.fromEnvironment('PRINT_NARRATIVE_QA')) {
            debugPrint(
              jsonEncode({
                'synthetic_narrative_qa': true,
                'language': language.name,
                'area': key.name,
                'length': text.length,
                'text': text,
              }),
            );
          }
        }
      }
    },
  );

  test(
    'detailed daily copy gives a field-specific reading, with evidence separate',
    () {
      for (final language in AppLanguage.values) {
        for (final prediction in _predictions(90, felt: '良い')) {
          final explanation = ForecastExplanation.forDaily(
            prediction: prediction,
            targetDate: DateTime.utc(2026, 10, 21, 3),
            strings: AppStrings(language),
            depth: ReadingDepth.detailed,
          );
          final before = jsonEncode(explanation.toJson());
          final text = explanation.narrativeText;
          expect(text, isNot(contains('Model:')));
          expect(text, isNot(contains('model_version')));
          expect(text, isNot(contains('正の材料')));
          expect(text, isNot(contains('No verified selected material')));
          expect(text.split('\n\n').length, inInclusiveRange(2, 3));
          expect(jsonEncode(explanation.toJson()), before);
          expect(explanation.toJson().containsKey('display_narrative'), false);
          expect(explanation.numericLedgerText, contains('Model:'));
          if (language == AppLanguage.en) {
            expect(
              RegExp(r'[\u3040-\u30ff\u3400-\u9fff]').hasMatch(text),
              false,
            );
          } else {
            expect(text.length, lessThan(250));
          }
          if (prediction.key == NineAreaKey.actionDecision) {
            expect(
              text,
              contains(language == AppLanguage.ja ? '活動性' : 'activity'),
            );
            expect(
              text,
              isNot(
                contains(
                  language == AppLanguage.ja ? '比較的進めやすい' : 'more supportive',
                ),
              ),
            );
          }
          if (prediction.key == NineAreaKey.felt)
            expect(explanation.score, isNull);
        }
      }
    },
  );

  test(
    'year names actual tied high and low months without a calculation preamble',
    () {
      List<NineAreaPrediction> daily(DateTime date) => _predictions(
        [4, 9].contains(date.month)
            ? 90
            : [1, 7].contains(date.month)
            ? 55
            : 72,
      );
      final summary = _year(daily);
      final samples = {
        for (final date in summary.dates)
          NineAreaPeriodSummary.dateLabel(date): daily(date),
      };
      final before = jsonEncode(summary.toJson());
      for (final language in AppLanguage.values) {
        final explanation = _explain(
          summary,
          NineAreaKey.work,
          language,
          samples: samples,
        );
        final text = explanation.narrativeText;
        for (final month
            in language == AppLanguage.ja
                ? ['4月', '9月', '1月', '7月']
                : ['April', 'September', 'January', 'July']) {
          expect(text, contains(month));
        }
        expect(text, isNot(contains('24標本')));
        expect(text, isNot(contains('確認日の総合点を集計')));
        expect(text.split('\n\n').length, 3);
        if (language == AppLanguage.ja) expect(text.length, lessThan(280));
        expect(
          _explain(
            summary,
            NineAreaKey.work,
            language,
            samples: samples,
            evidence: false,
          ).narrativeText,
          text,
        );
      }
      expect(jsonEncode(summary.toJson()), before);
    },
  );

  test(
    'flat and sub-point yearly spreads do not manufacture favorable months',
    () {
      for (final summary in [
        _year((_) => _predictions(70)),
        _year((d) => _predictions(d.month == 1 && d.day == 15 ? 71 : 70)),
      ]) {
        final text = _explain(
          summary,
          NineAreaKey.work,
          AppLanguage.ja,
        ).narrativeText;
        expect(text, contains('横ばい'));
        expect(text, isNot(contains('比較的進めやすい')));
      }
    },
  );

  test(
    'English month timing has one around for numeric activity and felt readings',
    () {
      final request = LongRangeDisplayRequest(
        mode: LongRangeDisplayMode.month,
        month: DateTime.utc(2026, 10),
        startYear: 2026,
        profile: _profile,
        houseSystem: HouseSystem.placidus,
      );
      final raw = {
        for (final date in request.dates)
          date: _predictions(
            date.day == 1
                ? 90
                : date.day == 8
                ? 55
                : 73,
            felt: date.day == 1
                ? '良い'
                : date.day == 8
                ? '悪い'
                : '普通',
          ),
      };
      final summary = LongRangeDisplaySummary.fromSamples(
        request: request,
        samples: raw,
      );
      final samples = {
        for (final entry in raw.entries)
          NineAreaPeriodSummary.dateLabel(entry.key): entry.value,
      };
      for (final key in [
        NineAreaKey.work,
        NineAreaKey.actionDecision,
        NineAreaKey.felt,
      ]) {
        final result = _explain(
          summary,
          key,
          AppLanguage.en,
          samples: samples,
          evidence: false,
        );
        final before = jsonEncode(result.toJson());
        final ledger = result.numericLedgerText;
        final timingText = result.narrativeText.toLowerCase();
        expect(timingText, contains('around october 1'));
        expect(timingText, contains('around october 8'));
        expect(timingText, isNot(contains('around around')));
        expect(
          RegExp(
            r'[\u3040-\u30ff\u3400-\u9fff]',
          ).hasMatch(result.narrativeText),
          false,
        );
        expect(jsonEncode(result.toJson()), before);
        expect(result.numericLedgerText, ledger);
      }
    },
  );

  test(
    'simple yearly card has a reading while canonical explanation stays intact',
    () {
      final summary = _year((_) => _predictions(90));
      final result = ForecastExplanation.forPeriod(
        summary: summary,
        area: summary.areas.singleWhere((a) => a.key == NineAreaKey.work),
        strings: const AppStrings(AppLanguage.ja),
      );
      expect(result.narrativeText, contains('準備した仕事'));
      expect(result.narrativeText, isNot(contains('確認日を集計')));
      expect(result.conclusion, contains('試作値'));
      expect(result.text, contains('試作値'));
    },
  );

  test('felt ties stay categorical and missing labels remain unavailable', () {
    List<NineAreaPrediction> daily(DateTime d) =>
        _predictions(75, felt: d.day == 1 ? '良い' : '悪い');
    final summary = _year(daily);
    final result = _explain(
      summary,
      NineAreaKey.felt,
      AppLanguage.ja,
      samples: {
        for (final d in summary.dates)
          NineAreaPeriodSummary.dateLabel(d): daily(d),
      },
    );
    expect(result.score, isNull);
    expect(result.narrativeText, contains('体感が混ざる'));
    expect(result.narrativeText, contains('良い'));
    expect(result.narrativeText, contains('悪い'));
    expect(result.narrativeText, isNot(contains('点の体感')));
    final missing = _explain(
      _year((_) => _predictions(75, felt: null)),
      NineAreaKey.felt,
      AppLanguage.ja,
    );
    expect(missing.narrativeText, contains('未予測'));
    expect(missing.narrativeText, isNot(contains('普通')));
  });

  test('five-year reading compares the five actual years', () {
    final request = LongRangeDisplayRequest(
      mode: LongRangeDisplayMode.fiveYear,
      month: DateTime.utc(2026),
      startYear: 2026,
      profile: _profile,
      houseSystem: HouseSystem.placidus,
    );
    final summary = LongRangeDisplaySummary.fromSamples(
      request: request,
      samples: {
        for (final d in request.dates)
          d: _predictions(
            d.year == 2027
                ? 91
                : d.year == 2029
                ? 56
                : 73,
          ),
      },
    );
    final text = _explain(
      summary,
      NineAreaKey.work,
      AppLanguage.ja,
    ).narrativeText;
    expect(text, contains('この5年間'));
    expect(text, contains('2027年'));
    expect(text, contains('2029年'));
    expect(text, isNot(contains('24標本')));
  });

  test(
    'single-day seven-point reading names 24:00 within the selected day',
    () {
      final fixture = SyntheticSevenPeriodFixture();
      final request = fixtureWeekRequest(DateTime.utc(2026, 12, 28));
      final wrapper = fixture.week(request);
      final week = PeriodSevenSummary.fromDailyV4(
        mode: LongRangeMode.week,
        startDateJst: DateTime.utc(2026, 12, 28),
        days: (wrapper['days'] as List)
            .map((e) => Map<String, Object?>.from(e as Map))
            .toList(),
        profile: sevenFixtureProfile,
        details: sevenFixtureDetails,
        requestedHouseSystem: HouseSystem.placidus,
        sourceName: AstrologyDataSources.current.sourceName,
        requireHighPrecision:
            AstrologyDataSources.current.usesHighPrecisionAstroData,
      );
      final day = week.daySummaryAt(0);
      final text = _explain(
        day,
        NineAreaKey.work,
        AppLanguage.ja,
        samples: day.predictionsByInstant,
      ).narrativeText;
      expect(text, contains('この日'));
      expect(text, contains('24時'));
      expect(text, isNot(contains('12/29')));
    },
  );
}
