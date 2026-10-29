part of 'main.dart';

/// Calendar display only. Never writes profiles, forecasts or global text scale.
class AstrologyCalendarTextSettings {
  AstrologyCalendarTextSettings._();
  static const storageKey = 'astrology.calendar_text_size';
  static const defaultSize = 17.0;
  static const sizes = <double>[15, 17, 19];

  static Future<double> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.get(storageKey);
      if (value is num && sizes.contains(value.toDouble())) {
        return value.toDouble();
      }
    } catch (_) {
      // A failed read does not rewrite any existing preference.
    }
    return defaultSize;
  }

  static Future<void> save(double size) async {
    if (!sizes.contains(size)) throw ArgumentError.value(size, 'size');
    final prefs = await SharedPreferences.getInstance();
    await BackupRestoreTransaction.replace(
      prefs: prefs,
      values: {storageKey: size},
    );
  }
}

bool _astrologyCalendarEnglish(BuildContext context) =>
    AppLanguageScope.stringsOf(context).language == AppLanguage.en;

String _astrologyCalendarCopy(
  BuildContext context,
  String japanese,
  String english,
) => _astrologyCalendarEnglish(context) ? english : japanese;

String _astrologyCalendarMonthLabel(int year, int month, bool english) {
  if (!english) return '${year}年${month}月';
  const months = [
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
  ];
  return '${months[month - 1]} $year';
}

String _astrologyCalendarDateLabel(
  int year,
  int month,
  int day,
  bool english,
) => english
    ? '${_astrologyCalendarMonthLabel(year, month, true).split(' ').first} $day, $year (JST)'
    : '${year}年${month}月${day}日（JST）';

String _astrologyCalendarProviderLabel(String value, bool english) {
  if (!english) return value;
  return switch (value) {
    'アプリ内簡易計算' => 'In-app simplified calculation',
    'アプリ内簡易計算（Swiss配置フォールバック）' =>
      'In-app simplified calculation (Swiss placement fallback)',
    _ => value,
  };
}

String _astrologyCalendarCellTime(DateTime utc) {
  final jst = utc.toUtc().add(DailySevenTimepointPlan.jstOffset);
  return '${jst.hour.toString().padLeft(2, '0')}:'
      '${jst.minute.toString().padLeft(2, '0')}';
}

String _astrologyCalendarShortPlanet(String label, bool english) {
  if (english) {
    return switch (label) {
      '太陽' => 'Su',
      '月' => 'Mo',
      '水星' => 'Me',
      '金星' => 'Ve',
      '火星' => 'Ma',
      '木星' => 'Ju',
      '土星' => 'Sa',
      '天王星' => 'Ur',
      '海王星' => 'Ne',
      '冥王星' => 'Pl',
      _ => label,
    };
  }
  return switch (label) {
    '太陽' => '太',
    '月' => '月',
    '水星' => '水',
    '金星' => '金',
    '火星' => '火',
    '木星' => '木',
    '土星' => '土',
    '天王星' => '天',
    '海王星' => '海',
    '冥王星' => '冥',
    _ => label,
  };
}

String _astrologyCalendarShortSign(String label, bool english) {
  if (english) {
    return switch (label) {
      '牡羊座' => 'Ari',
      '牡牛座' => 'Tau',
      '双子座' => 'Gem',
      '蟹座' => 'Can',
      '獅子座' => 'Leo',
      '乙女座' => 'Vir',
      '天秤座' => 'Lib',
      '蠍座' => 'Sco',
      '射手座' => 'Sag',
      '山羊座' => 'Cap',
      '水瓶座' => 'Aqu',
      '魚座' => 'Pis',
      _ => label,
    };
  }
  return switch (label) {
    '牡羊座' => '牡羊',
    '牡牛座' => '牡牛',
    '双子座' => '双子',
    '蟹座' => '蟹',
    '獅子座' => '獅子',
    '乙女座' => '乙女',
    '天秤座' => '天秤',
    '蠍座' => '蠍',
    '射手座' => '射手',
    '山羊座' => '山羊',
    '水瓶座' => '水瓶',
    '魚座' => '魚',
    _ => label,
  };
}

String _astrologyCalendarCellEventSummary(
  AstrologyCalendarEvent event, {
  required bool english,
  required bool includeTime,
}) {
  final time = event.startUtc == null
      ? null
      : _astrologyCalendarCellTime(event.startUtc!);
  switch (event.kind) {
    case AstrologyCalendarEventKind.signIngress:
      final match = RegExp(r'^(.+?)が(.+?)へ移動$').firstMatch(event.title);
      if (match == null) return english ? 'Ingress' : '移動';
      final planet = _astrologyCalendarShortPlanet(match.group(1)!, english);
      final sign = _astrologyCalendarShortSign(match.group(2)!, english);
      return '$planet→$sign${includeTime && time != null ? time : ''}';
    case AstrologyCalendarEventKind.retrogradeStation:
      final match = RegExp(r'^(.+?)が逆行(開始|終了)（留）$').firstMatch(event.title);
      if (match == null) return english ? 'Station' : '留';
      final planet = _astrologyCalendarShortPlanet(match.group(1)!, english);
      final direction = match.group(2) == '開始' ? 'R' : 'D';
      return '$planet$direction${includeTime && time != null ? time : ''}';
    case AstrologyCalendarEventKind.voidMoon:
      final end = event.endUtc == null
          ? null
          : _astrologyCalendarCellTime(event.endUtc!);
      final duration = event.startUtc == null || event.endUtc == null
          ? null
          : _astrologyCalendarDuration(
              event.endUtc!.difference(event.startUtc!),
              english: english,
            );
      if (english) {
        if (event.continuesFromPreviousDay && event.continuesIntoNextDay) {
          return 'V cont.${includeTime && duration != null ? ' $duration' : ''}';
        }
        if (event.continuesFromPreviousDay) {
          return 'V end${includeTime && end != null ? ' $end' : ''}';
        }
        if (event.continuesIntoNextDay) {
          return 'V start${includeTime && time != null ? ' $time' : ''}';
        }
        return 'V${includeTime && time != null && end != null ? ' $time-$end' : ''}';
      }
      if (event.continuesFromPreviousDay && event.continuesIntoNextDay) {
        return '月V継${includeTime && duration != null ? duration : ''}';
      }
      if (event.continuesFromPreviousDay) {
        return 'V終${includeTime && end != null ? end : ''}';
      }
      if (event.continuesIntoNextDay) {
        return 'V始${includeTime && time != null ? time : ''}';
      }
      return '月V${includeTime && time != null && end != null ? '$time-$end' : ''}';
    case AstrologyCalendarEventKind.majorLunarPhase:
      final phase = switch (event.title) {
        '新月' => english ? 'NM' : '新月',
        '上弦の月' => english ? 'FQ' : '上弦',
        '満月' => english ? 'FM' : '満月',
        '下弦の月' => english ? 'LQ' : '下弦',
        _ => english ? 'Phase' : '相',
      };
      return '$phase${includeTime && time != null ? time : ''}';
    case AstrologyCalendarEventKind.specialConfiguration:
      return english ? '✦ Pattern' : '✦配置';
  }
}

String _astrologyCalendarDuration(Duration duration, {required bool english}) {
  final totalMinutes = duration.inMinutes;
  final days = totalMinutes ~/ (24 * Duration.minutesPerHour);
  final hours = (totalMinutes ~/ Duration.minutesPerHour) % 24;
  final minutes = totalMinutes % Duration.minutesPerHour;
  if (english) {
    return [
      if (days > 0) '${days}d',
      if (hours > 0) '${hours}h',
      if (minutes > 0 || (days == 0 && hours == 0)) '${minutes}m',
    ].join(' ');
  }
  return [
    if (days > 0) '${days}日',
    if (hours > 0) '${hours}時間',
    if (minutes > 0 || (days == 0 && hours == 0)) '${minutes}分',
  ].join();
}

String _astrologyCalendarPrecisionLabel(String value, bool english) {
  if (!english) return value;
  return switch (value) {
    'Swiss Ephemeris未読込のため、星座境界付近、月、ハウス、ボイドは目安です。Android版では高精度アストロデータを優先して使います。' =>
      'Swiss Ephemeris is not loaded, so sign boundaries, the Moon, houses, and void-of-course periods are approximate. The Android version prioritizes high-precision astronomical data when available.',
    'Swiss Ephemeris Free Edition/AGPLをAndroidネイティブで使用しています。アプリ同梱のMoshier計算で星の位置を算出し、月ボイド開始は5分探索後に最後の主要アスペクトの正確時刻へ絞り込みます。' =>
      'Swiss Ephemeris Free Edition/AGPL is used natively on Android. Planet positions use the bundled Moshier calculations; void-of-course Moon start times are refined after a five-minute search to the last major aspect time.',
    _ => value,
  };
}

