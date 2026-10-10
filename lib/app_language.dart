import 'dart:ui' show Locale;

/// Display language only. It never selects a birthplace, civil day, UTC offset,
/// scoring model, or the language of previously saved predictions.
enum AppLanguage {
  ja('ja', '日本語'),
  en('en', 'English');

  const AppLanguage(this.code, this.nativeLabel);
  final String code;
  final String nativeLabel;

  static const defaultLanguage = AppLanguage.ja;
  static const supportedLocales = [Locale('ja', 'JP'), Locale('en')];

  Locale get locale => switch (this) {
    AppLanguage.ja => const Locale('ja', 'JP'),
    AppLanguage.en => const Locale('en'),
  };

  /// Persist only the canonical two-letter code. Do not infer intent from a
  /// malformed stored value, a legacy object, whitespace, or a language prefix.
  static AppLanguage fromStored(Object? value) => switch (value) {
    'en' => AppLanguage.en,
    'ja' => AppLanguage.ja,
    _ => defaultLanguage,
  };

  /// Accept this deliberately small, complete tag grammar: ja/en, optionally a
  /// script and/or region. Extensions, private-use tags, underscores, empty
  /// subtags and surrounding whitespace are unsupported and fall back to ja.
  /// BCP-47 tag casing is insensitive; stored preference casing remains strict.
  static AppLanguage fromTag(Object? value) {
    if (value is! String) return defaultLanguage;
    final match = RegExp(
      r'^(ja|en)(?:-[a-z]{4})?(?:-(?:[a-z]{2}|[0-9]{3}))?$',
      caseSensitive: false,
    ).matchAsPrefix(value);
    if (match == null || match.end != value.length) return defaultLanguage;
    return value.split('-').first.toLowerCase() == 'en' ? en : ja;
  }

  static AppLanguage fromLocale(Locale? value) =>
      fromTag(value?.toLanguageTag());
}

/// Presentation-only mirror of NineAreaKey. Never use its labels as storage,
/// JSON, or scoring identifiers; the existing machine keys remain unchanged.
enum AppNineArea {
  overall,
  love,
  work,
  money,
  mental,
  health,
  people,
  actionDecision,
  felt;

  static AppNineArea fromKey(String key) {
    for (final area in values) {
      if (area.name == key) return area;
    }
    throw ArgumentError.value(key, 'key', 'Unknown nine-area machine key');
  }
}

/// This first dictionary covers navigation, language settings, nine-area
/// labels/meanings, the seven-timepoint contract, and consultation export UI.
/// Detailed evidence, long-range readings, share images and JSON contents
/// still need their own deliberate translation work.
enum AppText {
  appTitle,
  testAppTitle,
  settings,
  profile,
  daily,
  month,
  year,
  language,
  languageHelp,
  languageIndependentTimeZone,
  save,
  saved,
  saveFailed,
  cancel,
  close,
  retry,
  loading,
  share,
  exportJson,
  nineAreaOverview,
  provisional,
  score,
  noNumericScore,
  overallMeaning,
  actionDecisionMeaning,
  feltMeaning,
  dailyStarTimeline,
  sevenTimepointMeaning,
  sevenTimepointTimes,
  midnightBoundary,
  natalHouseMeaning,
  timelineScope,
  samplingLimit,
  createDailyJson,
  createMonthJson,
  consultJsonExporting,
  consultJsonCombining,
  consultJsonCancelledRetry,
  consultJsonFailedRetry,
  consultJsonExportFailed,
  dailyJsonDialogHelp,
  monthlyJsonDialogHelp,
  consultJsonFilePrivacy,
  consultJsonShareSubject,
  consultJsonCardTitle,
  saveConsultJson,
  profileConsultJsonTitle,
  createDailyConsultData,
  createMonthConsultData,
  createYearConsultData,
  pickConsultDay,
  pickConsultMonth,
  pickConsultYear,
  confirmSelection,
  useSelectedMonth,
  useSelectedYear,
  dailyJsonDescription,
  consultJsonDescription,
  consultJsonInvalidDate,
  consultJsonContextUpdated,
  readingAppTitle,
  dailyReading,
  periodReading,
  starGuide,
  readingNavigator,
  relationshipReading,
  compactRelationshipReading,
  compactDailyReading,
  compactPeriodReading,
  compactStarGuide,
  compactReadingNavigator,
  compactProfile,
  returnToStart,
  simpleReading,
  detailedReading,
  simpleReadingDescription,
  detailedReadingDescription,
  timelineTapHint,
  timelineScrollHint,
  timelineNextMidnight,
  timelineEndBoundary,
  timelineVoidBand,
  timelineNoVoidInfo,
  timelineLoad,
  timelineShareImage,
  timelineApproximateScope,
  timelineInvalidNoon,
  timelineChangedInput,
  timelineCancelled,
  timelineFailed,
  timelineStartFailed,
  timelineNoMoonAspects,
  timelineHintTitle,
  timelineVoidHint,
}

