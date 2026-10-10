part of 'main.dart';

/// A local, deterministic response built from one already calculated daily
/// forecast. It never calculates a score or persists conversation state.
enum ConsultNavigationV2Status {
  answered,
  clarificationRequired,
  forecastRequired,
  unavailable,
}

enum ConsultNavigationV2Mode { standard, explainWhy, moreDetail }

class ConsultNavigationV2Request {
  const ConsultNavigationV2Request({
    required this.question,
    required this.todayJst,
    required this.forecastTargetDateJst,
    required this.predictions,
    required this.language,
    this.defaultTargetDateJst,
    this.previous,
    this.supplement,
  });

  final String question;

  /// A JST civil date supplied by the caller. Only its calendar fields are
  /// read; the module does not convert a selected date or use the device zone.
  final DateTime todayJst;

  /// Optional selected civil day for a question without a date. Explicit
  /// today/tomorrow still use [todayJst]; follow-ups use the previous answer.
  /// Omitting this preserves the earlier default-to-today API contract.
  final DateTime? defaultTargetDateJst;

  /// Civil date represented by [predictions]. A mismatch never reuses these
  /// predictions for another date.
  final DateTime forecastTargetDateJst;
  final List<NineAreaPrediction> predictions;
  final AppLanguage language;
  final ConsultNavigationV2Context? previous;
  final UserProfileDetails? supplement;
}

/// Ephemeral in-memory state for follow-up turns. The app must not serialize it
/// or write it to profile, diary, or chat-history storage.
class ConsultNavigationV2Context {
  const ConsultNavigationV2Context({
    required this.targetDateJst,
    required this.topic,
    required this.prediction,
    this.supplement,
  });

  final DateTime targetDateJst;
  final NineAreaKey topic;
  final NineAreaPrediction prediction;
  final UserProfileDetails? supplement;
}

class ConsultNavigationV2Result {
  const ConsultNavigationV2Result({
    required this.status,
    required this.text,
    required this.mode,
    this.targetDateJst,
    this.topic,
    this.conclusion,
    this.reason,
    this.action,
    this.score,
    this.feltLabel,
    this.interpretation,
    this.limitations = const [],
    this.supplementEffects = const [],
    this.modelVersion,
    this.explanation,
    this.nextContext,
  });

  final ConsultNavigationV2Status status;
  final ConsultNavigationV2Mode mode;
  final String text;
  final DateTime? targetDateJst;
  final NineAreaKey? topic;
  final String? conclusion;
  final String? reason;
  final String? action;
  final int? score;
  final String? feltLabel;
  final String? interpretation;
  final List<String> limitations;
  final List<String> supplementEffects;
  final String? modelVersion;
  final ForecastExplanationResult? explanation;
  final ConsultNavigationV2Context? nextContext;
}

class ConsultNavigationV2 {
  const ConsultNavigationV2._();

  static ConsultNavigationV2Result respond(ConsultNavigationV2Request request) {
    final language = request.language;
    final question = request.question.trim().toLowerCase();
    final previous = request.previous;
    final mode = _modeFor(question);
    if (_isAmbiguousReference(question)) {
      return _clarification(language, mode, 'ambiguous_reference');
    }
    if (_isUnsupportedPeriod(question)) {
      return _clarification(language, mode, 'unsupported_period');
    }

    final dateSelection = _selectDate(request, question);
    if (dateSelection.ambiguous) {
      return _clarification(language, mode, 'ambiguous_date');
    }
    if (dateSelection.needsPreviousDate) {
      return _clarification(language, mode, 'missing_previous_date');
    }

    final explicitTopics = _topicsIn(question);
    if (explicitTopics.length > 1) {
      return _clarification(
        language,
        mode,
        'multiple_topics',
        targetDateJst: dateSelection.date,
      );
    }
    final isFollowUpDate = dateSelection.isRelativeToPrevious;
    final topic =
        explicitTopics.singleOrNull ??
        (isFollowUpDate || mode != ConsultNavigationV2Mode.standard
            ? previous?.topic
            : null);
    if (topic == null) {
      return _clarification(
        language,
        mode,
        mode == ConsultNavigationV2Mode.standard
            ? 'missing_topic'
            : 'missing_context',
        targetDateJst: dateSelection.date,
      );
    }

    final targetDate = _civilDate(
      dateSelection.date ??
          (mode != ConsultNavigationV2Mode.standard && previous != null
              ? previous.targetDateJst
              : request.defaultTargetDateJst ?? request.todayJst),
    );

    if (mode != ConsultNavigationV2Mode.standard &&
        previous != null &&
        previous.topic == topic &&
        _sameCivilDate(previous.targetDateJst, targetDate) &&
        !dateSelection.explicitDifferentDate) {
      return _answerFromPrediction(
        prediction: previous.prediction,
        targetDateJst: previous.targetDateJst,
        topic: previous.topic,
        language: language,
        mode: mode,
        supplement: previous.supplement,
      );
    }

    if (!_sameCivilDate(request.forecastTargetDateJst, targetDate)) {
      return _forecastRequired(language, mode, targetDate, topic);
    }

    final byKey = <NineAreaKey, NineAreaPrediction>{};
    for (final prediction in request.predictions) {
      if (byKey.containsKey(prediction.key)) {
        return _unavailable(language, mode, targetDate, topic);
      }
      byKey[prediction.key] = prediction;
    }
    if (byKey.length != NineAreaKey.values.length ||
        !NineAreaKey.values.every(byKey.containsKey)) {
      return _unavailable(language, mode, targetDate, topic);
    }
    final selected = byKey[topic]!;
    if (topic == NineAreaKey.felt && selected.score != null) {
      return _unavailable(language, mode, targetDate, topic);
    }
    return _answerFromPrediction(
      prediction: selected,
      targetDateJst: targetDate,
      topic: topic,
      language: language,
      mode: mode,
      supplement: request.supplement,
    );
  }

