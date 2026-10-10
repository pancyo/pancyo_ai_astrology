import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

enum BackupStoreFault {
  falseBeforeWrite,
  throwBeforeWrite,
  falseAfterWrite,
  throwAfterWrite,
  acknowledgeWithoutWrite,
}

/// 架空データだけを保持し、実端末へ接続しない保存障害用バックエンド。
class BackupFaultStore extends SharedPreferencesStorePlatform {
  BackupFaultStore(Map<String, Object> initial)
    : _data = {
        for (final entry in initial.entries)
          'flutter.${entry.key}': _copy(entry.value),
      };

  final Map<String, Object> _data;
  final faults = <int, BackupStoreFault>{};
  final readFailures = <int>{};
  final operations = <String>[];
  Future<void> Function(int operation)? waitForMutation;
  int mutations = 0;
  int reads = 0;

  static Object _copy(Object value) =>
      value is List<String> ? List<String>.from(value) : value;

  Map<String, Object> snapshot() => {
    for (final entry in _data.entries)
      entry.key.substring('flutter.'.length): _copy(entry.value),
  };

  void putFromNative(String key, Object value) {
    _data['flutter.$key'] = _copy(value);
  }

  @override
  Future<Map<String, Object>> getAll() async {
    if (readFailures.contains(++reads)) throw StateError('架空の読込失敗');
    return {for (final entry in _data.entries) entry.key: _copy(entry.value)};
  }

  Future<bool> _mutate(String action, String key, Object? value) async {
    final operation = ++mutations;
    operations.add('$action:$key');
    await waitForMutation?.call(operation);
    final fault = faults[operation];
    if (fault == BackupStoreFault.falseBeforeWrite) return false;
    if (fault == BackupStoreFault.throwBeforeWrite) {
      throw StateError('架空の書込失敗');
    }
    if (fault == BackupStoreFault.acknowledgeWithoutWrite) return true;
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = _copy(value);
    }
    if (fault == BackupStoreFault.falseAfterWrite) return false;
    if (fault == BackupStoreFault.throwAfterWrite) {
      throw StateError('架空の書込後失敗');
    }
    return true;
  }

  @override
  Future<bool> remove(String key) => _mutate('remove', key, null);

  @override
  Future<bool> setValue(String valueType, String key, Object value) =>
      _mutate('set$valueType', key, value);

  @override
  Future<bool> clear() async => throw StateError('全設定のclearは禁止');
}
