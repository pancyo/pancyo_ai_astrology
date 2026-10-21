part of 'main.dart';

/// 期間相談JSONの計算入力。画面・BuildContext・保存先のプラグインは渡さない。
class PeriodConsultExportRequest {
  PeriodConsultExportRequest({
    required this.mode,
    required this.periodLabel,
    required this.weekStart,
    required this.month,
    required this.year,
    required this.profile,
    required this.details,
    required this.houseSystem,
    required this.requireHighPrecision,
    required this.temporaryRootPath,
    this.contextData,
    List<LongFortuneData> cards = const [],
    this.generatedAt,
    String? sourceName,
  }) : cards = List.unmodifiable(cards),
       sourceName =
           sourceName ??
           contextData?.ephemerisSourceName ??
           AstrologyDataSources.current.sourceName;

  final LongRangeMode mode;
  final String periodLabel;
  final DateTime weekStart;
  final DateTime month;
  final int year;
  final AstroProfile profile;
  final UserProfileDetails details;
  final HouseSystem houseSystem;
  final bool requireHighPrecision;
  final String temporaryRootPath;
  final HoroscopeReadingContext? contextData;
  final List<LongFortuneData> cards;
  final DateTime? generatedAt;
  final String sourceName;

  // Private operation token: never included in JSON or logs.
  String get identity => sha256
      .convert(
        utf8.encode(
          jsonEncode([
            mode.name,
            periodLabel,
            period,
            profile.name,
            profile.birthDate,
            profile.birthTime,
            profile.birthPlace,
            profile.theme,
            profile.savedProfileId,
            details.toJson(),
            houseSystem.name,
            sourceName,
            requireHighPrecision,
            generatedAt?.toIso8601String(),
          ]),
        ),
      )
      .toString();

  String get period => switch (mode) {
    LongRangeMode.year => year.toString().padLeft(4, '0'),
    LongRangeMode.month =>
      '${month.year.toString().padLeft(4, '0')}${month.month.toString().padLeft(2, '0')}',
    LongRangeMode.week =>
      '${weekStart.year.toString().padLeft(4, '0')}${weekStart.month.toString().padLeft(2, '0')}${weekStart.day.toString().padLeft(2, '0')}',
  };
}

class PeriodConsultExportResult {
  const PeriodConsultExportResult({
    required this.filePath,
    required this.contextMilliseconds,
    required this.dataMilliseconds,
    required this.writeMilliseconds,
    required this.cachedContextCount,
    required this.workerName,
  });

  final String filePath;
  final int contextMilliseconds;
  final int dataMilliseconds;
  final int writeMilliseconds;
  final int cachedContextCount;
  final String? workerName;
}

class PeriodConsultExportCancelled implements Exception {
  const PeriodConsultExportCancelled();
}

class PeriodConsultExportCalculation {
  const PeriodConsultExportCalculation({
    required this.data,
    required this.requestIdentity,
    required this.contextMilliseconds,
    required this.dataMilliseconds,
    required this.cachedContextCount,
    required this.workerName,
  });
  final Map<String, Object?> data;
  final String requestIdentity;
  final int contextMilliseconds, dataMilliseconds, cachedContextCount;
  final String? workerName;
}

abstract class PeriodConsultExportOperation {
  Future<PeriodConsultExportCalculation> get result;
  void cancel();
}

typedef PeriodConsultExportStarter =
    PeriodConsultExportOperation Function(PeriodConsultExportRequest request);
typedef PeriodConsultExportSpawner =
    Future<Isolate> Function(
      PeriodConsultExportRequest request,
      SendPort reply,
    );

/// The cancellable month/year worker calculates only; the current UI owns file writing.
class PeriodConsultExportJob implements PeriodConsultExportOperation {
  PeriodConsultExportJob.start(
    PeriodConsultExportRequest request, {
    PeriodConsultExportSpawner? spawnWorker,
  }) {
    _port.listen((message) {
      if (_finished) return;
      _finish();
      if (message is PeriodConsultExportCalculation) {
        _result.complete(message);
      } else {
        _result.completeError(StateError('月JSONを作成できませんでした。'));
      }
    });
    unawaited(_spawn(request, spawnWorker));
  }
  final _port = ReceivePort();
  final _result = Completer<PeriodConsultExportCalculation>();
  Isolate? _isolate;
  bool _finished = false;
  @override
  Future<PeriodConsultExportCalculation> get result => _result.future;

