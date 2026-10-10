import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_language.dart';
import 'backup_restore_transaction.dart';

/// Display-only preference, separate from profile/forecast/backup model data.
/// Reading old settings does not create, migrate, or rewrite any saved values.
class AppLanguageSettings {
  AppLanguageSettings._();
  static const storageKey = 'astrology.ui_language';
  static final current = ValueNotifier(AppLanguage.defaultLanguage);
  static bool _saving = false;
  static AppStrings get strings => AppStrings(current.value);

  static Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    current.value = AppLanguage.fromStored(prefs.get(storageKey));
  }

  static Future<void> save(AppLanguage language) async {
    if (_saving) throw StateError('Display language is already being saved.');
    _saving = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await BackupRestoreTransaction.replace(
        prefs: prefs,
        values: {storageKey: language.code},
        onVerified: () async => current.value = language,
      );
    } finally {
      _saving = false;
    }
  }
}

/// Subscribes display widgets to live language changes without recalculating
/// or translating their canonical prediction and profile data.
class AppLanguageScope extends InheritedNotifier<ValueNotifier<AppLanguage>> {
  AppLanguageScope({super.key, required super.child})
    : super(notifier: AppLanguageSettings.current);

  static AppStrings stringsOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppLanguageScope>();
    return AppStrings(scope?.notifier?.value ?? AppLanguageSettings.current.value);
  }
}