class AppStrings {
  const AppStrings(this.language);
  final AppLanguage language;

  String _pick(String ja, String en) => language == AppLanguage.en ? en : ja;

  String text(AppText key) => switch (key) {
    AppText.appTitle => _pick('ぱんちょ式 超本格占星術占い', 'Pancyo Astrology'),
    AppText.testAppTitle => _pick(
      'ぱんちょ式星占い（改修テスト）',
      'Pancyo Astrology (test build)',
    ),
    AppText.settings => _pick('設定', 'Settings'),
    AppText.profile => _pick('プロフィール', 'Profile'),
    AppText.daily => _pick('日', 'Day'),
    AppText.month => _pick('月', 'Month'),
    AppText.year => _pick('年', 'Year'),
    AppText.language => _pick('言語', 'Language'),
    AppText.languageHelp => _pick(
      '日本語と英語を選べます。主な操作画面は英語に対応しています。一部の生成鑑定文や研究比較専用画面の説明には日本語が残ります。',
      'Choose Japanese or English. Main screens are available in English. Some generated readings and research-comparison screens may still appear in Japanese.',
    ),
    AppText.languageIndependentTimeZone => _pick(
      '表示言語を変えても、出生地の時差や日表示のJSTは変わりません。',
      'Changing the display language does not change the birthplace time offset or the JST used for daily views.',
    ),
    AppText.save => _pick('保存', 'Save'),
    AppText.saved => _pick('保存しました', 'Saved'),
    AppText.saveFailed => _pick(
      '保存できませんでした。もう一度お試しください。',
      'Could not save. Please try again.',
    ),
    AppText.cancel => _pick('中止', 'Cancel'),
    AppText.close => _pick('閉じる', 'Close'),
    AppText.retry => _pick('再試行', 'Retry'),
    AppText.loading => _pick('計算中…', 'Calculating…'),
    AppText.share => _pick('共有', 'Share'),
    AppText.exportJson => _pick('JSONを出力', 'Export JSON'),
    AppText.nineAreaOverview => _pick('9項目の見通し', 'Nine-category outlook'),
    AppText.provisional => _pick('試作・未検証', 'Experimental; unvalidated'),
    AppText.score => _pick('点数', 'Score'),
    AppText.noNumericScore => _pick('数値点はありません', 'No numeric score'),
    AppText.overallMeaning => _pick(
      '総合は従来の恋愛・仕事・金運・心身の4分野平均に、該当時の総合リターン特例を反映します。9項目の平均ではありません。',
      'Overall uses the existing four-category average for love, work, money, and combined health/mental well-being, with the overall return exception when applicable. It is not an average of all nine categories.',
    ),
    AppText.actionDecisionMeaning => _pick(
      '行動・決断運は活動性の試作値です。成功や判断の正しさを示す点数ではありません。',
      'Action & decisions is an experimental measure of activity. It does not measure success or the correctness of a decision.',
    ),
    AppText.feltMeaning => _pick(
      '体感運は本人が感じる一日の良さの予測候補です。数値点はなく、実際の体感とは分けて記録します。',
      'Felt experience is an experimental prediction of how positive the day may feel to you. It has no numeric score and is recorded separately from your actual experience.',
    ),
    AppText.dailyStarTimeline => _pick(
      '1日の星の流れ（4時間ごと・JST）',
      'Daily star timeline (every 4 hours, JST)',
    ),
    AppText.sevenTimepointMeaning => _pick(
      '1日の7時点で、各時刻に既存の9項目の式を適用します。日点数の基準は正午のままで、7点平均にはしません。',
      'The existing nine-category formulas are applied at seven times during the day. Noon remains the daily reference; the seven samples are not averaged into the daily score.',
    ),
    AppText.sevenTimepointTimes => _pick(
      '0・4・8・12・16・20・24時（JST）',
      '00:00, 04:00, 08:00, 12:00, 16:00, 20:00, 24:00 (JST)',
    ),
    AppText.midnightBoundary => _pick(
      '24時は翌日0時の境界。日内は0時から翌日0時の直前までで、翌日と二重集計しません。',
      '24:00 is 00:00 the next day. The day ends just before that instant, so it is not counted twice.',
    ),
    AppText.natalHouseMeaning => _pick(
      '出生図のASC／MCとハウスを固定します。現在地の瞬間ASC／MCは計算しません。',
      'Natal ASC/MC and houses stay fixed. Current-location ASC/MC is not calculated.',
    ),
    AppText.timelineScope => _pick(
      '出生図基準の配置表示・日点数とは別',
      'Placements relative to your natal chart; separate from the daily score',
    ),
    AppText.samplingLimit => _pick(
      '4時間刻みの配置から正確なピークや全ボイド区間を推測しません。',
      'Sampling every four hours does not determine exact peak times or every void-of-course interval.',
    ),
    AppText.createDailyJson => _pick('日JSONを作成', 'Create daily JSON'),
    AppText.createMonthJson => _pick('月JSONを作成', 'Create monthly JSON'),
    AppText.consultJsonExporting => _pick(
      '鑑定データを出力中…',
      'Exporting reading data…',
    ),
    AppText.consultJsonCombining => _pick(
      '正午の鑑定と7時点をまとめています…',
      'Combining the noon reading and seven timepoints…',
    ),
    AppText.consultJsonCancelledRetry => _pick(
      '計算を中止しました。再試行できます。',
      'Calculation cancelled. You can try again.',
    ),
    AppText.consultJsonFailedRetry => _pick(
      'JSONを作成できませんでした。再試行できます。',
      'Could not create the JSON. You can try again.',
    ),
    AppText.consultJsonExportFailed => _pick(
      'JSON出力に失敗しました。もう一度お試しください。',
      'Could not export the JSON. Please try again.',
    ),
    AppText.dailyJsonDialogHelp => _pick(
      '正午の日点数に加え、7時点の点数と根拠を出力します。24時は翌日0時です。ファイル名に人物名が入り、出生情報も含みます。',
      'Exports the noon daily scores plus scores and evidence at seven times. 24:00 is 00:00 the next day. The filename includes the person’s name, and the file contains birth details.',
    ),
    AppText.monthlyJsonDialogHelp => _pick(
      'この月の全日の9項目と根拠をまとめます。途中で中止し、もう一度作成できます。',
      'Collects the nine categories and their evidence for every day of this month. You can cancel and create it again.',
    ),
    AppText.consultJsonFilePrivacy => _pick(
      'ファイル名に人物名が入り、出生情報も含みます。',
      'The filename includes the person’s name, and the file contains birth details.',
    ),
    AppText.consultJsonShareSubject => _pick(
      'ぱんちょ式星占い AIチャット相談用データ',
      'Pancyo Astrology data for AI chat consultation',
    ),
    AppText.consultJsonCardTitle => _pick(
      'AIチャット相談用データ',
      'Data for AI chat consultation',
    ),
    AppText.saveConsultJson => _pick('JSONを保存', 'Save JSON'),
    AppText.profileConsultJsonTitle => _pick(
      'AIチャットで詳しく相談するための占いデータ',
      'Astrology data for detailed AI chat consultation',
    ),
    AppText.createDailyConsultData => _pick(
      'この日の詳しい占いデータを作る',
      'Create detailed reading data for this day',
    ),
    AppText.createMonthConsultData => _pick(
      'この月の毎日占いデータを作る',
      'Create daily reading data for this month',
    ),
    AppText.createYearConsultData => _pick(
      'この年の年運データを作る',
      'Create annual reading data for this year',
    ),
    AppText.pickConsultDay => _pick(
      '詳しく相談したい日を選択',
      'Select a day for a detailed consultation',
    ),
    AppText.pickConsultMonth => _pick(
      '相談したい月を選択',
      'Select a month for consultation',
    ),
    AppText.pickConsultYear => _pick(
      '相談したい年を選択',
      'Select a year for consultation',
    ),
    AppText.confirmSelection => _pick('決定', 'Confirm'),
    AppText.useSelectedMonth => _pick('この月にする', 'Use this month'),
    AppText.useSelectedYear => _pick('この年にする', 'Use this year'),
    AppText.dailyJsonDescription => _pick(
      '正午の新9項目と、00・04・08・12・16・20・24時の星の配置・点数・根拠を保存できます。各時刻は8項目の数値と体感の判定です。24時は翌日0時、時刻の比較は4時間刻みです。出生図のハウスを使うため現在地は不要です。旧5項目は区別して残します。ファイル名に人物名が入り、出生情報も含むので共有先に注意してください。',
      'Save the nine categories at noon, plus planetary placements, scores, and evidence at 00:00, 04:00, 08:00, 12:00, 16:00, 20:00, and 24:00. Each timepoint has eight numeric categories and a felt-experience prediction. 24:00 is 00:00 the next day; comparisons use four-hour samples. Your current location is not needed because the calculation uses natal houses. The legacy five categories remain separate. The filename includes the person’s name, and the file contains birth details, so check where you share it.',
    ),
    AppText.consultJsonDescription => _pick(
      'ChatGPTなどへファイルを添えて相談したい時に使います。日は正午の9項目と、4時間ごとの7時点の配置・点数・根拠を含みます。各時刻は8項目の数値と体感の判定、24時は翌日0時です。出生図基準で現在地は不要、日の点数を7時点の平均にはしません。月は全日の9項目、年は各月1日・15日（計24時点）の日別9項目を含みます。期間9項目の試作集計は月5時点・年24時点で、体感は候補件数です。従来の5項目集計も参考として残します。ファイル名に人物名が入り、出生情報も含むので共有先に注意してください。',
      'Use these files when attaching astrology data to a chat with ChatGPT or another assistant. Daily data includes the nine categories at noon and placements, scores, and evidence at seven times, four hours apart. Each timepoint has eight numeric categories and a felt-experience prediction; 24:00 is 00:00 the next day. The calculation uses your natal chart, so your current location is not needed. The daily score is not an average of the seven samples. Monthly data includes all nine categories for every day. Annual data samples the 1st and 15th of each month, for 24 dates. The experimental nine-category period summary uses five dates per month or 24 dates per year; felt experience is summarized as counts of prediction labels. The legacy five-category summary remains as a reference. The filename includes the person’s name, and the file contains birth details, so check where you share it.',
    ),
    AppText.consultJsonInvalidDate => _pick(
      '日付を確認して、もう一度お試しください。',
      'Check the date and try again.',
    ),
    AppText.consultJsonContextUpdated => _pick(
      '入力や設定が変わりました。もう一度作成してください。',
      'The inputs or settings changed. Please create the file again.',
    ),
    AppText.readingAppTitle => _pick('ぱんちょ式星占い', 'Pancyo Astrology'),
    AppText.dailyReading => _pick('毎日の占い', 'Daily reading'),
    AppText.periodReading => _pick('週月年占い', 'Week, month & year'),
    AppText.starGuide => _pick('星の解説', 'Astrology guide'),
    AppText.readingNavigator => _pick('鑑定ナビ', 'Reading navigator'),
    AppText.relationshipReading => _pick('相性・恋愛', 'Relationships'),
    AppText.compactRelationshipReading => _pick('相性', 'Relations'),
    AppText.compactDailyReading => _pick('毎日', 'Daily'),
    AppText.compactPeriodReading => _pick('週月年', 'Periods'),
    AppText.compactStarGuide => _pick('星', 'Guide'),
    AppText.compactReadingNavigator => _pick('鑑定', 'Navigator'),
    AppText.compactProfile => _pick('プロフ', 'Profile'),
    AppText.returnToStart => _pick('最初に戻る', 'Return to start'),
    AppText.simpleReading => _pick('簡易', 'Simple'),
    AppText.detailedReading => _pick('本格', 'Detailed'),
    AppText.simpleReadingDescription => _pick(
      '初心者向けにやさしく読む',
      'A simple reading for beginners',
    ),
    AppText.detailedReadingDescription => _pick(
      '時期と流れまで詳しく占う',
      'A detailed reading of timing and trends',
    ),
    AppText.timelineTapHint => _pick(
      '時刻を押すと、その時の配置と一言ヒントを表示します。',
      'Select a time to see the placements and a short suggestion.',
    ),
    AppText.timelineScrollHint => _pick(
      '横にスライドして時刻を選択',
      'Scroll sideways to select a time',
    ),
    AppText.timelineNextMidnight => _pick('翌日0時', '00:00 next day'),
    AppText.timelineEndBoundary => _pick(
      '（翌日0時・日末境界）',
      ' (00:00 next day; end-of-day boundary)',
    ),
    AppText.timelineVoidBand => _pick(
      '黄帯：月ボイド ',
      'Yellow band: void-of-course Moon ',
    ),
    AppText.timelineNoVoidInfo => _pick(
      'この日の計算で月ボイドの情報はありません。',
      'No void-of-course Moon information is available in this day’s calculation.',
    ),
    AppText.timelineLoad => _pick(
      '7時点の配置を読む',
      'Read placements at seven times',
    ),
    AppText.timelineShareImage => _pick('星の流れを画像で共有', 'Share timeline image'),
    AppText.timelineApproximateScope => _pick(
      '近似計算の配置表示・日点数とは別',
      'Approximate placements; separate from the daily score',
    ),
    AppText.timelineInvalidNoon => _pick(
      '正午の計算基準を確認できません。',
      'The noon calculation reference could not be verified.',
    ),
    AppText.timelineChangedInput => _pick(
      '入力が変わったため、結果を表示しません。',
      'The inputs changed, so this result is not displayed.',
    ),
    AppText.timelineCancelled => _pick(
      '計算を中止しました。正午の配置を表示しています。',
      'Calculation cancelled. The noon placements are shown.',
    ),
    AppText.timelineFailed => _pick(
      '配置を読み取れませんでした。再試行できます。',
      'The placements could not be read. You can try again.',
    ),
    AppText.timelineStartFailed => _pick(
      '配置を開始できませんでした。再試行できます。',
      'The placement calculation could not be started. You can try again.',
    ),
    AppText.timelineNoMoonAspects => _pick(
      'この時点で月と出生図の主要角度はありません（オーブ6°以内）。',
      'The Moon has no major aspects to the natal chart at this time within a 6° orb.',
    ),
    AppText.timelineHintTitle => _pick('一言ヒント：', 'Suggestion: '),
    AppText.timelineVoidHint => _pick(
      '月ボイド中。新しい決定より、見直し・休息・準備を。',
      'During the void-of-course Moon, prioritize review, rest, and preparation over new decisions.',
    ),
  };

