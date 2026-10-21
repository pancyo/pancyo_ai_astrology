import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pancyo_ai_astrology/main.dart';
const subject = AstroProfile(
  name: 'SevenTimelineDemo',
  birthDate: '1990/1/2',
  birthTime: '08:30',
  birthPlace: '東京都',
  theme: '配置の表示検査',
);

MonthlyDailyConsultExportRequest request(int year, int month) {
  final source = AstrologyDataSources.current;
  return MonthlyDailyConsultExportRequest(
    startDate: DateTime.utc(year, month, 1, 3),
    profile: subject,
    details: const UserProfileDetails.empty(),
    requestedHouseSystem: HouseSystemSettings.current.value,
    sourceName: source.sourceName,
    requireHighPrecision: source.usesHighPrecisionAstroData,
    generatedAt: DateTime.utc(2026, 10, 16, 15),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'calendar months include leap-century rules and year-end JST boundary',
    () {
      for (final row in [
        [2026, 2, 28],
        [2024, 2, 29],
        [1900, 2, 28],
        [2000, 2, 29],
        [2026, 4, 30],
        [2026, 12, 31],
      ]) {
        final r = request(row[0], row[1]);
        expect(r.dayCount, row[2]);
        expect(r.dayPlans.map((p) => p.targetDateJst).toSet().length, row[2]);
        expect(r.listedPointCount, row[2] * 7);
        expect(r.uniqueInstantCount, row[2] * 6 + 1);
        for (var i = 0; i < r.dayCount - 1; i++) {
          expect(
            r.dayPlans[i].points.last.instantUtc,
            r.dayPlans[i + 1].points.first.instantUtc,
          );
          expect(r.dayPlans[i].points.last.isInsideDayInterval, false);
        }
        expect(
          r.dayPlans.first.points.first.instantUtc,
          DateTime.utc(row[0], row[1], 1, -9),
        );
        expect(
          r.dayPlans.last.points.last.instantUtc,
          DateTime.utc(row[0], row[1] + 1, 1, -9),
        );
      }
    },
  );

  test(
    'full month preserves every original daily-v4 record, 8 numbers and categorical felt; corrupt output rejected',
    () async {
      final r = request(2026, 12);
      final progress = <int>[];
      final data = buildMonthlyDailyConsultData(
        r,
        onProgress: (done, total) {
          expect(total, 217);
          progress.add(done);
        },
      );
      expect(progress, List.generate(217, (i) => i + 1));
      expect(data['schema'], 'pancyo_astrology_monthly_daily_consult_v1');
      expect((data['completeness'] as Map)['unique_instant_count'], 187);
      final days = data['days'] as List;
      expect(days.length, 31);
      for (var i = 0; i < 31; i++) {
        final original = buildDailyConsultDataV4(r.dailyRequestAt(i));
        expect(
          jsonEncode(days[i]),
          jsonEncode(original),
          reason: 'daily-v4 $i',
        );
        final points =
            ((days[i] as Map)['intraday_forecasts'] as Map)['points'] as List;
        expect(points.length, 7);
        for (final raw in points) {
          final areas =
              ((raw as Map)['nine_area_forecast'] as Map)['areas'] as List;
          expect(areas.length, 9);
          expect(areas.where((a) => a['score'] is num).length, 8);
          expect(areas.singleWhere((a) => a['key'] == 'felt')['score'], null);
        }
        expect(
          jsonEncode((points[3]['nine_area_forecast'] as Map)['areas']),
          jsonEncode((days[i]['nine_area_daily'] as Map)['areas']),
        );
        if (i > 0) {
          final prev =
              ((days[i - 1]['intraday_forecasts'] as Map)['points'] as List)
                  .last;
          expect(prev['instant_utc'], points.first['instant_utc']);
          expect(
            jsonEncode(prev['nine_area_forecast']),
            jsonEncode(points.first['nine_area_forecast']),
          );
        }
      }
      void rejects(void Function(Map<String, dynamic>) damage) {
        final bad = jsonDecode(jsonEncode(data)) as Map<String, dynamic>;
        damage(bad);
        expect(
          () => MonthlyDailyConsultExportResult.fromData(
            requestIdentity: r.identity,
            data: bad,
          ),
          throwsStateError,
        );
      }

      rejects((b) => (b['days'] as List).removeLast());
      rejects((b) => (b['days'] as List)[1] = b['days'][0]);
      rejects(
        (b) =>
            b['days'][0]['intraday_forecasts']['points'][0]['nine_area_forecast'] =
                null,
      );
      rejects(
        (b) =>
            (b['days'][0]['intraday_forecasts']['points'][0]['nine_area_forecast']['areas']
                    as List)
                .removeLast(),
      );
      rejects(
        (b) => b['days'][0]['intraday_forecasts']['points'][0]['instant_utc'] =
            'bad',
      );
      rejects((b) => b['timepoint_contract']['fixed_utc_offset'] = '+00:00');
      final root = await Directory.systemTemp.createTemp(
        'pancyo_monthly_test_',
      );
      try {
        final file = await MonthlyDailyConsultFileWriter.write(
          temporaryRoot: root,
          data: data,
          participantName: '架空テスト',
          period: '202612',
          isCurrent: () => true,
          generatedAt: r.generatedAt,
        );
        expect(jsonDecode(await file.readAsString()), data);
        expect(file.path.endsWith('.json'), true);
        expect(
          root
              .listSync(recursive: true)
              .whereType<File>()
              .any((f) => f.path.endsWith('.partial')),
          false,
        );
        final old = await file.readAsBytes();
        var checks = 0;
        await expectLater(
          MonthlyDailyConsultFileWriter.write(
            temporaryRoot: root,
            data: data,
            participantName: '架空テスト',
            period: '202612',
            isCurrent: () => ++checks < 3,
          ),
          throwsA(isA<MonthlyDailyConsultExportCancelled>()),
        );
        expect(await file.readAsBytes(), old);
        expect(root.listSync(recursive: true).whereType<File>().length, 1);
      } finally {
        await root.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test('cancel closes worker; a retry starts a distinct worker', () async {
    final r = request(2026, 2);
    final job = MonthlyDailyConsultExportJob.start(r, (_, __) {});
    final result = expectLater(
      job.result,
      throwsA(isA<MonthlyDailyConsultExportCancelled>()),
    );
    job.cancel();
    job.cancel();
    await result;
    final other = MonthlyDailyConsultExportJob.start(r, (_, __) {});
    expect(identical(job, other), false);
    final result2 = expectLater(
      other.result,
      throwsA(isA<MonthlyDailyConsultExportCancelled>()),
    );
    other.cancel();
    await result2;
  });
}
