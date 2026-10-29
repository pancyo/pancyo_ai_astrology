import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pancyo_ai_astrology/main.dart';

class PendingVoid implements AstrologyCalendarOperation {
  final completion = Completer<AstrologyCalendarDay>();
  bool cancelled = false;
  @override
  Future<AstrologyCalendarDay> get result => completion.future;
  @override
  void cancel() {
    cancelled = true;
  }
}

AstrologyCalendarEvent interval(DateTime start, DateTime end) {
  final dayStart = DateTime.utc(2026, 10, 28, 15),
      dayEnd = DateTime.utc(2026, 10, 29, 15);
  return AstrologyCalendarEvent(
    kind: AstrologyCalendarEventKind.voidMoon,
    title: '月ボイド',
    detail: 'fixture',
    startUtc: start,
    endUtc: end,
    overlapStartUtc: start.isAfter(dayStart) ? start : dayStart,
    overlapEndUtc: end.isBefore(dayEnd) ? end : dayEnd,
  );
}

AstrologyCalendarDay day(
  String date, {
  List<AstrologyCalendarEvent> events = const [],
  String source = 'fixture',
}) => AstrologyCalendarDay(
  targetDateJst: date,
  events: events,
  providerName: source,
  precisionNotice: 'fixture',
  usesHighPrecisionAstroData: false,
);

void main() {
  test(
    'multiple daily void bands preserve exact boundaries and both day crossings',
    () {
      final bands = GraphVoidBand.forDay('2026-10-29', [
        interval(
          DateTime.utc(2026, 10, 29, 13),
          DateTime.utc(2026, 10, 29, 18),
        ),
        interval(
          DateTime.utc(2026, 10, 28, 12),
          DateTime.utc(2026, 10, 28, 17),
        ),
      ]);
      expect(bands, hasLength(2));
      expect(bands.first.startFraction, 0);
      expect(bands.first.endFraction, closeTo(2 / 24, 1e-12));
      expect(bands.first.continuesFromPreviousDay, true);
      expect(bands.first.label(false), contains('00:00–02:00（前日から）'));
      expect(bands.last.startFraction, closeTo(22 / 24, 1e-12));
      expect(bands.last.endFraction, 1);
      expect(bands.last.continuesIntoNextDay, true);
      expect(bands.last.label(false), contains('22:00–24:00（翌日へ）'));
    },
  );
  test('short calendar voids are not rounded into samples or dropped', () {
    final start = DateTime.utc(2026, 10, 29, 3, 1, 10);
    final end = start.add(const Duration(seconds: 30));
    final band = GraphVoidBand.forDay('2026-10-29', [
      interval(start, end),
    ]).single;
    expect(band.startUtc, start);
    expect(band.endUtc, end);
    expect(band.endFraction - band.startFraction, closeTo(30 / 86400, 1e-12));
    expect(GraphVoidBand.forDay('2026-10-29', []), isEmpty);
    expect(
      () => GraphVoidBand.forDay('2026-10-29', [
        const AstrologyCalendarEvent(
          kind: AstrologyCalendarEventKind.voidMoon,
          title: 'bad',
          detail: 'missing',
        ),
      ]),
      throwsStateError,
    );
    expect(
      () => GraphVoidBand.forDay('2026-10-29', [
        interval(start, end),
        interval(
          start.add(const Duration(seconds: 10)),
          end.add(const Duration(seconds: 10)),
        ),
      ]),
      throwsStateError,
    );
  });
  testWidgets(
    'unloaded, verified empty and failed are distinct; retry uses strict source check',
    (tester) async {
      final jobs = <PendingVoid>[];
      AstrologyCalendarOperation starter(
        String date,
        void Function(int, int) progress,
      ) {
        final job = PendingVoid();
        jobs.add(job);
        return job;
      }

      await tester.pumpWidget(
        MaterialApp(
          home: DailyGraphVoidLayer(
            dateJst: '2026-10-29',
            enabled: true,
            sourceName: 'fixture',
            requireHighPrecision: false,
            startJob: starter,
            builder: (context, data, retry) =>
                DailyGraphVoidLegend(data: data, onRetry: retry),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(jobs, hasLength(1));
      expect(find.byKey(const ValueKey('daily-void-none')), findsNothing);
      jobs.single.completion.completeError(StateError('unavailable'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('daily-void-unavailable')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('daily-void-none')), findsNothing);
      await tester.tap(find.text('再取得'));
      await tester.pumpAndSettle();
      jobs.last.completion.complete(day('2026-10-29', source: 'wrong source'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('daily-void-unavailable')),
        findsOneWidget,
      );
      await tester.tap(find.text('再取得'));
      await tester.pumpAndSettle();
      jobs.last.completion.complete(day('2026-10-29'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('daily-void-none')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('date change cancels old void load and rejects stale bands', (
    tester,
  ) async {
    final jobs = <PendingVoid>[];
    DailyGraphVoidData? seen;
    AstrologyCalendarOperation starter(
      String date,
      void Function(int, int) progress,
    ) {
      final job = PendingVoid();
      jobs.add(job);
      return job;
    }

    Widget content(String date) => MaterialApp(
      home: DailyGraphVoidLayer(
        dateJst: date,
        enabled: true,
        sourceName: 'fixture',
        requireHighPrecision: false,
        startJob: starter,
        builder: (context, data, retry) {
          seen = data;
          return DailyGraphVoidLegend(data: data, onRetry: retry);
        },
      ),
    );
    await tester.pumpWidget(content('2026-10-29'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(content('2026-10-30'));
    await tester.pumpAndSettle();
    expect(jobs.first.cancelled, true);
    expect(jobs, hasLength(2));
    jobs.first.completion.complete(
      day(
        '2026-10-29',
        events: [
          interval(
            DateTime.utc(2026, 10, 29, 2),
            DateTime.utc(2026, 10, 29, 3),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(seen!.bands, isEmpty);
    expect(seen!.status, DailyGraphVoidStatus.loading);
    jobs.last.completion.complete(day('2026-10-30'));
    await tester.pumpAndSettle();
    expect(seen!.status, DailyGraphVoidStatus.ready);
    expect(seen!.bands, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
}
