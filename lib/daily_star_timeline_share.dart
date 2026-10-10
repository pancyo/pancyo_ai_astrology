part of 'main.dart';

/// Only display fields are copied. No birth input or private digest is printed.
/// Optional timepoint scores come only from the already-validated intraday
/// result for the same seven timeline samples.
class DailyStarTimelineShareData {
  DailyStarTimelineShareData._({
    required this.plan,
    required this.points,
    required this.voidMoon,
    required this.precise,
    required this.hasTimepointForecast,
    required String participantName,
  }) : _participantName = participantName;

  factory DailyStarTimelineShareData.checked({
    required DailyStarTimelineRequest request,
    required DailyStarTimelineResult result,
    DailyTimepointForecastResult? scoreResult,
  }) {
    if (request.identity != result.requestIdentity) {
      throw StateError('共有する人物・日付が一致しません。');
    }
    DailyStarTimelineResult.checked(
      request: request,
      points: result.points,
      elapsedMilliseconds: result.elapsedMilliseconds,
      workerName: result.workerName,
    );
    if (scoreResult != null &&
        (scoreResult.timelineIdentity != request.identity ||
            scoreResult.targetDateJst != request.plan.targetDateJst ||
            scoreResult.forecasts['target_date_jst'] !=
                request.plan.targetDateJst)) {
      throw StateError('共有する時刻別点数の日付が一致しません。');
    }
    final rawForecastPointsValue = scoreResult?.forecasts['points'];
    if (scoreResult != null &&
        (rawForecastPointsValue is! List ||
            rawForecastPointsValue.length != 7)) {
      throw StateError('共有する時刻別点数が7点揃っていません。');
    }
    final List? rawForecastPoints = rawForecastPointsValue is List
        ? rawForecastPointsValue
        : null;
    DailyStarTimelineSharePoint makePoint(int index) {
      final point = result.points[index];
      final scoreSnapshot = scoreResult == null
          ? null
          : _dailyTimelineShareSnapshot(
              request.plan.points[index],
              rawForecastPoints![index],
            );
      return DailyStarTimelineSharePoint._(
        point.clock,
        point.moon.sign,
        point.moon.degree,
        point.moon.house,
        point.isVoid,
        dailyStarTimelinePointHint(point),
        scores: scoreSnapshot?.scores,
        feltLabel: scoreSnapshot?.feltLabel,
      );
    }

    return DailyStarTimelineShareData._(
      plan: request.plan,
      precise: request.requireHighPrecision,
      voidMoon: request.voidMoon,
      hasTimepointForecast: scoreResult != null,
      participantName: request.profile.name,
      points: List.unmodifiable(
        List<DailyStarTimelineSharePoint>.generate(
          result.points.length,
          makePoint,
        ),
      ),
    );
  }
  final DailySevenTimepointPlan plan;
  final List<DailyStarTimelineSharePoint> points;
  final VoidMoonPeriod? voidMoon;
  final bool precise;
  final bool hasTimepointForecast;
  final String _participantName;
  String filename(DateTime issued) =>
      'pancyo_star_flow_'
      '${ConsultJsonFileWriter.safeParticipantName(_participantName)}_'
      '${plan.targetDateJst.replaceAll('-', '')}_${issued.toUtc().microsecondsSinceEpoch}.png';
  String get voidLabel => voidMoon == null
      ? 'この日の計算で月ボイドの情報はありません。'
      : '黄帯：月ボイド ${_shareEventTime(voidMoon!.startTime, plan)}〜'
            '${_shareEventTime(voidMoon!.endTime, plan)}（JST）';

  String displayVoidLabel(AppStrings strings) {
    if (strings.language == AppLanguage.ja) return voidLabel;
    if (voidMoon == null) return strings.text(AppText.timelineNoVoidInfo);
    String time(DateTime value) =>
        _shareEventTime(value, plan).replaceAll('（翌日0時）', ' (00:00 next day)');
    return 'Yellow band: void-of-course Moon ${time(voidMoon!.startTime)}–${time(voidMoon!.endTime)} (JST)';
  }
}

