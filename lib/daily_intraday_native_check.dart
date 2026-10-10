part of 'main.dart';

/// Explicit artificial integration QA. No profile/settings persistence or share.
class DailyIntradayNativeCheck {
  const DailyIntradayNativeCheck._();
  static const checkId = 'daily-v4-20261002-native-1';
  static const enabled = reworkTestBuild &&
      bool.fromEnvironment('PANCYO_DAILY_INTRADAY_NATIVE_CHECK');
  static const fixture = AstroProfile(name: 'ReworkDailyIntradayFixture',
    birthDate: '1990/1/2', birthTime: '08:30', birthPlace: '東京都', theme: '仕事');
  static final target = DateTime.utc(2026, 10, 2, 3);
  static final issued = DateTime.utc(2026, 10, 2, 7);

  static bool validCacheRoot(String root) => RegExp(
    r'^/data/(user/0|data)/com\.pancyo\.aiastrology\.rework/cache$').hasMatch(root);
  static bool validEvidenceRoot(String root) => RegExp(
    r'^/data/(user/0|data)/com\.pancyo\.aiastrology\.rework/cache/pancyo_daily_intraday_qa_[^/]+$').hasMatch(root);

  static void _require(bool condition) {
    if (!condition) throw StateError('Artificial daily native evidence is incomplete or inconsistent.');
  }

  /// Validates serialized data, not independent astronomical accuracy.
  static Map<String, Object?> validateData(Map<String, Object?> data, HouseSystem house) {
    final plan = DailySevenTimepointPlan.forJstDate('2026-10-02');
    final profile = data['profile'] as Map;
    final emptyDetails = const UserProfileDetails.empty();
    _require(profile['name'] == fixture.name && profile['birth_date'] == fixture.birthDate &&
      profile['birth_time'] == fixture.birthTime && profile['birth_place'] == fixture.birthPlace &&
      profile['theme'] == fixture.theme && profile['concerns'] == emptyDetails.concerns &&
      profile['reading_style'] == emptyDetails.readingStyle && data['generated_at'] == issued.toIso8601String() &&
      data['date_time_jst'] == '2026-10-02 12:00:00+09:00' && data['timezone'] == 'Asia/Tokyo' &&
      (data['house_calculation'] as Map)['house_system'] == house.name);
    final positions = data['intraday_positions'] as Map;
    final forecasts = data['intraday_forecasts'] as Map;
    final positionPoints = positions['points'] as List;
    final forecastPoints = forecasts['points'] as List;
    final houseInfo = positions['house_calculation'] as Map;
    _require(data['schema'] == 'pancyo_astrology_daily_consult_v4' &&
      positions['schema'] == 'pancyo_daily_intraday_positions_v1' &&
      forecasts['schema'] == 'pancyo_daily_intraday_forecasts_v1' &&
      positions['target_date_jst'] == plan.targetDateJst &&
      forecasts['target_date_jst'] == plan.targetDateJst &&
      houseInfo['requested_system'] == house.name && houseInfo['resolved_system'] == house.name &&
      (positions['calculation_source'] as Map)['provider'] == const SwissEphemerisProvider().sourceName &&
      (positions['calculation_source'] as Map)['provider_uses_high_precision'] == true &&
      (positions['completeness'] as Map)['status'] == 'complete' &&
      (forecasts['completeness'] as Map)['status'] == 'complete' &&
      (positions['completeness'] as Map)['point_count'] == 7 &&
      (positions['completeness'] as Map)['required_planets_per_point'] == 10 &&
      (forecasts['completeness'] as Map)['point_count'] == 7 &&
      (forecasts['completeness'] as Map)['areas_per_point'] == 9 &&
      positionPoints.length == 7 && forecastPoints.length == 7 &&
      forecasts['model_version'] == NineAreaDailyForecast.modelVersion &&
      forecasts['daily_scores_averaged_from_samples'] == false &&
      forecasts['felt_has_numeric_score'] == false && forecasts['daily_primary_reference_count'] == 1 &&
      forecasts['independent_astronomical_accuracy_verified'] == false &&
      forecasts['exact_optimal_time_search_complete'] == false);
    final cusps = [for (final value in houseInfo['natal_cusps_longitude'] as List) (value as num).toDouble()];
    _timelineValidateCusps(cusps);
    final houseFrame = HouseFrame(system: house, cusps: cusps);
    final interval = positions['day_interval'] as Map;
    _require(interval['start_utc'] == plan.dayStartUtc.toIso8601String() &&
      interval['end_utc'] == plan.dayEndUtc.toIso8601String() &&
      interval['start_inclusive'] == true && interval['end_inclusive'] == false);
    var numericCount = 0, feltCount = 0;
    for (var i = 0; i < 7; i++) {
      final point = forecastPoints[i] as Map, position = positionPoints[i] as Map;
      final clock = plan.points[i];
      for (final entry in clock.toJson().entries) {
        _require(point[entry.key] == entry.value && position[entry.key] == entry.value);
      }
      final dayStart = i == 6 ? plan.dayEndUtc : plan.dayStartUtc;
      _require(point['score_day_start_utc'] == dayStart.toIso8601String() &&
        point['score_day_end_utc'] == dayStart.add(const Duration(days: 1)).toIso8601String());
      final placements = position['placements'] as List;
      final planets = <String>{};
      _require(placements.length == 10);
      for (final raw in placements) {
        final placement = raw as Map;
        final planet = placement['planet'];
        final sign = placement['sign'];
        final degree = placement['degree'], longitude = placement['longitude'], number = placement['house'];
        _require(planet is String && AstroPlanet.values.take(10).any((p) => p.name == planet) &&
          sign is String && ZodiacSign.values.any((s) => s.name == sign) &&
          planets.add(planet) && degree is num && degree.isFinite && degree >= 0 && degree < 30 &&
          longitude is num && longitude.isFinite && longitude >= 0 && longitude < 360 &&
          number is int && number >= 1 && number <= 12);
        _require((ZodiacSign.values.byName(sign as String).index * 30.0 + (degree as num) - (longitude as num)).abs() < 1e-7 &&
          houseFrame.houseForLongitude(longitude.toDouble()) == number);
      }
      final forecast = point['nine_area_forecast'] as Map;
      final expectedDate = i == 6 ? '2026-10-03' : '2026-10-02';
      _require(forecast['target_date_jst'] == expectedDate && forecast['house_system'] == house.name &&
        forecast['uses_high_precision_astro_data'] == true &&
        forecast['model_version'] == NineAreaDailyForecast.modelVersion &&
        forecast['calculation_reference_jst'] == clock.instantJst);
      final areas = forecast['areas'] as List;
      _require(areas.length == 9);
      final seen = <String>{};
      for (final raw in areas) {
        final area = raw as Map;
        final key = area['key'];
        _require(key is String && NineAreaKey.values.any((k) => k.name == key) && seen.add(key));
        if (key == NineAreaKey.felt.name) {
          _require(area['score'] == null && !area.containsKey('score_breakdown'));
          FeltForecastCandidate.validateSnapshot(Map<String, Object?>.from(area['felt_prediction'] as Map),
            area['predicted_felt_label'] as String?);
          feltCount++;
        } else {
          _require(area['score'] is int);
          NineAreaScoreAudit.validate(Map<String, dynamic>.from(area['score_breakdown'] as Map), area['score'] as int);
          numericCount++;
        }
      }
    }
    _require(jsonEncode((forecastPoints[3] as Map)['nine_area_forecast']) == jsonEncode(data['nine_area_daily']));
    return {'point_count': 7, 'numeric_audits': numericCount, 'felt_audits': feltCount,
      'noon_preserved': true, 'boundary_preserved': true};
  }

