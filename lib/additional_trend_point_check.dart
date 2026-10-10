part of 'main.dart';

/// Artificial opt-in QA only. No preferences, sharing, or development screen.
class AdditionalTrendPointCheck {
  const AdditionalTrendPointCheck._();
  static const enabled =
      reworkTestBuild && bool.fromEnvironment('PANCYO_ADDITIONAL_POINT_CHECK');
  static const labels = ['健康', '対人', '行動／決断'];
  static const keys = ['health', 'people', 'actionDecision'];
  static const colors = [0xFF70B7FF, 0xFFFFBA7A, 0xFF67E0C0];
  static const candidates = ['最悪', '悪い', '普通', '良い', '最高'];
  static final _captured = <Object>{};
  static bool _busy = false;

  static void _checkFixture(PeriodTrendRequest request) {
    if (!PeriodTrendPointCheck.isFixture(request) ||
        request.mode == LongRangeMode.week) {
      throw StateError('月年の人工検査人物ではありません。');
    }
  }

  // Independent of NineAreaPeriodSummary.sampleDates and request.dates.
  static List<DateTime> sampleDates(LongRangeMode mode, DateTime point) {
    if (mode == LongRangeMode.month) {
      final last = DateTime.utc(
        point.year,
        point.month + 1,
        1,
      ).subtract(const Duration(days: 1)).day;
      return [
        for (final day in [1, 8, 15, 22, last])
          DateTime.utc(point.year, point.month, day, 3),
      ];
    }
    if (mode == LongRangeMode.year) {
      return [
        for (var m = 1; m <= 12; m++)
          for (final day in [1, 15]) DateTime.utc(point.year, m, day, 3),
      ];
    }
    throw ArgumentError('週は追加項目の検査対象ではありません。');
  }

  static String axisLabel(LongRangeMode mode, DateTime point) =>
      mode == LongRangeMode.year ? '${point.year}' : '${point.month}月';

  static int feltColor(String label) => switch (label) {
    '最高' || '良い' => 0xFFF6D77A,
    '普通' => 0xFFB58CFF,
    '悪い' => 0xFFFF2D8F,
    '最悪' => 0xFF57D6D1,
    '混在' || '未予測' => 0xB3FFFFFF,
    _ => throw StateError('未知の体感候補。'),
  };

