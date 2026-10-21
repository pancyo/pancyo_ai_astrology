import '../main.dart' as app;
import '../swiss_ephemeris_bridge.dart';
import '../swiss_ephemeris_time.dart';
import 'felt_forecast_candidate.dart';
import 'nine_area_score_audit.dart';

/// 人工データだけを使い、ネイティブ星計算を近似計算で代用しない確認。
/// 保存プロフィール・本人の記録は読み書きせず、返す値にも含めない。
class NativeSmokeCheck {
  const NativeSmokeCheck._();

  static void _require(bool condition, String message) {
    if (!condition) throw StateError(message);
  }

  static double _finite(double? value, String message) {
    _require(value != null && value.isFinite, message);
    return value!;
  }

  static double _julian(DateTime instant) {
    final args = SwissEphemerisUtcArguments.fromInstant(instant);
    return _finite(
      SwissEphemerisBridge.julianDayUtc(
        args.year,
        args.month,
        args.day,
        args.hour,
      ),
      'ネイティブUTC時刻の計算に失敗',
    );
  }

  static Map<String, Object?> reference() {
    _require(SwissEphemerisBridge.isAvailable, '同梱ネイティブライブラリを読み込めない');
    final julian = _finite(
      SwissEphemerisBridge.julianDayUtc(2000, 1, 1, 12),
      'J2000計算に失敗',
    );
    _require((julian - 2451545.0).abs() < 1e-9, 'J2000ユリウス日が不一致');
    for (var planet = 0; planet < 10; planet++) {
      final longitude = _finite(
        SwissEphemerisBridge.planetLongitudeUtc(julian, planet),
        '10天体の計算に失敗',
      );
      _require(longitude >= 0 && longitude < 360, '天体黄経が範囲外');
    }
    _require(
      SwissEphemerisBridge.planetLongitudeUtc(julian, -1) == null,
      '不正天体番号を受理',
    );
    _require(
      SwissEphemerisBridge.planetLongitudeUtc(julian, 10) == null,
      '不正天体番号を受理',
    );
    return {
      'name': 'j2000_ten_planets',
      'passed': true,
      'julian_day': julian,
      'planet_count': 10,
    };
  }

  static Map<String, Object?> sameInstant() {
    _require(SwissEphemerisBridge.isAvailable, '同梱ネイティブライブラリを読み込めない');
    final instant = DateTime.utc(2026, 10, 1, 3);
    const provider = app.SwissEphemerisProvider();
    final utc = provider.placementsFor(instant);
    final local = provider.placementsFor(instant.toLocal());
    _require(utc.length == 10 && local.length == 10, '天体数が不一致');
    var largestDifference = 0.0;
    for (var index = 0; index < utc.length; index++) {
      final direct = _finite(
        SwissEphemerisBridge.planetLongitudeUtc(
          _julian(instant),
          utc[index].planet.index,
        ),
        '直接FFI計算に失敗',
      );
      final difference =
          (utc[index].sign.index * 30 + utc[index].degree - direct).abs();
      _require(
        utc[index].planet == local[index].planet &&
            utc[index].sign == local[index].sign,
        '同一瞬間の天体・星座が不一致',
      );
      _require(
        (utc[index].degree - local[index].degree).abs() < 1e-9 &&
            difference < 1e-9,
        '同一瞬間・直接FFIの黄経が不一致',
      );
      if (difference > largestDifference) largestDifference = difference;
    }
    return {
      'name': 'same_instant_utc_local_direct',
      'passed': true,
      'maximum_direct_difference': largestDifference,
    };
  }

