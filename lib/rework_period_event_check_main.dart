import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'main.dart' as app;
import 'research/native_smoke_check.dart';

// Explicit QA entrypoint only. The usual rework_main.dart is unchanged.
Future<void> main() async {
  if (!app.PeriodEventNativeCheck.enabled) {
    throw StateError('実機比較の明示オプションが必要です。');
  }
  WidgetsFlutterBinding.ensureInitialized();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_run());
  });
  await app.main();
}

Future<void> _run() async {
  File? manifest;
  final rows = <Map<String, Object?>>[];
  try {
    final mode = app.LongRangeMode.values.byName(
      const String.fromEnvironment(
        'PANCYO_EVENT_CHECK_MODE',
        defaultValue: 'week',
      ),
    );
    final house = app.HouseSystem.values.byName(
      const String.fromEnvironment(
        'PANCYO_EVENT_CHECK_HOUSE',
        defaultValue: 'placidus',
      ),
    );
    final checks = await Isolate.run(NativeSmokeCheck.runAll);
    print(
      'PANCYO_REWORK_NATIVE_SMOKE ${jsonEncode({'passed': true, 'checks': checks})}',
    );
    final temporary = await getTemporaryDirectory();
    final root = await temporary.createTemp('pancyo_period_event_qa_');
    manifest = File('${root.path}/manifest.json');
    await manifest.writeAsString(
      jsonEncode({'status': 'running', 'rows': rows}),
      flush: true,
    );
    for (final (reuse, repetition) in [
      (false, 1),
      (true, 1),
      (true, 2),
      (false, 2),
    ]) {
      final row = await Isolate.run(
        () => app.PeriodEventNativeCheck.runOne(
          mode: mode,
          house: house,
          reuse: reuse,
          repetition: repetition,
          temporaryRoot: root.path,
        ),
        debugName: 'pancyo-artificial-event-comparison',
      );
      rows.add(row);
      await manifest.writeAsString(
        jsonEncode({'status': 'running', 'rows': rows}),
        flush: true,
      );
      print(
        'PANCYO_REWORK_EVENT_NATIVE_PROGRESS ${jsonEncode({'mode': mode.name, 'house_system': house.name, 'completed': rows.length, 'total': 4, 'reuse': reuse, 'repetition': repetition, 'context_us': row['context_us'], 'data_us': row['data_us'], 'write_us': row['write_us'], 'work_counts': row['work_counts']})}',
      );
    }
    final result = app.PeriodEventNativeCheck.validateRows(
      rows,
      mode: mode,
      house: house,
    );
    await manifest.writeAsString(
      jsonEncode({'status': 'complete', 'result': result, 'rows': rows}),
      flush: true,
    );
    print('PANCYO_REWORK_EVENT_NATIVE_CHECK ${jsonEncode(result)}');
  } catch (_) {
    if (manifest != null) {
      await manifest.writeAsString(
        jsonEncode({'status': 'failed', 'rows': rows}),
        flush: true,
      );
    }
    // No paths, names, dates or native error strings are logged.
    print(
      'PANCYO_REWORK_EVENT_NATIVE_CHECK ${jsonEncode({'passed': false, 'check_failed': true})}',
    );
  }
}
