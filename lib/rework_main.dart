import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/widgets.dart';

import 'main.dart' as app;
import 'research/native_smoke_check.dart';

// 別パッケージのローカル確認専用。正式版のエントリーポイントはmain.dartのまま。
Future<void> main() async {
  if (!app.reworkTestBuild) {
    throw StateError('改修テストの明示オプションが必要です。');
  }
  WidgetsFlutterBinding.ensureInitialized();
  // 初画面を先に描画し、人工データの星計算は別isolateで実施する。
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_runNativeSmoke());
  });
  await app.main();
}

Future<void> _runNativeSmoke() async {
  try {
    final checks = await Isolate.run(NativeSmokeCheck.runAll);
    print(
      'PANCYO_REWORK_NATIVE_SMOKE ${jsonEncode({'passed': true, 'checks': checks})}',
    );
    if (const bool.fromEnvironment('PANCYO_VOID_MEMO_CHECK')) {
      try {
        final result = await Isolate.run(app.MoonVoidMemoCheck.run);
        print('PANCYO_REWORK_VOID_MEMO_CHECK ${jsonEncode(result)}');
      } catch (error) {
        print(
          'PANCYO_REWORK_VOID_MEMO_CHECK ${jsonEncode({'passed': false, 'error': error.toString()})}',
        );
      }
    }
  } catch (error) {
    print(
      'PANCYO_REWORK_NATIVE_SMOKE ${jsonEncode({'passed': false, 'error': error.toString()})}',
    );
  }
}
