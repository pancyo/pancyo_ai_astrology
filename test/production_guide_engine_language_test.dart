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
      await tester.pumpWidget(
        _host(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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

      expect(find.text('Current Venus and natal Moon'), findsOneWidget);
      expect(find.text('Current Mercury and current Jupiter'), findsOneWidget);
      expect(find.text('Major aspects on this day'), findsOneWidget);
      expect(find.text('Aspects between current planets'), findsOneWidget);
      expect(find.text('Current planetary placements'), findsOneWidget);
      expect(find.text('sextile'), findsOneWidget);
      expect(find.text('An aspect that may create an opening'), findsOneWidget);
      expect(
        find.textContaining(
          'The influence may be quite strong. Affection and enjoyment may support mood and daily rhythm.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Mercury is retrograde'), findsOneWidget);
      expect(
        find.textContaining(
          'Venus: Scorpio 7.3° / relationships, enjoyment and attitudes toward money',
        ),
        findsOneWidget,
      );
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
    AppLanguageSettings.current.value = AppLanguage.en;
    await tester.pumpWidget(
      _host(TodayAstroDataPanel(contextData: _context())),
    );
    await tester.tap(find.text('Open the full aspect table'));
    await tester.pumpAndSettle();

    expect(find.text('Venus in Scorpio 7.3° / House 10'), findsOneWidget);
    expect(find.text('Moon in Libra 23.4° / House 10'), findsOneWidget);
    expect(
      find.text('Mercury in Scorpio 2.1° / House 9 retrograde'),
      findsOneWidget,
    );
    expect(find.text('Jupiter in Cancer 16.4° / House 5'), findsOneWidget);
    final moonHouseRow = find.text('Moon transiting natal House 10 / Work');
    await tester.ensureVisible(moonHouseRow);
    await tester.pumpAndSettle();
    expect(moonHouseRow, findsOneWidget);
    final noReturns = find.text('No planetary returns today.');
    await tester.ensureVisible(noReturns);
    await tester.pumpAndSettle();
    expect(noReturns, findsOneWidget);
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
