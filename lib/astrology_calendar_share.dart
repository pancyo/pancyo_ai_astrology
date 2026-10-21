part of 'main.dart';

/// A month snapshot contains only public astronomical calendar fields. It has
/// no profile, birth input, scores, diary or user-supplied caption.
class AstrologyCalendarShareData {
  AstrologyCalendarShareData._(this.year, this.month, this.days);

  factory AstrologyCalendarShareData.checked({
    required int year,
    required int month,
    required List<AstrologyCalendarDay> days,
  }) {
    if (year < 1900 || year > 2100 || month < 1 || month > 12) {
      throw const FormatException('Calendar month is out of range.');
    }
    final length = DateTime.utc(year, month + 1, 0).day;
    if (days.length != length) {
      throw const FormatException('Every day of the month must be loaded.');
    }
    final frozen = <String, AstrologyCalendarDay>{};
    for (final day in days) {
      // Roundtrip deliberately copies nested event objects, not a live cache.
      final copy = AstrologyCalendarDay.fromMessage(day.toMessage());
      final plan = DailySevenTimepointPlan.forJstDate(copy.targetDateJst);
      final expectedPrefix =
          '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-';
      if (!copy.targetDateJst.startsWith(expectedPrefix) ||
          copy.moonSignAtNoon == null ||
          copy.providerName.trim().isEmpty ||
          copy.precisionNotice.trim().isEmpty ||
          frozen.containsKey(copy.targetDateJst)) {
        throw const FormatException(
          'Calendar date, Moon or source is missing.',
        );
      }
      final eventKeys = <String>{};
      for (final event in copy.events) {
        if (!eventKeys.add(jsonEncode(event.toMessage()))) {
          throw const FormatException('Duplicate calendar event.');
        }
        if (event.kind == AstrologyCalendarEventKind.signIngress &&
            (event.ingressPlanet == null ||
                event.fromSign == null ||
                event.toSign == null)) {
          throw const FormatException('Sign ingress details are missing.');
        }
        if (event.kind == AstrologyCalendarEventKind.voidMoon) {
          final start = event.startUtc, end = event.endUtc;
          if (start == null || end == null || !end.isAfter(start)) {
            throw const FormatException('Void interval is incomplete.');
          }
          final overlapStart = start.isAfter(plan.dayStartUtc)
              ? start
              : plan.dayStartUtc;
          final overlapEnd = end.isBefore(plan.dayEndUtc)
              ? end
              : plan.dayEndUtc;
          if (!overlapEnd.isAfter(overlapStart) ||
              event.overlapStartUtc != overlapStart ||
              event.overlapEndUtc != overlapEnd ||
              event.continuesFromPreviousDay !=
                  start.isBefore(plan.dayStartUtc) ||
              event.continuesIntoNextDay != end.isAfter(plan.dayEndUtc)) {
            throw const FormatException('Void date boundaries do not match.');
          }
        } else {
          final time = event.startUtc ?? event.snapshotUtc;
          if (time == null ||
              time.isBefore(plan.dayStartUtc) ||
              !time.isBefore(plan.dayEndUtc)) {
            throw const FormatException(
              'Calendar event belongs to another day.',
            );
          }
        }
      }
      frozen[copy.targetDateJst] = copy;
    }
    final ordered = <AstrologyCalendarDay>[];
    for (var day = 1; day <= length; day++) {
      final key =
          '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
      final value = frozen[key];
      if (value == null)
        throw const FormatException('Calendar day is missing.');
      ordered.add(value);
    }
    return AstrologyCalendarShareData._(
      year,
      month,
      List.unmodifiable(ordered),
    );
  }

  final int year, month;
  final List<AstrologyCalendarDay> days;
  String get monthKey =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';
  int get leadingDays => DateTime.utc(year, month, 1).weekday - 1;
  int get weekCount => (leadingDays + days.length + 6) ~/ 7;
  List<AstrologyCalendarDay> daysInWeek(int week) {
    if (week < 0 || week >= weekCount) throw RangeError.index(week, days);
    return List.unmodifiable([
      for (var index = 0; index < days.length; index++)
        if ((leadingDays + index) ~/ 7 == week) days[index],
    ]);
  }
}

