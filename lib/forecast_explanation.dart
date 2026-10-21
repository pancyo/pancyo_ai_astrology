part of 'main.dart';

/// Presentation of an existing forecast, never a second scoring engine.
/// Background text selects examples and tone only; it is not astronomical evidence.
class ForecastExplanation {
  const ForecastExplanation._();

  static ForecastExplanationResult forDaily({
    required NineAreaPrediction prediction,
    required DateTime targetDate,
    required AppStrings strings,
    ReadingDepth depth = ReadingDepth.simple,
    UserProfileDetails? supplement,
    List<NineAreaPrediction> relatedPredictions = const [],
  }) {
    final p = prediction;
    _checkScore(p.key, p.score);
    final copy = _ForecastExplanationCopy(strings);
    final materials = _ForecastExplanationMaterials();
    final limitations = <String>[];
    final label = p.feltForecast?.label;
    String model = 'unknown_preserved';
    String basis;
    if (p.key == NineAreaKey.felt) {
      if (label != null && !FeltForecastCandidate.labels.contains(label)) {
        throw const FormatException('Unknown canonical felt label.');
      }
      final trace = p.feltForecast?.trace;
      model = trace?['model_version'] is String
          ? trace!['model_version'] as String
          : 'unknown_preserved';
      var valid = false;
      if (trace != null) {
        try {
          FeltForecastCandidate.validateSnapshot(trace, label);
          valid = true;
        } on FormatException {
          limitations.add(copy.missingTrace);
        }
      } else {
        limitations.add(copy.missingTrace);
      }
      if (valid && label != null) {
        final t = trace!;
        basis = copy.pick(
          '正規の月ベース体感候補。調和 ${copy.n(t['harmony'])} − 緊張 ${copy.n(t['tension'])} に感受性倍率 ${copy.n(t['sensitivity_multiplier'])} を反映。数値点へ換算しません。',
          'Canonical Moon-based felt candidate: harmony ${copy.n(t['harmony'])} minus tension ${copy.n(t['tension'])}, with sensitivity multiplier ${copy.n(t['sensitivity_multiplier'])}. It is not converted into a score.',
        );
        for (final row in (t['selected_aspects'] as List).cast<Map>()) {
          materials.addFelt(row, copy);
        }
      } else {
        basis = label == null ? copy.unavailable : copy.missingTrace;
      }
      if (p.feltComparison != null || p.longTermContext != null) {
        limitations.add(
          copy.pick(
            '楽しみ・長期背景の比較候補や参考配置は正規体感へ加算していません。',
            'Pleasure, longer-term comparison candidates and reference placements are not added to canonical felt experience.',
          ),
        );
      }
    } else {
      final b = p.scoreBreakdown;
      model = b?['model_version'] is String
          ? b!['model_version'] as String
          : 'unknown_preserved';
      basis = _numericBasis(p, copy, materials, limitations);
    }
    final missing = p.key == NineAreaKey.felt ? label == null : p.score == null;
    final reading = strings.areaReading(
      AppNineArea.fromKey(p.key.name),
      score: p.score,
      feltLabel: label,
      canonicalJapaneseReading: p.reading,
    );
    return _finish(
      key: p.key,
      score: p.score,
      feltLabel: label,
      title:
          '${NineAreaPeriodSummary.dateLabel(targetDate)} JST · ${strings.nineAreaTitle(p.key.name)}',
      conclusion: missing ? copy.unavailable : reading,
      basis: basis,
      modelVersion: model,
      status: missing
          ? 'not_predicted'
          : p.key == NineAreaKey.felt
          ? 'canonical_felt_trial_unvalidated'
          : p.provisional
          ? 'current_trial_unvalidated'
          : 'inherited_existing_unvalidated',
      materials: materials,
      limitations: limitations,
      depth: depth,
      supplement: supplement,
      copy: copy,
      displayNarrative: depth == ReadingDepth.detailed
          ? _dailyNarrative(p, relatedPredictions, supplement, copy)
          : null,
    );
  }

  /// [dailySamples] are already calculated forecasts indexed by JST date label,
  /// or by the exact JST instant for [PeriodSevenSummary].
  /// Missing traces stay unknown. This method never calculates another context.
  static ForecastExplanationResult forPeriod({
    required NineAreaPeriodSummary summary,
    required NineAreaPeriodEntry area,
    required AppStrings strings,
    ReadingDepth depth = ReadingDepth.simple,
    UserProfileDetails? supplement,
    Map<String, List<NineAreaPrediction>> dailySamples = const {},
    bool includeEvidence = true,
  }) {
    if (!summary.areas.contains(area)) {
      throw ArgumentError('The area must belong to this period summary.');
    }
    _checkScore(area.key, area.score);
    final copy = _ForecastExplanationCopy(strings);
    final materials = _ForecastExplanationMaterials();
    final limitations = <String>[];
    if (dailySamples.isNotEmpty) _validateSamples(summary, dailySamples);
    String basis;
    if (area.key == NineAreaKey.felt) {
      basis =
          '${summary.displaySamplingText(strings)}. ${summary.displayFeltDistribution(strings)}. ${copy.pick('最多同数は混在、全欠測は未予測。数値平均しません。', 'Ties remain Mixed, and all missing remains Not predicted. Labels are not numerically averaged.')}';
    } else if (area.inherited) {
      basis = copy.pick(
        '従来の期間点 ${area.score} 点を維持。確認日の日点平均へ置き換えていません。元の期間計算根拠がない正負材料は推定しません。',
        'The inherited period score of ${area.score} is retained. It is not replaced with a mean of daily samples. Positive or negative factors are not inferred without the original period trace.',
      );
    } else {
      basis =
          '${summary.displaySamplingText(strings)}. ${summary is PeriodSevenSummary ? copy.pick('各時点の点数', 'Unique-instant scores') : copy.pick('確認日点数', 'Sample scores')}: ${area.samples.join(', ')}. ${copy.pick('算術平均を最後に1回四捨五入', 'Arithmetic mean rounded once at the end')}: ${area.score}. ${copy.pick('期間ボーナスの追加なし。', 'No additional period bonus.')}';
    }
    if (includeEvidence && dailySamples.isNotEmpty && !area.inherited) {
      for (final date in summary.dates) {
        final dateLabel = _periodSampleKey(summary, date);
        final p = dailySamples[dateLabel]!.singleWhere(
          (p) => p.key == area.key,
        );
        final one = forDaily(prediction: p, targetDate: date, strings: strings);
        materials.positive.addAll(
          one.positiveMaterials.map((v) => '$dateLabel: $v'),
        );
        materials.negative.addAll(
          one.negativeMaterials.map((v) => '$dateLabel: $v'),
        );
        materials.neutral.addAll(
          one.neutralMaterials.map((v) => '$dateLabel: $v'),
        );
        if (one.limitations.contains(copy.missingTrace)) {
          limitations.add('$dateLabel: ${copy.missingTrace}');
        }
      }
      limitations.add(
        copy.pick(
          summary is PeriodSevenSummary
              ? '正負材料は各確認時点の採用済み根拠です。件数を期間の成功確率や独立した出来事数へ換算しません。'
              : '正負材料は各確認日の採用済み根拠です。件数を期間の成功確率や独立した出来事数へ換算しません。',
          'Materials are the selected factors at each sample. Their counts are not success probabilities or independent event counts.',
        ),
      );
    } else if (includeEvidence && !area.inherited) {
      limitations.add(copy.missingTrace);
    }
    limitations.add(
      summary is PeriodSevenSummary
          ? summary.displaySampleLimitation(strings)
          : copy.pick(
              '期間の確認時点の集計です。週の全時刻、月・年の全日を計算した結果ではありません。',
              'This aggregates reference samples, not every hour of a week or every day of a month or year.',
            ),
    );
    return _finish(
      key: area.key,
      score: area.score,
      feltLabel: area.key == NineAreaKey.felt ? summary.feltLabel : null,
      title: summary is PeriodSevenSummary
          ? '${summary.startDateJst}–${summary.endDateJst} JST · ${strings.nineAreaTitle(area.key.name)}'
          : '${NineAreaPeriodSummary.dateLabel(summary.dates.first)}–${NineAreaPeriodSummary.dateLabel(summary.dates.last)} JST · ${strings.nineAreaTitle(area.key.name)}',
      conclusion: summary.displayReading(area, strings),
      basis: basis,
      modelVersion: summary is PeriodSevenSummary
          ? summary.aggregationModelVersion
          : summary.useGeneralModel
          ? NineAreaPeriodSummary.generalModelVersion
          : NineAreaPeriodSummary.modelVersion,
      status: area.key == NineAreaKey.felt && summary.feltModes.isEmpty
          ? 'not_predicted'
          : area.inherited
          ? 'inherited_existing_unvalidated'
          : 'current_trial_unvalidated',
      materials: materials,
      limitations: limitations,
      depth: depth,
      supplement: supplement,
      copy: copy,
      displayNarrative: _periodNarrative(
        summary,
        area,
        dailySamples,
        supplement,
        copy,
        concise: depth == ReadingDepth.simple,
      ),
    );
  }

  // Reading-only comparisons of existing values, never inputs to scoring.
  static String _dailyNarrative(
    NineAreaPrediction prediction,
    List<NineAreaPrediction> relatedPredictions,
    UserProfileDetails? supplement,
    _ForecastExplanationCopy copy,
  ) {
    if (prediction.key == NineAreaKey.felt) {
      final label = prediction.feltForecast?.label;
      if (label == null) {
        return copy.pick(
          '体感は未予測です。今の気持ちに合わせて過ごしましょう。',
          'Felt experience is unavailable. Let your actual feelings guide your pace.',
        );
      }
      return [
        copy.pick(
              'この時点の体感は「${copy.strings.feltLabelText(label) ?? label}」の候補です。',
              'The felt candidate at this time is ${copy.strings.feltLabelText(label) ?? label}. ',
            ) +
            copy.feltOutlook(label),
        _aspectNarrative(prediction, relatedPredictions, copy),
        _displayPlan(prediction.key, supplement, copy),
      ].join('\n\n');
    }
    if (prediction.score == null) {
      return copy.pick(
        '必要なデータがなく、この時点の運勢は未予測です。',
        'The reading for this time is unavailable because required data is missing.',
      );
    }
    return [
      copy.displayOutlook(
        prediction.key,
        prediction.score!,
        copy.pick('この時点', 'At this time'),
      ),
      _aspectNarrative(prediction, relatedPredictions, copy),
      _displayPlan(prediction.key, supplement, copy),
    ].join('\n\n');
  }

