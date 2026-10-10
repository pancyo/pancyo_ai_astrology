part of 'main.dart';

/// Explicit artificial QA only. run() has no preferences, file, share, UI, or
/// network effects. It is intended to run in an explicitly requested isolate.
class MoonVoidBatchCheck {
  const MoonVoidBatchCheck._();

  static String _bits(double value) {
    final data = ByteData(8)..setFloat64(0, value);
    return data.getUint64(0).toRadixString(16).padLeft(16, '0');
  }

  static List<PlanetPlacement> _placements(List<double> raw) {
    final fallback = SwissEphemerisProvider._fallback;
    final first = fallback._signForLongitude(raw[0]);
    return [
      for (var index = 0; index < raw.length; index++)
        PlanetPlacement(
          planet: SwissEphemerisProvider._swissPlanets[index],
          sign: fallback._signForLongitude(raw[index]),
          degree: fallback._norm(raw[index]) % 30,
          house: fallback._wholeSignHouse(
            fallback._signForLongitude(raw[index]),
            first,
          ),
        ),
    ];
  }

  static List<Map<String, Object>> _placementData(
    List<PlanetPlacement> values,
  ) => [
    for (final value in values)
      {
        'planet': value.planet.name,
        'sign': value.sign.name,
        'degree_bits': _bits(value.degree),
        'house': value.house,
      },
  ];

  /// Pure deterministic fixture seam. It exercises the actual provider's route
  /// selection, frozen scalar error, new raw arithmetic and fallback counter.
  /// The fake native values never enter production caches or stored records.
  static Map<String, Object?> fixture({
    required bool batchAvailable,
    List<double>? batchValues,
    List<double>? scalarValues,
  }) {
    final scalar =
        scalarValues ??
        const [
          0.0,
          29.999999999999996,
          60.0,
          90.0,
          120.0,
          150.0,
          180.0,
          210.0,
          240.0,
          359.99999999999994,
        ];
    if (!SwissEphemerisLongitudeBatchContract.validLongitudes(scalar)) {
      throw ArgumentError('scalar fixture must contain ten finite longitudes');
    }
    final provider = _MoonVoidBatchFixtureProvider(
      batchAvailable,
      batchValues,
      _placements(scalar),
    );
    final before = SwissEphemerisProvider._placementFallbackCount;
    final at = DateTime.utc(2026, 10, 4, 3, 0, 0, 123, 456);
    try {
      final actual = provider._moonMajorAspectError(at);
      final scalarCalls = provider.scalarPlacementCalls;
      final batchCalls = provider.batchCalls;
      final delta = SwissEphemerisProvider._placementFallbackCount - before;
      final expectedScalar = provider._moonMajorAspectErrorScalar(at);
      final expectedFallback = SwissEphemerisProvider._fallback
          ._moonMajorAspectError(at);
      return {
        'actual_bits': _bits(actual),
        'scalar_bits': _bits(expectedScalar),
        'fallback_bits': _bits(expectedFallback),
        'scalar_placement_calls': scalarCalls,
        'batch_calls': batchCalls,
        'fallback_count_delta': delta,
      };
    } finally {
      SwissEphemerisProvider._placementFallbackCount = before;
    }
  }

  static void _resetVoidCaches() {
    SwissEphemerisProvider._voidMoonCache.clear();
    SwissEphemerisProvider._voidSegmentMemo.clear();
  }

  // Frozen pre-batch day wrapper. The existing memo QA's frozen search/refine
  // now calls _moonMajorAspectErrorScalar explicitly, never the batch method.
  static VoidMoonPeriod? _scalarUtcDay(
    SwissEphemerisProvider provider,
    DateTime dayStart,
  ) {
    final dayEnd = dayStart.add(const Duration(days: 1));
    var segmentStart = provider._moonSignSegmentStart(dayStart);
    while (segmentStart.isBefore(dayEnd)) {
      final segmentEnd = provider._moonSignSegmentEnd(segmentStart);
      final last = MoonVoidMemoCheck._legacyLast(
        provider,
        segmentStart,
        segmentEnd,
      );
      final start = last ?? segmentStart;
      final overlapStart = start.isBefore(dayStart) ? dayStart : start;
      final overlapEnd = segmentEnd.isAfter(dayEnd) ? dayEnd : segmentEnd;
      if (overlapEnd.isAfter(overlapStart.add(const Duration(minutes: 5)))) {
        return VoidMoonPeriod(
          start: SwissEphemerisProvider._fallback._timeLabel(overlapStart),
          end: SwissEphemerisProvider._fallback._timeLabel(overlapEnd),
          startTime: overlapStart,
          endTime: overlapEnd,
          guidance: '月が次の星座へ入る前の空白時間。新規決定より見直し、休息、準備向き。',
        );
      }
      segmentStart = segmentEnd.add(const Duration(minutes: 1));
    }
    return null;
  }