  static ConsultNavigationV2Result _answerFromPrediction({
    required NineAreaPrediction prediction,
    required DateTime targetDateJst,
    required NineAreaKey topic,
    required AppLanguage language,
    required ConsultNavigationV2Mode mode,
    required UserProfileDetails? supplement,
  }) {
    final strings = AppStrings(language);
    final explanation = ForecastExplanation.forDaily(
      prediction: prediction,
      targetDate: targetDateJst,
      strings: strings,
      depth: mode == ConsultNavigationV2Mode.standard
          ? ReadingDepth.simple
          : ReadingDepth.detailed,
      supplement: supplement,
    );
    return ConsultNavigationV2Result(
      status: ConsultNavigationV2Status.answered,
      mode: mode,
      text: explanation.text,
      targetDateJst: targetDateJst,
      topic: topic,
      conclusion: explanation.conclusion,
      reason: explanation.basis,
      action: explanation.advice,
      score: explanation.score,
      feltLabel: explanation.feltLabel,
      interpretation: explanation.interpretation,
      limitations: explanation.limitations,
      supplementEffects: explanation.supplementEffects,
      modelVersion: explanation.modelVersion,
      explanation: explanation,
      nextContext: ConsultNavigationV2Context(
        targetDateJst: targetDateJst,
        topic: topic,
        prediction: prediction,
        supplement: supplement,
      ),
    );
  }

  static ConsultNavigationV2Result _forecastRequired(
    AppLanguage language,
    ConsultNavigationV2Mode mode,
    DateTime targetDate,
    NineAreaKey topic,
  ) {
    final title = AppStrings(
      language,
    ).areaTitle(AppNineArea.fromKey(topic.name));
    final text = language == AppLanguage.ja
        ? '${NineAreaPeriodSummary.dateLabel(targetDate)} JST の$titleは、その日付の予測データが必要です。日付を変えずに計算後、回答します。'
        : 'A forecast for $title on ${NineAreaPeriodSummary.dateLabel(targetDate)} JST is required. The answer will use that date’s data.';
    return ConsultNavigationV2Result(
      status: ConsultNavigationV2Status.forecastRequired,
      mode: mode,
      text: text,
      targetDateJst: targetDate,
      topic: topic,
    );
  }

  static ConsultNavigationV2Result _unavailable(
    AppLanguage language,
    ConsultNavigationV2Mode mode,
    DateTime targetDate,
    NineAreaKey topic,
  ) => ConsultNavigationV2Result(
    status: ConsultNavigationV2Status.unavailable,
    mode: mode,
    text: language == AppLanguage.ja
        ? '対象日または9項目の予測データがそろっていないため、回答を作れません。'
        : 'The response is unavailable because the target date or a complete set of nine-area data is missing.',
    targetDateJst: targetDate,
    topic: topic,
  );

