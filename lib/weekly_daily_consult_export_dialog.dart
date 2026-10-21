part of 'main.dart';

/// A weekly day-JSON export belongs to one selected date and profile.
class WeeklyDailyConsultExportOwner extends ChangeNotifier {
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

String _weeklyDailyExportText(AppLanguage language, String ja, String en) =>
    language == AppLanguage.en ? en : ja;

String _weeklyStartJst(DateTime instant) {
  final jst = instant.toUtc().add(const Duration(hours: 9));
  return '${jst.year.toString().padLeft(4, '0')}-'
      '${jst.month.toString().padLeft(2, '0')}-'
      '${jst.day.toString().padLeft(2, '0')}';
}

DateTime _weeklyNoonJst(DateTime value) {
  final day = _weeklyStartJst(value);
  final parts = day.split('-').map(int.parse).toList(growable: false);
  return DateTime.utc(parts[0], parts[1], parts[2], 3);
}

Object? _weeklyDailyExportActive;

Future<void> _exportWeeklyDailyConsultJson(
  BuildContext context, {
  required DateTime startDate,
  required AstroProfile profile,
  required UserProfileDetails details,
  required WeeklyDailyConsultExportOwner owner,
  WeeklyDailyConsultExportStarter? startJob,
}) async {
  if (!context.mounted || !owner.alive || _weeklyDailyExportActive != null) {
    return;
  }
  final ticket = Object();
  _weeklyDailyExportActive = ticket;
  final revision = owner.revision;
  final origin = ModalRoute.of(context);
  final houseSystem = HouseSystemSettings.current.value;
  final cancelled = Completer<File?>();

  void ownerChanged() {
    if ((!owner.alive || owner.revision != revision) &&
        !cancelled.isCompleted) {
      cancelled.complete(null);
    }
  }

  owner.addListener(ownerChanged);
  bool current() =>
      context.mounted &&
      owner.alive &&
      owner.revision == revision &&
      HouseSystemSettings.current.value == houseSystem;

  try {
    final jstNoon = _weeklyNoonJst(startDate);
    final source = AstrologyDataSources.current;
    final request = WeeklyDailyConsultExportRequest(
      startDate: jstNoon,
      profile: profile,
      details: details,
      requestedHouseSystem: houseSystem,
      sourceName: source.sourceName,
      requireHighPrecision: source.usesHighPrecisionAstroData,
      generatedAt: DateTime.now(),
    );
    final dialog = showDialog<File>(
      context: context,
      barrierDismissible: false,
      builder: (_) => WeeklyDailyConsultExportDialog(
        request: request,
        owner: owner,
        startJob: startJob,
      ),
    );
    final file = await Future.any<File?>([dialog, cancelled.future]);
    if (file == null || !current() || origin?.isCurrent == false) return;
    final result = await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/json')],
      subject: _weeklyDailyExportText(
        AppLanguageSettings.strings.language,
        '日別占いデータの週版（7日・49時点）',
        'Daily reading data, weekly version (7 days, 49 time points)',
      ),
    );
    if (current() && origin?.isCurrent != false) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: ValueListenableBuilder<AppLanguage>(
            valueListenable: AppLanguageSettings.current,
            builder: (_, language, _) => Text(
              _weeklyDailyExportShareMessage(
                result,
                file.uri.pathSegments.last,
                language,
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
              _weeklyDailyExportText(
                language,
                '週版JSONを出力できませんでした。',
                'Could not export the weekly JSON.',
              ),
            ),
          ),
        ),
      );
    }
  } finally {
    owner.removeListener(ownerChanged);
    if (identical(_weeklyDailyExportActive, ticket)) {
      _weeklyDailyExportActive = null;
    }
  }
}

String _weeklyDailyExportShareMessage(
  ShareResult result,
  String filename,
  AppLanguage language,
) => switch (result.status) {
  ShareResultStatus.success => _weeklyDailyExportText(
    language,
    '週版JSONを作成し、共有先へ渡しました：$filename（保存完了は共有先で確認してください）',
    'Weekly JSON created and passed to the sharing destination: $filename (check there that saving has completed)',
  ),
  ShareResultStatus.dismissed => _weeklyDailyExportText(
    language,
    '共有をキャンセルしました。週版JSONは一時作成のみです：$filename',
    'Sharing cancelled. The weekly JSON was only created temporarily: $filename',
  ),
  ShareResultStatus.unavailable => _weeklyDailyExportText(
    language,
    '週版JSONを一時作成しました。共有先での保存結果は確認できません：$filename',
    'A temporary weekly JSON was created. Saving at the destination could not be confirmed: $filename',
  ),
};

class WeeklyDailyConsultExportDialog extends StatefulWidget {
  const WeeklyDailyConsultExportDialog({
    super.key,
    required this.request,
    required this.owner,
    this.startJob,
  });

