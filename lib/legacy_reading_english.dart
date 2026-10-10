import 'package:flutter/material.dart';

import 'app_language.dart';
import 'app_language_settings.dart';
import 'english_reading_text.dart';
import 'english_ui_catalog.dart';

/// Display-only translation of the application's inherited reading templates.
/// Never pass editable names, notes, places, questions or canonical JSON here.
/// Unknown sentences/captures stay verbatim. No scores or evidence are selected,
/// recalculated, shortened, or replaced with the current nine-area reading.
String englishLegacyReadingText(String source) => _translate(source, 0);

String localizedLegacyReadingText(BuildContext context, String source) =>
    AppLanguageScope.stringsOf(context).language == AppLanguage.en
    ? englishLegacyReadingText(source)
    : source;

class LegacyReadingText extends StatelessWidget {
  const LegacyReadingText(
    this.source, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
  });
  final String source;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) => Text(
    localizedLegacyReadingText(context, source),
    style: style,
    maxLines: maxLines,
    overflow: overflow,
    textAlign: textAlign,
  );
}

final _japanese = RegExp(r'[\u3040-\u30ff\u3400-\u9fff]');

String _translate(String source, int depth) {
  if (depth > 12 || source.isEmpty) return source;
  if (source != source.trim()) {
    final leading = source.substring(
      0,
      source.length - source.trimLeft().length,
    );
    final trailing = source.substring(source.trimRight().length);
    return '$leading${_translate(source.trim(), depth + 1)}$trailing';
  }
  final exact = _fixed[source];
  if (exact != null) return exact;
  final domain = _technical[source];
  if (domain != null) return domain;
  final knownUi = englishUiText(source);
  if (knownUi != source) return knownUi;
  final generatedAstrology = _englishGeneratedAstrologyDetail(source, depth);
  if (generatedAstrology != null) return generatedAstrology;
  final dated = englishPeriodLabel(source);
  if (!_japanese.hasMatch(dated)) return dated;
  // Match one authored sentence at a time. A generic evidence template must
  // never capture an earlier sentence and relocate it into a later clause.
  for (final separator in ['。', '\n']) {
    if (!source.contains(separator)) continue;
    final pieces = source.split(separator);
    final translated = pieces.map((p) => _translate(p, depth + 1)).toList();
    if (List.generate(
      pieces.length,
      (i) => pieces[i] != translated[i],
    ).any((changed) => changed)) {
      return translated.join(separator == '。' ? '. ' : separator);
    }
  }
  for (final template in _templates) {
    final match = template.pattern.firstMatch(source);
    if (match == null) continue;
    final captures = <String>[];
    for (var i = 1; i <= match.groupCount; i++) {
      captures.add(_translate(match.group(i)!, depth + 1));
    }
    // A new planet/name/prose cannot silently become an English assertion.
    if (captures.any(_japanese.hasMatch)) continue;
    return template.english.replaceAllMapped(
      RegExp(r'\{(\d+)\}'),
      (m) => captures[int.parse(m.group(1)!)],
    );
  }
  // Existing prose is joined with Japanese full stops and evidence separators.
  // Preserve every unknown segment, including its original punctuation.
  for (final separator in ['。', '\n', ' / ', ' -> ', '：', ': ', '・', '、']) {
    if (!source.contains(separator)) continue;
    final pieces = source.split(separator);
    final translated = pieces.map((p) => _translate(p, depth + 1)).toList();
    if (List.generate(
      pieces.length,
      (i) => pieces[i] != translated[i],
    ).any((changed) => changed)) {
      return translated.join(switch (separator) {
        '。' => '. ',
        '：' => ': ',
        '・' || '、' => ', ',
        _ => separator,
      });
    }
  }
  // A bounded technical vocabulary only. Reject the whole technical fallback
  // if any unknown Japanese remains; this is not a free-text translator.
  var technical = dated;
  // Preserve the authored technical structure, with readable token boundaries.
  const planets = '太陽|月|水星|金星|火星|木星|土星|天王星|海王星|冥王星|ASC|MC';
  const signs = '牡羊座|牡牛座|双子座|蟹座|獅子座|乙女座|天秤座|蠍座|射手座|山羊座|水瓶座|魚座';
  const aspects = 'コンジャンクション|セクスタイル|スクエア|トライン|オポジション';
  technical = technical.replaceAllMapped(
    RegExp('($planets)($signs)'),
    (m) => '${_technical[m[1]] ?? m[1]} in ${_technical[m[2]]}',
  );
  technical = technical.replaceAllMapped(
    RegExp('($planets)($aspects)出生図の($planets)'),
    (m) =>
        '${_technical[m[1]] ?? m[1]} ${_technical[m[2]]} natal ${_technical[m[3]] ?? m[3]}',
  );
  technical = technical.replaceAllMapped(
    RegExp('($planets)第(\\d+)ハウス'),
    (m) => '${_technical[m[1]] ?? m[1]} House ${m[2]}',
  );
  for (final entry in _technicalEntries) {
    technical = technical.replaceAll(entry.key, entry.value);
  }
  technical = technical.replaceAllMapped(
    RegExp(r'第(\d+)(?:ハウス)?'),
    (m) => 'House ${m.group(1)}',
  );
  return _japanese.hasMatch(technical) ? source : technical;
}

