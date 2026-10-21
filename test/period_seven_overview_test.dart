// Synthetic contract data is used for UI/lifecycle tests. Real calculated
// weekly aggregation is covered separately in period_seven_summary_test.dart.
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

class _WeekJob implements WeeklyDailyConsultExportOperation {
  final completer = Completer<WeeklyDailyConsultExportResult>();
  bool cancelled = false;
  @override
  Future<WeeklyDailyConsultExportResult> get result => completer.future;
  @override
  void cancel() => cancelled = true;
}

class _MonthJob implements MonthlyDailyConsultExportOperation {
  final completer = Completer<MonthlyDailyConsultExportResult>();
  bool cancelled = false;
  @override
  Future<MonthlyDailyConsultExportResult> get result => completer.future;
  @override
  void cancel() => cancelled = true;
}

// Bypass the result factory only to simulate a corrupt worker response; the
// production overview itself must validate it before rendering any result.
class _RawWeek implements WeeklyDailyConsultExportResult {
  _RawWeek(this.requestIdentity, Map<String, Object?> data)
    : json = jsonEncode(data);
  @override
  final String requestIdentity, json;
  @override
  int get elapsedMilliseconds => 1;
  @override
  String? get workerName => 'synthetic-invalid-worker';
  @override
  Map<String, Object?> get data =>
      Map<String, Object?>.from(jsonDecode(json) as Map);
}

