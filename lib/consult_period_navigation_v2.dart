part of 'main.dart';

enum ConsultPeriodNavigationV2Range {
  thisWeek,
  nextWeek,
  thisMonth,
  nextMonth,
  threeMonths,
  thisYear,
  fiveYears,
  compareMonths,
}

enum ConsultPeriodNavigationV2Status {
  answered,
  clarificationRequired,
  cancelled,
  unavailable,
  notHandled,
}

class ConsultPeriodNavigationV2Request {
  const ConsultPeriodNavigationV2Request({
    required this.question,
    required this.todayJst,
    required this.profile,
    required this.houseSystem,
    required this.language,
    this.explicitRange,
    this.explicitTopic,
    this.previous,
    this.supplement,
  });
  final String question;

  /// JST civil fields; never interpreted as a device-zone instant.
  final DateTime todayJst;
  final AstroProfile profile;
  final HouseSystem houseSystem;
  final AppLanguage language;
  final ConsultPeriodNavigationV2Range? explicitRange;
  final NineAreaKey? explicitTopic;
  final ConsultPeriodNavigationV2Context? previous;
  final UserProfileDetails? supplement;

  String get _identity => sha256
      .convert(
        utf8.encode(
          jsonEncode([
            [
              profile.name,
              profile.birthDate,
              profile.birthTime,
              profile.birthPlace,
              profile.birthClock?.cacheIdentity,
              profile.theme,
              profile.savedProfileId,
            ],
            houseSystem.name,
            AstrologyDataSources.current.sourceName,
            AstrologyDataSources.current.usesHighPrecisionAstroData,
            SwissEphemerisProvider._forceScalarVoidForCheck,
            NineAreaDailyForecast.modelVersion,
            NineAreaPeriodSummary.generalModelVersion,
            if (supplement?.useSupplement == true)
              [
                supplement!.personality,
                supplement!.concerns,
                supplement!.readingStyle,
              ],
          ]),
        ),
      )
      .toString();
}

/// In-memory only. No conversation storage, JSON persistence, or profile writes.
class ConsultPeriodNavigationV2Context {
  const ConsultPeriodNavigationV2Context._({
    required this.range,
    required this.topic,
    required this.periods,
    required String identity,
  }) : _identity = identity;
  final ConsultPeriodNavigationV2Range range;
  // A navigation-only week/month context needs no selected topic or samples.
  final NineAreaKey? topic;
  final List<ConsultPeriodNavigationV2Period> periods;
  final String _identity;
}

class ConsultPeriodNavigationV2Period {
  ConsultPeriodNavigationV2Period._(
    this.label,
    this.summary,
    Map<String, List<NineAreaPrediction>> samples,
  ) : dailySamples = Map.unmodifiable({
        for (final e in samples.entries)
          e.key: List<NineAreaPrediction>.unmodifiable(e.value),
      });
  final String label;
  final NineAreaPeriodSummary summary;
  final Map<String, List<NineAreaPrediction>> dailySamples;
}

class ConsultPeriodNavigationV2Result {
  const ConsultPeriodNavigationV2Result({
    required this.status,
    required this.text,
    required this.mode,
    this.nextContext,
    this.periods = const [],
    this.explanations = const [],
    this.reasonCode,
  });
  final ConsultPeriodNavigationV2Status status;
  final String text;
  final ConsultNavigationV2Mode mode;
  final ConsultPeriodNavigationV2Context? nextContext;
  final List<ConsultPeriodNavigationV2Period> periods;
  final List<ForecastExplanationResult> explanations;
  final String? reasonCode;
}

class ConsultPeriodNavigationV2 {
  const ConsultPeriodNavigationV2._();
  static bool recognizesPeriod(String question) {
    final q = question.toLowerCase();
    return _ranges(q).isNotEmpty ||
        RegExp(
          r'\d+\s*(か月|ヶ月|カ月|週間|週|年|months?\b|years?\b|weeks?\b)|来年|先月|next year|last month',
        ).hasMatch(q);
  }

