import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pancyo_ai_astrology/birth_clock.dart';
import 'package:pancyo_ai_astrology/civil_time.dart';
import 'package:pancyo_ai_astrology/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'backup_fault_store.dart';

const _civilChannel = MethodChannel(AndroidRegionalTimeResolver.channelName);
const _fixtureTzdb = 'roundtrip-fixture-only';

ResolvedBirthClock _tokyoFixtureClock(String time) {
  final local = CivilClockTime.parse('1990-01-02', '$time:00');
  return ResolvedBirthClock.fromResolution(
    resolution: CivilTimeResolution(
      zoneId: 'Asia/Tokyo',
      local: local,
      status: CivilResolutionStatus.unique,
      candidates: [
        CivilUtcCandidate(
          instantUtc: local.fields.subtract(const Duration(hours: 9)),
          offsetSeconds: 32400,
        ),
      ],
      tzdbVersion: _fixtureTzdb,
    ),
    resolverSource: const AndroidRegionalTimeResolver().source,
  );
}

const _oldDetails = UserProfileDetails(
  birthTime: '05:15',
  birthPlace: '大阪府大阪市',
  personality: '別の架空人物の性格',
  concerns: '別の架空人物のテーマ',
  readingStyle: '別の架空人物の文体',
);

Future<void> _frames(WidgetTester tester, [int count = 12]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _openReading(WidgetTester tester) async {
  final start = find.widgetWithText(FilledButton, 'ホロスコープを読む');
  await tester.ensureVisible(start);
  await tester.tap(start);
  await tester.pump();
  await tester.pump(const Duration(seconds: 6));
  await _frames(tester);
  expect(find.byType(ResultScreen), findsOneWidget);
  tester
      .widget<NavigationRail>(find.byType(NavigationRail))
      .onDestinationSelected!(4);
  await _frames(tester);
}

void _fillForm(WidgetTester tester, UserProfileDetails details) {
  for (final (label, value) in [
    ('出生時間', details.birthTime),
    ('出生地', details.birthPlace),
    ('性格・大切にしていること', details.storedPersonality),
    ('今の悩み・気になっているテーマ', details.storedConcerns),
    ('占いで特に見てほしいこと', details.storedReadingStyle),
  ]) {
    tester
            .widget<ProfileTextField>(
              find.byWidgetPredicate(
                (widget) => widget is ProfileTextField && widget.label == label,
              ),
            )
            .controller
            .text =
        value;
  }
}

void main() {
  final oldPerson = SavedUserProfile(
    id: 'fictional-original-person',
    name: '架空の元からいる人物',
    birthDate: '1985/3/4',
    details: _oldDetails,
    updatedAt: DateTime.utc(2026, 9, 1),
  );
  final seed = <String, Object>{
    'saved_profiles.list': jsonEncode([oldPerson.toJson()]),
    'profile.birthTime': _oldDetails.birthTime,
    'profile.birthPlace': _oldDetails.birthPlace,
    'profile.personality': _oldDetails.storedPersonality,
    'profile.concerns': _oldDetails.storedConcerns,
    'profile.readingStyle': _oldDetails.storedReadingStyle,
    'profile.useSupplement': true,
    'share_card_display_name': '架空の共有設定',
    'share_card_show_body': false,
    'unrelated.preference': '通常保存と復元の対象外',
  };
  late BackupFaultStore store;
  late String clipboard;
  late List<String> civilCalls;
  final originalHouseSystem = HouseSystemSettings.current.value;

  setUp(() {
    SharedPreferences.setMockInitialValues(seed);
    store = BackupFaultStore(seed);
    SharedPreferencesStorePlatform.instance = store;
    clipboard = '';
    civilCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.getData') return {'text': clipboard};
          return null;
        });
    // Contract fixture for two explicit fictional Tokyo clocks only.
    // This does not execute Android ZoneRules or a native ephemeris.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_civilChannel, (call) async {
          expect(call.method, 'resolveLocal');
          final args = Map<String, Object?>.from(call.arguments as Map);
          expect(args['zoneId'], 'Asia/Tokyo');
          expect(args['localDate'], '1990-01-02');
          final time = args['localTime'] as String;
          expect(time, isIn(['08:30:00', '09:45:00']));
          civilCalls.add(time);
          final local = CivilClockTime.parse('1990-01-02', time);
          return {
            'zoneId': 'Asia/Tokyo',
            'localDateTime': local.label,
            'status': 'unique',
            'candidates': [
              {
                'instantUtc': local.fields
                    .subtract(const Duration(hours: 9))
                    .toIso8601String(),
                'offsetSeconds': 32400,
              },
            ],
            'tzdbVersion': _fixtureTzdb,
          };
        });
  });
  tearDown(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_civilChannel, null);
    HouseSystemSettings.current.value = originalHouseSystem;
  });

  Future<void> restart(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await _frames(tester);
    // アプリとSharedPreferencesのキャッシュを捨て、架空保存バックエンドから読み直す。
    // Androidのプロセス再起動・実媒体の検査ではない。
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesStorePlatform.instance = store;
    await tester.pumpWidget(const PancyoAstrologyApp());
    await _frames(tester);
  }

  for (final explicitBirth in [false, true]) {
    testWidgets(
      '${explicitBirth ? '旧JST記録人物' : '出生未入力の新規人物'}の通常保存→キャッシュ破棄→相談JSON→変更→UI復元→再読込',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const name = '架空の通常保存通し確認';
        final details = UserProfileDetails(
          birthTime: explicitBirth ? '08:30' : '',
          birthPlace: explicitBirth ? '東京都' : '',
          personality: '架空の新規人物の性格',
          concerns: '架空の新規人物のテーマ',
          readingStyle: '架空の新規人物の文体',
          useSupplement: false,
        );
        if (explicitBirth) {
          // A pre-regional-clock stored record must retain its legacy meaning.
          // The regional-clock path is tested separately below because host
          // SimpleEphemeris deliberately rejects a resolved regional clock.
          final legacy = SavedUserProfile(
            id: 'fictional-pre-clock-person',
            name: name,
            birthDate: '1990/1/2',
            details: UserProfileDetails(
              birthTime: details.birthTime,
              birthPlace: details.birthPlace,
              personality: '',
              concerns: '',
              readingStyle: '',
            ),
            updatedAt: DateTime.utc(2026, 10, 1),
          );
          store.putFromNative(
            'saved_profiles.list',
            jsonEncode([legacy.toJson(), oldPerson.toJson()]),
          );
          SharedPreferences.setMockInitialValues({});
          SharedPreferencesStorePlatform.instance = store;
        }
        await tester.pumpWidget(const PancyoAstrologyApp());
        await _frames(tester);
        if (!explicitBirth) {
          final newPerson = find.widgetWithText(TextButton, '新しい人物を入力');
          await tester.ensureVisible(newPerson);
          await tester.tap(newPerson);
          await _frames(tester);
          final birthFields = tester.widgetList<TextField>(
            find.byType(TextField),
          );
          birthFields.first.controller!.text = name;
          birthFields.elementAt(1).controller!.text = '1990/1/2';
        }
        await _openReading(tester);
        expect(
          tester
              .widget<ProfileForm>(find.byType(ProfileForm))
              .initialDetails
              .toJson(),
          explicitBirth
              ? UserProfileDetails(
                  birthTime: details.birthTime,
                  birthPlace: details.birthPlace,
                  personality: '',
                  concerns: '',
                  readingStyle: '',
                ).toJson()
              : const UserProfileDetails.empty().toJson(),
          reason: '旧記録を保持し、新規人物へは前の人物の詳細を引き継がない',
        );
        _fillForm(tester, details);
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged!(
          false,
        );
        await _frames(tester);
        expect(find.text('趣味・悩みなどの反映をオフにしました'), findsOneWidget);
        final saved = (await SavedUserProfile.loadAll()).first;
        expect(saved.name, name);
        expect(saved.id, isNot(oldPerson.id));
        expect(saved.details.toJson(), details.toJson());
        expect((await UserProfileDetails.load()).toJson(), details.toJson());
        expect(await SavedUserProfile.loadAll(), hasLength(2));
        expect(
          (await SavedUserProfile.loadAll()).last.toJson(),
          oldPerson.toJson(),
        );
        final savedSnapshot = store.snapshot();
        final backup = await AppDataBackup.exportJson();
        expect(
          (jsonDecode(backup)['values'] as Map)['profile.useSupplement'],
          isFalse,
        );

        await restart(tester);
        expect(
          tester
              .widgetList<TextField>(find.byType(TextField))
              .first
              .controller!
              .text,
          name,
        );
        await _openReading(tester);
        final export = tester.widget<ProfileAstroJsonExportCard>(
          find.byType(ProfileAstroJsonExportCard),
        );
        expect(export.profile.savedProfileId, saved.id);
        expect(export.details.toJson(), details.toJson());
        expect(export.profile.birthTime, details.effectiveBirthTime);
        expect(export.profile.birthPlace, details.effectiveBirthPlace);
        final date = DateTime.utc(2026, 10, 1, 3);
        final json = DailyAstroDataExportCard(
          date: date,
          profile: export.profile,
          details: export.details,
          contextData: const AstrologyEngine().buildPreviewContext(
            profile: export.profile,
            date: date,
          ),
        ).buildData(generatedAt: date);
        expect((json['profile'] as Map)['name'], name);
        expect(
          (json['birth_input_quality']
              as Map)['assumed_fields_in_current_record'],
          explicitBirth ? isEmpty : ['birth_time', 'birth_place'],
        );

        final changed = UserProfileDetails(
          birthTime: explicitBirth ? '09:45' : '',
          birthPlace: '大阪府大阪市',
          personality: '架空の変更後の性格',
          concerns: '架空の変更後のテーマ',
          readingStyle: '架空の変更後の文体',
        );
        _fillForm(tester, changed);
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged!(
          true,
        );
        await _frames(tester);
        expect((await UserProfileDetails.load()).toJson(), changed.toJson());
        expect((await SavedUserProfile.loadAll()).first.id, saved.id);
        expect(await SavedUserProfile.loadAll(), hasLength(2));
        expect(store.snapshot(), isNot(savedSnapshot));

        clipboard = backup;
        final restore = find.widgetWithText(OutlinedButton, '復元');
        await tester.ensureVisible(restore);
        await tester.tap(restore);
        await _frames(tester);
        await tester.tap(find.widgetWithText(FilledButton, '置き換えて復元'));
        await _frames(tester, 18);
        expect(find.byType(ResultScreen), findsNothing);
        expect(store.snapshot(), savedSnapshot);
        expect(civilCalls, isEmpty, reason: '旧JST記録/出生未入力の経路は地域時計へ勝手に変換しない');
        await restart(tester);
        await _openReading(tester);
        final restored = tester.widget<ProfileForm>(find.byType(ProfileForm));
        expect(restored.profile.name, name);
        expect(restored.profile.savedProfileId, saved.id);
        expect(restored.initialDetails.toJson(), details.toJson());
        expect(
          (await SavedUserProfile.loadAll()).last.toJson(),
          oldPerson.toJson(),
        );
        expect(store.snapshot(), savedSnapshot);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await _frames(tester);
      },
    );
  }

  Future<void> regionalHost(
    WidgetTester tester,
    UserProfileDetails details,
    ValueChanged<SavedUserProfile> onSaved,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProfileForm(
              profile: const AstroProfile(
                name: 'Fictional Tokyo clock',
                birthDate: '1990/1/2',
                birthTime: '12:00',
                birthPlace: '東京都',
                theme: 'Fixture',
                savedProfileId: 'fictional-regional-clock',
              ),
              initialDetails: details,
              onSaved: onSaved,
            ),
          ),
        ),
      ),
    );
    await _frames(tester);
  }

  testWidgets('Tokyo契約mockの通常保存・時計変更・再読込・backup復元（native未実行）', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SavedUserProfile? captured;
    await regionalHost(
      tester,
      const UserProfileDetails.empty(),
      (value) => captured = value,
    );
    const input = UserProfileDetails(
      birthTime: '08:30',
      birthPlace: '東京都',
      personality: 'Original supplement',
      concerns: 'Original topic',
      readingStyle: 'Original style',
      useSupplement: false,
    );
    _fillForm(tester, input);
    tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged!(
      false,
    );
    await _frames(tester);
    final expected = UserProfileDetails(
      birthClock: _tokyoFixtureClock('08:30'),
      birthTime: input.birthTime,
      birthPlace: input.birthPlace,
      personality: input.storedPersonality,
      concerns: input.storedConcerns,
      readingStyle: input.storedReadingStyle,
      useSupplement: false,
    );
    expect(captured, isNotNull);
    expect(captured!.details.toJson(), expected.toJson());
    expect((await UserProfileDetails.load()).toJson(), expected.toJson());
    expect(civilCalls, ['08:30:00']);
    final savedSnapshot = store.snapshot();
    final backup = await AppDataBackup.exportJson();

    await tester.pumpWidget(const SizedBox.shrink());
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesStorePlatform.instance = store;
    final reloaded = (await SavedUserProfile.loadAll()).first;
    expect(reloaded.details.toJson(), expected.toJson());
    await regionalHost(tester, reloaded.details, (value) => captured = value);
    const changedInput = UserProfileDetails(
      birthTime: '09:45',
      birthPlace: '大阪府大阪市',
      personality: 'Changed supplement',
      concerns: 'Changed topic',
      readingStyle: 'Changed style',
    );
    _fillForm(tester, changedInput);
    tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged!(true);
    await _frames(tester);
    final changedExpected = UserProfileDetails(
      birthClock: _tokyoFixtureClock('09:45'),
      birthTime: changedInput.birthTime,
      birthPlace: changedInput.birthPlace,
      personality: changedInput.storedPersonality,
      concerns: changedInput.storedConcerns,
      readingStyle: changedInput.storedReadingStyle,
    );
    expect(captured!.details.toJson(), changedExpected.toJson());
    expect(
      (await UserProfileDetails.load()).toJson(),
      changedExpected.toJson(),
    );
    expect(civilCalls, ['08:30:00', '09:45:00']);
    expect(
      (await SavedUserProfile.loadAll()).first.id,
      'fictional-regional-clock',
    );
    expect(
      (await SavedUserProfile.loadAll()).last.toJson(),
      oldPerson.toJson(),
    );
    await AppDataBackup.restoreJson(backup);
    expect(store.snapshot(), savedSnapshot);
    expect((await UserProfileDetails.load()).toJson(), expected.toJson());
    expect(
      (await SavedUserProfile.loadAll()).first.details.toJson(),
      expected.toJson(),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await _frames(tester);
  });

  testWidgets('地域時計plugin不在では説明して保存を中断し原データを保持する', (tester) async {
    var unavailableCalls = 0;
    // An explicit missing-plugin response avoids delegating to the host engine.
    // TestDefaultBinaryMessenger encodes this as the real absent-plugin null
    // envelope. This is a channel-boundary fixture, not a native device test.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_civilChannel, (call) async {
          expect(call.method, 'resolveLocal');
          unavailableCalls++;
          throw MissingPluginException(
            'Fictional absent regional-clock plugin',
          );
        });
    SavedUserProfile? captured;
    final before = store.snapshot();
    await regionalHost(
      tester,
      const UserProfileDetails.empty(),
      (value) => captured = value,
    );
    _fillForm(
      tester,
      const UserProfileDetails(
        birthTime: '08:30',
        birthPlace: '東京都',
        personality: '',
        concerns: '',
        readingStyle: '',
      ),
    );
    tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged!(
      false,
    );
    await _frames(tester);
    expect(
      find.byKey(const ValueKey('birth-clock-error-unavailable')),
      findsOneWidget,
    );
    expect(unavailableCalls, 1);
    expect(captured, isNull);
    expect(store.mutations, 0);
    expect(store.snapshot(), before);
    await tester.tap(find.byKey(const ValueKey('birth-clock-close')));
    await _frames(tester);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
    expect(store.snapshot(), before);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await _frames(tester);
  });
}
