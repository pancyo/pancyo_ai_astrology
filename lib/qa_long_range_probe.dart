import 'dart:convert';

import 'package:flutter/material.dart';

import 'main.dart' as app;

/// Dedicated fictional native check. No preferences, profiles, files, backups,
/// saved JSON, or settings restoration are read by this entrypoint.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!app.reworkTestBuild) {
    throw StateError('This QA target requires PANCYO_REWORK_TEST=true.');
  }
  runApp(
    const _ProbeScreen(
      title: 'Native calculation check',
      message:
          'Checking two calculation paths with a fixed fictional fixture. '
          'Saved profiles and settings are not read.',
    ),
  );
  try {
    final result = await _runProbe();
    debugPrint('PANCYO_LIGHT_NATIVE_QA ${jsonEncode(result)}');
    runApp(
      const _ProbeScreen(
        title: 'Native check complete',
        message:
            'The two paths matched on five monthly reference samples. '
            'A separate 120-sample lightweight run and cached yearly reuse also passed. '
            'Full-path equivalence was checked for the five monthly samples only. '
            'This check does not enable the lightweight path in the normal app.',
      ),
    );
  } catch (error) {
    final code = error is _ProbeFailure ? error.code : 'native_check_failed';
    debugPrint(
      'PANCYO_LIGHT_NATIVE_QA ${jsonEncode({'equivalent': false, 'sample_count': 5, 'error_code': code})}',
    );
    runApp(
      _ProbeScreen(
        title: 'Native check failed',
        message: 'The check did not pass ($code). No result was adopted.',
      ),
    );
  }
}

class _ProbeFailure implements Exception {
  const _ProbeFailure(this.code);
  final String code;
}

void _require(bool condition, String code) {
  if (!condition) throw _ProbeFailure(code);
}

void _same(Object? oldValue, Object? newValue, String code) =>
    _require(jsonEncode(oldValue) == jsonEncode(newValue), code);

Map<String, dynamic> _clone(Map value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);

// These are the complete allowlists. No arbitrary recursive key deletion can
// hide a difference in aspects, sensitivity, arithmetic, models or coefficients.
Map<String, dynamic> _primaryWithoutVoid(Map trace) {
  final result = _clone(trace);
  _require(result['inputs'] is Map, 'missing_primary_inputs');
  (result['inputs'] as Map).remove('void_day_share');
  result.remove('void_context');
  return result;
}

Map<String, dynamic> _comparisonWithoutVoid(Map trace) {
  final result = _clone(trace);
  _require(
    result['inputs'] is Map && result['lunar_path'] is Map,
    'missing_comparison_inputs',
  );
  (result['inputs'] as Map).remove('void_day_share');
  result['lunar_path'] = _primaryWithoutVoid(result['lunar_path'] as Map);
  return result;
}