  /// Reads the unchanged daily-consult nine-area section, not period summaries.
  /// Keeps daily inputs for a second independent PC aggregation.
  static Map<String, Object?> aggregate(
    LongRangeMode mode,
    DateTime point,
    List<Map<String, Object?>> daily,
  ) {
    final dates = sampleDates(mode, point);
    if (daily.length != dates.length) throw StateError('日JSONの確認数が不一致。');
    final sums = List<int>.filled(3, 0);
    final counts = List<int>.filled(6, 0);
    final evidence = <Map<String, Object?>>[];
    for (var i = 0; i < daily.length; i++) {
      final json = daily[i];
      final date = dates[i];
      final day = date.toIso8601String().substring(0, 10);
      if (json['schema'] != 'pancyo_nine_area_daily_consult_v1' ||
          json['model_version'] != NineAreaDailyForecast.modelVersion ||
          json['target_date_jst'] != day ||
          json['calculation_reference_jst'] != '${day}T12:00:00.000+09:00') {
        throw StateError('日JSONの時点・モデルが不一致。');
      }
      final areas = (json['areas'] as List).cast<Map>();
      if (areas.length != 9 || areas.map((a) => a['key']).toSet().length != 9) {
        throw StateError('日JSONの9項目が不一致。');
      }
      final scores = <int>[];
      for (var column = 0; column < 3; column++) {
        final score = areas.singleWhere(
          (a) => a['key'] == keys[column],
        )['score'];
        if (score is! int || score < 50 || score > 99) {
          throw StateError('日JSONの数値が不足または範囲外。');
        }
        sums[column] += score;
        scores.add(score);
      }
      final felt = areas.singleWhere((a) => a['key'] == 'felt');
      final label = felt['predicted_felt_label'];
      if (felt['score'] != null ||
          (label != null && !candidates.contains(label))) {
        throw StateError('体感を数値や未知の候補として集計できません。');
      }
      counts[label == null ? 5 : candidates.indexOf(label as String)]++;
      evidence.add({
        'date_utc': date.toIso8601String(),
        'house_system': json['house_system'],
        'uses_high_precision_astro_data':
            json['uses_high_precision_astro_data'],
        'scores': scores,
        'felt_label': label,
      });
    }
    // Positive integer half-up rounding, implemented without summary.round().
    final scores = [
      for (final sum in sums) (sum * 2 + daily.length) ~/ (daily.length * 2),
    ];
    final maximum = counts.take(5).reduce((a, b) => a > b ? a : b);
    final winners = [
      if (maximum > 0)
        for (var i = 0; i < 5; i++)
          if (counts[i] == maximum) candidates[i],
    ];
    final felt = winners.isEmpty
        ? '未予測'
        : winners.length > 1
        ? '混在'
        : winners.single;
    final sampling = mode == LongRangeMode.month
        ? '月内1・8・15・22・末日の5時点（12:00 JST）'
        : '各月1日・15日の24時点（12:00 JST）';
    final distribution = [
      for (var i = 0; i < 5; i++) '${candidates[i]} ${counts[i]}件',
      '未予測 ${counts[5]}件',
    ].join(' / ');
    final detail =
        '$sampling\n$distribution\n'
        '最多同数は混在、全欠測は未予測。確認時点の件数であり、全日の割合や的中率ではありません。';
    final axis = axisLabel(mode, point);
    return {
      'label': axis,
      'scores': scores,
      'felt_label': felt,
      'felt_color_argb': feltColor(felt),
      'felt_counts': counts,
      'felt_detail': detail,
      'point_detail':
          '$axis\n${[for (var i = 0; i < 3; i++) '${labels[i]} ${scores[i]}点'].join('／')}\n体感 $felt\n$detail',
      'daily_samples': evidence,
    };
  }

  static Map<String, Object?> reference(PeriodTrendRequest request) {
    _checkFixture(request);
    if (request.requireHighPrecision && !SwissEphemerisProvider.isAvailable) {
      throw StateError('独立ネイティブ照合を利用できません。');
    }
    final beforeHouse = HouseSystemSettings.current.value;
    final beforeFallback = SwissEphemerisProvider._placementFallbackCount;
    final watch = Stopwatch()..start();
    try {
      HouseSystemSettings.current.value = request.houseSystem;
      final points = request.mode == LongRangeMode.month
          ? [
              for (var m = 1; m <= 12; m++)
                DateTime.utc(request.month.year, m, 1, 3),
            ]
          : [
              for (var y = request.year; y < request.year + 10; y++)
                DateTime.utc(y, 1, 1, 3),
            ];
      final rows = <Map<String, Object?>>[];
      for (final point in points) {
        final samples = <Map<String, Object?>>[];
        for (final date in sampleDates(request.mode, point)) {
          final context = const AstrologyEngine().buildPreviewContext(
            profile: request.profile,
            date: date,
          );
          if (request.requireHighPrecision &&
              (!context.usesHighPrecisionAstroData ||
                  context.houseSystem != request.houseSystem)) {
            throw StateError('日JSONの精度または方式が不一致。');
          }
          samples.add(
            NineAreaDailyConsultSnapshot.build(
              date: date,
              contextData: context,
            ),
          );
        }
        rows.add(aggregate(request.mode, point, samples));
        if (enabled && request.requireHighPrecision) {
          print(
            'PANCYO_REWORK_ADDITIONAL_POINT_PROGRESS ${jsonEncode({'mode': request.mode.name, 'house_system': request.houseSystem.name, 'completed': rows.length, 'total': points.length})}',
          );
        }
      }
      if (request.requireHighPrecision &&
          SwissEphemerisProvider._placementFallbackCount != beforeFallback) {
        throw StateError('日JSONの独立計算で近似代用が発生。');
      }
      return {
        'reference_route':
            'independent_daily_consult_section_manual_aggregation',
        'uses_high_precision_astro_data':
            AstrologyDataSources.current.usesHighPrecisionAstroData,
        'reference_ms': watch.elapsedMilliseconds,
        'daily_model_version': NineAreaDailyForecast.modelVersion,
        'period_model_version': NineAreaPeriodSummary.modelVersion,
        'dates_utc': [for (final point in points) point.toIso8601String()],
        'rows': rows,
      };
    } finally {
      HouseSystemSettings.current.value = beforeHouse;
    }
  }

