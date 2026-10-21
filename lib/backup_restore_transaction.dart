import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BackupRestoreBusyException implements Exception {
  const BackupRestoreBusyException();

  @override
  String toString() => '別のデータ保存処理中です。';
}

class BackupRestoreFailure implements Exception {
  const BackupRestoreFailure({required this.originalDataRestored});

  /// 書込前の失敗、または巻き戻し後の再読込が一致した場合だけtrue。
  final bool originalDataRestored;

  @override
  String toString() => originalDataRestored
      ? '復元に失敗しました。復元前のデータは保たれています。'
      : '復元に失敗しました。保存状態を確認できませんでした。';
}

/// 対象キーだけを検証付きで置換する、メモリ内の最善努力の巻き戻し。
/// 電源断・プロセス終了・別の保存経路との同時更新を保証するものではない。
class BackupRestoreTransaction {
  BackupRestoreTransaction._();

  static bool _running = false;

  static void ensureIdle() {
    if (_running) throw const BackupRestoreBusyException();
  }

  static Future<void> replace({
    required SharedPreferences prefs,
    Map<String, Object?>? values,
    Future<Map<String, Object?>> Function()? prepareValues,
    Future<void> Function()? onVerified,
  }) async {
    if ((values == null) == (prepareValues == null)) {
      throw ArgumentError('保存値か準備処理のどちらか一方が必要です。');
    }
    ensureIdle();
    _running = true;
    final before = <String, Object?>{};
    final attempted = <String>[];
    try {
      // setterのキャッシュ更新は保存成功の証明にならない。原状も再読込する。
      await prefs.reload();
      // 人物一覧の読込・追加も同じ排他内で行い、古い一覧からの上書きを避ける。
      final prepared = values ?? await prepareValues!();
      final expected = {
        for (final entry in prepared.entries) entry.key: _copy(entry.value),
      };
      for (final key in expected.keys) {
        before[key] = _copy(prefs.get(key));
      }
      for (final entry in expected.entries) {
        if (_same(before[entry.key], entry.value)) continue;
        // 例外やfalseが返る前に実際の保存が済む場合も巻き戻す対象にする。
        attempted.add(entry.key);
        if (!await _write(prefs, entry.key, entry.value)) {
          throw StateError('バックアップの保存失敗');
        }
      }
      await prefs.reload();
      if (!_matches(prefs, expected)) {
        throw StateError('バックアップの保存結果が不一致');
      }
      await onVerified?.call();
    } catch (_) {
      var restored = attempted.isEmpty;
      if (attempted.isNotEmpty) {
        var acknowledged = true;
        for (final key in attempted.reversed) {
          try {
            if (!await _write(prefs, key, before[key])) acknowledged = false;
          } catch (_) {
            acknowledged = false;
          }
        }
        try {
          await prefs.reload();
          restored = acknowledged && _matches(prefs, before);
        } catch (_) {
          restored = false;
        }
      }
      // 生の保存エラーや人物情報は例外文・ログへ含めない。
      throw BackupRestoreFailure(originalDataRestored: restored);
    } finally {
      _running = false;
    }
  }

  static Object? _copy(Object? value) =>
      value is List<String> ? List<String>.from(value) : value;

  static bool _same(Object? left, Object? right) =>
      left is List<String> && right is List<String>
      ? listEquals(left, right)
      : left == right;

  static bool _matches(SharedPreferences prefs, Map<String, Object?> values) =>
      values.entries.every((entry) => _same(prefs.get(entry.key), entry.value));

  static Future<bool> _write(
    SharedPreferences prefs,
    String key,
    Object? value,
  ) {
    if (value == null) return prefs.remove(key);
    if (value is String) return prefs.setString(key, value);
    if (value is bool) return prefs.setBool(key, value);
    if (value is int) return prefs.setInt(key, value);
    if (value is double) return prefs.setDouble(key, value);
    if (value is List<String>) return prefs.setStringList(key, value);
    throw StateError('対応しない保存型');
  }
}
