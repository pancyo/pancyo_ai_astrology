// Synthetic, controlled consultation tests. No personal profiles or native
// ephemeris equivalence claims. Annual fixture structure is retained from the
// pre-v90 period_reading_context_worker_test.dart without copying old outputs.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pancyo_ai_astrology/app_language.dart';
import 'package:pancyo_ai_astrology/main.dart';

const _profile = AstroProfile(
  name: 'SevenPointConsultationSynthetic',
  birthDate: '2000/1/2',
  birthTime: '12:00',
  birthPlace: '札幌市',
  theme: '仕事',
);

const _sevenPointRanges = [
  ConsultPeriodNavigationV2Range.thisWeek,
  ConsultPeriodNavigationV2Range.nextWeek,
  ConsultPeriodNavigationV2Range.thisMonth,
  ConsultPeriodNavigationV2Range.nextMonth,
  ConsultPeriodNavigationV2Range.threeMonths,
  ConsultPeriodNavigationV2Range.compareMonths,
];

ConsultPeriodNavigationV2Request _request(
  String question, {
  ConsultPeriodNavigationV2Range? range,
  NineAreaKey? topic,
  ConsultPeriodNavigationV2Context? previous,
  AppLanguage language = AppLanguage.ja,
  DateTime? today,
  AstroProfile profile = _profile,
}) => ConsultPeriodNavigationV2Request(
  question: question,
  todayJst: today ?? DateTime.utc(2026, 12, 10),
  profile: profile,
  houseSystem: HouseSystem.placidus,
  language: language,
  explicitRange: range,
  explicitTopic: topic,
  previous: previous,
);

class _PendingYear implements PeriodReadingContextOperation {
  _PendingYear(this.request, this.progress);
  final PeriodReadingContextRequest request;
  final void Function(int, int) progress;
  final completion = Completer<PeriodReadingContextResult>();
  bool cancelled = false;

  @override
  Future<PeriodReadingContextResult> get result => completion.future;
  @override
  void cancel() => cancelled = true;

  void finish() {
    HouseSystemSettings.current.value = request.houseSystem;
    final provider = AstrologyDataSources.current;
    final frame = provider.houseFrameFor(
      provider.dateFromProfile(request.profile),
      provider.placeForProfile(request.profile),
      request.houseSystem,
    );
    completion.complete(
      PeriodReadingContextResult(
        requestIdentity: request.identity,
        contexts: {
          for (final date in request.dates)
            date.toUtc(): const AstrologyEngine().buildPreviewContext(
              profile: request.profile,
              date: date,
            ),
        },
        signs: {
          for (final planet in request.signPlanets)
            planet: '${planet.label}: synthetic',
        },
        requestedHouseSystem: request.houseSystem,
        resolvedHouseSystem: frame.system,
        houseCusps: frame.cusps,
        elapsedMilliseconds: 0,
        workerName: 'controlled-annual-synthetic',
      ),
    );
  }
}

// Simulate an old in-memory context. Any read of its legacy samples or private
// identity fails, proving that the migration branch precedes old-data reuse.
class _LegacyShortContext implements ConsultPeriodNavigationV2Context {
  _LegacyShortContext(this.range);
  @override
  final ConsultPeriodNavigationV2Range range;
  @override
  NineAreaKey get topic => NineAreaKey.work;
  @override
  List<ConsultPeriodNavigationV2Period> get periods =>
      throw StateError('Legacy noon/representative samples must not be read.');
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Legacy identity must not be read for navigation.');
}

