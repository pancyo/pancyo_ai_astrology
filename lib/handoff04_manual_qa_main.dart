import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart' as crypto;

import 'main.dart' as app;

// Separate, artificial-only entry point. Installed-user APK uses
// rework_preserve_main.dart and never opens this page or these fixtures.
void main() {
  if (!app.reworkTestBuild)
    throw StateError('Explicit rework QA build required.');
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: const _ManualChecks(),
    ),
  );
}

const _profile = app.AstroProfile(
  name: 'YearFlowFiction',
  birthDate: '2000/1/2',
  birthTime: '12:00',
  birthPlace: '北海道札幌市',
  theme: '架空の動作確認',
);

class _ManualChecks extends StatefulWidget {
  const _ManualChecks();
  @override
  State<_ManualChecks> createState() => _ManualChecksState();
}

class _ManualChecksState extends State<_ManualChecks> {
  bool _running = false;
  String _report = '未実行。下の操作を選ぶまで検査を開始しません。';

  Future<void> _compareNative() async {
    setState(() {
      _running = true;
      _report = '旧scalar経路と新batch経路を照合しています。';
    });
    try {
      final result = await Isolate.run(app.MoonVoidBatchCheck.run);
      final value = jsonEncode(result);
      final bytes = utf8.encode(value);
      final encoded = base64Encode(bytes);
      final count = (encoded.length + 2799) ~/ 2800;
      debugPrint(
        'HANDOFF04_NATIVE_BEGIN:$count:${bytes.length}:${crypto.sha256.convert(bytes)}',
      );
      for (var i = 0; i < count; i++) {
        final end = (i + 1) * 2800;
        debugPrint(
          'HANDOFF04_NATIVE_CHUNK:$i/$count:${encoded.substring(i * 2800, end < encoded.length ? end : encoded.length)}',
          wrapWidth: 1000000,
        );
      }
      debugPrint('HANDOFF04_NATIVE_END:$count');
      if (mounted) setState(() => _report = value);
    } catch (error, stack) {
      debugPrint('HANDOFF04_NATIVE_FAILURE:$error\n$stack', wrapWidth: 1000000);
      if (mounted) setState(() => _report = '失敗：$error');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<List<app.SavedUserProfile>> _fictionProfiles() async => [
    app.SavedUserProfile(
      id: 'qa-fiction-a',
      name: 'Fiction A',
      birthDate: '2000/1/2',
      details: const app.UserProfileDetails(
        birthTime: '12:00',
        birthPlace: '北海道札幌市',
        personality: '',
        concerns: '',
        readingStyle: '',
      ),
      updatedAt: DateTime.utc(2026, 10, 10),
    ),
    app.SavedUserProfile(
      id: 'qa-fiction-b',
      name: 'Fiction B',
      birthDate: '2001/2/3',
      details: const app.UserProfileDetails(
        birthTime: '09:15',
        birthPlace: '東京都',
        personality: '',
        concerns: '',
        readingStyle: '',
      ),
      updatedAt: DateTime.utc(2026, 10, 10),
    ),
  ];

  void _open(Widget page) => Navigator.of(
    context,
  ).push<void>(MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('HANDOFF-04 専用機の架空検査')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('架空入力の専用検査です。相性の隔離ボタンだけが登録データも架空です。通常画面の保存・設定・共有は操作しません。'),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _running ? null : _compareNative,
            child: const Text('nativeの新旧同値を確認'),
          ),
          FilledButton(
            onPressed: () => _open(
              const app.ResultScreen(
                profile: _profile,
                initialDetails: app.UserProfileDetails.empty(),
              ),
            ),
            child: const Text('通常の画面・年グラフ（架空未保存）'),
          ),
          FilledButton(
            onPressed: () => _open(
              Scaffold(
                appBar: AppBar(title: const Text('相性の隔離データ検査')),
                body: SafeArea(
                  child: app.RelationshipReading(
                    profile: _profile,
                    details: const app.UserProfileDetails.empty(),
                    savedProfilesLoader: _fictionProfiles,
                  ),
                ),
              ),
            ),
            child: const Text('相性・恋愛（架空の登録データ）'),
          ),
          FilledButton(
            onPressed: () => _open(
              app.AstrologyCalendarView(initialDate: DateTime(2026, 10, 4)),
            ),
            child: const Text('星のカレンダー'),
          ),
          const SizedBox(height: 12),
          SelectableText(_report),
        ],
      ),
    ),
  );
}
