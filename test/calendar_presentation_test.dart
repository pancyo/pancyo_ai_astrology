import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pancyo_ai_astrology/main.dart';
import 'package:pancyo_ai_astrology/app_language.dart';
import 'package:pancyo_ai_astrology/app_language_settings.dart';

AstrologyCalendarDay fixture(String date, {bool busy = false}) =>
    AstrologyCalendarDay(
      targetDateJst: date,
      moonSignAtNoon: ZodiacSign.taurus,
      providerName: 'FICTIONAL layout fixture',
      precisionNotice: 'Synthetic, not astronomical data',
      usesHighPrecisionAstroData: false,
      events: busy
          ? [
              AstrologyCalendarEvent(
                kind: AstrologyCalendarEventKind.voidMoon,
                title: '月ボイド',
                detail: 'fixture',
                startUtc: DateTime.utc(2026, 10, 17, 14),
                endUtc: DateTime.utc(2026, 10, 17, 17),
                overlapStartUtc: DateTime.utc(2026, 10, 17, 15),
                overlapEndUtc: DateTime.utc(2026, 10, 17, 17),
                continuesFromPreviousDay: true,
              ),
              AstrologyCalendarEvent(
                kind: AstrologyCalendarEventKind.voidMoon,
                title: '月ボイド',
                detail: 'fixture',
                startUtc: DateTime.utc(2026, 10, 18, 11),
                endUtc: DateTime.utc(2026, 10, 18, 18),
                overlapStartUtc: DateTime.utc(2026, 10, 18, 11),
                overlapEndUtc: DateTime.utc(2026, 10, 18, 15),
                continuesIntoNextDay: true,
              ),
              AstrologyCalendarEvent(
                kind: AstrologyCalendarEventKind.signIngress,
                title: '月が牡牛座へ移動',
                detail: 'fixture',
                startUtc: DateTime.utc(2026, 10, 17, 17),
                ingressPlanet: AstroPlanet.moon,
                fromSign: ZodiacSign.aries,
                toSign: ZodiacSign.taurus,
              ),
              AstrologyCalendarEvent(
                kind: AstrologyCalendarEventKind.majorLunarPhase,
                title: '新月',
                detail: 'fixture',
                startUtc: DateTime.utc(2026, 10, 18, 5),
              ),
              for (var i = 0; i < 7; i++)
                AstrologyCalendarEvent(
                  kind: AstrologyCalendarEventKind.specialConfiguration,
                  title: 'グランドトライン（太陽・火星・木星）',
                  detail: 'fixture $i',
                  snapshotUtc: DateTime.utc(2026, 10, 18, 3),
                ),
            ]
          : [],
    );

