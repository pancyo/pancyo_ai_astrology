part of 'main.dart';

/// A monthly day-JSON export belongs to one selected date and profile.
class MonthlyDailyConsultExportOwner extends ChangeNotifier {
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

String _monthlyDailyExportText(AppLanguage language, String ja, String en) =>
    language == AppLanguage.en ? en : ja;

String _monthlyStartJst(DateTime instant) {
  final jst = instant.toUtc().add(const Duration(hours: 9));
  return '${jst.year.toString().padLeft(4, '0')}-'
      '${jst.month.toString().padLeft(2, '0')}-'
      '${jst.day.toString().padLeft(2, '0')}';
}

DateTime _monthlyNoonJst(DateTime value) {
  final day = _monthlyStartJst(value);
  final parts = day.split('-').map(int.parse).toList(growable: false);
  return DateTime.utc(parts[0], parts[1], parts[2], 3);
}

Object? _monthlyDailyExportActive;

Future<void> _exportMonthlyDailyConsultJson(
  BuildContext context, {
  required DateTime startDate,
  required AstroProfile profile,
  required UserProfileDetails details,
  required MonthlyDailyConsultExportOwner owner,
  MonthlyDailyConsultExportStarter? startJob,
}) async {
  if (!context.mounted || !owner.alive || _monthlyDailyExportActive != null) {
    return;
  }
  final ticket = Object();
  _monthlyDailyExportActive = ticket;
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
    final selected = startDate.toUtc().add(const Duration(hours: 9));
    final jstNoon = DateTime.utc(selected.year, selected.month, 1, 3);
    final source = AstrologyDataSources.current;
    final request = MonthlyDailyConsultExportRequest(
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
      builder: (_) => MonthlyDailyConsultExportDialog(
        request: request,
        owner: owner,
        startJob: startJob,
      ),
    );
    final file = await Future.any<File?>([dialog, cancelled.future]);
    if (file == null || !current() || origin?.isCurrent == false) return;
    final result = await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/json')],
      subject: _monthlyDailyExportText(
        AppLanguageSettings.strings.language,
        '日別占いデータの月間7点版',
        'Daily reading data, monthly version (7 time points per day)',
      ),
    );
    if (current() && origin?.isCurrent != false) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: ValueListenableBuilder<AppLanguage>(
            valueListenable: AppLanguageSettings.current,
            builder: (_, language, _) => Text(
              _monthlyDailyExportShareMessage(
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
              _monthlyDailyExportText(
                language,
                '月間7点版JSONを出力できませんでした。',
                'Could not export the monthly JSON.',
              ),
            ),
          ),
        ),
      );
    }
  } finally {
    owner.removeListener(ownerChanged);
    if (identical(_monthlyDailyExportActive, ticket)) {
      _monthlyDailyExportActive = null;
    }
  }
}

String _monthlyDailyExportShareMessage(
  ShareResult result,
  String filename,
  AppLanguage language,
) => switch (result.status) {
  ShareResultStatus.success => _monthlyDailyExportText(
    language,
    '月間7点版JSONを作成し、共有先へ渡しました：$filename（保存完了は共有先で確認してください）',
    'Monthly JSON created and passed to the sharing destination: $filename (check there that saving has completed)',
  ),
  ShareResultStatus.dismissed => _monthlyDailyExportText(
    language,
    '共有をキャンセルしました。月間7点版JSONは一時作成のみです：$filename',
    'Sharing cancelled. The monthly JSON was only created temporarily: $filename',
  ),
  ShareResultStatus.unavailable => _monthlyDailyExportText(
    language,
    '月間7点版JSONを一時作成しました。共有先での保存結果は確認できません：$filename',
    'A temporary monthly JSON was created. Saving at the destination could not be confirmed: $filename',
  ),
};

class MonthlyDailyConsultExportDialog extends StatefulWidget {
  const MonthlyDailyConsultExportDialog({
    super.key,
    required this.request,
    required this.owner,
    this.startJob,
  });