({Map<NineAreaKey, int?> scores, String? feltLabel})
_dailyTimelineShareSnapshot(DailySevenTimepoint clock, Object? rawPoint) {
  final point = _timelineMap(rawPoint);
  if (point['instant_utc'] != clock.instantUtc.toIso8601String()) {
    throw StateError('共有する時刻別点数の時刻が一致しません。');
  }
  final snapshot = _timelineMap(point['nine_area_forecast']);
  if (snapshot['model_version'] != NineAreaDailyForecast.modelVersion ||
      snapshot['target_date_jst'] != _timelineJstDate(clock.instantUtc)) {
    throw StateError('共有する時刻別点数のモデルが一致しません。');
  }
  final areas = snapshot['areas'];
  if (areas is! List || areas.length != NineAreaKey.values.length) {
    throw StateError('共有する時刻別点数の項目が揃っていません。');
  }
  final byKey = <NineAreaKey, Map<String, Object?>>{};
  for (final rawArea in areas) {
    final area = _timelineMap(rawArea);
    final keyName = area['key'];
    final key = NineAreaKey.values.where((value) => value.name == keyName);
    if (keyName is! String ||
        key.length != 1 ||
        byKey.containsKey(key.single)) {
      throw StateError('共有する時刻別点数の項目キーが不正です。');
    }
    byKey[key.single] = area;
  }
  if (byKey.length != NineAreaKey.values.length) {
    throw StateError('共有する時刻別点数の項目が不足しています。');
  }
  final scores = <NineAreaKey, int?>{};
  for (final key in NineAreaKey.values.where(
    (value) => value != NineAreaKey.felt,
  )) {
    final score = byKey[key]!['score'];
    if (score != null && score is! int) {
      throw StateError('共有する時刻別点数の値が不正です。');
    }
    scores[key] = score as int?;
  }
  final felt = byKey[NineAreaKey.felt]!;
  if (felt['score'] != null || felt['score_breakdown'] != null) {
    throw StateError('共有する体感カテゴリに数値点があります。');
  }
  final rawLabel = felt['predicted_felt_label'];
  const allowedFelt = {'最高', '良い', '普通', '悪い', '最悪'};
  if (rawLabel != null &&
      (rawLabel is! String || !allowedFelt.contains(rawLabel))) {
    throw StateError('共有する体感カテゴリが不正です。');
  }
  return (scores: Map.unmodifiable(scores), feltLabel: rawLabel as String?);
}

String _timelineShareMessage(BuildContext context, String source) {
  if (AppLanguageScope.stringsOf(context).language == AppLanguage.ja)
    return source;
  return switch (source) {
    '共有をキャンセルしました。画像は一時作成のみです。' =>
      'Sharing cancelled. Only a temporary image was created.',
    '共有先を選びました。保存・送信の完了は共有先で確認してください。' =>
      'A destination was selected. Check that app to confirm saving or sending.',
    '画像を一時作成しました。共有結果は確認できません。' =>
      'A temporary image was created. The sharing result could not be confirmed.',
    '共有機能へ画像を渡しました。保存・送信の結果は共有先で確認してください。' =>
      'The image was passed to sharing. Check the destination to confirm saving or sending.',
    '画像の作成・共有が完了しませんでした。もう一度お試しください。' =>
      'Could not finish creating or sharing the image. Please try again.',
    '共有カード用の時刻別点数を計算しています。' =>
      'Calculating timepoint scores for the share card.',
    '時刻別点数を用意できませんでした。再試行できます。' =>
      'Could not prepare timepoint scores. Tap share to retry.',
    _ => source,
  };
}

class DailyStarTimelineSharePoint {
  const DailyStarTimelineSharePoint._(
    this.clock,
    this.sign,
    this.degree,
    this.birthHouse,
    this.isVoid,
    this.hint, {
    this.scores,
    this.feltLabel,
  });
  final DailySevenTimepoint clock;
  final ZodiacSign sign;
  final double degree;
  final int birthHouse;
  final bool isVoid;
  final String hint;
  final Map<NineAreaKey, int?>? scores;
  final String? feltLabel;
}

