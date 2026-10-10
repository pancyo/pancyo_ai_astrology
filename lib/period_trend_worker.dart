part of 'main.dart';

/// 年内の採点と独立した、年グラフの表示窓。
const int periodTrendYearWindow = 7;

/// UI・コールバック・保存領域を持たない、押下時のグラフ入力。
class PeriodTrendRequest {
  const PeriodTrendRequest({
    required this.mode,
    required this.weekStart,
    required this.month,
    required this.year,
    required this.profile,
    required this.houseSystem,
    required this.requireHighPrecision,
  });
  final LongRangeMode mode;
  final DateTime weekStart;
  final DateTime month;
  final int year;
  final AstroProfile profile;
  final HouseSystem houseSystem;
  final bool requireHighPrecision;

  Object get identity => (
    mode,
    weekStart,
    month,
    year,
    // 詳細画面の開閉で親が同内容のprofileを作り直しても、結果を保持する。
    // 実際の入力変更は全フィールドで区別し、別人物の結果を使い回さない。
    (
      profile.name,
      profile.birthDate,
      profile.birthClock?.cacheIdentity,
      profile.birthTime,
      profile.birthPlace,
      profile.theme,
      profile.savedProfileId,
    ),
    houseSystem,
    requireHighPrecision,
  );
  List<DateTime> get dates => switch (mode) {
    LongRangeMode.week => List.generate(
      4,
      (i) => weekStart.add(Duration(days: i * 7)),
    ),
    LongRangeMode.month => List.generate(
      12,
      (i) => DateTime(month.year, i + 1, 1, 12),
    ),
    LongRangeMode.year => List.generate(
      periodTrendYearWindow,
      (i) => DateTime(year + i, 1, 1, 12),
    ),
  };
}

class PeriodTrendResult {
  PeriodTrendResult({
    required this.series,
    required this.additional,
    required this.elapsedMilliseconds,
    required this.contextMilliseconds,
    required this.contextCount,
    required this.workerName,
    this.contextTimings,
    this.yearInputKey,
    Map<int, PeriodTrendCompletedYear> completedYears = const {},
    this.computedYearCount = 0,
    this.reusedYearCount = 0,
    this.yearCacheEligible = true,
  }) : completedYears = Map.unmodifiable(completedYears);
  final List<FortuneFlowSeries> series;
  final AdditionalFortuneTrendData? additional;
  final int elapsedMilliseconds;
  final int contextMilliseconds;
  final int contextCount;
  final String? workerName;
  final Map<String, Object>? contextTimings;
  final PeriodTrendYearInputKey? yearInputKey;
  final Map<int, PeriodTrendCompletedYear> completedYears;
  final int computedYearCount;
  final int reusedYearCount;
  // 既存の返却挙動は維持し、配置fallbackを含む実行だけRAM保存から除く。
  final bool yearCacheEligible;
}

/// 年窓はkeyへ含めない。同じ人物・計算条件の完成年だけを共有する。
class PeriodTrendYearInputKey {
  PeriodTrendYearInputKey.fromRequest(
    PeriodTrendRequest request, {
    required String sourceName,
    required bool usesHighPrecision,
    Object modelContract = const (
      'period-trend-year-general-summary-v1',
      NineAreaDailyForecast.modelVersion,
      NineAreaModelContract.numericModelVersion,
      NineAreaPeriodSummary.modelVersion,
      NineAreaPeriodSummary.generalModelVersion,
      FeltForecastCandidate.modelVersion,
    ),
  }) : _identity = (
         (
           request.profile.name,
           request.profile.birthDate,
           request.profile.birthClock?.cacheIdentity,
           request.profile.birthTime,
           request.profile.birthPlace,
           request.profile.theme,
           request.profile.savedProfileId,
         ),
         request.houseSystem,
         AstrologyDataSources.current.dateFromProfile(request.profile).toUtc(),
         sourceName,
         usesHighPrecision,
         request.requireHighPrecision,
         modelContract,
       );

  final Object _identity;
  @override
  bool operator ==(Object other) =>
      other is PeriodTrendYearInputKey && _identity == other._identity;
  @override
  int get hashCode => _identity.hashCode;
}

PeriodTrendYearInputKey _periodTrendYearInputKey(PeriodTrendRequest request) =>
    PeriodTrendYearInputKey.fromRequest(
      request,
      sourceName: AstrologyDataSources.current.sourceName,
      usesHighPrecision:
          AstrologyDataSources.current.usesHighPrecisionAstroData,
    );