  static ConsultNavigationV2Result _clarification(
    AppLanguage language,
    ConsultNavigationV2Mode mode,
    String reason, {
    DateTime? targetDateJst,
  }) {
    final text = switch ((language, reason)) {
      (AppLanguage.ja, 'ambiguous_reference') =>
        'どの結論について知りたいですか？対象日と話題を一つずつ指定してください。',
      (AppLanguage.en, 'ambiguous_reference') =>
        'Which conclusion do you mean? Please specify one date and one topic.',
      (AppLanguage.ja, 'ambiguous_date') => '対象日が複数に読めます。確認したい日付を一つ指定してください。',
      (AppLanguage.en, 'ambiguous_date') =>
        'I read more than one possible date. Please specify one date.',
      (AppLanguage.ja, 'missing_previous_date') =>
        '「翌日」は直前の対象日が必要です。日付と話題をもう一度教えてください。',
      (AppLanguage.en, 'missing_previous_date') =>
        '“The next day” needs a previous target date. Please provide the date and topic.',
      (AppLanguage.ja, 'unsupported_period') =>
        '期間全体にはこの日別回答を使えません。日付を一日指定するか、週・月・年の画面を使ってください。',
      (AppLanguage.en, 'unsupported_period') =>
        'This daily answer cannot cover a whole period. Choose one date or use the week, month, or year view.',
      (AppLanguage.ja, 'multiple_topics') =>
        '複数の話題が含まれています。総合・恋愛・仕事・金運・メンタル・健康・対人・行動／決断・体感から一つ選んでください。',
      (AppLanguage.en, 'multiple_topics') =>
        'Your question includes multiple topics. Please choose one: overall, love, work, money, mental, health, people, action and decisions, or felt experience.',
      (AppLanguage.ja, 'missing_context') => '前の回答を参照できません。対象日と話題をもう一度教えてください。',
      (AppLanguage.en, 'missing_context') =>
        'There is no previous answer to refer to. Please provide the date and topic again.',
      (AppLanguage.ja, _) =>
        'どの話題を見ますか？総合・恋愛・仕事・金運・メンタル・健康・対人・行動／決断・体感から一つ選んでください。',
      (AppLanguage.en, _) =>
        'Which topic should I read? Choose one: overall, love, work, money, mental, health, people, action and decisions, or felt experience.',
    };
    return ConsultNavigationV2Result(
      status: ConsultNavigationV2Status.clarificationRequired,
      mode: mode,
      text: text,
      targetDateJst: targetDateJst,
    );
  }

