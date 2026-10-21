part of 'main.dart';

/// Presentation periods are deliberately separate from the formal JSON enum.
enum LongRangeDisplayMode { week, month, year, fiveYear }

class LongRangeDisplayRequest {
  LongRangeDisplayRequest({
    required this.mode,
    required DateTime month,
    required this.startYear,
    required this.profile,
    required this.houseSystem,
    String? sourceName,
    bool? requireHighPrecision,
    bool? scalarVoid,
    this.fullContext = true,
  }) : month = DateTime.utc(month.year, month.month),
       sourceName = sourceName ?? AstrologyDataSources.current.sourceName,
       requireHighPrecision =
           requireHighPrecision ??
           AstrologyDataSources.current.usesHighPrecisionAstroData,
       scalarVoid =
           scalarVoid ?? SwissEphemerisProvider._forceScalarVoidForCheck {
    if (mode == LongRangeDisplayMode.week) {
      throw ArgumentError('Weeks retain their existing seven-point worker.');
    }
  }

  final LongRangeDisplayMode mode;
  final DateTime month;
  final int startYear;
  final AstroProfile profile;
  final HouseSystem houseSystem;
  final String sourceName;
  final bool requireHighPrecision, scalarVoid;

  /// The preserved complete route remains the default until separately enabled.
  /// This flag never changes a formal daily or period JSON calculation.
  final bool fullContext;
  int get endYear =>
      startYear + (mode == LongRangeDisplayMode.fiveYear ? 4 : 0);
  late final List<DateTime> dates = List.unmodifiable(
    mode == LongRangeDisplayMode.month
        ? NineAreaPeriodSummary.sampleDates(
            LongRangeMode.month,
            month,
            month.year,
          )
        : [
            for (var year = startYear; year <= endYear; year++)
              ...NineAreaPeriodSummary.sampleDates(
                LongRangeMode.year,
                DateTime.utc(year),
                year,
              ),
          ],
  );

  late final String inputIdentity = sha256
      .convert(
        utf8.encode(
          jsonEncode([
            'long-range-display-inputs-v2',
            profile.name,
            profile.birthDate,
            profile.birthClock?.cacheIdentity,
            profile.birthTime,
            profile.birthPlace,
            profile.theme,
            profile.savedProfileId,
            houseSystem.name,
            sourceName,
            requireHighPrecision,
            scalarVoid,
            fullContext,
            NineAreaDailyForecast.modelVersion,
            NineAreaPeriodSummary.generalModelVersion,
          ]),
        ),
      )
      .toString();

  late final String identity = sha256
      .convert(
        utf8.encode(
          jsonEncode([
            inputIdentity,
            mode.name,
            dates.map((d) => d.toIso8601String()).toList(),
          ]),
        ),
      )
      .toString();

  bool get matchesCurrentInputs =>
      houseSystem == HouseSystemSettings.current.value &&
      sourceName == AstrologyDataSources.current.sourceName &&
      requireHighPrecision ==
          AstrologyDataSources.current.usesHighPrecisionAstroData &&
      scalarVoid == SwissEphemerisProvider._forceScalarVoidForCheck;
}

/// Only existing daily predictions are averaged. No score formula is added.
class LongRangeDisplaySummary extends NineAreaPeriodSummary {
  LongRangeDisplaySummary._({
    required this.displayMode,
    required this.startYear,
    required this.endYear,
    required List<DateTime> dates,
    required List<NineAreaPeriodEntry> areas,
    required Map<String, int> counts,
    required int missing,
    required List<String> modes,
    this.sampleDescriptionJa,
    this.sampleDescriptionEn,
  }) : super._(
         displayMode == LongRangeDisplayMode.month
             ? LongRangeMode.month
             : LongRangeMode.year,
         List.unmodifiable(dates),
         List.unmodifiable(areas),
         Map.unmodifiable(counts),
         missing,
         List.unmodifiable(modes),
         'display_only_unchanged_daily_samples',
         true,
       );

  final LongRangeDisplayMode displayMode;
  final int startYear, endYear;
  final String? sampleDescriptionJa, sampleDescriptionEn;
  bool get isFiveYear => displayMode == LongRangeDisplayMode.fiveYear;
  static const aggregationVersion = 'long-range-display-sample-mean-v1';

  factory LongRangeDisplaySummary.fromSamples({
    required LongRangeDisplayRequest request,
    required Map<DateTime, List<NineAreaPrediction>> samples,
  }) {
    final dates = request.dates;
    if (samples.length != dates.length ||
        dates.any((date) => !samples.containsKey(date))) {
      throw StateError('The selected reference samples are incomplete.');
    }
    return LongRangeDisplaySummary._aggregate(
      mode: request.mode,
      startYear: request.startYear,
      endYear: request.endYear,
      dates: dates,
      samples: samples,
    );
  }

  static LongRangeDisplaySummary _aggregate({
    required LongRangeDisplayMode mode,
    required int startYear,
    required int endYear,
    required List<DateTime> dates,
    required Map<DateTime, List<NineAreaPrediction>> samples,
    String? descriptionJa,
    String? descriptionEn,
  }) {
    if (dates.isEmpty) throw StateError('Reference samples are required.');
    final counts = {for (final label in FeltForecastCandidate.labels) label: 0};
    var missing = 0;
    for (final date in dates) {
      final predictions = samples[date];
      if (!date.isUtc ||
          date.hour != 3 ||
          date.minute != 0 ||
          predictions == null ||
          predictions.length != 9 ||
          predictions.map((p) => p.key).toSet().length != 9) {
        throw StateError('The nine daily predictions are incomplete.');
      }
      for (final prediction in predictions) {
        if (prediction.key == NineAreaKey.felt) {
          final label = prediction.feltForecast?.label;
          if (prediction.score != null ||
              (label != null && !counts.containsKey(label))) {
            throw StateError('Felt experience must remain categorical.');
          }
          if (label == null) {
            missing++;
          } else {
            counts[label] = counts[label]! + 1;
          }
        } else if (prediction.score == null ||
            prediction.score! < 50 ||
            prediction.score! > 99) {
          throw StateError('A reference score is missing or out of range.');
        }
      }
    }
    final maximum = counts.values.reduce(math.max);
    return LongRangeDisplaySummary._(
      displayMode: mode,
      startYear: startYear,
      endYear: endYear,
      dates: dates,
      areas: [
        for (final key in NineAreaKey.values)
          (() {
            final template = samples[dates.first]!.singleWhere(
              (p) => p.key == key,
            );
            final values = <int>[
              if (key != NineAreaKey.felt)
                for (final date in dates)
                  samples[date]!.singleWhere((p) => p.key == key).score!,
            ];
            return NineAreaPeriodEntry(
              key: key,
              title: template.title,
              icon: template.icon,
              score: values.isEmpty
                  ? null
                  : (values.reduce((a, b) => a + b) / values.length).round(),
              samples: List.unmodifiable(values),
              inherited: false,
            );
          })(),
      ],
      counts: counts,
      missing: missing,
      modes: [
        if (maximum > 0)
          for (final label in FeltForecastCandidate.labels)
            if (counts[label] == maximum) label,
      ],
      sampleDescriptionJa: descriptionJa,
      sampleDescriptionEn: descriptionEn,
    );
  }

