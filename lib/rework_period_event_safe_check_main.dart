import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'main.dart' as app;
import 'research/native_smoke_check.dart';

Future<void> main() async {
  if (!app.reworkTestBuild || !app.PeriodEventNativeCheck.enabled) {
    throw StateError('期間JSON比較の明示オプションが必要です。');
  }
  WidgetsFlutterBinding.ensureInitialized();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_run());
  });
  runApp(const _PeriodEventQaApp());
}

class _PeriodEventQaApp extends StatelessWidget {
  const _PeriodEventQaApp();

  @override
  Widget build(BuildContext context) => const Directionality(
    textDirection: TextDirection.ltr,
    child: ColoredBox(
      color: Color(0xFF17142B),
      child: SizedBox.expand(
        child: Center(
          child: Text(
            '期間JSONの人工比較を実行中',
            style: TextStyle(color: Color(0xFFFFFFFF)),
          ),
        ),
      ),
    ),
  );
}

Future<void> _run() async {
  File? manifest;
  Directory? evidenceRoot;
  final rows = <Map<String, Object?>>[];
  var mode = app.LongRangeMode.week;
  var house = app.HouseSystem.placidus;
  var stage = 'configuration';

  try {
    if (!Platform.isAndroid) {
      throw StateError('Android実機専用の検査です。');
    }
    mode = app.LongRangeMode.values.byName(
      const String.fromEnvironment(
        'PANCYO_EVENT_CHECK_MODE',
        defaultValue: 'week',
      ),
    );
    house = app.HouseSystem.values.byName(
      const String.fromEnvironment(
        'PANCYO_EVENT_CHECK_HOUSE',
        defaultValue: 'placidus',
      ),
    );

    stage = 'temporary_directory';
    final temporary = await getTemporaryDirectory();
    final resolvedTemporary = await temporary.resolveSymbolicLinks();
    if (!RegExp(
      r'^/data/(user/0|data)/com\.pancyo\.aiastrology\.rework/cache$',
    ).hasMatch(resolvedTemporary)) {
      throw StateError('人工証跡の保存先が改修版のcacheではありません。');
    }
    final createdRoot = await Directory(
      resolvedTemporary,
    ).createTemp('pancyo_period_event_qa_');
    final resolvedRoot = await createdRoot.resolveSymbolicLinks();
    if (!RegExp(
      r'^/data/(user/0|data)/com\.pancyo\.aiastrology\.rework/cache/pancyo_period_event_qa_[^/]+$',
    ).hasMatch(resolvedRoot)) {
      throw StateError('人工証跡の保存先が改修版の専用一時領域ではありません。');
    }
    evidenceRoot = Directory(resolvedRoot);
    manifest = File('$resolvedRoot/manifest.json');
    await _writeManifest(
      manifest,
      mode: mode,
      house: house,
      status: 'running',
      stage: stage,
      rows: rows,
      completed: 0,
    );

    stage = 'native_smoke';
    await _writeManifest(
      manifest,
      mode: mode,
      house: house,
      status: 'running',
      stage: stage,
      rows: rows,
      completed: rows.length,
    );
    final smoke = await Isolate.run(
      NativeSmokeCheck.runAll,
      debugName: 'pancyo-period-event-native-smoke',
    );
    print(
      'PANCYO_REWORK_NATIVE_SMOKE ${jsonEncode({'passed': true, 'checks': smoke})}',
    );

    const runs = [(false, 1), (true, 1), (true, 2), (false, 2)];
    for (var index = 0; index < runs.length; index++) {
      final (reuse, repetition) = runs[index];
      stage = 'comparison_${index + 1}';
      await _writeManifest(
        manifest,
        mode: mode,
        house: house,
        status: 'running',
        stage: stage,
        rows: rows,
        completed: rows.length,
      );
      final row = await Isolate.run(
        () => app.PeriodEventNativeCheck.runOne(
          mode: mode,
          house: house,
          reuse: reuse,
          repetition: repetition,
          temporaryRoot: evidenceRoot!.path,
        ),
        debugName: 'pancyo-artificial-event-comparison',
      );
      rows.add(row);
      await _writeManifest(
        manifest,
        mode: mode,
        house: house,
        status: 'running',
        stage: stage,
        rows: rows,
        completed: rows.length,
      );
      print(
        'PANCYO_REWORK_EVENT_NATIVE_PROGRESS ${jsonEncode({
          'mode': mode.name,
          'house_system': house.name,
          'completed': rows.length,
          'total': runs.length,
          'reuse': reuse,
          'repetition': repetition,
          'context_us': row['context_us'],
          'data_us': row['data_us'],
          'write_us': row['write_us'],
          'work_counts': row['work_counts'],
          'bytes': row['bytes'],
          'sha256': row['sha256'],
        })}',
      );
    }

    stage = 'validation';
    final result = app.PeriodEventNativeCheck.validateRows(
      rows,
      mode: mode,
      house: house,
    );
    await _writeManifest(
      manifest,
      mode: mode,
      house: house,
      status: 'complete',
      stage: stage,
      rows: rows,
      completed: rows.length,
      result: result,
    );
    print('PANCYO_REWORK_EVENT_NATIVE_CHECK ${jsonEncode(result)}');
  } catch (error) {
    final failure = {
      'stage': stage,
      'error_type': error.runtimeType.toString(),
    };
    if (manifest != null) {
      try {
        await _writeManifest(
          manifest,
          mode: mode,
          house: house,
          status: 'failed',
          stage: stage,
          rows: rows,
          completed: rows.length,
          failure: failure,
        );
      } catch (_) {}
    }
    print(
      'PANCYO_REWORK_EVENT_NATIVE_CHECK ${jsonEncode({
        'passed': false,
        'check_failed': true,
        ...failure,
      })}',
    );
  }
}

Future<void> _writeManifest(
  File manifest, {
  required app.LongRangeMode mode,
  required app.HouseSystem house,
  required String status,
  required String stage,
  required List<Map<String, Object?>> rows,
  required int completed,
  Map<String, Object?>? result,
  Map<String, Object?>? failure,
}) async {
  await manifest.writeAsString(
    jsonEncode({
      'status': status,
      'stage': stage,
      'mode': mode.name,
      'house_system': house.name,
      'progress': {'completed': completed, 'total': 4},
      'rows': rows,
      if (result != null) 'result': result,
      if (failure != null) 'failure': failure,
    }),
    flush: true,
  );
}