String? _englishGeneratedAstrologyDetail(String source, int depth) {
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
  const aspectNames = {
    'コンジャンクション': 'conjunction',
    'セクスタイル': 'sextile',
    'スクエア': 'square',
    'トライン': 'trine',
    'オポジション': 'opposition',
  };
  const themes = {
    '自分らしさと目的': 'individuality and purpose',
    '気分と生活リズム': 'mood and daily rhythm',
    '言葉と判断': 'words and decisions',
    '好意と楽しみ': 'affection and enjoyment',
    '行動力と勢い': 'drive and momentum',
    '成長と広がり': 'growth and expansion',
    '責任と現実的な土台': 'responsibility and practical foundations',
    '変化と自由': 'change and freedom',
    '想像力と曖昧さ': 'imagination and ambiguity',
    '深い変化と集中': 'deep change and focus',
    '自分の見せ方': 'self-presentation',
    '仕事と社会的な役割': 'work and social roles',
  };
  const strengths = {
    '影響はかなり強めです。': 'The influence may be quite strong. ',
    '影響は強めです。': 'The influence may be strong. ',
    '影響は中くらいです。': 'The influence may be moderate. ',
    '影響は穏やかですが、意識すると流れを使えます。':
        'The influence is mild, but may be useful when approached intentionally. ',
    '今日はピーク圏で、影響がかなり強めです。':
        'This aspect is near its peak today and may be quite strong. ',
    'これから強まりやすい流れです。': 'This influence may strengthen. ',
    'すでに出た流れを整えて活かす時期です。':
        'This is a time to organize and use an influence that is already present. ',
  };

  // These compact fields are generated from typed placements; preserve all
  // degrees, signs, houses and ingress date/time while translating labels.
  final ingress = RegExp(
    r'^(太陽|月|水星|金星|火星|木星|土星|天王星|海王星|冥王星): (牡羊座|牡牛座|双子座|蟹座|獅子座|乙女座|天秤座|蠍座|射手座|山羊座|水瓶座|魚座)(?: (\d+(?:\.\d+)?)°)?(?: → (牡羊座|牡牛座|双子座|蟹座|獅子座|乙女座|天秤座|蠍座|射手座|山羊座|水瓶座|魚座)(?: (.+))?)?$',
  ).firstMatch(source);
  if (ingress != null) {
    final parts = <String>[
      '${planets[ingress.group(1)]}: ${signs[ingress.group(2)]}',
    ];
    if (ingress.group(3) != null) parts[0] += ' ${ingress.group(3)}°';
    if (ingress.group(4) != null) {
      var timing = ingress.group(5) ?? '';
      final date = RegExp(
        r'^(\d{1,2})/(\d{1,2})\((月|火|水|木|金|土|日)\)(.*)$',
      ).firstMatch(timing);
      if (date != null) {
        const weekdays = {
          '月': 'Mon',
          '火': 'Tue',
          '水': 'Wed',
          '木': 'Thu',
          '金': 'Fri',
          '土': 'Sat',
          '日': 'Sun',
        };
        timing =
            '${date.group(1)}/${date.group(2)} (${weekdays[date.group(3)]})${date.group(4)}';
      }
      parts.add(
        '→ ${signs[ingress.group(4)]}${timing.isEmpty ? '' : ' $timing'}',
      );
    }
    return parts.join(' ');
  }

  final aspectLine = RegExp(
    r'^(?:現在の)?(太陽|月|水星|金星|火星|木星|土星|天王星|海王星|冥王星) (コンジャンクション|セクスタイル|スクエア|トライン|オポジション) (出生図(?:の)?)?(太陽|月|水星|金星|火星|木星|土星|天王星|海王星|冥王星)(?: ([\d.]+)°)?(?: / (.+))?$',
  ).firstMatch(source);
  if (aspectLine != null) {
    final transit = planets[aspectLine.group(1)]!;
    final aspect = aspectNames[aspectLine.group(2)]!;
    final otherPlanet = planets[aspectLine.group(4)]!;
    final relation = aspectLine.group(3) == null ? 'current' : 'natal';
    final orb = aspectLine.group(5) == null ? '' : ' ${aspectLine.group(5)}°';
    final timing = aspectLine.group(6);
    return 'Current $transit $aspect $relation $otherPlanet$orb${timing == null ? '' : ' / ${_translate(timing, depth + 1)}'}';
  }

  // The table's compact house-and-area row must precede the prose parser.
  // Otherwise its / area suffix is captured as unknown house prose.
  final transitHouseImpact = RegExp(
    r'^(太陽|月|水星|金星|火星|木星|土星|天王星|海王星|冥王星) 第(\d+)H / (.+)$',
  ).firstMatch(source);
  if (transitHouseImpact != null) {
    final house = int.tryParse(transitHouseImpact.group(2)!);
    final area = _translate(transitHouseImpact.group(3)!, depth + 1);
    if (house == null || house < 1 || house > 12 || _japanese.hasMatch(area)) {
      return null;
    }
    return '${planets[transitHouseImpact.group(1)]} transiting natal House $house / $area';
  }

  final houseTransit = RegExp(
    r'^(?:現在の|出生図の)?(太陽|月|水星|金星|火星|木星|土星|天王星|海王星|冥王星|ASC|MC)(?:が出生図の|が|:\s*|\s*)第(\d+)(?:ハウス|H)(?:を通過|通過)?(?::|：)?\s*(.*)$',
  ).firstMatch(source);
  if (houseTransit != null) {
    final planet = houseTransit.group(1)!;
    final house = int.tryParse(houseTransit.group(2)!);
    if (house == null || house < 1 || house > 12) return null;
    var body = houseTransit.group(3) ?? '';
    const effects = {
      'で自分を出す力が強まる': 'may strengthen self-expression',
      'に気分や安心感が左右されやすい': 'may influence mood and a sense of security',
      'で判断、連絡、調整が動きやすい':
          'may bring activity to decisions, communication and adjustments',
      'で愛情、お金、楽しみが動きやすい':
          'may bring activity to affection, money and enjoyment',
      'で拡大、支援、チャンスが出やすい': 'may bring expansion, support and opportunities',
      'で責任、制限、積み上げが出やすい':
          'may highlight responsibility, limits and steady effort',
      'で変化、独立、急な切り替えが出やすい': 'may bring change, independence and sudden shifts',
      'で直感、曖昧さ、理想が出やすい':
          'may bring intuition, ambiguity and ideals to the surface',
      'で深い変容、執着、再生が出やすい':
          'may bring deep change, attachment and renewal to the surface',
      'で第一印象、自分の出し方、始め方が出やすい':
          'may affect first impressions, self-presentation and new beginnings',
      'で肩書き、評価、社会的な役割が出やすい': 'may affect titles, recognition and social roles',
    };
    final transit = source.contains('通過') || body.startsWith('通過中は');
    body = body.replaceFirst('通過中は', '').replaceFirst('出生図で', '');
    for (final suffix in effects.entries) {
      if (!body.endsWith(suffix.key)) continue;
      final topic = body.substring(0, body.length - suffix.key.length);
      final translatedTopic = topic.isEmpty ? '' : _translate(topic, depth + 1);
      if (_japanese.hasMatch(translatedTopic)) return null;
      return transit
          ? '${planets[planet]} transiting natal House $house: during this transit, $translatedTopic ${suffix.value}.'
          : '${planets[planet]} in natal House $house: $translatedTopic ${suffix.value}.';
    }
    if (body.isNotEmpty) return null;
    return '${planets[planet]} / ${transit ? 'natal House transit' : 'natal House'} $house';
  }

  final aspectHeader = RegExp(
    r'^現在の(太陽|月|水星|金星|火星|木星|土星|天王星|海王星|冥王星) と (?:(出生図の)|(現在の))?(太陽|月|水星|金星|火星|木星|土星|天王星|海王星|冥王星)$',
  ).firstMatch(source);
  if (aspectHeader != null) {
    final role = aspectHeader.group(2) == null ? 'current' : 'natal';
    return 'Current ${planets[aspectHeader.group(1)]} and $role ${planets[aspectHeader.group(4)]}';
  }

  final position = RegExp(
    r'^(太陽|月|水星|金星|火星|木星|土星|天王星|海王星|冥王星|ASC|MC) (牡羊座|牡牛座|双子座|蟹座|獅子座|乙女座|天秤座|蠍座|射手座|山羊座|水瓶座|魚座) (\d+(?:\.\d+)?)° 第(\d+)H( 逆行)?$',
  ).firstMatch(source);
  if (position != null) {
    final house = int.tryParse(position.group(4)!);
    if (house == null || house < 1 || house > 12) return null;
    return '${planets[position.group(1)]} in ${signs[position.group(2)]} ${position.group(3)}° / House $house${position.group(5) == null ? '' : ' retrograde'}';
  }

  final placementGuidance = RegExp(
    r'^(太陽|月|水星|金星|火星|木星|土星|天王星|海王星|冥王星)：(牡羊座|牡牛座|双子座|蟹座|獅子座|乙女座|天秤座|蠍座|射手座|山羊座|水瓶座|魚座) ([\d.]+)° / (.+)$',
  ).firstMatch(source);
  if (placementGuidance != null) {
    const guidance = {
      '意志と行動の軸': 'will and direction for action',
      '気分と休息の整え方': 'mood and ways to restore energy',
      '連絡・考え方・予定': 'communication, thinking and plans',
      '対人・楽しみ・お金の感覚': 'relationships, enjoyment and attitudes toward money',
      '行動力とエネルギー配分': 'initiative and energy management',
      '広げることとチャンス': 'growth and opportunities',
      '責任・継続・見直し': 'responsibility, persistence and review',
      '変化と新しい選択': 'change and new choices',
      '想像力と休息': 'imagination and rest',
      '深い変化と手放し': 'deep change and letting go',
      '今日の流れ': 'today’s themes',
    };
    final translatedGuidance = guidance[placementGuidance.group(4)];
    if (translatedGuidance == null) return null;
    return '${planets[placementGuidance.group(1)]}: ${signs[placementGuidance.group(2)]} ${placementGuidance.group(3)}° / $translatedGuidance';
  }

  final retrograde = RegExp(
    r'^(太陽|月|水星|金星|火星|木星|土星|天王星|海王星|冥王星)逆行中$',
  ).firstMatch(source);
  if (retrograde != null)
    return '${planets[retrograde.group(1)]} is retrograde';

  final returnLine = RegExp(
    r'^(太陽|月|水星|金星|火星|木星|土星|天王星|海王星|冥王星)リターン ([\d.]+)° (接近中|ピーク|余韻) / 第(\d+)H$',
  ).firstMatch(source);
  if (returnLine != null) {
    final house = int.tryParse(returnLine.group(4)!);
    if (house == null || house < 1 || house > 12) return null;
    const phases = {'接近中': 'applying', 'ピーク': 'exact', '余韻': 'separating'};
    return '${planets[returnLine.group(1)]} return ${returnLine.group(2)}° / ${phases[returnLine.group(3)]} / House $house';
  }

  final returnStatus = RegExp(
    r'^(太陽|月|水星|金星|火星|木星|土星|天王星|海王星|冥王星)リターン: (接近中|近い|ピーク|余韻)・(接近中|ピーク|余韻)$',
  ).firstMatch(source);
  if (returnStatus != null) {
    const statuses = {
      '接近中': 'approaching',
      '近い': 'near',
      'ピーク': 'exact',
      '余韻': 'separating',
    };
    const phases = {'接近中': 'applying', 'ピーク': 'exact', '余韻': 'separating'};
    return '${planets[returnStatus.group(1)]} return: ${statuses[returnStatus.group(2)]}, ${phases[returnStatus.group(3)]}';
  }

  final stellium = RegExp(r'^(出生図集中: )?第(\d+)ハウス集中: (.+)$').firstMatch(source);
  if (stellium != null) {
    final house = int.tryParse(stellium.group(2)!);
    final names = stellium.group(3)!.split('・');
    if (house == null ||
        house < 1 ||
        house > 12 ||
        names.length < 3 ||
        names.any((name) => !planets.containsKey(name))) {
      return null;
    }
    return '${stellium.group(1) == null ? '' : 'Natal '}House $house stellium: ${names.map((name) => planets[name]).join(', ')}';
  }

  final peak = RegExp(r'^ピーク推定 (.+)$').firstMatch(source);
  if (peak != null)
    return 'Estimated peak: ${_translate(peak.group(1)!, depth + 1)}';

  final simpleTime = {
    '現在ピーク圏': 'Near its peak now',
    'ピーク接近': 'Approaching its peak',
    'ピーク通過後': 'Past its peak',
    '翌日以降にピーク見込み': 'Peak expected on a later date',
    '指定日': 'Selected date',
    '接近中': 'Applying',
    'ピーク': 'Exact',
    '余韻': 'Separating',
    '影響が直接出やすい角度': 'An aspect whose effects may be direct',
    'きっかけが生まれる角度': 'An aspect that may create an opening',
    '課題が出やすい角度': 'An aspect that may bring a challenge',
    '調和しやすい角度': 'An aspect that may feel harmonious',
    '外側から刺激が入る角度': 'An aspect bringing stimulus from outside',
  }[source];
  if (simpleTime != null) return simpleTime;

  var remaining = source;
  var strength = '';
  for (final entry in strengths.entries) {
    if (!remaining.startsWith(entry.key)) continue;
    strength = entry.value;
    remaining = remaining.substring(entry.key.length).trimLeft();
    break;
  }
  const natalEffects = {
    'が重なります。自分の気持ちや行動へ直接出やすいので、いま本当に優先したいことを一つに絞ると力になります。':
        'come together. This may directly affect feelings or actions, so focus on one priority that truly matters now.',
    'を後押しします。小さな連絡、準備、提案を自分から一つ動かすと、機会につながりやすい配置です。':
        'may support the other theme. Taking one small initiative with a message, preparation or suggestion may open an opportunity.',
    'が自然につながります。無理に背伸びせず、得意なやり方をそのまま使うほど、手応えを受け取りやすい日です。':
        'connect naturally. Using a familiar strength without overreaching may make progress easier to notice.',
    'がぶつかりやすい配置です。焦って結論を出すより、予定・言葉・体力のどれかを一段軽くして調整すると、負荷を成果へ変えられます。':
        'may come into conflict. Rather than rushing to a conclusion, ease one plan, message or physical demand to turn strain into useful adjustment.',
    'が向かい合います。相手の反応や外側の予定に振られやすいので、すぐ決めず、条件を並べてから折り合いをつけるのが向きます。':
        'face each other. As reactions or outside plans may pull in different directions, compare the conditions before deciding.',
  };
  const skyEffects = {
    'が同時に前へ出ます。ひとつのテーマへ集中しやすい反面、気持ちが偏りやすいので、優先順位を決めて使うと力になります。':
        'are active together. Focus may come more easily, but feelings can become one-sided; decide on a priority before acting.',
    'が協力しやすい配置です。話す、試す、整えるなど小さな一歩を出すと、今日の流れに乗りやすいです。':
        'work well together. A small step—talking, testing or organizing—may help you use today’s flow.',
    'が自然にかみ合います。いつもの得意な方法で進めるほど、対人・仕事・お金の流れを滑らかにしやすいです。':
        'fit together naturally. Using a familiar strength may help interactions, work or money matters flow more smoothly.',
    'の間で急ぎと現実のズレが出やすい配置です。勢いで決めず、期限・金額・相手への伝え方を一度見直すと崩れにくくなります。':
        'may create a gap between urgency and practical limits. Before acting on momentum, review the deadline, amount or wording once.',
    'が引っ張り合う配置です。一方だけを押し通すより、相手の事情や使える時間を確認して、ちょうどよい落とし所を探すのが向きます。':
        'may pull in different directions. Check the other person’s circumstances and available time, then look for a workable balance.',
  };
  for (final first in themes.entries) {
    for (final second in themes.entries) {
      final pairedPrefix = '${first.key}と${second.key}';
      if (remaining.startsWith(pairedPrefix)) {
        final translatedEffect =
            natalEffects[remaining.substring(pairedPrefix.length)];
        if (translatedEffect != null) {
          final sentence =
              '${first.value} and ${second.value} $translatedEffect';
          return '$strength${_capitalize(sentence)}';
        }
      }
      final supportPrefix = '${first.key}が${second.key}';
      if (remaining.startsWith(supportPrefix)) {
        final translatedEffect =
            natalEffects[remaining.substring(supportPrefix.length)];
        if (translatedEffect != null) {
          final sentence =
              '${first.value} ${translatedEffect.replaceFirst('the other theme', second.value)}';
          return '$strength${_capitalize(sentence)}';
        }
      }
      final pair = '${first.key}と${second.key}';
      if (!remaining.startsWith(pair)) continue;
      final translatedEffect = skyEffects[remaining.substring(pair.length)];
      if (translatedEffect != null) {
        final sentence = '${first.value} and ${second.value} $translatedEffect';
        return '$strength${_capitalize(sentence)}';
      }
    }
  }
  return null;
}