void _comparePredictions(
  List<app.NineAreaPrediction> full,
  List<app.NineAreaPrediction> light,
) {
  _same(
    full.map((p) => p.key.name).toList(),
    app.NineAreaKey.values.map((k) => k.name).toList(),
    'full_nine_items',
  );
  _same(
    light.map((p) => p.key.name).toList(),
    app.NineAreaKey.values.map((k) => k.name).toList(),
    'light_nine_items',
  );
  for (final key in app.NineAreaKey.values) {
    final old = full.singleWhere((p) => p.key == key);
    final next = light.singleWhere((p) => p.key == key);
    _require(old.icon == next.icon, 'prediction_icon_mismatch');
    _same(
      [old.title, old.summary, old.detail, old.reading, old.provisional],
      [next.title, next.summary, next.detail, next.reading, next.provisional],
      'prediction_metadata_mismatch',
    );
    _same(old.score, next.score, 'score_mismatch');
    _same(
      old.scoreBreakdown,
      next.scoreBreakdown,
      'numeric_breakdown_mismatch',
    );
    _same(
      old.longTermContext,
      next.longTermContext,
      'long_term_context_mismatch',
    );
    if (key != app.NineAreaKey.felt) {
      _require(
        next.score != null &&
            next.score! >= 50 &&
            next.score! <= 99 &&
            next.scoreBreakdown != null,
        'numeric_prediction_incomplete',
      );
      continue;
    }
    _require(
      old.score == null &&
          next.score == null &&
          old.feltForecast != null &&
          next.feltForecast != null &&
          old.feltComparison != null &&
          next.feltComparison != null,
      'categorical_felt_incomplete',
    );
    final oldPrimary = old.feltForecast!, nextPrimary = next.feltForecast!;
    final oldComparison = old.feltComparison!,
        nextComparison = next.feltComparison!;
    _require(
      oldPrimary.label != null && oldComparison.label != null,
      'native_felt_not_predicted',
    );
    _same(oldPrimary.label, nextPrimary.label, 'primary_felt_label_mismatch');
    _same(
      oldComparison.label,
      nextComparison.label,
      'comparison_felt_label_mismatch',
    );
    _same(
      _primaryWithoutVoid(oldPrimary.trace),
      _primaryWithoutVoid(nextPrimary.trace),
      'primary_felt_trace_mismatch',
    );
    _same(
      _comparisonWithoutVoid(oldComparison.trace),
      _comparisonWithoutVoid(nextComparison.trace),
      'comparison_felt_trace_mismatch',
    );
    _require(
      nextPrimary.trace['inputs'] is Map &&
          nextComparison.trace['inputs'] is Map &&
          nextPrimary.trace['parameters'] is Map,
      'light_felt_diagnostics_missing',
    );
    _require(
      (nextPrimary.trace['inputs'] as Map)['void_day_share'] == null &&
          (nextComparison.trace['inputs'] as Map)['void_day_share'] == null &&
          nextPrimary.trace['void_context'] == 'period_not_provided' &&
          (nextPrimary.trace['parameters'] as Map)['void_weight'] == 0,
      'void_omission_not_explicit_or_nonzero_weight',
    );
  }
}