  static String _periodNarrative(
    NineAreaPeriodSummary summary,
    NineAreaPeriodEntry area,
    Map<String, List<NineAreaPrediction>> dailySamples,
    UserProfileDetails? supplement,
    _ForecastExplanationCopy copy, {
    bool concise = false,
  }) {
    final singleDay = summary is PeriodSevenSummary && summary.isSingleDay;
    final fiveYear = summary is LongRangeDisplaySummary && summary.isFiveYear;
    final scope = copy.pick(
      singleDay
          ? 'この日'
          : fiveYear
          ? 'この5年間'
          : switch (summary.mode) {
              LongRangeMode.week => 'この週',
              LongRangeMode.month => 'この月',
              LongRangeMode.year => 'この年',
            },
      singleDay
          ? 'This day'
          : fiveYear
          ? 'These five years'
          : switch (summary.mode) {
              LongRangeMode.week => 'This week',
              LongRangeMode.month => 'This month',
              LongRangeMode.year => 'This year',
            },
    );
    if (area.key == NineAreaKey.felt) {
      final felt = _feltPeriodNarrative(
        summary,
        dailySamples,
        scope,
        supplement,
        copy,
        concise: concise,
      );
      return felt;
    }
    if (area.score == null) {
      return copy.pick(
        'この期間の運勢は未予測です。',
        'The reading for this period is unavailable.',
      );
    }
    if (concise) {
      return '${copy.displayOutlook(area.key, area.score!, scope)}\n${copy.shortAdvice(area.key)}';
    }
    final groups = <String, List<int>>{};
    if (summary is PeriodSevenSummary &&
        !singleDay &&
        area.samples.length == summary.dates.length) {
      // Each day's seven displayed points include its 24:00 boundary. The
      // original period score keeps its deduplicated sample population.
      final first = DateTime.parse(summary.startDateJst);
      for (var day = 0; day < summary.dayCount; day++) {
        final start = DateTime.utc(
          first.year,
          first.month,
          first.day + day,
        ).subtract(const Duration(hours: 9));
        final end = start.add(const Duration(days: 1));
        final values = [
          for (var i = 0; i < summary.dates.length; i++)
            if (!summary.dates[i].isBefore(start) &&
                !summary.dates[i].isAfter(end))
              area.samples[i],
        ];
        if (values.isNotEmpty) {
          groups[_narrativeSampleLabel(summary, start, copy)] = values;
        }
      }
    } else if (area.samples.length == summary.dates.length) {
      for (var i = 0; i < summary.dates.length; i++) {
        groups
            .putIfAbsent(
              _narrativeSampleLabel(summary, summary.dates[i], copy),
              () => [],
            )
            .add(area.samples[i]);
      }
    }
    final means = {
      for (final entry in groups.entries)
        entry.key: entry.value.reduce((a, b) => a + b) / entry.value.length,
    };
    String timing;
    if (means.isEmpty) {
      timing = copy.pick(
        '時期ごとの比較は未予測です。予定の区切りで状況を見直しましょう。',
        'Timing comparisons are unavailable. Review the situation at each stage of your plans.',
      );
    } else {
      final low = means.values.reduce(math.min),
          high = means.values.reduce(math.max);
      if (high - low < 1) {
        timing = copy.pick(
          '期間内の流れはおおむね横ばいです。特定の時期に予定を集中させず、準備が整ったことから順に進めましょう。',
          'The sampled pattern is broadly steady across the period. Spread out your plans and proceed as each task becomes ready.',
        );
      } else {
        final highs = means.entries
            .where((e) => e.value == high)
            .map((e) => e.key)
            .join(copy.pick('・', ', '));
        final lows = means.entries
            .where((e) => e.value == low)
            .map((e) => e.key)
            .join(copy.pick('・', ', '));
        if (area.key == NineAreaKey.actionDecision) {
          timing = copy.pick(
            '$highsは比較的活動が活発になる流れ。動きたいことを一つずつ試して。$lowsは活動を絞り、下調べや準備に時間を取りましょう。',
            'Activity is relatively higher around $highs. Try one action at a time. Around $lows, narrow your commitments and make time for research and preparation.',
          );
        } else {
          timing = copy.pick(
            '期間内では$highsが比較的進めやすい時期。${copy.timingUse(area.key, true)}\n$lowsは丁寧に整えたい時期。${copy.timingUse(area.key, false)}',
            'The relatively more supportive timing is around $highs. ${copy.timingUse(area.key, true)}\nTake extra care around $lows. ${copy.timingUse(area.key, false)}',
          );
        }
      }
    }
    return [
      copy.displayOutlook(area.key, area.score!, scope),
      _periodAspectNarrative(summary, area.key, dailySamples, copy),
      timing,
      if (_hasPracticalSupplement(supplement))
        _displayPlan(area.key, supplement, copy),
    ].join('\n\n');
  }

  static String _narrativeSampleLabel(
    NineAreaPeriodSummary summary,
    DateTime date,
    _ForecastExplanationCopy copy,
  ) {
    final jst = date.toUtc().add(const Duration(hours: 9));
    if (summary is LongRangeDisplaySummary && summary.isFiveYear) {
      return copy.pick('${jst.year}年', '${jst.year}');
    }
    if (summary is PeriodSevenSummary) {
      if (summary.isSingleDay) {
        final boundary =
            NineAreaPeriodSummary.dateLabel(date) != summary.startDateJst;
        return copy.pick(
          '${boundary ? 24 : jst.hour}時',
          '${boundary ? '24' : jst.hour.toString().padLeft(2, '0')}:00',
        );
      }
      final label = NineAreaPeriodSummary.dateLabel(date);
      final selected = label.compareTo(summary.endDateJst) > 0
          ? DateTime.parse(summary.endDateJst)
          : jst;
      return copy.pick(
        '${selected.month}/${selected.day}',
        '${copy.monthName(selected.month)} ${selected.day}',
      );
    }
    if (summary.mode == LongRangeMode.year) return copy.monthName(jst.month);
    return copy.pick('${jst.day}日頃', '${copy.monthName(jst.month)} ${jst.day}');
  }

  static String _feltPeriodNarrative(
    NineAreaPeriodSummary summary,
    Map<String, List<NineAreaPrediction>> dailySamples,
    String scope,
    UserProfileDetails? supplement,
    _ForecastExplanationCopy copy, {
    bool concise = false,
  }) {
    if (summary.feltModes.isEmpty) {
      return copy.pick(
        '$scopeの体感は未予測です。実際の気持ちに合わせて予定を組みましょう。',
        'Felt experience is unavailable for this period. Plan around how you actually feel.',
      );
    }
    final labels = summary.feltModes
        .map((v) => copy.strings.feltLabelText(v) ?? v)
        .join(copy.pick('・', ', '));
    final lead = summary.feltModes.length > 1
        ? copy.pick(
            '$scopeは「$labels」の候補が同じくらい現れる、体感が混ざる流れです。気持ちの切り替わりに合わせて、予定に余白を残しましょう。',
            '$scope: the felt candidates $labels are tied. Leave flexibility for changes in how the period feels.',
          )
        : copy.pick(
                '$scopeは「$labels」が中心の体感候補です。',
                '$scope: $labels is the most frequent felt candidate. ',
              ) +
              copy.feltOutlook(summary.feltModes.single);
    if (concise) return lead;
    final pleasant = <String>{}, demanding = <String>{};
    for (final date in summary.dates) {
      final sample = dailySamples[_periodSampleKey(summary, date)];
      if (sample == null) continue;
      final label = sample
          .singleWhere((p) => p.key == NineAreaKey.felt)
          .feltForecast
          ?.label;
      final time = _narrativeSampleLabel(summary, date, copy);
      if (label == '最高' || label == '良い') pleasant.add(time);
      if (label == '最悪' || label == '悪い') demanding.add(time);
    }
    String times(Set<String> values) {
      final first = values.take(4).join(copy.pick('・', ', '));
      return values.length <= 4
          ? first
          : copy.pick('$firstなど', '$first and other sampled times');
    }

    final timing = [
      if (pleasant.isNotEmpty)
        copy.pick(
          '${times(pleasant)}には、心地よく感じる候補が見られます。好きなことや気楽な交流を楽しむ余裕を。',
          'More pleasant felt candidates appear around ${times(pleasant)}. Leave space for something you enjoy or easy company.',
        ),
      if (demanding.isNotEmpty)
        copy.pick(
          '${times(demanding)}には、気持ちの負担を感じる候補も。用事を詰めず、静かに過ごす時間を取りましょう。',
          'More demanding felt candidates appear around ${times(demanding)}. Keep plans light and reserve some quiet time.',
        ),
      if (pleasant.isEmpty && demanding.isEmpty)
        copy.pick(
          '大きな高揚や落ち込みを前提にせず、いつもの楽しみと休息のリズムを大切にして。',
          'Keep your usual rhythm of enjoyment and rest, without assuming a strong emotional high or low.',
        ),
      if (summary.feltUnavailableCount > 0)
        copy.pick(
          '一部の時期は体感が未予測です。',
          'Some sampled times have no felt prediction.',
        ),
    ].join(' ');
    return [
      lead,
      _periodAspectNarrative(summary, NineAreaKey.felt, dailySamples, copy),
      timing,
      if (_hasPracticalSupplement(supplement))
        _displayPlan(NineAreaKey.felt, supplement, copy),
    ].join('\n\n');
  }

