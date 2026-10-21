part of 'main.dart';

/// Artificial, opt-in QA of the exact arrays passed to the native chart painter.
/// Does not read preferences, share files or expose a development UI.
class PeriodTrendPointCheck {
  const PeriodTrendPointCheck._();

  static const enabled =
      reworkTestBuild && bool.fromEnvironment('PANCYO_TREND_POINT_CHECK');
  static final _captured = <Object>{};
  static bool _busy = false;
  static const areaLabels = ['総合', '恋愛', '仕事', '金運', 'メンタル'];
  static const areaColors = [
    0xFFF6D77A,
    0xFFFF82B2,
    0xFF57D6D1,
    0xFF9BE06D,
    0xFFB58CFF,
  ];

  static bool isFixture(PeriodTrendRequest request) =>
      request.profile.name == 'ReworkNine' &&
      request.profile.birthDate == '1990/1/2' &&
      request.profile.birthTime == '12:00' &&
      const ['札幌市', '北海道札幌市'].contains(request.profile.birthPlace);

  static Map<String, Object?> snapshot(
    PeriodTrendRequest request,
    List<FortuneFlowSeries> series,
    List<String> labels,
  ) {
    if (!isFixture(request)) throw StateError('人工検査人物ではありません。');
    final expectedLabels = [
      for (final date in request.dates)
        switch (request.mode) {
          LongRangeMode.week => '${_monthDayWithWeekday(date)}週',
          LongRangeMode.month => '${date.month}月',
          LongRangeMode.year => '${date.year}',
        },
    ];
    if (jsonEncode(labels) != jsonEncode(expectedLabels) ||
        series.length != 5) {
      throw StateError('描画の系列数・期間ラベルが不一致。');
    }
    for (var index = 0; index < series.length; index++) {
      final item = series[index];
      if (item.label != areaLabels[index] ||
          item.color.toARGB32() != areaColors[index] ||
          item.values.length != request.dates.length ||
          item.values.any((value) => value < 50 || value > 99)) {
        throw StateError('描画の系列契約が不一致。');
      }
    }
    return {
      'mode': request.mode.name,
      'house_system': request.houseSystem.name,
      'dates_utc': [
        for (final date in request.dates) date.toUtc().toIso8601String(),
      ],
      'labels': List<String>.of(labels),
      'series': [
        for (final item in series)
          {
            'label': item.label,
            'color_argb': item.color.toARGB32(),
            'values': List<int>.of(item.values),
          },
      ],
    };
  }

  /// Uses the unchanged UI-card path, not PeriodConsultDataBuilder/graphScores
  /// or the graph worker. The fixture is unmounted and runs in a fresh isolate.
  static Map<String, Object?> reference(PeriodTrendRequest request) {
    if (!isFixture(request)) throw StateError('人工検査人物ではありません。');
    if (request.requireHighPrecision && !SwissEphemerisProvider.isAvailable) {
      throw StateError('ネイティブ精度の独立照合を利用できません。');
    }
    final oldHouse = HouseSystemSettings.current.value;
    final fallbackBefore = SwissEphemerisProvider._placementFallbackCount;
    final watch = Stopwatch()..start();
    try {
      HouseSystemSettings.current.value = request.houseSystem;
      final state = _PointCheckCardState(request);
      final expected = <List<int>>[];
      for (final date in request.dates) {
        final cards = state._chartCardsFor(date);
        final titles = [
          '総合運',
          '恋愛運',
          '仕事運',
          '金運',
          'メンタル運',
        ];
        if (jsonEncode(cards.map((card) => card.title).toList()) !=
            jsonEncode(titles)) {
          throw StateError('独立カードの項目順が不一致。');
        }
        expected.add(cards.map((card) => card.score).toList());
      }
      if (request.requireHighPrecision &&
          SwissEphemerisProvider._placementFallbackCount != fallbackBefore) {
        throw StateError('独立カード計算で近似代用が発生。');
      }
      return {
        'rows': expected,
        'uses_high_precision_astro_data':
            AstrologyDataSources.current.usesHighPrecisionAstroData,
        'reference_ms': watch.elapsedMilliseconds,
        'reference_route': 'unchanged_ui_chart_cards',
      };
    } finally {
      HouseSystemSettings.current.value = oldHouse;
    }
  }

