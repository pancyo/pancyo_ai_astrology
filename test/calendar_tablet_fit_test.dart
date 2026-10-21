import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pancyo_ai_astrology/app_language.dart';
import 'package:pancyo_ai_astrology/app_language_settings.dart';
import 'package:pancyo_ai_astrology/daily_seven_timepoint_plan.dart';
import 'package:pancyo_ai_astrology/main.dart';

// These are explicitly synthetic layout/boundary fixtures. Dates and UTC
// endpoints are internally consistent; they are not real astronomical events.
AstrologyCalendarDay tabletFixture(String date, {bool busy = false}) {
  final plan = DailySevenTimepointPlan.forJstDate(date);
  DateTime at(int hour) => plan.dayStartUtc.add(Duration(hours: hour));
  AstrologyCalendarEvent interval(int startHour, int endHour) =>
      AstrologyCalendarEvent(
        kind: AstrologyCalendarEventKind.voidMoon,
        title: '月ボイド',
        detail: 'SYNTHETIC void interval',
        startUtc: at(startHour),
        endUtc: at(endHour),
        overlapStartUtc: startHour < 0 ? at(0) : at(startHour),
        overlapEndUtc: endHour > 24 ? at(24) : at(endHour),
        continuesFromPreviousDay: startHour < 0,
        continuesIntoNextDay: endHour > 24,
      );
  return AstrologyCalendarDay(
    targetDateJst: date,
    moonSignAtNoon: ZodiacSign.taurus,
    providerName: 'SYNTHETIC tablet layout fixture',
    precisionNotice: 'Synthetic data, not actual astronomical calculation.',
    usesHighPrecisionAstroData: false,
    events: [
      if (date.endsWith('-09')) interval(-2, 26),
      if (busy) ...[
        interval(-2, 2),
        interval(20, 28),
        AstrologyCalendarEvent(
          kind: AstrologyCalendarEventKind.signIngress,
          title: '月が牡牛座へ移動',
          detail: '星座の移動',
          startUtc: at(2),
          ingressPlanet: AstroPlanet.moon,
          fromSign: ZodiacSign.aries,
          toSign: ZodiacSign.taurus,
        ),
        AstrologyCalendarEvent(
          kind: AstrologyCalendarEventKind.majorLunarPhase,
          title: '新月',
          detail: 'SYNTHETIC phase',
          startUtc: at(14),
        ),
        for (var index = 0; index < 8; index++)
          AstrologyCalendarEvent(
            kind: AstrologyCalendarEventKind.specialConfiguration,
            title: 'グランドトライン（太陽・火星・木星）',
            detail: 'SYNTHETIC supplement $index',
            snapshotUtc: plan.primaryNoon.instantUtc,
          ),
      ],
    ],
  );
}

class TabletDoneDay implements AstrologyCalendarOperation {
  TabletDoneDay(this.day);
  final AstrologyCalendarDay day;
  @override
  Future<AstrologyCalendarDay> get result => Future.value(day);
  @override
  void cancel() {}
}

const tabletLandscape = Size(1181.54, 738.46);
const tabletPortrait = Size(738.46, 1181.54);
const tabletInsets = EdgeInsets.only(top: 24, bottom: 48);

String dateKey(int month, int day) =>
    '2026-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

Finder cellFor(String date) =>
    find.byKey(ValueKey('astrology-calendar-day-$date'));

String visibleCellText(Finder cell) => find
    .descendant(of: cell, matching: find.byType(RichText))
    .evaluate()
    .map((element) => (element.widget as RichText).text.toPlainText())
    .join('\n');

void within(Rect inner, Rect outer, {required String reason}) {
  const epsilon = .6;
  expect(
    inner.left,
    greaterThanOrEqualTo(outer.left - epsilon),
    reason: reason,
  );
  expect(inner.top, greaterThanOrEqualTo(outer.top - epsilon), reason: reason);
  expect(inner.right, lessThanOrEqualTo(outer.right + epsilon), reason: reason);
  expect(
    inner.bottom,
    lessThanOrEqualTo(outer.bottom + epsilon),
    reason: reason,
  );
}

