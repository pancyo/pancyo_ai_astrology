import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pancyo_ai_astrology/consult_json_export.dart';
import 'package:pancyo_ai_astrology/main.dart';

import 'monthly_daily_consult_export_test.dart' as fixture;

WeeklyDailyConsultExportRequest request(DateTime start) {
  final source = AstrologyDataSources.current;
  return WeeklyDailyConsultExportRequest(
    startDate: start,
    profile: fixture.subject,
    details: const UserProfileDetails.empty(),
    requestedHouseSystem: HouseSystemSettings.current.value,
    sourceName: source.sourceName,
    requireHighPrecision: source.usesHighPrecisionAstroData,
    generatedAt: DateTime.utc(2026, 10, 18, 3),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('canonical weekly plans preserve month/leap/year boundaries and 24/00 identity', () {
    for (final start in [DateTime.utc(2026, 1, 28, 3), DateTime.utc(2024, 2, 26, 3), DateTime.utc(2026, 12, 28, 3)]) {
      final r = request(start);
      expect(r.dayPlans.length, 7);
      expect(r.dayPlans.map((p) => p.targetDateJst).toSet().length, 7);
      expect(r.dayPlans.first.points.first.instantUtc, start.subtract(const Duration(hours: 12)));
      expect(r.dayPlans.last.points.last.instantUtc, start.add(const Duration(days: 7, hours: -12)));
      expect(r.dayPlans.expand((p) => p.points).map((p) => p.instantUtc).toSet().length, 43);
      for (var i = 0; i < 6; i++) {
        expect(r.dayPlans[i].points.last.instantUtc, r.dayPlans[i + 1].points.first.instantUtc);
        expect(r.dayPlans[i].points.last.isInsideDayInterval, false);
      }
    }
  });

  test('weekly v1 keeps daily-v4 full records, noon, 49/43 boundaries and readback without overwriting old JSON', () async {
    final r = request(DateTime.utc(2026, 12, 28, 3));
    final progress = <int>[];
    final data = buildWeeklyDailyConsultData(r, onProgress: (done, total) {
      expect(total, 49);
      progress.add(done);
    });
    expect(progress, List.generate(49, (i) => i + 1));
    expect(data['schema'], 'pancyo_astrology_weekly_daily_consult_v1');
    expect((data['completeness'] as Map)['listed_point_count'], 49);
    expect((data['completeness'] as Map)['unique_instant_count'], 43);
    final days = data['days'] as List;
    expect(days.length, 7);
    for (var i = 0; i < days.length; i++) {
      expect(jsonEncode(days[i]), jsonEncode(buildDailyConsultDataV4(r.dailyRequestAt(i))), reason: 'Entire daily-v4 record $i');
      final points = days[i]['intraday_forecasts']['points'] as List;
      expect(points.length, 7);
      for (final point in points) {
        final areas = point['nine_area_forecast']['areas'] as List;
        expect(areas.length, 9);
        expect(areas.where((a) => a['score'] is num).length, 8);
        expect(areas.singleWhere((a) => a['key'] == 'felt')['score'], isNull);
      }
      expect(jsonEncode(points[3]['nine_area_forecast']['areas']), jsonEncode(days[i]['nine_area_daily']['areas']));
      if (i > 0) {
        final previous = (days[i - 1]['intraday_forecasts']['points'] as List).last;
        expect(previous['instant_utc'], points.first['instant_utc']);
        expect(jsonEncode(previous['nine_area_forecast']), jsonEncode(points.first['nine_area_forecast']));
      }
    }
    void rejects(void Function(Map<String, dynamic>) damage) {
      final bad = jsonDecode(jsonEncode(data)) as Map<String, dynamic>;
      damage(bad);
      expect(() => WeeklyDailyConsultExportResult.fromData(requestIdentity: r.identity, data: bad), throwsStateError);
    }
    rejects((b) => (b['days'] as List).removeLast());
    rejects((b) => (b['days'] as List)[1] = b['days'][0]);
    rejects((b) => (b['days'][0]['intraday_forecasts']['points'] as List).removeLast());
    rejects((b) => b['timepoint_contract']['fixed_utc_offset'] = '+00:00');
    final root = await Directory.systemTemp.createTemp('pancyo_week_schema_preserve_');
    try {
      final previous = File('${root.path}${Platform.pathSeparator}old_monthly_prediction.json');
      final previousText = '{ "schema": "historical-fixture", "keep": true }\n';
      await previous.writeAsString(previousText, flush: true);
      final output = await ConsultJsonFileWriter.write(
        temporaryRoot: root, data: data, participantName: fixture.subject.name,
        kind: 'week', period: '20261228', generatedAt: r.generatedAt,
      );
      expect(jsonDecode(await output.readAsString()), data);
      expect(await previous.readAsString(), previousText);
      final firstBytes = await output.readAsBytes();
      final second = await ConsultJsonFileWriter.write(
        temporaryRoot: root, data: data, participantName: fixture.subject.name,
        kind: 'week', period: '20261228', generatedAt: r.generatedAt,
      );
      expect(second.path, isNot(output.path));
      expect(await output.readAsBytes(), firstBytes);
      expect(jsonDecode(await second.readAsString()), data);
      expect(await previous.readAsString(), previousText);
    } finally {
      if (!root.absolute.path.startsWith('${Directory.systemTemp.absolute.path}${Platform.pathSeparator}pancyo_week_schema_preserve_')) {
        throw StateError('Refusing cleanup outside the directory created by this test.');
      }
      await root.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
