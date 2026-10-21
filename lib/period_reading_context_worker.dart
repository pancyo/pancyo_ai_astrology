part of 'main.dart';

/// One selected period only. The seven-year chart and JSON keep their own jobs.
class PeriodReadingContextRequest {
  PeriodReadingContextRequest({
    required this.mode,
    required this.weekStart,
    required this.month,
    required this.year,
    required this.profile,
    required this.houseSystem,
  }) : sourceName = AstrologyDataSources.current.sourceName,
       usesHighPrecision =
           AstrologyDataSources.current.usesHighPrecisionAstroData,
       scalarVoid = SwissEphemerisProvider._forceScalarVoidForCheck;

  final LongRangeMode mode;
  final DateTime weekStart, month;
  final int year;
  final AstroProfile profile;
  final HouseSystem houseSystem;
  final String sourceName;
  final bool usesHighPrecision, scalarVoid;

  static Object profileIdentity(AstroProfile p) => (
    p.name,
    p.birthDate,
    p.birthClock?.cacheIdentity,
    p.birthTime,
    p.birthPlace,
    p.theme,
    p.savedProfileId,
  );

  Object get inputIdentity => (
    profileIdentity(profile),
    houseSystem,
    sourceName,
    usesHighPrecision,
    scalarVoid,
    NineAreaDailyForecast.modelVersion,
    NineAreaPeriodSummary.generalModelVersion,
  );

  DateTime get reference => switch (mode) {
    LongRangeMode.week => DateTime(
      weekStart.year,
      weekStart.month,
      weekStart.day,
      12,
    ),
    LongRangeMode.month => DateTime(month.year, month.month, 1, 12),
    LongRangeMode.year => DateTime(year, 1, 1, 12),
  };

  /// Preserve the old local-noon card samples AND UTC03 summary samples.
  /// Deduplicate actual instants, never calendar labels or a fixed TZ offset.
  List<DateTime> get dates {
    final dates = <DateTime, DateTime>{};
    void add(DateTime date) => dates.putIfAbsent(date.toUtc(), () => date);
    add(reference);
    if (mode == LongRangeMode.year) {
      for (var m = 1; m <= 12; m++) add(DateTime(year, m, 1, 12));
      for (var m = 1; m <= 12; m++) add(DateTime(year, m, 15, 12));
    } else if (mode == LongRangeMode.month) {
      // Same expression as the old month cards, including local DST semantics.
      final days = DateTime(
        month.year,
        month.month + 1,
      ).difference(DateTime(month.year, month.month)).inDays;
      final samples = <int>{1, 8, 15, 22, days}.toList()..sort();
      for (final day in samples)
        add(DateTime(month.year, month.month, day, 12));
    }
    for (final date in NineAreaPeriodSummary.sampleDates(
      mode,
      month,
      year,
      weekStart: mode == LongRangeMode.week ? weekStart : null,
    )) {
      add(date);
    }
    return List.unmodifiable(dates.values);
  }

  List<AstroPlanet> get signPlanets => switch (mode) {
    LongRangeMode.week => const [],
    LongRangeMode.month => const [
      AstroPlanet.venus,
      AstroPlanet.mercury,
      AstroPlanet.sun,
      AstroPlanet.moon,
      AstroPlanet.jupiter,
    ],
    LongRangeMode.year => const [
      AstroPlanet.venus,
      AstroPlanet.moon,
      AstroPlanet.jupiter,
      AstroPlanet.saturn,
    ],
  };

  String get identity => sha256
      .convert(
        utf8.encode(
          jsonEncode([
            mode.name,
            reference.toUtc().toIso8601String(),
            profile.name,
            profile.birthDate,
            profile.birthClock?.cacheIdentity,
            profile.birthTime,
            profile.birthPlace,
            profile.theme,
            profile.savedProfileId,
            houseSystem.name,
            sourceName,
            usesHighPrecision,
            scalarVoid,
            NineAreaDailyForecast.modelVersion,
            NineAreaPeriodSummary.generalModelVersion,
            dates.map((d) => d.toUtc().toIso8601String()).toList(),
          ]),
        ),
      )
      .toString();
}