Future<void> pumpTablet(
  WidgetTester tester, {
  required Size size,
  required int month,
  required bool english,
  required double scale,
  String? failDate,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final languageBefore = AppLanguageSettings.current.value;
  addTearDown(() => AppLanguageSettings.current.value = languageBefore);
  AppLanguageSettings.current.value = english ? AppLanguage.en : AppLanguage.ja;
  final theme = ThemeData.dark();
  await tester.pumpWidget(
    MaterialApp(
      theme: theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: 'TabletFitTest'),
      ),
      home: AppLanguageScope(
        child: MediaQuery(
          data: MediaQueryData(
            size: size,
            padding: tabletInsets,
            viewPadding: tabletInsets,
            textScaler: TextScaler.linear(scale),
          ),
          child: AstrologyCalendarView(
            initialDate: DateTime.utc(2026, month, 18),
            initialShowAgenda: false,
            cacheIdentity: 'tablet-r2-$size-$month-$english-$scale-$failDate',
            startJob: (date, progress) {
              if (date == failDate) throw StateError('SYNTHETIC fetch failure');
              return TabletDoneDay(
                tabletFixture(date, busy: date.endsWith('-18')),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // Real font metrics are necessary for a useful tablet fit test. This only
    // affects the test process, never the application's packaged fonts.
    final font = File(r'C:\Windows\Fonts\meiryo.ttc');
    if (await font.exists()) {
      await (FontLoader(
        'TabletFitTest',
      )..addFont(font.readAsBytes().then(ByteData.sublistView))).load();
    }
  });

  for (final size in [tabletLandscape, tabletPortrait]) {
    for (final month in [10, 11]) {
      for (final english in [false, true]) {
        for (final scale in [1.0, 1.3]) {
          testWidgets(
            'T65Max ${size.width}x${size.height} month=$month ${english ? 'EN' : 'JA'} scale=$scale fits every day and mandatory line',
            (tester) async {
              await pumpTablet(
                tester,
                size: size,
                month: month,
                english: english,
                scale: scale,
              );
              await tester.tap(
                find.byKey(const ValueKey('astrology-calendar-month-load')),
              );
              await tester.pumpAndSettle();
              final fitted = find.byKey(
                const ValueKey('astrology-calendar-fitted-month'),
              );
              expect(fitted, findsOneWidget);
              final screen = Rect.fromLTWH(
                0,
                tabletInsets.top,
                size.width,
                size.height - tabletInsets.vertical,
              );
              within(
                tester.getRect(fitted),
                screen,
                reason: 'Fitted calendar must stay inside the usable screen.',
              );
              final days = DateTime.utc(2026, month + 1, 0).day;
              final dayRects = <Rect>[];
              for (var day = 1; day <= days; day++) {
                final date = dateKey(month, day);
                final cell = cellFor(date);
                expect(cell, findsOneWidget, reason: date);
                final rect = tester.getRect(cell);
                dayRects.add(rect);
                within(
                  rect,
                  screen,
                  reason: '$date must be visible without scrolling.',
                );
                expect(
                  cell.hitTestable(),
                  findsOneWidget,
                  reason: '$date must be tappable in the viewport.',
                );
                final text = visibleCellText(cell);
                expect(
                  text,
                  contains(english ? 'Moon' : '月'),
                  reason: '$date always has a Moon sign.',
                );
                expect(
                  text,
                  contains(english ? 'Void' : 'ボイド'),
                  reason: '$date always has a void status.',
                );
                expect(text, isNot(contains('未取得')), reason: date);
                expect(text, isNot(contains('not loaded')), reason: date);
                for (final element
                    in find
                        .descendant(of: cell, matching: find.byType(RichText))
                        .evaluate()) {
                  final paragraph =
                      element.findRenderObject()! as RenderParagraph;
                  final textWidget = element.widget as RichText;
                  within(
                    paragraph.localToGlobal(Offset.zero) & paragraph.size,
                    rect,
                    reason:
                        '$date text must not extend outside the day cell: ${textWidget.text.toPlainText()}',
                  );
                  expect(
                    paragraph.didExceedMaxLines,
                    isFalse,
                    reason: '$date text must not be ellipsized or dropped.',
                  );
                  final plain = textWidget.text.toPlainText();
                  if (plain.contains('月') ||
                      plain.contains('ボイド') ||
                      plain.contains('Moon') ||
                      plain.contains('Void') ||
                      plain.contains('02:00') ||
                      plain.contains('20:00')) {
                    final fontSize = textWidget.text.style?.fontSize ?? 14;
                    expect(
                      fontSize,
                      greaterThanOrEqualTo(14),
                      reason:
                          'Keep mandatory text at least the prior 14 px baseline.',
                    );
                    expect(
                      paragraph.textScaler.scale(fontSize),
                      greaterThanOrEqualTo(14 * scale - .01),
                      reason:
                          'Do not silently cancel the selected text scaling.',
                    );
                  }
                }
              }
              final rowTops = dayRects.map((rect) => rect.top.round()).toSet();
              expect(
                rowTops.length,
                month == 10 ? 5 : 6,
                reason: 'The final calendar week must be included.',
              );
              for (final element
                  in find
                      .descendant(of: fitted, matching: find.byType(Scrollable))
                      .evaluate()) {
                final position =
                    (element as StatefulElement).state as ScrollableState;
                expect(
                  position.position.maxScrollExtent,
                  closeTo(0, .1),
                  reason: 'Fitted month must not require scrolling.',
                );
              }
              final busyText = visibleCellText(cellFor(dateKey(month, 18)));
              expect(busyText, contains(english ? 'Ari' : '牡羊座'));
              expect(busyText, contains(english ? 'Tau' : '牡牛座'));
              expect(busyText, contains('02:00'));
              expect(busyText, contains('20:00'));
              expect(busyText, contains(english ? 'prev day' : '前日'));
              expect(busyText, contains(english ? 'next day' : '翌日'));
              if (english) {
                final labels = find
                    .descendant(
                      of: cellFor(dateKey(month, 18)),
                      matching: find.byType(Semantics),
                    )
                    .evaluate()
                    .map(
                      (element) =>
                          (element.widget as Semantics).properties.label ?? '',
                    )
                    .join('\n');
                expect(labels, contains('Aries'));
                expect(labels, contains('Taurus'));
                expect(labels, contains('Previous day'));
                expect(labels, contains('Next day'));
              }
              expect(
                visibleCellText(cellFor(dateKey(month, 9))),
                contains(english ? 'All day' : '終日'),
              );
              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }
  }

  testWidgets(
    'tablet day dialog keeps every supplemental event and returns to the fitted month',
    (tester) async {
      await pumpTablet(
        tester,
        size: tabletLandscape,
        month: 11,
        english: false,
        scale: 1.3,
      );
      await tester.tap(
        find.byKey(const ValueKey('astrology-calendar-month-load')),
      );
      await tester.pumpAndSettle();
      await tester.tap(cellFor('2026-11-18'));
      await tester.pumpAndSettle();
      final dialog = find.byKey(
        const ValueKey('astrology-calendar-day-dialog'),
      );
      expect(dialog, findsOneWidget);
      expect(
        find.descendant(
          of: dialog,
          matching: find.textContaining('SYNTHETIC supplement 7'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.textContaining('02:00')),
        findsWidgets,
      );
      expect(
        find.descendant(of: dialog, matching: find.textContaining('20:00')),
        findsWidgets,
      );
      Navigator.of(tester.element(dialog)).pop();
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      expect(cellFor('2026-11-30').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'tablet unavailable and failed days never show void-free status',
    (tester) async {
      await pumpTablet(
        tester,
        size: tabletLandscape,
        month: 11,
        english: false,
        scale: 1.0,
        failDate: '2026-11-17',
      );
      final failedCell = cellFor('2026-11-17');
      expect(visibleCellText(failedCell), contains('未取得'));
      expect(visibleCellText(failedCell), isNot(contains('なし')));
      await tester.tap(
        find.byKey(const ValueKey('astrology-calendar-month-load')),
      );
      await tester.pumpAndSettle();
      expect(visibleCellText(failedCell), contains('失敗'));
      expect(visibleCellText(failedCell), isNot(contains('なし')));
      expect(visibleCellText(cellFor('2026-11-16')), contains('なし'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'portrait English Moon abbreviations remain whole with matching measured height',
    (tester) async {
      const signLabels = ['Ari', 'Tau', 'Gem', 'Can', 'Leo', 'Vir', 'Lib', 'Sco', 'Sag', 'Cap', 'Aqu', 'Pis'];
      final dayPlan = DailySevenTimepointPlan.forJstDate('2026-11-13');
      for (final width in [95.0, 70.0]) {
        for (final scale in [1.0, 1.3]) {
          for (var signIndex = 0; signIndex < ZodiacSign.values.length; signIndex++) {
            for (final moving in [false, true]) {
              final before = ZodiacSign.values[signIndex];
              final after = ZodiacSign.values[(signIndex + 1) % ZodiacSign.values.length];
              final data = AstrologyCalendarDay(
                targetDateJst: dayPlan.targetDateJst,
                moonSignAtNoon: before,
                providerName: 'SYNTHETIC compact text fixture',
                precisionNotice: 'Synthetic data, not astronomical observations.',
                usesHighPrecisionAstroData: false,
                events: moving ? [AstrologyCalendarEvent(
                  kind: AstrologyCalendarEventKind.signIngress,
                  title: '月が${after.label}へ移動', detail: '星座の移動',
                  ingressPlanet: AstroPlanet.moon, fromSign: before, toSign: after,
                  startUtc: dayPlan.dayStartUtc.add(const Duration(hours: 5, minutes: 27)),
                )] : [],
              );
              const style = TextStyle(fontFamily: 'TabletFitTest', fontSize: 15);
              final measuredHeight = astrologyCalendarCompactRequiredHeight(
                data: data, english: true, width: width,
                textScaler: TextScaler.linear(scale), dayNumber: 13,
                fontSize: 15, textStyle: style,
              );
              await tester.pumpWidget(MaterialApp(
                home: Scaffold(body: Align(alignment: Alignment.topLeft,
                  child: MediaQuery(
                    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                    child: DefaultTextStyle(style: style,
                      child: SizedBox(width: width,
                        child: AstrologyCalendarCompactDayContent(
                          key: const ValueKey('portrait-abbreviation-content'),
                          data: data, english: true, dayNumber: 13,
                          fontSize: 15, maxHeight: measuredHeight, supplementalLimit: 0,
                        ),
                      ),
                    ),
                  ),
                )),
              ));
              await tester.pump();
              final content = find.byKey(const ValueKey('portrait-abbreviation-content'));
              final paragraphs = find.descendant(of: content, matching: find.byType(RichText));
              final renderedText = paragraphs.evaluate().map((element) =>
                  (element.widget as RichText).text.toPlainText()).join('\n');
              for (final label in {
                signLabels[signIndex],
                if (moving) signLabels[(signIndex + 1) % signLabels.length],
              }) {
                var found = false;
                for (final element in paragraphs.evaluate()) {
                  final text = (element.widget as RichText).text.toPlainText();
                  final position = text.indexOf(label);
                  if (position < 0) continue;
                  found = true;
                  final paragraph = element.findRenderObject()! as RenderParagraph;
                  final boxes = paragraph.getBoxesForSelection(
                    TextSelection(baseOffset: position, extentOffset: position + label.length),
                  );
                  expect(boxes, hasLength(1), reason:
                    '$label must stay whole at width=$width scale=$scale: $text');
                  expect(boxes.single.left, greaterThanOrEqualTo(-.1));
                  expect(boxes.single.right, lessThanOrEqualTo(width + .1));
                }
                expect(found, isTrue, reason: '$label is required: $renderedText');
              }
              expect(renderedText, contains('Moon:'));
              expect(renderedText, contains('Void none'));
              if (moving) {
                expect(renderedText, contains('→'));
                expect(renderedText, contains('05:27'));
              }
              expect(tester.getSize(content).height, lessThanOrEqualTo(measuredHeight + .1),
                reason: 'Height budget must use the same explicit line breaks as rendering.');
              expect(tester.takeException(), isNull);
            }
          }
        }
      }
    },
  );
}
