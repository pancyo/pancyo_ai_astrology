import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pancyo_ai_astrology/daily_seven_timepoint_plan.dart';
import 'package:pancyo_ai_astrology/main.dart';

// These interval fixtures test the display contract; they are not observed
// astronomical intervals and do not stand in for Android/Swiss verification.
void main() {
  final plan = DailySevenTimepointPlan.forJstDate('2026-10-31');
  DateTime at(int minutes) => plan.dayStartUtc.add(Duration(minutes: minutes));
  VoidMoonPeriod clipped(int start, int end) => VoidMoonPeriod(
    start: 'fixture', end: 'fixture', startTime: at(start), endTime: at(end),
    guidance: 'Synthetic interval fixture',
  );
  List<AstrologyCalendarEvent> display(
    List<({DateTime startUtc, DateTime endUtc})> intervals,
    VoidMoonPeriod? dayApi,
  ) => AstrologyCalendarEvent.voidMoonIntervalsForCalendarDisplay(
    plan: plan, rawIntervals: intervals, dayApiResult: dayApi,
  );

  group('synthetic calendar display intervals; no native calculation', () {
    test('retains a short boundary overlap and the longer day-API interval', () {
      final raw = [
        (startUtc: at(-60), endUtc: at(3)),
        (startUtc: at(600), endUtc: at(660)),
      ];
      final api = clipped(600, 660);
      final result = display(raw, api);
      expect(result, hasLength(2));
      expect(result.first.startUtc, at(-60));
      expect(result.first.overlapStartUtc, plan.dayStartUtc);
      expect(result.first.overlapEndUtc, at(3));
      expect(result.first.continuesFromPreviousDay, isTrue);
      expect(result.last.startUtc, api.startTime);
      final legacy = AstrologyCalendarEvent.voidMoonIntervalsForDay(
        plan: plan, rawIntervals: [raw.last], dayApiResult: api,
      );
      expect(result.last.toMessage(), legacy.single.toMessage());
      expect(api.dayShare(plan.primaryNoon.instantUtc, dayStartUtc: plan.dayStartUtc), 1/24);
    });

    test('exactly five minutes is retained only by the display path', () {
      final start = at(120), end = at(125);
      expect(AstrologyCalendarEvent.voidMoonForDay(
        plan: plan, actualStartUtc: start, actualEndUtc: end, dayApiResult: null,
      ), isNull);
      final result = display([(startUtc: start, endUtc: end)], null);
      expect(result, hasLength(1));
      expect(result.single.endUtc!.difference(result.single.startUtc!), const Duration(minutes: 5));
      expect(display([(startUtc: at(-60), endUtc: at(0))], null), isEmpty);
      expect(display([(startUtc: at(1440), endUtc: at(1500))], null), isEmpty);
    });

    test('all-day interval preserves actual endpoints and continuation', () {
      final result = display([(startUtc: at(-180), endUtc: at(1500))], clipped(0, 1440));
      final event = result.single;
      expect(event.startUtc, at(-180));
      expect(event.endUtc, at(1500));
      expect(event.continuesFromPreviousDay, isTrue);
      expect(event.continuesIntoNextDay, isTrue);
      expect(event.overlapStartUtc, plan.dayStartUtc);
      expect(event.overlapEndUtc, plan.dayEndUtc);
      expect(astrologyCalendarVoidLabel(event, plan.targetDateJst, english: false), '終日');
    });

    test('two independent longer intervals remain two rows with one event each', () {
      final result = display([
        (startUtc: at(60), endUtc: at(120)),
        (startUtc: at(900), endUtc: at(1500)),
      ], clipped(60, 120));
      expect(result, hasLength(2));
      expect(result.map((event) => astrologyCalendarVoidLabel(event, plan.targetDateJst, english: false)),
        ['01:00〜02:00', '15:00〜翌日']);
      expect(result.map((event) => '${event.startUtc}/${event.endUtc}').toSet(), hasLength(2));
    });

    test('missing or inconsistent day-API evidence fails, not no-void', () {
      expect(() => display([], clipped(60, 120)), throwsStateError);
      expect(() => display([(startUtc: at(60), endUtc: at(120))], null), throwsStateError);
      expect(() => display([(startUtc: at(60), endUtc: at(120))], clipped(61, 120)), throwsStateError);
      expect(() => display([
        (startUtc: at(60), endUtc: at(120)),
        (startUtc: at(100), endUtc: at(125)),
      ], clipped(60, 120)), throwsStateError);
      expect(() => display([(startUtc: at(60), endUtc: at(60))], null), throwsStateError);
    });

    test('month boundary is half-open and same physical interval is retained', () {
      final next = DailySevenTimepointPlan.forJstDate('2026-11-01');
      final raw = [(startUtc: at(1438), endUtc: at(1443))];
      final before = display(raw, null).single;
      final after = AstrologyCalendarEvent.voidMoonIntervalsForCalendarDisplay(
        plan: next, rawIntervals: raw, dayApiResult: null,
      ).single;
      expect(before.startUtc, after.startUtc);
      expect(before.endUtc, after.endUtc);
      expect(before.overlapEndUtc, after.overlapStartUtc);
      expect(before.overlapEndUtc, next.dayStartUtc);
      expect(astrologyCalendarVoidLabel(before, plan.targetDateJst, english: false), '23:58〜翌日');
      expect(astrologyCalendarVoidLabel(after, next.targetDateJst, english: false), '前日〜00:03');
    });
  });

  group('calendar metadata serialization', () {
    test('roundtrip keeps ingress before/after and moon sign without private input', () {
      final day = AstrologyCalendarDay(
        targetDateJst: plan.targetDateJst, providerName: 'Synthetic fixture',
        precisionNotice: 'No native computation', usesHighPrecisionAstroData: false,
        moonSignAtNoon: ZodiacSign.pisces,
        events: [AstrologyCalendarEvent(
          kind: AstrologyCalendarEventKind.signIngress,
          title: '月が牡羊座へ移動', detail: 'fixture', startUtc: at(900),
          ingressPlanet: AstroPlanet.moon, fromSign: ZodiacSign.pisces, toSign: ZodiacSign.aries,
        )],
      );
      final serialized = jsonEncode(day.toMessage());
      final readback = AstrologyCalendarDay.fromMessage(jsonDecode(serialized));
      expect(readback.toMessage(), day.toMessage());
      expect(readback.events.single.fromSign, ZodiacSign.pisces);
      expect(readback.events.single.toSign, ZodiacSign.aries);
      expect(readback.moonSignAtNoon, ZodiacSign.pisces);
      expect(serialized, isNot(contains('birth')));
      expect(serialized, isNot(contains('profile')));
      expect(serialized, isNot(contains('note')));
    });

    test('legacy absent metadata remains unknown, invalid metadata is rejected', () {
      final day = AstrologyCalendarDay.fromMessage({
        'target_date_jst': '2026-10-31', 'events': [],
      });
      expect(day.moonSignAtNoon, isNull);
      expect(() => AstrologyCalendarDay.fromMessage({
        'target_date_jst': '2026-10-31', 'events': [], 'moon_sign_at_noon': 'invalid',
      }), throwsFormatException);
      expect(() => AstrologyCalendarEvent.fromMessage({
        'kind': 'signIngress', 'from_sign': 'invalid',
      }), throwsFormatException);
    });
  });

  test('existing simple provider smoke: metadata only; not native astronomy validation', () {
    const provider = SimpleEphemeris();
    final day = calculateAstrologyCalendarDay('2026-10-01', providerOverride: provider);
    final dayPlan = DailySevenTimepointPlan.forJstDate(day.targetDateJst);
    final moon = provider.placementsFor(dayPlan.primaryNoon.instantUtc).singleWhere((p) => p.planet == AstroPlanet.moon);
    expect(day.moonSignAtNoon, moon.sign);
    expect(day.usesHighPrecisionAstroData, isFalse);
    for (final event in day.events.where((event) => event.kind == AstrologyCalendarEventKind.signIngress)) {
      expect(event.ingressPlanet, isNotNull);
      final previous = provider.placementsFor(dayPlan.dayStartUtc).singleWhere((p) => p.planet == event.ingressPlanet);
      final ingress = provider.nextSignIngress(event.ingressPlanet!, dayPlan.dayStartUtc)!;
      expect(event.fromSign, previous.sign);
      expect(event.toSign, ingress.sign);
      expect(event.startUtc, ingress.time.toUtc());
    }
  });
}