  Future<void> _spawn(
    PeriodConsultExportRequest request,
    PeriodConsultExportSpawner? spawnWorker,
  ) async {
    try {
      final worker =
          await (spawnWorker?.call(request, _port.sendPort) ??
              Isolate.spawn(
                _periodConsultWorker,
                (request, _port.sendPort),
                debugName: 'pancyo-period-consult-export',
                onError: _port.sendPort,
                onExit: _port.sendPort,
              ));
      if (_finished)
        worker.kill(priority: Isolate.immediate);
      else
        _isolate = worker;
    } catch (_) {
      if (!_finished) {
        _finish();
        _result.completeError(StateError('月JSONの別処理を開始できませんでした。'));
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
    _result.completeError(const PeriodConsultExportCancelled());
  }

  static Future<PeriodConsultExportResult> run(
    PeriodConsultExportRequest request,
  ) => Isolate.run(
    () => _calculatePeriodConsultExport(request),
    debugName: 'pancyo-period-consult-export',
  );
}

void _periodConsultWorker((PeriodConsultExportRequest, SendPort) input) {
  try {
    final result = _calculatePeriodConsultData(input.$1, verifySource: true);
    Isolate.exit(input.$2, result);
  } catch (_) {
    input.$2.send('failed');
  }
}

PeriodConsultExportCalculation _calculatePeriodConsultData(
  PeriodConsultExportRequest request, {
  bool verifySource = false,
}) {
  final contextWatch = Stopwatch()..start();
  // isolateの初期値を使わず、押下時のハウス方式を明示的に引き継ぐ。
  // 保存領域は読まず、変更もしない。
  HouseSystemSettings.current.value = request.houseSystem;
  if (request.requireHighPrecision &&
      !AstrologyDataSources.current.usesHighPrecisionAstroData) {
    throw StateError('期間JSONの高精度星計算をワーカーで利用できません。');
  }
  void checkSource(HoroscopeReadingContext context) {
    if (verifySource &&
        (context.ephemerisSourceName != request.sourceName ||
            context.usesHighPrecisionAstroData != request.requireHighPrecision))
      throw StateError('月JSONの計算元が一致しません。');
  }

  if (verifySource &&
      AstrologyDataSources.current.sourceName != request.sourceName)
    throw StateError('月JSONの計算元をワーカーで利用できません。');
  final placementFallbacksBefore =
      SwissEphemerisProvider._placementFallbackCount;
  final reference = switch (request.mode) {
    LongRangeMode.week => DateTime(
      request.weekStart.year,
      request.weekStart.month,
      request.weekStart.day,
      12,
    ),
    LongRangeMode.month => DateTime(
      request.month.year,
      request.month.month,
      1,
      12,
    ),
    LongRangeMode.year => DateTime(request.year, 1, 1, 12),
  };
  final contextData =
      request.contextData ??
      const AstrologyEngine().buildPreviewContext(
        profile: request.profile,
        date: reference,
      );
  checkSource(contextData);
  contextWatch.stop();
  final builder = PeriodConsultDataBuilder(
    mode: request.mode,
    periodLabel: request.periodLabel,
    weekStart: request.weekStart,
    month: request.month,
    year: request.year,
    profile: request.profile,
    details: request.details,
    contextData: contextData,
    cards: request.cards,
    contextResolver: verifySource
        ? (date) {
            final context = const AstrologyEngine().buildPreviewContext(
              profile: request.profile,
              date: date,
            );
            checkSource(context);
            return context;
          }
        : null,
  );
  final dataWatch = Stopwatch()..start();
  final data = builder.buildData(generatedAt: request.generatedAt);
  // The provider's Swiss label remains unchanged after a placement fallback.
  // A high-precision month must reject any such mixed calculation.
  if (verifySource &&
      request.requireHighPrecision &&
      SwissEphemerisProvider._placementFallbackCount !=
          placementFallbacksBefore) {
    throw StateError('月JSONの途中で高精度星計算を保持できませんでした。');
  }
  dataWatch.stop();
  return PeriodConsultExportCalculation(
    data: data,
    requestIdentity: request.identity,
    contextMilliseconds: contextWatch.elapsedMilliseconds,
    dataMilliseconds: dataWatch.elapsedMilliseconds,
    cachedContextCount: builder.cachedContextCount,
    workerName: Isolate.current.debugName,
  );
}

Future<PeriodConsultExportResult> _calculatePeriodConsultExport(
  PeriodConsultExportRequest request,
) async {
  final calculation = _calculatePeriodConsultData(request);
  final writeWatch = Stopwatch()..start();
  final file = await ConsultJsonFileWriter.write(
    temporaryRoot: Directory(request.temporaryRootPath),
    data: calculation.data,
    participantName: request.profile.name,
    kind: request.mode.name,
    period: request.period,
  );
  writeWatch.stop();
  return PeriodConsultExportResult(
    filePath: file.path,
    contextMilliseconds: calculation.contextMilliseconds,
    dataMilliseconds: calculation.dataMilliseconds,
    writeMilliseconds: writeWatch.elapsedMilliseconds,
    cachedContextCount: calculation.cachedContextCount,
    workerName: calculation.workerName,
  );
}

Object? _periodConsultExportActive;

Future<void> _exportPeriodConsultJson(
  BuildContext context, {
  required LongRangeMode mode,
  required String periodLabel,
  required DateTime weekStart,
  required DateTime month,
  required int year,
  required AstroProfile profile,
  required UserProfileDetails details,
  HoroscopeReadingContext? contextData,
  List<LongFortuneData> cards = const [],
  MonthlyConsultExportOwner? owner,
  PeriodConsultExportStarter? startJob,
}) async {
  if (mode == LongRangeMode.month || mode == LongRangeMode.year) {
    // Cards outside the Profile page own their token too. A temporary token is
    // only used for direct legacy callers and is disposed with this operation.
    final exportOwner = owner ?? MonthlyConsultExportOwner();
    try {
      await _exportMonthlyConsultJson(
        context,
        mode: mode,
        periodLabel: periodLabel,
        weekStart: weekStart,
        month: month,
        year: year,
        profile: profile,
        details: details,
        contextData: contextData,
        cards: cards,
        owner: exportOwner,
        startJob: startJob,
      );
    } finally {
      if (owner == null) exportOwner.dispose();
    }
    return;
  }
  if (!context.mounted || _periodConsultExportActive != null) return;
  final ticket = Object();
  _periodConsultExportActive = ticket;
  final houseSystem = HouseSystemSettings.current.value;
  final requireHighPrecision =
      AstrologyDataSources.current.usesHighPrecisionAstroData ||
      (contextData?.usesHighPrecisionAstroData ?? false);
  final watch = Stopwatch()..start();
  final originRoute = ModalRoute.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  final progress = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ValueListenableBuilder<AppLanguage>(
      valueListenable: AppLanguageSettings.current,
      builder: (_, language, _) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  AppStrings(language).text(AppText.consultJsonExporting),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  void closeProgress() {
    if (navigator.mounted && progress.isActive) navigator.removeRoute(progress);
  }

  try {
    unawaited(navigator.push(progress));
    await WidgetsBinding.instance.endOfFrame;
    final directory = await getTemporaryDirectory();
    final result = await PeriodConsultExportJob.run(
      PeriodConsultExportRequest(
        mode: mode,
        periodLabel: periodLabel,
        weekStart: weekStart,
        month: month,
        year: year,
        profile: profile,
        details: details,
        contextData: contextData,
        cards: cards,
        houseSystem: houseSystem,
        requireHighPrecision: requireHighPrecision,
        temporaryRootPath: directory.path,
      ),
    );
    if (reworkTestBuild) {
      // 時間と件数だけ。氏名・出生情報・ファイルパスはログへ出さない。
      print(
        'PANCYO_REWORK_PERIOD_EXPORT ${jsonEncode({'mode': mode.name, 'context_ms': result.contextMilliseconds, 'data_ms': result.dataMilliseconds, 'write_ms': result.writeMilliseconds, 'elapsed_ms': watch.elapsedMilliseconds, 'cached_contexts': result.cachedContextCount, 'worker': result.workerName})}',
      );
    }
    closeProgress();
    if (!context.mounted || originRoute?.isCurrent == false) return;
    final file = File(result.filePath);
    final shareResult = await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/json')],
      subject: AppLanguageSettings.strings.text(
        AppText.consultJsonShareSubject,
      ),
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: ValueListenableBuilder<AppLanguage>(
            valueListenable: AppLanguageSettings.current,
            builder: (_, language, _) => Text(
              _consultJsonShareMessage(
                shareResult,
                file.uri.pathSegments.last,
                strings: AppStrings(language),
              ),
            ),
          ),
        ),
      );
    }
  } catch (_) {
    closeProgress();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: ValueListenableBuilder<AppLanguage>(
            valueListenable: AppLanguageSettings.current,
            builder: (_, language, _) => Text(
              AppStrings(language).text(AppText.consultJsonExportFailed),
            ),
          ),
        ),
      );
    }
  } finally {
    closeProgress();
    if (identical(_periodConsultExportActive, ticket))
      _periodConsultExportActive = null;
  }
}

class MonthlyConsultExportOwner extends ChangeNotifier {
  int revision = 0;
  bool alive = true;
  void invalidate() {
    revision++;
    notifyListeners();
  }

  @override
  void dispose() {
    alive = false;
    invalidate();
    super.dispose();
  }
}

Future<void> _exportMonthlyConsultJson(
  BuildContext context, {
  LongRangeMode mode = LongRangeMode.month,
  required String periodLabel,
  required DateTime weekStart,
  required DateTime month,
  required int year,
  required AstroProfile profile,
  required UserProfileDetails details,
  required MonthlyConsultExportOwner owner,
  HoroscopeReadingContext? contextData,
  List<LongFortuneData> cards = const [],
  PeriodConsultExportStarter? startJob,
}) async {
  if (!context.mounted || !owner.alive || _periodConsultExportActive != null)
    return;
  final ticket = Object();
  _periodConsultExportActive = ticket;
  final revision = owner.revision;
  final origin = ModalRoute.of(context);
  final house = HouseSystemSettings.current.value;
  final source = AstrologyDataSources.current.sourceName;
  final precision = AstrologyDataSources.current.usesHighPrecisionAstroData;
  final cancelled = Completer<void>();
  bool current() =>
      context.mounted &&
      owner.alive &&
      owner.revision == revision &&
      HouseSystemSettings.current.value == house &&
      AstrologyDataSources.current.sourceName == source &&
      AstrologyDataSources.current.usesHighPrecisionAstroData == precision;
  void changed() {
    if (!current() && !cancelled.isCompleted) cancelled.complete();
  }

  owner.addListener(changed);
  HouseSystemSettings.current.addListener(changed);
  try {
    final request = PeriodConsultExportRequest(
      mode: mode,
      periodLabel: periodLabel,
      weekStart: weekStart,
      month: month,
      year: year,
      profile: profile,
      details: details,
      contextData: contextData == null
          ? null
          : _freezeDailyConsultContext(contextData),
      cards: cards,
      houseSystem: house,
      requireHighPrecision:
          precision || (contextData?.usesHighPrecisionAstroData ?? false),
      sourceName: contextData?.ephemerisSourceName ?? source,
      temporaryRootPath: '',
      generatedAt: DateTime.now(),
    );
    final dialog = showDialog<File>(
      context: context,
      barrierDismissible: false,
      builder: (_) => MonthlyConsultJsonExportDialog(
        request: request,
        owner: owner,
        startJob: startJob,
      ),
    );
    final file = await Future.any<File?>([
      dialog,
      cancelled.future.then<File?>((_) => null),
    ]);
    if (file == null || !current() || origin?.isCurrent == false) return;
    // An old chooser can remain pending after its page is destroyed. Its future
    // is observed, but cannot hold the next page's export lock or show notices.
    final share = Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/json')],
      subject: AppLanguageSettings.strings.text(
        AppText.consultJsonShareSubject,
      ),
    );
    final result = await Future.any<ShareResult?>([
      share,
      cancelled.future.then<ShareResult?>((_) => null),
    ]);
    if (result != null && current() && origin?.isCurrent != false) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: ValueListenableBuilder<AppLanguage>(
            valueListenable: AppLanguageSettings.current,
            builder: (_, language, _) => Text(
              _consultJsonShareMessage(
                result,
                file.uri.pathSegments.last,
                strings: AppStrings(language),
              ),
            ),
          ),
        ),
      );
    }
  } catch (_) {
    if (current() && origin?.isCurrent != false) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: ValueListenableBuilder<AppLanguage>(
            valueListenable: AppLanguageSettings.current,
            builder: (_, language, _) => Text(
              AppStrings(language).text(AppText.consultJsonExportFailed),
            ),
          ),
        ),
      );
    }
  } finally {
    owner.removeListener(changed);
    HouseSystemSettings.current.removeListener(changed);
    if (identical(_periodConsultExportActive, ticket))
      _periodConsultExportActive = null;
  }
}