  static String v3Digest(Map<String, Object?> data) {
    final baseline = Map<String, Object?>.from(data)..remove('intraday_forecasts');
    baseline['schema'] = 'pancyo_astrology_daily_consult_v3';
    return sha256.convert(utf8.encode(jsonEncode(baseline))).toString();
  }

  static Map<String, Object?> validateRows(List<Map<String, Object?>> rows) {
    _require(rows.length == 2);
    for (var i = 0; i < 2; i++) {
      final row = rows[i];
      _require(row['house_system'] == [HouseSystem.placidus, HouseSystem.wholeSign][i].name &&
        row['check_id'] == checkId && row['fixture_only'] == true &&
        row['fresh_isolate'] == true && row['high_precision'] == true && row['placement_fallbacks'] == 0 &&
        row['point_count'] == 7 && row['numeric_audits'] == 56 && row['felt_audits'] == 7 &&
        row['noon_preserved'] == true && row['boundary_preserved'] == true && row['v3_preserved'] == true &&
        row['read_back_matches'] == true && row['bytes'] is int && (row['bytes'] as int) > 0);
      for (final key in ['sha256', 'v3_sha256']) {
        _require(row[key] is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(row[key] as String));
      }
      for (final key in ['context_us', 'data_us', 'validation_us', 'write_us']) {
        _require(row[key] is int && (row[key] as int) >= 0);
      }
    }
    return {'passed': true, 'check_id': checkId, 'house_systems': 2,
      'point_count': 14, 'numeric_audits': 112, 'felt_audits': 14,
      'independent_astronomical_accuracy_verified': false};
  }

