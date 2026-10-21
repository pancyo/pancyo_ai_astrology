// Display fixtures exercise wording and rendering, not astronomical accuracy.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pancyo_ai_astrology/app_language.dart';
import 'package:pancyo_ai_astrology/app_language_settings.dart';
import 'package:pancyo_ai_astrology/main.dart';

final _cjk = RegExp(r'[\u3040-\u30ff\u3400-\u9fff]');
const _signNames = [
  'Aries',
  'Taurus',
  'Gemini',
  'Cancer',
  'Leo',
  'Virgo',
  'Libra',
  'Scorpio',
  'Sagittarius',
  'Capricorn',
  'Aquarius',
  'Pisces',
];

HoroscopeReadingContext _fixture({DateTime? instant}) {
  const profile = AstroProfile(
    name: 'Anonymous display fixture',
    birthDate: '1990/1/2',
    birthTime: '12:00',
    birthPlace: 'fixture',
    theme: 'fixture',
  );
  final placements = [
    for (final planet in AstroPlanet.values)
      PlanetPlacement(
        planet: planet,
        sign: planet.index < 3
            ? [
                ZodiacSign.aries,
                ZodiacSign.leo,
                ZodiacSign.sagittarius,
              ][planet.index]
            : ZodiacSign.values[planet.index],
        degree: planet.index < 3 ? 0 : 12,
        house: planet.index + 1,
      ),
  ];
  final aspects = [
    for (final type in AspectType.values)
      TransitAspect(
        transitPlanet: AstroPlanet.values[type.index],
        natalPlanet: AstroPlanet.values[type.index + 1],
        type: type,
        orb: type.index + 0.5,
        area: FortuneArea.values[type.index],
        meaning: '保存用の日本語本文は変更しない',
      ),
  ];
  return HoroscopeReadingContext(
    natal: NatalChart(
      profile: profile,
      placements: placements,
      stelliums: const [
        HouseEmphasis(
          house: 1,
          planets: [AstroPlanet.sun, AstroPlanet.moon, AstroPlanet.mercury],
          theme: '保存用のテーマ',
        ),
      ],
      retrogradePlanets: const {},
    ),
    transit: TransitChart(
      date: instant ?? DateTime.utc(2026, 10, 21, 3),
      placements: placements,
      voidMoon: VoidMoonPeriod(
        start: '11:00',
        end: '13:00',
        startTime: DateTime(2026, 10, 21, 11),
        endTime: DateTime(2026, 10, 21, 13),
        guidance: '保存用のボイド説明',
      ),
    ),
    nextTransitPlacements: placements,
    aspects: aspects,
    fullAspects: aspects,
    nextAspects: aspects,
    transitPairAspects: [
      for (final type in AspectType.values)
        TransitPairAspect(
          firstPlanet: AstroPlanet.values[type.index],
          secondPlanet: AstroPlanet.values[type.index + 1],
          type: type,
          orb: type.index + 0.5,
          phase: AspectPhase.values[type.index % 3],
        ),
    ],
    retrogradePlanets: const {AstroPlanet.mercury},
    houseTransits: const [
      HouseTransit(
        planet: AstroPlanet.venus,
        natalHouse: 7,
        area: FortuneArea.love,
        meaning: '保存用の通過説明',
      ),
    ],
    returns: const [
      PlanetReturnEvent(
        planet: AstroPlanet.jupiter,
        natalHouse: 9,
        status: '接近中',
        orb: 1.2,
        window: 6,
        area: FortuneArea.work,
        meaning: '保存用のリターン説明',
      ),
    ],
    birthPlace: const GeoPoint(label: 'fixture', latitude: 0, longitude: 0),
    ephemerisSourceName: 'Synthetic display fixture',
    ephemerisPrecisionNotice: 'Synthetic display fixture',
    usesHighPrecisionAstroData: false,
    houseSystem: HouseSystem.wholeSign,
    houseCusps: [for (var i = 0; i < 12; i++) i * 30.0],
  );
}

String _renderedText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
    .join('\n');