String astrologyCalendarShareDetails(
  AstrologyCalendarShareData data, {
  required bool english,
}) {
  final lines = <String>[
    '${english ? 'Star calendar' : '星のカレンダー'} ${data.monthKey}',
    'JST (UTC+09:00)',
    english
        ? 'Complete event list. Positions without a transition time are noon snapshots, not exact aspect times.'
        : '全イベント一覧。配置は正午のスナップショットであり、アスペクトの正確な成立時刻ではありません。',
  ];
  for (final day in data.days) {
    final presentation = AstrologyCalendarDayPresentation.fromDay(
      day,
      english: english,
    );
    lines.addAll([
      '',
      day.targetDateJst,
      ...presentation.moonLines,
      '${english ? 'Void' : 'ボイド'}: ${presentation.voidLines.join(' / ')}',
      '${english ? 'Source' : '計算元'}: ${_astrologyCalendarProviderLabel(day.providerName, english)}',
      _astrologyCalendarPrecisionLabel(day.precisionNotice, english),
    ]);
    for (final event in day.events) {
      String clock(DateTime? time) => time == null
          ? '-'
          : '${time.toUtc().add(DailySevenTimepointPlan.jstOffset).toIso8601String().replaceFirst('Z', '')}+09:00';
      lines.addAll([
        '${_astrologyCalendarEventTitle(event, english)}: ${_astrologyCalendarEventDetail(event, english)}',
        '  start=${clock(event.startUtc)} end=${clock(event.endUtc)} snapshot=${clock(event.snapshotUtc)}',
      ]);
    }
  }
  return '${lines.join('\n')}\n';
}

/// Both the preview and independent PNG rendering use this exact widget and
/// the same day presentation as the interactive calendar. No list virtualization.
class AstrologyCalendarShareImage extends StatelessWidget {
  const AstrologyCalendarShareImage({
    super.key,
    required this.data,
    required this.english,
    this.week,
    this.fontFamily,
  });
  static const double imageWidth = 1680;
  final AstrologyCalendarShareData data;
  final bool english;
  final int? week;

  /// Optional presentation override, also used for a real-font visual test.
  /// Production callers retain platform font resolution by leaving this null.
  final String? fontFamily;

  @override
  Widget build(BuildContext context) {
    final selectedDays = week == null ? data.days : data.daysInWeek(week!);
    final providers = selectedDays
        .map(
          (day) => _astrologyCalendarProviderLabel(day.providerName, english),
        )
        .toSet();
    final notices = selectedDays
        .map(
          (day) =>
              _astrologyCalendarPrecisionLabel(day.precisionNotice, english),
        )
        .toSet();
    final weekdays = english
        ? const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
        : const ['月', '火', '水', '木', '金', '土', '日'];
    final rows = <TableRow>[];
    for (var row = 0; row < data.weekCount; row++) {
      if (week != null && row != week) continue;
      rows.add(
        TableRow(
          children: [
            for (var column = 0; column < 7; column++)
              _dayCell(row * 7 + column - data.leadingDays),
          ],
        ),
      );
    }
    return MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.noScaling),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Theme(
          data: ThemeData.dark(useMaterial3: true),
          child: Material(
            color: const Color(0xff17182b),
            child: DefaultTextStyle(
              style: TextStyle(
                fontFamily: fontFamily,
                fontSize: 16,
                color: Color(0xfff5f0df),
                height: 1.35,
              ),
              child: Container(
                width: imageWidth,
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${english ? 'Star calendar' : '星のカレンダー'}  ${_astrologyCalendarMonthLabel(data.year, data.month, english)}'
                      '${week == null ? '' : '  ${english ? 'Week' : '第'} ${week! + 1}${english ? '' : '週'} / ${data.weekCount}'}',
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      english
                          ? 'All times: JST (UTC+09:00)'
                          : '表示時刻：JST（日本標準時・UTC+09:00）',
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        for (final label in weekdays)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(label, textAlign: TextAlign.center),
                            ),
                          ),
                      ],
                    ),
                    Table(
                      border: TableBorder.all(color: const Color(0xff55566e)),
                      defaultVerticalAlignment: TableCellVerticalAlignment.top,
                      children: rows,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      english
                          ? 'Legend: Moon → sign transition; Void = void-of-course Moon; previous/next day = continuation. Other events are ordered by importance. +N: see the separately saved complete event list.'
                          : '凡例：月の → は星座移動。ボイドは月の空白時間。前日／翌日は継続区間。その他は重要度順。＋件数は別に保存される全イベント一覧で確認できます。',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      english
                          ? 'Configurations are noon snapshots, not exact aspect times. This calendar contains general astronomical data.'
                          : '配置は正午のスナップショットであり、正確な成立時刻ではありません。一般の天文データを表示しています。',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${english ? 'Calculation source' : '計算元'}: ${providers.join(' / ')}',
                    ),
                    for (final notice in notices) Text(notice),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dayCell(int index) {
    if (index < 0 || index >= data.days.length) return const SizedBox.shrink();
    final day = data.days[index];
    return Padding(
      key: ValueKey('calendar-export-day-${day.targetDateJst}'),
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${index + 1}',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          AstrologyCalendarDayContent(data: day, english: english),
        ],
      ),
    );
  }
}

