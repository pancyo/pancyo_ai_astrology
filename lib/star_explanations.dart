part of 'main.dart';

String _planetNameEn(AstroPlanet planet) => switch (planet) {
  AstroPlanet.sun => 'Sun',
  AstroPlanet.moon => 'Moon',
  AstroPlanet.mercury => 'Mercury',
  AstroPlanet.venus => 'Venus',
  AstroPlanet.mars => 'Mars',
  AstroPlanet.jupiter => 'Jupiter',
  AstroPlanet.saturn => 'Saturn',
  AstroPlanet.uranus => 'Uranus',
  AstroPlanet.neptune => 'Neptune',
  AstroPlanet.pluto => 'Pluto',
  AstroPlanet.ascendant => 'Ascendant',
  AstroPlanet.midheaven => 'Midheaven',
};

String _signNameEn(ZodiacSign sign) => switch (sign) {
  ZodiacSign.aries => 'Aries',
  ZodiacSign.taurus => 'Taurus',
  ZodiacSign.gemini => 'Gemini',
  ZodiacSign.cancer => 'Cancer',
  ZodiacSign.leo => 'Leo',
  ZodiacSign.virgo => 'Virgo',
  ZodiacSign.libra => 'Libra',
  ZodiacSign.scorpio => 'Scorpio',
  ZodiacSign.sagittarius => 'Sagittarius',
  ZodiacSign.capricorn => 'Capricorn',
  ZodiacSign.aquarius => 'Aquarius',
  ZodiacSign.pisces => 'Pisces',
};

String _aspectNameEn(AspectType type) => switch (type) {
  AspectType.conjunction => 'conjunction',
  AspectType.sextile => 'sextile',
  AspectType.square => 'square',
  AspectType.trine => 'trine',
  AspectType.opposition => 'opposition',
};

String _phaseNameEn(AspectPhase phase) => switch (phase) {
  AspectPhase.applying => 'applying',
  AspectPhase.exact => 'exact',
  AspectPhase.separating => 'separating',
};

String _patternNameEn(String label) {
  var translated = switch (label) {
    'グランドトライン' => 'Grand trine',
    'カイト' => 'Kite',
    'グランドセクスタイル' => 'Grand sextile',
    'ミスティックレクタングル（ダイヤモンド）' => 'Mystic rectangle',
    'クレイドル（ゆりかご）' => 'Cradle',
    'Tスクエア' => 'T-square',
    'グランドクロス' => 'Grand cross',
    'ヨッド' => 'Yod',
    'ブーメラン（ヨッド）' => 'Boomerang Yod',
    'ハンマー・オブ・ソー' => 'Thor’s hammer',
    _ => label,
  };
  final planets = AstroPlanet.values.toList()
    ..sort((a, b) => b.label.length.compareTo(a.label.length));
  for (final planet in planets) {
    translated = translated.replaceAll(planet.label, _planetNameEn(planet));
  }
  return translated;
}

String _planetListEn(Iterable<AstroPlanet> planets) =>
    planets.map(_planetNameEn).join(', ');

/// Symbolic teaching copy, separate from selected scoring evidence.
/// The original design distinguishes stimulation, its nature and outcomes.
class StarMeaningGuide {
  const StarMeaningGuide(
    this.nature,
    this.constructive,
    this.pressure,
    this.practice,
  );
  final String nature;
  final String constructive;
  final String pressure;
  final String practice;