String _capitalize(String value) => value.isEmpty
    ? value
    : '${value.substring(0, 1).toUpperCase()}${value.substring(1)}';

class _Template {
  _Template(String source, this.english)
    : pattern = RegExp(
        '^${source.split(RegExp(r'\{\d+\}')).map(RegExp.escape).join('(.+?)')}\u0024',
        dotAll: true,
      );
  final RegExp pattern;
  final String english;
}

final _templates = <_Template>[
  _Template('今日は太陽が{0}へ移ります', 'Today the Sun enters {0}'),
  _Template('今日は水星が{0}へ移ります', 'Today Mercury enters {0}'),
  _Template('今日は金星が{0}へ移ります', 'Today Venus enters {0}'),
  _Template('今日は火星が{0}へ移ります', 'Today Mars enters {0}'),
  _Template(
    'これから約1か月の軸を一つ決めると、行動にまとまりが出ます',
    'Choosing one focus for the next 1 month may help organize your actions',
  ),
  _Template(
    '連絡や学びの進め方を、その星座らしい視点へ切り替えると役立ちます',
    'Adjusting how you communicate or learn to reflect this sign may be useful',
  ),
  _Template(
    '人間関係・お金・楽しみの基準を、心地よさだけでなく長く続く形へ整えましょう',
    'Shape your approach to relationships, money and enjoyment for lasting comfort, not just immediate ease',
  ),
  _Template(
    '行動の勢いを新しいテーマへ向ける前に、最初の一歩を具体的に決めましょう',
    'Before directing your energy toward a new theme, define a concrete first step',
  ),
  _Template('今は{0}に意識が向きやすい流れです', 'Attention may turn toward {0}'),
  _Template(
    '{0} さらに{1}が出生図の第{2}ハウスを通過中で、{3}',
    '{0}. In addition, {1} is transiting natal House {2}: {3}',
  ),
  _Template(
    '{0}は{1}点で、「{2}」がこの日の中心です',
    '{0} is {1} points; the central theme for this date is “{2}”',
  ),
  _Template(
    '現在の{0}と出生図の{1}が{2}（オーブ{3}°・{4}）です',
    'Current {0} forms a {2} to natal {1} (orb {3}°; {4})',
  ),
  _Template(
    '空では現在の{0}と{1}が{2}（オーブ{3}°・{4}）を作っています',
    'In the current sky, {0} and {1} form a {2} (orb {3}°; {4})',
  ),
  _Template(
    'さらに{0}が出生図の第{1}ハウスを通過中で、{2}',
    'In addition, {0} is transiting natal House {1}: {2}',
  ),
  _Template(
    '指定日の主な流れは、現在の{0}が出生図の{1}へ{2}を作る配置です',
    'The main configuration on this date is current {0} forming a {2} to natal {1}',
  ),
  _Template(
    'また、{0}が出生図の第{1}ハウスを通過しているため、{2}',
    'Also, {0} is transiting natal House {1}: {2}',
  ),
  _Template(
    '{0}が出生図の第{1}ハウスのテーマを再確認する時期',
    '{0} marks a time to revisit the themes of natal House {1}',
  ),
  _Template('{0}が第{1}ハウスのテーマを刺激', '{0} stimulates the themes of House {1}'),
  _Template('{0}リターンも重なり、{1}', 'A {0} return also occurs: {1}'),
  _Template('{0}リターンの影響もあり、{1}', 'The {0} return also contributes: {1}'),
  _Template(
    '月ボイドの{0}は、結論を急ぐより確認と下準備へ回す方が安定します',
    'During the void-of-course Moon ({0}), favor checks and preparation over rushed conclusions',
  ),
  _Template('月ボイドは{0}', 'Void-of-course Moon: {0}'),
  _Template('実行するなら、{0}', 'Action: {0}'),
  _Template(
    '{0}なので、勢いで決めず、確認、休憩、見直しのどれかを一つ挟みましょう',
    '{0}; avoid impulsive decisions and include a check, a rest or a review',
  ),
  _Template(
    '{0}なので、思いついたことを人に伝える、形にする、数字で見る行動を一つ選びましょう',
    '{0}; choose one action: communicate an idea, give it a concrete form, or examine its numbers',
  ),
  _Template(
    '月が{0}なので、迷うよりまず小さく着手すると流れに乗りやすい日です',
    'With the Moon in {0}, a small first step may help more than prolonged hesitation',
  ),
  _Template(
    '月が{0}なので、予定・持ち物・お金を一つ整える行動が向いています',
    'With the Moon in {0}, put one schedule, possession or money matter in order',
  ),
  _Template(
    '月が{0}なので、連絡・相談・情報整理を軽く進めると良い日です',
    'With the Moon in {0}, take a light approach to messages, consultation and organizing information',
  ),
  _Template(
    '月が{0}なので、無理に急がず、気持ちが落ち着く環境を整えてから動くと良い日です',
    'With the Moon in {0}, avoid forcing the pace; settle your surroundings before acting',
  ),
  _Template(
    '月が{0}なので、気持ちは動きやすい日',
    'With the Moon in {0}, feelings may be more active',
  ),
  _Template(
    '月が{0}なので、生活リズムを整えるほど気持ちが安定しやすい日です',
    'With the Moon in {0}, a regular daily rhythm may help feelings settle',
  ),
  _Template(
    '月が{0}なので、考えが散りやすい時は人に話すか、メモに出すと落ち着きます',
    'With the Moon in {0}, talking or writing a note may settle scattered thoughts',
  ),
  _Template('月が{0}なので、気分が深まりやすい日', 'With the Moon in {0}, feelings may deepen'),
  _Template('今は{0}に意識が向きやすい流れです', 'Attention may turn toward {0}'),
  _Template(
    'ただし気持ちや予定が定まりにくい{0}は、無理に進めず確認と休憩に回すと安定します',
    'During {0}, feelings and plans may be less settled; favor checks and rest rather than forcing progress',
  ),
  _Template('{0}が逆行中です', '{0} is retrograde'),
  _Template(
    '空の{0}に星が集中するため、そのテーマを一つに絞ると力を使いやすくなります',
    'Planets cluster in {0} in the current sky; focusing on one related theme may help channel the energy',
  ),
  _Template('現在は{0}が成立しています', 'The current sky contains {0}'),
  _Template(
    '現在は空の{0}にステリウムができています',
    'There is currently a stellium in {0} in the sky',
  ),
  _Template(
    '出生図の第{0}ハウスの星の集中',
    'A natal concentration of planets in House {0}',
  ),
  _Template(
    '{0}も日々の判断の土台です',
    '{0} also forms part of the background to everyday decisions',
  ),
  _Template('今日は{0}の留です', 'Today marks the station of {0}'),
  _Template('今日は{0}が{1}へ移ります', 'Today {0} enters {1}'),
  _Template('好調：{0}　注意：{1}', 'More favorable: {0} · Caution: {1}'),
  _Template('基準{0}点 {1} → {2}点', 'Base {0} points {1} → {2} points'),
  _Template(
    '基準{0}点 {1} = 計算値{2}点',
    'Base {0} points {1} = unrounded {2} points',
  ),
  _Template(
    '計算値 {0}点を四捨五入し、50〜99点の範囲で表示しています',
    'The unrounded value {0} is rounded and displayed within 50–99 points',
  ),
  _Template(
    '四捨五入し、50〜99点の範囲で {0}点 と表示しています',
    'Rounded and limited to 50–99 points: {0} points',
  ),
  _Template('{0}の点数計算', '{0}: score calculation'),
  _Template('算定: {0} = {1}', 'Calculation: {0} = {1}'),
  _Template('オーブ{0}°', 'Orb {0}°'),
  _Template('対象日の{0}%', '{0}% of the target day'),
  _Template('基本{0} × 日内割合{1}', 'Base {0} × fraction of day {1}'),
  _Template('基礎{0} × オーブ係数{1}', 'Base {0} × orb weight {1}'),
  _Template('月相（{0}）', 'Lunar phase ({0})'),
  _Template('{0}が出生図の第{1}ハウスを通過', '{0} transits natal House {1}'),
  _Template('第{0}ハウス強調', 'House {0} emphasis'),
  _Template('{0}の節目が出る流れ', 'A turning point associated with {0}'),
  _Template('{0}頃', 'around {0}'),
  _Template('{0}（{1}）', '{0} ({1})'),
  _Template('{0}: 出生図で{1}', '{0}: in the natal chart, {1}'),
  _Template('{0}: 通過中は{1}', '{0}: during the transit, {1}'),
  _Template('{0}で自分を出す力が強まる', 'Self-expression becomes more prominent in {0}'),
  _Template('{0}に気分や安心感が左右されやすい', 'Mood and security may be affected by {0}'),
  _Template(
    '{0}で判断、連絡、調整が動きやすい',
    'Decisions, messages and adjustments are active in {0}',
  ),
  _Template(
    '{0}で愛情、お金、楽しみが動きやすい',
    'Affection, money and enjoyment are active in {0}',
  ),
  _Template(
    '{0}で拡大、支援、チャンスが出やすい',
    'Growth, support and opportunities may arise in {0}',
  ),
  _Template(
    '{0}で責任、制限、積み上げが出やすい',
    'Responsibilities, limits and steady work are prominent in {0}',
  ),
  _Template(
    '{0}で変化、独立、急な切り替えが出やすい',
    'Change, independence and sudden shifts may arise in {0}',
  ),
  _Template(
    '{0}で直感、曖昧さ、理想が出やすい',
    'Intuition, uncertainty and ideals are prominent in {0}',
  ),
  _Template(
    '{0}で深い変容、執着、再生が出やすい',
    'Deep change, attachment and renewal are prominent in {0}',
  ),
  _Template(
    '{0}で第一印象、自分の出し方、始め方が出やすい',
    'First impressions, self-presentation and beginnings are prominent in {0}',
  ),
  _Template(
    '{0}で肩書き、評価、社会的な役割が出やすい',
    'Titles, recognition and social roles are prominent in {0}',
  ),
  _Template('{0}に出る', 'Expressed through {0}'),
  _Template('{0}が動く', '{0} becomes active'),
  _Template(
    '{0}が生まれ持った運の出どころ',
    '{0} is a natal source of the inherited reading’s themes',
  ),
];