  static Map<String, Object?> houses() {
    _require(SwissEphemerisBridge.isAvailable, '同梱ネイティブライブラリを読み込めない');
    const provider = app.SwissEphemerisProvider();
    const place = app.GeoPoint(
      label: '架空テスト地点',
      latitude: 35.68,
      longitude: 139.76,
    );
    var frameCount = 0;
    for (final instant in [
      DateTime.utc(2026, 9, 30, 14, 59),
      DateTime.utc(2026, 9, 30, 15),
    ]) {
      for (final system in app.HouseSystem.values) {
        final frame = provider.houseFrameFor(instant, place, system);
        _require(
          frame.system == system && frame.cusps.length == 12,
          'ハウス方式・カスプ数が不一致',
        );
        for (final cusp in frame.cusps) {
          _require(cusp.isFinite && cusp >= 0 && cusp < 360, 'ハウスカスプが範囲外');
        }
        final directAscendant = _finite(
          SwissEphemerisBridge.ascendantUtc(
            _julian(instant),
            place.latitude,
            place.longitude,
          ),
          'ネイティブASC計算に失敗',
        );
        for (var index = 0; index < 12; index++) {
          final expected = system == app.HouseSystem.wholeSign
              ? ((directAscendant / 30).floor() * 30 + index * 30) % 360
              : _finite(
                  SwissEphemerisBridge.houseCuspUtc(
                    _julian(instant),
                    place.latitude,
                    place.longitude,
                    index + 1,
                    1,
                  ),
                  'ネイティブカスプ計算に失敗',
                );
          _require(
            (frame.cusps[index] - expected).abs() < 1e-8,
            'ハウスカスプがネイティブ計算と不一致',
          );
        }
        final placements = provider.placementsFor(
          instant,
          place: place,
          houseFrame: frame,
        );
        _require(placements.length == 12, 'ASC/MCを含む配置数が不一致');
        final ascendant = placements.singleWhere(
          (item) => item.planet == app.AstroPlanet.ascendant,
        );
        _require(
          (ascendant.sign.index * 30 + ascendant.degree - directAscendant)
                  .abs() <
              1e-8,
          '配置のASCがネイティブ計算と不一致',
        );
        for (final item in placements) {
          _require(item.house >= 1 && item.house <= 12, 'ハウス番号が範囲外');
        }
        frameCount++;
      }
    }
    return {
      'name': 'houses_at_jst_boundary',
      'passed': true,
      'frame_count': frameCount,
    };
  }

  static Map<String, Object?> forecast() {
    _require(SwissEphemerisBridge.isAvailable, '同梱ネイティブライブラリを読み込めない');
    const profile = app.AstroProfile(
      name: '架空のネイティブ確認',
      birthDate: '1990/1/2',
      birthTime: '08:30',
      birthPlace: '東京都',
      theme: '今日の流れ',
    );
    final target = DateTime.utc(2030, 1, 1, 3);
    final context = const app.AstrologyEngine().buildPreviewContext(
      profile: profile,
      date: target,
    );
    _require(context.usesHighPrecisionAstroData, '近似計算へ切り替わっている');
    final predictions = app.NineAreaDailyForecast.fromContext(context);
    final data = app.NineAreaForecastSnapshot.build(
      targetDate: target,
      generatedAt: DateTime.utc(2026, 9, 30, 3),
      predictions: predictions,
      houseSystem: context.houseSystem.name,
      usesHighPrecisionAstroData: context.usesHighPrecisionAstroData,
    );
    _require(
      data['uses_high_precision_astro_data'] == true && predictions.length == 9,
      '予測の精度区分・項目数が不一致',
    );
    for (final prediction in predictions.take(8)) {
      NineAreaScoreAudit.validate(
        prediction.scoreBreakdown!,
        prediction.score!,
      );
    }
    final felt = predictions.last.feltForecast!;
    _require(felt.label != null, '人工データの体感候補が未予測');
    FeltForecastCandidate.validateSnapshot(felt.trace, felt.label);
    return {
      'name': 'nine_area_forecast_audit',
      'passed': true,
      'uses_high_precision_astro_data': true,
      'numeric_area_count': 8,
      'felt_candidate_available': true,
      'model_version': data['model_version'],
    };
  }