class _RawMonth implements MonthlyDailyConsultExportResult {
  _RawMonth(this.requestIdentity, Map<String, Object?> data)
    : json = jsonEncode(data);
  @override
  final String requestIdentity, json;
  @override
  int get elapsedMilliseconds => 1;
  @override
  String? get workerName => 'synthetic-invalid-worker';
  @override
  Map<String, Object?> get data =>
      Map<String, Object?>.from(jsonDecode(json) as Map);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SyntheticSevenPeriodFixture fixture;
  late HouseSystem originalHouse;
  late AppLanguage originalLanguage;
  late List<_WeekJob> weeks;
  late List<_MonthJob> months;
  late List<WeeklyDailyConsultExportRequest> weekRequests;
  late List<MonthlyDailyConsultExportRequest> monthRequests;
  late WeeklyDailyConsultExportStarter weekStarter;
  late MonthlyDailyConsultExportStarter monthStarter;
  late int pathCalls, shareCalls;
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
  setUpAll(() {
    final original = HouseSystemSettings.current.value;
    HouseSystemSettings.current.value = HouseSystem.placidus;
    fixture = SyntheticSevenPeriodFixture();
    HouseSystemSettings.current.value = original;
  });
  setUp(() {
    PeriodSevenDisplaySessionCache.clear();
    originalHouse = HouseSystemSettings.current.value;
    originalLanguage = AppLanguageSettings.current.value;
    HouseSystemSettings.current.value = HouseSystem.placidus;
    AppLanguageSettings.current.value = AppLanguage.ja;
    weeks = [];
    months = [];
    weekRequests = [];
    monthRequests = [];
    pathCalls = 0;
    shareCalls = 0;
    SharedPreferences.setMockInitialValues({
      'synthetic.old_json': 'preserve exact bytes',
      'synthetic.setting': 19,
    });
    weekStarter = (request, progress) {
      weekRequests.add(request);
      final job = _WeekJob();
      weeks.add(job);
      return job;
    };
    monthStarter = (request, progress) {
      monthRequests.add(request);
      final job = _MonthJob();
      months.add(job);
      return job;
    };
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(pathChannel, (_) async {
      pathCalls++;
      throw StateError('Readings must not write exports.');
    });
    messenger.setMockMethodCallHandler(shareChannel, (_) async {
      shareCalls++;
      return 'unavailable';
    });
  });
  tearDown(() {
    PeriodSevenDisplaySessionCache.clear();
    HouseSystemSettings.current.value = originalHouse;
    AppLanguageSettings.current.value = originalLanguage;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(pathChannel, null);
    messenger.setMockMethodCallHandler(shareChannel, null);
  });
  Widget shell(Widget child) => MaterialApp(
    theme: ThemeData.dark(),
    home: AppLanguageScope(
      child: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pump(
    WidgetTester tester, {
    LongRangeMode mode = LongRangeMode.week,
    DateTime? start,
    AstroProfile profile = sevenFixtureProfile,
    UserProfileDetails details = sevenFixtureDetails,
    ReadingDepth depth = ReadingDepth.simple,
    bool active = true,
  }) async {
    await tester.pumpWidget(
      shell(
        PeriodSevenOverview(
          mode: mode,
          startDateJst: start ?? DateTime.utc(2026, 12, 28),
          profile: profile,
          details: details,
          depth: depth,
          active: active,
          startWeeklyJob: weekStarter,
          startMonthlyJob: monthStarter,
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

  String textAt(WidgetTester tester, String key) {
    final finder = find.byKey(ValueKey(key));
    expect(finder, findsOneWidget);
    final widget = tester.widget(finder);
    if (widget is Text) {
      return widget.data ?? widget.textSpan?.toPlainText() ?? '';
    }
    return tester
        .widgetList<Text>(
          find.descendant(of: finder, matching: find.byType(Text)),
        )
        .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '')
        .join('\n');
  }

  Map<String, Object?> completeWeek({bool mixed = true}) {
    final r = weekRequests.last;
    final value = fixture.week(r, felt: mixed ? null : (_) => '良い');
    weeks.last.completer.complete(
      WeeklyDailyConsultExportResult.fromData(
        requestIdentity: r.identity,
        data: value,
      ),
    );
    return value;
  }

  Map<String, Object?> completeMonth() {
    final r = monthRequests.last;
    final value = fixture.month(r, felt: (_) => '良い');
    months.last.completer.complete(
      MonthlyDailyConsultExportResult.fromData(
        requestIdentity: r.identity,
        data: value,
      ),
    );
    return value;
  }

  void expectOverview(
    WidgetTester tester,
    int unique,
    AppLanguage language, {
    bool mixed = true,
  }) {
    expect(find.byType(FortuneNumber), findsNWidgets(8));
    for (final key in NineAreaKey.values) {
      final card = find.byKey(ValueKey('period-overview-card-${key.name}'));
      expect(card, findsOneWidget);
      final value = textAt(tester, 'period-overview-value-${key.name}');
      if (key == NineAreaKey.felt) {
        expect(
          find.descendant(of: card, matching: find.byType(FortuneNumber)),
          findsNothing,
        );
        expect(RegExp(r'\d').hasMatch(value), false);
        expect(
          value,
          contains(
            mixed
                ? (language == AppLanguage.ja ? '混在' : 'Mixed')
                : AppStrings(language).feltLabelText('良い')!,
          ),
        );
        if (!mixed) expect(find.byType(FeltFortuneBadge), findsOneWidget);
      } else {
        final badge = tester.widget<FortuneNumber>(
          find.descendant(of: card, matching: find.byType(FortuneNumber)),
        );
        final scores = List.generate(
          unique,
          (i) => SyntheticSevenPeriodFixture.scoreAt(i, key.name),
        );
        expect(badge.score, (scores.reduce((a, b) => a + b) / unique).round());
        expect(value, contains('${badge.score}'));
      }
      expect(
        textAt(tester, 'period-overview-narrative-${key.name}').trim(),
        isNotEmpty,
      );
    }
    expect(find.byKey(const ValueKey('period-overview-day')), findsNothing);
    expect(find.byKey(const ValueKey('period-overview-details')), findsNothing);
    expect(
      find.byKey(const ValueKey('period-reading-date-dropdown')),
      findsNothing,
    );
    for (final hour in [0, 4, 8, 12, 16, 20, 24]) {
      expect(find.byKey(ValueKey('period-overview-time-$hour')), findsNothing);
      expect(find.byKey(ValueKey('period-reading-time-$hour')), findsNothing);
    }
    for (final key in [
      'period-export-month-seven',
      'period-export-week-seven',
      'consult-json-month-seven',
      'consult-json-week-seven',
      'consult-json-year',
    ]) {
      expect(find.byKey(ValueKey(key)), findsNothing);
    }
    expect(find.byType(PeriodSevenReadingCards), findsNothing);
    expect(pathCalls, 0);
    expect(shareCalls, 0);
  }

  for (final language in AppLanguage.values) {
    for (final size in [const Size(390, 844), const Size(1181, 738)]) {
      testWidgets(
        '${language.name} ${size.width}: complete period nine circles, depth changes prose only, no daily picker or JSON entry',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          AppLanguageSettings.current.value = language;
          await pump(tester);
          expect(
            find.byKey(const ValueKey('period-overview-progress')),
            findsOneWidget,
          );
          expect(find.byType(FortuneNumber), findsNothing);
          final wrapper = completeWeek();
          final bytes = jsonEncode(wrapper);
          await frames(tester);
          expectOverview(tester, 43, language);
          expect(
            textAt(tester, 'period-overview-range'),
            contains('2026-12-28'),
          );
          expect(
            textAt(tester, 'period-overview-range'),
            contains('2027-01-03'),
          );
          expect(
            textAt(tester, 'period-overview-range'),
            isNot(contains('2027-01-04')),
          );
          final simple = textAt(tester, 'period-overview-narrative-work');
          final values = {
            for (final key in NineAreaKey.values)
              key: textAt(tester, 'period-overview-value-${key.name}'),
          };
          await pump(tester, depth: ReadingDepth.detailed);
          expectOverview(tester, 43, language);
          final detailed = textAt(tester, 'period-overview-narrative-work');
          expect(detailed, isNot(simple));
          expect(detailed.length, greaterThan(simple.length));
          for (final key in NineAreaKey.values) {
            expect(
              textAt(tester, 'period-overview-value-${key.name}'),
              values[key],
            );
            expect(
              find.byKey(ValueKey('period-overview-advice-${key.name}')),
              findsNothing,
            );
          }
          expect(find.byType(PeriodSevenTrend), findsNothing);
          expect(find.byType(MonthHalfDailyTrend), findsOneWidget);
          expect(
            find.byKey(const ValueKey('period-trend-area-dropdown')),
            findsNothing,
          );
          expect(find.byKey(const ValueKey('period-trend-load')), findsNothing);
          // The selected week's seven daily means reuse the loaded summary.
          // A depth-only rebuild must not start another worker.
          expect(
            tester
                .getTopLeft(find.byKey(const ValueKey('weekly-daily-graph')))
                .dy,
            lessThan(
              tester
                  .getTopLeft(
                    find.byKey(const ValueKey('period-overview-card-overall')),
                  )
                  .dy,
            ),
          );
          expect(weeks.length, 1);
          expect(find.byType(PeriodSevenGroupedTrendView), findsNothing);
          for (final key in NineAreaKey.values) {
            expect(
              textAt(tester, 'period-overview-value-${key.name}'),
              values[key],
            );
          }
          await tap(tester, 'period-overview-evidence-work');
          expect(textAt(tester, 'period-overview-ledger-work'), contains('43'));
          if (language == AppLanguage.en) {
            for (final key in NineAreaKey.values) {
              if (key != NineAreaKey.work) {
                await tap(tester, 'period-overview-evidence-${key.name}');
              }
              expect(
                RegExp(r'[\u3040-\u30ff\u3400-\u9fff]').hasMatch(
                  textAt(tester, 'period-overview-ledger-${key.name}'),
                ),
                false,
              );
            }
          }
          expectOverview(tester, 43, language);
          await tap(tester, 'period-overview-settings');
          expect(textAt(tester, 'period-overview-settings'), contains('43'));
          expect(textAt(tester, 'period-overview-settings'), contains('49'));
          expect(
            textAt(tester, 'period-overview-settings'),
            contains('UTC+09:00'),
          );
          expect(weeks.length, 1);
          expect(months, isEmpty);
          expect(jsonEncode(wrapper), bytes);
          expect(pathCalls, 0);
          expect(shareCalls, 0);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'complete monthly 28/29/30/31 day periods show full-range cards and conditions without daily controls',
    (tester) async {
      for (final row in [
        (2026, 2, 28),
        (2024, 2, 29),
        (2026, 4, 30),
        (2026, 12, 31),
      ]) {
        await pump(
          tester,
          mode: LongRangeMode.month,
          start: DateTime.utc(row.$1, row.$2, 18),
        );
        final value = completeMonth();
        final before = jsonEncode(value);
        await frames(tester);
        expectOverview(tester, row.$3 * 6 + 1, AppLanguage.ja, mixed: false);
        expect(
          tester
              .widget<PeriodSevenTrend>(find.byType(PeriodSevenTrend))
              .summary
              .uniqueInstantCount,
          row.$3 * 6 + 1,
        );
        expect(
          textAt(tester, 'period-overview-range'),
          contains('${row.$1}-${row.$2.toString().padLeft(2, '0')}-${row.$3}'),
        );
        await tap(tester, 'period-overview-settings');
        expect(
          textAt(tester, 'period-overview-settings'),
          contains('${row.$3 * 6 + 1}'),
        );
        expect(
          textAt(tester, 'period-overview-settings'),
          contains('${row.$3 * 7}'),
        );
        await tap(tester, 'period-overview-settings');
        expect(jsonEncode(value), before);
        expect(tester.takeException(), isNull);
      }
      expect(months.length, 4);
      expect(weeks, isEmpty);
      expect(pathCalls, 0);
      expect(shareCalls, 0);
    },
  );

  for (final mode in [LongRangeMode.week, LongRangeMode.month]) {
    testWidgets(
      '${mode.name}: cancel, late result, wrong identity, incomplete data and successful retry are separated',
      (tester) async {
        await pump(tester, mode: mode, start: DateTime.utc(2026, 2, 1));
        await tap(tester, 'period-overview-cancel');
        if (mode == LongRangeMode.week) {
          expect(weeks.last.cancelled, true);
          completeWeek();
        } else {
          expect(months.last.cancelled, true);
          completeMonth();
        }
        await frames(tester);
        expect(find.byType(FortuneNumber), findsNothing);
        await tap(tester, 'period-overview-retry');
        if (mode == LongRangeMode.week) {
          weeks.last.completer.complete(
            _RawWeek('wrong identity', fixture.week(weekRequests.last)),
          );
        } else {
          months.last.completer.complete(
            _RawMonth('wrong identity', fixture.month(monthRequests.last)),
          );
        }
        await frames(tester);
        expect(find.byType(FortuneNumber), findsNothing);
        await tap(tester, 'period-overview-retry');
        if (mode == LongRangeMode.week) {
          final bad = fixture.week(weekRequests.last);
          (bad['days'] as List).removeLast();
          weeks.last.completer.complete(
            _RawWeek(weekRequests.last.identity, bad),
          );
        } else {
          final bad = fixture.month(monthRequests.last);
          (bad['days'] as List).removeLast();
          months.last.completer.complete(
            _RawMonth(monthRequests.last.identity, bad),
          );
        }
        await frames(tester);
        expect(find.byType(FortuneNumber), findsNothing);
        expect(
          find.byKey(const ValueKey('period-overview-status')),
          findsOneWidget,
        );
        await tap(tester, 'period-overview-retry');
        if (mode == LongRangeMode.week) {
          completeWeek();
        } else {
          completeMonth();
        }
        await frames(tester);
        expect(find.byType(FortuneNumber), findsNWidgets(8));
        expect(mode == LongRangeMode.week ? weeks.length : months.length, 4);
        expect(pathCalls, 0);
        expect(shareCalls, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final change in ['profile', 'period', 'house', 'inactive', 'dispose']) {
    testWidgets(
      '$change invalidates the whole-period worker and rejects its late completion',
      (tester) async {
        await pump(tester);
        final job = weeks.single, request = weekRequests.single;
        switch (change) {
          case 'profile':
            await pump(
              tester,
              profile: sevenFixtureProfile.copyWith(
                name: 'Other fictional person',
              ),
            );
          case 'period':
            await pump(tester, start: DateTime.utc(2027, 1, 4));
          case 'house':
            HouseSystemSettings.current.value = HouseSystem.wholeSign;
            await frames(tester);
          case 'inactive':
            await pump(tester, active: false);
          case 'dispose':
            await tester.pumpWidget(shell(const Text('Another page')));
            await frames(tester);
        }
        expect(job.cancelled, true);
        job.completer.complete(
          WeeklyDailyConsultExportResult.fromData(
            requestIdentity: request.identity,
            data: fixture.week(request),
          ),
        );
        await frames(tester);
        expect(find.byType(FortuneNumber), findsNothing);
        expect(
          weeks.length,
          change == 'inactive' || change == 'dispose' ? 1 : 2,
        );
        expect(pathCalls, 0);
        expect(shareCalls, 0);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('synthetic.old_json'), 'preserve exact bytes');
        expect(prefs.getInt('synthetic.setting'), 19);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
