import 'dart:convert';
import 'dart:io';

/// 一時JSONの作成だけを担当。共有先での永続保存は保証しない。
class ForecastFileWriter {
  const ForecastFileWriter._();

  static Future<File> write(
    Directory temporaryRoot,
    Map<String, Object?> data,
  ) async {
    final day = data['target_date_jst'];
    final issued = data['issued_at_jst_device_clock'];
    if (data['schema'] != 'pancyo_nine_area_forecast_v1' ||
        data['forecast_only'] != true ||
        data['outcome_included'] != false ||
        day is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day) ||
        issued is! String ||
        !issued.endsWith('+09:00')) {
      throw const FormatException('専用の事前予測JSONではありません。');
    }
    final issuedAt = DateTime.tryParse(issued);
    if (issuedAt == null) throw const FormatException('予測の発行時刻が不正です。');
    // シリアライズ失敗時は一時ディレクトリも作らない。
    final json = const JsonEncoder.withIndent('  ').convert(data);
    // OSの排他的な一時ディレクトリ作成を使い、時計の巻き戻りや同時刻でも上書きしない。
    final folder = await temporaryRoot.createTemp('pancyo_forecast_');
    final nonce = folder.path.split(Platform.pathSeparator).last;
    final file = File(
      '${folder.path}${Platform.pathSeparator}'
      'pancyo_nine_area_forecast_${day.replaceAll('-', '')}_${issuedAt.toUtc().microsecondsSinceEpoch}_$nonce.json',
    );
    await file.writeAsString(json, flush: true);
    return file;
  }
}
