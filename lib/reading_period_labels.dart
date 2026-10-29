part of 'main.dart';

/// Five complete Sunday–Saturday weeks ending with the week of month end.
/// This graph window is separate from the preserved calendar-month summary.
List<List<DateTime>> monthlyReadingWeeks(DateTime month) {
  final last = DateTime.utc(month.year, month.month + 1, 0, 3);
  final end = last.add(Duration(days: 6 - last.weekday % 7));
  final start = end.subtract(const Duration(days: 34));
  return List.unmodifiable([
    for (var week = 0; week < 5; week++)
      List<DateTime>.unmodifiable([
        for (var day = 0; day < 7; day++) start.add(Duration(days: week * 7 + day)),
      ]),
  ]);
}

String readingCivilRange(DateTime start, DateTime end) {
  String d(DateTime value) => '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  return start == end ? d(start) : '${d(start)} – ${d(end)}';
}

/// A separate, explicitly labelled display export. Legacy formal JSON and
/// stored forecasts retain their schemas and original scopes.
Map<String, Object?> tenYearDisplayRecord(
  LongRangeDisplayRequest request,
  LongRangeDisplayResult result,
  AppStrings strings, {
  UserProfileDetails? details,
}) {
  if (request.mode != LongRangeDisplayMode.tenYear || !result.matches(request) ||
      result.summary.dates.length != 240 || result.trend.labels.length != 10) {
    throw StateError('A complete ten-year result is required.');
  }
  return {
    'schema': 'pancyo_ten_year_display_v1',
    'display_only': true,
    'formal_daily_json': false,
    'model_version': NineAreaDailyForecast.modelVersion,
    'aggregation_version': LongRangeDisplaySummary.aggregationVersion,
    'start_date_jst': '${request.startYear}-01-01',
    'end_date_jst': '${request.endYear}-12-31',
    'reference_sample_count': 240,
    'source': request.sourceName,
    'high_precision': request.requireHighPrecision,
    'areas': [for (final area in result.summary.areas) {
      'key': area.key.name,
      'score': area.score,
      if (area.key == NineAreaKey.felt) 'felt_modes': result.summary.feltModes,
      'reading': ForecastExplanation.forPeriod(summary: result.summary, area: area,
        strings: strings, depth: ReadingDepth.detailed, supplement: details,
        dailySamples: result.dailySamples).narrativeText,
    }],
    'year_labels': result.trend.labels,
    'yearly_main_series': [for (final series in result.trend.series) {
      'label': series.label, 'values': series.values,
    }],
    'yearly_additional_series': [for (final series in result.trend.additional.series) {
      'label': series.label, 'values': series.values,
    }],
    'reference_samples': [for (final date in request.summaryDates) {
      'instant_utc': date.toIso8601String(),
      'areas': [for (final prediction in result.samples[date]!.predictions) {
        'key': prediction.key.name, 'score': prediction.score,
        if (prediction.key == NineAreaKey.felt) 'felt': prediction.feltForecast?.label,
      }],
    }],
  };
}

String readingPeriodRange(NineAreaPeriodSummary summary) {
  if (summary is PeriodSevenSummary) {
    return summary.startDateJst == summary.endDateJst ? summary.startDateJst : '${summary.startDateJst} – ${summary.endDateJst}';
  }
  if (summary is LongRangeDisplaySummary) {
    if (summary.displayMode == LongRangeDisplayMode.month) {
      final date = summary.dates.first;
      return readingCivilRange(DateTime.utc(date.year, date.month), DateTime.utc(date.year, date.month + 1, 0));
    }
    return readingCivilRange(DateTime.utc(summary.startYear), DateTime.utc(summary.endYear, 12, 31));
  }
  final first = summary.dates.first.toUtc().add(const Duration(hours: 9));
  if (summary.mode == LongRangeMode.year) {
    return readingCivilRange(DateTime.utc(first.year), DateTime.utc(first.year, 12, 31));
  }
  if (summary.mode == LongRangeMode.month) {
    return readingCivilRange(DateTime.utc(first.year, first.month), DateTime.utc(first.year, first.month + 1, 0));
  }
  return readingCivilRange(DateTime.utc(first.year, first.month, first.day), DateTime.utc(first.year, first.month, first.day + 6));
}

class ReadingPeriodDate extends StatelessWidget {
  const ReadingPeriodDate({super.key, required this.label, this.marker = false});
  final String label;
  final bool marker;
  @override
  Widget build(BuildContext context) {
    final en = AppLanguageScope.stringsOf(context).language == AppLanguage.en;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text('${marker ? '◆ ' : ''}${marker ? (en ? 'Graph period' : 'グラフ期間') : (en ? 'Reading period' : '対象期間')}: $label · JST',
        style: TextStyle(fontSize: 14, height: 1.4, color: marker ? const Color(0xFFF6D77A) : const Color(0xFFB8C6E0), fontWeight: FontWeight.w700)),
    );
  }
}