  @override
  String get samplingText =>
      sampleDescriptionJa ??
      (isFiveYear
          ? '$startYear〜$endYear年の各月1日・15日、計120時点（12:00 JST）'
          : super.samplingText);

  @override
  String displaySamplingText(AppStrings strings) =>
      strings.language == AppLanguage.ja
      ? samplingText
      : sampleDescriptionEn ??
            (isFiveYear
                ? '120 samples from $startYear to $endYear: the first and fifteenth of each month, at 12:00 JST'
                : super.displaySamplingText(strings));

  @override
  String reading(NineAreaPeriodEntry area) => isFiveYear
      ? super.reading(area).replaceAll('この年', 'この5年間')
      : super.reading(area);

  @override
  String displayReading(NineAreaPeriodEntry area, AppStrings strings) =>
      strings.language == AppLanguage.ja
      ? reading(area)
      : isFiveYear
      ? super
            .displayReading(area, strings)
            .replaceAll('this year', 'these five years')
      : super.displayReading(area, strings);

  // This object is an in-memory presentation, never a formal consult record.
  @override
  Map<String, Object?> toJson() => throw UnsupportedError(
    'Display summaries are not formal JSON export records.',
  );
}

class LongRangeDisplaySample {
  LongRangeDisplaySample({
    required this.inputIdentity,
    required this.date,
    required this.sourceName,
    required this.precisionNotice,
    required this.usesHighPrecision,
    required this.resolvedHouseSystem,
    required List<double> houseCusps,
    required List<NineAreaPrediction> predictions,
    this.displayOnlyPositions = false,
  }) : predictions = List.unmodifiable(predictions),
       houseCusps = List.unmodifiable(houseCusps);
  final String inputIdentity;
  final DateTime date;
  final String sourceName, precisionNotice;
  final bool usesHighPrecision;
  final HouseSystem resolvedHouseSystem;
  final List<double> houseCusps;
  final List<NineAreaPrediction> predictions;
  final bool displayOnlyPositions;
  Map<String, Object?> get displayCalculation {
    final inputs = predictions
        .singleWhere((p) => p.key == NineAreaKey.felt)
        .feltForecast
        ?.trace['inputs'];
    return Map.unmodifiable({
      'display_only_positions': displayOnlyPositions,
      'void_period_status': displayOnlyPositions
          ? 'not_requested'
          : 'calculated',
      'void_day_share': displayOnlyPositions
          ? null
          : inputs is Map
          ? inputs['void_day_share']
          : null,
      'not_requested_void_is_not_zero': displayOnlyPositions,
    });
  }
}

/// Application-authored UI copy; the raw provider notice remains diagnostic.
String longRangeSourceDisplayNotice(
  LongRangeDisplaySample sample,
  AppStrings strings,
) {
  final en = strings.language == AppLanguage.en;
  final source = en && sample.sourceName == 'アプリ内簡易計算'
      ? 'Built-in simplified calculation'
      : sample.sourceName;
  if (sample.displayOnlyPositions) {
    return en
        ? 'Calculation source: $source. Uses the existing source positions; daily scores are unchanged. Lunar void context was not requested. This does not mean no void period or a zero value.'
        : '星データ：$source。既存の計算元の天体位置を使い、日点数は維持しています。月ボイドの背景情報は取得していません。未取得は無ボイドや0を意味しません。';
  }
  if (sample.usesHighPrecision &&
      sample.sourceName == 'Swiss Ephemeris Free Edition') {
    return en
        ? 'Calculation source: $source. Positions use the existing Android native Moshier calculation. Lunar void context is calculated through the existing full route.'
        : '星データ：$source。既存のAndroidネイティブMoshier計算で天体位置を取得しています。月ボイドの背景情報も従来の経路で計算しています。';
  }
  return en
      ? 'Calculation source: $source. High-precision astronomical data: ${sample.usesHighPrecision ? 'used' : 'not used'}. Lunar void context is calculated through the existing full route.'
      : '星データ：$source。高精度天文データ：${sample.usesHighPrecision ? '使用' : '未使用'}。月ボイドの背景情報も従来の経路で計算しています。';
}

class LongRangeDisplayResult {
  LongRangeDisplayResult({
    required this.requestIdentity,
    required Map<DateTime, LongRangeDisplaySample> samples,
    required this.summary,
    required this.trend,
    required this.computedSampleCount,
  }) : samples = Map.unmodifiable(samples);
  final String requestIdentity;
  final Map<DateTime, LongRangeDisplaySample> samples;
  final LongRangeDisplaySummary summary;
  final LongRangeDisplayTrendData trend;
  final int computedSampleCount;
  Map<String, List<NineAreaPrediction>> get dailySamples => Map.unmodifiable({
    for (final entry in samples.entries)
      NineAreaPeriodSummary.dateLabel(entry.key): entry.value.predictions,
  });
  bool matches(LongRangeDisplayRequest request) =>
      requestIdentity == request.identity &&
      samples.length == request.dates.length &&
      summary.dates.length == request.dates.length &&
      request.dates.every((date) {
        final sample = samples[date];
        return sample != null &&
            sample.inputIdentity == request.inputIdentity &&
            sample.date == date &&
            sample.sourceName == request.sourceName &&
            sample.usesHighPrecision == request.requireHighPrecision &&
            sample.displayOnlyPositions == !request.fullContext &&
            sample.houseCusps.length == 12 &&
            sample.houseCusps.every((cusp) => cusp.isFinite);
      });
}

class LongRangeDisplayTrendData {
  LongRangeDisplayTrendData._(this.labels, this.series, this.additional);
  final List<String> labels;
  final List<FortuneFlowSeries> series;
  final AdditionalFortuneTrendData additional;