  String timelineProgress(int completed) => _pick(
    '7時点の配置を計算中 $completed/7',
    'Calculating placements at seven times: $completed/7',
  );

  String timelineMoonDetail({
    required String time,
    required bool endBoundary,
    required String signKey,
    required String canonicalJapaneseSign,
    required String degree,
  }) =>
      '$time${endBoundary ? text(AppText.timelineEndBoundary) : ''}'
      '${_pick('  月：', '  Moon: ')}'
      '${language == AppLanguage.ja ? canonicalJapaneseSign : _zodiacNames[signKey] ?? canonicalJapaneseSign} $degree°';

  String timelineNatalHouse(int house) =>
      _pick('出生図の第${house}ハウス', 'Natal house $house');

  String timelineAspect({
    required String canonicalJapaneseLabel,
    required String transitKey,
    required String natalKey,
    required String aspectKey,
    required String orb,
  }) {
    if (language == AppLanguage.ja) return canonicalJapaneseLabel;
    final transit = _planetNames[transitKey];
    final natal = _planetNames[natalKey];
    if (transit == null || natal == null || !_aspectNames.contains(aspectKey)) {
      return canonicalJapaneseLabel;
    }
    return 'Current $transit $aspectKey natal $natal / $orb°';
  }

  /// Display translation only. The shared canonical hint and its identity
  /// remain Japanese, including when the image composer is opened.
  String timelineHint({
    required String signKey,
    required bool isVoid,
    required String canonicalJapaneseHint,
  }) {
    if (language == AppLanguage.ja) return canonicalJapaneseHint;
    if (isVoid) return text(AppText.timelineVoidHint);
    return switch (signKey) {
      'aries' => 'Start with just one task',
      'taurus' => 'Organize your plans and belongings',
      'gemini' => 'Lightly organize messages and information',
      'cancer' => 'Start from a place where you feel comfortable',
      'leo' => 'Give shape to one thing you want to show',
      'virgo' => 'Check the details before sending',
      'libra' => 'Consult someone and compare your options',
      'scorpio' => 'Focus on one thing and explore it further',
      'sagittarius' => 'Take a step toward learning or reaching out',
      'capricorn' => 'Set priorities and deadlines',
      'aquarius' => 'Try a new approach on a small scale',
      'pisces' => 'Prioritize rest and sorting out your feelings',
      _ => canonicalJapaneseHint,
    };
  }

