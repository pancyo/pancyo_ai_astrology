import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_language.dart';
import 'app_language_settings.dart';
import 'birth_clock.dart';
import 'civil_time.dart';

/// Resolve before saving. A null result means cancel/reject, never legacy or JST
/// fallback. This function itself does not write storage or calculate a chart.
Future<ResolvedBirthClock?> resolveBirthClockWithChoice(
  BuildContext context, {
  required String zoneId,
  required String birthDate,
  required String birthTime,
  RegionalTimeResolver resolver = const AndroidRegionalTimeResolver(),
}) async {
  if (!context.mounted) return null;
  final en = AppLanguageSettings.current.value == AppLanguage.en;
  late final CivilClockTime local;
  try {
    local = _parseBirthClock(birthDate, birthTime);
  } on FormatException {
    await _explain(
      context,
      en: en,
      code: 'invalid-clock',
      ja: '出生日時を年月日の順（YYYY/M/D または YYYY-MM-DD）、時刻はHH:mmで入力してください。存在しない日付や時刻は使えません。',
      english:
          'Enter the birth date in year/month/day order (YYYY/M/D or YYYY-MM-DD), and the time as HH:mm. The date and time must exist.',
    );
    return null;
  }
  if (zoneId.length > 100 ||
      !RegExp(
        r'^[A-Za-z][A-Za-z0-9_+.-]*(/[A-Za-z0-9_+.-]+)*$',
      ).hasMatch(zoneId)) {
    await _explain(
      context,
      en: en,
      code: 'invalid-zone',
      ja: '出生地の地域タイムゾーンIDを確認してください（例：America/New_York）。表示言語や現在の端末時差からは推定しません。',
      english:
          'Check the birthplace region time-zone ID, such as America/New_York. It is not inferred from the display language or device time zone.',
    );
    return null;
  }
  try {
    final source = resolver.source;
    final resolution = await resolver.resolveLocal(
      zoneId: zoneId,
      local: local,
    );
    if (!context.mounted) return null;
    if (resolution.zoneId != zoneId ||
        resolution.local.label != local.label ||
        resolver.source != source) {
      throw const FormatException('Regional clock response changed identity.');
    }
    if (resolution.status == CivilResolutionStatus.gap) {
      await _explain(
        context,
        en: en,
        code: 'gap',
        ja: 'この出生地では、時計の変更により入力された現地時刻が存在しません。時刻を自動でずらさず、出生記録を確認して入力し直してください。',
        english:
            'This local time did not exist in the birthplace because the clock changed. It will not be shifted automatically. Check the birth record and enter a valid time.',
      );
      return null;
    }
    if (resolution.status == CivilResolutionStatus.unique) {
      return ResolvedBirthClock.fromResolution(
        resolution: resolution,
        resolverSource: source,
      );
    }
    // Validate the returned candidate set before presenting either choice.
    final validated = CivilTimeResolution(
      zoneId: resolution.zoneId,
      local: resolution.local,
      status: resolution.status,
      candidates: resolution.candidates,
      tzdbVersion: resolution.tzdbVersion,
    );
    final providerLabel = resolver is AndroidRegionalTimeResolver
        ? 'Android ZoneRules'
        : source;
    final chosen = await showDialog<DateTime>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('birth-clock-overlap'),
        title: Text(en ? 'Choose the birth time' : '出生時刻の候補を選択'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                en
                    ? 'This local time occurred twice when the clock changed. Select the candidate that matches the birth record.'
                    : '時計の変更により、この現地時刻は2回あります。出生記録に合う候補を明示的に選択してください。',
              ),
              const SizedBox(height: 8),
              Text('$zoneId\n${local.label}\n$providerLabel'),
              for (var index = 0; index < validated.candidates.length; index++)
                TextButton(
                  key: ValueKey('birth-clock-candidate-$index'),
                  onPressed: () => Navigator.of(
                    dialogContext,
                  ).pop(validated.candidates[index].instantUtc),
                  child: Text(
                    '${_offset(validated.candidates[index].offsetSeconds)}\n${validated.candidates[index].instantUtc.toIso8601String()}',
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('birth-clock-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(en ? 'Cancel' : '中止'),
          ),
        ],
      ),
    );
    if (!context.mounted || chosen == null) return null;
    return ResolvedBirthClock.fromResolution(
      resolution: validated,
      resolverSource: source,
      explicitUtc: chosen,
    );
  } on PlatformException catch (error) {
    if (!context.mounted) return null;
    final invalid =
        error.code == 'invalid_civil_time' || error.code == 'invalid_zone';
    await _explain(
      context,
      en: en,
      code: invalid ? 'invalid-zone-or-clock' : 'unavailable',
      ja: invalid
          ? '地域タイムゾーンまたは現地の出生日時を認識できません。入力を確認してください。'
          : '地域の時刻ルールを取得できません。保存せず中止しました。もう一度お試しください。',
      english: invalid
          ? 'The region time zone or local birth date and time was not recognized. Check the input.'
          : 'Regional clock rules are unavailable. Saving was cancelled. Please try again.',
    );
  } on MissingPluginException {
    if (!context.mounted) return null;
    await _explain(
      context,
      en: en,
      code: 'unavailable',
      ja: 'この環境では地域の時刻ルールを利用できません。保存せず中止しました。',
      english:
          'Regional clock rules are not available in this environment. Saving was cancelled.',
    );
  } on FormatException {
    if (!context.mounted) return null;
    await _explain(
      context,
      en: en,
      code: 'invalid-response',
      ja: '出生時刻の変換結果を確認できないため、保存せず中止しました。',
      english:
          'The birth-time conversion could not be verified. Saving was cancelled.',
    );
  } catch (_) {
    if (!context.mounted) return null;
    await _explain(
      context,
      en: en,
      code: 'unavailable',
      ja: '出生時刻を解決できませんでした。保存せず中止しました。もう一度お試しください。',
      english:
          'The birth time could not be resolved. Saving was cancelled. Please try again.',
    );
  }
  return null;
}

CivilClockTime _parseBirthClock(String birthDate, String birthTime) {
  final date =
      RegExp(r'^(\d{4})/(\d{1,2})/(\d{1,2})$').firstMatch(birthDate.trim()) ??
      RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(birthDate.trim());
  final time = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(birthTime.trim());
  if (date == null || time == null)
    throw const FormatException('Invalid birth-clock fields.');
  return CivilClockTime.parse(
    '${date[1]}-${date[2]!.padLeft(2, '0')}-${date[3]!.padLeft(2, '0')}',
    '${time[1]}:${time[2]}:00',
  );
}

String _offset(int seconds) {
  final absolute = seconds.abs();
  final hour = (absolute ~/ 3600).toString().padLeft(2, '0');
  final minute = ((absolute % 3600) ~/ 60).toString().padLeft(2, '0');
  final remainder = absolute % 60;
  return 'UTC${seconds < 0 ? '-' : '+'}$hour:$minute${remainder == 0 ? '' : ':${remainder.toString().padLeft(2, '0')}'}';
}

Future<void> _explain(
  BuildContext context, {
  required bool en,
  required String code,
  required String ja,
  required String english,
}) async {
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: ValueKey('birth-clock-error-$code'),
      title: Text(en ? 'Check the birth time' : '出生時刻を確認'),
      content: SingleChildScrollView(child: Text(en ? english : ja)),
      actions: [
        TextButton(
          key: const ValueKey('birth-clock-close'),
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(en ? 'Close' : '閉じる'),
        ),
      ],
    ),
  );
}
