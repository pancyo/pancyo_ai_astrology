import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pancyo_ai_astrology/main.dart';
import 'package:pancyo_ai_astrology/app_language.dart';
import 'long_range_display_test.dart' as f;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ordinary weekly UI requests Sunday through Saturday', (tester) async {
    PeriodSevenDisplaySessionCache.clear();
    final requests = <WeeklyDailyConsultExportRequest>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: LongRangeReading(
      profile: f.profile, details: const UserProfileDetails.empty(), depth: ReadingDepth.simple,
      startWeeklyReadingJob: (request, progress) {
        requests.add(request);
        return f.PendingWeek();
      },
    )))));
    for (var i = 0; i < 8; i++) { await tester.pump(const Duration(milliseconds: 50)); }
    expect(requests, hasLength(1));
    expect(DateTime.parse(requests.single.startDateJst).weekday, DateTime.sunday);
    expect(DateTime.parse(requests.single.endDateJst).weekday, DateTime.saturday);
    expect(DateTime.parse(requests.single.endDateJst).difference(DateTime.parse(requests.single.startDateJst)).inDays, 6);
    expect(requests.single.dayPlans, hasLength(7));
    await tester.pumpWidget(const SizedBox());
    PeriodSevenDisplaySessionCache.clear();
  });

  test('400 Gregorian years retain exactly five complete Sunday weeks', () {
    for (var year = 2000; year < 2400; year++) {
      for (var month = 1; month <= 12; month++) {
        final weeks = monthlyReadingWeeks(DateTime.utc(year, month));
        expect(weeks, hasLength(5));
        final days = weeks.expand((week) => week).toList();
        expect(days.toSet(), hasLength(35));
        for (final week in weeks) {
          expect(week, hasLength(7));
          expect(week.first.weekday, DateTime.sunday);
          expect(week.last.weekday, DateTime.saturday);
          expect(week.last.difference(week.first).inDays, 6);
          expect(week.every((date) => date.isUtc && date.hour == 3), true);
        }
        final last = DateTime.utc(year, month + 1, 0, 3);
        expect(days.contains(last), true);
        expect(days.last.difference(last).inDays, inInclusiveRange(0, 6));
        for (var i = 1; i < days.length; i++) {
          expect(days[i].difference(days[i - 1]).inDays, 1);
        }
      }
    }
    final august = monthlyReadingWeeks(DateTime.utc(2026, 8));
    expect(august.first.first, DateTime.utc(2026, 8, 2, 3));
    expect(august.last.last, DateTime.utc(2026, 9, 5, 3));
  });

  test('monthly graph never changes the five-date calendar-month summary', () {
    for (final pair in [(2026, 8), (2028, 2), (2026, 12), (2027, 1)]) {
      final request = f.request(LongRangeDisplayMode.month, year: pair.$1, month: pair.$2);
      final samples = f.raw(request, (i) => 50 + i % 49);
      final summary = LongRangeDisplaySummary.fromSamples(request: request, samples: samples);
      expect(summary.dates, NineAreaPeriodSummary.sampleDates(LongRangeMode.month, request.month, pair.$1));
      expect(summary.dates.length, 5);
      final selected = summary.dates.map((d) => samples[d]!.first.score!).toList();
      expect(summary.areas.first.samples, selected);
      expect(summary.areas.first.score, (selected.reduce((a, b) => a + b) / 5).round());
      final result = f.completed(request, samples);
      expect(result.matches(request), true);
      expect(result.dailySamples.length, 5, reason: 'Out-of-month graph samples must not enter monthly narratives.');
      expect(result.trend.labels, hasLength(5));
      for (var i = 0; i < 5; i++) {
        final scores = request.monthWeeks[i].map((date) => samples[date]!.first.score!).toList();
        expect(result.trend.series.first.values[i], (scores.reduce((a, b) => a + b) / 7).round());
      }
    }
  });

  test('ten-year calculations, graph and saved JSON include 240 samples', () {
    final request = f.request(LongRangeDisplayMode.tenYear, year: 2026);
    final samples = f.raw(request, (i) => 50 + i % 49, felt: (i) => i < 120 ? '良い' : '悪い');
    final result = f.completed(request, samples);
    expect(request.endYear, 2035);
    expect(request.dates.toSet(), hasLength(240));
    expect(request.dates.map((d) => d.year).toSet(), {for (var y = 2026; y <= 2035; y++) y});
    expect(result.trend.labels, [for (var y = 2026; y <= 2035; y++) '$y']);
    expect(result.summary.areas.first.samples, hasLength(240));
    expect(result.summary.feltCounts['良い'], 120);
    expect(result.summary.feltCounts['悪い'], 120);
    final json = tenYearDisplayRecord(request, result, const AppStrings(AppLanguage.ja));
    expect(json['end_date_jst'], '2035-12-31');
    expect(json['reference_sample_count'], 240);
    expect(json['areas'], hasLength(9));
    expect(json['reference_samples'], hasLength(240));
    expect(jsonEncode(json), contains('この10年間'));
    expect(jsonEncode(json), isNot(contains('この5年間')));
    final missing = LongRangeDisplayResult(requestIdentity: request.identity,
      samples: Map.of(result.samples)..remove(request.dates.last),
      summary: result.summary, trend: result.trend, computedSampleCount: 239);
    expect(() => tenYearDisplayRecord(request, missing, const AppStrings(AppLanguage.ja)), throwsStateError);
    expect(readingPeriodRange(result.summary), '2026-01-01 – 2035-12-31');
  });

  testWidgets('both card sections show full date ranges on phone and tablet', (tester) async {
    for (final size in [const Size(390, 844), const Size(1000, 1300)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      for (final mode in [LongRangeDisplayMode.month, LongRangeDisplayMode.year, LongRangeDisplayMode.tenYear]) {
        final request = f.request(mode, year: 2026, month: 8);
        final summary = f.completed(request, f.raw(request, (_) => 70)).summary;
        for (final depth in ReadingDepth.values) {
          await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: NineAreaPeriodOverview(summary: summary, depth: depth)))));
          await tester.pump();
          final label = readingPeriodRange(summary);
          expect(find.textContaining(label), findsAtLeastNWidgets(2));
          expect(tester.takeException(), isNull);
        }
      }
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });
}