  static bool _dayQuestion(String q) => RegExp(
    r'今日|明日|あした|あさって|明後日|昨日|today|tomorrow|yesterday|\d{1,2}[月/]\d{1,2}日?|\d{4}-\d{2}-\d{2}',
  ).hasMatch(q);

  static Set<ConsultPeriodNavigationV2Range> _ranges(String q) {
    final result = <ConsultPeriodNavigationV2Range>{};
    bool has(List<String> values) => values.any(q.contains);
    final thisMonth = has(['今月', 'this month']);
    final nextMonth = has(['来月', 'next month']);
    if (thisMonth && nextMonth)
      result.add(ConsultPeriodNavigationV2Range.compareMonths);
    else if (thisMonth)
      result.add(ConsultPeriodNavigationV2Range.thisMonth);
    else if (nextMonth)
      result.add(ConsultPeriodNavigationV2Range.nextMonth);
    if (has(['今週', 'this week']))
      result.add(ConsultPeriodNavigationV2Range.thisWeek);
    if (has(['来週', 'next week']))
      result.add(ConsultPeriodNavigationV2Range.nextWeek);
    if (has(['three months']) ||
        RegExp(r'(^|[^0-9])3\s*(か月|ヶ月|カ月|months?\b)').hasMatch(q))
      result.add(ConsultPeriodNavigationV2Range.threeMonths);
    if (has(['five years']) ||
        RegExp(r'(^|[^0-9])5\s*(年|years?\b)').hasMatch(q))
      result.add(ConsultPeriodNavigationV2Range.fiveYears);
    if (has(['今年', 'this year', 'one year']) ||
        RegExp(r'(^|[^0-9])1\s*(年|year\b)').hasMatch(q))
      result.add(ConsultPeriodNavigationV2Range.thisYear);
    if (RegExp(r'(^|[^0-9])1\s*(か月|ヶ月|カ月|month\b)').hasMatch(q) ||
        has(['one month']))
      result.add(ConsultPeriodNavigationV2Range.thisMonth);
    if (RegExp(r'(^|[^0-9])1\s*(週間|week\b)').hasMatch(q) || has(['one week']))
      result.add(ConsultPeriodNavigationV2Range.thisWeek);
    return result;
  }

  static bool _unsupportedNumericPeriod(String q) {
    for (final m in RegExp(
      r'(\d+)\s*(か月|ヶ月|カ月|週間|週|年|months?\b|years?\b|weeks?\b)',
    ).allMatches(q)) {
      final n = int.parse(m[1]!);
      final unit = m[2]!;
      final allowed = unit == '年' || unit.startsWith('year')
          ? n == 1 || n == 5
          : unit == '週' || unit == '週間' || unit.startsWith('week')
          ? n == 1
          : n == 1 || n == 3;
      if (!allowed) return true;
    }
    return false;
  }
}

/// One controller per owning UI State. A new turn cancels its previous job;
/// periods run sequentially and no synchronous/native fallback is attempted.
/// The owner must also prevent concurrent graph/export jobs and cancel on exit.
class ConsultPeriodNavigationV2Controller {
  ConsultPeriodNavigationV2Controller({PeriodReadingContextStarter? starter})
    : _starter =
          starter ??
          ((r, p) => PeriodReadingContextJob.start(r, onProgress: p));
  final PeriodReadingContextStarter _starter;
  PeriodReadingContextOperation? _operation;
  Completer<void>? _cancelSignal;
  int _generation = 0;
  bool _disposed = false, _busy = false;
  bool get isBusy => _busy;

  void cancel() {
    _generation++;
    _operation?.cancel();
    _operation = null;
    final signal = _cancelSignal;
    if (signal != null && !signal.isCompleted) signal.complete();
    _cancelSignal = null;
    _busy = false;
  }

  void dispose() {
    cancel();
    _disposed = true;
  }