class PeriodReadingContextResult {
  PeriodReadingContextResult({
    required this.requestIdentity,
    required this.requestedHouseSystem,
    required this.resolvedHouseSystem,
    required List<double> houseCusps,
    required Map<DateTime, HoroscopeReadingContext> contexts,
    required Map<AstroPlanet, String> signs,
    required this.elapsedMilliseconds,
    required this.workerName,
  }) : contexts = Map.unmodifiable(contexts),
       signs = Map.unmodifiable(signs),
       houseCusps = List.unmodifiable(houseCusps);
  final String requestIdentity;
  final HouseSystem requestedHouseSystem, resolvedHouseSystem;
  final List<double> houseCusps;
  final Map<DateTime, HoroscopeReadingContext> contexts;
  final Map<AstroPlanet, String> signs;
  final int elapsedMilliseconds;
  final String? workerName;

  bool matches(PeriodReadingContextRequest request) {
    final dates = request.dates;
    return requestIdentity == request.identity &&
        requestedHouseSystem == request.houseSystem &&
        // Existing Simple/Swiss cusp fallback may resolve Placidus to WholeSign.
        (requestedHouseSystem == HouseSystem.placidus ||
            resolvedHouseSystem == HouseSystem.wholeSign) &&
        houseCusps.length == 12 &&
        houseCusps.every((v) => v.isFinite) &&
        contexts.length == dates.length &&
        signs.length == request.signPlanets.length &&
        request.signPlanets.every((p) => signs[p]?.isNotEmpty == true) &&
        dates.every((date) {
          final c = contexts[date.toUtc()];
          return c != null &&
              c.transit.date.toUtc() == date.toUtc() &&
              c.houseSystem == resolvedHouseSystem &&
              c.houseCusps.length == houseCusps.length &&
              List.generate(
                houseCusps.length,
                (i) => c.houseCusps[i] == houseCusps[i],
              ).every((v) => v) &&
              PeriodReadingContextRequest.profileIdentity(c.natal.profile) ==
                  PeriodReadingContextRequest.profileIdentity(
                    request.profile,
                  ) &&
              c.ephemerisSourceName == request.sourceName &&
              c.usesHighPrecisionAstroData == request.usesHighPrecision;
        });
  }
}

abstract class PeriodReadingContextOperation {
  Future<PeriodReadingContextResult> get result;
  void cancel();
}

typedef PeriodReadingContextStarter =
    PeriodReadingContextOperation Function(
      PeriodReadingContextRequest request,
      void Function(int completed, int total) onProgress,
    );

/// Assertions-only injection: never changes the production worker path.
class PeriodReadingContextTestHooks {
  static PeriodReadingContextStarter? _starter;
  static set starter(PeriodReadingContextStarter? value) {
    assert(() {
      _starter = value;
      return true;
    }());
  }
}

class PeriodReadingContextCancelled implements Exception {
  const PeriodReadingContextCancelled();
}

class PeriodReadingContextJob implements PeriodReadingContextOperation {
  PeriodReadingContextJob.start(
    PeriodReadingContextRequest request, {
    void Function(int completed, int total)? onProgress,
    Map<DateTime, HoroscopeReadingContext> seeds = const {},
  }) {
    _port.listen((message) {
      if (_finished) return;
      if (message is List && message.length == 3 && message[0] == 'progress') {
        onProgress?.call(message[1] as int, message[2] as int);
        return;
      }
      _finish();
      if (message is PeriodReadingContextResult && message.matches(request)) {
        _result.complete(message);
      } else {
        _result.completeError(StateError('期間の星配置を準備できませんでした。'));
      }
    });
    unawaited(_spawn(request, seeds));
  }
  final _port = ReceivePort();
  final _result = Completer<PeriodReadingContextResult>();
  Isolate? _isolate;
  bool _finished = false;
  @override
  Future<PeriodReadingContextResult> get result => _result.future;

