part of 'main.dart';

/// Presentation only: the sign is taken from the existing calculated placement.
/// These tendencies do not add an event, change a score, or alter saved text.
String readingMoonMood(ZodiacSign sign, AppLanguage language) {
  final (ja, en) = switch (sign) {
    ZodiacSign.aries => (
      '気持ちが前向きになり、すぐ動きたくなりやすい時。小さく始め、返事や判断は一呼吸おくと整います。',
      'You may feel more direct and eager to act. Start small, and pause before replying or deciding.',
    ),
    ZodiacSign.taurus => (
      '安心感や心地よさを求めやすい時。食事や休息、慣れた手順を大切にし、変化は少しずつ取り入れましょう。',
      'Comfort and steadiness may matter more. Make room for food, rest, and familiar routines; introduce change gradually.',
    ),
    ZodiacSign.gemini => (
      '好奇心が動き、話したり情報を集めたりしたくなりやすい時。短いやり取りを楽しみ、情報を増やしすぎない工夫を。',
      'Curiosity and conversation may lift your mood. Enjoy brief exchanges, and leave space away from information overload.',
    ),
    ZodiacSign.cancer => (
      '身近な人や居場所への思いが強まりやすい時。安心できる環境で気持ちを整え、相手の感情を抱え込みすぎないように。',
      'Home, belonging, and close relationships may feel more important. Seek a reassuring setting without taking on everyone else’s feelings.',
    ),
    ZodiacSign.leo => (
      '自分らしさを表したくなり、認められることが励みになりやすい時。好きなことを一つ形にし、相手へのねぎらいも言葉に。',
      'Self-expression and appreciation may brighten your mood. Make something you enjoy, and offer others a little recognition too.',
    ),
    ZodiacSign.virgo => (
      '細かいことに気づき、整えると落ち着きやすい時。片付けや準備を一つ進め、完璧を求めすぎず区切りをつけましょう。',
      'Noticing details and putting things in order may feel reassuring. Finish one practical task, then stop short of demanding perfection.',
    ),
    ZodiacSign.libra => (
      '人との調和や公平さを大切にしたくなりやすい時。対話で気持ちを整えつつ、自分の希望も一つ伝えてみましょう。',
      'Harmony and fairness may matter more. Talk things through, while making room to state one preference of your own.',
    ),
    ZodiacSign.scorpio => (
      '気持ちが深まり、信頼できるものに集中したくなりやすい時。静かな時間や率直な対話を選び、結論を急がずに。',
      'Feelings may deepen, with a wish to focus on what you trust. Choose quiet time or an honest conversation, and let conclusions take time.',
    ),
    ZodiacSign.sagittarius => (
      '気分を広げ、新しいことを試したくなりやすい時。学びや外の景色に触れ、予定は余裕を残して組みましょう。',
      'Fresh experiences and a wider perspective may lift your spirits. Explore or learn something, while leaving room in your schedule.',
    ),
    ZodiacSign.capricorn => (
      'やるべきことを進めると安心しやすい時。現実的な目標を一つ決め、責任を抱えすぎず休む時間も確保しましょう。',
      'Making practical progress may help you feel settled. Set one realistic goal, and balance responsibility with time to rest.',
    ),
    ZodiacSign.aquarius => (
      '少し距離を置いて考え、自分らしい方法を試したくなりやすい時。新しい視点を取り入れ、気持ちも言葉で補いましょう。',
      'You may want space to think and try your own approach. Welcome a fresh perspective, and put your feelings into words as well.',
    ),
    ZodiacSign.pisces => (
      '周囲の空気やイメージに敏感になりやすい時。音楽や休息で気持ちを整え、頼まれごとは自分の余力を確かめてから。',
      'Atmosphere and imagination may affect you more easily. Restore yourself with music or rest, and check your capacity before taking on requests.',
    ),
  };
  return language == AppLanguage.en ? en : ja;
}

/// Only recognizes the app's own canonical Moon event rows. Arbitrary input
/// and all underlying event times/signs remain untouched.
String? readingMoonEventDisplayCopy(String event, AppLanguage language) {
  final current = RegExp(
    r'^(12:00)　月は(.+?)：気分と行動のペースをここで確認$',
  ).firstMatch(event);
  final ingress = RegExp(r'^(\d{2}:\d{2})　月が(.+?)へ：気分の切替$').firstMatch(event);
  final match = current ?? ingress;
  if (match == null) return null;
  ZodiacSign? sign;
  for (final candidate in ZodiacSign.values) {
    if (candidate.label == match.group(2)) sign = candidate;
  }
  if (sign == null) return null;
  final mood = readingMoonMood(sign, language);
  final time = match.group(1)!;
  if (language == AppLanguage.en) {
    return ingress == null
        ? '$time JST — Moon in ${_signNameEn(sign)}: $mood'
        : '$time JST — Moon enters ${_signNameEn(sign)}. From this time, the mood tendency shifts: $mood';
  }
  return ingress == null
      ? '$time　月は${sign.label}：$mood'
      : '$time　月が${sign.label}へ：ここからの気分の傾向。$mood';
}

