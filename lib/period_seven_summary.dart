part of 'main.dart';

/// Display-only, explicitly approved aggregation of unchanged daily-v4 data.
/// The last 24:00 is included. An internal 24:00/00:00 pair counts only once,
/// after its complete forecast snapshots have been checked for equality.
/// This never calculates, saves, or changes a daily/weekly/monthly JSON record.
class PeriodSevenSummary extends NineAreaPeriodSummary {
  PeriodSevenSummary._({
    required LongRangeMode mode,
    required List<DateTime> instants,
    required List<NineAreaPeriodEntry> entries,
    required Map<String, int> counts,
    required List<String> modes,
    required this.startDateJst,
    required this.endDateJst,
    required this.dayCount,
    required this.predictionsByInstant,
    required this.sourceName,
    required this.usesHighPrecisionAstroData,
    required this.requestedHouseSystem,
    required this.generatedAt,
    this.isDisplayRange = false,
  }) : super._(
         mode,
         List.unmodifiable(instants),
         List.unmodifiable(entries),
         Map.unmodifiable(counts),
         0,
         List.unmodifiable(modes),
         'unchanged_daily_v4_intraday_forecasts',
         true,
       );

  static const aggregationVersion =
      'nine-area-seven-point-period-display-trial-20261018-1';
  final String startDateJst;
  final String endDateJst;
  final int dayCount;
  final Map<String, List<NineAreaPrediction>> predictionsByInstant;
  final String sourceName;
  final bool usesHighPrecisionAstroData;
  final HouseSystem requestedHouseSystem;
  final String generatedAt;
  final bool isDisplayRange;
  bool get isSingleDay => isDisplayRange && dayCount == 1;

  int get listedPointCount => dayCount * 7;
  int get uniqueInstantCount => dates.length;
  String get aggregationModelVersion => aggregationVersion;

  /// Civil JST timestamps rather than date-only keys; intraday samples must
  /// never overwrite one another in the explanation trace map.
  String sampleKey(DateTime instant) =>
      NineAreaForecastSnapshot._issuedAtJst(instant.toUtc());

  static String _instantKey(DateTime instant) =>
      NineAreaForecastSnapshot._issuedAtJst(instant.toUtc());

  factory PeriodSevenSummary.fromDailyV4({
    required LongRangeMode mode,
    required DateTime startDateJst,
    required List<Map<String, Object?>> days,
    required AstroProfile profile,
    required UserProfileDetails details,
    required HouseSystem requestedHouseSystem,
    required String sourceName,
    required bool requireHighPrecision,
  }) => PeriodSevenSummary._fromDays(
    mode: mode,
    startDateJst: startDateJst,
    days: days,
    profile: profile,
    details: details,
    requestedHouseSystem: requestedHouseSystem,
    sourceName: sourceName,
    requireHighPrecision: requireHighPrecision,
    displayOnly: false,
  );

  /// The display worker runs the same seven-point formulas without building
  /// unrelated export sections. Its separate schema is validated explicitly;
  /// it is never presented or saved as an official daily-v4 JSON document.
  factory PeriodSevenSummary.fromDisplayDays({
    required LongRangeMode mode,
    required DateTime startDateJst,
    required List<Map<String, Object?>> days,
    required AstroProfile profile,
    required UserProfileDetails details,
    required HouseSystem requestedHouseSystem,
    required String sourceName,
    required bool requireHighPrecision,
  }) => PeriodSevenSummary._fromDays(
    mode: mode,
    startDateJst: startDateJst,
    days: days,
    profile: profile,
    details: details,
    requestedHouseSystem: requestedHouseSystem,
    sourceName: sourceName,
    requireHighPrecision: requireHighPrecision,
    displayOnly: true,
  );

  /// Selected half-month (1–15 / 16–last day), or one day for the daily graph.
  /// This is an explicit partial-month display, never a full-month prediction.
  factory PeriodSevenSummary.fromDisplayRange({
    required DateTime startDateJst,
    required DateTime endDateJst,
    required List<Map<String, Object?>> days,
    required AstroProfile profile,
    required UserProfileDetails details,
    required HouseSystem requestedHouseSystem,
    required String sourceName,
    required bool requireHighPrecision,
  }) => PeriodSevenSummary._fromDays(
    mode: LongRangeMode.month,
    startDateJst: startDateJst,
    rangeEndDateJst: endDateJst,
    days: days,
    profile: profile,
    details: details,
    requestedHouseSystem: requestedHouseSystem,
    sourceName: sourceName,
    requireHighPrecision: requireHighPrecision,
    displayOnly: true,
  );