String _shareEventTime(DateTime value, DailySevenTimepointPlan plan) {
  if (value.toUtc() == plan.dayEndUtc) return '24:00（翌日0時）';
  final jst = value.toUtc().add(DailySevenTimepointPlan.jstOffset);
  final civil =
      '${jst.year.toString().padLeft(4, '0')}-'
      '${jst.month.toString().padLeft(2, '0')}-${jst.day.toString().padLeft(2, '0')}';
  return (civil == plan.targetDateJst ? '' : '$civil ') +
      _timelineTimeLabel(value);
}

class DailyStarTimelineShareFileWriter {
  const DailyStarTimelineShareFileWriter._();
  static Future<File> write({
    required Directory temporaryRoot,
    required Uint8List png,
    required DailyStarTimelineShareData data,
    DateTime? issuedAt,
  }) async {
    const signature = [137, 80, 78, 71, 13, 10, 26, 10];
    if (png.length <= signature.length ||
        !List.generate(8, (i) => png[i] == signature[i]).every((v) => v)) {
      throw const FormatException('PNG画像がありません。');
    }
    final folder = await temporaryRoot.createTemp('pancyo_star_flow_');
    final file = File(
      '${folder.path}${Platform.pathSeparator}'
      '${data.filename(issuedAt ?? DateTime.now())}',
    );
    await file.writeAsBytes(png, flush: true);
    return file;
  }
}