  static const _zodiacNames = <String, String>{
    'aries': 'Aries',
    'taurus': 'Taurus',
    'gemini': 'Gemini',
    'cancer': 'Cancer',
    'leo': 'Leo',
    'virgo': 'Virgo',
    'libra': 'Libra',
    'scorpio': 'Scorpio',
    'sagittarius': 'Sagittarius',
    'capricorn': 'Capricorn',
    'aquarius': 'Aquarius',
    'pisces': 'Pisces',
  };
  static const _planetNames = <String, String>{
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
    'ascendant': 'ASC',
    'midheaven': 'MC',
  };
  static const _aspectNames = <String>{
    'conjunction',
    'sextile',
    'square',
    'trine',
    'opposition',
  };

  /// Formats progress reported by the job; it does not estimate completion.
  String dailyJsonProgress(int completed, {int total = 7}) => _pick(
    '鑑定データを出力中…（7時点 $completed/$total）',
    'Exporting reading data… ($completed/$total timepoints)',
  );

  String consultJsonSharePassed(String filename) => _pick(
    'JSONを作成し、共有先へ渡しました：$filename（保存完了は共有先で確認してください）',
    'JSON created and passed to the sharing destination: $filename (check there that saving has completed)',
  );

  String consultJsonShareCancelled(String filename) => _pick(
    '共有をキャンセルしました。JSONは一時作成のみです：$filename',
    'Sharing cancelled. The JSON was only created as a temporary file: $filename',
  );

