part of 'main.dart';

/// A new, exclusive folder and a non-JSON staging file protect existing output.
/// Only validated, flushed and read-back content receives its final .json name.
class MonthlyDailyConsultFileWriter {
  /// Keep decoding, validation and serialization off the UI isolate as well.
  static Future<File> writeResult({
    required String temporaryRootPath,
    required MonthlyDailyConsultExportResult result,
    required MonthlyDailyConsultExportRequest request,
  }) async {
    final path = await Isolate.run(() async {
      if (result.requestIdentity != request.identity) {
        throw StateError('月間JSONの入力が一致しません。');
      }
      final data = result.data;
      _validateMonthlyDailyConsultData(data, request);
      final file = await write(
        temporaryRoot: Directory(temporaryRootPath), data: data,
        participantName: request.profile.name,
        period: request.startDateJst.substring(0, 7).replaceAll('-', ''),
        generatedAt: request.generatedAt, isCurrent: () => true,
      );
      return file.path;
    }, debugName: 'pancyo-monthly-json-save-readback');
    return File(path);
  }

  static Future<File> write({
    required Directory temporaryRoot,
    required Map<String, Object?> data,
    required String participantName,
    required String period,
    required bool Function() isCurrent,
    DateTime? generatedAt,
  }) async {
    _monthlyValidateWrapper(data);
    if (!RegExp(r'^\d{6}$').hasMatch(period) ||
        (_monthlyMap(data['month'], 'month')['start_date_jst'] as String)
                .substring(0, 7)
                .replaceAll('-', '') !=
            period) {
      throw const FormatException('対象月が一致しません。');
    }
    void check() {
      if (!isCurrent()) throw const MonthlyDailyConsultExportCancelled();
    }

    check();
    final text = ConsultJsonFileWriter.serialize(data);
    final folder = await temporaryRoot.createTemp('pancyo_monthly7_');
    try {
      check();
      final staging = File(
        '${folder.path}${Platform.pathSeparator}output.partial',
      );
      await staging.writeAsString(text, flush: true);
      check();
      final readback = await staging.readAsString();
      if (readback != text) throw StateError('保存後の読み戻しが一致しません。');
      _monthlyValidateWrapper(
        Map<String, Object?>.from(jsonDecode(readback) as Map),
      );
      check();
      final issued = (generatedAt ?? DateTime.now())
          .toUtc()
          .toIso8601String()
          .replaceAll(RegExp(r'[-:.]'), '');
      final name = ConsultJsonFileWriter.safeParticipantName(participantName);
      final result = await staging.rename(
        '${folder.path}${Platform.pathSeparator}'
        'pancyo_astrology_monthly7_${name}_${period}_$issued.json',
      );
      check();
      return result;
    } catch (_) {
      if (await folder.exists()) await folder.delete(recursive: true);
      rethrow;
    }
  }
}
