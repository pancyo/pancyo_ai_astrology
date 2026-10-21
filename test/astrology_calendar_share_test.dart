import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pancyo_ai_astrology/daily_seven_timepoint_plan.dart';
import 'package:pancyo_ai_astrology/main.dart';
import 'package:share_plus/share_plus.dart';

// All fixtures in this file are synthetic UI/boundary cases. They are not
// ephemeris observations and must not be delivered as actual sky predictions.
AstrologyCalendarDay dayFixture(
  String date, {
  ZodiacSign? moon = ZodiacSign.aries,
  List<AstrologyCalendarEvent> events = const [],
}) => AstrologyCalendarDay(
  targetDateJst: date,
  events: events,
  providerName: 'SYNTHETIC TEST DATA',
  precisionNotice: '試験用データ・実際の天文計算ではありません。',
  usesHighPrecisionAstroData: false,
  moonSignAtNoon: moon,
);

List<AstrologyCalendarDay> monthFixture(int year, int month) => [
  for (var day = 1; day <= DateTime.utc(year, month + 1, 0).day; day++)
    dayFixture(
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}',
    ),
];

List<AstrologyCalendarDay> variedMonthFixture() {
  final days = monthFixture(2026, 8);
  days[0] = dayFixture(
    '2026-08-01',
    events: [
      voidFixture('2026-08-01', -4, 3),
      voidFixture('2026-08-01', 20, 27),
    ],
  );
  days[1] = dayFixture(
    '2026-08-02',
    events: [voidFixture('2026-08-02', -5, 28)],
  );
  final plan = DailySevenTimepointPlan.forJstDate('2026-08-03');
  days[2] = dayFixture(
    '2026-08-03',
    events: [
      AstrologyCalendarEvent(
        kind: AstrologyCalendarEventKind.signIngress,
        title: '月が牡牛座へ移動',
        detail: '星座の移動',
        ingressPlanet: AstroPlanet.moon,
        fromSign: ZodiacSign.aries,
        toSign: ZodiacSign.taurus,
        startUtc: plan.dayStartUtc.add(const Duration(hours: 7)),
      ),
      AstrologyCalendarEvent(
        kind: AstrologyCalendarEventKind.majorLunarPhase,
        title: '新月',
        detail: '試験用',
        startUtc: plan.dayStartUtc.add(const Duration(hours: 8)),
      ),
      AstrologyCalendarEvent(
        kind: AstrologyCalendarEventKind.retrogradeStation,
        title: '水星が逆行開始（留）',
        detail: '試験用',
        startUtc: plan.dayStartUtc.add(const Duration(hours: 9)),
      ),
      for (var index = 0; index < 5; index++)
        AstrologyCalendarEvent(
          kind: AstrologyCalendarEventKind.specialConfiguration,
          title: 'グランドトライン（太陽・月・木星）',
          detail: '試験用配置$index',
          snapshotUtc: plan.primaryNoon.instantUtc,
        ),
    ],
  );
  days[30] = dayFixture(
    '2026-08-31',
    events: [voidFixture('2026-08-31', -2, 26)],
  );
  return days;
}

AstrologyCalendarEvent voidFixture(String date, int startHour, int endHour) {
  final plan = DailySevenTimepointPlan.forJstDate(date);
  final start = plan.dayStartUtc.add(Duration(hours: startHour));
  final end = plan.dayStartUtc.add(Duration(hours: endHour));
  return AstrologyCalendarEvent(
    kind: AstrologyCalendarEventKind.voidMoon,
    title: '月ボイド',
    detail: '試験用区間',
    startUtc: start,
    endUtc: end,
    overlapStartUtc: start.isAfter(plan.dayStartUtc) ? start : plan.dayStartUtc,
    overlapEndUtc: end.isBefore(plan.dayEndUtc) ? end : plan.dayEndUtc,
    continuesFromPreviousDay: startHour < 0,
    continuesIntoNextDay: endHour > 24,
  );
}