/// The remaining fixed event templates are also display-only. Unknown rows
/// return null; user-authored text is never translated by this helper.
String? readingSkyAdditionalEventDisplayCopy(
  String event,
  AppLanguage language,
) {
  if (language == AppLanguage.ja) return null;
  final copy = _ReadingSkyCopy(language);
  final voidEvent = RegExp(
    r'^(\d{2}:\d{2})〜(\d{2}:\d{2})　月ボイド：大きな決定は急がず確認を$',
  ).firstMatch(event);
  if (voidEvent != null) {
    return '${voidEvent.group(1)}–${voidEvent.group(2)} JST — Moon void of course: Check the details before a major decision.';
  }
  const phases = {
    '新月': (
      '新しいことは小さく始め、意図を一つ決める',
      'New Moon: Start small and choose one intention.',
    ),
    '上弦の月': (
      '育てたいことを一つ行動に移す',
      'First Quarter: Take one step toward something you want to develop.',
    ),
    '満月': (
      '結果と気持ちが表れやすいので、振り返りと調整を',
      'Full Moon: Results and feelings may surface; make room to reflect and adjust.',
    ),
    '下弦の月': (
      '手放すことを一つ決め、次の準備をする',
      'Last Quarter: Choose one thing to release and prepare for what comes next.',
    ),
  };
  final phase = RegExp(r'^(\d{2}:\d{2})頃　(.+?)：(.+)$').firstMatch(event);
  if (phase != null) {
    final text = phases[phase.group(2)];
    if (text != null && text.$1 == phase.group(3)) {
      return 'Around ${phase.group(1)} JST — ${text.$2}';
    }
  }
  final stellium = RegExp(
    r'^12:00　空の(.+?)のステリウム（(.+?)）：そのテーマを一つに絞ると力にしやすい$',
  ).firstMatch(event);
  if (stellium != null) {
    for (final sign in ZodiacSign.values) {
      if (sign.label == stellium.group(1)) {
        return '12:00 JST — Stellium in ${copy.sign(sign)} (${copy.patternPlanets(stellium.group(2)!)}): Focus on one theme to make practical use of it.';
      }
    }
  }
  final rare = RegExp(r'^12:00　(.+)（(.+)）：(.+)$').firstMatch(event);
  const rareGuidance = {
    'Tスクエア':
        'Several demands may gather around one issue. Choose a clear priority.',
    'グランドクロス':
        'Competing demands may pull in several directions. Share roles and adjust the load.',
    'ヨッド': 'Small adjustments matter. Refine the conditions before deciding.',
    'ブーメラン（ヨッド）':
        'Outside challenges may prompt a change of direction. Adapt your approach to the response.',
    'ミスティックレクタングル（ダイヤモンド）':
        'Contrasting values can work together. Help connect the differences.',
    'クレイドル（ゆりかご）':
        'There is room to ease a conflict. Build cooperation through a reassuring approach.',
    'ハンマー・オブ・ソー':
        'Tension can support practical reform. Agree on a process before reacting.',
    'グランドセクスタイル':
        'Several strengths can cooperate. Start with one and build connections from there.',
  };
  if (rare != null &&
      rareGuidance.containsKey(rare.group(1)) &&
      rare.group(3) ==
          FortuneScoreCalculator.rarePatternGuidance(rare.group(1)!)) {
    return '12:00 JST — ${_patternNameEn(rare.group(1)!)} (${copy.patternPlanets(rare.group(2)!)}): ${rareGuidance[rare.group(1)]}';
  }
  return null;
}

class _ReadingSkyCopy {
  const _ReadingSkyCopy(this.language);
  final AppLanguage language;
  bool get english => language == AppLanguage.en;
  String t(String ja, String en) => english ? en : ja;
  String planet(AstroPlanet value) =>
      english ? _planetNameEn(value) : value.label;
  String sign(ZodiacSign value) => english ? _signNameEn(value) : value.label;
  String aspect(AspectType value) =>
      english ? _aspectNameEn(value) : value.label;
  String phase(AspectPhase value) =>
      english ? _phaseNameEn(value) : value.label;
  String area(FortuneArea value) => english
      ? switch (value) {
          FortuneArea.overall => 'Overall',
          FortuneArea.love => 'Love',
          FortuneArea.work => 'Work',
          FortuneArea.money => 'Money',
          FortuneArea.mental => 'Health and mental balance',
        }
      : value.label;
  String planets(Iterable<AstroPlanet> values) =>
      values.map(planet).join(english ? ', ' : '・');
  String patternPlanets(String value) =>
      english ? _patternNameEn(value).replaceAll('・', ', ') : value;
  String orb(double value) => '${t('オーブ', 'Orb')} ${value.toStringAsFixed(1)}°';
  String house(int value) => t('第$valueハウス', 'House $value');

