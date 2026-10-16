import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pancyo_ai_astrology/app_language.dart';
import 'package:pancyo_ai_astrology/app_language_settings.dart';
import 'package:pancyo_ai_astrology/english_ui_catalog.dart';
import 'package:pancyo_ai_astrology/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _suffix = 'が目立つ出生図です。星が集まるテーマを一点集中で磨くほど、人生の軸になります。';
const _screenshot = '第9ハウス集中: 太陽・木星・土星 / 第10ハウス集中: 水星・冥王星・MC$_suffix';
const _profile = AstroProfile(
  name: '架空検査_NAMEそのまま',
  birthDate: '1990/1/2',
  birthTime: '12:00',
  birthPlace: '札幌市',
  theme: '仕事',
);
final _japanese = RegExp(r'[\u3040-\u30ff\u3400-\u9fff]');

void _expectGroups(String translated, List<List<String>> groups) {
  expect(_japanese.hasMatch(translated), isFalse, reason: translated);
  expect(RegExp(r'\bHouse \d+\b').allMatches(translated).length, groups.length);
  var cursor = 0;
  for (final group in groups) {
    for (final token in group) {
      final match = RegExp(
        '\\b${RegExp.escape(token)}\\b',
      ).firstMatch(translated.substring(cursor));
      expect(
        match,
        isNotNull,
        reason: '$token missing or out of order: $translated',
      );
      cursor += match!.end;
    }
  }
}

HoroscopeReadingContext _contextWithScreenshotStelliums() {
  final preview = const AstrologyEngine().buildPreviewContext(
    profile: _profile,
    date: DateTime.utc(2026, 10, 10, 3),
  );
  return HoroscopeReadingContext(
    natal: NatalChart(
      profile: preview.natal.profile,
      placements: preview.natal.placements,
      stelliums: const [
        HouseEmphasis(
          house: 9,
          planets: [AstroPlanet.sun, AstroPlanet.jupiter, AstroPlanet.saturn],
          theme: '架空の検査用テーマ9',
        ),
        HouseEmphasis(
          house: 10,
          planets: [
            AstroPlanet.mercury,
            AstroPlanet.pluto,
            AstroPlanet.midheaven,
          ],
          theme: '架空の検査用テーマ10',
        ),
      ],
      retrogradePlanets: preview.natal.retrogradePlanets,
    ),
    transit: preview.transit,
    nextTransitPlacements: preview.nextTransitPlacements,
    aspects: preview.aspects,
    fullAspects: preview.fullAspects,
    nextAspects: preview.nextAspects,
    transitPairAspects: preview.transitPairAspects,
    retrogradePlanets: preview.retrogradePlanets,
    houseTransits: preview.houseTransits,
    returns: preview.returns,
    birthPlace: preview.birthPlace,
    ephemerisSourceName: preview.ephemerisSourceName,
    ephemerisPrecisionNotice: preview.ephemerisPrecisionNotice,
    usesHighPrecisionAstroData: preview.usesHighPrecisionAstroData,
    houseSystem: preview.houseSystem,
    houseCusps: preview.houseCusps,
    scoreDayStartUtc: preview.scoreDayStartUtc,
  );
}

