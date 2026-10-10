import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pancyo_ai_astrology/backup_restore_transaction.dart';
import 'package:pancyo_ai_astrology/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'backup_fault_store.dart';

final _seed = <String, Object>{
  'saved_profiles.list': jsonEncode([
    {
      'id': 'fictional-before',
      'name': '架空の復元前',
      'birthDate': '1990/1/2',
      'details': const UserProfileDetails.empty().toJson(),
      'updatedAt': '2026-09-29T00:00:00.000Z',
    },
  ]),
  'profile.birthTime': '08:30',
  'profile.birthPlace': '東京都',
  'profile.personality': '架空の本文',
  'profile.useSupplement': false,
  'share_card_show_score': false,
  'astrology.house_system': 'wholeSign',
  'unrelated.preference': '保持',
  'app.text_scale': 1.15,
};

final _replacement = <String, Object?>{
  'saved_profiles.list': jsonEncode([
    {
      'id': 'fictional-after',
      'name': '架空の復元後',
      'birthDate': '1991/2/3',
      'details': const UserProfileDetails.empty().toJson(),
      'updatedAt': '2026-09-30T00:00:00.000Z',
    },
  ]),
  'profile.birthTime': '09:00',
  'profile.birthPlace': '大阪府',
  'profile.useSupplement': true,
  'share_card_show_score': true,
  'astrology.house_system': 'placidus',
};

String _backup(Map<String, Object?> values) => jsonEncode({
  'format': 'pancyo-astrology-backup',
  'version': 1,
  'values': values,
});