  final MonthlyDailyConsultExportRequest request;
  final MonthlyDailyConsultExportOwner owner;
  final MonthlyDailyConsultExportStarter? startJob;

  @override
  State<MonthlyDailyConsultExportDialog> createState() =>
      _MonthlyDailyConsultExportDialogState();
}

class _MonthlyDailyConsultExportDialogState
    extends State<MonthlyDailyConsultExportDialog> {
  MonthlyDailyConsultExportOperation? _job;
  late int _revision;
  int _generation = 0, _done = 0;
  bool _working = false, _closing = false, _started = false;
  final _watch = Stopwatch();
  Timer? _ticker;
  int _seconds = 0;
  int? get _remainingSeconds => _done < 7 || _seconds < 1
      ? null
      : ((_seconds / _done) * (widget.request.listedPointCount - _done)).ceil();
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
  }

  bool get _current =>
      mounted &&
      !_closing &&
      widget.owner.alive &&
      widget.owner.revision == _revision &&
      HouseSystemSettings.current.value ==
          widget.request.requestedHouseSystem &&
      AstrologyDataSources.current.sourceName == widget.request.sourceName &&
      AstrologyDataSources.current.usesHighPrecisionAstroData ==
          widget.request.requireHighPrecision;

  void _settingsChanged() {
    if (!_current) _cancel();
  }

  void _inputsChanged() => _cancel();

  void _cancel() {
    if (_closing) return;
    _closing = true;
    _generation++;
    _ticker?.cancel();
    _watch.stop();
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
    _ticker?.cancel();
    _watch.stop();
    _job?.cancel();
    widget.owner.removeListener(_inputsChanged);
    HouseSystemSettings.current.removeListener(_settingsChanged);
    super.dispose();
  }

  Future<void> _start() async {
    if (!_current || _working) return;
    final generation = ++_generation;
    _started = true;
    _watch.reset();
    _watch.start();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_current) setState(() => _seconds = _watch.elapsed.inSeconds);
    });
    setState(() {
      _working = true;
      _cancelledError = null;
      _done = 0;
      _seconds = 0;
    });
    try {
      final job = (widget.startJob ?? MonthlyDailyConsultExportJob.start)(
        widget.request,
        (done, total) {
          if (_current && generation == _generation) {
            setState(
              () => _done = done.clamp(0, widget.request.listedPointCount),
            );
          }
        },
      );
      _job = job;
      final result = await job.result;
      if (!_current || generation != _generation) return;
      _job = null;
      if (result.requestIdentity != widget.request.identity) {
        throw StateError('月間7点版JSONの入力が一致しません。');
      }
      final directory = await getTemporaryDirectory();
      if (!_current || generation != _generation) return;
      final file = await MonthlyDailyConsultFileWriter.writeResult(
        temporaryRootPath: directory.path,
        result: result,
        request: widget.request,
      );
      if (!_current || generation != _generation) {
        await file.parent.delete(recursive: true);
        return;
      }
      _ticker?.cancel();
      _watch.stop();
      _closing = true;
      Navigator.of(context).pop(file);
    } catch (error) {
      if (!_current || generation != _generation) return;
      _job = null;
      _ticker?.cancel();
      _watch.stop();
      setState(() {
        _working = false;
        _cancelledError = error is MonthlyDailyConsultExportCancelled;
      });
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppLanguage>(
    valueListenable: AppLanguageSettings.current,
    builder: (context, language, _) {
      final title = _monthlyDailyExportText(
        language,
        '日別占いデータの月間7点版',
        'Daily reading data: monthly version',
      );
      final cancelledError = _cancelledError;
      final error = cancelledError == null
          ? null
          : _monthlyDailyExportText(
              language,
              cancelledError
                  ? '作成を中止しました。再試行できます。'
                  : '${widget.request.dayCount}日・${widget.request.listedPointCount}時点の月間7点版JSONを完成できませんでした。再試行できます。',
              cancelledError
                  ? 'Export cancelled. You can try again.'
                  : 'The ${widget.request.dayCount}-day, ${widget.request.listedPointCount}-point JSON is incomplete. You can try again.',
            );
      final progress = _done == widget.request.listedPointCount
          ? _monthlyDailyExportText(
              language,
              '全日分を検査・保存しています…',
              'Validating and saving the complete month…',
            )
          : _monthlyDailyExportText(
              language,
              '月間7点版JSONを作成中…（$_done/${widget.request.listedPointCount}時点）',
              'Creating monthly JSON… ($_done/${widget.request.listedPointCount} points)',
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
                if (_working)
                  LinearProgressIndicator(
                    value: _done < widget.request.listedPointCount
                        ? _done / widget.request.listedPointCount
                        : null,
                  ),
                const SizedBox(height: 12),
                Text(
                  error ??
                      (_started
                          ? progress
                          : _monthlyDailyExportText(
                              language,
                              '対象：${widget.request.startDateJst}〜${widget.request.endDateJst}（${widget.request.dayCount}日・${widget.request.listedPointCount}時点）。計算には時間がかかります。開始前の所要時間は未計測です。計算中の実測から残り時間の目安を表示します。',
                              'Target: ${widget.request.startDateJst}–${widget.request.endDateJst} (${widget.request.dayCount} days, ${widget.request.listedPointCount} points). This can take a long time. No measured estimate is available before starting. Remaining time will be estimated from progress.',
                            )),
                ),
                if (_working)
                  Text(
                    _monthlyDailyExportText(
                      language,
                      '実測経過：${_seconds}秒 ／ ${_done == widget.request.listedPointCount ? "検査・保存中（残り時間の見積外）" : _remainingSeconds == null ? "残り時間は計測中" : "推定残り計算：約${_remainingSeconds}秒（実測進捗からの目安、保存時間は別）"}',
                      'Elapsed: ${_seconds}s / ${_done == widget.request.listedPointCount ? "Validating and saving (outside estimate)" : _remainingSeconds == null ? "Measuring remaining time" : "Estimated remaining calculation: about ${_remainingSeconds}s (saving is separate)"}',
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  _monthlyDailyExportText(
                    language,
                    '選択月の1日から末日まで、各日の00・04・08・12・16・20・24時のデータを収録します。24時と翌日00時は同じ瞬間です。',
                    'Includes the entire selected calendar month, with data at 00:00, 04:00, 08:00, 12:00, 16:00, 20:00, and 24:00 JST each day. 24:00 and the next day’s 00:00 are the same instant.',
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
                _monthlyDailyExportText(
                  language,
                  _working ? '中止' : '閉じる',
                  _working ? 'Cancel' : 'Close',
                ),
              ),
            ),
            if (!_working)
              FilledButton(
                onPressed: _start,
                child: Text(
                  _monthlyDailyExportText(
                    language,
                    _started ? '再試行' : '開始',
                    _started ? 'Retry' : 'Start',
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

void _validateMonthlyDailyConsultData(
  Map<String, Object?> data,
  MonthlyDailyConsultExportRequest request,
) {
  _monthlyValidateWrapper(data);
  final week = _monthlyMap(data['month'], '月間7点版JSONの対象期間');
  if (data['generated_at'] != request.generatedAt.toIso8601String() ||
      week['start_date_jst'] != request.startDateJst ||
      week['end_date_jst'] != request.endDateJst ||
      week['calculation_reference_time_jst'] != '12:00' ||
      week['day_count'] != request.dayCount) {
    throw StateError('月間7点版JSONの作成時刻が一致しません。');
  }
  final days = data['days'] as List;
  for (var i = 0; i < days.length; i++) {
    _monthlyValidateDailyV4(
      _monthlyMap(days[i], '月間7点版JSONの日次[$i]'),
      request: request,
      plan: request.dayPlans[i],
    );
  }
}