Future<void> _tick() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HouseSystem originalHouse;
  late List<_PendingYear> pending;
  late ConsultPeriodNavigationV2Controller controller;

  setUp(() {
    originalHouse = HouseSystemSettings.current.value;
    pending = [];
    controller = ConsultPeriodNavigationV2Controller(
      starter: (request, progress) {
        final operation = _PendingYear(request, progress);
        pending.add(operation);
        return operation;
      },
    );
  });
  tearDown(() {
    controller.dispose();
    HouseSystemSettings.current.value = originalHouse;
  });

  test(
    'all week/month routes point to canonical screens without calculation in both languages',
    () async {
      for (final language in AppLanguage.values) {
        for (final range in _sevenPointRanges) {
          var progressCalls = 0;
          final result = await controller.respond(
            _request('', range: range, language: language),
            onProgress: (_, _) => progressCalls++,
          );
          final week =
              range == ConsultPeriodNavigationV2Range.thisWeek ||
              range == ConsultPeriodNavigationV2Range.nextWeek;
          expect(result.status, ConsultPeriodNavigationV2Status.answered);
          expect(result.reasonCode, 'canonical_seven_point_navigation');
          expect(result.periods, isEmpty);
          expect(result.explanations, isEmpty);
          expect(result.nextContext!.periods, isEmpty);
          expect(result.nextContext!.topic, isNull);
          expect(result.nextContext!.range, range);
          expect(
            result.text,
            contains(
              language == AppLanguage.en
                  ? (week ? 'Weekly 7-point readings' : 'Monthly readings')
                  : (week ? '週間7点式' : '月間占い'),
            ),
          );
          expect(
            result.text,
            contains(
              language == AppLanguage.en ? 'Week, month & year' : '週月年占い',
            ),
          );
          expect(
            result.text,
            contains(
              language == AppLanguage.en
                  ? 'To create the formal JSON, open “Profile”'
                  : '正式なJSONの出力は「プロフィール」から行います',
            ),
          );
          expect(
            result.text,
            contains(
              language == AppLanguage.en
                  ? '00:00 / 04:00 / 08:00 / 12:00 / 16:00 / 20:00 / 24:00 JST'
                  : '00・04・08・12・16・20・24時（JST）',
            ),
          );
          expect(
            result.text,
            contains(
              language == AppLanguage.en
                  ? '24:00 is 00:00 on the following day'
                  : '24時は翌日00時',
            ),
          );
          if (week) {
            expect(
              result.text,
              contains(
                language == AppLanguage.en
                    ? 'seven calculated times for each of seven days'
                    : '1日7時点×7日',
              ),
            );
          } else {
            expect(
              result.text,
              contains(
                language == AppLanguage.en
                    ? 'five reference dates at noon JST'
                    : '正午JSTを代表5日',
              ),
            );
            expect(
              result.text,
              contains(
                language == AppLanguage.en ? 'four intervals' : '4区間のグラフ',
              ),
            );
            expect(
              result.text,
              contains(
                language == AppLanguage.en
                    ? 'retains seven points for every day of the complete month'
                    : '対象月の全日・各日7点を保持',
              ),
            );
            expect(result.text, isNot(contains('Monthly 7-point readings:')));
            expect(result.text, isNot(contains('月間7点式：')));
          }
          expect(pending, isEmpty);
          expect(progressCalls, 0);
          expect(controller.isBusy, isFalse);
        }
      }
    },
  );

  test(
    'navigation uses civil JST boundaries across years and preserves each target month',
    () async {
      final week = await controller.respond(
        _request(
          '',
          today: DateTime.utc(2027, 1, 3, 23),
          range: ConsultPeriodNavigationV2Range.thisWeek,
        ),
      );
      expect(week.text, contains('2026-12-28–2027-01-03'));
      final next = await controller.respond(
        _request(
          '',
          today: DateTime.utc(2027, 1, 3, 23),
          range: ConsultPeriodNavigationV2Range.nextWeek,
        ),
      );
      expect(next.text, contains('2027-01-04–2027-01-10'));
      final months = await controller.respond(_request('今後3か月の仕事'));
      expect(months.text, contains('2026-12・2027-01・2027-02'));
      final compare = await controller.respond(
        _request('this month and next month of work', language: AppLanguage.en),
      );
      expect(compare.text, contains('2026-12, 2027-01'));
      expect(
        compare.text,
        contains('has not calculated a score or compared the periods'),
      );
      expect(compare.text, isNot(contains('Next month minus this month')));
      expect(pending, isEmpty);
    },
  );

  test(
    'detail and topic follow-ups retain navigation only and never revive legacy periods',
    () async {
      final first = await controller.respond(_request('今月の仕事'));
      for (final question in ['前の相談を詳しく', 'なぜ？', '体感は？']) {
        final result = await controller.respond(
          _request(question, previous: first.nextContext),
        );
        expect(result.reasonCode, 'canonical_seven_point_navigation');
        expect(result.periods, isEmpty);
        expect(result.explanations, isEmpty);
        expect(result.nextContext!.periods, isEmpty);
        expect(result.text, contains('月間占い'));
        expect(result.text, contains('4区間のグラフ'));
      }
      final english = await controller.respond(
        _request(
          'more details',
          previous: first.nextContext,
          language: AppLanguage.en,
        ),
      );
      expect(english.reasonCode, 'canonical_seven_point_navigation');
      expect(english.text, contains('Monthly readings'));
      expect(english.text, contains('four intervals'));
      expect(pending, isEmpty);
    },
  );

  test(
    'pre-migration cached samples are not touched even on a changed-profile follow-up',
    () async {
      const other = AstroProfile(
        name: 'ChangedSynthetic',
        birthDate: '2001/1/3',
        birthTime: '12:00',
        birthPlace: '札幌市',
        theme: '仕事',
      );
      for (final range in _sevenPointRanges) {
        final result = await controller.respond(
          _request(
            '前の相談を詳しく',
            previous: _LegacyShortContext(range),
            profile: other,
          ),
        );
        expect(result.reasonCode, 'canonical_seven_point_navigation');
        expect(result.nextContext!.periods, isEmpty);
        expect(result.periods, isEmpty);
      }
      expect(pending, isEmpty);
    },
  );

  test(
    'annual 24 samples and explanatory follow-up remain unchanged',
    () async {
      expect(AstrologyDataSources.current.usesHighPrecisionAstroData, isFalse);
      final future = controller.respond(_request('今年の仕事'));
      expect(pending.single.request.mode, LongRangeMode.year);
      pending.single.finish();
      final first = await future;
      expect(first.status, ConsultPeriodNavigationV2Status.answered);
      final period = first.periods.single;
      expect(period.dailySamples, hasLength(24));
      expect(period.dailySamples.keys.first, '2026-01-01');
      expect(period.dailySamples.keys.last, '2026-12-15');
      expect(first.text, contains('各年の代表24時点'));
      final before = jsonEncode(period.summary.toJson());
      final work = period.summary.areas.singleWhere(
        (area) => area.key == NineAreaKey.work,
      );
      expect(work.score, (work.samples.fold(0, (a, b) => a + b) / 24).round());
      final follow = await controller.respond(
        _request('why?', previous: first.nextContext, language: AppLanguage.en),
      );
      expect(follow.text, contains('24 reference samples per year'));
      expect(follow.explanations.single.depth, ReadingDepth.detailed);
      expect(identical(follow.periods.single, period), isTrue);
      expect(jsonEncode(follow.periods.single.summary.toJson()), before);
      expect(pending, hasLength(1));
      final month = await controller.respond(
        _request('今月', previous: first.nextContext),
      );
      expect(month.reasonCode, 'canonical_seven_point_navigation');
      expect(month.nextContext!.periods, isEmpty);
      expect(pending, hasLength(1));
    },
  );

  test(
    'five annual periods still run sequentially with 24 samples each',
    () async {
      final future = controller.respond(
        _request('five years of work', language: AppLanguage.en),
      );
      for (var i = 0; i < 5; i++) {
        expect(pending, hasLength(i + 1));
        expect(pending.last.request.mode, LongRangeMode.year);
        expect(pending.last.request.year, 2026 + i);
        pending.last.finish();
        await _tick();
      }
      final result = await future;
      expect(result.status, ConsultPeriodNavigationV2Status.answered);
      expect(result.periods, hasLength(5));
      expect(
        result.periods.every((period) => period.dailySamples.length == 24),
        isTrue,
      );
      expect(result.text, contains('5 calendar year(s)'));
      expect(result.text, contains('No cross-period average'));
    },
  );

  test(
    'ambiguous, unsupported and daily requests retain their routing without work',
    () async {
      for (final question in ['今週と今月の仕事', '6か月の健康', '今日と今月の仕事', 'なぜ？']) {
        final result = await controller.respond(_request(question));
        expect(
          result.status,
          ConsultPeriodNavigationV2Status.clarificationRequired,
        );
        expect(result.periods, isEmpty);
      }
      final daily = await controller.respond(_request('明日の仕事'));
      expect(daily.status, ConsultPeriodNavigationV2Status.notHandled);
      expect(pending, isEmpty);
    },
  );

  test(
    'new seven-point guidance cancels a running annual worker and rejects its late result',
    () async {
      final old = controller.respond(_request('今年の仕事'));
      expect(pending, hasLength(1));
      final latest = await controller.respond(_request('来週の仕事'));
      expect(latest.reasonCode, 'canonical_seven_point_navigation');
      expect(pending.single.cancelled, isTrue);
      expect((await old).status, ConsultPeriodNavigationV2Status.cancelled);
      pending.single.completion.completeError(
        StateError('controlled late annual error'),
      );
      await _tick();
      expect(pending, hasLength(1));
      expect(controller.isBusy, isFalse);
      expect(latest.nextContext!.periods, isEmpty);
    },
  );

  test(
    'annual failure and disposed owner do not expose an old summary or start work',
    () async {
      final future = controller.respond(_request('今年の仕事'));
      pending.single.completion.completeError(StateError('synthetic failure'));
      final failed = await future;
      expect(failed.status, ConsultPeriodNavigationV2Status.unavailable);
      expect(failed.periods, isEmpty);
      controller.dispose();
      final later = await controller.respond(_request('今月'));
      expect(later.status, ConsultPeriodNavigationV2Status.cancelled);
      expect(pending, hasLength(1));
    },
  );
}