  String guidance(AstroPlanet value) => switch (value) {
    AstroPlanet.sun => 'Intentions and direction',
    AstroPlanet.moon => 'Mood, rest, and daily rhythm',
    AstroPlanet.mercury => 'Communication, thinking, and plans',
    AstroPlanet.venus => 'Relationships, pleasure, and spending',
    AstroPlanet.mars => 'Action and energy management',
    AstroPlanet.jupiter => 'Growth and opportunities',
    AstroPlanet.saturn => 'Responsibility, persistence, and review',
    AstroPlanet.uranus => 'Change and new choices',
    AstroPlanet.neptune => 'Imagination and rest',
    AstroPlanet.pluto => 'Deep change and letting go',
    AstroPlanet.ascendant => 'How you present yourself',
    AstroPlanet.midheaven => 'Work and your public role',
  };
  String theme(AstroPlanet value) => switch (value) {
    AstroPlanet.sun => 'identity and purpose',
    AstroPlanet.moon => 'mood and daily rhythm',
    AstroPlanet.mercury => 'communication and judgment',
    AstroPlanet.venus => 'affection and enjoyment',
    AstroPlanet.mars => 'initiative and momentum',
    AstroPlanet.jupiter => 'growth and expansion',
    AstroPlanet.saturn => 'responsibility and practical foundations',
    AstroPlanet.uranus => 'change and freedom',
    AstroPlanet.neptune => 'imagination and uncertainty',
    AstroPlanet.pluto => 'deep change and focus',
    AstroPlanet.ascendant => 'self-presentation',
    AstroPlanet.midheaven => 'work and social roles',
  };
  String hint(AspectType value) => switch (value) {
    AspectType.conjunction => 'The themes combine and can feel more immediate.',
    AspectType.sextile => 'A small step can open an opportunity.',
    AspectType.square => 'Friction calls for a practical adjustment.',
    AspectType.trine => 'The themes tend to work together naturally.',
    AspectType.opposition => 'Contrasting needs call for balance.',
  };

  String natalMeaning(TransitAspect value) {
    final strength = value.orb <= 0.7
        ? 'The influence is particularly strong.'
        : value.orb <= 2
        ? 'The influence is strong.'
        : value.orb <= 4
        ? 'The influence is moderate.'
        : 'The influence is gentle, but attention can help you use it.';
    final current = theme(value.transitPlanet);
    final natal = theme(value.natalPlanet);
    final effect = switch (value.type) {
      AspectType.conjunction =>
        'Current $current overlaps with your natal $natal. This can show directly in feelings and actions; choose one real priority.',
      AspectType.sextile =>
        'Current $current supports your natal $natal. A small message, preparation, or proposal can open a useful opportunity.',
      AspectType.trine =>
        'Current $current connects naturally with your natal $natal. Use a familiar strength without pushing beyond your limits.',
      AspectType.square =>
        'Current $current can clash with your natal $natal. Ease the pressure on your schedule, words, or energy before deciding.',
      AspectType.opposition =>
        'Current $current faces your natal $natal. Other people or outside plans may pull your attention; compare the conditions before finding a compromise.',
    };
    return '$strength $effect';
  }

  String skyMeaning(TransitPairAspect value) {
    final strength = value.orb <= 0.7
        ? 'This is near the peak, with a particularly strong influence.'
        : value.phase == AspectPhase.applying
        ? 'This influence is likely to grow.'
        : 'This is a time to work with and settle what has already emerged.';
    final pair = '${theme(value.firstPlanet)} and ${theme(value.secondPlanet)}';
    final effect = switch (value.type) {
      AspectType.conjunction =>
        'Themes of $pair come forward together. Focus can deepen, but so can bias; set a clear priority.',
      AspectType.sextile =>
        'Themes of $pair can cooperate. A small conversation, experiment, or practical adjustment helps you use the opening.',
      AspectType.trine =>
        'Themes of $pair fit together naturally. A familiar strength can ease relationships, work, or money matters.',
      AspectType.square =>
        'Themes of $pair may pull at different speeds. Recheck deadlines, costs, and how you communicate before acting.',
      AspectType.opposition =>
        'Themes of $pair pull in opposite directions. Check other people’s circumstances and the available time to find a workable balance.',
    };
    return '$strength $effect';
  }

  // These labels are produced by the existing display interpolation, never
  // by user input. Preserve its time, orb, phase, and rounding rules.
  String time(String value) {
    if (!english) return value;
    var result = value;
    const labels = {
      '現在ピーク圏': 'Near peak now',
      'ピーク接近': 'Approaching peak',
      '指定日': 'Selected date',
      'ピーク通過後': 'Past peak',
      '翌日以降にピーク見込み': 'Peak expected tomorrow or later',
      'ピーク推定 ': 'Estimated peak: ',
      '接近中': 'Applying',
      'ピーク': 'Exact',
      '余韻': 'Separating',
      '(月)': '(Mon)',
      '(火)': '(Tue)',
      '(水)': '(Wed)',
      '(木)': '(Thu)',
      '(金)': '(Fri)',
      '(土)': '(Sat)',
      '(日)': '(Sun)',
    };
    for (final entry in labels.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }
    return result;
  }

  String returnLine(PlanetReturnEvent value) => english
      ? '${planet(value.planet)} return: ${phase(value.phase)} / ${orb(value.orb)} / ${house(value.natalHouse)} / ${area(value.area)}'
      : '${value.label} / ${house(value.natalHouse)} / ${area(value.area)}';
}