Future<void> _panel(
  WidgetTester tester,
  HoroscopeReadingContext fixture,
  Size size,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    AppLanguageScope(
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: TodayAstroDataPanel(contextData: fixture),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  late AppLanguage originalLanguage;
  setUp(() {
    originalLanguage = AppLanguageSettings.current.value;
    AppLanguageSettings.current.value = AppLanguage.en;
  });
  tearDown(() => AppLanguageSettings.current.value = originalLanguage);

  test(
    'all twelve Moon signs have distinct JA/EN mood guidance and ingress context',
    () {
      final jaMoods = <String>{};
      final enMoods = <String>{};
      for (final sign in ZodiacSign.values) {
        final canonical = '12:00　月は${sign.label}：気分と行動のペースをここで確認';
        final ingress = '18:37　月が${sign.label}へ：気分の切替';
        final ja = readingMoonMood(sign, AppLanguage.ja);
        final en = readingMoonMood(sign, AppLanguage.en);
        jaMoods.add(ja);
        enMoods.add(en);
        expect(ja, matches(_cjk));
        expect(en, isNot(matches(_cjk)));
        for (final language in AppLanguage.values) {
          final current = readingMoonEventDisplayCopy(canonical, language)!;
          final moved = readingMoonEventDisplayCopy(ingress, language)!;
          final mood = readingMoonMood(sign, language);
          expect(current, contains(mood));
          expect(current, contains('12:00'));
          expect(moved, contains(mood));
          expect(moved, contains('18:37'));
          expect(
            moved,
            contains(language == AppLanguage.en ? 'From this time' : 'ここから'),
          );
          expect(
            current,
            contains(
              language == AppLanguage.en ? _signNames[sign.index] : sign.label,
            ),
          );
          if (language == AppLanguage.en) {
            expect('$current\n$moved', isNot(matches(_cjk)));
          }
        }
      }
      expect(jaMoods, hasLength(12));
      expect(enMoods, hasLength(12));
      expect(
        readingMoonEventDisplayCopy('user text 月は牡羊座', AppLanguage.en),
        isNull,
      );
      expect(
        readingMoonEventDisplayCopy('18:37　月が未知座へ：気分の切替', AppLanguage.en),
        isNull,
      );
    },
  );

  test(
    'known phase, void and configuration event templates are complete English',
    () {
      const events = [
        '11:42〜13:05　月ボイド：大きな決定は急がず確認を',
        '10:24頃　新月：新しいことは小さく始め、意図を一つ決める',
        '10:24頃　上弦の月：育てたいことを一つ行動に移す',
        '10:24頃　満月：結果と気持ちが表れやすいので、振り返りと調整を',
        '10:24頃　下弦の月：手放すことを一つ決め、次の準備をする',
        '12:00　空の牡羊座のステリウム（太陽・月・水星）：そのテーマを一つに絞ると力にしやすい',
      ];
      for (final event in events) {
        final copy = readingSkyAdditionalEventDisplayCopy(
          event,
          AppLanguage.en,
        );
        expect(copy, isNotNull);
        expect(copy, isNot(matches(_cjk)));
        expect(
          readingSkyAdditionalEventDisplayCopy(event, AppLanguage.ja),
          isNull,
        );
      }
      for (final label in [
        'Tスクエア',
        'グランドクロス',
        'ヨッド',
        'ブーメラン（ヨッド）',
        'ミスティックレクタングル（ダイヤモンド）',
        'クレイドル（ゆりかご）',
        'ハンマー・オブ・ソー',
        'グランドセクスタイル',
      ]) {
        final event =
            '12:00　$label（太陽・月・水星）：${FortuneScoreCalculator.rarePatternGuidance(label)}';
        final copy = readingSkyAdditionalEventDisplayCopy(
          event,
          AppLanguage.en,
        );
        expect(copy, isNotNull, reason: label);
        expect(copy, isNot(matches(_cjk)), reason: label);
      }
      expect(
        readingSkyAdditionalEventDisplayCopy(
          'arbitrary private text',
          AppLanguage.en,
        ),
        isNull,
      );
    },
  );

  testWidgets(
    'English phone aspect panel has complete headings, names, orb and meanings',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = _fixture();
      await _panel(tester, fixture, const Size(390, 844));
      final text = _renderedText(tester);
      expect(text, isNot(matches(_cjk)));
      for (final expected in [
        'Major aspects for this date',
        'Aspects between transiting planets',
        'Grand trines',
        'Mercury retrograde',
        'Planet positions for this date',
        'Planetary returns for this date',
        'Jupiter return',
        'Orb 1.2°',
        'conjunction',
        'sextile',
        'square',
        'trine',
        'opposition',
        'Current communication and judgment',
      ]) {
        expect(text, contains(expected));
      }
      expect(tester.takeException(), isNull);
      AppLanguageSettings.current.value = AppLanguage.ja;
      await tester.pump();
      expect(_renderedText(tester), contains('この日の主要アスペクト'));
      expect(fixture.aspects.first.meaning, '保存用の日本語本文は変更しない');
      expect(fixture.returns.first.status, '接近中');
    },
  );

  testWidgets(
    'English full aspect sheet covers placements, returns, houses and patterns',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _panel(tester, _fixture(), const Size(1100, 1000));
      await tester.tap(find.text('Open all aspects'));
      await tester.pumpAndSettle();
      final text = _renderedText(tester);
      expect(text, isNot(matches(_cjk)));
      for (final expected in [
        'All aspect details',
        'Current planet positions',
        'All aspects to the natal chart',
        'All aspects between transiting planets',
        'House transits',
        'Planetary returns',
        'Retrogrades, Moon void, and patterns',
        'Moon void of course: 11:00 - 13:00',
        'Natal stellium: House 1',
        'Midheaven',
        'Pisces',
        'Orb 4.5°',
        '2026-10-21 (Wed)',
      ]) {
        expect(text, contains(expected));
      }
      expect(tester.takeException(), isNull);
    },
  );

  for (final sample in [
    (
      DateTime.utc(2026, 10, 21, 3),
      DateTime(2026, 10, 21, 12),
      '2026-10-21 (Wed) 12:00',
    ),
    (
      DateTime.utc(2026, 10, 31, 15),
      DateTime(2026, 11, 1),
      '2026-11-01 (Sun) 00:00',
    ),
    (
      DateTime.utc(2026, 12, 31, 15, 7, 43),
      DateTime(2027, 1, 1, 0, 7),
      '2027-01-01 (Fri) 00:07',
    ),
  ]) {
    testWidgets(
      'detail date/time and unchanged picker use JST for ${sample.$1.toIso8601String()}',
      (tester) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final fixture = _fixture(instant: sample.$1);
        await _panel(tester, fixture, const Size(390, 900));
        await tester.tap(find.text('Open all aspects'));
        await tester.pumpAndSettle();
        final label = 'Positions: ${sample.$3} JST (UTC+09:00)';
        expect(find.text(label), findsOneWidget);
        final sheetLines = find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(AspectLine),
        );
        final before = tester.widget<AspectLine>(sheetLines.first);
        await tester.tap(find.text('Change date/time'));
        await tester.pumpAndSettle();
        final datePicker = tester.widget<DatePickerDialog>(
          find.byType(DatePickerDialog),
        );
        expect(
          datePicker.initialDate,
          DateTime(sample.$2.year, sample.$2.month, sample.$2.day),
        );
        expect(datePicker.helpText, 'Date for all aspects (JST)');
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        final timePicker = tester.widget<TimePickerDialog>(
          find.byType(TimePickerDialog),
        );
        expect(
          timePicker.initialTime,
          TimeOfDay(hour: sample.$2.hour, minute: sample.$2.minute),
        );
        expect(timePicker.helpText, 'Time for all aspects (JST)');
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        expect(find.text(label), findsOneWidget);
        // An unchanged selection must keep the synthetic source aspects instead
        // of invoking the engine and replacing them, even with source seconds.
        final after = tester.widget<AspectLine>(sheetLines.first);
        expect(after.from, before.from);
        expect(after.to, before.to);
        expect(after.orb, before.orb);
        expect(after.meaning, before.meaning);
        expect(fixture.transit.date, sample.$1);
        expect(fixture.transit.date.isUtc, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
