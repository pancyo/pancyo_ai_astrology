// Synthetic display/lifecycle tests. Two days are calculated once with the
// existing daily-v4 engine. Reusing these fixtures changes only generation
// metadata/request identity, never their timepoint values or model inputs.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pancyo_ai_astrology/app_language.dart';
import 'package:pancyo_ai_astrology/app_language_settings.dart';
import 'package:pancyo_ai_astrology/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'monthly_daily_consult_export_test.dart' as fixture;

class _ControlledDay implements DailyConsultExportOperation {
  final completer = Completer<DailyConsultExportResult>();
  bool cancelled = false;
  @override
  Future<DailyConsultExportResult> get result => completer.future;
  @override
  void cancel() => cancelled = true;
}

class _FixtureResult implements DailyConsultExportResult {
  _FixtureResult(this.requestIdentity, Map<String, Object?> value)
    : json = jsonEncode(value);
  @override
  final String requestIdentity, json;
  @override
  int get elapsedMilliseconds => 1;
  @override
  String get workerName => 'controlled-synthetic-reading';
  @override
  Map<String, Object?> get data =>
      Map<String, Object?>.from(jsonDecode(json) as Map);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final canonical = <String, Map<String, Object?>>{};
  final fixedGeneratedAt = DateTime.utc(2026, 10, 18, 3);
  late HouseSystem originalHouse;
  late AppLanguage originalLanguage;
  late List<_ControlledDay> jobs;
  late List<DailyConsultExportRequest> requests;
  late DailyConsultExportStarter starter;
  late int pathCalls, shareCalls;
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');

  DailyConsultExportRequest dayRequest(DateTime noon) {
    final source = AstrologyDataSources.current;
    return DailyConsultExportRequest(
      date: noon,
      profile: fixture.subject,
      details: const UserProfileDetails.empty(),
      requestedHouseSystem: HouseSystem.placidus,
      sourceName: source.sourceName,
      requireHighPrecision: source.usesHighPrecisionAstroData,
      generatedAt: fixedGeneratedAt,
    );
  }

  setUpAll(() {
    final previousHouse = HouseSystemSettings.current.value;
    try {
      HouseSystemSettings.current.value = HouseSystem.placidus;
      for (final noon in [
        DateTime.utc(2026, 12, 31, 3),
        DateTime.utc(2027, 1, 1, 3),
      ]) {
        final request = dayRequest(noon);
        canonical[request.plan.targetDateJst] = buildDailyConsultDataV4(
          request,
        );
      }
    } finally {
      HouseSystemSettings.current.value = previousHouse;
    }
  });

  setUp(() {
    originalHouse = HouseSystemSettings.current.value;
    originalLanguage = AppLanguageSettings.current.value;
    HouseSystemSettings.current.value = HouseSystem.placidus;
    AppLanguageSettings.current.value = AppLanguage.ja;
    SharedPreferences.setMockInitialValues({
      'synthetic.old_prediction': '{ "preserve": "exact bytes" }',
      'synthetic.other_setting': 29,
    });
    jobs = [];
    requests = [];
    pathCalls = 0;
    shareCalls = 0;
    starter = (request, progress) {
      requests.add(request);
      final job = _ControlledDay();
      jobs.add(job);
      return job;
    };
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(pathChannel, (_) async {
      pathCalls++;
      throw StateError('Reading must remain in memory.');
    });
    messenger.setMockMethodCallHandler(shareChannel, (_) async {
      shareCalls++;
      return 'dev.fluttercommunity.plus/share/unavailable';
    });
  });

  tearDown(() {
    HouseSystemSettings.current.value = originalHouse;
    AppLanguageSettings.current.value = originalLanguage;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(pathChannel, null);
    messenger.setMockMethodCallHandler(shareChannel, null);
  });

  Map<String, Object?> clone(Map<String, Object?> value) =>
      Map<String, Object?>.from(jsonDecode(jsonEncode(value)) as Map);
  List<dynamic> points(Map<String, Object?> day) =>
      (day['intraday_forecasts'] as Map)['points'] as List;
  Map<String, Object?> snapshot(Map<String, Object?> day, int index) =>
      Map<String, Object?>.from(
        points(day)[index]['nine_area_forecast'] as Map,
      );
  _FixtureResult resultFor(
    DailyConsultExportRequest request, {
    String? identity,
  }) {
    final value = clone(canonical[request.plan.targetDateJst]!);
    value['generated_at'] = request.generatedAt.toIso8601String();
    return _FixtureResult(identity ?? request.identity, value);
  }