BackupFaultStore _installStore([Map<String, Object>? seed]) {
  final initial = seed ?? _seed;
  SharedPreferences.setMockInitialValues(initial);
  final store = BackupFaultStore(initial);
  SharedPreferencesStorePlatform.instance = store;
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final originalHouseSystem = HouseSystemSettings.current.value;
  setUp(() => HouseSystemSettings.current.value = HouseSystem.wholeSign);
  tearDown(() {
    HouseSystemSettings.current.value = originalHouseSystem;
    SharedPreferences.setMockInitialValues({});
  });

  for (final fault in BackupStoreFault.values) {
    test('保存途中の${fault.name}で成功を装わず復元前のデータを保持する', () async {
      final store = _installStore()..faults[3] = fault;
      Object? failure;
      try {
        await AppDataBackup.restoreJson(_backup(_replacement));
      } catch (error) {
        failure = error;
      }
      expect(failure, isNotNull, reason: '保存失敗を復元成功と通知しない');
      expect(
        failure,
        isA<BackupRestoreFailure>().having(
          (error) => error.originalDataRestored,
          '原状の保持',
          isTrue,
        ),
      );
      expect(store.snapshot(), _seed);
      expect(HouseSystemSettings.current.value, HouseSystem.wholeSign);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('profile.birthPlace'), '東京都');
      store.faults.clear();
      await AppDataBackup.restoreJson(_backup(_replacement));
      expect(store.snapshot(), {
        ..._replacement.map((key, value) => MapEntry(key, value!)),
        'unrelated.preference': '保持',
        'app.text_scale': 1.15,
      });
      expect(HouseSystemSettings.current.value, HouseSystem.placidus);
    });
  }

  test('全7書込位置の失敗でも先行書込を巻き戻し、無関係な設定を保持する', () async {
    for (var position = 1; position <= 7; position++) {
      for (final fault in BackupStoreFault.values) {
        final store = _installStore()..faults[position] = fault;
        await expectLater(
          AppDataBackup.restoreJson(_backup(_replacement)),
          throwsA(
            isA<BackupRestoreFailure>().having(
              (error) => error.originalDataRestored,
              '原状の保持',
              isTrue,
            ),
          ),
        );
        expect(store.snapshot(), _seed, reason: '${fault.name}:$position');
      }
    }
  });

  test('開始前の読込失敗では保存を一件も呼ばない', () async {
    final store = _installStore()..readFailures.add(2);
    await expectLater(
      AppDataBackup.restoreJson(_backup(_replacement)),
      throwsA(
        isA<BackupRestoreFailure>().having(
          (error) => error.originalDataRestored,
          '書込なし',
          isTrue,
        ),
      ),
    );
    expect(store.mutations, 0);
    expect(store.snapshot(), _seed);
  });

  test('保存後の読込失敗でも成功にせず元へ戻す', () async {
    final store = _installStore()..readFailures.add(3);
    await expectLater(
      AppDataBackup.restoreJson(_backup(_replacement)),
      throwsA(
        isA<BackupRestoreFailure>().having(
          (error) => error.originalDataRestored,
          '巻き戻し確認',
          isTrue,
        ),
      ),
    );
    expect(store.snapshot(), _seed);
  });

  test('巻き戻しの読込も失敗した場合はデータ保持を保証しない', () async {
    final store = _installStore()
      ..faults[3] = BackupStoreFault.throwAfterWrite
      ..readFailures.add(3);
    await expectLater(
      AppDataBackup.restoreJson(_backup(_replacement)),
      throwsA(
        isA<BackupRestoreFailure>().having(
          (error) => error.originalDataRestored,
          '確認不能',
          isFalse,
        ),
      ),
    );
    // この模擬例は元に戻っていても、再読込できなければ保護済みと案内しない。
    expect(store.snapshot(), _seed);
  });

  test('巻き戻しの一件も失敗した場合は残るキーも復旧し、確認不能を返す', () async {
    final store = _installStore()
      ..faults[3] = BackupStoreFault.throwAfterWrite
      ..faults[4] = BackupStoreFault.throwBeforeWrite;
    await expectLater(
      AppDataBackup.restoreJson(_backup(_replacement)),
      throwsA(
        isA<BackupRestoreFailure>().having(
          (error) => error.originalDataRestored,
          '確認不能',
          isFalse,
        ),
      ),
    );
    expect(store.snapshot()['profile.birthPlace'], '大阪府');
    expect(
      store.snapshot()['saved_profiles.list'],
      _seed['saved_profiles.list'],
    );
    expect(store.snapshot()['profile.birthTime'], _seed['profile.birthTime']);
    expect(store.snapshot()['unrelated.preference'], '保持');
    expect(store.mutations, 6, reason: '一件の復旧失敗でほかの復旧を中止しない');
    expect(HouseSystemSettings.current.value, HouseSystem.wholeSign);
  });

  test('書込前にネイティブ保存値を読み直し、古いキャッシュへ巻き戻さない', () async {
    final store = _installStore();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('profile.birthTime'), '08:30');
    store.putFromNative('profile.birthTime', '07:00');
    store.faults[3] = BackupStoreFault.falseAfterWrite;
    await expectLater(
      AppDataBackup.restoreJson(_backup(_replacement)),
      throwsA(isA<BackupRestoreFailure>()),
    );
    expect(store.snapshot(), {..._seed, 'profile.birthTime': '07:00'});
    expect(prefs.getString('profile.birthTime'), '07:00');
  });

  test('元から同じ値は書き直さず、存在する値を先にremoveしない', () async {
    final store = _installStore();
    await AppDataBackup.restoreJson(_backup(_seed));
    expect(store.mutations, 0);
    await AppDataBackup.restoreJson(_backup(_replacement));
    expect(store.mutations, 7);
    expect(store.operations.where((op) => op.startsWith('remove:')), [
      'remove:flutter.profile.personality',
    ]);
  });

  test('元の型が異常でも巻き戻しはint・double・文字列配列を保持する', () async {
    final initial = {
      ..._seed,
      'profile.birthTime': 123,
      'profile.birthPlace': 1.25,
      'profile.personality': <String>['架空A', '架空B'],
    };
    final store = _installStore(initial)
      ..faults[7] = BackupStoreFault.throwAfterWrite;
    await expectLater(
      AppDataBackup.restoreJson(_backup(_replacement)),
      throwsA(isA<BackupRestoreFailure>()),
    );
    expect(store.snapshot(), initial);
  });

  test('元の未設定キーは巻き戻しでも未設定のまま残す', () async {
    final initial = Map<String, Object>.from(_seed)
      ..remove('profile.birthTime');
    final store = _installStore(initial)
      ..faults[3] = BackupStoreFault.falseAfterWrite;
    await expectLater(
      AppDataBackup.restoreJson(_backup(_replacement)),
      throwsA(isA<BackupRestoreFailure>()),
    );
    expect(store.snapshot(), initial);
  });

  test('反映コールバックの失敗も巻き戻し対象になる', () async {
    final store = _installStore();
    await expectLater(
      BackupRestoreTransaction.replace(
        prefs: await SharedPreferences.getInstance(),
        values: {'profile.birthPlace': '大阪府'},
        onVerified: () async => throw StateError('架空の反映失敗'),
      ),
      throwsA(
        isA<BackupRestoreFailure>().having(
          (error) => error.originalDataRestored,
          '原状の保持',
          isTrue,
        ),
      ),
    );
    expect(store.snapshot(), _seed);
  });

  test('復元中の別復元と出力は拒否し、完了後は再利用できる', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final store = _installStore();
    store.waitForMutation = (operation) async {
      if (operation != 1) return;
      entered.complete();
      await release.future;
    };
    final restoring = AppDataBackup.restoreJson(_backup(_replacement));
    await entered.future;
    try {
      await expectLater(
        AppDataBackup.restoreJson(_backup(_seed)),
        throwsA(isA<BackupRestoreBusyException>()),
      );
      await expectLater(
        AppDataBackup.exportJson(),
        throwsA(isA<BackupRestoreBusyException>()),
      );
      expect(store.mutations, 1);
    } finally {
      release.complete();
      await restoring;
    }
    expect(
      jsonDecode(await AppDataBackup.exportJson())['values'],
      _replacement,
    );
  });

  const profile = AstroProfile(
    name: '架空の保護確認',
    birthDate: '1990/1/2',
    birthTime: '12:00',
    birthPlace: '北海道札幌市',
    theme: '今日の流れ',
  );
  Future<void> openRestore(WidgetTester tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.getData')
            return {'text': _backup(_replacement)};
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
            child: ProfileDataUtilityCard(profile: profile),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, '復元'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '置き換えて復元'));
  }

  testWidgets('保存失敗時は復旧後の案内だけを表示し、待機画面を閉じる', (tester) async {
    final store = _installStore()..faults[3] = BackupStoreFault.falseAfterWrite;
    await openRestore(tester);
    await tester.pumpAndSettle();
    expect(store.snapshot(), _seed);
    expect(find.text('復元に失敗しました。復元前のデータは保たれています。'), findsOneWidget);
    expect(find.text('バックアップを復元中…'), findsNothing);
    expect(find.text('復元しました。アプリを開き直して人物を確認してください。'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('復旧失敗時は保存状態の確認とJSONの保管を案内する', (tester) async {
    _installStore()
      ..faults[3] = BackupStoreFault.throwAfterWrite
      ..faults[4] = BackupStoreFault.throwBeforeWrite;
    await openRestore(tester);
    await tester.pumpAndSettle();
    expect(
      find.text(
        '復元に失敗しました。元の状態へ戻せたか確認できません。プロフィールと設定を確認し、バックアップJSONは削除しないでください。',
      ),
      findsOneWidget,
    );
    expect(find.text('復元に失敗しました。復元前のデータは保たれています。'), findsNothing);
    expect(find.text('バックアップを復元中…'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('復元中は戻る操作を防ぎ、終われば待機画面だけを閉じる', (tester) async {
    final release = Completer<void>();
    final store = _installStore();
    store.waitForMutation = (operation) async {
      if (operation == 1) await release.future;
    };
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    await openRestore(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('バックアップを復元中…'), findsOneWidget);
    expect(
      await tester.state<NavigatorState>(find.byType(Navigator)).maybePop(),
      isTrue,
    );
    await tester.pump();
    expect(find.text('バックアップを復元中…'), findsOneWidget);
    release.complete();
    await tester.pumpAndSettle();
    expect(find.text('バックアップを復元中…'), findsNothing);
    expect(find.text('復元しました。アプリを開き直して人物を確認してください。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