  static bool _hasPracticalSupplement(UserProfileDetails? supplement) {
    final background = _ForecastExplanationBackground.read(supplement);
    return background.rest || background.video || background.study;
  }

  static String _aspectNarrative(
    NineAreaPrediction prediction,
    List<NineAreaPrediction> related,
    _ForecastExplanationCopy copy,
  ) {
    final facts = _ForecastAspectEvidence.read(prediction, related: related);
    final selected = _ForecastAspectEvidence.representatives(facts, limit: 2);
    if (prediction.key == NineAreaKey.felt && selected.length < 2) {
      final reference = _ForecastAspectEvidence.reference(
        prediction.longTermContext,
      );
      if (reference != null) selected.add(reference);
    }
    if (selected.isEmpty) return copy.noAspectDetail;
    return selected
        .map((fact) => copy.aspectReading(fact, prediction.key))
        .join(' ');
  }

  // Inspect traces at no more than two existing instants. In particular, a
  // five-year card does not rebuild 120 daily evidence ledgers per area.
  static String _periodAspectNarrative(
    NineAreaPeriodSummary summary,
    NineAreaKey key,
    Map<String, List<NineAreaPrediction>> samples,
    _ForecastExplanationCopy copy,
  ) {
    if (samples.isEmpty) return copy.noAspectDetail;
    final area = summary.areas.singleWhere((area) => area.key == key);
    final dates = <DateTime>[];
    if (key != NineAreaKey.felt && area.samples.isNotEmpty) {
      final low = area.samples.reduce(math.min);
      final high = area.samples.reduce(math.max);
      dates.add(summary.dates[area.samples.indexOf(high)]);
      dates.add(
        high == low
            ? summary.dates.last
            : summary.dates[area.samples.indexOf(low)],
      );
    } else {
      DateTime? pleasant, demanding;
      for (final date in summary.dates) {
        final day = samples[_periodSampleKey(summary, date)];
        final label = day?.singleWhere((p) => p.key == key).feltForecast?.label;
        if (pleasant == null && {'最高', '良い'}.contains(label)) pleasant = date;
        if (demanding == null && {'最悪', '悪い'}.contains(label)) demanding = date;
        if (pleasant != null && demanding != null) break;
      }
      dates.add(pleasant ?? summary.dates.first);
      dates.add(demanding ?? summary.dates.last);
    }
    final lines = <String>[];
    final seen = <String>{};
    for (final date in dates.toSet()) {
      final day = samples[_periodSampleKey(summary, date)];
      if (day == null) continue;
      final prediction = day.singleWhere((p) => p.key == key);
      final facts = _ForecastAspectEvidence.representatives(
        _ForecastAspectEvidence.read(prediction, related: day),
        limit: 2,
      );
      _ForecastAspectFact? fact;
      for (final candidate in facts) {
        if (!seen.contains(candidate.identity)) {
          fact = candidate;
          break;
        }
      }
      if (fact == null && key == NineAreaKey.felt) {
        final reference = _ForecastAspectEvidence.reference(
          prediction.longTermContext,
        );
        if (reference != null && !seen.contains(reference.identity))
          fact = reference;
      }
      if (fact == null) continue;
      seen.add(fact.identity);
      final jst = date.toUtc().add(const Duration(hours: 9));
      final time =
          '${jst.hour.toString().padLeft(2, '0')}:${jst.minute.toString().padLeft(2, '0')}';
      final label = copy.pick(
        '${jst.year}/${jst.month}/${jst.day} $time JSTの確認例',
        'Sample on ${copy.monthName(jst.month)} ${jst.day}, ${jst.year}, $time JST',
      );
      lines.add('$label: ${copy.aspectReading(fact, key)}');
      if (lines.length == 2) break;
    }
    if (lines.isEmpty) return copy.noAspectDetail;
    return lines.join(' ');
  }

  static String _displayPlan(
    NineAreaKey key,
    UserProfileDetails? supplement,
    _ForecastExplanationCopy copy,
  ) {
    final background = _ForecastExplanationBackground.read(supplement);
    if (background.rest) {
      return copy.pick(
        '休息を予定の中心に。必要な用事を一つに絞り、途中でやめられる余裕を残しましょう。',
        'Make rest central to your plans. Choose one essential task and leave room to stop partway through.',
      );
    }
    if ({
      NineAreaKey.work,
      NineAreaKey.overall,
      NineAreaKey.actionDecision,
    }.contains(key)) {
      if (background.video) {
        return copy.pick(
          '動画制作なら、構成・撮影・編集を分け、一本の完成につながる作業を選びましょう。',
          'For video work, separate planning, filming and editing, then choose a task that brings one video closer to completion.',
        );
      }
      if (background.study) {
        return copy.pick(
          '学習なら、復習と演習を分けて取り組み、理解が曖昧な所を一つずつ確かめましょう。',
          'For study, separate review from practice and check uncertain topics one at a time.',
        );
      }
    }
    return copy.displayPlan(key);
  }

  static void _checkScore(NineAreaKey key, int? score) {
    if (key == NineAreaKey.felt
        ? score != null
        : score != null && (score < 50 || score > 99)) {
      throw const FormatException('Invalid score or numeric felt value.');
    }
  }

  static void _validateSamples(
    NineAreaPeriodSummary summary,
    Map<String, List<NineAreaPrediction>> samples,
  ) {
    final expected = summary.dates
        .map((date) => _periodSampleKey(summary, date))
        .toSet();
    if (samples.length != expected.length ||
        !samples.keys.every(expected.contains)) {
      throw const FormatException('Period sample dates differ.');
    }
    final counts = {for (final label in FeltForecastCandidate.labels) label: 0};
    var missing = 0;
    for (var i = 0; i < summary.dates.length; i++) {
      final day = samples[_periodSampleKey(summary, summary.dates[i])]!;
      if (day.length != 9 || day.map((p) => p.key).toSet().length != 9) {
        throw const FormatException('Nine distinct sample areas are required.');
      }
      for (final p in day) {
        _checkScore(p.key, p.score);
        if (p.key != NineAreaKey.felt) {
          final a = summary.areas.singleWhere((a) => a.key == p.key);
          if (a.samples.length != summary.dates.length ||
              p.score != a.samples[i]) {
            throw const FormatException('Period sample score differs.');
          }
        } else {
          final label = p.feltForecast?.label;
          if (label == null) {
            missing++;
          } else if (!counts.containsKey(label)) {
            throw const FormatException('Unknown sample felt label.');
          } else {
            counts[label] = counts[label]! + 1;
          }
        }
      }
    }
    if (missing != summary.feltUnavailableCount ||
        counts.keys.any((k) => counts[k] != summary.feltCounts[k])) {
      throw const FormatException('Period felt distribution differs.');
    }
  }

  static String _periodSampleKey(
    NineAreaPeriodSummary summary,
    DateTime date,
  ) => summary is PeriodSevenSummary
      ? summary.sampleKey(date)
      : NineAreaPeriodSummary.dateLabel(date);

  static String _numericBasis(
    NineAreaPrediction p,
    _ForecastExplanationCopy copy,
    _ForecastExplanationMaterials materials,
    List<String> limitations,
  ) {
    if (p.score == null) return copy.unavailable;
    final b = p.scoreBreakdown;
    if (b == null) {
      limitations.add(copy.missingTrace);
      return copy.missingTrace;
    }
    try {
      NineAreaScoreAudit.validate(b, p.score!);
    } on FormatException {
      limitations.add(copy.missingTrace);
      return copy.missingTrace;
    }
    final kind = b['calculation_kind'];
    for (final f in (b['factors'] as List).cast<Map>()) {
      materials.addNumeric(f, p.key, copy, b['design_trace']);
    }
    if (kind == 'general_six_area_mean_v1') {
      final trace = b['design_trace'];
      final scores = trace is Map ? trace['source_area_scores'] : null;
      return copy.pick(
        '恋愛・仕事・金運・メンタル・健康・対人の6分野を丸め前に平均し、最後に四捨五入。活動性・体感・リターン加点は含みません。原内訳: ${scores ?? '未提供'}。',
        'Six areas (love, work, money, mental well-being, physical well-being and relationships) are averaged before final rounding. Activity, felt experience and return bonuses are excluded. Recorded components: ${scores ?? 'unavailable'}.',
      );
    }
    if (kind == 'inherited_overall') {
      return copy.pick(
        '従来4分野平均と原内訳のリターン特例を維持。新6分野平均ではありません。',
        'The inherited four-area mean and its recorded return exception are retained. This is not the new six-area mean.',
      );
    }
    if (kind == 'general_outcome_groups_v1' ||
        kind == 'general_activity_groups_v1') {
      limitations.add(
        copy.pick(
          '同じ動く天体の重複を抑え、選択済み最大3群の原内訳だけを説明します。未選択群を加点へ戻しません。',
          'Only the recorded selected groups (at most three, with duplication limited per transiting planet) are explained. Unselected groups are not added back.',
        ),
      );
    }
    return copy.pick(
      '原内訳: 基準 ${copy.n(b['base'])}、補正前合計 ${copy.n(b['unclamped_adjustment'])}、上限後補正 ${copy.n(b['adjustment'])}、丸め前 ${copy.n(b['raw_score'])} → ${p.score}点。',
      'Recorded trace: base ${copy.n(b['base'])}, adjustment before limits ${copy.n(b['unclamped_adjustment'])}, applied adjustment ${copy.n(b['adjustment'])}, unrounded score ${copy.n(b['raw_score'])} → ${p.score}.',
    );
  }

