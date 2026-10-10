import 'app_language.dart';

/// Exact-match, display-only additions for fixed Japanese UI strings.
///
/// Call this only for application-authored labels, helper text, messages, and
/// the explicitly recognized daily sky-event templates below. Do not pass
/// user-entered text, profile names, canonical JSON, machine keys, or scoring
/// data. Unknown text is returned unchanged.
String englishUiText(String source) {
  final existing = _appLanguageText[source];
  if (existing != null) return existing;
  final fixed = _englishUiOverrides[source];
  if (fixed != null) return fixed;
  return _englishDailyAstroEvent(source) ??
      _englishNatalProfileText(source) ??
      _englishResearchScoreComparisonText(source) ??
      _englishLearningGuideText(source) ??
      _englishMoonInfluenceDateLabel(source) ??
      source;
}

String? _englishResearchScoreComparisonText(String source) {
  final overall = RegExp(
    r'^仮案([AB])の総合：(-?\d+(?:\.\d+)?|保留)点$',
  ).firstMatch(source);
  if (overall != null) {
    final value = overall.group(2)!;
    if (value != '保留' && !double.parse(value).isFinite) return null;
    final score = value == '保留' ? 'on hold' : '$value points';
    return 'Prototype ${overall.group(1)} overall: $score';
  }

  final missing = RegExp(
    r'^(\d+)項目は必要な根拠が足りないため保留です。欠けた点数は推測しません。$',
  ).firstMatch(source);
  if (missing != null) {
    return '${missing.group(1)} items are on hold because the evidence is insufficient. Missing scores are not inferred.';
  }
  return null;
}

/// Translates only the generated position and house-stellium formats used by
/// NatalProfilePanel. Unknown planets, signs, houses, or prose remain intact.
String? _englishNatalProfileText(String source) {
  const planets = {
    '太陽': 'Sun',
    '月': 'Moon',
    '水星': 'Mercury',
    '金星': 'Venus',
    '火星': 'Mars',
    '木星': 'Jupiter',
    '土星': 'Saturn',
    '天王星': 'Uranus',
    '海王星': 'Neptune',
    '冥王星': 'Pluto',
    'ASC': 'Ascendant',
    'MC': 'Midheaven',
  };
  const signs = {
    '牡羊座': 'Aries',
    '牡牛座': 'Taurus',
    '双子座': 'Gemini',
    '蟹座': 'Cancer',
    '獅子座': 'Leo',
    '乙女座': 'Virgo',
    '天秤座': 'Libra',
    '蠍座': 'Scorpio',
    '射手座': 'Sagittarius',
    '山羊座': 'Capricorn',
    '水瓶座': 'Aquarius',
    '魚座': 'Pisces',
  };

  final positionPattern = RegExp(
    r'^(太陽|月|水星|金星|火星|木星|土星|天王星|海王星|冥王星|ASC|MC) (牡羊座|牡牛座|双子座|蟹座|獅子座|乙女座|天秤座|蠍座|射手座|山羊座|水瓶座|魚座)・第(\d+)ハウス$',
  );
  if (source.contains(' / ') || positionPattern.hasMatch(source)) {
    final entries = source.split(' / ');
    final translated = <String>[];
    for (final entry in entries) {
      final match = positionPattern.firstMatch(entry);
      if (match == null ||
          int.parse(match.group(3)!) < 1 ||
          int.parse(match.group(3)!) > 12) {
        return null;
      }
      translated.add(
        '${planets[match.group(1)]} in ${signs[match.group(2)]}, House ${match.group(3)}',
      );
    }
    return translated.join(' / ');
  }

  final stellium = RegExp(
    r'^第(\d+)ハウス集中: (.+?)が目立つ出生図です。星が集まるテーマを一点集中で磨くほど、人生の軸になります。$',
  ).firstMatch(source);
  if (stellium != null) {
    final house = int.parse(stellium.group(1)!);
    final names = stellium.group(2)!.split('・');
    if (house < 1 ||
        house > 12 ||
        names.length < 3 ||
        names.any((name) => !planets.containsKey(name))) {
      return null;
    }
    final translatedPlanets = names.map((name) => planets[name]!).join(', ');
    return 'A stellium in House $house stands out in your birth chart: $translatedPlanets. Focusing deeply on the shared theme may help it become a guiding part of your life.';
  }
  return null;
}

String? _englishMoonInfluenceDateLabel(String source) {
  final match = RegExp(r'^(感じやすい日|整えやすい日): (.+)$').firstMatch(source);
  if (match == null) return null;
  const weekdays = {'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'};
  final dates = match.group(2)!.split('・');
  final datePattern = RegExp(
    r'^(\d{2})-(\d{2}) \((Mon|Tue|Wed|Thu|Fri|Sat|Sun)\)$',
  );
  if (dates.isEmpty ||
      dates.any((date) {
        final parsed = datePattern.firstMatch(date);
        return parsed == null ||
            !weekdays.contains(parsed.group(3)) ||
            int.parse(parsed.group(1)!) < 1 ||
            int.parse(parsed.group(1)!) > 12 ||
            int.parse(parsed.group(2)!) < 1 ||
            int.parse(parsed.group(2)!) > 31;
      })) {
    return null;
  }
  final label = match.group(1) == '感じやすい日'
      ? 'Days to pay closer attention to'
      : 'Days suited to getting organized';
  return '$label: ${dates.join(', ')}';
}

