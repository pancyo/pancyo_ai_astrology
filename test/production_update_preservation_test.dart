import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pancyo_ai_astrology/app_language_settings.dart';
import 'package:pancyo_ai_astrology/main.dart' as app;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'backup_fault_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final singleMap in [false, true]) {
    testWidgets(
      'production main preserves all typed prefs and old AI file (${singleMap ? 'Map' : 'List'})',
      (tester) async {
        final previousPlatform = debugDefaultTargetPlatformOverride;
        final previousHouse = app.HouseSystemSettings.current.value;
        final previousScale = app.TextScaleSettings.current.value;
        final previousLanguage = AppLanguageSettings.current.value;
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        try {
          tester.view.physicalSize = const Size(1200, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(() {
            debugDefaultTargetPlatformOverride = previousPlatform;
            app.HouseSystemSettings.current.value = previousHouse;
            app.TextScaleSettings.current.value = previousScale;
            AppLanguageSettings.current.value = previousLanguage;
            SharedPreferences.setMockInitialValues({});
          });

          late Directory directory;
          late File oldModel;
          late BackupFaultStore store;
          late Map<String, Object> before;
          const oldBytes = <int>[0, 255, 13, 10, 7, 9, 0];
          await tester.runAsync(() async {
            directory = await Directory.systemTemp.createTemp(
              'pancyo_release_startup_fixture_',
            );
            oldModel = File(
              '${directory.path}${Platform.pathSeparator}old_model.bin',
            );
            await oldModel.writeAsBytes(oldBytes, flush: true);
            final person = {
              'id': 'legacy-existing',
              'name': 'Legacy profile',
              'birthDate': '1990/1/2',
              'details': {
                'birthTime': '',
                'birthPlace': '',
                'personality': 'Original text',
                'concerns': 'Preserve',
                'readingStyle': '',
                'useSupplement': false,
              },
            };
            final seed = <String, Object>{
              'saved_profiles.list': jsonEncode(singleMap ? person : [person]),
              'profile.birthTime': '',
              'profile.birthPlace': '',
              'profile.personality': 'Original text',
              'profile.concerns': 'Preserve',
              'profile.readingStyle': '',
              'profile.useSupplement': false,
              'astrology.house_system': 'wholeSign',
              'astrology.text_scale': 1.3,
              'astrology.ui_language': 'ja',
              'share_card_display_name': 'Original custom name',
              'share_card_show_score': false,
              'share_card_show_body': true,
              'share_card_theme': 'catFlower',
              'share_card_custom_wallpaper': '',
              'custom_fortune.logs': '[{"question":"Keep","answer":"Keep."}]',
              'daily_fortune_reflections.v1': '{"old":"keep exactly"}',
              'ai_data.installed': true,
              'ai_data.model_name': 'Old model',
              'ai_data.license': 'Original license',
              'ai_data.source_label': 'Original source',
              'ai_data.source_url': 'https://example.invalid/fixture',
              'ai_data.runtime': 'Old runtime',
              'ai_data.size_bytes': oldBytes.length,
              'ai_data.downloaded_at': '2025-01-02T00:00:00Z',
              'ai_data.checksum': 'Original checksum',
              'ai_data.file_path': oldModel.path,
              'unknown.string': 'Retain 原文',
              'unknown.int': 17,
              'unknown.double': 0.5,
              'unknown.bool': false,
              'unknown.list': <String>['one', 'two'],
            };
            SharedPreferences.setMockInitialValues({});
            store = BackupFaultStore(seed);
            SharedPreferencesStorePlatform.instance = store;
            before = store.snapshot();
            // Call the actual production entry, not just pump the root widget.
            await app.main();
          });
          addTearDown(() async {
            // Only the single file created in this test's fresh directory.
            if (await oldModel.exists()) await oldModel.delete();
            if (await directory.exists()) await directory.delete();
          });

          await tester.pump();
          await tester.pump();
          expect(find.byType(app.BirthInfoScreen), findsOneWidget);
          final texts = tester.widgetList<TextField>(find.byType(TextField));
          expect(
            texts.map((field) => field.controller?.text),
            contains('Legacy profile'),
          );
          expect(tester.takeException(), isNull);
          await tester.runAsync(() async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.reload();
            expect(
              store.mutations,
              0,
              reason: 'Startup must not even rewrite unchanged values',
            );
            expect(store.snapshot(), before);
            for (final entry in before.entries) {
              expect(prefs.get(entry.key), entry.value);
              expect(prefs.get(entry.key).runtimeType, entry.value.runtimeType);
            }
            expect(prefs.containsKey('profile.birthClock'), isFalse);
            expect(await oldModel.exists(), isTrue);
            expect(await oldModel.readAsBytes(), oldBytes);
          });
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        } finally {
          debugDefaultTargetPlatformOverride = previousPlatform;
        }
      },
    );
  }
}