  Future<ConsultPeriodNavigationV2Result> respond(
    ConsultPeriodNavigationV2Request request, {
    void Function(int completed, int total)? onProgress,
  }) async {
    cancel();
    final generation = _generation;
    final q = request.question.trim().toLowerCase();
    final mode = ConsultNavigationV2._modeFor(q);
    String pick(String ja, String en) =>
        request.language == AppLanguage.en ? en : ja;
    ConsultPeriodNavigationV2Result stop(
      ConsultPeriodNavigationV2Status status,
      String code,
      String ja,
      String en,
    ) => ConsultPeriodNavigationV2Result(
      status: status,
      text: pick(ja, en),
      mode: mode,
      reasonCode: code,
    );
    if (_disposed)
      return stop(
        ConsultPeriodNavigationV2Status.cancelled,
        'disposed',
        '中止しました。',
        'Cancelled.',
      );
    if (ConsultPeriodNavigationV2._dayQuestion(q)) {
      if (ConsultPeriodNavigationV2.recognizesPeriod(q) ||
          request.explicitRange != null) {
        return stop(
          ConsultPeriodNavigationV2Status.clarificationRequired,
          'mixed_day_and_period',
          '一日と期間の指定が混在しています。対象を一つ選んでください。',
          'A day and a period are both specified. Choose one target.',
        );
      }
      return stop(
        ConsultPeriodNavigationV2Status.notHandled,
        'daily_question',
        '日付の鑑定へ切り替えます。',
        'Switch to the daily reading.',
      );
    }
    final ranges = ConsultPeriodNavigationV2._ranges(q);
    if (ConsultPeriodNavigationV2._unsupportedNumericPeriod(q) ||
        ranges.isEmpty && ConsultPeriodNavigationV2.recognizesPeriod(q)) {
      return stop(
        ConsultPeriodNavigationV2Status.clarificationRequired,
        'unsupported_period',
        'その期間にはまだ対応していません。対応する暦期間を指定してください。',
        'That period is not supported. Choose a supported calendar period.',
      );
    }
    if (request.explicitRange != null) ranges.add(request.explicitRange!);
    if (ranges.length > 1)
      return stop(
        ConsultPeriodNavigationV2Status.clarificationRequired,
        'multiple_periods',
        '対象期間を一つ指定してください。今月と来月の比較は選べます。',
        'Choose one period. Comparing this month with next month is supported.',
      );
    final topics = ConsultNavigationV2._topicsIn(q);
    if (request.explicitTopic != null) topics.add(request.explicitTopic!);
    if (topics.length > 1)
      return stop(
        ConsultPeriodNavigationV2Status.clarificationRequired,
        'multiple_topics',
        '恋愛・仕事など、話題を一つ指定してください。',
        'Choose one topic, such as love or work.',
      );
    final previous = request.previous;
    final followUp =
        ranges.isEmpty &&
        previous != null &&
        (mode != ConsultNavigationV2Mode.standard || topics.isNotEmpty);
    final range = ranges.singleOrNull ?? (followUp ? previous.range : null);
    final topic = topics.singleOrNull ?? (followUp ? previous.topic : null);
    // Redirect before checking or reading a cached period. A pre-migration
    // week/month context may contain noon/representative-day summaries.
    if (range != null && _usesSevenPointScreen(range)) {
      return _sevenPointNavigation(request, range, topic, mode);
    }
    if (previous != null &&
        followUp &&
        previous._identity != request._identity) {
      return stop(
        ConsultPeriodNavigationV2Status.clarificationRequired,
        'changed_input',
        '人物・計算条件・補足が変わりました。期間と話題を指定して計算し直してください。',
        'The person, calculation settings or background changed. Choose the period and topic again.',
      );
    }
    if (range == null || topic == null)
      return stop(
        ConsultPeriodNavigationV2Status.clarificationRequired,
        range == null ? 'missing_or_unsupported_period' : 'missing_topic',
        '対象期間と話題を指定してください。対応期間は今週・来週・今月・来月・3暦月・今年・5暦年・今月と来月の比較です。',
        'Choose a period and topic: this/next week, this/next month, three calendar months, this year, five calendar years, or this month versus next month.',
      );
    final identity = request._identity;
    if (followUp) {
      return _answer(request, range, topic, previous.periods, mode, identity);
    }
    final plan = _plan(request, range);
    final total = plan.fold(0, (int sum, r) => sum + r.dates.length);
    var completed = 0;
    final periods = <ConsultPeriodNavigationV2Period>[];
    final signal = Completer<void>();
    _cancelSignal = signal;
    _busy = true;
    try {
      for (final r in plan) {
        if (generation != _generation ||
            _disposed ||
            request._identity != identity)
          throw const PeriodReadingContextCancelled();
        final op = _starter(r, (done, count) {
          if (generation == _generation && !_disposed)
            onProgress?.call(completed + done, total);
        });
        _operation = op;
        final result = await Future.any<PeriodReadingContextResult>([
          op.result,
          signal.future.then<PeriodReadingContextResult>(
            (_) => throw const PeriodReadingContextCancelled(),
          ),
        ]);
        if (generation != _generation || _disposed)
          throw const PeriodReadingContextCancelled();
        if (request._identity != identity || !result.matches(r))
          throw StateError('Period request conditions differ.');
        _operation = null;
        final samples = <String, List<NineAreaPrediction>>{};
        final dates = NineAreaPeriodSummary.sampleDates(
          r.mode,
          r.month,
          r.year,
          weekStart: r.mode == LongRangeMode.week ? r.weekStart : null,
        );
        for (final date in dates) {
          final context = result.contexts[date.toUtc()];
          if (context == null) throw StateError('Missing worker sample.');
          samples[NineAreaPeriodSummary.dateLabel(date)] = List.unmodifiable(
            NineAreaDailyForecast.fromContext(context),
          );
        }
        final summary = NineAreaPeriodSummary.build(
          mode: r.mode,
          month: r.month,
          year: r.year,
          weekStart: r.mode == LongRangeMode.week ? r.weekStart : null,
          // Compatibility values are unused with useGeneralModel:true.
          legacyScores: r.mode == LongRangeMode.week
              ? const {}
              : {
                  for (final key in NineAreaKey.values.take(4))
                    key:
                        samples.values.first
                            .singleWhere((p) => p.key == key)
                            .score ??
                        (throw StateError(
                          'Required numeric forecast unavailable.',
                        )),
                },
          dailyFor: (date) => samples[NineAreaPeriodSummary.dateLabel(date)]!,
          useGeneralModel: true,
        );
        final label = r.mode == LongRangeMode.year
            ? '${r.year}'
            : r.mode == LongRangeMode.month
            ? '${r.month.year}-${r.month.month.toString().padLeft(2, '0')}'
            : '${NineAreaPeriodSummary.dateLabel(dates.first)}–${NineAreaPeriodSummary.dateLabel(dates.last)} JST';
        periods.add(ConsultPeriodNavigationV2Period._(label, summary, samples));
        completed += r.dates.length;
        onProgress?.call(completed, total);
      }
      if (generation != _generation ||
          _disposed ||
          request._identity != identity)
        throw const PeriodReadingContextCancelled();
      return _answer(
        request,
        range,
        topic,
        List.unmodifiable(periods),
        mode,
        identity,
      );
    } on PeriodReadingContextCancelled {
      return stop(
        ConsultPeriodNavigationV2Status.cancelled,
        'cancelled',
        '中止しました。古い計算結果は表示しません。',
        'Cancelled. Stale results are not displayed.',
      );
    } catch (_) {
      if (generation != _generation || _disposed) {
        return stop(
          ConsultPeriodNavigationV2Status.cancelled,
          'cancelled',
          '中止しました。古い計算結果は表示しません。',
          'Cancelled. Stale results are not displayed.',
        );
      }
      return stop(
        ConsultPeriodNavigationV2Status.unavailable,
        'worker_or_forecast_unavailable',
        '期間の計算を完了できませんでした。再試行できます。同期計算で穴埋めしません。',
        'The period calculation could not finish. You can retry. No synchronous fallback is used.',
      );
    } finally {
      if (generation == _generation) {
        _operation = null;
        _cancelSignal = null;
        _busy = false;
      }
    }
  }