Future<Map<String, Object?>> _runProbe() async {
  _require(
    app.SwissEphemerisProvider.isAvailable &&
        app.AstrologyDataSources.current.usesHighPrecisionAstroData,
    'native_ephemeris_unavailable',
  );
  // This changes an in-memory notifier only, never persisted settings.
  app.HouseSystemSettings.current.value = app.HouseSystem.placidus;
  const subject = app.AstroProfile(
    name: 'AnonymousRangeProbe',
    birthDate: '1990/1/2',
    birthTime: '12:00',
    birthPlace: '北海道札幌市',
    theme: 'fictional_qa_fixture',
  );
  app.LongRangeDisplayRequest request(bool fullContext) =>
      app.LongRangeDisplayRequest(
        mode: app.LongRangeDisplayMode.month,
        month: DateTime.utc(2026, 3),
        startYear: 2026,
        profile: subject,
        houseSystem: app.HouseSystem.placidus,
        fullContext: fullContext,
      );
  final fullRequest = request(true), lightRequest = request(false);
  _require(
    fullRequest.requireHighPrecision && lightRequest.requireHighPrecision,
    'high_precision_not_requested',
  );
  _same(
    fullRequest.dates.map((d) => d.toIso8601String()).toList(),
    lightRequest.dates.map((d) => d.toIso8601String()).toList(),
    'sample_instants_differ',
  );
  _require(
    fullRequest.dates.length == 5 &&
        fullRequest.dates.toSet().length == 5 &&
        fullRequest.dates.every((d) => d.isUtc && d.hour == 3 && d.minute == 0),
    'reference_instants_incomplete',
  );
  final fullWatch = Stopwatch()..start();
  final fullJob = app.LongRangeDisplayJob.start(fullRequest);
  late final app.LongRangeDisplayResult full;
  try {
    full = await fullJob.result;
  } finally {
    fullJob.cancel();
  }
  fullWatch.stop();
  final lightWatch = Stopwatch()..start();
  final lightJob = app.LongRangeDisplayJob.start(lightRequest);
  late final app.LongRangeDisplayResult light;
  try {
    light = await lightJob.result;
  } finally {
    lightJob.cancel();
  }
  lightWatch.stop();
  _require(
    full.matches(fullRequest) &&
        light.matches(lightRequest) &&
        full.computedSampleCount == 5 &&
        light.computedSampleCount == 5,
    'worker_samples_or_conditions_incomplete',
  );
  for (final date in fullRequest.dates) {
    final old = full.samples[date]!, next = light.samples[date]!;
    _require(old.date == date && next.date == date, 'sample_date_mismatch');
    _same(
      [
        old.sourceName,
        old.precisionNotice,
        old.usesHighPrecision,
        old.resolvedHouseSystem.name,
        old.houseCusps,
      ],
      [
        next.sourceName,
        next.precisionNotice,
        next.usesHighPrecision,
        next.resolvedHouseSystem.name,
        next.houseCusps,
      ],
      'provider_diagnostics_mismatch',
    );
    _require(
      old.sourceName == fullRequest.sourceName &&
          old.usesHighPrecision &&
          old.resolvedHouseSystem == app.HouseSystem.placidus &&
          old.houseCusps.length == 12 &&
          old.houseCusps.every((v) => v.isFinite),
      'native_source_or_house_unavailable',
    );
    _require(
      !old.displayOnlyPositions && next.displayOnlyPositions,
      'calculation_path_diagnostic_mismatch',
    );
    _same(next.displayCalculation, {
      'display_only_positions': true,
      'void_period_status': 'not_requested',
      'void_day_share': null,
      'not_requested_void_is_not_zero': true,
    }, 'light_void_diagnostics_mismatch');
    _comparePredictions(old.predictions, next.predictions);
  }
  _same(
    full.summary.areas.map((a) => a.score).toList(),
    light.summary.areas.map((a) => a.score).toList(),
    'period_score_mismatch',
  );
  _same(
    full.summary.feltCounts,
    light.summary.feltCounts,
    'period_felt_counts_mismatch',
  );
  _same(
    full.trend.series.map((s) => s.values).toList(),
    light.trend.series.map((s) => s.values).toList(),
    'main_graph_mismatch',
  );
  _same(
    full.trend.additional.series.map((s) => s.values).toList(),
    light.trend.additional.series.map((s) => s.values).toList(),
    'additional_graph_mismatch',
  );
  final fiveYearMetrics = await _runFiveYearLightProbe(
    subject,
    full.samples.values.first,
  );
  return {
    'equivalent': true, 'sample_count': 5, 'numeric_score_checks': 40,
    'numeric_breakdown_checks': 40, 'primary_felt_checks': 5,
    'comparison_felt_checks': 5, 'provider_diagnostic_checks': 5,
    // The existing high-precision worker rejects any placement fallback.
    'placement_fallbacks': 0,
    'full_elapsed_ms': fullWatch.elapsedMilliseconds,
    'light_elapsed_ms': lightWatch.elapsedMilliseconds,
    'source': full.samples.values.first.sourceName,
    'high_precision': full.samples.values.first.usesHighPrecision,
    'excluded_void_metadata': [
      'primary.inputs.void_day_share',
      'primary.void_context',
      'comparison.inputs.void_day_share',
      'comparison.lunar_path.inputs.void_day_share',
      'comparison.lunar_path.void_context',
    ],
    ...fiveYearMetrics,
  };
}