  static ForecastExplanationResult _finish({
    required NineAreaKey key,
    required int? score,
    required String? feltLabel,
    required String title,
    required String conclusion,
    required String basis,
    required String modelVersion,
    required String status,
    required _ForecastExplanationMaterials materials,
    required List<String> limitations,
    required ReadingDepth depth,
    required UserProfileDetails? supplement,
    required _ForecastExplanationCopy copy,
    String? displayNarrative,
  }) {
    final background = _ForecastExplanationBackground.read(supplement);
    var advice = copy.advice(key);
    if (background.video &&
        {
          NineAreaKey.work,
          NineAreaKey.actionDecision,
          NineAreaKey.overall,
        }.contains(key)) {
      advice = copy.pick(
        '動画制作なら、短い下書きか編集確認を一つ選びましょう。再生数や収益は予測していません。',
        'For making videos, choose one small draft or editing check. This does not predict views or income.',
      );
    } else if (background.study &&
        {
          NineAreaKey.work,
          NineAreaKey.mental,
          NineAreaKey.actionDecision,
          NineAreaKey.overall,
        }.contains(key)) {
      advice = copy.pick(
        '学習なら、一つの小さな範囲を復習し、理解を確かめましょう。合格や成果の保証ではありません。',
        'For studying, review one small topic and check your understanding. This does not guarantee results or passing an exam.',
      );
    }
    if (background.brief) {
      if (background.video &&
          {
            NineAreaKey.work,
            NineAreaKey.actionDecision,
            NineAreaKey.overall,
          }.contains(key)) {
        advice = copy.pick(
          '動画制作は短い下書き一つから。再生数や収益の予測ではありません。',
          'Start with one small video draft. Views and income are not predicted.',
        );
      } else if (background.study &&
          {
            NineAreaKey.work,
            NineAreaKey.mental,
            NineAreaKey.actionDecision,
            NineAreaKey.overall,
          }.contains(key)) {
        advice = copy.pick(
          '学習は一つの範囲を復習して確認を。合格の保証ではありません。',
          'Review and check one study topic. Passing is not guaranteed.',
        );
      } else {
        advice = copy.shortAdvice(key);
      }
    }
    if (background.rest) {
      advice = copy.pick(
        '休むことを優先し、必要な確認を一つだけに絞ってください。予定を増やす必要はありません。',
        'Prioritize rest and limit yourself to one essential check. There is no need to add more plans.',
      );
    }
    if (background.noCareerChange &&
        {
          NineAreaKey.work,
          NineAreaKey.actionDecision,
          NineAreaKey.overall,
        }.contains(key)) {
      advice += copy.pick(
        ' 転職を勧めず、現在の範囲でできる調整にとどめます。',
        ' Keep adjustments within your current situation; changing jobs is not advised here.',
      );
    }
    if (background.polite) {
      advice = copy.pick(
        '無理のない範囲で大丈夫です。$advice',
        'At a pace that feels manageable, $advice',
      );
    }
    if (background.detailed) {
      advice += copy.pick(
        ' 実行後は実際の負担と進み具合を確かめ、必要なら予定を小さく調整しましょう。',
        ' Afterwards, check actual strain and progress and make a small adjustment if needed.',
      );
    }
    final interpretation =
        copy.meaning(key) +
        (materials.positive.isNotEmpty && materials.negative.isNotEmpty
            ? copy.pick(
                ' 調和と緊張が併存します。差が小さくても、材料がない日とは限りません。',
                ' Support and tension coexist. A small net difference does not mean nothing is happening.',
              )
            : '');
    limitations.add(
      copy.pick(
        '試作・未検証。点数や候補ラベルは実際の成果・体調・満足感を保証しません。',
        'Experimental and unvalidated. Scores and candidate labels do not guarantee results, health or satisfaction.',
      ),
    );
    return ForecastExplanationResult._(
      key: key,
      score: score,
      feltLabel: feltLabel,
      title: title,
      conclusion: conclusion,
      basis: basis,
      modelVersion: modelVersion,
      status: status,
      interpretation: interpretation,
      advice: advice,
      positiveMaterials: List.unmodifiable(materials.positive),
      negativeMaterials: List.unmodifiable(materials.negative),
      neutralMaterials: List.unmodifiable(materials.neutral),
      limitations: List.unmodifiable(limitations.toSet()),
      supplementEffects: List.unmodifiable(background.effects),
      depth: depth,
      language: copy.strings.language,
      displayNarrative: displayNarrative,
    );
  }
}

class ForecastExplanationResult {
  const ForecastExplanationResult._({
    required this.key,
    required this.score,
    required this.feltLabel,
    required this.title,
    required this.conclusion,
    required this.basis,
    required this.modelVersion,
    required this.status,
    required this.interpretation,
    required this.advice,
    required this.positiveMaterials,
    required this.negativeMaterials,
    required this.neutralMaterials,
    required this.limitations,
    required this.supplementEffects,
    required this.depth,
    required this.language,
    this.displayNarrative,
  });
  final NineAreaKey key;
  final int? score;
  final String? feltLabel;
  final String title,
      conclusion,
      basis,
      modelVersion,
      status,
      interpretation,
      advice;
  final List<String> positiveMaterials,
      negativeMaterials,
      neutralMaterials,
      limitations,
      supplementEffects;
  final ReadingDepth depth;
  final AppLanguage language;

  /// Reading prose only. Canonical text, JSON and the evidence ledger keep
  /// their original values and arithmetic.
  final String? displayNarrative;

  /// Detailed cards show the reading; arithmetic and full trace prose remain
  /// available through [numericLedgerText]. Stored [text] and [toJson] do not
  /// serialize the replacement card narrative.
  String get narrativeText {
    if (displayNarrative != null) return displayNarrative!;
    if (depth == ReadingDepth.simple)
      return text.split('\n').skip(1).join('\n');
    final en = language == AppLanguage.en;
    String prose(String row) => row.replaceFirst(
      RegExp(r':\s*(?:(?:活動刺激|activity stimulus)\s*)?[+-]?\d+(?:\.\d+)?\s*$'),
      '',
    );
    String section(String ja, String english, List<String> rows) =>
        '${en ? english : ja}: ${rows.isEmpty ? (en ? 'No verified selected material supplied' : '確認できる選択済み材料は未提供') : rows.map(prose).join(' / ')}';
    return [
      conclusion,
      interpretation,
      section('正の材料', 'Support materials', positiveMaterials),
      section('負の材料', 'Tension materials', negativeMaterials),
      section('活動・中立の材料', 'Activity / neutral materials', neutralMaterials),
      advice,
      ...limitations,
    ].join('\n\n');
  }

  /// The click-open arithmetic ledger; categorical felt is never a score.
  String get numericLedgerText {
    final en = language == AppLanguage.en;
    String section(String ja, String english, List<String> rows) =>
        '${en ? english : ja}: ${rows.isEmpty ? (en ? 'No verified selected material supplied' : '確認できる選択済み材料は未提供') : rows.join(' / ')}';
    return [
      title,
      basis,
      section('正の材料', 'Support materials', positiveMaterials),
      section('負の材料', 'Tension materials', negativeMaterials),
      section('活動・中立の材料', 'Activity / neutral materials', neutralMaterials),
      ...limitations,
      'Model: $modelVersion · $status',
    ].join('\n\n');
  }

  String get text {
    final en = language == AppLanguage.en;
    if (depth == ReadingDepth.simple) {
      final firstSentence = conclusion
          .split(RegExp(r'(?<=[。.!?])\s*\n|(?<=[.!?])\s+|(?<=。)'))
          .first;
      return '$title\n$firstSentence\n$advice\n${en ? 'Experimental and unvalidated.' : '試作・未検証です。'}';
    }
    String section(String ja, String english, List<String> rows) =>
        '${en ? english : ja}: ${rows.isEmpty ? (en ? 'No verified selected material supplied' : '確認できる選択済み材料は未提供') : rows.join(' / ')}';
    return [
      title,
      conclusion,
      basis,
      section('正の材料', 'Support materials', positiveMaterials),
      section('負の材料', 'Tension materials', negativeMaterials),
      section('活動・中立の材料', 'Activity / neutral materials', neutralMaterials),
      interpretation,
      advice,
      ...limitations,
      'Model: $modelVersion · $status',
    ].join('\n\n');
  }

  /// A separate explanation attachment. It never replaces canonical JSON fields.
  Map<String, Object?> toJson() => {
    'schema': 'pancyo_forecast_explanation_v1',
    'role': 'presentation_only',
    'key': key.name,
    'score': score,
    'felt_label': feltLabel,
    'model_version': modelVersion,
    'status': status,
    'language': language.name,
    'depth': depth.name,
    'title': title,
    'conclusion': conclusion,
    'basis': basis,
    'positive_materials': positiveMaterials,
    'negative_materials': negativeMaterials,
    'neutral_materials': neutralMaterials,
    'interpretation': interpretation,
    'advice': advice,
    'limitations': limitations,
    'supplement_effects': supplementEffects,
    'supplement_used_for_scoring': false,
    'additional_score_correction': 0,
  };
}