  static bool _usesSevenPointScreen(ConsultPeriodNavigationV2Range range) =>
      range != ConsultPeriodNavigationV2Range.thisYear &&
      range != ConsultPeriodNavigationV2Range.fiveYears;

  static ConsultPeriodNavigationV2Result _sevenPointNavigation(
    ConsultPeriodNavigationV2Request request,
    ConsultPeriodNavigationV2Range range,
    NineAreaKey? topic,
    ConsultNavigationV2Mode mode,
  ) {
    final english = request.language == AppLanguage.en;
    final week =
        range == ConsultPeriodNavigationV2Range.thisWeek ||
        range == ConsultPeriodNavigationV2Range.nextWeek;
    final today = DateTime.utc(
      request.todayJst.year,
      request.todayJst.month,
      request.todayJst.day,
    );
    String date(DateTime value) =>
        '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
    String month(DateTime value) =>
        '${value.year}-${value.month.toString().padLeft(2, '0')}';
    late final String target;
    if (week) {
      final start = today
          .subtract(Duration(days: today.weekday - DateTime.monday))
          .add(
            Duration(
              days: range == ConsultPeriodNavigationV2Range.nextWeek ? 7 : 0,
            ),
          );
      target = '${date(start)}–${date(start.add(const Duration(days: 6)))}';
    } else {
      final firstOffset = range == ConsultPeriodNavigationV2Range.nextMonth
          ? 1
          : 0;
      final count = range == ConsultPeriodNavigationV2Range.threeMonths
          ? 3
          : range == ConsultPeriodNavigationV2Range.compareMonths
          ? 2
          : 1;
      target = [
        for (var index = 0; index < count; index++)
          month(DateTime.utc(today.year, today.month + firstOffset + index)),
      ].join(english ? ', ' : '・');
    }
    final title = week
        ? (english ? 'Weekly 7-point readings' : '週間7点式')
        : (english ? 'Monthly readings' : '月間占い');
    final screenBasis = week
        ? (english
              ? 'The week screen uses seven calculated times for each of seven days. Its graph shows seven daily means, and the nine categories summarize the complete week. '
              : '週画面は1日7時点×7日を使い、グラフは各日の7点平均、9項目は週全体の集計を表示します。')
        : (english
              ? 'The month screen uses five reference dates at noon JST: the 1st, 8th, 15th, 22nd and last day. It shows four intervals; the final interval averages the 22nd and last day. The nine categories summarize all five samples. '
              : '月画面は1・8・15・22・末日の正午JSTを代表5日として、4区間のグラフを表示します。最後の区間は22日と末日の平均で、9項目は代表5日全体から集計します。');
    final text = english
        ? '$title: $target (JST).\n\n'
              'Open “Week, month & year”, select “${week ? 'Week' : 'Month'}”, '
              'and choose ${week ? 'the target week' : 'each target month'} to read the category readings. '
              '$screenBasis\n\n'
              'To create the formal JSON, open “Profile” and select '
              '${week ? 'the target week’s starting date' : 'each target month'} there. '
              'Use “${week ? 'Create weekly daily data (7 days, 49 points)' : 'Create monthly 7-point JSON'}”. '
              '${week ? '' : 'The formal monthly JSON retains seven points for every day of the complete month, separately from the five reference dates on screen. '}'
              'Each day includes '
              '00:00 / 04:00 / 08:00 / 12:00 / 16:00 / 20:00 / 24:00 JST. '
              '24:00 is 00:00 on the following day.\n\n'
              'This reply provides navigation only; it has not calculated a score '
              'or compared the periods.'
        : '$title：$target（JST）。\n\n'
              '「週月年占い」の「${week ? '週' : '月'}」を開き、'
              '${week ? '対象の週' : '対象の月を一つずつ'}を選ぶと項目ごとの占いを読めます。'
              '$screenBasis\n\n'
              '正式なJSONの出力は「プロフィール」から行います。'
              '${week ? '対象週の開始日' : '対象の月を一つずつ'}を指定し、'
              '「${week ? '日データの週版を作る（7日・49時点）' : '月間7点式JSONを作る'}」を押してください。'
              '${week ? '' : '正式な月JSONは画面の代表5日とは別に、従来どおり対象月の全日・各日7点を保持します。'}'
              '各日は00・04・08・12・16・20・24時（JST）の7点です。'
              '24時は翌日00時です。\n\n'
              'この応答は画面への案内です。点数の計算や期間の比較は行っていません。';
    return ConsultPeriodNavigationV2Result(
      status: ConsultPeriodNavigationV2Status.answered,
      text: text,
      mode: mode,
      reasonCode: 'canonical_seven_point_navigation',
      // Replace any cached legacy samples in the owning conversation, while
      // allowing “why?” and “more details” to return to this same guidance.
      nextContext: ConsultPeriodNavigationV2Context._(
        range: range,
        topic: topic,
        periods: const [],
        identity: request._identity,
      ),
    );
  }