  factory LongRangeDisplayTrendData.fromSamples({
    required LongRangeDisplayRequest request,
    required Map<DateTime, List<NineAreaPrediction>> samples,
  }) {
    final dates = request.dates;
    final groups = request.mode == LongRangeDisplayMode.month
        ? <List<DateTime>>[
            [dates[0]],
            [dates[1]],
            [dates[2]],
            [dates[3], dates[4]],
          ]
        : request.mode == LongRangeDisplayMode.year
        ? [for (var i = 0; i < 24; i += 2) dates.sublist(i, i + 2)]
        : [for (var i = 0; i < 120; i += 24) dates.sublist(i, i + 24)];
    final labels = request.mode == LongRangeDisplayMode.month
        ? ['1–7', '8–14', '15–21', '22–${dates.last.day}']
        : request.mode == LongRangeDisplayMode.year
        ? [for (var month = 1; month <= 12; month++) '$month月']
        : [
            for (var year = request.startYear; year <= request.endYear; year++)
              '$year',
          ];
    final summaries = [
      for (var i = 0; i < groups.length; i++)
        LongRangeDisplaySummary._aggregate(
          mode: request.mode == LongRangeDisplayMode.fiveYear
              ? LongRangeDisplayMode.year
              : LongRangeDisplayMode.month,
          startYear: groups[i].first.year,
          endYear: groups[i].last.year,
          dates: groups[i],
          samples: samples,
          descriptionJa: request.mode == LongRangeDisplayMode.month
              ? '${labels[i]}日区間の代表日${groups[i].map((d) => '${d.day}日').join('・')}（12:00 JST）'
              : request.mode == LongRangeDisplayMode.year
              ? '${i + 1}月1日・15日の2時点（12:00 JST）'
              : null,
          descriptionEn: request.mode == LongRangeDisplayMode.month
              ? 'Days ${labels[i]}: reference dates ${groups[i].map((d) => d.day).join(', ')}, at 12:00 JST'
              : request.mode == LongRangeDisplayMode.year
              ? 'Month ${i + 1}: two samples, on the first and fifteenth, at 12:00 JST'
              : null,
        ),
    ];
    List<int> values(NineAreaKey key) => [
      for (final summary in summaries)
        summary.areas.singleWhere((a) => a.key == key).score!,
    ];
    return LongRangeDisplayTrendData._(
      List.unmodifiable(labels),
      List.unmodifiable([
        for (var i = 0; i < PeriodSevenGroupedTrendData.mainKeys.length; i++)
          FortuneFlowSeries(
            label: PeriodSevenGroupedTrendData.mainLabels[i],
            color: PeriodSevenGroupedTrendData.mainColors[i],
            values: List.unmodifiable(
              values(PeriodSevenGroupedTrendData.mainKeys[i]),
            ),
          ),
      ]),
      AdditionalFortuneTrendData._build(
        labels,
        [for (final key in AdditionalFortuneTrendData.numericKeys) values(key)],
        [
          for (final summary in summaries)
            FeltTrendPoint(
              label: summary.feltDisplayLabel,
              periodSummary: summary,
              detail: summary.detail(
                summary.areas.singleWhere((a) => a.key == NineAreaKey.felt),
              ),
            ),
        ],
      ),
    );
  }
}

abstract class LongRangeDisplayOperation {
  Future<LongRangeDisplayResult> get result;
  void cancel();
}

typedef LongRangeDisplayStarter =
    LongRangeDisplayOperation Function(
      LongRangeDisplayRequest request,
      void Function(int completed, int total) onProgress,
    );

class LongRangeDisplayCancelled implements Exception {
  const LongRangeDisplayCancelled();
}

/// A bounded cache of completed samples for one person and calculation input.
class LongRangeDisplayCache {
  LongRangeDisplayCache({this.maxSamples = 240}) {
    if (maxSamples < 120 || maxSamples > 240) {
      throw RangeError.range(maxSamples, 120, 240, 'maxSamples');
    }
  }
  final int maxSamples;
  String? _inputIdentity;
  final _samples = <DateTime, LongRangeDisplaySample>{};
  int get retainedSampleCount => _samples.length;
  Map<DateTime, LongRangeDisplaySample> seeds(LongRangeDisplayRequest request) {
    if (_inputIdentity != request.inputIdentity) {
      _samples.clear();
      _inputIdentity = request.inputIdentity;
    }
    return {
      for (final date in request.dates)
        if (_samples.containsKey(date)) date: _samples[date]!,
    };
  }

  void publish(LongRangeDisplayRequest request, LongRangeDisplayResult result) {
    if (_inputIdentity != request.inputIdentity || !result.matches(request))
      return;
    _publish(result.samples);
  }

  void publishCompletedYear(
    LongRangeDisplayRequest request,
    Map<DateTime, LongRangeDisplaySample> samples,
  ) {
    if (_inputIdentity != request.inputIdentity || samples.length != 24) return;
    final year = samples.keys.first.year;
    final dates = NineAreaPeriodSummary.sampleDates(
      LongRangeMode.year,
      DateTime.utc(year),
      year,
    );
    if (year < request.startYear ||
        year > request.endYear ||
        dates.any(
          (date) =>
              samples[date]?.inputIdentity != request.inputIdentity ||
              samples[date]?.date != date ||
              samples[date]?.sourceName != request.sourceName ||
              samples[date]?.usesHighPrecision != request.requireHighPrecision,
        ))
      return;
    _publish(samples);
  }

  void _publish(Map<DateTime, LongRangeDisplaySample> samples) {
    for (final entry in samples.entries) {
      _samples.remove(entry.key);
      _samples[entry.key] = entry.value;
    }
    while (_samples.length > maxSamples) {
      _samples.remove(_samples.keys.first);
    }
  }
}

class LongRangeDisplayJob implements LongRangeDisplayOperation {
  LongRangeDisplayJob.start(
    LongRangeDisplayRequest request, {
    Map<DateTime, LongRangeDisplaySample> seeds = const {},
    void Function(int completed, int total)? onProgress,
    void Function(Map<DateTime, LongRangeDisplaySample> samples)?
    onCompletedYear,
  }) {
    _port.listen((message) {
      if (_finished) return;
      if (message is List && message.length == 3 && message[0] == 'progress') {
        onProgress?.call(message[1] as int, message[2] as int);
        return;
      }
      if (message is List && message.length == 2 && message[0] == 'year') {
        onCompletedYear?.call(
          Map<DateTime, LongRangeDisplaySample>.from(message[1] as Map),
        );
        return;
      }
      _finish();
      if (message is LongRangeDisplayResult && message.matches(request)) {
        _result.complete(message);
      } else {
        _result.completeError(StateError('期間の星配置を準備できませんでした。'));
      }
    });
    unawaited(_spawn(request, seeds));
  }
  final _port = ReceivePort();
  final _result = Completer<LongRangeDisplayResult>();
  Isolate? _isolate;
  bool _finished = false;
  @override
  Future<LongRangeDisplayResult> get result => _result.future;
  Future<void> _spawn(
    LongRangeDisplayRequest request,
    Map<DateTime, LongRangeDisplaySample> seeds,
  ) async {
    try {
      final worker = await Isolate.spawn(
        _longRangeDisplayWorker,
        (request, _port.sendPort, seeds),
        debugName: 'pancyo-long-range-display',
        onError: _port.sendPort,
        onExit: _port.sendPort,
      );
      if (_finished) {
        worker.kill(priority: Isolate.immediate);
      } else {
        _isolate = worker;
      }
    } catch (_) {
      if (!_finished) {
        _finish();
        _result.completeError(StateError('期間の別処理を開始できませんでした。'));
      }
    }
  }