class _ForecastExplanationMaterials {
  final positive = <String>[], negative = <String>[], neutral = <String>[];
  void addNumeric(
    Map row,
    NineAreaKey key,
    _ForecastExplanationCopy copy,
    Object? trace,
  ) {
    final value = row['value'];
    if (value is! num || !value.isFinite) return;
    final label = copy.factor(row);
    String factor(String idKey) {
      if (trace is! Map ||
          trace['groups'] is! List ||
          trace['factors'] is! List)
        return label;
      final groups = (trace['groups'] as List).whereType<Map>().where(
        (g) =>
            g['selected'] == true &&
            g['transit_planet'] == row['transit_planet'],
      );
      if (groups.length != 1) return label;
      final id = groups.single[idKey];
      final factors = (trace['factors'] as List).whereType<Map>().where(
        (f) => id != null && f['id'] == id,
      );
      return factors.length == 1 ? copy.factor(factors.single) : label;
    }

    if (key == NineAreaKey.actionDecision) {
      neutral.add(
        '${factor('stimulus_factor_id')}: ${copy.pick('活動刺激', 'activity stimulus')} ${copy.n(value)}',
      );
    } else if (row['support'] is num && row['tension'] is num) {
      final support = row['support'] as num, tension = row['tension'] as num;
      if (support.isFinite && support > 0)
        positive.add('${factor('positive_factor_id')}: ${copy.n(support)}');
      if (tension.isFinite && tension > 0)
        negative.add('${factor('negative_factor_id')}: ${copy.n(tension)}');
      if (support == 0 && tension == 0) neutral.add('$label: ${copy.n(value)}');
    } else if (value > 0) {
      positive.add('$label: +${copy.n(value)}');
    } else if (value < 0) {
      negative.add('$label: ${copy.n(value)}');
    } else {
      neutral.add('$label: 0');
    }
  }

  void addFelt(Map row, _ForecastExplanationCopy copy) {
    final value = row['signed_value'];
    if (value is! num || !value.isFinite) return;
    final label = '${copy.factor(row)}: ${copy.n(value)}';
    if (value > 0)
      positive.add(label);
    else if (value < 0)
      negative.add(label);
    else
      neutral.add(label);
  }
}

class _ForecastExplanationBackground {
  bool video = false, study = false, rest = false, noCareerChange = false;
  bool brief = false, detailed = false, polite = false;
  final effects = <String>[];
  static _ForecastExplanationBackground read(UserProfileDetails? details) {
    final result = _ForecastExplanationBackground();
    if (details == null || !details.useSupplement) return result;
    // Never read stored* getters, birth inputs, names, or arbitrary instructions.
    final fields = [
      details.personality,
      details.concerns,
      details.readingStyle,
    ];
    final clauses = fields
        .expand((v) => v.toLowerCase().split(RegExp(r'[。.!！?？\n;；、,]')))
        .toList();
    bool positiveTopic(RegExp topic) => clauses.any(
      (c) =>
          topic.hasMatch(c) &&
          !RegExp(
            r'ではない|ではなく|じゃない|しない|したくない|興味がない|趣味でない|やめた|していない|not\b|don.t\b|never\b|no longer',
          ).hasMatch(c),
    );
    result.video = positiveTopic(RegExp(r'動画|video|filmmaking'));
    result.study = positiveTopic(RegExp(r'勉強|学習|study|studying|learning'));
    final all = fields.join('\n').toLowerCase();
    result.rest = clauses.any(
      (c) =>
          RegExp(
            r'休む.{0,8}優先|休息.{0,8}優先|無理.{0,4}できない|prioriti[sz]e rest|need to rest|limited energy',
          ).hasMatch(c) &&
          !RegExp(
            r'優先しない|優先したくない|休みたくない|not.{0,20}rest|don.t.{0,20}rest',
          ).hasMatch(c),
    );
    result.noCareerChange = RegExp(
      r'転職.{0,8}(考えていない|考えない|しない|したくない|希望しない)|not.{0,20}(chang.{0,4} jobs|job change)|don.t.{0,20}(chang.{0,4} jobs|job change)',
    ).hasMatch(all);
    final style = details.readingStyle.toLowerCase();
    result.brief =
        !RegExp(r'短くしない|簡潔にしない|not.{0,10}(brief|concise)').hasMatch(style) &&
        RegExp(r'短く|簡潔|brief|concise').hasMatch(style);
    result.detailed =
        !result.brief &&
        !RegExp(r'詳しくしない|詳細にしない|not.{0,10}detail').hasMatch(style) &&
        RegExp(r'詳しく|詳細|理由も|detail|explain why').hasMatch(style);
    result.polite = RegExp(
      r'丁寧|やさしく|優しく|polite|gentle|supportive',
    ).hasMatch(details.readingStyle.toLowerCase());
    for (final entry in {
      'video_example': result.video,
      'study_example': result.study,
      'rest_constraint': result.rest,
      'no_career_change': result.noCareerChange,
      'brief_style': result.brief,
      'detailed_style': result.detailed,
      'gentle_style': result.polite,
    }.entries) {
      if (entry.value) result.effects.add(entry.key);
    }
    return result;
  }
}

/// A display-only view of a recorded, selected aspect. No geometry is inferred.
class _ForecastAspectFact {
  const _ForecastAspectFact(
    this.transit,
    this.natal,
    this.type,
    this.orb,
    this.strength,
    this.area,
    this.role,
  );
  final String transit, natal, type, role;
  final double orb, strength;
  final NineAreaKey area;
  String get identity => '$transit/$natal/$type';
}

class _ForecastAspectEvidence {
  const _ForecastAspectEvidence._();
  static const planets = {
    'sun',
    'moon',
    'mercury',
    'venus',
    'mars',
    'jupiter',
    'saturn',
    'uranus',
    'neptune',
    'pluto',
  };
  static const angles = {
    'conjunction': 0,
    'sextile': 60,
    'square': 90,
    'trine': 120,
    'opposition': 180,
  };
  static int direction(String type) => switch (type) {
    'sextile' || 'trine' => 1,
    'square' || 'opposition' => -1,
    _ => 0,
  };
  static bool near(Object? a, Object? b) =>
      a is num &&
      b is num &&
      a.isFinite &&
      b.isFinite &&
      (a - b).abs() < 0.0000001;

  static _ForecastAspectFact? _fact(
    Map row,
    NineAreaKey area,
    String role, {
    bool reference = false,
  }) {
    final transit = row['transit_planet'],
        natal = row[reference ? 'natal_point' : 'natal_planet'];
    final type = row['aspect_type'], orb = row['orb_degrees'];
    final strength = reference ? 0.0 : row['strength'];
    if (transit is! String ||
        !planets.contains(transit) ||
        natal is! String ||
        !(reference ? {...planets, 'ascendant', 'midheaven'} : planets)
            .contains(natal) ||
        type is! String ||
        !angles.containsKey(type) ||
        orb is! num ||
        !orb.isFinite ||
        orb < 0 ||
        (reference ? orb > 8 : orb >= 4) ||
        strength is! num ||
        !strength.isFinite ||
        strength < 0)
      return null;
    return _ForecastAspectFact(
      transit,
      natal,
      type,
      orb.toDouble(),
      strength.toDouble(),
      area,
      role,
    );
  }

  static List<_ForecastAspectFact> read(
    NineAreaPrediction prediction, {
    List<NineAreaPrediction> related = const [],
  }) {
    if (prediction.key == NineAreaKey.felt) {
      final trace = prediction.feltForecast?.trace;
      if (trace == null) return [];
      try {
        FeltForecastCandidate.validateSnapshot(
          trace,
          prediction.feltForecast?.label,
        );
      } on FormatException {
        return [];
      }
      final rows = trace['selected_aspects'];
      if (rows is! List) return [];
      return [
        for (final row in rows.whereType<Map>())
          if (_fact(row, prediction.key, _role(row['aspect_type']))
              case final fact?)
            fact,
      ];
    }
    final b = prediction.scoreBreakdown;
    if (b == null || prediction.score == null) return [];
    try {
      NineAreaScoreAudit.validate(b, prediction.score!);
    } on FormatException {
      return [];
    }
    final trace = b['design_trace'];
    if (b['calculation_kind'] == 'general_six_area_mean_v1') {
      if (trace is! Map ||
          trace['source_area_scores'] is! Map ||
          trace['formula'] !=
              'mean_of_six_clamped_continuous_outcome_scores_then_round_once' ||
          related.length != 9 ||
          related.map((p) => p.key).toSet().length != 9)
        return [];
      final source = trace['source_area_scores'] as Map;
      const keys = {
        NineAreaKey.love,
        NineAreaKey.work,
        NineAreaKey.money,
        NineAreaKey.mental,
        NineAreaKey.health,
        NineAreaKey.people,
      };
      if (source.length != keys.length) return [];
      if (!keys.every(
            (key) =>
                source[key.name] is num && (source[key.name] as num).isFinite,
          ) ||
          !near(
            b['base'],
            keys.fold(0.0, (sum, key) => sum + (source[key.name] as num)) /
                keys.length,
          ))
        return [];
      final facts = <_ForecastAspectFact>[];
      for (final key in keys) {
        final p = related.singleWhere((p) => p.key == key);
        if (!near(source[key.name], p.scoreBreakdown?['raw_score'])) return [];
        facts.addAll(read(p));
      }
      return facts;
    }
    if (b['calculation_kind'] == 'general_outcome_groups_v1' ||
        b['calculation_kind'] == 'general_activity_groups_v1') {
      if (trace is! Map ||
          trace['groups'] is! List ||
          trace['factors'] is! List ||
          trace['receiver_weights'] is! Map)
        return [];
      final activity = prediction.key == NineAreaKey.actionDecision;
      if (trace['interpretation'] !=
          (activity ? 'activity_not_success' : 'outcome_direction_hypothesis'))
        return [];
      final result = <_ForecastAspectFact>[];
      final recorded = (b['factors'] as List).whereType<Map>().toList();
      final weights = trace['receiver_weights'] as Map;
      for (final group in (trace['groups'] as List).whereType<Map>()) {
        if (group['selected'] != true || group['member_factor_ids'] is! List)
          continue;
        final rows = recorded
            .where(
              (row) =>
                  row['kind'] == 'normalized_transit_group' &&
                  row['transit_planet'] == group['transit_planet'],
            )
            .toList();
        if (rows.length != 1 ||
            ![
              'support',
              'tension',
              'stimulus',
            ].every((key) => near(rows.single[key], group[key])))
          continue;
        final fields = activity
            ? ['stimulus_factor_id']
            : ['positive_factor_id', 'negative_factor_id'];
        for (final field in fields) {
          final id = group[field];
          if (id is! String ||
              !(group['member_factor_ids'] as List).contains(id))
            continue;
          final aspects = (trace['factors'] as List)
              .whereType<Map>()
              .where((row) => row['id'] == id)
              .toList();
          if (aspects.length != 1) continue;
          final row = aspects.single;
          final role = activity
              ? 'activity'
              : field == 'positive_factor_id'
              ? 'support'
              : 'tension';
          final fact = _fact(row, prediction.key, role);
          if (fact == null ||
              fact.transit != group['transit_planet'] ||
              id != fact.identity ||
              row['direction'] != direction(fact.type) ||
              (!activity &&
                  direction(fact.type) != (role == 'support' ? 1 : -1)) ||
              !near(row['receiver_weight'], weights[fact.natal]) ||
              row['receiver_weight'] is! num ||
              !near(
                fact.strength,
                (1 - fact.orb / 4) * (row['receiver_weight'] as num),
              ) ||
              !near(
                fact.strength,
                group[activity
                    ? 'stimulus'
                    : role == 'support'
                    ? 'support'
                    : 'tension'],
              ))
            continue;
          result.add(fact);
        }
      }
      return result;
    }
    // Older structured aspect rows can be described, but labels alone cannot
    // establish a planet pair, an angle, or selection status.
    return [
      for (final row in (b['factors'] as List).whereType<Map>())
        if (row['kind'] == 'transit_natal_aspect' &&
            row['value'] is num &&
            (row['value'] as num).isFinite &&
            (row['value'] as num) != 0)
          if (_fact(
                row,
                prediction.key,
                prediction.key == NineAreaKey.actionDecision
                    ? 'activity'
                    : (row['value'] as num) > 0
                    ? 'support'
                    : 'tension',
              )
              case final fact?)
            fact,
    ];
  }