  String consultJsonShareUnknown(String filename) => _pick(
    'JSONを一時作成しました。共有先での保存結果は確認できません：$filename',
    'A temporary JSON file was created. Saving at the sharing destination could not be confirmed: $filename',
  );

  /// Uses selected calendar components only; display language never converts
  /// the target day to another instant or time zone.
  String consultDayTarget(
    DateTime value, {
    required String canonicalJapaneseDate,
  }) => _pick(
    '対象日: $canonicalJapaneseDate',
    'Target day: ${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}',
  );

  String consultMonthTarget(DateTime value) => _pick(
    '対象月: ${value.year}年${value.month}月',
    'Target month: ${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}',
  );

  String consultYearTarget(int year) =>
      _pick('対象年: $year年', 'Target year: $year');

  String areaTitle(AppNineArea area) => switch (area) {
    AppNineArea.overall => _pick('総合運', 'Overall outlook'),
    AppNineArea.love => _pick('恋愛運', 'Love'),
    AppNineArea.work => _pick('仕事運', 'Work'),
    AppNineArea.money => _pick('金運', 'Money'),
    AppNineArea.mental => _pick('メンタル運', 'Mental well-being'),
    AppNineArea.health => _pick('健康運', 'Physical well-being'),
    AppNineArea.people => _pick('対人運', 'Relationships'),
    AppNineArea.actionDecision => _pick('行動・決断運', 'Action & decisions'),
    AppNineArea.felt => _pick('体感運', 'Felt experience'),
  };

