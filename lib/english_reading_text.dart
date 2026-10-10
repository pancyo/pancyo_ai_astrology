import 'app_language.dart';
import 'nine_area_reading_catalog.dart';

/// Translate an existing selected reading; never select a different model,
/// calculate scores, translate user text, or mutate the canonical JSON.
String englishKnownReading(String source) {
  const strings = AppStrings(AppLanguage.en);
  for (final entry in NineAreaReadingCatalog.entries.entries) {
    final band = entry.value.indexOf(source);
    if (band >= 0) {
      return strings.areaReading(
        AppNineArea.fromKey(entry.key),
        score: const [60, 70, 90][band],
      );
    }
  }
  const missing = '必要な星データが不足しているため、体感運は未予測です。「普通」で穴埋めしません。';
  if (source == missing)
    return strings.areaReading(AppNineArea.felt, score: null);
  final felt = RegExp(
    r'^月から見る短期の体感は「(最高|良い|普通|悪い|最悪)」の候補。木星など長めの配置は詳細に併記します。体調の負荷と、一日の満足感は分けて見てください。$',
  ).firstMatch(source);
  if (felt != null)
    return strings.areaReading(
      AppNineArea.felt,
      score: null,
      feltLabel: felt[1],
    );
  return source;
}

/// Explicitly application-generated period labels only. No DateTime conversion
/// is performed; these dates continue to designate the same JST calendar days.
String englishPeriodLabel(String source) {
  const days = {
    '月': 'Mon',
    '火': 'Tue',
    '水': 'Wed',
    '木': 'Thu',
    '金': 'Fri',
    '土': 'Sat',
    '日': 'Sun',
  };
  var result = source.replaceAllMapped(
    RegExp(r'(\d{4})年(\d{1,2})月(\d{1,2})日\(([月火水木金土日])\)'),
    (m) =>
        '${m[1]}-${m[2]!.padLeft(2, '0')}-${m[3]!.padLeft(2, '0')} (${days[m[4]]})',
  );
  result = result.replaceAllMapped(
    RegExp(r'(\d{4})/(\d{1,2})/(\d{1,2})\(([月火水木金土日])\)'),
    (m) =>
        '${m[1]}-${m[2]!.padLeft(2, '0')}-${m[3]!.padLeft(2, '0')} (${days[m[4]]})',
  );
  result = result.replaceAllMapped(
    RegExp(r'(\d{1,2})/(\d{1,2})\(([月火水木金土日])\)'),
    (m) => '${m[1]!.padLeft(2, '0')}-${m[2]!.padLeft(2, '0')} (${days[m[3]]})',
  );
  result = result.replaceAllMapped(
    RegExp(r'(\d{4})年(\d{1,2})月'),
    (m) => '${m[1]}-${m[2]!.padLeft(2, '0')}',
  );
  result = result.replaceAllMapped(RegExp(r'(\d{4})年'), (m) => m[1]!);
  return result
      .replaceAll('の毎日占い', ' • Daily reading (JST)')
      .replaceAll('ぱんちょ式星占い / ', 'Pancyo Astrology / ');
}
