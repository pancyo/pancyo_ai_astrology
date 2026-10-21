// Explicit display scores only; no astronomy, native job, or persistence call.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pancyo_ai_astrology/app_language.dart';
import 'package:pancyo_ai_astrology/main.dart';

List<NineAreaPrediction> _predictions(Map<NineAreaKey, int?> scores) => [
  for (final entry in scores.entries)
    NineAreaPrediction(
      key: entry.key,
      title: entry.key.name,
      icon: Icons.circle,
      summary: 'Synthetic',
      detail: 'Synthetic',
      score: entry.value,
    ),
];

const _boundaryScores = <NineAreaKey, int?>{
  NineAreaKey.overall: 99,
  NineAreaKey.love: 80,
  NineAreaKey.work: 79,
  NineAreaKey.money: 70,
  NineAreaKey.mental: 71,
  NineAreaKey.health: 99,
  NineAreaKey.people: 50,
  NineAreaKey.actionDecision: 69,
  NineAreaKey.felt: null,
};

// An incomplete display fixture, not a calculated period. Only existing final
// entry values are provided; reading any other period material is an error.
class _DisplayedSummary extends Fake implements NineAreaPeriodSummary {
  _DisplayedSummary(List<NineAreaPrediction> predictions)
    : areas = [
        for (final prediction in predictions)
          NineAreaPeriodEntry(
            key: prediction.key,
            title: prediction.title,
            icon: prediction.icon,
            score: prediction.score,
            samples: const [],
            inherited: false,
          ),
      ];

  @override
  final List<NineAreaPeriodEntry> areas;
}