Future<void> showDailyStarTimelineShareComposer(
  BuildContext context, {
  required DailyStarTimelineShareData data,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: const Color(0xFF11172F),
  builder: (_) => DailyStarTimelineShareSheet(data: data),
);

typedef DailyStarShareCapture =
    Future<Uint8List> Function(RenderRepaintBoundary);
typedef DailyStarShareLaunch = Future<ShareResultStatus?> Function(XFile);

Future<ShareResultStatus?> launchDailyStarTimelineShareFile(XFile file) async {
  var opened = false;
  if (Platform.isAndroid) {
    try {
      opened =
          await const MethodChannel(
            'com.pancyo.aiastrology/share_compat',
          ).invokeMethod<bool>('shareImage', {
            'path': file.path,
            'mimeType': 'image/png',
          }) ??
          false;
    } on PlatformException {
      /* Use the established share_plus fallback. */
    }
  }
  return opened ? null : (await Share.shareXFiles([file])).status;
}

Future<Uint8List> captureDailyStarTimelineShareImage(
  RenderRepaintBoundary boundary,
) async {
  if (boundary.size.width <= 0 ||
      boundary.size.height <= 0 ||
      boundary.size.width > 1600 ||
      boundary.size.height > 6000) {
    throw StateError('共有画像の大きさを確認できません。');
  }
  final image = await boundary.toImage(pixelRatio: 1.5);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw StateError('共有画像を読み取れません。');
    return bytes.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// Separate composer: existing score/body preferences are read-only and never
/// changed. Opening/closing has no file writes and never launches a recipient.
class DailyStarTimelineShareSheet extends StatefulWidget {
  const DailyStarTimelineShareSheet({
    super.key,
    required this.data,
    this.captureImage,
    this.launchShare,
  });
  final DailyStarTimelineShareData data;
  final DailyStarShareCapture? captureImage;
  final DailyStarShareLaunch? launchShare;
  @override
  State<DailyStarTimelineShareSheet> createState() =>
      _DailyStarTimelineShareSheetState();
}

class _DailyStarTimelineShareSheetState
    extends State<DailyStarTimelineShareSheet> {
  final _previewKey = GlobalKey();
  final _name = TextEditingController(), _note = TextEditingController();
  FortuneShareTheme _theme = FortuneShareTheme.night;
  String _wallpaper = '', _error = '', _message = '';
  bool _sharing = false, _settingsReady = false, _showScore = true;
  @override
  void initState() {
    super.initState();
    unawaited(_readTheme());
  }

  Future<void> _readTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _theme = FortuneShareTheme.values.firstWhere(
          (t) => t.name == prefs.getString('share_card_theme'),
          orElse: () => FortuneShareTheme.night,
        );
        _wallpaper = prefs.getString('share_card_custom_wallpaper') ?? '';
        _showScore = prefs.getBool('share_card_show_score') ?? true;
        _settingsReady = true;
      });
    } catch (_) {
      if (mounted) setState(() => _settingsReady = true);
    }
  }

  Future<void> _share() async {
    if (_sharing || !_settingsReady) return;
    setState(() {
      _sharing = true;
      _error = '';
      _message = '';
    });
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final boundary = _previewKey.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary) throw StateError('No preview');
      final bytes =
          await (widget.captureImage ?? captureDailyStarTimelineShareImage)(
            boundary,
          );
      if (!mounted) return;
      final directory = await getTemporaryDirectory();
      final file = await DailyStarTimelineShareFileWriter.write(
        temporaryRoot: directory,
        png: bytes,
        data: widget.data,
      );
      if (!mounted) return;
      final status =
          await (widget.launchShare ?? launchDailyStarTimelineShareFile)(
            XFile(file.path, mimeType: 'image/png'),
          );
      if (mounted)
        setState(
          () => _message = switch (status) {
            ShareResultStatus.dismissed => '共有をキャンセルしました。画像は一時作成のみです。',
            ShareResultStatus.success => '共有先を選びました。保存・送信の完了は共有先で確認してください。',
            ShareResultStatus.unavailable => '画像を一時作成しました。共有結果は確認できません。',
            null => '共有機能へ画像を渡しました。保存・送信の結果は共有先で確認してください。',
          },
        );
    } catch (_) {
      if (mounted) setState(() => _error = '画像の作成・共有が完了しませんでした。もう一度お試しください。');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_sharing,
    child: SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _periodDisplayCopy(
                  context,
                  '星の流れの共有カード',
                  'Star timeline share card',
                ),
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                _periodDisplayCopy(
                  context,
                  '画面で確認した7時点を共有します。出生日時・出生地は画像に載せませんが、出生図のハウスとファイル名の人物名は含みます。共有前に内容を確認してください。',
                  'Share the seven displayed samples. Birth date, time and birthplace are excluded from the image, but natal houses and the participant name in the filename are included. Check the content before sharing.',
                ),
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 14),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: RepaintBoundary(
                    key: _previewKey,
                    child: DailyStarTimelineShareImageCard(
                      data: widget.data,
                      theme: _theme,
                      customWallpaperPath: _wallpaper,
                      showScores: _showScore,
                      displayName: _name.text.trim(),
                      note: _note.text.trim(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                key: const ValueKey('star-share-name'),
                controller: _name,
                enabled: !_sharing,
                maxLength: 20,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: _periodDisplayCopy(
                    context,
                    '表示名（任意・自動では載せません）',
                    'Display name (optional; not added automatically)',
                  ),
                ),
              ),
              TextField(
                key: const ValueKey('star-share-note'),
                controller: _note,
                enabled: !_sharing,
                maxLength: 42,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: localizedUiText(context, 'ひとこと（任意）'),
                ),
              ),
              Text(
                _periodDisplayCopy(context, 'カードの絵柄', 'Card artwork'),
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              IgnorePointer(
                ignoring: _sharing || !_settingsReady,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final theme in FortuneShareTheme.values.where(
                      (t) => t != FortuneShareTheme.custom,
                    ))
                      ShareWallpaperOption(
                        theme: theme,
                        selected: theme == _theme,
                        onTap: () => setState(() => _theme = theme),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const ValueKey('star-share-send'),
                  onPressed: _sharing || !_settingsReady ? null : _share,
                  icon: _sharing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.ios_share_outlined),
                  label: Text(
                    _periodDisplayCopy(
                      context,
                      _sharing ? '画像を作成・共有中…' : 'この画像を共有',
                      _sharing
                          ? 'Creating and sharing image…'
                          : 'Share this image',
                    ),
                  ),
                ),
              ),
              if (_error.isNotEmpty)
                Text(
                  _timelineShareMessage(context, _error),
                  key: const ValueKey('star-share-error'),
                ),
              if (_message.isNotEmpty)
                Text(
                  _timelineShareMessage(context, _message),
                  key: const ValueKey('star-share-result'),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// All seven rows are present in the repaint boundary, never horizontally
/// clipped or shortened to the selected point. No score / outcome inference.
class DailyStarTimelineShareImageCard extends StatelessWidget {
  const DailyStarTimelineShareImageCard({
    super.key,
    required this.data,
    this.theme = FortuneShareTheme.night,
    this.customWallpaperPath = '',
    this.showScores = true,
    this.displayName = '',
    this.note = '',
  });
  final DailyStarTimelineShareData data;
  final FortuneShareTheme theme;
  final bool showScores;
  final String customWallpaperPath, displayName, note;
  @override
  Widget build(BuildContext context) {
    final palette = theme.palette;
    final image = theme.imageProvider(customWallpaperPath);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.accent),
      ),
      padding: const EdgeInsets.all(14),
      child: Container(
        color: palette.surface,
        padding: const EdgeInsets.all(12),
        child: DefaultTextStyle(
          style: Theme.of(context).textTheme.bodyMedium!.copyWith(
            color: palette.text,
            fontSize: 12,
            height: 1.45,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _periodDisplayCopy(context, 'ぱんちょ式星占い', 'Pancyo Astrology'),
                style: TextStyle(
                  color: palette.accent,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                '${data.plan.targetDateJst} · ${_periodDisplayCopy(context, '1日の星の流れ', 'Daily star timeline')}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (displayName.isNotEmpty)
                Text(
                  displayName,
                  key: const ValueKey('star-shared-display-name'),
                ),
              if (image != null || theme.catArtKind != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: AspectRatio(
                      aspectRatio: 2,
                      child: theme.catArtKind != null
                          ? LayoutBuilder(
                              builder: (context, constraints) => ShareCatArt(
                                key: const ValueKey('star-shared-artwork'),
                                kind: theme.catArtKind!,
                                width: constraints.maxWidth,
                                height: constraints.maxHeight,
                              ),
                            )
                          : Image(
                              key: const ValueKey('star-shared-artwork'),
                              image: image!,
                              fit: BoxFit.contain,
                              alignment: Alignment.center,
                              excludeFromSemantics: true,
                            ),
                    ),
                  ),
                ),
              Text(
                _periodDisplayCopy(
                  context,
                  data.hasTimepointForecast && showScores
                      ? '4時間ごと・JST／月の配置・一言ヒント・時刻別9項目'
                      : data.hasTimepointForecast
                      ? '4時間ごと・JST／月の配置・一言ヒント・体感カテゴリ'
                      : '4時間ごと・JST／月の配置と一言ヒント',
                  data.hasTimepointForecast && showScores
                      ? 'Every 4 hours · JST / Moon placements, short suggestions, and nine timepoint categories'
                      : data.hasTimepointForecast
                      ? 'Every 4 hours · JST / Moon placements, short suggestions, and felt category'
                      : 'Every 4 hours · JST / Moon placements and short suggestions',
                ),
              ),
              if (data.hasTimepointForecast && showScores)
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    _periodDisplayCopy(
                      context,
                      '各時刻に既存の日モデルを適用した比較表示です。1日の見通しは正午基準で、7時点の平均や検証済みの時間帯予測ではありません。',
                      'These are comparison values from applying the existing daily model at each time. The daily outlook remains noon-based; these are not a seven-point average or validated time-of-day forecasts.',
                    ),
                    key: const ValueKey('star-shared-scores-context'),
                    style: TextStyle(
                      fontSize: 10,
                      color: palette.text.withValues(alpha: 0.78),
                    ),
                  ),
                ),
              if (showScores && !data.hasTimepointForecast)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _periodDisplayCopy(
                      context,
                      '時刻別点数は未読込のため掲載していません。',
                      'Timepoint scores are omitted because they are not loaded.',
                    ),
                    key: const ValueKey('star-shared-scores-unavailable'),
                    style: TextStyle(
                      fontSize: 11,
                      color: palette.text.withValues(alpha: 0.78),
                    ),
                  ),
                ),
              if (!showScores && data.hasTimepointForecast)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _periodDisplayCopy(
                      context,
                      '点数表示設定により数値は非表示です。体感はカテゴリ表示です。',
                      'Numeric scores are hidden by your setting. Felt experience remains a category.',
                    ),
                    key: const ValueKey('star-shared-scores-hidden'),
                    style: TextStyle(
                      fontSize: 11,
                      color: palette.text.withValues(alpha: 0.78),
                    ),
                  ),
                ),
              SizedBox(
                height: 40,
                width: double.infinity,
                child: CustomPaint(
                  painter: DailyStarTimeBarPainter(
                    plan: data.plan,
                    voidMoon: data.voidMoon,
                    selected: -1,
                    trackColor: palette.accent,
                    voidColor: palette.score,
                  ),
                ),
              ),
              Row(
                children: [
                  for (final p in data.points)
                    Expanded(
                      child: Text(
                        p.clock.hourFromDayStart.toString().padLeft(2, '0'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                data.displayVoidLabel(AppLanguageScope.stringsOf(context)),
                style: TextStyle(color: palette.score),
              ),
              const SizedBox(height: 8),
              if (showScores && data.hasTimepointForecast) ...[
                _dailyTimelineShareScoreTables(context, data.points, palette),
                const SizedBox(height: 8),
              ],
              for (final p in data.points)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Column(
                    key: ValueKey(
                      'star-shared-point-${p.clock.hourFromDayStart}',
                    ),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (AppLanguageScope.stringsOf(context).language ==
                                    AppLanguage.ja
                                ? '${p.clock.displayTime}${p.clock.isDayEndBoundary ? '（翌日0時）' : ''}  月：${p.sign.label} ${p.degree.toStringAsFixed(1)}°'
                                : AppLanguageScope.stringsOf(
                                    context,
                                  ).timelineMoonDetail(
                                    time: p.clock.displayTime,
                                    endBoundary: p.clock.isDayEndBoundary,
                                    signKey: p.sign.name,
                                    canonicalJapaneseSign: p.sign.label,
                                    degree: p.degree.toStringAsFixed(1),
                                  )) +
                            (p.isVoid
                                ? _periodDisplayCopy(context, '・ボイド', ' · Void')
                                : ''),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        AppLanguageScope.stringsOf(
                          context,
                        ).timelineNatalHouse(p.birthHouse),
                      ),
                      Text(
                        AppLanguageScope.stringsOf(context).timelineHint(
                          signKey: p.sign.name,
                          isVoid: p.isVoid,
                          canonicalJapaneseHint: p.hint,
                        ),
                      ),
                      if (p.scores != null) ...[
                        const SizedBox(height: 5),
                        _dailyTimelineShareFelt(context, p, palette),
                      ],
                    ],
                  ),
                ),
              Text(
                _periodDisplayCopy(
                  context,
                  '24時は翌日0時の境界。翌日と二重集計しません。',
                  '24:00 is the next day’s 00:00 boundary. It is not counted twice.',
                ),
                style: TextStyle(fontSize: 11),
              ),
              Text(
                _periodDisplayCopy(
                  context,
                  data.precise ? '出生図基準の配置表示・日点数とは別' : '近似計算の配置表示・日点数とは別',
                  data.precise
                      ? 'Natal-chart-based placements; separate from daily scores'
                      : 'Approximate placements; separate from daily scores',
                ),
                style: const TextStyle(fontSize: 11),
              ),
              if (note.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(note),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Eight unchanged numeric areas, with each category named once. Both tables
/// live entirely inside the preview/export boundary; no horizontal viewport.
Widget _dailyTimelineShareScoreTables(
  BuildContext context,
  List<DailyStarTimelineSharePoint> points,
  FortuneSharePalette palette,
) {
  final strings = AppLanguageScope.stringsOf(context);
  const groups = [
    [
      NineAreaKey.overall,
      NineAreaKey.love,
      NineAreaKey.work,
      NineAreaKey.money,
    ],
    [
      NineAreaKey.mental,
      NineAreaKey.health,
      NineAreaKey.people,
      NineAreaKey.actionDecision,
    ],
  ];
  String compactTitle(NineAreaKey key) => switch (key) {
    NineAreaKey.overall => 'Total',
    NineAreaKey.love => 'Love',
    NineAreaKey.work => 'Work',
    NineAreaKey.money => 'Money',
    NineAreaKey.mental => 'Mind',
    NineAreaKey.health => 'Body',
    NineAreaKey.people => 'Social',
    NineAreaKey.actionDecision => 'Action',
    NineAreaKey.felt => strings.nineAreaTitle(key.name),
  };
  return LayoutBuilder(
    builder: (context, constraints) {
      final compactEnglishHeaders =
          strings.language == AppLanguage.en &&
          (constraints.maxWidth < 420 ||
              MediaQuery.textScalerOf(context).scale(10) >= 16);
      Widget header(String text, {Key? key, String? semanticLabel}) {
        final visualText = Text(
          text,
          key: key,
          softWrap: !(compactEnglishHeaders && semanticLabel != null),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10,
            height: 1.15,
            fontWeight: FontWeight.w700,
            color: palette.text,
          ),
        );
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
          child: Semantics(
            header: true,
            label: semanticLabel ?? text,
            child: ExcludeSemantics(
              child: compactEnglishHeaders && semanticLabel != null
                  ? FittedBox(fit: BoxFit.scaleDown, child: visualText)
                  : visualText,
            ),
          ),
        );
      }

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var group = 0; group < groups.length; group++) ...[
            if (group > 0) const SizedBox(height: 6),
            Table(
              key: ValueKey('star-shared-score-table-$group'),
              columnWidths: const {0: IntrinsicColumnWidth()},
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              border: TableBorder.all(
                color: palette.accent.withValues(alpha: .24),
              ),
              children: [
                TableRow(
                  decoration: BoxDecoration(color: palette.noteBackground),
                  children: [
                    header(_periodDisplayCopy(context, '時刻\nJST', 'Time\nJST')),
                    for (final key in groups[group])
                      header(
                        compactEnglishHeaders
                            ? compactTitle(key)
                            : strings.nineAreaTitle(key.name),
                        key: ValueKey('star-shared-score-header-${key.name}'),
                        semanticLabel: strings.nineAreaTitle(key.name),
                      ),
                  ],
                ),
                for (final point in points)
                  TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        child: Text(
                          point.clock.displayTime,
                          softWrap: false,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 10, height: 1.15),
                        ),
                      ),
                      for (final key in groups[group])
                        Padding(
                          key: ValueKey(
                            'star-shared-score-${point.clock.hourFromDayStart}-${key.name}',
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 3,
                            vertical: 1,
                          ),
                          child: Semantics(
                            label:
                                '${point.clock.displayTime} · ${strings.nineAreaTitle(key.name)}',
                            child: Text(
                              point.scores?[key]?.toString() ?? '—',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: palette.score,
                                fontSize: 12,
                                height: 1.15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ],
        ],
      );
    },
  );
}

Widget _dailyTimelineShareFelt(
  BuildContext context,
  DailyStarTimelineSharePoint point,
  FortuneSharePalette palette,
) {
  final strings = AppLanguageScope.stringsOf(context);
  final value =
      strings.feltLabelText(point.feltLabel) ??
      _periodDisplayCopy(context, '未予測', 'Unavailable');
  return Container(
    key: ValueKey('star-shared-felt-${point.clock.hourFromDayStart}'),
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
    decoration: BoxDecoration(
      color: palette.noteBackground,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: 8,
      runSpacing: 2,
      children: [
        Text(strings.nineAreaTitle(NineAreaKey.felt.name)),
        Text(
          value,
          style: TextStyle(color: palette.text, fontWeight: FontWeight.w900),
        ),
      ],
    ),
  );
}
