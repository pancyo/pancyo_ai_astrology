import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pancyo_ai_astrology/main.dart';
import 'long_range_display_test.dart' as f;

void main() {
  test('daily marker follows actual JST time between the seven samples', () {
    final axis = GraphNowAxis.daily(DateTime.utc(2026, 10, 29));
    final now = DateTime.utc(2026, 10, 29, 3, 35);
    final marker = axis.markerAt(now)!;
    expect(marker.label, '今 12:35');
    expect(marker.position, closeTo(755 / 1440, 1e-12));
    expect(marker.pointIndex, 3);
    expect(marker.nearestSample, true);
    expect(
      axis.markerAt(DateTime.parse('2026-10-29T12:35:00+09:00'))!.position,
      marker.position,
    );
    expect(axis.markerAt(now, english: true)!.label, 'Now 12:35');
    expect(axis.markerAt(DateTime.utc(2026, 10, 28, 14, 59, 59)), isNull);
    expect(axis.markerAt(DateTime.utc(2026, 10, 28, 15))!.position, 0);
    expect(axis.markerAt(DateTime.utc(2026, 10, 29, 15)), isNull);
  });

  test('JST boundaries survive leap day and year rollover', () {
    final leap = GraphNowAxis.daily(DateTime.utc(2028, 2, 29));
    expect(leap.markerAt(DateTime.utc(2028, 2, 28, 15))!.position, 0);
    expect(leap.markerAt(DateTime.utc(2028, 2, 29, 14, 59)), isNotNull);
    expect(leap.markerAt(DateTime.utc(2028, 2, 29, 15)), isNull);
    final years = GraphNowAxis.years([2026, 2027]);
    expect(years.markerAt(DateTime.utc(2026, 12, 31, 14, 59))!.pointIndex, 0);
    expect(years.markerAt(DateTime.utc(2026, 12, 31, 15))!.pointIndex, 1);
    expect(years.markerAt(DateTime.utc(2027, 12, 31, 15)), isNull);
  });

  test('week marks today and month marks the actual complete week', () {
    final week = GraphNowAxis.days([
      for (var i = 0; i < 7; i++) DateTime.utc(2026, 10, 25 + i),
    ]);
    final thursday = week.markerAt(DateTime.utc(2026, 10, 29, 3))!;
    expect(thursday.pointIndex, 4);
    expect(thursday.position, closeTo(4 / 6, 1e-12));
    expect(thursday.label, '今日 10/29');
    expect(week.markerAt(DateTime.utc(2026, 11, 1, 3)), isNull);
    final month = GraphNowAxis.weeks(
      monthlyReadingWeeks(DateTime.utc(2026, 8)).map((w) => w.first),
    );
    expect(month.markerAt(DateTime.utc(2026, 8, 1, 3)), isNull);
    expect(month.markerAt(DateTime.utc(2026, 8, 2, 3))!.pointIndex, 0);
    expect(month.markerAt(DateTime.utc(2026, 8, 30, 3))!.pointIndex, 4);
    expect(month.markerAt(DateTime.utc(2026, 9, 5, 14, 59))!.position, 1);
    expect(month.markerAt(DateTime.utc(2026, 9, 5, 15)), isNull);
  });

  test('year and ten-year marker do not invent now outside the chart', () {
    final year = GraphNowAxis.months([
      for (var m = 1; m <= 12; m++) DateTime.utc(2026, m),
    ]);
    expect(year.markerAt(DateTime.utc(2026, 10, 29, 3))!.pointIndex, 9);
    expect(
      year.markerAt(DateTime.utc(2026, 10, 29, 3))!.position,
      closeTo(9 / 11, 1e-12),
    );
    expect(year.markerAt(DateTime.utc(2027, 1, 1, 3)), isNull);
    final decade = GraphNowAxis.years([for (var y = 2026; y <= 2035; y++) y]);
    expect(decade.markerAt(DateTime.utc(2026, 10, 29, 3))!.position, 0);
    expect(decade.markerAt(DateTime.utc(2035, 10, 29, 3))!.position, 1);
    expect(decade.markerAt(DateTime.utc(2036, 1, 1, 3)), isNull);
    expect(decade.markerAt(DateTime.utc(2025, 1, 1, 3)), isNull);
  });

  testWidgets('clock updates at the next minute and refreshes on resume', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 10, 29, 3, 59, 59);
    GraphNowMarker? seen;
    await tester.pumpWidget(
      MaterialApp(
        home: CurrentGraphClock(
          axis: GraphNowAxis.daily(DateTime.utc(2026, 10, 29)),
          nowUtc: () => now,
          builder: (context, marker) {
            seen = marker;
            return Text(marker?.label ?? 'outside');
          },
        ),
      ),
    );
    expect(find.text('今 12:59'), findsOneWidget);
    final previous = seen!.position;
    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('今 13:00'), findsOneWidget);
    expect(seen!.position, greaterThan(previous));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = DateTime.utc(2026, 10, 29, 15);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('outside'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'monthly main and additional graphs share now and preserve every score',
    (tester) async {
      final today = DateTime.now().toUtc().add(const Duration(hours: 9));
      final request = f.request(
        LongRangeDisplayMode.month,
        year: today.year,
        month: today.month,
      );
      final result = f.completed(request, f.raw(request, (i) => 50 + i % 49));
      final original = result.trend.series
          .map((s) => s.values.toList())
          .toList();
      tester.view.resetPhysicalSize();
      tester.view.physicalSize = const Size(1400, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LongRangeDisplayTrendView(
                data: result.trend,
                mode: LongRangeDisplayMode.month,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('additional-trend-toggle')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();
      final painters = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<FortuneFlowPainter>()
          .toList();
      expect(painters, hasLength(2));
      expect(painters.first.labels, hasLength(5));
      expect(painters.last.labels, hasLength(5));
      expect(painters.first.nowMarker, isNotNull);
      expect(
        painters.first.nowMarker!.position,
        painters.last.nowMarker!.position,
      );
      expect(
        painters.first.nowMarker!.pointIndex,
        painters.last.nowMarker!.pointIndex,
      );
      expect(
        find.byKey(const ValueKey('felt-current-position')),
        findsOneWidget,
      );
      expect(result.trend.series.map((s) => s.values).toList(), original);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'narrow chart initially reveals now and respects manual scrolling',
    (tester) async {
      var now = DateTime.utc(2026, 10, 29, 13);
      final axis = GraphNowAxis.daily(DateTime.utc(2026, 10, 29));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 200,
                height: 220,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: 800,
                    height: 220,
                    child: CurrentGraphClock(
                      axis: axis,
                      nowUtc: () => now,
                      builder: (context, marker) => const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position;
      expect(position.pixels, greaterThan(400));
      final x = 34 + (800 - 34 - 12) * axis.markerAt(now)!.position;
      expect(x, inInclusiveRange(position.pixels, position.pixels + 200));
      position.jumpTo(0);
      now = now.add(const Duration(minutes: 1));
      await tester.pump(const Duration(minutes: 1));
      expect(position.pixels, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'long monthly labels remain separated after end labels move inwards',
    () {
      const labels = [
        '9/27–10/3',
        '10/4–10/10',
        '10/11–10/17',
        '10/18–10/24',
        '10/25–10/31',
      ];
      for (final scale in [1.0, 1.5, 2.0]) {
        final scaler = TextScaler.linear(scale);
        final width = graphAxisMinimumWidth(labels, scaler);
        var previousRight = 0.0;
        for (var i = 0; i < labels.length; i++) {
          final painter = TextPainter(
            textDirection: TextDirection.ltr,
            textScaler: scaler,
            text: TextSpan(
              text: labels[i],
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
            ),
          )..layout();
          final center = 34 * scale + (width - 46 * scale) * i / 4;
          final left = graphAxisLabelLeft(center, painter.width, width);
          expect(left, greaterThanOrEqualTo(previousRight));
          previousRight = left + painter.width;
          expect(previousRight, lessThanOrEqualTo(width));
          painter.dispose();
        }
      }
    },
  );

  test('long right-edge week labels remain inside the scrollable canvas', () {
    for (final width in [450.0, 900.0, 1400.0]) {
      for (final scale in [1.0, 1.5, 2.0]) {
        final label = TextPainter(
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.linear(scale),
          text: const TextSpan(
            text: '10/25–10/31',
            style: TextStyle(fontSize: 10),
          ),
        )..layout();
        final left = graphAxisLabelLeft(width - 12 * scale, label.width, width);
        expect(left, greaterThanOrEqualTo(0));
        expect(left + label.width, lessThanOrEqualTo(width));
      }
    }
  });
}