String _astrologyCalendarPlanetLabel(AstroPlanet planet) => switch (planet) {
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

String _astrologyCalendarZodiacLabel(ZodiacSign sign) => switch (sign) {
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

String _astrologyCalendarPlanetFromLabel(String label) {
  for (final planet in AstroPlanet.values) {
    if (planet.label == label) return _astrologyCalendarPlanetLabel(planet);
  }
  return label;
}

String _astrologyCalendarZodiacFromLabel(String label) {
  for (final sign in ZodiacSign.values) {
    if (sign.label == label) return _astrologyCalendarZodiacLabel(sign);
  }
  return label;
}

String _astrologyCalendarEventTitle(
  AstrologyCalendarEvent event,
  bool english,
) {
  if (!english) return event.title;
  if (event.kind == AstrologyCalendarEventKind.voidMoon) {
    return 'Void-of-course Moon';
  }
  if (event.kind == AstrologyCalendarEventKind.majorLunarPhase) {
    return switch (event.title) {
      '新月' => 'New Moon',
      '上弦の月' => 'First Quarter',
      '満月' => 'Full Moon',
      '下弦の月' => 'Last Quarter',
      _ => event.title,
    };
  }
  if (event.kind == AstrologyCalendarEventKind.signIngress) {
    final match = RegExp(r'^(.+?)が(.+?)へ移動$').firstMatch(event.title);
    if (match == null) return event.title;
    final planet = _astrologyCalendarPlanetFromLabel(match.group(1)!);
    final sign = _astrologyCalendarZodiacFromLabel(match.group(2)!);
    if (planet == match.group(1) || sign == match.group(2)) return event.title;
    return '$planet enters $sign';
  }
  if (event.kind == AstrologyCalendarEventKind.retrogradeStation) {
    final match = RegExp(r'^(.+?)が逆行(開始|終了)（留）$').firstMatch(event.title);
    if (match == null) return event.title;
    final planet = _astrologyCalendarPlanetFromLabel(match.group(1)!);
    if (planet == match.group(1)) return event.title;
    return match.group(2) == '開始'
        ? '$planet stations retrograde'
        : '$planet turns direct';
  }
  if (event.kind == AstrologyCalendarEventKind.specialConfiguration) {
    const patternNames = <String, String>{
      'グランドトライン': 'Grand trine',
      'Tスクエア': 'T-square',
      'グランドクロス': 'Grand cross',
      'ヨッド': 'Yod',
      'ブーメラン（ヨッド）': 'Boomerang Yod',
      'ミスティックレクタングル（ダイヤモンド）': 'Mystic rectangle (diamond)',
      'クレイドル（ゆりかご）': 'Cradle',
      'ハンマー・オブ・ソー': "Thor's hammer",
      'グランドセクスタイル': 'Grand sextile',
    };
    String? patternName;
    String? planetText;
    for (final entry in patternNames.entries) {
      final marker = '${entry.key}（';
      if (event.title.startsWith(marker) && event.title.endsWith('）')) {
        patternName = entry.value;
        planetText = event.title.substring(
          marker.length,
          event.title.length - 1,
        );
        break;
      }
    }
    if (patternName == null || planetText == null) return event.title;
    final sourcePlanets = planetText.split('・');
    if (sourcePlanets.any(
      (label) => AstroPlanet.values.every((planet) => planet.label != label),
    )) {
      return event.title;
    }
    final planets = sourcePlanets.map(_astrologyCalendarPlanetFromLabel);
    return '$patternName (${planets.join(', ')})';
  }
  return event.title;
}

String _astrologyCalendarEventDetail(
  AstrologyCalendarEvent event,
  bool english,
) {
  if (!english) return event.detail;
  return switch (event.kind) {
    AstrologyCalendarEventKind.signIngress =>
      event.detail == '星座の移動' ? 'Sign ingress' : event.detail,
    AstrologyCalendarEventKind.retrogradeStation => switch (event.detail) {
      '連絡・契約・文章は仕上げと最終確認を優先' =>
        'Prioritize final checks for messages, agreements, and writing.',
      '切替直後は急いで結論を出さず、方針を見直す' =>
        'After the shift, review your approach before drawing a quick conclusion.',
      _ => event.detail,
    },
    AstrologyCalendarEventKind.majorLunarPhase =>
      event.detail == '太陽と月の黄経差を30分ごとに探索し、分単位で絞り込んだ時刻'
          ? 'Estimated by scanning the Sun–Moon longitude every 30 minutes, then refining to a minute-level time.'
          : event.detail,
    AstrologyCalendarEventKind.voidMoon =>
      event.detail == 'この日のボイド区間（5分以下）'
          ? 'A short void-of-course interval on this date (five minutes or less)'
          : event.detail == '月が次の星座へ入る前の空白時間。新規決定より見直し、休息、準備向き。'
          ? 'The interval before the Moon enters the next sign; suited to review, rest, and preparation rather than new decisions.'
          : event.detail,
    AstrologyCalendarEventKind.specialConfiguration =>
      event.detail == '正午の星配置'
          ? 'Planetary positions at 12:00 JST'
          : event.detail,
  };
}

/// A civil-date calendar for sky events. The date sent to [onDateSelected] is
/// the exact noon-JST instant (03:00 UTC); consumers should preserve its UTC
/// year/month/day fields rather than converting it to the host time zone.
class AstrologyCalendarView extends StatefulWidget {
  const AstrologyCalendarView({
    super.key,
    this.initialDate,
    this.initialShowAgenda = false,
    this.onDateSelected,
    this.startJob,
    this.nowUtc,
    this.cacheIdentity,
  });

  /// Date fields are interpreted as a Gregorian civil date, not as an instant.
  final DateTime? initialDate;

  /// Open on the calendar grid. The complete event list remains available
  /// through its view selector, or explicitly through this optional input.
  final bool initialShowAgenda;
  final ValueChanged<DateTime>? onDateSelected;
  final AstrologyCalendarStarter? startJob;
  final DateTime Function()? nowUtc;

  /// Tests and future provider configurations can isolate their read-only cache.
  final String? cacheIdentity;

  @override
  State<AstrologyCalendarView> createState() => _AstrologyCalendarViewState();
}

enum AstrologyCalendarEventKind {
  signIngress,
  retrogradeStation,
  majorLunarPhase,
  voidMoon,
  specialConfiguration,
}

// DailyAstroEventsCard._stationEvents only reads its provider argument. Keep
// the existing station search as the single source of event calculations;
// this inert context satisfies the existing card constructor without reading
// a user profile or contributing any chart, score, or preference data.
HoroscopeReadingContext _astrologyCalendarStationContext(DateTime date) =>
    HoroscopeReadingContext(
      natal: const NatalChart(
        profile: AstroProfile(
          name: '',
          birthDate: '',
          birthTime: '',
          birthPlace: '',
          theme: '',
        ),
        placements: [],
        stelliums: [],
        retrogradePlanets: {},
      ),
      transit: TransitChart(date: date, placements: [], voidMoon: null),
      nextTransitPlacements: const [],
      aspects: const [],
      fullAspects: const [],
      nextAspects: const [],
      transitPairAspects: const [],
      retrogradePlanets: const {},
      houseTransits: const [],
      returns: const [],
      birthPlace: const GeoPoint(label: '', latitude: 0, longitude: 0),
      ephemerisSourceName: '',
      ephemerisPrecisionNotice: '',
      usesHighPrecisionAstroData: false,
      houseSystem: HouseSystem.placidus,
      houseCusps: const [],
    );

AstrologyCalendarEvent _astrologyCalendarStationEvent(
  String description,
  DailySevenTimepointPlan plan,
) {
  final match = RegExp(
    r'^(\d{2}):(\d{2})頃　(.+?)逆行(開始|終了)（留）：(.+)$',
  ).firstMatch(description);
  if (match == null) {
    throw const FormatException('既存の留イベント形式を読み取れません。');
  }
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  if (hour > 23 || minute > 59) {
    throw const FormatException('既存の留イベント時刻が不正です。');
  }
  final planetLabel = match.group(3)!;
  if (!AstroPlanet.values.any((planet) => planet.label == planetLabel)) {
    throw const FormatException('既存の留イベント天体を読み取れません。');
  }
  final transition = match.group(4)!;
  // The existing daily-events card formats this clock time in JST. The plan
  // starts at JST midnight already represented as a UTC instant, so add the
  // JST clock directly to that UTC boundary.
  final eventUtc = plan.dayStartUtc.add(Duration(hours: hour, minutes: minute));
  if (eventUtc.isBefore(plan.dayStartUtc) ||
      !eventUtc.isBefore(plan.dayEndUtc)) {
    throw StateError('既存の留イベントが対象JST日と一致しません。');
  }
  return AstrologyCalendarEvent(
    kind: AstrologyCalendarEventKind.retrogradeStation,
    title: '${planetLabel}が逆行$transition（留）',
    detail: match.group(5)!,
    startUtc: eventUtc,
  );
}

typedef _AstrologyCalendarVoidInterval = ({DateTime startUtc, DateTime endUtc});

class AstrologyCalendarEvent {
  const AstrologyCalendarEvent({
    required this.kind,
    required this.title,
    required this.detail,
    this.startUtc,
    this.endUtc,
    this.snapshotUtc,
    this.overlapStartUtc,
    this.overlapEndUtc,
    this.ingressPlanet,
    this.fromSign,
    this.toSign,
    this.continuesFromPreviousDay = false,
    this.continuesIntoNextDay = false,
  });

  final AstrologyCalendarEventKind kind;
  final String title;
  final String detail;
  final DateTime? startUtc;
  final DateTime? endUtc;
  final DateTime? snapshotUtc;
  final DateTime? overlapStartUtc;
  final DateTime? overlapEndUtc;
  final AstroPlanet? ingressPlanet;
  final ZodiacSign? fromSign;
  final ZodiacSign? toSign;
  final bool continuesFromPreviousDay;
  final bool continuesIntoNextDay;

  /// Validates the raw interval against the existing UTC-day API's clipped
  /// result. Null means it does not overlap the requested half-open day.
  static AstrologyCalendarEvent? voidMoonForDay({
    required DailySevenTimepointPlan plan,
    required DateTime actualStartUtc,
    required DateTime actualEndUtc,
    required VoidMoonPeriod? dayApiResult,
  }) {
    final actualStart = actualStartUtc.toUtc();
    final actualEnd = actualEndUtc.toUtc();
    if (!actualEnd.isAfter(actualStart)) {
      throw ArgumentError('Void interval end must follow start.');
    }
    final overlapStart = actualStart.isAfter(plan.dayStartUtc)
        ? actualStart
        : plan.dayStartUtc;
    final overlapEnd = actualEnd.isBefore(plan.dayEndUtc)
        ? actualEnd
        : plan.dayEndUtc;
    if (!overlapEnd.isAfter(overlapStart) ||
        overlapEnd.difference(overlapStart) <= const Duration(minutes: 5)) {
      if (dayApiResult != null) {
        throw StateError('JST日単位APIの区間が対象日と食い違います。');
      }
      return null;
    }
    final clipped = dayApiResult;
    if (clipped == null ||
        clipped.startTime.toUtc() != overlapStart ||
        clipped.endTime.toUtc() != overlapEnd ||
        !clipped.contains(overlapStart) ||
        clipped.contains(overlapEnd)) {
      throw StateError('月ボイド実区間とJST日単位APIの区間が一致しません。');
    }
    final expectedShare =
        overlapEnd.difference(overlapStart).inSeconds /
        const Duration(days: 1).inSeconds;
    final actualShare = clipped.dayShare(
      plan.primaryNoon.instantUtc,
      dayStartUtc: plan.dayStartUtc,
    );
    if ((actualShare - expectedShare).abs() > 1e-9) {
      throw StateError('月ボイドの対象日内割合を検算できません。');
    }
    return AstrologyCalendarEvent(
      kind: AstrologyCalendarEventKind.voidMoon,
      title: '月ボイド',
      detail: clipped.guidance,
      startUtc: actualStart,
      endUtc: actualEnd,
      overlapStartUtc: overlapStart,
      overlapEndUtc: overlapEnd,
      continuesFromPreviousDay: actualStart.isBefore(plan.dayStartUtc),
      continuesIntoNextDay: actualEnd.isAfter(plan.dayEndUtc),
    );
  }

  /// Verifies the first interval against the existing day API and retains any
  /// later, nonoverlapping raw intervals that API intentionally does not list.
  static List<AstrologyCalendarEvent> voidMoonIntervalsForDay({
    required DailySevenTimepointPlan plan,
    required List<_AstrologyCalendarVoidInterval> rawIntervals,
    required VoidMoonPeriod? dayApiResult,
  }) {
    if (rawIntervals.isEmpty) {
      if (dayApiResult != null) {
        throw StateError('JST日単位APIと実区間の取得結果が一致しません。');
      }
      return const [];
    }

    final events = <AstrologyCalendarEvent>[];
    DateTime? previousEnd;
    for (var index = 0; index < rawIntervals.length; index++) {
      final raw = rawIntervals[index];
      final start = raw.startUtc.toUtc();
      final end = raw.endUtc.toUtc();
      if (!end.isAfter(start) ||
          (previousEnd != null && start.isBefore(previousEnd))) {
        throw StateError('月ボイドの実区間の時刻順を確認できません。');
      }
      previousEnd = end;

      final event = index == 0
          ? voidMoonForDay(
              plan: plan,
              actualStartUtc: start,
              actualEndUtc: end,
              dayApiResult: dayApiResult,
            )
          : _voidMoonEventFromRawInterval(
              plan: plan,
              actualStartUtc: start,
              actualEndUtc: end,
              detail: dayApiResult?.guidance ?? '月ボイド',
            );
      if (event == null) {
        throw StateError('対象日内の月ボイド区間を確定できません。');
      }
      events.add(event);
    }
    return List.unmodifiable(events);
  }

  /// Calendar-only retention of positive overlaps of five minutes or less.
  /// The existing day API intentionally excludes these overlaps. Its first
  /// longer interval is still checked by [voidMoonIntervalsForDay]; neither
  /// that API nor the scoring interpretation is changed here.
  static List<AstrologyCalendarEvent> voidMoonIntervalsForCalendarDisplay({
    required DailySevenTimepointPlan plan,
    required List<_AstrologyCalendarVoidInterval> rawIntervals,
    required VoidMoonPeriod? dayApiResult,
  }) {
    final longer = <_AstrologyCalendarVoidInterval>[];
    final shorter = <AstrologyCalendarEvent>[];
    DateTime? previousEnd;
    for (final raw in rawIntervals) {
      final start = raw.startUtc.toUtc();
      final end = raw.endUtc.toUtc();
      if (!end.isAfter(start) ||
          (previousEnd != null && start.isBefore(previousEnd))) {
        throw StateError('月ボイドの実区間の時刻順を確認できません。');
      }
      previousEnd = end;
      final overlapStart = start.isAfter(plan.dayStartUtc) ? start : plan.dayStartUtc;
      final overlapEnd = end.isBefore(plan.dayEndUtc) ? end : plan.dayEndUtc;
      if (!overlapEnd.isAfter(overlapStart)) continue;
      if (overlapEnd.difference(overlapStart) > const Duration(minutes: 5)) {
        longer.add(raw);
      } else {
        shorter.add(_voidMoonEventFromRawInterval(
          plan: plan,
          actualStartUtc: start,
          actualEndUtc: end,
          detail: 'この日のボイド区間（5分以下）',
          includeShortOverlap: true,
        )!);
      }
    }
    final events = <AstrologyCalendarEvent>[
      ...voidMoonIntervalsForDay(plan: plan, rawIntervals: longer, dayApiResult: dayApiResult),
      ...shorter,
    ]..sort((first, second) => first.sortTimeUtc.compareTo(second.sortTimeUtc));
    return List.unmodifiable(events);
  }

  static AstrologyCalendarEvent? _voidMoonEventFromRawInterval({
    required DailySevenTimepointPlan plan,
    required DateTime actualStartUtc,
    required DateTime actualEndUtc,
    required String detail,
    bool includeShortOverlap = false,
  }) {
    final actualStart = actualStartUtc.toUtc();
    final actualEnd = actualEndUtc.toUtc();
    if (!actualEnd.isAfter(actualStart)) {
      throw ArgumentError('Void interval end must follow start.');
    }
    final overlapStart = actualStart.isAfter(plan.dayStartUtc)
        ? actualStart
        : plan.dayStartUtc;
    final overlapEnd = actualEnd.isBefore(plan.dayEndUtc)
        ? actualEnd
        : plan.dayEndUtc;
    if (!overlapEnd.isAfter(overlapStart) ||
        (!includeShortOverlap &&
            overlapEnd.difference(overlapStart) <= const Duration(minutes: 5))) {
      return null;
    }
    return AstrologyCalendarEvent(
      kind: AstrologyCalendarEventKind.voidMoon,
      title: '月ボイド',
      detail: detail,
      startUtc: actualStart,
      endUtc: actualEnd,
      overlapStartUtc: overlapStart,
      overlapEndUtc: overlapEnd,
      continuesFromPreviousDay: actualStart.isBefore(plan.dayStartUtc),
      continuesIntoNextDay: actualEnd.isAfter(plan.dayEndUtc),
    );
  }

  DateTime get sortTimeUtc =>
      startUtc ?? snapshotUtc ?? DateTime.utc(9999, 12, 31);

  Map<String, Object?> toMessage() => {
    'kind': kind.name,
    'title': title,
    'detail': detail,
    'start_utc': startUtc?.toUtc().toIso8601String(),
    'end_utc': endUtc?.toUtc().toIso8601String(),
    'snapshot_utc': snapshotUtc?.toUtc().toIso8601String(),
    'overlap_start_utc': overlapStartUtc?.toUtc().toIso8601String(),
    'overlap_end_utc': overlapEndUtc?.toUtc().toIso8601String(),
    'ingress_planet': ingressPlanet?.name,
    'from_sign': fromSign?.name,
    'to_sign': toSign?.name,
    'continues_from_previous_day': continuesFromPreviousDay,
    'continues_into_next_day': continuesIntoNextDay,
  };

  factory AstrologyCalendarEvent.fromMessage(Map<Object?, Object?> value) {
    final kindName = value['kind'];
    final kind = AstrologyCalendarEventKind.values.firstWhere(
      (candidate) => candidate.name == kindName,
      orElse: () => throw FormatException('Unknown calendar event kind.'),
    );
    DateTime? parseTime(Object? raw) =>
        raw is String ? DateTime.parse(raw).toUtc() : null;
    return AstrologyCalendarEvent(
      kind: kind,
      title: value['title'] as String? ?? '',
      detail: value['detail'] as String? ?? '',
      startUtc: parseTime(value['start_utc']),
      endUtc: parseTime(value['end_utc']),
      snapshotUtc: parseTime(value['snapshot_utc']),
      overlapStartUtc: parseTime(value['overlap_start_utc']),
      overlapEndUtc: parseTime(value['overlap_end_utc']),
      ingressPlanet: _astrologyCalendarOptionalEnum(value['ingress_planet'], AstroPlanet.values),
      fromSign: _astrologyCalendarOptionalEnum(value['from_sign'], ZodiacSign.values),
      toSign: _astrologyCalendarOptionalEnum(value['to_sign'], ZodiacSign.values),
      continuesFromPreviousDay: value['continues_from_previous_day'] == true,
      continuesIntoNextDay: value['continues_into_next_day'] == true,
    );
  }
}

T? _astrologyCalendarOptionalEnum<T extends Enum>(Object? raw, List<T> values) {
  if (raw == null) return null;
  for (final value in values) {
    if (value.name == raw) return value;
  }
  throw FormatException('Unknown calendar metadata value: $raw');
}

class AstrologyCalendarDay {
  AstrologyCalendarDay({
    required this.targetDateJst,
    required Iterable<AstrologyCalendarEvent> events,
    required this.providerName,
    required this.precisionNotice,
    required this.usesHighPrecisionAstroData,
    this.moonSignAtNoon,
  }) : events = List.unmodifiable(events);

  final String targetDateJst;
  final List<AstrologyCalendarEvent> events;
  final String providerName;
  final String precisionNotice;
  final bool usesHighPrecisionAstroData;
  final ZodiacSign? moonSignAtNoon;

  Map<String, Object?> toMessage() => {
    'target_date_jst': targetDateJst,
    'provider_name': providerName,
    'precision_notice': precisionNotice,
    'uses_high_precision_astro_data': usesHighPrecisionAstroData,
    'moon_sign_at_noon': moonSignAtNoon?.name,
    'events': [for (final event in events) event.toMessage()],
  };

  factory AstrologyCalendarDay.fromMessage(Map<Object?, Object?> value) {
    final rawEvents = value['events'];
    if (rawEvents is! List)
      throw const FormatException('Calendar events are missing.');
    return AstrologyCalendarDay(
      targetDateJst: value['target_date_jst'] as String? ?? '',
      providerName: value['provider_name'] as String? ?? '',
      precisionNotice: value['precision_notice'] as String? ?? '',
      usesHighPrecisionAstroData:
          value['uses_high_precision_astro_data'] == true,
      moonSignAtNoon: _astrologyCalendarOptionalEnum(value['moon_sign_at_noon'], ZodiacSign.values),
      events: [
        for (final raw in rawEvents)
          if (raw is Map<Object?, Object?>)
            AstrologyCalendarEvent.fromMessage(raw)
          else
            throw const FormatException('Calendar event is malformed.'),
      ],
    );
  }
}

abstract interface class AstrologyCalendarOperation {
  Future<AstrologyCalendarDay> get result;
  void cancel();
}

typedef AstrologyCalendarStarter =
    AstrologyCalendarOperation Function(
      String targetDateJst,
      void Function(int completed, int total) onProgress,
    );

class _AstrologyCalendarViewState extends State<AstrologyCalendarView> {
  static const int _cacheCapacity = 45;
  static const int _calendarMinimumYear = 1900;
  static const int _calendarMaximumYear = 2100;
  static const List<String> _japaneseWeekdays = [
    '月',
    '火',
    '水',
    '木',
    '金',
    '土',
    '日',
  ];
  static const List<String> _englishWeekdays = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];
  static final Map<String, AstrologyCalendarDay> _sharedReadCache = {};

  late _AstrologyCalendarCivilDate _selected;
  late DateTime _visibleMonthUtc;
  AstrologyCalendarOperation? _operation;
  AstrologyCalendarOperation? _monthOperation;
  AstrologyCalendarDay? _selectedData;
  Object? _failure;
  int _generation = 0;
  int _monthGeneration = 0;
  int _completed = 0;
  int _total = 0;
  int _monthBatchCompleted = 0;
  int _monthBatchTotal = 0;
  String? _monthCurrentDate;
  bool _loading = false;
  bool _monthBatchRunning = false;
  bool _showAgenda = true;
  final Set<String> _monthFailures = {};
  final ValueNotifier<int> _detailUpdates = ValueNotifier<int>(0);
  double _calendarTextSize = AstrologyCalendarTextSettings.defaultSize;
  bool _textSizeReady = false;
  bool _textSizeSaving = false;

  String get _cacheIdentity =>
      widget.cacheIdentity ?? _astrologyCalendarProviderIdentity();

  @override
  void initState() {
    super.initState();
    _restoreCalendarTextSize();
    _showAgenda = widget.initialShowAgenda;
    final initial = widget.initialDate;
    _selected = initial == null
        ? _todayCivilDate()
        : _AstrologyCalendarCivilDate(
            initial.year,
            initial.month,
            initial.day,
          ).bounded();
    _visibleMonthUtc = DateTime.utc(_selected.year, _selected.month);
    _loadCurrentViewAfterFrame();
  }

  Future<void> _restoreCalendarTextSize() async {
    final size = await AstrologyCalendarTextSettings.restore();
    if (!mounted) return;
    setState(() {
      _calendarTextSize = size;
      _textSizeReady = true;
    });
  }

  Future<void> _chooseCalendarTextSize() async {
    final english = _astrologyCalendarEnglish(context);
    var draft = _calendarTextSize;
    final selected = await showDialog<double>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, updateDialog) => AlertDialog(
          key: const ValueKey('astrology-calendar-text-size-dialog'),
          scrollable: true,
          title: Text(english ? 'Calendar text size' : 'カレンダーの文字サイズ'),
          content: SizedBox(width: 400, child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final size in AstrologyCalendarTextSettings.sizes)
                RadioListTile<double>(
                  key: ValueKey('astrology-calendar-text-size-option-${size.toInt()}'),
                  value: size,
                  groupValue: draft,
                  onChanged: (value) => updateDialog(() => draft = value!),
                  title: Text(
                    english
                        ? '${size == 15 ? 'Standard' : size == 17 ? 'Large' : 'Extra large'} (${size.toInt()})'
                        : '${size == 15 ? '標準' : size == 17 ? '大' : '特大'}（${size.toInt()}）',
                    style: TextStyle(fontSize: size),
                  ),
                ),
              const SizedBox(height: 8),
              Text(english ? 'Moon: Aries → Taurus 08:30\nVoid 06:00–08:30' : '月：牡羊座 → 牡牛座 08:30\nボイド 06:00〜08:30',
                  style: TextStyle(fontSize: draft, height: 1.3)),
              const SizedBox(height: 12),
              Text(english
                  ? 'Applies to calendar date cells. If the month cannot fit at this size, scroll to see all dates. Saved images keep their own layout.'
                  : '日付マスの文字に反映します。月全体が収まらない場合はスクロールで全日を表示します。保存画像は専用の配置を保ちます。'),
            ],
          )),
          actions: [
            TextButton(key: const ValueKey('astrology-calendar-text-size-cancel'),
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(english ? 'Cancel' : '取消')),
            FilledButton(key: const ValueKey('astrology-calendar-text-size-apply'),
                onPressed: () => Navigator.of(dialogContext).pop(draft),
                child: Text(english ? 'Apply' : '適用')),
          ],
        ),
      ),
    );
    if (!mounted || selected == null || selected == _calendarTextSize) return;
    setState(() => _textSizeSaving = true);
    try {
      await AstrologyCalendarTextSettings.save(selected);
      if (mounted) setState(() => _calendarTextSize = selected);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(english ? 'The text size could not be saved. Please try again.' : '文字サイズを保存できませんでした。もう一度お試しください。'),
      ));
    } finally {
      if (mounted) setState(() => _textSizeSaving = false);
    }
  }

  @override
  void didUpdateWidget(covariant AstrologyCalendarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldDate = oldWidget.initialDate;
    final newDate = widget.initialDate;
    final initialViewChanged =
        oldWidget.initialShowAgenda != widget.initialShowAgenda;
    if (initialViewChanged) _showAgenda = widget.initialShowAgenda;
    final initialCivilDateChanged =
        oldDate?.year != newDate?.year ||
        oldDate?.month != newDate?.month ||
        oldDate?.day != newDate?.day;
    if (initialCivilDateChanged) {
      _cancelMonthBatch(updateState: false);
      final today = newDate == null
          ? _todayCivilDate()
          : _AstrologyCalendarCivilDate(
              newDate.year,
              newDate.month,
              newDate.day,
            ).bounded();
      _selected = today;
      _visibleMonthUtc = DateTime.utc(today.year, today.month);
      _selectedData = null;
      _loadCurrentViewAfterFrame();
    } else if (oldWidget.cacheIdentity != widget.cacheIdentity ||
        oldWidget.startJob != widget.startJob) {
      _cancelMonthBatch(updateState: false);
      _selectedData = null;
      if (_showAgenda) {
        _loadCurrentViewAfterFrame();
      } else {
        _loadSelected(force: true);
      }
    } else if (initialViewChanged) {
      _cancelMonthBatch(updateState: false);
      _loadCurrentViewAfterFrame();
    }
  }

  void _loadCurrentViewAfterFrame() {
    if (!_showAgenda) {
      _loadSelected();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_showAgenda || _monthBatchRunning) return;
      _loadVisibleMonthEvents();
    });
  }

  @override
  void dispose() {
    _generation++;
    _operation?.cancel();
    _operation = null;
    _cancelMonthBatch(updateState: false);
    _detailUpdates.dispose();
    super.dispose();
  }

  _AstrologyCalendarCivilDate _todayCivilDate() {
    final nowUtc = (widget.nowUtc?.call() ?? DateTime.now().toUtc()).toUtc();
    final jst = nowUtc.add(DailySevenTimepointPlan.jstOffset);
    return _AstrologyCalendarCivilDate(jst.year, jst.month, jst.day).bounded();
  }

  String _cacheKey(String dateKey) => '$_cacheIdentity|$dateKey';

  void _remember(AstrologyCalendarDay value) {
    final key = _cacheKey(value.targetDateJst);
    _sharedReadCache.remove(key);
    _sharedReadCache[key] = value;
    _monthFailures.remove(value.targetDateJst);
    while (_sharedReadCache.length > _cacheCapacity) {
      _sharedReadCache.remove(_sharedReadCache.keys.first);
    }
    _detailUpdates.value++;
  }

  void _select(_AstrologyCalendarCivilDate date) {
    final bounded = date.bounded();
    final monthChanged =
        bounded.year != _selected.year || bounded.month != _selected.month;
    if (monthChanged) _cancelMonthBatch();
    final batchStillRunning = _monthBatchRunning;
    final cached = _sharedReadCache[_cacheKey(bounded.key)];
    setState(() {
      _selected = bounded;
      _visibleMonthUtc = DateTime.utc(bounded.year, bounded.month);
      _selectedData = cached;
      _failure = _monthFailures.contains(bounded.key)
          ? StateError('その日の星イベントを取得できませんでした。')
          : null;
      _loading = false;
    });
    widget.onDateSelected?.call(bounded.noonUtc);
    if (!batchStillRunning) {
      if (monthChanged && _showAgenda) {
        _loadVisibleMonthEvents();
      } else {
        _loadSelected();
      }
    }
  }

  void _moveMonth(int offset) {
    final next = DateTime.utc(
      _visibleMonthUtc.year,
      _visibleMonthUtc.month + offset,
      1,
    );
    if (next.year < _calendarMinimumYear || next.year > _calendarMaximumYear)
      return;
    final maxDay = DateTime.utc(next.year, next.month + 1, 0).day;
    _select(
      _AstrologyCalendarCivilDate(
        next.year,
        next.month,
        math.min(_selected.day, maxDay).toInt(),
      ),
    );
  }

  void _goToToday() => _select(_todayCivilDate());

  void _cancelMonthBatch({bool updateState = true}) {
    final wasRunning = _monthBatchRunning || _monthOperation != null;
    _monthGeneration++;
    _monthOperation?.cancel();
    _monthOperation = null;
    if (wasRunning && updateState && mounted) {
      setState(() {
        _monthBatchRunning = false;
        _monthCurrentDate = null;
      });
    } else if (wasRunning) {
      _monthBatchRunning = false;
      _monthCurrentDate = null;
    }
  }

  Future<void> _loadVisibleMonthEvents({List<String>? dates}) async {
    if (_monthBatchRunning) {
      _cancelMonthBatch();
      if (_selectedData == null) _loadSelected(force: true);
      return;
    }

    _generation++;
    _operation?.cancel();
    _operation = null;
    final generation = ++_monthGeneration;
    final year = _visibleMonthUtc.year;
    final month = _visibleMonthUtc.month;
    final days = DateTime.utc(year, month + 1, 0).day;
    final dateKeys = dates ?? [
      for (var day = 1; day <= days; day++)
        _AstrologyCalendarCivilDate(year, month, day).key,
    ];
    setState(() {
      _monthBatchRunning = true;
      _monthBatchCompleted = 0;
      _monthBatchTotal = dateKeys.length;
      _monthCurrentDate = null;
      _monthFailures.removeAll(dateKeys);
      _selectedData = _sharedReadCache[_cacheKey(_selected.key)];
      _failure = null;
      _loading = false;
    });

    for (final dateKey in dateKeys) {
      if (!mounted || generation != _monthGeneration) return;
      final cached = _sharedReadCache[_cacheKey(dateKey)];
      if (cached != null) {
        setState(() {
          _monthBatchCompleted++;
          if (dateKey == _selected.key) {
            _selectedData = cached;
            _failure = null;
          }
        });
        continue;
      }

      setState(() => _monthCurrentDate = dateKey);
      try {
        final starter = widget.startJob ?? _AstrologyCalendarIsolateJob.start;
        final operation = starter(dateKey, (_, _) {});
        _monthOperation = operation;
        final value = await operation.result;
        if (!mounted || generation != _monthGeneration) return;
        if (value.targetDateJst != dateKey) {
          throw StateError('対象月の日付と取得結果が一致しません。');
        }
        _remember(value);
        setState(() {
          _monthBatchCompleted++;
          _monthCurrentDate = null;
          if (dateKey == _selected.key) {
            _selectedData = value;
            _failure = null;
            _loading = false;
          }
        });
      } catch (error) {
        if (!mounted || generation != _monthGeneration) return;
        _monthFailures.add(dateKey);
        setState(() {
          _monthBatchCompleted++;
          _monthCurrentDate = null;
          if (dateKey == _selected.key) {
            _selectedData = null;
            _failure = error;
            _loading = false;
          }
        });
      } finally {
        if (generation == _monthGeneration) _monthOperation = null;
        if (mounted) _detailUpdates.value++;
      }
    }

    if (!mounted || generation != _monthGeneration) return;
    setState(() {
      _monthBatchRunning = false;
      _monthCurrentDate = null;
    });
  }

  void _loadSelected({bool force = false}) {
    final generation = ++_generation;
    _operation?.cancel();
    _operation = null;
    final dateKey = _selected.key;
    final cached = force ? null : _sharedReadCache[_cacheKey(dateKey)];
    if (cached != null) {
      _sharedReadCache.remove(_cacheKey(dateKey));
      _sharedReadCache[_cacheKey(dateKey)] = cached;
      setState(() {
        _selectedData = cached;
        _failure = null;
        _loading = false;
        _completed = 0;
        _total = 0;
      });
      _monthFailures.remove(dateKey);
      _detailUpdates.value++;
      return;
    }

    setState(() {
      _selectedData = null;
      _failure = null;
      _loading = true;
      _completed = 0;
      _total = 0;
    });
    _detailUpdates.value++;
    try {
      final starter = widget.startJob ?? _AstrologyCalendarIsolateJob.start;
      final operation = starter(dateKey, (completed, total) {
        if (!mounted || generation != _generation) return;
        setState(() {
          _completed = completed;
          _total = total;
        });
        _detailUpdates.value++;
      });
      _operation = operation;
      unawaited(_collect(operation, generation, dateKey));
    } catch (error) {
      if (generation != _generation) return;
      _monthFailures.add(dateKey);
      setState(() {
        _loading = false;
        _failure = error;
      });
      _detailUpdates.value++;
    }
  }

  Future<void> _collect(
    AstrologyCalendarOperation operation,
    int generation,
    String requestedDate,
  ) async {
    try {
      final result = await operation.result;
      if (generation != _generation || !mounted) return;
      if (result.targetDateJst != requestedDate) {
        throw StateError('計算対象日が選択日と一致しません。');
      }
      _remember(result);
      setState(() {
        _selectedData = result;
        _failure = null;
        _loading = false;
        _operation = null;
      });
    } catch (error) {
      if (generation != _generation || !mounted) return;
      _monthFailures.add(requestedDate);
      setState(() {
        _failure = error;
        _loading = false;
        _operation = null;
      });
    } finally {
      if (mounted) _detailUpdates.value++;
    }
  }

  Future<void> _previewMonthImages() async {
    final english = _astrologyCalendarEnglish(context);
    final month = _visibleMonthUtc;
    final count = DateTime.utc(month.year, month.month + 1, 0).day;
    final days = <AstrologyCalendarDay>[];
    for (var i = 1; i <= count; i++) {
      final key = _AstrologyCalendarCivilDate(month.year, month.month, i).key;
      final day = _sharedReadCache[_cacheKey(key)];
      if (day == null || _monthFailures.contains(key)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(english
            ? 'Load every day with “Load this month’s event list” before exporting. Failed days need a retry.'
            : '先に「この月のイベントを一覧取得」で全日を取得してください。失敗した日は再取得が必要です。')));
        return;
      }
      days.add(day);
    }
    try {
      await showAstrologyCalendarSharePreview(context,
        year: month.year, month: month.month, days: days, english: english);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(english
          ? 'The complete month could not be prepared. Please reload the month.'
          : '共有用の全月データを確定できませんでした。月の一覧を再取得してください。')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final english = _astrologyCalendarEnglish(context);
    final lastMonth = DateTime.utc(_calendarMaximumYear, 12);
    final firstMonth = DateTime.utc(_calendarMinimumYear, 1);
    final canGoPrevious = _visibleMonthUtc.isAfter(firstMonth);
    final canGoNext = _visibleMonthUtc.isBefore(lastMonth);
    final today = _todayCivilDate();
    final tablet = MediaQuery.sizeOf(context).shortestSide >= 600;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _astrologyCalendarCopy(context, '星のカレンダー', 'Astrology calendar'),
        ),
        actions: [
          Tooltip(message: english ? 'Calendar text size' : 'カレンダーの文字サイズ', child: TextButton.icon(
            key: const ValueKey('astrology-calendar-text-size-button'),
            onPressed: _textSizeReady && !_textSizeSaving ? _chooseCalendarTextSize : null,
            icon: const Icon(Icons.text_fields),
            label: Text('${_calendarTextSize.toInt()}'),
            style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
          )),
        ],
      ),
      body: SafeArea(
        child: !tablet && !_showAgenda
            ? _phoneWeekCalendar(english, canGoPrevious, canGoNext)
            : tablet && !_showAgenda
            ? _tabletMonth(today, english, canGoPrevious, canGoNext)
            : SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF191A30).withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: const Color(0xFF716B9E).withValues(alpha: 0.48),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: english ? 'Previous month' : '前月',
                      onPressed: canGoPrevious ? () => _moveMonth(-1) : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: Text(
                        _astrologyCalendarMonthLabel(
                          _visibleMonthUtc.year,
                          _visibleMonthUtc.month,
                          english,
                        ),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: english ? 'Next month' : '翌月',
                      onPressed: canGoNext ? () => _moveMonth(1) : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _goToToday,
                    icon: const Icon(Icons.today_outlined, size: 17),
                    label: Text(english ? 'Today' : '今日'),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    key: const ValueKey('astrology-calendar-month-load'),
                    onPressed: _loadVisibleMonthEvents,
                    icon: Icon(
                      _monthBatchRunning
                          ? Icons.stop_circle_outlined
                          : Icons.list_alt,
                      size: 18,
                    ),
                    label: Text(
                      _monthBatchRunning
                          ? (english ? 'Stop month list' : '月一覧を中止')
                          : (english
                                ? 'Load this month’s event list'
                                : 'この月のイベントを一覧取得'),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    key: const ValueKey('astrology-calendar-share-preview'),
                    onPressed: _monthBatchRunning ? null : _previewMonthImages,
                    icon: const Icon(Icons.image_outlined),
                    label: Text(english ? 'Save / share month images' : '月の画像を保存・共有'),
                  ),
                ),
                if (_monthBatchRunning) ...[
                  Text(
                    english
                        ? 'Checking ${_monthCurrentDate ?? 'the next date'} · $_monthBatchCompleted/$_monthBatchTotal'
                        : '月内の日付を確認中（${_monthCurrentDate ?? '次の日'}） $_monthBatchCompleted/$_monthBatchTotal',
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: _monthBatchTotal == 0
                        ? null
                        : (_monthBatchCompleted / _monthBatchTotal)
                              .clamp(0.0, 1.0)
                              .toDouble(),
                  ),
                ],
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    ChoiceChip(
                      key: const ValueKey('astrology-calendar-grid-mode'),
                      label: Text(english ? 'Calendar' : 'カレンダー'),
                      selected: !_showAgenda,
                      onSelected: (_) => setState(() => _showAgenda = false),
                    ),
                    ChoiceChip(
                      key: const ValueKey('astrology-calendar-agenda-mode'),
                      label: Text(english ? 'Event list' : 'イベント一覧'),
                      selected: _showAgenda,
                      onSelected: (_) {
                        setState(() => _showAgenda = true);
                        if (!_monthBatchRunning) _loadVisibleMonthEvents();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_showAgenda) _monthAgenda(english),
                if (!_showAgenda) _calendarGrid(today, english),
                const SizedBox(height: 5),
                Text(
                  key: const ValueKey('astrology-calendar-legend'),
                  english
                      ? 'Moon / Void are always shown · → sign entry · Other events: details · Configurations are noon snapshots'
                      : '月・ボイドは全件表示。→は星座移動。ほかの動きは詳細へ。配置は正午時点。',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
                const SizedBox(height: 10),
                Text(
                  english
                      ? 'Select a date to check the sky for that day.'
                      : '日付を選ぶと、その日の星の動きを調べます',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
                Text(
                  english
                      ? 'All displayed times use JST (UTC+09:00).'
                      : '表示時刻はすべてJST（UTC+09:00）です。',
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
                const SizedBox(height: 6),
                Text(
                  _astrologyCalendarDateLabel(
                    _selected.year,
                    _selected.month,
                    _selected.day,
                    english,
                  ),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                _selectedDayDetails(english),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openTabletDay(_AstrologyCalendarCivilDate date, bool english) async {
    _select(date);
    await showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
      key: const ValueKey('astrology-calendar-day-dialog'),
      scrollable: true,
      title: Text(_astrologyCalendarDateLabel(date.year, date.month, date.day, english)),
      content: SizedBox(width: 620, child: ValueListenableBuilder<int>(
        valueListenable: _detailUpdates,
        builder: (_, value, child) => _selectedDayDetails(english),
      )),
      actions: [TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(english ? 'Close' : '閉じる'))],
    ));
  }

  List<DateTime> get _phoneWeekDates => astrologyCalendarPhoneWeekDates(
    DateTime.utc(_selected.year, _selected.month, _selected.day));

  void _movePhoneWeek(int offset) {
    final date = DateTime.utc(_selected.year, _selected.month, _selected.day)
        .add(Duration(days: offset * 7));
    if (date.year < _calendarMinimumYear || date.year > _calendarMaximumYear) return;
    _cancelMonthBatch();
    _select(_AstrologyCalendarCivilDate(date.year, date.month, date.day));
  }

  Widget _phoneWeekCalendar(bool english, bool previousMonth, bool nextMonth) {
    final dates = _phoneWeekDates;
    final first = dates.first;
    final last = dates.last;
    final selected = DateTime.utc(_selected.year, _selected.month, _selected.day);
    final rows = [for (final date in dates) () {
      final civil = _AstrologyCalendarCivilDate(date.year, date.month, date.day);
      return AstrologyCalendarPhoneDay(date: date,
        supported: date.year >= _calendarMinimumYear && date.year <= _calendarMaximumYear,
        data: _sharedReadCache[_cacheKey(civil.key)],
        failed: _monthFailures.contains(civil.key),
        loading: (_monthBatchRunning && _monthCurrentDate == civil.key) || (_loading && _selected == civil));
    }()];
    return SingleChildScrollView(
      key: const ValueKey('astrology-calendar-phone-week-scroll'),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          IconButton(tooltip: english ? 'Previous month' : '前月', onPressed: previousMonth ? () => _moveMonth(-1) : null, icon: const Icon(Icons.chevron_left)),
          Expanded(child: Text(_astrologyCalendarMonthLabel(_visibleMonthUtc.year, _visibleMonthUtc.month, english),
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
          IconButton(tooltip: english ? 'Next month' : '翌月', onPressed: nextMonth ? () => _moveMonth(1) : null, icon: const Icon(Icons.chevron_right)),
        ]),
        Row(children: [
          IconButton(key: const ValueKey('calendar-phone-previous-week'), tooltip: english ? 'Previous week' : '前の週',
            onPressed: first.year >= _calendarMinimumYear ? () => _movePhoneWeek(-1) : null, icon: const Icon(Icons.arrow_back)),
          Expanded(child: Text('${first.month}/${first.day}–${last.month}/${last.day}',
            key: const ValueKey('calendar-phone-week-range'), textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
          IconButton(key: const ValueKey('calendar-phone-next-week'), tooltip: english ? 'Next week' : '次の週',
            onPressed: last.year <= _calendarMaximumYear ? () => _movePhoneWeek(1) : null, icon: const Icon(Icons.arrow_forward)),
        ]),
        Wrap(spacing: 4, runSpacing: 2, children: [
          TextButton.icon(onPressed: _goToToday, icon: const Icon(Icons.today_outlined), label: Text(english ? 'Today' : '今日')),
          TextButton.icon(key: const ValueKey('calendar-phone-week-load'),
            onPressed: () => _loadVisibleMonthEvents(dates: [for (final day in rows) if (day.supported) day.date.toIso8601String().substring(0, 10)]),
            icon: Icon(_monthBatchRunning ? Icons.stop_circle_outlined : Icons.refresh),
            label: Text(_monthBatchRunning ? '$_monthBatchCompleted/$_monthBatchTotal ${english ? 'Stop' : '中止'}' : (english ? 'Load week' : 'この週を取得'))),
          TextButton(key: const ValueKey('astrology-calendar-month-load'), onPressed: () => _loadVisibleMonthEvents(), child: Text(english ? 'Load full month' : '全月を取得')),
          IconButton(key: const ValueKey('astrology-calendar-share-preview'), tooltip: english ? 'Save / share month images' : '月の画像を保存・共有', onPressed: _monthBatchRunning ? null : _previewMonthImages, icon: const Icon(Icons.image_outlined)),
          IconButton(key: const ValueKey('astrology-calendar-agenda-mode'), tooltip: english ? 'Event list' : 'イベント一覧',
            onPressed: () { setState(() => _showAgenda = true); if (!_monthBatchRunning) _loadVisibleMonthEvents(); }, icon: const Icon(Icons.list_alt)),
        ]),
        if (_monthBatchRunning) LinearProgressIndicator(value: _monthBatchTotal == 0 ? null : _monthBatchCompleted / _monthBatchTotal),
        const SizedBox(height: 8),
        AstrologyCalendarPhoneWeekRows(days: rows, english: english,
          fontSize: _calendarTextSize, selected: selected,
          onOpenDay: (date) => _openTabletDay(_AstrologyCalendarCivilDate(date.year, date.month, date.day), english)),
        const SizedBox(height: 8),
        Text(english ? 'JST (UTC+09:00) · Tap a date for all events · prev/next day = continuation'
          : 'JST（UTC+09:00）・日付タップで詳しく・前日／翌日はボイドの継続',
          key: const ValueKey('astrology-calendar-legend'), style: const TextStyle(fontSize: 12, color: Colors.white70)),
      ]),
    );
  }

  Widget _tabletMonth(_AstrologyCalendarCivilDate today, bool english, bool previous, bool next) {
    final year = _visibleMonthUtc.year;
    final month = _visibleMonthUtc.month;
    final days = DateTime.utc(year, month + 1, 0).day;
    final cells = <int?>[
      ...List<int?>.filled(DateTime.utc(year, month, 1).weekday - 1, null),
      for (var day = 1; day <= days; day++) day,
    ];
    while (cells.length % 7 != 0) { cells.add(null); }
    final weeks = cells.length ~/ 7;
    final compactButtonStyle = TextButton.styleFrom(minimumSize: const Size(36, 40), padding: const EdgeInsets.symmetric(horizontal: 8));
    return Padding(
      key: const ValueKey('astrology-calendar-fitted-month'),
      padding: const EdgeInsets.fromLTRB(6, 2, 6, 2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(height: 44, child: Row(children: [
          IconButton(tooltip: english ? 'Previous month' : '前月', onPressed: previous ? () => _moveMonth(-1) : null, icon: const Icon(Icons.chevron_left)),
          Expanded(child: Text(_astrologyCalendarMonthLabel(year, month, english), textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
          IconButton(tooltip: english ? 'Next month' : '翌月', onPressed: next ? () => _moveMonth(1) : null, icon: const Icon(Icons.chevron_right)),
          IconButton(tooltip: english ? 'Today' : '今日', onPressed: _goToToday, icon: const Icon(Icons.today_outlined, size: 21)),
          TextButton.icon(
            key: const ValueKey('astrology-calendar-month-load'),
            style: compactButtonStyle,
            onPressed: _loadVisibleMonthEvents,
            icon: Icon(_monthBatchRunning ? Icons.stop_circle_outlined : Icons.refresh, size: 19),
            label: Text(_monthBatchRunning ? '$_monthBatchCompleted/$_monthBatchTotal ${english ? 'Stop' : '中止'}' : (english ? 'Load month' : '全日を取得'), style: const TextStyle(fontSize: 14)),
          ),
          IconButton(key: const ValueKey('astrology-calendar-share-preview'), tooltip: english ? 'Save / share month images' : '月の画像を保存・共有', onPressed: _monthBatchRunning ? null : _previewMonthImages, icon: const Icon(Icons.image_outlined)),
          IconButton(key: const ValueKey('astrology-calendar-agenda-mode'), tooltip: english ? 'Event list' : 'イベント一覧', onPressed: () {
            setState(() => _showAgenda = true);
            if (!_monthBatchRunning) _loadVisibleMonthEvents();
          }, icon: const Icon(Icons.list_alt)),
        ])),
        SizedBox(height: 2, child: _monthBatchRunning
            ? LinearProgressIndicator(value: _monthBatchTotal == 0 ? null : _monthBatchCompleted / _monthBatchTotal)
            : const SizedBox.shrink()),
        SizedBox(height: 24, child: Row(children: [
          for (var col = 0; col < 7; col++) Expanded(child: Center(child: Text(
            english ? _englishWeekdays[col] : _japaneseWeekdays[col],
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: col == 6 ? const Color(0xFFFFAAA8) : col == 5 ? const Color(0xFF9BCBFF) : Colors.white70),
          ))),
        ])),
        Expanded(child: LayoutBuilder(builder: (context, constraints) {
          final width = constraints.maxWidth / 7;
          final innerWidth = width - 14;
          final scaler = MediaQuery.textScalerOf(context);
          final style = DefaultTextStyle.of(context).style;
          List<double> requiredHeights(double fontSize) => [
            for (var week = 0; week < weeks; week++)
              [for (var col = 0; col < 7; col++)
                if (cells[week * 7 + col] case final int day)
                  if (_sharedReadCache[_cacheKey(_AstrologyCalendarCivilDate(year, month, day).key)] case final AstrologyCalendarDay data)
                    astrologyCalendarCompactRequiredHeight(data: data, english: english, width: innerWidth, textScaler: scaler, dayNumber: day, fontSize: fontSize, textStyle: style) + 12
                  else _tabletPendingHeight(_AstrologyCalendarCivilDate(year, month, day), english, innerWidth, fontSize, style, scaler) + 12,
                42.0,
              ].reduce(math.max),
          ];
          final fontSize = _calendarTextSize;
          final heights = requiredHeights(fontSize);
          final minimum = heights.fold(0.0, (a,b) => a+b);
          final extra = math.max(0.0, (constraints.maxHeight - minimum) / weeks);
          final rows = Column(children: [
            for (var week = 0; week < weeks; week++)
              SizedBox(height: heights[week] + extra, child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var col = 0; col < 7; col++) Expanded(child: _tabletDayCell(cells[week*7+col], col, today, english, fontSize, heights[week] + extra - 12)),
              ])),
          ]);
          // Preserve the chosen size and every mandatory interval. Never
          // silently shrink a user's selection to make the month fit.
          if (minimum > constraints.maxHeight + 0.5) {
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(english ? 'Scroll for all dates · Text size: ${fontSize.toInt()}' : '全日は縦スクロールで表示・文字サイズ ${fontSize.toInt()}',
                key: const ValueKey('astrology-calendar-text-size-overflow-notice'),
                style: const TextStyle(fontSize: 14, color: Color(0xFFFFDCA6))),
              Expanded(child: SingleChildScrollView(key: const ValueKey('astrology-calendar-accessibility-overflow'), child: rows)),
            ]);
          }
          return rows;
        })),
        SizedBox(height: 24, child: Align(alignment: Alignment.centerLeft, child: Text(
          key: const ValueKey('astrology-calendar-legend'),
          english ? 'JST (UTC+09:00) · Tap a date for all events · prev/next day = continuation' : 'JST（UTC+09:00）・日付タップで詳しく・前日／翌日はボイドの継続',
          style: const TextStyle(fontSize: 12, color: Colors.white70),
        ))),
      ]),
    );
  }

  String _tabletDayStatus(_AstrologyCalendarCivilDate date, bool english) {
    final failed = _monthFailures.contains(date.key);
    final active = (_monthBatchRunning && _monthCurrentDate == date.key) || (_loading && _selected == date);
    return english ? 'Moon / Void: ${active ? 'loading' : failed ? 'failed · retry' : 'not loaded'}'
        : '月・ボイド：${active ? '取得中' : failed ? '取得失敗・再試行' : '未取得'}';
  }

  double _tabletPendingHeight(_AstrologyCalendarCivilDate date, bool english, double width, double fontSize, TextStyle style, TextScaler scaler) {
    final painter = TextPainter(text: TextSpan(text: '${date.day}\n${_tabletDayStatus(date, english)}', style: style.copyWith(fontSize: fontSize, height: 1.15, fontWeight: FontWeight.w600)), textDirection: TextDirection.ltr, textScaler: scaler);
    try { painter.layout(maxWidth: width); return painter.height.ceilToDouble(); } finally { painter.dispose(); }
  }

  Widget _tabletDayCell(int? day, int weekday, _AstrologyCalendarCivilDate today, bool english, double fontSize, double height) {
    if (day == null) return const SizedBox.shrink();
    final date = _AstrologyCalendarCivilDate(_visibleMonthUtc.year, _visibleMonthUtc.month, day);
    final data = _sharedReadCache[_cacheKey(date.key)];
    final status = _tabletDayStatus(date, english);
    return Semantics(button: true, selected: date == _selected, label: '${date.key} ${english ? 'Open details' : '詳細を開く'}', child: Material(
      color: date == _selected ? const Color(0xFF443D70) : const Color(0xFF191A30),
      child: InkWell(
        key: ValueKey<String>('astrology-calendar-day-${date.key}'),
        onTap: () => _openTabletDay(date, english),
        child: Container(
          margin: const EdgeInsets.all(1),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          decoration: BoxDecoration(border: Border.all(color: date == today ? const Color(0xFFEBD486) : const Color(0xFF48455F), width: date == today ? 1.2 : 0.5), borderRadius: BorderRadius.circular(5)),
          child: data != null
            ? AstrologyCalendarCompactDayContent(data: data, english: english, dayNumber: day, fontSize: fontSize, maxHeight: height)
            : Text('$day\n$status', style: TextStyle(fontSize: fontSize, height: 1.15, fontWeight: FontWeight.w600, color: const Color(0xFFCAE6FF))),
        ),
      ),
    ));
  }


  Widget _calendarGrid(
    _AstrologyCalendarCivilDate today,
    bool english,
  ) => LayoutBuilder(
    builder: (context, constraints) {
      // Preserve the app's inherited text scaler. Wider cells and natural
      // row heights keep event clocks readable instead of shrinking text.
      final minimumCellWidth = math.max(
        180.0,
        MediaQuery.textScalerOf(context).scale(_calendarTextSize) * 13,
      );
      final width = math.max(constraints.maxWidth, minimumCellWidth * 7);
      final scrolls = width > constraints.maxWidth;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (scrolls)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                english
                    ? 'Scroll sideways to see all dates. The event list also shows every date.'
                    : '横にスクロールすると全ての日付が見られます。イベント一覧でも全日を確認できます。',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ),
          SingleChildScrollView(
            key: const ValueKey('astrology-calendar-grid-scroll'),
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width.toDouble(),
              child: Table(
                key: const ValueKey('astrology-calendar-grid'),
                columnWidths: const {
                  0: FlexColumnWidth(),
                  1: FlexColumnWidth(),
                  2: FlexColumnWidth(),
                  3: FlexColumnWidth(),
                  4: FlexColumnWidth(),
                  5: FlexColumnWidth(),
                  6: FlexColumnWidth(),
                },
                children: [
                  TableRow(
                    children: [
                      for (
                        var weekdayIndex = 0;
                        weekdayIndex < 7;
                        weekdayIndex++
                      )
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                            english
                                ? _englishWeekdays[weekdayIndex]
                                : _japaneseWeekdays[weekdayIndex],
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: weekdayIndex == 6
                                  ? const Color(0xFFFFAAA8)
                                  : weekdayIndex == 5
                                  ? const Color(0xFF9BCBFF)
                                  : Colors.white70,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                  ..._monthRows(today, english),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );

  List<TableRow> _monthRows(_AstrologyCalendarCivilDate today, bool english) {
    final year = _visibleMonthUtc.year;
    final month = _visibleMonthUtc.month;
    final days = DateTime.utc(year, month + 1, 0).day;
    final firstWeekday = DateTime.utc(year, month, 1).weekday;
    final cells = <int?>[
      ...List<int?>.filled(firstWeekday - 1, null),
      for (var day = 1; day <= days; day++) day,
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    final rows = <TableRow>[];
    for (var offset = 0; offset < cells.length; offset += 7) {
      rows.add(
        TableRow(
          children: [
            for (var column = 0; column < 7; column++)
              _dayCell(cells[offset + column], column, today, english),
          ],
        ),
      );
    }
    return rows;
  }

  double _calendarCellHeight() {
    final scaler = MediaQuery.textScalerOf(context);
    return math
        .max(80.0, scaler.scale(13) * 1.2 + scaler.scale(12) * 1.25 * 3 + 18)
        .toDouble();
  }

  Widget _dayCell(
    int? day,
    int weekdayColumn,
    _AstrologyCalendarCivilDate today,
    bool english,
  ) {
    if (day == null) return SizedBox(height: _calendarCellHeight());
    final date = _AstrologyCalendarCivilDate(
      _visibleMonthUtc.year,
      _visibleMonthUtc.month,
      day,
    );
    final isSelected = date == _selected;
    final isToday = date == today;
    final result = _sharedReadCache[_cacheKey(date.key)];
    final dateIsCurrent =
        (_monthBatchRunning && _monthCurrentDate == date.key) ||
        (_loading && _selected.key == date.key);
    final dateHasFailed = _monthFailures.contains(date.key);
    final hint = result == null
        ? dateIsCurrent
              ? (english ? 'Currently checking' : '取得中')
              : dateHasFailed
              ? (english ? 'Event check failed' : '取得失敗')
              : _monthBatchRunning
              ? (english ? 'Queued in month list' : '月一覧の取得待ち')
              : (english ? 'Not yet checked' : '未取得')
        : result.events.isEmpty
        ? (english ? 'Checked; no listed events' : '取得済み・該当イベントなし')
        : '${english ? 'Checked; ${result.events.length} listed event(s): ' : '取得済み・イベント${result.events.length}件: '}'
              '${result.events.map((event) => _eventText(event, english)).join(english ? '; ' : '／')}';
    final dateLabel = _astrologyCalendarDateLabel(
      date.year,
      date.month,
      date.day,
      english,
    );
    final semantics = english
        ? '$dateLabel, select date. $hint'
        : '${date.year}年${date.month}月${date.day}日を選択、$hint';
    return Semantics(
      button: true,
      selected: isSelected,
      label: semantics,
      child: Tooltip(
        message: semantics,
        child: InkWell(
          key: ValueKey<String>('astrology-calendar-day-${date.key}'),
          onTap: () => _select(date),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints: BoxConstraints(minHeight: _calendarCellHeight()),
            margin: const EdgeInsets.all(2),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF6557A5)
                  : isToday
                  ? const Color(0xFF33334D)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isToday
                    ? const Color(0xFFF6D77A)
                    : Colors.white.withValues(alpha: 0.08),
                width: isToday ? 1.4 : 0.6,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    '$day',
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: _calendarTextSize,
                      fontWeight: isSelected || isToday
                          ? FontWeight.w900
                          : FontWeight.w600,
                      color: weekdayColumn == 6
                          ? const Color(0xFFFFAAA8)
                          : weekdayColumn == 5
                          ? const Color(0xFF9BCBFF)
                          : Colors.white,
                    ),
                  ),
                ),
                if (result == null)
                  Text(
                    english
                        ? 'Moon / Void: ${dateIsCurrent ? 'loading' : dateHasFailed ? 'failed · retry' : 'not loaded'}'
                        : '月・ボイド：${dateIsCurrent ? '取得中' : dateHasFailed ? '取得失敗・再試行' : '未取得'}',
                    style: TextStyle(fontSize: _calendarTextSize, color: const Color(0xFFCAE6FF)),
                  )
                else
                  AstrologyCalendarDayContent(data: result, english: english, fontSize: _calendarTextSize),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _monthAgenda(bool english) {
    final year = _visibleMonthUtc.year;
    final month = _visibleMonthUtc.month;
    final count = DateTime.utc(year, month + 1, 0).day;
    return Column(
      key: const ValueKey('astrology-calendar-agenda'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          english
              ? 'Void-of-course intervals, sign entries and retrograde/direct switches · JST'
              : 'ボイドの開始・終了・継続、星の移動、逆行・順行の切替（JST）',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        for (var day = 1; day <= count; day++)
          _agendaDay(_AstrologyCalendarCivilDate(year, month, day), english),
      ],
    );
  }

  Widget _agendaDay(_AstrologyCalendarCivilDate date, bool english) {
    final data = _sharedReadCache[_cacheKey(date.key)];
    final failed = _monthFailures.contains(date.key);
    final active =
        (_monthBatchRunning && _monthCurrentDate == date.key) ||
        (_loading && _selected == date);
    final events = [...?data?.events]
      ..sort(
        (a, b) =>
            (a.overlapStartUtc ??
                    a.startUtc ??
                    a.snapshotUtc ??
                    DateTime.utc(date.year, date.month, date.day, 3))
                .compareTo(
                  b.overlapStartUtc ??
                      b.startUtc ??
                      b.snapshotUtc ??
                      DateTime.utc(date.year, date.month, date.day, 3),
                ),
      );
    final status = failed
        ? (english ? 'Could not load · tap to retry' : '取得失敗・タップで再試行')
        : active
        ? (english ? 'Loading…' : '取得中…')
        : data == null
        ? (english ? 'Not loaded yet' : '未取得')
        : events.isEmpty
        ? (english ? 'Checked · no listed events' : '取得済み・対象イベントなし')
        : null;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Material(
        color: const Color(0xFF24243C),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: ValueKey('astrology-calendar-agenda-${date.key}'),
          borderRadius: BorderRadius.circular(12),
          onTap: () => _select(date),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _astrologyCalendarDateLabel(
                    date.year,
                    date.month,
                    date.day,
                    english,
                  ),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFFFD987),
                  ),
                ),
                if (status != null) Text(status),
                if (data != null)
                  AstrologyCalendarDayContent(data: data, english: english, supplementalLimit: 0),
                for (final event in events)
                  Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _eventIcon(event.kind),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _eventText(event, english),
                            softWrap: true,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _selectedDayDetails(bool english) {
    if (_loading) {
      final hasProgress = _total > 0;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(english ? 'Checking the sky…' : '星の動きを調べています…'),
              ),
            ],
          ),
          if (hasProgress) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: (_completed / _total).clamp(0.0, 1.0).toDouble(),
            ),
          ],
        ],
      );
    }
    if (_failure != null) {
      return Row(
        children: [
          Expanded(
            child: Text(
              english
                  ? 'Could not load the sky events for this date.'
                  : '星の動きを取得できませんでした。',
            ),
          ),
          TextButton(
            onPressed: () => _loadSelected(force: true),
            child: Text(english ? 'Try again' : '再試行'),
          ),
        ],
      );
    }
    final data = _selectedData;
    if (data == null) {
      if (_monthBatchRunning) {
        return Text(
          english
              ? 'This date is waiting in the month list.'
              : 'この日は月一覧の取得待ちです。',
          style: const TextStyle(fontSize: 12, color: Colors.white70),
        );
      }
      return const SizedBox.shrink();
    }
    if (data.events.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            english
                ? 'There are no listed events for this date.'
                : 'この日の補足イベントはありません。',
          ),
          AstrologyCalendarDayContent(data: data, english: english, supplementalLimit: 0),
          _providerNote(data, english),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AstrologyCalendarDayContent(data: data, english: english, supplementalLimit: 0),
        for (final event in data.events)
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _eventIcon(event.kind),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _eventText(event, english),
                    key: ValueKey(
                      'astrology-calendar-detail-${data.targetDateJst}-${data.events.indexOf(event)}',
                    ),
                    softWrap: true,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        _providerNote(data, english),
      ],
    );
  }

  Widget _providerNote(AstrologyCalendarDay data, bool english) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(
      english
          ? 'Source: ${_astrologyCalendarProviderLabel(data.providerName, true)}. ${_astrologyCalendarPrecisionLabel(data.precisionNotice, true)} This describes the calculation source; it is not independent proof of accuracy.'
          : '計算元: ${data.providerName}。${data.precisionNotice}。'
                'これは計算元の表示で、独立した精度証明ではありません。',
      softWrap: true,
      style: TextStyle(
        fontSize: 12,
        height: 1.35,
        color: Colors.white.withValues(alpha: 0.56),
      ),
    ),
  );

  Widget _eventIcon(AstrologyCalendarEventKind kind) {
    final (IconData icon, Color color) = switch (kind) {
      AstrologyCalendarEventKind.signIngress => (
        Icons.swap_horiz,
        const Color(0xFF9BCBFF),
      ),
      AstrologyCalendarEventKind.retrogradeStation => (
        Icons.swap_vert,
        const Color(0xFFF6D77A),
      ),
      AstrologyCalendarEventKind.majorLunarPhase => (
        Icons.brightness_2_outlined,
        const Color(0xFFF6D77A),
      ),
      AstrologyCalendarEventKind.voidMoon => (
        Icons.nights_stay_outlined,
        const Color(0xFFCEB5FF),
      ),
      AstrologyCalendarEventKind.specialConfiguration => (
        Icons.auto_awesome_outlined,
        const Color(0xFFFFB985),
      ),
    };
    return Icon(icon, size: 16, color: color);
  }

  String _eventText(AstrologyCalendarEvent event, bool english) {
    final title = _astrologyCalendarEventTitle(event, english);
    final detail = _astrologyCalendarEventDetail(event, english);
    final time = event.startUtc == null
        ? (english ? 'At 12:00 JST' : '正午時点')
        : _astrologyCalendarJstTimestamp(event.startUtc!, english: english);
    if (event.kind == AstrologyCalendarEventKind.voidMoon) {
      final start = _astrologyCalendarJstTimestamp(
        event.startUtc!,
        english: english,
      );
      final end = _astrologyCalendarJstTimestamp(
        event.endUtc!,
        english: english,
      );
      final continuation = [
        if (event.continuesFromPreviousDay)
          english ? 'continues from previous day' : '前日から継続',
        if (event.continuesIntoNextDay)
          english ? 'continues into next day' : '翌日も継続',
      ].join(english ? '; ' : '・');
      final overlapStart = _astrologyCalendarJstTimestamp(
        event.overlapStartUtc!,
        english: english,
      );
      final overlapEnd = _astrologyCalendarJstTimestamp(
        event.overlapEndUtc!,
        english: english,
      );
      final duration = _astrologyCalendarDuration(
        event.endUtc!.toUtc().difference(event.startUtc!.toUtc()),
        english: english,
      );
      if (english) {
        return 'Actual interval: $start – $end (duration: $duration)${continuation.isEmpty ? '' : ' ($continuation)'}. '
            'Overlap on this date: $overlapStart – $overlapEnd. $title: $detail';
      }
      return '実区間: $start〜$end（継続$duration）${continuation.isEmpty ? '' : '（$continuation）'}。'
          'この日の範囲: $overlapStart〜$overlapEnd。${event.title}：${event.detail}';
    }
    return english
        ? '$time  $title: $detail'
        : '$time　${event.title}：${event.detail}';
  }
}