String? _englishLearningGuideText(String source) {
  if (source.startsWith('・')) {
    final unbulleted = source.substring(1);
    if (unbulleted.startsWith('・')) return null;
    final translated = _englishLearningGuideText(unbulleted);
    return translated == null ? null : '• $translated';
  }
  const styles = {
    '自分から先に動く': 'taking the initiative',
    'じっくり安定させる': 'building stability step by step',
    '会話と情報を使う': 'using conversation and information',
    '安心できる人や場所を守る': 'protecting people and places that feel safe',
    '自信を持って表現する': 'expressing yourself with confidence',
    '整理して役立てる': 'organizing things and making them useful',
    '人とのバランスを取る': 'balancing with others',
    '深く集中して本音を扱う': 'focusing deeply and addressing what matters',
    '学びや挑戦へ広げる': 'expanding through learning and challenges',
    '目標へ着実に積み上げる': 'building steadily toward a goal',
    '自分らしい新しい方法を選ぶ': 'choosing a new approach that feels like you',
    '想像力と思いやりを使う': 'using imagination and compassion',
    '自分に合う形を選び直す': 'choosing a form that suits you',
  };
  const focuses = {
    '安心感と心の土台': 'security and emotional foundations',
    '学び、言葉、得意な伝え方': 'learning, communication and your way of expressing ideas',
    '好み、人との距離、楽しみ': 'preferences, closeness and enjoyment',
    '仕事、評価、社会での役割': 'work, recognition and social role',
    '成長、学び、選択肢の広がり': 'growth, learning and expanding options',
    '責任、継続、長く残る土台': 'responsibility, persistence and lasting foundations',
    '変化、自由、自分らしい選び方': 'change, freedom and choices that feel authentic',
    '共感、想像力、心の豊かさ': 'empathy, imagination and inner richness',
    '深い変化、集中、受け渡す力': 'deep change, focus and what you pass on',
    '自分らしい人生の軸': 'a life direction that feels true to you',
  };
  const scenes = {
    '自分の見せ方や始め方': 'self-presentation and how you begin',
    'お金と大切にするもの': 'money and what you value',
    '学び、会話、身近な行動': 'learning, conversation and everyday actions',
    '家、居場所、安心できる基盤': 'home, belonging and a secure foundation',
    '恋愛、創作、楽しみ': 'love, creativity and enjoyment',
    '日々の仕事、体調、習慣': 'daily work, well-being and habits',
    '対人関係や約束': 'relationships and commitments',
    '深い関係や共有すること': 'close relationships and shared matters',
    '学び、旅、視野を広げること': 'learning, travel and broadening your outlook',
    '仕事、評価、社会での役割': 'work, recognition and your role in society',
    '仲間、目標、これからの計画': 'community, goals and future plans',
    '休息、心の整理、表に出ない準備':
        'rest, emotional reflection and behind-the-scenes preparation',
    '日常の選び方': 'everyday choices',
  };
  const directions = {
    '安心の土台を作る': 'Build a secure foundation',
    '得意なことと言葉を育てる': 'Develop your strengths and communication',
    '好きなことと人との距離を形にする':
        'Give form to what you love and how you relate to others',
    '社会での役割と生活を組み立てる': 'Shape your role in society and everyday life',
    '選択肢を広げ、進む方向を選び直す': 'Expand your options and reconsider your direction',
    '経験を責任と信頼へ変える': 'Turn experience into responsibility and trust',
    '自分らしい変化を受け入れる': 'Make room for change on your own terms',
    '心の豊かさと受け取ったものを深める': 'Deepen inner richness and what you have received',
    '人生で育てた力を周囲へ渡す': 'Share the strengths you have developed',
  };

  ({String first, String second})? pair(
    String value, {
    required String prefix,
    required String between,
    required String suffix,
  }) {
    if (!value.startsWith(prefix)) return null;
    final rest = value.substring(prefix.length);
    for (final first in styles.keys) {
      if (!rest.startsWith(first)) continue;
      final middleStart = first.length;
      if (!rest.startsWith(between, middleStart)) continue;
      final secondStart = middleStart + between.length;
      final tail = rest.substring(secondStart);
      for (final second in styles.keys) {
        if (tail.startsWith(second) &&
            tail.substring(second.length) == suffix) {
          return (first: first, second: second);
        }
      }
    }
    return null;
  }

  final natal = pair(
    source,
    prefix: '',
    between: '自分らしさを大切にし、',
    suffix: '第一歩を出すタイプです。自分の方針を言葉にしてから動くと、周囲にも伝わりやすくなります。',
  );
  if (natal != null) {
    return 'Your Sun points to ${styles[natal.first]} as part of what feels authentic to you, while your Ascendant points to ${styles[natal.second]} as a way to take your first steps. Putting your intentions into words before acting can help others understand your direction.';
  }

  final love = pair(
    source,
    prefix: '好意は',
    between: '形で表れ、行動は',
    suffix: '形になりやすい配置です。好きかどうかだけで急がず、会話と行動の両方が続く相手を選ぶほど関係が育ちます。',
  );
  if (love != null) {
    return 'Affection may be expressed through ${styles[love.first]}, while actions may follow ${styles[love.second]}. Relationships can grow when both conversation and actions remain consistent, rather than rushing based on feelings alone.';
  }

  final work = pair(
    source,
    prefix: '',
    between: '考えを整理し、',
    suffix: '社会で役割を作るほど力が出ます。仕事は「何を完成させるか」と「誰へ届けるか」を決めると、持ち味が成果になりやすいです。',
  );
  if (work != null) {
    return 'Your ideas may become clearer through ${styles[work.first]}, and you may build a role in society by ${styles[work.second]}. At work, deciding what to complete and whom to reach can help turn your strengths into results.';
  }

  final moon = RegExp(
    r'^(.+?)安心感を求めやすい傾向。気分が揺れる時ほど、予定を増やすより、落ち着ける場所・人・習慣を一つ戻すと本来の調子が出やすくなります。$',
  ).firstMatch(source);
  if (moon != null && styles.containsKey(moon.group(1))) {
    return 'You may seek security through ${styles[moon.group(1)]}. When your mood shifts, returning to one calming place, person or routine may help more than adding plans.';
  }

  final money = RegExp(
    r'^(.+?)学びや経験を広げることで、収入や選択肢を育てやすい配置です。勢いで増やすより、自分の得意を人に役立つ形へ整えるほど、長く回収しやすくなります。$',
  ).firstMatch(source);
  if (money != null && styles.containsKey(money.group(1))) {
    return 'Learning and experience may help grow your income and options. Building on your strengths in a useful way can be more sustainable than expanding too quickly, especially when you ${styles[money.group(1)]}.';
  }

  final title = RegExp(r'^(.+): (.+)$').firstMatch(source);
  if (title != null &&
      directions.containsKey(title.group(1)) &&
      focuses.containsKey(title.group(2))) {
    return '${directions[title.group(1)]}: ${focuses[title.group(2)]}';
  }

  final currentTitle = RegExp(r'^現在の主題: (.+)$').firstMatch(source);
  if (currentTitle != null && focuses.containsKey(currentTitle.group(1))) {
    return 'Current theme: ${focuses[currentTitle.group(1)]}';
  }
  final nextTitle = RegExp(r'^次に育つ主題: (.+)$').firstMatch(source);
  if (nextTitle != null && focuses.containsKey(nextTitle.group(1))) {
    return 'Theme to develop next: ${focuses[nextTitle.group(1)]}';
  }

  const decadeEnding = '形で取り組むほど、この年代のテーマが自分らしい成果や安心感につながります。';
  for (final focus in focuses.entries) {
    final prefix = '出生図では${focus.key}が';
    if (!source.startsWith(prefix)) continue;
    final afterFocus = source.substring(prefix.length);
    for (final scene in scenes.entries) {
      final sceneMarker = '${scene.key}に表れやすい配置です。';
      if (!afterFocus.startsWith(sceneMarker)) continue;
      final afterScene = afterFocus.substring(sceneMarker.length);
      for (final style in styles.entries) {
        if (afterScene != '${style.key}$decadeEnding') continue;
        return 'In this birth chart, ${focus.value} may be expressed through ${scene.value}. Approaching things by ${style.value} may help this decade’s themes lead to outcomes and a sense of security that feel true to you.';
      }
    }
  }

  final noDriver = RegExp(
    r'^(.+?)を大切にしながら、自分に合うペースを選び直す時期です。$',
  ).firstMatch(source);
  if (noDriver != null && scenes.containsKey(noDriver.group(1))) {
    return 'A time to choose a pace that suits you while prioritizing ${scenes[noDriver.group(1)]}.';
  }

  final currentSummary = RegExp(
    r'^今の10年は、(.+?)を(.+?)で具体的な形にしていく時期です。$',
  ).firstMatch(source);
  if (currentSummary != null &&
      focuses.containsKey(currentSummary.group(1)) &&
      scenes.containsKey(currentSummary.group(2))) {
    return 'This decade is a time to give ${focuses[currentSummary.group(1)]} practical form through ${scenes[currentSummary.group(2)]}.';
  }

  final nextSummary = RegExp(
    r'^次の10年は、(.+?)を(.+?)へ広げる準備が始まる流れです。$',
  ).firstMatch(source);
  if (nextSummary != null &&
      focuses.containsKey(nextSummary.group(1)) &&
      scenes.containsKey(nextSummary.group(2))) {
    return 'The next decade begins a period of preparing to expand ${focuses[nextSummary.group(1)]} into ${scenes[nextSummary.group(2)]}.';
  }

  final startPoint = RegExp(
    r'^取り組む: (.+?)形で、今いちばん続けたいことを一つ決める。$',
  ).firstMatch(source);
  if (startPoint != null && styles.containsKey(startPoint.group(1))) {
    return 'Try ${styles[startPoint.group(1)]}; choose one thing you most want to keep doing now.';
  }
  final strength = RegExp(
    r'^強み: (.+?)に関する経験を、役割や得意分野として見せていく。$',
  ).firstMatch(source);
  if (strength != null && scenes.containsKey(strength.group(1))) {
    return 'Strength: Show experience in ${scenes[strength.group(1)]} through a role or area of expertise.';
  }
  if (source == '慎重: 周囲の期待だけで選ばず、生活の余力を残して進める。') {
    return 'Take care: Do not choose only to meet others’ expectations; leave room in your life as you move forward.';
  }
  final prepare = RegExp(
    r'^準備: 今のうちに(.+?)で必要になる知識、人、時間の余白を作る。$',
  ).firstMatch(source);
  if (prepare != null && scenes.containsKey(prepare.group(1))) {
    return 'Prepare: Make room now for the knowledge, people and time you will need for ${scenes[prepare.group(1)]}.';
  }
  final grow = RegExp(r'^育てる: (.+?)形で続けられる方法を試し、次の土台にする。$').firstMatch(source);
  if (grow != null && styles.containsKey(grow.group(1))) {
    return 'Develop: Try a sustainable approach by ${styles[grow.group(1)]} and use it as a foundation for what comes next.';
  }
  if (source == '手放す: 役目を終えた予定や、無理を前提にしたやり方を少しずつ減らす。') {
    return 'Let go: Gradually reduce commitments that have run their course and approaches that depend on overextending yourself.';
  }

  const plain = {
    '出生図の実際の配置から、その年代で中心になりやすい人生分野を読みます。出来事を断定する年表ではありません。':
        'This reading uses actual birth-chart placements to explore life areas that may become central in each decade. It is not a timeline that predicts specific events.',
  };
  final ageSummary = RegExp(
    r'^出生図の実際の配置から、その年代で中心になりやすい人生分野を読みます。出来事を断定する年表ではありません。現在は(\d+)歳前後の流れを強調表示しています。$',
  ).firstMatch(source);
  if (ageSummary != null) {
    return 'This reading uses actual birth-chart placements to explore life areas that may become central in each decade. It is not a timeline that predicts specific events. The flow around age ${ageSummary.group(1)} is highlighted.';
  }
  if (plain.containsKey(source)) return plain[source];

  final ageRange = RegExp(r'^(\d+)〜(\d+)歳$').firstMatch(source);
  if (ageRange != null) return 'Ages ${ageRange.group(1)}–${ageRange.group(2)}';
  return null;
}

