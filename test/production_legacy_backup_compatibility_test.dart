import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pancyo_ai_astrology/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'backup_fault_store.dart';

const _person = <String, Object?>{
  'id': 'legacy-person-id',
  'name': 'Legacy name — 原文',
  'birthDate': '1990/1/2',
  'birthPlace': '東京都',
  'updatedAt': '2026-10-01T00:00:00.000Z',
  'details': {
    'birthTime': '',
    'birthPlace': '',
    'personality': 'Original supplement',
    'concerns': '',
    'readingStyle': '',
    'useSupplement': false,
  },
  'unknown_future_field': {'keep': 'exact raw JSON'},
};

String _backup(String profiles) => jsonEncode({
  'format': 'pancyo-ai-astrology-backup',
  // Version-less backups are also an existing supported format.
  'values': {'saved_profiles.list': profiles, 'profile.birthPlace': '東京都'},
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BackupFaultStore store;
  late HouseSystem previousHouse;

  setUp(() {
    previousHouse = HouseSystemSettings.current.value;
    SharedPreferences.setMockInitialValues({});
    store = BackupFaultStore({
      'saved_profiles.list': jsonEncode([
        {'id': 'before', 'name': 'Before', 'birthDate': '1980/1/1'},
      ]),
      'profile.birthPlace': 'Before place',
      'astrology.house_system': 'wholeSign',
      'unrelated.double': 0.75,
      'unrelated.list': <String>['keep', 'raw'],
    });
    SharedPreferencesStorePlatform.instance = store;
    HouseSystemSettings.current.value = HouseSystem.wholeSign;
  });

  tearDown(() {
    HouseSystemSettings.current.value = previousHouse;
    SharedPreferences.setMockInitialValues({});
  });

  for (final singleMap in [false, true]) {
    test(
      'legacy ${singleMap ? 'Map' : 'List'} restores exact raw JSON',
      () async {
        final raw = const JsonEncoder.withIndent(
          '  ',
        ).convert(singleMap ? _person : [_person]);
        await AppDataBackup.restoreJson(_backup(raw));
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        expect(prefs.getString('saved_profiles.list'), raw);
        final restored = (await SavedUserProfile.loadAll()).single;
        expect(restored.id, 'legacy-person-id');
        expect(restored.name, _person['name']);
        expect(restored.birthDate, _person['birthDate']);
        expect(restored.details.birthTime, '');
        expect(restored.details.birthPlace, '東京都');
        expect(restored.details.storedPersonality, 'Original supplement');
        expect(restored.details.useSupplement, isFalse);
        expect(restored.details.birthClock, isNull);
        expect(prefs.getDouble('unrelated.double'), 0.75);
        expect(prefs.getStringList('unrelated.list'), ['keep', 'raw']);
        // Export must not normalize the old Map into a List or drop extra fields.
        final exported = jsonDecode(await AppDataBackup.exportJson()) as Map;
        expect((exported['values'] as Map)['saved_profiles.list'], raw);
      },
    );
  }

  test(
    'old Map with only a recorded name keeps supported missing fields',
    () async {
      const raw = '{ "name": "Legacy minimal" }';
      await AppDataBackup.restoreJson(_backup(raw));
      expect(store.snapshot()['saved_profiles.list'], raw);
      final restored = (await SavedUserProfile.loadAll()).single;
      expect(restored.name, 'Legacy minimal');
      expect(restored.details.birthClock, isNull);
    },
  );

  final invalid = <String, String>{
    'empty Map': '{}',
    'unrelated Map': '{"unrelated":"not a profile"}',
    'malformed JSON': '{',
    'scalar': '7',
    'invalid Map name type': '{"name":7}',
    'invalid Map details': '{"name":"Legacy","details":"bad"}',
    'invalid Map supplement type':
        '{"name":"Legacy","details":{"useSupplement":"false"}}',
    'invalid clock metadata':
        '{"name":"Legacy","details":{"birthClock":{"zoneId":"bad"}}}',
    'later invalid List entry': jsonEncode([
      _person,
      {
        'name': 'Later',
        'details': {'birthTime': 12},
      },
    ]),
  };
  for (final entry in invalid.entries) {
    test('${entry.key} fails before every write', () async {
      final before = store.snapshot();
      await expectLater(
        AppDataBackup.restoreJson(_backup(entry.value)),
        throwsA(isA<FormatException>()),
      );
      expect(store.mutations, 0);
      expect(store.snapshot(), before);
      expect(HouseSystemSettings.current.value, HouseSystem.wholeSign);
    });
  }
}