  static StarMeaningGuide forPlanet(AstroPlanet planet, AppLanguage language) {
    final en = language == AppLanguage.en;
    return switch (planet) {
      AstroPlanet.sun =>
        en
            ? const StarMeaningGuide(
                'Vitality, purpose and visibility; a strong Sun is not luck itself.',
                'Clarify a priority and take ownership.',
                'Pride, overexertion or pressure to be noticed can coexist.',
                'Choose one purpose, then check energy and the actual response separately.',
              )
            : const StarMeaningGuide(
                '生命力・目的・自己表現の象徴。強い太陽そのものが幸運ではありません。',
                '優先する目的を決め、自分の役割を引き受ける。',
                '自負・頑張りすぎ・注目への負担も同時に表れ得ます。',
                '目的を一つ選び、体力と実際の反応は別に確かめます。',
              ),
      AstroPlanet.moon =>
        en
            ? const StarMeaningGuide(
                'Emotion, bodily rhythm and immediate reaction; natal sensitivity differs from a date’s stimulus.',
                'Notice needs and make room for rest or care.',
                'Fluctuation, dependency or overstimulation may coexist.',
                'Read lunar aspects and timing, then observe actual feelings; a candidate label is not a diagnosis.',
              )
            : const StarMeaningGuide(
                '感情・身体のリズム・身近な反応の象徴。出生図の感受性と対象日の刺激は別です。',
                '必要な休息や安心に気づき、生活を整える。',
                '気分の揺れ・依存・刺激の多さも併存し得ます。',
                '月の角度と時刻を読み、実際の気分は別に確認します。候補ラベルは診断ではありません。',
              ),
      AstroPlanet.mercury =>
        en
            ? const StarMeaningGuide(
                'Traditionally mutable and neutral: thought, information, conversation, procedures and movement.',
                'Organize facts, communicate and revise a plan.',
                'Busyness, scattered attention, mistakes or repeated checking may increase.',
                'Separate how much you communicate or move from completion, recognition and success.',
              )
            : const StarMeaningGuide(
                '伝統的には中立で変化しやすい星。思考・情報・会話・手続き・移動の象徴です。',
                '情報を整理し、伝達や計画の見直しに使う。',
                '忙しさ・注意の分散・誤り・確認の往復も増え得ます。',
                '連絡や移動の量と、完了・評価・成功を分けて読みます。',
              ),
      AstroPlanet.venus =>
        en
            ? const StarMeaningGuide(
                'Traditionally benefic: attraction, connection, pleasure and values; no outcome is guaranteed.',
                'Make a considerate connection and choose what matters.',
                'Indulgence, avoidance or spending for comfort may coexist.',
                'Compare enjoyment and relationship quality with boundaries, cost and the other person’s response.',
              )
            : const StarMeaningGuide(
                '伝統的には吉星。魅力・関係・楽しみ・価値観の象徴ですが、結果の保証ではありません。',
                '思いやりを伝え、大切にしたいものを選ぶ。',
                '甘え・問題の先送り・心地よさのための出費も併存し得ます。',
                '楽しさや関係の質と、境界・費用・相手の反応を別に見ます。',
              ),
      AstroPlanet.mars =>
        en
            ? const StarMeaningGuide(
                'Traditionally malefic: drive, heat, conflict and cutting through; strong does not mean good or inevitably harmful.',
                'Use focused effort and set a clear boundary.',
                'Haste, irritation, clashes or exhaustion may coexist.',
                'Give action a small goal and a stopping point; intensity alone is not achievement.',
              )
            : const StarMeaningGuide(
                '伝統的には凶星。推進力・熱・衝突・切り開く働きの象徴。強さは吉や必ず起こる害を意味しません。',
                '力を絞って動き、必要な境界を示す。',
                '焦り・苛立ち・衝突・消耗も併存し得ます。',
                '行動の小さな目標と止め時を決めます。勢いだけを成果とは読みません。',
              ),
      AstroPlanet.jupiter =>
        en
            ? const StarMeaningGuide(
                'Traditionally benefic: expansion, learning and opportunity; expansion can include excess.',
                'Learn, seek perspective and explore a realistic opportunity.',
                'Overconfidence, overcommitment or enlarged costs can coexist.',
                'Check resources and limits before expanding; Jupiter’s symbolism does not prove income or a good day.',
              )
            : const StarMeaningGuide(
                '伝統的には吉星。拡大・学び・機会の象徴で、拡大には過剰も含まれます。',
                '視野を広げ、現実的な機会や学びを探す。',
                '楽観の行きすぎ・引受けすぎ・費用の拡大も併存し得ます。',
                '広げる前に資源と限界を確認します。木星の象徴だけで収益や好調を証明しません。',
              ),
      AstroPlanet.saturn =>
        en
            ? const StarMeaningGuide(
                'Traditionally malefic: limits, time, responsibility and endurance; a constraint is not an inevitable failure.',
                'Build a sustainable routine and finish essentials.',
                'Delay, heaviness, isolation or excessive self-demand may coexist.',
                'Separate a useful boundary from avoidable overload; assess progress on a realistic timescale.',
              )
            : const StarMeaningGuide(
                '伝統的には凶星。制限・時間・責任・持続の象徴。制約が必ず失敗になるわけではありません。',
                '続けられる仕組みを作り、必要なことを仕上げる。',
                '遅れ・重さ・孤立・自分への要求過多も併存し得ます。',
                '役立つ制約と過負荷を分け、現実的な時間幅で進み具合を見ます。',
              ),
      AstroPlanet.uranus =>
        en
            ? const StarMeaningGuide(
                'Change, independence and disruption; novelty is not automatically improvement.',
                'Test a different method and preserve room to adapt.',
                'Instability, abrupt detachment or broken routines may coexist.',
                'Try a reversible change before replacing what already works.',
              )
            : const StarMeaningGuide(
                '変化・独立・揺さぶりの象徴。新しさが自動的に改善になるわけではありません。',
                '別の方法を試し、対応できる余白を作る。',
                '不安定さ・急な離脱・日常の中断も併存し得ます。',
                '既存の良い仕組みを捨てる前に、戻せる範囲で試します。',
              ),
      AstroPlanet.neptune =>
        en
            ? const StarMeaningGuide(
                'Imagination, empathy, diffusion and ambiguity; inspiration is not verified information.',
                'Use creativity or compassion with a practical anchor.',
                'Confusion, idealization or blurred boundaries may coexist.',
                'Write down what is known, what is hoped for and what still needs checking.',
              )
            : const StarMeaningGuide(
                '想像力・共感・拡散・曖昧さの象徴。ひらめきは確認済み情報と別です。',
                '現実の足場を持ちながら創作や共感に使う。',
                '混乱・理想化・境界の曖昧さも併存し得ます。',
                '分かっていること・願い・未確認のことを書き分けます。',
              ),
      AstroPlanet.pluto =>
        en
            ? const StarMeaningGuide(
                'Intensity, power and deep change; a long-term symbol does not establish the cause of a particular event.',
                'Review a persistent pattern and what can be changed.',
                'Fixation, control or all-or-nothing pressure may coexist.',
                'Focus on a manageable decision and avoid assigning a personal event to this planet alone.',
              )
            : const StarMeaningGuide(
                '強度・力関係・深い変化の象徴。長期的な象徴から個別の出来事の原因は断定できません。',
                '繰り返すパターンと変えられる部分を見直す。',
                '執着・支配・極端な考え方の負担も併存し得ます。',
                '扱える判断に絞り、実際の出来事をこの星だけの原因にしません。',
              ),
      AstroPlanet.ascendant =>
        en
            ? const StarMeaningGuide(
                'The eastern-horizon angle, not a physical planet: approach, first response and presentation.',
                'Notice how you begin and relate to the immediate setting.',
                'A single first impression does not define your entire personality.',
                'Check birth-time precision and the actual house system before relying on this angle.',
              )
            : const StarMeaningGuide(
                '東の地平線の角度で、天体ではありません。入り方・最初の反応・見せ方の象徴です。',
                '物事の始め方と、その場への関わり方を見る。',
                '最初の印象一つで人格全体を決めることはできません。',
                '出生時刻の精度と実際のハウス方式を確認してから読みます。',
              ),
      AstroPlanet.midheaven =>
        en
            ? const StarMeaningGuide(
                'The upper-meridian angle, not a physical planet: public role and direction.',
                'Reflect on a role or contribution you want to develop.',
                'Social expectation and personal satisfaction may diverge.',
                'Use birth-time precision and natal context; this angle alone does not predict career achievement.',
              )
            : const StarMeaningGuide(
                '上の子午線の角度で、天体ではありません。社会的役割と目指す方向の象徴です。',
                '育てたい役割や貢献を考える。',
                '社会の期待と本人の満足感が一致するとは限りません。',
                '出生時刻の精度と出生図の文脈を確認します。この角度だけで仕事の達成を予測しません。',
              ),
    };
  }
}

class StarLearningIntroduction extends StatelessWidget {
  const StarLearningIntroduction({super.key});
  @override
  Widget build(BuildContext context) {
    final en = AppLanguageScope.stringsOf(context).language == AppLanguage.en;
    return ReadingCard(
      title: en ? 'Natal chart + target-date transits' : 'ネイタル＋対象日時のトランジット',
      body: en
          ? 'Start with the natal chart, then examine the target-time planets, the natal houses they cross and their angles to natal planets. The planet cards explain general symbolism and concrete ways to read it. In transit mode, the current nine-area selected factors appear separately from the preserved legacy four-area reference. Strong stimulation, favorable or difficult qualities and actual outcomes are different. These explanations do not add bonuses or turn an unvalidated trial into an established forecast.'
          : '出生図を土台に、対象日時の天体・出生図のどのハウスを通るか・出生図の星との角度を順に見ます。各星のカードで一般的な意味と具体的な読み方を確認でき、トランジット表示では現行９項目の採用済み根拠と従来４分野の参考を別々に読めます。刺激の強さ・良し悪しの性質・実際の結果は別です。この解説による追加加点や、未検証候補の正式採用は行いません。',
      icon: Icons.auto_awesome_motion,
    );
  }
}

class _StarReadingMethod extends StatelessWidget {
  const _StarReadingMethod({required this.english});
  final bool english;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: ExpansionTile(
      key: const ValueKey('star-reading-method'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 12),
      title: Text(
        english
            ? 'How to read the evidence, step by step'
            : '根拠を順に読む：星・星座・ハウス・角度',
      ),
      children: [
        _StarScopeNote(
          text: english
              ? '1. Planet: what is stimulated. Sign: its style. House: the setting. Natal placements describe a starting theme; transits describe the target instant. Neither is an observation of your actual experience.'
              : '1. 星は「何が刺激されるか」、星座は「表れ方」、ハウスは「場面」。出生図は土台、トランジットは対象日時の配置です。どちらも本人の実体験を観測した結果ではありません。',
        ),
        const SizedBox(height: 8),
        _StarScopeNote(
          text: english
              ? '2. Conjunction 0° combines themes; sextile 60° suggests cooperation; square 90° adjustment; trine 120° flow; opposition 180° competing viewpoints. These are traditional interaction patterns, not success or failure guarantees. A rare pattern or grand trine is not an automatic bonus.'
              : '2. 合0°はテーマの重なり、六分60°は協力、四分90°は調整、三分120°は流れ、衝180°は向き合う視点という伝統的な読み方です。成功・失敗の保証ではなく、レア配置やグランドトラインも自動加点の意味ではありません。',
        ),
        const SizedBox(height: 8),
        _StarScopeNote(
          text: english
              ? '3. Check the actual pair, orb, timing and source. A smaller orb means closer geometry, not a measured effect. Harmony and tension may coexist or offset in the selected model. Activity, real-world progress and felt experience remain separate.'
              : '3. 実際の星の組合せ・オーブ・時刻・計算元を確認します。小さいオーブは角度の近さで、実測した影響度ではありません。現行モデル内では調和と緊張の併存・相殺があり、活動量・現実の進展・体感は分けます。',
        ),
        const SizedBox(height: 8),
        _StarScopeNote(
          text: english
              ? '4. Use the selected factors below to understand the model, then choose a practical step. General symbolism, model arithmetic and independently reported outcomes are different kinds of evidence. Birth-time assumptions and approximate sources limit the reading.'
              : '4. 採用済みの内訳でモデルの判断を確かめ、実行できる一歩を選びます。一般的な象徴・モデルの計算・独立した実記録は別の根拠です。出生時刻の仮定や簡易計算には読みの限界があります。',
        ),
      ],
    ),
  );
}