/// Translates only the fixed, app-generated event grammars used by
/// DailyAstroEventsCard. Dynamic names are accepted only when they are known
/// planet/sign labels, and unrecognized formats remain untouched.
String? _englishDailyAstroEvent(String source) {
  const planets = {
    '太陽': 'Sun',
    '月': 'Moon',
    '水星': 'Mercury',
    '金星': 'Venus',
    '火星': 'Mars',
    '木星': 'Jupiter',
    '土星': 'Saturn',
    '天王星': 'Uranus',
    '海王星': 'Neptune',
    '冥王星': 'Pluto',
  };
  const signs = {
    '牡羊座': 'Aries',
    '牡牛座': 'Taurus',
    '双子座': 'Gemini',
    '蟹座': 'Cancer',
    '獅子座': 'Leo',
    '乙女座': 'Virgo',
    '天秤座': 'Libra',
    '蠍座': 'Scorpio',
    '射手座': 'Sagittarius',
    '山羊座': 'Capricorn',
    '水瓶座': 'Aquarius',
    '魚座': 'Pisces',
  };
  String? planetList(String value) {
    final names = value.split('・');
    if (names.isEmpty || names.any((name) => !planets.containsKey(name))) {
      return null;
    }
    return names.map((name) => planets[name]!).join(', ');
  }

  final moonSign = RegExp(
    r'^12:00　月は(.+?)：気分と行動のペースをここで確認$',
  ).firstMatch(source);
  if (moonSign != null && signs.containsKey(moonSign.group(1))) {
    return '12:00 JST — Moon in ${signs[moonSign.group(1)]}: Check the pace of your mood and actions.';
  }

  final stellium = RegExp(
    r'^12:00　空の(.+?)のステリウム（(.+?)）：そのテーマを一つに絞ると力にしやすい$',
  ).firstMatch(source);
  if (stellium != null && signs.containsKey(stellium.group(1))) {
    final translatedPlanets = planetList(stellium.group(2)!);
    if (translatedPlanets != null) {
      return '12:00 JST — Stellium in ${signs[stellium.group(1)]} ($translatedPlanets): Focus on one theme to make the most of it.';
    }
  }

  const patternLabels = {
    'Tスクエア': 'T-square',
    'グランドクロス': 'Grand cross',
    'ヨッド': 'Yod',
    'ブーメラン（ヨッド）': 'Boomerang Yod',
    'ミスティックレクタングル（ダイヤモンド）': 'Mystic rectangle (diamond)',
    'クレイドル（ゆりかご）': 'Cradle',
    'ハンマー・オブ・ソー': 'Thor’s hammer',
    'グランドセクスタイル': 'Grand sextile',
  };
  const patternGuidance = {
    'Tスクエア': (
      '今日は複数の課題が一点へ集まりやすい配置。優先順位を一つに絞って動く',
      'Several challenges may converge. Choose one priority and act on it.',
    ),
    'グランドクロス': (
      '今日は四方向からの要請がぶつかりやすい配置。役割と負担を分けて調整する',
      'Demands from several directions may clash. Separate roles and burdens, then adjust.',
    ),
    'ヨッド': (
      '今日は小さなずれの調整が大切な配置。急いで決めず、条件を微調整する',
      'Small adjustments matter. Fine-tune the conditions instead of rushing a decision.',
    ),
    'ブーメラン（ヨッド）': (
      '今日は外からの課題を通じて方向転換しやすい配置。反応を見て進め方を変える',
      'Outside challenges may prompt a change in direction. Watch the response and adjust your approach.',
    ),
    'ミスティックレクタングル（ダイヤモンド）': (
      '今日は対立した価値観を両立させる配置。違いをつなぐ役を引き受ける',
      'This pattern can help reconcile opposing values. Take a role in connecting differences.',
    ),
    'クレイドル（ゆりかご）': (
      '今日は対立を受け止める逃げ道がある配置。安心できる方法で協力を育てる',
      'This pattern offers a way to hold opposing views. Build cooperation in a way that feels safe.',
    ),
    'ハンマー・オブ・ソー': (
      '今日は緊張を具体的な改革へ変えやすい配置。衝動でぶつからず、手順を決める',
      'Tension may be turned into practical change. Set out the steps instead of reacting impulsively.',
    ),
    'グランドセクスタイル': (
      '今日は複数の得意分野が連携しやすい配置。一つを起点に周りへ広げる',
      'Several strengths may work together. Start with one and build outward.',
    ),
  };
  for (final label in patternLabels.keys) {
    final prefix = '12:00　$label（';
    if (!source.startsWith(prefix)) continue;
    final separator = source.indexOf('）：', prefix.length);
    if (separator < 0) return null;
    final guidance = patternGuidance[label];
    final translatedPlanets = planetList(
      source.substring(prefix.length, separator),
    );
    final actualGuidance = source.substring(separator + 2);
    if (guidance != null &&
        actualGuidance == guidance.$1 &&
        translatedPlanets != null) {
      return '12:00 JST — ${patternLabels[label]} ($translatedPlanets): ${guidance.$2}';
    }
    return null;
  }

  final grandTrine = RegExp(
    r'^12:00　グランドトライン（(.+?)）：得意なことを具体的な行動へつなげる$',
  ).firstMatch(source);
  if (grandTrine != null) {
    final translatedPlanets = planetList(grandTrine.group(1)!);
    if (translatedPlanets != null) {
      return '12:00 JST — Grand trine ($translatedPlanets): Put one natural strength into a concrete action.';
    }
  }

  final lunarPhase = RegExp(
    r'^12:00　月相：(.+)（照度([0-9.]+)%・月齢目安([0-9.]+)日）$',
  ).firstMatch(source);
  if (lunarPhase != null) {
    const phases = {
      '新月': 'New Moon',
      '満ちていく三日月': 'Waxing Crescent',
      '上弦の月': 'First Quarter',
      '満ちていく凸月': 'Waxing Gibbous',
      '満月': 'Full Moon',
      '欠けていく凸月': 'Waning Gibbous',
      '下弦の月': 'Last Quarter',
      '欠けていく三日月': 'Waning Crescent',
    };
    final phase = phases[lunarPhase.group(1)];
    if (phase != null) {
      return '12:00 JST — Lunar phase: $phase (illumination ${lunarPhase.group(2)}%; approximate lunar age ${lunarPhase.group(3)} days).';
    }
  }

  final retrograde = RegExp(
    r'^12:00　(.+?)逆行中：連絡、予定、判断は見直してから確定$',
  ).firstMatch(source);
  if (retrograde != null) {
    final translatedPlanets = planetList(retrograde.group(1)!);
    if (translatedPlanets != null) {
      return '12:00 JST — $translatedPlanets retrograde: Review messages, plans, and decisions before confirming.';
    }
  }

  final ingress = RegExp(
    r'^(\d{2}:\d{2})　(太陽|月|水星|金星|火星|木星|土星|天王星|海王星|冥王星)が(.+?)へ：(.+)$',
  ).firstMatch(source);
  if (ingress != null && signs.containsKey(ingress.group(3))) {
    final planet = ingress.group(2)!;
    final expected = planet == '月' ? '気分の切替' : '${planet}のテーマが切替';
    if (ingress.group(4) == expected) {
      final name = planets[planet]!;
      final guidance = planet == '月'
          ? 'A shift in mood.'
          : 'A shift in $name themes.';
      return '${ingress.group(1)} JST — $name enters ${signs[ingress.group(3)]}: $guidance';
    }
  }

  final station = RegExp(
    r'^(\d{2}:\d{2})頃　(.+?)(逆行開始|逆行終了)（留）：(.+)$',
  ).firstMatch(source);
  if (station != null) {
    final translatedPlanets = planetList(station.group(2)!);
    final guidance = switch (station.group(4)) {
      '連絡・契約・文章は仕上げと最終確認を優先' =>
        'Prioritize finishing and reviewing messages, agreements, and writing.',
      '切替直後は急いで結論を出さず、方針を見直す' =>
        'After the shift, review your direction before reaching a conclusion.',
      _ => null,
    };
    if (translatedPlanets != null && guidance != null) {
      final direction = station.group(3) == '逆行開始' ? 'retrograde' : 'direct';
      return '${station.group(1)} JST — $translatedPlanets stations $direction. $guidance';
    }
  }

  final moonVoid = RegExp(
    r'^(\d{2}:\d{2})〜(\d{2}:\d{2})　月ボイド：大きな決定は急がず確認を$',
  ).firstMatch(source);
  if (moonVoid != null) {
    return '${moonVoid.group(1)}–${moonVoid.group(2)} JST — Void-of-course Moon: Pause and review before making major decisions.';
  }

  final phaseEvent = RegExp(r'^(\d{2}:\d{2})頃　(.+?)：(.+)$').firstMatch(source);
  if (phaseEvent != null) {
    const phaseLabels = {
      '新月': 'New Moon',
      '上弦の月': 'First Quarter',
      '満月': 'Full Moon',
      '下弦の月': 'Last Quarter',
    };
    const phaseDescriptions = {
      '新月': (
        '新しいことは小さく始め、意図を一つ決める',
        'Start something new on a small scale and set one clear intention.',
      ),
      '上弦の月': (
        '育てたいことを一つ行動に移す',
        'Take one practical step toward something you want to develop.',
      ),
      '満月': (
        '結果と気持ちが表れやすいので、振り返りと調整を',
        'Results and feelings may become clearer; reflect and make adjustments.',
      ),
      '下弦の月': (
        '手放すことを一つ決め、次の準備をする',
        'Choose one thing to let go of and prepare for what comes next.',
      ),
    };
    final label = phaseLabels[phaseEvent.group(2)];
    final phase = phaseDescriptions[phaseEvent.group(2)];
    if (label != null && phase != null && phaseEvent.group(3) == phase.$1) {
      return '${phaseEvent.group(1)} JST — $label: ${phase.$2}';
    }
  }
  return null;
}

/// Reuse the existing display dictionary wherever it already has an exact,
/// parameter-free Japanese source string.
final Map<String, String> _appLanguageText = {
  for (final key in AppText.values)
    AppStrings(AppLanguage.ja).text(key): AppStrings(AppLanguage.en).text(key),
};

