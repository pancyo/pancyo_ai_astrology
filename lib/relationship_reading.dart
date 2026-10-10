part of 'main.dart';

bool _relationshipEnglish(BuildContext context) =>
    AppLanguageScope.stringsOf(context).language == AppLanguage.en;

String _relationshipCopy(
  BuildContext context,
  String japanese,
  String english,
) => _relationshipEnglish(context) ? english : japanese;

String _relationshipPlanetLabel(AstroPlanet planet, bool english) {
  if (!english) return planet.label;
  return switch (planet) {
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
}

String _relationshipAspectLabel(AspectType type, bool english) {
  if (!english) return '${type.label}（${type.angle}）';
  final name = switch (type) {
    AspectType.conjunction => 'Conjunction',
    AspectType.sextile => 'Sextile',
    AspectType.square => 'Square',
    AspectType.trine => 'Trine',
    AspectType.opposition => 'Opposition',
  };
  return '$name (${type.angle})';
}

String _relationshipCategoryTitle(
  RelationshipCategoryReading category,
  bool english,
) {
  if (!english) return category.title;
  return switch (category.key) {
    'conversation' => 'Communication style',
    'familiarity' => 'Closeness and comfort',
    'differences' => 'Possible points of misalignment',
    _ => category.title,
  };
}

String _relationshipCategoryCaption(String key, bool english) {
  if (!english) {
    return switch (key) {
      'familiarity' => '心地よい距離を探す',
      'conversation' => '言葉を、やさしく重ねる',
      _ => '違いを、ふたりの味方に',
    };
  }
  return switch (key) {
    'familiarity' => 'Find a comfortable closeness',
    'conversation' => 'Build understanding through conversation',
    'differences' => 'Make room for your differences',
    _ => 'Explore this theme together',
  };
}

String _relationshipNarrative(String japanese, bool english) {
  if (!english) return japanese;
  return const <String, String>{
        '今回の条件に合う配置の根拠は見つかりませんでした。':
            'No matching placements were found under the current criteria.',
        '助けになる面と、調整が必要な面の両方を考えられます。':
            'There may be both supportive qualities and areas that call for adjustment.',
        '言葉の伝え方や考え方のすり合わせに注目できます。':
            'You may find it useful to reflect on how you communicate and align your ways of thinking.',
        '話がずれた時は、相手の言葉を短く言い換えて確認してみましょう。':
            'If a conversation drifts, briefly restate what you heard and check that you understood.',
        '説明の速さや言葉の選び方で、行き違いが生じる場面も考えられます。':
            'Differences in pace or word choice may sometimes lead to misunderstandings.',
        '結論を急がず、質問を一つずつ確認すると話しやすくなります。':
            'Rather than rushing to a conclusion, take questions one at a time.',
        '会話に関する配置のつながりがあります。具体的な会話で確かめてください。':
            'The selected placements connect with communication themes. Check how this appears in actual conversations.',
        '意見が違う時は、まず相手が何を伝えたいかを尋ねてみましょう。':
            'When you disagree, first ask what the other person wants you to understand.',
        '一緒にいる時の心地よさや、好意の表し方を考える材料があります。':
            'These placements offer a prompt to reflect on comfort together and how affection is expressed.',
        '相手がうれしいと感じる小さな行動を、本人に聞いてみましょう。':
            'Ask what small gestures help the other person feel appreciated.',
        '親しみ方や安心する距離に違いが出ることもあります。':
            'You may have different ways of showing closeness or choosing a comfortable distance.',
        '心地よい距離や連絡の頻度を、決めつけずに話し合ってみましょう。':
            'Talk about a comfortable distance and how often to stay in touch without making assumptions.',
        '親しみ方に関する配置のつながりがあります。実際のやりとりも大切です。':
            'The selected placements connect with themes of closeness. Your actual interactions matter too.',
        '相手の反応を見ながら、好意の伝え方を調整してみましょう。':
            "Notice the other person's response and adjust how you show affection.",
        '行動のペースや責任の分け方に違いがないかを見直す材料があります。':
            'These placements offer a prompt to reflect on differences in pace or how responsibilities are shared.',
        '予定や役割を具体的に言葉にすると、負担の偏りを確かめやすくなります。':
            'Putting plans and roles into words can make it easier to check whether the workload feels balanced.',
        '行動の速さや慎重さ、責任の感じ方で意見が分かれることもあります。':
            'You may differ in how quickly you act, how cautious you are, or how you view responsibility.',
        '違いが出たら、急いで結論を出さず、できる範囲を分けて相談しましょう。':
            'When differences arise, avoid rushing to a conclusion; discuss what each of you can manage.',
        '行動やペースに関する配置のつながりがあります。問題を決めつけるものではありません。':
            'The selected placements connect with themes of pace and action. They do not establish a problem.',
        '困りごとを一つ選び、双方が無理なくできる案を一緒に探してみましょう。':
            'Choose one concern and look together for an option that feels manageable for both of you.',
        'このテーマは占星術の配置だけで判断せず、実際の会話や希望を確かめてください。':
            'Do not judge this theme from astrology alone; check in about real conversations and wishes.',
        'うまくいった場面と困った場面を分けて話し、合う方法を探してみましょう。':
            'Talk separately about what has gone well and what has felt difficult, then look for an approach that works for both of you.',
      }[japanese] ??
      japanese;
}

String _relationshipDisplayError(String japanese, bool english) {
  if (!english) return japanese;
  return switch (japanese) {
    '登録プロフィールを読み込めませんでした。手入力は引き続き使えます。' =>
      'Could not load saved profiles. You can still enter details manually.',
    '有効な日付を YYYY/MM/DD で入力してください。' => 'Enter a valid date as YYYY-MM-DD.',
    '時刻は 0:00〜23:59 の形式で入力してください。' =>
      'Enter a time in 24-hour format, from 00:00 to 23:59.',
    '出生地を認識できません。国内の登録地名または緯度,経度を入力してください。未対応地点を札幌扱いしません。' =>
      'Birthplace not recognized. Enter a supported location name in Japan or latitude, longitude coordinates. Unsupported locations are not treated as Sapporo.',
    '星の配置を計算できませんでした。入力を確認して、もう一度お試しください。' =>
      'Could not calculate the placements. Check the inputs and try again.',
    _ => japanese,
  };
}

String _relationshipInputMessage(String japanese, bool english) {
  if (!english) return japanese;
  return switch (japanese) {
    '登録プロフィールを読み込めませんでした。手入力は引き続き使えます。' =>
      'Could not load saved profiles. You can still enter details manually.',
    '登録プロフィールを確認しています…' => 'Loading saved profiles…',
    '入力した出生日時は日本標準時（JST）として扱います。海外の現地時刻からの時差変換は行いません。' =>
      'Birth dates and times are interpreted as Japan Standard Time (JST). Times from other time zones are not converted.',
    _ => _relationshipDisplayError(japanese, english),
  };
}

String _relationshipPersonDisplayName(
  _RelationshipPersonInput person,
  bool english,
) => english && person.nameWasOmitted ? 'Name not provided' : person.name;

String _relationshipProviderName(String value, bool english) {
  if (!english) return value;
  return switch (value) {
    'アプリ内簡易計算' => 'In-app simplified calculation',
    'アプリ内簡易計算（Swiss配置フォールバック）' =>
      'In-app simplified calculation (Swiss placement fallback)',
    _ => value,
  };
}

String _relationshipPrecisionNotice(String value, bool english) {
  if (!english) return value;
  return switch (value) {
    'Swiss Ephemeris未読込のため、星座境界付近、月、ハウス、ボイドは目安です。Android版では高精度アストロデータを優先して使います。' =>
      'Swiss Ephemeris is not loaded, so sign boundaries, the Moon, houses, and void-of-course periods are approximate. The Android version prioritizes high-precision astronomical data when available.',
    'Swiss Ephemeris Free Edition/AGPLをAndroidネイティブで使用しています。アプリ同梱のMoshier計算で星の位置を算出し、月ボイド開始は5分探索後に最後の主要アスペクトの正確時刻へ絞り込みます。' =>
      'Swiss Ephemeris Free Edition/AGPL is used natively on Android. Planet positions use the bundled Moshier calculations; void-of-course Moon start times are refined after a five-minute search to the last major aspect time.',
    _ => value,
  };
}

String _relationshipSummary(_RelationshipResult result, bool english) {
  if (!english) return result.summary;
  final present = result.categories
      .where((category) => category.hasEvidence)
      .map((category) => _relationshipCategoryTitle(category, true))
      .toList();
  if (present.isEmpty) {
    return 'The placements selected under these conditions did not provide evidence for the three themes.';
  }
  final joined = present.length == 1
      ? present.single
      : present.length == 2
      ? '${present.first} and ${present.last}'
      : '${present.take(present.length - 1).join(', ')}, and ${present.last}';
  return 'The selected astrological placements offer perspectives for discussing $joined. They do not determine your relationship.';
}

typedef RelationshipSavedProfilesLoader =
    Future<List<SavedUserProfile>> Function();

/// A session-only synastry reading. Profile selection is read-only and values
/// typed here are never written to preferences.
class RelationshipReading extends StatefulWidget {
  const RelationshipReading({
    super.key,
    required this.profile,
    required this.details,
    this.savedProfilesLoader,
    this.ephemerisProvider,
  });

  final AstroProfile profile;
  final UserProfileDetails details;
  final RelationshipSavedProfilesLoader? savedProfilesLoader;
  final EphemerisProvider? ephemerisProvider;

  @override
  State<RelationshipReading> createState() => _RelationshipReadingState();
}

class _RelationshipDraft {
  _RelationshipDraft({
    required String name,
    required String birthDate,
    required String birthTime,
    required String birthPlace,
  }) : nameController = TextEditingController(text: name),
       dateController = TextEditingController(text: birthDate),
       timeController = TextEditingController(text: birthTime),
       placeController = TextEditingController(text: birthPlace);
  final TextEditingController nameController;
  final TextEditingController dateController;
  final TextEditingController timeController;
  final TextEditingController placeController;
  String profileSelection = 'manual';

  void dispose() {
    nameController.dispose();
    dateController.dispose();
    timeController.dispose();
    placeController.dispose();
  }
}

class _RelationshipPersonInput {
  const _RelationshipPersonInput({
    required this.name,
    required this.nameWasOmitted,
    required this.birthDate,
    required this.birthTime,
    required this.birthPlace,
    required this.date,
    required this.timeKnown,
    required this.instantUtc,
  });

  final String name;
  final bool nameWasOmitted;
  final String birthDate;
  final String birthTime;
  final String birthPlace;
  final DateTime date;
  final bool timeKnown;
  final DateTime instantUtc;
}

class RelationshipCategoryReading {
  const RelationshipCategoryReading({
    required this.key,
    required this.title,
    required this.evidence,
    required this.text,
    required this.hint,
  });

  final String key;
  final String title;
  final List<TransitAspect> evidence;
  final String text;
  final String hint;

  bool get hasEvidence => evidence.isNotEmpty;
}

/// Keeps this screen's interpretation rules separate from natal/transit scores.
class RelationshipInterpretationService {
  const RelationshipInterpretationService();

  static const planetOrder = <AstroPlanet>[
    AstroPlanet.sun,
    AstroPlanet.moon,
    AstroPlanet.mercury,
    AstroPlanet.venus,
    AstroPlanet.mars,
    AstroPlanet.jupiter,
    AstroPlanet.saturn,
  ];
  static const allowedPlanets = <AstroPlanet>{
    AstroPlanet.sun,
    AstroPlanet.moon,
    AstroPlanet.mercury,
    AstroPlanet.venus,
    AstroPlanet.mars,
    AstroPlanet.jupiter,
    AstroPlanet.saturn,
  };
  static const maxOrbDegrees = 5.0;

  List<TransitAspect> eligibleAspects(Iterable<TransitAspect> source) {
    return source.where((aspect) {
      return allowedPlanets.contains(aspect.transitPlanet) &&
          allowedPlanets.contains(aspect.natalPlanet) &&
          aspect.orb.isFinite &&
          aspect.orb >= 0 &&
          aspect.orb <= maxOrbDegrees;
    }).toList()..sort((a, b) {
      final orbOrder = a.orb.compareTo(b.orb);
      if (orbOrder != 0) return orbOrder;
      final firstOrder = a.natalPlanet.index.compareTo(b.natalPlanet.index);
      return firstOrder != 0
          ? firstOrder
          : a.transitPlanet.index.compareTo(b.transitPlanet.index);
    });
  }

  List<PlanetPlacement> checkedPlacements(
    Iterable<PlanetPlacement> source, {
    Iterable<AstroPlanet>? requiredPlanets,
  }) {
    final found = <AstroPlanet, PlanetPlacement>{};
    for (final placement in source) {
      if (!allowedPlanets.contains(placement.planet)) continue;
      if (!placement.degree.isFinite ||
          placement.degree < 0 ||
          placement.degree >= 30) {
        throw StateError('Invalid planetary placement degree');
      }
      if (found.containsKey(placement.planet)) {
        throw StateError('Duplicate planetary placement');
      }
      found[placement.planet] = placement;
    }
    final required = requiredPlanets ?? planetOrder;
    final missing = required.where((planet) => !found.containsKey(planet));
    if (missing.isNotEmpty) {
      throw StateError('Missing required planetary placement');
    }
    return planetOrder
        .where(found.containsKey)
        .map((planet) => found[planet]!)
        .toList();
  }

  List<RelationshipCategoryReading> assess(Iterable<TransitAspect> input) {
    final aspects = eligibleAspects(input);
    final conversation = aspects
        .where(
          (aspect) =>
              aspect.transitPlanet == AstroPlanet.mercury ||
              aspect.natalPlanet == AstroPlanet.mercury,
        )
        .toList();
    final familiarity = aspects.where((aspect) {
      final venusPair =
          aspect.transitPlanet == AstroPlanet.venus ||
          aspect.natalPlanet == AstroPlanet.venus;
      final sunMoonPair =
          (aspect.transitPlanet == AstroPlanet.sun &&
              aspect.natalPlanet == AstroPlanet.moon) ||
          (aspect.transitPlanet == AstroPlanet.moon &&
              aspect.natalPlanet == AstroPlanet.sun);
      return venusPair || sunMoonPair;
    }).toList();
    final differences = aspects
        .where(
          (aspect) =>
              aspect.transitPlanet == AstroPlanet.mars ||
              aspect.natalPlanet == AstroPlanet.mars ||
              aspect.transitPlanet == AstroPlanet.saturn ||
              aspect.natalPlanet == AstroPlanet.saturn,
        )
        .toList();

    return [
      _category(
        'conversation',
        '会話の傾向',
        conversation,
        '言葉の伝え方や考え方のすり合わせに注目できます。',
        '話がずれた時は、相手の言葉を短く言い換えて確認してみましょう。',
        '説明の速さや言葉の選び方で、行き違いが生じる場面も考えられます。',
        '結論を急がず、質問を一つずつ確認すると話しやすくなります。',
        '会話に関する配置のつながりがあります。具体的な会話で確かめてください。',
        '意見が違う時は、まず相手が何を伝えたいかを尋ねてみましょう。',
      ),
      _category(
        'familiarity',
        '親しみ・心地よさ',
        familiarity,
        '一緒にいる時の心地よさや、好意の表し方を考える材料があります。',
        '相手がうれしいと感じる小さな行動を、本人に聞いてみましょう。',
        '親しみ方や安心する距離に違いが出ることもあります。',
        '心地よい距離や連絡の頻度を、決めつけずに話し合ってみましょう。',
        '親しみ方に関する配置のつながりがあります。実際のやりとりも大切です。',
        '相手の反応を見ながら、好意の伝え方を調整してみましょう。',
      ),
      _category(
        'differences',
        'すれ違いやすい点',
        differences,
        '行動のペースや責任の分け方に違いがないかを見直す材料があります。',
        '予定や役割を具体的に言葉にすると、負担の偏りを確かめやすくなります。',
        '行動の速さや慎重さ、責任の感じ方で意見が分かれることもあります。',
        '違いが出たら、急いで結論を出さず、できる範囲を分けて相談しましょう。',
        '行動やペースに関する配置のつながりがあります。問題を決めつけるものではありません。',
        '困りごとを一つ選び、双方が無理なくできる案を一緒に探してみましょう。',
      ),
    ];
  }

  RelationshipCategoryReading _category(
    String key,
    String title,
    List<TransitAspect> evidence,
    String supportive,
    String supportiveHint,
    String tense,
    String tenseHint,
    String neutral,
    String neutralHint,
  ) {
    if (evidence.isEmpty) {
      return RelationshipCategoryReading(
        key: key,
        title: title,
        evidence: const [],
        text: '今回の条件に合う配置の根拠は見つかりませんでした。',
        hint: 'このテーマは占星術の配置だけで判断せず、実際の会話や希望を確かめてください。',
      );
    }
    final hasSupportive = evidence.any(
      (aspect) =>
          aspect.type == AspectType.sextile || aspect.type == AspectType.trine,
    );
    final hasTension = evidence.any(
      (aspect) =>
          aspect.type == AspectType.square ||
          aspect.type == AspectType.opposition,
    );
    if (hasSupportive && hasTension) {
      return RelationshipCategoryReading(
        key: key,
        title: title,
        evidence: evidence,
        text: '助けになる面と、調整が必要な面の両方を考えられます。',
        hint: 'うまくいった場面と困った場面を分けて話し、合う方法を探してみましょう。',
      );
    }
    if (hasSupportive) {
      return RelationshipCategoryReading(
        key: key,
        title: title,
        evidence: evidence,
        text: supportive,
        hint: supportiveHint,
      );
    }
    if (hasTension) {
      return RelationshipCategoryReading(
        key: key,
        title: title,
        evidence: evidence,
        text: tense,
        hint: tenseHint,
      );
    }
    return RelationshipCategoryReading(
      key: key,
      title: title,
      evidence: evidence,
      text: neutral,
      hint: neutralHint,
    );
  }
}

class _RelationshipResult {
  const _RelationshipResult({
    required this.first,
    required this.second,
    required this.categories,
    required this.ephemerisName,
    required this.precisionNotice,
    required this.highPrecision,
    required this.moonExcluded,
  });

  final _RelationshipPersonInput first;
  final _RelationshipPersonInput second;
  final List<RelationshipCategoryReading> categories;
  final String ephemerisName;
  final String precisionNotice;
  final bool highPrecision;
  final bool moonExcluded;

  String get summary {
    final present = categories
        .where((item) => item.hasEvidence)
        .map((item) => item.title)
        .toList();
    if (present.isEmpty) {
      return '今回の条件で採用した配置から、3つのテーマに対応する根拠は見つかりませんでした。';
    }
    return '占星術の配置から、' +
        present.join('・') +
        'を話し合うための視点が見つかりました。二人の関係を決めつけるものではありません。';
  }
}

class _RelationshipReadingState extends State<RelationshipReading> {
  static const _manualProfile = 'manual';
  late _RelationshipDraft _firstDraft;
  late _RelationshipDraft _secondDraft;
  List<SavedUserProfile> _savedProfiles = const [];
  bool _profilesLoading = true;
  bool _isCalculating = false;
  String? _profileLoadError;
  String? _calculationError;
  Map<String, String> _fieldErrors = const {};
  _RelationshipResult? _result;
  Timer? _calculationDelay;
  int _calculationOwner = 0;
  int _profileLoadOwner = 0;

  EphemerisProvider get _ephemeris =>
      widget.ephemerisProvider ?? AstrologyDataSources.current;

  @override
  void initState() {
    super.initState();
    _firstDraft = _draftFromCurrentProfile();
    _secondDraft = _RelationshipDraft(
      name: '',
      birthDate: '',
      birthTime: '',
      birthPlace: '',
    );
    _attachDraftListeners(_firstDraft);
    _attachDraftListeners(_secondDraft);
    _loadSavedProfiles();
  }

  _RelationshipDraft _draftFromCurrentProfile() {
    return _RelationshipDraft(
      name: widget.profile.name,
      birthDate: widget.profile.birthDate,
      // details contains the recorded value. profile may already contain a
      // calculation-only noon fallback, which must stay unknown here.
      birthTime: widget.details.birthTime,
      birthPlace: widget.details.birthPlace,
    );
  }

  void _attachDraftListeners(_RelationshipDraft draft) {
    draft.nameController.addListener(_inputChanged);
    draft.dateController.addListener(_inputChanged);
    draft.timeController.addListener(_inputChanged);
    draft.placeController.addListener(_inputChanged);
  }

  @override
  void didUpdateWidget(covariant RelationshipReading oldWidget) {
    super.didUpdateWidget(oldWidget);
    final profileChanged =
        oldWidget.profile.name != widget.profile.name ||
        oldWidget.profile.birthDate != widget.profile.birthDate ||
        oldWidget.details.birthTime != widget.details.birthTime ||
        oldWidget.details.birthPlace != widget.details.birthPlace;
    if (profileChanged) {
      _invalidateCalculation(notify: false);
      _firstDraft.dispose();
      _firstDraft = _draftFromCurrentProfile();
      _attachDraftListeners(_firstDraft);
    }
  }

  Future<void> _loadSavedProfiles() async {
    final owner = ++_profileLoadOwner;
    try {
      final profiles =
          await (widget.savedProfilesLoader ?? SavedUserProfile.loadAll)();
      if (!mounted || owner != _profileLoadOwner) return;
      setState(() {
        _savedProfiles = profiles;
        _profilesLoading = false;
        _profileLoadError = null;
      });
    } catch (_) {
      if (!mounted || owner != _profileLoadOwner) return;
      setState(() {
        _profilesLoading = false;
        _profileLoadError = '登録プロフィールを読み込めませんでした。手入力は引き続き使えます。';
      });
    }
  }

  @override
  void dispose() {
    _calculationOwner++;
    _profileLoadOwner++;
    _calculationDelay?.cancel();
    _firstDraft.dispose();
    _secondDraft.dispose();
    super.dispose();
  }

  void _invalidateCalculation({bool notify = true}) {
    _calculationOwner++;
    _calculationDelay?.cancel();
    _result = null;
    _isCalculating = false;
    _calculationError = null;
    _fieldErrors = const {};
    if (notify && mounted) setState(() {});
  }

  void _inputChanged() {
    _invalidateCalculation();
  }

  void _selectSavedProfile(_RelationshipDraft draft, String? selection) {
    if (selection == null) return;
    draft.profileSelection = selection;
    if (selection != _manualProfile) {
      final id = selection.substring('saved:'.length);
      SavedUserProfile? saved;
      for (final candidate in _savedProfiles) {
        if (candidate.id == id) {
          saved = candidate;
          break;
        }
      }
      if (saved != null) {
        draft.nameController.text = saved.name;
        draft.dateController.text = saved.birthDate;
        draft.timeController.text = saved.details.birthTime;
        draft.placeController.text = saved.details.birthPlace;
      }
    }
    setState(() {});
  }

  DateTime? _parseDate(String text) {
    final match = RegExp(
      r'^(\d{4})\s*[./年-]\s*(\d{1,2})\s*[./月-]\s*(\d{1,2})\s*日?$',
    ).firstMatch(text.trim());
    if (match == null) return null;
    final year = int.tryParse(match.group(1) ?? '');
    final month = int.tryParse(match.group(2) ?? '');
    final day = int.tryParse(match.group(3) ?? '');
    if (year == null || month == null || day == null || year < 1) return null;
    final date = DateTime.utc(year, month, day);
    if (date.year != year || date.month != month || date.day != day)
      return null;
    return date;
  }

  (int hour, int minute)? _parseTime(String text) {
    if (text.trim().isEmpty) return null;
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(text.trim());
    if (match == null) return null;
    final hour = int.tryParse(match.group(1) ?? '');
    final minute = int.tryParse(match.group(2) ?? '');
    if (hour == null || minute == null || hour > 23 || minute > 59) return null;
    return (hour, minute);
  }

  bool _placeIsRecognized(_RelationshipDraft draft, String time) {
    final placeText = draft.placeController.text.trim();
    if (placeText.isEmpty) return false;
    final profile = AstroProfile(
      name: draft.nameController.text.trim(),
      birthDate: draft.dateController.text.trim(),
      birthTime: time,
      birthPlace: placeText,
      theme: widget.profile.theme,
    );
    final resolved = _ephemeris.placeForProfile(profile);
    final coordinateMatch = RegExp(
      r'(-?\d+(?:\.\d+)?)\s*[,、]\s*(-?\d+(?:\.\d+)?)',
    ).firstMatch(placeText);
    if (coordinateMatch != null) {
      final latitude = double.tryParse(coordinateMatch.group(1) ?? '');
      final longitude = double.tryParse(coordinateMatch.group(2) ?? '');
      return latitude != null &&
          longitude != null &&
          latitude.isFinite &&
          longitude.isFinite &&
          latitude.abs() <= 90 &&
          longitude.abs() <= 180 &&
          resolved.label == '緯度経度指定';
    }
    // Existing location resolution falls back to Sapporo for an unrecognized
    // string. Do not silently present that fallback as a real birthplace.
    if (resolved.label == '北海道札幌市' && !placeText.contains('札幌')) {
      return false;
    }
    return resolved.latitude.isFinite &&
        resolved.longitude.isFinite &&
        resolved.latitude.abs() <= 90 &&
        resolved.longitude.abs() <= 180;
  }

  bool _validateInputs() {
    final errors = <String, String>{};
    void validate(_RelationshipDraft draft, String prefix) {
      final parsedDate = _parseDate(draft.dateController.text);
      final timeValue = draft.timeController.text.trim();
      if (parsedDate == null) {
        errors[prefix + '.date'] = '有効な日付を YYYY/MM/DD で入力してください。';
      }
      if (timeValue.isNotEmpty && _parseTime(timeValue) == null) {
        errors[prefix + '.time'] = '時刻は 0:00〜23:59 の形式で入力してください。';
      }
      if (parsedDate != null &&
          (timeValue.isEmpty || _parseTime(timeValue) != null) &&
          !_placeIsRecognized(draft, timeValue)) {
        errors[prefix + '.place'] =
            '出生地を認識できません。国内の登録地名または緯度,経度を入力してください。未対応地点を札幌扱いしません。';
      }
    }

    validate(_firstDraft, 'first');
    validate(_secondDraft, 'second');
    setState(() => _fieldErrors = errors);
    return errors.isEmpty;
  }

  _RelationshipPersonInput _makePersonInput(_RelationshipDraft draft) {
    final date = _parseDate(draft.dateController.text)!;
    final parsedTime = _parseTime(draft.timeController.text);
    final known = parsedTime != null;
    final hour = parsedTime?.$1 ?? 12;
    final minute = parsedTime?.$2 ?? 0;
    final instantUtc = DateTime.utc(
      date.year,
      date.month,
      date.day,
      hour,
      minute,
    ).subtract(const Duration(hours: 9));
    return _RelationshipPersonInput(
      name: draft.nameController.text.trim().isEmpty
          ? '名前未入力'
          : draft.nameController.text.trim(),
      nameWasOmitted: draft.nameController.text.trim().isEmpty,
      birthDate: draft.dateController.text.trim(),
      birthTime: known ? draft.timeController.text.trim() : '12:00（仮）',
      birthPlace: draft.placeController.text.trim(),
      date: date,
      timeKnown: known,
      instantUtc: instantUtc,
    );
  }

  Future<void> _calculate() async {
    FocusScope.of(context).unfocus();
    if (!_validateInputs()) return;
    final first = _makePersonInput(_firstDraft);
    final second = _makePersonInput(_secondDraft);
    final owner = ++_calculationOwner;
    _calculationDelay?.cancel();
    setState(() {
      _result = null;
      _calculationError = null;
      _isCalculating = true;
    });
    // Yield so the calculating state is rendered. Any edit or route disposal
    // invalidates owner before a delayed result can be committed.
    _calculationDelay = Timer(const Duration(milliseconds: 24), () {
      if (!mounted || owner != _calculationOwner) return;
      try {
        final useSwiss = _ephemeris is SwissEphemerisProvider;
        final swissFallbacksBefore = useSwiss
            ? SwissEphemerisProvider._placementFallbackCount
            : null;
        final placementValidator = const RelationshipInterpretationService();
        final moonExcluded = !first.timeKnown || !second.timeKnown;
        final requiredPlanets = moonExcluded
            ? RelationshipInterpretationService.planetOrder.where(
                (planet) => planet != AstroPlanet.moon,
              )
            : RelationshipInterpretationService.planetOrder;
        final firstAll = placementValidator.checkedPlacements(
          _ephemeris.placementsFor(first.instantUtc),
          requiredPlanets: requiredPlanets,
        );
        final secondAll = placementValidator.checkedPlacements(
          _ephemeris.placementsFor(second.instantUtc),
          requiredPlanets: requiredPlanets,
        );
        final firstPlacements = moonExcluded
            ? firstAll.where((item) => item.planet != AstroPlanet.moon).toList()
            : firstAll;
        final secondPlacements = moonExcluded
            ? secondAll
                  .where((item) => item.planet != AstroPlanet.moon)
                  .toList()
            : secondAll;
        final rawAspects = _ephemeris.aspects(
          transit: secondPlacements,
          natal: firstPlacements,
        );
        final secondPlanets = secondPlacements
            .map((item) => item.planet)
            .toSet();
        final firstPlanets = firstPlacements.map((item) => item.planet).toSet();
        final presentAspects = rawAspects.where(
          (aspect) =>
              secondPlanets.contains(aspect.transitPlanet) &&
              firstPlanets.contains(aspect.natalPlanet),
        );
        final categories = const RelationshipInterpretationService().assess(
          presentAspects,
        );
        final swissFallbackOccurred =
            useSwiss &&
            SwissEphemerisProvider._placementFallbackCount !=
                swissFallbacksBefore;
        final result = _RelationshipResult(
          first: first,
          second: second,
          categories: categories,
          ephemerisName: swissFallbackOccurred
              ? 'アプリ内簡易計算（Swiss配置フォールバック）'
              : _ephemeris.sourceName,
          precisionNotice: swissFallbackOccurred
              ? const SimpleEphemeris().precisionNotice
              : _ephemeris.precisionNotice,
          highPrecision:
              _ephemeris.usesHighPrecisionAstroData && !swissFallbackOccurred,
          moonExcluded: moonExcluded,
        );
        if (!mounted || owner != _calculationOwner) return;
        setState(() {
          _result = result;
          _isCalculating = false;
          _calculationDelay = null;
        });
      } catch (_) {
        if (!mounted || owner != _calculationOwner) return;
        setState(() {
          _isCalculating = false;
          _calculationDelay = null;
          _calculationError = '星の配置を計算できませんでした。入力を確認して、もう一度お試しください。';
        });
      }
    });
  }

  void _cancelCalculation() {
    _invalidateCalculation();
  }

  static const _ink = Color(0xFF3F3149);
  static const _muted = Color(0xFF74657B);
  static const _rose = Color(0xFFA7476A);
  static const _lilac = Color(0xFF75639D);
  static const _line = Color(0xFFE8DEEA);

  @override
  Widget build(BuildContext context) {
    final parent = Theme.of(context);
    final scheme =
        ColorScheme.fromSeed(
          seedColor: _rose,
          brightness: Brightness.light,
        ).copyWith(
          primary: _rose,
          secondary: _lilac,
          surface: const Color(0xFFFFFCFE),
          onSurface: _ink,
          onSurfaceVariant: _muted,
          outline: const Color(0xFFAE9BAD),
        );
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: parent.textTheme.apply(bodyColor: _ink, displayColor: _ink),
      // ResultScreen already paints the shared StarScaffold background.
      // Keep this page transparent so its cards sit over that artwork.
      scaffoldBackgroundColor: Colors.transparent,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFFFFCFE),
        labelStyle: const TextStyle(color: _muted, fontSize: 14),
        hintStyle: const TextStyle(color: _muted, fontSize: 13),
        helperStyle: const TextStyle(color: _muted, fontSize: 12, height: 1.45),
        helperMaxLines: 4,
        errorMaxLines: 3,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 15,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _rose, width: 1.7),
        ),
      ),
      dividerColor: _line,
    );
    return Theme(
      data: theme,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(
            _relationshipCopy(context, '相性・恋愛', 'Relationships & Romance'),
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          foregroundColor: Colors.white,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          actions: const [
            Padding(
              padding: EdgeInsets.only(right: 20),
              child: Icon(Icons.balance_rounded, color: _lilac, size: 23),
            ),
          ],
        ),
        bottomNavigationBar: Builder(builder: _actionBar),
        body: SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, viewport) {
              final largeText = MediaQuery.textScalerOf(context).scale(14) > 18;
              final wide = viewport.maxWidth >= (largeText ? 1080 : 800);
              final gutter = viewport.maxWidth < 480 ? 16.0 : 28.0;
              return SingleChildScrollView(
                key: const ValueKey('relationship-scroll'),
                padding: EdgeInsets.fromLTRB(gutter, 6, gutter, 28),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1120),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _RelationshipReveal(child: _hero(context)),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: _step(
                                '01',
                                _relationshipCopy(
                                  context,
                                  viewport.maxWidth < 480
                                      ? '二人の入力'
                                      : '二人のプロフィール',
                                  viewport.maxWidth < 480
                                      ? 'Enter both people'
                                      : 'Both profiles',
                                ),
                                active: _result == null,
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 10),
                              child: Icon(
                                Icons.chevron_right_rounded,
                                color: _muted,
                                size: 18,
                              ),
                            ),
                            Expanded(
                              child: _step(
                                '02',
                                _relationshipCopy(
                                  context,
                                  '星からのヒント',
                                  'Explore the themes',
                                ),
                                active: _result != null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (wide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _personCard(
                                  context,
                                  _firstDraft,
                                  _relationshipCopy(context, '一人目', 'Person 1'),
                                  'first',
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  10,
                                  32,
                                  10,
                                  0,
                                ),
                                child: Icon(
                                  Icons.favorite_rounded,
                                  size: 20,
                                  color: _rose.withValues(alpha: 0.65),
                                ),
                              ),
                              Expanded(
                                child: _personCard(
                                  context,
                                  _secondDraft,
                                  _relationshipCopy(context, '二人目', 'Person 2'),
                                  'second',
                                ),
                              ),
                            ],
                          )
                        else ...[
                          _personCard(
                            context,
                            _firstDraft,
                            _relationshipCopy(context, '一人目', 'Person 1'),
                            'first',
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: Icon(
                              Icons.favorite_rounded,
                              size: 20,
                              color: _rose,
                            ),
                          ),
                          _personCard(
                            context,
                            _secondDraft,
                            _relationshipCopy(context, '二人目', 'Person 2'),
                            'second',
                          ),
                        ],
                        const SizedBox(height: 16),
                        _limitsCard(context),
                        if (_calculationError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Semantics(
                              liveRegion: true,
                              child: Text(
                                _relationshipDisplayError(
                                  _calculationError!,
                                  _relationshipEnglish(context),
                                ),
                                style: TextStyle(color: scheme.error),
                              ),
                            ),
                          ),
                        if (_result != null) ...[
                          const SizedBox(height: 24),
                          _RelationshipReveal(
                            key: ObjectKey(_result),
                            scrollIntoView: true,
                            child: _resultView(context, _result!),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _hero(BuildContext context) {
    final compact =
        MediaQuery.sizeOf(context).width < 580 ||
        MediaQuery.textScalerOf(context).scale(14) > 18;
    return Container(
      padding: EdgeInsets.all(compact ? 22 : 28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF9E8EE), Color(0xFFF1EAF7), Color(0xFFEBEAF7)],
        ),
        border: Border.all(color: const Color(0xFFF0DFE9)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.auto_awesome_rounded,
                      size: 15,
                      color: _rose,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        _relationshipCopy(
                          context,
                          'ふたりの星、ふたりの関係',
                          'A reading for two people',
                        ),
                        style: TextStyle(
                          color: _rose,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _relationshipCopy(
                    context,
                    'ふたりの距離を、\n星から読み解く。',
                    'Explore your\nrelationship through the stars.',
                  ),
                  style: TextStyle(
                    fontSize: compact ? 25 : 30,
                    height: 1.4,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _relationshipCopy(
                    context,
                    '親しみ方も、言葉の伝え方も。\nふたりらしい関係のヒントを見つけよう。',
                    'Reflect on closeness, communication, and what makes your relationship yours.',
                  ),
                  style: TextStyle(color: _muted, height: 1.7, fontSize: 13),
                ),
              ],
            ),
          ),
          if (!compact) ...[
            const SizedBox(width: 28),
            const _RelationshipOrbit(size: 164),
          ],
        ],
      ),
    );
  }

  Widget _step(String number, String title, {required bool active}) {
    return _RelationshipStep(number: number, title: title, active: active);
  }

  Widget _surface({
    required Widget child,
    Color? color,
    EdgeInsets padding = const EdgeInsets.all(20),
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _line),
        boxShadow: [
          BoxShadow(
            color: _ink.withValues(alpha: 0.035),
            blurRadius: 20,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Material(type: MaterialType.transparency, child: child),
    );
  }

  Widget _personCard(
    BuildContext context,
    _RelationshipDraft draft,
    String label,
    String prefix,
  ) {
    final first = prefix == 'first';
    final english = _relationshipEnglish(context);
    final accent = first ? _rose : _lilac;
    final options = <DropdownMenuItem<String>>[
      DropdownMenuItem(
        value: _manualProfile,
        child: Text(
          english ? 'Enter for this session (not saved)' : '今回のみ入力（保存しない）',
          overflow: TextOverflow.ellipsis,
        ),
      ),
      ..._savedProfiles.map(
        (profile) => DropdownMenuItem(
          value: 'saved:' + profile.id,
          child: Text(
            (english ? 'Saved: ' : '登録済み: ') + profile.name,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    ];
    final selected = options.any((item) => item.value == draft.profileSelection)
        ? draft.profileSelection
        : _manualProfile;
    return _surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.09),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  first ? Icons.wb_sunny_outlined : Icons.nightlight_round,
                  color: accent,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      draft.nameController.text.trim().isEmpty
                          ? (english ? 'Enter profile details' : 'プロフィールを入力')
                          : draft.nameController.text,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            key: ValueKey('relationship-profile-' + prefix),
            value: selected,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: english ? 'Profile' : 'プロフィール',
            ),
            items: options,
            onChanged: (value) => _selectSavedProfile(draft, value),
          ),
          if (_profilesLoading)
            Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                english ? 'Loading saved profiles…' : '登録プロフィールを確認しています…',
                style: const TextStyle(fontSize: 12, color: _muted),
              ),
            ),
          if (_profileLoadError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _relationshipInputMessage(_profileLoadError!, english),
                style: const TextStyle(color: Color(0xFFBA1A1A)),
              ),
            ),
          const SizedBox(height: 12),
          TextField(
            key: ValueKey('relationship-name-' + prefix),
            controller: draft.nameController,
            decoration: InputDecoration(
              labelText: english ? 'Name (optional)' : '呼び名（任意）',
              prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextField(
            key: ValueKey('relationship-date-' + prefix),
            controller: draft.dateController,
            keyboardType: TextInputType.datetime,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: english ? 'Date of birth' : '生年月日',
              hintText: english ? 'YYYY-MM-DD' : 'YYYY/MM/DD',
              helperText: english
                  ? 'Birth date and time are interpreted in Japan Standard Time (JST).'
                  : null,
              prefixIcon: const Icon(Icons.calendar_today_outlined, size: 19),
              errorText: _fieldErrors[prefix + '.date'] == null
                  ? null
                  : _relationshipInputMessage(
                      _fieldErrors[prefix + '.date']!,
                      english,
                    ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: ValueKey('relationship-time-' + prefix),
            controller: draft.timeController,
            keyboardType: TextInputType.datetime,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: english
                  ? 'Birth time (leave blank if unknown)'
                  : '出生時刻（不明なら空欄）',
              hintText: english ? 'e.g. 14:30' : '例 14:30',
              prefixIcon: const Icon(Icons.schedule_rounded, size: 20),
              errorText: _fieldErrors[prefix + '.time'] == null
                  ? null
                  : _relationshipInputMessage(
                      _fieldErrors[prefix + '.time']!,
                      english,
                    ),
              helperText: english
                  ? 'If you do not know the time, leave this blank.'
                  : '分からない場合は、空欄のままで大丈夫です。',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: ValueKey('relationship-place-' + prefix),
            controller: draft.placeController,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: english ? 'Birthplace' : '出生地',
              hintText: english ? 'e.g. 35.68, 139.76' : '例 東京都、または緯度,経度',
              prefixIcon: const Icon(Icons.place_outlined, size: 20),
              errorText: _fieldErrors[prefix + '.place'] == null
                  ? null
                  : _relationshipInputMessage(
                      _fieldErrors[prefix + '.place']!,
                      english,
                    ),
              helperText: english
                  ? 'Use a supported location in Japan or latitude, longitude coordinates. Unsupported locations are rejected.'
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBar(BuildContext context) {
    final english = _relationshipEnglish(context);
    final narrow =
        MediaQuery.sizeOf(context).width < 680 ||
        MediaQuery.textScalerOf(context).scale(14) > 18;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: const BoxDecoration(
          color: Colors.transparent,
          border: Border(top: BorderSide(color: Color(0x33FFFFFF))),
        ),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: Row(
              children: [
                if (!narrow) ...[
                  const Icon(
                    Icons.favorite_border_rounded,
                    color: _rose,
                    size: 21,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      english
                          ? 'Relationship reflections inspired by your charts.'
                          : 'ふたりの星から、関係のヒントを。',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                ],
                Expanded(
                  flex: narrow ? 1 : 0,
                  child: FilledButton(
                    key: const ValueKey('relationship-calculate'),
                    onPressed: _isCalculating ? null : _calculate,
                    style: FilledButton.styleFrom(
                      backgroundColor: _rose,
                      disabledBackgroundColor: const Color(0xFFF0E4ED),
                      disabledForegroundColor: _ink,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 52),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_isCalculating)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _rose,
                            ),
                          )
                        else
                          const Icon(Icons.auto_awesome_rounded, size: 20),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            _isCalculating
                                ? (english
                                      ? 'Calculating placements…'
                                      : '配置を計算しています…')
                                : (english
                                      ? 'Explore your connection'
                                      : '相性を読み解く'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_isCalculating) ...[
                  const SizedBox(width: 6),
                  TextButton(
                    key: const ValueKey('relationship-cancel'),
                    onPressed: _cancelCalculation,
                    child: Text(english ? 'Cancel' : '計算を中止'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _limitsCard(BuildContext context) {
    final english = _relationshipEnglish(context);
    return ExpansionTile(
      key: const ValueKey('relationship-reading-conditions'),
      tilePadding: const EdgeInsets.symmetric(horizontal: 8),
      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      leading: const Icon(Icons.info_outline_rounded, size: 20, color: _muted),
      title: Text(
        english ? 'How this reading works' : 'この読みの前提',
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        english
            ? 'This reading does not give a compatibility score or success rate.'
            : '相性を成功率や点数で表しません。',
        style: const TextStyle(fontSize: 12, color: _muted),
      ),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              english
                  ? 'Birth dates and times are interpreted as Japan Standard Time (JST). Times from other time zones are not converted.'
                  : '入力した出生日時は日本標準時（JST）として扱います。海外の現地時刻からの時差変換は行いません。',
            ),
            SizedBox(height: 8),
            Text(
              english
                  ? 'Birthplace must be a supported location in Japan or latitude/longitude coordinates. This reading does not use birthplace and does not include the Ascendant, Midheaven, or houses.'
                  : '出生地は国内登録地点または緯度・経度で認識します。この読みでは場所を計算に使わず、ASC・MC・ハウスも扱いません。',
            ),
            SizedBox(height: 8),
            Text(
              english
                  ? 'If either birth time is unknown, noon is used as a temporary calculation time and the Moon is excluded for both people. Noon is not recorded as an actual birth time.'
                  : '出生時刻が一人でも不明なら正午を仮の計算時刻に使い、月は二人とも除外します。正午を実際の出生時刻として記録しません。',
            ),
            SizedBox(height: 8),
            Text(
              english
                  ? 'The reading uses seven traditional planets, five major aspects, and a fixed orb of up to 5°.'
                  : '伝統的な7天体と主要5アスペクト、固定オーブ5°以内だけを使います。',
            ),
          ],
        ),
      ],
    );
  }

  Widget _resultView(BuildContext context, _RelationshipResult result) {
    final english = _relationshipEnglish(context);
    return Column(
      key: const ValueKey('relationship-result'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _surface(
          color: const Color(0xFFF7EFF6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.auto_awesome_rounded,
                    color: _rose,
                    size: 20,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      english ? 'Reading summary' : '読み解きの要約',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  _namePill(
                    _relationshipPersonDisplayName(result.first, english),
                    _rose,
                  ),
                  const Icon(Icons.favorite_rounded, color: _rose, size: 18),
                  _namePill(
                    _relationshipPersonDisplayName(result.second, english),
                    _lilac,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                _relationshipSummary(result, english),
                style: const TextStyle(height: 1.8, fontSize: 14),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const ValueKey('relationship-open-share'),
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  constraints: const BoxConstraints(maxWidth: 720),
                  builder: (context) => RelationshipShareComposerSheet(
                    summary: _relationshipSummary(result, english),
                    firstName: result.first.nameWasOmitted
                        ? ''
                        : result.first.name,
                    secondName: result.second.nameWasOmitted
                        ? ''
                        : result.second.name,
                    sections: [
                      for (final category in result.categories)
                        RelationshipShareSection(
                          title: _relationshipCategoryTitle(category, english),
                          body: _relationshipNarrative(category.text, english),
                          hint: _relationshipNarrative(category.hint, english),
                        ),
                    ],
                  ),
                ),
                icon: const Icon(Icons.ios_share),
                label: Text(english ? 'Create a share card' : '相性の共有カードを作る'),
              ),
              if (result.moonExcluded)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    english
                        ? 'Because at least one birth time is unknown, Moon placements are excluded for both people.'
                        : '出生時刻が不明な人がいるため、月の配置は二人とも含めていません。',
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 12,
                      height: 1.6,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        for (var index = 0; index < result.categories.length; index++)
          _RelationshipReveal(
            order: index + 1,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _categoryView(context, result.categories[index], result),
            ),
          ),
        _surface(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                (english ? 'Calculation source: ' : '計算元: ') +
                    _relationshipProviderName(result.ephemerisName, english),
                style: const TextStyle(fontSize: 12, color: _muted),
              ),
              const SizedBox(height: 4),
              Text(
                result.highPrecision
                    ? (english
                          ? 'High-precision astronomical data is in use.'
                          : '高精度の天文データを利用しています。')
                    : (english
                          ? 'This is a reference reading from simplified calculations; it has not been checked against high-precision data.'
                          : '簡易計算による参考表示です。高精度データによる確認ではありません。'),
                style: const TextStyle(
                  fontSize: 12,
                  color: _muted,
                  height: 1.6,
                ),
              ),
              if (!result.highPrecision &&
                  result.precisionNotice.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _relationshipPrecisionNotice(
                      result.precisionNotice,
                      english,
                    ),
                    style: const TextStyle(fontSize: 12, color: _muted),
                  ),
                ),
              const SizedBox(height: 10),
              Text(
                english
                    ? 'This uses traditional astrological symbolism. It does not determine anyone’s personality or the outcome of a relationship. Base important decisions on direct conversation and real circumstances.'
                    : '占星術の伝統的な象徴解釈であり、相手の性格や関係の結果を確定するものではありません。大切な判断は本人同士の対話や現実の状況をもとにしてください。',
                style: const TextStyle(
                  fontSize: 12,
                  color: _muted,
                  height: 1.7,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _namePill(String name, Color color) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Text(
        name,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
        softWrap: true,
      ),
    );
  }

  Widget _categoryView(
    BuildContext context,
    RelationshipCategoryReading category,
    _RelationshipResult result,
  ) {
    final english = _relationshipEnglish(context);
    final (icon, accent) = switch (category.key) {
      'familiarity' => (Icons.favorite_border_rounded, _rose),
      'conversation' => (Icons.forum_outlined, _lilac),
      _ => (Icons.balance_rounded, const Color(0xFF876B50)),
    };
    final caption = _relationshipCategoryCaption(category.key, english);
    return _surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      caption,
                      style: TextStyle(fontSize: 11, color: accent),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _relationshipCategoryTitle(category, english),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _relationshipNarrative(category.text, english),
            style: const TextStyle(fontSize: 14, height: 1.8),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.045),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  english
                      ? (category.hasEvidence
                            ? 'Conversation prompt'
                            : 'Something to explore together')
                      : (category.hasEvidence ? '話し合いのヒント' : 'ふたりで確かめたいこと'),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: accent,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _relationshipNarrative(category.hint, english),
                  style: const TextStyle(fontSize: 13, height: 1.75),
                ),
              ],
            ),
          ),
          if (category.hasEvidence)
            ExpansionTile(
              key: ValueKey('relationship-evidence-' + category.key),
              tilePadding: EdgeInsets.zero,
              title: Text(
                english ? 'Show placement details' : '配置の根拠を表示',
                style: const TextStyle(fontSize: 12, color: _muted),
              ),
              children: category.evidence.map((aspect) {
                final firstName = _relationshipPersonDisplayName(
                  result.first,
                  english,
                );
                final secondName = _relationshipPersonDisplayName(
                  result.second,
                  english,
                );
                final pair = english
                    ? "$firstName's ${_relationshipPlanetLabel(aspect.natalPlanet, true)} × $secondName's ${_relationshipPlanetLabel(aspect.transitPlanet, true)}"
                    : '$firstNameの${aspect.natalPlanet.label} × $secondNameの${aspect.transitPlanet.label}';
                final aspectName = _relationshipAspectLabel(
                  aspect.type,
                  english,
                );
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    pair + ' — ' + aspectName,
                    style: const TextStyle(fontSize: 13, height: 1.5),
                  ),
                  subtitle: Text(
                    (english ? 'Orb difference ' : '角度差 ') +
                        aspect.orb.toStringAsFixed(1) +
                        '°',
                    style: const TextStyle(fontSize: 12, color: _muted),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}

class _RelationshipStep extends StatelessWidget {
  const _RelationshipStep({
    required this.number,
    required this.title,
    required this.active,
  });
  final String number;
  final String title;
  final bool active;
  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFFA7476A) : const Color(0xFF74657B);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          decoration: BoxDecoration(
            color: active ? const Color(0xFFF3E2EA) : const Color(0xFFF0EBF2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            number,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

/// A finite entrance: no repeating ticker, and no animated stale result on edit.
class _RelationshipReveal extends StatefulWidget {
  const _RelationshipReveal({
    super.key,
    required this.child,
    this.order = 0,
    this.scrollIntoView = false,
  });
  final Widget child;
  final int order;
  final bool scrollIntoView;
  @override
  State<_RelationshipReveal> createState() => _RelationshipRevealState();
}

class _RelationshipRevealState extends State<_RelationshipReveal> {
  @override
  void initState() {
    super.initState();
    if (widget.scrollIntoView) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final media = MediaQuery.of(context);
        Scrollable.ensureVisible(
          context,
          alignment: 0.04,
          duration: media.disableAnimations || media.accessibleNavigation
              ? Duration.zero
              : const Duration(milliseconds: 380),
          curve: Curves.easeOutCubic,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    if (media.disableAnimations || media.accessibleNavigation)
      return widget.child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Interval(
        math.min(widget.order * 0.1, 0.4),
        1,
        curve: Curves.easeOutCubic,
      ),
      child: widget.child,
      builder: (context, progress, child) => Opacity(
        opacity: progress.clamp(0, 1),
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - progress)),
          child: child,
        ),
      ),
    );
  }
}

class _RelationshipOrbit extends StatelessWidget {
  const _RelationshipOrbit({required this.size});
  final double size;
  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final still = media.disableAnimations || media.accessibleNavigation;
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: still ? 1 : 0, end: 1),
          duration: still ? Duration.zero : const Duration(milliseconds: 1100),
          curve: Curves.easeOutCubic,
          builder: (context, value, _) => SizedBox.square(
            dimension: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: Size.square(size),
                  painter: _RelationshipOrbitPainter(value),
                ),
                Transform.scale(
                  scale: 0.9 + value * 0.1,
                  child: const Icon(
                    Icons.favorite_rounded,
                    color: Color(0xFFA7476A),
                    size: 32,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RelationshipOrbitPainter extends CustomPainter {
  const _RelationshipOrbitPainter(this.progress);
  final double progress;
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25;
    final radius = size.width * 0.34;
    for (var i = 0; i < 2; i++) {
      paint.color = (i == 0 ? const Color(0xFFA7476A) : const Color(0xFF75639D))
          .withValues(alpha: 0.36);
      final shift = Offset((i == 0 ? -1 : 1) * size.width * 0.13, 0);
      canvas.drawArc(
        Rect.fromCircle(center: center + shift, radius: radius),
        -math.pi / 2,
        math.pi * 2 * progress,
        false,
        paint,
      );
      final angle = (i == 0 ? -0.5 : 2.6) + (1 - progress) * 0.5;
      final dot =
          center + shift + Offset(math.cos(angle), math.sin(angle)) * radius;
      canvas.drawCircle(
        dot,
        5,
        Paint()
          ..color = i == 0 ? const Color(0xFFC47792) : const Color(0xFF9984BC),
      );
    }
    paint.color = const Color(0xFFB59873).withValues(alpha: 0.5);
    for (final point in [
      Offset(size.width * 0.5, 12),
      Offset(size.width - 8, size.height * 0.73),
      Offset(12, size.height * 0.83),
    ]) {
      final d = 4.0 * progress;
      canvas.drawLine(point - Offset(d, 0), point + Offset(d, 0), paint);
      canvas.drawLine(point - Offset(0, d), point + Offset(0, d), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RelationshipOrbitPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
