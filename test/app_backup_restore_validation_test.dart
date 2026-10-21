import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pancyo_ai_astrology/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _profile = AstroProfile(
  name: '架空の復元確認',
  birthDate: '1990/1/2',
  birthTime: '12:00',
  birthPlace: '北海道札幌市',
  theme: '今日の流れ',
);
const _booleanKeys = {
  'profile.useSupplement',
  'share_card_show_score',
  'share_card_show_body',
};
final _saved = SavedUserProfile(
  id: 'fictional-existing',
  name: _profile.name,
  birthDate: _profile.birthDate,
  details: const UserProfileDetails.empty(),
  updatedAt: DateTime.utc(2026, 9, 29),
).toJson();
final _seed = <String, Object>{
  'saved_profiles.list': jsonEncode([_saved]),
  'profile.birthTime': '08:30',
  'profile.birthPlace': '東京都',
  'profile.personality': '架空の性格',
  'profile.concerns': '架空のテーマ',
  'profile.readingStyle': '架空の文体',
  'profile.useSupplement': false,
  'share_card_display_name': '架空の共有名',
  'share_card_show_score': false,
  'share_card_show_body': true,
  'share_card_theme': 'night',
  'astrology.house_system': 'wholeSign',
  'unrelated.preference': '保持',
  'app.text_scale': 1.15,
};

String _backup(Map<String, Object?> values) => jsonEncode({
  'format': 'pancyo-astrology-backup',
  'version': 1,
  'values': values,
});

Future<Map<String, Object?>> _snapshot() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  return {for (final key in prefs.getKeys()) key: prefs.get(key)};
}

