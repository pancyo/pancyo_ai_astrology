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
    );
  }

  /// [dailySamples] are already calculated forecasts indexed by JST date label.
  /// Missing traces stay unknown. This method never calculates another context.
  static ForecastExplanationResult forPeriod({
    required NineAreaPeriodSummary summary,
    required NineAreaPeriodEntry area,
    required AppStrings strings,
    ReadingDepth depth = ReadingDepth.simple,
    UserProfileDetails? supplement,
    Map<String, List<NineAreaPrediction>> dailySamples = const {},
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
          '${summary.displaySamplingText(strings)}. ${copy.pick('確認日点数', 'Sample scores')}: ${area.samples.join(', ')}. ${copy.pick('算術平均を最後に1回四捨五入', 'Arithmetic mean rounded once at the end')}: ${area.score}. ${copy.pick('期間ボーナスの追加なし。', 'No additional period bonus.')}';
    }
    if (dailySamples.isNotEmpty && !area.inherited) {
      for (final date in summary.dates) {
        final dateLabel = NineAreaPeriodSummary.dateLabel(date);
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
          '正負材料は各確認日の採用済み根拠です。件数を期間の成功確率や独立した出来事数へ換算しません。',
          'Materials are the selected factors at each sample. Their counts are not success probabilities or independent event counts.',
        ),
      );
    } else if (!area.inherited) {
      limitations.add(copy.missingTrace);
    }
    limitations.add(
      copy.pick(
        '期間の確認時点の集計です。週の全時刻、月・年の全日を計算した結果ではありません。',
        'This aggregates reference samples, not every hour of a week or every day of a month or year.',
      ),
    );
    return _finish(
      key: area.key,
      score: area.score,
      feltLabel: area.key == NineAreaKey.felt ? summary.feltLabel : null,
      title:
          '${NineAreaPeriodSummary.dateLabel(summary.dates.first)}–${NineAreaPeriodSummary.dateLabel(summary.dates.last)} JST · ${strings.nineAreaTitle(area.key.name)}',
      conclusion: summary.displayReading(area, strings),
      basis: basis,
      modelVersion: summary.useGeneralModel
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
      annualNarrative:
          summary.mode == LongRangeMode.year && depth == ReadingDepth.detailed
          ? _annualNarrative(summary, area, dailySamples, materials, copy)
          : null,
    );
  }

  /// Descriptive comparisons of the existing samples, never new period scores.
  /// A sub-point monthly spread is called small rather than manufacturing peaks.
  static String _annualNarrative(
    NineAreaPeriodSummary summary,
    NineAreaPeriodEntry area,
    Map<String, List<NineAreaPrediction>> dailySamples,
    _ForecastExplanationMaterials materials,
    _ForecastExplanationCopy copy,
  ) {
    final year = summary.dates.first.toUtc().add(const Duration(hours: 9)).year;
    String month(int m) => copy.pick(
      '$m月',
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
      ][m - 1],
    );
    String months(Iterable<int> values) =>
        values.map(month).join(copy.pick('・', ', '));
    final dates = summary.dates.map(NineAreaPeriodSummary.dateLabel).toList();
    final expected = [
      for (var m = 1; m <= 12; m++)
        for (final d in [1, 15])
          '$year-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}',
    ];
    if (dates.length != 24 ||
        !List.generate(24, (i) => dates[i] == expected[i]).every((v) => v)) {
      return copy.pick(
        '年の流れを比べる24標本がそろっていません。月の山や谷は推定しません。',
        'The 24 reference samples needed for a yearly comparison are unavailable. Monthly peaks or troughs are not inferred.',
      );
    }
    List<int> supportMonths = const [], cautionMonths = const [];
    final sections = <String>[
      copy.pick(
        '$year年の読み方：各月1日・15日、正午JSTの24標本から、一年の流れを比較します。月内の全日や出来事の発生時期を予測したものではありません。',
        'Reading $year: compare the year using 24 noon-JST samples, on the first and fifteenth of each month. These do not predict every day or the timing of events.',
      ),
    ];
    if (area.key == NineAreaKey.felt) {
      if (dailySamples.isEmpty) {
        sections.add(
          copy.pick(
            '年間のカテゴリ分布は既存集計に残りますが、日別ラベルが未提供のため月ごとの体感は不明です。年間の最多ラベルを全月へ割り当てません。',
            'The existing annual category distribution is retained, but monthly felt experience is unknown without the daily labels. The annual most-frequent label is not assigned to every month.',
          ),
        );
      } else {
        final rows = <String>[];
        final mixed = <int>[], missing = <int>[];
        for (var m = 1; m <= 12; m++) {
          final labels = [
            for (final i in [(m - 1) * 2, (m - 1) * 2 + 1])
              dailySamples[dates[i]]!
                  .singleWhere((p) => p.key == NineAreaKey.felt)
                  .feltForecast
                  ?.label,
          ];
          if (labels.contains(null)) missing.add(m);
          final known = labels.whereType<String>().toSet();
          if (known.length > 1) mixed.add(m);
          String label(String? v) => v == null
              ? copy.pick('未予測', 'Not predicted')
              : copy.strings.feltLabelText(v) ?? v;
          rows.add(
            '${month(m)}: ${labels.map(label).join(' / ')}${known.length > 1 ? copy.pick('（混在）', ' (Mixed)') : ''}',
          );
        }
        sections.add(
          copy.pick(
                '月ごとの体感候補（1日 / 15日）\n',
                'Monthly felt candidates (first / fifteenth)\n',
              ) +
              rows.join('\n'),
        );
        sections.add(
          [
            if (mixed.isNotEmpty)
              copy.pick(
                '${months(mixed)}は2標本のカテゴリが異なります。同じ月にも異なる感じ方があり、年間の最多カテゴリだけでは見えません。',
                '${months(mixed)} have different categories at the two samples. Different experiences can coexist within a month and are hidden by a single annual mode.',
              ),
            if (missing.isNotEmpty)
              copy.pick(
                '${months(missing)}には未予測があります。普通で補完せず、その時期の判断は保留します。',
                '${months(missing)} include unpredicted samples. They are not filled with Normal; judgement for those samples remains open.',
              ),
            copy.pick(
              'カテゴリを点数や月の順位へ換算しません。心地よく感じる候補でも予定を詰めず、負担を感じる時期は休息枠を残し、実際の気持ちを優先してください。',
              'Categories are not converted into scores or monthly rankings. Leave space even when a sample suggests a positive experience, reserve rest when strain is suggested, and prioritize how you actually feel.',
            ),
          ].join(' '),
        );
      }
    } else if (area.samples.length == 24) {
      // This unrounded two-sample comparison is display-only. The existing
      // annual mean/rounding, source samples and canonical JSON are untouched.
      final means = [
        for (var i = 0; i < 24; i += 2)
          (area.samples[i] + area.samples[i + 1]) / 2,
      ];
      final low = means.reduce(math.min), high = means.reduce(math.max);
      final changing = [
        for (var m = 1; m <= 12; m++)
          if (area.samples[(m - 1) * 2] != area.samples[(m - 1) * 2 + 1]) m,
      ];
      final highs = [
        for (var m = 1; m <= 12; m++)
          if (means[m - 1] == high) m,
      ];
      final lows = [
        for (var m = 1; m <= 12; m++)
          if (means[m - 1] == low) m,
      ];
      if (area.inherited)
        sections.add(
          copy.pick(
            '以下の月比較は日標本の補助的な見通しです。維持した従来の年間点の内訳や再計算ではありません。',
            'The following monthly comparison is supplementary daily-sample context. It is not the breakdown or a recalculation of the retained inherited annual score.',
          ),
        );
      if (high - low < 1) {
        sections.add(
          copy.pick(
            high == low
                ? '各月の2標本平均はすべて同率です。年内の優劣をつけず、特別な好機や慎重月を作りません。'
                : '各月の2標本平均の差は小さく、明確な山や谷とは扱いません。わずかな差だけで月の優劣を決めません。',
            high == low
                ? 'All monthly two-sample means are tied. No month is ranked above another, and special opportunities or caution months are not manufactured.'
                : 'The monthly two-sample means differ only slightly. They are not treated as distinct peaks or troughs, and tiny differences do not rank the months.',
          ),
        );
        sections.add(
          copy.pick(
            '時期の使い分け：月の順位に頼らず、実際の準備と余力を確かめながら小さく進め、定期的に見直します。',
            'Using the timing: work in small steps and review regularly according to actual readiness and capacity, rather than a monthly ranking.',
          ),
        );
      } else {
        supportMonths = highs;
        cautionMonths = lows;
        sections.add(
          copy.pick(
            '一年の傾向：年間平均だけでは月ごとの違いが隠れます。2標本平均で相対的に高いのは${months(highs)}、低めで確認を厚くしたいのは${months(lows)}です。複数月の同率はすべて併記します。これはこの年内の比較であり、幸運月・凶月や成果の保証ではありません。',
            'Yearly pattern: the annual mean hides differences between months. The relatively higher two-sample means are in ${months(highs)}; the lower means, where extra checks may help, are in ${months(lows)}. All tied months are listed. This compares months within this year; it does not identify lucky or unlucky months or guarantee results.',
          ),
        );
        sections.add(
          copy.pick(
            '時期の使い分け（実際の余力と本人の制約を優先）：${months(highs)}は${copy.annualUse(area.key, true)} ${months(lows)}は${copy.annualUse(area.key, false)}',
            'Using the timing, subject to actual capacity and personal constraints: in ${months(highs)}, ${copy.annualUse(area.key, true)} In ${months(lows)}, ${copy.annualUse(area.key, false)}',
          ),
        );
      }
      sections.add(
        copy.pick(
          changing.isEmpty
              ? '各月の1日と15日にも点差はありません。ただし未標本の日まで同じ状態とは限りません。'
              : '${months(changing)}は1日と15日で値が異なります。月平均や年間平均が同じでも月内の揺れは残るため、月全体を一つの調子と決めつけず、予定の前に実際の状況を確かめます。',
          changing.isEmpty
              ? 'The first and fifteenth also have equal values in each month. Unsampled days are not thereby assumed to be the same.'
              : '${months(changing)} differ between the first and fifteenth. Within-month variation remains even when monthly or annual means match; do not assume one constant condition throughout a month, and check actual circumstances before plans.',
        ),
      );
    } else {
      sections.add(copy.missingTrace);
    }
    String examples(List<String> rows, [List<int> preferredMonths = const []]) {
      final selected = <String>[];
      final identities = <String>{};
      int? recordedMonth(String row) {
        final date = RegExp(r'^\d{4}-(\d{2})-\d{2}:').firstMatch(row);
        return date == null ? null : int.parse(date.group(1)!);
      }

      final representatives = <String>[];
      for (final month in preferredMonths) {
        final matching = rows.where((row) => recordedMonth(row) == month);
        if (matching.isNotEmpty) representatives.add(matching.first);
        if (representatives.length == 2) break;
      }
      final ordered = [...representatives, ...rows];
      for (final row in ordered) {
        final prose = row.replaceFirst(
          RegExp(
            r':\s*(?:(?:活動刺激|activity stimulus)\s*)?[+-]?\d+(?:\.\d+)?\s*$',
          ),
          '',
        );
        final identity =
            prose
                .replaceFirst(RegExp(r'^\d{4}-\d{2}-\d{2}:\s*'), '')
                .replaceAll(RegExp(r'\s+\d+(?:\.\d+)?°'), '') +
            (preferredMonths.isEmpty ? '' : '/${recordedMonth(row)}');
        if (identities.add(identity)) selected.add(prose);
        if (selected.length == 2) break;
      }
      return selected.isEmpty
          ? copy.pick(
              '確認できる選択済み材料は未提供',
              'No verified selected material supplied',
            )
          : selected.join(' / ');
    }

    final representativeMonths = [
      if (supportMonths.isNotEmpty) supportMonths.first,
      if (cautionMonths.isNotEmpty) cautionMonths.first,
    ];
    sections.add(
      copy.pick(
        '正の材料（代表）：${examples(materials.positive, representativeMonths)}。調和の材料は進め方を考える参考で、出来事や成果の原因とは断定しません。\n負の材料（代表）：${examples(materials.negative, representativeMonths)}。緊張の材料は余裕・確認・調整を考える参考で、失敗の予告とは扱いません。',
        'Support materials (representative): ${examples(materials.positive, representativeMonths)}. Harmonious material helps consider an approach; it does not establish the cause of an event or result.\nTension materials (representative): ${examples(materials.negative, representativeMonths)}. Tension helps consider buffers, checks and adjustments; it is not a prediction of failure.',
      ),
    );
    if (representativeMonths.isNotEmpty)
      sections.add(
        copy.pick(
          '代表日は相対的に高い側・低い側の標本から選んでいます。月を正・負に分けるものではなく、同じ日に両方の材料がある場合も併記しています。',
          'Representative dates come from the relatively higher and lower samples. Months are not divided into positive and negative ones; both kinds of material are shown when present on the same date.',
        ),
      );
    final materialText = [
      ...materials.positive,
      ...materials.negative,
      ...materials.neutral,
    ].join('\n');
    final meanings = <String>[];
    for (final entry in const [
      (
        '木星',
        'jupiter',
        '木星の材料は広げ方・機会の検討として読み、利益や成功と同一視しません。',
        'Jupiter material concerns expansion and considering opportunities, not assured profit or success.',
      ),
      (
        '土星',
        'saturn',
        '土星の材料は制約・責任・積み直しとして読み、余裕や確認工程を考えます。',
        'Saturn material concerns limits, responsibility and rebuilding; consider buffers and checks.',
      ),
      (
        '火星',
        'mars',
        '火星の材料は動く勢いや摩擦として読み、活動量を成果と分けます。',
        'Mars material concerns momentum or friction; keep activity separate from results.',
      ),
      (
        '水星',
        'mercury',
        '水星の材料は連絡・情報・段取りとして読み、伝達内容の確認へつなげます。',
        'Mercury material concerns communication, information and planning; check what is conveyed.',
      ),
      (
        '金星',
        'venus',
        '金星の材料は関係や心地よさ・価値の選び方として読み、相手の意向は別に確かめます。',
        'Venus material concerns relationships, comfort and values; another person’s wishes still need checking.',
      ),
    ]) {
      if (materialText.contains(copy.pick(entry.$1, entry.$2)))
        meanings.add(copy.pick(entry.$3, entry.$4));
      if (meanings.length == 2) break;
    }
    if (meanings.isNotEmpty) sections.add(meanings.join(' '));
    if (area.key == NineAreaKey.actionDecision)
      sections.add(
        copy.pick(
          '活動・中立の材料（代表）：${examples(materials.neutral)}。相対的に高い時期も活動の刺激が多い候補であり、成功率や判断の正しさへ読み替えません。',
          'Activity / neutral materials (representative): ${examples(materials.neutral)}. Relatively higher periods suggest more activity stimulation, not success probability or correct decisions.',
        ),
      );
    sections.add(
      copy.pick(
        '正負の全材料・24標本・数値の内訳は項目のクリック内訳に保持しています。同じ配置の反復も含むため、材料数を独立した出来事数や的中率とは数えません。',
        'All support/tension materials, the 24 samples and arithmetic remain in the click-open ledger. Repeated configurations are included; material counts are not independent events or prediction accuracy.',
      ),
    );
    return sections.join('\n\n');
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
    final expected = summary.dates.map(NineAreaPeriodSummary.dateLabel).toSet();
    if (samples.length != expected.length ||
        !samples.keys.every(expected.contains)) {
      throw const FormatException('Period sample dates differ.');
    }
    final counts = {for (final label in FeltForecastCandidate.labels) label: 0};
    var missing = 0;
    for (var i = 0; i < summary.dates.length; i++) {
      final day = samples[NineAreaPeriodSummary.dateLabel(summary.dates[i])]!;
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
    String? annualNarrative,
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
      annualNarrative: annualNarrative,
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
    this.annualNarrative,
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

  /// Detailed annual display only; existing text/JSON/ledger stay unchanged.
  final String? annualNarrative;

  /// Card prose keeps the full interpretation and advice in detailed mode.
  /// Only the generated terminal contribution value is omitted from materials;
  /// dates, planet pairs, aspect angles and orbs remain evidence, not scores.
  /// Stored [text], raw materials and [toJson] are deliberately unchanged.
  String get narrativeText {
    if (depth == ReadingDepth.simple)
      return text.split('\n').skip(1).join('\n');
    if (annualNarrative != null) {
      return [
        conclusion,
        annualNarrative!,
        interpretation,
        advice,
        ...limitations
            .map((v) => v.replaceFirst(RegExp(r'^\d{4}-\d{2}-\d{2}:\s*'), ''))
            .toSet(),
      ].join('\n\n');
    }
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

class _ForecastExplanationCopy {
  const _ForecastExplanationCopy(this.strings);
  final AppStrings strings;
  String pick(String ja, String en) =>
      strings.language == AppLanguage.en ? en : ja;
  String n(Object? value) => value is num && value.isFinite
      ? value.toStringAsFixed(2)
      : pick('不明', 'unknown');
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
