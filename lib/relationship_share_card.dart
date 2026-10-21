part of 'main.dart';

const double _relationshipShareCanvasWidth = 560;
const double _relationshipShareOutputPixelRatio = 2;

/// Only display text reaches the image. Birth data and profile notes are absent.
class RelationshipShareSection {
  const RelationshipShareSection({
    required this.title,
    required this.body,
    required this.hint,
  });
  final String title;
  final String body;
  final String hint;
}

class RelationshipShareComposerSheet extends StatefulWidget {
  const RelationshipShareComposerSheet({
    super.key,
    required this.summary,
    required this.sections,
    this.firstName = '',
    this.secondName = '',
  });
  final String summary;
  final List<RelationshipShareSection> sections;
  final String firstName;
  final String secondName;
  @override
  State<RelationshipShareComposerSheet> createState() =>
      _RelationshipShareComposerSheetState();
}

class _RelationshipShareComposerSheetState
    extends State<RelationshipShareComposerSheet> {
  final _preview = GlobalKey();
  late final TextEditingController _first;
  late final TextEditingController _second;
  bool _includeNames = false;
  bool _busy = false;
  String? _error;
  FortuneShareTheme _theme = FortuneShareTheme.catTwilight;
  String _copy(String ja, String en) => _relationshipCopy(context, ja, en);

  Widget _cardCanvas(BuildContext context) {
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(textScaler: TextScaler.noScaling),
      child: SizedBox(
        width: _relationshipShareCanvasWidth,
        child: RelationshipShareImageCard(
          summary: widget.summary,
          sections: widget.sections,
          firstName: _includeNames ? _first.text.trim() : '',
          secondName: _includeNames ? _second.text.trim() : '',
          theme: _theme,
        ),
      ),
    );
  }

  void _showEnlargedPreview() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final availableHeight = MediaQuery.sizeOf(dialogContext).height - 96;
        final viewerHeight = availableHeight < 720 ? availableHeight : 720.0;
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: SizedBox(
            width: _relationshipShareCanvasWidth,
            height: viewerHeight,
            child: Stack(
              children: [
                Positioned.fill(
                  child: InteractiveViewer(
                    constrained: false,
                    minScale: 0.45,
                    maxScale: 4,
                    boundaryMargin: const EdgeInsets.all(48),
                    child: _cardCanvas(dialogContext),
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: IconButton.filledTonal(
                    tooltip: _copy('閉じる', 'Close'),
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _first = TextEditingController(text: widget.firstName);
    _second = TextEditingController(text: widget.secondName);
  }

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary = _preview.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary) {
        throw StateError('Preview not ready');
      }
      final image = await boundary.toImage(
        pixelRatio: _relationshipShareOutputPixelRatio,
      );
      ByteData? bytes;
      try {
        bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      } finally {
        image.dispose();
      }
      if (bytes == null) throw StateError('PNG unavailable');
      final png = bytes.buffer.asUint8List(
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      );
      final temporary = await getTemporaryDirectory();
      final folder = Directory(
        '${temporary.path}${Platform.pathSeparator}'
        'pancyo_relationship_share_${DateTime.now().microsecondsSinceEpoch}',
      );
      await folder.create();
      final file = File(
        '${folder.path}${Platform.pathSeparator}relationship.png',
      );
      await file.writeAsBytes(png, flush: true);
      final readback = await file.readAsBytes();
      var equal = png.length == readback.length;
      for (var i = 0; equal && i < png.length; i++) {
        equal = png[i] == readback[i];
      }
      if (!equal) throw StateError('PNG readback differs');
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
          // Fall back to the existing platform share implementation.
        } on MissingPluginException {
          // Host tests / platforms without the Android compatibility bridge.
        }
      }
      if (!opened) {
        await Share.shareXFiles([XFile(file.path, mimeType: 'image/png')]);
      }
    } catch (_) {
      if (mounted)
        setState(
          () => _error = _copy(
            '共有画像を作成・表示できませんでした。もう一度お試しください。',
            'Could not prepare or open the share image. Please try again.',
          ),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: AbsorbPointer(
        absorbing: _busy,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            16,
            20,
            16,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _copy('相性の共有カード', 'Relationship share card'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                _copy(
                  '二人の傾向と会話のヒントを共有できます。名前は選んだ場合だけ載せます。',
                  'Share relationship themes and conversation ideas. Names appear only if you choose to include them.',
                ),
              ),
              const SizedBox(height: 16),
              Semantics(
                button: true,
                label: _copy('共有カードを拡大して表示', 'Enlarge share card preview'),
                child: GestureDetector(
                  key: const ValueKey('relationship-share-preview-zoom'),
                  onTap: _showEnlargedPreview,
                  child: FittedBox(
                    key: const ValueKey('relationship-share-preview-fit'),
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.topCenter,
                    child: RepaintBoundary(
                      key: _preview,
                      child: _cardCanvas(context),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  _copy('画像をタップすると拡大できます', 'Tap the image to zoom'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 16),
              SwitchListTile.adaptive(
                key: const ValueKey('relationship-share-include-names'),
                contentPadding: EdgeInsets.zero,
                title: Text(_copy('共有カードに名前を載せる', 'Include names on the card')),
                value: _includeNames,
                onChanged: (value) => setState(() => _includeNames = value),
              ),
              if (_includeNames) ...[
                TextField(
                  key: const ValueKey('relationship-share-first-name'),
                  controller: _first,
                  decoration: InputDecoration(
                    labelText: _copy('一人目の表示名', 'First display name'),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                TextField(
                  key: const ValueKey('relationship-share-second-name'),
                  controller: _second,
                  decoration: InputDecoration(
                    labelText: _copy('二人目の表示名', 'Second display name'),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
              const SizedBox(height: 16),
              Text(_copy('カードの絵柄', 'Card theme')),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final theme in FortuneShareTheme.values)
                    if (theme != FortuneShareTheme.custom)
                      ShareWallpaperOption(
                        theme: theme,
                        selected: theme == _theme,
                        onTap: () => setState(() => _theme = theme),
                      ),
                ],
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!),
                ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const ValueKey('relationship-share-export'),
                onPressed: _busy ? null : _share,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.ios_share),
                label: Text(_copy('この画像を共有', 'Share this image')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RelationshipShareImageCard extends StatelessWidget {
  const RelationshipShareImageCard({
    super.key,
    required this.summary,
    required this.sections,
    this.firstName = '',
    this.secondName = '',
    this.theme = FortuneShareTheme.catTwilight,
  });
  final String summary;
  final List<RelationshipShareSection> sections;
  final String firstName;
  final String secondName;
  final FortuneShareTheme theme;

  @override
  Widget build(BuildContext context) {
    final english = _relationshipEnglish(context);
    final palette = theme.palette;
    final art = theme.catArtKind;
    final image = theme.imageProvider('');
    return Container(
      key: const ValueKey('relationship-share-image'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.accent.withValues(alpha: 0.5)),
      ),
      child: DefaultTextStyle(
        style: TextStyle(color: palette.text, fontSize: 14, height: 1.5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) => ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxWidth * 0.48,
                ),
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    Positioned.fill(
                      child: Opacity(
                        opacity: 0.42,
                        child: image != null
                            ? Image(image: image, fit: BoxFit.contain)
                            : art == null
                            ? const SizedBox.shrink()
                            : Center(
                                child: ShareCatArt(
                                  kind: art,
                                  width: constraints.maxWidth,
                                  height: constraints.maxWidth * 0.55,
                                ),
                              ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: palette.surface.withValues(alpha: 0.88),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              english ? 'Pancyo Astrology' : 'ぱんちょ式星占い',
                              style: TextStyle(
                                color: palette.accent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              english
                                  ? 'Our relationship themes'
                                  : 'ふたりの相性のヒント',
                              style: const TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (firstName.isNotEmpty ||
                                secondName.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                [
                                  firstName,
                                  secondName,
                                ].where((name) => name.isNotEmpty).join(' × '),
                                key: const ValueKey('relationship-share-names'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text(summary),
            ),
            for (var index = 0; index < sections.length; index++)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Container(
                  key: ValueKey('relationship-share-section-$index'),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: palette.noteBackground,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        sections[index].title,
                        style: TextStyle(
                          color: palette.accent,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(sections[index].body),
                      const SizedBox(height: 8),
                      Text(
                        '${english ? 'Try this' : '会話のヒント'}: ${sections[index].hint}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
              child: Text(
                english
                    ? 'Astrological perspectives for conversation, not a score or a prediction of your relationship.'
                    : '二人で話すための占星術のヒントです。点数や関係の結果を示すものではありません。',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
