import 'package:flutter/material.dart';

import 'app_language.dart';
import 'app_language_settings.dart';
import 'english_ui_catalog.dart';
import 'english_reading_text.dart';

/// An explicit presentation boundary. Callers must not pass editable names,
/// places, diary entries or other user-authored content through this widget.
/// Stored model text and exported machine data are never changed here.
String localizedUiText(BuildContext context, String source) =>
    AppLanguageScope.stringsOf(context).language == AppLanguage.en
    ? _nativeFollowupEnglishOverrides[englishPeriodLabel(source)] ??
          englishUiText(englishPeriodLabel(source))
    : source;

/// Presentation-only labels for the astrology-engine summary. Keep this
/// explicit so callers can leave editable profile values (especially the
/// entered birthplace) untouched.
String localizedAstrologyEngineLabel(BuildContext context, String source) {
  if (AppLanguageScope.stringsOf(context).language != AppLanguage.en) {
    return source;
  }
  return _astrologyEngineLabels[source] ?? englishUiText(source);
}

/// Translates only known, app-generated values shown by HoroscopeEngineSummary.
/// The entered birthplace is user-authored and must remain verbatim. Unknown
/// text is preserved rather than guessed at.
String localizedAstrologyEngineValue(
  BuildContext context, {
  required String label,
  required String source,
}) {
  if (AppLanguageScope.stringsOf(context).language != AppLanguage.en ||
      label == '入力出生地') {
    return source;
  }
  return _englishAstrologyEngineValue(source) ?? englishUiText(source);
}

const Map<String, String> _astrologyEngineLabels = {
  '鑑定エンジンの見る範囲': 'What the reading engine covers',
  '出生図の太陽': 'Natal Sun',
  '出生図の月': 'Natal Moon',
  '出生図の金星': 'Natal Venus',
  '入力出生地': 'Entered birthplace',
  '計算地点': 'Calculation location',
  'ASC/MC': 'Ascendant / Midheaven',
  'ハウス': 'House system',
  '星データ': 'Ephemeris',
  '計算精度': 'Calculation accuracy',
  '現在の星': 'Current planets',
  'トランジット': 'Transits',
  'ハウス通過': 'House transits',
  '集中補正': 'Stellium adjustment',
  'ボイド/リターン': 'Void Moon / planetary returns',
};

