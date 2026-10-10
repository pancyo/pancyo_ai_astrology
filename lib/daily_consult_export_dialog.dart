part of 'main.dart';

/// A page owns this token; replacing inputs or disposing cancels its export.
class DailyConsultExportOwner extends ChangeNotifier {
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

Object? _dailyConsultExportActive;

Future<void> _exportDailyConsultJson(
  BuildContext context, {
  required DateTime date,
  required AstroProfile profile,
  required UserProfileDetails details,
  required DailyConsultExportOwner owner,
  HoroscopeReadingContext? contextData,
  DailyConsultExportStarter? startJob,
}) async {
  if (!context.mounted || !owner.alive || _dailyConsultExportActive != null)
    return;
  final ticket = Object();
  _dailyConsultExportActive = ticket;
  final revision = owner.revision;
  final origin = ModalRoute.of(context);
  final houseSystem = HouseSystemSettings.current.value;
  // A destroyed Navigator may never complete its DialogRoute future. Release
  // this export on owner invalidation too, without releasing a newer ticket.
  final cancelled = Completer<File?>();
  void ownerChanged() {
    if ((!owner.alive || owner.revision != revision) && !cancelled.isCompleted)
      cancelled.complete(null);
  }

  owner.addListener(ownerChanged);
  bool current() =>
      context.mounted &&
      owner.alive &&
      owner.revision == revision &&
      HouseSystemSettings.current.value == houseSystem;
  try {
    final request = DailyConsultExportRequest(
      date: date,
      profile: profile,
      details: details,
      requestedHouseSystem: houseSystem,
      sourceName:
          contextData?.ephemerisSourceName ??
          AstrologyDataSources.current.sourceName,
      requireHighPrecision:
          contextData?.usesHighPrecisionAstroData ??
          AstrologyDataSources.current.usesHighPrecisionAstroData,
      generatedAt: DateTime.now(),
      contextData: contextData,
    );
    final dialog = showDialog<File>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DailyConsultJsonExportDialog(
        request: request,
        owner: owner,
        startJob: startJob,
      ),
    );
    final file = await Future.any<File?>([dialog, cancelled.future]);
    if (file == null || !current() || origin?.isCurrent == false) return;
    final result = await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/json')],
      subject: AppLanguageSettings.strings.text(
        AppText.consultJsonShareSubject,
      ),
    );
    if (current() && origin?.isCurrent != false) {
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
    owner.removeListener(ownerChanged);
    if (identical(_dailyConsultExportActive, ticket))
      _dailyConsultExportActive = null;
  }
}

class DailyConsultJsonExportDialog extends StatefulWidget {
  const DailyConsultJsonExportDialog({
    super.key,
    required this.request,
    required this.owner,
    this.startJob,
  });
  final DailyConsultExportRequest request;
  final DailyConsultExportOwner owner;
  final DailyConsultExportStarter? startJob;
  @override
  State<DailyConsultJsonExportDialog> createState() =>
      _DailyConsultJsonExportDialogState();
}