  factory PeriodSevenSummary._fromDays({
    required LongRangeMode mode,
    required DateTime startDateJst,
    required List<Map<String, Object?>> days,
    required AstroProfile profile,
    required UserProfileDetails details,
    required HouseSystem requestedHouseSystem,
    required String sourceName,
    required bool requireHighPrecision,
    required bool displayOnly,
    DateTime? rangeEndDateJst,
  }) {
    if (mode == LongRangeMode.year) {
      throw ArgumentError('Seven-point period readings support weeks/months.');
    }
    final first = DateTime.utc(
      startDateJst.year,
      startDateJst.month,
      startDateJst.day,
    );
    final last = rangeEndDateJst == null
        ? null
        : DateTime.utc(
            rangeEndDateJst.year,
            rangeEndDateJst.month,
            rangeEndDateJst.day,
          );
    if (last != null &&
        (!displayOnly ||
            mode != LongRangeMode.month ||
            first.year != last.year ||
            first.month != last.month ||
            !(first == last ||
                (first.day == 1 && last.day == 15) ||
                (first.day == 16 &&
                    last.day ==
                        DateTime.utc(first.year, first.month + 1, 0).day)))) {
      throw ArgumentError(
        'A display range must be one day or a complete month half.',
      );
    }
    if (last == null && mode == LongRangeMode.month && first.day != 1) {
      throw ArgumentError('A monthly reading must start on the first day.');
    }
    final dayCount = last != null
        ? last.difference(first).inDays + 1
        : mode == LongRangeMode.week
        ? 7
        : DateTime.utc(first.year, first.month + 1, 0).day;
    if (days.length != dayCount) {
      throw StateError('All days of the selected period are required.');
    }
    final counts = {for (final label in FeltForecastCandidate.labels) label: 0};
    final instants = <DateTime>[];
    final predictions = <String, List<NineAreaPrediction>>{};
    Map<String, Object?>? previousBoundary;
    String? generatedAt;
    for (var dayIndex = 0; dayIndex < dayCount; dayIndex++) {
      final date = first.add(Duration(days: dayIndex));
      final plan = DailySevenTimepointPlan.forJstDate(_monthlyDateLabel(date));
      final daily = days[dayIndex];
      final rawGeneratedAt = daily['generated_at'];
      final parsedGeneratedAt = rawGeneratedAt is String
          ? DateTime.tryParse(rawGeneratedAt)
          : null;
      if (rawGeneratedAt is! String ||
          parsedGeneratedAt == null ||
          (generatedAt != null && generatedAt != rawGeneratedAt)) {
        throw StateError(
          'Period days have missing or different generation times.',
        );
      }
      generatedAt ??= rawGeneratedAt;
      final request = DailyConsultExportRequest(
        date: plan.primaryNoon.instantUtc,
        profile: profile,
        details: details,
        requestedHouseSystem: requestedHouseSystem,
        sourceName: sourceName,
        requireHighPrecision: requireHighPrecision,
        generatedAt: parsedGeneratedAt,
      );
      // The async owner must already have checked its operation/request token.
      // Here the reconstructed request validates payload provenance and clocks;
      // it does not claim to authenticate an operation from the data alone.
      if (displayOnly) {
        validatePeriodSevenDisplayDay(data: daily, request: request);
      } else {
        validatePeriodSevenReadingData(
          data: daily,
          request: request,
          resultRequestIdentity: request.identity,
        );
      }
      final group = _monthlyMap(
        daily['intraday_forecasts'],
        'Period forecasts',
      );
      final points = _monthlyList(group['points'], 'Period points');
      for (var pointIndex = 0; pointIndex < 7; pointIndex++) {
        final point = _monthlyMap(points[pointIndex], 'Period point');
        final snapshot = _monthlyMap(
          point['nine_area_forecast'],
          'Period snapshot',
        );
        final instant = plan.points[pointIndex].instantUtc;
        final key = _instantKey(instant);
        if (dayIndex > 0 && pointIndex == 0) {
          if (previousBoundary == null ||
              jsonEncode(previousBoundary) != jsonEncode(snapshot) ||
              !predictions.containsKey(key)) {
            throw StateError('24:00 and the next 00:00 forecasts differ.');
          }
          continue;
        }
        if (predictions.containsKey(key)) {
          throw StateError('Unexpected duplicate period instant.');
        }
        final rawAreas = _monthlyList(snapshot['areas'], 'Period areas');
        final sample = <NineAreaPrediction>[];
        final keys = <NineAreaKey>{};
        for (final rawArea in rawAreas) {
          final area = _monthlyMap(rawArea, 'Period area');
          final rawKey = area['key'];
          if (rawKey is! String ||
              !NineAreaKey.values.any((value) => value.name == rawKey)) {
            throw StateError('Unknown period area.');
          }
          final areaKey = NineAreaKey.values.byName(rawKey);
          if (!keys.add(areaKey)) throw StateError('Duplicate period area.');
          final prediction = PeriodSevenReadingCards._prediction(area, areaKey);
          if (areaKey == NineAreaKey.felt) {
            final label = prediction.feltForecast?.label;
            if (prediction.score != null ||
                label == null ||
                !counts.containsKey(label)) {
              throw StateError(
                'Missing or unknown non-numeric felt candidate.',
              );
            }
            counts[label] = counts[label]! + 1;
          } else if (prediction.score == null ||
              prediction.score! < 50 ||
              prediction.score! > 99) {
            throw StateError('Missing or out-of-range period numeric score.');
          }
          sample.add(prediction);
        }
        if (sample.length != 9 || keys.length != NineAreaKey.values.length) {
          throw StateError(
            'Nine distinct areas are required at every instant.',
          );
        }
        instants.add(instant);
        predictions[key] = List.unmodifiable(sample);
        if (pointIndex == 6) previousBoundary = snapshot;
      }
    }
    if (instants.length != dayCount * 6 + 1 ||
        counts.values.reduce((a, b) => a + b) != instants.length) {
      throw StateError('The complete unique-instant series is required.');
    }
    for (var index = 1; index < instants.length; index++) {
      if (instants[index].difference(instants[index - 1]) !=
          const Duration(hours: 4)) {
        throw StateError(
          'A four-hour period sample is missing or out of order.',
        );
      }
    }
    final entries = <NineAreaPeriodEntry>[];
    for (final areaKey in NineAreaKey.values) {
      final firstPrediction = predictions.values.first.singleWhere(
        (prediction) => prediction.key == areaKey,
      );
      final values = <int>[
        if (areaKey != NineAreaKey.felt)
          for (final sample in predictions.values)
            sample
                .singleWhere((prediction) => prediction.key == areaKey)
                .score!,
      ];
      entries.add(
        NineAreaPeriodEntry(
          key: areaKey,
          title: firstPrediction.title,
          icon: firstPrediction.icon,
          score: areaKey == NineAreaKey.felt
              ? null
              : (values.reduce((a, b) => a + b) / values.length).round(),
          samples: List.unmodifiable(values),
          inherited: false,
        ),
      );
    }
    final maximum = counts.values.reduce(math.max);
    return PeriodSevenSummary._(
      mode: mode,
      instants: instants,
      entries: entries,
      counts: counts,
      modes: [
        for (final label in FeltForecastCandidate.labels)
          if (counts[label] == maximum) label,
      ],
      startDateJst: _monthlyDateLabel(first),
      endDateJst: _monthlyDateLabel(first.add(Duration(days: dayCount - 1))),
      dayCount: dayCount,
      predictionsByInstant: Map.unmodifiable(predictions),
      sourceName: sourceName,
      usesHighPrecisionAstroData: requireHighPrecision,
      requestedHouseSystem: requestedHouseSystem,
      generatedAt: generatedAt!,
      isDisplayRange: last != null,
    );
  }