String? _englishAstrologyEngineValue(String source) {
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
  const aspects = {
    'コンジャンクション': 'conjunction',
    'セクスタイル': 'sextile',
    'スクエア': 'square',
    'トライン': 'trine',
    'オポジション': 'opposition',
  };
  const phases = {'接近中': 'applying', 'ピーク': 'exact', '余韻': 'separating'};

  const fixed = {
    '出生時刻と出生地から算出': 'Calculated from birth time and birthplace',
    'ASC算出中': 'Calculating Ascendant',
    'MC算出中': 'Calculating Midheaven',
    'Placidus。出生地・出生時刻から各カスプを計算。':
        'Placidus. House cusps are calculated from the birthplace and birth time.',
    'Whole Sign。ASCのある星座全体を第1ハウスとして計算。':
        'Whole Sign. The entire Ascendant sign is treated as the first house.',
    'アプリ内簡易計算': 'In-app simplified calculations',
    '指定日の天体位置から算出': 'Calculated from planetary positions on the selected date',
    '出生図との角度を確認': 'Checking aspects to the natal chart',
    '現在の星が出生図の何ハウスを通過するか確認':
        'Checking which natal houses the current planets pass through',
    'ステリウムや強調ハウスを確認': 'Checking for stelliums and emphasized houses',
    '影響が直接出やすい角度': 'An aspect whose effects may be direct',
    'きっかけが生まれる角度': 'An aspect that may create an opening',
    '課題が出やすい角度': 'An aspect that may bring a challenge',
    '調和しやすい角度': 'An aspect that may feel harmonious',
    '外側から刺激が入る角度': 'An aspect bringing stimulus from outside',
    '現在ピーク圏': 'Near its peak now',
    'ピーク接近': 'Approaching its peak',
    'ピーク通過後': 'Past its peak',
    '翌日以降にピーク見込み': 'Peak expected on a later date',
    '指定日': 'Selected date',
    '接近中': 'Applying',
    'ピーク': 'Exact',
    '余韻': 'Separating',
    'Swiss Ephemeris未読込のため、星座境界付近、月、ハウス、ボイドは目安です。Android版では高精度アストロデータを優先して使います。':
        'Swiss Ephemeris is unavailable, so positions near sign boundaries, the Moon, houses and void-of-course periods are approximate. The Android version prioritizes higher-precision astronomical data.',
    'Swiss Ephemeris Free Edition/AGPLをAndroidネイティブで使用しています。アプリ同梱のMoshier計算で星の位置を算出し、月ボイド開始は5分探索後に最後の主要アスペクトの正確時刻へ絞り込みます。':
        'Swiss Ephemeris Free Edition/AGPL runs natively on Android. Planetary positions use the bundled Moshier calculations; the void-of-course Moon start is refined from a five-minute search to the exact time of the last major aspect.',
  };
  final fixedValue = fixed[source];
  if (fixedValue != null) return fixedValue;

  for (final fallback in ['ASC算出中', 'MC算出中']) {
    if (source.startsWith('$fallback / ')) {
      final other = _englishAstrologyEngineValue(
        source.substring('$fallback / '.length),
      );
      if (other != null) return '${fixed[fallback]} / $other';
    }
    if (source.endsWith(' / $fallback')) {
      final other = _englishAstrologyEngineValue(
        source.substring(0, source.length - ' / $fallback'.length),
      );
      if (other != null) return '$other / ${fixed[fallback]}';
    }
  }

  // PlanetPlacement.compactLabel, including the ASC/MC pair joined by the
  // summary. Require every segment to match before translating any of it.
  final placement = RegExp(
    r'(太陽|月|水星|金星|火星|木星|土星|天王星|海王星|冥王星|ASC|MC): (牡羊座|牡牛座|双子座|蟹座|獅子座|乙女座|天秤座|蠍座|射手座|山羊座|水瓶座|魚座) (\d+(?:\.\d+)?)° / 第(\d+)ハウス',
  );
  final placementMatches = placement.allMatches(source).toList();
  if (placementMatches.isNotEmpty) {
    final pieces = <String>[];
    var cursor = 0;
    for (final match in placementMatches) {
      if (source.substring(cursor, match.start) !=
          (pieces.isEmpty ? '' : ' / ')) {
        return null;
      }
      final house = int.tryParse(match.group(4)!);
      if (house == null || house < 1 || house > 12) return null;
      pieces.add(
        '${planets[match.group(1)]} in ${signs[match.group(2)]} ${match.group(3)}° / House $house',
      );
      cursor = match.end;
    }
    if (cursor != source.length) return null;
    return pieces.join(' / ');
  }

  final coordinates = RegExp(
    r'^(.+) / 緯度(-?\d+(?:\.\d+)?) 経度(-?\d+(?:\.\d+)?)$',
  ).firstMatch(source);
  if (coordinates != null) {
    final place = coordinates.group(1)!;
    final translatedPlace = place == '札幌' ? 'Sapporo' : englishUiText(place);
    return '$translatedPlace / latitude ${coordinates.group(2)}°, longitude ${coordinates.group(3)}°';
  }

  // ASC/MC may independently be unavailable while the other is calculated.
  if (source.contains(' / ')) {
    final entries = source.split(' / ');
    if (entries.every((entry) => fixed.containsKey(entry))) {
      return entries.map((entry) => fixed[entry]!).join(' / ');
    }
  }

  final aspect = RegExp(
    r'^現在の(太陽|月|水星|金星|火星|木星|土星|天王星|海王星|冥王星) (コンジャンクション|セクスタイル|スクエア|トライン|オポジション) 出生図の(太陽|月|水星|金星|火星|木星|土星|天王星|海王星|冥王星) / (\d+(?:\.\d+)?)°$',
  ).firstMatch(source);
  if (aspect != null) {
    return '${planets[aspect.group(1)]} ${aspects[aspect.group(2)]} natal ${planets[aspect.group(3)]} / ${aspect.group(4)}°';
  }

  final houseTransit = RegExp(
    r'^現在の(太陽|月|水星|金星|火星|木星|土星|天王星|海王星|冥王星): 第(\d+)ハウス$',
  ).firstMatch(source);
  if (houseTransit != null) {
    final house = int.tryParse(houseTransit.group(2)!);
    if (house != null && house >= 1 && house <= 12) {
      return '${planets[houseTransit.group(1)]}: transiting natal House $house';
    }
  }

  final stellium = RegExp(r'^第(\d+)ハウス集中: (.+)$').firstMatch(source);
  if (stellium != null) {
    final house = int.tryParse(stellium.group(1)!);
    final names = stellium.group(2)!.split('・');
    if (house != null &&
        house >= 1 &&
        house <= 12 &&
        names.length >= 3 &&
        names.every(planets.containsKey)) {
      return 'House $house stellium: ${names.map((name) => planets[name]).join(', ')}';
    }
  }

  if (source.startsWith('月ボイド ')) {
    final parts = source.split(' / ');
    final first =
        'Void-of-course Moon ${englishPeriodLabel(parts.first.substring('月ボイド '.length))}';
    if (parts.length == 1) return first;
    final rest = parts.skip(1).map(_englishAstrologyEngineValue).toList();
    if (rest.any((value) => value == null)) return null;
    return [first, ...rest.cast<String>()].join(' / ');
  }

  final estimatedPeak = RegExp(r'^ピーク推定 (.+)$').firstMatch(source);
  if (estimatedPeak != null) {
    return 'Estimated peak: ${englishPeriodLabel(estimatedPeak.group(1)!)}';
  }

  final aspectHeader = RegExp(
    r'^現在の(太陽|月|水星|金星|火星|木星|土星|天王星|海王星|冥王星) と 出生図の(太陽|月|水星|金星|火星|木星|土星|天王星|海王星|冥王星)$',
  ).firstMatch(source);
  if (aspectHeader != null) {
    return 'Current ${planets[aspectHeader.group(1)]} and natal ${planets[aspectHeader.group(2)]}';
  }

  final returnEvent = RegExp(
    r'^(太陽|月|水星|金星|火星|木星|土星|天王星|海王星|冥王星)リターン: (接近中|近い|ピーク|余韻)・(接近中|ピーク|余韻)$',
  ).firstMatch(source);
  if (returnEvent != null) {
    final distance = {
      '接近中': 'approaching',
      '近い': 'near',
      'ピーク': 'exact',
      '余韻': 'separating',
    }[returnEvent.group(2)];
    return '${planets[returnEvent.group(1)]} return: $distance, ${phases[returnEvent.group(3)]}';
  }
  return null;
}