  /// Must run in a new isolate. The input cannot accept a saved profile.
  static Future<Map<String, Object?>> runOne({required HouseSystem house,
      required String temporaryRoot}) async {
    _require(enabled && Platform.isAndroid && SwissEphemerisProvider.isAvailable);
    final root = await Directory(temporaryRoot).resolveSymbolicLinks();
    _require(validEvidenceRoot(root));
    _require(AstrologyEngine._natalCache.isEmpty && SwissEphemerisProvider._voidMoonCache.isEmpty &&
      SwissEphemerisProvider._ingressCache.isEmpty && SwissEphemerisProvider._voidSegmentMemo.length == 0 &&
      SwissEphemerisProvider._placementFallbackCount == 0 && target.toLocal().timeZoneOffset == const Duration(hours: 9));
    final original = HouseSystemSettings.current.value;
    HouseSystemSettings.current.value = house; // Child isolate only; no save/restore.
    try {
      final contextWatch = Stopwatch()..start();
      final context = const AstrologyEngine().buildPreviewContext(profile: fixture, date: target);
      contextWatch.stop();
      _require(context.usesHighPrecisionAstroData && context.houseSystem == house);
      final request = DailyConsultExportRequest(date: target, profile: fixture,
        details: const UserProfileDetails.empty(), contextData: context,
        requestedHouseSystem: house, sourceName: context.ephemerisSourceName,
        requireHighPrecision: true, generatedAt: issued);
      final dataWatch = Stopwatch()..start();
      final data = buildDailyConsultDataV4(request);
      dataWatch.stop();
      final validationWatch = Stopwatch()..start();
      final evidence = validateData(data, house);
      final v3 = buildDailyConsultDataV3(request);
      _require(v3Digest(data) == sha256.convert(utf8.encode(jsonEncode(v3))).toString());
      _require(SwissEphemerisProvider._placementFallbackCount == 0);
      validationWatch.stop();
      final writeWatch = Stopwatch()..start();
      final file = await ConsultJsonFileWriter.write(temporaryRoot: Directory(root),
        data: data, participantName: fixture.name, kind: 'daily', period: '20261002', generatedAt: issued);
      final bytes = await file.readAsBytes();
      final readBack = Map<String, Object?>.from(jsonDecode(utf8.decode(bytes)) as Map);
      _require(jsonEncode(readBack) == jsonEncode(data));
      validateData(readBack, house);
      writeWatch.stop();
      return {'check_id': checkId, 'house_system': house.name, 'fixture_only': true,
        'fresh_isolate': true, 'high_precision': true, 'placement_fallbacks': 0,
        ...evidence, 'v3_preserved': true, 'read_back_matches': true,
        'context_us': contextWatch.elapsedMicroseconds, 'data_us': dataWatch.elapsedMicroseconds,
        'validation_us': validationWatch.elapsedMicroseconds, 'write_us': writeWatch.elapsedMicroseconds,
        'bytes': bytes.length, 'sha256': sha256.convert(bytes).toString(), 'v3_sha256': v3Digest(data),
        'file_path': file.path}; // Private cache manifest only, never stdout.
    } finally {
      HouseSystemSettings.current.value = original;
    }
  }

  /// Same check/input/source only. Digest and data validation are required anew.
  static Future<Map<String, Object?>?> readCompleted(String cacheRoot) async {
    try {
      _require(enabled && Platform.isAndroid && SwissEphemerisProvider.isAvailable);
      final root = await Directory(cacheRoot).resolveSymbolicLinks();
      _require(validCacheRoot(root));
      final manifest = File('$root/pancyo_daily_intraday_qa_completed.json');
      if (!await manifest.exists()) return null;
      _require(await manifest.resolveSymbolicLinks() == manifest.path);
      final data = jsonDecode(await manifest.readAsString()) as Map;
      _require(data['status'] == 'complete' && data['check_id'] == checkId);
      final rows = [for (final raw in data['rows'] as List) Map<String, Object?>.from(raw as Map)];
      final result = validateRows(rows);
      for (final row in rows) {
        final path = row['file_path'];
        _require(path is String && path.startsWith('$root/pancyo_daily_intraday_qa_'));
        final file = File(path as String);
        final resolved = await file.resolveSymbolicLinks();
        _require(resolved == path && resolved.startsWith('$root/pancyo_daily_intraday_qa_'));
        final bytes = await file.readAsBytes();
        _require(bytes.length == row['bytes'] && sha256.convert(bytes).toString() == row['sha256']);
        final contents = Map<String, Object?>.from(jsonDecode(utf8.decode(bytes)) as Map);
        validateData(contents, HouseSystem.values.byName(row['house_system'] as String));
        _require(v3Digest(contents) == row['v3_sha256']);
      }
      return {...result, 'cached_evidence_revalidated': true};
    } catch (_) {
      return null; // Incomplete/invalid evidence cannot suppress a retry.
    }
  }
}