  Widget shell(Widget child) => MaterialApp(
    theme: ThemeData.dark(),
    home: AppLanguageScope(
      child: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pumpView(
    WidgetTester tester, {
    LongRangeMode mode = LongRangeMode.week,
    DateTime? start,
    AstroProfile? profile,
    bool active = true,
    ReadingDepth depth = ReadingDepth.simple,
  }) async {
    await tester.pumpWidget(
      shell(
        PeriodSevenReadingView(
          mode: mode,
          startDateJst: start ?? DateTime.utc(2026, 12, 31),
          profile: profile ?? fixture.subject,
          details: const UserProfileDetails.empty(),
          startJob: starter,
          active: active,
          depth: depth,
        ),
      ),
    );
    await frames(tester);
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
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

  void expectValues(
    WidgetTester tester,
    Map<String, Object?> value,
    AppLanguage language, {
    ReadingDepth depth = ReadingDepth.simple,
  }) {
    final strings = AppStrings(language);
    final areas = value['areas'] as List;
    expect(areas.where((a) => a['score'] is num).length, 8);
    expect(find.byType(FortuneNumber), findsNWidgets(8));
    expect(find.byType(FeltFortuneBadge), findsOneWidget);
    for (final raw in areas) {
      final key = raw['key'] as String;
      final card = find.byKey(ValueKey('seven-reading-card-$key'));
      expect(card, findsOneWidget);
      final displayed = textAt(tester, 'seven-reading-value-$key');
      if (key == 'felt') {
        expect(raw['score'], isNull);
        final badge = find.descendant(
          of: card,
          matching: find.byType(FeltFortuneBadge),
        );
        expect(badge, findsOneWidget);
        expect(
          tester.widget<FeltFortuneBadge>(badge).label,
          raw['predicted_felt_label'],
        );
        expect(
          find.descendant(of: card, matching: find.byType(FortuneNumber)),
          findsNothing,
          reason: 'A felt category must not become a numeric badge.',
        );
        expect(
          displayed,
          contains(
            strings.feltLabelText(raw['predicted_felt_label'] as String)!,
          ),
        );
        expect(RegExp(r'\d').hasMatch(displayed), false);
      } else {
        final badge = find.descendant(
          of: card,
          matching: find.byType(FortuneNumber),
        );
        expect(badge, findsOneWidget);
        expect(
          tester.widget<FortuneNumber>(badge).score,
          raw['score'],
          reason: 'The round badge must retain the selected canonical score.',
        );
        expect(
          find.descendant(of: card, matching: find.byType(FeltFortuneBadge)),
          findsNothing,
        );
        expect(displayed, contains('${raw['score']}'));
      }
      expect(textAt(tester, 'seven-reading-narrative-$key').trim(), isNotEmpty);
      if (depth == ReadingDepth.simple) {
        expect(textAt(tester, 'seven-reading-advice-$key').trim(), isNotEmpty);
      } else {
        expect(
          find.byKey(ValueKey('seven-reading-advice-$key')),
          findsNothing,
          reason: 'Detailed narrative includes advice without repeating it.',
        );
      }
      expect(
        find.byKey(ValueKey('seven-reading-evidence-$key')),
        findsOneWidget,
      );
    }
  }

  test(
    'validator accepts original daily-v4 and rejects wrong input, missing points and changed noon',
    () {
      final request = dayRequest(DateTime.utc(2026, 12, 31, 3));
      final original = canonical['2026-12-31']!;
      validatePeriodSevenReadingData(
        data: original,
        request: request,
        resultRequestIdentity: request.identity,
      );
      expect(
        () => validatePeriodSevenReadingData(
          data: original,
          request: request,
          resultRequestIdentity: 'wrong identity',
        ),
        throwsA(anything),
      );
      for (final damage in <void Function(Map<String, Object?>)>[
        (d) => points(d).removeLast(),
        (d) => (d['profile'] as Map)['name'] = 'A different synthetic subject',
        (d) => (d['nine_area_daily'] as Map)['target_date_jst'] = '2027-01-01',
        (d) => points(d)[0]['instant_utc'] = '2026-12-31T12:00:00Z',
      ]) {
        final invalid = clone(original);
        damage(invalid);
        expect(
          () => validatePeriodSevenReadingData(
            data: invalid,
            request: request,
            resultRequestIdentity: request.identity,
          ),
          throwsA(anything),
        );
      }
    },
  );

  for (final language in AppLanguage.values) {
    for (final size in [const Size(390, 844), const Size(1181, 738)]) {
      testWidgets(
        '${language.name} ${size.width.toInt()}x${size.height.toInt()}: all nine cards retain eight scores, categorical felt and readable evidence',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          AppLanguageSettings.current.value = language;
          final day = canonical['2026-12-31']!;
          final point = points(day)[3];
          final value = snapshot(day, 3);
          final before = jsonEncode(value);
          await tester.pumpWidget(
            shell(
              PeriodSevenReadingCards(
                snapshot: value,
                targetDate: DateTime.parse(point['instant_utc'] as String),
                displayTime: '12:00',
                details: const UserProfileDetails.empty(),
              ),
            ),
          );
          await frames(tester);
          expectValues(tester, value, language);
          await tapKey(tester, 'seven-reading-evidence-work');
          expect(
            textAt(tester, 'seven-reading-ledger-work').trim(),
            isNotEmpty,
          );
          if (language == AppLanguage.en) {
            for (final area in value['areas'] as List) {
              final key = area['key'] as String;
              if (key != 'work') {
                await tapKey(tester, 'seven-reading-evidence-$key');
              }
              expect(
                RegExp(
                  r'[\u3040-\u30ff\u3400-\u9fff]',
                ).hasMatch(textAt(tester, 'seven-reading-ledger-$key')),
                false,
                reason:
                    'English evidence must not expose Japanese raw JSON text: $key',
              );
            }
          }
          await tester.ensureVisible(
            find.byKey(const ValueKey('seven-reading-card-felt')),
          );
          await frames(tester);
          expect(tester.takeException(), isNull);
          expect(
            jsonEncode(value),
            before,
            reason: 'Rendering must not rewrite JSON.',
          );
          expect(pathCalls, 0);
          expect(shareCalls, 0);
        },
      );
    }
  }

  for (final language in AppLanguage.values) {
    testWidgets(
      '${language.name}: simple and detailed readings share the same snapshot and job while explanation changes',
      (tester) async {
        AppLanguageSettings.current.value = language;
        await pumpView(tester, depth: ReadingDepth.simple);
        jobs.single.completer.complete(resultFor(requests.single));
        await frames(tester);
        final value = snapshot(canonical['2026-12-31']!, 3);
        expectValues(tester, value, language);
        final simpleCards = tester.widget<PeriodSevenReadingCards>(
          find.byType(PeriodSevenReadingCards),
        );
        expect(simpleCards.depth, ReadingDepth.simple);
        final before = jsonEncode(simpleCards.snapshot);
        final values = {
          for (final area in value['areas'] as List)
            area['key'] as String: textAt(
              tester,
              'seven-reading-value-${area['key']}',
            ),
        };
        final simpleNarrative = textAt(tester, 'seven-reading-narrative-work');
        await tapKey(tester, 'seven-reading-evidence-work');
        final simpleEvidence = textAt(tester, 'seven-reading-ledger-work');

        await pumpView(tester, depth: ReadingDepth.detailed);
        final detailedCards = tester.widget<PeriodSevenReadingCards>(
          find.byType(PeriodSevenReadingCards),
        );
        expect(detailedCards.depth, ReadingDepth.detailed);
        expect(jsonEncode(detailedCards.snapshot), before);
        expectValues(tester, value, language, depth: ReadingDepth.detailed);
        for (final entry in values.entries) {
          expect(
            textAt(tester, 'seven-reading-value-${entry.key}'),
            entry.value,
          );
        }
        final detailedNarrative = textAt(
          tester,
          'seven-reading-narrative-work',
        );
        expect(detailedNarrative, isNot(simpleNarrative));
        expect(detailedNarrative.length, greaterThan(simpleNarrative.length));
        expect(
          textAt(tester, 'seven-reading-ledger-work'),
          isNot(simpleEvidence),
        );
        if (language == AppLanguage.en) {
          expect(
            RegExp(r'[\u3040-\u30ff\u3400-\u9fff]').hasMatch(detailedNarrative),
            false,
          );
          expect(
            RegExp(
              r'[\u3040-\u30ff\u3400-\u9fff]',
            ).hasMatch(textAt(tester, 'seven-reading-ledger-work')),
            false,
          );
        }
        expect(jobs.length, 1, reason: 'Reading depth is presentation only.');
        expect(requests.length, 1);
        expect(pathCalls, 0);
        expect(shareCalls, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'a missing numeric item remains unavailable while the other canonical cards retain their values',
    (tester) async {
      final day = canonical['2026-12-31']!;
      final value = clone(snapshot(day, 3));
      final work =
          (value['areas'] as List).singleWhere((area) => area['key'] == 'work')
              as Map;
      work['score'] = null;
      await tester.pumpWidget(
        shell(
          PeriodSevenReadingCards(
            snapshot: value,
            targetDate: DateTime.parse(points(day)[3]['instant_utc'] as String),
            displayTime: '12:00',
            details: const UserProfileDetails.empty(),
          ),
        ),
      );
      await frames(tester);
      expect(textAt(tester, 'seven-reading-value-work'), contains('未予測'));
      expect(
        find.byType(FortuneNumber),
        findsNWidgets(7),
        reason: 'Unavailable work must not be shown as a zero-score circle.',
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('seven-reading-card-work')),
          matching: find.byType(FortuneNumber),
        ),
        findsNothing,
      );
      expect(find.byType(FeltFortuneBadge), findsOneWidget);
      expect(
        find.byKey(const ValueKey('seven-reading-partial-warning')),
        findsOneWidget,
      );
      for (final area in (snapshot(day, 3)['areas'] as List)) {
        final key = area['key'] as String;
        expect(find.byKey(ValueKey('seven-reading-card-$key')), findsOneWidget);
        if (key != 'work' && key != 'felt') {
          expect(
            textAt(tester, 'seven-reading-value-$key'),
            contains('${area['score']}'),
          );
        }
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'time changes use all canonical snapshots without another job; noon and next-day 00 match',
    (tester) async {
      await pumpView(tester);
      expect(requests.single.date, DateTime.utc(2026, 12, 31, 3));
      jobs.single.completer.complete(resultFor(requests.single));
      await frames(tester);
      final day = canonical['2026-12-31']!;
      expect(
        jsonEncode(
          tester
              .widget<PeriodSevenReadingCards>(
                find.byType(PeriodSevenReadingCards),
              )
              .snapshot,
        ),
        jsonEncode(snapshot(day, 3)),
      );
      for (var i = 0; i < 7; i++) {
        final hour = i * 4;
        await tapKey(tester, 'period-reading-time-$hour');
        final cards = tester.widget<PeriodSevenReadingCards>(
          find.byType(PeriodSevenReadingCards),
        );
        expect(jsonEncode(cards.snapshot), jsonEncode(snapshot(day, i)));
        expect(
          cards.targetDate.toUtc(),
          DateTime.parse(points(day)[i]['instant_utc'] as String),
        );
        expect(cards.displayTime, '${hour.toString().padLeft(2, '0')}:00');
        expectValues(tester, snapshot(day, i), AppLanguage.ja);
        expect(
          jobs.length,
          1,
          reason: 'Time selection uses the loaded canonical day.',
        );
      }
      expect(
        find.byKey(const ValueKey('seven-reading-boundary')),
        findsOneWidget,
      );
      expect(
        jsonEncode(snapshot(day, 3)['areas']),
        jsonEncode((day['nine_area_daily'] as Map)['areas']),
      );
      final boundary = snapshot(day, 6);
      await tapKey(tester, 'period-reading-next-day');
      expect(requests.last.date, DateTime.utc(2027, 1, 1, 3));
      jobs.last.completer.complete(resultFor(requests.last));
      await frames(tester);
      await tapKey(tester, 'period-reading-time-0');
      final next = tester.widget<PeriodSevenReadingCards>(
        find.byType(PeriodSevenReadingCards),
      );
      expect(jsonEncode(next.snapshot['areas']), jsonEncode(boundary['areas']));
      expect(next.targetDate.toUtc(), DateTime.utc(2026, 12, 31, 15));
      expect(
        find.byKey(const ValueKey('seven-reading-boundary')),
        findsNothing,
      );
      expect(pathCalls, 0);
      expect(shareCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'week/month date choices include leap day and both year edges without outside days',
    (tester) async {
      for (final row in [
        (
          LongRangeMode.month,
          DateTime.utc(2024, 2, 12),
          29,
          '2024-02-01',
          '2024-02-29',
        ),
        (
          LongRangeMode.month,
          DateTime.utc(2026, 12, 18),
          31,
          '2026-12-01',
          '2026-12-31',
        ),
        (
          LongRangeMode.week,
          DateTime.utc(2026, 12, 28),
          7,
          '2026-12-28',
          '2027-01-03',
        ),
      ]) {
        await pumpView(tester, mode: row.$1, start: row.$2);
        final dropdown = tester.widget<DropdownButton<String>>(
          find.byKey(const ValueKey('period-reading-date-dropdown')),
        );
        final values = dropdown.items!.map((item) => item.value).toList();
        expect(values.length, row.$3);
        expect(values.toSet().length, row.$3);
        expect(values.first, row.$4);
        expect(values.last, row.$5);
        dropdown.onChanged!(values.last);
        await frames(tester);
        expect(requests.last.plan.targetDateJst, row.$5);
        final next = tester.widget<IconButton>(
          find.byKey(const ValueKey('period-reading-next-day')),
        );
        expect(next.onPressed, isNull);
      }
      expect(jobs.take(jobs.length - 1).every((job) => job.cancelled), true);
      expect(find.byType(PeriodSevenReadingCards), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cancel and retry discard late success; wrong identity fails before showing cards',
    (tester) async {
      await pumpView(tester);
      await tapKey(tester, 'period-reading-cancel');
      expect(jobs.first.cancelled, true);
      jobs.first.completer.complete(resultFor(requests.first));
      await frames(tester);
      expect(find.byType(PeriodSevenReadingCards), findsNothing);
      await tapKey(tester, 'period-reading-retry');
      jobs.last.completer.complete(
        resultFor(requests.last, identity: 'another request'),
      );
      await frames(tester);
      expect(find.byType(PeriodSevenReadingCards), findsNothing);
      expect(
        find.byKey(const ValueKey('period-reading-retry')),
        findsOneWidget,
      );
      await tapKey(tester, 'period-reading-retry');
      jobs.last.completer.complete(resultFor(requests.last));
      await frames(tester);
      expect(find.byType(PeriodSevenReadingCards), findsOneWidget);
      expect(jobs.length, 3);
      expect(pathCalls, 0);
      expect(shareCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final change in ['profile', 'period', 'house', 'inactive', 'dispose']) {
    testWidgets(
      '$change invalidates pending day and discards late canonical result',
      (tester) async {
        await pumpView(tester);
        final firstJob = jobs.first;
        final firstRequest = requests.first;
        switch (change) {
          case 'profile':
            await pumpView(
              tester,
              profile: fixture.subject.copyWith(
                name: 'Another fictional profile',
              ),
            );
          case 'period':
            await pumpView(tester, start: DateTime.utc(2027, 1, 1));
          case 'house':
            HouseSystemSettings.current.value = HouseSystem.wholeSign;
            await frames(tester);
          case 'inactive':
            await pumpView(tester, active: false);
          case 'dispose':
            await tester.pumpWidget(shell(const Text('Other page')));
            await frames(tester);
        }
        expect(firstJob.cancelled, true);
        firstJob.completer.complete(resultFor(firstRequest));
        await frames(tester);
        expect(find.byType(PeriodSevenReadingCards), findsNothing);
        expect(
          jobs.length,
          change == 'inactive' || change == 'dispose' ? 1 : 2,
        );
        expect(pathCalls, 0);
        expect(shareCalls, 0);
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getString('synthetic.old_prediction'),
          '{ "preserve": "exact bytes" }',
        );
        expect(prefs.getInt('synthetic.other_setting'), 29);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