/// Projection of the current shared explanation; no new astronomical search,
/// scoring coefficient or background/profile input is introduced here.
class StarSelectedEvidence {
  const StarSelectedEvidence(
    this.area,
    this.polarity,
    this.text,
    this.modelVersion,
    this.status,
  );
  final NineAreaKey area;
  final String polarity;
  final String text;
  final String modelVersion;
  final String status;

  static List<StarSelectedEvidence> forPlanet({
    required AstroPlanet planet,
    required Iterable<NineAreaPrediction> predictions,
    required DateTime targetDate,
    required AppStrings strings,
  }) {
    final name = _planetNameEn(planet).toLowerCase();
    final word = RegExp('\\b${RegExp.escape(name)}\\b', caseSensitive: false);
    final matches = <StarSelectedEvidence>[];
    for (final p in predictions) {
      final e = ForecastExplanation.forDaily(
        prediction: p,
        targetDate: targetDate,
        strings: strings,
      );
      for (final pair in [
        ('support', e.positiveMaterials),
        ('tension', e.negativeMaterials),
        ('context', e.neutralMaterials),
      ]) {
        for (final text in pair.$2) {
          if (text.contains(planet.label) || word.hasMatch(text)) {
            matches.add(
              StarSelectedEvidence(
                p.key,
                pair.$1,
                text,
                e.modelVersion,
                e.status,
              ),
            );
          }
        }
      }
    }
    return List.unmodifiable(matches);
  }
}

class AstroPlacementExplanationPanel extends StatefulWidget {
  const AstroPlacementExplanationPanel({
    super.key,
    required this.contextData,
    required this.mode,
  });

  final HoroscopeReadingContext contextData;
  final PlacementExplanationMode mode;

  @override
  State<AstroPlacementExplanationPanel> createState() =>
      _AstroPlacementExplanationPanelState();
}

