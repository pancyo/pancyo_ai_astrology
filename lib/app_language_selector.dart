part of 'main.dart';

class AppLanguageSelector extends StatefulWidget {
  const AppLanguageSelector({super.key});
  @override
  State<AppLanguageSelector> createState() => _AppLanguageSelectorState();
}

class _AppLanguageSelectorState extends State<AppLanguageSelector> {
  bool _saving = false;
  Future<void> _select(AppLanguage language) async {
    if (_saving || language == AppLanguageSettings.current.value) return;
    setState(() => _saving = true);
    try {
      await AppLanguageSettings.save(language);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLanguageSettings.strings.text(AppText.saveFailed))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppLanguage>(
    valueListenable: AppLanguageSettings.current,
    builder: (context, language, _) {
      final strings = AppStrings(language);
      return GlassPanel(
        margin: const EdgeInsets.only(top: 14), padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _SmallSectionLabel(icon: Icons.language_outlined, text: strings.text(AppText.language)),
          const SizedBox(height: 12),
          SegmentedButton<AppLanguage>(
            segments: [for (final item in AppLanguage.values)
              ButtonSegment(value: item, label: Text(item.nativeLabel))],
            selected: {language},
            onSelectionChanged: _saving ? null : (selected) => _select(selected.single),
          ),
          const SizedBox(height: 10),
          Text(strings.text(AppText.languageHelp), style: const TextStyle(fontSize: 12, height: 1.45)),
          const SizedBox(height: 6),
          Text(strings.text(AppText.languageIndependentTimeZone),
            style: const TextStyle(fontSize: 12, height: 1.45, color: Color(0xFFB8C6E0))),
        ]),
      );
    },
  );
}