  String areaSummary(AppNineArea area) => switch (area) {
    AppNineArea.overall => _pick(
      '一日の全体的な流れ',
      'Average outlook across six categories',
    ),
    AppNineArea.love => _pick('恋愛・親密な関係', 'Romance and intimate relationships'),
    AppNineArea.work => _pick('成果・完成・見直し', 'Progress, completion, and review'),
    AppNineArea.money => _pick(
      '収支・使い方の判断',
      'Income, spending, and money choices',
    ),
    AppNineArea.mental => _pick(
      '気分・集中・心理的負荷',
      'Mood, concentration, and mental load',
    ),
    AppNineArea.health => _pick('休息・身体の負荷', 'Rest and physical strain'),
    AppNineArea.people => _pick('家族・友人・協力', 'Family, friends, and cooperation'),
    AppNineArea.actionDecision => _pick(
      '着手・判断の活発さ',
      'Initiative and decision activity',
    ),
    AppNineArea.felt => _pick(
      '本人が感じる一日の良さ',
      'How positive the day may feel to you',
    ),
  };

  String nineAreaTitle(String exactKey) =>
      areaTitle(AppNineArea.fromKey(exactKey));
  String nineAreaSummary(String exactKey) =>
      areaSummary(AppNineArea.fromKey(exactKey));