class MonthlyConsultJsonExportDialog extends StatefulWidget {
  const MonthlyConsultJsonExportDialog({
    super.key,
    required this.request,
    required this.owner,
    this.startJob,
  });
  final PeriodConsultExportRequest request;
  final MonthlyConsultExportOwner owner;
  final PeriodConsultExportStarter? startJob;
  @override
  State<MonthlyConsultJsonExportDialog> createState() =>
      _MonthlyConsultJsonExportDialogState();
}

class _MonthlyConsultJsonExportDialogState
    extends State<MonthlyConsultJsonExportDialog> {
  PeriodConsultExportOperation? _job;
  late int _revision;
  late String _source;
  late bool _precision;
  int _generation = 0;
  bool _working = false, _closing = false;
  AppText? _error;
  NavigatorState? _navigator;
  ModalRoute<dynamic>? _route;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _navigator = Navigator.of(context);
    _route = ModalRoute.of(context);
  }

  @override
  void initState() {
    super.initState();
    _revision = widget.owner.revision;
    _source = AstrologyDataSources.current.sourceName;
    _precision = AstrologyDataSources.current.usesHighPrecisionAstroData;
    widget.owner.addListener(_changed);
    HouseSystemSettings.current.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_closing) _start();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  bool get _current =>
      mounted &&
      !_closing &&
      widget.owner.alive &&
      widget.owner.revision == _revision &&
      HouseSystemSettings.current.value == widget.request.houseSystem &&
      AstrologyDataSources.current.sourceName == _source &&
      AstrologyDataSources.current.usesHighPrecisionAstroData == _precision;
  void _changed() {
    if (!_current) _cancel();
  }

  void _cancel() {
    if (_closing) return;
    _closing = true;
    _generation++;
    _job?.cancel();
    _job = null;
    final navigator = _navigator, route = _route;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigator?.mounted == true && route?.isActive == true)
        navigator!.removeRoute(route!);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void dispose() {
    _closing = true;
    _generation++;
    _job?.cancel();
    widget.owner.removeListener(_changed);
    HouseSystemSettings.current.removeListener(_changed);
    super.dispose();
  }

  Future<void> _start() async {
    if (!_current || _working) return;
    final generation = ++_generation;
    final watch = Stopwatch()..start();
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final job =
          (widget.startJob ??
          (request) => PeriodConsultExportJob.start(request))(widget.request);
      _job = job;
      if (!_current || generation != _generation) {
        unawaited(job.result.then<void>((_) {}, onError: (_) {}));
        job.cancel();
        _job = null;
        return;
      }
      final result = await job.result;
      if (!_current || generation != _generation) return;
      _job = null;
      if (result.requestIdentity != widget.request.identity)
        throw StateError('期間JSONの入力が一致しません。');
      final directory = await getTemporaryDirectory();
      if (!_current || generation != _generation) return;
      final writeWatch = Stopwatch()..start();
      final file = await ConsultJsonFileWriter.write(
        temporaryRoot: directory,
        data: result.data,
        participantName: widget.request.profile.name,
        kind: widget.request.mode.name,
        period: widget.request.period,
        generatedAt: widget.request.generatedAt,
      );
      // Cancellation during a write may leave a private temporary file, never a share.
      if (!_current || generation != _generation) return;
      if (reworkTestBuild)
        print(
          'PANCYO_REWORK_PERIOD_EXPORT ${jsonEncode({'mode': widget.request.mode.name, 'context_ms': result.contextMilliseconds, 'data_ms': result.dataMilliseconds, 'write_ms': writeWatch.elapsedMilliseconds, 'elapsed_ms': watch.elapsedMilliseconds, 'cached_contexts': result.cachedContextCount, 'worker': result.workerName})}',
        );
      _closing = true;
      final navigator = _navigator, route = _route;
      if (navigator?.mounted == true && route?.isActive == true) {
        if (route!.isCurrent)
          navigator!.pop(file);
        else
          navigator!.removeRoute(route, file);
      }
    } catch (error) {
      if (!_current || generation != _generation) return;
      _job = null;
      setState(() {
        _working = false;
        _error = error is PeriodConsultExportCancelled
            ? AppText.consultJsonCancelledRetry
            : AppText.consultJsonFailedRetry;
      });
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppLanguage>(
    valueListenable: AppLanguageSettings.current,
    builder: (context, language, _) {
      final strings = AppStrings(language);
      return PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(
            strings.text(
              widget.request.mode == LongRangeMode.year
                  ? AppText.createYearConsultData
                  : AppText.createMonthJson,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_working) const CircularProgressIndicator(strokeWidth: 2),
                const SizedBox(height: 12),
                Text(strings.text(_error ?? AppText.consultJsonExporting)),
                const SizedBox(height: 8),
                Text(
                  widget.request.mode == LongRangeMode.month
                      ? strings.text(AppText.monthlyJsonDialogHelp)
                      : language == AppLanguage.ja
                      ? 'この年の鑑定データを作成します。途中で中止し、もう一度作成できます。'
                      : 'Creates this year’s reading data. You can cancel and create it again.',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 8),
                Text(
                  strings.text(AppText.consultJsonFilePrivacy),
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: _cancel,
              child: Text(
                strings.text(_working ? AppText.cancel : AppText.close),
              ),
            ),
            if (!_working)
              FilledButton(
                onPressed: _start,
                child: Text(strings.text(AppText.retry)),
              ),
          ],
        ),
      );
    },
  );
}

class _ExternalAstroDataExportCardState
    extends State<ExternalAstroDataExportCard> {
  final owner = MonthlyConsultExportOwner();
  @override
  void didUpdateWidget(covariant ExternalAstroDataExportCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode ||
        oldWidget.month != widget.month ||
        oldWidget.year != widget.year ||
        _dailyConsultOwnerInput(oldWidget.profile, oldWidget.details) !=
            _dailyConsultOwnerInput(widget.profile, widget.details) ||
        !identical(oldWidget.contextData, widget.contextData) ||
        !identical(oldWidget.cards, widget.cards) ||
        oldWidget.startJob != widget.startJob)
      owner.invalidate();
  }

  @override
  void dispose() {
    owner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget._build(context);
}

/// 元の期間JSON生成を移した純粋なデータ組み立て。計算式とスキーマは維持。
class PeriodConsultDataBuilder {
  PeriodConsultDataBuilder({
    required this.mode,
    required this.periodLabel,
    required this.weekStart,
    required this.month,
    required this.year,
    required this.profile,
    required this.details,
    required this.contextData,
    required this.cards,
    this.cacheContexts = true,
    this.includeNineAreaSamples = true,
    this.contextResolver,
    this.eventWorkCounts,
    this.reuseEventSearches = true,
  });

  final LongRangeMode mode;
  final String periodLabel;
  final DateTime weekStart;
  final DateTime month;
  final int year;
  final AstroProfile profile;
  final UserProfileDetails details;
  final HoroscopeReadingContext contextData;
  final List<LongFortuneData> cards;
  final bool cacheContexts;
  final bool includeNineAreaSamples;
  // グラフの一回の計算内で同日時を共用する。UIや保存設定は渡さない。
  final HoroscopeReadingContext Function(DateTime)? contextResolver;
  final AstroEventWorkCounts? eventWorkCounts;
  final bool reuseEventSearches;
  final _contexts = <DateTime, HoroscopeReadingContext>{};
  int get cachedContextCount => _contexts.length;

  HoroscopeReadingContext _contextFor(DateTime date) {
    HoroscopeReadingContext calculate() =>
        contextResolver?.call(date) ??
        const AstrologyEngine().buildPreviewContext(
          profile: profile,
          date: date,
        );
    // local/UTCの表記が違っても同じ瞬間なら一度だけ計算する。
    return cacheContexts
        ? _contexts.putIfAbsent(date.toUtc(), calculate)
        : calculate();
  }

  String get _scoreAggregation => switch (mode) {
    LongRangeMode.week => '7日分の12:00 JSTスコア平均',
    LongRangeMode.month => '月内5時点（1日・8日・15日・22日・最終日）の12:00 JSTスコア平均',
    LongRangeMode.year => '各月1日・15日、計24時点の12:00 JSTスコア平均',
  };

  String _dateTimeJst(DateTime value) {
    final jst = value.toUtc().add(const Duration(hours: 9));
    return '${jst.year.toString().padLeft(4, '0')}-${jst.month.toString().padLeft(2, '0')}-${jst.day.toString().padLeft(2, '0')} '
        '${jst.hour.toString().padLeft(2, '0')}:${jst.minute.toString().padLeft(2, '0')}:00+09:00';
  }

  List<Map<String, Object?>> _placements(HoroscopeReadingContext context) {
    return context.transit.placements
        .map(
          (item) => <String, Object?>{
            'planet': item.planet.label,
            'sign': item.sign.label,
            'degree': item.degree,
            'house': item.house,
          },
        )
        .toList();
  }