const _fixed = <String, String>{
  '該当する主要5角度はありません。': 'No matching aspects from the five major angle types.',
  '今日のリターンはありません。': 'No planetary returns today.',
  '目立つ補助配置はありません。': 'No notable supporting configurations.',
  '3つの星の調和が強まりやすい時間帯': 'Three planets may be working in harmony at this time',
  '得意なことを一つ形にします': 'Put one of your strengths into practice',
  'データはありません。': 'No data is available.',
  '連絡、判断、予定は急いで確定せず、見直しと再確認を優先します。':
      'Avoid rushing to finalize messages, decisions or plans; review and double-check them first.',
  '連絡、判断、予定は急いで確定せず、見直しと再確認を優先します':
      'Avoid rushing to finalize messages, decisions or plans; review and double-check them first',
  'この日は主要アスペクトの影響が弱めです。大きく動かすより、普段の調整を丁寧にすると流れが整います。':
      'Major aspects are relatively mild today. Careful adjustments to your usual routine may help things settle.',
  '3つの星の調和が強まりやすい時間帯。得意なことを一つ形にします。':
      'A time when three planets may work in harmony. Put one of your strengths into practice.',
  '今は気持ちと行動が同じテーマへ集まりやすい日です':
      'Feelings and actions may gather around the same theme today',
  '優先順位を一つに絞ると力を使いやすくなります':
      'Focusing on one priority can help you use your energy well.',
  '今は小さな働きかけがきっかけになりやすい日です': 'A small initiative may create an opening today',
  '連絡、準備、提案のどれかを一つ動かすと流れが開きます':
      'Taking one step with a message, preparation or proposal may help things move forward.',
  '今は得意なやり方をそのまま使いやすい日です': 'Your familiar approach may work well today',
  '無理に背伸びせず、続けやすい方法を選ぶと手応えにつながります':
      'Choose a sustainable method instead of stretching yourself, and you may see tangible progress.',
  '今は急ぎたい気持ちと現実の間にズレが出やすい日です':
      'There may be a gap between the urge to hurry and practical constraints today',
  '予定や言葉を一段軽くして調整すると崩れにくくなります':
      'Lighten one commitment or message and adjust it to keep plans on track.',
  '今は相手や外側の予定に振られやすい日です':
      'Other people or outside plans may pull your attention today',
  '一方だけで決めず、条件を並べてから折り合いをつけると安定します':
      'Compare the conditions before deciding and look for a workable compromise.',
  '今日は新月です': 'Today is the New Moon',
  'これから育てたいことを一つ決め、小さく始めると流れを作りやすい日です':
      'Choose one thing you want to grow and begin with a small step to build momentum.',
  '今日は上弦の月です': 'Today is the First Quarter Moon',
  '育てたいことを一つ行動に移し、進み具合を確かめると流れを活かせます':
      'Put one intention into action and check your progress to make use of the momentum.',
  '今日は満月です': 'Today is the Full Moon',
  '結果と気持ちが表れやすいので、振り返りと調整に使うと整います':
      'Results and feelings may be more visible; use the moment to reflect and make adjustments.',
  '今日は下弦の月です': 'Today is the Last Quarter Moon',
  '負担や不要なことを一つ手放し、次の準備を整えると気持ちが軽くなります':
      'Let go of one burden or unnecessary task and prepare for what comes next.',
  '自然な一言が好印象につながる日': 'A natural, friendly remark may leave a good impression',
  '気になる相手には、明るい近況を素直に伝えると距離が縮まります':
      'Share a light update sincerely with someone you like; it may help you feel closer.',
  '人との縁が動きやすい日': 'Connections may be more active today',
  '誘いや連絡は先延ばしにせず、無理のない予定を一つ提案すると流れに乗れます':
      'Instead of delaying an invitation or message, suggest one manageable plan.',
  'やさしい言葉が効く日': 'Kind words may help today',
  '駆け引きより素直な一言を選ぶと、関係が落ち着いて進みます':
      'A sincere remark rather than a tactic may help the relationship move forward calmly.',
  '相手との温度差を整えやすい日': 'This may be a good day to bridge differences in pace',
  '返事を急かさず、聞く時間を少し長くすると安心感が生まれます':
      'Do not rush a reply; listening a little longer may build reassurance.',
  '気持ちを急いで結論にしない日': 'Avoid rushing to a conclusion about your feelings',
  '送る前に言葉を一度見直し、相手の都合も考えた連絡にすると運が整います':
      'Review your words before sending a message and consider the other person’s availability.',
  '小さな誤解が出やすい日': 'Small misunderstandings may arise',
  '決めつけずに一つ確認してから動くと、関係のぎこちなさを防げます':
      'Check one point before reacting rather than assuming; this may help prevent awkwardness.',
  '仕事の判断と連絡がスムーズに進む日': 'Work decisions and communication may move smoothly',
  '後回しにしていた依頼を一つ片づけると、次の話も入りやすくなります':
      'Complete one postponed request, which may make room for the next conversation.',
  '考えを形にする力が強い日': 'It may be easier to turn ideas into concrete form',
  '提案や相談は短く整理して伝えると、周囲の協力を得やすくなります':
      'Keep a proposal or question brief to make cooperation easier.',
  '連絡や整理に追い風': 'Communication and organization have a tailwind',
  '曖昧な予定を一つ確定させると流れが良くなります': 'Confirm one vague plan to keep things moving.',
  '細かな確認が成果につながる日': 'Small checks can contribute to results',
  '優先順位を二つに絞り、先に一つを終わらせると安心です':
      'Narrow your priorities to two and finish one first for peace of mind.',
  '仕事を抱え込みやすい日': 'You may take on too much work',
  '期限と確認先を先に書き出し、一人で迷う前に早めに相談しましょう':
      'Write down the deadline and who to check with, then ask early instead of getting stuck alone.',
  '予定の行き違いに注意したい日': 'Watch for schedule mix-ups',
  '送信前に日時と相手を確認すると、余計なやり直しを防げます':
      'Check the date and recipient before sending to avoid rework.',
  'お金の流れを広げやすい日': 'It may be easier to expand your financial options',
  '必要な道具や学びへの小さな投資は、将来の収入につながるかを見て選びましょう':
      'When investing a little in tools or learning, consider whether it could support future income.',
  '価値のある使い方を見極めやすい日': 'It may be easier to identify useful spending',
  '予算を決めてから、長く役立つものを一つ選ぶと満足度が上がります':
      'Set a budget, then choose one thing that will serve you for a while.',
  '大きな買い物は慎重に': 'Be cautious with major purchases',
  '小さな自己投資には良い気配があるので、予算内で一つだけ選ぶと安心です':
      'A small investment in yourself may be worthwhile; choose just one within your budget.',
  '収入と支出を整えやすい日': 'It may be a good time to organize income and expenses',
  '使っていない定額サービスを一つ確認すると、先の余裕が増えます':
      'Checking one unused subscription may create more room later.',
  '気分で財布がゆるみやすい日': 'You may be prone to impulse purchases',
  '欲しい物はすぐ決めず、予算と必要性を一度メモしてから判断しましょう':
      'Do not decide immediately; write down the budget and need first.',
  'お金の不安を一度に解決しようとしない日': 'Do not try to solve money worries all at once',
  '今日の支出を確認し、明日できる見直しを一つ決めると落ち着きます':
      'Review today’s spending and choose one thing to revisit tomorrow.',
  '心身の調子を整えやすい日': 'It may be easier to care for your condition',
  'やりたいことを一つ選び、休む時間も予定に入れると気持ちよく動けます':
      'Choose one activity you want to do and schedule rest so you can move comfortably.',
  '安心できる場所や人から力をもらえる日': 'You may draw support from a place or person you trust',
  '無理な我慢を減らし、気分転換の時間を先に確保しましょう':
      'Reduce unnecessary self-restraint and set aside time for a change of pace.',
  '気持ちの奥にある本音が見えやすい日': 'You may notice what you truly feel',
  '静かな時間を少し作ると、自然に調子が整います': 'A little quiet time can help you settle.',
  '生活リズムを戻しやすい日': 'This may be a good day to restore your routine',
  '食事や休憩を抜かず、夜の予定を一つ減らすと心に余裕ができます':
      'Do not skip meals or breaks; reducing one evening plan can create mental space.',
  '今日は体調・メンタルを気にかける日':
      'Pay attention to your physical condition and mental well-being today',
  '短い休憩を先に決め、無理に答えを出さず明日に回す選択も大切です':
      'Schedule a short break first; it is okay to leave a difficult answer until tomorrow.',
  '周囲の空気を受けやすいので、一人で落ち着く時間を確保し、眠る前は画面から少し離れましょう':
      'You may be sensitive to the atmosphere around you, so make quiet time alone and step away from screens before bed.',
  '復縁なら、短い近況確認から始めましょう':
      'If you hope to reconnect, start with a brief, friendly check-in.',
  '復縁の結論は急がず、距離を整えましょう':
      'Do not rush a conclusion about reconnecting; first find a comfortable distance.',
  '出会いの入口を一つ試してみましょう': 'Try one low-pressure way to meet someone new.',
  '出会い探しは、プロフィール整理を先にしましょう':
      'If you are looking to meet someone, start by refreshing your profile.',
  '短い連絡を一通送りましょう': 'Send one brief message.',
  '会う候補を一つ提案してみましょう': 'Suggest one possible time to meet.',
  '人と会う予定を一つ作りましょう': 'Make one plan to see someone.',
  '追い連絡は控えましょう': 'Hold off on sending follow-up messages.',
  '返事を待つ余白を作りましょう': 'Leave space while waiting for a reply.',
  '相手の反応を決めつけないようにしましょう': 'Avoid assuming what the other person thinks.',
  '公開か告知を一件進めましょう': 'Move one publication or announcement forward.',
  '公開より、制作と見直しを優先しましょう': 'Prioritize creating and reviewing over publishing.',
  '求人か応募を一件進めましょう': 'Take one step toward a job search or application.',
  '転職条件の比較を先にしましょう': 'Compare the conditions of a possible job change first.',
  '副業の小さな実績を一つ作りましょう': 'Create one small result in your side project.',
  '報酬と作業時間を先に確認しましょう': 'Check compensation and time commitments first.',
  '短い演習を一回終えましょう': 'Complete one short practice session.',
  '勉強範囲を小さく区切りましょう': 'Break the study material into smaller sections.',
  '止まっている作業を一つ進めましょう': 'Move one stalled task forward.',
  '相談か提出を一件進めましょう': 'Advance one consultation or submission.',
  '今日の優先作業を一つ終えましょう': 'Finish one priority task today.',
  '期限と手順を確認しましょう': 'Check the deadline and steps.',
  '抱え込まず一件相談しましょう': 'Ask for help with one item instead of carrying it alone.',
  'やり直せる準備を先にしましょう': 'Prepare a way to revise or recover first.',
  '投資は条件と上限を確認してから判断しましょう':
      'Check the terms and limits before making an investment decision.',
  '投資判断は保留し、仕組みを確認しましょう':
      'Pause the investment decision and review how it works.',
  '先取りで残す額を決めましょう': 'Decide how much to set aside first.',
  '固定費を一件見直しましょう': 'Review one recurring expense.',
  '予算内の買い物を一つ選びましょう': 'Choose one purchase within your budget.',
  '必要な支払いを一件済ませましょう': 'Complete one necessary payment.',
  '将来役立つ使い道を一つ選びましょう': 'Choose one use that could be useful later.',
  '大きな買い物は一晩置きましょう': 'Wait overnight before making a major purchase.',
  '契約条件を数字で確認しましょう': 'Check the contract terms and amounts.',
  '今日の支出を一度見直しましょう': 'Review today’s spending once.',
  '今夜の就寝時刻を決めましょう': 'Set a bedtime for tonight.',
  '予定を一つ減らして、睡眠を優先しましょう': 'Reduce one commitment and prioritize sleep.',
  '軽い運動を一回始めましょう': 'Start one light exercise session.',
  '強度を下げ、食事と休息を優先しましょう': 'Lower the intensity and prioritize meals and rest.',
  '整えたい習慣を一つ始めましょう': 'Start one habit you want to make more manageable.',
  '短い運動か休憩を予定に入れましょう': 'Schedule a short exercise session or a break.',
  '食事と水分の時間を守りましょう': 'Keep regular times for meals and hydration.',
  '休憩を先に確保しましょう': 'Schedule a break first.',
  '夜の予定を一つ減らしましょう': 'Reduce one evening commitment.',
  '無理な活動量を落としましょう': 'Scale back strenuous activity.',
  '今は気持ちと行動が同じテーマへ集まりやすい日です。優先順位を一つに絞ると力を使いやすくなります':
      'Feelings and actions may gather around the same theme today. Focusing on one priority can help you use your energy well.',
  '今は小さな働きかけがきっかけになりやすい日です。連絡、準備、提案のどれかを一つ動かすと流れが開きます':
      'A small initiative may create an opening today. Taking one step with a message, preparation or proposal may help things move forward.',
  '今は得意なやり方をそのまま使いやすい日です。無理に背伸びせず、続けやすい方法を選ぶと手応えにつながります':
      'Your familiar approach may work well today. Choose a sustainable method instead of stretching yourself, and you may see tangible progress.',
  '今は急ぎたい気持ちと現実の間にズレが出やすい日です。予定や言葉を一段軽くして調整すると崩れにくくなります':
      'There may be a gap between the urge to hurry and practical constraints today. Lighten one commitment or message and adjust it to keep plans on track.',
  '今は相手や外側の予定に振られやすい日です。一方だけで決めず、条件を並べてから折り合いをつけると安定します':
      'Other people or outside plans may pull your attention today. Compare the conditions before deciding and look for a workable compromise.',
  '今日は新月です。これから育てたいことを一つ決め、小さく始めると流れを作りやすい日です':
      'Today is the New Moon. Choose one thing you want to grow and begin with a small step to build momentum.',
  '今日は上弦の月です。育てたいことを一つ行動に移し、進み具合を確かめると流れを活かせます':
      'Today is the First Quarter Moon. Put one intention into action and check your progress to make use of the momentum.',
  '今日は満月です。結果と気持ちが表れやすいので、振り返りと調整に使うと整います':
      'Today is the Full Moon. Results and feelings may be more visible; use the moment to reflect and make adjustments.',
  '今日は下弦の月です。負担や不要なことを一つ手放し、次の準備を整えると気持ちが軽くなります':
      'Today is the Last Quarter Moon. Let go of one burden or unnecessary task and prepare for what comes next.',
  '自然な一言が好印象につながる日。気になる相手には、明るい近況を素直に伝えると距離が縮まります。':
      'A natural, friendly remark may leave a good impression. Share a light update sincerely with someone you like; it may help you feel closer.',
  '人との縁が動きやすい日。誘いや連絡は先延ばしにせず、無理のない予定を一つ提案すると流れに乗れます。':
      'Connections may be more active today. Instead of delaying an invitation or message, suggest one manageable plan.',
  'やさしい言葉が効く日。駆け引きより素直な一言を選ぶと、関係が落ち着いて進みます。':
      'Kind words may help today. A sincere remark rather than a tactic may help the relationship move forward calmly.',
  '相手との温度差を整えやすい日。返事を急かさず、聞く時間を少し長くすると安心感が生まれます。':
      'This may be a good day to bridge differences in pace. Do not rush a reply; listening a little longer may build reassurance.',
  '気持ちを急いで結論にしない日。送る前に言葉を一度見直し、相手の都合も考えた連絡にすると運が整います。':
      'Avoid rushing to a conclusion about your feelings. Review your words before sending a message and consider the other person’s availability.',
  '小さな誤解が出やすい日。決めつけずに一つ確認してから動くと、関係のぎこちなさを防げます。':
      'Small misunderstandings may arise. Check one point before reacting rather than assuming; this may help prevent awkwardness.',
  '仕事の判断と連絡がスムーズに進む日。後回しにしていた依頼を一つ片づけると、次の話も入りやすくなります。':
      'Work decisions and communication may move smoothly. Complete one postponed request, which may make room for the next conversation.',
  '考えを形にする力が強い日。提案や相談は短く整理して伝えると、周囲の協力を得やすくなります。':
      'It may be easier to turn ideas into concrete form. Keep a proposal or question brief to make cooperation easier.',
  '連絡や整理に追い風。曖昧な予定を一つ確定させると流れが良くなります。':
      'Communication and organization have a tailwind. Confirm one vague plan to keep things moving.',
  '細かな確認が成果につながる日。優先順位を二つに絞り、先に一つを終わらせると安心です。':
      'Small checks can contribute to results. Narrow your priorities to two and finish one first for peace of mind.',
  '仕事を抱え込みやすい日。期限と確認先を先に書き出し、一人で迷う前に早めに相談しましょう。':
      'You may take on too much work. Write down the deadline and who to check with, then ask early instead of getting stuck alone.',
  '予定の行き違いに注意したい日。送信前に日時と相手を確認すると、余計なやり直しを防げます。':
      'Watch for schedule mix-ups. Check the date and recipient before sending to avoid rework.',
  'お金の流れを広げやすい日。必要な道具や学びへの小さな投資は、将来の収入につながるかを見て選びましょう。':
      'It may be easier to expand your financial options. When investing a little in tools or learning, consider whether it could support future income.',
  '価値のある使い方を見極めやすい日。予算を決めてから、長く役立つものを一つ選ぶと満足度が上がります。':
      'It may be easier to identify useful spending. Set a budget, then choose one thing that will serve you for a while.',
  '大きな買い物は慎重に。小さな自己投資には良い気配があるので、予算内で一つだけ選ぶと安心です。':
      'Be cautious with major purchases. A small investment in yourself may be worthwhile; choose just one within your budget.',
  '収入と支出を整えやすい日。使っていない定額サービスを一つ確認すると、先の余裕が増えます。':
      'It may be a good time to organize income and expenses. Checking one unused subscription may create more room later.',
  '気分で財布がゆるみやすい日。欲しい物はすぐ決めず、予算と必要性を一度メモしてから判断しましょう。':
      'You may be prone to impulse purchases. Do not decide immediately; write down the budget and need first.',
  'お金の不安を一度に解決しようとしない日。今日の支出を確認し、明日できる見直しを一つ決めると落ち着きます。':
      'Do not try to solve money worries all at once. Review today’s spending and choose one thing to revisit tomorrow.',
  '心身の調子を整えやすい日。やりたいことを一つ選び、休む時間も予定に入れると気持ちよく動けます。':
      'It may be easier to care for your condition. Choose one activity you want to do and schedule rest so you can move comfortably.',
  '安心できる場所や人から力をもらえる日。無理な我慢を減らし、気分転換の時間を先に確保しましょう。':
      'You may draw support from a place or person you trust. Reduce unnecessary self-restraint and set aside time for a change of pace.',
  '気持ちの奥にある本音が見えやすい日。静かな時間を少し作ると、自然に調子が整います。':
      'You may notice what you truly feel. A little quiet time can help you settle.',
  '生活リズムを戻しやすい日。食事や休憩を抜かず、夜の予定を一つ減らすと心に余裕ができます。':
      'This may be a good day to restore your routine. Do not skip meals or breaks; reducing one evening plan can create mental space.',
  '今日は体調・メンタルを気にかける日。短い休憩を先に決め、無理に答えを出さず明日に回す選択も大切です。':
      'Pay attention to your physical condition and mental well-being today. Schedule a short break first; it is okay to leave a difficult answer until tomorrow.',
  '今日は体調・メンタルを気にかける日。周囲の空気を受けやすいので、一人で落ち着く時間を確保し、眠る前は画面から少し離れましょう。':
      'Pay attention to your physical condition and mental well-being today. You may be sensitive to the atmosphere around you, so make quiet time alone and step away from screens before bed.',
  '復縁なら、短い近況確認から始めましょう。':
      'If you hope to reconnect, start with a brief, friendly check-in.',
  '復縁の結論は急がず、距離を整えましょう。':
      'Do not rush a conclusion about reconnecting; first find a comfortable distance.',
  '出会いの入口を一つ試してみましょう。': 'Try one low-pressure way to meet someone new.',
  '出会い探しは、プロフィール整理を先にしましょう。':
      'If you are looking to meet someone, start by refreshing your profile.',
  '短い連絡を一通送りましょう。': 'Send one brief message.',
  '会う候補を一つ提案してみましょう。': 'Suggest one possible time to meet.',
  '人と会う予定を一つ作りましょう。': 'Make one plan to see someone.',
  '追い連絡は控えましょう。': 'Hold off on sending follow-up messages.',
  '返事を待つ余白を作りましょう。': 'Leave space while waiting for a reply.',
  '相手の反応を決めつけないようにしましょう。': 'Avoid assuming what the other person thinks.',
  '公開か告知を一件進めましょう。': 'Move one publication or announcement forward.',
  '公開より、制作と見直しを優先しましょう。': 'Prioritize creating and reviewing over publishing.',
  '求人か応募を一件進めましょう。': 'Take one step toward a job search or application.',
  '転職条件の比較を先にしましょう。': 'Compare the conditions of a possible job change first.',
  '副業の小さな実績を一つ作りましょう。': 'Create one small result in your side project.',
  '報酬と作業時間を先に確認しましょう。': 'Check compensation and time commitments first.',
  '短い演習を一回終えましょう。': 'Complete one short practice session.',
  '勉強範囲を小さく区切りましょう。': 'Break the study material into smaller sections.',
  '止まっている作業を一つ進めましょう。': 'Move one stalled task forward.',
  '相談か提出を一件進めましょう。': 'Advance one consultation or submission.',
  '今日の優先作業を一つ終えましょう。': 'Finish one priority task today.',
  '期限と手順を確認しましょう。': 'Check the deadline and steps.',
  '抱え込まず一件相談しましょう。': 'Ask for help with one item instead of carrying it alone.',
  'やり直せる準備を先にしましょう。': 'Prepare a way to revise or recover first.',
  '投資は条件と上限を確認してから判断しましょう。':
      'Check the terms and limits before making an investment decision.',
  '投資判断は保留し、仕組みを確認しましょう。':
      'Pause the investment decision and review how it works.',
  '先取りで残す額を決めましょう。': 'Decide how much to set aside first.',
  '固定費を一件見直しましょう。': 'Review one recurring expense.',
  '予算内の買い物を一つ選びましょう。': 'Choose one purchase within your budget.',
  '必要な支払いを一件済ませましょう。': 'Complete one necessary payment.',
  '将来役立つ使い道を一つ選びましょう。': 'Choose one use that could be useful later.',
  '大きな買い物は一晩置きましょう。': 'Wait overnight before making a major purchase.',
  '契約条件を数字で確認しましょう。': 'Check the contract terms and amounts.',
  '今日の支出を一度見直しましょう。': 'Review today’s spending once.',
  '今夜の就寝時刻を決めましょう。': 'Set a bedtime for tonight.',
  '予定を一つ減らして、睡眠を優先しましょう。': 'Reduce one commitment and prioritize sleep.',
  '軽い運動を一回始めましょう。': 'Start one light exercise session.',
  '強度を下げ、食事と休息を優先しましょう。': 'Lower the intensity and prioritize meals and rest.',
  '整えたい習慣を一つ始めましょう。': 'Start one habit you want to make more manageable.',
  '短い運動か休憩を予定に入れましょう。': 'Schedule a short exercise session or a break.',
  '食事と水分の時間を守りましょう。': 'Keep regular times for meals and hydration.',
  '休憩を先に確保しましょう。': 'Schedule a break first.',
  '夜の予定を一つ減らしましょう。': 'Reduce one evening commitment.',
  '無理な活動量を落としましょう。': 'Scale back strenuous activity.',
  '点': 'points',
  '健康・メンタル運': 'Combined physical and mental well-being',
  '恋愛・対人面': 'Love and relationships',
  '仕事・発信面': 'Work and communication',
  'お金と価値の面': 'Money and value',
  '心身と生活の面': 'Combined mind/body and daily life',
  '全体の流れ': 'Overall flow',
  'かなり良い流れの日です': 'The inherited reading indicates a very favorable flow',
  '良い運気の日です': 'The inherited reading indicates a favorable flow',
  '安定寄りの日です': 'The inherited reading leans toward stability',
  '慎重に整える日です': 'A day to make careful adjustments',
  '無理せず守りを固めたい日です': 'A day to protect your footing without overextending',
  '大きな偏りなし': 'No major concentration',
  'この組み合わせが、この分野の空気と判断の速さに影響します':
      'This combination influences the tone of this domain and the pace of decisions',
  '水星逆行中でもあるため、送信、公開、支払いは内容と日時を一度見直してから進めましょう':
      'Mercury is also retrograde; review content and dates before sending, publishing or paying',
  '今日は体調・メンタルを気にかける日です':
      'Pay attention to both physical condition and mental well-being today',
  '睡眠、食事、休憩を後回しにせず、予定を一つ減らすくらいの余白を作りましょう':
      'Protect sleep, meals and breaks; leave enough space to remove one commitment',
  '星の意味が重なり強く出る': 'The meanings of the planets overlap and become pronounced',
  '意識して使うと開く機会': 'An opportunity that opens through deliberate use',
  '葛藤や負荷が成長点になる': 'Conflict or strain becomes a point for growth',
  '無理なく伸びる追い風': 'Support for growth without forcing the pace',
  '相手や外側から刺激が入る':
      'Stimulus comes through other people or external circumstances',
  'ピーク': 'Peak',
  '指定日': 'Selected date',
  '接近中': 'Applying',
  '余韻': 'Separating',
  '通過中': 'In transit',
  '追い風': 'Supportive flow',
  '調整': 'Adjustment',
  '安定': 'Stable',
  '広げるチャンスを選ぶ流れ': 'Choosing opportunities for growth',
  '続ける仕組みを整える流れ': 'Building a sustainable structure',
  '価値ある使い方を見直す流れ': 'Reviewing worthwhile uses of money',
  '人との距離を整える流れ': 'Adjusting closeness with others',
  '言葉と予定を組み直す流れ': 'Reworking words and plans',
  '気持ちを急がず確認する流れ': 'Checking feelings without rushing',
  '行き違いを先に防ぐ流れ': 'Preventing misunderstandings in advance',
  '勢い買いを止めて選ぶ流れ': 'Pausing impulse purchases before choosing',
  '疲れを早めにほどく流れ': 'Easing fatigue early',
  '無理を減らして整える流れ': 'Reducing strain and making adjustments',
  '本音をやわらかく出せる流れ': 'Expressing honest feelings gently',
  '考えを形にしやすい流れ': 'Giving ideas a concrete form',
  '価値ある選択をしやすい流れ': 'Making worthwhile choices',
  '気持ちを落ち着けやすい流れ': 'Settling your feelings',
  '追い風を一つ使える流れ': 'Using one supportive opportunity',
  '楽しさを収入へつなげる流れ': 'Connecting enjoyment with income',
  '好意と広がりが重なる流れ': 'Affection and expansion overlap',
  '言葉と判断が動きやすい流れ': 'Words and decisions become active',
  '行動力が強まりやすい流れ': 'Energy for action may increase',
  '現実的に固める流れ': 'Making practical foundations firmer',
  '空の星同士が今日の色を作る流れ': 'Interactions in the sky shape the tone of the day',
  'これから強まる流れ': 'This influence is applying',
  '今日いちばん出やすい流れ': 'This influence is most pronounced today',
  '余韻を使える流れ': 'This separating influence can still be used',
  '関係性の置き場所を整える流れ': 'Finding a sustainable place for relationships',
  '役割と評価を整える流れ': 'Adjusting roles and recognition',
  '持ち物と収支を整える流れ': 'Organizing possessions, income and expenses',
  '暮らしと回復を整える流れ': 'Supporting daily life and recovery',
  '生活の土台を整える流れ': 'Putting everyday foundations in order',
  '価値と安心を選び直す流れ': 'Reconsidering value and security',
  '連絡と学びが動く流れ': 'Messages and learning become active',
  '居場所を整える流れ': 'Putting your home base in order',
  '生活リズムを整える流れ': 'Restoring your daily rhythm',
  '人との距離が見えやすい流れ': 'Noticing closeness and distance with others',
  '評価と役割が見えやすい流れ': 'Noticing recognition and roles',
  '仲間や発信が広がる流れ': 'Broadening friendships and communication',
  '静かに回復する流れ': 'Recovering quietly',
  '会話の温度を整える流れ': 'Adjusting the tone of conversation',
  '小さな段取りが効く流れ': 'Small preparations make a difference',
  '支出を選び直す流れ': 'Reconsidering spending choices',
  '気持ちの波を整える流れ': 'Settling emotional fluctuations',
  '今日の優先順位を整える流れ': 'Putting today’s priorities in order',
  '判断を急がず整える流れ': 'Making adjustments without rushed judgments',
  '新しく増やすより、続ける条件、期限、負担を一つ見直しましょう':
      'Rather than adding more, review one condition, deadline or burden that affects sustainability',
  '収入や支出の中で、長く残したい使い方を一つ選びましょう':
      'Choose one use of income or spending that you want to sustain',
  '連絡や約束は急に詰めず、心地よい距離を一つ言葉にしましょう':
      'Do not crowd messages or commitments; put one comfortable boundary into words',
  '今後も使う資料、手順、連絡文を一つ整えましょう':
      'Improve one document, procedure or message that you will use again',
  '生活の中で続けたい習慣を一つだけ短く始めましょう':
      'Make a small start on one habit you want to continue',
  '返事や判断を急がず、送る前に言葉を一度短く整えましょう':
      'Do not rush replies or judgments; briefly refine your wording before sending',
  '締切、相手、完了条件を先に確認してから作業を始めましょう':
      'Confirm the deadline, recipient and completion criteria before beginning work',
  '欲しい理由と予算をメモし、即決しない時間を作りましょう':
      'Note why you want it and your budget, then allow time before deciding',
  '予定を一つ減らし、休憩を先に入れて気持ちの負荷を下げましょう':
      'Remove one commitment and schedule a break to reduce emotional strain',
  '大きな決断を急がず、確認できる材料を一つ増やしましょう':
      'Do not rush a major decision; add one piece of evidence you can check',
  '明るい近況や感謝を一つ伝えると、関係の温度が上がりやすいです':
      'A cheerful update or expression of thanks may bring warmth to a relationship',
  '提案、連絡、下書きのどれかを一つ外へ出すと進展しやすいです':
      'Sharing one proposal, message or draft may help things move forward',
  '長く役立つもの、回収できる学び、固定費の見直しを一つ選びましょう':
      'Choose one lasting tool, useful learning opportunity or review of fixed costs',
  '安心できる場所や人を先に選び、短い回復時間を予定に入れましょう':
      'Choose a safe place or trusted person and schedule a short recovery break',
  '一番伸ばしたいことを小さく始め、反応を見て整えましょう':
      'Start small on what you most want to develop, then adjust to the response',
  '相手との約束や距離感を、無理なく続く形に一つ直しましょう':
      'Adjust one commitment or boundary into a form you can comfortably sustain',
  '任されている作業の範囲と次の確認先を一つ明確にしましょう':
      'Clarify your assigned scope and the next person or place to check with',
  '持ち物、支出、使う目的を一つ見直すと判断が落ち着きます':
      'Reviewing a possession, expense or purpose may settle your judgment',
  '家、睡眠、休憩のどれかを先に整えると気持ちが安定します':
      'Attending to home, sleep or breaks first may help feelings stabilize',
  '今日の予定を一つ減らし、優先順位が見える形にしましょう':
      'Remove one item from today’s plans and make the priorities clear',
  '連絡、メモ、短い確認を一つ済ませると流れが軽くなります':
      'Finishing one message, note or quick check may ease the flow',
  '部屋、食事、家の用事を一つ整えると気持ちが戻りやすいです':
      'Putting one room, meal or household task in order may help you feel settled',
  '休憩、食事、作業時間を一つだけ整えると調子を保ちやすいです':
      'Adjust one break, meal or work period to help maintain your condition',
  '見られる作業を一つ丁寧に仕上げると評価につながりやすいです':
      'Carefully finish one visible piece of work to support recognition',
  '人に合わせすぎず、静かな時間を先に確保しましょう':
      'Avoid over-adapting to others; reserve some quiet time first',
  '会話は短く明るく、相手の反応を待つ余白を残しましょう':
      'Keep conversation brief and warm, leaving room for the other person’s response',
  '最初の15分で一つだけ着手し、終わりの形を決めましょう':
      'Begin one task in the first 15 minutes and define what finishing means',
  '買う前に必要性と予算を確認し、迷うものは一度保留しましょう':
      'Check need and budget before buying; pause on anything uncertain',
  '短い休憩と水分を先に入れ、夜の予定を詰めすぎないようにしましょう':
      'Plan a short break and water first; avoid crowding the evening',
  '一日の中で一番大事な予定を一つだけ先に決めましょう':
      'Choose the day’s single most important commitment first',
  '決定より確認、公開より下書き、連絡より見直しを一つ選ぶと安定します':
      'Choose a check over a decision, a draft over publishing, or a review over sending',
  '今日は星の配置を材料に、動く場面と整える場面を分けて使うと流れを活かしやすくなります':
      'Use the configurations to distinguish moments for action from moments for adjustment',
  'その場面を一つ整えると、気持ちと予定がかみ合いやすくなります':
      'Putting one part of that area in order may bring feelings and plans into alignment',
  '大きく動かすより、普段の調整を丁寧にすると運が整います':
      'Careful everyday adjustments may be more useful than major moves',
  '過去のやり方を見直して次の段階へ進む節目も重なるため、続けたいことを一つ選び直すと動きやすくなります':
      'A turning point for reviewing old methods also occurs; choose again what you want to continue',
  '連絡や予定は一度見直してから確定すると安心です':
      'Review messages and plans once before confirming them',
  'グランドトラインができるため、得意なやり方を一つ具体的な行動へつなげると流れに乗りやすくなります':
      'A grand trine forms; connect one familiar strength with a concrete action',
  '今日は朝のうちに一番進めたいことへ着手し、午後は反応を見て仕上げに回すのがおすすめです':
      'Begin your main priority in the morning; respond and finish in the afternoon',
  '今日は予定を二つまでに絞り、そのうち一つを確実に終えることを最優先にしましょう':
      'Limit plans to two items and prioritize finishing one reliably',
  '今日は大きな結論を急がず、確認できる材料を一つ増やしてから次へ進むと安定します':
      'Avoid a rushed major conclusion; check one more piece of evidence before moving on',
  'この時間帯は新しい決断より、見直し、休憩、準備に回すと総合運が崩れにくくなります':
      'During this interval, review, rest and preparation may support the inherited overall reading better than new decisions',
  '連絡、契約、買い物、予定は一度見返してから確定すると、余計なやり直しを減らせます':
      'Review messages, contracts, purchases and plans before confirming them to reduce avoidable rework',
  '得意な方法を一つ決め、具体的な行動へつなげると力を活かしやすい日です':
      'Choose one familiar method and turn it into a concrete action',
  '関係するテーマを一つに絞り、優先順位を散らさないほど力を活かしやすい日です':
      'Focus on one related theme rather than scattering priorities',
  '星が集まるテーマは、あれこれ広げず一点を深めるほど持ち味になりやすいでしょう':
      'A concentrated natal theme may become a strength through depth rather than spreading attention',
  '朝のうちに最優先を一つ始め、午後は反応を見て仕上げへ回すのがおすすめです':
      'Begin one priority in the morning and use the afternoon to respond and finish',
  '今日は予定を二つまでに絞り、途中で一度だけ確認時間を取ると安定します':
      'Limit plans to two items and include one check along the way',
  '急いで結論を出さず、確認できる材料を一つ増やしてから次の判断へ進みましょう':
      'Do not rush a conclusion; check one more piece of evidence before the next decision',
  '勢いが出すぎたら短い休憩で整えましょう': 'If momentum becomes excessive, take a short break',
  '落ち込みを感じたら一人で抱えず、休息と安心できる時間を優先しましょう':
      'If you feel low, do not carry it alone; prioritize rest and reassuring time',
  '自分を出す流れが強まる': 'Self-expression becomes stronger',
  '楽しみと拡大が金運を動かす': 'Enjoyment and expansion influence money themes',
  '関係性と好みが動きやすい': 'Relationships and preferences become active',
  '判断と連絡が整いやすい': 'Decisions and messages may become more organized',
  '責任と課題が表に出る': 'Responsibilities and challenges come to the surface',
  '気分の波が運勢に出やすい': 'Mood fluctuations may appear in the inherited reading',
  '広げる力が働く': 'An expansive influence is active',
  '今期の流れに影響': 'Influences the flow of this period',
  '流れを後押しする': 'Supports the flow',
  '小さな機会を作る': 'Creates a small opportunity',
  '課題として強く出る': 'Appears strongly as a challenge',
  '影響が直接出やすい': 'The influence may be expressed directly',
  '決断を弱め、調整を強める':
      'Reduces emphasis on decisions and increases emphasis on adjustment',
  '好みと愛情の再確認': 'Revisiting preferences and affection',
  '考え方と伝え方を更新': 'Updating thinking and communication',
  '拡大運を強める': 'Emphasizes expansion in the inherited reading',
  '責任と節目を強める': 'Emphasizes responsibilities and turning points',
  '特定テーマを強調': 'Emphasizes a particular theme',
  '心身の波を反映': 'Reflects combined physical and emotional fluctuations',
  '運勢の強弱を調整': 'Adjusts the strength of the inherited outlook',
  '自分らしさ、目的、表に出る力': 'Individuality, purpose and self-expression',
  '気分、安心感、日々のコンディション': 'Mood, security and daily condition',
  '判断、連絡、言葉、学び': 'Decisions, messages, words and learning',
  '好み、愛情、お金の使い方': 'Preferences, affection and use of money',
  '拡大、チャンス、増える流れ': 'Expansion, opportunities and growth',
  '責任、制限、続ける課題': 'Responsibilities, limits and ongoing tasks',
  '今期の空気を作る': 'Shapes the tone of this period',
  '星がどの生活領域を動かすかで判断':
      'Read according to which life domain the planet activates',
  '人生の方向性': 'Direction in life',
  '心の癖と安心感': 'Emotional habits and security',
  '好きなものと愛情表現': 'Preferences and expressions of affection',
  '第一印象と自分の出し方': 'First impressions and self-presentation',
  '社会的な役割と評価': 'Social roles and recognition',
  'もともと強く出る人生テーマ': 'Life themes prominent in the natal chart',
  '出生図で重く見るテーマ': 'A theme emphasized in the natal chart',
  '好み、愛情、お金の使い方を再確認': 'Review preferences, affection and the use of money',
  '考え方、言葉、判断を更新': 'Update thinking, words and decisions',
  '拡大運、チャンス、成長を強める': 'Emphasizes expansion, opportunities and growth',
  '責任、節目、現実化を強める':
      'Emphasizes responsibilities, turning points and practical realization',
  '決断より確認、休息、調整向き': 'Favors checks, rest and adjustment over decisions',
  '星が集中するテーマを強調': 'Emphasizes the theme where planets cluster',
  '心身のリズムを運勢に反映':
      'Reflects combined physical and emotional rhythms in the inherited reading',
  '仕事、評価、肩書き': 'work, recognition and titles',
  '仲間、未来計画、広がり': 'friends, future plans and expansion',
  '休息、内面、見えない疲れ': 'rest, inner life and hidden fatigue',
  '自分の動きや見せ方': 'your actions and self-presentation',
  '収入、所有、価値観': 'income, possessions and values',
  '家、安心感、心の土台': 'home, security and emotional foundations',
  '対人関係、恋愛、約束': 'relationships, love and commitments',
  '共有、深い関係、受け取るもの': 'sharing, close relationships and what you receive',
  'そのハウスのテーマ': 'the themes of that house',
  '始める・意図を決める流れ': 'Beginning and setting intentions',
  '小さく続けて土台を育てる流れ': 'Building foundations through small continued efforts',
  '行動に移して進み具合を確かめる流れ': 'Taking action and checking progress',
  '仕上げ前の準備を整える流れ': 'Preparing before completion',
  '結果や気持ちを受け取り、振り返る流れ': 'Receiving results and feelings, then reflecting',
  '成果を分け合い、役目を整理する流れ': 'Sharing results and clarifying responsibilities',
  '不要な負担を手放し、次へ備える流れ':
      'Letting go of unnecessary burdens and preparing for what follows',
  '休息と整理で次の新月へ備える流れ': 'Resting and organizing before the next new Moon',
  '対象ハウスの定数補正を最大2天体分まで合算':
      'Sum the fixed adjustments for relevant houses, for at most 2 planets',
  '月相ごとの分野別補正（吉凶を一律にせず、最大±1.2点）':
      'Domain-specific lunar-phase adjustment, without a universal favorable/unfavorable classification; at most ±1.2 points',
  'アスペクト、オーブ、位相、ハウス重み、出生図感受性を合算':
      'Combine aspect, orb, phase, house weighting and natal sensitivity',
  'レア配置ごとの分野別補正（上限あり）':
      'Domain-specific adjustment for each rare configuration, subject to a limit',
  '分野に関係する逆行星の見直し補正（重ね掛けはせず合算上限あり）':
      'Review adjustment for retrograde planets relevant to this domain; no repeated multiplication and a cap on the sum',
  '伝統7天体の支配+0.80・高揚+0.55・損傷-0.55・フォール-0.75 × 主要要因係数（アスペクト1.00・リターン0.85・有効ハウス0.65）。同一天体は最も強い1件、合計は-1.4〜+1.4点':
      'Traditional 7 planets: domicile +0.80, exaltation +0.55, detriment -0.55, fall -0.75 × activation weight (aspect 1.00, return 0.85, relevant house 0.65). Use the strongest 1 for each planet; total -1.4 to +1.4 points',
};