  /// Translate only the five canonical prediction labels. Missing/unknown
  /// labels stay unavailable; no score or presumed Normal label fills the gap.
  String? feltLabelText(String? exactLabel) {
    final english = switch (exactLabel) {
      '最高' => 'Excellent',
      '良い' => 'Good',
      '普通' => 'Normal',
      '悪い' => 'Bad',
      '最悪' => 'Very bad',
      _ => null,
    };
    return english == null
        ? null
        : language == AppLanguage.en
        ? english
        : exactLabel;
  }

  /// English display translation of NineAreaPrediction.reading. Its thresholds
  /// and advice stay unchanged. This does not produce or replace a forecast.
  /// Japanese callers supply the existing canonical reading verbatim, so that
  /// this dictionary never becomes a second source of Japanese model text.
  String areaReading(
    AppNineArea area, {
    required int? score,
    String? feltLabel,
    String? canonicalJapaneseReading,
  }) {
    if (area == AppNineArea.felt && score != null) {
      throw ArgumentError.value(
        score,
        'score',
        'Felt experience has no numeric score',
      );
    }
    if (language == AppLanguage.ja) {
      if (canonicalJapaneseReading == null) {
        throw ArgumentError.notNull('canonicalJapaneseReading');
      }
      return canonicalJapaneseReading;
    }
    if (area == AppNineArea.felt) {
      final label = feltLabelText(feltLabel);
      return label == null
          ? 'Felt experience is not predicted because the required astronomical data is missing. It is not filled in as Normal.'
          : 'The short-term Moon-based candidate is "$label". Longer-term placements such as Jupiter are shown separately in the details. This experimental prediction is separate from your actual experience. Consider physical strain and satisfaction with the day separately.';
    }
    if (score == null) {
      return 'A prediction is not yet available because the required calculation data is incomplete.';
    }
    final band = score >= (area == AppNineArea.actionDecision ? 80 : 82)
        ? 2
        : score <= 65
        ? 0
        : 1;
    return switch (area) {
      AppNineArea.overall => const [
        'A day to prioritize checks and adjustments over major decisions. Choose one manageable task instead of taking everything on at once. Avoid rushing uncertain decisions, and leave room for a calm review.',
        'A day to put your usual routine in order with care. Keep your plans focused and move through them one at a time. When unsure, check first rather than rushing to the next step.',
        'It may be easier to get started on something you want to do. Take a small first step, checking other people’s responses and schedules as you go. Avoid expanding on momentum alone, and leave time to finish.',
      ][band],
      AppNineArea.love => const [
        'A day to avoid rushing to conclusions about your feelings. Review your words before sending them, and check the other person’s availability. Do not judge by reply speed alone; keep a comfortable distance.',
        'A day to value kind words and natural conversation. Listen to the other person without pressing for a reply. Share your feelings calmly, starting with a brief update or a word of thanks.',
        'A day to share an honest word with someone close to you. Try a cheerful update or an invitation that puts no pressure on them. Respect their reply and availability, and enjoy a natural conversation.',
      ][band],
      AppNineArea.work => const [
        'A day to prioritize checks and organization at work. Write down deadlines and whom to consult, and ask for help before taking too much on. Address gaps in the work at hand rather than adding new tasks.',
        'A day to build on small, careful checks. Focus your priorities and finish one task at a time. Check progress at each pause and communicate early when needed to keep things moving calmly.',
        'A day to turn your ideas into something concrete. Organize a proposal or message concisely, then put one task into action. Leave time for checks, balancing momentum with care.',
      ][band],
      AppNineArea.money => const [
        'A day to check your budget and needs rather than shopping on impulse. Give yourself time before a large purchase. Separate what you need now from what can wait.',
        'A day to organize your income, spending, and use of money. Check one planned expense or subscription, and choose within your budget. Make small adjustments and aim for choices you remain comfortable with afterward.',
        'Use this day as a chance to review how you use money. A high score does not guarantee a profit. Check your needs and budget first, then compare the terms and choose within your means.',
      ][band],
      AppNineArea.mental => const [
        'The experimental score suggests paying attention to strain on mood and concentration. Reduce your plans a little and make time for quiet rest. Put your actual feelings ahead of the score, and avoid pushing yourself too hard.',
        'The experimental score suggests a day to steady your mood and concentration. Take breaks between tasks and check your own pace. Focus on one thing at a time without rushing yourself.',
        'The experimental score suggests more emotional breathing room. Choose one thing you want to do and leave time to rest. Even if you feel well, avoid overfilling your schedule and respect your actual mood.',
      ][band],
      AppNineArea.health => const [
        'The experimental score suggests paying attention to physical strain. Do not put off breaks; adjust your plans to how your body actually feels.',
        'The experimental score suggests a day to steady your daily routine. Do not skip meals or breaks, and put your actual physical condition first.',
        'The experimental score suggests keeping activity within your limits. A high score does not guarantee good health. Make time for rest too.',
      ][band],
      AppNineArea.people => const [
        'The experimental score suggests checking rather than rushing interactions. Ask one question instead of making assumptions, and adjust your distance from the other person.',
        'The experimental score suggests a day to improve everyday contact with people around you. Send a brief message or a word of thanks, choosing a level of involvement that feels manageable.',
        'The experimental score suggests focusing on cooperation. Try one conversation or invitation to talk, and check the other person’s availability as you go.',
      ][band],
      AppNineArea.actionDecision => const [
        'The experimental score suggests a lower activity level. Try a small first step. A low score does not mean failure.',
        'The experimental score suggests a moderate activity level. Check one purpose before acting. This score does not show whether a decision is correct.',
        'The experimental score suggests a higher activity level. Pause to check before taking on more actions or decisions. Success is not guaranteed.',
      ][band],
      AppNineArea.felt => throw StateError(
        'Felt experience is not converted from a score',
      ),
    };
  }
}