Future<void> _rejectUnchanged(String source) async {
  final before = await _snapshot();
  Object? failure;
  try {
    await AppDataBackup.restoreJson(source);
  } catch (error) {
    failure = error;
  }
  expect(await _snapshot(), before, reason: '復元前の検査失敗で現在の設定を変えない');
  expect(failure, isA<FormatException>());
  expect(HouseSystemSettings.current.value, HouseSystem.wholeSign);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final originalHouseSystem = HouseSystemSettings.current.value;
  setUp(() {
    SharedPreferences.setMockInitialValues(_seed);
    HouseSystemSettings.current.value = HouseSystem.wholeSign;
  });
  tearDown(() => HouseSystemSettings.current.value = originalHouseSystem);

  for (final key in _seed.keys.where(
    (key) => key != 'unrelated.preference' && key != 'app.text_scale',
  )) {
    test('不正な $key は全項目を書き換える前に拒否する', () async {
      await _rejectUnchanged(
        _backup({
          'profile.birthPlace': '大阪府',
          key: _booleanKeys.contains(key) ? 'false' : ['壊れた型'],
        }),
      );
    });
  }

  test('JSON破損・別形式・不正なvaluesを復元前に拒否する', () async {
    for (final source in [
      '{',
      '[]',
      'null',
      jsonEncode({'format': 'other', 'values': {}}),
      jsonEncode({'format': 'pancyo-astrology-backup', 'values': []}),
      jsonEncode({'format': 'pancyo-astrology-backup'}),
    ]) {
      await _rejectUnchanged(source);
    }
  });

  test('未対応版や不正な版表記を現在データの置換前に拒否する', () async {
    for (final version in <Object?>[0, 2, '1', 1.0, null]) {
      await _rejectUnchanged(
        jsonEncode({
          'format': 'pancyo-astrology-backup',
          'version': version,
          'values': {'profile.birthPlace': '大阪府'},
        }),
      );
    }
  });

  test('保存人物の内側のJSON・配列・詳細構造の破損を拒否する', () async {
    for (final profiles in [
      '{',
      '{}',
      'null',
      '[null]',
      '["壊れた人物"]',
      jsonEncode([
        {'details': '壊れた詳細'},
      ]),
      jsonEncode([
        {'details': []},
      ]),
    ]) {
      await _rejectUnchanged(_backup({'saved_profiles.list': profiles}));
    }
  });

  test('保存人物の既知フィールドの型を検査し、後半の破損でも一部復元しない', () async {
    for (final field in [
      'id',
      'name',
      'birthDate',
      'birthPlace',
      'updatedAt',
    ]) {
      await _rejectUnchanged(
        _backup({
          'saved_profiles.list': jsonEncode([
            _saved,
            {field: 123},
          ]),
        }),
      );
    }
    for (final field in [
      'birthTime',
      'birthPlace',
      'personality',
      'concerns',
      'readingStyle',
      'useSupplement',
    ]) {
      await _rejectUnchanged(
        _backup({
          'saved_profiles.list': jsonEncode([
            _saved,
            {
              'details': {field: field == 'useSupplement' ? 'false' : 123},
            },
          ]),
        }),
      );
    }
  });

  test('新旧名・版なしの旧バックアップを既存形式のまま復元できる', () async {
    for (final format in [
      'pancyo-astrology-backup',
      'pancyo-ai-astrology-backup',
    ]) {
      for (final includeVersion in [true, false]) {
        SharedPreferences.setMockInitialValues(_seed);
        await AppDataBackup.restoreJson(
          jsonEncode({
            'format': format,
            if (includeVersion) 'version': 1,
            'values': {
              'saved_profiles.list': jsonEncode([_saved]),
              'profile.birthPlace': '',
            },
          }),
        );
        expect((await SavedUserProfile.loadAll()).single.toJson(), _saved);
        expect((await UserProfileDetails.load()).birthPlace, '');
        expect((await UserProfileDetails.load()).useSupplement, isFalse);
      }
    }
  });

  test('旧人物の詳細なし・null・旧トップレベル出生地を補完せず検査に通す', () async {
    final raw = jsonEncode([
      {
        'id': 'fictional-legacy-1',
        'name': '架空旧人物A',
        'birthDate': '1991/2/3',
        'birthPlace': '北海道札幌市',
      },
      {'id': 'fictional-legacy-2', 'name': '架空旧人物B', 'details': null},
      {
        'id': 'fictional-legacy-3',
        'name': null,
        'details': {'birthPlace': null, 'useSupplement': null},
      },
    ]);
    await AppDataBackup.restoreJson(_backup({'saved_profiles.list': raw}));
    expect((await _snapshot())['saved_profiles.list'], raw);
    final all = await SavedUserProfile.loadAll();
    expect(all, hasLength(3));
    expect(
      all
          .singleWhere((item) => item.id == 'fictional-legacy-1')
          .details
          .birthPlace,
      '北海道札幌市',
    );
  });

  test('既知キーのnullは従来どおり未設定へ戻し、未知キーは触らない', () async {
    await AppDataBackup.restoreJson(
      _backup({
        'profile.birthPlace': null,
        'profile.useSupplement': null,
        'unrelated.preference': '上書きしない',
        'unknown.field': {'ignored': true},
      }),
    );
    final prefs = await _snapshot();
    expect(prefs['profile.birthPlace'], isNull);
    expect(prefs['profile.useSupplement'], isNull);
    expect(prefs['unrelated.preference'], '保持');
    expect(prefs.containsKey('unknown.field'), isFalse);
    expect((await UserProfileDetails.load()).useSupplement, isTrue);
  });

  test('欠けた既知キーは従来どおり置換し、補足キーの欠落だけ設定を維持', () async {
    await AppDataBackup.restoreJson(_backup({}));
    expect(await _snapshot(), {
      'profile.useSupplement': false,
      'unrelated.preference': '保持',
      'app.text_scale': 1.15,
    });
    expect(HouseSystemSettings.current.value, HouseSystem.placidus);
  });

  test('正常バックアップを検査しても人物JSONの表記や未知フィールドを再生成しない', () async {
    final raw = const JsonEncoder.withIndent('  ').convert([
      {
        ..._saved,
        'unknown.future_field': {'label': 'そのまま'},
      },
    ]);
    await AppDataBackup.restoreJson(
      _backup({
        ..._seed,
        'saved_profiles.list': raw,
        'profile.useSupplement': true,
      }),
    );
    expect((await _snapshot())['saved_profiles.list'], raw);
    expect((await _snapshot())['unrelated.preference'], '保持');
    expect((await UserProfileDetails.load()).useSupplement, isTrue);
  });

  for (final theme in FortuneShareTheme.values) {
    test('絵柄の保存名 ${theme.name} は既存設定と一緒に往復復元できる', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('share_card_theme', theme.name);
      final before = await _snapshot();
      final backup = await AppDataBackup.exportJson();
      expect(jsonDecode(backup)['values']['share_card_theme'], theme.name);
      await prefs.setString('share_card_theme', 'temporary-change');
      await AppDataBackup.restoreJson(backup);
      expect(await _snapshot(), before);
    });
  }

  Future<void> openRestore(WidgetTester tester, String clipboard) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.getData') return {'text': clipboard};
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: ProfileDataUtilityCard(profile: _profile),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, '復元'));
    await tester.pumpAndSettle();
    expect(find.text('バックアップを復元'), findsOneWidget);
  }

  testWidgets('破損バックアップの画面操作でも現在データを保持して理由を案内する', (tester) async {
    await openRestore(tester, _backup({'saved_profiles.list': '壊れたJSON'}));
    await tester.tap(find.widgetWithText(FilledButton, '置き換えて復元'));
    await tester.pumpAndSettle();
    expect(await _snapshot(), _seed);
    expect(
      find.text('バックアップの形式や内容を確認できませんでした。現在のデータは変更していません。'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('復元確認のキャンセルは正常なJSONでも現在データを変更しない', (tester) async {
    await openRestore(tester, _backup({'profile.birthPlace': '大阪府'}));
    await tester.tap(find.widgetWithText(TextButton, 'キャンセル'));
    await tester.pumpAndSettle();
    expect(await _snapshot(), _seed);
    expect(find.text('バックアップを復元'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('正常な復元を本人が確認した場合だけ置換して完了を表示する', (tester) async {
    await openRestore(
      tester,
      _backup({'profile.birthPlace': '大阪府', 'profile.useSupplement': true}),
    );
    await tester.tap(find.widgetWithText(FilledButton, '置き換えて復元'));
    await tester.pumpAndSettle();
    expect((await UserProfileDetails.load()).birthPlace, '大阪府');
    expect((await UserProfileDetails.load()).useSupplement, isTrue);
    expect(find.text('復元しました。アプリを開き直して人物を確認してください。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final (orientation, size) in [
    ('横置き', const Size(1920, 1200)),
    ('縦置き', const Size(1200, 1920)),
  ]) {
    testWidgets('最大文字倍率の$orientationでも復元確認を全文スクロールして閉じられる', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.625;
      tester.platformDispatcher.textScaleFactorTestValue = 2.4;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await openRestore(tester, _backup(_seed));
      expect(tester.takeException(), isNull);
      final input = tester.widget<TextField>(find.byType(TextField));
      expect(input.controller!.text, _backup(_seed));
      final cancel = find.widgetWithText(TextButton, 'キャンセル');
      await tester.ensureVisible(cancel);
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      expect(await _snapshot(), _seed);
      expect(find.text('バックアップを復元'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