class _DailyConsultJsonExportDialogState
    extends State<DailyConsultJsonExportDialog> {
  DailyConsultExportOperation? _job;
  late int _revision;
  int _generation = 0, _done = 0;
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
    widget.owner.addListener(_inputsChanged);
    HouseSystemSettings.current.addListener(_settingsChanged);
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
      HouseSystemSettings.current.value == widget.request.requestedHouseSystem;
  void _settingsChanged() {
    if (!_current) _cancel();
  }

  void _inputsChanged() => _cancel();
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
    widget.owner.removeListener(_inputsChanged);
    HouseSystemSettings.current.removeListener(_settingsChanged);
    super.dispose();
  }

  Future<void> _start() async {
    if (!_current || _working) return;
    final generation = ++_generation;
    setState(() {
      _working = true;
      _error = null;
      _done = 0;
    });
    try {
      final job = (widget.startJob ?? DailyConsultExportJob.start)(
        widget.request,
        (done, total) {
          if (_current && generation == _generation)
            setState(() {
              _done = done;
            });
        },
      );
      _job = job;
      final result = await job.result;
      if (!_current || generation != _generation) return;
      _job = null;
      if (result.requestIdentity != widget.request.identity)
        throw StateError('日JSONの入力が一致しません。');
      final data = result.data;
      final intraday = data['intraday_positions'] as Map;
      final forecasts = data['intraday_forecasts'] as Map;
      if (data['schema'] != 'pancyo_astrology_daily_consult_v4' ||
          intraday['target_date_jst'] != widget.request.plan.targetDateJst ||
          (intraday['points'] as List).length != 7 ||
          (intraday['completeness'] as Map)['status'] != 'complete' ||
          forecasts['target_date_jst'] != widget.request.plan.targetDateJst ||
          (forecasts['points'] as List).length != 7 ||
          (forecasts['completeness'] as Map)['status'] != 'complete') {
        throw StateError('日JSONの7時点が完成していません。');
      }
      final directory = await getTemporaryDirectory();
      if (!_current || generation != _generation) return;
      final file = await ConsultJsonFileWriter.write(
        temporaryRoot: directory,
        data: data,
        participantName: widget.request.profile.name,
        kind: 'daily',
        period: widget.request.plan.targetDateJst.replaceAll('-', ''),
        generatedAt: widget.request.generatedAt,
      );
      // Cancellation while writing may leave a private temporary file, never a share.
      if (!_current || generation != _generation) return;
      _closing = true;
      Navigator.of(context).pop(file);
    } catch (error) {
      if (!_current || generation != _generation) return;
      _job = null;
      setState(() {
        _working = false;
        _error = error is DailyConsultExportCancelled
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
          title: Text(strings.text(AppText.createDailyJson)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_working) const LinearProgressIndicator(),
                const SizedBox(height: 12),
                Text(
                  _error != null
                      ? strings.text(_error!)
                      : _done == 7
                      ? strings.text(AppText.consultJsonCombining)
                      : strings.dailyJsonProgress(_done),
                ),
                const SizedBox(height: 8),
                Text(
                  strings.text(AppText.dailyJsonDialogHelp),
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

String _dailyConsultOwnerInput(AstroProfile p, UserProfileDetails d) =>
    jsonEncode([
      p.name,
      p.birthDate,
      p.birthTime,
      p.birthPlace,
      p.theme,
      p.savedProfileId,
      d.toJson(),
    ]);

class _DailyAstroDataExportCardState extends State<DailyAstroDataExportCard> {
  final _owner = DailyConsultExportOwner();
  final _weeklyOwner = WeeklyDailyConsultExportOwner();
  @override
  void didUpdateWidget(covariant DailyAstroDataExportCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.date != widget.date ||
        !identical(oldWidget.contextData, widget.contextData) ||
        _dailyConsultOwnerInput(oldWidget.profile, oldWidget.details) !=
            _dailyConsultOwnerInput(widget.profile, widget.details) ||
        oldWidget.startJob != widget.startJob) {
      _owner.invalidate();
    }
    if (oldWidget.date != widget.date ||
        _dailyConsultOwnerInput(oldWidget.profile, oldWidget.details) !=
            _dailyConsultOwnerInput(widget.profile, widget.details) ||
        oldWidget.startWeeklyJob != widget.startWeeklyJob) {
      _weeklyOwner.invalidate();
    }
  }

  @override
  void dispose() {
    _owner.dispose();
    _weeklyOwner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget._build(
    context,
    () => _exportDailyConsultJson(
      context,
      date: widget.date,
      profile: widget.profile,
      details: widget.details,
      contextData: widget.contextData,
      owner: _owner,
      startJob: widget.startJob,
    ),
    () => _exportWeeklyDailyConsultJson(
      context,
      startDate: DateTime.utc(
        widget.date.year,
        widget.date.month,
        widget.date.day,
        3,
      ),
      profile: widget.profile,
      details: widget.details,
      owner: _weeklyOwner,
      startJob: widget.startWeeklyJob,
    ),
  );
}