  void _finish() {
    _finished = true;
    _port.close();
    _isolate?.kill(priority: Isolate.immediate);
  }

  @override
  void cancel() {
    if (_finished) return;
    _finish();
    _result.completeError(const LongRangeDisplayCancelled());
  }
}

void _longRangeDisplayWorker(
  (LongRangeDisplayRequest, SendPort, Map<DateTime, LongRangeDisplaySample>)
  input,
) {
  try {
    final request = input.$1;
    HouseSystemSettings.current.value = request.houseSystem;
    SwissEphemerisProvider._forceScalarVoidForCheck = request.scalarVoid;
    if (!request.matchesCurrentInputs)
      throw StateError('Calculation source changed.');
    final before = SwissEphemerisProvider._placementFallbackCount;
    final houseBefore = SwissEphemerisProvider._houseFallbackCount;
    final ephemeris = AstrologyDataSources.current;
    final natalDate = ephemeris.dateFromProfile(request.profile);
    final birthPlace = ephemeris.placeForProfile(request.profile);
    final frame = ephemeris.houseFrameFor(
      natalDate,
      birthPlace,
      request.houseSystem,
    );
    // Shared real natal positions, constructed only if a missing display-only
    // sample needs them. A completely cached request does not recalculate them.
    late final NatalChart displayNatal = _longRangeDisplayNatal(
      request: request,
      ephemeris: ephemeris,
      frame: frame,
      natalDate: natalDate,
      birthPlace: birthPlace,
      placementFallbackBefore: before,
      houseFallbackBefore: houseBefore,
    );
    final samples = <DateTime, LongRangeDisplaySample>{};
    var computed = 0;
    for (final date in request.dates) {
      final seed = input.$3[date];
      if (seed != null &&
          (seed.inputIdentity != request.inputIdentity ||
              seed.date != date ||
              seed.resolvedHouseSystem != frame.system ||
              seed.sourceName != request.sourceName ||
              seed.usesHighPrecision != request.requireHighPrecision ||
              seed.displayOnlyPositions != !request.fullContext ||
              seed.houseCusps.length != frame.cusps.length ||
              List.generate(
                frame.cusps.length,
                (i) => seed.houseCusps[i] != frame.cusps[i],
              ).any((v) => v))) {
        throw StateError('Cached reference conditions do not match.');
      }
      if (seed != null) {
        samples[date] = seed;
      } else if (!request.fullContext) {
        final natal = displayNatal;
        final placements = ephemeris.placementsFor(date, houseFrame: frame);
        if (!request.matchesCurrentInputs ||
            (request.requireHighPrecision &&
                SwissEphemerisProvider._placementFallbackCount != before)) {
          throw StateError('Display reference precision is incomplete.');
        }
        samples[date] = LongRangeDisplaySample(
          inputIdentity: request.inputIdentity,
          date: date,
          sourceName: ephemeris.sourceName,
          precisionNotice: ephemeris.precisionNotice,
          usesHighPrecision: ephemeris.usesHighPrecisionAstroData,
          resolvedHouseSystem: frame.system,
          houseCusps: frame.cusps,
          displayOnlyPositions: true,
          predictions: NineAreaDailyForecast.fromDisplayPositions(
            natal: natal,
            instantUtc: date,
            transitPlacements: placements,
            usesHighPrecisionAstroData: ephemeris.usesHighPrecisionAstroData,
          ),
        );
        computed++;
      } else {
        final context = const AstrologyEngine().buildPreviewContext(
          profile: request.profile,
          date: date,
        );
        if (context.ephemerisSourceName != request.sourceName ||
            context.usesHighPrecisionAstroData !=
                request.requireHighPrecision ||
            context.houseSystem != frame.system) {
          throw StateError(
            'Reference precision or house system does not match.',
          );
        }
        samples[date] = LongRangeDisplaySample(
          inputIdentity: request.inputIdentity,
          date: date,
          sourceName: context.ephemerisSourceName,
          precisionNotice: context.ephemerisPrecisionNotice,
          usesHighPrecision: context.usesHighPrecisionAstroData,
          resolvedHouseSystem: context.houseSystem,
          houseCusps: context.houseCusps,
          predictions: NineAreaDailyForecast.fromContext(context),
        );
        computed++;
      }
      input.$2.send(['progress', samples.length, request.dates.length]);
      if (request.mode != LongRangeDisplayMode.month &&
          date.month == 12 &&
          date.day == 15) {
        if (request.requireHighPrecision &&
            SwissEphemerisProvider._placementFallbackCount != before) {
          throw StateError(
            'High-precision placement calculation was incomplete.',
          );
        }
        input.$2.send([
          'year',
          {
            for (final entry in samples.entries)
              if (entry.key.year == date.year) entry.key: entry.value,
          },
        ]);
      }
    }
    if (request.requireHighPrecision &&
        SwissEphemerisProvider._placementFallbackCount != before) {
      throw StateError('High-precision placement calculation was incomplete.');
    }
    final predictions = {
      for (final entry in samples.entries) entry.key: entry.value.predictions,
    };
    final result = LongRangeDisplayResult(
      requestIdentity: request.identity,
      samples: samples,
      summary: LongRangeDisplaySummary.fromSamples(
        request: request,
        samples: predictions,
      ),
      trend: LongRangeDisplayTrendData.fromSamples(
        request: request,
        samples: predictions,
      ),
      computedSampleCount: computed,
    );
    if (!result.matches(request))
      throw StateError('Reference data is incomplete.');
    Isolate.exit(input.$2, result);
  } catch (_) {
    input.$2.send('failed');
  }
}