  final WeeklyDailyConsultExportRequest request;
  final WeeklyDailyConsultExportOwner owner;
  final WeeklyDailyConsultExportStarter? startJob;

  @override
  State<WeeklyDailyConsultExportDialog> createState() =>
      _WeeklyDailyConsultExportDialogState();
}

class _WeeklyDailyConsultExportDialogState
    extends State<WeeklyDailyConsultExportDialog> {
  WeeklyDailyConsultExportOperation? _job;
  late int _revision;
  int _generation = 0, _done = 0;
  bool _working = false, _closing = false;
  bool? _cancelledError;
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
      if (navigator?.mounted == true && route?.isActive == true) {
        navigator!.removeRoute(route!);
      }
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
      _cancelledError = null;
      _done = 0;
    });
    try {
      final job = (widget.startJob ?? WeeklyDailyConsultExportJob.start)(
        widget.request,
        (done, total) {
          if (_current && generation == _generation) {
            setState(() => _done = done.clamp(0, 49));
          }
        },
      );
      _job = job;
      final result = await job.result;
      if (!_current || generation != _generation) return;
      _job = null;
      if (result.requestIdentity != widget.request.identity) {
        throw StateError('週版JSONの入力が一致しません。');
      }
      final data = result.data;
      _validateWeeklyDailyConsultData(data, widget.request);
      final directory = await getTemporaryDirectory();
      if (!_current || generation != _generation) return;
      final file = await ConsultJsonFileWriter.write(
        temporaryRoot: directory,
        data: data,
        participantName: widget.request.profile.name,
        kind: 'week',
        period: widget.request.startDateJst.replaceAll('-', ''),
        generatedAt: widget.request.generatedAt,
      );
      if (!_current || generation != _generation) return;
      _closing = true;
      Navigator.of(context).pop(file);
    } catch (error) {
      if (!_current || generation != _generation) return;
      _job = null;
      setState(() {
        _working = false;
        _cancelledError = error is WeeklyDailyConsultExportCancelled;
      });
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppLanguage>(
    valueListenable: AppLanguageSettings.current,
    builder: (context, language, _) {
      final title = _weeklyDailyExportText(
        language,
        '日別占いデータの週版',
        'Daily reading data: weekly version',
      );
      final cancelledError = _cancelledError;
      final error = cancelledError == null
          ? null
          : _weeklyDailyExportText(
              language,
              cancelledError
                  ? '作成を中止しました。再試行できます。'
                  : '7日・49時点の週版JSONを完成できませんでした。再試行できます。',
              cancelledError
                  ? 'Export cancelled. You can try again.'
                  : 'The 7-day, 49-point JSON is incomplete. You can try again.',
            );
      final progress = _done == 49
          ? _weeklyDailyExportText(
              language,
              '7日分をまとめています…',
              'Finishing the 7-day file…',
            )
          : _weeklyDailyExportText(
              language,
              '週版JSONを作成中…（$_done/49時点）',
              'Creating weekly JSON… ($_done/49 points)',
            );
      return PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_working) const LinearProgressIndicator(),
                const SizedBox(height: 12),
                Text(error ?? progress),
                const SizedBox(height: 8),
                Text(
                  _weeklyDailyExportText(
                    language,
                    '選択日から7日間、各日の00・04・08・12・16・20・24時のデータを収録します。24時と翌日00時は同じ瞬間です。',
                    'Includes seven days from the selected date, with data at 00:00, 04:00, 08:00, 12:00, 16:00, 20:00, and 24:00 JST each day. 24:00 and the next day’s 00:00 are the same instant.',
                  ),
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: _cancel,
              child: Text(
                _weeklyDailyExportText(
                  language,
                  _working ? '中止' : '閉じる',
                  _working ? 'Cancel' : 'Close',
                ),
              ),
            ),
            if (!_working)
              FilledButton(
                onPressed: _start,
                child: Text(_weeklyDailyExportText(language, '再試行', 'Retry')),
              ),
          ],
        ),
      );
    },
  );
}

void _validateWeeklyDailyConsultData(
  Map<String, Object?> data,
  WeeklyDailyConsultExportRequest request,
) {
  _weeklyValidateWrapper(data);
  final week = _weeklyMap(data['week'], '週版JSONの対象期間');
  if (data['generated_at'] != request.generatedAt.toIso8601String() ||
      week['start_date_jst'] != request.startDateJst ||
      week['end_date_jst'] != request.endDateJst ||
      week['calculation_reference_time_jst'] != '12:00' ||
      week['day_count'] != 7) {
    throw StateError('週版JSONの作成時刻が一致しません。');
  }
  final days = data['days'] as List;
  for (var i = 0; i < days.length; i++) {
    _weeklyValidateDailyV4(
      _weeklyMap(days[i], '週版JSONの日次[$i]'),
      request: request,
      plan: request.dayPlans[i],
    );
  }
}