  static Map<String, Object?> snapshot(
    PeriodTrendRequest request,
    List<FortuneFlowSeries> series,
    List<String> axis,
    AdditionalFortuneTrendData data,
  ) {
    _checkFixture(request);
    final count = request.dates.length;
    if (series.length != 3 ||
        data.series.length != 3 ||
        axis.length != count ||
        data.felt.length != count ||
        jsonEncode(axis) != jsonEncode(data.labels) ||
        jsonEncode(axis) !=
            jsonEncode([
              for (final date in request.dates) axisLabel(request.mode, date),
            ])) {
      throw StateError('追加描画の次元・期間軸が不一致。');
    }
    for (var column = 0; column < 3; column++) {
      final item = series[column];
      final source = data.series[column];
      if (item.label != labels[column] ||
          item.color.toARGB32() != colors[column] ||
          item.values.length != count ||
          item.values.any((v) => v < 50 || v > 99) ||
          item.label != source.label ||
          item.color != source.color ||
          jsonEncode(item.values) != jsonEncode(source.values)) {
        throw StateError('描画線と体感詳細の数値契約が不一致。');
      }
    }
    if (data.felt.any((p) => ![...candidates, '混在', '未予測'].contains(p.label))) {
      throw StateError('未知の体感を描画できません。');
    }
    return {
      'mode': request.mode.name,
      'house_system': request.houseSystem.name,
      'dates_utc': [
        for (final date in request.dates) date.toUtc().toIso8601String(),
      ],
      'labels': List<String>.of(axis),
      'series': [
        for (final item in series)
          {
            'label': item.label,
            'color_argb': item.color.toARGB32(),
            'values': List<int>.of(item.values),
          },
      ],
      'felt': [
        for (final point in data.felt)
          {
            'label': point.label,
            'color_argb': point.color.toARGB32(),
            'detail': point.detail,
          },
      ],
      'point_details': [for (var i = 0; i < count; i++) data.pointDetail(i)],
    };
  }