  String _areaKey(FortuneArea area) => switch (area) {
    FortuneArea.love => 'love',
    FortuneArea.work => 'work',
    FortuneArea.money => 'money',
    FortuneArea.mental => 'mental',
    FortuneArea.overall => 'overall',
  };

  String _areaTitle(FortuneArea area) => switch (area) {
    FortuneArea.love => '恋愛運',
    FortuneArea.work => '仕事運',
    FortuneArea.money => '金運',
    FortuneArea.mental => '健康・メンタル運',
    FortuneArea.overall => '総合運',
  };

  Map<String, Object?> _overallBreakdownSnapshot(
    Map<FortuneArea, FortuneScoreBreakdown> areaBreakdowns,
    HoroscopeReadingContext context,
  ) {
    final areaScores = <String, int>{
      for (final area in const [
        FortuneArea.love,
        FortuneArea.work,
        FortuneArea.money,
        FortuneArea.mental,
      ])
        _areaKey(area): areaBreakdowns[area]!.score,
    };
    final average = FortuneScoreCalculator.overallFromAreas(areaScores.values);
    final bonus = FortuneScoreCalculator.overallReturnBonus(context);
    final rawScore = average + (bonus?.value ?? 0);
    final finalScore = rawScore.round().clamp(50, 99).toInt();
    return {
      'base': average,
      'area_scores': areaScores,
      'average_before_return_bonus': average,
      'return_bonus': bonus == null
          ? null
          : {
              'planet': bonus.planet.label,
              'value': double.parse(bonus.value.toStringAsFixed(2)),
              'detail': bonus.detail,
              'formula': bonus.formula,
            },
      'adjustment': double.parse((bonus?.value ?? 0).toStringAsFixed(2)),
      'raw_score': double.parse(rawScore.toStringAsFixed(2)),
      'final_score': finalScore,
      'formula':
          '恋愛・仕事・金運・健康/メンタルの4分野のfinal_score平均 → 総合リターン特例を最強1件だけ加算 → 四捨五入（50〜99点）',
    };
  }

  Map<String, Object?> _dailyScoreBreakdowns(HoroscopeReadingContext context) {
    final areaBreakdowns = <FortuneArea, FortuneScoreBreakdown>{
      for (final area in const [
        FortuneArea.love,
        FortuneArea.work,
        FortuneArea.money,
        FortuneArea.mental,
      ])
        area: FortuneScoreCalculator.dailyAreaBreakdown(
          context,
          area,
          FortuneScoreCalculator.standardBase(area),
        ),
    };
    return {
      'overall': _overallBreakdownSnapshot(areaBreakdowns, context),
      for (final entry in areaBreakdowns.entries)
        _areaKey(entry.key): entry.value.toJson(),
    };
  }

  Map<String, Object?> _periodAreaBreakdownSnapshot({
    required FortuneArea area,
    required List<HoroscopeReadingContext> contexts,
    required List<DateTime> dates,
    required int finalScore,
    required String aggregation,
    double periodAdjustment = 0,
  }) {
    final samples = List.generate(contexts.length, (index) {
      final breakdown = FortuneScoreCalculator.periodAreaBreakdown(
        contexts[index],
        area,
        dates[index],
        FortuneScoreCalculator.standardBase(area),
      );
      return {
        'date_time_jst': _dateTimeJst(dates[index]),
        'score': breakdown.score,
        'calculation': breakdown.toJson(),
      };
    });
    final sampleAverage =
        (samples
                    .map((sample) => sample['score'] as int)
                    .fold<int>(0, (sum, score) => sum + score) /
                samples.length)
            .round();
    return {
      'area': _areaKey(area),
      'aggregation': aggregation,
      'samples': samples,
      'sample_score_average': sampleAverage,
      'period_adjustment': double.parse(periodAdjustment.toStringAsFixed(2)),
      'final_score': finalScore,
      'formula': '各基準時刻のcalculation.final_scoreを平均し、期間専用補正があれば加えて最終点にします。',
    };
  }

  Map<String, Object?> _periodOverallBreakdownSnapshot({
    required List<HoroscopeReadingContext> contexts,
    required List<DateTime> dates,
    required int finalScore,
    required String aggregation,
    double periodAdjustment = 0,
    Map<String, Object?>? extra,
  }) {
    final samples = List.generate(contexts.length, (index) {
      final scoreBreakdown = _dailyScoreBreakdowns(contexts[index]);
      return {
        'date_time_jst': _dateTimeJst(dates[index]),
        'score': scoreBreakdown['overall']! is Map<String, Object?>
            ? (scoreBreakdown['overall']!
                  as Map<String, Object?>)['final_score']
            : null,
        'calculation': scoreBreakdown['overall'],
        'area_scores': {
          for (final area in const [
            FortuneArea.love,
            FortuneArea.work,
            FortuneArea.money,
            FortuneArea.mental,
          ])
            _areaKey(area):
                (scoreBreakdown[_areaKey(area)]!
                    as Map<String, Object?>)['final_score'],
        },
      };
    });
    final sampleAverage =
        (samples
                    .map((sample) => sample['score'] as int)
                    .fold<int>(0, (sum, score) => sum + score) /
                samples.length)
            .round();
    return {
      'area': 'overall',
      'aggregation': aggregation,
      'samples': samples,
      'sample_score_average': sampleAverage,
      'period_adjustment': double.parse(periodAdjustment.toStringAsFixed(2)),
      'final_score': finalScore,
      'formula': '各基準時刻の4分野平均（必要な場合は各日の総合リターン特例を含む）を期間平均し、期間専用補正を加えて最終点にします。',
      if (extra != null) ...extra,
    };
  }

  Map<String, Object?> _annualAreaBreakdownSnapshot({
    required FortuneArea area,
    required List<HoroscopeReadingContext> monthlyContexts,
    required List<HoroscopeReadingContext> midMonthContexts,
    required int finalScore,
    required double annualAdjustment,
  }) {
    final months = List.generate(12, (index) {
      final firstDate = DateTime(
        monthlyContexts[index].transit.date.year,
        monthlyContexts[index].transit.date.month,
        1,
        12,
      );
      final middleDate = DateTime(
        monthlyContexts[index].transit.date.year,
        monthlyContexts[index].transit.date.month,
        15,
        12,
      );
      final first = FortuneScoreCalculator.periodAreaBreakdown(
        monthlyContexts[index],
        area,
        firstDate,
        FortuneScoreCalculator.standardBase(area),
      );
      final middle = FortuneScoreCalculator.periodAreaBreakdown(
        midMonthContexts[index],
        area,
        middleDate,
        FortuneScoreCalculator.standardBase(area),
      );
      return {
        'month':
            '${firstDate.year.toString().padLeft(4, '0')}-${firstDate.month.toString().padLeft(2, '0')}',
        'score_average': ((first.score + middle.score) / 2).round(),
        'first': {
          'date_time_jst': _dateTimeJst(firstDate),
          'score': first.score,
          'calculation': first.toJson(),
        },
        'middle': {
          'date_time_jst': _dateTimeJst(middleDate),
          'score': middle.score,
          'calculation': middle.toJson(),
        },
      };
    });
    final baseScore =
        (months
                    .map((month) => month['score_average'] as int)
                    .fold<int>(0, (sum, score) => sum + score) /
                months.length)
            .round();
    return {
      'area': _areaKey(area),
      'aggregation': '各月1日・15日、計24時点の12:00 JSTスコアを月ごとに平均し、その12か月平均',
      'months': months,
      'base_score_before_annual_event': baseScore,
      'annual_event_adjustment': double.parse(
        annualAdjustment.toStringAsFixed(2),
      ),
      'final_score': finalScore,
      'formula':
          '24時点を月ごとに平均 → 12か月平均を四捨五入 → 年専用の人生イベント補正を分野別に加算 → 50〜99点に収めます。',
    };
  }