/// A separate render tree paints all rows even when the on-screen preview is
/// scrolled or clipped. This never captures the device screen or private UI.
Future<Uint8List> captureAstrologyCalendarImage(
  ui.FlutterView view,
  Widget imageWidget,
) async {
  const width = AstrologyCalendarShareImage.imageWidth;
  const maximumHeight = 10000.0;
  final boundary = RenderRepaintBoundary();
  final positioned = RenderPositionedBox(
    alignment: Alignment.topLeft,
    child: boundary,
  );
  final renderView = RenderView(
    view: view,
    configuration: const ViewConfiguration(
      logicalConstraints: BoxConstraints.tightFor(
        width: width,
        height: maximumHeight,
      ),
      physicalConstraints: BoxConstraints.tightFor(
        width: width,
        height: maximumHeight,
      ),
      devicePixelRatio: 1,
    ),
    child: positioned,
  );
  final pipeline = PipelineOwner()..rootNode = renderView;
  final focus = FocusManager();
  final buildOwner = BuildOwner(focusManager: focus);
  RenderObjectToWidgetElement<RenderBox>? element;
  try {
    renderView.prepareInitialFrame();
    element = RenderObjectToWidgetAdapter<RenderBox>(
      container: boundary,
      child: imageWidget,
    ).attachToRenderTree(buildOwner);
    buildOwner.buildScope(element);
    buildOwner.finalizeTree();
    pipeline.flushLayout();
    pipeline.flushCompositingBits();
    pipeline.flushPaint();
    if (boundary.size.width != width ||
        boundary.size.height <= 0 ||
        boundary.size.height >= maximumHeight) {
      throw StateError('Calendar image is too large; choose weekly images.');
    }
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('Calendar PNG encoding failed.');
      return bytes.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    if (element != null) {
      RenderObjectToWidgetAdapter<RenderBox>(
        container: boundary,
      ).attachToRenderTree(buildOwner, element);
      buildOwner.buildScope(element);
      buildOwner.finalizeTree();
    }
    pipeline.rootNode = null;
    renderView.child = null;
    positioned.child = null;
    boundary.dispose();
    positioned.dispose();
    renderView.dispose();
    pipeline.dispose();
    focus.dispose();
  }
}

class AstrologyCalendarSavedExport {
  const AstrologyCalendarSavedExport(
    this.directory,
    this.images,
    this.details,
    this.manifest,
  );
  final Directory directory;
  final List<File> images;
  final File details, manifest;
  List<XFile> get shareFiles => [
    for (final image in images) XFile(image.path, mimeType: 'image/png'),
  ];
  XFile get detailsShareFile => XFile(details.path, mimeType: 'text/plain');
}

typedef AstrologyCalendarImageRenderer = Future<Uint8List> Function(int? week);

