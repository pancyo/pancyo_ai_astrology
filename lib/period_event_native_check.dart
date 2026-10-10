part of 'main.dart';

/// Explicit artificial QA only; never reads profiles or writes preferences.
class PeriodEventNativeCheck {
  const PeriodEventNativeCheck._();

  static const enabled =
      reworkTestBuild &&
      bool.fromEnvironment('PANCYO_PERIOD_EVENT_NATIVE_CHECK');

  static int snapshotCount(LongRangeMode mode) => switch (mode) {
    LongRangeMode.week => 8,
    LongRangeMode.month => 32,
    LongRangeMode.year => 25,
  };

  static Future<Map<String, Object?>> runOne({
    required LongRangeMode mode,
    required HouseSystem house,
    required bool reuse,
    required int repetition,
    required String temporaryRoot,
  }) async {
    if (!enabled || !SwissEphemerisProvider.isAvailable) {
      throw StateError('人工実機検査には明示指定とネイティブ計算が必要です。');
    }
    if (repetition != 1 && repetition != 2) {
      throw ArgumentError('人工反復番号が不正です。');
    }
    final root = await Directory(temporaryRoot).resolveSymbolicLinks();
    if (!RegExp(
      r'^/data/(user/0|data)/com\.pancyo\.aiastrology\.rework/cache/pancyo_period_event_qa_[^/]+$',
    ).hasMatch(root)) {
      throw StateError('人工証跡の保存先が改修版の専用一時領域ではありません。');
    }
    if (SwissEphemerisProvider._voidMoonCache.isNotEmpty ||
        SwissEphemerisProvider._ingressCache.isNotEmpty ||
        SwissEphemerisProvider._voidSegmentMemo.length != 0 ||
        SwissEphemerisProvider._placementFallbackCount != 0) {
      throw StateError('各人工反復には未使用の独立isolateが必要です。');
    }
    const profile = AstroProfile(
      name: 'ReworkPeriodEventFixture',
      birthDate: '1990/1/2',
      birthTime: '12:00',
      birthPlace: '札幌市',
      theme: '仕事',
    );
    final reference = mode == LongRangeMode.year
        ? DateTime(2026, 1, 1, 12)
        : DateTime(2026, 10, 1, 12);
    if (reference.timeZoneOffset != const Duration(hours: 9)) {
      throw StateError('人工JST実機比較の端末タイムゾーンが違います。');
    }
    final originalHouse = HouseSystemSettings.current.value;
    HouseSystemSettings.current.value = house;
    try {
      HoroscopeReadingContext reading(DateTime date) {
        final value = const AstrologyEngine().buildPreviewContext(
          profile: profile,
          date: date,
        );
        if (!value.usesHighPrecisionAstroData || value.houseSystem != house) {
          throw StateError('人工配置の精度または方式が要求と違います。');
        }
        return value;
      }

      final contextWatch = Stopwatch()..start();
      final context = reading(reference);
      contextWatch.stop();
      final counts = AstroEventWorkCounts();
      final builder = PeriodConsultDataBuilder(
        mode: mode,
        periodLabel: '架空期間（実機検査専用）',
        weekStart: DateTime(2026, 10, 1),
        month: DateTime(2026, 10),
        year: 2026,
        profile: profile,
        details: const UserProfileDetails.empty(),
        contextData: context,
        cards: const [],
        contextResolver: reading,
        reuseEventSearches: reuse,
        eventWorkCounts: counts,
      );
      final issued = DateTime.utc(2026, 10, 1, 3);
      final dataWatch = Stopwatch()..start();
      final data = builder.buildData(generatedAt: issued);
      dataWatch.stop();
      if (SwissEphemerisProvider._placementFallbackCount != 0) {
        throw StateError('人工比較に近似配置への代用が混入しました。');
      }
      final writeWatch = Stopwatch()..start();
      final file = await ConsultJsonFileWriter.write(
        temporaryRoot: Directory(root),
        data: data,
        participantName: profile.name,
        kind: mode.name,
        period: switch (mode) {
          LongRangeMode.week => '20261001',
          LongRangeMode.month => '202610',
          LongRangeMode.year => '2026',
        },
        generatedAt: issued,
      );
      writeWatch.stop();
      final bytes = await file.readAsBytes();
      return {
        'mode': mode.name,
        'house_system': house.name,
        'reuse': reuse,
        'repetition': repetition,
        'cold_cache': true,
        'high_precision': true,
        'placement_fallbacks': 0,
        'context_us': contextWatch.elapsedMicroseconds,
        'data_us': dataWatch.elapsedMicroseconds,
        'write_us': writeWatch.elapsedMicroseconds,
        'cached_contexts': builder.cachedContextCount,
        'work_counts': counts.safeSnapshot,
        'bytes': bytes.length,
        'sha256': sha256.convert(bytes).toString(),
        'file_path': file.path,
      };
    } finally {
      HouseSystemSettings.current.value = originalHouse;
    }
  }

  /// Pure validation, also exercised with synthetic host evidence.
  static Map<String, Object?> validateRows(
    List<Map<String, Object?>> rows, {
    required LongRangeMode mode,
    required HouseSystem house,
  }) {
    if (rows.length != 4) throw StateError('人工反復が4件完了していません。');
    final expectedOrder = [(false, 1), (true, 1), (true, 2), (false, 2)];
    final digest = rows.first['sha256'];
    final bytes = rows.first['bytes'];
    if (digest is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest) ||
        bytes is! int ||
        bytes <= 0) {
      throw StateError('人工JSONの証跡が不正です。');
    }
    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      final (reuse, repetition) = expectedOrder[index];
      final count = snapshotCount(mode) * (reuse ? 1 : 2);
      final work = row['work_counts'];
      if (row['mode'] != mode.name ||
          row['house_system'] != house.name ||
          row['reuse'] != reuse ||
          row['repetition'] != repetition ||
          row['cold_cache'] != true ||
          row['high_precision'] != true ||
          row['placement_fallbacks'] != 0 ||
          row['cached_contexts'] != snapshotCount(mode) - 1 ||
          row['sha256'] != digest ||
          row['bytes'] != bytes ||
          work is! Map ||
          work.length != 2 ||
          work['station_calls'] != count ||
          work['lunar_phase_calls'] != count) {
        throw StateError('人工JSON全文・探索回数・精度・反復条件が不一致です。');
      }
      for (final key in ['context_us', 'data_us', 'write_us']) {
        if (row[key] is! int || (row[key] as int) < 0) {
          throw StateError('人工計測値が不正です。');
        }
      }
    }
    return {'passed': true, 'full_json_matches': 4, 'placement_fallbacks': 0};
  }
}
