// UI contracts use a fictional real daily context and explicit synthetic period
// samples. Opening the composer must never invoke a platform share or export.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pancyo_ai_astrology/app_language.dart';
import 'package:pancyo_ai_astrology/app_language_settings.dart';
import 'package:pancyo_ai_astrology/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'period_seven_test_fixture.dart';

class _WeekShareJob implements WeeklyDailyConsultExportOperation {
  final completion = Completer<WeeklyDailyConsultExportResult>();
  @override
  Future<WeeklyDailyConsultExportResult> get result => completion.future;
  @override
  void cancel() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SyntheticSevenPeriodFixture fixture;
  late HoroscopeReadingContext noon;
  late List<NineAreaPrediction> daily;
  late AppLanguage oldLanguage;
  late HouseSystem oldHouse;
  var platformCalls = 0;
  final date = DateTime.utc(2026, 12, 28, 3);
  const channels = [
    MethodChannel('dev.fluttercommunity.plus/share'),
    MethodChannel('com.pancyo.aiastrology/share_compat'),
    MethodChannel('plugins.flutter.io/path_provider'),
  ];

  setUpAll(() async {
    // Use the Android-default font bundled with the existing Flutter SDK for
    // screen-fit measurements. The test-only Ahem font gives every Latin glyph
    // a full-em width and does not represent the native reading layout.
    final flutterRoot =
        Platform.environment['FLUTTER_ROOT'] ?? r'C:\Users\pancy\flutter';
    final font = FontLoader('Roboto');
    for (final name in ['roboto-regular.ttf', 'roboto-bold.ttf']) {
      font.addFont(
        File(
          '$flutterRoot/bin/cache/artifacts/material_fonts/$name',
        ).readAsBytes().then(ByteData.sublistView),
      );
    }
    await font.load();
    final previous = HouseSystemSettings.current.value;
    HouseSystemSettings.current.value = HouseSystem.placidus;
    fixture = SyntheticSevenPeriodFixture();
    noon = const AstrologyEngine().buildPreviewContext(
      profile: sevenFixtureProfile,
      date: date,
    );
    daily = NineAreaDailyForecast.fromContext(noon);
    HouseSystemSettings.current.value = previous;
  });