  Map<String, Object?> _periodBreakdownSnapshots() {
    if (mode == LongRangeMode.week || mode == LongRangeMode.month) {
      final dates =
          mode == LongRangeMode.week
                ? List.generate(
                    7,
                    (index) => DateTime(
                      weekStart.year,
                      weekStart.month,
                      weekStart.day + index,
                      12,
                    ),
                  )
                : <int>{
                        1,
                        8,
                        15,
                        22,
                        DateTime(month.year, month.month + 1, 0).day,
                      }
                      .map((day) => DateTime(month.year, month.month, day, 12))
                      .toList()
            ..sort();
      final contexts = dates.map((date) => _contextFor(date)).toList();
      final aggregation = mode == LongRangeMode.week
          ? '7日分の12:00 JSTスコア平均'
          : '月内5時点（1日・8日・15日・22日・最終日）の12:00 JSTスコア平均';
      final result = <String, Object?>{};
      for (final area in const [
        FortuneArea.love,
        FortuneArea.work,
        FortuneArea.money,
        FortuneArea.mental,
      ]) {
        final scores = contexts
            .map(
              (context) => FortuneScoreCalculator.periodAreaBreakdown(
                context,
                area,
                context.transit.date,
                FortuneScoreCalculator.standardBase(area),
              ).score,
            )
            .toList();
        result[_areaTitle(area)] = _periodAreaBreakdownSnapshot(
          area: area,
          contexts: contexts,
          dates: dates,
          finalScore:
              (scores.reduce((sum, score) => sum + score) / scores.length)
                  .round(),
          aggregation: aggregation,
        );
      }
      final overallScores = contexts.map((context) {
        final areas = <FortuneArea, FortuneScoreBreakdown>{
          for (final area in const [
            FortuneArea.love,
            FortuneArea.work,
            FortuneArea.money,
            FortuneArea.mental,
          ])
            area: FortuneScoreCalculator.periodAreaBreakdown(
              context,
              area,
              context.transit.date,
              FortuneScoreCalculator.standardBase(area),
            ),
        };
        return FortuneScoreCalculator.overallWithReturnBonus(
          areas.values.map((breakdown) => breakdown.score),
          context,
        );
      }).toList();
      final peak = FortuneScoreCalculator.periodReturnPeakBonus(contexts);
      result['総合運'] = _periodOverallBreakdownSnapshot(
        contexts: contexts,
        dates: dates,
        finalScore:
            ((overallScores.reduce((sum, score) => sum + score) /
                        overallScores.length) +
                    (peak?.value ?? 0))
                .round()
                .clamp(50, 99)
                .toInt(),
        aggregation: aggregation,
        periodAdjustment: peak?.value ?? 0,
        extra: {
          'period_peak_bonus': peak == null
              ? null
              : {
                  'planet': peak.planet.label,
                  'value': double.parse(peak.value.toStringAsFixed(2)),
                  'detail': peak.detail,
                  'formula': peak.formula,
                },
        },
      );
      return result;
    }

    final monthlyContexts = List.generate(
      12,
      (index) => _contextFor(DateTime(year, index + 1, 1, 12)),
    );
    final midMonthContexts = List.generate(
      12,
      (index) => _contextFor(DateTime(year, index + 1, 15, 12)),
    );
    final annualBoost = FortuneScoreCalculator.annualLifeEventBoost([
      ...monthlyContexts,
      ...midMonthContexts,
    ]);
    final result = <String, Object?>{};
    final areaScores = <FortuneArea, int>{};
    for (final area in const [
      FortuneArea.love,
      FortuneArea.work,
      FortuneArea.money,
      FortuneArea.mental,
    ]) {
      final base = _annualAreaBreakdownSnapshot(
        area: area,
        monthlyContexts: monthlyContexts,
        midMonthContexts: midMonthContexts,
        finalScore: 0,
        annualAdjustment: 0,
      );
      final baseScore = base['base_score_before_annual_event'] as int;
      final adjustment = annualBoost?.effectFor(area) ?? 0;
      final finalScore = (baseScore + adjustment).round().clamp(50, 99).toInt();
      areaScores[area] = finalScore;
      result[_areaTitle(area)] = _annualAreaBreakdownSnapshot(
        area: area,
        monthlyContexts: monthlyContexts,
        midMonthContexts: midMonthContexts,
        finalScore: finalScore,
        annualAdjustment: adjustment,
      );
    }
    result['総合運'] = {
      'area': 'overall',
      'aggregation': '年内24時点の各分野集計後、4分野の最終点を平均',
      'area_scores': {
        for (final entry in areaScores.entries)
          _areaKey(entry.key): entry.value,
      },
      'average_before_annual_event': FortuneScoreCalculator.overallFromAreas(
        areaScores.values,
      ),
      'annual_event_note': annualBoost == null
          ? null
          : {
              'value': annualBoost.value,
              'detail': annualBoost.detail,
              'formula': annualBoost.formula,
            },
      'final_score': FortuneScoreCalculator.overallFromAreas(areaScores.values),
      'formula': '各分野の24時点集計と年専用補正を確定 → 恋愛・仕事・金運・健康/メンタルの4分野平均 → 総合運',
    };
    return result;
  }

  Map<String, Object?> _transitSnapshot(HoroscopeReadingContext context) {
    final eventSnapshot = PeriodAstroEventSnapshot.build(
      reference: context.transit.date,
      contextData: context,
      workCounts: eventWorkCounts,
      reuseIdenticalSearches: reuseEventSearches,
    );
    final stationEvents = eventSnapshot['station_events_jst'] as List<String>;
    final dailyEvents =
        eventSnapshot['daily_events_jst'] as List<Map<String, Object?>>;
    return {
      'date_time_jst': _dateTimeJst(context.transit.date),
      'placements': _placements(context),
      'transit_house_reference': _transitHouseReferenceSnapshot(),
      'void_moon': context.transit.voidMoon == null
          ? null
          : {
              'start': _dateTimeJst(context.transit.voidMoon!.startTime),
              'end': _dateTimeJst(context.transit.voidMoon!.endTime),
            },
      'lunar_phase': eventSnapshot['lunar_phase'],
      'lunar_phase_score_effects':
          FortuneScoreCalculator.lunarPhaseScoreEffects(context),
      'planetary_sign_dignity_effects':
          FortuneScoreCalculator.planetarySignDignityEffects(context),
      'overall_return_bonus': _overallReturnBonusSnapshot(context),
      'retrograde_planets': {
        ...context.retrogradePlanets,
        ...DailyAstroEventsCard.verifiedRetrogradesAt(context.transit.date),
      }.map((item) => item.label).toList(),
      'station_events_jst': stationEvents,
      if (dailyEvents.isNotEmpty) 'daily_events_jst': dailyEvents,
      'special_configurations_at_reference_time': _transitConfigurationSnapshot(
        context,
      ),
    };
  }

  Map<String, Object?>? _overallReturnBonusSnapshot(
    HoroscopeReadingContext context,
  ) {
    final bonus = FortuneScoreCalculator.overallReturnBonus(context);
    if (bonus == null) return null;
    return {
      'planet': bonus.planet.label,
      'value': double.parse(bonus.value.toStringAsFixed(2)),
      'detail': bonus.detail,
      'formula': bonus.formula,
      'rule': '星別上限・近さ・位相で計算し、最強1件のみを4分野平均後に加算',
    };
  }

  Map<String, Object?> _dailySnapshot(DateTime date) {
    final daily = _contextFor(date);
    final eventSnapshot = PeriodAstroEventSnapshot.build(
      reference: date,
      contextData: daily,
      workCounts: eventWorkCounts,
      reuseIdenticalSearches: reuseEventSearches,
    );
    final stationEvents = eventSnapshot['station_events_jst'] as List<String>;
    final dailyEvents =
        eventSnapshot['daily_events_jst'] as List<Map<String, Object?>>;
    return {
      'date':
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      'date_time_jst': _dateTimeJst(date),
      'overall': FortuneScoreCalculator.dailyOverall(daily),
      'love': FortuneScoreCalculator.dailyArea(
        daily,
        FortuneArea.love,
        FortuneScoreCalculator.standardBase(FortuneArea.love),
      ),
      'work': FortuneScoreCalculator.dailyArea(
        daily,
        FortuneArea.work,
        FortuneScoreCalculator.standardBase(FortuneArea.work),
      ),
      'money': FortuneScoreCalculator.dailyArea(
        daily,
        FortuneArea.money,
        FortuneScoreCalculator.standardBase(FortuneArea.money),
      ),
      'mental': FortuneScoreCalculator.dailyArea(
        daily,
        FortuneArea.mental,
        FortuneScoreCalculator.standardBase(FortuneArea.mental),
      ),
      'score_breakdown': _dailyScoreBreakdowns(daily),
      'moon_sign': daily.transit.placements
          .where((item) => item.planet == AstroPlanet.moon)
          .map((item) => item.sign.label)
          .join(),
      'transit_placements': _placements(daily),
      'transit_house_reference': _transitHouseReferenceSnapshot(),
      'void_moon': daily.transit.voidMoon == null
          ? null
          : {
              'start': _dateTimeJst(daily.transit.voidMoon!.startTime),
              'end': _dateTimeJst(daily.transit.voidMoon!.endTime),
            },
      'lunar_phase': eventSnapshot['lunar_phase'],
      'lunar_phase_score_effects':
          FortuneScoreCalculator.lunarPhaseScoreEffects(daily),
      'planetary_sign_dignity_effects':
          FortuneScoreCalculator.planetarySignDignityEffects(daily),
      'overall_return_bonus': _overallReturnBonusSnapshot(daily),
      'retrograde_planets': {
        ...daily.retrogradePlanets,
        ...DailyAstroEventsCard.verifiedRetrogradesAt(date),
      }.map((item) => item.label).toList(),
      'station_events_jst': stationEvents,
      if (dailyEvents.isNotEmpty) 'daily_events_jst': dailyEvents,
      'special_configurations_at_reference_time': _transitConfigurationSnapshot(
        daily,
      ),
    };
  }