// 旧年点のlocal正午24時点と追加summaryのUTC24時点を両方保存する。
// TZ名だけに依存せず、各年のDSTを含む実際の瞬間を再利用時に照合する。
List<DateTime> _periodTrendYearSampleInstants(int year) => [
  for (var month = 1; month <= 12; month++)
    for (final day in const [1, 15]) DateTime(year, month, day, 12).toUtc(),
  ...NineAreaPeriodSummary.sampleDates(
    LongRangeMode.year,
    DateTime(year),
    year,
  ),
];

/// contextや出生情報を保持せず、完成した年点とimmutable summaryだけを渡す。
class PeriodTrendCompletedYear {
  PeriodTrendCompletedYear({
    required this.reference,
    required List<int> scores,
    required this.summary,
    required List<DateTime> sampleInstants,
  }) : scores = List.unmodifiable(scores),
       sampleInstants = List.unmodifiable(sampleInstants) {
    if (scores.length != 5 ||
        scores.any((p) => p < 50 || p > 99) ||
        summary.mode != LongRangeMode.year ||
        summary.areas.length != 9 ||
        summary.areas.map((p) => p.key).toSet().length != 9 ||
        List.generate(
          4,
          (i) => summary.areas[i].score != scores[i],
        ).any((v) => v) ||
        summary.areas[4].score != scores[4]) {
      throw StateError('完成年の点数・summaryが不正です。');
    }
  }
  final DateTime reference;
  final List<int> scores;
  final NineAreaPeriodSummary summary;
  final List<DateTime> sampleInstants;

  bool matches(DateTime date) {
    if (reference != date || reference.isUtc != date.isUtc) return false;
    final expected = _periodTrendYearSampleInstants(date.year);
    final summaryDates = NineAreaPeriodSummary.sampleDates(
      LongRangeMode.year,
      date,
      date.year,
    );
    return sampleInstants.length == expected.length &&
        List.generate(
          expected.length,
          (i) => sampleInstants[i].isUtc && sampleInstants[i] == expected[i],
        ).every((v) => v) &&
        summary.dates.length == summaryDates.length &&
        List.generate(
          summaryDates.length,
          (i) => summary.dates[i].isUtc && summary.dates[i] == summaryDates[i],
        ).every((v) => v);
  }
}

class PeriodTrendYearLease {
  PeriodTrendYearLease._(
    this._generation,
    this._request,
    this.inputKey,
    this._allowPublish,
    Map<int, PeriodTrendCompletedYear> seeds,
  ) : seeds = Map.unmodifiable(seeds);
  final int _generation;
  final PeriodTrendRequest _request;
  final PeriodTrendYearInputKey inputKey;
  final bool _allowPublish;
  final Map<int, PeriodTrendCompletedYear> seeds;
}

/// 呼出元isolateのRAMだけ。単一入力・最大24年、失敗途中の年は保存しない。
class PeriodTrendYearCache {
  PeriodTrendYearCache({this.maxYears = 24}) {
    if (maxYears < 10 || maxYears > 30) {
      throw RangeError.range(maxYears, 10, 30, 'maxYears');
    }
  }
  final int maxYears;
  final _years = <int, PeriodTrendCompletedYear>{};
  PeriodTrendYearInputKey? _inputKey;
  int _generation = 0;
  int get retainedYearCount => _years.length;

  PeriodTrendYearLease begin(
    PeriodTrendRequest request, {
    PeriodTrendYearInputKey? inputKey,
    bool reuseCompletedYears = true,
  }) {
    final key = inputKey ?? _periodTrendYearInputKey(request);
    if (_inputKey != key) {
      _years.clear();
      _inputKey = key;
    }
    final seeds = <int, PeriodTrendCompletedYear>{};
    if (request.mode == LongRangeMode.year && reuseCompletedYears) {
      for (final date in request.dates) {
        final existing = _years[date.year];
        if (existing != null && existing.matches(date)) {
          seeds[date.year] = existing;
        }
      }
    }
    return PeriodTrendYearLease._(
      ++_generation,
      request,
      key,
      reuseCompletedYears,
      seeds,
    );
  }

