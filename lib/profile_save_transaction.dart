import 'package:shared_preferences/shared_preferences.dart';

import 'backup_restore_transaction.dart';

class ProfileSaveBusyException implements Exception {
  const ProfileSaveBusyException();

  @override
  String toString() => 'プロフィールの保存またはバックアップの復元中です。';
}

class ProfileSaveFailure implements Exception {
  const ProfileSaveFailure({required this.originalDataRestored});

  final bool originalDataRestored;

  @override
  String toString() => originalDataRestored
      ? 'プロフィールを保存できませんでした。保存前のデータは保たれています。'
      : 'プロフィールを保存できませんでした。元の保存状態へ戻せたか確認できません。';
}

/// バックアップと同じ排他・照合・最善努力の巻き戻しを通常保存にも使う。
/// 電源断や、この処理を使わない保存経路の同時書込までは保証しない。
class ProfileSaveTransaction {
  const ProfileSaveTransaction._();

  static Future<void> write({
    required SharedPreferences prefs,
    required Future<Map<String, Object?>> Function() prepareValues,
  }) async {
    try {
      await BackupRestoreTransaction.replace(
        prefs: prefs,
        prepareValues: prepareValues,
      );
    } on BackupRestoreBusyException {
      throw const ProfileSaveBusyException();
    } on BackupRestoreFailure catch (failure) {
      throw ProfileSaveFailure(
        originalDataRestored: failure.originalDataRestored,
      );
    }
  }
}