  List<Map<String, Object?>> _annualMonths() {
    return List.generate(12, (index) {
      final month = index + 1;
      final firstDate = DateTime(year, month, 1, 12);
      final middleDate = DateTime(year, month, 15, 12);
      final first = _contextFor(firstDate);
      final middle = _contextFor(middleDate);
      List<int> scorePair(FortuneArea area, int base) => [
        FortuneScoreCalculator.periodArea(area, first, firstDate, base),
        FortuneScoreCalculator.periodArea(area, middle, middleDate, base),
      ];
      int average(List<int> values) => ((values[0] + values[1]) / 2).round();
      final lovePair = scorePair(
        FortuneArea.love,
        FortuneScoreCalculator.standardBase(FortuneArea.love),
      );
      final workPair = scorePair(
        FortuneArea.work,
        FortuneScoreCalculator.standardBase(FortuneArea.work),
      );
      final moneyPair = scorePair(
        FortuneArea.money,
        FortuneScoreCalculator.standardBase(FortuneArea.money),
      );
      final mentalPair = scorePair(
        FortuneArea.mental,
        FortuneScoreCalculator.standardBase(FortuneArea.mental),
      );
      final love = average(lovePair);
      final work = average(workPair);
      final money = average(moneyPair);
      final mental = average(mentalPair);
      final overall =
          ((FortuneScoreCalculator.overallWithReturnBonus([
                        lovePair[0],
                        workPair[0],
                        moneyPair[0],
                        mentalPair[0],
                      ], first) +
                      FortuneScoreCalculator.overallWithReturnBonus([
                        lovePair[1],
                        workPair[1],
                        moneyPair[1],
                        mentalPair[1],
                      ], middle)) /
                  2)
              .round();
      return {
        'month':
            '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}',
        'transit_samples': [_transitSnapshot(first), _transitSnapshot(middle)],
        'scores': {
          'overall': overall,
          'love': love,
          'work': work,
          'money': money,
          'mental': mental,
        },
        'score_breakdown': {
          'overall': _periodOverallBreakdownSnapshot(
            contexts: [first, middle],
            dates: [firstDate, middleDate],
            finalScore: overall,
            aggregation: '各月1日・15日の12:00 JST総合運平均',
          ),
          'love': _periodAreaBreakdownSnapshot(
            area: FortuneArea.love,
            contexts: [first, middle],
            dates: [firstDate, middleDate],
            finalScore: love,
            aggregation: '各月1日・15日の12:00 JSTスコア平均',
          ),
          'work': _periodAreaBreakdownSnapshot(
            area: FortuneArea.work,
            contexts: [first, middle],
            dates: [firstDate, middleDate],
            finalScore: work,
            aggregation: '各月1日・15日の12:00 JSTスコア平均',
          ),
          'money': _periodAreaBreakdownSnapshot(
            area: FortuneArea.money,
            contexts: [first, middle],
            dates: [firstDate, middleDate],
            finalScore: money,
            aggregation: '各月1日・15日の12:00 JSTスコア平均',
          ),
          'mental': _periodAreaBreakdownSnapshot(
            area: FortuneArea.mental,
            contexts: [first, middle],
            dates: [firstDate, middleDate],
            finalScore: mental,
            aggregation: '各月1日・15日の12:00 JSTスコア平均',
          ),
        },
      };
    });
  }

  Map<String, Object?>? _annualLifeEventBoostSnapshot() {
    if (mode != LongRangeMode.year) return null;
    final contexts = <HoroscopeReadingContext>[
      for (var monthIndex = 1; monthIndex <= 12; monthIndex++)
        _contextFor(DateTime(year, monthIndex, 1, 12)),
      for (var monthIndex = 1; monthIndex <= 12; monthIndex++)
        _contextFor(DateTime(year, monthIndex, 15, 12)),
    ];
    final boost = FortuneScoreCalculator.annualLifeEventBoost(contexts);
    if (boost == null) return null;
    return {
      'value': double.parse(boost.value.toStringAsFixed(2)),
      'detail': boost.detail,
      'formula': boost.formula,
      'area_effects': {
        'love': double.parse(
          boost.effectFor(FortuneArea.love).toStringAsFixed(2),
        ),
        'work': double.parse(
          boost.effectFor(FortuneArea.work).toStringAsFixed(2),
        ),
        'money': double.parse(
          boost.effectFor(FortuneArea.money).toStringAsFixed(2),
        ),
        'mental': double.parse(
          boost.effectFor(FortuneArea.mental).toStringAsFixed(2),
        ),
      },
      'rule':
          '年運のみ。木星・土星・外惑星などのリターン、出生図の全天体・ASC・MCへのタイトな調和アスペクト、良いレア配置から最強1件だけを選び、関係する分野へ配分します。総合運は4分野への配分の平均で、各分野は最大+3.5点です。',
    };
  }

  /// プロフィール画面からの出力には画面カードを渡さないため、ここで同じ集計値を
  /// 作る。日別・月別の明細だけでなく、先頭の期間スコアも空にしない。
  /// グラフ用も旧JSONの実点数と同じ式。未使用の詳細Snapshotだけ作らない。
  List<Map<String, Object?>> graphScores() =>
      _periodScores(useProvidedCards: false, includeBreakdowns: false);