// Longest tokens first so e.g. a lunar phase is not split into "Moon".
final _technicalEntries = (_technical.entries.toList()
  ..sort((a, b) => b.key.length.compareTo(a.key.length)));
const _technical = <String, String>{
  'ぱんちょ式星占い': 'Pancyo Astrology',
  '健康・メンタル運': 'Combined physical and mental well-being',
  '恋愛運': 'Love',
  '仕事運': 'Work',
  '金運': 'Money',
  '総合運': 'Overall',
  '月のハウス通過': 'Moon house transit',
  'ハウス通過': 'House transit',
  '出生図の月との響き': 'Resonance with the natal Moon',
  '天体のサイン品位': 'Planetary sign dignity',
  '出生図のステリウム': 'Natal stellium',
  '出生図のカイト': 'Natal kite',
  '空のレア配置': 'Rare sky configuration',
  '金星支配の感受性': 'Venus rulership sensitivity',
  '逆行中の星': 'Retrograde planets',
  '空の星同士のアスペクト': 'Aspects between transiting planets',
  '反映した根拠': 'Evidence used',
  '現在の星座': 'Current sign',
  'アスペクト根拠': 'Aspect basis',
  'アスペクト': 'Aspect',
  '出生図全体': 'Whole natal chart',
  '現在の流れ': 'Current influences',
  '出生図への効き方': 'Effects on the natal chart',
  '出生図の': 'natal ',
  '出生図': 'Natal chart',
  '現在の': 'current ',
  '補正': 'Adjustment',
  '現在': 'Current',
  '通過': 'Transit',
  '出生': 'Natal',
  '詳しく': 'Details',
  '閉じる': 'Close',
  '星': 'Planet',
  '月ボイド': 'Void-of-course Moon',
  '満ちていく三日月': 'Waxing crescent',
  '満ちていく凸月': 'Waxing gibbous',
  '欠けていく凸月': 'Waning gibbous',
  '欠けていく三日月': 'Waning crescent',
  '上弦の月': 'First quarter Moon',
  '下弦の月': 'Last quarter Moon',
  '新月': 'New Moon',
  '満月': 'Full Moon',
  'グランドトライン': 'Grand trine',
  'グランドクロス': 'Grand cross',
  'グランドセクスタイル': 'Grand sextile',
  'ミスティックレクタングル（ダイヤモンド）': 'Mystic rectangle (diamond)',
  'クレイドル（ゆりかご）': 'Cradle',
  'ブーメラン（ヨッド）': 'Boomerang (Yod)',
  'ハンマー・オブ・ソー': 'Thor’s hammer',
  'Tスクエア': 'T-square',
  'ヨッド': 'Yod',
  'コンジャンクション': 'conjunction',
  'セクスタイル': 'sextile',
  'スクエア': 'square',
  'トライン': 'trine',
  'オポジション': 'opposition',
  'ステリウム': 'Stellium',
  'リターン': ' return',
  '月相': 'Lunar phase',
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
  '天王星': 'Uranus',
  '海王星': 'Neptune',
  '冥王星': 'Pluto',
  '太陽': 'Sun',
  '水星': 'Mercury',
  '金星': 'Venus',
  '火星': 'Mars',
  '木星': 'Jupiter',
  '土星': 'Saturn',
  '月': 'Moon',
  '接近中': 'Applying',
  'ピーク': 'Peak',
  '余韻': 'Separating',
  '支配': 'domicile',
  '高揚': 'exaltation',
  '損傷': 'detriment',
  'フォール': 'fall',
};