class _AstroPlacementExplanationPanelState
    extends State<AstroPlacementExplanationPanel> {
  AstroPlanet? _expandedPlanet;

  bool _isEnglish(BuildContext context) =>
      AppLanguageScope.stringsOf(context).language == AppLanguage.en;

  @override
  Widget build(BuildContext context) {
    final placements = _placements();
    final sensitivity = widget.mode == PlacementExplanationMode.simple
        ? AstroSensitivityCalculator.calculate(widget.contextData)
        : null;
    final english = _isEnglish(context);
    final title = switch (widget.mode) {
      PlacementExplanationMode.simple =>
        english ? 'Birth chart themes' : '生まれた星の読み方',
      PlacementExplanationMode.natal => english ? 'Natal placements' : 'ネイタルの星',
      PlacementExplanationMode.transit =>
        english ? 'Transits for this date' : '対象日のトランジット',
    };
    final subtitle = switch (widget.mode) {
      PlacementExplanationMode.simple =>
        english
            ? 'A short introduction to selected themes in the birth chart.'
            : '出生図にある主なテーマを、占星術の一般的な見方で紹介します。',
      PlacementExplanationMode.natal =>
        english
            ? 'Birth-time placements describe natal themes; they are not today’s transits.'
            : '出生時の配置から読む性質やテーマです。今日のトランジットとは別です。',
      PlacementExplanationMode.transit =>
        english
            ? 'The placements shown come from the target instant in this reading context. They describe astrological themes, not guaranteed events.'
            : '表示する天体は、この鑑定コンテキストの対象日時の配置です。占星術上のテーマを示し、出来事を保証するものではありません。',
    };
    final retrogradeNote = switch (widget.mode) {
      PlacementExplanationMode.simple => '',
      PlacementExplanationMode.natal =>
        english
            ? '“Retrograde” in a birth chart marks a planet that appeared to move backward at birth. '
                  'It is shown only for the relevant planets.'
            : '「逆行」は出生時にその星が逆向きに見えていた印です。該当する星だけに表示します。',
      PlacementExplanationMode.transit =>
        english
            ? 'How retrograde is shown: The app compares positions now and 24 hours later, '
                  'and also uses verified retrograde periods. Near a change in direction, '
                  'the label may differ from the motion at that moment.'
            : '逆行の見方：現在と24時間後の星の位置を比べ、確認済みの逆行期間も使っています。'
                  '星の向きが変わる前後は、その瞬間の動きと表示が異なることがあります。',
    };

    return Column(
      children: [
        if (sensitivity != null) ...[
          AstroSensitivityCard(reading: sensitivity),
          _StarScopeNote(
            text: english
                ? 'The /100 value above is a birth-chart sensitivity indicator, not a daily fortune score or an accuracy measure.'
                : '上の/100は出生図から作る「感じ取りやすさ」の目安です。今日の運勢点や予測精度ではありません。',
          ),
        ],
        GlassPanel(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SmallSectionLabel(
                icon: widget.mode == PlacementExplanationMode.transit
                    ? Icons.public_outlined
                    : Icons.auto_awesome_motion,
                text: title,
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.62),
                  height: 1.45,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              _StarScopeNote(
                text: english
                    ? 'Planet symbolism is a general astrological interpretation. An aspect type describes an interaction pattern; orb describes angular closeness. Neither measures event intensity, certainty, or success.'
                    : '惑星の意味は占星術の一般的な解釈です。アスペクト名は相互作用の型、オーブは角度の近さを表します。出来事の強さ・確実さ・成功を測るものではありません。',
              ),
              const SizedBox(height: 7),
              _StarScopeNote(
                text: english
                    ? 'Work activity and work outcomes are different. These placements alone do not predict completion, recognition, or success.'
                    : '仕事の活動量と成果は別です。配置だけから、完了・評価・成功を予測することはできません。',
              ),
              _StarReadingMethod(english: english),
              if (widget.mode == PlacementExplanationMode.transit) ...[
                const SizedBox(height: 12),
                TransitSkySummaryCard(contextData: widget.contextData),
              ],
              if (widget.mode == PlacementExplanationMode.natal) ...[
                const SizedBox(height: 12),
                NatalSkySummaryCard(contextData: widget.contextData),
              ],
              if (widget.mode != PlacementExplanationMode.simple) ...[
                const SizedBox(height: 8),
                Text(
                  retrogradeNote,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF57D6D1).withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFF57D6D1).withValues(alpha: 0.28),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.touch_app_outlined,
                      size: 17,
                      color: Color(0xFF57D6D1),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: EnglishUiText(
                        '気になる星のカードをタップすると、意味をやさしく詳しく読めます',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.82),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 720;
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: placements
                        .map(
                          (placement) => SizedBox(
                            width: isWide
                                ? (constraints.maxWidth - 10) / 2
                                : constraints.maxWidth,
                            child: AstroPlacementTile(
                              placement: placement,
                              contextData: widget.contextData,
                              mode: widget.mode,
                              retrograde:
                                  widget.mode ==
                                      PlacementExplanationMode.transit
                                  ? widget.contextData.retrogradePlanets
                                        .contains(placement.planet)
                                  : widget.contextData.natal.retrogradePlanets
                                        .contains(placement.planet),
                              expanded: _expandedPlanet == placement.planet,
                              onTap: () => setState(() {
                                _expandedPlanet =
                                    _expandedPlanet == placement.planet
                                    ? null
                                    : placement.planet;
                              }),
                            ),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<PlanetPlacement> _placements() {
    final source = widget.mode == PlacementExplanationMode.transit
        ? widget.contextData.transit.placements
        : widget.contextData.natal.placements;
    final planets = switch (widget.mode) {
      PlacementExplanationMode.simple => const [
        AstroPlanet.sun,
        AstroPlanet.moon,
        AstroPlanet.venus,
        AstroPlanet.mercury,
        AstroPlanet.jupiter,
        AstroPlanet.ascendant,
        AstroPlanet.midheaven,
      ],
      PlacementExplanationMode.natal => const [
        AstroPlanet.sun,
        AstroPlanet.moon,
        AstroPlanet.mercury,
        AstroPlanet.venus,
        AstroPlanet.mars,
        AstroPlanet.jupiter,
        AstroPlanet.saturn,
        AstroPlanet.uranus,
        AstroPlanet.neptune,
        AstroPlanet.pluto,
        AstroPlanet.ascendant,
        AstroPlanet.midheaven,
      ],
      PlacementExplanationMode.transit => const [
        AstroPlanet.sun,
        AstroPlanet.moon,
        AstroPlanet.mercury,
        AstroPlanet.venus,
        AstroPlanet.mars,
        AstroPlanet.jupiter,
        AstroPlanet.saturn,
        AstroPlanet.uranus,
        AstroPlanet.neptune,
        AstroPlanet.pluto,
      ],
    };
    return [
      for (final planet in planets)
        for (final placement in source)
          if (placement.planet == planet) placement,
    ];
  }
}

class _StarScopeNote extends StatelessWidget {
  const _StarScopeNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.045),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.66),
        fontSize: 11,
        height: 1.4,
      ),
    ),
  );
}

class NatalSkySummaryCard extends StatelessWidget {
  const NatalSkySummaryCard({super.key, required this.contextData});

  final HoroscopeReadingContext contextData;

  @override
  Widget build(BuildContext context) {
    final english =
        AppLanguageScope.stringsOf(context).language == AppLanguage.en;
    final natal = contextData.natal;
    final sun = natal.placementOf(AstroPlanet.sun);
    final moon = natal.placementOf(AstroPlanet.moon);
    final asc = natal.placementOf(AstroPlanet.ascendant);
    final mc = natal.placementOf(AstroPlanet.midheaven);
    final rarePatterns = FortuneScoreCalculator.natalRarePatternLabels(
      contextData,
    );
    final lines = <String>[
      if (sun != null && moon != null)
        english
            ? 'Sun in ${_signNameEn(sun.sign)} × Moon in ${_signNameEn(moon.sign)}: identity and emotional-security themes.'
            : '太陽 ${sun.sign.label} × 月 ${moon.sign.label}：自分らしさと安心の土台',
      if (asc != null)
        english
            ? 'Ascendant in ${_signNameEn(asc.sign)}: first impressions and ways of beginning.'
            : 'ASC ${asc.sign.label}：第一印象と始め方のテーマ',
      if (mc != null)
        english
            ? 'Midheaven in ${_signNameEn(mc.sign)}: public roles and long-term aims; not a result forecast.'
            : 'MC ${mc.sign.label}：社会での役割や目標のテーマ。成果の予測ではありません。',
      if (natal.retrogradePlanets.isNotEmpty)
        english
            ? 'Birth-chart retrograde planets: ${_planetListEn(natal.retrogradePlanets)}.'
            : '${natal.retrogradePlanets.map((planet) => planet.label).join('・')}が出生時に逆行',
      ...natal.stelliums.map(
        (item) => english
            ? 'House ${item.house} emphasis: ${item.planets.map(_planetNameEn).join(', ')}.'
            : '${item.label}：ハウスに配置が集まる形',
      ),
      if (FortuneScoreCalculator.hasNatalKite(contextData))
        english
            ? 'Natal kite pattern: an astrological configuration, not proof of talent or achievement.'
            : 'カイト：占星術上の配置パターンです。才能や成果を証明するものではありません。',
      ...rarePatterns.map(
        (label) => english
            ? '${_patternNameEn(label)}: a pattern astrologers may use as a broad interpretive theme.'
            : '$label：占星術で広い解釈テーマとして扱われる配置です。',
      ),
    ];
    final visibleLines = lines.take(6).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF6D77A).withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFFF6D77A).withValues(alpha: 0.30),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SmallSectionLabel(
            icon: Icons.auto_awesome_motion,
            text: english ? 'Main natal placements' : '生まれ持った主要配置',
          ),
          const SizedBox(height: 7),
          Text(
            visibleLines.join('\n'),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.80),
              fontSize: 12,
              height: 1.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (lines.length > visibleLines.length) ...[
            const SizedBox(height: 5),
            Text(
              english
                  ? 'Open the planet cards below for more detail.'
                  : '詳しい意味は下の各星カードで確認できます。',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 10,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class TransitSkySummaryCard extends StatelessWidget {
  const TransitSkySummaryCard({super.key, required this.contextData});

  final HoroscopeReadingContext contextData;

  @override
  Widget build(BuildContext context) {
    final english =
        AppLanguageScope.stringsOf(context).language == AppLanguage.en;
    final retrogrades = contextData.retrogradePlanets;
    final pairAspects = [...contextData.transitPairAspects]
      ..sort((a, b) => a.orb.compareTo(b.orb));
    final tightAspects = pairAspects.take(3).toList();
    final bySign = <ZodiacSign, List<AstroPlanet>>{};
    for (final placement in contextData.transit.placements) {
      if (placement.planet == AstroPlanet.ascendant ||
          placement.planet == AstroPlanet.midheaven)
        continue;
      bySign.putIfAbsent(placement.sign, () => []).add(placement.planet);
    }
    final stelliums = bySign.entries
        .where((entry) => entry.value.length >= 3)
        .map(
          (entry) => english
              ? '${entry.value.map(_planetNameEn).join(', ')} in ${_signNameEn(entry.key)}'
              : '${entry.key.label}に${entry.value.map((planet) => planet.label).join('・')}が集中',
        )
        .toList();
    final grandTrines = FortuneScoreCalculator.transitGrandTrineLabels(
      contextData,
    );
    final rarePatterns = FortuneScoreCalculator.transitRarePatternLabels(
      contextData,
    ).where((label) => !label.startsWith('グランドトライン')).toList();
    final lines = <String>[
      if (retrogrades.isNotEmpty)
        english
            ? 'Retrograde markers: ${_planetListEn(retrogrades)}.'
            : '${retrogrades.map((planet) => planet.label).join('・')}が逆行中。表示上の天体運動の区分です。',
      ...tightAspects.map(
        (aspect) => english
            ? '${_planetNameEn(aspect.firstPlanet)} ${_aspectNameEn(aspect.type)} ${_planetNameEn(aspect.secondPlanet)} (${aspect.orb.toStringAsFixed(1)}° orb; ${_phaseNameEn(aspect.phase)})'
            : '${aspect.firstPlanet.label} ${aspect.type.label} ${aspect.secondPlanet.label}（${aspect.orb.toStringAsFixed(1)}°・${aspect.phase.label}）',
      ),
      ...stelliums,
      ...grandTrines.map(
        (label) => english
            ? 'Grand trine: ${_patternNameEn(label)}.'
            : 'グランドトライン（$label）',
      ),
      ...rarePatterns.map(
        (label) => english
            ? '${_patternNameEn(label)}: a general configuration pattern.'
            : '$label：占星術上の一般的な配置パターンです。',
      ),
      if (contextData.transit.voidMoon != null)
        english
            ? 'A void-of-course Moon period is recorded for this date.'
            : 'この日に月ボイドの時間帯があります。',
    ];
    final visibleLines = lines.take(6).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF57D6D1).withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFF57D6D1).withValues(alpha: 0.30),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SmallSectionLabel(
            icon: Icons.hub_outlined,
            text: english ? 'Transit overview' : '対象日の主な配置',
          ),
          const SizedBox(height: 7),
          Text(
            visibleLines.isEmpty
                ? (english
                      ? 'No items in this overview met its display filter. This is not a forecast of an uneventful day.'
                      : 'この概要の表示条件に当てはまる項目はありません。出来事が少ない日の予測ではありません。')
                : visibleLines.join('\n'),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.80),
              fontSize: 12,
              height: 1.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (lines.length > visibleLines.length) ...[
            const SizedBox(height: 5),
            Text(
              english
                  ? 'Other placements appear in the cards and full aspect table.'
                  : 'ほかの配置は下の各星カードと「全アスペクト表」で確認できます。',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 10,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class AstroPlacementTile extends StatelessWidget {
  const AstroPlacementTile({
    super.key,
    required this.placement,
    required this.contextData,
    required this.mode,
    required this.retrograde,
    required this.expanded,
    required this.onTap,
  });

  final PlanetPlacement placement;
  final HoroscopeReadingContext contextData;
  final PlacementExplanationMode mode;
  final bool retrograde;
  final bool expanded;
  final VoidCallback onTap;

  bool get _isSimple => mode == PlacementExplanationMode.simple;

  String _retrogradeMeaning({required bool english}) {
    if (english) {
      final theme = switch (placement.planet) {
        AstroPlanet.mercury => 'thinking, communication, and coordination',
        AstroPlanet.venus => 'affection, preferences, and spending choices',
        AstroPlanet.mars => 'initiative, anger, and ways of acting',
        AstroPlanet.jupiter => 'growth, learning, and expansion',
        AstroPlanet.saturn => 'responsibility, limits, and persistence',
        AstroPlanet.uranus => 'change, independence, and freedom',
        AstroPlanet.neptune => 'ideals, imagination, and boundaries',
        AstroPlanet.pluto => 'deep change, release, and renewal',
        AstroPlanet.sun => 'identity and purpose',
        AstroPlanet.moon => 'mood and emotional security',
        AstroPlanet.ascendant => 'first impressions and beginnings',
        AstroPlanet.midheaven => 'public roles and long-term aims',
      };
      return mode == PlacementExplanationMode.natal || _isSimple
          ? 'At birth, ${_planetNameEn(placement.planet)} was marked retrograde. In traditional astrology, $theme may be approached through reflection and revision. This is an interpretation, not a measured effect.'
          : '${_planetNameEn(placement.planet)} is marked retrograde for this date. Astrologers often use this as a prompt to review $theme; it does not by itself predict a problem.';
    }
    final theme = switch (placement.planet) {
      AstroPlanet.mercury => '考え方・言葉・連絡',
      AstroPlanet.venus => '愛情・好み・お金の使い方',
      AstroPlanet.mars => '行動力・怒り・進め方',
      AstroPlanet.jupiter => '成長・学び・広げ方',
      AstroPlanet.saturn => '責任・課題・続け方',
      AstroPlanet.uranus => '変化・独自性・自由',
      AstroPlanet.neptune => '理想・想像力・境界線',
      AstroPlanet.pluto => '深い変化・手放し・再生',
      AstroPlanet.sun => '自分らしさ・目的',
      AstroPlanet.moon => '気分・安心感',
      AstroPlanet.ascendant => '自分の見せ方・始め方',
      AstroPlanet.midheaven => '仕事・社会での役割',
    };
    if (mode == PlacementExplanationMode.natal || _isSimple) {
      return '出生時の${placement.planet.label}は逆行です。占星術では、$themeを見直しながら育てるテーマとして解釈します。測定された影響や成果の予測ではありません。';
    }
    return '対象日の${placement.planet.label}は逆行として表示されています。占星術では、$themeを見直すきっかけとして読むことがあります。これだけで問題を予測するものではありません。';
  }

  @override
  Widget build(BuildContext context) {
    final english =
        AppLanguageScope.stringsOf(context).language == AppLanguage.en;
    final planetName = english
        ? _planetNameEn(placement.planet)
        : placement.planet.label;
    final signName = english
        ? _signNameEn(placement.sign)
        : placement.sign.label;
    return InkWell(
      key: ValueKey('astro-placement-${placement.planet.name}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFB58CFF).withValues(alpha: 0.075),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: const Color(0xFFB58CFF).withValues(alpha: 0.22),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _iconFor(placement.planet),
                  size: 18,
                  color: const Color(0xFFF6D77A),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    english
                        ? '$planetName / $signName${_isSimple ? '' : ' / House ${placement.house}'}${retrograde ? ' / Retrograde' : ''}'
                        : _isSimple
                        ? '$planetName / $signName${retrograde ? ' / 逆行' : ''}'
                        : '$planetName / $signName / 第${placement.house}ハウス${retrograde ? ' / 逆行' : ''}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (retrograde)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6D77A).withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: const Color(0xFFF6D77A).withValues(alpha: 0.48),
                      ),
                    ),
                    child: Text(
                      english ? 'Retrograde' : '逆行',
                      style: TextStyle(
                        color: Color(0xFFF6D77A),
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
              ],
            ),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 180),
              crossFadeState: expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _placementSummary(placement, english: english),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.76),
                        fontSize: 12,
                        height: 1.4,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          english ? 'Tap for details' : 'タップして詳しく読む',
                          style: TextStyle(
                            color: const Color(
                              0xFF57D6D1,
                            ).withValues(alpha: 0.9),
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const Icon(
                          Icons.expand_more,
                          size: 17,
                          color: Color(0xFF57D6D1),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              secondChild: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _planetMeaning(placement.planet, english: english),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 12,
                        height: 1.45,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (expanded) ...[
                      const SizedBox(height: 8),
                      _StarPlanetGuide(
                        planet: placement.planet,
                        english: english,
                      ),
                    ],
                    const SizedBox(height: 7),
                    Text(
                      english
                          ? 'Sign theme: ${_signMeaning(placement.sign, english: true)}'
                          : _isSimple
                          ? '星座のテーマ: ${_signMeaning(placement.sign, english: false)}'
                          : '${placement.sign.label}: ${_signMeaning(placement.sign, english: false)}',
                      style: TextStyle(
                        color: const Color(0xFF57D6D1).withValues(alpha: 0.88),
                        fontSize: 12,
                        height: 1.4,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      english
                          ? 'House theme: ${_houseMeaning(placement.house, english: true)}'
                          : _isSimple
                          ? 'テーマが表れやすい場面: ${_houseMeaning(placement.house, english: false)}'
                          : '第${placement.house}ハウス: ${_houseMeaning(placement.house, english: false)}',
                      style: TextStyle(
                        color: const Color(0xFFF6D77A).withValues(alpha: 0.88),
                        fontSize: 12,
                        height: 1.4,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (retrograde) ...[
                      const SizedBox(height: 7),
                      Text(
                        _retrogradeMeaning(english: english),
                        style: TextStyle(
                          color: const Color(
                            0xFFF6D77A,
                          ).withValues(alpha: 0.92),
                          fontSize: 12,
                          height: 1.45,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                    const SizedBox(height: 7),
                    Text(
                      _placementSummary(placement, english: english),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.90),
                        fontSize: 12,
                        height: 1.45,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      english
                          ? 'Reflection prompt: ${_actionHint(placement, english: true)}'
                          : '考えるヒント: ${_actionHint(placement, english: false)}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 12,
                        height: 1.45,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 9),
                    if (expanded && mode == PlacementExplanationMode.transit)
                      Column(
                        children: [
                          _CurrentPlanetScoreEvidence(
                            planet: placement.planet,
                            contextData: contextData,
                            english: english,
                          ),
                          _PlanetScoreEvidence(
                            planet: placement.planet,
                            contextData: contextData,
                            english: english,
                          ),
                        ],
                      )
                    else if (expanded)
                      _StarScopeNote(
                        text: english
                            ? 'This birth-chart placement is a natal theme, separate from today’s transits. The daily score can use natal context with target-date signals; this description does not assign this placement a separate score effect.'
                            : 'この出生図の配置は、今日のトランジットとは別の生まれ持ったテーマです。日々の点数は出生図の文脈と対象日の要因を組み合わせますが、この説明だけで個別の点数効果を割り当てるものではありません。',
                      ),
                    const SizedBox(height: 7),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          english ? 'Close' : '閉じる',
                          style: TextStyle(
                            color: const Color(
                              0xFF57D6D1,
                            ).withValues(alpha: 0.9),
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const Icon(
                          Icons.expand_less,
                          size: 17,
                          color: Color(0xFF57D6D1),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _actionHint(PlanetPlacement value, {required bool english}) {
    if (english) {
      return switch (value.planet) {
        AstroPlanet.moon =>
          'If your mood shifts, consider leaving room for rest and one reassuring routine.',
        AstroPlanet.mercury =>
          'Writing or talking through one idea may help you organize your thoughts.',
        AstroPlanet.venus =>
          'You might make space for people or activities you enjoy when considering what matters to you.',
        AstroPlanet.mars =>
          'When energy rises, choosing one small first step can make action easier to manage.',
        AstroPlanet.sun =>
          'Naming one priority can help you reflect on where to focus your effort.',
        AstroPlanet.jupiter =>
          'A small learning step or conversation may help you notice another option.',
        AstroPlanet.saturn =>
          'Breaking a responsibility into a clear next step may make it easier to manage.',
        AstroPlanet.uranus =>
          'You could try one different approach while keeping what already works.',
        AstroPlanet.neptune =>
          'When things feel unclear, separating rest from fact-checking may help.',
        AstroPlanet.pluto =>
          'You might reflect on what to release and what deserves focused attention.',
        AstroPlanet.ascendant =>
          'You can choose one way you want to begin or present yourself.',
        AstroPlanet.midheaven =>
          'Putting a goal into one sentence may help you think about direction.',
      };
    }
    return switch (value.planet) {
      AstroPlanet.moon => '気分が揺れる日は、予定を一つ減らして安心できる習慣を先に置くと整いやすいです。',
      AstroPlanet.mercury => '考えを頭の中だけで回さず、短く書く・話すことで判断がまとまりやすくなります。',
      AstroPlanet.venus => '好きなものや心地よい人との時間を予定に入れると、対人やお金について考えるきっかけになります。',
      AstroPlanet.mars => '勢いが出た時ほど、最初の一手を小さく決めてから動くと力を使いやすいです。',
      AstroPlanet.sun => '自分で決めた優先順位を一つ表に出して、どこに力を使うか考えてみましょう。',
      AstroPlanet.jupiter => '学びや人とのつながりを少し広げて、選択肢を見直すきっかけにできます。',
      AstroPlanet.saturn => '負担を抱え込まず、期限と役割を小さく区切るほど続けやすくなります。',
      AstroPlanet.uranus => 'いつもと違う方法を一つだけ試すと、変化を味方にしやすくなります。',
      AstroPlanet.neptune => '気持ちが曖昧な時は、休息と事実確認を分けると迷いが薄れます。',
      AstroPlanet.pluto => '手放すことを一つ決め、深く取り組む対象を絞ると変化を活かせます。',
      AstroPlanet.ascendant => '人に見せる最初の一歩について、自分が望む形を考えてみましょう。',
      AstroPlanet.midheaven => '仕事や目標を一文で言える形にすると、進む方向がぶれにくくなります。',
    };
  }

  IconData _iconFor(AstroPlanet planet) {
    switch (planet) {
      case AstroPlanet.sun:
        return Icons.wb_sunny_outlined;
      case AstroPlanet.moon:
        return Icons.dark_mode_outlined;
      case AstroPlanet.mercury:
        return Icons.forum_outlined;
      case AstroPlanet.venus:
        return Icons.favorite_border;
      case AstroPlanet.mars:
        return Icons.local_fire_department_outlined;
      case AstroPlanet.jupiter:
        return Icons.savings_outlined;
      case AstroPlanet.saturn:
        return Icons.account_tree_outlined;
      case AstroPlanet.ascendant:
        return Icons.person_pin_circle_outlined;
      case AstroPlanet.midheaven:
        return Icons.work_outline;
      case AstroPlanet.uranus:
      case AstroPlanet.neptune:
      case AstroPlanet.pluto:
        return Icons.auto_awesome_motion;
    }
  }

  String _placementSummary(PlanetPlacement value, {required bool english}) {
    final summary = _summary(value, english: english);
    if (english) {
      return mode == PlacementExplanationMode.transit
          ? 'Transit theme for this date: $summary'
          : 'Birth-chart theme: $summary';
    }
    return mode == PlacementExplanationMode.transit
        ? '対象日の一般的な配置テーマ：$summary'
        : '出生図の一般的なテーマ：$summary';
  }

  String _summary(PlanetPlacement value, {required bool english}) {
    if (english) {
      final focus = switch (value.planet) {
        AstroPlanet.sun => 'identity and direction',
        AstroPlanet.moon => 'emotional needs and security',
        AstroPlanet.mercury => 'thinking and communication',
        AstroPlanet.venus => 'preferences and connection',
        AstroPlanet.mars => 'initiative and drive',
        AstroPlanet.jupiter => 'growth and exploration',
        AstroPlanet.saturn => 'responsibility and persistence',
        AstroPlanet.uranus => 'change and independence',
        AstroPlanet.neptune => 'imagination and ideals',
        AstroPlanet.pluto => 'deep change and focus',
        AstroPlanet.ascendant => 'first impressions and beginnings',
        AstroPlanet.midheaven => 'public roles and long-term aims',
      };
      final style = switch (value.sign) {
        ZodiacSign.aries => 'initiative and quick starts',
        ZodiacSign.taurus => 'steadiness and the senses',
        ZodiacSign.gemini => 'conversation and information',
        ZodiacSign.cancer => 'care and a sense of belonging',
        ZodiacSign.leo => 'expression and confidence',
        ZodiacSign.virgo => 'organizing and improving',
        ZodiacSign.libra => 'balance with others',
        ZodiacSign.scorpio => 'depth and focus',
        ZodiacSign.sagittarius => 'learning and exploration',
        ZodiacSign.capricorn => 'patient effort toward goals',
        ZodiacSign.aquarius => 'independent or inventive approaches',
        ZodiacSign.pisces => 'imagination and empathy',
      };
      final scene = _houseMeaning(value.house, english: true);
      return 'In general astrology, this placement is associated with $focus, $style, and themes of $scene. It is a symbolic interpretation, not a predicted result.';
    }
    final focus = switch (value.planet) {
      AstroPlanet.sun => '自分らしさ',
      AstroPlanet.moon => '安心できる感情の扱い',
      AstroPlanet.mercury => '考え方と言葉',
      AstroPlanet.venus => '好きなものと人との距離',
      AstroPlanet.mars => '行動の勢い',
      AstroPlanet.jupiter => '成長と広がり',
      AstroPlanet.saturn => '責任と積み重ね',
      AstroPlanet.uranus => '変化と独自性',
      AstroPlanet.neptune => '想像力と共感',
      AstroPlanet.pluto => '深い変化',
      AstroPlanet.ascendant => '第一印象と始め方',
      AstroPlanet.midheaven => '社会での役割',
    };
    final style = switch (value.sign) {
      ZodiacSign.aries => '自分から先に動く形で',
      ZodiacSign.taurus => 'じっくり安定させる形で',
      ZodiacSign.gemini => '会話や情報を使う形で',
      ZodiacSign.cancer => '安心できる人や場所を守る形で',
      ZodiacSign.leo => '自信を持って表現する形で',
      ZodiacSign.virgo => '整理して役立てる形で',
      ZodiacSign.libra => '人とのバランスを取る形で',
      ZodiacSign.scorpio => '深く集中する形で',
      ZodiacSign.sagittarius => '学びや挑戦へ広げる形で',
      ZodiacSign.capricorn => '目標へ着実に積み上げる形で',
      ZodiacSign.aquarius => '自分らしい新しい方法で',
      ZodiacSign.pisces => '想像力や思いやりを使う形で',
    };
    final scene = _houseMeaning(value.house, english: false);
    return '$focusが、$style、$sceneに関わるとされる配置です。出来事や結果を予測するものではありません。';
  }

  String _planetMeaning(AstroPlanet planet, {required bool english}) {
    if (english) {
      return switch (planet) {
        AstroPlanet.sun =>
          'General astrology: identity, direction, and self-expression. This symbolism alone does not determine an overall score.',
        AstroPlanet.moon =>
          'General astrology: moods, comfort, and everyday emotional rhythms. Its meaning is not a guarantee about how a day will feel.',
        AstroPlanet.mercury =>
          'General astrology: communication, information, and choices. This symbolism does not predict work success.',
        AstroPlanet.venus =>
          'General astrology: affection, preferences, pleasure, and values. It does not automatically raise love or money scores.',
        AstroPlanet.mars =>
          'General astrology: initiative, effort, and assertion. Activity or effort is different from an outcome.',
        AstroPlanet.jupiter =>
          'General astrology: growth, learning, and widening perspective. Jupiter alone does not automatically raise money or overall scores.',
        AstroPlanet.saturn =>
          'General astrology: responsibility, limits, and sustained effort. A challenge theme does not determine a result.',
        AstroPlanet.uranus =>
          'General astrology: change, independence, and experimentation.',
        AstroPlanet.neptune =>
          'General astrology: ideals, imagination, and ambiguity.',
        AstroPlanet.pluto =>
          'General astrology: intensity, focus, and deep change; not a claim that an event is unavoidable.',
        AstroPlanet.ascendant =>
          'General astrology: first impressions and ways of beginning. This is calculated from birth time and place.',
        AstroPlanet.midheaven =>
          'General astrology: public roles and long-term direction; it does not forecast career success.',
      };
    }
    switch (planet) {
      case AstroPlanet.sun:
        return '占星術の一般的な象徴：自分らしさ、方向性、自己表現。この意味だけで総合点が決まるものではありません。';
      case AstroPlanet.moon:
        return '占星術の一般的な象徴：気分、安心感、日々の感情のリズム。その日の気分を保証するものではありません。';
      case AstroPlanet.mercury:
        return '占星術の一般的な象徴：言葉、情報、考え方。この意味だけで仕事の成功を予測しません。';
      case AstroPlanet.venus:
        return '占星術の一般的な象徴：愛情、好み、楽しみ、価値観。恋愛点や金運点を自動で上げる意味ではありません。';
      case AstroPlanet.mars:
        return '占星術の一般的な象徴：行動力、意欲、主張。活動や努力と、その成果は別です。';
      case AstroPlanet.jupiter:
        return '占星術の一般的な象徴：成長、学び、視野の広がり。木星だけで金運・総合点が自動的に上がるわけではありません。';
      case AstroPlanet.saturn:
        return '占星術の一般的な象徴：責任、制約、継続。課題のテーマが結果を決めるわけではありません。';
      case AstroPlanet.uranus:
        return '占星術の一般的な象徴：変化、独立性、新しい試み。';
      case AstroPlanet.neptune:
        return '占星術の一般的な象徴：理想、想像力、曖昧さ。';
      case AstroPlanet.pluto:
        return '占星術の一般的な象徴：強い集中、手放し、深い変化。出来事が避けられないという意味ではありません。';
      case AstroPlanet.ascendant:
        return '占星術の一般的な象徴：第一印象や始め方。出生時刻と場所を使って計算します。';
      case AstroPlanet.midheaven:
        return '占星術の一般的な象徴：社会での役割や長期的な方向性。仕事の成功を予測するものではありません。';
    }
  }

  String _signMeaning(ZodiacSign sign, {required bool english}) {
    if (english) {
      return switch (sign) {
        ZodiacSign.aries => 'initiative and quick starts',
        ZodiacSign.taurus => 'stability and the senses',
        ZodiacSign.gemini => 'information and conversation',
        ZodiacSign.cancer => 'security and care',
        ZodiacSign.leo => 'expression and confidence',
        ZodiacSign.virgo => 'organization and improvement',
        ZodiacSign.libra => 'balance and relationships',
        ZodiacSign.scorpio => 'depth and focus',
        ZodiacSign.sagittarius => 'learning and exploration',
        ZodiacSign.capricorn => 'responsibility and steady effort',
        ZodiacSign.aquarius => 'independence and new ideas',
        ZodiacSign.pisces => 'empathy and imagination',
      };
    }
    switch (sign) {
      case ZodiacSign.aries:
        return '勢いよく始める、直感で動く';
      case ZodiacSign.taurus:
        return '安定、五感、じっくり育てる';
      case ZodiacSign.gemini:
        return '情報、会話、軽やかな切り替え';
      case ZodiacSign.cancer:
        return '安心感、身内、守る力';
      case ZodiacSign.leo:
        return '表現、自信、主役になる力';
      case ZodiacSign.virgo:
        return '整理、改善、実務力';
      case ZodiacSign.libra:
        return '調和、対人、バランス';
      case ZodiacSign.scorpio:
        return '深い関係、集中、本音';
      case ZodiacSign.sagittarius:
        return '探求、遠くへ広げる、学び';
      case ZodiacSign.capricorn:
        return '責任、成果、積み上げ';
      case ZodiacSign.aquarius:
        return '自由、仲間、未来志向';
      case ZodiacSign.pisces:
        return '共感、直感、境界を溶かす';
    }
  }

  String _houseMeaning(int house, {required bool english}) {
    if (english) {
      return switch (house) {
        1 => 'self-presentation and beginnings',
        2 => 'resources and values (not an income result)',
        3 => 'communication, learning, and nearby activity',
        4 => 'home and emotional foundations',
        5 => 'creativity, recreation, and romance themes',
        6 => 'routines, work activity, and health habits (not work outcomes)',
        7 => 'partnerships and agreements',
        8 => 'shared resources and close bonds',
        9 => 'learning, travel, and wider perspectives',
        10 => 'public roles, goals, and work themes (not career success)',
        11 => 'groups, communities, and future plans',
        12 => 'rest, reflection, and private preparation',
        _ => 'everyday life themes',
      };
    }
    switch (house) {
      case 1:
        return '自分自身、第一印象、始め方に出る';
      case 2:
        return '持ち物や価値観に関わるテーマ（収入の結果ではありません）';
      case 3:
        return '会話、学び、近い移動、情報に出る';
      case 4:
        return '家、安心感、心の土台に出る';
      case 5:
        return '恋愛、創作、楽しみ、自己表現に出る';
      case 6:
        return '日課、仕事の活動、健康習慣に関わるテーマ（仕事の成果とは別です）';
      case 7:
        return '対人関係、恋愛、約束に出る';
      case 8:
        return '共有、深い関係、受け取るものに出る';
      case 9:
        return '学び、遠方、信念、専門性に出る';
      case 10:
        return '社会での役割や目標に関わるテーマ（仕事の成功や評価の予測ではありません）';
      case 11:
        return '仲間、未来計画、コミュニティに出る';
      case 12:
        return '休息、無意識、見えない疲れに出る';
      default:
        return 'その星のテーマが第$houseハウス領域に出る';
    }
  }
}

class _StarPlanetGuide extends StatelessWidget {
  const _StarPlanetGuide({required this.planet, required this.english});
  final AstroPlanet planet;
  final bool english;
  @override
  Widget build(BuildContext context) {
    final guide = StarMeaningGuide.forPlanet(
      planet,
      english ? AppLanguage.en : AppLanguage.ja,
    );
    return Column(
      key: ValueKey('star-meaning-guide-${planet.name}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in [
          (english ? 'Nature' : '性質', guide.nature),
          (english ? 'Constructive use' : '活かし方', guide.constructive),
          (english ? 'Possible pressure' : '併存し得る負担', guide.pressure),
          (english ? 'How to read it' : '具体的な読み方', guide.practice),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '${row.$1}: ${row.$2}',
              style: const TextStyle(fontSize: 12, height: 1.5),
            ),
          ),
      ],
    );
  }
}

class _CurrentPlanetScoreEvidence extends StatelessWidget {
  const _CurrentPlanetScoreEvidence({
    required this.planet,
    required this.contextData,
    required this.english,
  });
  final AstroPlanet planet;
  final HoroscopeReadingContext contextData;
  final bool english;
  @override
  Widget build(BuildContext context) {
    final strings = AppStrings(english ? AppLanguage.en : AppLanguage.ja);
    final evidence = StarSelectedEvidence.forPlanet(
      planet: planet,
      predictions: NineAreaDailyForecast.fromContext(contextData),
      targetDate: contextData.transit.date,
      strings: strings,
    );
    return Container(
      key: ValueKey('star-current-evidence-${planet.name}'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            english ? 'Current nine-area selected evidence' : '現行９項目の採用済み根拠',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            '${NineAreaPeriodSummary.dateLabel(contextData.transit.date)} JST · ${contextData.ephemerisSourceName}',
            style: const TextStyle(fontSize: 11),
          ),
          const SizedBox(height: 6),
          _StarScopeNote(
            text: english
                ? 'These are the shared explanation’s selected factors that explicitly name this planet, in either natal or transit roles. Support and tension describe model contributions, not observed outcomes. No match does not mean no influence. Current trial candidates remain unvalidated; categorical felt experience is separate from numeric scores.'
                : '共通解説の採用済み要因から、この星名が明記されたものだけを表示します。出生図側・運行側のどちらの役割も含みます。正負はモデル内の材料で実際の結果ではなく、該当なしは影響ゼロではありません。現行の暫定候補は未検証で、カテゴリ体感は数値点と分けます。',
          ),
          const SizedBox(height: 6),
          if (evidence.isEmpty)
            Text(
              english
                  ? 'No explicitly named selected factor is available. The factor is not inferred from general symbolism.'
                  : '星名が明記された採用済み材料はありません。一般的な象徴から要因を補いません。',
              style: const TextStyle(fontSize: 11, height: 1.4),
            ),
          for (final row in evidence)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${strings.nineAreaTitle(row.area.name)} · ${switch (row.polarity) {
                  'support' => english ? 'Support' : '調和材料',
                  'tension' => english ? 'Tension' : '緊張材料',
                  _ => english ? 'Context' : '参考材料',
                }}\n${row.text}\n${row.modelVersion} · ${row.status}',
                style: const TextStyle(fontSize: 11, height: 1.45),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlanetScoreEvidence extends StatelessWidget {
  const _PlanetScoreEvidence({
    required this.planet,
    required this.contextData,
    required this.english,
  });

  final AstroPlanet planet;
  final HoroscopeReadingContext contextData;
  final bool english;

  List<({FortuneArea area, FortuneScoreFactor factor, bool combined})>
  _matchingFactors() {
    final matches =
        <({FortuneArea area, FortuneScoreFactor factor, bool combined})>[];
    const areas = [
      FortuneArea.love,
      FortuneArea.work,
      FortuneArea.money,
      FortuneArea.mental,
    ];
    for (final area in areas) {
      final breakdown = FortuneScoreCalculator.dailyAreaBreakdown(
        contextData,
        area,
        FortuneScoreCalculator.standardBase(area),
      );
      for (final factor in breakdown.factors) {
        final explicitAspectOrReturn =
            factor.label.startsWith(planet.label) &&
            (factor.label.contains('出生図の') || factor.label.endsWith('リターン'));
        final houseDetailMentionsPlanet =
            factor.label == 'ハウス通過' &&
            (factor.detail ?? '')
                .split(' / ')
                .any((part) => part.startsWith('${planet.label} '));
        if (explicitAspectOrReturn || houseDetailMentionsPlanet) {
          matches.add((
            area: area,
            factor: factor,
            combined: houseDetailMentionsPlanet,
          ));
        }
      }
    }
    return matches;
  }

  String _areaLabel(FortuneArea area) {
    if (!english) return area.label;
    return switch (area) {
      FortuneArea.overall => 'Overall',
      FortuneArea.love => 'Love',
      FortuneArea.work => 'Work',
      FortuneArea.money => 'Money',
      FortuneArea.mental => 'Well-being',
    };
  }

  String _factorLabel(String label) {
    if (!english) return label;
    if (label == 'ハウス通過') return 'House transit (combined factor)';
    var translated = label
        .replaceAll('出生図の', ' to natal ')
        .replaceAll('コンジャンクション', 'conjunction')
        .replaceAll('オポジション', 'opposition')
        .replaceAll('セクスタイル', 'sextile')
        .replaceAll('トライン', 'trine')
        .replaceAll('スクエア', 'square')
        .replaceAll('リターン', 'return');
    final planets = AstroPlanet.values.toList()
      ..sort((a, b) => b.label.length.compareTo(a.label.length));
    for (final item in planets) {
      translated = translated.replaceAll(item.label, _planetNameEn(item));
    }
    return translated;
  }

  @override
  Widget build(BuildContext context) {
    final factors = _matchingFactors();
    final dateLabel = NineAreaPeriodSummary.dateLabel(contextData.transit.date);
    return Container(
      key: ValueKey('astro-score-evidence-${planet.name}'),
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF57D6D1).withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFF57D6D1).withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            english
                ? 'Legacy four-area reference (separate model)'
                : '従来４分野の参考（別モデル）',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          Text(
            english
                ? 'Named factors in four area breakdowns for $dateLabel'
                : '$dateLabel の点数式でこの星名が明記された要因',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          Text(
            english
                ? 'Preserved for comparison. These adjustments are not the current nine-area selected factors and must not be added to them. The legacy combined well-being area is not the current mental or health area.'
                : '比較のため従来の内訳を残しています。現行９項目の採用要因とは別で、二重加算しません。旧版のメンタル・健康の合成領域は、現行のメンタルや健康と同じ尺度ではありません。',
            style: const TextStyle(fontSize: 10, height: 1.4),
          ),
          const SizedBox(height: 5),
          Text(
            english
                ? 'This reference lists only factors that explicitly name this planet; other combined signals may also use it. Adjustments are model values, not effects on real events.'
                : 'この欄は天体名が明記された要因だけを表示します。名前がない複合要因にこの星が含まれる場合もあります。補正値は点数モデル上の値で、実際の出来事への影響ではありません。',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.66),
              fontSize: 10,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 6),
          if (factors.isEmpty)
            Text(
              english
                  ? 'No matching named factor appears in the four area breakdowns for this date.'
                  : 'この日の4分野の内訳に、この星名を含む要因はありません。',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 11,
                height: 1.35,
              ),
            )
          else
            ...factors.map(
              (item) => Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  '${_areaLabel(item.area)}: ${_factorLabel(item.factor.label)} '
                  '(${item.factor.signedValue}${english ? ' points' : '点'})'
                  '${item.combined ? (english ? ' — includes other placements' : '（他の配置と合算）') : ''}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