  static Map<String, Object?> dailyConsult() {
    _require(SwissEphemerisBridge.isAvailable, '同梱ネイティブライブラリを読み込めない');
    const profile = app.AstroProfile(
      name: '架空の相談JSON確認',
      birthDate: '1990/1/2',
      birthTime: '08:30',
      birthPlace: '東京都',
      theme: '今日の流れ',
    );
    final date = DateTime.utc(2026, 9, 21, 3);
    final context = const app.AstrologyEngine().buildPreviewContext(
      profile: profile,
      date: date,
    );
    _require(context.usesHighPrecisionAstroData, '近似計算へ切り替わっている');
    final data = app.DailyAstroDataExportCard(
      date: date,
      profile: profile,
      details: const app.UserProfileDetails.empty(),
      contextData: context,
    ).buildData(generatedAt: DateTime.utc(2026, 9, 30, 3));
    final nine = data['nine_area_daily'] as Map;
    final birthQuality = data['birth_input_quality'] as Map;
    _require(
      (birthQuality['ephemeris'] as Map)['uses_high_precision_astro_data'] == true &&
          birthQuality['birth_facts_verified_by_exporter'] == false &&
          (birthQuality['birth_time'] as Map)['source'] == 'unverified_profile_value',
      '高精度計算と出生入力の確認状態が混同されている',
    );
    final areas = nine['areas'] as List;
    final predictions = app.NineAreaDailyForecast.fromContext(context);
    _require(
      areas.length == 9 && nine['uses_high_precision_astro_data'] == true,
      '相談JSONの項目数・精度が不一致',
    );
    for (var i = 0; i < 9; i++) {
      final area = areas[i] as Map;
      _require(
        area['score'] == predictions[i].score &&
            area['display_reading'] == predictions[i].reading,
        '画面と相談JSONが不一致',
      );
    }
    _require(
      (areas.last as Map)['predicted_felt_label'] ==
          predictions.last.feltForecast!.label,
      '体感ラベルが不一致',
    );
    _require(
      (data['fortune_scores'] as Map)['mental'] ==
          app.FortuneScoreCalculator.dailyArea(
            context,
            app.FortuneArea.mental,
            app.FortuneScoreCalculator.standardBase(app.FortuneArea.mental),
          ),
      '従来の心身点が変わっている',
    );
    // 保存・復元の形を人工データだけで往復する。端末の保存領域には書かない。
    final saved = app.SavedUserProfile.fromProfile(
      profile.copyWith(birthTime: '12:00', birthPlace: '北海道札幌市'),
      const app.UserProfileDetails.empty(),
    );
    final reloaded = app.SavedUserProfile.fromJson(saved.toJson());
    _require(
      reloaded.details.birthTime.isEmpty && reloaded.details.birthPlace.isEmpty,
      '未入力の出生条件が保存時に仮値で埋められている',
    );
    final assumedProfile = profile.copyWith(
      birthTime: reloaded.details.effectiveBirthTime,
      birthPlace: reloaded.details.effectiveBirthPlace,
    );
    final assumedContext = const app.AstrologyEngine().buildPreviewContext(
      profile: assumedProfile, date: date,
    );
    _require(assumedContext.usesHighPrecisionAstroData, '仮条件の確認が近似計算へ切り替わっている');
    final assumedData = app.DailyAstroDataExportCard(
      date: date, profile: assumedProfile, details: reloaded.details,
      contextData: assumedContext,
    ).buildData();
    final assumedQuality = assumedData['birth_input_quality'] as Map;
    _require(
      (assumedQuality['birth_time'] as Map)['source'] == 'assumed_default' &&
          (assumedQuality['birth_place'] as Map)['source'] == 'assumed_default',
      '保存往復後の仮出生条件を相談JSONで区別できない',
    );
    return {
      'name': 'nine_area_daily_consult_audit',
      'birth_input_quality_checked': true,
      'unset_birth_roundtrip_checked': true,
      'passed': true,
      'uses_high_precision_astro_data': true,
      'area_count': areas.length,
      'model_version': nine['model_version'],
    };
  }

  static List<Map<String, Object?>> runAll() => [
    reference(),
    sameInstant(),
    houses(),
    forecast(),
    dailyConsult(),
  ];
}