  static String _role(Object? type) => type is String && direction(type) > 0
      ? 'support'
      : type is String && direction(type) < 0
      ? 'tension'
      : 'neutral';

  static List<_ForecastAspectFact> representatives(
    List<_ForecastAspectFact> facts, {
    required int limit,
  }) {
    final ordered = [...facts]
      ..sort((a, b) => b.strength.compareTo(a.strength));
    final selected = <_ForecastAspectFact>[];
    final seen = <String>{};
    for (final role in ['support', 'tension', 'activity', 'neutral']) {
      for (final fact in ordered) {
        if (fact.role == role && seen.add(fact.identity)) {
          selected.add(fact);
          break;
        }
      }
      if (selected.length == limit) return selected;
    }
    for (final fact in ordered) {
      if (seen.add(fact.identity)) selected.add(fact);
      if (selected.length == limit) break;
    }
    return selected;
  }

  static _ForecastAspectFact? reference(Map<String, Object?>? context) {
    if (context == null ||
        context['context_version'] != 'slow-transit-context-20261003-1' ||
        context['status'] != 'configuration_only_unvalidated' ||
        context['score_effect'] != 0 ||
        context['predicts_felt_label'] != false ||
        context['reference'] !=
            'provided_transit_positions_against_natal_chart' ||
        context['aspects'] is! List)
      return null;
    final facts = <_ForecastAspectFact>[];
    for (final row in (context['aspects'] as List).whereType<Map>()) {
      if (!{
        'jupiter',
        'saturn',
        'uranus',
        'neptune',
        'pluto',
      }.contains(row['transit_planet']))
        continue;
      final fact = _fact(row, NineAreaKey.felt, 'reference', reference: true);
      if (fact != null) facts.add(fact);
    }
    facts.sort((a, b) => a.orb.compareTo(b.orb));
    return facts.isEmpty ? null : facts.first;
  }
}

class _ForecastExplanationCopy {
  const _ForecastExplanationCopy(this.strings);
  final AppStrings strings;
  String pick(String ja, String en) =>
      strings.language == AppLanguage.en ? en : ja;
  String n(Object? value) => value is num && value.isFinite
      ? value.toStringAsFixed(2)
      : pick('不明', 'unknown');

  String get noAspectDetail => pick(
    '読み解ける採用済みアスペクトが記録されていないため、星の組合せは特定できません。',
    'No usable selected aspect was recorded, so a specific planetary interaction cannot be identified.',
  );

  String _planet(String id) => pick(
    const {
      'sun': '太陽',
      'moon': '月',
      'mercury': '水星',
      'venus': '金星',
      'mars': '火星',
      'jupiter': '木星',
      'saturn': '土星',
      'uranus': '天王星',
      'neptune': '海王星',
      'pluto': '冥王星',
      'ascendant': 'ASC',
      'midheaven': 'MC',
    }[id]!,
    const {
      'sun': 'Sun',
      'moon': 'Moon',
      'mercury': 'Mercury',
      'venus': 'Venus',
      'mars': 'Mars',
      'jupiter': 'Jupiter',
      'saturn': 'Saturn',
      'uranus': 'Uranus',
      'neptune': 'Neptune',
      'pluto': 'Pluto',
      'ascendant': 'Ascendant',
      'midheaven': 'Midheaven',
    }[id]!,
  );

  String _planetTheme(String id) => pick(
    const {
      'sun': '目的・自己表現',
      'moon': '感情・日々の反応',
      'mercury': '思考・伝達',
      'venus': '好意・価値観',
      'mars': '行動意欲・熱量',
      'jupiter': '拡大・学び',
      'saturn': '責任・制約',
      'uranus': '変化・自立',
      'neptune': '想像力・曖昧さ',
      'pluto': '集中・深い変化',
      'ascendant': '第一印象・始め方',
      'midheaven': '社会的役割・方向性',
    }[id]!,
    const {
      'sun': 'purpose and self-expression',
      'moon': 'feelings and everyday reactions',
      'mercury': 'thought and communication',
      'venus': 'affection and values',
      'mars': 'initiative and intensity',
      'jupiter': 'expansion and learning',
      'saturn': 'responsibility and limits',
      'uranus': 'change and independence',
      'neptune': 'imagination and ambiguity',
      'pluto': 'focus and deep change',
      'ascendant': 'first impressions and beginnings',
      'midheaven': 'social roles and direction',
    }[id]!,
  );

  String aspectReading(_ForecastAspectFact fact, NineAreaKey displayed) {
    final name = pick(
      const {
        'conjunction': 'コンジャンクション',
        'sextile': 'セクスタイル',
        'square': 'スクエア',
        'trine': 'トライン',
        'opposition': 'オポジション',
      }[fact.type]!,
      fact.type,
    );
    final angle = _ForecastAspectEvidence.angles[fact.type]!;
    final role = fact.role == 'reference'
        ? pick(
            '参考配置（体感判定へは未加算）',
            'Reference placement (not added to the felt label)',
          )
        : fact.role == 'neutral'
        ? pick(
            '採用配置（調和・緊張の加減算なし）',
            'Selected neutral placement (no harmony or tension contribution)',
          )
        : pick(
            fact.role == 'activity'
                ? '採用された活動刺激の例'
                : fact.role == 'support'
                ? '採用された調和材料の例'
                : '採用された緊張材料の例',
            fact.role == 'activity'
                ? 'Selected activity stimulus'
                : fact.role == 'support'
                ? 'Selected supportive factor'
                : 'Selected tension factor',
          );
    final source = displayed == NineAreaKey.overall
        ? pick(
            '総合を構成する${strings.nineAreaTitle(fact.area.name)}の$role',
            '$role within ${strings.nineAreaTitle(fact.area.name)}, a component of the overall mean',
          )
        : role;
    final relation = pick(
      const {
        'conjunction': '重なり',
        'sextile': '協力の糸口',
        'square': 'ぶつかりと調整',
        'trine': '自然な連携',
        'opposition': '異なる要求のすり合わせ',
      }[fact.type]!,
      const {
        'conjunction': 'combine',
        'sextile': 'can find ways to cooperate',
        'square': 'call for adjustment',
        'trine': 'can flow together',
        'opposition': 'call for balance between competing needs',
      }[fact.type]!,
    );
    final focus = pick(
      const {
        NineAreaKey.overall: '日々の優先順位',
        NineAreaKey.love: '好意の伝え方や距離感',
        NineAreaKey.work: '目標と進め方のすり合わせ',
        NineAreaKey.money: '必要な支出と価値観の見直し',
        NineAreaKey.mental: '気持ちの負担と集中の配分',
        NineAreaKey.health: '活動と休息の配分',
        NineAreaKey.people: '伝え方や役割分担',
        NineAreaKey.actionDecision: '動きたい気持ちの扱い方',
        NineAreaKey.felt: '心地よさと刺激の受け止め方',
      }[fact.area]!,
      const {
        NineAreaKey.overall: 'everyday priorities',
        NineAreaKey.love:
            'expressing affection and setting a comfortable distance',
        NineAreaKey.work: 'aligning goals with the way work is done',
        NineAreaKey.money: 'reviewing necessary spending and personal values',
        NineAreaKey.mental: 'balancing emotional demands and concentration',
        NineAreaKey.health: 'balancing activity and rest',
        NineAreaKey.people: 'communication and shared responsibilities',
        NineAreaKey.actionDecision: 'handling the urge to act',
        NineAreaKey.felt: 'how comfort and stimulation are experienced',
      }[fact.area]!,
    );
    final interpretation = pick(
      '${_planetTheme(fact.transit)}と${_planetTheme(fact.natal)}の「$relation」という象徴から、$focusを読む配置です。',
      'Symbolically, ${_planetTheme(fact.transit)} and ${_planetTheme(fact.natal)} $relation, a theme for $focus.',
    );
    return pick(
      '$source：運行${_planet(fact.transit)}×出生${_planet(fact.natal)}の$name$angle°（オーブ${n(fact.orb)}°）。$interpretation',
      '$source: transiting ${_planet(fact.transit)} in $name with natal ${_planet(fact.natal)}, $angle° (orb ${n(fact.orb)}°). $interpretation',
    );
  }