class _AstrologyCalendarCivilDate {
  const _AstrologyCalendarCivilDate(this.year, this.month, this.day);

  final int year, month, day;
  String get key =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';
  DateTime get noonUtc => _astrologyCalendarCivilInstantUtc(
    year,
    month,
    day,
    clockTime: const Duration(hours: 12),
    utcOffset: DailySevenTimepointPlan.jstOffset,
  );

  _AstrologyCalendarCivilDate bounded() {
    final boundedYear = year.clamp(1900, 2100).toInt();
    final boundedMonth = month.clamp(1, 12).toInt();
    final maxDay = DateTime.utc(boundedYear, boundedMonth + 1, 0).day;
    return _AstrologyCalendarCivilDate(
      boundedYear,
      boundedMonth,
      day.clamp(1, maxDay).toInt(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _AstrologyCalendarCivilDate &&
      year == other.year &&
      month == other.month &&
      day == other.day;

  @override
  int get hashCode => Object.hash(year, month, day);
}

String _astrologyCalendarProviderIdentity() {
  final provider = AstrologyDataSources.current;
  return 'calendar-v3|-${provider.sourceName}|'
      'precision=${provider.usesHighPrecisionAstroData}';
}

DateTime _astrologyCalendarInstantAtOffset(
  DateTime instantUtc, {
  required Duration offset,
}) => instantUtc.toUtc().add(offset);

DateTime _astrologyCalendarCivilInstantUtc(
  int year,
  int month,
  int day, {
  required Duration clockTime,
  required Duration utcOffset,
}) => DateTime.utc(year, month, day).add(clockTime).subtract(utcOffset);

String _astrologyCalendarJstTimestamp(DateTime utc, {bool english = false}) {
  final jst = _astrologyCalendarInstantAtOffset(
    utc,
    offset: DailySevenTimepointPlan.jstOffset,
  );
  final dateAndTime =
      '${jst.year.toString().padLeft(4, '0')}-'
      '${jst.month.toString().padLeft(2, '0')}-'
      '${jst.day.toString().padLeft(2, '0')} '
      '${jst.hour.toString().padLeft(2, '0')}:'
      '${jst.minute.toString().padLeft(2, '0')}:'
      '${jst.second.toString().padLeft(2, '0')}';
  return english ? '$dateAndTime JST' : '$dateAndTime+09:00';
}

DateTime _astrologyCalendarMoonSegmentStart(
  EphemerisProvider provider,
  DateTime utc,
) => switch (provider) {
  SwissEphemerisProvider value => value._moonSignSegmentStart(utc),
  SimpleEphemeris value => value._moonSignSegmentStart(utc),
  _ => throw UnsupportedError('JST日単位の月ボイドAPIがありません。'),
};

DateTime _astrologyCalendarMoonSegmentEnd(
  EphemerisProvider provider,
  DateTime utc,
) => switch (provider) {
  SwissEphemerisProvider value => value._moonSignSegmentEnd(utc),
  SimpleEphemeris value => value._moonSignSegmentEnd(utc),
  _ => throw UnsupportedError('JST日単位の月ボイドAPIがありません。'),
};

DateTime? _astrologyCalendarLastMoonAspect(
  EphemerisProvider provider,
  DateTime segmentStartUtc,
  DateTime segmentEndUtc,
) => switch (provider) {
  SwissEphemerisProvider value => value._lastMoonMajorAspectTime(
    segmentStartUtc,
    segmentEndUtc,
  ),
  SimpleEphemeris value => value._lastMoonMajorAspectTime(
    segmentStartUtc,
    segmentEndUtc,
  ),
  _ => throw UnsupportedError('JST日単位の月ボイドAPIがありません。'),
};

class _AstrologyCalendarStrictSwissProvider extends SwissEphemerisProvider {
  const _AstrologyCalendarStrictSwissProvider();

  @override
  double? _longitudeForPlanet(AstroPlanet planet, DateTime date) {
    final longitude = super._longitudeForPlanet(planet, date);
    if (longitude == null) {
      throw StateError('Swiss天体位置の取得に失敗しました。');
    }
    return longitude;
  }
}

class _AstrologyCalendarIsolateJob implements AstrologyCalendarOperation {
  _AstrologyCalendarIsolateJob.start(
    String targetDateJst,
    void Function(int, int) onProgress,
  ) : _onProgress = onProgress {
    _port.listen((message) {
      if (_finished) return;
      if (message is List && message.length == 3 && message[0] == 'progress') {
        _onProgress(message[1] as int, message[2] as int);
        return;
      }
      if (message is Map<Object?, Object?>) {
        try {
          final result = AstrologyCalendarDay.fromMessage(message);
          _finish();
          _result.complete(result);
        } catch (error) {
          _finish();
          _result.completeError(error);
        }
        return;
      }
      _finish();
      _result.completeError(StateError('星イベント計算を読み取れませんでした。'));
    });
    unawaited(_spawn(targetDateJst));
  }

  final ReceivePort _port = ReceivePort();
  final Completer<AstrologyCalendarDay> _result =
      Completer<AstrologyCalendarDay>();
  final void Function(int, int) _onProgress;
  Isolate? _isolate;
  bool _finished = false;

  @override
  Future<AstrologyCalendarDay> get result => _result.future;

  Future<void> _spawn(String date) async {
    try {
      final isolate = await Isolate.spawn<(String, SendPort)>(
        _astrologyCalendarWorker,
        (date, _port.sendPort),
        debugName: 'pancyo-astrology-calendar',
        onError: _port.sendPort,
        onExit: _port.sendPort,
      );
      if (_finished) {
        isolate.kill(priority: Isolate.immediate);
      } else {
        _isolate = isolate;
      }
    } catch (error) {
      if (_finished) return;
      _finish();
      _result.completeError(error);
    }
  }

  void _finish() {
    _finished = true;
    _port.close();
    _isolate?.kill(priority: Isolate.immediate);
  }

  @override
  void cancel() {
    if (_finished) return;
    _finish();
    _result.completeError(const _AstrologyCalendarCancelled());
  }
}

class _AstrologyCalendarCancelled implements Exception {
  const _AstrologyCalendarCancelled();
}

void _astrologyCalendarWorker((String, SendPort) input) {
  try {
    final day = calculateAstrologyCalendarDay(
      input.$1,
      onProgress: (completed, total) =>
          input.$2.send(['progress', completed, total]),
    );
    input.$2.send(day.toMessage());
  } catch (error) {
    input.$2.send({'worker_error': error.toString()});
  }
}

/// Calculates only the selected civil JST day. This is a positions/events
/// display; it never reads profiles, preferences, ratings, or score models.
AstrologyCalendarDay calculateAstrologyCalendarDay(
  String targetDateJst, {
  void Function(int completed, int total)? onProgress,
  EphemerisProvider? providerOverride,
}) {
  final plan = DailySevenTimepointPlan.forJstDate(targetDateJst);
  final year = int.parse(targetDateJst.substring(0, 4));
  if (year < 1900 || year > 2100) {
    throw RangeError.range(year, 1900, 2100, 'year');
  }
  const total = 17;
  var completed = 0;
  void progress() => onProgress?.call(++completed, total);

  final configuredProvider = providerOverride ?? AstrologyDataSources.current;
  final ephemeris = configuredProvider is SwissEphemerisProvider
      ? const _AstrologyCalendarStrictSwissProvider()
      : configuredProvider;
  final swissFallbackCountBefore = configuredProvider is SwissEphemerisProvider
      ? SwissEphemerisProvider._placementFallbackCount
      : null;
  final events = <AstrologyCalendarEvent>[];
  Map<AstroPlanet, ZodiacSign>? signsAtDayStart;
  ZodiacSign ingressPreviousSign(AstroPlanet planet) {
    signsAtDayStart ??= {
      for (final placement in ephemeris.placementsFor(plan.dayStartUtc))
        placement.planet: placement.sign,
    };
    final sign = signsAtDayStart![planet];
    if (sign == null) throw StateError('星座移動前の天体位置を取得できません。');
    // nextSignIngress searches for the first departure from this same start
    // sign. Reusing the start position handles both direct and retrograde
    // ingress without inventing a direction or changing the search itself.
    return sign;
  }
  final ingressPlanets = AstroPlanet.values.take(10);
  for (final planet in ingressPlanets) {
    final ingress = ephemeris.nextSignIngress(planet, plan.dayStartUtc);
    if (ingress != null) {
      final timeUtc = ingress.time.toUtc();
      if (!timeUtc.isBefore(plan.dayStartUtc) &&
          timeUtc.isBefore(plan.dayEndUtc)) {
        events.add(
          AstrologyCalendarEvent(
            kind: AstrologyCalendarEventKind.signIngress,
            title: '${planet.label}が${ingress.sign.label}へ移動',
            detail: '星座の移動',
            startUtc: timeUtc,
            ingressPlanet: planet,
            fromSign: ingressPreviousSign(planet),
            toSign: ingress.sign,
          ),
        );
      }
    }
    progress();
  }

  final stationCard = DailyAstroEventsCard(
    date: plan.primaryNoon.instantUtc,
    contextData: _astrologyCalendarStationContext(plan.primaryNoon.instantUtc),
  );
  events.addAll(
    stationCard
        ._stationEvents(plan.dayStartUtc, plan.dayEndUtc, ephemeris)
        .map(
          (description) => _astrologyCalendarStationEvent(description, plan),
        ),
  );
  progress();

  final longitudeCache = <DateTime, Map<AstroPlanet, double>>{};
  Map<AstroPlanet, double> longitudesAt(DateTime utc) =>
      longitudeCache.putIfAbsent(utc, () {
        final placements = ephemeris.placementsFor(utc.toUtc());
        final values = <AstroPlanet, double>{};
        for (final placement in placements) {
          if (placement.planet == AstroPlanet.ascendant ||
              placement.planet == AstroPlanet.midheaven)
            continue;
          final longitude = placement.sign.index * 30 + placement.degree;
          if (!longitude.isFinite || longitude < 0 || longitude >= 360) {
            throw StateError('星の位置を検証できませんでした。');
          }
          values[placement.planet] = longitude;
        }
        if (!values.containsKey(AstroPlanet.sun) ||
            !values.containsKey(AstroPlanet.moon)) {
          throw StateError('太陽または月の位置が不足しています。');
        }
        return values;
      });

  double forwardAngle(double from, double to) => (to - from + 360) % 360;
  double shortestAngle(double first, double second) {
    final forward = forwardAngle(first, second);
    return forward > 180 ? 360 - forward : forward;
  }

  for (final target in const [
    (0.0, '新月'),
    (90.0, '上弦の月'),
    (180.0, '満月'),
    (270.0, '下弦の月'),
  ]) {
    var previousTime = plan.dayStartUtc;
    var previous = longitudesAt(previousTime);
    for (var minutes = 30; minutes <= 24 * 60; minutes += 30) {
      final currentTime = plan.dayStartUtc.add(Duration(minutes: minutes));
      final current = longitudesAt(currentTime);
      final beforeAngle =
          (previous[AstroPlanet.moon]! - previous[AstroPlanet.sun]! + 360) %
          360;
      final afterAngle =
          (current[AstroPlanet.moon]! - current[AstroPlanet.sun]! + 360) % 360;
      final traveled = forwardAngle(beforeAngle, afterAngle);
      final distance = forwardAngle(beforeAngle, target.$1);
      if (traveled <= 3 && distance <= traveled) {
        // Use the exclusive next-midnight sample as a bracket witness. A root
        // exactly on that boundary belongs to the following civil JST day.
        if (currentTime == plan.dayEndUtc &&
            (traveled - distance).abs() <= 1e-9) {
          break;
        }
        final estimateMinutes = traveled == 0
            ? 0
            : (distance / traveled * 30).round();
        final center = previousTime.add(Duration(minutes: estimateMinutes));
        DateTime? closest;
        var closestError = double.infinity;
        for (var offset = -3; offset <= 3; offset++) {
          final candidate = center.add(Duration(minutes: offset));
          if (candidate.isBefore(plan.dayStartUtc) ||
              !candidate.isBefore(plan.dayEndUtc))
            continue;
          final at = longitudesAt(candidate);
          final angle =
              (at[AstroPlanet.moon]! - at[AstroPlanet.sun]! + 360) % 360;
          final error = shortestAngle(angle, target.$1);
          if (error < closestError) {
            closestError = error;
            closest = candidate;
          }
        }
        if (closest != null) {
          events.add(
            AstrologyCalendarEvent(
              kind: AstrologyCalendarEventKind.majorLunarPhase,
              title: target.$2,
              detail: '太陽と月の黄経差を30分ごとに探索し、分単位で絞り込んだ時刻',
              startUtc: closest,
            ),
          );
        }
        break;
      }
      previousTime = currentTime;
      previous = current;
    }
    progress();
  }

  final dayApiVoid = switch (ephemeris) {
    SwissEphemerisProvider provider => provider.voidMoonForUtcDay(
      plan.dayStartUtc,
    ),
    SimpleEphemeris provider => provider.voidMoonForUtcDay(plan.dayStartUtc),
    _ => throw UnsupportedError('JST日単位の月ボイドAPIがありません。'),
  };
  final rawVoidIntervals = <_AstrologyCalendarVoidInterval>[];
  var segmentStartUtc = _astrologyCalendarMoonSegmentStart(
    ephemeris,
    plan.dayStartUtc,
  ).toUtc();
  var segmentCount = 0;
  while (segmentStartUtc.isBefore(plan.dayEndUtc)) {
    if (++segmentCount > 3) {
      throw StateError('対象日の月サイン区間を一意に確認できません。');
    }
    final segmentEndUtc = _astrologyCalendarMoonSegmentEnd(
      ephemeris,
      segmentStartUtc,
    ).toUtc();
    if (!segmentEndUtc.isAfter(segmentStartUtc)) {
      throw StateError('月サイン区間の時刻順を確認できません。');
    }
    final lastAspect = _astrologyCalendarLastMoonAspect(
      ephemeris,
      segmentStartUtc,
      segmentEndUtc,
    )?.toUtc();
    if (lastAspect != null &&
        (lastAspect.isBefore(segmentStartUtc) ||
            !lastAspect.isBefore(segmentEndUtc))) {
      throw StateError('月の最後の主要アスペクト時刻を検証できません。');
    }
    final actualStartUtc = lastAspect ?? segmentStartUtc;
    final actualEndUtc = segmentEndUtc;
    final overlapStart = actualStartUtc.isAfter(plan.dayStartUtc)
        ? actualStartUtc
        : plan.dayStartUtc;
    final overlapEnd = actualEndUtc.isBefore(plan.dayEndUtc)
        ? actualEndUtc
        : plan.dayEndUtc;
    if (overlapEnd.isAfter(overlapStart)) {
      rawVoidIntervals.add((startUtc: actualStartUtc, endUtc: actualEndUtc));
    }
    segmentStartUtc = segmentEndUtc.add(const Duration(minutes: 1));
  }
  events.addAll(
    AstrologyCalendarEvent.voidMoonIntervalsForCalendarDisplay(
      plan: plan,
      rawIntervals: rawVoidIntervals,
      dayApiResult: dayApiVoid,
    ),
  );
  progress();

  final noonPlacements = ephemeris.placementsFor(plan.primaryNoon.instantUtc);
  final validPlanets = <AstroPlanet>{};
  for (final placement in noonPlacements) {
    if (placement.planet == AstroPlanet.ascendant ||
        placement.planet == AstroPlanet.midheaven)
      continue;
    if (!placement.degree.isFinite ||
        placement.degree < 0 ||
        placement.degree >= 30 ||
        !validPlanets.add(placement.planet)) {
      throw StateError('正午の星配置が不足または不正です。');
    }
  }
  if (!validPlanets.containsAll(AstroPlanet.values.take(10))) {
    throw StateError('正午の10天体配置が不足しています。');
  }
  for (final group in FortuneScoreCalculator._grandTrineGroups(
    noonPlacements,
  )) {
    final planets = group.toList()..sort((a, b) => a.index.compareTo(b.index));
    events.add(
      AstrologyCalendarEvent(
        kind: AstrologyCalendarEventKind.specialConfiguration,
        title: 'グランドトライン（${planets.map((planet) => planet.label).join('・')}）',
        detail: '正午の星配置',
        snapshotUtc: plan.primaryNoon.instantUtc,
      ),
    );
  }
  for (final pattern in FortuneScoreCalculator._rarePatternDetails(
    noonPlacements,
  )) {
    events.add(
      AstrologyCalendarEvent(
        kind: AstrologyCalendarEventKind.specialConfiguration,
        title:
            '${pattern.label}（${pattern.planets.map((planet) => planet.label).join('・')}）',
        detail: '正午の星配置',
        snapshotUtc: plan.primaryNoon.instantUtc,
      ),
    );
  }
  progress();

  events.sort((a, b) => a.sortTimeUtc.compareTo(b.sortTimeUtc));
  if (swissFallbackCountBefore != null &&
      swissFallbackCountBefore !=
          SwissEphemerisProvider._placementFallbackCount) {
    throw StateError('Swiss計算中に簡易計算へ戻ったため、再試行してください。');
  }
  return AstrologyCalendarDay(
    targetDateJst: targetDateJst,
    events: events,
    providerName: ephemeris.sourceName,
    precisionNotice: ephemeris.precisionNotice,
    usesHighPrecisionAstroData: ephemeris.usesHighPrecisionAstroData,
    moonSignAtNoon: noonPlacements.firstWhere((placement) => placement.planet == AstroPlanet.moon).sign,
  );
}
