import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'main.dart' as app;
import 'app_language_settings.dart';

/// Local QA package with usable normal UI. Deliberately skips app.main and its
/// LegacyDataCleanup. The three restores read settings without persisting them.
Future<void> main() async {
  if (!app.DailyIntradayNativeCheck.enabled) throw StateError('Explicit daily QA flags required.');
  WidgetsFlutterBinding.ensureInitialized();
  await app.HouseSystemSettings.restore();
  await app.TextScaleSettings.restore();
  await AppLanguageSettings.restore();
  WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  runApp(const app.PancyoAstrologyApp());
}

Future<void> _run() async {
  var stage = 'cache_validation';
  try {
    final cache = await (await getTemporaryDirectory()).resolveSymbolicLinks();
    if (!app.DailyIntradayNativeCheck.validCacheRoot(cache)) throw StateError('Invalid QA cache root.');
    final cached = await app.DailyIntradayNativeCheck.readCompleted(cache);
    if (cached != null) {
      print('PANCYO_REWORK_DAILY_V4_NATIVE ${jsonEncode(cached)}');
      return;
    }
    final rows = <Map<String, Object?>>[];
    for (final house in [app.HouseSystem.placidus, app.HouseSystem.wholeSign]) {
      stage = house.name;
      final root = await Directory(cache).createTemp('pancyo_daily_intraday_qa_');
      final row = await Isolate.run(() => app.DailyIntradayNativeCheck.runOne(
        house: house, temporaryRoot: root.path), debugName: 'pancyo-daily-v4-native-qa');
      rows.add(row);
      print('PANCYO_REWORK_DAILY_V4_NATIVE_PROGRESS ${jsonEncode({
        'house_system': house.name, 'completed': rows.length, 'total': 2,
        'point_count': row['point_count'], 'numeric_audits': row['numeric_audits'],
        'felt_audits': row['felt_audits'], 'context_us': row['context_us'],
        'data_us': row['data_us'], 'validation_us': row['validation_us'],
        'write_us': row['write_us'], 'bytes': row['bytes'], 'sha256': row['sha256'],
      })}');
    }
    stage = 'manifest_write';
    final result = app.DailyIntradayNativeCheck.validateRows(rows);
    final manifest = File('$cache/pancyo_daily_intraday_qa_completed.json');
    if (await FileSystemEntity.type(manifest.path, followLinks: false) != FileSystemEntityType.notFound &&
        await manifest.resolveSymbolicLinks() != manifest.path) {
      throw StateError('Invalid QA manifest path.');
    }
    await manifest.writeAsString(jsonEncode({'status': 'complete',
      'check_id': app.DailyIntradayNativeCheck.checkId, 'rows': rows}), flush: true);
    stage = 'manifest_readback';
    final checked = await app.DailyIntradayNativeCheck.readCompleted(cache);
    if (checked == null) throw StateError('Evidence read-back failed.');
    print('PANCYO_REWORK_DAILY_V4_NATIVE ${jsonEncode({...result, 'cache_read_back_verified': true})}');
  } catch (_) {
    print('PANCYO_REWORK_DAILY_V4_NATIVE ${jsonEncode({'passed': false,
      'check_id': app.DailyIntradayNativeCheck.checkId, 'check_failed': true, 'stage': stage})}');
  }
}
