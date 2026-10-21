part of 'main.dart';

/// Presentation values supplied by the existing day/period forecast. No scoring
/// or birth/profile data is read by the card. Felt remains a category.
class FortuneShareArea {
  const FortuneShareArea({
    required this.key,
    required this.title,
    this.score,
    this.feltLabel,
  });

  final NineAreaKey key;
  final String title;
  final int? score;
  final String? feltLabel;
}

class FortuneShareComposerSheet extends StatefulWidget {
  const FortuneShareComposerSheet({
    super.key,
    required this.periodLabel,
    required this.score,
    required this.body,
    required this.metricLabel,
    this.areas = const [],
    this.areaHighlightsText = '',
  });

  final String periodLabel;
  final int? score;
  final String body;
  final String metricLabel;
  final List<FortuneShareArea> areas;
  final String areaHighlightsText;

  @override
  State<FortuneShareComposerSheet> createState() =>
      _FortuneShareComposerSheetState();
}

class _FortuneShareComposerSheetState extends State<FortuneShareComposerSheet> {
  static const _shareCompatibilityChannel = MethodChannel(
    'com.pancyo.aiastrology/share_compat',
  );
  static const _displayNameKey = 'share_card_display_name';
  static const _showScoreKey = 'share_card_show_score';
  static const _showBodyKey = 'share_card_show_body';
  static const _themeKey = 'share_card_theme';
  static const _customWallpaperKey = 'share_card_custom_wallpaper';

  final _previewKey = GlobalKey();
  final _displayNameController = TextEditingController();
  final _noteController = TextEditingController();
  bool _showScore = true;
  bool _showBody = true;
  FortuneShareTheme _theme = FortuneShareTheme.night;
  String _customWallpaperPath = '';
  bool _sharing = false;
  String _shareError = '';

  @override
  void initState() {
    super.initState();
    _restoreSettings();
  }

