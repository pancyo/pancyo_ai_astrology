import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pancyo_ai_astrology/app_language.dart';
import 'package:pancyo_ai_astrology/app_language_settings.dart';
import 'package:pancyo_ai_astrology/legacy_reading_english.dart';
import 'package:pancyo_ai_astrology/main.dart';

const _profile = AstroProfile(
  name: 'QA guide fixture',
  birthDate: '1990/1/2',
  birthTime: '12:00',
  birthPlace: '札幌・本人入力',
  theme: '仕事',
);

HoroscopeReadingContext _context() {
  const natalSun = PlanetPlacement(
    planet: AstroPlanet.sun,
    sign: ZodiacSign.libra,
    degree: 11.2,
    house: 1,
  );
  const natalMoon = PlanetPlacement(
    planet: AstroPlanet.moon,
    sign: ZodiacSign.taurus,
    degree: 4.8,
    house: 7,
  );
  const natalVenus = PlanetPlacement(
    planet: AstroPlanet.venus,
    sign: ZodiacSign.scorpio,
    degree: 7.3,
    house: 10,
  );
  const transitVenus = PlanetPlacement(
    planet: AstroPlanet.venus,
    sign: ZodiacSign.scorpio,
    degree: 7.3,
    house: 10,
  );
  const transitMoon = PlanetPlacement(
    planet: AstroPlanet.moon,
    sign: ZodiacSign.libra,
    degree: 23.4,
    house: 10,
  );
  const transitMercury = PlanetPlacement(
    planet: AstroPlanet.mercury,
    sign: ZodiacSign.scorpio,
    degree: 2.1,
    house: 9,
  );
  const transitJupiter = PlanetPlacement(
    planet: AstroPlanet.jupiter,
    sign: ZodiacSign.cancer,
    degree: 16.4,
    house: 5,
  );
  const natal = NatalChart(
    profile: _profile,
    placements: [natalSun, natalMoon, natalVenus],
    stelliums: [],
    retrogradePlanets: {},
  );
  const venusMoon = TransitAspect(
    transitPlanet: AstroPlanet.venus,
    natalPlanet: AstroPlanet.moon,
    type: AspectType.sextile,
    orb: 0.4,
    area: FortuneArea.love,
    meaning: '架空テスト用の説明',
  );
  const mercuryJupiter = TransitPairAspect(
    firstPlanet: AstroPlanet.mercury,
    secondPlanet: AstroPlanet.jupiter,
    type: AspectType.trine,
    orb: 0.3,
    phase: AspectPhase.exact,
  );
  return HoroscopeReadingContext(
    natal: natal,
    transit: TransitChart(
      date: DateTime.utc(2026, 10, 11, 3),
      placements: [transitVenus, transitMoon, transitMercury, transitJupiter],
      voidMoon: null,
    ),
    nextTransitPlacements: [transitMercury, transitJupiter],
    aspects: [venusMoon],
    fullAspects: [venusMoon],
    nextAspects: [],
    transitPairAspects: [mercuryJupiter],
    retrogradePlanets: {AstroPlanet.mercury},
    houseTransits: const [
      HouseTransit(
        planet: AstroPlanet.moon,
        natalHouse: 10,
        area: FortuneArea.work,
        meaning: '架空テスト用の説明',
      ),
    ],
    returns: const [],
    birthPlace: const GeoPoint(
      label: '札幌',
      latitude: 43.061,
      longitude: 141.354,
    ),
    ephemerisSourceName: 'Swiss Ephemeris Free Edition/AGPL',
    ephemerisPrecisionNotice:
        'Swiss Ephemeris Free Edition/AGPLをAndroidネイティブで使用しています。アプリ同梱のMoshier計算で星の位置を算出し、月ボイド開始は5分探索後に最後の主要アスペクトの正確時刻へ絞り込みます。',
    usesHighPrecisionAstroData: true,
    houseSystem: HouseSystem.placidus,
    houseCusps: List<double>.filled(12, 0),
  );
}