List<String> _panelText(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byType(NatalProfilePanel),
        matching: find.byType(Text),
      ),
    )
    .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
    .where((text) => text.isNotEmpty)
    .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'screenshot with two natal house concentrations translates completely',
    () {
      final translated = englishUiText(_screenshot);
      _expectGroups(translated, [
        ['House 9', 'Sun', 'Jupiter', 'Saturn'],
        ['House 10', 'Mercury', 'Pluto', 'Midheaven'],
      ]);
      expect(translated, contains('Focusing deeply on the shared theme'));
    },
  );

  test(
    'three concentrations preserve source order, edge houses and ASC/MC',
    () {
      const source =
          '第12ハウス集中: 海王星・冥王星・月 / 第1ハウス集中: 太陽・火星・ASC / '
          '第10ハウス集中: 水星・金星・MC$_suffix';
      _expectGroups(englishUiText(source), [
        ['House 12', 'Neptune', 'Pluto', 'Moon'],
        ['House 1', 'Sun', 'Mars', 'Ascendant'],
        ['House 10', 'Mercury', 'Venus', 'Midheaven'],
      ]);
    },
  );

  test(
    'invalid later concentration leaves the entire generated text unchanged',
    () {
      for (final second in [
        '第0ハウス集中: 水星・冥王星・MC',
        '第13ハウス集中: 水星・冥王星・MC',
        '第999999999999999999999999999999ハウス集中: 水星・冥王星・MC',
        '第10ハウス集中: 水星・架空星・MC',
        '第10ハウス集中: 水星・MC',
        '第10ハウス集中: 水星・冥王星・',
        '水星 天秤座・第10ハウス',
        '',
      ]) {
        final source = '第9ハウス集中: 太陽・木星・土星 / $second$_suffix';
        expect(englishUiText(source), source, reason: second);
      }
      const customProse = '第9ハウス集中: 太陽・木星・土星 / 第10ハウス集中: 水星・冥王星・MC本人の自由文';
      expect(englishUiText(customProse), customProse);
    },
  );

  test(
    'existing single-house and paired-position translations stay identical',
    () {
      expect(
        englishUiText('第9ハウス集中: 太陽・水星・土星・天王星・海王星$_suffix'),
        'A stellium in House 9 stands out in your birth chart: Sun, Mercury, Saturn, Uranus, Neptune. Focusing deeply on the shared theme may help it become a guiding part of your life.',
      );
      expect(
        englishUiText('太陽 山羊座・第9ハウス / ASC 牡牛座・第1ハウス'),
        'Sun in Capricorn, House 9 / Ascendant in Taurus, House 1',
      );
      const invalidPosition = '太陽 山羊座・第9ハウス / 架空星 牡牛座・第1ハウス';
      expect(englishUiText(invalidPosition), invalidPosition);
    },
  );

  test('kite and no-concentration natal theme alternatives also translate', () {
    const alternatives = {
      'グランドトラインを土台にしたカイトがあり、得意なことを外へ向けて動かすほど、才能が実用的な成果につながりやすい出生図です。':
          'Your birth chart has a kite built on a grand trine. Putting your strengths into action in the world may help turn your talents into practical results.',
      '一つだけの型に決めつけず、経験しながら自分に合う役割を選び直せる出生図です。大事な時ほど、得意・疲れにくさ・続けられるかの三つで選ぶとぶれにくくなります。':
          'Your birth chart leaves room to explore different roles and choose what suits you through experience. For important decisions, consider your strengths, what feels less draining, and what you can sustain.',
    };
    for (final entry in alternatives.entries) {
      expect(englishUiText(entry.key), entry.value);
      expect(_japanese.hasMatch(englishUiText(entry.key)), isFalse);
    }
  });

  testWidgets(
    'actual natal panel switches JA to EN to JA with all themes and raw name',
    (tester) async {
      final originalLanguage = AppLanguageSettings.current.value;
      SharedPreferences.setMockInitialValues({'unrelated': 'PRIVATE_KEEP'});
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() {
        AppLanguageSettings.current.value = originalLanguage;
        SharedPreferences.setMockInitialValues({});
      });
      AppLanguageSettings.current.value = AppLanguage.ja;
      final data = _contextWithScreenshotStelliums();
      final natal = data.natal;
      final labels = natal.stelliums.map((item) => item.label).toList();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: AppLanguageScope(
            child: Scaffold(
              body: SingleChildScrollView(
                child: NatalProfilePanel(contextData: data, profile: _profile),
              ),
            ),
          ),
        ),
      );
      final japaneseBefore = _panelText(tester);
      expect(japaneseBefore, contains(_screenshot));
      expect(
        japaneseBefore.any((text) => text.contains('${_profile.name}さん')),
        isTrue,
      );

      AppLanguageSettings.current.value = AppLanguage.en;
      await tester.pumpAndSettle();
      final english = _panelText(tester);
      expect(english, contains('Prominent natal themes'));
      expect(
        english.any((text) => text.startsWith('${_profile.name}:')),
        isTrue,
      );
      expect(
        english
            .map((text) => text.replaceAll(_profile.name, ''))
            .where(_japanese.hasMatch),
        isEmpty,
        reason: english.join('\n'),
      );
      final theme = english.singleWhere(
        (text) => text.startsWith('Stelliums stand out'),
      );
      _expectGroups(theme, [
        ['House 9', 'Sun', 'Jupiter', 'Saturn'],
        ['House 10', 'Mercury', 'Pluto', 'Midheaven'],
      ]);
      expect(
        tester
            .widget<NatalProfilePanel>(find.byType(NatalProfilePanel))
            .contextData,
        same(data),
      );
      expect(data.natal, same(natal));
      expect(data.natal.stelliums.map((item) => item.label), labels);

      AppLanguageSettings.current.value = AppLanguage.ja;
      await tester.pumpAndSettle();
      expect(_panelText(tester), japaneseBefore);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), {'unrelated'});
      expect(prefs.getString('unrelated'), 'PRIVATE_KEEP');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
