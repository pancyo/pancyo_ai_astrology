import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pancyo_ai_astrology/app_language.dart';
import 'package:pancyo_ai_astrology/app_language_settings.dart';
import 'package:pancyo_ai_astrology/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Synthetic sky-only fixtures. No real profile, diary, ephemeris or device data.
const _unrelatedPreferences = <String, Object>{
  'calendar_size_qa_keep_string': 'keep synthetic marker',
  'calendar_size_qa_keep_bool': true,
  'calendar_size_qa_keep_int': 42,
  'calendar_size_qa_keep_list': <String>['synthetic-a', 'synthetic-b'],
};

class _TextSizeReadyDay implements AstrologyCalendarOperation {
  _TextSizeReadyDay(this.date);
  final String date;

  @override
  Future<AstrologyCalendarDay> get result async => AstrologyCalendarDay(
    targetDateJst: date,
    events: const [],
    moonSignAtNoon: ZodiacSign.taurus,
    providerName: 'SYNTHETIC TEXT SIZE TEST',
    precisionNotice: 'Synthetic UI fixture; not astronomical observations.',
    usesHighPrecisionAstroData: false,
  );

  @override
  void cancel() {}
}

Finder _key(String name) => find.byKey(ValueKey(name));

Future<void> _pumpCalendar(
  WidgetTester tester, {
  required List<String> calls,
  required String identity,
  Size size = const Size(1181.54, 738.46),
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: AppLanguageScope(
        child: MediaQuery(
          data: MediaQueryData(
            size: size,
            padding: const EdgeInsets.only(top: 24, bottom: 48),
            viewPadding: const EdgeInsets.only(top: 24, bottom: 48),
            textScaler: TextScaler.linear(scale),
          ),
          child: AstrologyCalendarView(
            initialDate: DateTime.utc(2026, 11, 18),
            initialShowAgenda: false,
            cacheIdentity: identity,
            startJob: (date, progress) {
              calls.add(date);
              return _TextSizeReadyDay(date);
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _openSizeDialog(WidgetTester tester) async {
  final button = _key('astrology-calendar-text-size-button');
  expect(button, findsOneWidget);
  await tester.tap(button);
  await tester.pumpAndSettle();
  expect(_key('astrology-calendar-text-size-dialog'), findsOneWidget);
}

void _expectSelected(WidgetTester tester, double size) {
  for (final choice in [15, 17, 19]) {
    final radio = tester.widget<RadioListTile<dynamic>>(
      _key('astrology-calendar-text-size-option-$choice'),
    );
    expect(radio.value, choice.toDouble());
    expect(radio.groupValue, size);
  }
}

Future<void> _expectPreferences({double? selected}) async {
  final prefs = await SharedPreferences.getInstance();
  final expected = <String, Object>{
    ..._unrelatedPreferences,
    if (selected != null) AstrologyCalendarTextSettings.storageKey: selected,
  };
  expect(prefs.getKeys(), expected.keys.toSet());
  for (final entry in expected.entries) {
    expect(prefs.get(entry.key), entry.value, reason: entry.key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppLanguage oldLanguage;

  setUp(() {
    SharedPreferences.setMockInitialValues(_unrelatedPreferences);
    oldLanguage = AppLanguageSettings.current.value;
    AppLanguageSettings.current.value = AppLanguage.ja;
  });

  tearDown(() {
    AppLanguageSettings.current.value = oldLanguage;
    SharedPreferences.setMockInitialValues({});
  });

  test('text-size defaults to 17 without modifying unrelated preferences', () async {
    expect(AstrologyCalendarTextSettings.storageKey, 'astrology.calendar_text_size');
    expect(AstrologyCalendarTextSettings.defaultSize, 17.0);
    expect(AstrologyCalendarTextSettings.sizes, [15.0, 17.0, 19.0]);
    expect(await AstrologyCalendarTextSettings.restore(), 17.0);
    await _expectPreferences();
  });

  test('all three supported sizes persist and restore with other preferences intact', () async {
    for (final size in [15.0, 17.0, 19.0]) {
      await AstrologyCalendarTextSettings.save(size);
      expect(await AstrologyCalendarTextSettings.restore(), size);
      await _expectPreferences(selected: size);
    }
  });

  test('unsupported stored size falls back without rewriting and rejects invalid save', () async {
    SharedPreferences.setMockInitialValues({
      ..._unrelatedPreferences,
      AstrologyCalendarTextSettings.storageKey: 'invalid synthetic value',
    });
    expect(await AstrologyCalendarTextSettings.restore(), 17.0);
    await expectLater(AstrologyCalendarTextSettings.save(9), throwsArgumentError);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.get(AstrologyCalendarTextSettings.storageKey), 'invalid synthetic value');
    for (final entry in _unrelatedPreferences.entries) {
      expect(prefs.get(entry.key), entry.value);
    }
  });

  testWidgets('large chosen text is retained with an explicit scroll fallback and final date reachable', (tester) async {
    SharedPreferences.setMockInitialValues({
      ..._unrelatedPreferences,
      AstrologyCalendarTextSettings.storageKey: 19.0,
    });
    final calls = <String>[];
    await _pumpCalendar(tester, calls: calls, identity: 'text-size-overflow',
      size: const Size(600, 600), scale: 1.3);
    await tester.tap(_key('astrology-calendar-month-load'));
    await tester.pumpAndSettle();
    expect(calls.toSet().length, 30);
    expect(_key('astrology-calendar-text-size-overflow-notice'), findsOneWidget);
    expect(_key('astrology-calendar-accessibility-overflow'), findsOneWidget);
    for (final cell in tester.widgetList<AstrologyCalendarCompactDayContent>(find.byType(AstrologyCalendarCompactDayContent))) {
      expect(cell.fontSize, 19.0, reason: 'Never shrink the chosen font to fit.');
    }
    final finalDate = _key('astrology-calendar-day-2026-11-30');
    await tester.ensureVisible(finalDate);
    await tester.pumpAndSettle();
    expect(tester.getRect(finalDate).bottom, lessThanOrEqualTo(600 - 48));
    expect(tester.takeException(), isNull);
    expect(await AstrologyCalendarTextSettings.restore(), 19.0);
  });

  testWidgets('apply 15, 17 and 19 changes only display settings without new sky jobs', (tester) async {
    final calls = <String>[];
    await _pumpCalendar(tester, calls: calls, identity: 'text-size-apply-three');
    expect(calls, ['2026-11-18']);
    var previous = 17.0;
    for (final size in [15.0, 17.0, 19.0]) {
      await _openSizeDialog(tester);
      _expectSelected(tester, previous);
      await tester.tap(_key('astrology-calendar-text-size-option-${size.toInt()}'));
      await tester.pumpAndSettle();
      _expectSelected(tester, size);
      expect(calls, ['2026-11-18'], reason: 'Selecting a radio must not recalculate.');
      await tester.tap(_key('astrology-calendar-text-size-apply'));
      await tester.pumpAndSettle();
      expect(_key('astrology-calendar-text-size-dialog'), findsNothing);
      expect(await AstrologyCalendarTextSettings.restore(), size);
      await _expectPreferences(selected: size);
      expect(calls, ['2026-11-18'], reason: 'Applying text size must not start a new sky job.');
      expect(tester.takeException(), isNull);
      previous = size;
    }
  });

  testWidgets('phone Japanese and English retain 19 and accessible text-size controls', (tester) async {
    SharedPreferences.setMockInitialValues({AstrologyCalendarTextSettings.storageKey: 19.0});
    for (final language in [AppLanguage.ja, AppLanguage.en]) {
      AppLanguageSettings.current.value = language;
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpCalendar(tester, calls: [], identity: 'phone-text-$language',
        size: const Size(390, 844), scale: 1.3);
      expect(_key('astrology-calendar-grid-scroll'), findsOneWidget);
      final content = tester.widget<AstrologyCalendarDayContent>(find.descendant(
        of: _key('astrology-calendar-day-2026-11-18'),
        matching: find.byType(AstrologyCalendarDayContent),
      ));
      expect(content.fontSize, 19);
      await _openSizeDialog(tester);
      _expectSelected(tester, 19);
      await tester.ensureVisible(_key('astrology-calendar-text-size-cancel'));
      await tester.tap(_key('astrology-calendar-text-size-cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('cancel leaves default unpersisted and preserves the applied value after restore', (tester) async {
    final calls = <String>[];
    await _pumpCalendar(tester, calls: calls, identity: 'text-size-cancel-default');
    await _openSizeDialog(tester);
    _expectSelected(tester, 17.0);
    await tester.tap(_key('astrology-calendar-text-size-option-19'));
    await tester.pumpAndSettle();
    _expectSelected(tester, 19.0);
    await tester.tap(_key('astrology-calendar-text-size-cancel'));
    await tester.pumpAndSettle();
    await _expectPreferences();
    expect(await AstrologyCalendarTextSettings.restore(), 17.0);
    expect(calls, ['2026-11-18']);

    await _openSizeDialog(tester);
    _expectSelected(tester, 17.0);
    await tester.tap(_key('astrology-calendar-text-size-option-19'));
    await tester.pumpAndSettle();
    await tester.tap(_key('astrology-calendar-text-size-apply'));
    await tester.pumpAndSettle();
    await _expectPreferences(selected: 19.0);
    expect(calls, ['2026-11-18']);

    // Remount a new calendar to exercise restoration rather than dialog state.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    final reopenedCalls = <String>[];
    await _pumpCalendar(tester, calls: reopenedCalls, identity: 'text-size-restore-new-view');
    await _openSizeDialog(tester);
    _expectSelected(tester, 19.0);
    await tester.tap(_key('astrology-calendar-text-size-option-15'));
    await tester.pumpAndSettle();
    _expectSelected(tester, 15.0);
    await tester.tap(_key('astrology-calendar-text-size-cancel'));
    await tester.pumpAndSettle();
    await _expectPreferences(selected: 19.0);
    await _openSizeDialog(tester);
    _expectSelected(tester, 19.0);
    await tester.tap(_key('astrology-calendar-text-size-cancel'));
    await tester.pumpAndSettle();
    expect(reopenedCalls, ['2026-11-18'], reason: 'Cancel/reopen must reuse the existing sky data.');
    expect(tester.takeException(), isNull);
  });
}