Widget _host(Widget child) => MaterialApp(
  theme: ThemeData.dark(),
  home: AppLanguageScope(
    child: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: child,
      ),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    AppLanguageSettings.current.value = AppLanguage.ja;
  });

  const voidGuidance = '月が次の星座へ入る前の空白時間。新規決定より見直し、休息、準備向き。';
  const englishVoidGuidance =
      'A pause before the Moon enters the next sign. Favor review, rest and preparation over new decisions.';
  final voidPeriod = VoidMoonPeriod(
    start: '09:15',
    end: '10:45',
    startTime: DateTime.utc(2026, 10, 2, 0, 15),
    endTime: DateTime.utc(2026, 10, 2, 1, 45),
    guidance: voidGuidance,
  );

  for (final language in AppLanguage.values) {
    for (final width in [360.0, 800.0]) {
      testWidgets('void notice ${language.name} at width $width', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        AppLanguageSettings.current.value = language;
        await tester.pumpWidget(_host(VoidTimeNotice(period: voidPeriod)));

        expect(
          find.text(
            language == AppLanguage.en ? englishVoidGuidance : voidGuidance,
          ),
          findsOneWidget,
        );
        expect(find.text('09:15 - 10:45'), findsOneWidget);
        expect(voidPeriod.guidance, voidGuidance);
        expect(voidPeriod.startTime, DateTime.utc(2026, 10, 2, 0, 15));
        expect(voidPeriod.endTime, DateTime.utc(2026, 10, 2, 1, 45));
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(_host(const VoidTimeNotice(period: null)));
        expect(find.text('09:15 - 10:45'), findsNothing);
        expect(find.text(englishVoidGuidance), findsNothing);
        expect(find.text(voidGuidance), findsNothing);
      });
    }

    testWidgets(
      'share void caption follows colored theme in ${language.name}',
      (tester) async {
        final noon = DateTime.utc(2026, 10, 2, 3);
        final base = const AstrologyEngine().buildPreviewContext(
          profile: _profile,
          date: noon,
        );
        final contextData = HoroscopeReadingContext(
          natal: base.natal,
          transit: TransitChart(
            date: base.transit.date,
            placements: base.transit.placements,
            voidMoon: voidPeriod,
          ),
          nextTransitPlacements: base.nextTransitPlacements,
          aspects: base.aspects,
          fullAspects: base.fullAspects,
          nextAspects: base.nextAspects,
          transitPairAspects: base.transitPairAspects,
          retrogradePlanets: base.retrogradePlanets,
          houseTransits: base.houseTransits,
          returns: base.returns,
          birthPlace: base.birthPlace,
          ephemerisSourceName: base.ephemerisSourceName,
          ephemerisPrecisionNotice: base.ephemerisPrecisionNotice,
          usesHighPrecisionAstroData: base.usesHighPrecisionAstroData,
          houseSystem: base.houseSystem,
          houseCusps: base.houseCusps,
        );
        final request = DailyStarTimelineRequest.fromContext(
          date: noon,
          contextData: contextData,
          profile: _profile,
        );
        final result = calculateDailyStarTimeline(request);
        final data = DailyStarTimelineShareData.checked(
          request: request,
          result: result,
        );
        AppLanguageSettings.current.value = language;
        await tester.pumpWidget(
          _host(
            DailyStarTimelineShareImageCard(
              data: data,
              theme: FortuneShareTheme.catFlower,
            ),
          ),
        );
        final caption = language == AppLanguage.en
            ? 'Highlighted band: void-of-course Moon 09:15–10:45 (JST)'
            : 'ハイライト帯：月ボイド 09:15〜10:45（JST）';
        expect(find.text(caption), findsOneWidget);
        expect(find.textContaining('Yellow band'), findsNothing);
        expect(find.textContaining('黄帯'), findsNothing);
        final painter = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((widget) => widget.painter)
            .whereType<DailyStarTimeBarPainter>()
            .single;
        expect(painter.voidColor, FortuneShareTheme.catFlower.palette.score);
        expect(painter.voidMoon, same(voidPeriod));
        expect(data.voidMoon, same(voidPeriod));
        for (var i = 0; i < data.points.length; i++) {
          expect(data.points[i].degree, result.points[i].moon.degree);
          expect(data.points[i].birthHouse, result.points[i].moon.house);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final language in AppLanguage.values) {
    testWidgets('legacy current details preserve ingress dates in ${language.name}', (
      tester,
    ) async {
      AppLanguageSettings.current.value = language;
      const current =
          '現在: 金星: 蠍座 7.3° → 天秤座 10/11(日) 12:00 / 月: 天秤座 23.4° → 蠍座 10/12(月) 08:15 / 木星: 獅子座 21.3° / 水星: 蠍座 2.1°';
      await tester.pumpWidget(
        _host(
          const LongFortuneEvidencePanel(
            current: current,
            transitHouse: '金星 第7ハウス / 月 第6ハウス',
            natal: '金星 第10ハウス',
            correction: '現在の金星 セクスタイル 出生図の月',
          ),
        ),
      );
      final details = find
          .text(language == AppLanguage.en ? 'Details' : '詳しく')
          .first;
      await tester.ensureVisible(details);
      await tester.tap(details);
      await tester.pumpAndSettle();
      for (final line
          in language == AppLanguage.en
              ? [
                  'Venus: Scorpio 7.3° → Libra 10/11 (Sun) 12:00: Preferences, affection and use of money',
                  'Moon: Libra 23.4° → Scorpio 10/12 (Mon) 08:15: Mood, security and daily condition',
                  'Jupiter: Leo 21.3°: Expansion, opportunities and growth',
                  'Mercury: Scorpio 2.1°: Decisions, messages, words and learning',
                ]
              : [
                  '金星: 蠍座 7.3° → 天秤座 10/11(日) 12:00: 好み、愛情、お金の使い方',
                  '月: 天秤座 23.4° → 蠍座 10/12(月) 08:15: 気分、安心感、日々のコンディション',
                  '木星: 獅子座 21.3°: 拡大、チャンス、増える流れ',
                  '水星: 蠍座 2.1°: 判断、連絡、言葉、学び',
                ]) {
        final displayed = find.text(line);
        await tester.ensureVisible(displayed);
        await tester.pumpAndSettle();
        expect(displayed, findsOneWidget);
      }
      if (language == AppLanguage.en) {
        expect(
          find.textContaining('Venus transiting natal House 7:'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Moon transiting natal House 6:'),
          findsOneWidget,
        );
        expect(
          find.text('Venus: Scorpio 7.3° → Libra 10: 好み、愛情、お金の使い方'),
          findsNothing,
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'engine summary translates known values but preserves entered place',
    (tester) async {
      AppLanguageSettings.current.value = AppLanguage.en;
      await tester.pumpWidget(
        _host(HoroscopeEngineSummary(contextData: _context())),
      );

      expect(find.text('What the reading engine covers'), findsOneWidget);
      expect(find.text('Natal Venus'), findsOneWidget);
      expect(
        find.text('Venus in Scorpio 7.3° / House 10'),
        findsAtLeastNWidgets(1),
      );
      expect(find.text('Entered birthplace'), findsOneWidget);
      expect(find.text('札幌・本人入力'), findsOneWidget);
      expect(
        find.text('Sapporo / latitude 43.061°, longitude 141.354°'),
        findsOneWidget,
      );
      expect(find.text('Moon: transiting natal House 10'), findsOneWidget);
      expect(
        find.textContaining('Swiss Ephemeris Free Edition/AGPL runs natively'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'daily aspect, placement and expanded House 10 details are translated',
    (tester) async {
      AppLanguageSettings.current.value = AppLanguage.en;
      final contextData = _context();
      await tester.pumpWidget(
        _host(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TodayAstroDataPanel(contextData: contextData),
              const LongFortuneEvidencePanel(
                current: '月',
                transitHouse: '月 第10ハウス',
                natal: '金星 第7ハウス',
                correction: '現在の金星 セクスタイル 出生図の月',
              ),
            ],
          ),
        ),
      );

      expect(find.text('Transiting Venus and natal Moon'), findsOneWidget);
      expect(
        find.text('Transiting Mercury and transiting Jupiter'),
        findsOneWidget,
      );
      expect(find.text('Major aspects for this date'), findsOneWidget);
      expect(find.text('Aspects between transiting planets'), findsOneWidget);
      expect(find.text('Planet positions for this date'), findsOneWidget);
      expect(find.text('sextile'), findsOneWidget);
      expect(find.text('A small step can open an opportunity.'), findsOneWidget);
      expect(
        find.text(
          'The influence is particularly strong. Current affection and enjoyment '
          'supports your natal mood and daily rhythm. A small message, '
          'preparation, or proposal can open a useful opportunity.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Mercury retrograde. Review messages, decisions, and plans before '
          'confirming them.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Venus: Scorpio 7.3° / Relationships, pleasure, and spending'),
        findsOneWidget,
      );
      final aspects = tester.widgetList<AspectLine>(find.byType(AspectLine));
      final natalAspect = aspects.singleWhere(
        (line) => line.from == 'Transiting Venus',
      );
      expect(natalAspect.to, 'natal Moon');
      expect(natalAspect.aspectName, 'sextile');
      expect(natalAspect.angle, '60°');
      expect(natalAspect.orb, 'Orb 0.4°');
      expect(natalAspect.time, 'Near peak now');
      final skyAspect = aspects.singleWhere(
        (line) => line.from == 'Transiting Mercury',
      );
      expect(skyAspect.to, 'transiting Jupiter');
      expect(skyAspect.aspectName, 'trine');
      expect(skyAspect.angle, '120°');
      expect(skyAspect.orb, 'Orb 0.3°');
      expect(skyAspect.time, 'Near peak now');
      final detailsButton = find.text('Details').first;
      await tester.ensureVisible(detailsButton);
      await tester.pumpAndSettle();
      await tester.tap(detailsButton);
      await tester.pumpAndSettle();
      final moonHouseDetail = find.textContaining(
        'Moon transiting natal House 10: during this transit, work, recognition and titles may influence mood and a sense of security.',
      );
      await tester.ensureVisible(moonHouseDetail);
      await tester.pumpAndSettle();
      expect(moonHouseDetail, findsOneWidget);
      expect(contextData.aspects.single.meaning, '架空テスト用の説明');
      expect(contextData.transit.date, DateTime.utc(2026, 10, 11, 3));
      expect(contextData.transit.date.isUtc, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Japanese mode keeps original generated wording and house numbers',
    (tester) async {
      AppLanguageSettings.current.value = AppLanguage.ja;
      await tester.pumpWidget(
        _host(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HoroscopeEngineSummary(contextData: _context()),
              TodayAstroDataPanel(contextData: _context()),
              const LongFortuneEvidencePanel(
                current: '月',
                transitHouse: '月 第10ハウス',
                natal: '金星 第7ハウス',
                correction: '現在の金星 セクスタイル 出生図の月',
              ),
            ],
          ),
        ),
      );

      expect(find.text('鑑定エンジンの見る範囲'), findsOneWidget);
      expect(find.text('この日の主要アスペクト'), findsOneWidget);
      expect(find.text('現在の金星 と 出生図の月'), findsOneWidget);
      final detailsButton = find.text('詳しく').first;
      await tester.ensureVisible(detailsButton);
      await tester.pumpAndSettle();
      await tester.tap(detailsButton);
      await tester.pumpAndSettle();
      final moonHouseDetail = find.textContaining(
        '月 第10ハウス: 通過中は仕事、評価、肩書きに気分や安心感が左右されやすい',
      );
      await tester.ensureVisible(moonHouseDetail);
      await tester.pumpAndSettle();
      expect(moonHouseDetail, findsOneWidget);
    },
  );

  testWidgets('the full aspect table translates positions and house transits', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    AppLanguageSettings.current.value = AppLanguage.en;
    final contextData = _context();
    await tester.pumpWidget(
      _host(TodayAstroDataPanel(contextData: contextData)),
    );
    await tester.tap(find.text('Open all aspects'));
    await tester.pumpAndSettle();

    const positionsLabel =
        'Positions: 2026-10-11 (Sun) 12:00 JST (UTC+09:00)';
    expect(find.text(positionsLabel), findsOneWidget);
    for (final expected in [
      'All aspect details',
      'Current planet positions',
      'All aspects to the natal chart',
      'All aspects between transiting planets',
      'Venus Scorpio 7.3° House 10',
      'Moon Libra 23.4° House 10',
      'Mercury Scorpio 2.1° House 9 retrograde',
      'Jupiter Cancer 16.4° House 5',
      'Venus sextile natal Moon Orb 0.4° / Near peak now',
      'Mercury trine Jupiter Orb 0.3° / Near peak now',
    ]) {
      expect(find.text(expected), findsOneWidget, reason: expected);
    }
    final moonHouseRow = find.text('Moon House 10 / Work');
    await tester.ensureVisible(moonHouseRow);
    await tester.pumpAndSettle();
    expect(moonHouseRow, findsOneWidget);
    final noReturns = find.text('No planetary returns for this date.');
    await tester.ensureVisible(noReturns);
    await tester.pumpAndSettle();
    expect(noReturns, findsOneWidget);

    // The picker edits civil JST fields. Confirming unchanged controls must
    // preserve the original instant and synthetic aspects, not recalculate.
    await tester.tap(find.text('Change date/time'));
    await tester.pumpAndSettle();
    final datePicker = tester.widget<DatePickerDialog>(
      find.byType(DatePickerDialog),
    );
    expect(datePicker.initialDate, DateTime(2026, 10, 11));
    expect(datePicker.helpText, 'Date for all aspects (JST)');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    final timePicker = tester.widget<TimePickerDialog>(
      find.byType(TimePickerDialog),
    );
    expect(timePicker.initialTime, const TimeOfDay(hour: 12, minute: 0));
    expect(timePicker.helpText, 'Time for all aspects (JST)');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text(positionsLabel), findsOneWidget);
    expect(
      find.text('Venus sextile natal Moon Orb 0.4° / Near peak now'),
      findsOneWidget,
    );
    expect(contextData.transit.date, DateTime.utc(2026, 10, 11, 3));
    expect(contextData.transit.date.isUtc, isTrue);
    expect(contextData.aspects.single.meaning, '架空テスト用の説明');
    expect(contextData.fullAspects.single, same(contextData.aspects.single));
    expect(contextData.natal.profile.birthPlace, '札幌・本人入力');
    expect(tester.takeException(), isNull);
  });

  test(
    'generated transit evidence keeps signs, degrees and houses distinct',
    () {
      expect(
        englishLegacyReadingText('金星: 蠍座 7.3° → 天秤座 10/11(日) 12:00'),
        'Venus: Scorpio 7.3° → Libra 10/11 (Sun) 12:00',
      );
      expect(
        englishLegacyReadingText('月: 天秤座 23.4° / 第10ハウス'),
        'Moon: Libra 23.4° / House 10',
      );
      expect(
        englishLegacyReadingText('月 第10H / 仕事運'),
        'Moon transiting natal House 10 / Work',
      );
      for (final planet in ['金星', '月', '木星', '水星']) {
        expect(
          englishLegacyReadingText('$planetが出生図の第10ハウスを通過'),
          contains('House transit 10'),
        );
        final detail = englishLegacyReadingText(
          '$planet: 第10ハウス通過: 通過中は仕事、評価、肩書き${switch (planet) {
            '金星' => 'で愛情、お金、楽しみが動きやすい',
            '月' => 'に気分や安心感が左右されやすい',
            '木星' => 'で拡大、支援、チャンスが出やすい',
            _ => 'で判断、連絡、調整が動きやすい',
          }}',
        );
        expect(detail, contains('transiting natal House 10'));
        expect(detail, isNot(matches(RegExp(r'[\u3040-\u30ff\u3400-\u9fff]'))));
      }
      expect(
        englishLegacyReadingText('出生図集中: 第10ハウス集中: 太陽・金星・水星'),
        'Natal House 10 stellium: Sun, Venus, Mercury',
      );
      expect(
        englishLegacyReadingText('金星リターン: 近い・接近中'),
        'Venus return: near, applying',
      );
    },
  );
}