  static Map<String, Object?> compare(
    Map<String, Object?> painted,
    Map<String, Object?> expected,
  ) {
    final series = (painted['series'] as List).cast<Map>();
    final axis = painted['labels'] as List;
    final felt = (painted['felt'] as List).cast<Map>();
    final details = painted['point_details'] as List;
    final rows = (expected['rows'] as List).cast<Map>();
    final count = axis.length;
    if (series.length != 3 ||
        rows.length != count ||
        felt.length != count ||
        details.length != count ||
        series.any((s) => (s['values'] as List).length != count) ||
        rows.any(
          (r) =>
              (r['scores'] as List).length != 3 ||
              (r['felt_counts'] as List).length != 6,
        )) {
      throw StateError('追加独立照合の次元が不一致。');
    }
    final differences = <Map<String, Object>>[];
    void check(
      Object? actual,
      Object? reference,
      String kind,
      int point, [
      int? column,
    ]) {
      if (actual != reference) {
        differences.add({
          'kind': kind,
          'point_index': point,
          if (column != null) 'series_index': column,
        });
      }
    }

    final actualDates = painted['dates_utc'] as List;
    final expectedDates = expected['dates_utc'] as List;
    if (actualDates.length != count || expectedDates.length != count) {
      throw StateError('追加独立照合の日付数が不一致。');
    }
    for (var point = 0; point < count; point++) {
      final row = rows[point];
      check(axis[point], row['label'], 'axis_label', point);
      check(actualDates[point], expectedDates[point], 'axis_date', point);
      for (var column = 0; column < 3; column++) {
        check(
          series[column]['label'],
          labels[column],
          'series_label',
          point,
          column,
        );
        check(
          series[column]['color_argb'],
          colors[column],
          'series_color',
          point,
          column,
        );
        check(
          (series[column]['values'] as List)[point],
          (row['scores'] as List)[column],
          'score',
          point,
          column,
        );
      }
      check(felt[point]['label'], row['felt_label'], 'felt_label', point);
      check(
        felt[point]['color_argb'],
        row['felt_color_argb'],
        'felt_color',
        point,
      );
      check(
        felt[point]['detail'],
        row['felt_detail'],
        'felt_distribution_detail',
        point,
      );
      check(details[point], row['point_detail'], 'point_detail', point);
    }
    return {
      'passed': differences.isEmpty,
      'point_count': count,
      'score_checks': count * 3,
      'felt_label_checks': count,
      'felt_color_checks': count,
      'felt_distribution_checks': count * 6,
      'point_detail_checks': count,
      'mismatch_count': differences.length,
      'differences': differences,
    };
  }

  static void capturePainted(
    PeriodTrendRequest request,
    List<FortuneFlowSeries> series,
    List<String> axis,
    AdditionalFortuneTrendData data,
  ) {
    if (!enabled ||
        !PeriodTrendPointCheck.isFixture(request) ||
        request.mode == LongRangeMode.week ||
        _busy ||
        !_captured.add(request.identity))
      return;
    try {
      final painted = snapshot(request, series, axis, data);
      _busy = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_audit(request, painted));
      });
    } catch (_) {
      print(
        'PANCYO_REWORK_ADDITIONAL_POINT_CHECK ${jsonEncode({'mode': request.mode.name, 'passed': false, 'check_failed': true})}',
      );
    }
  }

  static Future<void> _audit(
    PeriodTrendRequest request,
    Map<String, Object?> painted,
  ) async {
    try {
      if (!request.requireHighPrecision ||
          !SwissEphemerisProvider.isAvailable) {
        throw StateError('人工実機照合はネイティブ計算が必要。');
      }
      final expected = await Isolate.run(
        () => reference(request),
        debugName: 'pancyo-additional-point-reference',
      );
      final comparison = compare(painted, expected);
      final payload = {
        'schema': 'pancyo_rework_additional_point_check_v1',
        'participant_name': 'ReworkNine',
        'artificial_fixture_only': true,
        'rendered': painted,
        'reference': expected,
        'comparison': comparison,
      };
      final json = const JsonEncoder.withIndent('  ').convert(payload);
      final root = await getTemporaryDirectory();
      final folder = await root.createTemp('pancyo_additional_point_check_');
      final stamp = DateTime.now().toUtc().microsecondsSinceEpoch;
      await File(
        '${folder.path}${Platform.pathSeparator}ReworkNine_additional_points_${request.mode.name}_${request.houseSystem.name}_$stamp.json',
      ).writeAsString(json, flush: true);
      print(
        'PANCYO_REWORK_ADDITIONAL_POINT_CHECK ${jsonEncode({'mode': request.mode.name, 'house_system': request.houseSystem.name, 'passed': comparison['passed'], 'score_checks': comparison['score_checks'], 'felt_label_checks': comparison['felt_label_checks'], 'mismatch_count': comparison['mismatch_count'], 'reference_ms': expected['reference_ms']})}',
      );
    } catch (_) {
      // No raw input, point values, path, or exception text in logs.
      print(
        'PANCYO_REWORK_ADDITIONAL_POINT_CHECK ${jsonEncode({'mode': request.mode.name, 'passed': false, 'check_failed': true})}',
      );
    } finally {
      _busy = false;
    }
  }
}