/// Documents are retained on cancel. Every new export has its own directory;
/// previously saved images, forecasts and backups are never overwritten.
Future<AstrologyCalendarSavedExport> saveAstrologyCalendarExport({
  required Directory documentsRoot,
  required AstrologyCalendarShareData data,
  required bool english,
  required bool splitWeeks,
  required AstrologyCalendarImageRenderer render,
}) async {
  final root = Directory(
    '${documentsRoot.path}${Platform.pathSeparator}star_calendar_exports',
  );
  await root.create(recursive: true);
  final directory = await root.createTemp('${data.monthKey}_');
  final files = <File>[];
  final hashes = <String, String>{};
  Future<File> writeChecked(String name, List<int> bytes) async {
    final file = File('${directory.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(bytes, flush: true);
    final readback = await file.readAsBytes();
    final digest = sha256.convert(bytes).toString();
    if (readback.length != bytes.length ||
        sha256.convert(readback).toString() != digest) {
      throw StateError('Calendar file readback failed.');
    }
    hashes[name] = digest;
    return file;
  }

  final count = splitWeeks ? data.weekCount : 1;
  for (var index = 0; index < count; index++) {
    final bytes = await render(splitWeeks ? index : null);
    // Decode before writing: a non-PNG or truncated image cannot be shared.
    if (bytes.length < 8 ||
        !List.generate(8, (i) => bytes[i]).asMap().entries.every(
          (entry) =>
              entry.value == const [137, 80, 78, 71, 13, 10, 26, 10][entry.key],
        )) {
      throw const FormatException('Calendar capture is not a PNG.');
    }
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      try {
        if (frame.image.width != AstrologyCalendarShareImage.imageWidth ||
            frame.image.height <= 0 ||
            frame.image.height >= 10000) {
          throw const FormatException('Calendar image dimensions are invalid.');
        }
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
    files.add(
      await writeChecked(
        'star_calendar_${data.monthKey}${splitWeeks ? '_week_${index + 1}' : ''}.png',
        bytes,
      ),
    );
  }
  final details = await writeChecked(
    'star_calendar_${data.monthKey}_events.txt',
    utf8.encode(astrologyCalendarShareDetails(data, english: english)),
  );
  final manifest = await writeChecked(
    'manifest.json',
    utf8.encode(
      jsonEncode({
        'format': 'pancyo-star-calendar-images-v1',
        'month': data.monthKey,
        'timezone': 'JST / UTC+09:00',
        'created_at_utc': DateTime.now().toUtc().toIso8601String(),
        'day_count': data.days.length,
        'image_count': files.length,
        'split_weeks': splitWeeks,
        'days': [for (final day in data.days) day.targetDateJst],
        'providers': data.days.map((day) => day.providerName).toSet().toList(),
        'precision_notices': data.days
            .map((day) => day.precisionNotice)
            .toSet()
            .toList(),
        'files_sha256': Map<String, String>.of(hashes),
      }),
    ),
  );
  return AstrologyCalendarSavedExport(
    directory,
    List.unmodifiable(files),
    details,
    manifest,
  );
}

/// Copy only this requested export to the Android calendar cache. A unique
/// directory plus a full readback protects previous exports and share retries.
Future<List<File>> prepareAstrologyCalendarShareCache({
  required Directory temporaryRoot,
  required List<XFile> files,
}) async {
  if (files.isEmpty || files.length > 6) {
    throw const FormatException('Expected one to six calendar images.');
  }
  final mimeType = files.first.mimeType;
  if ((mimeType != 'image/png' && mimeType != 'text/plain') ||
      files.any((file) => file.mimeType != mimeType) ||
      (mimeType == 'text/plain' && files.length != 1) ||
      files.map((file) => file.path).toSet().length != files.length) {
    throw const FormatException('Share images or one event list separately.');
  }
  final extension = mimeType == 'image/png' ? '.png' : '.txt';
  if (files.any((file) => !file.path.toLowerCase().endsWith(extension))) {
    throw const FormatException('Calendar file type does not match its MIME.');
  }
  final root = Directory(
    '${temporaryRoot.path}${Platform.pathSeparator}calendar_exports',
  );
  await root.create(recursive: true);
  final directory = await root.createTemp('calendar_');
  final copies = <File>[];
  for (var index = 0; index < files.length; index++) {
    final bytes = await File(files[index].path).readAsBytes();
    if (bytes.isEmpty) throw const FormatException('Calendar file is empty.');
    final copy = File(
      '${directory.path}${Platform.pathSeparator}calendar_${index + 1}$extension',
    );
    await copy.writeAsBytes(bytes, flush: true);
    final readback = await copy.readAsBytes();
    if (bytes.length != readback.length ||
        sha256.convert(bytes).toString() !=
            sha256.convert(readback).toString()) {
      throw StateError('Calendar share cache readback failed.');
    }
    copies.add(copy);
  }
  return List.unmodifiable(copies);
}

/// Android uses the already established no-result chooser strategy. A null
/// result means handed to the chooser, never a selected recipient or a cancel.
/// There is deliberately no fallback to the known problematic result callback.
Future<ShareResultStatus?> launchAstrologyCalendarShareFiles(
  List<XFile> files, {
  Rect? sharePositionOrigin,
  bool? useAndroidCompatibility,
  Directory? temporaryRoot,
}) async {
  if (useAndroidCompatibility ?? Platform.isAndroid) {
    final copies = await prepareAstrologyCalendarShareCache(
      temporaryRoot: temporaryRoot ?? await getTemporaryDirectory(),
      files: files,
    );
    final opened =
        await const MethodChannel(
          'com.pancyo.aiastrology/share_compat',
        ).invokeMethod<bool>('shareCalendarFiles', {
          'paths': copies.map((file) => file.path).toList(),
          'mimeType': files.first.mimeType,
        });
    if (opened != true) throw StateError('Calendar share menu did not open.');
    return null;
  }
  return (await Share.shareXFiles(
    files,
    sharePositionOrigin: sharePositionOrigin,
  )).status;
}

String astrologyCalendarShareOutcome(
  ShareResultStatus? status, {
  required bool english,
}) => switch (status) {
  ShareResultStatus.success =>
    english
        ? 'A recipient was selected. Confirm saving or sending in the destination app. Files remain saved in this app.'
        : '共有先を選びました。保存・送信の完了は共有先で確認してください。アプリ内の画像は保存済みです。',
  ShareResultStatus.dismissed =>
    english
        ? 'Sharing was cancelled. The images remain saved in this app.'
        : '共有を取り消しました。画像はアプリ内に保存済みです。',
  ShareResultStatus.unavailable =>
    english
        ? 'Files are saved in this app; the sharing result could not be confirmed.'
        : '画像はアプリ内に保存済みです。共有結果は確認できません。',
  null =>
    english
        ? 'Files were handed to the share menu. Confirm saving, sending or cancellation in the destination app. Files remain saved in this app.'
        : '共有メニューへ渡しました。保存・送信・取消の結果は共有先で確認してください。画像はアプリ内に保存済みです。',
};

Future<void> showAstrologyCalendarSharePreview(
  BuildContext context, {
  required int year,
  required int month,
  required List<AstrologyCalendarDay> days,
  required bool english,
}) async {
  AstrologyCalendarShareData data;
  try {
    data = AstrologyCalendarShareData.checked(
      year: year,
      month: month,
      days: days,
    );
  } catch (_) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          english
              ? 'The month is incomplete or contains inconsistent dates/Moon data. Load every day and retry; failed days are not treated as void-free.'
              : '月全体の取得が未完了、または日付・月の情報を確認できません。全日を取得してから再試行してください。取得失敗を「ボイドなし」として共有しません。',
        ),
      ),
    );
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => AstrologyCalendarShareSheet(data: data, english: english),
  );
}