  static Map<String, Object?> compare(
    Map<String, Object?> rendered,
    Map<String, Object?> reference,
  ) {
    final series = rendered['series'] as List;
    final rows = reference['rows'] as List;
    final labels = rendered['labels'] as List;
    if (series.length != 5 ||
        rows.length != labels.length ||
        rows.any((row) => (row as List).length != 5)) {
      throw StateError('独立照合の次元が不一致。');
    }
    final differences = <Map<String, int>>[];
    for (var column = 0; column < 5; column++) {
      final values = (series[column] as Map)['values'] as List;
      if (values.length != rows.length) throw StateError('描画点数が不一致。');
      for (var point = 0; point < rows.length; point++) {
        if (values[point] != (rows[point] as List)[column]) {
          differences.add({'series_index': column, 'point_index': point});
        }
      }
    }
    return {
      'passed': differences.isEmpty,
      'point_count': rows.length,
      'score_checks': rows.length * 5,
      'mismatch_count': differences.length,
      'differences': differences,
    };
  }

  static void capturePainted(
    PeriodTrendRequest request,
    List<FortuneFlowSeries> series,
    List<String> labels,
  ) {
    if (!enabled ||
        !isFixture(request) ||
        _busy ||
        !_captured.add(request.identity))
      return;
    // Freeze the values actually painted before any rebuild can replace them.
    try {
      final painted = snapshot(request, series, labels);
      _busy = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_audit(request, painted));
      });
    } catch (_) {
      print(
        'PANCYO_REWORK_UPPER_POINT_CHECK ${jsonEncode({'mode': request.mode.name, 'passed': false, 'check_failed': true})}',
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
        debugName: 'pancyo-upper-point-reference',
      );
      final result = compare(painted, expected);
      final payload = {
        'schema': 'pancyo_rework_upper_point_check_v1',
        'participant_name': 'ReworkNine',
        'artificial_fixture_only': true,
        'rendered': painted,
        'reference': expected,
        'comparison': result,
      };
      final json = const JsonEncoder.withIndent('  ').convert(payload);
      final root = await getTemporaryDirectory();
      final folder = await root.createTemp('pancyo_upper_point_check_');
      final stamp = DateTime.now().toUtc().microsecondsSinceEpoch;
      final file = File(
        '${folder.path}${Platform.pathSeparator}'
        'ReworkNine_upper_points_${request.mode.name}_$stamp.json',
      );
      await file.writeAsString(json, flush: true);
      print(
        'PANCYO_REWORK_UPPER_POINT_CHECK ${jsonEncode({'mode': request.mode.name, 'house_system': request.houseSystem.name, 'passed': result['passed'], 'score_checks': result['score_checks'], 'mismatch_count': result['mismatch_count'], 'reference_ms': expected['reference_ms']})}',
      );
    } catch (_) {
      // No raw input, path, point scores or exception message in shared logs.
      print(
        'PANCYO_REWORK_UPPER_POINT_CHECK ${jsonEncode({'mode': request.mode.name, 'passed': false, 'check_failed': true})}',
      );
    } finally {
      _busy = false;
    }
  }
}

class _PointCheckCardState extends _LongRangeReadingState {
  _PointCheckCardState(PeriodTrendRequest request)
    : _fixtureWidget = LongRangeReading(
        profile: request.profile,
        details: const UserProfileDetails.empty(),
        depth: ReadingDepth.simple,
      ) {
    _mode = request.mode;
  }
  final LongRangeReading _fixtureWidget;
  @override
  LongRangeReading get widget => _fixtureWidget;
}