  static List<PeriodReadingContextRequest> _plan(
    ConsultPeriodNavigationV2Request r,
    ConsultPeriodNavigationV2Range range,
  ) {
    final today = DateTime.utc(
      r.todayJst.year,
      r.todayJst.month,
      r.todayJst.day,
    );
    PeriodReadingContextRequest one(LongRangeMode mode, DateTime start) =>
        PeriodReadingContextRequest(
          mode: mode,
          weekStart: DateTime(start.year, start.month, start.day),
          month: DateTime(start.year, start.month),
          year: start.year,
          profile: r.profile,
          houseSystem: r.houseSystem,
        );
    return List.unmodifiable(switch (range) {
      ConsultPeriodNavigationV2Range.thisWeek ||
      ConsultPeriodNavigationV2Range.nextWeek ||
      ConsultPeriodNavigationV2Range.thisMonth ||
      ConsultPeriodNavigationV2Range.nextMonth ||
      ConsultPeriodNavigationV2Range.threeMonths ||
      ConsultPeriodNavigationV2Range.compareMonths => throw StateError(
        'Week/month readings use the formal seven-point screen.',
      ),
      ConsultPeriodNavigationV2Range.thisYear => [
        one(LongRangeMode.year, DateTime.utc(today.year)),
      ],
      ConsultPeriodNavigationV2Range.fiveYears => [
        for (var i = 0; i < 5; i++)
          one(LongRangeMode.year, DateTime.utc(today.year + i)),
      ],
    });
  }