/// Uses the same provider calls and retrograde comparison as the preserved
/// engine's natal computation, once per display worker. It never fabricates an
/// empty natal retrograde set, substitutes positions, or changes house rules.
NatalChart _longRangeDisplayNatal({
  required LongRangeDisplayRequest request,
  required EphemerisProvider ephemeris,
  required HouseFrame frame,
  required DateTime natalDate,
  required GeoPoint birthPlace,
  required int placementFallbackBefore,
  required int houseFallbackBefore,
}) {
  if (request.profile.birthClock != null &&
      !ephemeris.usesHighPrecisionAstroData) {
    throw StateError('Regional birth time requires the native ephemeris.');
  }
  final placements = ephemeris.placementsFor(
    natalDate,
    place: birthPlace,
    houseFrame: frame,
  );
  final next = ephemeris.placementsFor(
    natalDate.add(const Duration(days: 1)),
    place: birthPlace,
    houseFrame: frame,
  );
  if (request.profile.birthClock != null &&
      (SwissEphemerisProvider._placementFallbackCount !=
              placementFallbackBefore ||
          SwissEphemerisProvider._houseFallbackCount != houseFallbackBefore ||
          frame.system != request.houseSystem)) {
    throw StateError(
      'Regional natal calculation is unavailable; no fallback result is shown.',
    );
  }
  return NatalChart(
    profile: request.profile,
    placements: placements,
    stelliums: ephemeris.stelliums(placements),
    retrogradePlanets: {
      for (final planet in const [
        AstroPlanet.mercury,
        AstroPlanet.venus,
        AstroPlanet.mars,
        AstroPlanet.jupiter,
        AstroPlanet.saturn,
        AstroPlanet.uranus,
        AstroPlanet.neptune,
        AstroPlanet.pluto,
      ])
        if (const AstrologyEngine()._isRetrograde(planet, placements, next))
          planet,
    },
  );
}

class LongRangeOverviewPanel extends StatefulWidget {
  const LongRangeOverviewPanel({
    super.key,
    required this.request,
    required this.details,
    required this.depth,
    this.startJob,
  });
  final LongRangeDisplayRequest request;
  final UserProfileDetails details;
  final ReadingDepth depth;
  final LongRangeDisplayStarter? startJob;
  @override
  State<LongRangeOverviewPanel> createState() => _LongRangeOverviewPanelState();
}

class _LongRangeOverviewPanelState extends State<LongRangeOverviewPanel>
    with WidgetsBindingObserver {
  static final _cache = LongRangeDisplayCache();
  LongRangeDisplayOperation? _operation;
  LongRangeDisplayResult? _result;
  int _generation = 0, _completed = 0;
  bool _failed = false, _cancelled = false;
  final _completedYears = <int, Map<DateTime, LongRangeDisplaySample>>{};
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _schedule();
  }

  void _schedule() {
    final generation = ++_generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _generation) return;
      _begin(generation);
    });
  }

  void _begin(int generation) {
    final request = widget.request;
    final watch = Stopwatch()..start();
    bool current() =>
        mounted &&
        generation == _generation &&
        request.identity == widget.request.identity &&
        request.matchesCurrentInputs;
    void failed(Object error) {
      if (!current()) return;
      setState(() {
        _operation = null;
        _cancelled = error is LongRangeDisplayCancelled;
        _failed = !_cancelled;
      });
    }

    try {
      void progress(int done, int total) {
        if (current()) setState(() => _completed = done);
      }

      final operation =
          widget.startJob?.call(request, progress) ??
          LongRangeDisplayJob.start(
            request,
            seeds: _cache.seeds(request),
            onProgress: progress,
            onCompletedYear: (samples) {
              if (!current()) return;
              _cache.publishCompletedYear(request, samples);
              setState(
                () => _completedYears[samples.keys.first.year] = samples,
              );
              if (reworkTestBuild) {
                debugPrint(
                  'PANCYO_RANGE_QA ${jsonEncode({'phase': 'year_ready', 'elapsed_ms': watch.elapsedMilliseconds, 'ready_year_count': _completedYears.length})}',
                );
              }
            },
          );
      _operation = operation;
      unawaited(
        operation.result.then((result) {
          if (!current()) return;
          if (!result.matches(request)) {
            failed(StateError('条件が一致しません。'));
            return;
          }
          _cache.publish(request, result);
          watch.stop();
          if (reworkTestBuild) {
            final source = result.samples.values.first;
            debugPrint(
              'PANCYO_RANGE_QA ${jsonEncode({'phase': 'complete', 'mode': request.mode.name, 'samples': result.samples.length, 'computed': result.computedSampleCount, 'elapsed_ms': watch.elapsedMilliseconds, 'source': source.sourceName, 'high_precision': source.usesHighPrecision, 'full_context': request.fullContext})}',
            );
          }
          setState(() {
            _operation = null;
            _result = result;
          });
        }, onError: failed),
      );
    } catch (error) {
      failed(error);
    }
  }

  void _stop() {
    ++_generation;
    _operation?.cancel();
    _operation = null;
  }

  @override
  void didUpdateWidget(covariant LongRangeOverviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request.identity != widget.request.identity ||
        oldWidget.startJob != widget.startJob) {
      _stop();
      _result = null;
      _completed = 0;
      _failed = false;
      _cancelled = false;
      _completedYears.clear();
      _schedule();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _result == null) {
      _stop();
      if (mounted) setState(() => _cancelled = true);
    }
  }

  @override
  void dispose() {
    _stop();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLanguageScope.stringsOf(context);
    final en = strings.language == AppLanguage.en;
    final result = _result;
    if (result == null) {
      return GlassPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _failed
                  ? (en
                        ? 'Unable to prepare the reference positions.'
                        : '期間の星配置を準備できませんでした。')
                  : _cancelled
                  ? (en ? 'Calculation stopped.' : '期間の準備を中止しました。')
                  : en
                  ? 'Preparing readings… $_completed/${widget.request.dates.length}'
                  : '期間の星配置を準備中… $_completed/${widget.request.dates.length}',
              key: const ValueKey('long-range-status'),
            ),
            const SizedBox(height: 12),
            if (!_failed && !_cancelled)
              LinearProgressIndicator(
                value: _completed / widget.request.dates.length,
              ),
            TextButton(
              key: ValueKey(
                _failed || _cancelled
                    ? 'long-range-retry'
                    : 'long-range-cancel',
              ),
              onPressed: () {
                if (_failed || _cancelled) {
                  setState(() {
                    _failed = false;
                    _cancelled = false;
                    _completed = 0;
                  });
                  _schedule();
                } else {
                  _stop();
                  setState(() => _cancelled = true);
                }
              },
              child: Text(
                _failed || _cancelled
                    ? (en ? 'Retry' : '準備を再試行')
                    : (en ? 'Stop' : '準備を中止'),
              ),
            ),
            if (widget.request.mode == LongRangeDisplayMode.fiveYear) ...[
              Text(
                en
                    ? 'The five-year summary is incomplete until all 120 reference samples are ready.'
                    : '120の代表時点がそろうまで、5年間全体の占いは未完成です。',
                key: const ValueKey('five-year-incomplete'),
              ),
              const SizedBox(height: 12),
              LongRangePartialYearView(
                request: widget.request,
                completedYears: _completedYears,
                depth: widget.depth,
                details: widget.details,
              ),
            ],
          ],
        ),
      );
    }
    final source = result.samples.values.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProfileReflectionNotice(hasProfileDetails: widget.details.hasAny),
        if (!widget.details.hasExactBirthBase) const BirthPrecisionNotice(),
        BirthLocationReviewNotice(profile: widget.request.profile),
        if (source.resolvedHouseSystem != widget.request.houseSystem)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              en
                  ? 'Requested house system: ${widget.request.houseSystem.label}. Resolved house system: ${source.resolvedHouseSystem.label}.'
                  : '指定ハウス方式：${widget.request.houseSystem.label}。今回の計算方式：${source.resolvedHouseSystem.label}。',
              style: const TextStyle(fontSize: 12, color: Color(0xFFB8C6E0)),
            ),
          ),
        if (widget.depth == ReadingDepth.detailed)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              longRangeSourceDisplayNotice(source, strings),
              style: const TextStyle(fontSize: 12, color: Color(0xFFB8C6E0)),
            ),
          ),
        const SizedBox(height: 14),
        LongRangeDisplayTrendView(
          data: result.trend,
          mode: widget.request.mode,
        ),
        const SizedBox(height: 18),
        NineAreaPeriodOverview(
          summary: result.summary,
          depth: widget.depth,
          details: widget.details,
          dailySamples: result.dailySamples,
        ),
      ],
    );
  }
}