  Future<void> _restoreSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _displayNameController.text = prefs.getString(_displayNameKey) ?? '';
      _showScore = prefs.getBool(_showScoreKey) ?? true;
      _showBody = prefs.getBool(_showBodyKey) ?? true;
      _theme = FortuneShareTheme.values.firstWhere(
        (theme) => theme.name == prefs.getString(_themeKey),
        orElse: () => FortuneShareTheme.night,
      );
      _customWallpaperPath = prefs.getString(_customWallpaperKey) ?? '';
    });
  }

  Future<void> _pickCustomWallpaper() async {
    try {
      final selected = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1800,
        imageQuality: 90,
      );
      if (selected == null) return;
      final documents = await getApplicationDocumentsDirectory();
      final directory = Directory(
        '${documents.path}${Platform.pathSeparator}share_wallpapers',
      );
      if (!await directory.exists()) await directory.create(recursive: true);
      final extension = selected.path.toLowerCase().endsWith('.png')
          ? '.png'
          : '.jpg';
      final target = File(
        '${directory.path}${Platform.pathSeparator}custom_wallpaper$extension',
      );
      await File(selected.path).copy(target.path);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_customWallpaperKey, target.path);
      if (!mounted) return;
      setState(() {
        _customWallpaperPath = target.path;
        _theme = FortuneShareTheme.custom;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: EnglishUiText('壁紙を読み込めませんでした。別の画像でお試しください。')),
        );
      }
    }
  }

  Future<void> _clearCustomWallpaper() async {
    final path = _customWallpaperPath;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_customWallpaperKey);
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _customWallpaperPath = '';
      if (_theme == FortuneShareTheme.custom) _theme = FortuneShareTheme.night;
    });
  }

  Future<void> _share() async {
    if (_sharing) return;
    final renderObject = _previewKey.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) {
      setState(() => _shareError = '共有画像の準備ができませんでした。画面を開き直してください。');
      return;
    }
    final boundary = renderObject;
    setState(() {
      _sharing = true;
      _shareError = '';
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _displayNameKey,
        _displayNameController.text.trim(),
      );
      await prefs.setBool(_showScoreKey, _showScore);
      await prefs.setBool(_showBodyKey, _showBody);
      await prefs.setString(_themeKey, _theme.name);
      await prefs.setString(_customWallpaperKey, _customWallpaperPath);

      XFile shareFile;
      try {
        await WidgetsBinding.instance.endOfFrame;
        final image = await boundary.toImage(pixelRatio: 1.5);
        ByteData? bytes;
        try {
          bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        } finally {
          image.dispose();
        }
        if (bytes == null) throw StateError('共有画像を作成できませんでした');
        final directory = await getTemporaryDirectory();
        final file = File(
          '${directory.path}${Platform.pathSeparator}pancyo_share_${DateTime.now().millisecondsSinceEpoch}.png',
        );
        final pngBytes = bytes.buffer.asUint8List(
          bytes.offsetInBytes,
          bytes.lengthInBytes,
        );
        await file.writeAsBytes(pngBytes, flush: true);
        final savedBytes = await file.readAsBytes();
        var bytesMatch = savedBytes.length == pngBytes.length;
        for (var index = 0; bytesMatch && index < pngBytes.length; index++) {
          bytesMatch = savedBytes[index] == pngBytes[index];
        }
        if (!bytesMatch) {
          throw StateError('共有画像の保存内容を確認できませんでした。');
        }
        shareFile = XFile(file.path, mimeType: 'image/png');
      } catch (error, stackTrace) {
        debugPrint('Share image generation failed: $error\n$stackTrace');
        if (mounted)
          setState(() => _shareError = '共有画像を作成できませんでした。もう一度お試しください。');
        return;
      }
      try {
        // Androidは結果待ちをしない共有起動にして、singleTaskの共有先を
        // このアプリの画面スタックへ積まない。iOSなどはshare_plusを使う。
        var openedByCompatibilityShare = false;
        if (Platform.isAndroid) {
          try {
            openedByCompatibilityShare =
                await _shareCompatibilityChannel.invokeMethod<bool>(
                  'shareImage',
                  {'path': shareFile.path, 'mimeType': 'image/png'},
                ) ??
                false;
          } on PlatformException catch (error, stackTrace) {
            debugPrint(
              'Compatibility share launch failed: $error\n$stackTrace',
            );
          }
        }
        if (!openedByCompatibilityShare) {
          // 画像と文章の同時共有を受け取れないSNSがあるため、PNGだけを渡す。
          await Share.shareXFiles([shareFile]);
        }
      } catch (error, stackTrace) {
        debugPrint('Share sheet launch failed: $error\n$stackTrace');
        if (mounted)
          setState(() => _shareError = '共有機能を開けませんでした。アプリを更新してもう一度お試しください。');
      }
    } catch (error, stackTrace) {
      debugPrint('Share preparation failed: $error\n$stackTrace');
      if (mounted) setState(() => _shareError = '共有の準備に失敗しました。もう一度お試しください。');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyboardBottom = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + keyboardBottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const EnglishUiText(
                '共有カードを整える',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              EnglishUiText(
                '数値と説明はそのままに、見せ方だけを自分用にできます。',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.64),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 14),
              RepaintBoundary(
                key: _previewKey,
                child: FortuneShareImageCard(
                  periodLabel: widget.periodLabel,
                  score: widget.score,
                  body: widget.body,
                  metricLabel: widget.metricLabel,
                  areas: widget.areas,
                  areaHighlightsText: widget.areaHighlightsText,
                  displayName: _displayNameController.text.trim(),
                  note: _noteController.text.trim(),
                  showScore: _showScore,
                  showBody: _showBody,
                  theme: _theme,
                  customWallpaperPath: _customWallpaperPath,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _displayNameController,
                maxLength: 20,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: localizedUiText(context, '表示名（任意）'),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _noteController,
                maxLength: 42,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: localizedUiText(context, 'ひとこと（任意）'),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 6),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const EnglishUiText('点数を表示'),
                value: _showScore,
                onChanged: (value) => setState(() => _showScore = value),
              ),
              const SizedBox(height: 6),
              const EnglishUiText(
                'カードのテーマ',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: FortuneShareTheme.values
                    .where((theme) => theme != FortuneShareTheme.custom)
                    .map(
                      (theme) => ShareWallpaperOption(
                        theme: theme,
                        selected: _theme == theme,
                        onTap: () => setState(() => _theme = theme),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickCustomWallpaper,
                    icon: const Icon(
                      Icons.add_photo_alternate_outlined,
                      size: 18,
                    ),
                    label: Text(
                      localizedUiText(
                        context,
                        _theme == FortuneShareTheme.custom ? '壁紙を変更' : '壁紙を選ぶ',
                      ),
                    ),
                  ),
                  if (_customWallpaperPath.isNotEmpty) ...[
                    _CustomWallpaperThumbnail(path: _customWallpaperPath),
                  ],
                  if (_customWallpaperPath.isNotEmpty) ...[
                    IconButton(
                      tooltip: localizedUiText(context, 'カスタム壁紙を削除'),
                      onPressed: _clearCustomWallpaper,
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ],
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const EnglishUiText('鑑定文を表示'),
                value: _showBody,
                onChanged: (value) => setState(() => _showBody = value),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _sharing ? null : _share,
                  icon: _sharing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.ios_share_outlined),
                  label: Text(
                    localizedUiText(context, _sharing ? '画像を作成中…' : 'この画像を共有'),
                  ),
                ),
              ),
              if (_shareError.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  localizedUiText(context, _shareError),
                  style: const TextStyle(
                    color: Color(0xFFFFB4AB),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class FortuneShareImageCard extends StatelessWidget {
  const FortuneShareImageCard({
    super.key,
    required this.periodLabel,
    required this.score,
    required this.body,
    required this.metricLabel,
    this.areas = const [],
    this.areaHighlightsText = '',
    required this.displayName,
    required this.note,
    required this.showScore,
    required this.showBody,
    required this.theme,
    required this.customWallpaperPath,
  });

  final String periodLabel;
  final int? score;
  final String body;
  final String metricLabel;
  final List<FortuneShareArea> areas;
  final String areaHighlightsText;
  final String displayName;
  final String note;
  final bool showScore;
  final bool showBody;
  final FortuneShareTheme theme;
  final String customWallpaperPath;

  FortuneShareArea? _area(NineAreaKey key) {
    for (final area in areas) {
      if (area.key == key) return area;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final palette = theme.palette;
    final strings = AppLanguageScope.stringsOf(context);
    final english = strings.language == AppLanguage.en;
    final translatedBody = localizedKnownReading(context, body);
    final previewLimit = english ? 240 : 120;
    final previewBody = translatedBody.runes.length > previewLimit
        ? '${String.fromCharCodes(translatedBody.runes.take(previewLimit))}…'
        : translatedBody;
    final imageProvider = theme.imageProvider(customWallpaperPath);
    final art = theme.catArtKind;
    final primary = areas.length == 1
        ? areas.single
        : _area(NineAreaKey.overall);
    final primaryScore = areas.isEmpty ? score : primary?.score;
    String title(FortuneShareArea area) =>
        english ? strings.nineAreaTitle(area.key.name) : area.title;
    final primaryTitle = areas.isEmpty
        ? localizedUiText(context, metricLabel)
        : primary == null
        ? strings.nineAreaTitle('overall')
        : title(primary);
    final felt = _area(NineAreaKey.felt);
    Widget areaTile(FortuneShareArea area) => Container(
      key: ValueKey('share-area-${area.key.name}'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: palette.noteBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title(area),
            style: TextStyle(color: palette.text, fontSize: 12),
          ),
          if (showScore) ...[
            const SizedBox(height: 4),
            Text(
              area.score?.toString() ?? '—',
              key: ValueKey('share-score-${area.key.name}'),
              style: TextStyle(
                color: palette.score,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ],
      ),
    );
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: palette.background,
          border: Border.all(color: palette.accent.withValues(alpha: 0.55)),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth.isFinite
                    ? constraints.maxWidth
                    : 360.0;
                // At normal text scale the hero is a generous 10:7 frame.
                // It grows for accessibility text so the overlay never clips.
                final heroHeight =
                    width *
                    (0.70 + (textScale - 1).clamp(0.0, 1.0) * 0.38).toDouble();
                final vectorArtHeight = heroHeight * 0.78;
                final overlayWidth = art == null ? 0.78 : 0.54;
                return ConstrainedBox(
                  key: const ValueKey('share-art-region'),
                  // The artwork keeps its normal frame as a minimum. The
                  // overlay determines any extra height required by text.
                  constraints: BoxConstraints(minHeight: heroHeight),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(17),
                    ),
                    child: Stack(
                      fit: StackFit.loose,
                      alignment: Alignment.centerLeft,
                      children: [
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  palette.background,
                                  Color.lerp(
                                    palette.background,
                                    palette.accent,
                                    0.22,
                                  )!,
                                  palette.background,
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (imageProvider != null) ...[
                          // The soft, expanded copy fills only the letterbox
                          // margins; the complete sharp artwork stays intact
                          // above it in BoxFit.contain.
                          Positioned.fill(
                            child: Opacity(
                              opacity: 0.48,
                              child: ImageFiltered(
                                imageFilter: ui.ImageFilter.blur(
                                  sigmaX: 18,
                                  sigmaY: 18,
                                ),
                                child: Image(
                                  image: imageProvider,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: Image(
                              image: imageProvider,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ] else if (art != null)
                          Positioned.fill(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: ShareCatArt(
                                kind: art,
                                width: vectorArtHeight * 132 / 92,
                                height: vectorArtHeight,
                              ),
                            ),
                          ),
                        // This fade keeps the image visible while providing a
                        // quiet reading zone behind the translucent overlay.
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                stops: const [0, 0.56, 1],
                                colors: [
                                  palette.surface.withValues(alpha: 0.88),
                                  palette.surface.withValues(alpha: 0.72),
                                  palette.surface.withValues(alpha: 0),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: overlayWidth,
                            child: Padding(
                              padding: const EdgeInsets.only(
                                left: 12,
                                right: 8,
                                top: 10,
                                bottom: 10,
                              ),
                              child: Container(
                                key: const ValueKey('share-overlay-panel'),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: palette.surface.withValues(
                                    alpha: 0.82,
                                  ),
                                  borderRadius: BorderRadius.circular(15),
                                  border: Border.all(
                                    color: palette.accent.withValues(
                                      alpha: 0.38,
                                    ),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.12,
                                      ),
                                      blurRadius: 14,
                                      offset: const Offset(0, 5),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    EnglishUiText(
                                      'ぱんちょ式星占い',
                                      style: TextStyle(
                                        color: palette.accent,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    EnglishUiText(
                                      periodLabel,
                                      key: const ValueKey('share-period'),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: palette.text,
                                        fontSize: 15,
                                        height: 1.18,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    if (displayName.isNotEmpty) ...[
                                      const SizedBox(height: 3),
                                      // Only the explicitly chosen name is used.
                                      Text(
                                        displayName,
                                        key: const ValueKey(
                                          'share-display-name',
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: palette.text,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 5),
                                    Text(
                                      primaryTitle,
                                      key: const ValueKey(
                                        'share-primary-title',
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: palette.text,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    if (showScore)
                                      Text(
                                        primary?.key == NineAreaKey.felt
                                            ? periodFeltDisplayLabel(
                                                primary?.feltLabel ?? '未予測',
                                                strings,
                                              )
                                            : primaryScore?.toString() ?? '—',
                                        key: ValueKey(
                                          'share-score-${primary?.key.name ?? 'overall'}',
                                        ),
                                        style: TextStyle(
                                          fontSize:
                                              primary?.key == NineAreaKey.felt
                                              ? 24
                                              : 40,
                                          height: 1.05,
                                          fontWeight: FontWeight.w900,
                                          color: palette.score,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            Container(
              key: const ValueKey('share-text-surface'),
              color: palette.surface,
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (areas.length > 1) ...[
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth >= 360 ? 3 : 2;
                        final tileWidth =
                            (constraints.maxWidth - (columns - 1) * 8) /
                            columns;
                        return Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final key in NineAreaKey.values)
                              if (key != NineAreaKey.overall &&
                                  key != NineAreaKey.felt &&
                                  _area(key) != null)
                                SizedBox(
                                  width: tileWidth,
                                  child: areaTile(_area(key)!),
                                ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    if (felt != null)
                      Container(
                        key: const ValueKey('share-felt-category'),
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: palette.noteBackground,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title(felt),
                              style: TextStyle(
                                color: palette.text,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              periodFeltDisplayLabel(
                                felt.feltLabel ?? '未予測',
                                strings,
                              ),
                              key: const ValueKey('share-felt-label'),
                              style: TextStyle(
                                color: palette.text,
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  if (showBody && areaHighlightsText.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      areaHighlightsText,
                      key: const ValueKey('share-area-highlights'),
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 14,
                        height: 1.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (showBody && previewBody.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      previewBody,
                      key: const ValueKey('share-reading'),
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 13,
                        height: 1.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  if (note.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: palette.noteBackground,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        note,
                        key: const ValueKey('share-note'),
                        style: TextStyle(
                          color: palette.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ShareWallpaperOption extends StatelessWidget {
  const ShareWallpaperOption({
    super.key,
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  final FortuneShareTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = theme.palette;
    final image = theme.imageProvider('');
    return Semantics(
      button: true,
      selected: selected,
      label: theme.displayLabel(AppLanguageScope.stringsOf(context)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 104,
          height: 74,
          decoration: BoxDecoration(
            color: palette.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? const Color(0xFF57D6D1)
                  : Colors.white.withValues(alpha: 0.22),
              width: selected ? 2 : 1,
            ),
            image: image == null
                ? null
                : DecorationImage(image: image, fit: BoxFit.cover),
          ),
          child: Stack(
            children: [
              if (theme.catArtKind != null)
                ShareCatArt(kind: theme.catArtKind!, width: 104, height: 74),
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(7),
                    ),
                  ),
                  child: Text(
                    theme.displayLabel(AppLanguageScope.stringsOf(context)),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomWallpaperThumbnail extends StatelessWidget {
  const _CustomWallpaperThumbnail({required this.path});
  final String path;

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    if (!file.existsSync()) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.file(file, width: 44, height: 36, fit: BoxFit.cover),
    );
  }
}

enum FortuneShareTheme {
  night('アプリ背景'),
  bright('明るめ'),
  report('資料風'),
  catMoon('ねこ月'),
  catBook('ねこ読書'),
  catSleep('ねこおやすみ'),
  catStars('ねこ星めぐり'),
  catFlower('ねこ花日和'),
  catForest('ねこ森だより'),
  catTwilight('ねこ黄昏'),
  custom('カスタム');

  const FortuneShareTheme(this.label);
  final String label;

  String displayLabel(AppStrings strings) => strings.language == AppLanguage.ja
      ? label
      : switch (this) {
          FortuneShareTheme.night => 'Night sky',
          FortuneShareTheme.bright => 'Bright',
          FortuneShareTheme.report => 'Report',
          FortuneShareTheme.catMoon => 'Moon cat',
          FortuneShareTheme.catBook => 'Book cat',
          FortuneShareTheme.catSleep => 'Sleepy cat',
          FortuneShareTheme.catStars => 'Stargazing cat',
          FortuneShareTheme.catFlower => 'Flower cat',
          FortuneShareTheme.catForest => 'Forest cat',
          FortuneShareTheme.catTwilight => 'Twilight cat',
          FortuneShareTheme.custom => 'Custom',
        };

  ShareCatArtKind? get catArtKind => switch (this) {
    FortuneShareTheme.catFlower => ShareCatArtKind.flowers,
    FortuneShareTheme.catForest => ShareCatArtKind.forest,
    FortuneShareTheme.catTwilight => ShareCatArtKind.twilight,
    _ => null,
  };

  FortuneSharePalette get palette => switch (this) {
    FortuneShareTheme.night => const FortuneSharePalette(
      Color(0xFF121936),
      Color(0xFF57D6D1),
      Color(0xFFF6D77A),
      Color(0xFFE9EEFF),
      Color(0x18FFFFFF),
      Color(0xFF11172F),
    ),
    FortuneShareTheme.bright => const FortuneSharePalette(
      Color(0xFFF5F8FF),
      Color(0xFF147B85),
      Color(0xFFB56A00),
      Color(0xFF17203B),
      Color(0x1817203B),
      Color(0xFFF5F8FF),
    ),
    FortuneShareTheme.report => const FortuneSharePalette(
      Color(0xFF10231F),
      Color(0xFF91D5B4),
      Color(0xFFFFD480),
      Color(0xFFF2FFF7),
      Color(0x1FFFFFFF),
      Color(0xFF10231F),
    ),
    FortuneShareTheme.catMoon => const FortuneSharePalette(
      Color(0xFF10264A),
      Color(0xFFFFD77B),
      Color(0xFFFFD77B),
      Color(0xFFF7F4E8),
      Color(0x24FFFFFF),
      Color(0xFF10264A),
    ),
    FortuneShareTheme.catBook => const FortuneSharePalette(
      Color(0xFF1A294B),
      Color(0xFFFFD89A),
      Color(0xFFFFD89A),
      Color(0xFFFFF6E8),
      Color(0x24FFFFFF),
      Color(0xFF14203B),
    ),
    FortuneShareTheme.catSleep => const FortuneSharePalette(
      Color(0xFF10264A),
      Color(0xFFFFD77B),
      Color(0xFFFFD77B),
      Color(0xFFF7F4E8),
      Color(0x24FFFFFF),
      Color(0xFF10264A),
    ),
    FortuneShareTheme.catStars => const FortuneSharePalette(
      Color(0xFF1A294B),
      Color(0xFFFFD89A),
      Color(0xFFFFD89A),
      Color(0xFFFFF6E8),
      Color(0x24FFFFFF),
      Color(0xFF14203B),
    ),
    FortuneShareTheme.catFlower => const FortuneSharePalette(
      Color(0xFFFFF7EE),
      Color(0xFF92566D),
      Color(0xFF8B425B),
      Color(0xFF3D3035),
      Color(0xFFFFEAF0),
      Color(0xFFFFFCF7),
    ),
    FortuneShareTheme.catForest => const FortuneSharePalette(
      Color(0xFFE9F2E4),
      Color(0xFF486347),
      Color(0xFF3E623B),
      Color(0xFF2C382A),
      Color(0xFFEAF0DD),
      Color(0xFFFFFCF0),
    ),
    FortuneShareTheme.catTwilight => const FortuneSharePalette(
      Color(0xFFFFDDBF),
      Color(0xFF74527D),
      Color(0xFF83516C),
      Color(0xFF3E3048),
      Color(0xFFF2E6F3),
      Color(0xFFFFF7EF),
    ),
    FortuneShareTheme.custom => const FortuneSharePalette(
      Color(0xFF121936),
      Color(0xFF57D6D1),
      Color(0xFFF6D77A),
      Color(0xFFE9EEFF),
      Color(0x18FFFFFF),
      Color(0xFF11172F),
    ),
  };

  ImageProvider? imageProvider(String customWallpaperPath) => switch (this) {
    FortuneShareTheme.night => const AssetImage(
      'assets/images/astro_lake_hero.png',
    ),
    FortuneShareTheme.catMoon => const AssetImage(
      'assets/images/share_cat_moon.png',
    ),
    FortuneShareTheme.catBook => const AssetImage(
      'assets/images/share_cat_book.png',
    ),
    FortuneShareTheme.catSleep => const AssetImage(
      'assets/images/share_cat_sleep.png',
    ),
    FortuneShareTheme.catStars => const AssetImage(
      'assets/images/share_cat_stars.png',
    ),
    FortuneShareTheme.custom
        when customWallpaperPath.trim().isNotEmpty &&
            File(customWallpaperPath).existsSync() =>
      FileImage(File(customWallpaperPath)),
    _ => null,
  };
}

class FortuneSharePalette {
  const FortuneSharePalette(
    this.background,
    this.accent,
    this.score,
    this.text,
    this.noteBackground,
    this.surface,
  );
  final Color background;
  final Color accent;
  final Color score;
  final Color text;
  final Color noteBackground;
  final Color surface;
}