  static ConsultPeriodNavigationV2Result _answer(
    ConsultPeriodNavigationV2Request request,
    ConsultPeriodNavigationV2Range range,
    NineAreaKey topic,
    List<ConsultPeriodNavigationV2Period> periods,
    ConsultNavigationV2Mode mode,
    String identity,
  ) {
    if (_usesSevenPointScreen(range)) {
      return _sevenPointNavigation(request, range, topic, mode);
    }
    final strings = AppStrings(request.language);
    final en = request.language == AppLanguage.en;
    final explanations = [
      for (final p in periods)
        ForecastExplanation.forPeriod(
          summary: p.summary,
          area: p.summary.areas.singleWhere((a) => a.key == topic),
          strings: strings,
          depth: mode == ConsultNavigationV2Mode.standard
              ? ReadingDepth.simple
              : ReadingDepth.detailed,
          supplement: request.supplement,
          dailySamples: p.dailySamples,
        ),
    ];
    final scope = switch (range) {
      ConsultPeriodNavigationV2Range.thisYear ||
      ConsultPeriodNavigationV2Range.fiveYears =>
        en
            ? '${periods.length} calendar year(s), January through December, with 24 reference samples per year. This is not a rolling full-year window from today.'
            : '${periods.length}暦年（1月から12月）。各年の代表24時点です。今日からちょうど1年・5年の窓ではありません。',
      _ => throw StateError(
        'Only annual summaries are available in consultation.',
      ),
    };
    final body = <String>[
      scope,
      for (var i = 0; i < periods.length; i++)
        '${periods[i].label}\n${_periodAnswerText(periods[i], explanations[i], strings)}',
    ];
    body.add(
      en
          ? 'Experimental and unvalidated. No cross-period average, new coefficient, or diary adjustment is added.'
          : '試作・未検証。複数期間を一つに平均せず、新係数や日記補正を追加しません。',
    );
    return ConsultPeriodNavigationV2Result(
      status: ConsultPeriodNavigationV2Status.answered,
      text: body.join('\n\n'),
      mode: mode,
      periods: List.unmodifiable(periods),
      explanations: List.unmodifiable(explanations),
      nextContext: ConsultPeriodNavigationV2Context._(
        range: range,
        topic: topic,
        periods: List.unmodifiable(periods),
        identity: identity,
      ),
    );
  }