/// Fixed labels and short form guidance not yet represented by AppText.
/// These translations affect presentation only; no value is serialized back.
///
/// Coverage: existing parameter-free AppText entries, profile selection and
/// validation, share-card controls/errors, backup/restore/support dialogs,
/// fixed relationship-form labels, and conversational navigator labels,
/// prompts, examples, and short score badges in this research copy.
/// Gaps: unrecognized interpolated messages, user-authored/profile prose,
/// city/place lists, long generated reading prose, and operating-system
/// share-sheet text. Only explicitly recognized app-authored templates are
/// translated. The relationship entries describe a research-copy screen and
/// do not establish that it is in the protected public release.
const Map<String, String> _englishUiOverrides = {
  // Profile entry and saved-profile picker.
  '出生データを入力': 'Enter birth details',
  '新しい人物を入力': 'Add a new person',
  'ニックネーム': 'Nickname',
  '例）ぱんちょ': 'e.g., Alex',
  'タップして選択 / 例）1980/9/24': 'Tap to select / e.g., 1980/9/24',
  'ホロスコープを読む': 'Read my horoscope',
  'サンプルで試す': 'Try a sample profile',
  'このプロフィールで占う': 'Read with this profile',
  '使用中のプロフィール': 'Current profile',
  '復元したプロフィールを読み込んでいます。少しお待ちください。':
      'Loading the restored profile. Please wait.',
  '生年月日を正しい日付で入力してください。': 'Enter a valid birth date.',
  '保存データを表示できませんでした。': 'Could not display saved data.',
  '保存プロフィール': 'Saved profiles',
  '一覧を更新': 'Refresh list',
  '確認中...': 'Checking…',
  '保存したプロフィールはありません。': 'No saved profiles yet.',
  'プロフィールを削除しますか？': 'Delete this profile?',
  'プロフィールを削除': 'Delete profile',
  '反映': 'Apply',
  '出生地未入力': 'Birthplace not entered',
  '出生時間': 'Birth time',
  '出生地': 'Birthplace',
  '出生地未設定': 'Birthplace not set',
  'プロフィールを保存しました': 'Profile saved.',
  '趣味・悩みなどの反映をオンにしました':
      'Profile interests and concerns are now included in your reading.',
  '趣味・悩みなどの反映をオフにしました':
      'Profile interests and concerns are no longer included in your reading.',

  // Share-card editor and image sharing.
  '共有カードを整える': 'Customize share card',
  '数値と説明はそのままに、見せ方だけを自分用にできます。':
      'Personalize the look while keeping the scores and explanations unchanged.',
  '表示名（任意）': 'Display name (optional)',
  'ひとこと（任意）': 'Short note (optional)',
  '点数を表示': 'Show score',
  'カードのテーマ': 'Card theme',
  '壁紙を変更': 'Change wallpaper',
  '壁紙を選ぶ': 'Choose wallpaper',
  'カスタム壁紙を削除': 'Remove custom wallpaper',
  '鑑定文を表示': 'Show reading text',
  '画像を作成中…': 'Creating image…',
  'この画像を共有': 'Share this image',
  '壁紙を読み込めませんでした。別の画像でお試しください。':
      'Could not load the wallpaper. Try another image.',
  '共有画像の準備ができませんでした。画面を開き直してください。':
      'Could not prepare the share image. Reopen this screen.',
  '共有画像を作成できませんでした': 'Could not create the share image.',
  '共有画像を作成できませんでした。もう一度お試しください。':
      'Could not create the share image. Please try again.',
  '共有機能を開けませんでした。アプリを更新してもう一度お試しください。':
      'Could not open sharing. Update the app and try again.',
  '共有の準備に失敗しました。もう一度お試しください。': 'Could not prepare sharing. Please try again.',

  // Backup, restore, and support dialogs.
  'バックアップJSONを出力中…': 'Exporting backup JSON…',
  'ぱんちょ式星占い バックアップ': 'Pancyo Astrology backup',
  'ぱんちょ式星占いのバックアップです。': 'Pancyo Astrology backup file.',
  'バックアップJSONを出力できませんでした。': 'Could not export the backup JSON.',
  'バックアップを復元': 'Restore backup',
  'バックアップJSONの中身を全選択して貼り付けます。現在の保存プロフィールと共有設定はバックアップ内容で置き換わります。':
      'Select and paste the full contents of the backup JSON. Saved profiles and sharing settings will be replaced with the backup contents.',
  'バックアップJSONを貼り付け': 'Paste backup JSON',
  '置き換えて復元': 'Replace and restore',
  'バックアップを復元中…': 'Restoring backup…',
  '復元しました。アプリを開き直して人物を確認してください。':
      'Restored. Reopen the app to check your profiles.',
  '復元しました。出生データ画面で人物を確認してください。':
      'Restored. Check your profiles on the birth details screen.',
  'バックアップの形式や内容を確認できませんでした。現在のデータは変更していません。':
      'The backup format or contents could not be verified. Your current data was not changed.',
  '復元に失敗しました。復元前のデータは保たれています。':
      'Restore failed. Your data from before the restore is intact.',
  '復元に失敗しました。元の状態へ戻せたか確認できません。プロフィールと設定を確認し、バックアップJSONは削除しないでください。':
      'Restore failed, and the original state could not be verified. Check your profiles and settings, and keep the backup JSON.',
  '別のデータ保存処理中です。完了してから試してください。':
      'Another data-saving operation is in progress. Try again when it finishes.',
  'バックアップを確認できませんでした。': 'Could not verify the backup.',
  '不具合報告のひな形をコピーしました。': 'Copied the issue-report template.',
  'データと不具合報告': 'Data and issue reports',
  '保存プロフィールと共有カード設定をJSONファイルへバックアップできます。復元はファイル内の文字を全選択して貼り付けます。':
      'Back up saved profiles and share-card settings to a JSON file. To restore, select and paste all text from the file.',
  'バックアップ': 'Back up',
  '復元': 'Restore',
  '不具合報告をコピー': 'Copy issue report',
  '不具合報告: コピー後に、このチャットや連絡先へ貼り付けてください。起きたこと、操作手順、可能ならスクリーンショットも添えると確認が早くなります。':
      'Issue report: After copying, paste it into this chat or a support message. Include what happened, the steps to reproduce it, and a screenshot if possible.',

  // Relationship form labels and non-generated method limits in this research copy.
  '今回のみ入力（保存しない）': 'Enter for this time only (not saved)',
  'プロフィールを入力': 'Enter profile details',
  '呼び名（任意）': 'Name (optional)',
  '生年月日': 'Date of birth',
  '出生時刻（不明なら空欄）': 'Birth time (leave blank if unknown)',
  '例 14:30': 'e.g., 14:30',
  '分からない場合は、空欄のままで大丈夫です。':
      'If you do not know the time, you can leave this blank.',
  '例 東京都、または緯度,経度': 'e.g., Tokyo, or latitude,longitude',
  '二人のプロフィール': 'Two profiles',
  '二人の入力': 'Enter two people',
  '一人目': 'Person 1',
  '二人目': 'Person 2',
  'ふたりの星から、関係のヒントを。': 'Relationship insights from both charts',
  '配置を計算しています…': 'Calculating placements…',
  '相性を読み解く': 'Explore your relationship',
  '計算を中止': 'Cancel calculation',
  'この読みの前提': 'About this reading',
  '相性を成功率や点数で表しません。':
      'This reading does not give compatibility a score or success rate.',
  '入力した出生日時は日本標準時（JST）として扱います。海外の現地時刻からの時差変換は行いません。':
      'Entered birth dates and times are treated as Japan Standard Time (JST). Local times abroad are not converted.',
  '出生地は国内登録地点または緯度・経度で認識します。この読みでは場所を計算に使わず、ASC・MC・ハウスも扱いません。':
      'Birthplace is recognized as a supported location in Japan or as latitude and longitude. This reading does not use location, the Ascendant, the Midheaven, or houses.',
  '出生時刻が一人でも不明なら正午を仮の計算時刻に使い、月は二人とも除外します。正午を実際の出生時刻として記録しません。':
      'If either birth time is unknown, noon is used as a temporary calculation time and the Moon is excluded for both people. Noon is not recorded as the actual birth time.',
  '伝統的な7天体と主要5アスペクト、固定オーブ5°以内だけを使います。':
      'This reading uses the traditional seven planets and five major aspects with a fixed 5° orb.',
  '読み解きの要約': 'Reading summary',
  '出生時刻が不明な人がいるため、月の配置は二人とも含めていません。':
      'Because one birth time is unknown, Moon placements are excluded for both people.',
  '話し合いのヒント': 'Conversation idea',
  'ふたりで確かめたいこと': 'Something to explore together',
  '配置の根拠を表示': 'Show placement evidence',
  '角度差 ': 'Orb ',
  '占星術の伝統的な象徴解釈であり、相手の性格や関係の結果を確定するものではありません。大切な判断は本人同士の対話や現実の状況をもとにしてください。':
      'This is a traditional symbolic interpretation of astrology; it does not determine another person’s character or the outcome of a relationship. Make important decisions through conversation and with your real-world circumstances in mind.',

  // Fixed main-screen text and supported-place display labels (English copy).
  // Place translations are display labels only; keep original values for input.
  '今日の星': 'Today\'s sky',
  'はじめての方へ': 'Getting started',
  '生年月日を選び、ホロスコープを読むと毎日・週・月・年の占いを確認できます。':
      'Choose your birth date and open your horoscope to explore daily, weekly, monthly and yearly readings.',
  '今日の星を、あなたの物語として読む。': 'Read today\'s sky as part of your own story.',
  '生まれた星と今日の星を重ね、恋愛・仕事・心の流れをやさしく読み解きます。':
      'We bring your birth chart and today\'s sky together for gentle insights into love, work and your inner life.',
  '本格的な占星術': 'In-depth astrology',
  '最新の天体データ': 'Up-to-date planetary data',
  'やさしい星の解説': 'Clear explanations of the stars',
  'ぱんちょ式 超本格占星術占い\n© 2026 pancyo Astrology / AGPL-3.0-or-later':
      'Pancyo In-depth Astrology\n© 2026 pancyo Astrology / AGPL-3.0-or-later',
  '健康・メンタル運': 'Health and mental well-being',
  '全アスペクト表を開く': 'Open all aspects',
  'この日の主要アスペクト': 'Major aspects on this day',
  'この日は主要アスペクトの影響が弱めです。大きく動かすより、普段の調整を丁寧にすると流れが整います。':
      'Major aspects have a weaker influence on this day. Careful everyday adjustments may be more helpful than big moves.',
  '空の星同士の流れ': 'Patterns between transiting planets',
  'グランドトライン': 'Grand trine',
  'Tスクエア': 'T-square',
  'グランドクロス': 'Grand cross',
  'ヨッド': 'Yod',
  'ブーメラン（ヨッド）': 'Boomerang Yod',
  'ミスティックレクタングル（ダイヤモンド）': 'Mystic rectangle (diamond)',
  'クレイドル（ゆりかご）': 'Cradle',
  'ハンマー・オブ・ソー': 'Thor’s hammer',
  'グランドセクスタイル': 'Grand sextile',
  '今日の星の配置': 'Today\'s placements',
  '今日のリターン': 'Today\'s returns',
  '全アスペクト詳細表': 'Full aspect details',
  '日時を変更': 'Change date and time',
  '指定日時のアスペクトはありません。': 'No aspects for the selected date and time.',
  '現在の天体位置': 'Current planetary positions',
  '出生図との全アスペクト': 'All aspects to the natal chart',
  '空の星同士の全アスペクト': 'All aspects between transiting planets',
  'ハウス通過': 'House transits',
  '逆行・月ボイド・複合配置': 'Retrogrades, void Moon and aspect patterns',
  'ボイドタイム': 'Void-of-course times',
  '星のリターン補正': 'Planetary return adjustments',
  'この日は強いリターン補正は出ていません。通常のトランジットとハウス通過を中心に読みます。':
      'No strong return adjustments appear on this day. The reading focuses on ordinary transits and house passages.',
  '出生図の反応ポイント': 'Sensitive points in your natal chart',
  '角ハウスの星': 'Planets in angular houses',
  '星の集中': 'Planetary concentrations',
  '木星×金星': 'Jupiter × Venus',
  '補正の読み方: 木星は総合・金運、金星は恋愛・金運、水星と土星は仕事、月と海王星は健康・メンタルを中心に反映。出生図のハウス、ステリウム、アスペクト、リターン、逆行、月の通過が重なるほど影響を強めますが、同じ要素は重複加点しないよう調整します。':
      'How adjustments work: Jupiter mainly affects overall and money scores; Venus affects love and money; Mercury and Saturn affect work; and the Moon and Neptune affect health and mental well-being. Overlapping natal houses, stelliums, aspects, returns, retrogrades and lunar transits strengthen the influence, with adjustments to avoid counting the same factor twice.',
  '判断を急がず整える流れ': 'Take time to review before deciding',
  '月相': 'Moon phase',
  '支配': 'Domicile',
  'フォール': 'Fall',
  '損傷': 'Detriment',
  '高揚': 'Exaltation',
  'コンジャンクション': 'Conjunction',
  'セクスタイル': 'Sextile',
  'スクエア': 'Square',
  'トライン': 'Trine',
  'セスキコードレート': 'Sesquiquadrate',
  'クインカンクス': 'Quincunx',
  'オポジション': 'Opposition',
  'かなり強い運気': 'Very strong outlook',
  '良い運気': 'Favorable outlook',
  '安定した運気': 'Steady outlook',
  '整えたい運気': 'Time to regroup',
  '慎重に扱う運気': 'Proceed with care',
  '反映した根拠': 'Factors used in this reading',
  'この点数の理由': 'Why this score?',
  '詳細を見る': 'View details',
  '加点・減点の内訳': 'Positive and negative score adjustments',
  '検証用の予測を保存': 'Save a prediction for validation',
  '氏名・出生日時・出生地・日記は含みません。出生図の星座・ハウス・角度などの計算根拠は含まれるため、保存先を確認してください。端末時計の時刻は事前予測の証明にはなりません。':
      'This file excludes names, birth dates and times, birthplaces and diary entries. It includes calculated natal signs, houses and angles, so check where you save it. A device-clock timestamp does not prove a prediction was made in advance.',
  '続ける': 'Continue',
  '予測JSONの作成・共有が完了しませんでした。日付・保存先を確認して再度お試しください。':
      'Could not finish creating or sharing the prediction JSON. Check the date and destination, then try again.',
  '翌日以降・日本時間12時の予測を保存できます':
      'Save predictions for tomorrow or later, calculated for noon in Japan',
  '総合運は恋愛・仕事・金運・メンタル・健康・対人の6分野を平均します。活動性と体感は含みません。一般向け暫定式・未検証です。':
      'The overall score averages six areas: love, work, money, mental well-being, health and relationships. Activity and felt experience are excluded. This general-purpose formula is provisional and unvalidated.',
  '各日の前半5項目と同じ12:00 JSTの点数です。全項目が一般向け暫定式・未検証です。':
      'Scores use the same 12:00 JST reference as the first five areas for each day. All areas use provisional, unvalidated formulas for general use.',
  '各日の占いカードと同じ12:00 JSTの点数です。':
      'Scores use the same 12:00 JST reference as each day’s reading card.',
  '選択日から7日間、各日の12:00 JST。試作・未検証です。':
      'Seven days from the selected date, at 12:00 JST each day. Prototype; not validated.',
  'この日のヒント': 'A tip for this day',
  '従来版の詳しい本文・点数根拠': 'Detailed legacy reading and score evidence',
  '従来の心身点も含む参考表示。新しい9項目の点数とは区別してください。':
      'Reference information includes the legacy combined mind-and-body score. Keep it separate from the newer nine-area scores.',
  '現行版の総合運：恋愛・仕事・金運・健康・メンタルの4分野を平均しています。':
      'This version\'s overall score averages four areas: love, work, money and combined health/mental well-being.',
  '7日間の運勢の流れ': 'Your seven-day outlook',
  '週間占い': 'Weekly reading',
  '月間占い': 'Monthly reading',
  '年間占い': 'Yearly reading',
  '週': 'Week',
  '期間を選ぶ': 'Choose a period',
  '占う期間を選択': 'Select a reading period',
  '前年': 'Previous year',
  '前週': 'Previous week',
  '前月': 'Previous month',
  '翌年': 'Next year',
  '翌週': 'Next week',
  '翌月': 'Next month',
  '今年': 'This year',
  '読み替え中…': 'Updating the period…',
  '期間の星配置を準備できませんでした。':
      'Could not prepare the planetary placements for this period.',
  '期間の準備を中止しました。': 'Period preparation was cancelled.',
  '同じ年の12か月分を計算するため、読み込みに少し時間がかかります。':
      'Loading takes a little longer because all 12 months in the same year are calculated.',
  '運勢の流れグラフは必要なときだけ読み込みます。': 'The trend chart loads only when you need it.',
  'グラフの読み込みを中止しました。': 'Chart loading was cancelled.',
  'グラフを読み込めませんでした。もう一度お試しください。': 'Could not load the chart. Please try again.',
  '1週間ごとの4週間': 'Four weeks, one week at a time',
  '4週間の推移は、各週7日・12:00 JSTの一般向け暫定式9項目を集計。':
      'The four-week trend aggregates nine provisional general-purpose areas across seven days per week, using 12:00 JST.',
  '同じ年の12か月分の月間占いカードと同じ点数から、月ごとの流れを反映。':
      'The monthly trend uses the same scores as the 12 monthly reading cards for that year.',
  '各週の7日分を集計した期間点・体感候補です。試作・未検証です。':
      'Period scores and felt-experience candidates aggregate seven days for each week. Prototype; not validated.',
  '各年の24時点を集計した期間点・体感候補です。試作・未検証です。':
      'Period scores and felt-experience candidates aggregate 24 points for each year. Prototype; not validated.',
  '各月の5時点を集計した期間点・体感候補です。試作・未検証です。':
      'Period scores and felt-experience candidates aggregate five points for each month. Prototype; not validated.',
  '研究：点数の仮案を比較': 'Research: Compare score prototypes',
  '研究・点数の仮案を比較': 'Research: Compare score prototypes',
  '点数の仮案を比較': 'Compare score prototypes',
  '未検証の研究用です。元の点数は変更しません。点数が上がっても、当たりやすくなったことを意味しません。':
      'For research only; unvalidated. Original scores are unchanged. A higher score does not mean a reading is more accurate.',
  '詳しく見る仮案': 'Prototype to inspect',
  'A：良悪の材料が多い3群': 'A: Top three positive/negative groups',
  'B：全ての方向群を残す': 'B: Keep all directional groups',
  '項目': 'Area',
  '金運': 'Money',
  '心': 'Mental well-being',
  '健康': 'Health',
  '対人': 'Relationships',
  '行動': 'Activity',
  '元の点数': 'Original score',
  '仮案A（差）': 'Prototype A (change)',
  '仮案B（差）': 'Prototype B (change)',
  'Aは、良い面と難しい面の材料が多い天体の上位3群を使います。':
      'Prototype A uses the top three planetary groups with the most supportive and challenging evidence.',
  'Bは、方向性がある全ての天体群を使い、4群以上は3÷群数で調整します。全群を残す設計理由から、この比較画面の初期表示に選んでいます。':
      'Prototype B uses every planetary group with a directional signal, scaling four or more groups by 3 divided by the group count. It is the initial choice on this comparison screen because the design retains all groups.',
  '総合は6分野の丸め前平均です。行動運と正規の体感は変更していません。':
      'The overall score is the unrounded mean of six areas. Activity and the canonical felt rating are unchanged.',
  '一般向けの採用判断は保留です。仮JSONの研究比較欄にも元の点数・仮案・差・計算の根拠を分けて残します。':
      'Adoption for general use remains on hold. The prototype JSON also keeps the original score, prototype, difference and calculation rationale separate in its research-comparison field.',
  '保留': 'Hold',
  '新月': 'New Moon',
  '満ちていく三日月': 'Waxing crescent',
  '上弦の月': 'First quarter',
  '満ちていく凸月': 'Waxing gibbous',
  '満月': 'Full Moon',
  '欠けていく凸月': 'Waning gibbous',
  '下弦の月': 'Last quarter',
  '欠けていく三日月': 'Waning crescent',
  '今日の星イベント（JST）': 'Today\'s sky events (JST)',
  '本格・星の解説': 'Detailed astrology guide',
  '星の解説': 'Astrology guide',
  '占いで使う星の配置を読む': 'Explore the planetary placements used in a reading',
  '主要な星をやさしく読む': 'Explore key planets in clear language',
  '出生図から読む、あなたらしい傾向': 'Explore your personal patterns through your birth chart',
  '出生図から読む、10年ごとの長い流れ':
      'Explore longer-term trends by decade through your birth chart',
  '今日': 'Today',
  'プロフィール未保存時はサンプル仮データとして12:00・北海道札幌市で計算しています。正確に見る場合は、出生時間と出生地をプロフィールに保存してください。':
      'Without a saved profile, sample calculations use noon and Sapporo, Hokkaido. Save your birth time and birthplace in your profile for a more specific reading.',
  '準備を再試行': 'Retry preparation',
  '準備を中止': 'Cancel preparation',
  'グラフを読む': 'Read the graph',
  '運勢の流れ': 'Trends over time',
  '読み込み中もスクロールや期間の切り替えができます。':
      'You can scroll or change the period while loading.',
  '読み込みを中止': 'Cancel loading',
  'グラフを再読み込み': 'Reload graph',
  '選択した月と同じ年の、各月の月間占い点数を表示しています。':
      'Shows monthly reading scores for each month in the same year as the selected month.',
  '現在の流れ': 'Current influences',
  '出生図への効き方': 'How this affects your natal chart',
  'ネイタル + トランジット': 'Natal + transits',
  'あなた': 'You',
  '人生の流れ': 'Life trends',
  '人生の軸・第一印象': 'Life direction and first impressions',
  '心のクセ・休み方': 'Emotional patterns and ways to rest',
  '恋愛・人との距離': 'Love and closeness',
  '仕事・得意な進め方': 'Work and your natural approach',
  'お金・伸び方': 'Money and growth',
  '出生図の目立つテーマ': 'Prominent natal themes',
  'あなたの出生図プロフィール': 'Your natal chart profile',
  'プロフィールを重ねた読み方': 'A reading with your profile in context',
  'プロフィールを重ねた人生の見方': 'A view of your life flow with your profile in context',
  '発信や創作を続けたい関心に重ねると、各10年の仕事・学び・仲間のテーマは、企画を育てる時期、外へ見せる時期、続け方を整える時期として使えます。':
      'With your interest in continuing to publish or create in mind, the themes of work, learning and community in each decade can help you identify when to develop ideas, share them and refine a sustainable way to continue.',
  '発信や創作を続けたい関心に重ねると、下の仕事・お金の資質は、企画の選び方、見せ方、続けられる制作量を決めるヒントとして使えます。':
      'With your interest in continuing to publish or create in mind, the strengths below in work and money can help you choose projects, present them and set a sustainable production pace.',
  '仕事や学びの関心に重ねると、各10年のテーマは、力を蓄える時期、役割を広げる時期、働き方を見直す時期として読むと活かしやすくなります。':
      'With your interest in work or learning in mind, each decade’s themes can be read as periods for building skills, expanding your role or reconsidering how you work.',
  '仕事や学びの関心に重ねると、下の資質は、得意な進め方、無理なく続く役割、学びを成果へつなげる方法として使えます。':
      'With your interest in work or learning in mind, the strengths below can help you find your natural way of working, choose a role you can sustain and turn learning into results.',
  '人との関係を大切にしたい関心に重ねると、各10年のテーマは、出会いを広げる時期、安心できる関係を選ぶ時期、自分の居場所を整える時期として読めます。':
      'With your interest in relationships in mind, each decade’s themes can be read as periods for broadening your connections, choosing secure relationships and building a place where you belong.',
  '人との関係を大切にしたい関心に重ねると、下の恋愛・心の項目は、安心できる距離感と、無理をしない関係の選び方として使えます。':
      'With your interest in relationships in mind, the love and emotional areas below can help you find a comfortable distance and choose relationships without overextending yourself.',
  'お金と生活を整えたい関心に重ねると、各10年のテーマは、収入の土台を作る時期、学びや経験へ配分する時期、守る仕組みを整える時期として使えます。':
      'With your interest in money and daily life in mind, each decade’s themes can help you identify when to build an income base, invest in learning and experience, and put protective systems in place.',
  'お金と生活を整えたい関心に重ねると、下の仕事・お金の資質は、得意を収入へつなげる方法と、無理のない使い方の目安になります。':
      'With your interest in money and daily life in mind, the work and money strengths below offer ways to turn your strengths into income and a guide to spending within your means.',
  '心身の余力を大切にしたい関心に重ねると、各10年のテーマは、広げる時期と休む時期を分け、生活の土台を守りながら進むための目安になります。':
      'With your interest in preserving your energy in mind, each decade’s themes can help you distinguish periods for growth and rest, and move forward while protecting the foundations of daily life.',
  '心身の余力を大切にしたい関心に重ねると、下の心のクセ・休み方は、頑張る量と回復の仕方を自分に合う形へ整えるヒントになります。':
      'With your interest in preserving your energy in mind, the emotional patterns and ways to rest below offer ideas for adjusting effort and recovery to suit you.',
  '入力した性格や大切にしたいことに重ねると、各10年のテーマは、今の自分にとって何を育て、何を見直す時期かを選ぶ目安になります。':
      'With your personality and priorities in mind, each decade’s themes offer a guide to what to develop and reconsider for who you are now.',
  '入力した性格や大切にしたいことに重ねると、下の出生図プロフィールは、得意な使い方と無理をしやすい場面を見分けるヒントになります。':
      'With your personality and priorities in mind, the birth-chart profile below can help you distinguish where your strengths work well and where you may tend to overextend yourself.',
  '10年ごとの人生の流れ': 'Life trends by decade',
  '出生時間・出生地が未入力のため、年代の人生分野は目安です。入力すると、仕事・対人・居場所などの読み分けがより正確になります。':
      'Without a birth time and birthplace, life areas for each decade are approximate. Adding them makes distinctions such as work, relationships and home more specific.',
  '今の10年': 'This decade',
  '次の10年': 'Next decade',
  '今ここ': 'You are here',
  'ネイタル': 'Natal',
  'トランジット': 'Transit',
  '星の影響度': 'Strength of influence',
  '今週の月の影響予報': 'This week\'s lunar outlook',
  '月の動きが気分や生活リズムへ表れやすい日を先に示します。良い悪いではなく、予定の組み方に使う目安です。':
      'Highlights days when lunar movements may be more noticeable in your mood or daily rhythm. Use it to plan your schedule, rather than label days good or bad.',
  '直感、創作、休息、気持ちの整理に使いやすい日です。予定を詰めすぎず、余白を先に置くと整います。':
      'A day suited to intuition, creativity, rest and sorting through feelings. Leave some room in your schedule instead of filling every moment.',
  '気分が安定しやすいので、決めることや続けたい習慣を一つ進めるのに向きます。':
      'A steadier mood may help you make a decision or take one step with a habit you want to keep.',
  '気になる星のカードをタップすると、意味をやさしく詳しく読めます':
      'Tap a planet card for a clear, detailed explanation',
  '生まれ持った主要配置': 'Key natal placements',
  '詳しい意味は下の各星カードで確認できます。': 'Explore each planet card below for more detail.',
  '本日の主要配置': 'Today\'s key placements',
  'ほかの配置は下の各カードと「全アスペクト表」で確認できます。':
      'Find other placements in the cards below and the full aspect table.',
  '逆行': 'Retrograde',
  'タップして詳しく読む': 'Tap to explore',
  '鑑定エンジンの見る範囲': 'What the reading engine covers',
  '出生図の太陽': 'Natal Sun',
  '出生図の月': 'Natal Moon',
  '出生図の金星': 'Natal Venus',
  '入力出生地': 'Entered birthplace',
  '計算地点': 'Calculation location',
  '星データ': 'Planetary data',
  '計算精度': 'Calculation precision',
  '現在の星': 'Current sky',
  '集中補正': 'Concentration adjustment',
  'ボイド/リターン': 'Void Moon / returns',
  '鑑定を作成できませんでした。会話欄の案内をご確認ください。':
      'Could not create the reading. Check the guidance in the chat area.',
  '鑑定ナビ（会話式）': 'Conversational reading guide',
  '鑑定ナビを閉じる': 'Close reading navigator',
  '鑑定ナビを開く': 'Open reading navigator',
  '鑑定を送信': 'Send reading',
  '注意点を見たい日を選択': 'Select a date to review',
  '星の流れを踏まえて、続けて相談できます。恋愛の時期、向く仕事、今の選択などを聞いてください。':
      'Ask follow-up questions informed by the current sky: timing in love, suitable work, choices you are facing and more.',
  '星の配置を確認しています…': 'Checking planetary placements…',
  'テーマ・期間・知りたい結論を選ぶと、会話のまま星の根拠と行動まで詳しく読めます。':
      'Choose a theme, period and question to explore astrological evidence and practical steps in conversation.',
  'いまの状況': 'Current situation',
  '知りたい結論': 'What you want to understand',
  '対象期間': 'Time period',
  '聞きたいこと': 'Your question',
  'テーマ': 'Topic',
  '総合': 'Overall',
  '恋愛': 'Love',
  '仕事': 'Work',
  'お金': 'Money',
  '心と体': 'Mind & body',
  '新しく始めること': 'Something new',
  '続けていること': 'Something ongoing',
  '人との関係': 'Relationships',
  '結果・評価': 'Outcomes & feedback',
  'お金・生活の整え方': 'Money and daily-life balance',
  '今どう動く？': 'What can I do now?',
  '注意点': 'Things to consider',
  '良い時期': 'Favorable timing',
  '比較する': 'Compare options',
  '長期の流れ': 'Long-term trends',
  '今週': 'This week',
  '今月': 'This month',
  '今後3か月': 'Next 3 months',
  '今後1年': 'Next year',
  '今後5年': 'Next 5 years',
  '3暦月': '3 calendar months',
  '今年（暦年）': 'This calendar year',
  '5暦年': '5 calendar years',
  '星をもう少し詳しく読む': 'Explore the sky in more detail',
  '星のカレンダー': 'Astrology calendar',
  '一人用の鑑定ナビ': 'Personal reading guide',
  'カレンダーは選んだ日の星の動き、鑑定ナビは今日を基準にしたテーマ別相談です。':
      'The calendar shows the sky for a selected day. The reading guide offers topic-based readings for today.',
  '良い時期は短期（今週〜今後3か月）のピークを見ます。年単位の流れは「長期の流れ」を選んでください。':
      'Favorable timing uses short-term peaks, from this week to the next three months. Choose long-term trends for a view across years.',
  'この内容で鑑定': 'Read with these details',
  '質問例': 'Example questions',
  '選ぶと入力欄へ入ります。送信前に自由に直せます。':
      'Choose an example to fill the input. You can edit it before sending.',
  '今日の恋愛運と連絡のタイミングは？': 'What does today look like for love and reaching out?',
  '今日、いちばん進めると良い作業は？': 'Which task would be useful to move forward today?',
  '今日、大きな買い物をしてもいい？': 'Is today a good time for a major purchase?',
  '今日、疲れをためない過ごし方は？': 'How can I avoid building up fatigue today?',
  '今日の流れを活かす一手は？': 'What is one way to work with today’s flow?',
  '今日、動画を公開していい？': 'Should I publish a video today?',
  '今週、資格の勉強を始めてもいい？': 'Should I begin studying for a qualification this week?',
  '今月、出会いに向く時期は？': 'When this month may be suitable for meeting someone?',
  '恋愛と仕事、今はどちらを優先する？': 'Which should I prioritize now: love or work?',
  '今週、副業を始めてもいい？': 'Should I start a side project this week?',
  '今月の金運と大きな買い物は？':
      'What does this month suggest about money and a major purchase?',
  '睡眠を整えるのに向く時期は？': 'When may be a good time to improve my sleep routine?',
  '太陽が第1ハウスだと恋愛運は？': 'What does the Sun in the first house mean for love?',
  '最高潮': 'Peak',
  '好調': 'Favorable',
  '安定': 'Steady',
  '調整': 'Adjustment',
  '慎重': 'Caution',
  '占星術の読みをあなた向けに整える情報': 'Information to personalize your astrology reading',
  '占いとの付き合い方': 'Using astrology thoughtfully',
  'このアプリの占いは、毎日を少し見つめ直すためのヒントです。結果の通りにしなければいけないものではなく、人生の大切な判断を代わりに決めるものでもありません。':
      'These readings offer prompts for reflecting on everyday life. You do not have to follow them, and they do not make important life decisions for you.',
  '恋愛、仕事、お金、人間関係の判断は、現実の状況と自分の意思を優先してください。':
      'For decisions about love, work, money and relationships, put your real circumstances and your own wishes first.',
  '医療、法律、投資、緊急性のある悩みは、必ず専門家や公的な相談先を頼ってください。':
      'For medical, legal, investment or urgent concerns, seek help from qualified professionals or appropriate public services.',
  '不安が強い時、占いを見るほど苦しくなる時は、少し距離を置いて休むことも大切です。':
      'If astrology makes you more anxious or distressed, take a break and give yourself some space.',
  '出生時間を00:00〜23:59で入力してください。': 'Enter a birth time from 00:00 to 23:59.',
  'あとで追加するプロフィール': 'Profile details to add later',
  '出生時間と出生地を書くと、月とハウスの読みが安定します。北海道の主要都市名は内部座標へ自動変換します。未入力や未対応住所の時は12:00・北海道札幌市で仮計算します。':
      'A birth time and birthplace make Moon and house readings more consistent. Major Hokkaido city names are matched to stored coordinates. Missing or unsupported details use noon and Sapporo, Hokkaido, as temporary calculation values.',
  'タップして選択 / 不明なら空欄': 'Tap to choose / leave blank if unknown',
  '市区町村名・住所・緯度経度 / 例）北海道釧路市':
      'City, address or coordinates / e.g., Kushiro, Hokkaido',
  '趣味・悩みなどを占いへ反映する': 'Use interests and concerns in readings',
  '性格・大切にしていること': 'Personality and what matters to you',
  '好きなことや普段の活動を書いてください。動画制作・学習など、対応する話題を助言の例に使います。':
      'Describe your interests and everyday activities. Supported topics, such as making videos or studying, are used as examples in advice.',
  '困っていることや避けたいことを書いてください。休息の優先や転職を望まない希望などを助言に使います。':
      'Describe concerns or things you want to avoid. Supported preferences, such as prioritizing rest or not wanting to change jobs, guide the advice.',
  '「丁寧に」「やさしく」などの希望を書けます。本文の詳しさは本格／簡潔で切り替えます。':
      'You can request a polite or gentle tone. Use Detailed or Concise to choose how much explanation appears.',
  '例）慎重だけど、好きなことには一気に集中する':
      'e.g., Cautious, but deeply focused on things I love',
  '今の悩み・気になっているテーマ': 'Current concerns or themes',
  '例）仕事の方向性、恋愛、人間関係、お金の使い方':
      'e.g., Career direction, love, relationships or spending',
  '占いで特に見てほしいこと': 'What you would like from a reading',
  '例）背中を押してほしい / 現実的に整理してほしい': 'e.g., Encouragement / a practical perspective',
  'ハウス方式': 'House system',
  '出生地・出生時刻から不均等なカスプを計算':
      'Calculate unequal house cusps from birthplace and birth time',
  'ASCのある星座全体を第1ハウスにする':
      'Use the entire sign containing the Ascendant as the first house',
  '出生地と出生時刻が入力されている時の、天体が入るハウスの計算方法です。Placidusを標準にしています。':
      'The method used to calculate planetary houses when birth time and birthplace are available. Placidus is the default.',
  '文字サイズ': 'Text size',
  '画面の文字を見やすく調整できます。大きくすると一部の画面は縦に長くなるため、必要に応じてスクロールしてください。':
      'Adjust the text for readability. Larger text may make some screens taller; scroll when needed.',
  '標準': 'Standard',
  '大きめ': 'Large',
  '特大': 'Extra large',
  'Android版の星計算にはSwiss Ephemeris Free Editionを使います。このアプリはAGPL条件に合わせ、ソース公開前提で整備しています。':
      'The Android version uses Swiss Ephemeris Free Edition for planetary calculations. This app is being prepared for source publication under the AGPL terms.',
  'AGPL': 'AGPL',
  '確認対象': 'To be reviewed',
  'Swiss Ephemeris Free EditionをAndroidネイティブ組み込み。公式ソースはthird_party/swissephに配置済み。':
      'Swiss Ephemeris Free Edition is integrated natively on Android. Its official source is included in third_party/swisseph.',
  'Swiss EphemerisのAGPL条件に合わせ、配布時は対応するソースコードを公開します。':
      'The corresponding source code will be published when the app is distributed, in accordance with Swiss Ephemeris’s AGPL terms.',
  '使用パッケージとライセンス表記をリリース前に一覧化します。':
      'Packages used and their license notices will be inventoried before release.',
  'アプリ本体': 'Application',
  'Flutter / ライブラリ': 'Flutter / libraries',
  'Swiss公式': 'Swiss Ephemeris website',
  'アプリのソース': 'App source code',
  'Swissソース': 'Swiss Ephemeris source code',
  'ライセンス情報': 'License information',
  'この人物のチャット式カスタム鑑定ログだけをすべて削除します。この操作は元に戻せません。':
      'Delete all conversational reading logs for this person only. This cannot be undone.',
  '消去': 'Erase',
  'チャット式カスタム鑑定ログを消去しました': 'Conversational reading logs erased',
  '全消去': 'Erase all',
  'すべて見る': 'View all',
  'この鑑定ログを削除しますか？': 'Delete this reading log?',
  'この1件の相談内容と回答を削除します。この操作は元に戻せません。':
      'Delete this question and its answer. This cannot be undone.',
  'チャット式カスタム鑑定ログを削除しました': 'Conversational reading log deleted',
  '保存されているチャット式カスタム鑑定ログはありません。': 'No saved conversational reading logs.',
  '作者プロフィール': 'About the creator',
  'ぱんちょ\n\n': 'Pancyo\n\n',
  'ぱんちょ\n\n'
          '北海道出身のミュージシャン兼小説家。\n\n'
          '音楽、小説、そして占星術を愛し、日々の出来事や創作活動とホロスコープを照らし合わせながら、独自の「ぱんちょ式 超本格占星術」を研究・構築しています。\n\n'
          'このアプリでは、「当たる占い」だけではなく、「納得できる占い」を目指しています。\n\n'
          'あなたの人生を照らす、星の声を一緒に探してみませんか。':
      'Pancyo\n\n'
      'A musician and novelist from Hokkaido.\n\n'
      'Loving music, novels and astrology, I research and develop my own “Pancyo In-depth Astrology” by comparing everyday events and creative work with horoscopes.\n\n'
      'With this app, I aim not only for readings that “come true,” but for readings that “make sense.”\n\n'
      'Would you like to explore together the voice of the stars that illuminates your life?',
  'Kindle作品一覧': 'Kindle books',
  'プライバシーポリシー': 'Privacy policy',
  'Swiss公式 のリンクを開けませんでした': 'Could not open the Swiss Ephemeris website.',
  'アプリのソース のリンクを開けませんでした': 'Could not open the app source code.',
  'Swissソース のリンクを開けませんでした': 'Could not open the Swiss Ephemeris source code.',
  'AGPL のリンクを開けませんでした': 'Could not open the AGPL license page.',
  'YouTube のリンクを開けませんでした': 'Could not open the YouTube link.',
  'Kindle作品一覧 のリンクを開けませんでした': 'Could not open the Kindle books page.',
  'プライバシーポリシー のリンクを開けませんでした': 'Could not open the privacy policy.',
  '月の影響予報を画像で共有': 'Share the lunar influence forecast as an image',
  '月の影響度': 'Lunar influence',
  '主な都市から選ぶ': 'Choose a city',
  '緯度経度例': 'Coordinate examples',
  '出生地の主な都市': 'Birthplace cities',
  '地域を選んでから都市を選びます。選んだ市名は、ハウス計算用の内部座標へ自動変換されます。':
      'Choose a region, then a city. The selected city is matched to stored coordinates for house calculations.',
  '住所や市区町村名も入力できますが、未対応の出生地は北海道札幌市として仮計算します。正確にしたい時は候補を選ぶか、緯度経度を「43.0618,141.3545」の形で入力してください。':
      'You can also enter an address or city name, but unsupported birthplaces temporarily use Sapporo, Hokkaido. For a more specific location, select a listed city or enter coordinates such as 43.0618,141.3545.',
  '星の追い風': 'Supportive influences',
  '今日は自分の感覚を信じつつ、確認を一つ挟むと良い日です。':
      'Trust your instincts today, while adding one moment to double-check.',
  '今日のホロスコープを、あなたの物語として読む。':
      'Read today\'s horoscope as part of your own story.',
  '生まれた瞬間の星と、今日動いている星。その重なりから、恋愛・仕事・心の流れをやさしく深く読みます。':
      'The sky at your birth and the planets moving today come together for deeper, gentle insights into love, work and your inner life.',
  '今日の星読みプレビュー': 'Today\'s reading preview',
  '月は気持ちの奥にある本音を照らし、金星は人との距離感をやわらかく整えます。今日は「急がず、でも曖昧にしない」が合図です。':
      'The Moon brings deeper feelings into focus, while Venus softens the distance between people. Today\'s cue is to take your time without leaving things unclear.',
  '月の感情': 'The Moon and emotions',
  '金星の調和': 'Venus and harmony',
  '火星の行動力': 'Mars and initiative',
  '北海道札幌市': 'Sapporo, Hokkaido',
  '北海道旭川市': 'Asahikawa, Hokkaido',
  '北海道函館市': 'Hakodate, Hokkaido',
  '北海道釧路市': 'Kushiro, Hokkaido',
  '北海道帯広市': 'Obihiro, Hokkaido',
  '北海道北見市': 'Kitami, Hokkaido',
  '北海道苫小牧市': 'Tomakomai, Hokkaido',
  '北海道小樽市': 'Otaru, Hokkaido',
  '北海道江別市': 'Ebetsu, Hokkaido',
  '北海道千歳市': 'Chitose, Hokkaido',
  '北海道北広島市': 'Kitahiroshima, Hokkaido',
  '北海道室蘭市': 'Muroran, Hokkaido',
  '北海道岩見沢市': 'Iwamizawa, Hokkaido',
  '北海道網走市': 'Abashiri, Hokkaido',
  '北海道稚内市': 'Wakkanai, Hokkaido',
  '北海道根室市': 'Nemuro, Hokkaido',
  '北海道斜里郡小清水町美和': 'Miwa, Koshimizu, Shari District, Hokkaido',
  '青森県青森市': 'Aomori, Aomori',
  '青森県八戸市': 'Hachinohe, Aomori',
  '岩手県盛岡市': 'Morioka, Iwate',
  '宮城県仙台市': 'Sendai, Miyagi',
  '秋田県秋田市': 'Akita, Akita',
  '山形県山形市': 'Yamagata, Yamagata',
  '福島県福島市': 'Fukushima, Fukushima',
  '福島県郡山市': 'Koriyama, Fukushima',
  '福島県いわき市': 'Iwaki, Fukushima',
  '茨城県水戸市': 'Mito, Ibaraki',
  '茨城県つくば市': 'Tsukuba, Ibaraki',
  '栃木県宇都宮市': 'Utsunomiya, Tochigi',
  '群馬県前橋市': 'Maebashi, Gunma',
  '群馬県高崎市': 'Takasaki, Gunma',
  '埼玉県さいたま市': 'Saitama, Saitama',
  '埼玉県川越市': 'Kawagoe, Saitama',
  '千葉県千葉市': 'Chiba, Chiba',
  '千葉県船橋市': 'Funabashi, Chiba',
  '東京都八王子市': 'Hachioji, Tokyo',
  '神奈川県横浜市': 'Yokohama, Kanagawa',
  '神奈川県川崎市': 'Kawasaki, Kanagawa',
  '神奈川県相模原市': 'Sagamihara, Kanagawa',
  '新潟県新潟市': 'Niigata, Niigata',
  '新潟県長岡市': 'Nagaoka, Niigata',
  '富山県富山市': 'Toyama, Toyama',
  '石川県金沢市': 'Kanazawa, Ishikawa',
  '福井県福井市': 'Fukui, Fukui',
  '山梨県甲府市': 'Kofu, Yamanashi',
  '長野県長野市': 'Nagano, Nagano',
  '長野県松本市': 'Matsumoto, Nagano',
  '岐阜県岐阜市': 'Gifu, Gifu',
  '静岡県静岡市': 'Shizuoka, Shizuoka',
  '静岡県浜松市': 'Hamamatsu, Shizuoka',
  '愛知県名古屋市': 'Nagoya, Aichi',
  '愛知県豊田市': 'Toyota, Aichi',
  '三重県津市': 'Tsu, Mie',
  '滋賀県大津市': 'Otsu, Shiga',
  '京都府京都市': 'Kyoto, Kyoto',
  '大阪府大阪市': 'Osaka, Osaka',
  '大阪府堺市': 'Sakai, Osaka',
  '兵庫県神戸市': 'Kobe, Hyogo',
  '兵庫県姫路市': 'Himeji, Hyogo',
  '奈良県奈良市': 'Nara, Nara',
  '和歌山県和歌山市': 'Wakayama, Wakayama',
  '鳥取県鳥取市': 'Tottori, Tottori',
  '島根県松江市': 'Matsue, Shimane',
  '島根県出雲市': 'Izumo, Shimane',
  '岡山県岡山市': 'Okayama, Okayama',
  '岡山県倉敷市': 'Kurashiki, Okayama',
  '広島県広島市': 'Hiroshima, Hiroshima',
  '広島県福山市': 'Fukuyama, Hiroshima',
  '山口県山口市': 'Yamaguchi, Yamaguchi',
  '山口県下関市': 'Shimonoseki, Yamaguchi',
  '徳島県徳島市': 'Tokushima, Tokushima',
  '香川県高松市': 'Takamatsu, Kagawa',
  '愛媛県松山市': 'Matsuyama, Ehime',
  '高知県高知市': 'Kochi, Kochi',
  '福岡県福岡市': 'Fukuoka, Fukuoka',
  '佐賀県佐賀市': 'Saga, Saga',
  '長崎県長崎市': 'Nagasaki, Nagasaki',
  '熊本県熊本市': 'Kumamoto, Kumamoto',
  '大分県大分市': 'Oita, Oita',
  '宮崎県宮崎市': 'Miyazaki, Miyazaki',
  '鹿児島県鹿児島市': 'Kagoshima, Kagoshima',
  '沖縄県那覇市': 'Naha, Okinawa',
  '緯度経度指定': 'Custom coordinates',
};
