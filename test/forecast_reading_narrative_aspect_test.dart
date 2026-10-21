// Synthetic geometry and existing model traces only; never accuracy evidence.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pancyo_ai_astrology/app_language.dart';
import 'package:pancyo_ai_astrology/main.dart';
import 'package:pancyo_ai_astrology/research/felt_forecast_candidate.dart';
import 'package:pancyo_ai_astrology/research/nine_area_general_forecast.dart';
import 'package:pancyo_ai_astrology/research/nine_area_model_contract.dart';

const _profile = AstroProfile(
  name: 'AspectNarrativeSynthetic',
  birthDate: '1990/1/2',
  birthTime: '12:00',
  birthPlace: '札幌市',
  theme: 'fixture',
);
final _date = DateTime.utc(2026, 10, 21, 3);

List<NineAreaPrediction> _fixture() {
  const names = [
    'sun',
    'moon',
    'mercury',
    'venus',
    'mars',
    'jupiter',
    'saturn',
    'uranus',
    'neptune',
    'pluto',
  ];
  const transits = [
    10.5,
    100.8,
    192.0,
    42.0,
    252.0,
    132.0,
    12.0,
    72.0,
    162.0,
    282.0,
  ];
  final result = GeneralNineAreaForecast.calculate(
    instantUtc: _date,
    natalLongitudes: {
      for (var i = 0; i < names.length; i++) names[i]: 10.0 + i * 30,
    },
    transitLongitudes: {
      for (var i = 0; i < names.length; i++) names[i]: transits[i],
    },
    natalMoonHouse: 4,
    moonInStellium: false,
  );
  return [
    for (final key in NineAreaKey.values)
      NineAreaPrediction(
        key: key,
        title: key.name,
        icon: Icons.circle,
        summary: 'Synthetic',
        detail: 'Synthetic',
        provisional: true,
        score: result.numeric[key.name]?['score'] as int?,
        scoreBreakdown:
            result.numeric[key.name]?['score_breakdown']
                as Map<String, Object?>?,
        feltForecast: key == NineAreaKey.felt
            ? NineAreaModelContract.primaryFromComparison(result.felt)
            : null,
      ),
  ];
}

ForecastExplanationResult _daily(
  NineAreaPrediction p,
  AppLanguage language, {
  List<NineAreaPrediction> related = const [],
  ReadingDepth depth = ReadingDepth.detailed,
}) => ForecastExplanation.forDaily(
  prediction: p,
  targetDate: _date,
  strings: AppStrings(language),
  relatedPredictions: related,
  depth: depth,
);

NineAreaPrediction _copy(
  NineAreaPrediction p, {
  Map<String, Object?>? breakdown,
  FeltForecastResult? felt,
  Map<String, Object?>? context,
}) => NineAreaPrediction(
  key: p.key,
  title: p.title,
  icon: p.icon,
  summary: p.summary,
  detail: p.detail,
  score: p.score,
  provisional: p.provisional,
  scoreBreakdown: breakdown ?? p.scoreBreakdown,
  feltForecast: felt ?? p.feltForecast,
  longTermContext: context,
);

Map<String, Object?> _clone(Map<String, Object?> source) =>
    Map<String, Object?>.from(jsonDecode(jsonEncode(source)) as Map);