/// Fresh Dart worker and empty application sample cache. Swiss's process-level
/// internal cache is not reset, so this is not a cold native-cache benchmark.
/// It validates light-path completeness; it never claims full 120 equivalence.
Future<Map<String, Object?>> _runFiveYearLightProbe(
  app.AstroProfile subject,
  app.LongRangeDisplaySample monthBaseline,
) async {
  final request = app.LongRangeDisplayRequest(
    mode: app.LongRangeDisplayMode.fiveYear,
    month: DateTime.utc(2026, 3),
    startYear: 2026,
    profile: subject,
    houseSystem: app.HouseSystem.placidus,
    fullContext: false,
  );
  final cache = app.LongRangeDisplayCache();
  final seeds = cache.seeds(request);
  _require(
    seeds.isEmpty && !request.fullContext && request.requireHighPrecision,
    'five_year_fresh_light_request_invalid',
  );
  var completed = 0;
  var progressValid = true;
  final completedYears = <Map<DateTime, app.LongRangeDisplaySample>>[];
  final watch = Stopwatch()..start();
  final job = app.LongRangeDisplayJob.start(
    request,
    seeds: seeds,
    onProgress: (done, total) {
      if (total != 120 || done != completed + 1) progressValid = false;
      completed = done;
    },
    onCompletedYear: (samples) {
      completedYears.add(samples);
      cache.publishCompletedYear(request, samples);
    },
  );
  late final app.LongRangeDisplayResult result;
  try {
    result = await job.result;
  } finally {
    job.cancel();
  }
  watch.stop();
  _require(
    result.matches(request) &&
        result.computedSampleCount == 120 &&
        result.samples.length == 120 &&
        progressValid &&
        completed == 120,
    'five_year_worker_incomplete',
  );
  _require(
    request.dates.length == 120 &&
        request.dates.toSet().length == 120 &&
        result.summary.dates.toSet().length == 120 &&
        request.dates.every(
          (d) =>
              d.isUtc &&
              d.hour == 3 &&
              d.minute == 0 &&
              d.second == 0 &&
              d.millisecond == 0 &&
              d.microsecond == 0,
        ),
    'five_year_reference_instants_invalid',
  );
  _same(
    request.dates.map((d) => d.toIso8601String()).toList(),
    result.summary.dates.map((d) => d.toIso8601String()).toList(),
    'five_year_summary_instants_mismatch',
  );
  _require(
    completedYears.length == 5 && completedYears.every((s) => s.length == 24),
    'five_year_completion_events_incomplete',
  );
  _same(
    result.summary.areas.map((a) => a.key.name).toList(),
    app.NineAreaKey.values.map((k) => k.name).toList(),
    'five_year_summary_nine_items',
  );
  final feltCounts = <String, int>{};
  for (final date in request.dates) {
    final sample = result.samples[date];
    _require(sample != null, 'five_year_sample_missing');
    final actual = sample!;
    _require(
      actual.date == date &&
          actual.displayOnlyPositions &&
          actual.usesHighPrecision &&
          actual.sourceName == monthBaseline.sourceName &&
          actual.precisionNotice == monthBaseline.precisionNotice &&
          actual.resolvedHouseSystem == app.HouseSystem.placidus,
      'five_year_native_diagnostic_mismatch',
    );
    _same(
      actual.houseCusps,
      monthBaseline.houseCusps,
      'five_year_house_cusps_mismatch',
    );
    _same(
      actual.predictions.map((p) => p.key.name).toList(),
      app.NineAreaKey.values.map((k) => k.name).toList(),
      'five_year_daily_nine_items',
    );
    _same(actual.displayCalculation, {
      'display_only_positions': true,
      'void_period_status': 'not_requested',
      'void_day_share': null,
      'not_requested_void_is_not_zero': true,
    }, 'five_year_void_diagnostic_mismatch');
    for (final prediction in actual.predictions) {
      if (prediction.key != app.NineAreaKey.felt) {
        _require(
          prediction.score != null &&
              prediction.score! >= 50 &&
              prediction.score! <= 99 &&
              prediction.scoreBreakdown != null,
          'five_year_numeric_sample_incomplete',
        );
      } else {
        _require(
          prediction.score == null &&
              prediction.feltForecast?.label != null &&
              prediction.feltComparison?.label != null,
          'five_year_categorical_sample_incomplete',
        );
        final label = prediction.feltForecast!.label!;
        feltCounts.update(label, (value) => value + 1, ifAbsent: () => 1);
        final inputs = prediction.feltForecast!.trace['inputs'];
        _require(
          inputs is Map &&
              inputs['void_day_share'] == null &&
              prediction.feltForecast!.trace['void_context'] ==
                  'period_not_provided',
          'five_year_void_omission_not_explicit',
        );
      }
    }
  }
  for (final area in result.summary.areas) {
    if (area.key == app.NineAreaKey.felt) {
      _require(
        area.score == null && result.summary.feltUnavailableCount == 0,
        'five_year_felt_summary_invalid',
      );
      for (final entry in result.summary.feltCounts.entries) {
        _require(
          entry.value == (feltCounts[entry.key] ?? 0),
          'five_year_felt_count_mismatch',
        );
      }
      continue;
    }
    final scores = [
      for (final date in request.dates)
        result.samples[date]!.predictions
            .singleWhere((p) => p.key == area.key)
            .score!,
    ];
    _same(area.samples, scores, 'five_year_raw_samples_mismatch');
    _require(
      area.score == (scores.reduce((a, b) => a + b) / 120).round(),
      'five_year_raw_mean_mismatch',
    );
  }
  _require(
    result.trend.labels.length == 5 &&
        result.trend.series.length == 5 &&
        result.trend.additional.series.length == 3 &&
        result.trend.additional.felt.length == 5,
    'five_year_graph_item_count_invalid',
  );
  final numericSeries = [
    ...result.trend.series,
    ...result.trend.additional.series,
  ];
  _require(
    numericSeries.every((s) => s.values.length == 5),
    'five_year_graph_point_count_invalid',
  );
  for (var i = 0; i < numericSeries.length; i++) {
    final values = result.summary.areas[i].samples;
    _same(numericSeries[i].values, [
      for (var yearIndex = 0; yearIndex < 5; yearIndex++)
        (values
                    .sublist(yearIndex * 24, yearIndex * 24 + 24)
                    .reduce((a, b) => a + b) /
                24)
            .round(),
    ], 'five_year_graph_raw_mean_mismatch');
  }
  cache.publish(request, result);
  final yearRequest = app.LongRangeDisplayRequest(
    mode: app.LongRangeDisplayMode.year,
    month: DateTime.utc(2026, 1),
    startYear: 2026,
    profile: subject,
    houseSystem: app.HouseSystem.placidus,
    fullContext: false,
  );
  final yearSeeds = cache.seeds(yearRequest);
  _require(yearSeeds.length == 24, 'five_year_shared_year_seeds_incomplete');
  final yearWatch = Stopwatch()..start();
  final yearJob = app.LongRangeDisplayJob.start(yearRequest, seeds: yearSeeds);
  late final app.LongRangeDisplayResult reusedYear;
  try {
    reusedYear = await yearJob.result;
  } finally {
    yearJob.cancel();
  }
  yearWatch.stop();
  _require(
    reusedYear.matches(yearRequest) &&
        reusedYear.samples.length == 24 &&
        reusedYear.computedSampleCount == 0 &&
        reusedYear.trend.labels.length == 12,
    'five_year_year_reuse_failed',
  );
  _same(
    reusedYear.summary.areas.take(8).map((a) => a.score).toList(),
    [
      for (final area in result.summary.areas.take(8))
        (area.samples.take(24).reduce((a, b) => a + b) / 24).round(),
    ],
    'five_year_reused_year_score_mismatch',
  );
  return {
    'five_year_light_fresh_worker': true,
    'five_year_native_cache_cold': false,
    'five_year_full_equivalence_checked': false,
    'five_year_light_sample_count': 120,
    'five_year_light_computed': result.computedSampleCount,
    'five_year_light_elapsed_ms': watch.elapsedMilliseconds,
    'five_year_light_all_nine_item_checks': 120,
    'five_year_light_graph_points': 5,
    'five_year_light_completed_year_events': completedYears.length,
    'five_year_light_high_precision':
        result.samples.values.first.usesHighPrecision,
    'year_reuse_sample_count': reusedYear.samples.length,
    'year_reuse_computed': reusedYear.computedSampleCount,
    'year_reuse_elapsed_ms': yearWatch.elapsedMilliseconds,
  };
}

class _ProbeScreen extends StatelessWidget {
  const _ProbeScreen({required this.title, required this.message});
  final String title, message;
  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Text(message, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