class LongRangeDisplayTrendView extends StatelessWidget {
  const LongRangeDisplayTrendView({
    super.key,
    required this.data,
    required this.mode,
  });
  final LongRangeDisplayTrendData data;
  final LongRangeDisplayMode mode;
  @override
  Widget build(BuildContext context) {
    final strings = AppLanguageScope.stringsOf(context);
    final en = strings.language == AppLanguage.en;
    final basis = mode == LongRangeDisplayMode.month
        ? (en
              ? 'Four intervals in this month; reference dates are 1, 8, 15, 22 and the last day. The final point averages the 22nd and last day.'
              : 'この月の4区間。代表日は1・8・15・22・末日で、最後の点は22日と末日の平均です。')
        : mode == LongRangeDisplayMode.year
        ? (en
              ? '12 monthly points, each averaging the first and fifteenth at noon JST.'
              : '月ごとの12点。各点は1日・15日の正午JSTの平均です。')
        : (en
              ? 'Five yearly points, each averaging 24 noon-JST reference samples.'
              : '年ごとの5点。各点は各年24の正午JST代表時点の平均です。');
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            en ? 'Fortune trends' : '運勢の流れ',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            basis,
            style: const TextStyle(fontSize: 12, color: Color(0xFFB8C6E0)),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: math.max(
                  constraints.maxWidth,
                  MediaQuery.textScalerOf(context).scale(56) *
                      data.labels.length,
                ),
                height: FortuneFlowPainter.chartHeight(
                  MediaQuery.textScalerOf(context),
                ),
                child: CustomPaint(
                  key: const ValueKey('long-range-main-chart'),
                  painter: FortuneFlowPainter(
                    series: data.series,
                    textScaler: MediaQuery.textScalerOf(context),
                    labels: data.labels
                        .map((label) => periodTrendAxisLabel(label, strings))
                        .toList(),
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              for (final series in data.series)
                _FlowLegend(label: series.label, color: series.color),
            ],
          ),
          AdditionalFortuneTrendChart(
            dataIdentity: data,
            dataFor: () => data.additional,
            basis: basis,
          ),
        ],
      ),
    );
  }
}

class LongRangePartialYearView extends StatefulWidget {
  const LongRangePartialYearView({
    super.key,
    required this.request,
    required this.completedYears,
    required this.depth,
    required this.details,
  });
  final LongRangeDisplayRequest request;
  final Map<int, Map<DateTime, LongRangeDisplaySample>> completedYears;
  final ReadingDepth depth;
  final UserProfileDetails details;
  @override
  State<LongRangePartialYearView> createState() =>
      _LongRangePartialYearViewState();
}