Future<Uint8List> smallTestPng() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 1680, 2),
    Paint()..color = Colors.indigo,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(1680, 2);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (Platform.environment['PANCYO_CALENDAR_CAPTURE_ROOT'] != null) {
      final font = File(r'C:\Windows\Fonts\meiryo.ttc');
      if (await font.exists()) {
        final bytes = await font.readAsBytes();
        for (final family in ['CalendarVisualTest']) {
          await (FontLoader(
            family,
          )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
        }
      }
    }
  });

  test(
    'complete leap month freezes and sorts all days without mutable aliases',
    () {
      final days = monthFixture(2028, 2).reversed.toList();
      final data = AstrologyCalendarShareData.checked(
        year: 2028,
        month: 2,
        days: days,
      );
      expect(data.days.length, 29);
      expect(data.days.first.targetDateJst, '2028-02-01');
      expect(data.days.last.targetDateJst, '2028-02-29');
      expect(identical(data.days.first, days.last), isFalse);
      days.clear();
      expect(data.days.length, 29);
      expect(() => data.days.clear(), throwsUnsupportedError);
    },
  );

  test(
    'missing, duplicate, foreign-month, missing-Moon and incomplete ingress reject',
    () {
      final days = monthFixture(2026, 10);
      void reject(List<AstrologyCalendarDay> candidates) => expect(
        () => AstrologyCalendarShareData.checked(
          year: 2026,
          month: 10,
          days: candidates,
        ),
        throwsFormatException,
      );
      reject(days.take(30).toList());
      reject([...days.take(30), days.first]);
      reject([...days.take(30), dayFixture('2026-11-01')]);
      reject([...days.take(30), dayFixture('2026-10-31', moon: null)]);
      reject([
        ...days.take(30),
        dayFixture(
          '2026-10-31',
          events: [
            AstrologyCalendarEvent(
              kind: AstrologyCalendarEventKind.signIngress,
              title: '月が牡牛座へ移動',
              detail: '試験用',
              startUtc: DateTime.utc(2026, 10, 31),
            ),
          ],
        ),
      ]);
    },
  );

  test('bad event date, duplicate event and bad void clipping reject', () {
    final days = monthFixture(2026, 10);
    final event = AstrologyCalendarEvent(
      kind: AstrologyCalendarEventKind.majorLunarPhase,
      title: '新月',
      detail: '試験用',
      startUtc: DateTime.utc(2026, 10, 30, 15),
    );
    final badVoid = AstrologyCalendarEvent(
      kind: AstrologyCalendarEventKind.voidMoon,
      title: '月ボイド',
      detail: '試験用',
      startUtc: DateTime.utc(2026, 10, 30, 15),
      endUtc: DateTime.utc(2026, 10, 30, 18),
    );
    for (final events in [
      [event, event],
      [badVoid],
      [
        AstrologyCalendarEvent(
          kind: AstrologyCalendarEventKind.majorLunarPhase,
          title: '新月',
          detail: '試験用',
          startUtc: DateTime.utc(2026, 10, 31, 15),
        ),
      ],
    ]) {
      expect(
        () => AstrologyCalendarShareData.checked(
          year: 2026,
          month: 10,
          days: [
            ...days.take(30),
            dayFixture('2026-10-31', events: events),
          ],
        ),
        throwsFormatException,
      );
    }
  });

  test(
    'month and weekly partitions contain each calendar day exactly once',
    () {
      for (final period in [(2026, 2), (2026, 8), (2026, 12), (2027, 1)]) {
        final data = AstrologyCalendarShareData.checked(
          year: period.$1,
          month: period.$2,
          days: monthFixture(period.$1, period.$2),
        );
        final partition = [
          for (var week = 0; week < data.weekCount; week++)
            ...data.daysInWeek(week),
        ];
        expect(
          partition.map((day) => day.targetDateJst),
          data.days.map((day) => day.targetDateJst),
        );
        expect(
          partition.map((day) => day.targetDateJst).toSet().length,
          data.days.length,
        );
      }
    },
  );

  test(
    'complete text retains both void periods, boundary and all supplemental events',
    () {
      final days = monthFixture(2026, 10);
      final plan = DailySevenTimepointPlan.forJstDate('2026-10-31');
      final extras = [
        for (var index = 0; index < 10; index++)
          AstrologyCalendarEvent(
            kind: AstrologyCalendarEventKind.specialConfiguration,
            title: '試験配置$index',
            detail: '試験根拠$index',
            snapshotUtc: plan.primaryNoon.instantUtc,
          ),
      ];
      days[30] = dayFixture(
        '2026-10-31',
        events: [
          voidFixture('2026-10-31', -3, 2),
          voidFixture('2026-10-31', 20, 27),
          ...extras,
        ],
      );
      final data = AstrologyCalendarShareData.checked(
        year: 2026,
        month: 10,
        days: days,
      );
      final text = astrologyCalendarShareDetails(data, english: false);
      expect(text, contains('前日'));
      expect(text, contains('翌日'));
      expect(text, contains('試験根拠9'));
      expect(text, contains('2026-11-01T03:00:00.000+09:00'));
      expect(text, contains('正午'));
      expect(text, isNot(contains('participant')));
    },
  );

  testWidgets('full grid paints six weeks offscreen including final day', (
    tester,
  ) async {
    final days = variedMonthFixture();
    final data = AstrologyCalendarShareData.checked(
      year: 2026,
      month: 8,
      days: days,
    );
    expect(data.weekCount, 6);
    await tester.pumpWidget(
      MaterialApp(
        home: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            child: AstrologyCalendarShareImage(data: data, english: false),
          ),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('calendar-export-day-2026-08-31')),
      findsOneWidget,
    );
    expect(find.byType(AstrologyCalendarDayContent), findsNWidgets(31));
    expect(find.text('月：牡羊座 → 牡牛座 07:00'), findsOneWidget);
    expect(find.text('前日〜03:00'), findsOneWidget);
    expect(find.text('20:00〜翌日'), findsOneWidget);
    expect(find.text('終日'), findsNWidgets(2));
    expect(find.text('ほか5件・詳細へ'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final png = await tester.runAsync(
      () => captureAstrologyCalendarImage(
        tester.view,
        AstrologyCalendarShareImage(
          data: data,
          english: false,
          fontFamily:
              Platform.environment['PANCYO_CALENDAR_CAPTURE_ROOT'] == null
              ? null
              : 'CalendarVisualTest',
        ),
      ),
    );
    expect(png, isNotNull);
    await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(png!);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 1680);
      expect(frame.image.height, greaterThan(700));
      frame.image.dispose();
      codec.dispose();
      final captureRoot = Platform.environment['PANCYO_CALENDAR_CAPTURE_ROOT'];
      if (captureRoot != null) {
        await Directory(captureRoot).create(recursive: true);
        await File(
          '$captureRoot${Platform.pathSeparator}synthetic-calendar-six-weeks.png',
        ).writeAsBytes(png, flush: true);
      }
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'PNG writer reads back all weekly files and keeps prior exports',
    (tester) async {
      await tester.runAsync(() async {
        final root = await Directory.systemTemp.createTemp(
          'calendar_share_test_',
        );
        try {
          final data = AstrologyCalendarShareData.checked(
            year: 2026,
            month: 8,
            days: monthFixture(2026, 8),
          );
          final png = await smallTestPng();
          final renderedWeeks = <int?>[];
          final first = await saveAstrologyCalendarExport(
            documentsRoot: root,
            data: data,
            english: false,
            splitWeeks: true,
            render: (week) async {
              renderedWeeks.add(week);
              return png;
            },
          );
          expect(renderedWeeks, [0, 1, 2, 3, 4, 5]);
          expect(first.images.length, 6);
          expect(first.shareFiles.length, 6);
          expect(first.detailsShareFile.mimeType, 'text/plain');
          final manifest =
              jsonDecode(await first.manifest.readAsString()) as Map;
          expect(manifest['day_count'], 31);
          expect((manifest['files_sha256'] as Map).length, 7);
          expect(await first.details.readAsString(), contains('2026-08-31'));
          final second = await saveAstrologyCalendarExport(
            documentsRoot: root,
            data: data,
            english: true,
            splitWeeks: false,
            render: (week) async {
              expect(week, isNull);
              return png;
            },
          );
          expect(second.directory.path, isNot(first.directory.path));
          expect(await first.images.last.exists(), isTrue);
          expect(await second.images.single.readAsBytes(), png);
          await expectLater(
            saveAstrologyCalendarExport(
              documentsRoot: root,
              data: data,
              english: false,
              splitWeeks: false,
              render: (_) async => Uint8List.fromList([1, 2, 3]),
            ),
            throwsFormatException,
          );
        } finally {
          await root.delete(recursive: true);
        }
      });
    },
  );

  test(
    'share outcomes distinguish cancellation, accepted recipient and unknown result',
    () {
      expect(
        astrologyCalendarShareOutcome(
          ShareResultStatus.dismissed,
          english: false,
        ),
        contains('取り消し'),
      );
      expect(
        astrologyCalendarShareOutcome(
          ShareResultStatus.success,
          english: false,
        ),
        contains('共有先で確認'),
      );
      expect(
        astrologyCalendarShareOutcome(
          ShareResultStatus.unavailable,
          english: false,
        ),
        contains('確認できません'),
      );
    },
  );

  testWidgets(
    'sheet saves real files, shares PNG alone, preserves cancel and retries failure',
    (tester) async {
      late Directory root;
      late Uint8List png;
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp('calendar_share_sheet_');
        png = await smallTestPng();
      });
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
      const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
      final shared = <List<String>>[];
      var renderCount = 0;
      var failShare = false;
      var shareReply = '';
      messenger.setMockMethodCallHandler(pathChannel, (_) async => root.path);
      messenger.setMockMethodCallHandler(shareChannel, (call) async {
        expect(call.method, 'shareFiles');
        final args = call.arguments as Map;
        final paths = (args['paths'] as List).cast<String>();
        final mimes = (args['mimeTypes'] as List).cast<String>();
        expect(paths.every((path) => File(path).existsSync()), isTrue);
        expect(
          mimes.toSet().length,
          1,
          reason: 'Do not mix text and images in Android share intents.',
        );
        shared.add(paths);
        if (failShare) throw PlatformException(code: 'synthetic-share-failure');
        return shareReply;
      });
      try {
        final data = AstrologyCalendarShareData.checked(
          year: 2026,
          month: 8,
          days: variedMonthFixture(),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AstrologyCalendarShareSheet(
                data: data,
                english: false,
                renderImage: (_) async {
                  renderCount++;
                  return png;
                },
              ),
            ),
          ),
        );
        Future<void> clickAndWait(String label, int expectedCalls) async {
          await tester.ensureVisible(find.text(label));
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            await tester.tap(find.text(label));
            for (
              var index = 0;
              index < 200 && shared.length < expectedCalls;
              index++
            ) {
              await Future<void>.delayed(const Duration(milliseconds: 10));
            }
          });
          await tester.pumpAndSettle();
          expect(shared.length, expectedCalls);
        }

        await clickAndWait('保存して共有', 1);
        expect(shared.first.single, endsWith('.png'));
        expect(find.textContaining('取り消しました'), findsOneWidget);
        expect(renderCount, 1);
        failShare = true;
        await clickAndWait('保存して共有', 2);
        expect(find.textContaining('共有に失敗'), findsOneWidget);
        expect(shared[1], shared.first);
        failShare = false;
        shareReply = 'synthetic.recipient';
        await clickAndWait('保存して共有', 3);
        expect(find.textContaining('共有先を選びました'), findsOneWidget);
        expect(
          renderCount,
          1,
          reason: 'Retry uses the same successfully saved files.',
        );
        shareReply = 'dev.fluttercommunity.plus/share/unavailable';
        await clickAndWait('補足一覧を共有', 4);
        expect(shared.last.single, endsWith('_events.txt'));
        expect(find.textContaining('共有結果は確認できません'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        messenger.setMockMethodCallHandler(pathChannel, null);
        messenger.setMockMethodCallHandler(shareChannel, null);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() => root.delete(recursive: true));
      }
    },
  );

  test(
    'Android calendar cache rejects mixed MIME, too many, duplicates and wrong suffix',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'calendar_android_args_',
      );
      try {
        final png = XFile('${root.path}/test.png', mimeType: 'image/png');
        final txt = XFile('${root.path}/events.txt', mimeType: 'text/plain');
        final cases = <List<XFile>>[
          [],
          [png, txt],
          [png, png],
          [txt, txt],
          [XFile('${root.path}/wrong.txt', mimeType: 'image/png')],
          [
            for (var index = 0; index < 7; index++)
              XFile('${root.path}/$index.png', mimeType: 'image/png'),
          ],
        ];
        for (final files in cases) {
          await expectLater(
            prepareAstrologyCalendarShareCache(
              temporaryRoot: root,
              files: files,
            ),
            throwsFormatException,
          );
        }
        expect(
          await Directory('${root.path}/calendar_exports').exists(),
          isFalse,
        );
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'Android compatibility route copies and reads back six PNGs and one separate TXT',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'calendar_android_route_',
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const compat = MethodChannel('com.pancyo.aiastrology/share_compat');
      const legacy = MethodChannel('dev.fluttercommunity.plus/share');
      var legacyCalls = 0;
      final calls = <Map>[];
      messenger.setMockMethodCallHandler(legacy, (_) async {
        legacyCalls++;
        return '';
      });
      messenger.setMockMethodCallHandler(compat, (call) async {
        expect(call.method, 'shareCalendarFiles');
        final args = call.arguments as Map;
        final paths = (args['paths'] as List).cast<String>();
        expect(paths.toSet().length, paths.length);
        for (final path in paths) {
          expect(
            path,
            contains('calendar_exports${Platform.pathSeparator}calendar_'),
          );
          expect(await File(path).exists(), isTrue);
        }
        calls.add(args);
        return true;
      });
      try {
        final bytes = Uint8List.fromList([
          137,
          80,
          78,
          71,
          13,
          10,
          26,
          10,
          1,
          2,
          3,
        ]);
        final sources = <XFile>[];
        for (var index = 0; index < 6; index++) {
          final file = File(
            '${root.path}${Platform.pathSeparator}source_$index.png',
          );
          await file.writeAsBytes(bytes, flush: true);
          sources.add(XFile(file.path, mimeType: 'image/png'));
        }
        expect(
          await launchAstrologyCalendarShareFiles(
            sources,
            useAndroidCompatibility: true,
            temporaryRoot: root,
          ),
          isNull,
        );
        expect(calls.single['mimeType'], 'image/png');
        expect((calls.single['paths'] as List).length, 6);
        for (final path in calls.single['paths'] as List) {
          expect(await File(path as String).readAsBytes(), bytes);
        }
        final txt = File('${root.path}${Platform.pathSeparator}events.txt');
        await txt.writeAsString('試験用の一般天文イベント一覧', flush: true);
        expect(
          await launchAstrologyCalendarShareFiles(
            [XFile(txt.path, mimeType: 'text/plain')],
            useAndroidCompatibility: true,
            temporaryRoot: root,
          ),
          isNull,
        );
        expect(calls.last['mimeType'], 'text/plain');
        expect((calls.last['paths'] as List).length, 1);
        expect(
          await File(
            (calls.last['paths'] as List).single as String,
          ).readAsString(),
          await txt.readAsString(),
        );
        expect(legacyCalls, 0);
        expect(
          astrologyCalendarShareOutcome(null, english: false),
          contains('共有メニューへ渡しました'),
        );
        expect(
          astrologyCalendarShareOutcome(null, english: false),
          isNot(contains('取り消しました')),
        );
        expect(await File(sources.first.path).exists(), isTrue);
      } finally {
        messenger.setMockMethodCallHandler(compat, null);
        messenger.setMockMethodCallHandler(legacy, null);
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'Android compatibility errors never fall back and can retry existing export',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'calendar_android_fail_',
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const compat = MethodChannel('com.pancyo.aiastrology/share_compat');
      const legacy = MethodChannel('dev.fluttercommunity.plus/share');
      var legacyCalls = 0;
      var attempt = 0;
      messenger.setMockMethodCallHandler(legacy, (_) async {
        legacyCalls++;
        return '';
      });
      messenger.setMockMethodCallHandler(compat, (_) async {
        attempt++;
        if (attempt == 1) return false;
        if (attempt == 2)
          throw PlatformException(code: 'synthetic-compat-failure');
        return true;
      });
      try {
        final file = File('${root.path}${Platform.pathSeparator}events.txt');
        await file.writeAsString('試験用イベント', flush: true);
        Future<ShareResultStatus?> share() => launchAstrologyCalendarShareFiles(
          [XFile(file.path, mimeType: 'text/plain')],
          useAndroidCompatibility: true,
          temporaryRoot: root,
        );
        await expectLater(share(), throwsStateError);
        await expectLater(share(), throwsA(isA<PlatformException>()));
        expect(await share(), isNull);
        expect(attempt, 3);
        expect(legacyCalls, 0);
        expect(await file.readAsString(), '試験用イベント');
        final subdirs = await Directory(
          '${root.path}${Platform.pathSeparator}calendar_exports',
        ).list().toList();
        expect(
          subdirs.length,
          3,
          reason: 'Each retry gets a new cache directory.',
        );
      } finally {
        messenger.setMockMethodCallHandler(compat, null);
        messenger.setMockMethodCallHandler(legacy, null);
        await root.delete(recursive: true);
      }
    },
  );
}