  String monthName(int month) => pick(
    '$month月',
    const [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ][month - 1],
  );

  String displayOutlook(NineAreaKey key, int score, String scope) {
    final band = score >= (key == NineAreaKey.actionDecision ? 80 : 82)
        ? 2
        : score <= 65
        ? 0
        : 1;
    String choose(List<String> ja, List<String> en) => pick(ja[band], en[band]);
    final text = switch (key) {
      NineAreaKey.overall => choose(
        [
          '広げるより、今ある予定を整えることが鍵になる流れです。',
          '優先順位を絞り、一つずつ着実に進めたい流れです。',
          '温めていたことを、小さく行動に移したい流れです。',
        ],
        [
          'focus on adjusting existing plans before expanding them.',
          'choose clear priorities and make steady progress, one step at a time.',
          'take a small step on something you have been preparing.',
        ],
      ),
      NineAreaKey.love => choose(
        [
          '気持ちを急いで結論にせず、距離感を整えたい恋愛運です。',
          '近況や感謝を交わし、自然な会話を育てたい恋愛運です。',
          '素直な一言や気軽な誘いを、親しい相手に届けたい恋愛運です。',
        ],
        [
          'give feelings time and find a comfortable distance in close relationships.',
          'build a natural conversation through small updates and appreciation.',
          'share an honest word or a low-pressure invitation with someone close.',
        ],
      ),
      NineAreaKey.work => choose(
        [
          '仕事の整理と手直しに力を向けたい流れです。',
          '仕事の優先順位を決め、完成まで着実に進めたい流れです。',
          '考えを形にし、準備した仕事を外へ届けたい流れです。',
        ],
        [
          'put attention into organizing and revising work.',
          'set work priorities and follow each task through to completion.',
          'turn an idea into a concrete piece of work and share what is ready.',
        ],
      ),
      NineAreaKey.money => choose(
        [
          '支出を急がず、必要なものを選び直したい金運です。',
          '収支のバランスを整え、納得できる使い方を考えたい金運です。',
          '使い道を比較し、暮らしに役立つ選択を考えたい金運です。',
        ],
        [
          'review what you need before committing to spending.',
          'balance income and expenses and choose spending you can feel comfortable with.',
          'compare uses for your money and choose what supports everyday life.',
        ],
      ),
      NineAreaKey.mental => choose(
        [
          '気持ちを急かさず、刺激と予定を減らす余裕を持ちたい流れです。',
          '集中と休憩を切り替え、自分のペースを整えたい流れです。',
          '気持ちの余白を、興味のあることに少し向けたい流れです。',
        ],
        [
          'make room to reduce stimulation and commitments without rushing yourself.',
          'alternate focused work with breaks and settle into your own pace.',
          'give a little of your emotional breathing room to something that interests you.',
        ],
      ),
      NineAreaKey.health => choose(
        [
          '休息を先に確保し、身体の負担を減らしたい流れです。',
          '食事・睡眠・休憩のリズムを整えたい流れです。',
          '無理のない活動と休息を、バランスよく続けたい流れです。',
        ],
        [
          'reserve rest first and reduce physical strain.',
          'steady your rhythm of meals, sleep and breaks.',
          'balance manageable activity with regular rest.',
        ],
      ),
      NineAreaKey.people => choose(
        [
          'やり取りを急がず、行き違いをほどきたい対人運です。',
          '身近な人との連絡や感謝を、丁寧につなぎたい対人運です。',
          '相談や協力のきっかけを、一つ試したい対人運です。',
        ],
        [
          'slow down interactions and work through misunderstandings.',
          'maintain everyday contact and express appreciation to people around you.',
          'try one conversation or small opportunity to cooperate.',
        ],
      ),
      NineAreaKey.actionDecision => choose(
        [
          '活動性は控えめな流れです。着手を小さくし、準備の時間を活かして。',
          '活動性は中程度の流れです。目的を決めてから、動く順番を整えて。',
          '活動性は高めの流れです。動きたいことが増えたら、一度に抱えず順番に。',
        ],
        [
          'activity is relatively quiet. Start small and make use of preparation time.',
          'activity is moderate. Choose a purpose and put your actions in order.',
          'activity is relatively high. Take new actions in sequence instead of all at once.',
        ],
      ),
      NineAreaKey.felt => throw StateError(
        'Felt experience has no numeric outlook.',
      ),
    };
    final japanese = key == NineAreaKey.actionDecision
        ? '$scopeの$text'
        : scope == 'この時点'
        ? '$scopeでは、$text'
        : '$scopeは、$text';
    return pick(japanese, '$scope: $text');
  }

  String timingUse(NineAreaKey key, bool higher) => switch (key) {
    NineAreaKey.overall =>
      higher
          ? pick(
              '優先したいことを一つ選び、具体的な一歩を。',
              'Choose one priority and take a concrete first step.',
            )
          : pick(
              '大きな予定を重ねず、必要な調整から始めましょう。',
              'Avoid stacking major plans; begin with the adjustments that matter.',
            ),
    NineAreaKey.love =>
      higher
          ? pick(
              '相手の都合を確かめて、会話や気軽な誘いを。',
              'Check availability, then try a conversation or an easy invitation.',
            )
          : pick(
              '返事を急かさず、言葉と距離感を丁寧に選びましょう。',
              'Allow time for replies and choose your words and boundaries with care.',
            ),
    NineAreaKey.work =>
      higher
          ? pick(
              '準備した案の提出や相談を、一つ進めましょう。',
              'Submit or discuss one prepared piece of work.',
            )
          : pick(
              '締切に余裕を取り、確認と手直しの時間を確保して。',
              'Allow deadline buffers and reserve time for checks and revisions.',
            ),
    NineAreaKey.money =>
      higher
          ? pick(
              '予算内の候補を比較し、必要な使い道を選びましょう。',
              'Compare options within budget and choose what you need.',
            )
          : pick(
              '固定費や契約条件を見直し、大きな支出は急がずに。',
              'Review fixed costs and contract terms without rushing major spending.',
            ),
    NineAreaKey.mental =>
      higher
          ? pick(
              '集中しやすい作業を短く区切り、余白も楽しんで。',
              'Use short blocks for focused tasks and enjoy some breathing room.',
            )
          : pick(
              '刺激の多い予定を減らし、静かな休憩を取りましょう。',
              'Reduce demanding plans and make time for quiet breaks.',
            ),
    NineAreaKey.health =>
      higher
          ? pick(
              '体調に合う軽い日課を、休息と組み合わせましょう。',
              'Pair gentle routines that suit your condition with regular rest.',
            )
          : pick(
              '休憩を先に予定し、疲れに合わせて負荷を調整して。',
              'Schedule breaks first and adjust your load when tired.',
            ),
    NineAreaKey.people =>
      higher
          ? pick(
              '相談や声かけを試し、互いにできる範囲で協力を。',
              'Try a small request or conversation and cooperate within mutual limits.',
            )
          : pick(
              '役割と連絡方法を確かめ、思い込みを一つ減らして。',
              'Clarify roles and communication, and check an assumption.',
            ),
    NineAreaKey.actionDecision =>
      higher
          ? pick(
              '動きたいことを小さな試行へ分け、合間に確認を。',
              'Split the urge to act into small trials with checks in between.',
            )
          : pick(
              '必要な行動を絞り、下調べや準備を進めましょう。',
              'Narrow your essential actions and make progress on preparation.',
            ),
    NineAreaKey.felt => displayPlan(key),
  };

  String displayPlan(NineAreaKey key) => switch (key) {
    NineAreaKey.overall => pick(
      '進めることと整えることを分け、終わらせる時間まで見込んでおくと動きやすくなります。',
      'Separate action from review and leave enough time to finish what you start.',
    ),
    NineAreaKey.love => pick(
      '相手の反応を決めつけず、自分の気持ちも短い言葉で伝えて。無理のない距離を大切にしましょう。',
      'Leave room for the other person’s response and express your feelings simply. Keep a distance that feels comfortable to both of you.',
    ),
    NineAreaKey.work => pick(
      '作業・相談・仕上げの順番を見える形に。抱える仕事を絞り、区切りで進み具合を確かめましょう。',
      'Make the stages of work, discussion and finishing visible. Limit parallel tasks and check progress at each stage.',
    ),
    NineAreaKey.money => pick(
      '買う前に必要性と上限額を決めることが支えに。収入や利益を見込んで予算を広げず、手元の範囲で選んで。',
      'Set a need and a spending limit before buying. Stay within available funds rather than budgeting around hoped-for income or profit.',
    ),
    NineAreaKey.mental => pick(
      'やることを一つずつにし、気持ちが追いつかないときは立ち止まって。実際の集中力と疲れを目安にしましょう。',
      'Take one thing at a time and pause when you need to. Let actual focus and tiredness guide your pace.',
    ),
    NineAreaKey.health => pick(
      '予定より実際の体調を優先して。食事と睡眠を削らず、無理なく続くペースを選びましょう。',
      'Put your actual condition ahead of the schedule. Protect meals and sleep and choose a sustainable pace.',
    ),
    NineAreaKey.people => pick(
      '頼むことと引き受けることを明確に。短い確認を挟みながら、気持ちのよい協力関係を育てましょう。',
      'Be clear about requests and commitments. Use brief check-ins to build comfortable cooperation.',
    ),
    NineAreaKey.actionDecision => pick(
      '活動の多さと成果は分けて見ましょう。判断の正しさは、情報と実際の結果を確かめて評価して。',
      'Assess activity separately from results. Judge decisions by checking the information and what actually happens.',
    ),
    NineAreaKey.felt => pick(
      '楽しい気持ちと身体の疲れが同時にあることも。点数に置き換えず、実際の満足感と休みたい気持ちを大切にして。',
      'Enjoyment and physical tiredness can coexist. Keep this categorical and make room for both actual satisfaction and the need for rest.',
    ),
  };