  // Navigation needs a reason even in its first, concise answer. The common
  // card's short text intentionally omits trace details; retain its structured
  // conclusion/materials/advice here without calculating another forecast.
  static String _periodAnswerText(
    ConsultPeriodNavigationV2Period period,
    ForecastExplanationResult explanation,
    AppStrings strings,
  ) {
    final en = strings.language == AppLanguage.en;
    final detailed = explanation.depth == ReadingDepth.detailed;
    String pick(String ja, String english) => en ? english : ja;
    final area = period.summary.areas.singleWhere(
      (area) => area.key == explanation.key,
    );
    final lines = <String>[
      explanation.title,
      '${pick('結論', 'Conclusion')}: '
          '${explanation.score == null ? '' : '${explanation.score}${pick('点。', ' points. ')}'}'
          '${explanation.conclusion}',
      '${pick('理由', 'Why')}: ${explanation.basis}',
    ];
    if (area.key != NineAreaKey.felt &&
        area.samples.isNotEmpty &&
        area.samples.length == period.summary.dates.length &&
        !area.inherited) {
      // Descriptive extrema of the existing sample values, never a new score,
      // interpolation, probability, or claim to have searched every day.
      final low = area.samples.reduce(math.min);
      final high = area.samples.reduce(math.max);
      String datesFor(int score) {
        final dates = [
          for (var i = 0; i < area.samples.length; i++)
            if (area.samples[i] == score)
              NineAreaPeriodSummary.dateLabel(period.summary.dates[i]),
        ];
        return '${dates.take(2).join(', ')}'
            '${dates.length > 2 ? pick(' ほか${dates.length - 2}時点', ' +${dates.length - 2} more samples') : ''}';
      }

      lines.add(
        pick(
          '確認時点の比較: 最低 $low点 (${datesFor(low)})、最高 $high点 (${datesFor(high)})。確認時点の計算値であり、実績や全日を調べた最良日ではありません。',
          'Sample comparison: lowest $low (${datesFor(low)}); highest $high (${datesFor(high)}). These are sampled model values, not observed outcomes or the best days from an all-day search.',
        ),
      );
    }

    final exampleLimit = detailed ? 4 : 2;
    void materials(String ja, String english, List<String> rows) {
      final examples = rows.take(exampleLimit).toList();
      lines.add(
        '${pick(ja, english)}: '
        '${examples.isEmpty ? pick('確認できる選択済み材料は未提供', 'No verified selected material supplied') : examples.join(' / ')}'
        '${rows.length > examples.length ? pick('（ほか${rows.length - examples.length}件。確認日ごとの材料の例示です）', ' (${rows.length - examples.length} further entries; examples of selected sample factors)') : ''}',
      );
    }

    materials(
      '正の材料（例）',
      'Support materials (examples)',
      explanation.positiveMaterials,
    );
    materials(
      '負の材料（例）',
      'Tension materials (examples)',
      explanation.negativeMaterials,
    );
    if (area.key == NineAreaKey.actionDecision ||
        explanation.neutralMaterials.isNotEmpty) {
      materials(
        '活動・中立の材料（例）',
        'Activity / neutral materials (examples)',
        explanation.neutralMaterials,
      );
    }
    lines.add('${pick('解釈', 'Interpretation')}: ${explanation.interpretation}');
    lines.add('${pick('行動', 'Action')}: ${explanation.advice}');
    if (detailed) {
      lines.addAll(explanation.limitations);
      lines.add('Model: ${explanation.modelVersion} · ${explanation.status}');
    } else {
      lines.add(
        pick(
          '材料の件数は成功確率や独立した出来事数ではありません。根拠と制約の補足は「なぜ？」で確認できます。',
          'Factor counts are not success probabilities or independent events. Ask "why?" for more evidence and limitations.',
        ),
      );
    }
    return lines.join('\n\n');
  }
}