  bool publish(
    PeriodTrendYearLease lease,
    Map<int, PeriodTrendCompletedYear> completedYears,
  ) {
    if (lease._generation != _generation ||
        lease.inputKey != _inputKey ||
        !lease._allowPublish ||
        lease._request.mode != LongRangeMode.year) {
      return false;
    }
    final dates = lease._request.dates;
    if (completedYears.length != dates.length ||
        dates.any((date) => completedYears[date.year]?.matches(date) != true)) {
      throw StateError('${dates.length}年窓が完成していないため保存できません。');
    }
    // 成功した窓を末尾へ移し、最も古い完成年から上限だけ落とす。
    for (final date in dates) {
      _years.remove(date.year);
      _years[date.year] = completedYears[date.year]!;
    }
    while (_years.length > maxYears) {
      _years.remove(_years.keys.first);
    }
    return true;
  }

  void cancel(PeriodTrendYearLease lease) {
    if (lease._generation == _generation) ++_generation;
  }
}

class PeriodTrendCancelled implements Exception {
  const PeriodTrendCancelled();
}

/// 離脱／中止でワーカーも終了する。古い結果の破棄だけでCPUを残さない。
class PeriodTrendJob {
  static final _completedYearCache = PeriodTrendYearCache();
  PeriodTrendJob.start(
    PeriodTrendRequest request, {
    void Function(int completed, int total)? onProgress,
    // 独立QAは従来どおり全点を計算できる。request identityは変えない。
    bool reuseCompletedYears = true,
  }) : _lease = _completedYearCache.begin(
         request,
         reuseCompletedYears: reuseCompletedYears,
       ) {
    _port.listen((message) {
      if (_finished) return;
      if (message is PeriodTrendResult) {
        try {
          if (message.yearInputKey != _lease.inputKey) {
            throw StateError('年計算の入力条件が変わりました。');
          }
          if (message.yearCacheEligible &&
              HouseSystemSettings.current.value == request.houseSystem &&
              _periodTrendYearInputKey(request) == _lease.inputKey) {
            _completedYearCache.publish(_lease, message.completedYears);
          }
        } catch (_) {
          _completedYearCache.cancel(_lease);
          _finish();
          _result.completeError(StateError('期間グラフを計算できませんでした。'));
          return;
        }
        _finish();
        _result.complete(message);
      } else if (message is List &&
          message.length == 3 &&
          message.first == 'progress') {
        onProgress?.call(message[1] as int, message[2] as int);
      } else {
        _completedYearCache.cancel(_lease);
        _finish();
        // 生の例外・出生情報を画面／ログへ流さない。
        _result.completeError(StateError('期間グラフを計算できませんでした。'));
      }
    });
    unawaited(_spawn(request));
  }
  final _port = ReceivePort();
  final PeriodTrendYearLease _lease;
  final _result = Completer<PeriodTrendResult>();
  Isolate? _isolate;
  bool _finished = false;
  Future<PeriodTrendResult> get result => _result.future;

  Future<void> _spawn(PeriodTrendRequest request) async {
    try {
      final worker = await Isolate.spawn(
        _periodTrendWorker,
        (request, _port.sendPort, _lease.inputKey, _lease.seeds),
        debugName: 'pancyo-period-trend',
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
        _completedYearCache.cancel(_lease);
        _finish();
        _result.completeError(StateError('期間グラフを開始できませんでした。'));
      }
    }
  }

  void _finish() {
    _finished = true;
    _port.close();
    _isolate?.kill(priority: Isolate.immediate);
  }

  void cancel() {
    if (_finished) return;
    _completedYearCache.cancel(_lease);
    _finish();
    _result.completeError(const PeriodTrendCancelled());
  }
}

void _periodTrendWorker(
  (
    PeriodTrendRequest,
    SendPort,
    PeriodTrendYearInputKey,
    Map<int, PeriodTrendCompletedYear>,
  )
  input,
) {
  try {
    final result = _calculatePeriodTrend(
      input.$1,
      inputKey: input.$3,
      completedYearSeeds: input.$4,
      onProgress: (completed, total) =>
          input.$2.send(['progress', completed, total]),
    );
    Isolate.exit(input.$2, result);
  } catch (_) {
    input.$2.send('failed');
  }
}

