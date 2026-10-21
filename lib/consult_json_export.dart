import 'dart:convert';
import 'dart:io';
import 'research/json_research_preview.dart';

/// AI相談用の記名JSON。匿名の研究用予測とは別の保存処理。
class ConsultJsonFileWriter {
  const ConsultJsonFileWriter._();

  /// Research metadata is emitted only when explicitly requested.
  static String serialize(Map<String, Object?> data, {
    ResearchPreviewOptions? researchPreview,
  }) => const JsonEncoder.withIndent('  ').convert(researchPreview == null
      ? data : ResearchJsonPreview.build(data, researchPreview));

  static String safeParticipantName(String name) {
    var safe = name
        .trim()
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f\x7f-\x9f]'), '_')
        .replaceAll(RegExp('[\u202a-\u202e\u2066-\u2069]'), '_');
    safe = String.fromCharCodes(
      safe.runes.take(40),
    ).replaceAll(RegExp(r'^[. ]+|[. ]+$'), '');
    return safe.isEmpty ? '氏名未設定' : safe;
  }

  static Future<File> write({
    required Directory temporaryRoot,
    required Map<String, Object?> data,
    required String participantName,
    required String kind,
    required String period,
    DateTime? generatedAt,
    ResearchPreviewOptions? researchPreview,
  }) async {
    final validPeriod = switch (kind) {
      'daily' || 'week' => RegExp(r'^\d{8}$').hasMatch(period),
      'month' => RegExp(r'^\d{6}$').hasMatch(period),
      'year' => RegExp(r'^\d{4}$').hasMatch(period),
      _ => false,
    };
    if (!validPeriod) throw const FormatException('相談用JSONの対象期間が不正です。');
    // シリアライズしてから排他的な一時領域を作り、再出力・同時作成で上書きしない。
    final json = serialize(data, researchPreview: researchPreview);
    final issued = (generatedAt ?? DateTime.now())
        .toUtc()
        .toIso8601String()
        .replaceAll(RegExp(r'[-:.]'), '');
    final name = researchPreview == null
        ? safeParticipantName(participantName) : 'anonymous-research';
    final prefix = researchPreview == null
        ? 'pancyo_astrology' : 'pancyo_research_preview';
    final folder = await temporaryRoot.createTemp('pancyo_consult_');
    final file = File(
      '${folder.path}${Platform.pathSeparator}'
      '${prefix}_${kind}_${name}_${period}_$issued.json',
    );
    await file.writeAsString(json, flush: true);
    return file;
  }
}
