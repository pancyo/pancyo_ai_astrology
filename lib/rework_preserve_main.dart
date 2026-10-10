import 'package:flutter/widgets.dart';

import 'app_language_settings.dart';
import 'main.dart' as app;

/// Local rework UI for installed users. Restore settings without running
/// legacy cleanup or any automatic fixture checks against their device.
Future<void> main() async {
  if (!app.reworkTestBuild) {
    throw StateError('改修テストの明示オプションが必要です。');
  }
  WidgetsFlutterBinding.ensureInitialized();
  await app.HouseSystemSettings.restore();
  await app.TextScaleSettings.restore();
  await AppLanguageSettings.restore();
  runApp(const app.PancyoAstrologyApp());
}