PeriodTrendResult _calculatePeriodTrend(
  PeriodTrendRequest request, {
  required void Function(int, int) onProgress,
  required PeriodTrendYearInputKey inputKey,
  required Map<int, PeriodTrendCompletedYear> completedYearSeeds,
}) {
  final watch = Stopwatch()..start();
  final placementFallbacksBefore =
      SwissEphemerisProvider._placementFallbackCount;
  HouseSystemSettings.current.value = request.houseSystem;
  if (_periodTrendYearInputKey(request) != inputKey) {
    throw StateError('workerの計算条件が要求と違います。');
  }
  if (request.requireHighPrecision &&
      !AstrologyDataSources.current.usesHighPrecisionAstroData) {
    throw StateError('高精度のグラフ計算を利用できません。');
  }
  final contexts = <DateTime, HoroscopeReadingContext>{};
  final contextWatch = Stopwatch();
  // 配布版は集計もログも無効。改修テスト版の一回のworker内だけで計測。
  final contextTiming = reworkTestBuild ? AstrologyContextTiming() : null;
  HoroscopeReadingContext contextFor(DateTime date) =>
      contexts.putIfAbsent(date.toUtc(), () {
        contextWatch.start();
        try {
          return const AstrologyEngine().buildPreviewContext(
            profile: request.profile,
            date: date,
            timing: contextTiming,
          );
        } finally {
          contextWatch.stop();
        }
      });
  final dates = request.dates;
  final scores = <List<int>>[];
  final summaries = <DateTime, NineAreaPeriodSummary>{};
  final completedYears = <int, PeriodTrendCompletedYear>{};
  var computedYearCount = 0;
  var reusedYearCount = 0;
  for (final date in dates) {
    final seed = request.mode == LongRangeMode.year
        ? completedYearSeeds[date.year]
        : null;
    if (seed != null && seed.matches(date)) {
      scores.add(seed.scores);
      summaries[date] = seed.summary;
      completedYears[date.year] = seed;
      reusedYearCount++;
      onProgress(scores.length, dates.length);
      continue;
    }
    // 週は日モデルの固定UTC7時点だけを集計し、使わない旧週点を計算しない。
    // 月・年は既存の旧期間点を出典用に保ち、従来と同じsummaryを作る。
    final legacyScores = request.mode == LongRangeMode.week
        ? const <int>[]
        : PeriodConsultDataBuilder(
            mode: request.mode,
            periodLabel: '',
            weekStart: date,
            month: date,
            year: date.year,
            profile: request.profile,
            details: const UserProfileDetails.empty(),
            contextData: contextFor(date),
            cards: const [],
            contextResolver: contextFor,
          ).graphScores().map((p) => p['score'] as int).toList();
    final summary = NineAreaPeriodSummary.build(
      mode: request.mode,
      month: date,
      year: date.year,
      weekStart: request.mode == LongRangeMode.week ? date : null,
      useGeneralModel: true,
      legacyScores: request.mode == LongRangeMode.week
          ? const {}
          : {
              for (var i = 0; i < 4; i++)
                NineAreaKey.values[i]: legacyScores[i],
            },
      dailyFor: (sample) =>
          NineAreaDailyForecast.fromContext(contextFor(sample)),
    );
    summaries[date] = summary;
    final points = [for (var i = 0; i < 5; i++) summary.areas[i].score!];
    scores.add(points);
    if (request.mode == LongRangeMode.year) {
      completedYears[date.year] = PeriodTrendCompletedYear(
        reference: date,
        scores: points,
        summary: summaries[date]!,
        sampleInstants: _periodTrendYearSampleInstants(date.year),
      );
      computedYearCount++;
    }
    onProgress(scores.length, dates.length);
  }
  const labels = ['総合', '恋愛', '仕事', '金運', 'メンタル'];
  const colors = [
    Color(0xFFF6D77A),
    Color(0xFFFF82B2),
    Color(0xFF57D6D1),
    Color(0xFF9BE06D),
    Color(0xFFB58CFF),
  ];
  return PeriodTrendResult(
    series: List.unmodifiable([
      for (var i = 0; i < 5; i++)
        FortuneFlowSeries(
          label: labels[i],
          color: colors[i],
          values: List.unmodifiable(scores.map((p) => p[i])),
        ),
    ]),
    additional: AdditionalFortuneTrendData.period(
      mode: request.mode,
      dates: dates,
      summaryFor: (date) => summaries[date]!,
    ),
    elapsedMilliseconds: watch.elapsedMilliseconds,
    contextMilliseconds: contextWatch.elapsedMilliseconds,
    contextCount: contexts.length,
    workerName: Isolate.current.debugName,
    contextTimings: contextTiming?.safeSnapshot,
    yearInputKey: inputKey,
    completedYears: completedYears,
    computedYearCount: computedYearCount,
    reusedYearCount: reusedYearCount,
    yearCacheEligible:
        SwissEphemerisProvider._placementFallbackCount ==
        placementFallbacksBefore,
  );
}