  List<Map<String, Object?>> _periodScores({
    bool useProvidedCards = true,
    bool includeBreakdowns = true,
  }) {
    // 画面カードをそのままJSON化する経路でも、年専用補正の分野別根拠を
    // 落とさない。外部AIが「なぜ仕事だけ高いか」を読み取れるようにする。
    AnnualLifeEventBoost? annualLifeEventBoostForOutput;
    if (mode == LongRangeMode.year) {
      final annualContextsForOutput = <HoroscopeReadingContext>[
        for (var monthIndex = 1; monthIndex <= 12; monthIndex++)
          _contextFor(DateTime(year, monthIndex, 1, 12)),
        for (var monthIndex = 1; monthIndex <= 12; monthIndex++)
          _contextFor(DateTime(year, monthIndex, 15, 12)),
      ];
      annualLifeEventBoostForOutput =
          FortuneScoreCalculator.annualLifeEventBoost(annualContextsForOutput);
    }

    String? annualLifeEventEvidenceForTitle(String title) {
      final boost = annualLifeEventBoostForOutput;
      if (boost == null) return null;
      final area = switch (title) {
        '総合運' => FortuneArea.overall,
        '恋愛運' => FortuneArea.love,
        '仕事運' => FortuneArea.work,
        '金運' => FortuneArea.money,
        '健康・メンタル運' => FortuneArea.mental,
        _ => null,
      };
      if (area == null) return null;
      final effect = area == FortuneArea.overall
          ? boost.value
          : boost.effectFor(area);
      if (effect <= 0) return null;
      return '年専用の人生イベント補正: +${effect.toStringAsFixed(2)}点（${boost.detail}） / ${boost.formula}';
    }

    List<String> evidenceWithAnnualLifeEvent(
      List<String> evidence,
      String title,
    ) {
      final annualEvidence = annualLifeEventEvidenceForTitle(title);
      if (annualEvidence == null ||
          evidence.any((item) => item.startsWith('年専用の人生イベント補正:'))) {
        return evidence;
      }
      return [...evidence, annualEvidence];
    }

    final periodBreakdownSnapshots = includeBreakdowns
        ? _periodBreakdownSnapshots()
        : <String, Object?>{};

    if (useProvidedCards && cards.isNotEmpty) {
      return cards
          .map(
            (item) => {
              'area': item.title,
              'score': item.score,
              'sign': item.sign,
              'secondary_sign': item.secondarySign,
              'transit_house': item.transitHouse,
              'natal_house': item.natalHouse,
              'aspect_basis':
                  '代表日（${_dateTimeJst(contextData.transit.date)}）: ${item.aspectBasis.replaceFirst('現在の', '')}',
              'evidence': evidenceWithAnnualLifeEvent(
                item.evidence,
                item.title,
              ),
              'score_aggregation': _scoreAggregation,
              'representative_transit_scope':
                  'sign・transit_house・natal_house・aspect_basisは期間開始日12:00 JSTの代表配置',
              'basis_note':
                  'scoreは${_scoreAggregation}です。日別の配置と点数はdaily_scores、年間の月別データはannual_monthsを参照してください。',
              'representative_transit_date_jst': _dateTimeJst(
                contextData.transit.date,
              ),
              'score_breakdown': periodBreakdownSnapshots[item.title],
            },
          )
          .toList();
    }

    int average(List<int> values) =>
        (values.reduce((sum, value) => sum + value) / values.length).round();
    List<Map<String, Object?>> entries({
      required int overall,
      required int love,
      required int work,
      required int money,
      required int mental,
      String? overallEvidence,
      Map<String, List<String>> areaEvidence = const {},
      Map<String, Object?> scoreBreakdowns = const {},
    }) {
      Map<String, Object?>? breakdownFor(String title) =>
          scoreBreakdowns[title] as Map<String, Object?>?;
      return [
        _periodScoreEntry(
          area: '総合運',
          score: overall,
          evidence: [
            '総合運: 4分野平均を${_scoreAggregation}で集計',
            if (overallEvidence != null) overallEvidence,
          ],
          scoreBreakdown: breakdownFor('総合運'),
        ),
        _periodScoreEntry(
          area: '恋愛運',
          score: love,
          evidence: areaEvidence['恋愛運'] ?? const [],
          scoreBreakdown: breakdownFor('恋愛運'),
        ),
        _periodScoreEntry(
          area: '仕事運',
          score: work,
          evidence: areaEvidence['仕事運'] ?? const [],
          scoreBreakdown: breakdownFor('仕事運'),
        ),
        _periodScoreEntry(
          area: '金運',
          score: money,
          evidence: areaEvidence['金運'] ?? const [],
          scoreBreakdown: breakdownFor('金運'),
        ),
        _periodScoreEntry(
          area: '健康・メンタル運',
          score: mental,
          evidence: areaEvidence['健康・メンタル運'] ?? const [],
          scoreBreakdown: breakdownFor('健康・メンタル運'),
        ),
      ];
    }

    if (mode == LongRangeMode.week) {
      final contexts = List.generate(7, (index) {
        final date = weekStart.add(Duration(days: index));
        return _contextFor(DateTime(date.year, date.month, date.day, 12));
      });
      List<int> scores(FortuneArea area) => contexts
          .map(
            (context) => FortuneScoreCalculator.dailyArea(
              context,
              area,
              FortuneScoreCalculator.standardBase(area),
            ),
          )
          .toList();
      final loveScores = scores(FortuneArea.love);
      final workScores = scores(FortuneArea.work);
      final moneyScores = scores(FortuneArea.money);
      final mentalScores = scores(FortuneArea.mental);
      final overallSamples = List.generate(
        contexts.length,
        (index) => FortuneScoreCalculator.overallWithReturnBonus([
          loveScores[index],
          workScores[index],
          moneyScores[index],
          mentalScores[index],
        ], contexts[index]),
      );
      final peak = FortuneScoreCalculator.periodReturnPeakBonus(contexts);
      return entries(
        overall: (average(overallSamples) + (peak?.value ?? 0))
            .round()
            .clamp(50, 99)
            .toInt(),
        love: average(loveScores),
        work: average(workScores),
        money: average(moneyScores),
        mental: average(mentalScores),
        overallEvidence: peak == null
            ? null
            : '期間ピーク補正: ${peak.planet.label}+${peak.value.toStringAsFixed(1)}点（${peak.detail}）',
        scoreBreakdowns: periodBreakdownSnapshots,
      );
    }

    if (mode == LongRangeMode.month) {
      final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
      final dates =
          <int>{
              1,
              8,
              15,
              22,
              daysInMonth,
            }.map((day) => DateTime(month.year, month.month, day, 12)).toList()
            ..sort();
      final contexts = dates.map((date) => _contextFor(date)).toList();
      List<int> scores(FortuneArea area) => List.generate(
        contexts.length,
        (index) => FortuneScoreCalculator.periodArea(
          area,
          contexts[index],
          dates[index],
          FortuneScoreCalculator.standardBase(area),
        ),
      );
      final loveScores = scores(FortuneArea.love);
      final workScores = scores(FortuneArea.work);
      final moneyScores = scores(FortuneArea.money);
      final mentalScores = scores(FortuneArea.mental);
      final overallSamples = List.generate(
        contexts.length,
        (index) => FortuneScoreCalculator.overallWithReturnBonus([
          loveScores[index],
          workScores[index],
          moneyScores[index],
          mentalScores[index],
        ], contexts[index]),
      );
      final peak = FortuneScoreCalculator.periodReturnPeakBonus(contexts);
      return entries(
        overall: (average(overallSamples) + (peak?.value ?? 0))
            .round()
            .clamp(50, 99)
            .toInt(),
        love: average(loveScores),
        work: average(workScores),
        money: average(moneyScores),
        mental: average(mentalScores),
        overallEvidence: peak == null
            ? null
            : '期間ピーク補正: ${peak.planet.label}+${peak.value.toStringAsFixed(1)}点（${peak.detail}）',
        scoreBreakdowns: periodBreakdownSnapshots,
      );
    }

    final contexts = <HoroscopeReadingContext>[
      for (var monthIndex = 1; monthIndex <= 12; monthIndex++)
        _contextFor(DateTime(year, monthIndex, 1, 12)),
      for (var monthIndex = 1; monthIndex <= 12; monthIndex++)
        _contextFor(DateTime(year, monthIndex, 15, 12)),
    ];
    int annualArea(FortuneArea area) => FortuneScoreCalculator.overallFromAreas(
      List.generate(12, (index) {
        final first = contexts[index];
        final middle = contexts[index + 12];
        final firstScore = FortuneScoreCalculator.periodArea(
          area,
          first,
          first.transit.date,
          FortuneScoreCalculator.standardBase(area),
        );
        final middleScore = FortuneScoreCalculator.periodArea(
          area,
          middle,
          middle.transit.date,
          FortuneScoreCalculator.standardBase(area),
        );
        return ((firstScore + middleScore) / 2).round();
      }),
    );
    final love = annualArea(FortuneArea.love);
    final work = annualArea(FortuneArea.work);
    final money = annualArea(FortuneArea.money);
    final mental = annualArea(FortuneArea.mental);
    final annualBoost = FortuneScoreCalculator.annualLifeEventBoost(contexts);
    final annualAreaEvidence = <String, List<String>>{};
    if (annualBoost != null) {
      for (final entry in const [
        ('恋愛運', FortuneArea.love),
        ('仕事運', FortuneArea.work),
        ('金運', FortuneArea.money),
        ('健康・メンタル運', FortuneArea.mental),
      ]) {
        final effect = annualBoost.effectFor(entry.$2);
        if (effect > 0) {
          annualAreaEvidence[entry.$1] = [
            '年専用の人生イベント補正: +${effect.toStringAsFixed(2)}点（${annualBoost.detail}） / ${annualBoost.formula}',
          ];
        }
      }
    }
    int withAnnualLifeEvent(int score, FortuneArea area) {
      return (score + (annualBoost?.effectFor(area) ?? 0))
          .round()
          .clamp(50, 99)
          .toInt();
    }

    return entries(
      overall: FortuneScoreCalculator.overallFromAreas([
        withAnnualLifeEvent(love, FortuneArea.love),
        withAnnualLifeEvent(work, FortuneArea.work),
        withAnnualLifeEvent(money, FortuneArea.money),
        withAnnualLifeEvent(mental, FortuneArea.mental),
      ]),
      love: withAnnualLifeEvent(love, FortuneArea.love),
      work: withAnnualLifeEvent(work, FortuneArea.work),
      money: withAnnualLifeEvent(money, FortuneArea.money),
      mental: withAnnualLifeEvent(mental, FortuneArea.mental),
      overallEvidence: annualBoost == null
          ? null
          : '年専用の人生イベント補正: +${annualBoost.value.toStringAsFixed(1)}点（${annualBoost.detail}）',
      areaEvidence: annualAreaEvidence,
      scoreBreakdowns: periodBreakdownSnapshots,
    );
  }

  Map<String, Object?> _periodScoreEntry({
    required String area,
    required int score,
    List<String> evidence = const [],
    Map<String, Object?>? scoreBreakdown,
  }) => {
    'area': area,
    'score': score,
    'evidence': evidence,
    'score_aggregation': _scoreAggregation,
    'basis_note':
        'scoreは${_scoreAggregation}です。日別の配置と点数はdaily_scores、年間の月別データはannual_monthsを参照してください。',
    'representative_transit_date_jst': _dateTimeJst(contextData.transit.date),
    if (scoreBreakdown != null) 'score_breakdown': scoreBreakdown,
  };