  static _ConsultNavigationV2DateSelection _selectDate(
    ConsultNavigationV2Request request,
    String question,
  ) {
    final candidates = <DateTime>[];
    var needsPreviousDate = false;
    final today = _civilDate(request.todayJst);
    final previous = request.previous;
    void add(DateTime value, {bool relativeToPrevious = false}) {
      candidates.add(_civilDate(value));
      if (relativeToPrevious && previous == null) needsPreviousDate = true;
    }

    final isDayAfterTomorrow =
        question.contains('明後日') ||
        question.contains('あさって') ||
        question.contains('day after tomorrow');
    final isTomorrow = question.contains('明日') || question.contains('tomorrow');
    final isToday =
        question.contains('今日') ||
        question.contains('本日') ||
        RegExp(r'\btoday\b').hasMatch(question);
    final isYesterday =
        question.contains('昨日') ||
        question.contains('きのう') ||
        RegExp(r'\byesterday\b').hasMatch(question);
    final isNextDay =
        question.contains('翌日') ||
        question.contains('次の日') ||
        RegExp(r'\bnext\s+day\b').hasMatch(question);
    if (isDayAfterTomorrow) add(today.add(const Duration(days: 2)));
    if (isTomorrow && !isDayAfterTomorrow) {
      add(today.add(const Duration(days: 1)));
    }
    if (isToday) add(today);
    if (isYesterday) add(today.subtract(const Duration(days: 1)));
    if (isNextDay) {
      if (previous == null) {
        needsPreviousDate = true;
      } else {
        add(
          previous.targetDateJst.add(const Duration(days: 1)),
          relativeToPrevious: true,
        );
      }
    }

    var invalidExplicitDate = false;
    final japaneseFullMatches = RegExp(
      r'(\d{4})年(\d{1,2})月(\d{1,2})日?',
    ).allMatches(question).toList();
    final dateMatches = <RegExpMatch>[
      ...japaneseFullMatches,
      ...RegExp(r'(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})').allMatches(question),
    ];
    for (final match in dateMatches) {
      final year = int.tryParse(match.group(1) ?? '');
      final month = int.tryParse(match.group(2) ?? '');
      final day = int.tryParse(match.group(3) ?? '');
      if (year == null || month == null || day == null) {
        invalidExplicitDate = true;
        continue;
      }
      final candidate = DateTime.utc(year, month, day);
      if (candidate.year != year ||
          candidate.month != month ||
          candidate.day != day) {
        invalidExplicitDate = true;
        continue;
      }
      add(candidate);
    }
    final japaneseMonthDayMatches = RegExp(
      r'(\d{1,2})月(\d{1,2})日?',
    ).allMatches(question);
    for (final match in japaneseMonthDayMatches) {
      if (japaneseFullMatches.any(
        (full) => full.start <= match.start && full.end >= match.end,
      )) {
        continue;
      }
      final month = int.tryParse(match.group(1) ?? '');
      final day = int.tryParse(match.group(2) ?? '');
      if (month == null || day == null) {
        invalidExplicitDate = true;
        continue;
      }
      final candidate = DateTime.utc(today.year, month, day);
      if (candidate.month != month || candidate.day != day) {
        invalidExplicitDate = true;
        continue;
      }
      add(candidate);
    }
    const monthNumbers = <String, int>{
      'january': 1,
      'february': 2,
      'march': 3,
      'april': 4,
      'may': 5,
      'june': 6,
      'july': 7,
      'august': 8,
      'september': 9,
      'october': 10,
      'november': 11,
      'december': 12,
    };
    final englishDatePattern = RegExp(
      r'\b(january|february|march|april|may|june|july|august|september|october|november|december)\s+(\d{1,2})(?:st|nd|rd|th)?(?:,?\s+((?:19|20|21)\d{2}))?\b',
    );
    final englishDateMatches = englishDatePattern.allMatches(question).toList();
    for (final match in englishDateMatches) {
      final month = monthNumbers[match.group(1) ?? ''];
      final day = int.tryParse(match.group(2) ?? '');
      final year = int.tryParse(match.group(3) ?? '') ?? today.year;
      if (month == null || day == null) {
        invalidExplicitDate = true;
        continue;
      }
      final candidate = DateTime.utc(year, month, day);
      if (candidate.year != year ||
          candidate.month != month ||
          candidate.day != day) {
        invalidExplicitDate = true;
        continue;
      }
      add(candidate);
    }
    final distinct = candidates.map(_dateKey).toSet();
    return _ConsultNavigationV2DateSelection(
      date: distinct.length == 1 ? candidates.first : null,
      ambiguous: distinct.length > 1 || invalidExplicitDate,
      needsPreviousDate: needsPreviousDate,
      isRelativeToPrevious: isNextDay,
      explicitDifferentDate:
          dateMatches.isNotEmpty || englishDateMatches.isNotEmpty,
    );
  }

  static Set<NineAreaKey> _topicsIn(String question) {
    final matches = <NineAreaKey>{};
    void add(NineAreaKey key, List<String> terms) {
      if (terms.any(question.contains)) matches.add(key);
    }

    add(NineAreaKey.overall, ['総合', '全体', 'overall', 'general']);
    add(NineAreaKey.love, ['恋愛', '親密な関係', 'love', 'romance']);
    add(NineAreaKey.work, ['仕事', '職場', 'キャリア', 'work', 'career', 'job']);
    add(NineAreaKey.money, ['金運', 'お金', '収支', 'money', 'finance', 'budget']);
    add(NineAreaKey.mental, [
      'メンタル',
      '気分',
      '心理',
      '集中',
      'mental',
      'mood',
      'focus',
      'stress',
    ]);
    add(NineAreaKey.health, [
      '健康',
      '体調',
      '身体',
      '体の調子',
      'health',
      'physical',
      'body',
      'fatigue',
      'rest',
    ]);
    add(NineAreaKey.people, [
      '対人',
      '人間関係',
      '家族',
      '友人',
      '協力',
      'people',
      'social',
      'family',
      'friends',
    ]);
    add(NineAreaKey.actionDecision, [
      '行動',
      '決断',
      '着手',
      'activity',
      'action',
      'decision',
    ]);
    add(NineAreaKey.felt, [
      '体感',
      '満足感',
      'felt experience',
      'felt',
      'satisfaction',
    ]);
    return matches;
  }