  String feltOutlook(String label) => switch (label) {
    '最高' => pick(
      '楽しみたいことに目を向け、心が動く時間を味わって。予定は詰めすぎず、余韻も大切に。',
      'Make space for what you enjoy and appreciate moments that move you. Leave time to unwind too.',
    ),
    '良い' => pick(
      '身近な楽しみや気軽な交流を、無理のない範囲で取り入れたい流れです。',
      'Make room for simple pleasures or easy company at a manageable pace.',
    ),
    '普通' => pick(
      '特別な刺激を求めず、いつもの楽しみと落ち着く日課を大切にしたい流れです。',
      'Value familiar pleasures and settling routines without seeking extra stimulation.',
    ),
    '悪い' => pick(
      '気分が乗らないときは用事を減らし、落ち着ける場所や一人の時間を選んで。',
      'When things feel uninviting, lighten your plans and choose a quiet place or some time alone.',
    ),
    '最悪' => pick(
      '気持ちを無理に上向かせず、負担の少ない過ごし方を。大きな結論は急がず、安心できる時間を確保して。',
      'Do not force a positive mood. Keep demands light, allow time before major conclusions and make space to feel at ease.',
    ),
    _ => throw const FormatException('Unknown canonical felt label.'),
  };
  String get unavailable => pick(
    '必要な計算データが不足しているため未予測です。0点や普通で補完しません。',
    'Not predicted because required calculation data is unavailable. It is not filled in with zero or Normal.',
  );
  String get missingTrace => pick(
    '対応する星の計算根拠は未提供または検証不能です。材料の欠損を0と解釈しません。',
    'The corresponding astronomical trace is missing or cannot be verified. Missing material is not treated as zero.',
  );
  String factor(Map row) {
    if (strings.language == AppLanguage.ja && row['label'] is String)
      return row['label'] as String;
    const ja = {
      'sun': '太陽',
      'moon': '月',
      'mercury': '水星',
      'venus': '金星',
      'mars': '火星',
      'jupiter': '木星',
      'saturn': '土星',
      'uranus': '天王星',
      'neptune': '海王星',
      'pluto': '冥王星',
    };
    const aspects = {
      'conjunction': '合',
      'sextile': '60°の調和角',
      'square': '90°の緊張角',
      'trine': '120°の調和角',
      'opposition': '180°の緊張角',
    };
    String planet(Object? key) => strings.language == AppLanguage.ja
        ? ja[key] ?? '天体'
        : key is String
        ? key
        : 'Recorded factor';
    return [
      planet(row['transit_planet'] ?? row['planet']),
      if (row['natal_planet'] != null)
        '× ${pick('出生', 'natal')} ${planet(row['natal_planet'])}',
      if (row['aspect_type'] is String)
        pick(
          aspects[row['aspect_type']] ?? row['aspect_type'] as String,
          row['aspect_type'] as String,
        ),
      if (row['orb_degrees'] is num) '${n(row['orb_degrees'])}°',
    ].join(' ');
  }

  String meaning(NineAreaKey key) => switch (key) {
    NineAreaKey.overall => pick(
      '総合は分野の見通しです。幸福・達成・体感と同じ指標ではありません。',
      'Overall summarizes domain outlooks. It is not the same measure as happiness, achievement or felt experience.',
    ),
    NineAreaKey.love => pick(
      '親密な関係の見通しです。相手の本心や返信を確定するものではありません。',
      'This concerns intimacy, not certainty about another person’s feelings or replies.',
    ),
    NineAreaKey.work => pick(
      '仕事の成果・完成・進展を考える材料です。忙しさや活動量と分けます。',
      'This concerns results, completion and progress at work, separately from busyness or activity.',
    ),
    NineAreaKey.money => pick(
      '収支・使い方を考える材料です。利益や収入を保証しません。',
      'This concerns income, spending and money choices. It does not guarantee profit or income.',
    ),
    NineAreaKey.mental => pick(
      '気分・集中・心理的負荷の候補です。身体の状態と分けて確認します。',
      'This concerns mood, focus and mental load, separately from physical condition.',
    ),
    NineAreaKey.health => pick(
      '身体の負荷と休息を考える候補です。高得点でも健康を保証せず、実際の体調を優先します。',
      'This concerns physical strain and rest. A high score does not guarantee good health; prioritize your actual condition.',
    ),
    NineAreaKey.people => pick(
      '家族・友人・協力関係の見通しです。交流の回数や恋愛の点数ではありません。',
      'This concerns family, friends and cooperation, not contact counts or a romance score.',
    ),
    NineAreaKey.actionDecision => pick(
      '活動性を表します。調和・緊張・合の刺激を成功や判断の正しさに読み替えません。',
      'This describes activity. Harmonious, tense and conjunction stimulation is not a measure of success or correct decisions.',
    ),
    NineAreaKey.felt => pick(
      '本人が感じる日の良さの5段階候補です。身体の負担と満足感は併存でき、数値点とは別です。',
      'This is a five-label candidate for how positive a day may feel. Physical strain and satisfaction can coexist; it is separate from numeric scores.',
    ),
  };
  String annualUse(NineAreaKey key, bool higher) => switch (key) {
    NineAreaKey.overall =>
      higher
          ? pick(
              '優先する分野を一つ選び、他の分野との兼ね合いを確認しながら進めます。',
              'choose one priority and check the balance with other domains as you proceed.',
            )
          : pick(
              '複数の大きな予定を重ねず、分野ごとの条件を確認して調整します。',
              'avoid stacking major plans and review conditions in each domain.',
            ),
    NineAreaKey.love =>
      higher
          ? pick(
              '相手の都合を確かめて、負担の少ない対話を試します。',
              'check availability and try a low-pressure conversation.',
            )
          : pick(
              '返答を急がず、期待や距離感のすり合わせに時間を取ります。',
              'allow time to clarify expectations and boundaries without rushing a reply.',
            ),
    NineAreaKey.work =>
      higher
          ? pick(
              '準備した仕事を小さく提出・相談し、実際の進展を確かめます。',
              'submit or discuss a small prepared piece of work and check actual progress.',
            )
          : pick(
              '締切に余裕を取り、確認・修正工程を先に確保します。',
              'allow deadline buffers and reserve time for checks and revisions.',
            ),
    NineAreaKey.money =>
      higher
          ? pick(
              '予算内の選択肢を比較し、必要性を確認して使い方を整えます。利益を約束する時期ではありません。',
              'compare options within budget and review needs; this is not a promised profit window.',
            )
          : pick(
              '固定費・契約条件・予備費を確認し、大きな支出を急ぎません。',
              'review fixed costs, contract terms and reserves without rushing major spending.',
            ),
    NineAreaKey.mental =>
      higher
          ? pick(
              '実際に集中しやすい時間を見つけ、短い作業枠を活かします。',
              'find times when you actually feel focused and use short work blocks.',
            )
          : pick(
              '刺激や予定を減らす余地を残し、気持ちの負担を確認します。',
              'leave room to reduce stimulation or plans and check actual mental strain.',
            ),
    NineAreaKey.health =>
      higher
          ? pick(
              '実際の体調に合う日課を整え、無理に負荷を上げません。',
              'maintain routines that fit your actual condition without increasing strain unnecessarily.',
            )
          : pick(
              '休息と予定変更の余地を先に確保し、実際の症状への対応を優先します。',
              'reserve rest and flexibility and prioritize responding to actual symptoms.',
            ),
    NineAreaKey.people =>
      higher
          ? pick(
              '互いの余裕を確かめて、小さな相談や協力を試します。',
              'check mutual capacity and try a small request or collaboration.',
            )
          : pick(
              '役割や連絡方法を確認し、行き違いを減らす調整をします。',
              'clarify roles and communication to reduce misunderstandings.',
            ),
    NineAreaKey.actionDecision =>
      higher
          ? pick(
              '動きたい刺激を小さな試行へ分け、忙しさと成果を別に確認します。',
              'split the urge to act into small trials and assess busyness separately from results.',
            )
          : pick(
              '必要な行動を絞って準備を整えます。活動が少ないことを失敗とは扱いません。',
              'focus on essential actions and preparation; less activity is not failure.',
            ),
    NineAreaKey.felt => advice(key),
  };

  String advice(NineAreaKey key) => switch (key) {
    NineAreaKey.love || NineAreaKey.people => pick(
      '相手の都合を確かめ、負担の少ない連絡を一つ選びましょう。',
      'Check the other person’s availability and choose one low-pressure way to communicate.',
    ),
    NineAreaKey.money => pick(
      '必要性と予算を確認し、大きな支出は条件を比べてから判断しましょう。',
      'Check needs and budget; compare terms before deciding on a large expense.',
    ),
    NineAreaKey.health || NineAreaKey.mental || NineAreaKey.felt => pick(
      '実際の気持ちと体調を確認し、休む余裕を残しましょう。',
      'Check how you actually feel and leave room for rest.',
    ),
    _ => pick(
      '無理のない作業を一つ選び、途中と最後に確認しましょう。',
      'Choose one manageable task and check it during the work and at the end.',
    ),
  };
  String shortAdvice(NineAreaKey key) => switch (key) {
    NineAreaKey.love || NineAreaKey.people => pick(
      '相手の都合を確認し、短い連絡を。',
      'Check availability before a short message.',
    ),
    NineAreaKey.money => pick(
      '必要性と予算を確認してから判断を。',
      'Check needs and budget before deciding.',
    ),
    NineAreaKey.health || NineAreaKey.mental || NineAreaKey.felt => pick(
      '実際の体調と気持ちを優先し、休息を。',
      'Prioritize your actual condition and leave room for rest.',
    ),
    _ => pick('作業を一つ選び、最後に確認を。', 'Choose one task and check it at the end.'),
  };
}
