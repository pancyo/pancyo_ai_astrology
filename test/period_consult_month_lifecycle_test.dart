// Adapted from the prior monthly lifecycle suite for the retained annual route.
// Monthly seven-point lifecycle coverage remains in monthly_daily_consult_export_ui_test.dart.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pancyo_ai_astrology/app_language.dart';
import 'package:pancyo_ai_astrology/app_language_settings.dart';
import 'package:pancyo_ai_astrology/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Job implements PeriodConsultExportOperation {
  final completer = Completer<PeriodConsultExportCalculation>();
  bool cancelled = false;
  @override
  Future<PeriodConsultExportCalculation> get result => completer.future;
  @override
  void cancel() {
    cancelled = true;
  }
}

const _profile = AstroProfile(
  name: 'AnnualFixture',
  birthDate: '1990/1/2',
  birthTime: '12:00',
  birthPlace: '北海道札幌市',
  theme: '仕事',
);
const _path = MethodChannel('plugins.flutter.io/path_provider');
const _share = MethodChannel('dev.fluttercommunity.plus/share');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late HouseSystem original;
  late AppLanguage originalLanguage;
  late PeriodConsultExportStarter starter;
  late List<_Job> jobs;
  late List<PeriodConsultExportRequest> requests;
  late List<File> shared;
  Completer<String>? pathWait, shareWait;
  bool failPath = false, failShare = false;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('pancyo_year_lifecycle_');
    original = HouseSystemSettings.current.value;
    originalLanguage = AppLanguageSettings.current.value;
    AppLanguageSettings.current.value = AppLanguage.ja;
    HouseSystemSettings.current.value = HouseSystem.wholeSign;
    SharedPreferences.setMockInitialValues({'month_preserve': '保持'});
    jobs = [];
    requests = [];
    shared = [];
    pathWait = null;
    shareWait = null;
    failPath = false;
    failShare = false;
    starter = (request) {
      requests.add(request);
      final job = _Job();
      jobs.add(job);
      return job;
    };
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_path, (_) async {
      if (failPath) throw PlatformException(code: 'path_fail');
      return pathWait?.future ?? root.path;
    });
    messenger.setMockMethodCallHandler(_share, (call) async {
      expect(call.method, 'shareFiles');
      final args = call.arguments as Map;
      expect(args['mimeTypes'], ['application/json']);
      final file = File((args['paths'] as List).single as String);
      expect(await file.exists(), true);
      final json = jsonDecode(await file.readAsString()) as Map;
      expect(json['schema'], 'pancyo_astrology_external_consult_v3');
      expect(requests.last.mode, LongRangeMode.year);
      expect(json['nine_area_period']['daily_samples'], hasLength(24));
      shared.add(file);
      if (failShare) throw PlatformException(code: 'share_fail');
      return shareWait?.future ?? '';
    });
  });
  tearDown(() async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_path, null);
    messenger.setMockMethodCallHandler(_share, null);
    expect(
      (await SharedPreferences.getInstance()).getString('month_preserve'),
      '保持',
    );
    HouseSystemSettings.current.value = original;
    AppLanguageSettings.current.value = originalLanguage;
    if (!root.absolute.path.startsWith(
      '${Directory.systemTemp.absolute.path}${Platform.pathSeparator}pancyo_year_lifecycle_',
    )) {
      throw StateError('自分のテスト一時領域以外は削除しない');
    }
    await root.delete(recursive: true);
  });
  Future<void> pump(
    WidgetTester tester, {
    AstroProfile profile = _profile,
    UserProfileDetails details = const UserProfileDetails.empty(),
    int year = 2026,
    bool profilePage = false,
  }) async {
    final selected = DateTime(year, 1, 1, 12);
    final child = profilePage
        ? ProfileAstroJsonExportCard(
            profile: profile,
            details: details,
            startYearJob: starter,
          )
        : ExternalAstroDataExportCard(
            mode: LongRangeMode.year,
            periodLabel: '${selected.year}年',
            weekStart: selected,
            month: selected,
            year: selected.year,
            profile: profile,
            details: details,
            contextData: const AstrologyEngine().buildPreviewContext(
              profile: profile,
              date: selected,
            ),
            cards: const [],
            startJob: starter,
          );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
  }

  Future<void> begin(WidgetTester tester, {bool profilePage = false}) async {
    final finder = find.widgetWithText(
      profilePage ? FilledButton : OutlinedButton,
      profilePage ? 'この年の年運データを作る' : 'JSONを保存',
    );
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  Future<void> flush(WidgetTester tester, {int steps = 8}) async {
    for (var i = 0; i < steps; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 30));
    }
  }

  PeriodConsultExportCalculation calculation(
    PeriodConsultExportRequest request, {
    String? identity,
    bool content = true,
  }) {
    final Map<String, Object?> data;
    if (!content) {
      data = <String, Object?>{};
    } else {
      data = PeriodConsultDataBuilder(
        mode: request.mode,
        periodLabel: request.periodLabel,
        weekStart: request.weekStart,
        month: request.month,
        year: request.year,
        profile: request.profile,
        details: request.details,
        contextData:
            request.contextData ??
            const AstrologyEngine().buildPreviewContext(
              profile: request.profile,
              date: DateTime(request.month.year, request.month.month, 1, 12),
            ),
        cards: request.cards,
      ).buildData(generatedAt: request.generatedAt);
    }
    return PeriodConsultExportCalculation(
      data: data,
      requestIdentity: identity ?? request.identity,
      contextMilliseconds: 0,
      dataMilliseconds: 0,
      cachedContextCount: 0,
      workerName: 'controlled',
    );
  }

  Future<void> complete(
    WidgetTester tester,
    int index, {
    String? identity,
  }) async {
    final expectedShares = shared.length + 1;
    jobs[index].completer.complete(
      calculation(
        requests[index],
        identity: identity,
        content: identity == null,
      ),
    );
    for (
      var i = 0;
      i < 150 &&
          shared.length < expectedShares &&
          find.text('JSONを作成できませんでした。再試行できます。').evaluate().isEmpty;
      i++
    ) {
      await flush(tester, steps: 1);
    }
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<List<FileSystemEntity>> files(WidgetTester tester) async =>
      (await tester.runAsync(() => root.list(recursive: true).toList()))!;

  testWidgets('中止後の遅い結果は0ファイル・0共有、次の年出力は成功', (tester) async {
    await pump(tester);
    await begin(tester);
    expect(jobs, hasLength(1));
    expect(find.text('中止'), findsOneWidget);
    await tester.tap(find.text('中止'));
    await flush(tester);
    expect(jobs.single.cancelled, true);
    jobs.single.completer.complete(
      calculation(requests.single, content: false),
    );
    await flush(tester);
    expect(shared, isEmpty);
    expect(await files(tester), isEmpty);
    await begin(tester);
    await complete(tester, 1);
    expect(shared, hasLength(1));
    expect(tester.takeException(), isNull);
  });
  testWidgets('Profile年JSONは中止後の遅い結果を捨て、年modeで再試行を開始できる', (tester) async {
    await pump(tester, profilePage: true);
    await begin(tester, profilePage: true);
    expect(jobs, hasLength(1));
    expect(requests.single.mode, LongRangeMode.year);
    expect(find.text('中止'), findsOneWidget);
    await tester.tap(find.text('中止'));
    await flush(tester);
    expect(jobs.single.cancelled, true);
    jobs.single.completer.complete(
      calculation(requests.single, content: false),
    );
    await flush(tester);
    expect(shared, isEmpty);
    expect(await files(tester), isEmpty);

    await begin(tester, profilePage: true);
    expect(jobs, hasLength(2));
    expect(requests.last.mode, LongRangeMode.year);
    expect(find.text('中止'), findsOneWidget);
    await tester.tap(find.text('中止'));
    await flush(tester);
    expect(jobs.last.cancelled, true);
    jobs.last.completer.complete(calculation(requests.last, content: false));
    await flush(tester);
    expect(shared, isEmpty);
    expect(await files(tester), isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Profile年ownerは入力更新と画面破棄で古いjobを中止する', (tester) async {
    await pump(tester, profilePage: true);
    await begin(tester, profilePage: true);
    expect(requests.single.mode, LongRangeMode.year);
    await pump(
      tester,
      profilePage: true,
      profile: _profile.copyWith(name: 'UpdatedFixture'),
    );
    await flush(tester);
    expect(jobs.first.cancelled, true);
    jobs.first.completer.complete(calculation(requests.first, content: false));
    await flush(tester);
    expect(shared, isEmpty);
    expect(await files(tester), isEmpty);

    await begin(tester, profilePage: true);
    expect(jobs, hasLength(2));
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('別画面'))),
    );
    await flush(tester);
    expect(jobs.last.cancelled, true);
    jobs.last.completer.complete(calculation(requests.last, content: false));
    await flush(tester);
    expect(shared, isEmpty);
    expect(await files(tester), isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('連打と別入口は重複開始せず、戻るは中止操作へ任せる', (tester) async {
    await pump(tester, profilePage: true);
    final callback = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'この年の年運データを作る'))
        .onPressed!;
    callback();
    callback();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    callback();
    expect(jobs, hasLength(1));
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('中止'), findsOneWidget);
    await tester.tap(find.text('中止'));
    await flush(tester);
    callback();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(jobs, hasLength(2));
    await tester.tap(find.text('中止'));
    await flush(tester);
    expect(await files(tester), isEmpty);
  });
  testWidgets('同じ年でも別人物identityは拒否し、同じ画面の再試行で復帰', (tester) async {
    await pump(tester);
    await begin(tester);
    await complete(tester, 0, identity: 'wrong-person');
    expect(shared, isEmpty);
    expect(await files(tester), isEmpty);
    expect(find.text('再試行'), findsOneWidget);
    await tester.tap(find.text('再試行'));
    await tester.pump();
    expect(jobs, hasLength(2));
    await complete(tester, 1);
    expect(shared, hasLength(1));
  });
  for (final change in ['人物', '補足', '対象年', 'ハウス方式']) {
    testWidgets('$change変更で中止し、古い結果は出力しない', (tester) async {
      await pump(tester);
      await begin(tester);
      switch (change) {
        case '人物':
          await pump(tester, profile: _profile.copyWith(name: '別の架空人物'));
        case '補足':
          await pump(
            tester,
            details: const UserProfileDetails(
              birthTime: '',
              birthPlace: '',
              personality: '',
              concerns: '架空の相談',
              readingStyle: '',
            ),
          );
        case '対象年':
          await pump(tester, year: 2027);
        case 'ハウス方式':
          HouseSystemSettings.current.value = HouseSystem.placidus;
          await tester.pump();
      }
      await flush(tester);
      expect(jobs.single.cancelled, true);
      jobs.single.completer.complete(
        calculation(requests.single, content: false),
      );
      await flush(tester);
      expect(shared, isEmpty);
      expect(await files(tester), isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('一時領域の取得待ちで中止した後に書き込まない', (tester) async {
    pathWait = Completer<String>();
    await pump(tester);
    await begin(tester);
    jobs.single.completer.complete(calculation(requests.single));
    await flush(tester);
    await tester.tap(find.text('中止'));
    await flush(tester);
    pathWait!.complete(root.path);
    await flush(tester);
    expect(shared, isEmpty);
    expect(await files(tester), isEmpty);
  });
  testWidgets('書込準備失敗から再試行し、共有例外後も再出力できる', (tester) async {
    failPath = true;
    await pump(tester);
    await begin(tester);
    await complete(tester, 0);
    expect(find.text('再試行'), findsOneWidget);
    expect(shared, isEmpty);
    failPath = false;
    failShare = true;
    await tester.tap(find.text('再試行'));
    await tester.pump();
    await complete(tester, 1);
    await flush(tester);
    expect(shared, hasLength(1));
    final before = (await tester.runAsync(shared.single.readAsBytes))!;
    expect(find.text('JSON出力に失敗しました。もう一度お試しください。'), findsOneWidget);
    failShare = false;
    await begin(tester);
    await complete(tester, 2);
    await flush(tester);
    expect(shared, hasLength(2));
    expect(shared.last.path, isNot(shared.first.path));
    expect(await tester.runAsync(shared.first.readAsBytes), before);
  });
  testWidgets('通常プロフィールの共有待ちは二重開始しない、破棄で次画面へ解放', (tester) async {
    shareWait = Completer<String>();
    await pump(tester, profilePage: true);
    await begin(tester, profilePage: true);
    await complete(tester, 0);
    await flush(tester);
    expect(shared, hasLength(1));
    final callback = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'この年の年運データを作る'))
        .onPressed!;
    callback();
    await tester.pump();
    expect(jobs, hasLength(1));
    final oldShare = shareWait!;
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('別の画面'))),
    );
    await flush(tester);
    shareWait = null;
    await pump(tester, profilePage: true);
    await begin(tester, profilePage: true);
    expect(jobs, hasLength(2));
    oldShare.completeError(PlatformException(code: 'late_share_failure'));
    await flush(tester);
    expect(find.textContaining('JSON出力に失敗しました'), findsNothing);
    final nextCallback = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'この年の年運データを作る'))
        .onPressed!;
    nextCallback();
    await tester.pump();
    expect(jobs, hasLength(2));
    await complete(tester, 1);
    await flush(tester);
    expect(shared, hasLength(2));
    expect(tester.takeException(), isNull);
  });
  testWidgets('計算中と失敗後の言語切替は年入力を保ち、再試行中止後の遅い結果を共有しない', (tester) async {
    await pump(tester);
    await begin(tester);
    final originalRequest = requests.single;
    final originalIdentity = originalRequest.identity;
    AppLanguageSettings.current.value = AppLanguage.en;
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      find.text('Create annual reading data for this year'),
      findsOneWidget,
    );
    expect(jobs, hasLength(1));
    expect(identical(requests.single, originalRequest), true);
    expect(requests.single.identity, originalIdentity);

    jobs.single.completer.completeError(
      StateError('artificial-language-failure'),
    );
    await flush(tester, steps: 2);
    expect(
      find.text('Could not create the JSON. You can try again.'),
      findsOneWidget,
    );
    AppLanguageSettings.current.value = AppLanguage.ja;
    await tester.pump();
    expect(find.text('JSONを作成できませんでした。再試行できます。'), findsOneWidget);
    expect(jobs, hasLength(1));
    await tester.tap(find.text('再試行'));
    await tester.pump();
    expect(jobs, hasLength(2));
    AppLanguageSettings.current.value = AppLanguage.en;
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(jobs.last.cancelled, true);
    jobs.last.completer.complete(calculation(requests.last, content: false));
    await flush(tester, steps: 2);
    expect(shared, isEmpty);
    expect(await files(tester), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('画面破棄でjob中止・遅い完了抑止・新画面で再出力', (tester) async {
    await pump(tester);
    await begin(tester);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('破棄'))),
    );
    await flush(tester);
    expect(jobs.single.cancelled, true);
    jobs.single.completer.complete(
      calculation(requests.single, content: false),
    );
    await flush(tester);
    await pump(tester);
    await begin(tester);
    expect(jobs, hasLength(2));
    await tester.tap(find.text('中止'));
    await flush(tester);
    expect(shared, isEmpty);
    expect(await files(tester), isEmpty);
  });
}