  static ConsultNavigationV2Mode _modeFor(String question) {
    if (['なぜ', 'なんで', 'どうして', '理由', 'why'].any(question.contains)) {
      return ConsultNavigationV2Mode.explainWhy;
    }
    if ([
      'もっと詳しく',
      '詳しく',
      '詳細',
      'more detail',
      'more details',
      'in more detail',
    ].any(question.contains)) {
      return ConsultNavigationV2Mode.moreDetail;
    }
    return ConsultNavigationV2Mode.standard;
  }

  static bool _isAmbiguousReference(String question) => [
    'それは',
    'それって',
    'あれは',
    'どうなの',
    'what about that',
    'how about that',
  ].any(question.contains);

  static bool _isUnsupportedPeriod(String question) {
    const japaneseTerms = [
      '今週',
      '来週',
      '先週',
      '今月',
      '来月',
      '先月',
      '今年',
      '来年',
      '去年',
      '週運',
      '月運',
      '年運',
      '今後',
      '数日',
      '数週間',
      '数か月',
      '数ヶ月',
    ];
    if (japaneseTerms.any(question.contains)) return true;
    final fullNumericDate = RegExp(
      r'(?:\b(?:19|20|21)\d{2}[-/.]\d{1,2}[-/.]\d{1,2}\b|'
      r'\b(?:19|20|21)\d{2}年\d{1,2}月\d{1,2}日?)',
    ).hasMatch(question);
    final fullEnglishDate = RegExp(
      r'\b(january|february|march|april|may|june|july|august|september|october|november|december)\s+\d{1,2}(st|nd|rd|th)?(?:,?\s+(?:19|20|21)\d{2})?\b',
    ).hasMatch(question);
    if (!fullNumericDate &&
        !fullEnglishDate &&
        RegExp(r'\b(?:19|20|21)\d{2}\b').hasMatch(question)) {
      return true;
    }
    if (RegExp(
      r'(?:(?:19|20|21)\d{2}年)?\d{1,2}月(?!\s*\d{1,2}日)',
    ).hasMatch(question)) {
      return true;
    }
    if (RegExp(
      r'\b(?:19|20|21)\d{2}[-/.]\d{1,2}(?!\d)(?![-/.]\d{1,2}\b)',
    ).hasMatch(question)) {
      return true;
    }
    if (RegExp(r'\b\d{1,2}[-/.]\d{1,2}\b').hasMatch(question) &&
        !RegExp(
          r'\b(?:19|20|21)\d{2}[-/.]\d{1,2}[-/.]\d{1,2}\b',
        ).hasMatch(question)) {
      return true;
    }
    if (RegExp(r'\d{1,2}日').hasMatch(question) &&
        !RegExp(r'(?:19|20|21)\d{2}年\d{1,2}月\d{1,2}日?').hasMatch(question) &&
        !RegExp(r'\d{1,2}月\d{1,2}日?').hasMatch(question)) {
      return true;
    }
    if (RegExp(
      r'\b(january|february|march|april|june|july|august|september|october|november|december)\b(?!\s+\d{1,2}(st|nd|rd|th)?\b)|'
      r'\bin\s+may\b|\bmay\s+(?:19|20|21)\d{2}\b',
    ).hasMatch(question)) {
      return true;
    }
    return RegExp(
      r'\b(this|next|last)\s+(week|month|year|quarter|weekend)\b|'
      r'\b(weekly|monthly|yearly|annual|quarterly)\b|'
      r'\b\d+\s*(days?|weeks?|months?|years?)\b',
    ).hasMatch(question);
  }

  /// Canonical 12:00 JST instant for a civil date. The shared explanation
  /// API formats dates by converting its instant to JST, so UTC 03:00 is used.
  static DateTime _civilDate(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day, 3);

  static bool _sameCivilDate(DateTime first, DateTime second) =>
      first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;

  static String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}

class _ConsultNavigationV2DateSelection {
  const _ConsultNavigationV2DateSelection({
    required this.date,
    required this.ambiguous,
    required this.needsPreviousDate,
    required this.isRelativeToPrevious,
    required this.explicitDifferentDate,
  });

  final DateTime? date;
  final bool ambiguous;
  final bool needsPreviousDate;
  final bool isRelativeToPrevious;
  final bool explicitDifferentDate;
}

extension _SingleOrNullConsultNavigation<T> on Iterable<T> {
  T? get singleOrNull {
    if (isEmpty || length != 1) return null;
    return first;
  }
}