class AstrologyCalendarShareSheet extends StatefulWidget {
  const AstrologyCalendarShareSheet({
    super.key,
    required this.data,
    required this.english,
    this.renderImage,
  });
  final AstrologyCalendarShareData data;
  final bool english;
  final AstrologyCalendarImageRenderer? renderImage;
  @override
  State<AstrologyCalendarShareSheet> createState() =>
      _AstrologyCalendarShareSheetState();
}

class _AstrologyCalendarShareSheetState
    extends State<AstrologyCalendarShareSheet> {
  bool _busy = false, _split = false;
  String _message = '';
  AstrologyCalendarSavedExport? _saved;
  final _transform = TransformationController(
    Matrix4.diagonal3Values(.35, .35, 1),
  );
  String copy(String ja, String en) => widget.english ? en : ja;

  Future<void> _save({required bool share, bool detailsOnly = false}) async {
    if (_busy) return;
    final view = View.of(context);
    final box = context.findRenderObject();
    final origin = box is RenderBox
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    setState(() {
      _busy = true;
      _message = '';
    });
    try {
      final result =
          _saved ??
          await saveAstrologyCalendarExport(
            documentsRoot: await getApplicationDocumentsDirectory(),
            data: widget.data,
            english: widget.english,
            splitWeeks: _split,
            render:
                widget.renderImage ??
                (week) => captureAstrologyCalendarImage(
                  view,
                  AstrologyCalendarShareImage(
                    data: widget.data,
                    english: widget.english,
                    week: week,
                  ),
                ),
          );
      _saved = result;
      if (!mounted) return;
      if (share) {
        final outcome = await launchAstrologyCalendarShareFiles(
          detailsOnly ? [result.detailsShareFile] : result.shareFiles,
          sharePositionOrigin: origin,
        );
        if (mounted)
          setState(
            () => _message = astrologyCalendarShareOutcome(
              outcome,
              english: widget.english,
            ),
          );
      } else {
        setState(
          () => _message = copy(
            '画像${result.images.length}枚と全イベント一覧をアプリ内に保存し、読み戻し確認しました。共有メニューから写真・ファイルの保存先を選べます。',
            '${result.images.length} images and the event list were saved in this app and read back. Use Share to choose a photo or file destination.',
          ),
        );
      }
    } catch (_) {
      if (mounted)
        setState(
          () => _message = _saved != null
              ? copy(
                  '画像はアプリ内に保存済みですが、共有に失敗しました。もう一度共有できます。',
                  'Images are saved in this app, but sharing failed. You can retry sharing.',
                )
              : copy(
                  '画像作成・保存が完了しませんでした。全月画像が大きい場合は週ごとの分割画像を選んでください。',
                  'Image creation or saving did not complete. If the month is too large, choose weekly images.',
                ),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              copy('星のカレンダー・画像保存と共有', 'Star calendar · Save and share'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              copy(
                '選択月の全日と補足一覧を保存します。画像はアプリ内に保存されます。写真などへの保存先は共有メニューで選んでください。出生情報・名前・私的メモは含みません。',
                'Save every day of this month and the full event list inside the app. Choose a photo or file destination from Share. No birth data, names or private notes are included.',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              copy(
                'プレビューは拡大・移動できます。画面外の週も画像に含まれます。',
                'Pan and zoom the preview. Export includes weeks outside this viewport.',
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 360,
              width: double.infinity,
              child: ClipRect(
                child: InteractiveViewer(
                  constrained: false,
                  transformationController: _transform,
                  minScale: .15,
                  maxScale: 2,
                  boundaryMargin: const EdgeInsets.all(40),
                  child: AstrologyCalendarShareImage(
                    data: widget.data,
                    english: widget.english,
                  ),
                ),
              ),
            ),
            SwitchListTile(
              value: _split,
              onChanged: _busy
                  ? null
                  : (value) => setState(() {
                      _split = value;
                      _saved = null;
                      _message = '';
                    }),
              title: Text(copy('週ごとの分割画像にする', 'Create separate weekly images')),
              subtitle: Text(
                copy(
                  '全${widget.data.weekCount}週をまとめて画像共有します。補足一覧は別のボタンで共有できます。',
                  'Share all ${widget.data.weekCount} weeks as images. Share the complete event list separately.',
                ),
              ),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_message.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  _message,
                  key: const ValueKey('calendar-share-result'),
                ),
              ),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : () => _save(share: false),
                  icon: const Icon(Icons.save_alt),
                  label: Text(copy('アプリ内に画像保存', 'Save images in app')),
                ),
                FilledButton.icon(
                  onPressed: _busy ? null : () => _save(share: true),
                  icon: const Icon(Icons.share),
                  label: Text(copy('保存して共有', 'Save and share')),
                ),
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _save(share: true, detailsOnly: true),
                  icon: const Icon(Icons.list_alt),
                  label: Text(copy('補足一覧を共有', 'Share event list')),
                ),
                TextButton(
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  child: Text(copy('閉じる', 'Close')),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