  /// Reuses the already validated seven points. No ephemeris calculation,
  /// serialization, or second validation of a half-month payload is performed.
  PeriodSevenSummary daySummaryAt(int index) {
    RangeError.checkValueInInterval(index, 0, dayCount - 1, 'index');
    final dayInstants = dates.sublist(index * 6, index * 6 + 7);
    final dayPredictions = <String, List<NineAreaPrediction>>{
      for (final instant in dayInstants)
        sampleKey(instant): predictionsByInstant[sampleKey(instant)]!,
    };
    final counts = {for (final label in FeltForecastCandidate.labels) label: 0};
    for (final sample in dayPredictions.values) {
      final label = sample
          .singleWhere((p) => p.key == NineAreaKey.felt)
          .feltForecast!
          .label!;
      counts[label] = counts[label]! + 1;
    }
    final entries = <NineAreaPeriodEntry>[];
    for (final area in areas) {
      final values = <int>[
        if (area.key != NineAreaKey.felt)
          for (final sample in dayPredictions.values)
            sample.singleWhere((p) => p.key == area.key).score!,
      ];
      entries.add(
        NineAreaPeriodEntry(
          key: area.key,
          title: area.title,
          icon: area.icon,
          score: area.key == NineAreaKey.felt
              ? null
              : (values.reduce((a, b) => a + b) / values.length).round(),
          samples: List.unmodifiable(values),
          inherited: false,
        ),
      );
    }
    final maximum = counts.values.reduce(math.max);
    final date = _monthlyDateLabel(
      dayInstants.first.add(DailySevenTimepointPlan.jstOffset),
    );
    return PeriodSevenSummary._(
      mode: LongRangeMode.month,
      instants: dayInstants,
      entries: entries,
      counts: counts,
      modes: [
        for (final label in FeltForecastCandidate.labels)
          if (counts[label] == maximum) label,
      ],
      startDateJst: date,
      endDateJst: date,
      dayCount: 1,
      predictionsByInstant: Map.unmodifiable(dayPredictions),
      sourceName: sourceName,
      usesHighPrecisionAstroData: usesHighPrecisionAstroData,
      requestedHouseSystem: requestedHouseSystem,
      generatedAt: generatedAt,
      isDisplayRange: true,
    );
  }