void main() {
  test(
    'inclusive 80/70 highlights include seven numeric areas and exclude overall and felt',
    () {
      final predictions = _predictions(_boundaryScores);
      final before = [for (final p in predictions) (p.key, p.score)];
      final result = OverallAreaHighlights.fromPredictions(predictions);
      expect(result.higher, {NineAreaKey.love: 80, NineAreaKey.health: 99});
      expect(result.careNeeded, {
        NineAreaKey.money: 70,
        NineAreaKey.people: 50,
        NineAreaKey.actionDecision: 69,
      });
      expect(result.missing, isEmpty);
      expect(result.scores.length, 7);
      expect(result.scores.containsKey(NineAreaKey.overall), false);
      expect(result.scores[NineAreaKey.actionDecision], 69);
      expect(result.scores.containsKey(NineAreaKey.felt), false);
      for (final language in AppLanguage.values) {
        final strings = AppStrings(language);
        final lines = result.lines(strings);
        expect(lines.length, 2);
        expect(result.text(strings), lines.join('\n'));
        expect(
          lines[0],
          startsWith(
            language == AppLanguage.ja ? '高め（80点以上）：' : 'Higher (80+): ',
          ),
        );
        expect(
          lines[1],
          startsWith(
            language == AppLanguage.ja
                ? '注意（70点以下）：'
                : 'Care needed (70 or below): ',
          ),
        );
        expect(
          lines[0],
          contains(
            '${strings.nineAreaTitle('love')}${language == AppLanguage.en ? ' ' : ''}80',
          ),
        );
        expect(
          lines[1],
          contains(
            '${strings.nineAreaTitle('money')}${language == AppLanguage.en ? ' ' : ''}70',
          ),
        );
        for (final excluded in [NineAreaKey.overall, NineAreaKey.felt]) {
          expect(
            result.text(strings),
            isNot(contains(strings.nineAreaTitle(excluded.name))),
          );
        }
        if (language == AppLanguage.en) {
          expect(
            RegExp(
              r'[\u3040-\u30ff\u3400-\u9fff\uff00-\uffef]',
            ).hasMatch(result.text(strings)),
            false,
          );
        }
      }
      expect([for (final p in predictions) (p.key, p.score)], before);
      expect(
        () => result.scores[NineAreaKey.love] = 50,
        throwsUnsupportedError,
      );
      expect(
        () => result.missing.add(NineAreaKey.work),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'complete middle scores mean none; missing values remain unavailable, never zero',
    () {
      final scores = {
        for (final key in OverallAreaHighlights.highlightKeys) key: 75,
      };
      final complete = OverallAreaHighlights.fromPredictions(
        _predictions(scores),
      );
      final partial = OverallAreaHighlights.fromPredictions(
        _predictions({...scores, NineAreaKey.work: null}),
      );
      final absent = OverallAreaHighlights.fromPredictions(
        _predictions({
          for (final entry in scores.entries)
            if (entry.key != NineAreaKey.work) entry.key: entry.value,
        }),
      );
      for (final language in AppLanguage.values) {
        final strings = AppStrings(language);
        expect(complete.lines(strings).length, 2);
        expect(
          complete
              .lines(strings)
              .every(
                (line) =>
                    line.endsWith(language == AppLanguage.ja ? '該当なし' : 'None'),
              ),
          true,
        );
        for (final missing in [partial, absent]) {
          expect(missing.lines(strings).length, 3);
          expect(
            missing.lines(strings)[0],
            endsWith(
              language == AppLanguage.ja
                  ? '確認済みでは該当なし'
                  : 'None among available areas',
            ),
          );
          expect(
            missing.lines(strings).last,
            '${language == AppLanguage.ja ? '未取得：' : 'Unavailable: '}${strings.nineAreaTitle('work')}',
          );
          expect(missing.scores.containsKey(NineAreaKey.work), false);
          expect(missing.careNeeded, isEmpty);
          expect(missing.missing, [NineAreaKey.work]);
        }
        final allMissing = OverallAreaHighlights.fromPredictions(const []);
        expect(allMissing.scores, isEmpty);
        expect(allMissing.higher, isEmpty);
        expect(allMissing.careNeeded, isEmpty);
        expect(
          allMissing.lines(strings)[0],
          endsWith(language == AppLanguage.ja ? '未予測' : 'Unavailable'),
        );
        expect(
          allMissing.lines(strings).last,
          language == AppLanguage.ja ? '未取得：全7項目' : 'Unavailable: all 7 areas',
        );
      }
    },
  );

  test(
    'ambiguous and out-of-contract values stay missing without hiding valid highlights',
    () {
      final predictions = _predictions({
        NineAreaKey.love: 82,
        NineAreaKey.work: 0,
        NineAreaKey.money: 100,
        NineAreaKey.mental: null,
        NineAreaKey.health: 68,
        NineAreaKey.people: 85,
        NineAreaKey.actionDecision: 79,
      });
      predictions.addAll(_predictions({NineAreaKey.people: 85}));
      final result = OverallAreaHighlights.fromPredictions(predictions);
      expect(result.higher, {NineAreaKey.love: 82});
      expect(result.careNeeded, {NineAreaKey.health: 68});
      expect(result.missing, [
        NineAreaKey.work,
        NineAreaKey.money,
        NineAreaKey.mental,
        NineAreaKey.people,
      ]);
      expect(result.scores.values, everyElement(inInclusiveRange(50, 99)));
      for (final language in AppLanguage.values) {
        final lines = result.lines(AppStrings(language));
        expect(lines.length, 3);
        expect(lines[0], contains('82'));
        expect(lines[1], contains('68'));
        expect(lines.last, isNot(contains('0')));
      }
    },
  );

  test(
    'period highlights use final displayed inherited scores and preserve period JSON',
    () {
      final daily = _predictions({
        ..._boundaryScores,
        NineAreaKey.love: 55,
        NineAreaKey.work: 95,
        NineAreaKey.money: 99,
        NineAreaKey.mental: 79,
        NineAreaKey.health: 71,
      });
      final summary = NineAreaPeriodSummary.build(
        mode: LongRangeMode.month,
        month: DateTime.utc(2026, 10),
        year: 2026,
        legacyScores: const {
          NineAreaKey.overall: 96,
          NineAreaKey.love: 80,
          NineAreaKey.work: 70,
          NineAreaKey.money: 75,
        },
        dailyFor: (_) => daily,
      );
      final before = jsonEncode(summary.toJson());
      final result = OverallAreaHighlights.fromSummary(summary);
      expect(result.higher, {NineAreaKey.love: 80});
      expect(result.careNeeded, {
        NineAreaKey.work: 70,
        NineAreaKey.people: 50,
        NineAreaKey.actionDecision: 69,
      });
      expect(result.missing, isEmpty);
      expect(result.scores, {
        NineAreaKey.love: 80,
        NineAreaKey.work: 70,
        NineAreaKey.money: 75,
        NineAreaKey.mental: 79,
        NineAreaKey.health: 71,
        NineAreaKey.people: 50,
        NineAreaKey.actionDecision: 69,
      });
      expect(
        OverallAreaHighlights.fromPredictions(
          daily,
        ).higher.containsKey(NineAreaKey.work),
        true,
      );
      for (final language in AppLanguage.values) {
        result.text(AppStrings(language));
      }
      expect(jsonEncode(summary.toJson()), before);
    },
  );

  test(
    'activity 69 is care needed and 70/71/79/80 boundaries hold for daily and period in JA/EN',
    () {
      for (final activity in [69, 70, 71, 79, 80]) {
        final predictions = _predictions({
          ..._boundaryScores,
          NineAreaKey.actionDecision: activity,
        });
        final dailyBefore = [for (final p in predictions) (p.key, p.score)];
        final summary = NineAreaPeriodSummary.build(
          mode: LongRangeMode.month,
          month: DateTime.utc(2026, 10),
          year: 2026,
          legacyScores: const {
            NineAreaKey.overall: 96,
            NineAreaKey.love: 80,
            NineAreaKey.work: 70,
            NineAreaKey.money: 75,
          },
          dailyFor: (_) => predictions,
          useGeneralModel: true,
        );
        final periodBefore = jsonEncode(summary.toJson());
        final helpers = [
          OverallAreaHighlights.fromPredictions(predictions),
          OverallAreaHighlights.fromSummary(summary),
        ];
        for (final helper in helpers) {
          expect(helper.scores[NineAreaKey.actionDecision], activity);
          expect(
            helper.higher.containsKey(NineAreaKey.actionDecision),
            activity >= 80,
          );
          expect(
            helper.careNeeded.containsKey(NineAreaKey.actionDecision),
            activity <= 70,
          );
          expect(helper.missing, isEmpty);
          for (final language in AppLanguage.values) {
            final strings = AppStrings(language);
            final title = strings.nineAreaTitle('actionDecision');
            final item =
                '$title${language == AppLanguage.en ? ' ' : ''}$activity';
            final lines = helper.lines(strings);
            expect(lines.length, 2);
            expect(lines[0].contains(item), activity >= 80);
            expect(lines[1].contains(item), activity <= 70);
            if (activity > 70 && activity < 80) {
              expect(helper.text(strings), isNot(contains(title)));
            }
            if (language == AppLanguage.en) {
              expect(
                RegExp(
                  r'[\u3040-\u30ff\u3400-\u9fff\uff00-\uffef]',
                ).hasMatch(helper.text(strings)),
                false,
              );
            }
          }
        }
        expect([for (final p in predictions) (p.key, p.score)], dailyBefore);
        expect(jsonEncode(summary.toJson()), periodBefore);
      }
    },
  );

  test(
    'missing activity remains unavailable in daily and period highlights, never care at zero',
    () {
      final withNull = _predictions({
        ..._boundaryScores,
        NineAreaKey.actionDecision: null,
      });
      for (final predictions in [
        withNull,
        withNull.where((p) => p.key != NineAreaKey.actionDecision).toList(),
      ]) {
        final summary = _DisplayedSummary(predictions);
        final before = [
          for (final area in summary.areas) (area.key, area.score),
        ];
        for (final helper in [
          OverallAreaHighlights.fromPredictions(predictions),
          OverallAreaHighlights.fromSummary(summary),
        ]) {
          expect(helper.scores.containsKey(NineAreaKey.actionDecision), false);
          expect(
            helper.careNeeded.containsKey(NineAreaKey.actionDecision),
            false,
          );
          expect(helper.higher.containsKey(NineAreaKey.actionDecision), false);
          expect(helper.missing, [NineAreaKey.actionDecision]);
          for (final language in AppLanguage.values) {
            final strings = AppStrings(language);
            final title = strings.nineAreaTitle('actionDecision');
            final lines = helper.lines(strings);
            expect(lines.length, 3);
            expect(lines[0], isNot(contains(title)));
            expect(lines[1], isNot(contains(title)));
            expect(
              lines.last,
              '${language == AppLanguage.ja ? '未取得：' : 'Unavailable: '}$title',
            );
          }
        }
        expect([
          for (final area in summary.areas) (area.key, area.score),
        ], before);
      }
      final emptySummary = OverallAreaHighlights.fromSummary(
        _DisplayedSummary(const []),
      );
      expect(emptySummary.scores, isEmpty);
      expect(emptySummary.missing.length, 7);
      expect(
        emptySummary.lines(const AppStrings(AppLanguage.ja)).last,
        '未取得：全7項目',
      );
      expect(
        emptySummary.lines(const AppStrings(AppLanguage.en)).last,
        'Unavailable: all 7 areas',
      );
    },
  );

  testWidgets(
    'body-sized highlights wrap all seven long labels at narrow width and enlarged text',
    (tester) async {
      for (final language in AppLanguage.values) {
        final strings = AppStrings(language);
        final highlights = OverallAreaHighlights.fromPredictions(
          _predictions({
            for (final key in OverallAreaHighlights.highlightKeys) key: 85,
          }),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Center(
                  child: SizedBox(
                    width: 180,
                    child: MediaQuery(
                      data: const MediaQueryData(
                        textScaler: TextScaler.linear(2),
                      ),
                      child: OverallAreaHighlightsBlock(
                        highlights: highlights,
                        strings: strings,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        for (final line in highlights.lines(strings)) {
          final finder = find.text(line);
          expect(finder, findsOneWidget);
          final text = tester.widget<Text>(finder);
          expect(text.maxLines, isNull);
          expect(text.softWrap, true);
          expect(
            text.style?.fontSize,
            Theme.of(tester.element(finder)).textTheme.bodyMedium?.fontSize,
          );
        }
        expect(
          tester.getSize(find.text(highlights.lines(strings).first)).height,
          greaterThan(80),
        );
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );
}
