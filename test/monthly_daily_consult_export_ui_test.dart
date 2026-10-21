import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pancyo_ai_astrology/app_language.dart';
import 'package:pancyo_ai_astrology/app_language_settings.dart';
import 'package:pancyo_ai_astrology/main.dart';
import 'monthly_daily_consult_export_test.dart' as f;

class ControlledMonth implements MonthlyDailyConsultExportOperation {
  final completer = Completer<MonthlyDailyConsultExportResult>();
  bool cancelled = false;
  @override
  Future<MonthlyDailyConsultExportResult> get result => completer.future;
  @override
  void cancel() {
    cancelled = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late List<ControlledMonth> jobs;
  late List<MonthlyDailyConsultExportRequest> requests;
  late void Function(int, int) progress;
  late List<File> shared;
  late MonthlyDailyConsultExportStarter starter;
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
  setUp(() async {
    root = await Directory.systemTemp.createTemp('pancyo_month_ui_');
    AppLanguageSettings.current.value = AppLanguage.ja;
    jobs = [];
    requests = [];
    shared = [];
    starter = (r, p) {
      requests.add(r);
      progress = p;
      final j = ControlledMonth();
      jobs.add(j);
      return j;
    };
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(pathChannel, (_) async => root.path);
    messenger.setMockMethodCallHandler(shareChannel, (call) async {
      final file = File(
        ((call.arguments as Map)['paths'] as List).single as String,
      );
      expect(file.existsSync(), true);
      expect(file.path.endsWith('.json'), true);
      expect(
        jsonDecode(file.readAsStringSync())['completeness']['status'],
        'complete',
      );
      shared.add(file);
      return 'dev.fluttercommunity.plus/share/unavailable';
    });
  });
  tearDown(() async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(pathChannel, null);
    messenger.setMockMethodCallHandler(shareChannel, null);
    await root.delete(recursive: true);
  });
  Future<void> pumpProfile(WidgetTester t, {AstroProfile? profile}) async {
    await t.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: AppLanguageScope(
          child: Scaffold(
            body: SingleChildScrollView(
              child: ProfileAstroJsonExportCard(
                profile: profile ?? f.subject,
                details: const UserProfileDetails.empty(),
                startMonthlyDailyJob: starter,
              ),
            ),
          ),
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 200));
  }

  Future<void> begin(WidgetTester t) async {
    final b = find.byKey(const ValueKey('consult-json-month-seven'));
    await t.ensureVisible(b);
    await t.tap(b);
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
  }

  Future<void> flush(WidgetTester t) async {
    for (var i = 0; i < 12; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await t.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets(
    'preflight precedes work; measured progress and estimate; cancel produces no file',
    (t) async {
      await pumpProfile(t);
      await begin(t);
      expect(find.textContaining('計算には時間がかかります'), findsOneWidget);
      expect(jobs, isEmpty);
      await t.tap(find.text('開始'));
      await t.pump();
      expect(jobs.length, 1);
      progress(7, requests.single.listedPointCount);
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1100)));
      await t.pump(const Duration(seconds: 1));
      expect(find.textContaining('推定残り計算：約'), findsOneWidget);
      expect(
        find.textContaining('7/${requests.single.listedPointCount}時点'),
        findsOneWidget,
      );
      await t.tap(find.text('中止'));
      await t.pump();
      await flush(t);
      expect(jobs.single.cancelled, true);
      expect(root.listSync(recursive: true), isEmpty);
      expect(shared, isEmpty);
      jobs.single.completer.completeError(
        const MonthlyDailyConsultExportCancelled(),
      );
      await t.pump();
      expect(t.takeException(), null);
    },
  );
  testWidgets(
    'profile invalidation cancels work; stale completion never shared',
    (t) async {
      await pumpProfile(t);
      await begin(t);
      await t.tap(find.text('開始'));
      await t.pump();
      await pumpProfile(
        t,
        profile: f.subject.copyWith(name: 'Changed fictional profile'),
      );
      await flush(t);
      expect(jobs.single.cancelled, true);
      jobs.single.completer.completeError(
        const MonthlyDailyConsultExportCancelled(),
      );
      await t.pump();
      expect(shared, isEmpty);
      expect(t.takeException(), null);
    },
  );
  testWidgets(
    'failed month can retry; only validated complete month shared',
    (t) async {
      await pumpProfile(t);
      await begin(t);
      await t.tap(find.text('開始'));
      await t.pump();
      jobs.single.completer.completeError(StateError('synthetic failure'));
      await t.pump();
      expect(find.text('再試行'), findsOneWidget);
      expect(shared, isEmpty);
      await t.tap(find.text('再試行'));
      await t.pump();
      expect(jobs.length, 2);
      final data = buildMonthlyDailyConsultData(requests.last);
      jobs.last.completer.complete(
        MonthlyDailyConsultExportResult.fromData(
          requestIdentity: requests.last.identity,
          data: data,
        ),
      );
      for (var i = 0; i < 60 && shared.isEmpty; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
        await t.pump(const Duration(milliseconds: 100));
      }
      await flush(t);
      expect(shared.length, 1);
      expect(t.takeException(), null);
      // Cancel during asynchronous save/readback. The first completed output
      // must survive, and the new private staging folder must be discarded.
      final originalBytes = await t.runAsync(shared.single.readAsBytes);
      await begin(t);
      await t.tap(find.text('開始'));
      await t.pump();
      final nextData = jsonDecode(jsonEncode(data)) as Map<String, dynamic>;
      final issued = requests.last.generatedAt.toIso8601String();
      nextData['generated_at'] = issued;
      for (final day in nextData['days'] as List) { day['generated_at'] = issued; }
      jobs.last.completer.complete(MonthlyDailyConsultExportResult.fromData(
        requestIdentity: requests.last.identity, data: nextData));
      await t.pump();
      for (var i=0;i<80;i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds:100)));
        await t.pump(const Duration(milliseconds:100));
        if (root.listSync().length > 1) break;
      }
      expect(find.text('中止'), findsOneWidget);
      await t.tap(find.text('中止'));
      await t.pump();
      for (var i=0;i<80 && root.listSync().length>1;i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds:100)));
        await t.pump(const Duration(milliseconds:100));
      }
      await flush(t);
      expect(shared.length, 1);
      expect(root.listSync().length, 1);
      expect(await t.runAsync(shared.single.readAsBytes), originalBytes);
      expect(t.takeException(), null);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