  setUp(() {
    oldLanguage = AppLanguageSettings.current.value;
    oldHouse = HouseSystemSettings.current.value;
    AppLanguageSettings.current.value = AppLanguage.en;
    HouseSystemSettings.current.value = HouseSystem.placidus;
    PeriodSevenDisplaySessionCache.clear();
    SharedPreferences.setMockInitialValues({'preserved.profile': 'untouched'});
    platformCalls = 0;
    for (final channel in channels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            platformCalls++;
            throw StateError('Opening a composer must not share or export.');
          });
    }
  });

  tearDown(() {
    AppLanguageSettings.current.value = oldLanguage;
    HouseSystemSettings.current.value = oldHouse;
    PeriodSevenDisplaySessionCache.clear();
    for (final channel in channels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  Widget shell(Widget child, {double scale = 1}) => MaterialApp(
    theme: ThemeData(brightness: Brightness.dark, fontFamily: 'Roboto'),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: AppLanguageScope(
      child: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );

  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<PeriodSevenSummary> week(
    WidgetTester tester, {
    double scale = 1,
    ReadingDepth depth = ReadingDepth.simple,
    int? actionScore,
  }) async {
    final jobs = <_WeekShareJob>[];
    final requests = <WeeklyDailyConsultExportRequest>[];
    await tester.pumpWidget(
      shell(
        PeriodSevenOverview(
          mode: LongRangeMode.week,
          startDateJst: date,
          profile: sevenFixtureProfile,
          details: sevenFixtureDetails,
          depth: depth,
          startWeeklyJob: (request, progress) {
            requests.add(request);
            final job = _WeekShareJob();
            jobs.add(job);
            return job;
          },
        ),
        scale: scale,
      ),
    );
    await frames(tester);
    expect(requests, hasLength(1));
    jobs.single.completion.complete(
      WeeklyDailyConsultExportResult.fromData(
        requestIdentity: requests.single.identity,
        data: fixture.week(
          requests.single,
          score: actionScore == null
              ? null
              : (index, area) => area == NineAreaKey.actionDecision.name
                    ? actionScore
                    : SyntheticSevenPeriodFixture.scoreAt(index, area),
        ),
      ),
    );
    await frames(tester);
    return tester
        .widget<MonthHalfDailyTrend>(find.byType(MonthHalfDailyTrend))
        .summary;
  }

  Future<FortuneShareComposerSheet> open(
    WidgetTester tester,
    String key,
  ) async {
    final entry = find.byKey(ValueKey(key));
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.byType(FortuneShareComposerSheet), findsOneWidget);
    expect(platformCalls, 0);
    expect(tester.takeException(), isNull);
    return tester.widget<FortuneShareComposerSheet>(
      find.byType(FortuneShareComposerSheet),
    );
  }

  Future<void> close(WidgetTester tester) async {
    Navigator.of(tester.element(find.byType(FortuneShareComposerSheet))).pop();
    await tester.pumpAndSettle();
  }

  void expectShareAvailability(
    WidgetTester tester, {
    required String readingKey,
    required String sharePrefix,
    required String cardPrefix,
    AppLanguage language = AppLanguage.en,
    ReadingDepth depth = ReadingDepth.simple,
  }) {
    final visible = depth == ReadingDepth.simple;
    expect(
      find.byKey(ValueKey(readingKey)),
      visible ? findsOneWidget : findsNothing,
    );
    expect(
      find.text(
        language == AppLanguage.en ? 'Share summary (all 9)' : 'まとめ（全9項目）を共有',
      ),
      visible ? findsOneWidget : findsNothing,
    );
    expect(
      find.text(language == AppLanguage.en ? 'Share overall only' : '総合運のみ共有'),
      visible ? findsOneWidget : findsNothing,
    );
    expect(
      find.byIcon(Icons.ios_share_outlined),
      visible ? findsNWidgets(2) : findsNothing,
    );
    for (final key in NineAreaKey.values) {
      expect(find.byKey(ValueKey('$cardPrefix-${key.name}')), findsOneWidget);
      expect(
        find.byKey(ValueKey('$sharePrefix-${key.name}')),
        visible && key == NineAreaKey.overall ? findsOneWidget : findsNothing,
      );
    }
  }

  Future<void> expectDetailedReading(
    WidgetTester tester,
    String cardPrefix,
  ) async {
    expect(find.byType(FortuneShareComposerSheet), findsNothing);
    for (final key in NineAreaKey.values) {
      final card = find.byKey(ValueKey('$cardPrefix-${key.name}'));
      expect(card, findsOneWidget);
      final paragraphs = tester
          .widgetList<Text>(
            find.descendant(of: card, matching: find.byType(Text)),
          )
          .map((text) => text.data ?? '')
          .where((text) => text.contains('\n\n'));
      expect(
        paragraphs,
        isNotEmpty,
        reason: '$cardPrefix/${key.name} reading remains',
      );
    }
    if (cardPrefix == 'period-nine') {
      final entry = find
          .descendant(
            of: find.byKey(const ValueKey('period-nine-overall')),
            matching: find.byType(InkWell),
          )
          .first;
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      final dialog = find.byType(AlertDialog);
      expect(dialog, findsOneWidget);
      expect(
        find.descendant(of: dialog, matching: find.textContaining('Model:')),
        findsOneWidget,
      );
      Navigator.of(tester.element(dialog)).pop();
      await tester.pumpAndSettle();
    } else {
      final prefix = cardPrefix == 'nine-area' ? 'daily' : 'period-overview';
      for (final key in NineAreaKey.values) {
        expect(
          find.byKey(ValueKey('$prefix-evidence-${key.name}')),
          findsOneWidget,
        );
      }
      final entry = find.byKey(ValueKey('$prefix-evidence-overall'));
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      final ledger = tester.widget<Text>(
        find.byKey(ValueKey('$prefix-ledger-overall')),
      );
      expect(ledger.data, contains('Model:'));
    }
    expect(platformCalls, 0);
    expect(tester.takeException(), isNull);
  }

  void expectOverallBlock(
    WidgetTester tester,
    String cardPrefix,
    String expected,
  ) {
    expect(find.byType(OverallAreaHighlightsBlock), findsOneWidget);
    final block = tester.widget<OverallAreaHighlightsBlock>(
      find.byType(OverallAreaHighlightsBlock),
    );
    expect(block.highlights.text(block.strings), expected);
    for (final key in NineAreaKey.values) {
      expect(
        find.descendant(
          of: find.byKey(ValueKey('$cardPrefix-${key.name}')),
          matching: find.byType(OverallAreaHighlightsBlock),
        ),
        key == NineAreaKey.overall ? findsOneWidget : findsNothing,
      );
    }
  }

  void expectFullShareHighlights(
    WidgetTester tester,
    FortuneShareComposerSheet sheet,
    String expected,
  ) {
    expect(sheet.areaHighlightsText, expected);
    expect(
      tester
          .widget<FortuneShareImageCard>(find.byType(FortuneShareImageCard))
          .areaHighlightsText,
      expected,
    );
    final text = tester.widget<Text>(
      find.byKey(const ValueKey('share-area-highlights')),
    );
    expect(text.data, expected);
    expect(text.maxLines, isNull);
    expect(text.overflow, isNot(TextOverflow.ellipsis));
  }

  void expectSimpleLayout(WidgetTester tester, String cardPrefix) {
    final dashboard = find.byType(SimpleNineAreaDashboard);
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    final tablet = size.shortestSide >= 600;
    expect(dashboard, tablet ? findsOneWidget : findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    for (final area in NineAreaKey.values) {
      final card = find.byKey(ValueKey('$cardPrefix-${area.name}'));
      expect(card, findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.byType(ExpansionTile)),
        findsNothing,
      );
      for (final ink in tester.widgetList<InkWell>(
        find.descendant(of: card, matching: find.byType(InkWell)),
      )) {
        expect(ink.onTap, isNull);
      }
      expect(
        find.descendant(
          of: card,
          matching: find.byIcon(Icons.ios_share_outlined),
        ),
        findsNothing,
      );
      final prefix = cardPrefix == 'nine-area'
          ? 'daily'
          : cardPrefix == 'period-nine'
          ? 'period-nine'
          : 'period-overview';
      final narrative = tester.widget<Text>(
        find.byKey(ValueKey('$prefix-narrative-${area.name}')),
      );
      expect(
        narrative.data,
        isNotEmpty,
        reason: 'Every area must retain its Simple prose',
      );
      expect(narrative.maxLines, isNull);
      expect(narrative.overflow, isNot(TextOverflow.ellipsis));
      if (!tablet &&
          size.width < 600 &&
          MediaQuery.textScalerOf(tester.element(card)).scale(16) <= 19.21) {
        final value = tester.getRect(
          find.byKey(ValueKey('$prefix-value-${area.name}')),
        );
        final prose = tester.getRect(
          find.byKey(ValueKey('$prefix-narrative-${area.name}')),
        );
        expect(
          prose.left,
          greaterThanOrEqualTo(value.right),
          reason:
              'Phone Simple uses the research layout: circle left, current prose right',
        );
      }
      if (!tablet && size.width < 600) {
        expect(
          tester.getSize(card).width,
          closeTo(
            tester.getSize(find.byKey(ValueKey('$cardPrefix-overall'))).width,
            0.1,
          ),
        );
      }
    }
    if (tablet) {
      final data = tester.widget<SimpleNineAreaDashboard>(dashboard);
      expect(data.items.map((item) => item.area), NineAreaKey.values);
      final whole = tester.getRect(find.byKey(data.mainFiveKey));
      final overall = tester.getRect(
        find.byKey(ValueKey('$cardPrefix-overall')),
      );
      expect(overall.width, closeTo(whole.width, 0.1));
      final love = tester.getRect(find.byKey(ValueKey('$cardPrefix-love')));
      final work = tester.getRect(find.byKey(ValueKey('$cardPrefix-work')));
      final money = tester.getRect(find.byKey(ValueKey('$cardPrefix-money')));
      final mental = tester.getRect(find.byKey(ValueKey('$cardPrefix-mental')));
      expect(love.top, closeTo(work.top, 0.1));
      expect(money.top, closeTo(mental.top, 0.1));
      expect(money.left, closeTo(love.left, 0.1));
      expect(mental.left, closeTo(work.left, 0.1));
      expect(love.top - overall.bottom, greaterThanOrEqualTo(14));
      expect(money.top - love.bottom, greaterThanOrEqualTo(14));
      expect(work.left - love.right, greaterThanOrEqualTo(14));
      for (final item in data.items) {
        final narrative = tester.widget<Text>(
          find.byKey(ValueKey('${data.narrativeKeyPrefix}-${item.area.name}')),
        );
        expect(
          narrative.data,
          item.narrative,
          reason:
              'Tablet must retain the full original Simple prose, including overall',
        );
        expect(narrative.style?.fontSize, 14);
        expect(narrative.style?.height, 1.45);
        final card = find.byKey(ValueKey('$cardPrefix-${item.area.name}'));
        final panel = tester.widget<GlassPanel>(
          find.descendant(of: card, matching: find.byType(GlassPanel)),
        );
        expect(panel.padding, const EdgeInsets.all(18));
        final icon = tester.widget<Icon>(
          find.descendant(of: card, matching: find.byIcon(item.icon)),
        );
        expect(icon.size, 20);
        expect(icon.color, const Color(0xFFF6D77A));
        final titles = tester
            .widgetList<Text>(
              find.descendant(of: card, matching: find.text(item.title)),
            )
            .where(
              (text) =>
                  text.style?.fontSize ==
                      (item.area == NineAreaKey.overall ? 20 : 17) &&
                  text.style?.fontWeight == FontWeight.w900,
            );
        expect(titles, hasLength(1));
        expect(
          find.descendant(
            of: card,
            matching: find.text('Five main categories'),
          ),
          findsNothing,
        );
        expect(
          find.descendant(of: card, matching: find.text('主要5項目')),
          findsNothing,
        );
      }
      if (whole.width >= 700) {
        expect(
          tester.getRect(find.byKey(data.shareSummaryKey)).top,
          closeTo(tester.getRect(find.byKey(data.shareOverallKey)).top, 0.1),
        );
      }
    }
    expect(tester.takeException(), isNull);
  }

  for (final dimensions in [
    (390.0, 800.0, 1.0),
    (390.0, 800.0, 1.2),
    (1024.0, 600.0, 1.0),
    (1024.0, 600.0, 1.2),
    (390.0, 800.0, 2.0),
    (800.0, 390.0, 1.0),
  ]) {
    testWidgets(
      'phone restores full nine readings; tablet leaves generous space for all Simple prose at ${dimensions.$1}x${dimensions.$2} scale ${dimensions.$3}',
      (tester) async {
        tester.view.physicalSize = Size(dimensions.$1, dimensions.$2);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          shell(
            NineAreaDailyOverview(
              contextData: noon,
              date: date,
              details: sevenFixtureDetails,
            ),
            scale: dimensions.$3,
          ),
        );
        await frames(tester);
        expectSimpleLayout(tester, 'nine-area');
        for (final item in daily) {
          expect(
            tester
                .widget<Text>(
                  find.byKey(ValueKey('daily-narrative-${item.key.name}')),
                )
                .data,
            ForecastExplanation.forDaily(
              prediction: item,
              targetDate: date,
              strings: const AppStrings(AppLanguage.en),
              depth: ReadingDepth.simple,
              supplement: sevenFixtureDetails,
              relatedPredictions: daily,
            ).narrativeText,
          );
        }
        final dailyBadge = tester.widget<FortuneNumber>(
          find.descendant(
            of: find.byKey(const ValueKey('daily-value-work')),
            matching: find.byType(FortuneNumber),
          ),
        );
        expect(
          dailyBadge.fixedSize,
          greaterThanOrEqualTo(dailyFortuneBadgeSize * dimensions.$3),
        );
        await tester.pumpWidget(const SizedBox());
        final summary = await week(tester, scale: dimensions.$3);
        expectSimpleLayout(tester, 'period-overview-card');
        for (final area in summary.areas) {
          expect(
            tester
                .widget<Text>(
                  find.byKey(
                    ValueKey('period-overview-narrative-${area.key.name}'),
                  ),
                )
                .data,
            ForecastExplanation.forPeriod(
              summary: summary,
              area: area,
              strings: const AppStrings(AppLanguage.en),
              depth: ReadingDepth.simple,
              supplement: sevenFixtureDetails,
            ).narrativeText,
          );
        }
        final weekBadge = tester.widget<FortuneNumber>(
          find.descendant(
            of: find.byKey(const ValueKey('period-overview-value-work')),
            matching: find.byType(FortuneNumber),
          ),
        );
        expect(weekBadge.fixedSize, dailyBadge.fixedSize);
        expect(platformCalls, 0);
      },
    );
  }

  testWidgets('daily Simple shares noon values; Detailed keeps readings only', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final expectedHighlights = OverallAreaHighlights.fromPredictions(
      daily,
    ).text(const AppStrings(AppLanguage.en));
    for (final depth in ReadingDepth.values) {
      await tester.pumpWidget(
        shell(
          NineAreaDailyOverview(
            contextData: noon,
            date: date,
            details: sevenFixtureDetails,
            depth: depth,
          ),
        ),
      );
      await frames(tester);
      expectShareAvailability(
        tester,
        readingKey: 'daily-share-reading',
        sharePrefix: 'daily-share',
        cardPrefix: 'nine-area',
        depth: depth,
      );
      expectOverallBlock(tester, 'nine-area', expectedHighlights);
      if (depth == ReadingDepth.detailed) {
        await expectDetailedReading(tester, 'nine-area');
        continue;
      }
      final whole = await open(tester, 'daily-share-reading');
      expect(whole.areas.map((area) => area.key), NineAreaKey.values);
      expect(
        whole.areas.map((area) => (area.key, area.score, area.feltLabel)),
        daily.map((item) => (item.key, item.score, item.feltForecast?.label)),
      );
      expect(whole.score, daily.first.score);
      expect(whole.periodLabel, contains('2026-12-28'));
      expect(whole.periodLabel, contains('12:00 JST'));
      expectFullShareHighlights(tester, whole, expectedHighlights);
      await close(tester);

      final selected = daily.singleWhere(
        (value) => value.key == NineAreaKey.overall,
      );
      final sheet = await open(tester, 'daily-share-overall');
      expect(sheet.areas, hasLength(1));
      expect(sheet.areas.single.key, NineAreaKey.overall);
      expect(sheet.areas.single.score, selected.score);
      expect(sheet.areas.single.feltLabel, isNull);
      expect(sheet.score, selected.score);
      expect(
        sheet.body,
        ForecastExplanation.forDaily(
          prediction: selected,
          targetDate: date,
          strings: const AppStrings(AppLanguage.en),
          depth: depth,
          supplement: sevenFixtureDetails,
          relatedPredictions: daily,
        ).narrativeText,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('share-primary-title')))
            .data,
        const AppStrings(AppLanguage.en).nineAreaTitle('overall'),
      );
      expect(find.byKey(const ValueKey('share-score-overall')), findsOneWidget);
      expect(find.byKey(const ValueKey('share-felt-category')), findsNothing);
      expectFullShareHighlights(tester, sheet, expectedHighlights);
      await close(tester);
    }
    expect(
      (await SharedPreferences.getInstance()).getString('preserved.profile'),
      'untouched',
    );
    expect(platformCalls, 0);
  });

  testWidgets('weekly Simple has two shares; Detailed retains all nine cards', (
    tester,
  ) async {
    for (final depth in ReadingDepth.values) {
      await tester.pumpWidget(const SizedBox());
      PeriodSevenDisplaySessionCache.clear();
      final summary = await week(tester, depth: depth);
      final expectedHighlights = OverallAreaHighlights.fromSummary(
        summary,
      ).text(const AppStrings(AppLanguage.en));
      expectShareAvailability(
        tester,
        readingKey: 'weekly-share-reading',
        sharePrefix: 'period-overview-share',
        cardPrefix: 'period-overview-card',
        depth: depth,
      );
      expectOverallBlock(tester, 'period-overview-card', expectedHighlights);
      if (depth == ReadingDepth.detailed) {
        await expectDetailedReading(tester, 'period-overview-card');
        continue;
      }
      final whole = await open(tester, 'weekly-share-reading');
      expect(whole.areas.map((area) => area.key), NineAreaKey.values);
      expect(
        whole.areas.map((area) => (area.key, area.score, area.feltLabel)),
        summary.areas.map(
          (area) => (
            area.key,
            area.score,
            area.key == NineAreaKey.felt ? summary.feltDisplayLabel : null,
          ),
        ),
      );
      expect(summary.feltModes, hasLength(2));
      expect(whole.score, summary.areas.first.score);
      expect(whole.periodLabel, contains(summary.startDateJst));
      expectFullShareHighlights(tester, whole, expectedHighlights);
      await close(tester);

      final sheet = await open(tester, 'period-overview-share-overall');
      final area = summary.areas.singleWhere(
        (area) => area.key == NineAreaKey.overall,
      );
      expect(sheet.areas, hasLength(1));
      expect(sheet.areas.single.key, NineAreaKey.overall);
      expect(sheet.score, area.score);
      expect(
        sheet.body,
        ForecastExplanation.forPeriod(
          summary: summary,
          area: area,
          strings: const AppStrings(AppLanguage.en),
          depth: depth,
          supplement: sevenFixtureDetails,
        ).narrativeText,
      );
      expect(sheet.areas.single.score, area.score);
      expect(sheet.areas.single.feltLabel, isNull);
      expectFullShareHighlights(tester, sheet, expectedHighlights);
      await close(tester);
    }
    expect(platformCalls, 0);
  });

  testWidgets(
    'felt composer remains inside its hero at 390px and double text size',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({
        'preserved.profile': 'untouched',
        'share_card_display_name': 'Evening reader',
        'share_card_theme': FortuneShareTheme.catFlower.name,
      });
      await tester.pumpWidget(
        shell(
          Builder(
            builder: (context) => TextButton(
              key: const ValueKey('felt-zoom-share'),
              onPressed: () => showNineAreaReadingShareComposer(
                context,
                periodLabel: '2026-12-28 · Daily reading (12:00 JST)',
                areas: const [
                  FortuneShareArea(
                    key: NineAreaKey.felt,
                    title: 'Felt experience',
                    feltLabel: '未予測',
                  ),
                ],
                body: List.filled(
                  12,
                  'The required inputs are unavailable. Leave the felt category unpredicted and review it when data is available.',
                ).join(' '),
              ),
              child: const Text('Share felt reading'),
            ),
          ),
          scale: 2,
        ),
      );
      final sheet = await open(tester, 'felt-zoom-share');
      expect(sheet.areas.single.key, NineAreaKey.felt);
      expect(sheet.score, isNull);
      expect(sheet.areaHighlightsText, isEmpty);
      expect(find.byKey(const ValueKey('share-area-highlights')), findsNothing);
      expect(
        tester
            .widget<FortuneShareImageCard>(find.byType(FortuneShareImageCard))
            .areaHighlightsText,
        isEmpty,
      );
      expect(find.text('Not predicted'), findsOneWidget);
      expect(find.byKey(const ValueKey('share-display-name')), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('share-display-name')))
            .data,
        'Evening reader',
      );
      final hero = tester.getRect(
        find.byKey(const ValueKey('share-art-region')),
      );
      for (final key in [
        'share-display-name',
        'share-primary-title',
        'share-score-felt',
      ]) {
        final bounds = tester.getRect(find.byKey(ValueKey(key)));
        expect(bounds.top, greaterThanOrEqualTo(hero.top), reason: key);
        expect(bounds.bottom, lessThanOrEqualTo(hero.bottom), reason: key);
      }
      expect(tester.takeException(), isNull);
      expect(platformCalls, 0);
      expect(
        (await SharedPreferences.getInstance()).getString('preserved.profile'),
        'untouched',
      );
    },
  );

  // Explicit regression: unlike the real-context roundtrip tests above, this
  // fixture pins activity to 69. All other daily displayed values remain intact;
  // the six-area overall score is not recomputed or replaced.
  for (final mode in ['daily', 'week', 'month', 'year', 'fiveYear']) {
    testWidgets(
      'activity 69 stays in care for $mode Simple shares and Detailed cards',
      (tester) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final action69 = [
          for (final prediction in daily)
            if (prediction.key == NineAreaKey.actionDecision)
              NineAreaPrediction(
                key: prediction.key,
                title: prediction.title,
                icon: prediction.icon,
                summary: 'Synthetic activity 69 fixture',
                detail: 'Synthetic activity 69 fixture',
                score: 69,
                provisional: true,
              )
            else
              prediction,
        ];
        expect(action69.first.score, daily.first.score);
        for (final language in AppLanguage.values) {
          for (final depth in ReadingDepth.values) {
            await tester.pumpWidget(const SizedBox());
            PeriodSevenDisplaySessionCache.clear();
            AppLanguageSettings.current.value = language;
            final strings = AppStrings(language);
            late String readingKey, sharePrefix, cardPrefix;
            late OverallAreaHighlights highlights;
            if (mode == 'daily') {
              readingKey = 'daily-share-reading';
              sharePrefix = 'daily-share';
              cardPrefix = 'nine-area';
              highlights = OverallAreaHighlights.fromPredictions(action69);
              // The daily grid is the existing presentation boundary for already
              // computed predictions. The public overview's real context/share
              // roundtrip remains covered above without adding an injection API.
              await tester.pumpWidget(
                shell(
                  Builder(
                    builder: (context) {
                      void share(NineAreaPrediction? selected) {
                        final primary = selected ?? action69.first;
                        showNineAreaReadingShareComposer(
                          context,
                          periodLabel:
                              '2026-12-28 · activity 69 regression fixture',
                          areaHighlightsText:
                              OverallAreaHighlights.fromPredictions(
                                action69,
                              ).text(strings),
                          areas: [
                            for (final item
                                in selected == null ? action69 : [primary])
                              FortuneShareArea(
                                key: item.key,
                                title: strings.nineAreaTitle(item.key.name),
                                score: item.score,
                                feltLabel: item.feltForecast?.label,
                              ),
                          ],
                          body: ForecastExplanation.forDaily(
                            prediction: primary,
                            targetDate: date,
                            strings: strings,
                            depth: depth,
                            supplement: sevenFixtureDetails,
                            relatedPredictions: action69,
                          ).narrativeText,
                        );
                      }

                      return NineAreaGrid(
                        predictions: action69,
                        targetDate: date,
                        depth: depth,
                        details: sevenFixtureDetails,
                        onShare: () => share(null),
                        onShareArea: share,
                      );
                    },
                  ),
                ),
              );
            } else if (mode == 'week') {
              readingKey = 'weekly-share-reading';
              sharePrefix = 'period-overview-share';
              cardPrefix = 'period-overview-card';
              final summary = await week(tester, depth: depth, actionScore: 69);
              expect(
                summary.areas
                    .singleWhere(
                      (area) => area.key == NineAreaKey.actionDecision,
                    )
                    .score,
                69,
              );
              highlights = OverallAreaHighlights.fromSummary(summary);
            } else {
              readingKey = 'period-share-reading';
              sharePrefix = 'period-share';
              cardPrefix = 'period-nine';
              final request = LongRangeDisplayRequest(
                mode: LongRangeDisplayMode.values.byName(mode),
                month: DateTime.utc(2026, 12),
                startYear: 2026,
                profile: sevenFixtureProfile,
                houseSystem: HouseSystem.placidus,
                fullContext: false,
              );
              final samples = {
                for (final instant in request.dates) instant: action69,
              };
              final summary = LongRangeDisplaySummary.fromSamples(
                request: request,
                samples: samples,
              );
              expect(
                summary.areas
                    .singleWhere(
                      (area) => area.key == NineAreaKey.actionDecision,
                    )
                    .score,
                69,
              );
              highlights = OverallAreaHighlights.fromSummary(summary);
              await tester.pumpWidget(
                shell(
                  NineAreaPeriodOverview(
                    summary: summary,
                    depth: depth,
                    details: sevenFixtureDetails,
                    dailySamples: {
                      for (final row in samples.entries)
                        NineAreaPeriodSummary.dateLabel(row.key): row.value,
                    },
                  ),
                ),
              );
            }
            await frames(tester);
            final reason = '$mode/${language.name}/${depth.name}';
            final expected = highlights.text(strings);
            final activity =
                '${strings.nineAreaTitle('actionDecision')}${language == AppLanguage.en ? ' ' : ''}69';
            final carePrefix = language == AppLanguage.en
                ? 'Care needed (70 or below):'
                : '注意（70点以下）：';
            // These are independent fixed expectations: comparing a UI with the
            // same helper alone would miss the original six-category omission.
            expect(
              highlights.careNeeded[NineAreaKey.actionDecision],
              69,
              reason: reason,
            );
            expect(
              highlights.higher.containsKey(NineAreaKey.actionDecision),
              false,
              reason: reason,
            );
            expect(
              expected
                  .split('\n')
                  .singleWhere((line) => line.startsWith(carePrefix)),
              contains(activity),
              reason: reason,
            );
            expectShareAvailability(
              tester,
              readingKey: readingKey,
              sharePrefix: sharePrefix,
              cardPrefix: cardPrefix,
              language: language,
              depth: depth,
            );
            expectOverallBlock(tester, cardPrefix, expected);
            final block = find.descendant(
              of: find.byKey(ValueKey('$cardPrefix-overall')),
              matching: find.byType(OverallAreaHighlightsBlock),
            );
            expect(
              find.descendant(
                of: block,
                matching: find.textContaining(activity),
              ),
              findsOneWidget,
              reason: reason,
            );

            if (depth == ReadingDepth.detailed) {
              await expectDetailedReading(tester, cardPrefix);
              continue;
            }

            expectSimpleLayout(tester, cardPrefix);
            for (final width in [390.0, 1024.0]) {
              tester.view.physicalSize = Size(width, width < 700 ? 800 : 600);
              tester.view.devicePixelRatio = 1;
              await frames(tester);
              expectSimpleLayout(tester, cardPrefix);
            }
            for (final entry in [readingKey, '$sharePrefix-overall']) {
              final sheet = await open(tester, entry);
              expectFullShareHighlights(tester, sheet, expected);
              expect(
                sheet.areaHighlightsText
                    .split('\n')
                    .singleWhere((line) => line.startsWith(carePrefix)),
                contains(activity),
                reason: '$reason/$entry',
              );
              final imageText = tester
                  .widget<Text>(
                    find.byKey(const ValueKey('share-area-highlights')),
                  )
                  .data!;
              expect(
                imageText
                    .split('\n')
                    .singleWhere((line) => line.startsWith(carePrefix)),
                contains(activity),
                reason: '$reason/$entry',
              );
              if (entry == readingKey) {
                expect(sheet.areas, hasLength(9));
                expect(
                  sheet.areas
                      .singleWhere(
                        (area) => area.key == NineAreaKey.actionDecision,
                      )
                      .score,
                  69,
                );
              } else {
                expect(sheet.areas, hasLength(1));
                expect(sheet.areas.single.key, NineAreaKey.overall);
              }
              await close(tester);
            }
            expect(platformCalls, 0);
          }
        }
      },
    );
  }

  for (final mode in [
    LongRangeDisplayMode.month,
    LongRangeDisplayMode.year,
    LongRangeDisplayMode.fiveYear,
  ]) {
    testWidgets(
      '${mode.name} Simple shares values; Detailed keeps nine readings',
      (tester) async {
        final request = LongRangeDisplayRequest(
          mode: mode,
          month: DateTime.utc(2026, 12),
          startYear: 2026,
          profile: sevenFixtureProfile,
          houseSystem: HouseSystem.placidus,
          fullContext: false,
        );
        final samples = {for (final instant in request.dates) instant: daily};
        final dailySamples = {
          for (final row in samples.entries)
            NineAreaPeriodSummary.dateLabel(row.key): row.value,
        };
        final summary = LongRangeDisplaySummary.fromSamples(
          request: request,
          samples: samples,
        );
        final expectedHighlights = OverallAreaHighlights.fromSummary(
          summary,
        ).text(const AppStrings(AppLanguage.en));
        for (final depth in ReadingDepth.values) {
          await tester.pumpWidget(
            shell(
              NineAreaPeriodOverview(
                summary: summary,
                dailySamples: dailySamples,
                details: sevenFixtureDetails,
                depth: depth,
              ),
            ),
          );
          await frames(tester);
          expectShareAvailability(
            tester,
            readingKey: 'period-share-reading',
            sharePrefix: 'period-share',
            cardPrefix: 'period-nine',
            depth: depth,
          );
          expectOverallBlock(tester, 'period-nine', expectedHighlights);
          if (depth == ReadingDepth.detailed) {
            await expectDetailedReading(tester, 'period-nine');
            continue;
          }
          final whole = await open(tester, 'period-share-reading');
          expect(whole.areas.map((area) => area.key), NineAreaKey.values);
          expect(
            whole.areas.map((area) => (area.key, area.score, area.feltLabel)),
            summary.areas.map(
              (area) => (
                area.key,
                area.score,
                area.key == NineAreaKey.felt
                    ? summary.displayFeltLabel(const AppStrings(AppLanguage.en))
                    : null,
              ),
            ),
          );
          expect(whole.score, summary.areas.first.score);
          expect(
            whole.periodLabel,
            nineAreaPeriodShareLabel(summary, const AppStrings(AppLanguage.en)),
          );
          expectFullShareHighlights(tester, whole, expectedHighlights);
          await close(tester);

          final sheet = await open(tester, 'period-share-overall');
          final area = summary.areas.singleWhere(
            (area) => area.key == NineAreaKey.overall,
          );
          expect(sheet.areas, hasLength(1));
          expect(sheet.areas.single.key, NineAreaKey.overall);
          expect(sheet.areas.single.score, area.score);
          expect(sheet.areas.single.feltLabel, isNull);
          expect(sheet.score, area.score);
          expect(
            sheet.body,
            ForecastExplanation.forPeriod(
              summary: summary,
              area: area,
              strings: const AppStrings(AppLanguage.en),
              depth: depth,
              supplement: sevenFixtureDetails,
              dailySamples: dailySamples,
              includeEvidence: false,
            ).narrativeText,
          );
          expectFullShareHighlights(tester, sheet, expectedHighlights);
          await close(tester);
        }
        expect(platformCalls, 0);
      },
    );
  }
}