  static Map<String, Object?> run() {
    if (!reworkTestBuild ||
        !SwissEphemerisProvider.isAvailable ||
        !SwissEphemerisBridge.isPlanetLongitudeBatchAvailable) {
      throw StateError('人工batch比較は改修指定と対応ネイティブ計算が必要です。');
    }
    const provider = SwissEphemerisProvider();
    const profile = AstroProfile(
      name: 'YearFlowFiction',
      birthDate: '2000/1/2',
      birthTime: '12:00',
      birthPlace: '北海道札幌市',
      theme: '今日の流れ',
    );
    final dates = [
      DateTime(2026, 10, 4, 12),
      DateTime(2027, 1, 1, 12),
      DateTime(2028, 2, 29, 12),
    ];
    final originalHouse = HouseSystemSettings.current.value;
    final originalForce = SwissEphemerisProvider._forceScalarVoidForCheck;
    final beforeFallbacks = SwissEphemerisProvider._placementFallbackCount;
    var rawChecks = 0;
    var placementChecks = 0;
    var errorChecks = 0;
    var contextChecks = 0;
    var noVoidDays = 0;
    final direct = <Map<String, Object?>>[];
    final scalarJson = <String>[];
    final scalarVoids = <Map<String, Object?>?>[];
    final batchJson = <String>[];
    final batchVoids = <Map<String, Object?>?>[];
    final scalarWatch = Stopwatch();
    final batchWatch = Stopwatch();
    try {
      // These include both sides of the same frozen sign-boundary instants and
      // fractional microseconds, with no rounded cache or shifted search grid.
      final instants = <DateTime>[];
      for (final date in dates) {
        final start = provider._moonSignSegmentStart(date);
        final end = provider._moonSignSegmentEnd(start);
        instants.addAll([
          date.add(const Duration(microseconds: 123456)),
          start.subtract(const Duration(microseconds: 1)),
          start.add(const Duration(microseconds: 1)),
          end.subtract(const Duration(microseconds: 1)),
          end.add(const Duration(microseconds: 1)),
        ]);
      }
      for (var index = 0; index < instants.length; index++) {
        final at = instants[index];
        final scalar = provider._longitudesFor(at);
        final batch = provider._voidBatchLongitudesFor(at);
        if (scalar == null ||
            !SwissEphemerisLongitudeBatchContract.validLongitudes(batch)) {
          throw StateError('人工配置比較のnative欠損（$index）');
        }
        for (var planet = 0; planet < 10; planet++) {
          if (_bits(scalar[SwissEphemerisProvider._swissPlanets[planet]]!) !=
              _bits(batch![planet])) {
            throw StateError('旧scalar/batchのlongitude bit不一致（$index/$planet）');
          }
          rawChecks++;
        }
        if (jsonEncode(_placementData(provider.placementsFor(at))) !=
            jsonEncode(_placementData(_placements(batch!)))) {
          throw StateError('全惑星のsign/degree/house不一致（$index）');
        }
        placementChecks += 10;
        final oldError = provider._moonMajorAspectErrorScalar(at);
        final newError = provider._moonMajorAspectError(at);
        if (_bits(oldError) != _bits(newError)) {
          throw StateError('主要aspect error bit不一致（$index）');
        }
        errorChecks++;
        direct.add({'fixture_index': index, 'error_bits': _bits(newError)});
      }
      // Both routes start with empty Dart void day/segment caches. Swiss's own
      // internal native cache is not reset; these times are not a cold benchmark.
      _resetVoidCaches();
      SwissEphemerisProvider._forceScalarVoidForCheck = true;
      scalarWatch.start();
      for (final date in dates) {
        final value = MoonVoidMemoCheck._legacyVoid(provider, date);
        scalarVoids.add(MoonVoidMemoCheck._voidData(value));
        final key = '${date.year}-${date.month}-${date.day}';
        SwissEphemerisProvider._voidMoonCache[key] = value;
        for (final house in HouseSystem.values) {
          HouseSystemSettings.current.value = house;
          final context = const AstrologyEngine().buildPreviewContext(
            profile: profile,
            date: date,
          );
          if (!context.usesHighPrecisionAstroData) {
            throw StateError('旧人工contextが近似へ切替');
          }
          scalarJson.add(
            jsonEncode(
              DailyAstroDataExportCard(
                date: date,
                profile: profile,
                details: const UserProfileDetails.empty(),
                contextData: context,
              ).buildData(generatedAt: DateTime.utc(2026, 10, 1, 3)),
            ),
          );
        }
      }
      scalarWatch.stop();
      _resetVoidCaches();
      SwissEphemerisProvider._forceScalarVoidForCheck = false;
      batchWatch.start();
      for (final date in dates) {
        final value = provider.voidMoonFor(date);
        batchVoids.add(MoonVoidMemoCheck._voidData(value));
        if (value == null) noVoidDays++;
        for (final house in HouseSystem.values) {
          HouseSystemSettings.current.value = house;
          final context = const AstrologyEngine().buildPreviewContext(
            profile: profile,
            date: date,
          );
          if (!context.usesHighPrecisionAstroData) {
            throw StateError('新人工contextが近似へ切替');
          }
          batchJson.add(
            jsonEncode(
              DailyAstroDataExportCard(
                date: date,
                profile: profile,
                details: const UserProfileDetails.empty(),
                contextData: context,
              ).buildData(generatedAt: DateTime.utc(2026, 10, 1, 3)),
            ),
          );
        }
      }
      batchWatch.stop();
      if (jsonEncode(scalarVoids) != jsonEncode(batchVoids)) {
        throw StateError('日ボイドnull/開始終了microsecond/表示文不一致');
      }
      for (var index = 0; index < scalarJson.length; index++) {
        if (scalarJson[index] != batchJson[index]) {
          throw StateError('全日JSON/点数/根拠/正規体感不一致（$index）');
        }
        contextChecks++;
      }
      // Explicit JST reference day represented as UTC, separate from local date.
      final utcStart = DateTime.utc(2028, 2, 28, 15);
      _resetVoidCaches();
      final oldUtc = _scalarUtcDay(provider, utcStart);
      _resetVoidCaches();
      final newUtc = provider.voidMoonForUtcDay(utcStart);
      if (jsonEncode(MoonVoidMemoCheck._voidData(oldUtc)) !=
          jsonEncode(MoonVoidMemoCheck._voidData(newUtc))) {
        throw StateError('UTC表現のJST日ボイド不一致');
      }
      if (SwissEphemerisProvider._placementFallbackCount != beforeFallbacks) {
        throw StateError('人工native比較で近似fallback発生');
      }
      return {
        'schema': 'pancyo_moon_void_batch_native_check_v1',
        'passed': true,
        'fiction_only': true,
        'batch_abi_version': SwissEphemerisLongitudeBatchContract.version,
        'local_day_count': dates.length,
        'utc_jst_day_checks': 1,
        'no_void_local_days': noVoidDays,
        'instant_count': instants.length,
        'raw_longitude_bit_checks': rawChecks,
        'placement_field_checks': placementChecks,
        'major_aspect_error_bit_checks': errorChecks,
        'full_daily_json_checks': contextChecks,
        'house_system_count': HouseSystem.values.length,
        'source': provider.sourceName,
        'precision_notice': provider.precisionNotice,
        'model_version': NineAreaDailyForecast.modelVersion,
        'scalar_route_us': scalarWatch.elapsedMicroseconds,
        'batch_route_us': batchWatch.elapsedMicroseconds,
        'dart_void_caches_reset_between_routes': true,
        'native_internal_cache_reset': false,
        'timing_is_cold_benchmark': false,
        'placement_fallbacks': 0,
        'direct_checks': direct,
        'void_days': batchVoids,
        'daily_json_sha256': [
          for (final value in batchJson)
            sha256.convert(utf8.encode(value)).toString(),
        ],
      };
    } finally {
      scalarWatch.stop();
      batchWatch.stop();
      HouseSystemSettings.current.value = originalHouse;
      SwissEphemerisProvider._forceScalarVoidForCheck = originalForce;
      _resetVoidCaches();
    }
  }
}

class _MoonVoidBatchFixtureProvider extends SwissEphemerisProvider {
  _MoonVoidBatchFixtureProvider(this.available, this.values, this.scalar);

  final bool available;
  final List<double>? values;
  final List<PlanetPlacement> scalar;
  int scalarPlacementCalls = 0;
  int batchCalls = 0;

  @override
  bool get _usesVoidLongitudeBatch => available;

  @override
  List<double>? _voidBatchLongitudesFor(DateTime time) {
    batchCalls++;
    return values;
  }

  @override
  List<PlanetPlacement> placementsFor(
    DateTime date, {
    GeoPoint? place,
    ZodiacSign? firstHouseSign,
    HouseFrame? houseFrame,
  }) {
    scalarPlacementCalls++;
    return scalar;
  }
}