// Fixed copy verified in the native English QA follow-up. Keep this exact-match
// table presentation-only; names, places, dates, and generated prose stay raw.
const Map<String, String> _nativeFollowupEnglishOverrides = {
  '月が次の星座へ入る前の空白時間。新規決定より見直し、休息、準備向き。':
      'A pause before the Moon enters the next sign. Favor review, rest and preparation over new decisions.',
  '西洋占星術のホロスコープであなたの本質を読み解きます。':
      'Explore your personality through a Western astrology chart.',
  '今日の星の動きから運勢の流れをお届けします。':
      'Follow the day’s outlook through current planetary movements.',
  '難しい専門用語は使わずに、丁寧に言葉へ変えます。':
      'Astrology concepts are explained in clear, everyday language.',
  'カレンダーは選んだ日の星の動きを表示します。鑑定ナビは日付を選べる日ごとの注意点や期間別の相談に使えます。期間相談は今日を起点にします。':
      'The calendar shows sky events for a selected day. The reading navigator supports date-specific daily questions and period-based consultations; periods start from today.',
  '生年月日を選択': 'Select your date of birth',
  '出生時間を選択': 'Select your birth time',
  '鑑定エンジンの見る範囲': 'What the reading engine covers',
  '全アスペクト表を開く': 'Open the full aspect table',
  'この日の主要アスペクト': 'Major aspects on this day',
  '空の星同士の流れ': 'Aspects between current planets',
  'グランドトライン': 'Grand trine',
  '今日の星の配置': 'Current planetary placements',
  '今日のリターン': 'Planetary returns today',
  '現在の天体位置': 'Current planetary positions',
  '出生図との全アスペクト': 'All aspects to the natal chart',
  '空の星同士の全アスペクト': 'All aspects between current planets',
  'リターン': 'Returns',
  '逆行・月ボイド・複合配置': 'Retrogrades, void Moon and aspect patterns',
  '該当する主要5角度はありません。': 'No matching aspects from the five major angle types.',
  '目立つ補助配置はありません。': 'No notable supporting configurations.',
  '指定日時のアスペクトはありません。': 'No aspects are available for this date and time.',
  '総合運': 'Overall',
  '恋愛運': 'Love',
  '仕事': 'Work',
  '金運': 'Money',
  '健康': 'Health',
  'メンタル': 'Mental well-being',
  '対人運': 'Relationships',
  '行動・決断': 'Action & decisions',
};

String localizedKnownReading(BuildContext context, String source) =>
    AppLanguageScope.stringsOf(context).language == AppLanguage.en
    ? englishKnownReading(source)
    : source;

class EnglishUiText extends StatelessWidget {
  const EnglishUiText(
    this.source, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  });

  final String source;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final Color? selectionColor;

  @override
  Widget build(BuildContext context) => Text(
    localizedUiText(context, source),
    style: style,
    strutStyle: strutStyle,
    textAlign: textAlign,
    textDirection: textDirection,
    locale: locale,
    softWrap: softWrap,
    overflow: overflow,
    textScaler: textScaler,
    maxLines: maxLines,
    semanticsLabel: semanticsLabel == null
        ? null
        : localizedUiText(context, semanticsLabel!),
    textWidthBasis: textWidthBasis,
    textHeightBehavior: textHeightBehavior,
    selectionColor: selectionColor,
  );
}