class _LongRangePartialYearViewState extends State<LongRangePartialYearView> {
  final _summaries = <int, LongRangeDisplaySummary>{};
  @override
  void didUpdateWidget(covariant LongRangePartialYearView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request.identity != widget.request.identity)
      _summaries.clear();
  }

  @override
  Widget build(BuildContext context) {
    final en = AppLanguageScope.stringsOf(context).language == AppLanguage.en;
    for (final entry in widget.completedYears.entries) {
      _summaries.putIfAbsent(
        entry.key,
        () => LongRangeDisplaySummary._aggregate(
          mode: LongRangeDisplayMode.year,
          startYear: entry.key,
          endYear: entry.key,
          dates: widget.request.dates
              .where((d) => d.year == entry.key)
              .toList(),
          samples: {
            for (final sample in entry.value.entries)
              sample.key: sample.value.predictions,
          },
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_summaries.isNotEmpty) ...[
          SizedBox(
            height: FortuneFlowPainter.chartHeight(
              MediaQuery.textScalerOf(context),
            ),
            child: CustomPaint(
              key: const ValueKey('five-year-partial-chart'),
              painter: _LongRangePartialPainter(
                startYear: widget.request.startYear,
                summaries: Map.unmodifiable(_summaries),
                textScaler: MediaQuery.textScalerOf(context),
              ),
              child: const SizedBox.expand(),
            ),
          ),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              for (
                var i = 0;
                i < PeriodSevenGroupedTrendData.mainKeys.length;
                i++
              )
                _FlowLegend(
                  label: PeriodSevenGroupedTrendData.mainLabels[i],
                  color: PeriodSevenGroupedTrendData.mainColors[i],
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        for (
          var year = widget.request.startYear;
          year <= widget.request.endYear;
          year++
        )
          if (_summaries[year] case final summary?)
            ExpansionTile(
              key: ValueKey('five-year-ready-$year'),
              title: Text(en ? '$year · Ready' : '$year年 · 完了'),
              subtitle: Text(
                en
                    ? '24 reference samples. Open the yearly reading.'
                    : '24代表時点。開くとこの年の占いを表示します。',
              ),
              children: [
                NineAreaPeriodOverview(
                  summary: summary,
                  details: widget.details,
                  depth: widget.depth,
                  dailySamples: {
                    for (final entry in widget.completedYears[year]!.entries)
                      NineAreaPeriodSummary.dateLabel(entry.key):
                          entry.value.predictions,
                  },
                ),
              ],
            )
          else
            ListTile(
              key: ValueKey('five-year-waiting-$year'),
              title: Text(en ? '$year · Waiting' : '$year年 · 待機中'),
              subtitle: Text(
                en ? 'No score is available yet.' : '点数はまだ計算されていません。',
              ),
            ),
      ],
    );
  }
}

/// Five fixed positions; missing years have neither a score nor a line segment.
class _LongRangePartialPainter extends CustomPainter {
  const _LongRangePartialPainter({
    required this.startYear,
    required this.summaries,
    required this.textScaler,
  });
  final int startYear;
  final Map<int, LongRangeDisplaySummary> summaries;
  final TextScaler textScaler;
  @override
  void paint(Canvas canvas, Size size) {
    final left = math.max(34.0, textScaler.scale(34));
    final right = math.max(12.0, textScaler.scale(12));
    final top = math.max(12.0, textScaler.scale(12));
    final bottom = math.max(42.0, textScaler.scale(42));
    final chart = Rect.fromLTWH(
      left,
      top,
      math.max(1, size.width - left - right),
      math.max(1, size.height - top - bottom),
    );
    final label = TextPainter(
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    );
    double y(int value) =>
        chart.bottom - chart.height * ((value - 50) / 49).clamp(0.0, 1.0);
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.1)
      ..strokeWidth = 1;
    for (final value in [60, 70, 80, 90]) {
      canvas.drawLine(
        Offset(chart.left, y(value)),
        Offset(chart.right, y(value)),
        grid,
      );
      label.text = TextSpan(
        text: '$value',
        style: const TextStyle(color: Colors.white54, fontSize: 10),
      );
      label.layout();
      label.paint(canvas, Offset(2, y(value) - label.height / 2));
    }
    for (var i = 0; i < 5; i++) {
      label.text = TextSpan(
        text: '${startYear + i}',
        style: const TextStyle(color: Colors.white54, fontSize: 10),
      );
      label.layout();
      label.paint(
        canvas,
        Offset(
          chart.left + chart.width * i / 4 - label.width / 2,
          chart.bottom + 8,
        ),
      );
    }
    for (var areaIndex = 0; areaIndex < 5; areaIndex++) {
      final paint = Paint()
        ..color = PeriodSevenGroupedTrendData.mainColors[areaIndex]
        ..strokeWidth = 2.6;
      Offset? previous;
      for (var i = 0; i < 5; i++) {
        final summary = summaries[startYear + i];
        if (summary == null) {
          previous = null;
          continue;
        }
        final point = Offset(
          chart.left + chart.width * i / 4,
          y(summary.areas[areaIndex].score!),
        );
        if (previous != null) canvas.drawLine(previous, point, paint);
        canvas.drawCircle(point, 3.4, paint);
        previous = point;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LongRangePartialPainter oldDelegate) =>
      oldDelegate.startYear != startYear ||
      oldDelegate.summaries != summaries ||
      oldDelegate.textScaler != textScaler;
}

class _LongRangeDisplayReadingState extends State<LongRangeReading> {
  LongRangeDisplayMode _mode = LongRangeDisplayMode.week;
  int _weekOffset = 0, _monthOffset = 0, _yearOffset = 0, _fiveYearOffset = 0;
  bool _navigationBusy = false;
  @override
  void initState() {
    super.initState();
    HouseSystemSettings.current.addListener(_houseChanged);
  }

  void _houseChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    HouseSystemSettings.current.removeListener(_houseChanged);
    super.dispose();
  }

  Future<void> _navigate(VoidCallback action) async {
    if (_navigationBusy) return;
    setState(() => _navigationBusy = true);
    // Dispose the old worker before allowing the next period to start.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    setState(() {
      action();
      _navigationBusy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return const SizedBox.shrink();
    final en = AppLanguageScope.stringsOf(context).language == AppLanguage.en;
    final now = DateTime.now().toUtc().add(DailySevenTimepointPlan.jstOffset);
    final today = DateTime.utc(now.year, now.month, now.day);
    final week = today
        .subtract(Duration(days: today.weekday - 1))
        .add(Duration(days: 7 * _weekOffset));
    final month = DateTime.utc(now.year, now.month + _monthOffset);
    final year =
        now.year +
        (_mode == LongRangeDisplayMode.fiveYear
            ? _fiveYearOffset
            : _yearOffset);
    final title = switch (_mode) {
      LongRangeDisplayMode.week => en ? 'Weekly readings' : '週間占い',
      LongRangeDisplayMode.month => en ? 'Monthly readings' : '月間占い',
      LongRangeDisplayMode.year => en ? 'Yearly readings' : '年間占い',
      LongRangeDisplayMode.fiveYear => en ? 'Five-year readings' : '5年運',
    };
    final label = switch (_mode) {
      LongRangeDisplayMode.week =>
        '${NineAreaPeriodSummary.dateLabel(DateTime.utc(week.year, week.month, week.day, 3))} – ${NineAreaPeriodSummary.dateLabel(DateTime.utc(week.year, week.month, week.day + 6, 3))}',
      LongRangeDisplayMode.month =>
        en
            ? '${month.year}-${month.month.toString().padLeft(2, '0')}'
            : '${month.year}年${month.month}月',
      LongRangeDisplayMode.year => en ? '$year' : '$year年',
      LongRangeDisplayMode.fiveYear =>
        en ? '$year–${year + 4}' : '$year〜${year + 4}年',
    };
    void shift(int direction) => _navigate(() {
      switch (_mode) {
        case LongRangeDisplayMode.week:
          _weekOffset += direction;
        case LongRangeDisplayMode.month:
          _monthOffset += direction;
        case LongRangeDisplayMode.year:
          _yearOffset += direction;
        case LongRangeDisplayMode.fiveYear:
          _fiveYearOffset += direction * 5;
      }
    });
    return ReadingPage(
      title: title,
      subtitle: '${widget.profile.name} · $label',
      children: [
        GlassPanel(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final labels = [
                    en ? 'Week' : '週',
                    en ? 'Month' : '月',
                    en ? 'Year' : '年',
                    en ? '5 years' : '5年',
                  ];
                  if (constraints.maxWidth <
                      MediaQuery.textScalerOf(context).scale(440)) {
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (
                          var i = 0;
                          i < LongRangeDisplayMode.values.length;
                          i++
                        )
                          SizedBox(
                            width: (constraints.maxWidth - 8) / 2,
                            child: Semantics(
                              selected: _mode == LongRangeDisplayMode.values[i],
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  backgroundColor:
                                      _mode == LongRangeDisplayMode.values[i]
                                      ? const Color(0x3357D6D1)
                                      : null,
                                ),
                                onPressed: _navigationBusy
                                    ? null
                                    : () {
                                        final next =
                                            LongRangeDisplayMode.values[i];
                                        if (next == _mode) return;
                                        _navigate(() => _mode = next);
                                      },
                                child: Text(
                                  labels[i],
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  }
                  return SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<LongRangeDisplayMode>(
                      segments: [
                        ButtonSegment(
                          value: LongRangeDisplayMode.week,
                          label: Text(en ? 'Week' : '週'),
                        ),
                        ButtonSegment(
                          value: LongRangeDisplayMode.month,
                          label: Text(en ? 'Month' : '月'),
                        ),
                        ButtonSegment(
                          value: LongRangeDisplayMode.year,
                          label: Text(en ? 'Year' : '年'),
                        ),
                        ButtonSegment(
                          value: LongRangeDisplayMode.fiveYear,
                          label: Text(en ? '5 years' : '5年'),
                        ),
                      ],
                      selected: {_mode},
                      onSelectionChanged: _navigationBusy
                          ? null
                          : (values) {
                              if (values.first == _mode) return;
                              _navigate(() => _mode = values.first);
                            },
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  IconButton(
                    key: const ValueKey('long-range-previous'),
                    tooltip: _mode == LongRangeDisplayMode.fiveYear
                        ? (en ? 'Previous five years' : '前の5年')
                        : (en ? 'Previous period' : '前の期間'),
                    onPressed: _navigationBusy ? null : () => shift(-1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('long-range-next'),
                    tooltip: _mode == LongRangeDisplayMode.fiveYear
                        ? (en ? 'Next five years' : '次の5年')
                        : (en ? 'Next period' : '次の期間'),
                    onPressed: _navigationBusy ? null : () => shift(1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  TextButton(
                    key: const ValueKey('long-range-current'),
                    onPressed: _navigationBusy
                        ? null
                        : () {
                            final offset = switch (_mode) {
                              LongRangeDisplayMode.week => _weekOffset,
                              LongRangeDisplayMode.month => _monthOffset,
                              LongRangeDisplayMode.year => _yearOffset,
                              LongRangeDisplayMode.fiveYear => _fiveYearOffset,
                            };
                            if (offset == 0) return;
                            _navigate(() {
                              switch (_mode) {
                                case LongRangeDisplayMode.week:
                                  _weekOffset = 0;
                                case LongRangeDisplayMode.month:
                                  _monthOffset = 0;
                                case LongRangeDisplayMode.year:
                                  _yearOffset = 0;
                                case LongRangeDisplayMode.fiveYear:
                                  _fiveYearOffset = 0;
                              }
                            });
                          },
                    child: Text(
                      _navigationBusy
                          ? (en ? 'Changing…' : '読み替え中…')
                          : switch (_mode) {
                              LongRangeDisplayMode.week =>
                                en ? 'This week' : '今週',
                              LongRangeDisplayMode.month =>
                                en ? 'This month' : '今月',
                              LongRangeDisplayMode.year =>
                                en ? 'This year' : '今年',
                              LongRangeDisplayMode.fiveYear =>
                                en ? 'Current five years' : '現在の5年',
                            },
                    ),
                  ),
                  TextButton.icon(
                    key: const ValueKey('long-range-select-period'),
                    icon: const Icon(Icons.date_range_outlined, size: 18),
                    label: Text(en ? 'Select period' : '期間を選ぶ'),
                    onPressed: _navigationBusy
                        ? null
                        : () async {
                            final initial = _mode == LongRangeDisplayMode.week
                                ? week
                                : _mode == LongRangeDisplayMode.month
                                ? month
                                : DateTime.utc(year);
                            final selected = await showDatePicker(
                              context: context,
                              initialDate: DateTime(
                                initial.year,
                                initial.month,
                                initial.day,
                              ),
                              firstDate: DateTime(1900),
                              lastDate: DateTime(2100, 12, 31),
                              helpText: _mode == LongRangeDisplayMode.fiveYear
                                  ? (en
                                        ? 'Select the starting year'
                                        : '5年間の開始年を選択')
                                  : (en
                                        ? 'Select a reading period'
                                        : '占う期間を選択'),
                            );
                            if (selected == null || !mounted) return;
                            _navigate(() {
                              switch (_mode) {
                                case LongRangeDisplayMode.week:
                                  final civil = DateTime.utc(
                                    selected.year,
                                    selected.month,
                                    selected.day,
                                  );
                                  final start = civil.subtract(
                                    Duration(days: civil.weekday - 1),
                                  );
                                  final current = today.subtract(
                                    Duration(days: today.weekday - 1),
                                  );
                                  _weekOffset =
                                      start.difference(current).inDays ~/ 7;
                                case LongRangeDisplayMode.month:
                                  _monthOffset =
                                      (selected.year - now.year) * 12 +
                                      selected.month -
                                      now.month;
                                case LongRangeDisplayMode.year:
                                  _yearOffset = selected.year - now.year;
                                case LongRangeDisplayMode.fiveYear:
                                  _fiveYearOffset = selected.year - now.year;
                              }
                            });
                          },
                  ),
                ],
              ),
            ],
          ),
        ),
        if (!_navigationBusy)
          if (_mode == LongRangeDisplayMode.week)
            PeriodSevenPointPanel(
              mode: LongRangeMode.week,
              startDateJst: week,
              profile: widget.profile,
              details: widget.details,
              depth: widget.depth,
              startWeeklyJob: widget.startWeeklyReadingJob,
              startMonthlyJob: widget.startMonthlyReadingJob,
            )
          else
            LongRangeOverviewPanel(
              request: LongRangeDisplayRequest(
                mode: _mode,
                month: month,
                startYear: year,
                profile: widget.profile,
                houseSystem: HouseSystemSettings.current.value,
                // Approved display-only route; formal JSON/day/week stay full.
                fullContext: false,
              ),
              details: widget.details,
              depth: widget.depth,
              startJob: widget.startLongRangeDisplayJob,
            ),
      ],
    );
  }
}