// Independent selection oracle: only actual selected group representative IDs
// may appear as score drivers. All group members are deliberately not accepted.
List<Map> _selected(NineAreaPrediction p, List<NineAreaPrediction> related) {
  if (p.key == NineAreaKey.felt)
    return (p.feltForecast!.trace['selected_aspects'] as List).cast<Map>();
  if (p.key == NineAreaKey.overall)
    return [
      for (final source in related.where(
        (p) => const {
          NineAreaKey.love,
          NineAreaKey.work,
          NineAreaKey.money,
          NineAreaKey.mental,
          NineAreaKey.health,
          NineAreaKey.people,
        }.contains(p.key),
      ))
        ..._selected(source, related),
    ];
  final trace = p.scoreBreakdown!['design_trace'] as Map;
  final ids = <Object?>{};
  for (final group in (trace['groups'] as List).cast<Map>()) {
    if (group['selected'] != true) continue;
    if (p.key == NineAreaKey.actionDecision) {
      ids.add(group['stimulus_factor_id']);
    } else {
      ids.add(group['positive_factor_id']);
      ids.add(group['negative_factor_id']);
    }
  }
  return (trace['factors'] as List)
      .cast<Map>()
      .where((row) => ids.contains(row['id']))
      .toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'all nine detailed daily readings show selected real aspect facts in JA and EN',
    () {
      final predictions = _fixture();
      for (final language in AppLanguage.values) {
        for (final p in predictions) {
          final result = _daily(p, language, related: predictions);
          final text = result.narrativeText;
          final before = jsonEncode(result.toJson());
          expect(
            text,
            contains(language == AppLanguage.ja ? 'オーブ' : 'orb'),
            reason: p.key.name,
          );
          expect(
            text,
            contains(language == AppLanguage.ja ? 'という象徴' : 'Symbolically'),
            reason: p.key.name,
          );
          expect(text.split('\n\n').length, 3);
          expect(
            text.length,
            lessThan(language == AppLanguage.ja ? 600 : 1600),
          );
          final rows = _selected(p, predictions);
          expect(rows, isNotEmpty, reason: p.key.name);
          if (language == AppLanguage.en) {
            expect(
              RegExp(r'[\u3040-\u30ff\u3400-\u9fff]').hasMatch(text),
              false,
            );
            final pairs = RegExp(
              r'transiting (\w+) in (\w+) with natal (\w+), (\d+)° \(orb ([\d.]+)°\)',
            ).allMatches(text).toList();
            expect(pairs, isNotEmpty);
            expect(pairs.length, lessThanOrEqualTo(2));
            for (final pair in pairs) {
              expect(
                rows.any(
                  (row) =>
                      row['transit_planet'] == pair[1]!.toLowerCase() &&
                      row['aspect_type'] == pair[2] &&
                      row['natal_planet'] == pair[3]!.toLowerCase() &&
                      (row['orb_degrees'] as num).toStringAsFixed(2) == pair[5],
                ),
                true,
                reason:
                    '${p.key.name}: ${pair[0]} must be an adopted representative',
              );
            }
          }
          expect(jsonEncode(result.toJson()), before);
          expect(result.toJson().containsKey('display_narrative'), false);
          final withoutPeers = _daily(p, language);
          expect(
            result.toJson(),
            withoutPeers.toJson(),
            reason: 'Display peer evidence cannot alter serialization.',
          );
          expect(result.numericLedgerText, withoutPeers.numericLedgerText);
          final simple = _daily(
            p,
            language,
            related: predictions,
            depth: ReadingDepth.simple,
          ).narrativeText;
          expect(
            simple,
            isNot(contains(language == AppLanguage.ja ? 'オーブ' : 'orb')),
          );
        }
      }
      final activity = _daily(
        predictions.singleWhere((p) => p.key == NineAreaKey.actionDecision),
        AppLanguage.en,
      ).narrativeText;
      expect(activity, contains('Selected activity stimulus'));
      expect(activity, isNot(contains('Selected supportive factor')));
      final felt = _daily(
        predictions.singleWhere((p) => p.key == NineAreaKey.felt),
        AppLanguage.en,
      );
      expect(felt.score, isNull);
    },
  );

  test(
    'overall requires matching mean components and never claims an independent aspect bonus',
    () {
      final predictions = _fixture();
      final overall = predictions.singleWhere(
        (p) => p.key == NineAreaKey.overall,
      );
      expect(
        _daily(overall, AppLanguage.en).narrativeText,
        contains('No usable selected aspect'),
      );
      expect(
        _daily(overall, AppLanguage.en, related: predictions).narrativeText,
        contains('a component of the overall mean'),
      );
      final changed = _clone(overall.scoreBreakdown!);
      final trace = changed['design_trace'] as Map;
      (trace['source_area_scores'] as Map)['love'] = 50;
      expect(
        _daily(
          _copy(overall, breakdown: changed),
          AppLanguage.en,
          related: predictions,
        ).narrativeText,
        contains('No usable selected aspect'),
      );
    },
  );

  test(
    'unselected groups and malformed geometry are never promoted from labels',
    () {
      final p = _fixture().singleWhere((p) => p.key == NineAreaKey.work);
      for (final corrupt in ['unselected', 'unknown_planet', 'nonfinite_orb']) {
        final b = _clone(p.scoreBreakdown!);
        final trace = b['design_trace'] as Map;
        if (corrupt == 'unselected') {
          for (final group in (trace['groups'] as List).cast<Map>()) {
            group['selected'] = false;
          }
        } else {
          for (final factor in (trace['factors'] as List).cast<Map>()) {
            if (corrupt == 'unknown_planet') {
              factor['natal_planet'] = 'invented';
            } else {
              factor['orb_degrees'] = double.nan;
            }
          }
        }
        final result = _daily(_copy(p, breakdown: b), AppLanguage.en);
        expect(
          result.narrativeText,
          contains('No usable selected aspect'),
          reason: corrupt,
        );
        expect(result.narrativeText, isNot(contains('orb')));
      }
    },
  );

  test(
    'slow reference is explicitly unscored and canonical felt stays categorical',
    () {
      final p = _fixture().singleWhere((p) => p.key == NineAreaKey.felt);
      final empty = FeltForecastCandidate.predict(
        natalMoonSign: 'taurus',
        natalMoonHouse: 4,
        moonInStellium: false,
        aspects: const [],
        lunarElongationDegrees: 90,
      );
      final context = <String, Object?>{
        'context_version': 'slow-transit-context-20261003-1',
        'status': 'configuration_only_unvalidated',
        'score_effect': 0,
        'predicts_felt_label': false,
        'reference': 'provided_transit_positions_against_natal_chart',
        'aspects': [
          <String, Object?>{
            'transit_planet': 'saturn',
            'natal_point': 'sun',
            'aspect_type': 'square',
            'orb_degrees': 1.5,
            'configuration_kind': 'tense',
          },
        ],
      };
      for (final language in AppLanguage.values) {
        final result = _daily(
          _copy(p, felt: empty, context: context),
          language,
        );
        expect(result.score, isNull);
        expect(result.feltLabel, empty.label);
        expect(
          result.narrativeText,
          contains(
            language == AppLanguage.ja
                ? '体感判定へは未加算'
                : 'not added to the felt label',
          ),
        );
        expect(
          result.narrativeText,
          contains(
            language == AppLanguage.ja
                ? 'スクエア90°'
                : 'square with natal Sun, 90°',
          ),
        );
        expect(result.narrativeText, contains('1.50°'));
      }
      expect(
        _daily(
          _copy(p, felt: empty, context: {...context, 'score_effect': 1}),
          AppLanguage.en,
        ).narrativeText,
        contains('No usable selected aspect'),
      );
    },
  );

  test(
    'month year and five-year detailed prose uses dated existing samples and bounded facts',
    () {
      final predictions = _fixture();
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
        final raw = {for (final date in request.dates) date: predictions};
        final summary = LongRangeDisplaySummary.fromSamples(
          request: request,
          samples: raw,
        );
        final samples = {
          for (final entry in raw.entries)
            NineAreaPeriodSummary.dateLabel(entry.key): entry.value,
        };
        for (final language in AppLanguage.values) {
          for (final area in summary.areas) {
            final result = ForecastExplanation.forPeriod(
              summary: summary,
              area: area,
              strings: AppStrings(language),
              depth: ReadingDepth.detailed,
              dailySamples: samples,
              includeEvidence: false,
            );
            final text = result.narrativeText;
            expect(
              text,
              contains(language == AppLanguage.ja ? 'JSTの確認例' : 'Sample on'),
              reason: '${mode.name}/${area.key.name}',
            );
            expect(text, contains(language == AppLanguage.ja ? 'オーブ' : 'orb'));
            expect(
              RegExp(
                language == AppLanguage.ja ? 'JSTの確認例' : 'Sample on',
              ).allMatches(text).length,
              lessThanOrEqualTo(2),
            );
            expect(text, isNot(contains('24標本')));
            expect(text, isNot(contains('lasts throughout')));
            if (language == AppLanguage.en)
              expect(
                RegExp(r'[\u3040-\u30ff\u3400-\u9fff]').hasMatch(text),
                false,
              );
            if (mode == LongRangeDisplayMode.fiveYear) {
              expect(
                text,
                contains(
                  language == AppLanguage.ja ? 'この5年間' : 'These five years',
                ),
              );
              expect(text, contains('2030'));
            }
          }
        }
      }
    },
  );

  test(
    'day and week seven-point detailed readings interpret existing sampled traces for all nine areas',
    () {
      final start = DateTime.utc(2026, 10, 19);
      final request = PeriodSevenDisplayRequest(
        startDateJst: start,
        endDateJst: DateTime.utc(2026, 10, 25),
        profile: _profile,
        details: const UserProfileDetails.empty(),
        requestedHouseSystem: HouseSystemSettings.current.value,
        sourceName: AstrologyDataSources.current.sourceName,
        requireHighPrecision:
            AstrologyDataSources.current.usesHighPrecisionAstroData,
        generatedAt: DateTime.utc(2026, 10, 18, 3),
      );
      // Calculate the fixture once. Explanation calls below receive only these
      // existing in-memory samples, just as the normal display does.
      final days = buildPeriodSevenDisplayData(request);
      final summaries = [
        PeriodSevenSummary.fromDisplayRange(
          startDateJst: start,
          endDateJst: start,
          days: [days.first],
          profile: _profile,
          details: request.details,
          requestedHouseSystem: request.requestedHouseSystem,
          sourceName: request.sourceName,
          requireHighPrecision: request.requireHighPrecision,
        ),
        PeriodSevenSummary.fromDisplayDays(
          mode: LongRangeMode.week,
          startDateJst: start,
          days: days,
          profile: _profile,
          details: request.details,
          requestedHouseSystem: request.requestedHouseSystem,
          sourceName: request.sourceName,
          requireHighPrecision: request.requireHighPrecision,
        ),
      ];
      for (final summary in summaries) {
        final before = jsonEncode(days);
        expect(summary.uniqueInstantCount, summary.isSingleDay ? 7 : 43);
        for (final language in AppLanguage.values) {
          for (final area in summary.areas) {
            final result = ForecastExplanation.forPeriod(
              summary: summary,
              area: area,
              strings: AppStrings(language),
              depth: ReadingDepth.detailed,
              dailySamples: summary.predictionsByInstant,
              includeEvidence: false,
            );
            final text = result.narrativeText;
            expect(
              text,
              contains(language == AppLanguage.ja ? 'JSTの確認例' : 'Sample on'),
              reason: '${summary.isSingleDay}/${area.key.name}',
            );
            expect(text, contains(language == AppLanguage.ja ? 'オーブ' : 'orb'));
            expect(
              RegExp(
                language == AppLanguage.ja ? 'JSTの確認例' : 'Sample on',
              ).allMatches(text).length,
              lessThanOrEqualTo(2),
            );
            if (language == AppLanguage.en)
              expect(
                RegExp(r'[\u3040-\u30ff\u3400-\u9fff]').hasMatch(text),
                false,
              );
            final simple = ForecastExplanation.forPeriod(
              summary: summary,
              area: area,
              strings: AppStrings(language),
              dailySamples: summary.predictionsByInstant,
              includeEvidence: false,
            ).narrativeText;
            expect(
              simple,
              isNot(contains(language == AppLanguage.ja ? 'オーブ' : 'orb')),
            );
          }
        }
        expect(jsonEncode(days), before);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
