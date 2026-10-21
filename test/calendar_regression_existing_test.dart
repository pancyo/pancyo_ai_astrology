// Regression cases retained from the pre-v90 local calendar tests.
// Explicit synthetic fixtures only; this file does not certify real ephemeris data.
import 'package:flutter_test/flutter_test.dart';
import 'package:pancyo_ai_astrology/daily_seven_timepoint_plan.dart';
import 'package:pancyo_ai_astrology/main.dart';

void main() {
  test('Swiss取得不能を簡易計算へ置換せず失敗にする', () {
    expect(
      () => calculateAstrologyCalendarDay(
        '2026-04-01',
        providerOverride: const SwissEphemerisProvider(),
      ),
      throwsA(isA<StateError>()),
    );
  }, skip: SwissEphemerisProvider.isAvailable);

  test(
    'JST day boundaries and existing daily-event worker targets are preserved',
    () {
      final plan = DailySevenTimepointPlan.forJstDate('2026-10-10');
      expect(plan.dayStartUtc, DateTime.utc(2026, 10, 9, 15));
      expect(plan.dayEndUtc, DateTime.utc(2026, 10, 10, 15));
      expect(plan.primaryNoon.instantUtc, DateTime.utc(2026, 10, 10, 3));

      final progress = <(int, int)>[];
      final day = calculateAstrologyCalendarDay(
        '2026-10-10',
        providerOverride: const _IngressCalendarProvider(),
        onProgress: (completed, total) => progress.add((completed, total)),
      );
      expect(day.targetDateJst, '2026-10-10');
      expect(
        day.events
            .where(
              (event) => event.kind == AstrologyCalendarEventKind.signIngress,
            )
            .map((event) => event.title),
        containsAll(['木星が牡牛座へ移動', '冥王星が魚座へ移動']),
      );
      expect(progress, hasLength(17));
      expect(progress.last, (17, 17));
    },
  );

  _checkVoidWindowSemantics();
}

void _checkVoidWindowSemantics() {
  test('同日の複数月ボイドは先頭だけ日API照合し、後続も保持する', () {
    final plan = DailySevenTimepointPlan.forJstDate('2024-01-31');
    final firstStart = plan.dayStartUtc.add(const Duration(hours: 1));
    final firstEnd = plan.dayStartUtc.add(const Duration(hours: 2));
    final secondStart = plan.dayStartUtc.add(const Duration(hours: 4));
    final secondEnd = plan.dayStartUtc.add(const Duration(hours: 5));
    final dayApi = VoidMoonPeriod(
      start: '01:00',
      end: '02:00',
      startTime: firstStart,
      endTime: firstEnd,
      guidance: 'test guidance',
    );

    final events = AstrologyCalendarEvent.voidMoonIntervalsForDay(
      plan: plan,
      rawIntervals: [
        (startUtc: firstStart, endUtc: firstEnd),
        (startUtc: secondStart, endUtc: secondEnd),
      ],
      dayApiResult: dayApi,
    );

    expect(events, hasLength(2));
    expect(events.first.startUtc, firstStart);
    expect(events.first.endUtc, firstEnd);
    expect(events.last.startUtc, secondStart);
    expect(events.last.endUtc, secondEnd);
    expect(events.last.overlapStartUtc, secondStart);
    expect(events.last.overlapEndUtc, secondEnd);
    expect(events.last.detail, dayApi.guidance);
    expect(
      () => AstrologyCalendarEvent.voidMoonIntervalsForDay(
        plan: plan,
        rawIntervals: [
          (startUtc: firstStart, endUtc: secondEnd),
          (startUtc: secondStart, endUtc: secondEnd),
        ],
        dayApiResult: dayApi,
      ),
      throwsStateError,
    );
  });

  test('月ボイドの実開始終了と対象日内の切詰めを別に保持し境界を扱う', () {
    final plan = DailySevenTimepointPlan.forJstDate('2024-01-31');
    final previousDayStart = plan.dayStartUtc.subtract(
      const Duration(hours: 2),
    );
    final sameDayEnd = plan.dayStartUtc.add(const Duration(hours: 3));
    final clippedByDayApi = VoidMoonPeriod(
      start: '00:00',
      end: '03:00',
      startTime: plan.dayStartUtc,
      endTime: sameDayEnd,
      guidance: 'test',
    );
    final continuing = AstrologyCalendarEvent.voidMoonForDay(
      plan: plan,
      actualStartUtc: previousDayStart,
      actualEndUtc: sameDayEnd,
      dayApiResult: clippedByDayApi,
    )!;
    expect(continuing.startUtc, previousDayStart);
    expect(continuing.overlapStartUtc, plan.dayStartUtc);
    expect(continuing.continuesFromPreviousDay, isTrue);
    expect(continuing.continuesIntoNextDay, isFalse);
    expect(
      clippedByDayApi.dayShare(
        plan.primaryNoon.instantUtc,
        dayStartUtc: plan.dayStartUtc,
      ),
      3 / 24,
    );

    final nextDayStart = plan.dayEndUtc;
    final nextDayEnd = nextDayStart.add(const Duration(minutes: 20));
    final clippedAtEnd = VoidMoonPeriod(
      start: '23:00',
      end: '00:00',
      startTime: plan.dayStartUtc.add(const Duration(hours: 23)),
      endTime: plan.dayEndUtc,
      guidance: 'test',
    );
    final endingNextDay = AstrologyCalendarEvent.voidMoonForDay(
      plan: plan,
      actualStartUtc: clippedAtEnd.startTime,
      actualEndUtc: nextDayEnd,
      dayApiResult: clippedAtEnd,
    )!;
    expect(endingNextDay.endUtc, nextDayEnd);
    expect(endingNextDay.overlapEndUtc, plan.dayEndUtc);
    expect(endingNextDay.continuesIntoNextDay, isTrue);
    expect(
      AstrologyCalendarEvent.voidMoonForDay(
        plan: plan,
        actualStartUtc: previousDayStart,
        actualEndUtc: plan.dayStartUtc,
        dayApiResult: null,
      ),
      isNull,
    );
    expect(
      AstrologyCalendarEvent.voidMoonForDay(
        plan: plan,
        actualStartUtc: plan.dayStartUtc,
        actualEndUtc: plan.dayEndUtc,
        dayApiResult: VoidMoonPeriod(
          start: '00:00',
          end: '00:00',
          startTime: plan.dayStartUtc,
          endTime: plan.dayEndUtc,
          guidance: 'test',
        ),
      )!.continuesIntoNextDay,
      isFalse,
    );
    expect(
      () => AstrologyCalendarEvent.voidMoonForDay(
        plan: plan,
        actualStartUtc: previousDayStart,
        actualEndUtc: sameDayEnd,
        dayApiResult: VoidMoonPeriod(
          start: '00:01',
          end: '03:00',
          startTime: plan.dayStartUtc.add(const Duration(minutes: 1)),
          endTime: sameDayEnd,
          guidance: 'mismatch',
        ),
      ),
      throwsStateError,
    );
  });
}

class _IngressCalendarProvider extends SimpleEphemeris {
  const _IngressCalendarProvider();

  @override
  SignIngress? nextSignIngress(AstroPlanet planet, DateTime date) {
    final (ZodiacSign sign, int hours)? event = switch (planet) {
      AstroPlanet.jupiter => (ZodiacSign.taurus, 4),
      AstroPlanet.pluto => (ZodiacSign.pisces, 8),
      _ => null,
    };
    return event == null
        ? null
        : SignIngress(
            sign: event.$1,
            time: date.add(Duration(hours: event.$2)),
          );
  }
}