  Future<void> _spawn(
    PeriodReadingContextRequest request,
    Map<DateTime, HoroscopeReadingContext> seeds,
  ) async {
    try {
      final worker = await Isolate.spawn(
        _periodReadingContextWorker,
        (request, _port.sendPort, seeds),
        debugName: 'pancyo-period-reading-context',
        onError: _port.sendPort,
        onExit: _port.sendPort,
      );
      if (_finished) {
        worker.kill(priority: Isolate.immediate);
      } else {
        _isolate = worker;
      }
    } catch (_) {
      if (!_finished) {
        _finish();
        _result.completeError(StateError('期間の別処理を開始できませんでした。'));
      }
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
    _result.completeError(const PeriodReadingContextCancelled());
  }
}

// Same placement/ingress/text operations formerly performed by _periodSign.
String _periodReadingSign(AstroPlanet planet, DateTime start, bool monthMode) {
  final ephemeris = AstrologyDataSources.current;
  final placement = ephemeris
      .placementsFor(start)
      .firstWhere((item) => item.planet == planet);
  final ingress = ephemeris.nextSignIngress(planet, start);
  final end = monthMode
      ? DateTime(start.year, start.month + 1)
      : DateTime(start.year + 1);
  final moveLabel = ingress != null && ingress.time.isBefore(end)
      ? ' → ${ingress.sign.label} ${_monthDayWithWeekday(ingress.time)}'
      : '';
  return '${planet.label}: ${placement.sign.label}$moveLabel';
}

void _periodReadingContextWorker(
  (
    PeriodReadingContextRequest,
    SendPort,
    Map<DateTime, HoroscopeReadingContext>,
  )
  input,
) {
  try {
    final request = input.$1;
    HouseSystemSettings.current.value = request.houseSystem;
    SwissEphemerisProvider._forceScalarVoidForCheck = request.scalarVoid;
    if (AstrologyDataSources.current.sourceName != request.sourceName ||
        AstrologyDataSources.current.usesHighPrecisionAstroData !=
            request.usesHighPrecision) {
      throw StateError('計算元が一致しません。');
    }
    final watch = Stopwatch()..start();
    final fallbackBefore = SwissEphemerisProvider._placementFallbackCount;
    final ephemeris = AstrologyDataSources.current;
    final frame = ephemeris.houseFrameFor(
      ephemeris.dateFromProfile(request.profile),
      ephemeris.placeForProfile(request.profile),
      request.houseSystem,
    );
    final contexts = <DateTime, HoroscopeReadingContext>{};
    final dates = request.dates;
    for (final date in dates) {
      final seed = input.$3[date.toUtc()];
      if (seed != null &&
          (seed.transit.date.toUtc() != date.toUtc() ||
              PeriodReadingContextRequest.profileIdentity(seed.natal.profile) !=
                  PeriodReadingContextRequest.profileIdentity(
                    request.profile,
                  ) ||
              seed.ephemerisSourceName != request.sourceName ||
              seed.usesHighPrecisionAstroData != request.usesHighPrecision)) {
        throw StateError('保存した期間の計算条件が一致しません。');
      }
      if (seed != null &&
          (seed.houseSystem != frame.system ||
              seed.houseCusps.length != frame.cusps.length ||
              List.generate(
                frame.cusps.length,
                (i) => seed.houseCusps[i] != frame.cusps[i],
              ).any((v) => v))) {
        throw StateError('保存した期間のハウス方式が一致しません。');
      }
      contexts[date.toUtc()] =
          seed ??
          const AstrologyEngine().buildPreviewContext(
            profile: request.profile,
            date: date,
          );
      input.$2.send(['progress', contexts.length, dates.length]);
    }
    final signs = {
      for (final p in request.signPlanets)
        p: _periodReadingSign(
          p,
          request.reference,
          request.mode == LongRangeMode.month,
        ),
    };
    if (request.usesHighPrecision &&
        SwissEphemerisProvider._placementFallbackCount != fallbackBefore) {
      throw StateError('高精度の配置を完了できませんでした。');
    }
    final result = PeriodReadingContextResult(
      requestIdentity: request.identity,
      contexts: contexts,
      signs: signs,
      requestedHouseSystem: request.houseSystem,
      resolvedHouseSystem: frame.system,
      houseCusps: frame.cusps,
      elapsedMilliseconds: watch.elapsedMilliseconds,
      workerName: Isolate.current.debugName,
    );
    if (!result.matches(request)) throw StateError('期間の計算条件が一致しません。');
    Isolate.exit(input.$2, result);
  } catch (_) {
    input.$2.send('failed');
  }
}