class DoneDay implements AstrologyCalendarOperation {
  DoneDay(this.day);
  final AstrologyCalendarDay day;
  @override
  Future<AstrologyCalendarDay> get result => Future.value(day);
  @override
  void cancel() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = File(r'C:\Windows\Fonts\meiryo.ttc');
    if (font.existsSync()) {
      await (FontLoader('CalendarNameWrapTest')..addFont(
        font.readAsBytes().then(ByteData.sublistView))).load();
    }
  });
  test(
    'mandatory intervals remain separate, ingress has both signs, supplements prioritized',
    () {
      final value = AstrologyCalendarDayPresentation.fromDay(
        fixture('2026-10-18', busy: true),
        english: false,
      );
      expect(value.voidLines, ['前日〜02:00', '20:00〜翌日']);
      expect(value.moonLines.single, '月：牡羊座 → 牡牛座 02:00');
      expect(value.supplementalEvents.length, 8);
      expect(value.supplementalEvents.first.title, '新月');
      expect(
        astrologyCalendarSupplementLabel(
          value.supplementalEvents.last,
          english: false,
        ),
        contains('太陽・火星・木星'),
      );
    },
  );
  test(
    'full-day and exact next midnight are clear; no ingress still shows Moon sign',
    () {
      final e = AstrologyCalendarEvent(
        kind: AstrologyCalendarEventKind.voidMoon,
        title: '月ボイド',
        detail: 'fixture',
        startUtc: DateTime.utc(2026, 10, 16),
        endUtc: DateTime.utc(2026, 10, 19),
      );
      expect(astrologyCalendarVoidLabel(e, '2026-10-18', english: false), '終日');
      final midnight = AstrologyCalendarEvent(
        kind: e.kind,
        title: e.title,
        detail: e.detail,
        startUtc: DateTime.utc(2026, 10, 18, 11),
        endUtc: DateTime.utc(2026, 10, 18, 15),
      );
      expect(
        astrologyCalendarVoidLabel(midnight, '2026-10-18', english: false),
        '20:00〜24:00',
      );
      expect(
        AstrologyCalendarDayPresentation.fromDay(
          fixture('2026-10-18'),
          english: false,
        ).moonLines,
        ['月：牡牛座'],
      );
    },
  );
  for (final size in [const Size(390, 844), const Size(1280, 800)]) {
    for (final english in [false, true]) {
      testWidgets(
        'calendar ${size.width} ${english ? 'EN' : 'JA'} large text and all mandatory lines',
        (t) async {
          t.view.physicalSize = size;
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          AppLanguageSettings.current.value = english
              ? AppLanguage.en
              : AppLanguage.ja;
          await t.pumpWidget(
            MaterialApp(
              theme: ThemeData.dark(),
              home: AppLanguageScope(
                child: MediaQuery(
                  data: MediaQueryData(
                    size: size,
                    textScaler: TextScaler.linear(1.3),
                  ),
                  child: AstrologyCalendarView(
                    initialDate: DateTime.utc(2026, 10, 18),
                    initialShowAgenda: false,
                    cacheIdentity: 'fixture-${size.width}-$english',
                    startJob: (date, p) =>
                        DoneDay(fixture(date, busy: date == '2026-10-18')),
                  ),
                ),
              ),
            ),
          );
          await t.pumpAndSettle();
          final cell = find.byKey(
            const ValueKey('astrology-calendar-day-2026-10-18'),
          );
          if (size.width < 600) {
            // The phone's readable scrolling presentation remains unchanged.
            expect(
              find.descendant(
                of: cell,
                matching: find.text(english ? 'Void-of-course' : 'ボイド'),
              ),
              findsOneWidget,
            );
            expect(
              find.descendant(
                of: cell,
                matching: find.text(
                  english ? 'Previous day–02:00' : '前日〜02:00',
                ),
              ),
              findsOneWidget,
            );
            expect(
              find.descendant(
                of: cell,
                matching: find.text(english ? '20:00–Next day' : '20:00〜翌日'),
              ),
              findsOneWidget,
            );
          } else {
            // Tablet rows include the heading and interval together. Validate
            // the rendered content plus the complete accessibility description.
            final visible = find
                .descendant(of: cell, matching: find.byType(RichText))
                .evaluate()
                .map(
                  (element) => (element.widget as RichText).text.toPlainText(),
                )
                .join('\n');
            if (english) {
              // Narrow layouts keep each sign intact on a separate line.
              expect(visible, contains('Moon:'));
              expect(visible, contains('Ari→Tau'));
            } else {
              expect(visible, contains('月:'));
              expect(visible, contains('牡羊座'));
              expect(visible, contains('牡牛座'));
              expect(visible, contains('→'));
            }
            expect(visible, contains('02:00'));
            expect(
              visible,
              contains(english ? 'Void prev day–02:00' : 'ボイド 前日〜02:00'),
            );
            expect(
              visible,
              contains(english ? 'Void 20:00–next day' : 'ボイド 20:00〜翌日'),
            );
            final fullLabels = find
                .descendant(of: cell, matching: find.byType(Semantics))
                .evaluate()
                .map(
                  (element) =>
                      (element.widget as Semantics).properties.label ?? '',
                )
                .join('\n');
            expect(
              fullLabels,
              contains(
                english ? 'Moon：Aries → Taurus 02:00' : '月：牡羊座 → 牡牛座 02:00',
              ),
            );
            expect(
              fullLabels,
              contains(english ? 'Previous day–02:00' : '前日〜02:00'),
            );
            expect(
              fullLabels,
              contains(english ? '20:00–Next day' : '20:00〜翌日'),
            );
          }
          expect(
            find.textContaining(english ? 'not loaded' : '未取得'),
            findsWidgets,
          );
          expect(t.takeException(), isNull);
          await t.ensureVisible(find.byTooltip(english ? 'Next month' : '翌月'));
          await t.tap(find.byTooltip(english ? 'Next month' : '翌月'));
          await t.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('astrology-calendar-day-2026-11-30')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('astrology-calendar-day-2026-10-31')),
            findsNothing,
          );
          expect(t.takeException(), isNull);
        },
      );
    }
  }
  testWidgets('failed acquisition stays failed, never no void', (t) async {
    AppLanguageSettings.current.value = AppLanguage.ja;
    await t.pumpWidget(
      MaterialApp(
        home: AppLanguageScope(
          child: AstrologyCalendarView(
            initialDate: DateTime.utc(2026, 10, 1),
            initialShowAgenda: false,
            cacheIdentity: 'failed-fixture',
            startJob: (_, __) => throw StateError('fixture failure'),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    final cell = find.byKey(
      const ValueKey('astrology-calendar-day-2026-10-01'),
    );
    expect(
      find.descendant(of: cell, matching: find.textContaining('月・ボイド：取得失敗・再試行')),
      findsOneWidget,
    );
    expect(find.descendant(of: cell, matching: find.text('なし')), findsNothing);
  });

  testWidgets('day content accepts a screen font size and keeps export default 14', (tester) async {
    for (final fontSize in [null, 17.0, 19.0]) {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(width: 600,
        child: fontSize == null
          ? AstrologyCalendarDayContent(data: fixture('2026-10-18'), english: false)
          : AstrologyCalendarDayContent(data: fixture('2026-10-18'), english: false, fontSize: fontSize),
      ))));
      final textWidgets = find.descendant(of: find.byType(AstrologyCalendarDayContent), matching: find.byType(Text));
      expect(textWidgets, findsNWidgets(3));
      for (final element in textWidgets.evaluate()) {
        expect((element.widget as Text).style?.fontSize, fontSize ?? 14.0);
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('enlarged Japanese sign names stay whole and use the measured height', (tester) async {
    final source = fixture('2026-10-18', busy: true);
    for (final width in [89.78, 153.08]) {
      for (final fontSize in [17.0, 19.0]) {
        for (final scale in [1.0, 1.3]) {
          for (var index = 0; index < ZodiacSign.values.length; index++) {
            for (final moving in [false, true]) {
              final before = ZodiacSign.values[index];
              final after = ZodiacSign.values[(index + 1) % ZodiacSign.values.length];
              final data = AstrologyCalendarDay(
                targetDateJst: source.targetDateJst,
                moonSignAtNoon: moving ? after : before,
                providerName: source.providerName,
                precisionNotice: source.precisionNotice,
                usesHighPrecisionAstroData: false,
                events: [
                  ...source.events.where((event) => event.kind == AstrologyCalendarEventKind.voidMoon),
                  if (moving) AstrologyCalendarEvent(
                    kind: AstrologyCalendarEventKind.signIngress,
                    title: '月が${after.label}へ移動', detail: 'Synthetic display fixture',
                    startUtc: DateTime.utc(2026,10,17,17),
                    ingressPlanet: AstroPlanet.moon, fromSign: before, toSign: after,
                  ),
                ],
              );
              const base = TextStyle(fontFamily: 'CalendarNameWrapTest');
              final measured = astrologyCalendarCompactRequiredHeight(
                data: data, english: false, width: width,
                textScaler: TextScaler.linear(scale), dayNumber: 18,
                fontSize: fontSize, textStyle: base,
              );
              await tester.pumpWidget(MaterialApp(home: Scaffold(body: Align(
                alignment: Alignment.topLeft,
                child: MediaQuery(data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: DefaultTextStyle(style: base, child: SizedBox(width: width,
                    child: AstrologyCalendarCompactDayContent(
                      key: const ValueKey('ja-name-wrap'), data: data, english: false,
                      dayNumber: 18, fontSize: fontSize, maxHeight: measured, supplementalLimit: 0,
                    ),
                  )),
                ),
              ))));
              await tester.pump();
              final content = find.byKey(const ValueKey('ja-name-wrap'));
              final paragraphs = find.descendant(of: content, matching: find.byType(RichText));
              final text = paragraphs.evaluate().map((element) =>
                (element.widget as RichText).text.toPlainText()).join('\n');
              for (final sign in {before, if (moving) after}) {
                var found = false;
                for (final element in paragraphs.evaluate()) {
                  final widget = element.widget as RichText;
                  final position = widget.text.toPlainText().indexOf(sign.label);
                  if (position < 0) continue;
                  found = true;
                  final paragraph = element.findRenderObject()! as RenderParagraph;
                  final boxes = paragraph.getBoxesForSelection(TextSelection(
                    baseOffset: position, extentOffset: position + sign.label.length));
                  expect(boxes, hasLength(1), reason:
                    '${sign.label} must not split at width=$width font=$fontSize scale=$scale: $text');
                  expect(boxes.single.left, greaterThanOrEqualTo(-.1));
                  expect(boxes.single.right, lessThanOrEqualTo(width + .1));
                  var matchingSpans = 0;
                  void verifyFont(InlineSpan span, TextStyle inherited) {
                    final effective = inherited.merge(span.style);
                    if (span is TextSpan) {
                      if (span.text?.contains(sign.label) ?? false) {
                        matchingSpans++;
                        expect(effective.fontSize, fontSize);
                      }
                      for (final child in span.children ?? <InlineSpan>[]) {
                        verifyFont(child, effective);
                      }
                    }
                  }
                  verifyFont(widget.text, const TextStyle());
                  expect(matchingSpans, greaterThan(0));
                  expect(paragraph.textScaler.scale(fontSize), closeTo(fontSize * scale, .01));
                }
                expect(found, isTrue, reason: 'Required sign ${sign.label} missing: $text');
              }
              expect(text, contains('ボイド 前日〜02:00'));
              expect(text, contains('ボイド 20:00〜翌日'));
              if (moving) expect(text, contains('→'));
              expect(tester.getSize(content).height, lessThanOrEqualTo(measured + .1));
              expect(tester.takeException(), isNull);
            }
          }
        }
      }
    }
  });
}