  String displayRangeLabel(AppStrings strings) {
    final english = strings.language == AppLanguage.en;
    if (isSingleDay) return english ? 'this day' : 'この日';
    if (isDisplayRange) return english ? 'the selected half-month' : '選択した半月';
    return mode == LongRangeMode.week
        ? (english ? 'this week' : 'この週')
        : (english ? 'this month' : 'この月');
  }

  String get _sevenPeriodLabel =>
      displayRangeLabel(const AppStrings(AppLanguage.ja));

  @override
  String get samplingText =>
      '$startDateJst〜$endDateJst の全$dayCount日、各日00・04・08・12・16・20・24時 JST。'
      '$listedPointCount掲載点のうち、24時＝翌00時を1回だけ数えた$uniqueInstantCount時点を集計'
      '（最終日の24時＝翌日00時を含む）';

  @override
  String displaySamplingText(AppStrings strings) =>
      strings.language == AppLanguage.ja
      ? samplingText
      : 'All $dayCount days from $startDateJst to $endDateJst, at 00:00, '
            '04:00, 08:00, 12:00, 16:00, 20:00 and 24:00 JST. '
            '$listedPointCount listed points become $uniqueInstantCount unique instants: '
            '24:00 and the following 00:00 count once. Includes the final day’s '
            '24:00 (00:00 on the following day).';

  String displaySampleLimitation(AppStrings strings) =>
      strings.language == AppLanguage.ja
      ? '全日の7点式データを使った期間表示用の試作集計です。'
            '4時間ごとの確認時点と終端の集計であり、全時刻の平均や的中率ではありません。'
            '日別の採点式・モデル係数・保存済みJSONは変更していません。'
      : 'This provisional period display uses seven-point data for every day. '
            'It aggregates four-hour samples and the final boundary, not every '
            'instant or prediction accuracy. Daily scoring, model coefficients '
            'and saved JSON remain unchanged.';

  @override
  String reading(NineAreaPeriodEntry area) {
    if (area.key == NineAreaKey.felt) {
      final candidate = feltModes.length > 1
          ? '最多同数のため「混在」です'
          : '「$feltLabel」が最多の候補です';
      return '$_sevenPeriodLabel全体の$uniqueInstantCount時点では、体感は$candidate。'
          '体感は数値化せず、期間内で最も多い候補として示しています。';
    }
    // Retain the existing area-specific wording. Only the sampling population
    // changes; these texts do not introduce thresholds, weights or bonuses.
    final result = super.reading(area).replaceAll('確認日', '全日の7点式・重複を除いた時点');
    return isDisplayRange
        ? result.replaceAll('この月', _sevenPeriodLabel)
        : result;
  }

  @override
  String displayReading(NineAreaPeriodEntry area, AppStrings strings) {
    if (strings.language == AppLanguage.ja) return reading(area);
    if (area.key == NineAreaKey.felt) {
      final candidate = feltModes.length > 1
          ? 'the most frequent labels are tied (Mixed)'
          : '${strings.feltLabelText(feltLabel) ?? feltLabel} is the most frequent candidate';
      return 'Across all $uniqueInstantCount unique sampled instants of '
          '${displayRangeLabel(strings)}, $candidate. '
          'Felt experience stays categorical and describes the most frequent '
          'candidate over the period.';
    }
    final result = super
        .displayReading(area, strings)
        .replaceAll(
          'the sampled dates',
          'the unique seven-point samples across every day',
        );
    return isDisplayRange
        ? result.replaceAll('this month', displayRangeLabel(strings))
        : result;
  }