  Map<String, Object?> _nineAreaPeriodSnapshot(
    List<Map<String, Object?>> legacyScores,
  ) {
    // 旧経路は一枚だけのカードも受け取る。旧欄はそのまま保ち、期間9項目用には
    // 月・年でカードが不完全な場合だけ従来式から一式を計算する。週は日モデルから
    // 7日分を集計し、旧5項目の値を新しい9項目へ流用しない。
    const requiredTitles = ['総合運', '恋愛運', '仕事運', '金運'];
    final complete =
        mode == LongRangeMode.week ||
        requiredTitles.every(
          (title) =>
              legacyScores.where((item) => item['area'] == title).length == 1,
        );
    final summaryLegacy = mode == LongRangeMode.week
        ? const <Map<String, Object?>>[]
        : complete
        ? legacyScores
        : _periodScores(useProvidedCards: false);
    final dates = switch (mode) {
      LongRangeMode.week => [
        for (var index = 0; index < 7; index++)
          DateTime.utc(
            weekStart.year,
            weekStart.month,
            weekStart.day + index,
            3,
          ),
      ],
      LongRangeMode.month => List.generate(
        DateTime(month.year, month.month + 1, 0).day,
        (index) => DateTime.utc(month.year, month.month, index + 1, 3),
      ),
      LongRangeMode.year => [
        for (var monthIndex = 1; monthIndex <= 12; monthIndex++)
          for (final day in const [1, 15])
            DateTime.utc(year, monthIndex, day, 3),
      ],
    };
    final sampleBasis = switch (mode) {
      LongRangeMode.week => 'seven_consecutive_calendar_days',
      LongRangeMode.month => 'all_calendar_days',
      LongRangeMode.year => 'first_and_fifteenth_each_month',
    };
    final summarySamples = <String, List<NineAreaPrediction>>{};
    final periodSummary = NineAreaPeriodSummary.build(
      mode: mode,
      month: month,
      year: year,
      weekStart: mode == LongRangeMode.week ? weekStart : null,
      useGeneralModel: true,
      legacyScores: mode == LongRangeMode.week
          ? const <NineAreaKey, int>{}
          : {
              for (final key in NineAreaKey.values.take(4))
                key:
                    summaryLegacy.singleWhere(
                          (item) =>
                              item['area'] ==
                              switch (key) {
                                NineAreaKey.overall => '総合運',
                                NineAreaKey.love => '恋愛運',
                                NineAreaKey.work => '仕事運',
                                NineAreaKey.money => '金運',
                                _ => throw StateError('旧期間点のキーが不正です。'),
                              },
                        )['score']!
                        as int,
            },
      dailyFor: (date) {
        final predictions = NineAreaDailyForecast.fromContext(
          _contextFor(date),
        );
        summarySamples[NineAreaPeriodSummary.dateLabel(date)] = predictions;
        return predictions;
      },
      legacySourcePrefix: complete
          ? 'period_scores'
          : 'nine_area_period.legacy_period_scores_for_summary',
    );
    const explanationStrings = AppStrings(AppLanguage.ja);
    return {
      'schema': 'pancyo_nine_area_period_consult_v1',
      'purpose': 'ai_chat_consultation_not_prospective_validation',
      'model_version': NineAreaDailyForecast.modelVersion,
      'ephemeris_time_contract': 'instant_to_utc_v1',
      'period_type': mode.name,
      'sampling': {
        'basis': sampleBasis,
        'sample_count': dates.length,
        'all_calendar_days_included':
            mode == LongRangeMode.week || mode == LongRangeMode.month,
        'timezone': 'Asia/Tokyo',
        'calculation_time': '12:00 JST',
        'note': switch (mode) {
          LongRangeMode.week => '指定週の7日間すべての12:00 JSTを含む。',
          LongRangeMode.month => '指定月の全日の12:00 JSTを含む。',
          LongRangeMode.year => '各月1日・15日の計24時点。年内全日を含むデータではなく、他の日の値を補間しない。',
        },
      },
      'aggregation': {
        'numeric_scores': 'per_sample_daily_scores_without_period_adjustments',
        'felt': 'per_sample_categorical_labels_not_numeric',
        'period_scores_generated': true,
        'note':
            'daily_samplesは同じ日の一般向け暫定式9項目。summaryは同じ日点数による期間代表値（週7日／月5／年24時点）。体感の数値化・平均・未予測の補完は行わない。旧period_scoresやannual_months.scoresは従来集計値として保持する。',
      },
      if (!complete) 'legacy_period_scores_for_summary': summaryLegacy,
      if (!complete)
        'incomplete_cards_note':
            '旧period_scoresは受け取った部分カードのまま保持。summaryは一般向け暫定式の日点数から別途集計する。',
      'summary': periodSummary.toJson(),
      'presentation_explanation': {
        'schema': _presentationExplanationSchema,
        'language': 'ja',
        'areas': [
          for (final area in periodSummary.areas)
            ForecastExplanation.forPeriod(
              summary: periodSummary,
              area: area,
              strings: explanationStrings,
              depth: ReadingDepth.detailed,
              supplement: details,
              dailySamples: summarySamples,
            ).toJson(),
        ],
      },
      'daily_samples': [
        for (final date in dates)
          NineAreaDailyConsultSnapshot.build(
            date: date,
            contextData: _contextFor(date),
          ),
      ],
    };
  }

  Map<String, Object?> buildData({DateTime? generatedAt}) {
    final legacyScores = _periodScores();
    return {
      'schema': 'pancyo_astrology_external_consult_v3',
      'generated_at': (generatedAt ?? DateTime.now()).toIso8601String(),
      'birth_input_quality': _consultBirthInputQualitySnapshot(
        profile,
        details,
        contextData,
      ),
      'period': {
        'type': mode.name,
        'label': periodLabel,
        'timezone': 'Asia/Tokyo',
        'calculation_time': '12:00 JST',
        'notice': switch (mode) {
          LongRangeMode.week =>
            '週間は7日分の日別配置と9項目を参照してください。従来5項目のperiod_scoresは参考値として保持しています。period_start_transitは期間開始日の値です。',
          LongRangeMode.month =>
            '月間は日別配置、年間は各月1日・15日の配置を参照してください。period_start_transitは期間開始日の値です。',
          LongRangeMode.year =>
            '月間は日別配置、年間は各月1日・15日の配置を参照してください。period_start_transitは期間開始日の値です。',
        },
      },
      'profile': {
        'birth_date': profile.birthDate,
        'birth_time': profile.birthTime,
        'birth_place': profile.birthPlace,
        'theme': profile.theme,
        'concerns': details.concerns,
        'reading_style': details.readingStyle,
      },
      'house_calculation': _houseCalculationSnapshot(contextData),
      'natal_placements': contextData.natal.placements
          .map(
            (item) => {
              'planet': item.planet.label,
              'sign': item.sign.label,
              'degree': item.degree,
              'house': item.house,
            },
          )
          .toList(),
      'natal_retrograde_planets': contextData.natal.retrogradePlanets
          .map((item) => item.label)
          .toList(),
      // 旧v1のtransit_placementsは月初日の値を日付なしで出していた。
      // v2では期間開始日を明示し、月間は日別、年間は月別の配置を併記する。
      'period_start_transit': _transitSnapshot(contextData),
      'period_scores': legacyScores,
      if (mode == LongRangeMode.year)
        'annual_life_event_boost': _annualLifeEventBoostSnapshot(),
      if (mode == LongRangeMode.week)
        'daily_scores': List.generate(7, (index) {
          final day = weekStart.add(Duration(days: index));
          return _dailySnapshot(DateTime(day.year, day.month, day.day, 12));
        }),
      if (mode == LongRangeMode.month)
        'daily_scores': List.generate(
          DateTime(month.year, month.month + 1, 0).day,
          (index) =>
              _dailySnapshot(DateTime(month.year, month.month, index + 1, 12)),
        ),
      if (mode == LongRangeMode.year) 'annual_months': _annualMonths(),
      if (includeNineAreaSamples) ...{
        'primary_fortune_data': 'nine_area_period.daily_samples',
        'nine_area_period': _nineAreaPeriodSnapshot(legacyScores),
        'legacy_field_notes': {
          'period_scores': mode == LongRangeMode.week
              ? '週の旧5項目は従来の期間集計値のまま保持。新9項目はnine_area_period.daily_samplesの7日分を使い、同じ値とは限らない。'
              : '従来5項目の期間集計値。新9項目の日別値はnine_area_period.daily_samplesを使う。集計時点・期間補正が異なるため、日別9項目の平均と同じ値とは限らない。',
          if (mode == LongRangeMode.week)
            'daily_scores.mental': '従来の健康・メンタル合算点。新しい分離メンタル・健康で上書きしていない。',
          if (mode == LongRangeMode.month)
            'daily_scores.mental': '従来の健康・メンタル合算点。新しい分離メンタル・健康で上書きしていない。',
          if (mode == LongRangeMode.year)
            'annual_months.scores.mental':
                '従来の健康・メンタル合算点の月別集計。新しい分離メンタル・健康で上書きしていない。',
          'new_period_scores':
              'nine_area_period.summaryは一般向け暫定式の期間集計。週は7日／月は5時点／年は24時点、数値8項目は同じ日点数を集計。総合は日別6成果分野平均に基づき、活動性・体感・追加ボーナスを含めない。体感は候補件数であり数値平均しない。',
        },
      },
    };
  }
}