  @override
  String detail(NineAreaPeriodEntry area) =>
      displayDetail(area, const AppStrings(AppLanguage.ja));

  @override
  String displayDetail(NineAreaPeriodEntry area, AppStrings strings) {
    final english = strings.language == AppLanguage.en;
    final lines = <String>[
      displaySamplingText(strings),
      if (area.key == NineAreaKey.felt)
        displayFeltDistribution(strings)
      else ...[
        for (var index = 0; index < dates.length; index++)
          '${sampleKey(dates[index])}: ${area.samples[index]}',
        english
            ? 'Arithmetic mean rounded once at the end: ${area.score}. No period bonus or new coefficient.'
            : '算術平均を最後に1回四捨五入：${area.score}点。期間ボーナス・新しい係数は追加しません。',
      ],
      if (area.key == NineAreaKey.felt)
        english
            ? 'The most frequent candidate is used; ties remain Mixed. No numeric mean or missing-value imputation.'
            : '最多候補を表示し、最多同数は混在。数値平均・欠測の補完はしません。',
      '${english ? 'Daily model' : '日別モデル'}: ${NineAreaDailyForecast.modelVersion}',
      '${english ? 'Period display aggregation' : '期間表示集計'}: $aggregationModelVersion',
      displaySampleLimitation(strings),
    ];
    return lines.join('\n');
  }

  /// Diagnostic presentation summary only. This is deliberately a separate
  /// schema and never replaces any formal consultation export serializer.
  @override
  Map<String, Object?> toJson() => {
    'schema': 'pancyo_seven_point_period_display_summary_v1',
    'model_version': aggregationModelVersion,
    'daily_model_version': NineAreaDailyForecast.modelVersion,
    'provisional': true,
    'generated_at': generatedAt,
    'sampling': {
      'basis':
          'all_calendar_days_seven_points_unique_instants_including_final_boundary',
      'start_date_jst': startDateJst,
      'end_date_jst': endDateJst,
      'day_count': dayCount,
      'time_zone': 'Asia/Tokyo',
      'fixed_utc_offset': '+09:00',
      'times_jst': List<String>.of(_monthlyDailyTimesJst),
      'listed_point_count': listedPointCount,
      'unique_instant_count': uniqueInstantCount,
      'sample_count': uniqueInstantCount,
      'all_calendar_days_included': true,
      if (isDisplayRange)
        'display_range': isSingleDay ? 'single_day' : 'selected_half_month',
      'final_boundary_included': true,
      'instants_utc': [for (final date in dates) date.toIso8601String()],
      'instants_jst': [for (final date in dates) sampleKey(date)],
      'boundary_rule': '24:00_equals_next_00:00_verified_then_counted_once',
    },
    'calculation_source': {
      'provider': sourceName,
      'provider_uses_high_precision': usesHighPrecisionAstroData,
      'requested_house_system': requestedHouseSystem.name,
    },
    'overall_basis':
        'mean_of_existing_overall_scores_no_activity_or_felt_added',
    'areas': [
      for (final area in areas)
        {
          'key': area.key.name,
          'title': area.title,
          'score': area.score,
          'provisional': true,
          'reading': reading(area),
          'aggregation': area.key == NineAreaKey.felt
              ? 'categorical_frequency_no_numeric_average'
              : 'mean_of_rounded_unique_instant_scores_then_round_once',
          if (area.key != NineAreaKey.felt) ...{
            'sample_scores': List<int>.of(area.samples),
            'sum': area.samples.reduce((a, b) => a + b),
            'count': area.samples.length,
            'mean_before_rounding':
                area.samples.reduce((a, b) => a + b) / area.samples.length,
            'additional_period_bonus': 0,
          } else ...{
            'label': feltLabel,
            'display_label': feltDisplayLabel,
            'counts': Map<String, int>.of(feltCounts),
            'unavailable_count': feltUnavailableCount,
            'mode_labels': List<String>.of(feltModes),
            'tie_rule': 'display_mixed_without_selecting_a_label',
          },
        },
    ],
    'notice': displaySampleLimitation(const AppStrings(AppLanguage.ja)),
  };
}
