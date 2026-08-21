import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'swiss_ephemeris_bridge.dart';

// 旧版の任意ダウンロードデータと廃止した履歴だけを、更新時に安全に掃除する。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await HouseSystemSettings.restore();
  await LegacyDataCleanup.removeFromPreviousVersions();
  runApp(const PancyoAstrologyApp());
}

/// 旧版の任意ダウンロードデータと、保存しない方針に変えた履歴だけを起動時に掃除する。
/// プロフィールや占い設定など利用者の設定は対象外。
class LegacyDataCleanup {
  const LegacyDataCleanup._();

  static Future<void> removeFromPreviousVersions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      const keys = <String>[
        'ai_data.installed', 'ai_data.model_name', 'ai_data.license',
        'ai_data.source_label', 'ai_data.source_url', 'ai_data.runtime',
        'ai_data.size_bytes', 'ai_data.downloaded_at', 'ai_data.checksum',
        'ai_data.file_path',
        'custom_fortune.logs',
        'daily_fortune_reflections.v1',
      ];
      final modelPath = prefs.getString('ai_data.file_path');
      for (final key in keys) {
        await prefs.remove(key);
      }
      if (modelPath != null && modelPath.trim().isNotEmpty) {
        final file = File(modelPath);
        if (await file.exists()) await file.delete();
      }
    } catch (_) {}
  }
}

class PancyoAstrologyApp extends StatelessWidget {
  const PancyoAstrologyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final interactionOverlay = WidgetStateProperty.resolveWith<Color?>((states) {
      if (states.contains(WidgetState.pressed)) {
        return const Color(0xFFB8FFF5).withValues(alpha: 0.32);
      }
      if (states.contains(WidgetState.hovered) || states.contains(WidgetState.focused)) {
        return const Color(0xFF57D6D1).withValues(alpha: 0.18);
      }
      return null;
    });
    return MaterialApp(
      title: 'ぱんちょ式 超本格占星術占い',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ja', 'JP'),
      supportedLocales: const [
        Locale('ja', 'JP'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF070713),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF57D6D1),
          brightness: Brightness.dark,
        ),
        splashFactory: InkSparkle.splashFactory,
        splashColor: const Color(0xFFB8FFF5).withValues(alpha: 0.26),
        highlightColor: const Color(0xFF57D6D1).withValues(alpha: 0.22),
        filledButtonTheme: FilledButtonThemeData(
          style: ButtonStyle(overlayColor: interactionOverlay),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: ButtonStyle(overlayColor: interactionOverlay),
        ),
        textButtonTheme: TextButtonThemeData(
          style: ButtonStyle(overlayColor: interactionOverlay),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: ButtonStyle(overlayColor: interactionOverlay),
        ),
        fontFamily: 'Roboto',
      ),
      home: const BirthInfoScreen(),
    );
  }
}

class BirthInfoScreen extends StatefulWidget {
  const BirthInfoScreen({super.key});

  @override
  State<BirthInfoScreen> createState() => _BirthInfoScreenState();
}

class _BirthInfoScreenState extends State<BirthInfoScreen> {
  final _nameController = TextEditingController(text: 'pancyo');
  final _birthDateController = TextEditingController(text: '1980/9/24');
  UserProfileDetails _selectedDetails = const UserProfileDetails.empty();
  SavedUserProfile? _activeSavedProfile;
  late Future<List<SavedUserProfile>> _savedProfilesFuture;
  String _theme = '仕事';

  @override
  void initState() {
    super.initState();
    _savedProfilesFuture = SavedUserProfile.loadAll();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _birthDateController.dispose();
    super.dispose();
  }

  void _startReading() {
    final birthDateText = _birthDateController.text.trim();
    final parsedBirthDate = _birthDateFromText();
    final today = DateTime.now();
    if (birthDateText.isNotEmpty &&
        (parsedBirthDate == null || parsedBirthDate.isAfter(today))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('生年月日を正しい日付で入力してください。')),
      );
      return;
    }
    final activeProfile = _activeSavedProfile;
    final isEditingActiveProfile = activeProfile != null &&
        _nameController.text.trim() == activeProfile.name.trim() &&
        _birthDateController.text.trim() == activeProfile.birthDate.trim();
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (_) => ReadingScreen(
          profile: AstroProfile(
            name: _nameController.text.trim().isEmpty
                ? 'あなた'
                : _nameController.text.trim(),
            birthDate: _birthDateController.text.trim().isEmpty
                ? '1980/9/24'
                : _birthDateController.text.trim(),
            birthTime: _selectedDetails.effectiveBirthTime,
            birthPlace: _selectedDetails.effectiveBirthPlace,
            theme: _theme,
            savedProfileId:
                isEditingActiveProfile ? activeProfile!.id : SavedUserProfile.createId(),
          ),
          // Empty details must also be passed explicitly. Otherwise a new person
          // can accidentally inherit the previous person's locally cached birth data.
          initialDetails: _selectedDetails,
          onProfileSaved: _handleProfileSaved,
        ),
      ),
    )
        .then((_) {
      if (!mounted) return;
      setState(() {
        _savedProfilesFuture = SavedUserProfile.loadAll();
      });
    });
  }

  void _handleProfileSaved(SavedUserProfile saved) {
    if (!mounted) return;
    setState(() {
      _selectedDetails = saved.details;
      _activeSavedProfile = saved;
      _savedProfilesFuture = SavedUserProfile.loadAll();
    });
  }

  void _reloadSavedProfiles() {
    if (!mounted) return;
    setState(() {
      _savedProfilesFuture = SavedUserProfile.loadAll();
    });
  }

  void _startNewProfile() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _nameController.clear();
      _birthDateController.clear();
      _selectedDetails = const UserProfileDetails.empty();
      _activeSavedProfile = null;
      _theme = '仕事';
    });
  }

  void _applySavedProfile(SavedUserProfile saved) {
    setState(() {
      _nameController.text = saved.name;
      _birthDateController.text = saved.birthDate;
      _selectedDetails = saved.details;
      _activeSavedProfile = saved;
      _savedProfilesFuture = SavedUserProfile.loadAll();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${saved.name} を反映しました')),
    );
  }

  void _detachSavedProfileIfIdentityChanged() {
    final active = _activeSavedProfile;
    if (active == null) return;
    final unchanged = _nameController.text.trim() == active.name.trim() &&
        _birthDateController.text.trim() == active.birthDate.trim();
    if (unchanged) return;
    setState(() {
      _activeSavedProfile = null;
      _selectedDetails = const UserProfileDetails.empty();
    });
  }

  Future<void> _deleteSavedProfile(SavedUserProfile saved) async {
    await SavedUserProfile.delete(saved.id);
    if (!mounted) return;
    setState(() {
      _savedProfilesFuture = SavedUserProfile.loadAll();
      final isSelected = _nameController.text.trim() == saved.name.trim() &&
          _birthDateController.text.trim() == saved.birthDate.trim();
      if (isSelected) {
        _selectedDetails = const UserProfileDetails.empty();
      }
      if (_activeSavedProfile?.id == saved.id) {
        _activeSavedProfile = null;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${saved.name} のプロフィールと関連ログを削除しました')),
    );
  }

  Future<void> _pickBirthDate() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final now = DateTime.now();
    final initialDate = _birthDateFromText() ?? DateTime(1980, 9, 24);
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate.isAfter(now) ? now : initialDate,
      firstDate: DateTime(1900),
      lastDate: now,
      initialDatePickerMode: DatePickerMode.year,
      helpText: '生年月日を選択',
      cancelText: '閉じる',
      confirmText: '決定',
    );
    if (picked == null) return;
    if (!mounted) return;
    _birthDateController.text = '${picked.year}/${picked.month}/${picked.day}';
    _detachSavedProfileIfIdentityChanged();
  }

  DateTime? _birthDateFromText() {
    final match = RegExp(r'(\d{4})\D+(\d{1,2})\D+(\d{1,2})').firstMatch(
      _birthDateController.text,
    );
    if (match == null) return null;
    final year = int.tryParse(match.group(1) ?? '');
    final month = int.tryParse(match.group(2) ?? '');
    final day = int.tryParse(match.group(3) ?? '');
    if (year == null || month == null || day == null) return null;
    final parsed = DateTime(year, month, day);
    if (parsed.year != year || parsed.month != month || parsed.day != day) return null;
    return parsed;
  }

  @override
  Widget build(BuildContext context) {
    return StarScaffold(
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 26, 28, 28),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 44,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _LandingHeader(),
                        const SizedBox(height: 52),
                        const _LandingHero(),
                        const SizedBox(height: 42),
                        _InputPanel(
                          nameController: _nameController,
                          birthDateController: _birthDateController,
                          savedProfilesFuture: _savedProfilesFuture,
                          activeSavedProfile: _activeSavedProfile,
                          onSavedProfilesRefresh: _reloadSavedProfiles,
                          onStartNewProfile: _startNewProfile,
                          theme: _theme,
                          onThemeChanged: (value) => setState(() => _theme = value),
                          onBirthDateTap: _pickBirthDate,
                          onIdentityChanged: _detachSavedProfileIfIdentityChanged,
                          onSavedProfileSelected: _applySavedProfile,
                          onSavedProfileDeleted: _deleteSavedProfile,
                          onStart: _startReading,
                        ),
                        const SizedBox(height: 26),
                        const _FeatureCards(),
                        const SizedBox(height: 28),
                        const _LandingFooter(),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _InputPanel extends StatelessWidget {
  const _InputPanel({
    required this.nameController,
    required this.birthDateController,
    required this.savedProfilesFuture,
    required this.activeSavedProfile,
    required this.onSavedProfilesRefresh,
    required this.onStartNewProfile,
    required this.theme,
    required this.onThemeChanged,
    required this.onBirthDateTap,
    required this.onIdentityChanged,
    required this.onSavedProfileSelected,
    required this.onSavedProfileDeleted,
    required this.onStart,
  });

  final TextEditingController nameController;
  final TextEditingController birthDateController;
  final Future<List<SavedUserProfile>> savedProfilesFuture;
  final SavedUserProfile? activeSavedProfile;
  final VoidCallback onSavedProfilesRefresh;
  final VoidCallback onStartNewProfile;
  final String theme;
  final ValueChanged<String> onThemeChanged;
  final VoidCallback onBirthDateTap;
  final VoidCallback onIdentityChanged;
  final ValueChanged<SavedUserProfile> onSavedProfileSelected;
  final ValueChanged<SavedUserProfile> onSavedProfileDeleted;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(30, 28, 30, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _DecoratedSectionTitle(text: '出生データを入力'),
          const SizedBox(height: 24),
          SavedProfilePicker(
            profilesFuture: savedProfilesFuture,
            onRefresh: onSavedProfilesRefresh,
            onSelected: onSavedProfileSelected,
            onDeleted: onSavedProfileDeleted,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onStartNewProfile,
              icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
              label: const Text('新しい人物を入力'),
            ),
          ),
          const SizedBox(height: 4),
          if (activeSavedProfile != null) ...[
            _ActiveSavedProfileNotice(profile: activeSavedProfile!),
            const SizedBox(height: 16),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 860;
              final fields = [
                AstroTextField(
                  controller: nameController,
                  label: 'ニックネーム',
                  hint: '例）ぱんちょ',
                  icon: Icons.person_outline,
                  onChanged: (_) => onIdentityChanged(),
                ),
                AstroTextField(
                  controller: birthDateController,
                  label: '生年月日',
                  hint: 'タップして選択 / 例）1980/9/24',
                  icon: Icons.calendar_month_outlined,
                  onTap: onBirthDateTap,
                  suffixIcon: Icons.expand_more,
                ),
              ];

              if (!isWide) {
                return Column(children: fields);
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: fields
                    .map(
                      (field) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: field,
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 24),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7A4DFF), Color(0xFFF6D77A)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFF6D77A).withValues(alpha: 0.22),
                      blurRadius: 26,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: FilledButton.icon(
                  onPressed: onStart,
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('ホロスコープを読む'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(62),
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: onStart,
            icon: const Icon(Icons.arrow_forward, size: 18),
            label: const Text('サンプルで試す'),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _ActiveSavedProfileNotice extends StatelessWidget {
  const _ActiveSavedProfileNotice({required this.profile});

  final SavedUserProfile profile;

  @override
  Widget build(BuildContext context) {
    final details = profile.details;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF57D6D1).withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF57D6D1).withValues(alpha: 0.48)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_outline, color: Color(0xFF57D6D1), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '使用中のプロフィール',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  '${profile.name} / ${profile.birthDate}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '出生時間 ${details.effectiveBirthTime} / 出生地 ${details.effectiveBirthPlace}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.64),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SavedProfilePicker extends StatelessWidget {
  const SavedProfilePicker({
    super.key,
    required this.profilesFuture,
    required this.onRefresh,
    required this.onSelected,
    required this.onDeleted,
  });

  final Future<List<SavedUserProfile>> profilesFuture;
  final VoidCallback onRefresh;
  final ValueChanged<SavedUserProfile> onSelected;
  final ValueChanged<SavedUserProfile> onDeleted;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SavedUserProfile>>(
      future: profilesFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: _SavedProfileShell(
              child: Text(
                '保存データを表示できませんでした。',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        }
        final profiles = snapshot.data ?? const <SavedUserProfile>[];
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        if (profiles.isEmpty) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: _SavedProfileShell(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.folder_shared_outlined, color: Color(0xFFF6D77A), size: 20),
                      const SizedBox(width: 10),
                      Text(
                        '保存プロフィール',
                        style: TextStyle(
                          color: const Color(0xFFF6D77A).withValues(alpha: 0.9),
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: onRefresh,
                        icon: const Icon(Icons.refresh, size: 19),
                        tooltip: '一覧を更新',
                        color: Colors.white.withValues(alpha: 0.72),
                        constraints: const BoxConstraints.tightFor(width: 34, height: 34),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isLoading
                        ? '確認中...'
                        : '保存したプロフィールはありません。',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.66),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: _SavedProfileShell(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.folder_shared_outlined, color: Color(0xFFF6D77A), size: 20),
                    const SizedBox(width: 10),
                    Text(
                      '保存プロフィール',
                      style: TextStyle(
                        color: const Color(0xFFF6D77A).withValues(alpha: 0.9),
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    IconButton(
                      onPressed: onRefresh,
                      icon: const Icon(Icons.refresh, size: 19),
                      tooltip: '一覧を更新',
                      color: Colors.white.withValues(alpha: 0.72),
                      constraints: const BoxConstraints.tightFor(width: 34, height: 34),
                      padding: EdgeInsets.zero,
                    ),
                    const Spacer(),
                    Text(
                      '${profiles.length}件',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.56),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: profiles
                      .map(
                        (profile) => _SavedProfileButton(
                          profile: profile,
                          onSelected: onSelected,
                          onDeleted: onDeleted,
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SavedProfileShell extends StatelessWidget {
  const _SavedProfileShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF070A1B).withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF6D77A).withValues(alpha: 0.22)),
      ),
      child: child,
    );
  }
}

class _SavedProfileButton extends StatelessWidget {
  const _SavedProfileButton({
    required this.profile,
    required this.onSelected,
    required this.onDeleted,
  });

  final SavedUserProfile profile;
  final ValueChanged<SavedUserProfile> onSelected;
  final ValueChanged<SavedUserProfile> onDeleted;

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('プロフィールを削除しますか？'),
        content: Text('${profile.name} の保存プロフィールを削除します。鑑定ナビの会話履歴と保存メモも削除されます。占い結果や星データそのものは削除されません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      onDeleted(profile);
    }
  }

  @override
  Widget build(BuildContext context) {
    final details = profile.details;
    final hasBirthInfo = details.hasAny;
    final subtitle = hasBirthInfo
        ? '${profile.birthDate} / ${details.effectiveBirthTime} / ${details.effectiveBirthPlace}'
        : '${profile.birthDate} / 出生地未入力';

    return InkWell(
      onTap: () => onSelected(profile),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        constraints: const BoxConstraints(minWidth: 190, maxWidth: 300),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.person_pin_circle_outlined, size: 22, color: Color(0xFF57D6D1)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.58),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => _confirmDelete(context),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  tooltip: 'プロフィールを削除',
                  color: Colors.white.withValues(alpha: 0.62),
                  constraints: const BoxConstraints.tightFor(width: 34, height: 34),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => onSelected(profile),
                icon: const Icon(Icons.file_open_outlined, size: 16),
                label: const Text('反映'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFF6D77A),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStats extends StatelessWidget {
  const _MiniStats();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        Expanded(
          child: _MiniStat(
            label: '出生図',
            value: 'Natal',
            icon: Icons.blur_circular_outlined,
          ),
        ),
        SizedBox(width: 8),
        Expanded(
          child: _MiniStat(
            label: '今日の星',
            value: 'Transit',
            icon: Icons.timeline_outlined,
          ),
        ),
        SizedBox(width: 8),
        Expanded(
          child: _MiniStat(
            label: '星の解説',
            value: 'Guide',
            icon: Icons.menu_book_outlined,
          ),
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: const Color(0xFFF6D77A)),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.58),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _LandingHeader extends StatelessWidget {
  const _LandingHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF6D77A), Color(0xFFE0B055)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFF6D77A).withValues(alpha: 0.30),
                blurRadius: 22,
              ),
            ],
          ),
          child: const Icon(
            Icons.nights_stay,
            color: Color(0xFF071018),
            size: 30,
          ),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ぱんちょ式 超本格占星術占い',
                style: TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w500,
                  height: 1.0,
                  letterSpacing: 0,
                ),
              ),
              SizedBox(height: 5),
              Text(
                'Astrology Reading',
                style: TextStyle(
                  color: Color(0xFFD8CBAF),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        if (MediaQuery.sizeOf(context).width >= 620)
          OutlinedButton.icon(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('はじめての方へ'),
                content: const Text(
                  '生年月日を選び、ホロスコープを読むと毎日・週・月・年の占いを確認できます。'
                  '出生時間と出生地をプロフィールへ保存すると、ハウスやASCを含む鑑定がより正確になります。\n\n'
                  '占い結果は参考情報です。医療・法律・投資など重要な判断は、必要に応じて専門家へ相談してください。',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('閉じる'),
                  ),
                ],
              ),
            ),
            icon: const Icon(Icons.menu_book_outlined, size: 18),
            label: const Text('はじめての方へ'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.22)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            ),
          ),
      ],
    );
  }
}

class _LandingHero extends StatelessWidget {
  const _LandingHero();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text(
          '今日の星を、あなたの物語として読む。',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 31,
            fontWeight: FontWeight.w500,
            height: 1.35,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 14),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Text(
            '生まれた星と今日の星を重ね、恋愛・仕事・心の流れをやさしく読み解きます。',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.76),
              fontSize: 14,
              height: 1.55,
            ),
          ),
        ),
      ],
    );
  }
}

class _DecoratedSectionTitle extends StatelessWidget {
  const _DecoratedSectionTitle({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const style = TextStyle(
          color: Color(0xFFF6D77A),
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        );
        if (MediaQuery.sizeOf(context).width < 390) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.auto_awesome, size: 16, color: Color(0xFFF6D77A)),
              const SizedBox(width: 8),
              Text(text, textAlign: TextAlign.center, style: style),
            ],
          );
        }
        return Row(
          children: [
            const Expanded(child: Divider(color: Color(0x6657D6D1))),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Icon(Icons.auto_awesome, size: 16, color: Color(0xFFF6D77A)),
            ),
            Text(text, textAlign: TextAlign.center, style: style),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Icon(Icons.auto_awesome, size: 16, color: Color(0xFFF6D77A)),
            ),
            const Expanded(child: Divider(color: Color(0x6657D6D1))),
          ],
        );
      },
    );
  }
}

class _FeatureCards extends StatelessWidget {
  const _FeatureCards();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 760;
        final cards = const [
          _FeatureCard(
            icon: Icons.blur_circular_outlined,
            title: '本格的な占星術',
            body: '西洋占星術のホロスコープであなたの本質を読み解きます。',
          ),
          _FeatureCard(
            icon: Icons.public_outlined,
            title: '最新の天体データ',
            body: '今日の星の動きから運勢の流れをお届けします。',
          ),
          _FeatureCard(
            icon: Icons.auto_awesome,
            title: 'やさしい星の解説',
            body: '難しい専門用語は使わずに、丁寧に言葉へ変えます。',
          ),
        ];

        if (!isWide) {
          return Column(children: cards);
        }

        return Row(
          children: cards
              .map(
                (card) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: card,
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(22),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF8A4DFF).withValues(alpha: 0.55)),
              color: const Color(0xFF8A4DFF).withValues(alpha: 0.10),
            ),
            child: Icon(icon, color: const Color(0xFFF6D77A)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFFF6D77A),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  body,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.70),
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LandingFooter extends StatelessWidget {
  const _LandingFooter();

  @override
  Widget build(BuildContext context) {
    return Text(
      'ぱんちょ式 超本格占星術占い\n© 2026 pancyo Astrology / AGPL-3.0-or-later',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.70),
        height: 1.7,
      ),
    );
  }
}

class _QuietFooter extends StatelessWidget {
  const _QuietFooter();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Icon(
            Icons.blur_on,
            size: 16,
            color: const Color(0xFFF6D77A).withValues(alpha: 0.72),
          ),
          Text(
            'Natal chart / Transit reading',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.58),
              fontSize: 13,
              letterSpacing: 0,
            ),
          ),
          Icon(
            Icons.blur_on,
            size: 16,
            color: const Color(0xFFF6D77A).withValues(alpha: 0.72),
          ),
        ],
      ),
    );
  }
}

class ReadingScreen extends StatefulWidget {
  const ReadingScreen({
    super.key,
    required this.profile,
    required this.initialDetails,
    this.onProfileSaved,
  });

  final AstroProfile profile;
  final UserProfileDetails initialDetails;
  final ValueChanged<SavedUserProfile>? onProfileSaved;

  @override
  State<ReadingScreen> createState() => _ReadingScreenState();
}

class _ReadingScreenState extends State<ReadingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
    Future<void>.delayed(const Duration(seconds: 5), () {
      if (!mounted) return;
      setState(() => _done = true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) {
      return ResultScreen(
        profile: widget.profile,
        initialDetails: widget.initialDetails,
        onProfileSaved: widget.onProfileSaved,
      );
    }

    return StarScaffold(
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = math.min(constraints.maxWidth * 0.78, 340.0);

            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _CosmicReadingStage(
                      animation: _controller,
                      size: size,
                      profile: widget.profile,
                    ),
                    const SizedBox(height: 28),
                    Text(
                      '${widget.profile.name}さんの星図を鑑定中',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                        shadows: [
                          Shadow(
                            color: const Color(0xFF57D6D1).withValues(alpha: 0.28),
                            blurRadius: 18,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    _ReadingSteps(animation: _controller),
                    const SizedBox(height: 16),
                    _ReadingMetricsStrip(animation: _controller),
                    const SizedBox(height: 16),
                    _ReadingStatusPanel(animation: _controller, profile: widget.profile),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CosmicReadingStage extends StatelessWidget {
  const _CosmicReadingStage({
    required this.animation,
    required this.size,
    required this.profile,
  });

  final Animation<double> animation;
  final double size;
  final AstroProfile profile;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final pulse = (math.sin(animation.value * math.pi * 2) + 1) / 2;
        return SizedBox(
          width: size + 86,
          height: size + 86,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                painter: ReadingScanPainter(animation.value),
                size: Size.square(size + 86),
              ),
              Transform.rotate(
                angle: -animation.value * math.pi * 2,
                child: CustomPaint(
                  painter: AstroPulsePainter(animation.value),
                  size: Size.square(size + 58),
                ),
              ),
              Transform.rotate(
                angle: animation.value * math.pi * 2,
                child: CustomPaint(
                  painter: HoroscopePainter(animation.value),
                  size: Size.square(size),
                ),
              ),
              Transform.rotate(
                angle: animation.value * math.pi * 4,
                child: CustomPaint(
                  painter: ReadingConstellationPainter(animation.value),
                  size: Size.square(size * 0.86),
                ),
              ),
              Container(
                width: size * (0.34 + pulse * 0.025),
                height: size * (0.34 + pulse * 0.025),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFFF6D77A).withValues(alpha: 0.50),
                      const Color(0xFF57D6D1).withValues(alpha: 0.18),
                      Colors.transparent,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFF6D77A).withValues(alpha: 0.20 + pulse * 0.16),
                      blurRadius: 30 + pulse * 18,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.auto_awesome, color: Color(0xFFF6D77A), size: 32),
                    const SizedBox(height: 6),
                    Text(
                      profile.theme,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                bottom: 6,
                child: _ReadingPhasePill(animation: animation),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ReadingPhasePill extends StatelessWidget {
  const _ReadingPhasePill({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final phases = ['NATAL', 'TRANSIT', 'ASPECT', 'HOUSE', 'MESSAGE'];
        final index =
            (animation.value * phases.length).floor().clamp(0, phases.length - 1).toInt();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFF070D24).withValues(alpha: 0.74),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFF6D77A).withValues(alpha: 0.34)),
          ),
          child: Text(
            'PHASE ${phases[index]}',
            style: const TextStyle(
              color: Color(0xFFF6D77A),
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        );
      },
    );
  }
}

class _ReadingSteps extends StatelessWidget {
  const _ReadingSteps({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final steps = [
      '出生図の太陽・月・ASCを配置中',
      '現在の月と惑星を重ね合わせ中',
      'アスペクトとハウス通過を解析中',
      'ボイドとリターン補正を確認中',
      '相談テーマに合わせて言葉を整え中',
    ];

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final index =
            (animation.value * steps.length).floor().clamp(0, steps.length - 1).toInt();
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          child: Text(
            steps[index],
            key: ValueKey(index),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      },
    );
  }
}

class _ReadingMetricsStrip extends StatelessWidget {
  const _ReadingMetricsStrip({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final values = [
          _MetricData('出生図', 0.30 + animation.value * 0.70, const Color(0xFFF6D77A)),
          _MetricData('月', 0.18 + ((animation.value + 0.25) % 1.0) * 0.82, const Color(0xFF57D6D1)),
          _MetricData('アスペクト', 0.10 + ((animation.value + 0.50) % 1.0) * 0.90, const Color(0xFFB58CFF)),
        ];

        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Row(
            children: values
                .map(
                  (item) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _ReadingMetric(item: item),
                    ),
                  ),
                )
                .toList(),
          ),
        );
      },
    );
  }
}

class _MetricData {
  const _MetricData(this.label, this.value, this.color);

  final String label;
  final double value;
  final Color color;
}

class _ReadingMetric extends StatelessWidget {
  const _ReadingMetric({required this.item});

  final _MetricData item;

  @override
  Widget build(BuildContext context) {
    final value = item.value.clamp(0.0, 1.0).toDouble();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: item.color.withValues(alpha: 0.22)),
      ),
      child: Column(
        children: [
          Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.66),
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 5,
              color: item.color,
              backgroundColor: Colors.white.withValues(alpha: 0.10),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadingStatusPanel extends StatelessWidget {
  const _ReadingStatusPanel({
    required this.animation,
    required this.profile,
  });

  final Animation<double> animation;
  final AstroProfile profile;

  @override
  Widget build(BuildContext context) {
    final logs = [
      'Natal: ${profile.birthDate} ${profile.birthTime} の出生図を作成',
      'Place: ${profile.birthPlace} のハウス基準を確認',
      'Moon: 感情の波とボイド帯を探索',
      'Venus/Jupiter: 恋愛運と金運の流れを解析',
      'Transit: 現在の星回りと出生図を照合',
      'Message: ${profile.theme}に合わせて鑑定文を生成',
    ];

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final progress = (animation.value * 1.18).clamp(0.0, 1.0);
        final activeCount = (progress * logs.length).ceil().clamp(1, logs.length).toInt();

        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: Colors.white.withValues(alpha: 0.10),
                    color: const Color(0xFF57D6D1),
                  ),
                ),
                const SizedBox(height: 14),
                ...List.generate(logs.length, (index) {
                  final active = index < activeCount;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(
                          active ? Icons.check_circle : Icons.radio_button_unchecked,
                          size: 18,
                          color: active
                              ? const Color(0xFFF6D77A)
                              : Colors.white.withValues(alpha: 0.34),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            logs[index],
                            style: TextStyle(
                              color: active
                                  ? Colors.white.withValues(alpha: 0.88)
                                  : Colors.white.withValues(alpha: 0.42),
                              fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }
}

class ResultScreen extends StatefulWidget {
  const ResultScreen({
    super.key,
    required this.profile,
    required this.initialDetails,
    this.onProfileSaved,
  });

  final AstroProfile profile;
  final UserProfileDetails initialDetails;
  final ValueChanged<SavedUserProfile>? onProfileSaved;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  int _tabIndex = 0;
  bool _switchingTab = false;
  final Set<int> _visitedTabs = {0};
  ReadingDepth _readingDepth = ReadingDepth.simple;
  UserProfileDetails _details = const UserProfileDetails.empty();
  HoroscopeReadingContext? _customContext;
  String? _customContextKey;
  String _chatDraft = '';

  @override
  void initState() {
    super.initState();
    HouseSystemSettings.current.addListener(_onHouseSystemChanged);
    _details = widget.initialDetails;
  }

  @override
  void dispose() {
    HouseSystemSettings.current.removeListener(_onHouseSystemChanged);
    super.dispose();
  }

  void _onHouseSystemChanged() {
    _customContext = null;
    _customContextKey = null;
    if (mounted) setState(() {});
  }

  HoroscopeReadingContext _customContextFor(AstroProfile profile) {
    final now = DateTime.now();
    final key = '${profile.name}|${profile.birthDate}|${profile.birthTime}|${profile.birthPlace}|${HouseSystemSettings.current.value.name}|${now.year}-${now.month}-${now.day}';
    if (_customContext == null || _customContextKey != key) {
      _customContext = const AstrologyEngine().buildPreviewContext(profile: profile, date: now);
      _customContextKey = key;
    }
    return _customContext!;
  }

  void _openChatWithQuestion(String question) {
    setState(() {
      _chatDraft = question;
      _tabIndex = 3;
      _visitedTabs.add(3);
    });
  }

  void _selectTab(int value) {
    if (_switchingTab || value == _tabIndex) return;
    setState(() {
      _switchingTab = true;
      _tabIndex = value;
      _visitedTabs.add(value);
    });
    Future<void>.delayed(const Duration(milliseconds: 160), () {
      if (mounted) setState(() => _switchingTab = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final effectiveProfile = widget.profile.copyWith(
      birthTime: _details.effectiveBirthTime,
      birthPlace: _details.effectiveBirthPlace,
    );
    final tabs = [
      _TabItem(
        '毎日の占い',
        Icons.today_outlined,
        DailyReading(profile: effectiveProfile, details: _details, depth: _readingDepth),
        compactLabel: '毎日',
      ),
      _TabItem(
        '週月年占い',
        Icons.calendar_month_outlined,
        LongRangeReading(profile: effectiveProfile, details: _details, depth: _readingDepth),
        compactLabel: '週月年',
      ),
      _TabItem(
        '星の解説',
        Icons.public_outlined,
        LearningReading(
          profile: effectiveProfile,
          details: _details,
          depth: _readingDepth,
          onAskInChat: _openChatWithQuestion,
        ),
      compactLabel: '星',
      ),
      _TabItem(
        '鑑定ナビ',
        Icons.chat_bubble_outline,
        _visitedTabs.contains(3)
            ? CustomReading(
                profile: effectiveProfile,
                details: _details,
                contextData: _customContextFor(effectiveProfile),
                initialQuestion: _chatDraft,
                onInitialQuestionConsumed: () {
                  if (_chatDraft.isNotEmpty && mounted) setState(() => _chatDraft = '');
                },
              )
            : const SizedBox.shrink(),
        compactLabel: '鑑定',
      ),
      _TabItem(
        'プロフィール',
        Icons.person_outline,
        ProfileView(
          profile: effectiveProfile,
          details: _details,
          onSaved: (saved) {
            setState(() => _details = saved.details);
            widget.onProfileSaved?.call(saved);
          },
        ),
        compactLabel: 'プロフ',
      ),
    ];

    return StarScaffold(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('ぱんちょ式星占い'),
          actions: [
            IconButton(
              tooltip: '最初に戻る',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 760;
              final screenHeight = MediaQuery.sizeOf(context).height;
              // 一部端末ではScaffoldのresize後にviewInsetsが0になるため、
              // キーボードで大きく縮んだ場合だけ利用可能高も見る。AppBar分の高さで
              // 誤判定すると、通常時に下部タブまで隠れてしまう。
              final keyboardOpen = !isWide &&
                  (MediaQuery.viewInsetsOf(context).bottom > 0 ||
                      constraints.maxHeight < screenHeight * 0.72);
              final showReadingDepth = _tabIndex <= 2;
              // 一度開いたタブはツリー上に残し、日別・期間別の計算キャッシュと
              // スクロール位置を保つ。未訪問タブは空のままなので初回表示を重くしない。
              final content = IndexedStack(
                index: _tabIndex,
                children: List.generate(
                  tabs.length,
                  (index) => KeyedSubtree(
                    key: ValueKey('tab-$index'),
                    child: _visitedTabs.contains(index)
                        ? tabs[index].view
                        : const SizedBox.shrink(),
                  ),
                ),
              );
              final contentWithMode = Column(
                children: [
                  if (!keyboardOpen && showReadingDepth)
                    ReadingDepthSwitcher(
                      depth: _readingDepth,
                      onChanged: (value) => setState(() => _readingDepth = value),
                    ),
                  Expanded(child: content),
                ],
              );

              if (isWide) {
                return Row(
                  children: [
                    NavigationRail(
                      backgroundColor: Colors.black.withValues(alpha: 0.18),
                      selectedIndex: _tabIndex,
                      onDestinationSelected: _switchingTab ? null : _selectTab,
                      labelType: NavigationRailLabelType.all,
                      destinations: tabs
                          .map(
                            (tab) => NavigationRailDestination(
                              icon: Icon(tab.icon),
                              selectedIcon: Icon(tab.icon, color: const Color(0xFF57D6D1)),
                              label: Text(tab.label),
                            ),
                          )
                          .toList(),
                    ),
                    Expanded(child: contentWithMode),
                  ],
                );
              }

              return Column(
                children: [
                  Visibility(
                    visible: !keyboardOpen && showReadingDepth,
                    maintainState: true,
                    maintainAnimation: true,
                    child: ReadingDepthSwitcher(
                      depth: _readingDepth,
                      onChanged: (value) => setState(() => _readingDepth = value),
                    ),
                  ),
                  Expanded(child: content),
                  Visibility(
                    visible: !keyboardOpen,
                    maintainState: true,
                    maintainAnimation: true,
                    child: NavigationBarTheme(
                      data: NavigationBarThemeData(
                        height: 82,
                        backgroundColor: const Color(0xFF0D1020),
                        indicatorColor: const Color(0xFF57D6D1).withValues(alpha: 0.30),
                        labelTextStyle: WidgetStateProperty.resolveWith(
                          (states) => TextStyle(
                            color: states.contains(WidgetState.selected)
                                ? const Color(0xFFB8FFF5)
                                : Colors.white.withValues(alpha: 0.72),
                            fontWeight: states.contains(WidgetState.selected)
                                ? FontWeight.w900
                                : FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                        iconTheme: WidgetStateProperty.resolveWith(
                          (states) => IconThemeData(
                            color: states.contains(WidgetState.selected)
                                ? const Color(0xFFB8FFF5)
                                : Colors.white.withValues(alpha: 0.72),
                            size: states.contains(WidgetState.selected) ? 26 : 24,
                          ),
                        ),
                      ),
                      child: NavigationBar(
                        selectedIndex: _tabIndex,
                        onDestinationSelected: _switchingTab ? null : _selectTab,
                        destinations: tabs
                            .map(
                              (tab) => NavigationDestination(
                                icon: Icon(tab.icon),
                                // 360dp級だけ短縮名にし、一般的なスマホでは
                                // 以前からの正式なタブ名を表示する。
                                label: MediaQuery.sizeOf(context).width < 390
                                    ? tab.compactLabel ?? tab.label
                                    : tab.label,
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

String moonSignActionHint(HoroscopeReadingContext contextData, {required bool mental}) {
  PlanetPlacement? moon;
  for (final placement in contextData.transit.placements) {
    if (placement.planet == AstroPlanet.moon) {
      moon = placement;
      break;
    }
  }
  if (moon == null) return '';
  final message = switch (moon.sign) {
    ZodiacSign.aries || ZodiacSign.leo || ZodiacSign.sagittarius => mental
        ? '月が${moon.sign.label}なので、気持ちは動きやすい日。勢いが出すぎたら短い休憩で整えましょう。'
        : '月が${moon.sign.label}なので、迷うよりまず小さく着手すると流れに乗りやすい日です。',
    ZodiacSign.taurus || ZodiacSign.virgo || ZodiacSign.capricorn => mental
        ? '月が${moon.sign.label}なので、生活リズムを整えるほど気持ちが安定しやすい日です。'
        : '月が${moon.sign.label}なので、予定・持ち物・お金を一つ整える行動が向いています。',
    ZodiacSign.gemini || ZodiacSign.libra || ZodiacSign.aquarius => mental
        ? '月が${moon.sign.label}なので、考えが散りやすい時は人に話すか、メモに出すと落ち着きます。'
        : '月が${moon.sign.label}なので、連絡・相談・情報整理を軽く進めると良い日です。',
    ZodiacSign.cancer || ZodiacSign.scorpio || ZodiacSign.pisces => mental
        ? '月が${moon.sign.label}なので、気分が深まりやすい日。落ち込みを感じたら一人で抱えず、休息と安心できる時間を優先しましょう。'
        : '月が${moon.sign.label}なので、無理に急がず、気持ちが落ち着く環境を整えてから動くと良い日です。',
  };
  return message;
}

String moonSignTimeActionHint(ZodiacSign sign) => switch (sign) {
  ZodiacSign.aries => 'まず一件だけ着手', ZodiacSign.taurus => '予定と持ち物を整える',
  ZodiacSign.gemini => '連絡と情報を軽く整理', ZodiacSign.cancer => '安心できる場所から進める',
  ZodiacSign.leo => '見せたいことを一つ形にする', ZodiacSign.virgo => '細部を整えてから送る',
  ZodiacSign.libra => '相談して選択肢を比べる', ZodiacSign.scorpio => '一つに集中して掘り下げる',
  ZodiacSign.sagittarius => '学びや外向きの一歩を出す', ZodiacSign.capricorn => '優先順位と期限を決める',
  ZodiacSign.aquarius => '新しい方法を小さく試す', ZodiacSign.pisces => '休息と気持ちの整理を優先',
};

class OverallScoreMethodNotice extends StatelessWidget {
  const OverallScoreMethodNotice({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, right: 4, bottom: 8),
        child: Text(
          text,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.64),
            fontSize: 12,
            height: 1.4,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

class OverallFortuneCard extends StatelessWidget {
  const OverallFortuneCard({
    super.key,
    required this.detailed,
    required this.contextData,
    this.date,
    this.onShare,
  });

  final bool detailed;
  final HoroscopeReadingContext contextData;
  final DateTime? date;
  final VoidCallback? onShare;

  int get score {
    return FortuneScoreCalculator.dailyOverall(contextData);
  }

  String get areaSummary {
    final areas = <({String label, int score})>[
      (label: '恋愛運', score: FortuneScoreCalculator.dailyAreaBreakdown(contextData, FortuneArea.love, 70).score),
      (label: '仕事運', score: FortuneScoreCalculator.dailyAreaBreakdown(contextData, FortuneArea.work, 74).score),
      (label: '金運', score: FortuneScoreCalculator.dailyAreaBreakdown(contextData, FortuneArea.money, 68).score),
      (label: '健康・メンタル運', score: FortuneScoreCalculator.dailyAreaBreakdown(contextData, FortuneArea.mental, 72).score),
    ];
    final favorable = areas.where((area) => area.score >= 80).map((area) => area.label).toList();
    final caution = areas.where((area) => area.score <= 65).map((area) => area.label).toList();
    final favorableText = favorable.isEmpty ? '大きな偏りなし' : favorable.join('・');
    final cautionText = caution.isEmpty ? '大きな偏りなし' : caution.join('・');
    return '好調：$favorableText　注意：$cautionText';
  }

  String get body {
    final voidMoon = contextData.transit.voidMoon;
    final aspect = contextData.aspects.isEmpty ? null : contextData.aspects.first;
    final returnEvent = contextData.returns.isEmpty ? null : contextData.returns.first;
    final overallReturnBonus = FortuneScoreCalculator.overallReturnBonus(contextData);
    final transit = contextData.houseTransits.isEmpty ? null : contextData.houseTransits.first;
    final stationHint = _stationReadingHint(date, contextData);
    final effectiveRetrogrades = <AstroPlanet>{
      ...contextData.retrogradePlanets,
      if (date != null) ...DailyAstroEventsCard.verifiedRetrogradesAt(date!),
    };
    final lunarPhaseHint = _lunarPhaseReadingHint(date, contextData);
    final majorIngressHint = _majorIngressReadingHint(date);
    final transitStelliums = _transitStelliumLabels(contextData);

    if (!detailed) {
      final mood = _scoreMood(score);
      final parts = <String>[mood];
      parts.add(moonSignActionHint(contextData, mental: false));
      if (aspect != null) {
        parts.add(_simpleAspectMessage(aspect));
      } else if (transit != null) {
        parts.add('今は${_simpleHouseScene(transit.natalHouse)}に意識が向きやすい流れです。その場面を一つ整えると、気持ちと予定がかみ合いやすくなります');
      } else {
        parts.add('大きく動かすより、普段の調整を丁寧にすると運が整います');
      }
      if (voidMoon != null) {
        parts.add('ただし気持ちや予定が定まりにくい${_simpleVoidTimeRange(voidMoon)}は、無理に進めず確認と休憩に回すと安定します');
      }
      if (stationHint != null) {
        parts.add(stationHint);
      }
      if (lunarPhaseHint != null) {
        parts.add(lunarPhaseHint);
      }
      if (majorIngressHint != null) {
        parts.add(majorIngressHint);
      }
      if (returnEvent != null) {
        parts.add('過去のやり方を見直して次の段階へ進む節目も重なるため、続けたいことを一つ選び直すと動きやすくなります');
      } else if (effectiveRetrogrades.isNotEmpty) {
        parts.add('${effectiveRetrogrades.map((planet) => planet.label).join('・')}が逆行中です。連絡や予定は一度見直してから確定すると安心です');
      }
      if (transitStelliums.isNotEmpty) {
        parts.add('空の${transitStelliums.join('・')}に星が集中するため、そのテーマを一つに絞ると力を使いやすくなります');
      }
      final grandTrines = FortuneScoreCalculator.transitGrandTrineLabels(contextData);
      if (grandTrines.isNotEmpty) {
        parts.add('グランドトラインができるため、得意なやり方を一つ具体的な行動へつなげると流れに乗りやすくなります');
      }
      if (score >= 78) {
        parts.add('今日は朝のうちに一番進めたいことへ着手し、午後は反応を見て仕上げに回すのがおすすめです');
      } else if (score >= 66) {
        parts.add('今日は予定を二つまでに絞り、そのうち一つを確実に終えることを最優先にしましょう');
      } else {
        parts.add('今日は大きな結論を急がず、確認できる材料を一つ増やしてから次へ進むと安定します');
      }
      return '${parts
          .map((part) => part.trim().replaceFirst(RegExp(r'[。．]+$'), ''))
          .where((part) => part.isNotEmpty)
          .join('。')}。';
    }

    final parts = <String>[];
    parts.add('${_scoreMood(score)}。今日は星の配置を材料に、動く場面と整える場面を分けて使うと流れを活かしやすくなります。');
    parts.add(moonSignActionHint(contextData, mental: false));
    if (aspect != null) {
      parts.add('指定日の主な流れは、現在の${aspect.transitPlanet.label}が出生図の${aspect.natalPlanet.label}へ${aspect.type.label}を作る配置です。${aspect.meaning}。');
    }
    if (transit != null) {
      parts.add('また、${transit.planet.label}が出生図の第${transit.natalHouse}ハウスを通過しているため、${transit.meaning}。');
    }
    if (returnEvent != null) {
      parts.add('${returnEvent.planet.label}リターンの影響もあり、${returnEvent.meaning}。');
    }
    if (voidMoon != null) {
      parts.add('月ボイドは${voidMoon.label}。この時間帯は新しい決断より、見直し、休憩、準備に回すと総合運が崩れにくくなります。');
    }
    if (stationHint != null) {
      parts.add('$stationHint。');
    }
    if (lunarPhaseHint != null) {
      parts.add('$lunarPhaseHint。');
    }
    if (majorIngressHint != null) {
      parts.add('$majorIngressHint。');
    }
    final retrograde = effectiveRetrogrades.map((planet) => planet.label).toList();
    if (retrograde.isNotEmpty) {
      parts.add('${retrograde.join('・')}が逆行中です。連絡、契約、買い物、予定は一度見返してから確定すると、余計なやり直しを減らせます。');
    }
    final grandTrines = FortuneScoreCalculator.transitGrandTrineLabels(contextData);
    if (grandTrines.isNotEmpty) {
      parts.add('現在は${grandTrines.map((label) => 'グランドトライン（$label）').join('、')}が成立しています。得意な方法を一つ決め、具体的な行動へつなげると力を活かしやすい日です。');
    }
    if (transitStelliums.isNotEmpty) {
      parts.add('現在は空の${transitStelliums.join('、')}にステリウムができています。関係するテーマを一つに絞り、優先順位を散らさないほど力を活かしやすい日です。');
    }
    if (contextData.natal.stelliums.isNotEmpty) {
      final stelliums = contextData.natal.stelliums
          .map((item) => '出生図の第${item.house}ハウスの星の集中')
          .join('、');
      parts.add('$stelliumsも日々の判断の土台です。星が集まるテーマは、あれこれ広げず一点を深めるほど持ち味になりやすいでしょう。');
    }
    if (score >= 78) {
      parts.add('朝のうちに最優先を一つ始め、午後は反応を見て仕上げへ回すのがおすすめです。');
    } else if (score >= 66) {
      parts.add('今日は予定を二つまでに絞り、途中で一度だけ確認時間を取ると安定します。');
    } else {
      parts.add('急いで結論を出さず、確認できる材料を一つ増やしてから次の判断へ進みましょう。');
    }
    if (parts.isEmpty) {
      parts.add('この日は強い補正が少なめなので、派手に動くより生活リズムと小さな確認を整えるほど運が安定します。');
    }
    return parts.join(' ');
  }

  String _scoreMood(int value) {
    if (value >= 88) return 'かなり良い流れの日です';
    if (value >= 78) return '良い運気の日です';
    if (value >= 68) return '安定寄りの日です';
    if (value >= 58) return '慎重に整える日です';
    return '無理せず守りを固めたい日です';
  }

  String _simpleAspectMessage(TransitAspect aspect) {
    return switch (aspect.type) {
      AspectType.conjunction => '今は気持ちと行動が同じテーマへ集まりやすい日です。優先順位を一つに絞ると力を使いやすくなります',
      AspectType.sextile => '今は小さな働きかけがきっかけになりやすい日です。連絡、準備、提案のどれかを一つ動かすと流れが開きます',
      AspectType.trine => '今は得意なやり方をそのまま使いやすい日です。無理に背伸びせず、続けやすい方法を選ぶと手応えにつながります',
      AspectType.square => '今は急ぎたい気持ちと現実の間にズレが出やすい日です。予定や言葉を一段軽くして調整すると崩れにくくなります',
      AspectType.opposition => '今は相手や外側の予定に振られやすい日です。一方だけで決めず、条件を並べてから折り合いをつけると安定します',
    };
  }

  String _simpleHouseScene(int house) {
    return switch (house) {
      1 => '自分の見せ方や始め方', 2 => 'お金や大切にしたいもの',
      3 => '連絡、学び、身近な用事', 4 => '家や安心できる場所',
      5 => '恋愛、創作、楽しみ', 6 => '日々の仕事、体調、習慣',
      7 => '人との約束や関係', 8 => '深い関係や共有すること',
      9 => '学びや視野を広げること', 10 => '仕事や評価',
      11 => '仲間やこれからの計画', 12 => '休息や心の整理',
      _ => '日常の優先順位',
    };
  }

  String _simpleVoidTimeRange(VoidMoonPeriod period) {
    String time(DateTime value) => '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
    if (period.startTime.year == period.endTime.year &&
        period.startTime.month == period.endTime.month &&
        period.startTime.day == period.endTime.day) {
      return '${time(period.startTime)}〜${time(period.endTime)}';
    }
    return '${period.startTime.month}/${period.startTime.day} ${time(period.startTime)}〜${period.endTime.month}/${period.endTime.day} ${time(period.endTime)}';
  }

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 92,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF6D77A).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFF6D77A).withValues(alpha: 0.28)),
            ),
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FortuneNumber(score: score),
                const SizedBox(height: 5),
                const Text(
                  '点',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('総合運', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                          Text(
                            date == null
                                ? 'ぱんちょ式星占い'
                                : 'ぱんちょ式星占い / ${date!.year}/${date!.month}/${date!.day}',
                            style: const TextStyle(fontSize: 10, color: Color(0xFF57D6D1), fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                    if (onShare != null)
                      IconButton(
                        tooltip: 'この結果を画像で共有',
                        onPressed: onShare,
                        icon: const Icon(Icons.ios_share_outlined, size: 20),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(body),
                const SizedBox(height: 10),
                Text(
                  areaSummary,
                  style: const TextStyle(color: Color(0xFFF6D77A), fontSize: 12, fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showFortuneShareComposer(
  BuildContext context, {
  required String periodLabel,
  required int score,
  required String body,
  String metricLabel = '総合運',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF11172F),
    builder: (_) => FortuneShareComposerSheet(
      periodLabel: periodLabel,
      score: score,
      body: body,
      metricLabel: metricLabel,
    ),
  );
}

class FortuneShareComposerSheet extends StatefulWidget {
  const FortuneShareComposerSheet({
    super.key,
    required this.periodLabel,
    required this.score,
    required this.body,
    required this.metricLabel,
  });

  final String periodLabel;
  final int score;
  final String body;
  final String metricLabel;

  @override
  State<FortuneShareComposerSheet> createState() => _FortuneShareComposerSheetState();
}

class _FortuneShareComposerSheetState extends State<FortuneShareComposerSheet> {
  static const _shareCompatibilityChannel = MethodChannel('com.pancyo.aiastrology/share_compat');
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
      final directory = Directory('${documents.path}${Platform.pathSeparator}share_wallpapers');
      if (!await directory.exists()) await directory.create(recursive: true);
      final extension = selected.path.toLowerCase().endsWith('.png') ? '.png' : '.jpg';
      final target = File('${directory.path}${Platform.pathSeparator}custom_wallpaper$extension');
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
          const SnackBar(content: Text('壁紙を読み込めませんでした。別の画像でお試しください。')),
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
      await prefs.setString(_displayNameKey, _displayNameController.text.trim());
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
        await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
        shareFile = XFile(file.path, mimeType: 'image/png');
      } catch (error, stackTrace) {
        debugPrint('Share image generation failed: $error\n$stackTrace');
        if (mounted) setState(() => _shareError = '共有画像を作成できませんでした。もう一度お試しください。');
        return;
      }
      try {
        // Androidは結果待ちをしない共有起動にして、singleTaskの共有先を
        // このアプリの画面スタックへ積まない。iOSなどはshare_plusを使う。
        var openedByCompatibilityShare = false;
        if (Platform.isAndroid) {
          try {
            openedByCompatibilityShare = await _shareCompatibilityChannel.invokeMethod<bool>(
                  'shareImage',
                  {'path': shareFile.path, 'mimeType': 'image/png'},
                ) ??
                false;
          } on PlatformException catch (error, stackTrace) {
            debugPrint('Compatibility share launch failed: $error\n$stackTrace');
          }
        }
        if (!openedByCompatibilityShare) {
          // 画像と文章の同時共有を受け取れないSNSがあるため、PNGだけを渡す。
          await Share.shareXFiles([shareFile]);
        }
      } catch (error, stackTrace) {
        debugPrint('Share sheet launch failed: $error\n$stackTrace');
        if (mounted) setState(() => _shareError = '共有機能を開けませんでした。アプリを更新してもう一度お試しください。');
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
              const Text('共有カードを整える', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text('数値と説明はそのままに、見せ方だけを自分用にできます。', style: TextStyle(color: Colors.white.withValues(alpha: 0.64), fontSize: 12)),
              const SizedBox(height: 14),
              RepaintBoundary(
                key: _previewKey,
                child: FortuneShareImageCard(
                  periodLabel: widget.periodLabel,
                  score: widget.score,
                  body: widget.body,
                  metricLabel: widget.metricLabel,
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
                decoration: const InputDecoration(labelText: '表示名（任意）', counterText: ''),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _noteController,
                maxLength: 42,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'ひとこと（任意）', counterText: ''),
              ),
              const SizedBox(height: 6),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('点数を表示'),
                value: _showScore,
                onChanged: (value) => setState(() => _showScore = value),
              ),
              const SizedBox(height: 6),
              const Text('カードのテーマ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: FortuneShareTheme.values
                    .where((theme) => theme != FortuneShareTheme.custom)
                    .map((theme) => ShareWallpaperOption(
                          theme: theme,
                          selected: _theme == theme,
                          onTap: () => setState(() => _theme = theme),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 8),
              Row(children: [
                OutlinedButton.icon(
                  onPressed: _pickCustomWallpaper,
                  icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                  label: Text(_theme == FortuneShareTheme.custom ? '壁紙を変更' : '壁紙を選ぶ'),
                ),
                if (_customWallpaperPath.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  _CustomWallpaperThumbnail(path: _customWallpaperPath),
                ],
                if (_customWallpaperPath.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'カスタム壁紙を削除',
                    onPressed: _clearCustomWallpaper,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ]),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('鑑定文を表示'),
                value: _showBody,
                onChanged: (value) => setState(() => _showBody = value),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _sharing ? null : _share,
                  icon: _sharing
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.ios_share_outlined),
                  label: Text(_sharing ? '画像を作成中…' : 'この画像を共有'),
                ),
              ),
              if (_shareError.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  _shareError,
                  style: const TextStyle(color: Color(0xFFFFB4AB), fontSize: 12, fontWeight: FontWeight.w700),
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
    required this.displayName,
    required this.note,
    required this.showScore,
    required this.showBody,
    required this.theme,
    required this.customWallpaperPath,
  });

  final String periodLabel;
  final int score;
  final String body;
  final String metricLabel;
  final String displayName;
  final String note;
  final bool showScore;
  final bool showBody;
  final FortuneShareTheme theme;
  final String customWallpaperPath;

  @override
  Widget build(BuildContext context) {
    final palette = theme.palette;
    final previewBody = body.length > 260 ? '${body.substring(0, 260)}…' : body;
    final imageProvider = theme.imageProvider(customWallpaperPath);
    final hasWallpaper = imageProvider != null;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.accent.withValues(alpha: 0.55)),
        image: imageProvider == null
            ? null
            : DecorationImage(
                image: imageProvider,
                fit: BoxFit.cover,
              ),
      ),
      child: Padding(
        padding: EdgeInsets.all(hasWallpaper ? 12 : 18),
        child: Padding(
          padding: EdgeInsets.all(hasWallpaper ? 14 : 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('ぱんちょ式星占い', style: TextStyle(color: palette.accent, fontSize: 12, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(periodLabel, style: TextStyle(color: palette.text, fontSize: 16, fontWeight: FontWeight.w900)),
          if (displayName.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(displayName, style: TextStyle(color: palette.score, fontSize: 12, fontWeight: FontWeight.w800)),
          ],
          if (showScore) ...[
            const SizedBox(height: 14),
            Row(children: [
              Text('$score', style: TextStyle(fontSize: 42, fontWeight: FontWeight.w900, color: palette.score)),
              const SizedBox(width: 5),
              Text('点', style: TextStyle(color: palette.text, fontSize: 14, fontWeight: FontWeight.w900)),
              const SizedBox(width: 12),
              Text(metricLabel, style: TextStyle(color: palette.text, fontSize: 16, fontWeight: FontWeight.w900)),
            ]),
          ],
          if (showBody) ...[
            const SizedBox(height: 12),
            Text(previewBody, style: TextStyle(color: palette.text, fontSize: 13, height: 1.55, fontWeight: FontWeight.w600)),
          ],
          if (note.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: palette.noteBackground, borderRadius: BorderRadius.circular(6)),
              child: Text(note, style: TextStyle(color: palette.text, fontSize: 12, fontWeight: FontWeight.w800)),
            ),
          ],
          ]),
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
      label: '${theme.label}の壁紙',
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
              color: selected ? const Color(0xFF57D6D1) : Colors.white.withValues(alpha: 0.22),
              width: selected ? 2 : 1,
            ),
            image: image == null
                ? null
                : DecorationImage(
                    image: image,
                    fit: BoxFit.cover,
                  ),
          ),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              decoration: BoxDecoration(
                color: (image == null ? palette.background : palette.surface).withValues(alpha: image == null ? 0.92 : 0.82),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(7)),
              ),
              child: Text(
                theme.label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: image == null && theme == FortuneShareTheme.bright ? palette.text : Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
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
  custom('カスタム');

  const FortuneShareTheme(this.label);
  final String label;

  FortuneSharePalette get palette => switch (this) {
    FortuneShareTheme.night => const FortuneSharePalette(Color(0xFF121936), Color(0xFF57D6D1), Color(0xFFF6D77A), Color(0xFFE9EEFF), Color(0x18FFFFFF), Color(0xFF11172F)),
    FortuneShareTheme.bright => const FortuneSharePalette(Color(0xFFF5F8FF), Color(0xFF147B85), Color(0xFFB56A00), Color(0xFF17203B), Color(0x1817203B), Color(0xFFF5F8FF)),
    FortuneShareTheme.report => const FortuneSharePalette(Color(0xFF10231F), Color(0xFF91D5B4), Color(0xFFFFD480), Color(0xFFF2FFF7), Color(0x1FFFFFFF), Color(0xFF10231F)),
    FortuneShareTheme.catMoon => const FortuneSharePalette(Color(0xFF10264A), Color(0xFFFFD77B), Color(0xFFFFD77B), Color(0xFFF7F4E8), Color(0x24FFFFFF), Color(0xFF10264A)),
    FortuneShareTheme.catBook => const FortuneSharePalette(Color(0xFF1A294B), Color(0xFFFFD89A), Color(0xFFFFD89A), Color(0xFFFFF6E8), Color(0x24FFFFFF), Color(0xFF14203B)),
    FortuneShareTheme.custom => const FortuneSharePalette(Color(0xFF121936), Color(0xFF57D6D1), Color(0xFFF6D77A), Color(0xFFE9EEFF), Color(0x18FFFFFF), Color(0xFF11172F)),
  };

  ImageProvider? imageProvider(String customWallpaperPath) => switch (this) {
    FortuneShareTheme.night => const AssetImage('assets/images/astro_lake_hero.png'),
    FortuneShareTheme.catMoon => const AssetImage('assets/images/share_cat_moon.png'),
    FortuneShareTheme.catBook => const AssetImage('assets/images/share_cat_book.png'),
    FortuneShareTheme.custom when customWallpaperPath.trim().isNotEmpty && File(customWallpaperPath).existsSync() => FileImage(File(customWallpaperPath)),
    _ => null,
  };
}

class FortuneSharePalette {
  const FortuneSharePalette(this.background, this.accent, this.score, this.text, this.noteBackground, this.surface);
  final Color background;
  final Color accent;
  final Color score;
  final Color text;
  final Color noteBackground;
  final Color surface;
}

enum ReadingDepth {
  simple('簡易', '初心者向けにやさしく読む'),
  detailed('本格', '時期と流れまで詳しく占う');

  const ReadingDepth(this.label, this.description);

  final String label;
  final String description;
}

class ReadingDepthSwitcher extends StatelessWidget {
  const ReadingDepthSwitcher({
    super.key,
    required this.depth,
    required this.onChanged,
  });

  final ReadingDepth depth;
  final ValueChanged<ReadingDepth> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = MediaQuery.sizeOf(context).width < 390;
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF080B18).withValues(alpha: 0.86),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: Row(
            mainAxisAlignment: compact ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              if (!compact) ...[
                Icon(
                  depth == ReadingDepth.detailed
                      ? Icons.auto_awesome_motion
                      : Icons.short_text,
                  color: const Color(0xFFF6D77A),
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    depth.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.68),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              SegmentedButton<ReadingDepth>(
                showSelectedIcon: false,
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  textStyle: WidgetStateProperty.all(
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                  ),
                ),
                segments: ReadingDepth.values
                    .map(
                      (value) => ButtonSegment<ReadingDepth>(
                        value: value,
                        label: Text(value.label),
                      ),
                    )
                    .toList(),
                selected: {depth},
                onSelectionChanged: (value) => onChanged(value.first),
              ),
            ],
          ),
        );
      },
    );
  }
}

class TodayAstroDataPanel extends StatelessWidget {
  const TodayAstroDataPanel({super.key, required this.contextData});

  final HoroscopeReadingContext contextData;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      margin: const EdgeInsets.only(top: 14, bottom: 14),
      padding: const EdgeInsets.all(18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 680;
          final aspectList = contextData.aspects.map(_aspectLine).toList();
          final pairAspectList = contextData.transitPairAspects.map(_pairAspectLine).toList();
          final grandTrines = FortuneScoreCalculator.transitGrandTrineLabels(contextData);

          final aspects = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _showAllAspects(context),
                  icon: const Icon(Icons.table_view_outlined),
                  label: const Text('全アスペクト表を開く'),
                ),
              ),
              const SizedBox(height: 16),
              if (contextData.retrogradePlanets.isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6D77A).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFF6D77A).withValues(alpha: 0.48)),
                  ),
                  child: Text(
                    '${contextData.retrogradePlanets.map((planet) => planet.label).join('・')}逆行中。連絡、判断、予定は急いで確定せず、見直しと再確認を優先します。',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.82),
                      height: 1.45,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              Row(
                children: [
                  const Expanded(
                    child: _SmallSectionLabel(
                      icon: Icons.hub_outlined,
                      text: 'この日の主要アスペクト',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (aspectList.isEmpty)
                Text(
                  'この日は主要アスペクトの影響が弱めです。大きく動かすより、普段の調整を丁寧にすると流れが整います。',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.66),
                    height: 1.45,
                    fontWeight: FontWeight.w700,
                  ),
                )
              else
                ...aspectList,
              if (pairAspectList.isNotEmpty) ...[
                const SizedBox(height: 16),
                const _SmallSectionLabel(
                  icon: Icons.auto_awesome_outlined,
                  text: '空の星同士の流れ',
                ),
                const SizedBox(height: 10),
                ...pairAspectList,
              ],
              if (grandTrines.isNotEmpty) ...[
                const SizedBox(height: 16),
                const _SmallSectionLabel(
                  icon: Icons.change_history_outlined,
                  text: 'グランドトライン',
                ),
                const SizedBox(height: 8),
                ...grandTrines.map(
                  (label) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '$label: 3つの星の調和が強まりやすい時間帯。得意なことを一つ形にします。',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.72), height: 1.4),
                    ),
                  ),
                ),
              ],
              if (contextData.transit.placements.isNotEmpty) ...[
                const SizedBox(height: 16),
                const _SmallSectionLabel(
                  icon: Icons.public_outlined,
                  text: '今日の星の配置',
                ),
                const SizedBox(height: 8),
                ...contextData.transit.placements.take(8).map(
                  (placement) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '${placement.planet.label}：${placement.sign.label} ${placement.degree.toStringAsFixed(1)}° / ${_planetGuidance(placement.planet)}',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.72), height: 1.4),
                    ),
                  ),
                ),
              ],
              if (contextData.returns.isNotEmpty) ...[
                const SizedBox(height: 16),
                const _SmallSectionLabel(
                  icon: Icons.restart_alt,
                  text: '今日のリターン',
                ),
                const SizedBox(height: 8),
                ...contextData.returns.map(
                  (event) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '${event.label} / 第${event.natalHouse}ハウス / ${event.area.label}',
                      style: TextStyle(color: const Color(0xFFF6D77A).withValues(alpha: 0.84), height: 1.4),
                    ),
                  ),
                ),
              ],
            ],
          );

          if (!isWide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                aspects,
              ],
            );
          }

          return aspects;
        },
      ),
    );
  }

  String _planetGuidance(AstroPlanet planet) => switch (planet) {
        AstroPlanet.sun => '意志と行動の軸',
        AstroPlanet.moon => '気分と休息の整え方',
        AstroPlanet.mercury => '連絡・考え方・予定',
        AstroPlanet.venus => '対人・楽しみ・お金の感覚',
        AstroPlanet.mars => '行動力とエネルギー配分',
        AstroPlanet.jupiter => '広げることとチャンス',
        AstroPlanet.saturn => '責任・継続・見直し',
        AstroPlanet.uranus => '変化と新しい選択',
        AstroPlanet.neptune => '想像力と休息',
        AstroPlanet.pluto => '深い変化と手放し',
        _ => '今日の流れ',
      };

  AspectLine _aspectLine(TransitAspect aspect, [HoroscopeReadingContext? source]) {
    return AspectLine(
      from: '現在の${aspect.transitPlanet.label}',
      aspectName: aspect.type.label,
      aspectHint: _aspectHint(aspect.type),
      angle: aspect.type.angle,
      time: _aspectTimeLabel(aspect, source),
      to: '出生図の${aspect.natalPlanet.label}',
      meaning: _natalAspectImpact(aspect),
    );
  }

  AspectLine _pairAspectLine(TransitPairAspect aspect, [HoroscopeReadingContext? source]) {
    return AspectLine(
      from: '現在の${aspect.firstPlanet.label}',
      aspectName: aspect.type.label,
      aspectHint: '${_aspectHint(aspect.type)} / ${aspect.phase.label}',
      angle: aspect.type.angle,
      time: _pairTimeLabel(aspect, source),
      to: '現在の${aspect.secondPlanet.label}',
      meaning: _skyAspectImpact(aspect),
    );
  }

  String _natalAspectImpact(TransitAspect aspect) {
    final strength = aspect.orb <= 0.7
        ? '影響はかなり強めです。'
        : aspect.orb <= 2.0
            ? '影響は強めです。'
            : aspect.orb <= 4.0
                ? '影響は中くらいです。'
                : '影響は穏やかですが、意識すると流れを使えます。';
    final current = _planetTheme(aspect.transitPlanet);
    final natal = _planetTheme(aspect.natalPlanet);
    final effect = switch (aspect.type) {
      AspectType.conjunction => '$currentと$natalが重なります。自分の気持ちや行動へ直接出やすいので、いま本当に優先したいことを一つに絞ると力になります。',
      AspectType.sextile => '$currentが$natalを後押しします。小さな連絡、準備、提案を自分から一つ動かすと、機会につながりやすい配置です。',
      AspectType.trine => '$currentと$natalが自然につながります。無理に背伸びせず、得意なやり方をそのまま使うほど、手応えを受け取りやすい日です。',
      AspectType.square => '$currentと$natalがぶつかりやすい配置です。焦って結論を出すより、予定・言葉・体力のどれかを一段軽くして調整すると、負荷を成果へ変えられます。',
      AspectType.opposition => '$currentと$natalが向かい合います。相手の反応や外側の予定に振られやすいので、すぐ決めず、条件を並べてから折り合いをつけるのが向きます。',
    };
    return '$strength $effect';
  }

  String _skyAspectImpact(TransitPairAspect aspect) {
    final strength = aspect.orb <= 0.7
        ? '今日はピーク圏で、影響がかなり強めです。'
        : aspect.phase == AspectPhase.applying
            ? 'これから強まりやすい流れです。'
            : 'すでに出た流れを整えて活かす時期です。';
    final pair = '${_planetTheme(aspect.firstPlanet)}と${_planetTheme(aspect.secondPlanet)}';
    final effect = switch (aspect.type) {
      AspectType.conjunction => '$pairが同時に前へ出ます。ひとつのテーマへ集中しやすい反面、気持ちが偏りやすいので、優先順位を決めて使うと力になります。',
      AspectType.sextile => '$pairが協力しやすい配置です。話す、試す、整えるなど小さな一歩を出すと、今日の流れに乗りやすいです。',
      AspectType.trine => '$pairが自然にかみ合います。いつもの得意な方法で進めるほど、対人・仕事・お金の流れを滑らかにしやすいです。',
      AspectType.square => '$pairの間で急ぎと現実のズレが出やすい配置です。勢いで決めず、期限・金額・相手への伝え方を一度見直すと崩れにくくなります。',
      AspectType.opposition => '$pairが引っ張り合う配置です。一方だけを押し通すより、相手の事情や使える時間を確認して、ちょうどよい落とし所を探すのが向きます。',
    };
    return '$strength $effect';
  }

  String _planetTheme(AstroPlanet planet) {
    return switch (planet) {
      AstroPlanet.sun => '自分らしさと目的',
      AstroPlanet.moon => '気分と生活リズム',
      AstroPlanet.mercury => '言葉と判断',
      AstroPlanet.venus => '好意と楽しみ',
      AstroPlanet.mars => '行動力と勢い',
      AstroPlanet.jupiter => '成長と広がり',
      AstroPlanet.saturn => '責任と現実的な土台',
      AstroPlanet.uranus => '変化と自由',
      AstroPlanet.neptune => '想像力と曖昧さ',
      AstroPlanet.pluto => '深い変化と集中',
      AstroPlanet.ascendant => '自分の見せ方',
      AstroPlanet.midheaven => '仕事と社会的な役割',
    };
  }

  String _aspectTimeLabel(TransitAspect aspect, [HoroscopeReadingContext? source]) {
    final data = source ?? contextData;
    if (aspect.orb <= 0.7) return '現在ピーク圏';
    final next = data.nextAspects.where(
      (item) => item.transitPlanet == aspect.transitPlanet &&
          item.natalPlanet == aspect.natalPlanet && item.type == aspect.type,
    );
    if (next.isEmpty) return aspect.orb <= 2 ? 'ピーク接近' : '指定日';
    final nextOrb = next.first.orb;
    if (nextOrb >= aspect.orb) return 'ピーク通過後';
    final estimatedHours = aspect.orb / (aspect.orb - nextOrb) * 24;
    if (!estimatedHours.isFinite || estimatedHours >= 24) return '翌日以降にピーク見込み';
    final hours = estimatedHours.round().clamp(1, 23);
    final time = data.transit.date.add(Duration(hours: hours));
    return 'ピーク推定 ${_peakDateTimeLabel(time, data)}';
  }

  String _pairTimeLabel(TransitPairAspect aspect, [HoroscopeReadingContext? source]) {
    final data = source ?? contextData;
    if (aspect.phase == AspectPhase.exact) return '現在ピーク圏';
    final first = _placement(data.transit.placements, aspect.firstPlanet);
    final second = _placement(data.transit.placements, aspect.secondPlanet);
    final nextFirst = _placement(data.nextTransitPlacements, aspect.firstPlanet);
    final nextSecond = _placement(data.nextTransitPlacements, aspect.secondPlanet);
    if (first == null || second == null || nextFirst == null || nextSecond == null) return aspect.phase.label;
    final nextOrb = _pairOrb(nextFirst, nextSecond, aspect.type);
    if (nextOrb >= aspect.orb) return 'ピーク通過後';
    final estimatedHours = aspect.orb / (aspect.orb - nextOrb) * 24;
    if (!estimatedHours.isFinite || estimatedHours >= 24) return '翌日以降にピーク見込み';
    final hours = estimatedHours.round().clamp(1, 23);
    final time = data.transit.date.add(Duration(hours: hours));
    return 'ピーク推定 ${_peakDateTimeLabel(time, data)}';
  }

  String _peakDateTimeLabel(DateTime time, [HoroscopeReadingContext? source]) {
    final timeLabel = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    final base = (source ?? contextData).transit.date;
    if (time.year == base.year && time.month == base.month && time.day == base.day) return timeLabel;
    return '${time.month}/${time.day} $timeLabel';
  }

  double _pairOrb(PlanetPlacement first, PlanetPlacement second, AspectType type) {
    var distance = (first.sign.index * 30 + first.degree - second.sign.index * 30 - second.degree).abs() % 360;
    if (distance > 180) distance = 360 - distance;
    final exact = switch (type) {
      AspectType.conjunction => 0.0,
      AspectType.sextile => 60.0,
      AspectType.square => 90.0,
      AspectType.trine => 120.0,
      AspectType.opposition => 180.0,
    };
    return (distance - exact).abs();
  }

  PlanetPlacement? _placement(List<PlanetPlacement> placements, AstroPlanet planet) {
    for (final placement in placements) {
      if (placement.planet == planet) return placement;
    }
    return null;
  }

  Future<void> _showAllAspects(BuildContext context) async {
    var activeContext = contextData;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final allAspects = activeContext.fullAspects;
          final targetDate = activeContext.transit.date;
          final targetDateTimeLabel =
              '${targetDate.year}年${targetDate.month}月${targetDate.day}日 '
              '${targetDate.hour.toString().padLeft(2, '0')}:'
              '${targetDate.minute.toString().padLeft(2, '0')}';
          final isTablet = MediaQuery.sizeOf(context).width >= 680;
          final usesBaseDateTime = targetDate == contextData.transit.date;

          Future<void> selectDateTime() async {
            final date = await showDatePicker(
              context: context,
              initialDate: targetDate,
              firstDate: DateTime(1900),
              lastDate: DateTime(2100),
              helpText: '全アスペクト表の日付',
            );
            if (date == null || !context.mounted) return;
            final time = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.fromDateTime(targetDate),
              helpText: '全アスペクト表の時刻',
            );
            if (time == null || !context.mounted) return;
            final selected = DateTime(date.year, date.month, date.day, time.hour, time.minute);
            final nextContext = const AstrologyEngine().buildPreviewContext(
              profile: contextData.natal.profile,
              date: selected,
            );
            setSheetState(() => activeContext = nextContext);
          }

          return SafeArea(
            top: false,
            child: Container(
              height: MediaQuery.sizeOf(context).height * (isTablet ? 0.94 : 0.90),
              padding: EdgeInsets.fromLTRB(isTablet ? 22 : 18, 12, isTablet ? 22 : 18, 18),
              decoration: const BoxDecoration(
                color: Color(0xFF171A36),
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.34),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '全アスペクト詳細表',
                          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
                        ),
                      ),
                      Text(
                        '${allAspects.length}件',
                        style: TextStyle(
                          color: const Color(0xFFF6D77A).withValues(alpha: 0.84),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        tooltip: '閉じる',
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.schedule_outlined,
                        size: 17,
                        color: const Color(0xFF57D6D1).withValues(alpha: 0.9),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          '星の配置: $targetDateTimeLabel',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.82),
                            fontSize: isTablet ? 13 : 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (!usesBaseDateTime)
                        IconButton(
                          onPressed: () => setSheetState(() => activeContext = contextData),
                          tooltip: '選択日の12:00に戻す',
                          icon: const Icon(Icons.restore, size: 20),
                        ),
                      OutlinedButton.icon(
                        onPressed: selectDateTime,
                        icon: const Icon(Icons.edit_calendar_outlined, size: 17),
                        label: const Text('日時を変更'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: isTablet
                        ? _TabletDailyAstroBoard(
                            contextData: activeContext,
                            allAspects: allAspects,
                            aspectTimeLabel: (aspect) => _aspectTimeLabel(aspect, activeContext),
                            pairTimeLabel: (aspect) => _pairTimeLabel(aspect, activeContext),
                          )
                        : allAspects.isEmpty
                            ? const Center(child: Text('指定日時のアスペクトはありません。'))
                            : ListView.builder(
                                padding: const EdgeInsets.only(bottom: 16),
                                itemCount: allAspects.length,
                                itemBuilder: (context, index) => _aspectLine(allAspects[index], activeContext),
                              ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _aspectHint(AspectType type) {
    switch (type) {
      case AspectType.conjunction:
        return '影響が直接出やすい角度';
      case AspectType.sextile:
        return 'きっかけが生まれる角度';
      case AspectType.square:
        return '課題が出やすい角度';
      case AspectType.trine:
        return '調和しやすい角度';
      case AspectType.opposition:
        return '外側から刺激が入る角度';
    }
  }
}

class _TabletDailyAstroBoard extends StatelessWidget {
  const _TabletDailyAstroBoard({
    required this.contextData,
    required this.allAspects,
    required this.aspectTimeLabel,
    required this.pairTimeLabel,
  });

  final HoroscopeReadingContext contextData;
  final List<TransitAspect> allAspects;
  final String Function(TransitAspect aspect) aspectTimeLabel;
  final String Function(TransitPairAspect aspect) pairTimeLabel;

  @override
  Widget build(BuildContext context) {
    final grandTrines = FortuneScoreCalculator.transitGrandTrineLabels(contextData);
    final placements = contextData.transit.placements
        .map(
          (placement) => '${placement.planet.label} ${placement.sign.label} ${placement.degree.toStringAsFixed(1)}° '
              '第${placement.house}H${contextData.retrogradePlanets.contains(placement.planet) ? ' 逆行' : ''}',
        )
        .toList();
    final natalAspectLines = allAspects
        .map(
          (aspect) => '${aspect.transitPlanet.label} ${aspect.type.label} 出生図${aspect.natalPlanet.label} '
              '${aspect.orb.toStringAsFixed(1)}° / ${aspectTimeLabel(aspect)}',
        )
        .toList();
    final skyAspectLines = contextData.transitPairAspects
        .map(
          (aspect) => '${aspect.firstPlanet.label} ${aspect.type.label} ${aspect.secondPlanet.label} '
              '${aspect.orb.toStringAsFixed(1)}° / ${pairTimeLabel(aspect)}',
        )
        .toList();
    final houseLines = contextData.houseTransits
        .map((transit) => '${transit.planet.label} 第${transit.natalHouse}H / ${transit.area.label}')
        .toList();
    final returnLines = contextData.returns
        .map(
          (event) => '${event.planet.label}リターン ${event.orb.toStringAsFixed(1)}° '
              '${event.phase.label} / 第${event.natalHouse}H',
        )
        .toList();
    final specialLines = <String>[
      if (contextData.retrogradePlanets.isNotEmpty)
        '逆行: ${contextData.retrogradePlanets.map((planet) => planet.label).join('・')}',
      if (contextData.transit.voidMoon != null) '月ボイド: ${contextData.transit.voidMoon!.label}',
      ...grandTrines.map((label) => 'グランドトライン: $label'),
      ...contextData.natal.stelliums.map((item) => '出生図集中: ${item.label}'),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1120
            ? 4
            : constraints.maxWidth >= 680
                ? 3
                : constraints.maxWidth >= 480
                    ? 2
                    : 1;
        const gap = 10.0;
        final cardWidth = (constraints.maxWidth - gap * (columns - 1)) / columns;
        final cards = <Widget>[
          _AstroBoardCard(icon: Icons.public_outlined, title: '現在の天体位置', lines: placements),
          _AstroBoardCard(
            icon: Icons.hub_outlined,
            title: '出生図との全アスペクト',
            count: natalAspectLines.length,
            lines: natalAspectLines,
            emptyText: '該当する主要5角度はありません。',
          ),
          _AstroBoardCard(
            icon: Icons.auto_awesome_outlined,
            title: '空の星同士の全アスペクト',
            count: skyAspectLines.length,
            lines: skyAspectLines,
            emptyText: '該当する主要5角度はありません。',
          ),
          _AstroBoardCard(icon: Icons.home_work_outlined, title: 'ハウス通過', lines: houseLines),
          _AstroBoardCard(
            icon: Icons.restart_alt,
            title: 'リターン',
            count: returnLines.length,
            lines: returnLines,
            emptyText: '今日のリターンはありません。',
          ),
          _AstroBoardCard(
            icon: Icons.change_history_outlined,
            title: '逆行・月ボイド・複合配置',
            lines: specialLines,
            emptyText: '目立つ補助配置はありません。',
          ),
        ];
        return ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 24),
          children: [
            Wrap(
              spacing: gap,
              runSpacing: gap,
              children: cards.map((card) => SizedBox(width: cardWidth, child: card)).toList(),
            ),
          ],
        );
      },
    );
  }
}

class _AstroBoardCard extends StatelessWidget {
  const _AstroBoardCard({
    required this.icon,
    required this.title,
    required this.lines,
    this.count,
    this.emptyText = 'データはありません。',
  });

  final IconData icon;
  final String title;
  final List<String> lines;
  final int? count;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: const Color(0xFFF6D77A)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                ),
              ),
              if (count != null)
                Text(
                  '$count件',
                  style: TextStyle(
                    color: const Color(0xFFF6D77A).withValues(alpha: 0.84),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 7),
          if (lines.isEmpty)
            Text(
              emptyText,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.54), fontSize: 11, height: 1.28),
            )
          else
            ...lines.map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  line,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontSize: 11,
                    height: 1.26,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class VoidTimeNotice extends StatelessWidget {
  const VoidTimeNotice({super.key, required this.period});

  final VoidMoonPeriod? period;

  @override
  Widget build(BuildContext context) {
    if (period == null) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = MediaQuery.sizeOf(context).width < 390;
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFF6D77A).withValues(alpha: 0.18)),
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _VoidTimeHeader(period: period!),
                    const SizedBox(height: 6),
                    _VoidTimeBody(compact: compact, period: period!),
                  ],
                )
              : Row(
                  children: [
                    _VoidTimeHeader(period: period!),
                    const SizedBox(width: 8),
                    Expanded(child: _VoidTimeBody(compact: compact, period: period!)),
                  ],
                ),
        );
      },
    );
  }
}

class _VoidTimeHeader extends StatelessWidget {
  const _VoidTimeHeader({required this.period});

  final VoidMoonPeriod period;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.hourglass_bottom_outlined,
          size: 17,
          color: Color(0xFFF6D77A),
        ),
        const SizedBox(width: 8),
        const Text(
          'ボイドタイム',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
        ),
        const SizedBox(width: 8),
        Text(
          period.label,
          style: TextStyle(
            color: const Color(0xFFF6D77A).withValues(alpha: 0.92),
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _VoidTimeBody extends StatelessWidget {
  const _VoidTimeBody({required this.compact, required this.period});

  final bool compact;
  final VoidMoonPeriod period;

  @override
  Widget build(BuildContext context) {
    return Text(
      period.guidance,
      maxLines: compact ? 2 : 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.62),
        fontSize: 12,
        height: 1.35,
      ),
    );
  }
}

class PlanetReturnPanel extends StatelessWidget {
  const PlanetReturnPanel({super.key, required this.contextData});

  final HoroscopeReadingContext contextData;

  @override
  Widget build(BuildContext context) {
    final returns = contextData.returns.map(_returnItem).toList();

    return GlassPanel(
      margin: const EdgeInsets.only(top: 14, bottom: 14),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SmallSectionLabel(
            icon: Icons.restart_alt,
            text: '星のリターン補正',
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 680;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: returns.isEmpty
                    ? [
                        SizedBox(
                          width: constraints.maxWidth,
                          child: Text(
                            'この日は強いリターン補正は出ていません。通常のトランジットとハウス通過を中心に読みます。',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.66),
                              height: 1.45,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ]
                    : returns
                        .map(
                          (item) => SizedBox(
                            width: isWide ? (constraints.maxWidth - 20) / 3 : constraints.maxWidth,
                            child: _PlanetReturnTile(item: item),
                          ),
                        )
                        .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  PlanetReturnItem _returnItem(PlanetReturnEvent event) {
    return PlanetReturnItem(
      planet: '${event.planet.label}リターン',
      status: event.status,
      target: '${event.area.label} / 第${event.natalHouse}ハウス',
      note: event.meaning,
    );
  }
}

class PlanetReturnItem {
  const PlanetReturnItem({
    required this.planet,
    required this.status,
    required this.target,
    required this.note,
  });

  final String planet;
  final String status;
  final String target;
  final String note;
}

class _PlanetReturnTile extends StatelessWidget {
  const _PlanetReturnTile({required this.item});

  final PlanetReturnItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.planet,
                  style: const TextStyle(
                    color: Color(0xFFF6D77A),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _AspectTypeChip(label: item.status),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            item.target,
            style: TextStyle(
              color: const Color(0xFF57D6D1).withValues(alpha: 0.84),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.note,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.68),
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class NatalSensitivityPanel extends StatelessWidget {
  const NatalSensitivityPanel({super.key, required this.contextData});

  final HoroscopeReadingContext contextData;

  @override
  Widget build(BuildContext context) {
    final angular = contextData.natal.placements
        .where(
          (placement) =>
              placement.planet != AstroPlanet.ascendant &&
              placement.planet != AstroPlanet.midheaven &&
              {1, 4, 7, 10}.contains(placement.house),
        )
        .map((placement) => '${placement.planet.label}（第${placement.house}ハウス）')
        .toList();
    final stelliums = contextData.natal.stelliums
        .map((item) => '第${item.house}ハウス: ${item.planets.map((planet) => planet.label).join('・')}')
        .toList();
    final hasJupiterVenus = FortuneScoreCalculator.hasNatalJupiterVenusConjunction(contextData);
    final hasFactors = angular.isNotEmpty || stelliums.isNotEmpty || hasJupiterVenus;

    return GlassPanel(
      margin: const EdgeInsets.only(top: 14, bottom: 14),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SmallSectionLabel(
            icon: Icons.sensors_outlined,
            text: '出生図の反応ポイント',
          ),
          const SizedBox(height: 10),
          Text(
            hasFactors
                ? '以下の出生図要素が、実際に該当する星やハウスを通過した日にだけ点数補正を強めます。毎日一律に加点する仕組みではありません。'
                : '角ハウス・星の集中・主要な結びつきが強く重なる日は、点数補正に反映します。',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.68),
              fontSize: 12,
              height: 1.45,
            ),
          ),
          if (angular.isNotEmpty) ...[
            const SizedBox(height: 10),
            _SensitivityRow(label: '角ハウスの星', value: angular.join(' / ')),
          ],
          if (stelliums.isNotEmpty) ...[
            const SizedBox(height: 8),
            _SensitivityRow(label: '星の集中', value: stelliums.join(' / ')),
          ],
          if (hasJupiterVenus) ...[
            const SizedBox(height: 8),
            const _SensitivityRow(label: '木星×金星', value: '出生図で重なり。通過時に恋愛・金運の共鳴補正'),
          ],
          const SizedBox(height: 10),
          Text(
            '補正の読み方: 木星は総合・金運、金星は恋愛・金運、水星と土星は仕事、月と海王星は健康・メンタルを中心に反映。出生図のハウス、ステリウム、アスペクト、リターン、逆行、月の通過が重なるほど影響を強めますが、同じ要素は重複加点しないよう調整します。',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.62),
              fontSize: 12,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _SensitivityRow extends StatelessWidget {
  const _SensitivityRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$label: $value',
      style: TextStyle(
        color: const Color(0xFF57D6D1).withValues(alpha: 0.88),
        fontSize: 12,
        height: 1.4,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class AspectLine extends StatelessWidget {
  const AspectLine({
    super.key,
    required this.from,
    required this.aspectName,
    required this.aspectHint,
    required this.angle,
    required this.time,
    required this.to,
    required this.meaning,
  });

  final String from;
  final String aspectName;
  final String aspectHint;
  final String angle;
  final String time;
  final String to;
  final String meaning;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final header = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '$from と $to',
                  maxLines: 2,
                  overflow: TextOverflow.visible,
                  style: const TextStyle(
                    color: Color(0xFFF6D77A),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    height: 1.25,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _AspectTimeChip(time: time),
            ],
          );

          final detail = Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              _AspectTypeChip(label: aspectName),
              Text(
                angle,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.58),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          );

          final meaningText = Text(
            meaning,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.74),
              height: 1.4,
            ),
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              header,
              const SizedBox(height: 8),
              detail,
              const SizedBox(height: 6),
              Text(
                aspectHint,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.52),
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 8),
              meaningText,
            ],
          );
        },
      ),
    );
  }
}

class _AspectTypeChip extends StatelessWidget {
  const _AspectTypeChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF57D6D1).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF57D6D1),
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _AspectTimeChip extends StatelessWidget {
  const _AspectTimeChip({required this.time});

  final String time;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF6D77A).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFF6D77A).withValues(alpha: 0.22)),
      ),
      child: Text(
        time,
        style: const TextStyle(
          color: Color(0xFFF6D77A),
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _SmallSectionLabel extends StatelessWidget {
  const _SmallSectionLabel({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF57D6D1), size: 18),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class TodayFortuneGrid extends StatefulWidget {
  const TodayFortuneGrid({
    super.key,
    required this.detailed,
    required this.profile,
    required this.details,
    required this.date,
    required this.contextData,
  });

  final bool detailed;
  final AstroProfile profile;
  final UserProfileDetails details;
  final DateTime date;
  final HoroscopeReadingContext contextData;

  @override
  State<TodayFortuneGrid> createState() => _TodayFortuneGridState();
}

class _TodayFortuneGridState extends State<TodayFortuneGrid> {

  List<TodayFortuneItem> _itemsFor(HoroscopeReadingContext contextData) {
    final venusSign = _transitSign(contextData, AstroPlanet.venus, '金星: 天秤座');
    final mercurySign = _transitSign(contextData, AstroPlanet.mercury, '水星: 乙女座');
    final jupiterSign = _transitSign(contextData, AstroPlanet.jupiter, '木星: 蟹座');
    final moonSign = _transitSign(contextData, AstroPlanet.moon, '月: 魚座');
    final loveBreakdown = FortuneScoreCalculator.dailyAreaBreakdown(contextData, FortuneArea.love, 70);
    final workBreakdown = FortuneScoreCalculator.dailyAreaBreakdown(contextData, FortuneArea.work, 74);
    final moneyBreakdown = FortuneScoreCalculator.dailyAreaBreakdown(contextData, FortuneArea.money, 68);
    final mentalBreakdown = FortuneScoreCalculator.dailyAreaBreakdown(contextData, FortuneArea.mental, 72);
    final loveScore = loveBreakdown.score;
    final workScore = workBreakdown.score;
    final moneyScore = moneyBreakdown.score;
    final mentalScore = mentalBreakdown.score;

    return [
    TodayFortuneItem(
      title: '恋愛運',
      score: loveScore,
      scoreBreakdown: loveBreakdown,
      sign: venusSign,
      natalHouse: _natalLabel(contextData, AstroPlanet.venus, '出生図の金星: 第7ハウス'),
      aspectLabel: _aspectLabel(contextData, FortuneArea.love, '現在の金星 トライン 出生図の月'),
      transitHouseLabel: _houseTransitLabel(contextData, AstroPlanet.venus, '金星が出生図の第7ハウスを通過'),
      aspectBasis: _dailyAspectBasis(
        contextData,
        FortuneArea.love,
        '金星と出生図の月・対人ハウスの角度を加味。',
      ),
      dailyHighlight: _dailyHighlight(contextData, FortuneArea.love, loveScore),
      text: _simpleDailyText(
        contextData,
        FortuneArea.love,
        loveScore,
        high: const ['自然な一言が好印象につながる日。気になる相手には、明るい近況を素直に伝えると距離が縮まります。', '人との縁が動きやすい日。誘いや連絡は先延ばしにせず、無理のない予定を一つ提案すると流れに乗れます。'],
        steady: const ['やさしい言葉が効く日。駆け引きより素直な一言を選ぶと、関係が落ち着いて進みます。', '相手との温度差を整えやすい日。返事を急かさず、聞く時間を少し長くすると安心感が生まれます。'],
        careful: const ['気持ちを急いで結論にしない日。送る前に言葉を一度見直し、相手の都合も考えた連絡にすると運が整います。', '小さな誤解が出やすい日。決めつけずに一つ確認してから動くと、関係のぎこちなさを防げます。'],
      ),
      detailedText:
          _detailedDailyText(contextData, FortuneArea.love, loveScore),
      icon: Icons.favorite_border,
    ),
    TodayFortuneItem(
      title: '仕事運',
      score: workScore,
      scoreBreakdown: workBreakdown,
      sign: mercurySign,
      natalHouse: _natalLabel(contextData, AstroPlanet.midheaven, '出生図のMC: 第10ハウス'),
      aspectLabel: _aspectLabel(contextData, FortuneArea.work, '現在の水星 セクスタイル 出生図の太陽'),
      transitHouseLabel: _houseTransitLabel(contextData, AstroPlanet.mercury, '水星が出生図の第10ハウスを通過'),
      aspectBasis: _dailyAspectBasis(
        contextData,
        FortuneArea.work,
        '水星と出生図の太陽・仕事ハウスの角度を加味。',
      ),
      dailyHighlight: _dailyHighlight(contextData, FortuneArea.work, workScore),
      text: _simpleDailyText(
        contextData,
        FortuneArea.work,
        workScore,
        high: const ['仕事の判断と連絡がスムーズに進む日。後回しにしていた依頼を一つ片づけると、次の話も入りやすくなります。', '考えを形にする力が強い日。提案や相談は短く整理して伝えると、周囲の協力を得やすくなります。'],
        steady: const ['連絡や整理に追い風。曖昧な予定を一つ確定させると流れが良くなります。', '細かな確認が成果につながる日。優先順位を二つに絞り、先に一つを終わらせると安心です。'],
        careful: const ['仕事を抱え込みやすい日。期限と確認先を先に書き出し、一人で迷う前に早めに相談しましょう。', '予定の行き違いに注意したい日。送信前に日時と相手を確認すると、余計なやり直しを防げます。'],
      ),
      detailedText:
          _detailedDailyText(contextData, FortuneArea.work, workScore),
      icon: Icons.work_outline,
    ),
    TodayFortuneItem(
      title: '金運',
      score: moneyScore,
      scoreBreakdown: moneyBreakdown,
      sign: venusSign,
      secondarySign: jupiterSign,
      natalHouse: _natalLabel(contextData, AstroPlanet.venus, '出生図の金星: 第2ハウス'),
      aspectLabel: _aspectLabel(contextData, FortuneArea.money, '現在の木星 スクエア 出生図の金星'),
      transitHouseLabel: _houseTransitLabel(contextData, AstroPlanet.jupiter, '木星が出生図の第2ハウスを通過'),
      stelliumLabel: '第2ハウス強調',
      aspectBasis: _dailyAspectBasis(
        contextData,
        FortuneArea.money,
        '金星・木星と出生図の金銭ハウスの角度を加味。',
      ),
      dailyHighlight: _dailyHighlight(contextData, FortuneArea.money, moneyScore),
      text: _simpleDailyText(
        contextData,
        FortuneArea.money,
        moneyScore,
        high: const ['お金の流れを広げやすい日。必要な道具や学びへの小さな投資は、将来の収入につながるかを見て選びましょう。', '価値のある使い方を見極めやすい日。予算を決めてから、長く役立つものを一つ選ぶと満足度が上がります。'],
        steady: const ['大きな買い物は慎重に。小さな自己投資には良い気配があるので、予算内で一つだけ選ぶと安心です。', '収入と支出を整えやすい日。使っていない定額サービスを一つ確認すると、先の余裕が増えます。'],
        careful: const ['気分で財布がゆるみやすい日。欲しい物はすぐ決めず、予算と必要性を一度メモしてから判断しましょう。', 'お金の不安を一度に解決しようとしない日。今日の支出を確認し、明日できる見直しを一つ決めると落ち着きます。'],
      ),
      detailedText:
          _detailedDailyText(contextData, FortuneArea.money, moneyScore),
      icon: Icons.savings_outlined,
    ),
    TodayFortuneItem(
      title: '健康・メンタル運',
      score: mentalScore,
      scoreBreakdown: mentalBreakdown,
      sign: moonSign,
      natalHouse: _natalLabel(contextData, AstroPlanet.moon, '出生図の月: 第4ハウス'),
      aspectLabel: _aspectLabel(contextData, FortuneArea.mental, '現在の月 コンジャンクション 出生図の月'),
      transitHouseLabel: _houseTransitLabel(contextData, AstroPlanet.moon, '月が出生図の第4ハウスを通過'),
      aspectBasis: '月と出生図の月・心身ハウスの角度を加味。月ボイドは対象日の時間割合で補正。',
      dailyHighlight: _dailyHighlight(contextData, FortuneArea.mental, mentalScore),
      text: _simpleDailyText(
        contextData,
        FortuneArea.mental,
        mentalScore,
        high: const ['心身の調子を整えやすい日。やりたいことを一つ選び、休む時間も予定に入れると気持ちよく動けます。', '安心できる場所や人から力をもらえる日。無理な我慢を減らし、気分転換の時間を先に確保しましょう。'],
        steady: const ['気持ちの奥にある本音が見えやすい日。静かな時間を少し作ると、自然に調子が整います。', '生活リズムを戻しやすい日。食事や休憩を抜かず、夜の予定を一つ減らすと心に余裕ができます。'],
        careful: const ['今日は体調・メンタルを気にかける日。短い休憩を先に決め、無理に答えを出さず明日に回す選択も大切です。', '今日は体調・メンタルを気にかける日。周囲の空気を受けやすいので、一人で落ち着く時間を確保し、眠る前は画面から少し離れましょう。'],
      ),
      detailedText:
          _detailedDailyText(contextData, FortuneArea.mental, mentalScore),
      icon: Icons.dark_mode_outlined,
    ),
    ];
  }

  String _dailyAspectBasis(
    HoroscopeReadingContext contextData,
    FortuneArea area,
    String base,
  ) {
    final returns = contextData.returnsFor(area).map((event) => event.planet.label).toSet();
    if (returns.isEmpty) return base;
    return '$base 実際の${returns.join('・')}リターンも補正。';
  }

  String _dailyReturnText(HoroscopeReadingContext contextData, FortuneArea area) {
    final returns = contextData.returnsFor(area).map((event) => event.planet.label).toSet();
    if (returns.isEmpty) return '';
    return '${returns.join('・')}リターンが実際に重なるため、過去のやり方を一つ見直すのも向きます。';
  }

  String _detailedDailyText(
    HoroscopeReadingContext contextData,
    FortuneArea area,
    int score,
  ) {
    final aspectCandidates = contextData.aspectsFor(area).toList()
      ..sort((a, b) => a.orb.compareTo(b.orb));
    final aspect = aspectCandidates.isEmpty ? null : aspectCandidates.first;
    final transitCandidates = contextData.houseTransitsFor(area).toList();
    final transit = transitCandidates.isEmpty ? null : transitCandidates.first;
    final skyPair = _areaTransitPair(contextData, area);
    final returns = contextData.returnsFor(area).toList()
      ..sort((a, b) => a.orb.compareTo(b.orb));
    final highlight = _dailyHighlight(contextData, area, score);
    final areaName = switch (area) {
      FortuneArea.love => '恋愛・対人面',
      FortuneArea.work => '仕事・発信面',
      FortuneArea.money => 'お金と価値の面',
      FortuneArea.mental => '心身と生活の面',
      FortuneArea.overall => '全体の流れ',
    };
    final parts = <String>[
      '$areaNameは${score}点で、「${highlight.title}」がこの日の中心です。',
    ];

    if (aspect != null) {
      final phase = _natalAspectPhase(contextData, aspect);
      parts.add(
        '現在の${aspect.transitPlanet.label}と出生図の${aspect.natalPlanet.label}が${aspect.type.label}（オーブ${aspect.orb.toStringAsFixed(1)}°・$phase）です。${aspect.meaning}',
      );
    } else if (skyPair != null) {
      parts.add(
        '空では現在の${skyPair.firstPlanet.label}と${skyPair.secondPlanet.label}が${skyPair.type.label}（オーブ${skyPair.orb.toStringAsFixed(1)}°・${skyPair.phase.label}）を作っています。この組み合わせが、この分野の空気と判断の速さに影響します。',
      );
    }
    if (transit != null) {
      parts.add('さらに${transit.planet.label}が出生図の第${transit.natalHouse}ハウスを通過中で、${transit.meaning}。');
    }
    if (returns.isNotEmpty) {
      final event = returns.first;
      parts.add('${event.planet.label}リターンも重なり、${event.meaning}。');
    }
    final voidMoon = contextData.transit.voidMoon;
    if (voidMoon != null) {
      parts.add('月ボイドの${voidMoon.label}は、結論を急ぐより確認と下準備へ回す方が安定します。');
    }
    if (contextData.retrogradePlanets.contains(AstroPlanet.mercury) &&
        (area == FortuneArea.work || area == FortuneArea.money || area == FortuneArea.love)) {
      parts.add('水星逆行中でもあるため、送信、公開、支払いは内容と日時を一度見直してから進めましょう。');
    }
    if (area == FortuneArea.mental && score <= 65) {
      parts.add('今日は体調・メンタルを気にかける日です。睡眠、食事、休憩を後回しにせず、予定を一つ減らすくらいの余白を作りましょう。');
    }
    parts.add('実行するなら、${highlight.actionHint}');
    return parts.join(' ');
  }

  String _simpleDailyText(
    HoroscopeReadingContext contextData,
    FortuneArea area,
    int score, {
    required List<String> high,
    required List<String> steady,
    required List<String> careful,
  }) {
    final choices = score >= 82 ? high : score >= 66 ? steady : careful;
    final index = (widget.date.day + widget.date.month + area.index) % choices.length;
    final useCaseHint = _dailyQuestionDatabaseHint(area, score);
    final moonHint = area == FortuneArea.mental
        ? moonSignActionHint(contextData, mental: true)
        : '';
    return [choices[index], useCaseHint, moonHint]
        .where((text) => text.isNotEmpty)
        .join(' ');
  }

  String _dailyQuestionDatabaseHint(FortuneArea area, int score) {
    final hasProfileGuidance =
        widget.details.personality.trim().isNotEmpty ||
        widget.details.concerns.trim().isNotEmpty ||
        widget.details.readingStyle.trim().isNotEmpty;
    if (!hasProfileGuidance) return '';
    final raw =
        '${widget.profile.theme} ${widget.details.personality} ${widget.details.concerns} ${widget.details.readingStyle}'
            .toLowerCase();
    String choose(List<String> values) => values[(widget.date.day + area.index) % values.length];
    final favorable = score >= 78;
    return switch (area) {
      FortuneArea.love when raw.contains('復縁') =>
        favorable ? '復縁なら、短い近況確認から始めましょう。' : '復縁の結論は急がず、距離を整えましょう。',
      FortuneArea.love when raw.contains('マッチング') || raw.contains('出会') =>
        favorable ? '出会いの入口を一つ試してみましょう。' : '出会い探しは、プロフィール整理を先にしましょう。',
      FortuneArea.love => choose(
          favorable
              ? const ['短い連絡を一通送りましょう。', '会う候補を一つ提案してみましょう。', '人と会う予定を一つ作りましょう。']
              : const ['追い連絡は控えましょう。', '返事を待つ余白を作りましょう。', '相手の反応を決めつけないようにしましょう。'],
        ),
      FortuneArea.work when raw.contains('youtube') || raw.contains('動画') || raw.contains('創作') || raw.contains('発信') =>
        favorable ? '公開か告知を一件進めましょう。' : '公開より、制作と見直しを優先しましょう。',
      FortuneArea.work when raw.contains('転職') =>
        favorable ? '求人か応募を一件進めましょう。' : '転職条件の比較を先にしましょう。',
      FortuneArea.work when raw.contains('副業') =>
        favorable ? '副業の小さな実績を一つ作りましょう。' : '報酬と作業時間を先に確認しましょう。',
      FortuneArea.work when raw.contains('資格') || raw.contains('勉強') || raw.contains('学習') =>
        favorable ? '短い演習を一回終えましょう。' : '勉強範囲を小さく区切りましょう。',
      FortuneArea.work => choose(
          favorable
              ? const ['止まっている作業を一つ進めましょう。', '相談か提出を一件進めましょう。', '今日の優先作業を一つ終えましょう。']
              : const ['期限と手順を確認しましょう。', '抱え込まず一件相談しましょう。', 'やり直せる準備を先にしましょう。'],
        ),
      FortuneArea.money when raw.contains('投資') || raw.contains('nisa') =>
        favorable ? '投資は条件と上限を確認してから判断しましょう。' : '投資判断は保留し、仕組みを確認しましょう。',
      FortuneArea.money when raw.contains('貯金') || raw.contains('節約') =>
        favorable ? '先取りで残す額を決めましょう。' : '固定費を一件見直しましょう。',
      FortuneArea.money => choose(
          favorable
              ? const ['予算内の買い物を一つ選びましょう。', '必要な支払いを一件済ませましょう。', '将来役立つ使い道を一つ選びましょう。']
              : const ['大きな買い物は一晩置きましょう。', '契約条件を数字で確認しましょう。', '今日の支出を一度見直しましょう。'],
        ),
      FortuneArea.mental when raw.contains('睡眠') || raw.contains('眠') =>
        favorable ? '今夜の就寝時刻を決めましょう。' : '予定を一つ減らして、睡眠を優先しましょう。',
      FortuneArea.mental when raw.contains('ダイエット') || raw.contains('運動') =>
        favorable ? '軽い運動を一回始めましょう。' : '強度を下げ、食事と休息を優先しましょう。',
      FortuneArea.mental => choose(
          favorable
              ? const ['整えたい習慣を一つ始めましょう。', '短い運動か休憩を予定に入れましょう。', '食事と水分の時間を守りましょう。']
              : const ['休憩を先に確保しましょう。', '夜の予定を一つ減らしましょう。', '無理な活動量を落としましょう。'],
        ),
      FortuneArea.overall => '',
    };
  }

  DailyHighlight _dailyHighlight(
    HoroscopeReadingContext contextData,
    FortuneArea area,
    int score,
  ) {
    final returnEvents = contextData.returnsFor(area).toList()
      ..sort((a, b) => a.orb.compareTo(b.orb));
    if (returnEvents.isNotEmpty) {
      final event = returnEvents.first;
      return DailyHighlight(
        title: _returnHighlightTitle(event, area),
        phase: event.phase.label,
        reason: '${event.planet.label}リターン / 第${event.natalHouse}ハウス',
        actionHint: _returnActionHint(event, area, score),
        strength: _highlightStrength(score, event.orb),
      );
    }

    final aspects = contextData.aspectsFor(area).toList()
      ..sort((a, b) => a.orb.compareTo(b.orb));
    if (aspects.isNotEmpty) {
      final aspect = aspects.first;
      final phase = _natalAspectPhase(contextData, aspect);
      return DailyHighlight(
        title: _aspectHighlightTitle(aspect, area),
        phase: phase,
        reason:
            '${aspect.transitPlanet.label}${aspect.type.label}${aspect.natalPlanet.label} / ${aspect.orb.toStringAsFixed(1)}°',
        actionHint: _aspectActionHint(aspect, area, score),
        strength: _highlightStrength(score, aspect.orb),
      );
    }

    final pair = _areaTransitPair(contextData, area);
    if (pair != null) {
      return DailyHighlight(
        title: _pairHighlightTitle(pair, area),
        phase: pair.phase.label,
        reason:
            '${pair.firstPlanet.label}${pair.type.label}${pair.secondPlanet.label} / ${pair.orb.toStringAsFixed(1)}°',
        actionHint: _pairActionHint(pair, area, score),
        strength: _highlightStrength(score, pair.orb),
      );
    }

    final transits = contextData.houseTransitsFor(area).toList();
    if (transits.isNotEmpty) {
      final transit = transits.first;
      return DailyHighlight(
        title: _houseHighlightTitle(transit, area),
        phase: '通過中',
        reason: '${transit.planet.label} 第${transit.natalHouse}ハウス通過',
        actionHint: _houseActionHint(transit, area, score),
        strength: score >= 82 ? 4 : 3,
      );
    }

    final voidMoonPeriod = contextData.transit.voidMoon;
    if (voidMoonPeriod != null && voidMoonPeriod.contains(contextData.transit.date)) {
      return DailyHighlight(
        title: '判断を急がず整える流れ',
        phase: '調整',
        reason: '月ボイド ${voidMoonPeriod.label}',
        actionHint: '決定より確認、公開より下書き、連絡より見直しを一つ選ぶと安定します。',
        strength: 3,
      );
    }

    final moon = _placement(contextData.transit.placements, AstroPlanet.moon);
    final house = moon?.house ?? 0;
    return DailyHighlight(
      title: _moonHouseHighlightTitle(house, area),
      phase: score >= 82 ? '追い風' : score < 66 ? '調整' : '安定',
      reason: house > 0 ? '月 第$houseハウス通過' : '日付とプロフィールの流れ',
      actionHint: _moonHouseActionHint(house, area),
      strength: score >= 82 ? 4 : score < 66 ? 2 : 3,
    );
  }

  int _highlightStrength(int score, double orb) {
    final orbBoost = orb <= 0.7 ? 2 : orb <= 1.6 ? 1 : 0;
    final scoreBoost = score >= 82 ? 2 : score >= 66 ? 1 : 0;
    return math.max(1, math.min(5, 2 + orbBoost + scoreBoost));
  }

  String _natalAspectPhase(HoroscopeReadingContext contextData, TransitAspect aspect) {
    final next = contextData.nextAspects.where(
      (item) =>
          item.transitPlanet == aspect.transitPlanet &&
          item.natalPlanet == aspect.natalPlanet &&
          item.type == aspect.type,
    );
    if (aspect.orb <= 0.7) return 'ピーク';
    if (next.isEmpty) return '指定日';
    return next.first.orb < aspect.orb ? '接近中' : '余韻';
  }

  TransitPairAspect? _areaTransitPair(HoroscopeReadingContext contextData, FortuneArea area) {
    final candidates = contextData.transitPairAspects.where((aspect) {
      final planets = {aspect.firstPlanet, aspect.secondPlanet};
      return switch (area) {
        FortuneArea.love => planets.contains(AstroPlanet.venus) || planets.contains(AstroPlanet.moon),
        FortuneArea.work => planets.contains(AstroPlanet.mercury) ||
            planets.contains(AstroPlanet.saturn) ||
            planets.contains(AstroPlanet.sun),
        FortuneArea.money => planets.contains(AstroPlanet.venus) || planets.contains(AstroPlanet.jupiter),
        FortuneArea.mental => planets.contains(AstroPlanet.moon) ||
            planets.contains(AstroPlanet.mars) ||
            planets.contains(AstroPlanet.saturn),
        FortuneArea.overall => true,
      };
    }).toList()
      ..sort((a, b) => a.orb.compareTo(b.orb));
    return candidates.isEmpty ? null : candidates.first;
  }

  String _returnHighlightTitle(PlanetReturnEvent event, FortuneArea area) {
    if (event.planet == AstroPlanet.jupiter) return '広げるチャンスを選ぶ流れ';
    if (event.planet == AstroPlanet.saturn) return '続ける仕組みを整える流れ';
    if (event.planet == AstroPlanet.venus) return area == FortuneArea.money ? '価値ある使い方を見直す流れ' : '人との距離を整える流れ';
    if (event.planet == AstroPlanet.mercury) return '言葉と予定を組み直す流れ';
    return '${event.planet.label}の節目が出る流れ';
  }

  String _returnActionHint(PlanetReturnEvent event, FortuneArea area, int score) {
    if (event.planet == AstroPlanet.saturn || score < 66) {
      return '新しく増やすより、続ける条件、期限、負担を一つ見直しましょう。';
    }
    if (area == FortuneArea.money) return '収入や支出の中で、長く残したい使い方を一つ選びましょう。';
    if (area == FortuneArea.love) return '連絡や約束は急に詰めず、心地よい距離を一つ言葉にしましょう。';
    if (area == FortuneArea.work) return '今後も使う資料、手順、連絡文を一つ整えましょう。';
    return '生活の中で続けたい習慣を一つだけ短く始めましょう。';
  }

  String _aspectHighlightTitle(TransitAspect aspect, FortuneArea area) {
    if (aspect.type == AspectType.square || aspect.type == AspectType.opposition) {
      return switch (area) {
        FortuneArea.love => '気持ちを急がず確認する流れ',
        FortuneArea.work => '行き違いを先に防ぐ流れ',
        FortuneArea.money => '勢い買いを止めて選ぶ流れ',
        FortuneArea.mental => '疲れを早めにほどく流れ',
        FortuneArea.overall => '無理を減らして整える流れ',
      };
    }
    return switch (area) {
      FortuneArea.love => '本音をやわらかく出せる流れ',
      FortuneArea.work => '考えを形にしやすい流れ',
      FortuneArea.money => '価値ある選択をしやすい流れ',
      FortuneArea.mental => '気持ちを落ち着けやすい流れ',
      FortuneArea.overall => '追い風を一つ使える流れ',
    };
  }

  String _aspectActionHint(TransitAspect aspect, FortuneArea area, int score) {
    final hard = aspect.type == AspectType.square || aspect.type == AspectType.opposition || score < 66;
    if (hard) {
      return switch (area) {
        FortuneArea.love => '返事や判断を急がず、送る前に言葉を一度短く整えましょう。',
        FortuneArea.work => '締切、相手、完了条件を先に確認してから作業を始めましょう。',
        FortuneArea.money => '欲しい理由と予算をメモし、即決しない時間を作りましょう。',
        FortuneArea.mental => '予定を一つ減らし、休憩を先に入れて気持ちの負荷を下げましょう。',
        FortuneArea.overall => '大きな決断を急がず、確認できる材料を一つ増やしましょう。',
      };
    }
    return switch (area) {
      FortuneArea.love => '明るい近況や感謝を一つ伝えると、関係の温度が上がりやすいです。',
      FortuneArea.work => '提案、連絡、下書きのどれかを一つ外へ出すと進展しやすいです。',
      FortuneArea.money => '長く役立つもの、回収できる学び、固定費の見直しを一つ選びましょう。',
      FortuneArea.mental => '安心できる場所や人を先に選び、短い回復時間を予定に入れましょう。',
      FortuneArea.overall => '一番伸ばしたいことを小さく始め、反応を見て整えましょう。',
    };
  }

  String _pairHighlightTitle(TransitPairAspect pair, FortuneArea area) {
    if (pair.involves(AstroPlanet.venus) && pair.involves(AstroPlanet.jupiter)) {
      return area == FortuneArea.money ? '楽しさを収入へつなげる流れ' : '好意と広がりが重なる流れ';
    }
    if (pair.involves(AstroPlanet.mercury)) return '言葉と判断が動きやすい流れ';
    if (pair.involves(AstroPlanet.mars)) return '行動力が強まりやすい流れ';
    if (pair.involves(AstroPlanet.saturn)) return '現実的に固める流れ';
    return '空の星同士が今日の色を作る流れ';
  }

  String _pairActionHint(TransitPairAspect pair, FortuneArea area, int score) {
    final phase = pair.phase == AspectPhase.applying
        ? 'これから強まる流れなので'
        : pair.phase == AspectPhase.exact
            ? '今日いちばん出やすい流れなので'
            : '余韻を使える流れなので';
    if (score < 66 || pair.type == AspectType.square || pair.type == AspectType.opposition) {
      return '$phase、勢いで決めず、確認、休憩、見直しのどれかを一つ挟みましょう。';
    }
    return '$phase、思いついたことを人に伝える、形にする、数字で見る行動を一つ選びましょう。';
  }

  String _houseHighlightTitle(HouseTransit transit, FortuneArea area) {
    return switch (area) {
      FortuneArea.love => '関係性の置き場所を整える流れ',
      FortuneArea.work => '役割と評価を整える流れ',
      FortuneArea.money => '持ち物と収支を整える流れ',
      FortuneArea.mental => '暮らしと回復を整える流れ',
      FortuneArea.overall => '生活の土台を整える流れ',
    };
  }

  String _houseActionHint(HouseTransit transit, FortuneArea area, int score) {
    return switch (area) {
      FortuneArea.love => '相手との約束や距離感を、無理なく続く形に一つ直しましょう。',
      FortuneArea.work => '任されている作業の範囲と次の確認先を一つ明確にしましょう。',
      FortuneArea.money => '持ち物、支出、使う目的を一つ見直すと判断が落ち着きます。',
      FortuneArea.mental => '家、睡眠、休憩のどれかを先に整えると気持ちが安定します。',
      FortuneArea.overall => '今日の予定を一つ減らし、優先順位が見える形にしましょう。',
    };
  }

  String _moonHouseHighlightTitle(int house, FortuneArea area) {
    if (house == 2) return '価値と安心を選び直す流れ';
    if (house == 3) return '連絡と学びが動く流れ';
    if (house == 4) return '居場所を整える流れ';
    if (house == 6) return '生活リズムを整える流れ';
    if (house == 7) return '人との距離が見えやすい流れ';
    if (house == 10) return '評価と役割が見えやすい流れ';
    if (house == 11) return '仲間や発信が広がる流れ';
    if (house == 12) return '静かに回復する流れ';
    return switch (area) {
      FortuneArea.love => '会話の温度を整える流れ',
      FortuneArea.work => '小さな段取りが効く流れ',
      FortuneArea.money => '支出を選び直す流れ',
      FortuneArea.mental => '気持ちの波を整える流れ',
      FortuneArea.overall => '今日の優先順位を整える流れ',
    };
  }

  String _moonHouseActionHint(int house, FortuneArea area) {
    if (house == 3) return '連絡、メモ、短い確認を一つ済ませると流れが軽くなります。';
    if (house == 4) return '部屋、食事、家の用事を一つ整えると気持ちが戻りやすいです。';
    if (house == 6) return '休憩、食事、作業時間を一つだけ整えると調子を保ちやすいです。';
    if (house == 10) return '見られる作業を一つ丁寧に仕上げると評価につながりやすいです。';
    if (house == 12) return '人に合わせすぎず、静かな時間を先に確保しましょう。';
    return switch (area) {
      FortuneArea.love => '会話は短く明るく、相手の反応を待つ余白を残しましょう。',
      FortuneArea.work => '最初の15分で一つだけ着手し、終わりの形を決めましょう。',
      FortuneArea.money => '買う前に必要性と予算を確認し、迷うものは一度保留しましょう。',
      FortuneArea.mental => '短い休憩と水分を先に入れ、夜の予定を詰めすぎないようにしましょう。',
      FortuneArea.overall => '一日の中で一番大事な予定を一つだけ先に決めましょう。',
    };
  }

  String _dailyStrongSignalText(HoroscopeReadingContext contextData, FortuneArea area) {
    final returns = contextData.returnsFor(area).toList();
    for (final event in returns) {
      if (event.planet == AstroPlanet.jupiter) {
        final focus = area == FortuneArea.money ? '収入や価値につながる選択' : 'この分野で長く育てたいこと';
        return ' 長期的な拡大の節目が重なる日なので、$focusを一つ始めるのに向きます。';
      }
      if (event.planet == AstroPlanet.saturn) {
        return ' 長期的な見直しの節目なので、急に広げるより続ける仕組みを一つ整えましょう。';
      }
    }
    if (FortuneScoreCalculator.hasTransitGrandTrine(contextData)) {
      return ' 複数の星が調和しやすい配置の日なので、恋愛・金運・仕事のうち今伸ばしたいことを一つ選ぶと追い風を活かせます。';
    }
    final beneficPair = FortuneScoreCalculator.strongestBeneficPair(contextData);
    if (beneficPair != null) {
      final phaseHint = switch (beneficPair.phase) {
        AspectPhase.applying => 'これから追い風が強まりやすいので',
        AspectPhase.exact => '追い風が最も強まりやすいので',
        AspectPhase.separating => '直前からの良い流れを活かしやすいので',
      };
      if (beneficPair.involves(AstroPlanet.jupiter) && beneficPair.involves(AstroPlanet.venus)) {
        return ' $phaseHint、好きなこと・人とのつながり・お金につながる行動を一つ具体化しましょう。';
      }
      return ' $phaseHint、得意なことを人に伝える、または小さく形にする行動が向きます。';
    }
    if (widget.detailed && FortuneScoreCalculator.hasNatalKite(contextData)) {
      return ' 出生図のカイト配置が持つ集中力を活かし、得意なことを具体的な成果へつなげる一歩を選びましょう。';
    }
    final strongAspect =
        contextData.aspectsFor(area).where((aspect) => aspect.orb <= 2.0).toList();
    if (strongAspect.isNotEmpty) {
      return ' この日の影響が強く出やすいので、迷っていることは一つに絞って動くと流れを活かせます。';
    }
    return '';
  }

  String _moonDailyText(HoroscopeReadingContext contextData) {
    final moon = _placement(contextData.transit.placements, AstroPlanet.moon);
    if (moon == null || moon.house < 1 || moon.house > 12) return '';
    final hint = switch (moon.house) {
      4 => ' 居場所を整えると気持ちが落ち着きやすい日です。',
      6 => ' 生活リズムと短い休憩を意識すると調子を保ちやすい日です。',
      12 => ' 一人の時間や睡眠を先に確保すると回復しやすい日です。',
      8 => ' 深く考えすぎず、抱えていることを一つだけ整理すると安心です。',
      _ => '',
    };
    return hint;
  }

  String _transitSign(HoroscopeReadingContext contextData, AstroPlanet planet, String fallback) {
    final placement = _placement(contextData.transit.placements, planet);
    if (placement == null) return fallback;
    final ingress = AstrologyDataSources.current.nextSignIngress(planet, widget.date);
    final ingressText = ingress == null ? '' : ' → ${ingress.sign.label} ${ingress.label}';
    return '${planet.label}: ${placement.sign.label} ${placement.degree.toStringAsFixed(1)}°$ingressText';
  }

  String _natalLabel(HoroscopeReadingContext contextData, AstroPlanet planet, String fallback) {
    final placement = _placement(contextData.natal.placements, planet);
    if (placement == null) return fallback;
    return '出生図の${planet.label}: 第${placement.house}ハウス';
  }

  String _aspectLabel(HoroscopeReadingContext contextData, FortuneArea area, String fallback) {
    final matches = contextData.aspectsFor(area).toList();
    if (matches.isEmpty) return fallback;
    final aspect = matches.first;
    return '現在の${aspect.transitPlanet.label} ${aspect.type.label} 出生図の${aspect.natalPlanet.label}';
  }

  String _houseTransitLabel(
    HoroscopeReadingContext contextData,
    AstroPlanet planet,
    String fallback,
  ) {
    for (final transit in contextData.houseTransits) {
      if (transit.planet == planet) {
        return '${planet.label}が出生図の第${transit.natalHouse}ハウスを通過';
      }
    }
    return fallback;
  }

  PlanetPlacement? _placement(List<PlanetPlacement> placements, AstroPlanet planet) {
    for (final placement in placements) {
      if (placement.planet == planet) return placement;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return _buildGrid(context, aiText: const {}, aiLoading: false);
  }

  Widget _buildGrid(
    BuildContext context, {
    required Map<String, String> aiText,
    required bool aiLoading,
    bool aiFailed = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 720;
            final itemWidth = isWide ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth;

            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _itemsFor(widget.contextData)
                  .map(
                    (item) => SizedBox(
                      width: itemWidth,
                      child: TodayFortuneItemView(
                        item: item,
                        detailed: widget.detailed,
                        profile: widget.profile,
                        details: widget.details,
                        date: widget.date,
                        aiText: aiText[item.title],
                        aiLoading: aiLoading,
                        aiFailed: aiFailed,
                        showAiInline: true,
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ],
    );
  }
}

class AnnualLifeEventBoost {
  const AnnualLifeEventBoost({
    required this.value,
    required this.detail,
    required this.formula,
    required this.areaEffects,
  });

  final double value;
  final String detail;
  final String formula;
  final Map<FortuneArea, double> areaEffects;

  double effectFor(FortuneArea area) => areaEffects[area] ?? 0;
}

class FortuneScoreCalculator {
  static int standardBase(FortuneArea area) => switch (area) {
        FortuneArea.love => 70,
        FortuneArea.work => 74,
        FortuneArea.money => 68,
        FortuneArea.mental => 72,
        FortuneArea.overall => 71,
      };

  const FortuneScoreCalculator._();

  static int dailyOverall(HoroscopeReadingContext contextData) {
    return overallWithReturnBonus(
      [
        dailyArea(contextData, FortuneArea.love, standardBase(FortuneArea.love)),
        dailyArea(contextData, FortuneArea.work, standardBase(FortuneArea.work)),
        dailyArea(contextData, FortuneArea.money, standardBase(FortuneArea.money)),
        dailyArea(contextData, FortuneArea.mental, standardBase(FortuneArea.mental)),
      ],
      contextData,
    );
  }

  static int dailyArea(
    HoroscopeReadingContext contextData,
    FortuneArea area,
    int base,
  ) {
    return dailyAreaBreakdown(contextData, area, base).score;
  }

  static FortuneScoreBreakdown dailyAreaBreakdown(
    HoroscopeReadingContext contextData,
    FortuneArea area,
    int base,
  ) {
    return _scoreBreakdown(
      contextData: contextData,
      area: area,
      date: contextData.transit.date,
      base: base,
      includeAllSignals: false,
    );
  }

  static int periodArea(
    FortuneArea area,
    HoroscopeReadingContext contextData,
    DateTime periodStart,
    int base,
  ) {
    return _scoreBreakdown(
      contextData: contextData,
      area: area,
      date: periodStart,
      base: base,
      includeAllSignals: false,
    ).score;
  }

  static int overallFromAreas(Iterable<int> areaScores) {
    final scores = areaScores.toList();
    if (scores.isEmpty) return 50;
    final total = scores.fold<int>(0, (sum, score) => sum + score);
    return (total / scores.length).round().clamp(50, 99).toInt();
  }

  static int overallWithReturnBonus(
    Iterable<int> areaScores,
    HoroscopeReadingContext contextData,
  ) {
    final average = overallFromAreas(areaScores);
    final bonus = overallReturnBonus(contextData);
    return (average + (bonus?.value ?? 0)).round().clamp(50, 99).toInt();
  }

  static ({AstroPlanet planet, double value, String detail, String formula})? overallReturnBonus(
    HoroscopeReadingContext contextData,
  ) {
    final candidates = <({AstroPlanet planet, double value, String detail, String formula})>[];
    for (final event in contextData.returns) {
      final maximum = switch (event.planet) {
        AstroPlanet.jupiter => 2.2,
        AstroPlanet.saturn => 1.3,
        AstroPlanet.sun => 1.0,
        AstroPlanet.venus || AstroPlanet.mars => 0.6,
        AstroPlanet.mercury => 0.4,
        AstroPlanet.uranus || AstroPlanet.neptune || AstroPlanet.pluto => 0.8,
        AstroPlanet.moon || AstroPlanet.ascendant || AstroPlanet.midheaven => 0.0,
      };
      if (maximum == 0) continue;
      final isOuter = event.planet == AstroPlanet.uranus ||
          event.planet == AstroPlanet.neptune ||
          event.planet == AstroPlanet.pluto;
      if (isOuter && event.orb > 2.0) continue;
      final closeness = isOuter
          ? ((2.0 - event.orb) / 2.0).clamp(0.0, 1.0).toDouble()
          : ((event.window - event.orb) / event.window).clamp(0.0, 1.0).toDouble();
      final phaseWeight = switch (event.phase) {
        AspectPhase.applying => 0.78,
        AspectPhase.exact => 1.0,
        AspectPhase.separating => 0.52,
      };
      final value = maximum * closeness * phaseWeight;
      if (value < 0.05) continue;
      candidates.add((
        planet: event.planet,
        value: value,
        detail: '第${event.natalHouse}ハウス / オーブ${event.orb.toStringAsFixed(1)}° / ${event.phase.label}',
        formula: '星別上限${maximum.toStringAsFixed(1)} × 近さ係数${closeness.toStringAsFixed(2)} × 位相係数${phaseWeight.toStringAsFixed(2)}（最強1件のみ）',
      ));
    }
    if (candidates.isEmpty) return null;
    candidates.sort((left, right) => right.value.compareTo(left.value));
    return candidates.first;
  }

  /// 週・月では、平均に埋もれる「正確なリターン直前/直後」の山だけを示す。
  /// 日運の通常補正とは別で、総合運に一度だけ加える。木星は12年に一度のため
  /// 最も大きく、土星・外惑星は人生テーマとしては重くても点数は穏やかにする。
  static ({AstroPlanet planet, double value, String detail, String formula})? periodReturnPeakBonus(
    Iterable<HoroscopeReadingContext> contexts,
  ) {
    final candidates = <({AstroPlanet planet, double value, String detail, String formula})>[];
    for (final context in contexts) {
      for (final event in context.returns) {
        final maximum = switch (event.planet) {
          AstroPlanet.jupiter => 7.5,
          AstroPlanet.saturn => 3.5,
          AstroPlanet.uranus || AstroPlanet.neptune || AstroPlanet.pluto => 2.4,
          AstroPlanet.sun => 1.4,
          AstroPlanet.venus || AstroPlanet.mars => 1.0,
          AstroPlanet.mercury => 0.7,
          AstroPlanet.moon || AstroPlanet.ascendant || AstroPlanet.midheaven => 0.0,
        };
        if (maximum == 0) continue;
        // 4度以内だけをピーク扱いにする。広いリターン窓全体を底上げしない。
        final closeness = ((4.0 - event.orb) / 4.0).clamp(0.0, 1.0).toDouble();
        if (closeness <= 0) continue;
        final phaseWeight = switch (event.phase) {
          AspectPhase.applying => 0.90,
          AspectPhase.exact => 1.0,
          AspectPhase.separating => 0.70,
        };
        final value = maximum * closeness * phaseWeight;
        if (value < 0.25) continue;
        candidates.add((
          planet: event.planet,
          value: value,
          detail: '${context.transit.date.month}/${context.transit.date.day}頃・第${event.natalHouse}ハウス・オーブ${event.orb.toStringAsFixed(1)}°・${event.phase.label}',
          formula: '期間ピーク: ${event.planet.label}上限${maximum.toStringAsFixed(1)} × 4°以内の近さ${closeness.toStringAsFixed(2)} × 位相${phaseWeight.toStringAsFixed(2)}（最強1件のみ）',
        ));
      }
    }
    if (candidates.isEmpty) return null;
    candidates.sort((left, right) => right.value.compareTo(left.value));
    return candidates.first;
  }

  /// 年運では、24時点の平均で埋もれやすい「節目」だけを最強1件に絞って示す。
  /// 日・週・月には使わず、通常のリターン・アスペクト点とは別の年専用補正。
  static AnnualLifeEventBoost? annualLifeEventBoost(
    Iterable<HoroscopeReadingContext> contexts,
  ) {
    final candidates = <({double value, String detail, String formula, Map<FortuneArea, double> areaEffects})>[];
    String dateLabel(DateTime date) => '${date.month}/${date.day}';
    for (final context in contexts) {
      for (final event in context.returns) {
        final isOuterPlanet = event.planet == AstroPlanet.uranus ||
            event.planet == AstroPlanet.neptune ||
            event.planet == AstroPlanet.pluto;
        // 外惑星リターンは年単位では長く表示されるため、通常のリターン判定と
        // 同じく十分にタイトな期間だけを「人生イベント」として扱う。
        if (isOuterPlanet && event.orb > 2.0) continue;
        final maximum = switch (event.planet) {
          AstroPlanet.jupiter => 3.2,
          AstroPlanet.saturn => 2.5,
          AstroPlanet.uranus || AstroPlanet.neptune || AstroPlanet.pluto => 2.0,
          AstroPlanet.sun => 1.2,
          AstroPlanet.venus || AstroPlanet.mars => 1.0,
          AstroPlanet.mercury => 0.7,
          AstroPlanet.moon || AstroPlanet.ascendant || AstroPlanet.midheaven => 0.0,
        };
        if (maximum == 0) continue;
        final closeness = ((event.window - event.orb) / event.window).clamp(0.0, 1.0).toDouble();
        final phaseWeight = switch (event.phase) {
          AspectPhase.applying => 0.84,
          AspectPhase.exact => 1.0,
          AspectPhase.separating => 0.62,
        };
        final value = maximum * closeness * phaseWeight;
        if (value >= 0.15) {
          candidates.add((
            value: value,
            detail: '${dateLabel(context.transit.date)}頃の${event.planet.label}リターン（第${event.natalHouse}ハウス、オーブ${event.orb.toStringAsFixed(1)}°）',
            formula: '年専用: ${event.planet.label}の節目上限${maximum.toStringAsFixed(1)} × 近さ${closeness.toStringAsFixed(2)} × 位相${phaseWeight.toStringAsFixed(2)}（最強1件、上限+3.5）',
            areaEffects: _annualReturnAreaEffects(event, value),
          ));
        }
      }
      // 表示用の上位8件ではなく全アスペクトを対象にする。これで、強いMC/ASC
      // だけでなく太陽・月・各天体への長期トランジットも年運から漏れない。
      for (final aspect in context.fullAspects) {
        if (aspect.orb > 1.5) continue;
        final planetWeight = switch (aspect.transitPlanet) {
          AstroPlanet.jupiter => 2.4,
          AstroPlanet.saturn => 1.9,
          AstroPlanet.uranus || AstroPlanet.neptune || AstroPlanet.pluto => 1.7,
          _ => 0.0,
        };
        final aspectWeight = switch (aspect.type) {
          AspectType.trine => 1.0,
          AspectType.sextile => 0.85,
          AspectType.conjunction => 0.70,
          AspectType.square || AspectType.opposition => 0.0,
        };
        final closeness = ((1.5 - aspect.orb) / 1.5).clamp(0.0, 1.0).toDouble();
        final value = planetWeight * aspectWeight * closeness;
        if (value >= 0.15) {
          candidates.add((
            value: value,
            detail: '${dateLabel(context.transit.date)}頃の${aspect.transitPlanet.label}${aspect.type.label}出生図の${aspect.natalPlanet.label}（オーブ${aspect.orb.toStringAsFixed(1)}°）',
            formula: '年専用: ${aspect.natalPlanet.label}への長期トランジット上限${planetWeight.toStringAsFixed(1)} × 調和角係数${aspectWeight.toStringAsFixed(2)} × 近さ${closeness.toStringAsFixed(2)}（最強1件、分野別に配分）',
            areaEffects: _annualAspectAreaEffects(aspect, value),
          ));
        }
      }
      for (final label in _rarePatternLabels(context.transit.placements)) {
        final value = switch (label) {
          'グランドセクスタイル' => 1.4,
          'ミスティックレクタングル（ダイヤモンド）' => 0.9,
          'クレイドル（ゆりかご）' => 0.7,
          'グランドトライン' => 0.7,
          'カイト' => 0.8,
          _ => 0.0,
        };
        if (value > 0) {
          candidates.add((
            value: value,
            detail: '${dateLabel(context.transit.date)}頃の$label',
            formula: '年専用: 良いレア配置の節目補正+${value.toStringAsFixed(1)}（最強1件、上限+3.5）',
            areaEffects: _annualRarePatternAreaEffects(label, value),
          ));
        }
      }
    }
    if (candidates.isEmpty) return null;
    candidates.sort((left, right) => right.value.compareTo(left.value));
    final best = candidates.first;
    final normalizedEffects = <FortuneArea, double>{
      for (final area in const [
        FortuneArea.love,
        FortuneArea.work,
        FortuneArea.money,
        FortuneArea.mental,
      ])
        area: best.areaEffects[area]?.clamp(0.0, 3.5).toDouble() ?? 0,
    };
    final overallEffect = normalizedEffects.values.fold<double>(0, (sum, value) => sum + value) /
        normalizedEffects.length;
    return AnnualLifeEventBoost(
      value: overallEffect.clamp(0.0, 3.5).toDouble(),
      detail: best.detail,
      formula: best.formula,
      areaEffects: normalizedEffects,
    );
  }

  static Map<FortuneArea, double> _annualReturnAreaEffects(
    PlanetReturnEvent event,
    double value,
  ) => _scaledAnnualEffects(
        switch (event.planet) {
          AstroPlanet.sun => const {FortuneArea.work: 0.55, FortuneArea.mental: 0.45},
          AstroPlanet.moon => const {FortuneArea.love: 0.35, FortuneArea.mental: 1.0},
          AstroPlanet.mercury => const {FortuneArea.work: 1.0, FortuneArea.money: 0.25},
          AstroPlanet.venus => const {FortuneArea.love: 1.0, FortuneArea.money: 0.45},
          AstroPlanet.mars => const {FortuneArea.love: 0.45, FortuneArea.work: 0.8, FortuneArea.mental: 0.2},
          AstroPlanet.jupiter => const {FortuneArea.work: 0.45, FortuneArea.money: 1.0, FortuneArea.mental: 0.15},
          AstroPlanet.saturn => const {FortuneArea.work: 1.0, FortuneArea.mental: 0.5},
          AstroPlanet.uranus => const {FortuneArea.work: 0.6, FortuneArea.mental: 0.65},
          AstroPlanet.neptune => const {FortuneArea.love: 0.35, FortuneArea.mental: 0.85},
          AstroPlanet.pluto => const {FortuneArea.work: 0.65, FortuneArea.money: 0.2, FortuneArea.mental: 0.8},
          AstroPlanet.ascendant || AstroPlanet.midheaven => const {},
        },
        value,
      );

  static Map<FortuneArea, double> _annualAspectAreaEffects(
    TransitAspect aspect,
    double value,
  ) => _scaledAnnualEffects(
        switch (aspect.natalPlanet) {
          AstroPlanet.ascendant => const {FortuneArea.love: 0.25, FortuneArea.work: 0.15, FortuneArea.mental: 1.0},
          AstroPlanet.midheaven => const {FortuneArea.work: 1.25, FortuneArea.money: 0.3},
          AstroPlanet.sun => const {FortuneArea.work: 0.55, FortuneArea.mental: 0.55},
          AstroPlanet.moon => const {FortuneArea.love: 0.4, FortuneArea.mental: 1.0},
          AstroPlanet.mercury => const {FortuneArea.work: 1.0, FortuneArea.money: 0.35},
          AstroPlanet.venus => const {FortuneArea.love: 1.0, FortuneArea.money: 0.55},
          AstroPlanet.mars => const {FortuneArea.love: 0.35, FortuneArea.work: 1.0, FortuneArea.mental: 0.3},
          AstroPlanet.jupiter => const {FortuneArea.work: 0.45, FortuneArea.money: 1.0, FortuneArea.mental: 0.15},
          AstroPlanet.saturn => const {FortuneArea.work: 0.85, FortuneArea.mental: 0.6},
          AstroPlanet.uranus => const {FortuneArea.work: 0.55, FortuneArea.mental: 0.7},
          AstroPlanet.neptune => const {FortuneArea.love: 0.35, FortuneArea.mental: 0.9},
          AstroPlanet.pluto => const {FortuneArea.work: 0.55, FortuneArea.money: 0.2, FortuneArea.mental: 0.85},
        },
        value,
      );

  static Map<FortuneArea, double> _annualRarePatternAreaEffects(
    String label,
    double value,
  ) => _scaledAnnualEffects(
        switch (label) {
          'グランドセクスタイル' => const {
              FortuneArea.love: 0.8,
              FortuneArea.work: 1.0,
              FortuneArea.money: 0.9,
              FortuneArea.mental: 0.8,
            },
          'ミスティックレクタングル（ダイヤモンド）' => const {
              FortuneArea.love: 0.55,
              FortuneArea.work: 0.75,
              FortuneArea.money: 0.55,
              FortuneArea.mental: 1.0,
            },
          'クレイドル（ゆりかご）' => const {
              FortuneArea.love: 0.65,
              FortuneArea.work: 0.35,
              FortuneArea.money: 0.35,
              FortuneArea.mental: 1.0,
            },
          'グランドトライン' => const {
              FortuneArea.love: 0.55,
              FortuneArea.work: 0.7,
              FortuneArea.money: 0.55,
              FortuneArea.mental: 0.7,
            },
          'カイト' => const {
              FortuneArea.love: 0.5,
              FortuneArea.work: 1.0,
              FortuneArea.money: 0.6,
              FortuneArea.mental: 0.6,
            },
          _ => const {},
        },
        value,
      );

  static Map<FortuneArea, double> _scaledAnnualEffects(
    Map<FortuneArea, double> weights,
    double value,
  ) => {
        for (final entry in weights.entries) entry.key: value * entry.value,
      };

  static FortuneScoreBreakdown _scoreBreakdown({
    required HoroscopeReadingContext contextData,
    required FortuneArea area,
    required DateTime date,
    required int base,
    required bool includeAllSignals,
  }) {
    var value = base.toDouble();
    final factors = <FortuneScoreFactor>[];
    void add(String label, double adjustment, {String? detail, String? formula}) {
      if (adjustment.abs() < 0.05) return;
      value += adjustment;
      factors.add(FortuneScoreFactor(label: label, value: adjustment, detail: detail, formula: formula));
    }
    final aspects = includeAllSignals
        ? contextData.aspects
        : contextData.aspectsFor(area).toList();
    final aspectLimit = includeAllSignals ? 5 : 3;
    for (final aspect in aspects.take(aspectLimit)) {
      final calculation = _aspectCalculation(aspect);
      add(
        '${aspect.transitPlanet.label}${aspect.type.label}出生図の${aspect.natalPlanet.label}',
        calculation.value,
        detail: 'オーブ${aspect.orb.toStringAsFixed(1)}° / ${_aspectPhaseLabel(contextData, aspect)}',
        formula: calculation.formula,
      );
    }

    final returns = includeAllSignals
        ? contextData.returns
        : contextData.returnsFor(area).toList();
    for (final event in returns.take(includeAllSignals ? 2 : 1)) {
      final calculation = _returnCalculation(event, area, contextData);
      add(
        '${event.planet.label}リターン',
        calculation.value,
        detail: '第${event.natalHouse}ハウス / オーブ${event.orb.toStringAsFixed(1)}° / ${event.phase.label}',
        formula: calculation.formula,
      );
    }

    final houseTransits = includeAllSignals
        ? contextData.houseTransitsFor(FortuneArea.overall).toList()
        : contextData.houseTransitsFor(area).toList();
    if (houseTransits.isNotEmpty) {
      final pulse = _housePulse(houseTransits, date, area);
      add(
        'ハウス通過',
        pulse.toDouble(),
        detail: houseTransits.take(2).map((item) => '${item.planet.label} 第${item.natalHouse}ハウス').join(' / '),
        formula: '対象ハウスの定数補正を最大2天体分まで合算',
      );
    }

    final signDignity = _planetarySignDignityPulse(
      contextData,
      area,
      aspects: aspects.take(aspectLimit),
      returns: returns.take(includeAllSignals ? 2 : 1),
      houseTransits: houseTransits,
    );
    if (signDignity.value != 0) {
      add(
        '天体のサイン品位',
        signDignity.value,
        detail: signDignity.detail,
        formula: signDignity.formula,
      );
    }

    add('出生図の月との響き', _natalMoonPulse(contextData, area).toDouble());
    add('月のハウス通過', _moonHousePulse(contextData, area));
    final lunarPhase = _lunarPhasePulse(contextData, area);
    if (lunarPhase.value != 0) {
      add(
        '月相（${lunarPhase.label}）',
        lunarPhase.value,
        detail: lunarPhase.detail,
        formula: '月相ごとの分野別補正（吉凶を一律にせず、最大±1.2点）',
      );
    }
    add(
      '空の星同士のアスペクト',
      _transitPairPulse(contextData, area),
      formula: 'アスペクト、オーブ、位相、ハウス重み、出生図感受性を合算',
    );
    add('グランドトライン', _grandTrinePulse(contextData, area));
    add('出生図のステリウム', _natalStelliumPulse(contextData, area));
    add('出生図のカイト', _natalPatternPulse(contextData, area));
    final rarePatterns = _rarePatternLabels(contextData.transit.placements);
    final rarePatternPulse = _rarePatternPulse(rarePatterns, area);
    if (rarePatternPulse != 0) {
      add('空のレア配置', rarePatternPulse, detail: rarePatterns.join('・'), formula: 'レア配置ごとの分野別補正（上限あり）');
    }
    add('金星支配の感受性', _venusRulerSensitivityPulse(contextData, area));
    final retrogradePulse = _retrogradePulse(contextData, area);
    if (retrogradePulse != 0) {
      add(
        '逆行中の星',
        retrogradePulse,
        detail: contextData.retrogradePlanets.map((planet) => planet.label).join('・'),
        formula: '分野に関係する逆行星の見直し補正（重ね掛けはせず合算上限あり）',
      );
    }

    final voidMoon = contextData.transit.voidMoon;
    if (voidMoon != null) {
      final dayShare = voidMoon.dayShare(contextData.transit.date);
      final penalty = switch (area) {
        FortuneArea.mental => 4.0,
        FortuneArea.love => 3.0,
        FortuneArea.work || FortuneArea.money => 2.0,
        FortuneArea.overall => 2.5,
      };
      add(
        '月ボイド',
        -(penalty * dayShare),
        detail: '${voidMoon.label} / 対象日の${(dayShare * 100).round()}%',
        formula: '基本-${penalty.toStringAsFixed(1)} × 日内割合${dayShare.toStringAsFixed(2)}',
      );
    }

    return FortuneScoreBreakdown(
      base: base,
      factors: factors,
      rawScore: value,
      score: value.round().clamp(50, 99).toInt(),
    );
  }

  /// 月相は一律の吉凶ではなく、各段階で進めやすい分野だけを穏やかに補正する。
  /// 月の星座・出生図とのアスペクト・ハウス通過は別の要因として既に計上する。
  static ({String label, String detail, double value}) _lunarPhasePulse(
    HoroscopeReadingContext contextData,
    FortuneArea area,
  ) {
    final sun = _placement(contextData.transit.placements, AstroPlanet.sun);
    final moon = _placement(contextData.transit.placements, AstroPlanet.moon);
    if (sun == null || moon == null) return (label: '月相', detail: '月相データなし', value: 0);
    final elongation = ((_planetLongitude(moon) - _planetLongitude(sun)) + 360) % 360;
    final phase = switch (elongation) {
      < 22.5 || >= 337.5 => '新月',
      < 67.5 => '満ちていく三日月',
      < 112.5 => '上弦の月',
      < 157.5 => '満ちていく凸月',
      < 202.5 => '満月',
      < 247.5 => '欠けていく凸月',
      < 292.5 => '下弦の月',
      _ => '欠けていく三日月',
    };
    final value = switch (phase) {
      '新月' => switch (area) {
          FortuneArea.work => 0.8,
          FortuneArea.love => 0.6,
          FortuneArea.money => 0.4,
          FortuneArea.mental => 0.9,
          FortuneArea.overall => 0.7,
        },
      '満ちていく三日月' => switch (area) {
          FortuneArea.work => 0.6,
          FortuneArea.love => 0.4,
          FortuneArea.money => 0.5,
          FortuneArea.mental => 0.4,
          FortuneArea.overall => 0.5,
        },
      '上弦の月' => switch (area) {
          FortuneArea.work => 1.1,
          FortuneArea.love => 0.5,
          FortuneArea.money => 0.7,
          FortuneArea.mental => 0.2,
          FortuneArea.overall => 0.6,
        },
      '満ちていく凸月' => switch (area) {
          FortuneArea.work => 0.7,
          FortuneArea.love => 0.5,
          FortuneArea.money => 0.8,
          FortuneArea.mental => 0.3,
          FortuneArea.overall => 0.6,
        },
      '満月' => switch (area) {
          FortuneArea.work => 0.4,
          FortuneArea.love => 1.1,
          FortuneArea.money => 0.3,
          FortuneArea.mental => 1.2,
          FortuneArea.overall => 0.7,
        },
      '欠けていく凸月' => switch (area) {
          FortuneArea.work => 0.2,
          FortuneArea.love => 0.7,
          FortuneArea.money => 0.3,
          FortuneArea.mental => 0.8,
          FortuneArea.overall => 0.5,
        },
      '下弦の月' => switch (area) {
          FortuneArea.work => -0.3,
          FortuneArea.love => 0.2,
          FortuneArea.money => -0.2,
          FortuneArea.mental => 0.9,
          FortuneArea.overall => 0.2,
        },
      _ => switch (area) {
          FortuneArea.work => -0.2,
          FortuneArea.love => 0.1,
          FortuneArea.money => -0.1,
          FortuneArea.mental => 0.7,
          FortuneArea.overall => 0.1,
        },
    };
    final detail = switch (phase) {
      '新月' => '始める・意図を決める流れ',
      '満ちていく三日月' => '小さく続けて土台を育てる流れ',
      '上弦の月' => '行動に移して進み具合を確かめる流れ',
      '満ちていく凸月' => '仕上げ前の準備を整える流れ',
      '満月' => '結果や気持ちを受け取り、振り返る流れ',
      '欠けていく凸月' => '成果を分け合い、役目を整理する流れ',
      '下弦の月' => '不要な負担を手放し、次へ備える流れ',
      _ => '休息と整理で次の新月へ備える流れ',
    };
    return (label: phase, detail: detail, value: value);
  }

  static Map<String, Object?> lunarPhaseScoreEffects(HoroscopeReadingContext contextData) {
    Map<String, Object?> factor(FortuneArea area) {
      final pulse = _lunarPhasePulse(contextData, area);
      return {'value': double.parse(pulse.value.toStringAsFixed(1)), 'detail': pulse.detail};
    }
    final representative = _lunarPhasePulse(contextData, FortuneArea.overall);
    return {
      'phase_label': representative.label,
      'formula': '月相ごとの分野別補正。吉凶を一律にせず、最大±1.2点。月の星座・出生図とのアスペクト・ハウス通過は別途計上。',
      'areas': {
        'love': factor(FortuneArea.love),
        'work': factor(FortuneArea.work),
        'money': factor(FortuneArea.money),
        'mental': factor(FortuneArea.mental),
      },
    };
  }

  static _ScoreCalculation _returnCalculation(
    PlanetReturnEvent event,
    FortuneArea area,
    HoroscopeReadingContext contextData,
  ) {
    final planetBase = switch (event.planet) {
      AstroPlanet.jupiter => 8.0,
      AstroPlanet.saturn => switch (area) {
        FortuneArea.work => 5.0,
        FortuneArea.money => 1.5,
        FortuneArea.overall => 2.0,
        FortuneArea.love => -2.0,
        FortuneArea.mental => -1.0,
      },
      AstroPlanet.sun || AstroPlanet.moon => 3.0,
      _ => 2.5,
    };
    var houseBonus = 0.0;
    if (event.planet != AstroPlanet.saturn &&
        event.planet == AstroPlanet.jupiter &&
        (event.natalHouse == 1 || event.natalHouse == 5 || event.natalHouse == 9)) {
      houseBonus = 3.0;
    } else if (event.planet != AstroPlanet.saturn &&
        area == FortuneArea.money && (event.natalHouse == 2 || event.natalHouse == 8)) {
      houseBonus = 3.0;
    } else if (event.planet != AstroPlanet.saturn && area == FortuneArea.love && event.natalHouse == 7) {
      houseBonus = 2.5;
    } else if (event.planet != AstroPlanet.saturn && area == FortuneArea.work &&
        (event.natalHouse == 6 || event.natalHouse == 10)) {
      houseBonus = 2.5;
    } else if (event.planet != AstroPlanet.saturn && area == FortuneArea.mental &&
        (event.natalHouse == 4 || event.natalHouse == 6 || event.natalHouse == 12)) {
      houseBonus = 2.0;
    }
    final closeness = ((event.window - event.orb) / event.window).clamp(0.0, 1.0).toDouble();
    final phaseWeight = switch (event.phase) {
      AspectPhase.applying => 0.9,
      AspectPhase.exact => 1.2,
      AspectPhase.separating => event.planet == AstroPlanet.jupiter || event.planet == AstroPlanet.saturn
          ? 0.72
          : 0.52,
    };
    final sensitivity = _natalTransitSensitivity(contextData, area, {event.planet});
    final orbWeight = 0.45 + closeness * 0.55;
    final value = (planetBase + houseBonus) * orbWeight * phaseWeight * sensitivity;
    return _ScoreCalculation(
      value,
      '(基礎${planetBase.toStringAsFixed(1)} + ハウス${houseBonus.toStringAsFixed(1)}) × オーブ係数${orbWeight.toStringAsFixed(2)} × 位相係数${phaseWeight.toStringAsFixed(2)} × 出生図係数${sensitivity.toStringAsFixed(2)}',
    );
  }

  static double _venusRulerSensitivityPulse(
    HoroscopeReadingContext contextData,
    FortuneArea area,
  ) {
    if (area != FortuneArea.love && area != FortuneArea.money) return 0;
    final sun = _placement(contextData.natal.placements, AstroPlanet.sun);
    final asc = _placement(contextData.natal.placements, AstroPlanet.ascendant);
    final venusRuled = [sun, asc].any(
      (placement) => placement != null &&
          (placement.sign == ZodiacSign.taurus || placement.sign == ZodiacSign.libra),
    );
    if (!venusRuled) return 0;
    final venusActive = contextData.returns.any((event) => event.planet == AstroPlanet.venus) ||
        contextData.aspects.any(
          (aspect) => aspect.transitPlanet == AstroPlanet.venus || aspect.natalPlanet == AstroPlanet.venus,
        ) ||
        contextData.transitPairAspects.any((aspect) => aspect.involves(AstroPlanet.venus));
    return venusActive ? (area == FortuneArea.love ? 2.2 : 1.7) : 0;
  }

  /// 逆行は吉凶の断定ではなく、進め方を見直す必要がある分だけ
  /// 点数へ穏やかに補正する。全惑星を対象にし、過大に下げない。
  static double _retrogradePulse(
    HoroscopeReadingContext contextData,
    FortuneArea area,
  ) {
    var pulse = 0.0;
    for (final planet in contextData.retrogradePlanets) {
      pulse += switch (planet) {
        AstroPlanet.mercury => switch (area) {
            FortuneArea.work => -1.8,
            FortuneArea.money => -1.0,
            FortuneArea.love => -0.7,
            _ => -0.4,
          },
        AstroPlanet.venus => switch (area) {
            FortuneArea.love => -1.5,
            FortuneArea.money => -1.4,
            _ => -0.4,
          },
        AstroPlanet.mars => switch (area) {
            FortuneArea.work || FortuneArea.mental => -1.1,
            FortuneArea.love => -0.8,
            _ => -0.5,
          },
        AstroPlanet.jupiter => switch (area) {
            FortuneArea.money || FortuneArea.overall => -1.0,
            _ => -0.4,
          },
        AstroPlanet.saturn => switch (area) {
            FortuneArea.work => -1.6,
            FortuneArea.mental => -1.0,
            FortuneArea.overall => -0.8,
            _ => -0.4,
          },
        AstroPlanet.uranus => area == FortuneArea.work || area == FortuneArea.overall ? -0.7 : -0.3,
        AstroPlanet.neptune => area == FortuneArea.mental || area == FortuneArea.overall ? -0.7 : -0.3,
        AstroPlanet.pluto => area == FortuneArea.overall || area == FortuneArea.mental ? -0.6 : -0.25,
        AstroPlanet.sun || AstroPlanet.moon || AstroPlanet.ascendant || AstroPlanet.midheaven => 0.0,
      };
    }
    return pulse.clamp(-3.5, 0.0).toDouble();
  }

  static _ScoreCalculation _aspectCalculation(TransitAspect aspect) {
    double base;
    switch (aspect.type) {
      case AspectType.conjunction:
        base = 4.0;
        break;
      case AspectType.sextile:
        base = 3.5;
        break;
      case AspectType.square:
        base = -5.0;
        break;
      case AspectType.trine:
        base = 6.0;
        break;
      case AspectType.opposition:
        base = -2.5;
        break;
    }
    final exactness = ((6.0 - aspect.orb) / 6.0).clamp(0.0, 1.0).toDouble();
    final orbWeight = 0.45 + exactness * 0.75;
    return _ScoreCalculation(
      base * orbWeight,
      '基礎${base >= 0 ? '+' : ''}${base.toStringAsFixed(1)} × オーブ係数${orbWeight.toStringAsFixed(2)}',
    );
  }

  static String _aspectPhaseLabel(HoroscopeReadingContext contextData, TransitAspect aspect) {
    if (aspect.orb <= 0.7) return 'ピーク';
    final next = contextData.nextAspects.where(
      (item) =>
          item.transitPlanet == aspect.transitPlanet &&
          item.natalPlanet == aspect.natalPlanet &&
          item.type == aspect.type,
    );
    if (next.isEmpty) return '指定日';
    return next.first.orb < aspect.orb ? '接近中' : '余韻';
  }

  static int _housePulse(
    List<HouseTransit> transits,
    DateTime date,
    FortuneArea area,
  ) {
    var pulse = 0.0;
    for (final transit in transits.take(2)) {
      final house = transit.natalHouse;
      final houseValue = switch (area) {
        FortuneArea.love => switch (house) {
            5 => 3.5,
            7 => 4.0,
            8 => 2.0,
            12 => -2.0,
            _ => 0.0,
          },
        FortuneArea.work => switch (house) {
            6 => 3.5,
            10 => 4.5,
            11 => 2.5,
            12 => -2.0,
            _ => 0.0,
          },
        FortuneArea.money => switch (house) {
            2 => 4.0,
            8 => 3.5,
            11 => 2.5,
            12 => -2.0,
            _ => 0.0,
          },
        FortuneArea.mental => switch (house) {
            4 => 3.5,
            6 => 2.0,
            12 => 3.5,
            8 => -2.0,
            _ => 0.0,
          },
        FortuneArea.overall => switch (house) {
            1 => 2.5,
            5 => 2.0,
            9 => 3.0,
            10 => 3.0,
            _ => 0.0,
          },
      };
      pulse += houseValue;
    }
    return pulse.round().clamp(-4, 5).toInt();
  }

  static int _natalMoonPulse(HoroscopeReadingContext contextData, FortuneArea area) {
    final transitMoon = _placement(contextData.transit.placements, AstroPlanet.moon);
    final natalMoon = _placement(contextData.natal.placements, AstroPlanet.moon);
    if (transitMoon == null || natalMoon == null) return 0;
    final signDistance = (transitMoon.sign.index - natalMoon.sign.index).abs() % 12;
    int pulse;
    switch (signDistance) {
      case 0:
        pulse = 4;
        break;
      case 1:
      case 11:
        pulse = 1;
        break;
      case 2:
      case 10:
        pulse = 3;
        break;
      case 3:
      case 9:
        pulse = -3;
        break;
      case 4:
      case 8:
        pulse = 3;
        break;
      case 5:
      case 7:
        pulse = -1;
        break;
      case 6:
        pulse = -4;
        break;
      default:
        pulse = 0;
        break;
    }
    if (area == FortuneArea.mental) return pulse;
    if (area == FortuneArea.overall) return (pulse / 2).round();
    return (pulse / 3).round();
  }

  /// 伝統的な7天体だけを対象に、その天体が実際の主要要因になった日だけ
  /// サイン上の働きやすさを穏やかに補正する。外惑星へは流派差のある固定評価を置かない。
  static ({double value, String detail, String formula}) _planetarySignDignityPulse(
    HoroscopeReadingContext contextData,
    FortuneArea area, {
    required Iterable<TransitAspect> aspects,
    required Iterable<PlanetReturnEvent> returns,
    required Iterable<HouseTransit> houseTransits,
  }) {
    final activation = <AstroPlanet, double>{};
    void activate(AstroPlanet planet, double weight) {
      if (!_usesTraditionalDignity(planet)) return;
      final previous = activation[planet] ?? 0.0;
      if (weight > previous) activation[planet] = weight;
    }

    for (final aspect in aspects) {
      activate(aspect.transitPlanet, 1.00);
    }
    for (final event in returns) {
      activate(event.planet, 0.85);
    }
    for (final transit in houseTransits) {
      if (_hasScoredHouseForArea(area, transit.natalHouse)) {
        activate(transit.planet, 0.65);
      }
    }

    var value = 0.0;
    final details = <String>[];
    for (final entry in activation.entries) {
      final placement = _placement(contextData.transit.placements, entry.key);
      if (placement == null) continue;
      final dignity = _essentialDignity(entry.key, placement.sign);
      if (dignity == null) continue;
      value += dignity.value * entry.value;
      details.add('${entry.key.label}${placement.sign.label}:${dignity.label}×${entry.value.toStringAsFixed(2)}');
    }
    final bounded = value.clamp(-1.4, 1.4).toDouble();
    return (
      value: bounded,
      detail: details.isEmpty ? '主要天体に支配・高揚・損傷・フォール該当なし' : details.join(' / '),
      formula: '伝統7天体の支配+0.80・高揚+0.55・損傷-0.55・フォール-0.75 × 主要要因係数（アスペクト1.00・リターン0.85・有効ハウス0.65）。同一天体は最も強い1件、合計は-1.4〜+1.4点',
    );
  }

  static ({double value, String detail, String formula}) planetarySignDignityFor(
    HoroscopeReadingContext contextData,
    FortuneArea area,
  ) => _planetarySignDignityPulse(
        contextData,
        area,
        aspects: contextData.aspectsFor(area).take(3),
        returns: contextData.returnsFor(area).take(1),
        houseTransits: contextData.houseTransitsFor(area),
      );

  static Map<String, Object?> planetarySignDignityEffects(
    HoroscopeReadingContext contextData,
  ) {
    Map<String, Object?> factor(FortuneArea area) {
      final pulse = planetarySignDignityFor(contextData, area);
      return {
        'value': double.parse(pulse.value.toStringAsFixed(2)),
        'detail': pulse.detail,
      };
    }

    return {
      'formula': '伝統7天体の支配+0.80・高揚+0.55・損傷-0.55・フォール-0.75に、アスペクト1.00・リターン0.85・有効ハウス0.65の主要要因係数を掛ける。同一天体は最強1件、分野ごとの合計は-1.4〜+1.4点。外惑星は固定品位点なし。',
      'areas': {
        'love': factor(FortuneArea.love),
        'work': factor(FortuneArea.work),
        'money': factor(FortuneArea.money),
        'mental': factor(FortuneArea.mental),
      },
    };
  }

  static bool _usesTraditionalDignity(AstroPlanet planet) => switch (planet) {
        AstroPlanet.sun ||
        AstroPlanet.moon ||
        AstroPlanet.mercury ||
        AstroPlanet.venus ||
        AstroPlanet.mars ||
        AstroPlanet.jupiter ||
        AstroPlanet.saturn => true,
        AstroPlanet.uranus ||
        AstroPlanet.neptune ||
        AstroPlanet.pluto ||
        AstroPlanet.ascendant ||
        AstroPlanet.midheaven => false,
      };

  static ({String label, double value})? _essentialDignity(
    AstroPlanet planet,
    ZodiacSign sign,
  ) {
    final domicile = switch (planet) {
      AstroPlanet.sun => {ZodiacSign.leo},
      AstroPlanet.moon => {ZodiacSign.cancer},
      AstroPlanet.mercury => {ZodiacSign.gemini, ZodiacSign.virgo},
      AstroPlanet.venus => {ZodiacSign.taurus, ZodiacSign.libra},
      AstroPlanet.mars => {ZodiacSign.aries, ZodiacSign.scorpio},
      AstroPlanet.jupiter => {ZodiacSign.sagittarius, ZodiacSign.pisces},
      AstroPlanet.saturn => {ZodiacSign.capricorn, ZodiacSign.aquarius},
      _ => <ZodiacSign>{},
    };
    final exaltation = switch (planet) {
      AstroPlanet.sun => ZodiacSign.aries,
      AstroPlanet.moon => ZodiacSign.taurus,
      AstroPlanet.mercury => ZodiacSign.virgo,
      AstroPlanet.venus => ZodiacSign.pisces,
      AstroPlanet.mars => ZodiacSign.capricorn,
      AstroPlanet.jupiter => ZodiacSign.cancer,
      AstroPlanet.saturn => ZodiacSign.libra,
      _ => null,
    };
    final detriment = switch (planet) {
      AstroPlanet.sun => {ZodiacSign.aquarius},
      AstroPlanet.moon => {ZodiacSign.capricorn},
      AstroPlanet.mercury => {ZodiacSign.sagittarius, ZodiacSign.pisces},
      AstroPlanet.venus => {ZodiacSign.aries, ZodiacSign.scorpio},
      AstroPlanet.mars => {ZodiacSign.libra, ZodiacSign.taurus},
      AstroPlanet.jupiter => {ZodiacSign.gemini, ZodiacSign.virgo},
      AstroPlanet.saturn => {ZodiacSign.cancer, ZodiacSign.leo},
      _ => <ZodiacSign>{},
    };
    final fall = switch (planet) {
      AstroPlanet.sun => ZodiacSign.libra,
      AstroPlanet.moon => ZodiacSign.scorpio,
      AstroPlanet.mercury => ZodiacSign.pisces,
      AstroPlanet.venus => ZodiacSign.virgo,
      AstroPlanet.mars => ZodiacSign.cancer,
      AstroPlanet.jupiter => ZodiacSign.capricorn,
      AstroPlanet.saturn => ZodiacSign.aries,
      _ => null,
    };
    if (domicile.contains(sign)) return (label: '支配', value: 0.80);
    // 水星の乙女座（支配かつ高揚）などは重ねず、強い区分を1つだけ採用する。
    if (fall == sign) return (label: 'フォール', value: -0.75);
    if (detriment.contains(sign)) return (label: '損傷', value: -0.55);
    if (exaltation == sign) return (label: '高揚', value: 0.55);
    return null;
  }

  static bool _hasScoredHouseForArea(FortuneArea area, int house) => switch (area) {
        FortuneArea.love => {5, 7, 8, 12}.contains(house),
        FortuneArea.work => {6, 10, 11, 12}.contains(house),
        FortuneArea.money => {2, 8, 11, 12}.contains(house),
        FortuneArea.mental => {4, 6, 8, 12}.contains(house),
        FortuneArea.overall => {1, 5, 9, 10}.contains(house),
      };

  static double _moonHousePulse(HoroscopeReadingContext contextData, FortuneArea area) {
    final moon = _placement(contextData.transit.placements, AstroPlanet.moon);
    if (moon == null || moon.house < 1 || moon.house > 12) return 0;
    final house = moon.house;
    switch (area) {
      case FortuneArea.love:
        return house == 5 || house == 7 ? 2.0 : house == 12 ? -1.0 : 0.0;
      case FortuneArea.work:
        return house == 6 || house == 10 ? 2.0 : house == 12 ? -1.0 : 0.0;
      case FortuneArea.money:
        return house == 2 || house == 8 ? 2.0 : 0.0;
      case FortuneArea.mental:
        return house == 4 || house == 6 || house == 12 ? 3.0 : house == 8 ? -1.0 : 0.0;
      case FortuneArea.overall:
        return house == 1 || house == 4 || house == 10 ? 1.5 : 0.0;
    }
  }

  static double _transitPairPulse(HoroscopeReadingContext contextData, FortuneArea area) {
    var pulse = 0.0;
    for (final aspect in contextData.transitPairAspects.take(5)) {
      final first = aspect.firstPlanet;
      final second = aspect.secondPlanet;
      final has = (AstroPlanet planet) => first == planet || second == planet;
      double areaWeight = 0.0;
      if (has(AstroPlanet.jupiter) && has(AstroPlanet.venus)) {
        areaWeight = switch (area) {
          FortuneArea.love || FortuneArea.money => 1.0,
          FortuneArea.overall => 0.7,
          _ => 0.25,
        };
      } else if (has(AstroPlanet.venus) && has(AstroPlanet.mars)) {
        areaWeight = area == FortuneArea.love ? 1.0 : area == FortuneArea.overall ? 0.55 : 0.15;
      } else if (has(AstroPlanet.jupiter) && has(AstroPlanet.mercury)) {
        areaWeight = switch (area) {
          FortuneArea.work || FortuneArea.money => 0.9,
          FortuneArea.overall => 0.55,
          _ => 0.15,
        };
      } else if (has(AstroPlanet.sun) && has(AstroPlanet.jupiter)) {
        areaWeight = area == FortuneArea.overall ? 0.85 : area == FortuneArea.money ? 0.55 : 0.2;
      } else if (has(AstroPlanet.venus) && has(AstroPlanet.mercury)) {
        areaWeight = area == FortuneArea.love || area == FortuneArea.work ? 0.7 : 0.2;
      } else if (has(AstroPlanet.jupiter) && has(AstroPlanet.saturn)) {
        areaWeight = area == FortuneArea.work || area == FortuneArea.money ? 0.65 : 0.3;
      }
      if (areaWeight == 0) continue;

      final aspectValue = switch (aspect.type) {
        AspectType.conjunction => 5.4,
        AspectType.trine => 4.6,
        AspectType.sextile => 3.2,
        AspectType.square => -3.4,
        AspectType.opposition => -1.8,
      };
      final closeness = ((6.0 - aspect.orb) / 6.0).clamp(0.0, 1.0).toDouble();
      final phaseWeight = switch (aspect.phase) {
        AspectPhase.applying => 0.92,
        AspectPhase.exact => 1.18,
        AspectPhase.separating => 0.62,
      };
      final houseWeight = _pairHouseWeight(contextData, aspect, area);
      final natalResonance = hasNatalJupiterVenusConjunction(contextData) &&
              has(AstroPlanet.jupiter) &&
              has(AstroPlanet.venus)
          ? 1.18
          : 1.0;
      final sensitivity = _natalTransitSensitivity(contextData, area, {first, second});
      pulse += aspectValue *
          (0.4 + closeness * 0.6) *
          phaseWeight *
          areaWeight *
          houseWeight *
          natalResonance *
          sensitivity;
    }
    return pulse.clamp(-5.0, 7.0).toDouble();
  }

  static double _pairHouseWeight(
    HoroscopeReadingContext contextData,
    TransitPairAspect aspect,
    FortuneArea area,
  ) {
    final first = _placement(contextData.transit.placements, aspect.firstPlanet);
    final second = _placement(contextData.transit.placements, aspect.secondPlanet);
    final houses = [first?.house, second?.house].whereType<int>().toSet();
    final supportive = switch (area) {
      FortuneArea.love => {5, 7, 8},
      FortuneArea.work => {6, 10, 11},
      FortuneArea.money => {2, 8, 11},
      FortuneArea.mental => {4, 6, 12},
      FortuneArea.overall => {1, 5, 9, 10},
    };
    if (houses.any(supportive.contains)) return 1.22;
    if (houses.contains(12) && area != FortuneArea.mental) return 0.78;
    return 1.0;
  }

  static bool hasNatalJupiterVenusConjunction(HoroscopeReadingContext contextData) {
    final jupiter = _placement(contextData.natal.placements, AstroPlanet.jupiter);
    final venus = _placement(contextData.natal.placements, AstroPlanet.venus);
    if (jupiter == null || venus == null) return false;
    return _nearAspect(_planetLongitude(jupiter), _planetLongitude(venus), 0, orb: 6.0);
  }

  static double _natalTransitSensitivity(
    HoroscopeReadingContext contextData,
    FortuneArea area,
    Set<AstroPlanet> activePlanets,
  ) {
    final supportiveHouses = switch (area) {
      FortuneArea.love => {5, 7, 8},
      FortuneArea.work => {6, 10, 11},
      FortuneArea.money => {2, 8, 11},
      FortuneArea.mental => {4, 6, 12},
      FortuneArea.overall => {1, 4, 5, 9, 10},
    };
    var sensitivity = 0.9;
    for (final placement in contextData.natal.placements) {
      if (!activePlanets.contains(placement.planet)) continue;
      sensitivity += 0.12;
      if ({1, 4, 7, 10}.contains(placement.house)) sensitivity += 0.12;
      if (supportiveHouses.contains(placement.house)) sensitivity += 0.1;
    }
    for (final stellium in contextData.natal.stelliums) {
      if (stellium.planets.any(activePlanets.contains)) sensitivity += 0.1;
      if (stellium.planets.any(activePlanets.contains) && supportiveHouses.contains(stellium.house)) {
        sensitivity += 0.08;
      }
    }
    final natalMoon = _placement(contextData.natal.placements, AstroPlanet.moon);
    if (natalMoon != null && {1, 4, 7, 10}.contains(natalMoon.house)) sensitivity += 0.06;
    return sensitivity.clamp(0.85, 1.38).toDouble();
  }

  static TransitPairAspect? strongestBeneficPair(HoroscopeReadingContext contextData) {
    final candidates = contextData.transitPairAspects.where(
      (aspect) =>
          (aspect.involves(AstroPlanet.jupiter) && aspect.involves(AstroPlanet.venus)) ||
          (aspect.involves(AstroPlanet.venus) && aspect.involves(AstroPlanet.mars)) ||
          (aspect.involves(AstroPlanet.jupiter) && aspect.involves(AstroPlanet.mercury)),
    );
    if (candidates.isEmpty) return null;
    return candidates.first;
  }

  static List<TransitPairAspect> transitPairAspects({
    required List<PlanetPlacement> current,
    required List<PlanetPlacement> next,
  }) {
    final nextByPlanet = {for (final placement in next) placement.planet: placement};
    final result = <TransitPairAspect>[];
    final planets = current
        .where((placement) =>
            placement.planet != AstroPlanet.ascendant &&
            placement.planet != AstroPlanet.midheaven)
        .toList();
    for (var i = 0; i < planets.length; i++) {
      for (var j = i + 1; j < planets.length; j++) {
        final first = planets[i];
        final second = planets[j];
        final type = _aspectTypeBetween(_planetLongitude(first), _planetLongitude(second));
        if (type == null) continue;
        final orb = _aspectOrb(_planetLongitude(first), _planetLongitude(second), type);
        final nextFirst = nextByPlanet[first.planet];
        final nextSecond = nextByPlanet[second.planet];
        if (nextFirst == null || nextSecond == null) continue;
        final nextOrb = _aspectOrb(
          _planetLongitude(nextFirst),
          _planetLongitude(nextSecond),
          type,
        );
        final phase = orb <= 0.7
            ? AspectPhase.exact
            : nextOrb < orb
                ? AspectPhase.applying
                : AspectPhase.separating;
        result.add(
          TransitPairAspect(
            firstPlanet: first.planet,
            secondPlanet: second.planet,
            type: type,
            orb: orb,
            phase: phase,
          ),
        );
      }
    }
    result.sort((a, b) {
      final strengthA = _pairSortStrength(a);
      final strengthB = _pairSortStrength(b);
      return strengthB.compareTo(strengthA);
    });
    return result;
  }

  static AspectType? _aspectTypeBetween(double first, double second) {
    for (final type in AspectType.values) {
      if (_aspectOrb(first, second, type) <= 6.0) return type;
    }
    return null;
  }

  static double _aspectOrb(double first, double second, AspectType type) {
    final exact = double.parse(type.angle.replaceAll('°', ''));
    var distance = (first - second).abs() % 360.0;
    if (distance > 180.0) distance = 360.0 - distance;
    return (distance - exact).abs();
  }

  static double _pairSortStrength(TransitPairAspect aspect) {
    final hasJupiter = aspect.involves(AstroPlanet.jupiter);
    final hasVenus = aspect.involves(AstroPlanet.venus);
    final hasMars = aspect.involves(AstroPlanet.mars);
    final hasMercury = aspect.involves(AstroPlanet.mercury);
    final priority = hasJupiter && hasVenus
        ? 4.0
        : hasVenus && hasMars
            ? 3.0
            : hasJupiter && hasMercury
                ? 2.6
                : hasJupiter
                    ? 2.0
                    : 1.0;
    final phase = aspect.phase == AspectPhase.exact
        ? 1.2
        : aspect.phase == AspectPhase.applying
            ? 1.0
            : 0.7;
    return priority * phase * (6.1 - aspect.orb);
  }

  static double _grandTrinePulse(HoroscopeReadingContext contextData, FortuneArea area) {
    final groups = _grandTrineGroups(contextData.transit.placements);
    if (groups.isEmpty) return 0;
    var pulse = 0.0;
    for (final group in groups) {
      final hasVenusOrJupiter = group.contains(AstroPlanet.venus) || group.contains(AstroPlanet.jupiter);
      final hasMoon = group.contains(AstroPlanet.moon);
      final hasWorkPlanet = group.contains(AstroPlanet.mercury) || group.contains(AstroPlanet.saturn);
      if (area == FortuneArea.love && hasVenusOrJupiter) pulse += 4.0;
      if (area == FortuneArea.money && hasVenusOrJupiter) pulse += 4.0;
      if (area == FortuneArea.mental && hasMoon) pulse += 3.0;
      if (area == FortuneArea.work && hasWorkPlanet) pulse += 3.0;
      if (area == FortuneArea.overall) pulse += 3.0;
    }
    return pulse.clamp(0.0, 6.0).toDouble();
  }

  static bool hasTransitGrandTrine(HoroscopeReadingContext contextData) {
    return _grandTrineGroups(contextData.transit.placements).isNotEmpty;
  }

  static List<String> transitRarePatternLabels(HoroscopeReadingContext contextData) =>
      transitRarePatternDetails(contextData).map((item) => item.label).toSet().toList()..sort();

  static List<String> natalRarePatternLabels(HoroscopeReadingContext contextData) =>
      natalRarePatternDetails(contextData).map((item) => item.label).toSet().toList()..sort();

  static List<RarePatternConfiguration> transitRarePatternDetails(
    HoroscopeReadingContext contextData,
  ) => _rarePatternDetails(contextData.transit.placements);

  static List<RarePatternConfiguration> natalRarePatternDetails(
    HoroscopeReadingContext contextData,
  ) => _rarePatternDetails(contextData.natal.placements);

  static List<String> _rarePatternLabels(List<PlanetPlacement> placements) =>
      _rarePatternDetails(placements).map((item) => item.label).toSet().toList()..sort();

  static String rarePatternGuidance(String label, {bool natal = false}) {
    final timeWord = natal ? 'もともと' : '今日は';
    return switch (label) {
      'Tスクエア' => '$timeWord複数の課題が一点へ集まりやすい配置。優先順位を一つに絞って動く',
      'グランドクロス' => '$timeWord四方向からの要請がぶつかりやすい配置。役割と負担を分けて調整する',
      'ヨッド' => '$timeWord小さなずれの調整が大切な配置。急いで決めず、条件を微調整する',
      'ブーメラン（ヨッド）' => '$timeWord外からの課題を通じて方向転換しやすい配置。反応を見て進め方を変える',
      'ミスティックレクタングル（ダイヤモンド）' => '$timeWord対立した価値観を両立させる配置。違いをつなぐ役を引き受ける',
      'クレイドル（ゆりかご）' => '$timeWord対立を受け止める逃げ道がある配置。安心できる方法で協力を育てる',
      'ハンマー・オブ・ソー' => '$timeWord緊張を具体的な改革へ変えやすい配置。衝動でぶつからず、手順を決める',
      'グランドセクスタイル' => '$timeWord複数の得意分野が連携しやすい配置。一つを起点に周りへ広げる',
      _ => '$timeWord配置の特徴を生かし、無理のない一歩へつなげる',
    };
  }

  static List<RarePatternConfiguration> _rarePatternDetails(List<PlanetPlacement> source) {
    final placements = source.where((item) => item.planet != AstroPlanet.ascendant && item.planet != AstroPlanet.midheaven).toList();
    final result = <RarePatternConfiguration>[];
    final seen = <String>{};
    void add(String label, List<PlanetPlacement> members) {
      final sorted = [...members]..sort((left, right) => left.planet.index.compareTo(right.planet.index));
      final key = '$label|${sorted.map((item) => item.planet.index).join(',')}';
      if (seen.add(key)) result.add(RarePatternConfiguration(label: label, placements: sorted));
    }
    for (var a = 0; a < placements.length; a++) {
      for (var b = a + 1; b < placements.length; b++) {
        for (var c = b + 1; c < placements.length; c++) {
          final ab = _planetLongitude(placements[a]);
          final bc = _planetLongitude(placements[b]);
          final ac = _planetLongitude(placements[c]);
          if ((_nearAspect(ab, bc, 180) && _nearAspect(ab, ac, 90) && _nearAspect(ac, bc, 90)) ||
              (_nearAspect(ab, ac, 180) && _nearAspect(ab, bc, 90) && _nearAspect(bc, ac, 90)) ||
              (_nearAspect(ac, bc, 180) && _nearAspect(ac, ab, 90) && _nearAspect(ab, bc, 90))) add('Tスクエア', [placements[a], placements[b], placements[c]]);
          int? yodApex;
          if (_nearAspect(ab, ac, 60) && _nearAspect(ab, bc, 150, orb: 3) && _nearAspect(ac, bc, 150, orb: 3)) {
            yodApex = b;
          } else if (_nearAspect(ab, bc, 60) && _nearAspect(ab, ac, 150, orb: 3) && _nearAspect(bc, ac, 150, orb: 3)) {
            yodApex = c;
          } else if (_nearAspect(ac, bc, 60) && _nearAspect(ac, ab, 150, orb: 3) && _nearAspect(bc, ab, 150, orb: 3)) {
            yodApex = a;
          }
          if (yodApex != null) {
            add('ヨッド', [placements[a], placements[b], placements[c]]);
            for (var d = 0; d < placements.length; d++) {
              if (d == a || d == b || d == c) continue;
              if (_nearAspect(_planetLongitude(placements[yodApex]), _planetLongitude(placements[d]), 180)) {
                add('ブーメラン（ヨッド）', [placements[a], placements[b], placements[c], placements[d]]);
              }
            }
          }
          // ハンマー・オブ・ソー: 90度の土台へ、二本の135度が集まる。
          if ((_nearAspect(ab, ac, 90) && _nearAspect(ab, bc, 135, orb: 3) && _nearAspect(ac, bc, 135, orb: 3)) ||
              (_nearAspect(ab, bc, 90) && _nearAspect(ab, ac, 135, orb: 3) && _nearAspect(bc, ac, 135, orb: 3)) ||
              (_nearAspect(ac, bc, 90) && _nearAspect(ac, ab, 135, orb: 3) && _nearAspect(bc, ab, 135, orb: 3))) add('ハンマー・オブ・ソー', [placements[a], placements[b], placements[c]]);
          for (var d = c + 1; d < placements.length; d++) {
            final values = [ab, bc, ac, _planetLongitude(placements[d])];
            var oppositions = 0; var squares = 0; var trines = 0; var sextiles = 0;
            for (var i = 0; i < values.length; i++) {
              for (var j = i + 1; j < values.length; j++) {
                if (_nearAspect(values[i], values[j], 180)) oppositions++;
                if (_nearAspect(values[i], values[j], 90)) squares++;
                if (_nearAspect(values[i], values[j], 120)) trines++;
                if (_nearAspect(values[i], values[j], 60)) sextiles++;
              }
            }
            final members = [placements[a], placements[b], placements[c], placements[d]];
            if (oppositions == 2 && squares == 4) add('グランドクロス', members);
            if (oppositions == 2 && trines == 2 && sextiles == 2) add('ミスティックレクタングル（ダイヤモンド）', members);
            if (oppositions == 1 && trines == 2 && sextiles == 2) add('クレイドル（ゆりかご）', members);
          }
        }
      }
    }
    if (placements.length >= 6) {
      for (var a = 0; a < placements.length; a++) {
        for (var b = a + 1; b < placements.length; b++) {
          for (var c = b + 1; c < placements.length; c++) {
            for (var d = c + 1; d < placements.length; d++) {
              for (var e = d + 1; e < placements.length; e++) {
                for (var f = e + 1; f < placements.length; f++) {
                  final members = [placements[a], placements[b], placements[c], placements[d], placements[e], placements[f]]
                    ..sort((left, right) => _planetLongitude(left).compareTo(_planetLongitude(right)));
                  var hexagon = true;
                  for (var index = 0; index < members.length; index++) {
                    final first = _planetLongitude(members[index]);
                    final second = _planetLongitude(members[(index + 1) % members.length]);
                    final step = (second - first + 360) % 360;
                    if ((step - 60).abs() > 6) {
                      hexagon = false;
                      break;
                    }
                  }
                  if (hexagon) add('グランドセクスタイル', members);
                }
              }
            }
          }
        }
      }
    }
    result.sort((left, right) => left.label.compareTo(right.label));
    return result;
  }

  static double _rarePatternPulse(List<String> labels, FortuneArea area) {
    var value = 0.0;
    for (final label in labels) {
      if (label == 'グランドクロス' || label == 'Tスクエア') value += area == FortuneArea.mental ? -1.8 : -1.3;
      if (label == 'ヨッド') value += area == FortuneArea.overall ? -0.8 : -0.5;
      if (label == 'クレイドル（ゆりかご）') value += area == FortuneArea.mental ? 1.6 : 1.2;
      if (label == 'ミスティックレクタングル（ダイヤモンド）') value += 1.6;
      if (label == 'グランドセクスタイル') value += 2.6;
      if (label == 'ブーメラン（ヨッド）' || label == 'ハンマー・オブ・ソー') value += -1.0;
    }
    return value.clamp(-3.5, 3.5).toDouble();
  }

  static List<String> transitGrandTrineLabels(HoroscopeReadingContext contextData) {
    return _grandTrineGroups(contextData.transit.placements)
        .map((group) => group.map((planet) => planet.label).join('・'))
        .toList();
  }

  static double _natalStelliumPulse(HoroscopeReadingContext contextData, FortuneArea area) {
    var pulse = 0.0;
    final supportiveHouses = switch (area) {
      FortuneArea.love => {5, 7, 8},
      FortuneArea.work => {6, 10, 11},
      FortuneArea.money => {2, 8, 11},
      FortuneArea.mental => {4, 6, 12},
      FortuneArea.overall => {1, 4, 5, 9, 10},
    };
    for (final stellium in contextData.natal.stelliums) {
      final planets = stellium.planets;
      var signal = 0.0;
      if (area == FortuneArea.love && planets.contains(AstroPlanet.venus)) signal += 3.0;
      if (area == FortuneArea.money && planets.contains(AstroPlanet.venus)) signal += 2.8;
      if ((area == FortuneArea.overall || area == FortuneArea.money) &&
          planets.contains(AstroPlanet.jupiter)) signal += 3.2;
      if (area == FortuneArea.work && planets.contains(AstroPlanet.mercury)) signal += 2.3;
      if (area == FortuneArea.work && planets.contains(AstroPlanet.saturn)) signal += 2.6;
      if (area == FortuneArea.love && planets.contains(AstroPlanet.mars)) signal += 2.0;
      if (area == FortuneArea.mental &&
          (planets.contains(AstroPlanet.moon) || planets.contains(AstroPlanet.neptune))) {
        signal += planets.contains(AstroPlanet.moon) && planets.contains(AstroPlanet.neptune) ? 3.0 : 2.2;
      }
      if (area == FortuneArea.overall && signal == 0) signal = 1.3;
      if (signal == 0) continue;
      if (supportiveHouses.contains(stellium.house)) signal *= 1.18;
      if (planets.contains(AstroPlanet.jupiter) && planets.contains(AstroPlanet.venus)) {
        signal += area == FortuneArea.love || area == FortuneArea.money ? 1.8 : 1.0;
      }
      pulse += signal;
    }
    return pulse.clamp(0.0, 8.0).toDouble();
  }

  static double _natalPatternPulse(HoroscopeReadingContext contextData, FortuneArea area) {
    var pulse = _hasNatalKite(contextData) ? (area == FortuneArea.overall ? 3.0 : 2.0) : 0.0;
    pulse += _rarePatternPulse(_rarePatternLabels(contextData.natal.placements), area) * 0.55;
    return pulse.clamp(-3.0, 4.0).toDouble();
  }

  static bool hasNatalKite(HoroscopeReadingContext contextData) {
    return _hasNatalKite(contextData);
  }

  static bool _hasNatalKite(HoroscopeReadingContext contextData) {
    final placements = contextData.natal.placements
        .where((placement) =>
            placement.planet != AstroPlanet.ascendant &&
            placement.planet != AstroPlanet.midheaven)
        .toList();
    for (var i = 0; i < placements.length; i++) {
      for (var j = i + 1; j < placements.length; j++) {
        for (var k = j + 1; k < placements.length; k++) {
          final a = _planetLongitude(placements[i]);
          final b = _planetLongitude(placements[j]);
          final c = _planetLongitude(placements[k]);
          if (!(_nearTrine(a, b) && _nearTrine(b, c) && _nearTrine(a, c))) continue;
          for (var d = 0; d < placements.length; d++) {
            if (d == i || d == j || d == k) continue;
            final fourth = _planetLongitude(placements[d]);
            if ((_nearAspect(a, fourth, 180) && _nearAspect(fourth, b, 60) && _nearAspect(fourth, c, 60)) ||
                (_nearAspect(b, fourth, 180) && _nearAspect(fourth, a, 60) && _nearAspect(fourth, c, 60)) ||
                (_nearAspect(c, fourth, 180) && _nearAspect(fourth, a, 60) && _nearAspect(fourth, b, 60))) {
              return true;
            }
          }
        }
      }
    }
    return false;
  }

  static bool _nearAspect(double first, double second, double target, {double orb = 8.0}) {
    var distance = (first - second).abs() % 360.0;
    if (distance > 180.0) distance = 360.0 - distance;
    return (distance - target).abs() <= orb;
  }

  static List<Set<AstroPlanet>> _grandTrineGroups(List<PlanetPlacement> placements) {
    final planets = placements
        .where((item) => item.planet != AstroPlanet.ascendant && item.planet != AstroPlanet.midheaven)
        .toList();
    final result = <Set<AstroPlanet>>[];
    for (var i = 0; i < planets.length; i++) {
      for (var j = i + 1; j < planets.length; j++) {
        for (var k = j + 1; k < planets.length; k++) {
          final first = _planetLongitude(planets[i]);
          final second = _planetLongitude(planets[j]);
          final third = _planetLongitude(planets[k]);
          if (_nearTrine(first, second) &&
              _nearTrine(second, third) &&
              _nearTrine(first, third)) {
            result.add({planets[i].planet, planets[j].planet, planets[k].planet});
          }
        }
      }
    }
    return result;
  }

  static double _planetLongitude(PlanetPlacement placement) {
    return placement.sign.index * 30.0 + placement.degree;
  }

  static bool _nearTrine(double first, double second) {
    var distance = (first - second).abs() % 360.0;
    if (distance > 180.0) distance = 360.0 - distance;
    return (distance - 120.0).abs() <= 8.0;
  }

  static PlanetPlacement? _placement(List<PlanetPlacement> placements, AstroPlanet planet) {
    for (final placement in placements) {
      if (placement.planet == planet) return placement;
    }
    return null;
  }
}

class RarePatternConfiguration {
  const RarePatternConfiguration({required this.label, required this.placements});

  final String label;
  final List<PlanetPlacement> placements;

  List<AstroPlanet> get planets => placements.map((item) => item.planet).toList();

  List<String> get aspectDetails {
    final details = <String>[];
    const aspectDefinitions = <({String label, double angle, double orb})>[
      (label: 'コンジャンクション', angle: 0, orb: 8),
      (label: 'セクスタイル', angle: 60, orb: 8),
      (label: 'スクエア', angle: 90, orb: 8),
      (label: 'トライン', angle: 120, orb: 8),
      (label: 'セスキコードレート', angle: 135, orb: 3),
      (label: 'クインカンクス', angle: 150, orb: 3),
      (label: 'オポジション', angle: 180, orb: 8),
    ];
    for (var first = 0; first < placements.length; first++) {
      for (var second = first + 1; second < placements.length; second++) {
        final firstLongitude = FortuneScoreCalculator._planetLongitude(placements[first]);
        final secondLongitude = FortuneScoreCalculator._planetLongitude(placements[second]);
        for (final aspect in aspectDefinitions) {
          if (!FortuneScoreCalculator._nearAspect(
            firstLongitude,
            secondLongitude,
            aspect.angle,
            orb: aspect.orb,
          )) {
            continue;
          }
          var distance = (firstLongitude - secondLongitude).abs() % 360.0;
          if (distance > 180.0) distance = 360.0 - distance;
          final orb = (distance - aspect.angle).abs();
          details.add('${placements[first].planet.label} ${aspect.label} ${placements[second].planet.label}（オーブ${orb.toStringAsFixed(1)}°）');
          break;
        }
      }
    }
    return details;
  }

  Map<String, Object?> toJson() => {
        'label': label,
        'planets': placements.map((item) => {
              'planet': item.planet.label,
              'sign': item.sign.label,
              'degree': double.parse(item.degree.toStringAsFixed(2)),
            }).toList(),
        'aspects': aspectDetails,
      };
}

class FortuneScoreFactor {
  const FortuneScoreFactor({required this.label, required this.value, this.detail, this.formula});

  final String label;
  final double value;
  final String? detail;
  final String? formula;

  String get signedValue => '${value >= 0 ? '+' : ''}${value.toStringAsFixed(value.abs() >= 2 ? 0 : 1)}';

  String get preciseSignedValue => '${value >= 0 ? '+' : ''}${value.toStringAsFixed(1)}';
}

class _ScoreCalculation {
  const _ScoreCalculation(this.value, this.formula);

  final double value;
  final String formula;
}

class FortuneScoreBreakdown {
  const FortuneScoreBreakdown({
    required this.base,
    required this.factors,
    required this.rawScore,
    required this.score,
  });

  final int base;
  final List<FortuneScoreFactor> factors;
  final double rawScore;
  final int score;

  double get adjustment => factors.fold<double>(0, (sum, factor) => sum + factor.value);

  List<FortuneScoreFactor> get keyFactors {
    final sorted = [...factors]..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
    return sorted.take(3).toList();
  }

  String get promptSummary {
    if (keyFactors.isEmpty) return '大きな補正は少なめ';
    return keyFactors.map((factor) => '${factor.label}${factor.signedValue}').join('、');
  }
}

class TodayFortuneItem {
  const TodayFortuneItem({
    required this.title,
    required this.score,
    required this.scoreBreakdown,
    required this.sign,
    this.secondarySign,
    required this.natalHouse,
    this.aspectLabel,
    this.transitHouseLabel,
    this.stelliumLabel,
    required this.aspectBasis,
    required this.dailyHighlight,
    this.chartBasis = '出生図全体: ハウス集中も補正',
    required this.text,
    required this.detailedText,
    required this.icon,
  });

  final String title;
  final int score;
  final FortuneScoreBreakdown scoreBreakdown;
  final String sign;
  final String? secondarySign;
  final String natalHouse;
  final String? aspectLabel;
  final String? transitHouseLabel;
  final String? stelliumLabel;
  final String aspectBasis;
  final DailyHighlight dailyHighlight;
  final String chartBasis;
  final String text;
  final String detailedText;
  final IconData icon;
}

class DailyHighlight {
  const DailyHighlight({
    required this.title,
    required this.phase,
    required this.reason,
    required this.actionHint,
    required this.strength,
  });

  final String title;
  final String phase;
  final String reason;
  final String actionHint;
  final int strength;

  String get promptLine =>
      '$title / $phase / 強さ$strength / 根拠:$reason / 行動:$actionHint';
}

class FortuneNumber extends StatelessWidget {
  const FortuneNumber({super.key, required this.score, this.compact = false});

  final int score;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final style = compact
        ? FortuneNumberStyle.fromScore(score).compact()
        : FortuneNumberStyle.fromScore(score);

    return Tooltip(
      message: style.label,
      child: Container(
        width: style.size,
        height: style.size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: style.background,
          border: Border.all(color: style.border, width: 2),
          boxShadow: [
            BoxShadow(
              color: style.glow.withValues(alpha: 0.30),
              blurRadius: style.glowRadius,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ScoreText(score: score, style: style),
            const SizedBox(height: 3),
            Text(
              style.shortLabel,
              style: TextStyle(
                color: style.textColor.withValues(alpha: 0.82),
                fontSize: style.labelFontSize,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoreText extends StatelessWidget {
  const _ScoreText({required this.score, required this.style});

  final int score;
  final FortuneNumberStyle style;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      '$score',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: style.textColor,
        fontSize: style.fontSize,
        fontWeight: FontWeight.w900,
        height: 1,
        shadows: [
          Shadow(
            color: style.glow.withValues(alpha: 0.50),
            blurRadius: style.glowRadius,
          ),
        ],
      ),
    );

    if (style.gradient == null) return text;

    return ShaderMask(
      shaderCallback: (bounds) => style.gradient!.createShader(bounds),
      child: text,
    );
  }
}

class FortuneNumberStyle {
  const FortuneNumberStyle({
    required this.label,
    required this.shortLabel,
    required this.color,
    required this.textColor,
    required this.background,
    required this.border,
    required this.fontSize,
    required this.size,
    required this.labelFontSize,
    required this.glow,
    required this.glowRadius,
    this.gradient,
  });

  final String label;
  final String shortLabel;
  final Color color;
  final Color textColor;
  final Color background;
  final Color border;
  final double fontSize;
  final double size;
  final double labelFontSize;
  final Color glow;
  final double glowRadius;
  final LinearGradient? gradient;

  FortuneNumberStyle compact() {
    return FortuneNumberStyle(
      label: label,
      shortLabel: shortLabel,
      color: color,
      textColor: textColor,
      background: background,
      border: border,
      fontSize: math.max(28, fontSize - 5),
      size: math.max(56, size - 10),
      labelFontSize: math.max(9, labelFontSize - 1),
      glow: glow,
      glowRadius: math.max(5, glowRadius - 2),
      gradient: gradient,
    );
  }

  static FortuneNumberStyle fromScore(int score) {
    if (score >= 90) {
      return const FortuneNumberStyle(
        label: 'かなり強い運気',
        shortLabel: '最高潮',
        color: Color(0xFFFFFFFF),
        textColor: Color(0xFFFFFFFF),
        background: Color(0xEE121528),
        border: Color(0xFFFFD66B),
        fontSize: 46,
        size: 78,
        labelFontSize: 10,
        glow: Color(0xFFFF82B2),
        glowRadius: 18,
        gradient: LinearGradient(
          colors: [
            Color(0xFF57D6D1),
            Color(0xFFF6D77A),
            Color(0xFFFF82B2),
            Color(0xFFB58CFF),
          ],
        ),
      );
    }
    if (score >= 82) {
      return const FortuneNumberStyle(
        label: '良い運気',
        shortLabel: '好調',
        color: Color(0xFFF6D77A),
        textColor: Color(0xFFFFF4C2),
        background: Color(0xEE121528),
        border: Color(0xFFF6D77A),
        fontSize: 43,
        size: 74,
        labelFontSize: 10,
        glow: Color(0xFFF6D77A),
        glowRadius: 14,
      );
    }
    if (score >= 74) {
      return const FortuneNumberStyle(
        label: '安定した運気',
        shortLabel: '安定',
        color: Color(0xFFB58CFF),
        textColor: Color(0xFFF6F0FF),
        background: Color(0xEE121528),
        border: Color(0xFFB58CFF),
        fontSize: 40,
        size: 70,
        labelFontSize: 10,
        glow: Color(0xFFB58CFF),
        glowRadius: 14,
      );
    }
    if (score >= 66) {
      return const FortuneNumberStyle(
        label: '整えたい運気',
        shortLabel: '調整',
        color: Color(0xFFFF2D8F),
        textColor: Color(0xFFFFECF6),
        background: Color(0xEE121528),
        border: Color(0xFFFF2D8F),
        fontSize: 38,
        size: 67,
        labelFontSize: 10,
        glow: Color(0xFFFF2D8F),
        glowRadius: 12,
      );
    }
    return const FortuneNumberStyle(
      label: '慎重に扱う運気',
      shortLabel: '慎重',
      color: Color(0xFF57D6D1),
      textColor: Color(0xFFE9FFFF),
      background: Color(0xEE121528),
      border: Color(0xFF57D6D1),
      fontSize: 36,
      size: 64,
      labelFontSize: 10,
      glow: Color(0xFF57D6D1),
      glowRadius: 7,
    );
  }
}

class TodayFortuneItemView extends StatelessWidget {
  const TodayFortuneItemView({
    super.key,
    required this.item,
    required this.detailed,
    required this.profile,
    required this.details,
    required this.date,
    this.aiText,
    this.aiLoading = false,
    this.aiFailed = false,
    this.showAiInline = true,
  });

  final TodayFortuneItem item;
  final bool detailed;
  final AstroProfile profile;
  final UserProfileDetails details;
  final DateTime date;
  final String? aiText;
  final bool aiLoading;
  final bool aiFailed;
  final bool showAiInline;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = MediaQuery.sizeOf(context).width < 390;
        return GlassPanel(
          padding: EdgeInsets.all(compact ? 16 : 18),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        FortuneNumber(score: item.score),
                        const SizedBox(width: 14),
                        Expanded(child: _titleRow()),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _body(),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 90,
                      child: FortuneNumber(score: item.score),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _titleRow(),
                          const SizedBox(height: 4),
                          _body(),
                        ],
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _titleRow() {
    return Row(
      children: [
        Icon(item.icon, color: const Color(0xFFF6D77A), size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            item.title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }

  Widget _body() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (detailed) _basis(),
        const SizedBox(height: 8),
        Text(
          detailed ? item.detailedText : item.text,
          maxLines: null,
          overflow: TextOverflow.visible,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.76), height: 1.45),
        ),
        if (detailed) ...[
          const SizedBox(height: 8),
          ScoreReasonPanel(
            title: item.title,
            breakdown: item.scoreBreakdown,
            showTechnicalDetail: true,
          ),
        ],
        if (detailed) ...[
          const SizedBox(height: 12),
          LongFortuneEvidencePanel(
            current: [
              '現在: ${item.sign}',
              if (item.secondarySign != null) item.secondarySign!,
            ].join(' / '),
            transitHouse: item.transitHouseLabel ?? '通過: 出生図全体',
            natal: item.natalHouse,
            correction: [
              if (item.aspectLabel != null) 'アスペクト: ${item.aspectLabel}',
              if (item.stelliumLabel != null) 'ステリウム: ${item.stelliumLabel}',
              'アスペクト根拠: ${item.aspectBasis}',
              item.chartBasis,
            ].join(' / '),
          ),
        ],
      ],
    );
  }

  Widget _basis() {
    return Tooltip(
      message: '${item.aspectBasis}\n${item.chartBasis}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _AstroBasisChip(
                prefix: '現在の星座',
                text: item.sign,
                color: const Color(0xFF57D6D1),
              ),
              if (item.secondarySign != null)
                _AstroBasisChip(
                  prefix: '現在の星座',
                  text: item.secondarySign!,
                  color: const Color(0xFF57D6D1),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '反映した根拠',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.44),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (item.aspectLabel != null)
                _AstroBasisChip(
                  prefix: 'アスペクト',
                  text: item.aspectLabel!,
                  color: const Color(0xFFB58CFF),
                ),
              if (item.transitHouseLabel != null)
                _AstroBasisChip(
                  prefix: '通過',
                  text: item.transitHouseLabel!,
                  color: const Color(0xFFB58CFF),
                ),
              if (item.stelliumLabel != null)
                _AstroBasisChip(
                  prefix: 'ステリウム',
                  text: item.stelliumLabel!,
                  color: const Color(0xFFB58CFF),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class ScoreReasonPanel extends StatelessWidget {
  const ScoreReasonPanel({
    super.key,
    required this.title,
    required this.breakdown,
    required this.showTechnicalDetail,
  });

  final String title;
  final FortuneScoreBreakdown breakdown;
  final bool showTechnicalDetail;

  @override
  Widget build(BuildContext context) {
    final adjustment = breakdown.adjustment;
    final summary = '基準${breakdown.base}点 ${adjustment >= 0 ? '+' : ''}${adjustment.toStringAsFixed(1)} → ${breakdown.score}点';
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 4),
        iconColor: const Color(0xFF57D6D1),
        collapsedIconColor: Colors.white.withValues(alpha: 0.62),
        title: Row(
          children: [
            const Expanded(
              child: Text('この点数の理由', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
            ),
            TextButton.icon(
              onPressed: () => _openDetail(context),
              icon: const Icon(Icons.open_in_new, size: 15),
              label: const Text('詳細を見る'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        subtitle: Text(
          summary,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.58), fontSize: 12),
        ),
        children: [
          for (final factor in breakdown.keyFactors)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 34,
                    child: Text(
                      factor.signedValue,
                      style: TextStyle(
                        color: factor.value >= 0 ? const Color(0xFF57D6D1) : const Color(0xFFFF82B2),
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      showTechnicalDetail && factor.detail != null
                          ? '${factor.label}（${factor.detail}）'
                          : factor.label,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.76), fontSize: 12, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Text(
            '計算値 ${breakdown.rawScore.toStringAsFixed(1)}点を四捨五入し、50〜99点の範囲で表示しています。',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.48), fontSize: 11, height: 1.35),
          ),
        ],
      ),
    );
  }

  void _openDetail(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF11172F),
      builder: (context) => ScoreCalculationDetailSheet(
        title: title,
        breakdown: breakdown,
      ),
    );
  }
}

class ScoreCalculationDetailSheet extends StatelessWidget {
  const ScoreCalculationDetailSheet({super.key, required this.title, required this.breakdown});

  final String title;
  final FortuneScoreBreakdown breakdown;

  @override
  Widget build(BuildContext context) {
    final adjustment = breakdown.adjustment;
    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.45,
        maxChildSize: 0.92,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                const Icon(Icons.calculate_outlined, color: Color(0xFFF6D77A)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$titleの点数計算',
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
                  ),
                ),
                IconButton(
                  tooltip: '閉じる',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              '基準${breakdown.base}点 ${adjustment >= 0 ? '+' : ''}${adjustment.toStringAsFixed(1)} = 計算値${breakdown.rawScore.toStringAsFixed(1)}点',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.78), fontSize: 14, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              '四捨五入し、50〜99点の範囲で ${breakdown.score}点 と表示しています。',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12),
            ),
            const SizedBox(height: 18),
            const Text('加点・減点の内訳', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            for (final factor in breakdown.factors)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 46,
                      child: Text(
                        factor.preciseSignedValue,
                        style: TextStyle(
                          color: factor.value >= 0 ? const Color(0xFF57D6D1) : const Color(0xFFFF82B2),
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(factor.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                          if (factor.detail != null) ...[
                            const SizedBox(height: 3),
                            Text(
                              factor.detail!,
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.58), fontSize: 12),
                            ),
                          ],
                          if (factor.formula != null) ...[
                            const SizedBox(height: 3),
                            Text(
                              '算定: ${factor.formula} = ${factor.preciseSignedValue}',
                              style: TextStyle(color: const Color(0xFFB8FFF5).withValues(alpha: 0.78), fontSize: 12, height: 1.35),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 鑑定ナビの意図判定に使う、日本語の同義語・言い換え辞書。
/// 表示文は元の質問を尊重しつつ、検索だけはこの表記へ正規化する。
class JapaneseQuestionNormalizer {
  const JapaneseQuestionNormalizer._();

  static const List<MapEntry<String, String>> _dictionary = [
    MapEntry('明後日', '明後日'),
    MapEntry('あさって', '明後日'),
    MapEntry('本日', '今日'),
    MapEntry('当日', '今日'),
    MapEntry('きょう', '今日'),
    MapEntry('翌日', '明日'),
    MapEntry('あした', '明日'),
    MapEntry('前日', '昨日'),
    MapEntry('きのう', '昨日'),
    MapEntry('当週', '今週'),
    MapEntry('今しゅう', '今週'),
    MapEntry('翌週', '来週'),
    MapEntry('前週', '先週'),
    MapEntry('当月', '今月'),
    MapEntry('今ヶ月', '今月'),
    MapEntry('翌月', '来月'),
    MapEntry('前月', '先月'),
    MapEntry('本年', '今年'),
    MapEntry('当年', '今年'),
    MapEntry('翌年', '来年'),
    MapEntry('前年', '去年'),
    MapEntry('メンタル面', 'メンタル'),
    MapEntry('精神面', 'メンタル'),
    MapEntry('健康面', '健康'),
    MapEntry('身体', '体'),
    MapEntry('おしごと', '仕事'),
  ];

  static String normalize(String input) {
    var normalized = input.replaceAll('　', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    for (final entry in _dictionary) {
      normalized = normalized.replaceAll(entry.key, entry.value);
    }
    return normalized;
  }
}

class FortuneRuleService {
  const FortuneRuleService();

  static final Map<String, String> _questionTimingCache = {};

  _SafetyQuestionKind? _isSafetyCriticalQuestion(String question) {
    final value = question.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    if (['自殺', '死にたい', '消えたい', '自分を傷', '自傷', '殺したい', '殺され', '今すぐ危険', '監禁']
        .any(value.contains)) {
      return _SafetyQuestionKind.immediate;
    }
    if (['dv', '家庭内暴力', '暴力を受け', '虐待', 'ストーカー', 'つきまと', '脅され', '性的被害', '性被害', 'レイプ', '暴行']
        .any(value.contains)) {
      return _SafetyQuestionKind.abuse;
    }
    if (['交通事故', '事故に遭', '事故が起', '運転中', '飲酒運転', '車で事故', 'バイクで事故', '危険な日', 'けがをする']
        .any(value.contains)) {
      return _SafetyQuestionKind.traffic;
    }
    return null;
  }

  String _natalAspectPhase(HoroscopeReadingContext contextData, TransitAspect aspect) {
    final next = contextData.nextAspects.where(
      (item) =>
          item.transitPlanet == aspect.transitPlanet &&
          item.natalPlanet == aspect.natalPlanet &&
          item.type == aspect.type,
    );
    if (aspect.orb <= 0.7) return 'ピーク';
    if (next.isEmpty) return '指定日';
    return next.first.orb < aspect.orb ? '接近中' : '余韻';
  }

  Future<String> createCustomFortune({
    required AstroProfile profile,
    required UserProfileDetails details,
    required String question,
    required HoroscopeReadingContext contextData,
    List<CustomFortuneLog> previousLogs = const [],
    bool compactForMobile = false,
  }) async {
    // 判定・検索に入る前に、表記ゆれを一つの語へ寄せる。
    // 例: 「本日」と「今日」を別の質問として扱わない。
    question = JapaneseQuestionNormalizer.normalize(question);
    final smallTalkReply = _smallTalkReply(question);
    if (smallTalkReply != null) return smallTalkReply;
    final safetyKind = _isSafetyCriticalQuestion(question);
    if (safetyKind != null) {
      return _safetyCriticalReading(
        question: question,
        contextData: contextData,
        compactForMobile: compactForMobile,
        kind: safetyKind,
      );
    }
    if (_isMinorSensitiveQuestion(profile, question)) {
      return _minorSensitiveReading(compactForMobile: compactForMobile);
    }
    if (_isGamblingOrWindfallQuestion(question)) {
      return _gamblingOrWindfallReading(
        question: question,
        contextData: contextData,
        compactForMobile: compactForMobile,
      );
    }
    if (_isLongTermHealthQuestion(question)) {
      return _longTermHealthReading(
        profile: profile,
        contextData: contextData,
        compactForMobile: compactForMobile,
      );
    }
    if (_isLongTermWealthQuestion(question)) {
      return _longTermWealthReading(
        profile: profile,
        contextData: contextData,
        compactForMobile: compactForMobile,
      );
    }
    if (_isLifeCourseQuestion(question)) {
      return _lifeCourseReading(
        profile: profile,
        question: question,
        contextData: contextData,
        compactForMobile: compactForMobile,
      );
    }
    if (_isSpecificDateFortuneQuestion(question)) {
      return _specificDateFortuneReading(
        profile: profile,
        question: question,
        compactForMobile: compactForMobile,
      );
    }
    final invalidAstrologyPremise = _invalidAstrologyPremiseReply(
      question,
      compactForMobile: compactForMobile,
    );
    if (invalidAstrologyPremise != null) return invalidAstrologyPremise;
    if (_isNatalProfileQuestion(question)) {
      return _natalProfileReading(
        profile: profile,
        question: question,
        contextData: contextData,
        compactForMobile: compactForMobile,
      );
    }
    if (_isLightCustomQuestion(question)) {
      return _createLightCustomFortune(
        profile: profile,
        question: question,
        contextData: contextData,
      );
    }
    if (_isCurrentMoonFlowQuestion(question)) {
      return _currentMoonFlowReading(
        question: question,
        contextData: contextData,
        compactForMobile: compactForMobile,
      );
    }
    if (_isAstrologyTermQuestion(question)) {
      return _astrologyTermExplanation(question, compactForMobile: compactForMobile);
    }
    if (_isChatFollowUp(question, previousLogs)) {
      return _createChatFollowUp(
        question: question,
        contextData: contextData,
        previousLogs: previousLogs,
      );
    }
    if (_isHealthIncomeQuestion(question)) {
      return _healthIncomeReading(
        profile: profile,
        question: question,
        contextData: contextData,
        compactForMobile: compactForMobile,
      );
    }
    if (_isMoneyHardshipQuestion(question)) {
      return _moneyHardshipReading(
        profile: profile,
        contextData: contextData,
        compactForMobile: compactForMobile,
      );
    }
    if (_isMultiTopicDecisionQuestion(question)) {
      return _multiTopicDecisionReading(
        profile: profile,
        question: question,
        contextData: contextData,
        compactForMobile: compactForMobile,
      );
    }
    if (_isTodayFortuneQuestion(question)) {
      return _todayFortuneReading(
        profile: profile,
        question: question,
        contextData: contextData,
        compactForMobile: compactForMobile,
      );
    }
    if (_isRelativeDayFortuneQuestion(question)) {
      return _relativeDayFortuneReading(
        profile: profile,
        question: question,
        compactForMobile: compactForMobile,
      );
    }
    if (_isRecentFortuneQuestion(question)) {
      return _recentFortuneReading(
        profile: profile,
        question: question,
        compactForMobile: compactForMobile,
      );
    }
    if (_isStartTimingComparisonQuestion(question)) {
      return _startTimingComparisonReading(
        profile: profile,
        question: question,
        compactForMobile: compactForMobile,
      );
    }
    if (_isPeriodFortuneQuestion(question)) {
      return _periodFortuneReading(
        profile: profile,
        question: question,
        compactForMobile: compactForMobile,
      );
    }
    if (_isCareerFitQuestion(question)) {
      return _careerFitReading(
        profile: profile,
        contextData: contextData,
        question: question,
        compactForMobile: compactForMobile,
      );
    }
    if (_isLoveTimingQuestion(question)) {
      return _loveTimingReading(
        profile: profile,
        contextData: contextData,
        compactForMobile: compactForMobile,
      );
    }
    if (_isStructuredDecisionQuestion(question)) {
      return _structuredDecisionReading(
        profile: profile,
        question: question,
        contextData: contextData,
        compactForMobile: compactForMobile,
      );
    }
    if (_isAreaFortuneQuestion(question)) {
      return _recentFortuneReading(
        profile: profile,
        question: question,
        compactForMobile: compactForMobile,
      );
    }
    if (_isAstrologyApplicationQuestion(question)) {
      return _astrologyApplicationReading(
        question: question,
        compactForMobile: compactForMobile,
      );
    }
    final rawFallback = _customProposalFallback(
      profile: profile,
      question: question,
      contextData: contextData,
    );
    return _completeLocalReading(
      rawFallback,
      maxCharacters: _customMaxCharacters(question, compactForMobile: compactForMobile),
      fallback: rawFallback,
    );
  }

  String _safetyCriticalReading({
    required String question,
    required HoroscopeReadingContext contextData,
    required bool compactForMobile,
    required _SafetyQuestionKind kind,
  }) {
    if (kind == _SafetyQuestionKind.immediate) {
      const answer = '今は占いより安全を最優先にしてください。自分や誰かを傷つけそう、または危険が迫っているなら、ひとりにならず、近くの信頼できる人や緊急窓口へすぐ連絡してください。日本では緊急時は110番・119番です。ここでは危険な時期の占断はせず、まず今いる場所を安全にすることを勧めます。';
      return compactForMobile ? _shortText(answer, 180) : answer;
    }
    if (kind == _SafetyQuestionKind.abuse) {
      const answer = '暴力、つきまとい、脅し、性的な被害については、占いで相手の行動や安全な日を判断しません。今すぐ危険なら安全な場所へ移り、110番・119番や近くの信頼できる人へ連絡してください。記録を残せる範囲で残しつつ、ひとりで相手と会って解決しようとしないことを優先してください。';
      return compactForMobile ? _shortText(answer, 180) : answer;
    }
    final mental = FortuneScoreCalculator.dailyArea(contextData, FortuneArea.mental, FortuneScoreCalculator.standardBase(FortuneArea.mental));
    final focus = mental < 70
        ? '今日は気持ちが急ぎやすい流れなので、時間に余裕を取り、運転中や横断時は通知を見ないことを優先してください。'
        : '今日は落ち着いて確認しやすい流れですが、星の点数に関係なく、運転中や横断時は通知を見ない・急がないを徹底してください。';
    final answer = '交通事故やけがが起きる日を占いで特定することはできません。$focus 出発前に予定を5分早める、疲れている時は運転を代わってもらうなど、現実の安全確認を最優先にしてください。';
    return compactForMobile ? _shortText(answer, 180) : answer;
  }

  bool _isMinorSensitiveQuestion(AstroProfile profile, String question) {
    final birth = DateTime.tryParse(profile.birthDate);
    if (birth == null) return false;
    final today = DateTime.now();
    var age = today.year - birth.year;
    if (DateTime(today.year, birth.month, birth.day).isAfter(today)) age--;
    if (age >= 18) return false;
    final value = question.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    return ['sex', 'セックス', '性行為', '裸', 'エロ', '援交', '大人の関係'].any(value.contains);
  }

  String _minorSensitiveReading({required bool compactForMobile}) {
    const answer = 'その内容は、ここでは年齢に合った安全な形では扱えません。気になることや困っていることがあるなら、信頼できる大人、学校の先生、保健室などに相談してください。恋愛の気持ちや友人関係、今の過ごし方についてなら一緒に占えます。';
    return compactForMobile ? _shortText(answer, 180) : answer;
  }

  bool _isGamblingOrWindfallQuestion(String question) {
    final value = question.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    const terms = ['宝くじ', 'ロト', 'ギャンブル', '競馬', 'パチンコ', '当選', 'お金を拾', '臨時収入'];
    return terms.any(value.contains);
  }

  String _gamblingOrWindfallReading({
    required String question,
    required HoroscopeReadingContext contextData,
    required bool compactForMobile,
  }) {
    final money = FortuneScoreCalculator.dailyArea(contextData, FortuneArea.money, FortuneScoreCalculator.standardBase(FortuneArea.money));
    final answer = '宝くじの当選日やお金を拾える日を占いで示すことはできません。今日の金運は${money}点ですが、これは収支を整えやすい目安であって、賭けや偶然の収入を勧める意味ではありません。楽しむなら失っても困らない額を先に決め、拾得物は必ず届け出るのがいちばん運を下げない行動です。';
    return compactForMobile ? _shortText(answer, 180) : answer;
  }

  bool _isLongTermHealthQuestion(String question) {
    final value = question.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    const terms = [
      '長生き', '寿命', '何歳まで生き', '健康寿命', '一生健康', '健康に恵まれ',
      '心と体', '心身', '今後の健康', '将来の健康', '体の流れ', '体調の流れ',
    ];
    return terms.any(value.contains);
  }

  String _longTermHealthReading({
    required AstroProfile profile,
    required HoroscopeReadingContext contextData,
    required bool compactForMobile,
  }) {
    final moon = contextData.natal.placementOf(AstroPlanet.moon);
    final score = FortuneScoreCalculator.dailyArea(contextData, FortuneArea.mental, FortuneScoreCalculator.standardBase(FortuneArea.mental));
    final rhythm = switch (moon?.sign) {
      ZodiacSign.aries || ZodiacSign.leo || ZodiacSign.sagittarius =>
        '元気な時に動きすぎやすいため、疲れる前に休む予定を入れること',
      ZodiacSign.taurus || ZodiacSign.virgo || ZodiacSign.capricorn =>
        '睡眠・食事・通院などを同じ時間帯で続け、小さな変化を記録すること',
      ZodiacSign.gemini || ZodiacSign.libra || ZodiacSign.aquarius =>
        '情報や人とのやり取りを詰め込みすぎず、頭を休める時間を作ること',
      ZodiacSign.cancer || ZodiacSign.scorpio || ZodiacSign.pisces =>
        '気分の波を我慢だけで処理せず、睡眠と安心できる居場所を守ること',
      null => '無理なく続く睡眠・食事・休息の形を一つずつ整えること',
    };
    final answer = '結論: 寿命や将来の病気の有無は、出生図から断定できません。ただ、${profile.name}さんは${rhythm}が健康運を守る鍵です。今日の健康・メンタル運は${score}点なので、${score >= 78 ? '今は生活習慣を一つ始めて定着させやすい流れです。' : score < 62 ? '今は予定を増やさず、回復と現実の体調確認を優先してください。' : '今は無理な改善より、乱れやすい習慣を一つ戻すのが合います。'} 症状や検査、寿命の判断は占いに任せず、健診や医療機関で確認してください。';
    return compactForMobile ? _shortText(answer, 180) : answer;
  }

  bool _isLongTermWealthQuestion(String question) {
    final value = question.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    const terms = [
      '金持ち', 'お金持ち', '大金持ち', '億万長者', '資産家', '裕福', '富裕', '年収', '経済的自由',
      '一生お金に困ら', '財産を築', '大きく稼げ',
    ];
    return terms.any(value.contains);
  }

  DateTime? _dateFromQuestion(String question) {
    final value = question.replaceAll(RegExp(r'\s+'), '');
    final match = RegExp(r'(?:(\d{4})[年/.-])?(\d{1,2})[月/.-](\d{1,2})日?').firstMatch(value);
    if (match == null) return null;
    final year = int.tryParse(match.group(1) ?? '') ?? DateTime.now().year;
    final month = int.tryParse(match.group(2) ?? '');
    final day = int.tryParse(match.group(3) ?? '');
    if (month == null || day == null) return null;
    final parsed = DateTime(year, month, day, 12);
    if (parsed.year != year || parsed.month != month || parsed.day != day) return null;
    return parsed;
  }

  bool _isSpecificDateFortuneQuestion(String question) {
    if (_dateFromQuestion(question) == null) return false;
    final value = question.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    return const ['運', '運勢', '運気', '流れ', '調子', 'どう', '良い', '悪い', '注意', '気をつけ', '避け', '何に気を']
        .any(value.contains);
  }

  String _specificDateFortuneReading({
    required AstroProfile profile,
    required String question,
    required bool compactForMobile,
  }) {
    final date = _dateFromQuestion(question)!;
    final context = const AstrologyEngine().buildPreviewContext(profile: profile, date: date);
    final area = _fortuneAreaForQuestion(question);
    final score = area == FortuneArea.overall
        ? FortuneScoreCalculator.dailyOverall(context)
        : FortuneScoreCalculator.dailyArea(context, area, FortuneScoreCalculator.standardBase(area));
    final label = area == FortuneArea.overall ? '総合運' : _questionTopicLabel(_questionTopic(question));
    PlanetPlacement? moon;
    for (final placement in context.transit.placements) {
      if (placement.planet == AstroPlanet.moon) {
        moon = placement;
        break;
      }
    }
    final voidMoon = context.transit.voidMoon;
    final voidNote = voidMoon == null
        ? ''
        : voidMoon.contains(date)
            ? '月ボイド中なので、新しい約束や大きな決定は急がないで。'
            : '月ボイドは${voidMoon.label}なので、その時間は確認を一段増やして。';
    final flow = score >= 80
        ? '進めたいことを一つ形にしやすい日です。'
        : score < 62
            ? '急いで結論を出すより、予定と条件を見直す方が安全です。'
            : '小さく試して反応を見ながら進めると安定します。';
    final moonNote = moon == null ? '' : '月は${moon.sign.label}${moon.degree.toStringAsFixed(0)}度。';
    final answer = '結論: ${date.month}/${date.day}の$labelは${score}点。$flow $moonNote $voidNote 気をつけることは、返事・申込み・買い物を勢いだけで決めないことです。';
    return compactForMobile ? _shortText(answer, 180) : answer;
  }

  Future<String> _longTermWealthReading({
    required AstroProfile profile,
    required HoroscopeReadingContext contextData,
    required bool compactForMobile,
  }) async {
    final jupiter = contextData.natal.placementOf(AstroPlanet.jupiter);
    final venus = contextData.natal.placementOf(AstroPlanet.venus);
    final anchor = jupiter ?? venus;
    final method = switch (anchor?.sign) {
      ZodiacSign.aries || ZodiacSign.leo || ZodiacSign.sagittarius =>
        '自分の企画や表現を外へ出し、実績を増やす',
      ZodiacSign.taurus || ZodiacSign.virgo || ZodiacSign.capricorn =>
        '技術・品質・継続できる仕組みを積み上げる',
      ZodiacSign.gemini || ZodiacSign.libra || ZodiacSign.aquarius =>
        '情報、説明、人とのつながりを価値へ変える',
      ZodiacSign.cancer || ZodiacSign.scorpio || ZodiacSign.pisces =>
        '相手の必要を深く理解し、信頼される形で届ける',
      null => '得意なことを繰り返し届け、収入になる形を育てる',
    };
    final scene = switch (anchor?.house) {
      2 || 6 => '日々の仕事と技能',
      3 || 9 => '学び・発信・教えること',
      5 || 10 => '創作・自己表現・社会での評価',
      7 || 11 => '契約・顧客・仲間との協力',
      4 || 8 => '生活基盤・共有する資産の管理',
      1 || 12 => '自分の看板と表から見えない準備',
      _ => '続けられる仕事と人との信頼',
    };
    final score = FortuneScoreCalculator.dailyArea(contextData, FortuneArea.money, FortuneScoreCalculator.standardBase(FortuneArea.money));
    final timing = await _questionTimingWindow(
      profile,
      FortuneArea.money,
      topic: 'money',
      contextData: contextData,
    );
    final answer = '結論: お金持ち・億万長者・特定の年収になれると出生図だけで保証はできません。ただ、${profile.name}さんは、${scene}で「${method}」ほど収入の柱を育てやすい傾向です。現在の金運は${score}点。今後6週間では$timing 一発の当たりを狙うより、売れる技能・実績・継続収入を一つずつ増やし、金額と期限を記録する方が出生図の強みを現実の資産へ変えやすくなります。投資や契約は利益を前提にせず、損失上限を決めてください。';
    return compactForMobile ? _shortText(answer, 180) : answer;
  }

  bool _isLifeCourseQuestion(String question) {
    final value = question.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    const terms = [
      '人生は幸せ', '幸せな人生', '将来幸せ', '人生最大の転機', '人生の転機',
      '開運するには', '運気を上げるには', '運を良くするには',
    ];
    return terms.any(value.contains);
  }

  Future<String> _lifeCourseReading({
    required AstroProfile profile,
    required String question,
    required HoroscopeReadingContext contextData,
    required bool compactForMobile,
  }) async {
    final value = question.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    if (value.contains('転機')) {
      final today = DateTime.now();
      final birth = DateTime.tryParse(profile.birthDate);
      final candidates = <MapEntry<int, int>>[];
      for (var offset = 0; offset <= 10; offset++) {
        final year = today.year + offset;
        final date = DateTime(year, birth?.month ?? today.month, birth?.day ?? today.day, 12);
        final preview = const AstrologyEngine().buildPreviewContext(profile: profile, date: date);
        candidates.add(MapEntry(year, FortuneScoreCalculator.dailyOverall(preview)));
        await Future<void>.delayed(Duration.zero);
      }
      candidates.sort((a, b) => b.value.compareTo(a.value));
      final first = candidates[0];
      final second = candidates[1];
      final answer = '結論: 「人生最大」と一生分を断定はできませんが、今後10年の同じ季節を比較すると、${first.key}年が${first.value}点で最も流れを使いやすく、次が${second.key}年の${second.value}点です。転機は出来事が自動で起こる年ではなく、仕事・関係・住まいなどの選択を動かした時に形になります。強い年の前までに、続けたいものと手放すものを一つずつ決めておくと、追い風を現実の変化へつなげやすくなります。';
      return compactForMobile ? _shortText(answer, 180) : answer;
    }
    if (value.contains('開運') || value.contains('運気を上げ') || value.contains('運を良く')) {
      final scores = <FortuneArea, int>{
        FortuneArea.love: FortuneScoreCalculator.dailyArea(contextData, FortuneArea.love, FortuneScoreCalculator.standardBase(FortuneArea.love)),
        FortuneArea.work: FortuneScoreCalculator.dailyArea(contextData, FortuneArea.work, FortuneScoreCalculator.standardBase(FortuneArea.work)),
        FortuneArea.money: FortuneScoreCalculator.dailyArea(contextData, FortuneArea.money, FortuneScoreCalculator.standardBase(FortuneArea.money)),
        FortuneArea.mental: FortuneScoreCalculator.dailyArea(contextData, FortuneArea.mental, FortuneScoreCalculator.standardBase(FortuneArea.mental)),
      };
      final strongest = scores.entries.reduce((a, b) => a.value >= b.value ? a : b);
      final topic = switch (strongest.key) {
        FortuneArea.love => 'love',
        FortuneArea.work => 'work',
        FortuneArea.money => 'money',
        FortuneArea.mental => 'health',
        FortuneArea.overall => 'overall',
      };
      final timing = await _questionTimingWindow(
        profile,
        strongest.key,
        topic: topic,
        contextData: contextData,
      );
      final answer = '結論: 今の開運は、いちばん点の高い${strongest.key.label}（${strongest.value}点）を先に動かすことです。${_questionTopicAction(topic)}。今後6週間では$timing 開運用品や一発逆転より、強い分野で小さな結果を一つ作り、その余力を点の低い分野の整理へ回す方が、全体の運を現実的に持ち上げられます。';
      return compactForMobile ? _shortText(answer, 180) : answer;
    }
    final sun = contextData.natal.placementOf(AstroPlanet.sun);
    final fulfillment = switch (sun?.sign) {
      ZodiacSign.aries || ZodiacSign.leo || ZodiacSign.sagittarius =>
        '自分で選び、挑戦や表現を形にしている時',
      ZodiacSign.taurus || ZodiacSign.virgo || ZodiacSign.capricorn =>
        '安心できる土台を作り、役に立つ成果を積み上げている時',
      ZodiacSign.gemini || ZodiacSign.libra || ZodiacSign.aquarius =>
        '学び、人とつながり、自分の考えを伝えられている時',
      ZodiacSign.cancer || ZodiacSign.scorpio || ZodiacSign.pisces =>
        '信頼できる関係を育て、気持ちや想像力を大切にできている時',
      null => '自分の価値観に合う選択を続けられている時',
    };
    final overall = FortuneScoreCalculator.dailyOverall(contextData);
    final answer = '結論: 出生図は幸せ・不幸を決めませんが、${profile.name}さんは${fulfillment}に幸せを実感しやすい傾向です。現在の総合運は${overall}点。${overall >= 78 ? '今は望む生活へ近づく行動を一つ始める時です。' : overall < 62 ? '今は答えを急がず、負担を減らして土台を守る時です。' : '今は生活の中で続けたいものを一つ選び直す時です。'} 他人の基準だけで成功を決めず、時間・人間関係・仕事のうち、満たしたい条件を三つ書くと進む方向が具体化します。';
    return compactForMobile ? _shortText(answer, 180) : answer;
  }

  Future<String> _createLightCustomFortune({
    required AstroProfile profile,
    required String question,
    required HoroscopeReadingContext contextData,
  }) async => _lightCustomFallback(question);
  String? _smallTalkReply(String question) {
    final value = question.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    if (value.contains('色いい') || value.contains('色がいい') || value.contains('似合') ||
        value.contains('かわいい') || value.contains('かっこいい') || value.contains('きれい')) {
      return 'ありがとう。今日は少し気分が上がる色を選んでみました。そう言ってもらえると嬉しいです。';
    }
    if (value.contains('うんこ') || value.contains('うんち')) {
      return '急に来ましたね。今日はそのくらいくだらないことで笑える余白も大事そうです。';
    }
    if (value.contains('おはよう') || value.contains('こんにちは') || value.contains('こんばんは')) {
      return '声をかけてくれてありがとう。今日はどんなことを占ってみますか？';
    }
    if (value.contains('ありがとう') || value.contains('ありがと')) {
      return 'どういたしまして。気になる流れがあれば、そのまま続けて聞いてください。';
    }
    return null;
  }

  bool _isAstrologyTermQuestion(String question) {
    final value = question.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    const terms = [
      '占星術', 'ホロスコープ', '出生図', 'ネイタル', 'トランジット', 'アスペクト',
      'コンジャンクション', 'セクスタイル', 'スクエア', 'トライン', 'オポジション',
      'ハウス', 'asc', 'アセンダント', 'mc', 'ミッドヘブン', '逆行', 'リターン',
      'ボイド', '月ボイド', 'ステリウム', 'グランドトライン', 'オーブ', '星座',
      'ic', 'イムムコエリ', '支配星', 'ルーラー', 'ディグニティ', 'ディスポジター',
      'ノード', 'ドラゴンヘッド', 'ドラゴンテイル', 'シナストリー', 'コンポジット',
      'プログレス', '二次進行', 'ソーラーリターン', 'ルナリターン', 'ソーラーアーク',
    ];
    const explanationWords = [
      'とは', 'って何', 'とは何', '意味', '教えて', '解説', 'わから', '知りたい',
      '見方', '読み方', 'どう読む', '解釈', '使い方', '判断', 'オーブは',
    ];
    return terms.any(value.contains) && explanationWords.any(value.contains);
  }

  String _astrologyTermExplanation(String question, {required bool compactForMobile}) {
    final value = question.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    final explanation = switch (true) {
      _ when value.contains('ソーラーリターン') => 'ソーラーリターンは、太陽が出生時の位置へ戻る頃の図です。誕生日から次の誕生日までの一年で、何を前面に出しやすいかを読みます。',
      _ when value.contains('ルナリターン') => 'ルナリターンは、月が出生時の位置へ戻る頃の図です。約一か月の感情面、生活リズム、身近な出来事の流れを細かく見る時に使います。',
      _ when value.contains('ソーラーアーク') => 'ソーラーアークは、出生図の全要素を太陽の進行量だけ同じだけ動かして、人生の節目を読む技法です。正確な接触の時期を絞る補助に使います。',
      _ when value.contains('プログレス') || value.contains('二次進行') => 'プログレス（二次進行）は、生後一日を人生の一年に対応させて内面の成熟や長期の変化を読む技法です。トランジットと重ねて節目を絞ります。',
      _ when value.contains('シナストリー') => 'シナストリーは、二人の出生図を重ねて相性や関係の動き方を読む方法です。相手の星が自分のどの天体・ハウスへ触れるかを見ます。',
      _ when value.contains('コンポジット') => 'コンポジットは、二人の天体の中間点から作る関係そのものの図です。個人の相性とは別に、その関係が何を育てやすいかを読みます。',
      _ when value.contains('ディスポジター') => 'ディスポジターは、ある天体がいる星座の支配星のことです。星の力が最終的にどこへ流れるかを見るため、配置を一段深くつなげられます。',
      _ when value.contains('ディグニティ') => 'ディグニティは、天体が自分の力を出しやすい星座かどうかを見る考え方です。品位が良いかだけで決めず、ハウスやアスペクトと合わせて使います。',
      _ when value.contains('支配星') || value.contains('ルーラー') => '支配星（ルーラー）は、各星座を司る天体です。ハウスのカスプの星座から支配星を追うと、その分野の出来事がどこにつながりやすいかを読めます。',
      _ when value.contains('ドラゴンヘッド') || value.contains('ノード') => 'ノードは月の軌道と太陽の通り道が交わる点です。ドラゴンヘッドは伸ばしていく方向、ドラゴンテイルは慣れた資質や手放し方のテーマとして読みます。',
      _ when value.contains('ic') || value.contains('イムムコエリ') => 'IC（イムム・コエリ）は、出生図の底にある感受点です。家庭、居場所、安心の土台、内側のルーツを読み、MCと対になる軸として使います。',
      _ when value.contains('コンジャンクション') => 'コンジャンクションは、二つの星が同じ場所付近で重なる角度です。二つのテーマが強く一緒に出やすくなります。',
      _ when value.contains('セクスタイル') => 'セクスタイルは60度の角度です。意識して使うと、小さな機会や協力につながりやすい配置です。',
      _ when value.contains('スクエア') => 'スクエアは90度の角度です。引っかかりや課題が出やすい一方、調整すれば成長のきっかけになります。',
      _ when value.contains('トライン') => 'トラインは120度の角度です。無理なく使いやすい才能や追い風として出やすい配置です。',
      _ when value.contains('オポジション') => 'オポジションは180度の向かい合う角度です。相手や外側からの刺激を通して、バランスを取るテーマが出ます。',
      _ when value.contains('アスペクト') => 'アスペクトは、星と星の間にできる角度のことです。星の意味が、協力・緊張・強調のどの形で出やすいかを読みます。',
      _ when value.contains('asc') || value.contains('アセンダント') => 'ASC（アセンダント）は、生まれた時に東の空から上っていた星座です。第一印象、行動の始め方、外から見えやすい自分を表します。',
      _ when value.contains('mc') || value.contains('ミッドヘブン') => 'MC（ミッドヘブン）は、仕事、社会での役割、目指す方向を見る場所です。適職や評価の読みで特に使います。',
      _ when value.contains('ハウス') => 'ハウスは、星の働きが人生のどの分野に出るかを分けた12の部屋です。仕事、恋愛、お金、家庭などの場面を読み分けます。',
      _ when value.contains('逆行') => '逆行は、地球から見ると星が後ろへ動くように見える期間です。新しく急ぐより、見直し、再確認、やり直しに向きます。',
      _ when value.contains('リターン') => 'リターンは、現在の星が生まれた時の星の位置へ戻るタイミングです。その星のテーマを見直し、更新する節目として読みます。',
      _ when value.contains('ボイド') => '月ボイドは、月が次の星座へ移る前の空白時間です。新しい決定より、確認、準備、休息へ向けると安定しやすいと読みます。',
      _ when value.contains('ステリウム') => 'ステリウムは、複数の星が同じ星座やハウスへ集まる状態です。その分野が人生で強く出やすい傾向を表します。',
      _ when value.contains('グランドトライン') => 'グランドトラインは、三つの星が120度ずつの正三角形を作る配置です。才能や流れが自然につながりやすい形として読みます。',
      _ when value.contains('オーブ') => 'オーブは、アスペクトが成立すると考える角度の許容幅です。ぴったり近いほど、その影響は強く出やすいと読みます。',
      _ when value.contains('出生図') || value.contains('ネイタル') => '出生図（ネイタルチャート）は、生まれた時刻と場所の星の配置です。性格、得意な動き方、人生で繰り返しやすいテーマの土台を読みます。',
      _ when value.contains('トランジット') => 'トランジットは、今空を動いている星の配置です。出生図へ重ねて、今どのテーマが動きやすいかを読みます。',
      _ => 'ホロスコープは、生まれた時と現在の星の配置を図にしたものです。このアプリでは出生図と現在の星を重ね、日・週・月・年の流れを読みます。',
    };
    final practitionerQuestion = [
      '占い師', 'プロ', '実務', '読み方', '見方', 'どう読む', '解釈', '判断',
      'オーブ', '優先', '使い方',
    ].any(value.contains);
    if (practitionerQuestion) {
      final practitionerNote = switch (true) {
        _ when value.contains('オーブ') =>
          '占い師向けには、オーブを固定値だけで扱わず、太陽・月などの主要天体か、正確な角度へ接近中か、出生図かトランジットかで重みを変えます。まずタイトなアスペクト、次に接近中、最後にハウスと支配星で現れ方を絞ると読みが散りません。',
        _ when value.contains('アスペクト') || value.contains('コンジャンクション') || value.contains('セクスタイル') || value.contains('スクエア') || value.contains('トライン') || value.contains('オポジション') =>
          '占い師向けには、角度の吉凶だけで結論を出しません。関わる天体、サイン、ハウス、支配星、オーブ、接近・分離の順で確認します。同じスクエアでも、10ハウスなら仕事、7ハウスなら対人関係として現れ方が変わります。',
        _ when value.contains('トランジット') || value.contains('逆行') || value.contains('リターン') || value.contains('ボイド') =>
          '占い師向けには、出生図のどの天体・感受点へ触れるかを先に見ます。正確な日だけでなく接近・ピーク・分離を分け、トランジットの通過ハウスと逆行の有無を重ねて、起こりやすい場面と時期を絞ります。',
        _ when value.contains('ハウス') || value.contains('asc') || value.contains('アセンダント') || value.contains('mc') || value.contains('ミッドヘブン') =>
          '占い師向けには、その場所のサインだけで断定せず、在住天体、支配星の位置とアスペクト、トランジットで刺激される時期を重ねます。ASCは本人の出方、MCは社会的な役割として、同じ天体でも読み分けます。',
        _ =>
          '占い師向けには、用語を単独で決め手にせず、天体・サイン・ハウス・支配星・アスペクト・オーブ・時期を順に重ねます。出生図の素質とトランジットの時期を分けてから統合すると、占断が具体的になります。',
      };
      if (compactForMobile) return '$explanation ${_shortText(practitionerNote, 105)}';
      return '$explanation\n\n$practitionerNote';
    }
    if (compactForMobile) return explanation;
    return '$explanation 気になる言葉があれば、その言葉だけ続けて聞いてください。';
  }

  bool _isAstrologyApplicationQuestion(String question) {
    final value = question.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    const astroWords = [
      '太陽', '月が', '月と', '月は', '月の配置', '月星座', '出生図の月', '現在の月',
      '水星', '金星', '火星', '木星', '土星', '天王星', '海王星', '冥王星',
      'ハウス', 'コンジャンクション', 'セクスタイル', 'スクエア', 'トライン', 'オポジション',
      '逆行', '順行', 'リターン', '通過', 'アスペクト',
    ];
    const applicationWords = [
      '影響', '追い風', '良い配置', '活か', '注意', '転機', '運気', '伸ば', '避け', 'いつ',
      '今後', '幸運', '才能', 'メッセージ', '恋愛', '仕事', '金運', '健康', '人間関係', '学習',
    ];
    return astroWords.any(value.contains) && applicationWords.any(value.contains);
  }

  String? _invalidAstrologyPremiseReply(
    String question, {
    required bool compactForMobile,
  }) {
    final value = question.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    final sunRetrograde = RegExp(r'太陽(?:が|は|の)?[^。？！]{0,18}逆行').hasMatch(value);
    final moonRetrograde =
        RegExp(r'(?:出生図の|現在の)?月が[^。？！]{0,18}逆行').hasMatch(value) ||
        value.startsWith('月の逆行') ||
        value.startsWith('月逆行') ||
        value.contains('出生図の月の逆行') ||
        value.contains('現在の月の逆行');
    final sunMercuryOpposition = RegExp(r'(太陽.{0,12}水星|水星.{0,12}太陽).{0,16}(オポジション|180度)').hasMatch(value);
    final sunVenusOpposition = RegExp(r'(太陽.{0,12}金星|金星.{0,12}太陽).{0,16}(オポジション|180度)').hasMatch(value);
    if (!sunRetrograde && !moonRetrograde && !sunMercuryOpposition && !sunVenusOpposition) return null;
    if (sunMercuryOpposition || sunVenusOpposition) {
      final body = sunMercuryOpposition
          ? '太陽と水星は地球から見て大きく離れないため、通常の西洋占星術では180度のオポジションになりません。その前提での鑑定はせず、太陽と水星の合、または各天体と別の星の角度としてなら読み直せます。'
          : '太陽と金星は地球から見て大きく離れないため、通常の西洋占星術では180度のオポジションになりません。その前提での鑑定はせず、太陽と金星の合、または各天体と別の星の角度としてなら読み直せます。';
      return compactForMobile ? _shortText(body, 180) : body;
    }
    final body = sunRetrograde
        ? '太陽は占星術で逆行として扱いません。「太陽が逆行中」という前提は成立しないため、その部分を使った鑑定はできません。太陽の星座・ハウス・他の星との角度、または実際に逆行中の水星以遠の星からなら読み直せます。'
        : '月は通常の西洋占星術で逆行として扱いません。「月が逆行中」という前提は成立しないため、その部分を使った鑑定はできません。月の星座・ハウス・空白時間・他の星との角度からなら読み直せます。';
    return compactForMobile ? _shortText(body, 180) : body;
  }

  String _astrologyApplicationReading({
    required String question,
    required bool compactForMobile,
  }) {
    final value = question.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    final topic = _questionTopic(value);
    final label = _questionTopicLabel(topic);
    final condition = switch (true) {
      _ when value.contains('コンジャンクション') => '二つのテーマが強く重なり、一つに集中しやすい配置',
      _ when value.contains('セクスタイル') => '自分から使うほど小さな機会や協力につながりやすい配置',
      _ when value.contains('スクエア') => '引っかかりを調整するほど力へ変えやすい配置',
      _ when value.contains('トライン') => '無理なく使える強みや追い風が出やすい配置',
      _ when value.contains('オポジション') => '相手や外側からの刺激を通じて釣り合いを取る配置',
      _ when value.contains('逆行') => '新規に急ぐより、見直しや再挑戦で成果を拾いやすい時期',
      _ when value.contains('リターン') => '過去のやり方を更新し、その星のテーマをやり直す節目',
      _ when value.contains('通過') || value.contains('ハウス') => 'その人生分野が前面へ出て、具体的な予定が動きやすい時期',
      _ => 'その星のテーマが目立ち、意識して使うほど結果へつなげやすい配置',
    };
    final planetFocus = _astrologyPlanetFocus(value);
    final action = _questionTopicAction(topic);
    final caution = _questionTopicCaution(topic);
    final answer = '質問に書かれた配置を前提に読むと、$conditionです。$planetFocus $labelでは、$action を意識すると配置を活かしやすくなります。$caution 実際にあなたの出生図へある配置か、今どの程度強く働くかは、本格の星の詳細で照合するとより具体的に読めます。';
    return compactForMobile ? _shortText(answer, 180) : answer;
  }

  String _astrologyPlanetFocus(String value) {
    const meanings = <String, String>{
      '太陽': '自分らしさと意思',
      '月': '感情と生活リズム',
      '水星': '考え方と連絡',
      '金星': '好みと人との距離',
      '火星': '行動力と競争心',
      '木星': '成長と広がり',
      '土星': '責任と長期的な課題',
      '天王星': '変化と独自性',
      '海王星': '想像力と曖昧さ',
      '冥王星': '集中と根本的な変化',
    };
    final found = meanings.entries.where((entry) => value.contains(entry.key)).take(2).toList();
    if (found.isEmpty) return '';
    if (found.length == 1) {
      return '${found.first.key}は${found.first.value}を表すため、その部分が強調されます。';
    }
    return '${found[0].key}の${found[0].value}と、${found[1].key}の${found[1].value}が結びつく配置です。';
  }

  bool _isCurrentMoonFlowQuestion(String question) {
    final value = question.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    const moonTerms = ['月ボイド', 'ボイド', '月星座', '月が', '月獅子座', '月天秤座', '月の終わり', 'サイン終盤'];
    const stateTerms = ['気分', '気持ち', 'だる', '落ち', '下が', '眠', 'しんど', '影響', 'だから', 'せい', '終盤', '終わり'];
    return moonTerms.any(value.contains) && stateTerms.any(value.contains);
  }

  bool _isNatalProfileQuestion(String question) {
    final value = question.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    const profileWords = [
      '性格', '自分の特徴', '自分って', 'どんな人', '強み', '弱み', '才能',
      '恋愛傾向', '恋愛の傾向', '恋愛の癖', '恋愛のくせ',
      '仕事の傾向', '働き方の傾向', 'お金の傾向', '金運の傾向',
      '人生のテーマ', '人生テーマ', '人生の流れ', '人生傾向', '10年', '十年',
      '年代ごと', '何歳ごろの流れ', '何歳頃の流れ',
    ];
    return profileWords.any(value.contains);
  }

  String _natalProfileReading({
    required AstroProfile profile,
    required String question,
    required HoroscopeReadingContext contextData,
    required bool compactForMobile,
  }) {
    final value = question.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    PlanetPlacement? placement(AstroPlanet planet) => contextData.natal.placementOf(planet);
    final sun = placement(AstroPlanet.sun);
    final moon = placement(AstroPlanet.moon);
    final venus = placement(AstroPlanet.venus);
    final mars = placement(AstroPlanet.mars);
    final mercury = placement(AstroPlanet.mercury);
    final jupiter = placement(AstroPlanet.jupiter);
    final ascendant = placement(AstroPlanet.ascendant);
    final midheaven = placement(AstroPlanet.midheaven);
    String style(ZodiacSign? sign) => switch (sign) {
      ZodiacSign.aries => '自分から先に動く', ZodiacSign.taurus => 'じっくり安定させる',
      ZodiacSign.gemini => '会話と情報を使う', ZodiacSign.cancer => '安心できる人や場所を守る',
      ZodiacSign.leo => '自信を持って表現する', ZodiacSign.virgo => '整理して役立てる',
      ZodiacSign.libra => '人とのバランスを取る', ZodiacSign.scorpio => '深く集中して本音を扱う',
      ZodiacSign.sagittarius => '学びや挑戦へ広げる', ZodiacSign.capricorn => '目標へ着実に積み上げる',
      ZodiacSign.aquarius => '自分らしい新しい方法を選ぶ', ZodiacSign.pisces => '想像力と思いやりを使う',
      null => '自分に合う形を選び直す',
    };
    String scene(int? house) => switch (house) {
      1 => '自分の見せ方や始め方', 2 => 'お金と大切にするもの',
      3 => '学び、会話、身近な行動', 4 => '家や安心できる基盤',
      5 => '恋愛、創作、楽しみ', 6 => '日々の仕事、体調、習慣',
      7 => '対人関係や約束', 8 => '深い関係や共有すること',
      9 => '学びや視野を広げること', 10 => '仕事、評価、社会での役割',
      11 => '仲間、目標、これからの計画', 12 => '休息や心の整理',
      _ => '日常の選び方',
    };
    final lifeQuestion = ['人生の流れ', '人生傾向', '10年', '十年', '年代ごと', '何歳'].any(value.contains);
    final relationshipQuestion = ['恋愛傾向', '恋愛の傾向', '恋愛の癖', '恋愛のくせ'].any(value.contains);
    final workQuestion = ['仕事の傾向', '働き方の傾向'].any(value.contains);
    final moneyQuestion = ['お金の傾向', '金運の傾向'].any(value.contains);
    final mindQuestion = value.contains('性格') || value.contains('自分って') || value.contains('どんな人');
    if (lifeQuestion) {
      final birthYear = int.tryParse(RegExp(r'\d{4}').firstMatch(profile.birthDate)?.group(0) ?? '');
      final age = birthYear == null ? null : DateTime.now().year - birthYear;
      final decade = age == null ? null : (age ~/ 10) * 10;
      final driverPlanet = switch (decade) {
        0 => AstroPlanet.moon, 10 => AstroPlanet.mercury, 20 => AstroPlanet.venus,
        30 => AstroPlanet.midheaven, 40 => AstroPlanet.jupiter, 50 => AstroPlanet.saturn,
        60 => AstroPlanet.uranus, 70 => AstroPlanet.neptune, _ => AstroPlanet.pluto,
      };
      final driver = placement(driverPlanet) ??
          (driverPlanet == AstroPlanet.midheaven ? sun : null);
      final focus = switch (driverPlanet) {
        AstroPlanet.moon => '安心感と心の土台', AstroPlanet.mercury => '学び、言葉、得意な伝え方',
        AstroPlanet.venus => '好み、人との距離、楽しみ', AstroPlanet.midheaven => '仕事、評価、社会での役割',
        AstroPlanet.jupiter => '成長、学び、選択肢の広がり', AstroPlanet.saturn => '責任、継続、長く残る土台',
        AstroPlanet.uranus => '変化、自由、自分らしい選び方', AstroPlanet.neptune => '共感、想像力、心の豊かさ',
        _ => '深い変化、集中、受け渡す力',
      };
      final answer = '${profile.name}さんの人生の大きな軸は、${style(sun?.sign)}自分らしさを形にし、${style(midheaven?.sign)}社会で役割を作ることです。${age == null ? '' : '今は${age}歳前後で、$focusが中心になりやすい年代です。出生図ではこの力が${scene(driver?.house)}に表れやすいため、${style(driver?.sign)}形で取り組むほど手応えにつながります。'} 出来事を決めつける年表ではなく、何へ時間を寄せると自分らしく力を使えるかを見る目安です。';
      return compactForMobile ? _shortText(answer, 180) : answer;
    }
    if (relationshipQuestion) {
      final answer = '${profile.name}さんは、好意を${style(venus?.sign)}形で受け取り、気持ちが動くと${style(mars?.sign)}行動に出やすい傾向です。相手の言葉だけで判断せず、会話が続くか・約束を実行してくれるかを両方見るほど、無理のない関係を選べます。';
      return compactForMobile ? _shortText(answer, 180) : answer;
    }
    if (workQuestion) {
      final answer = '${profile.name}さんは、${style(mercury?.sign)}考えを扱い、${style(midheaven?.sign)}仕事の役割を作るほど力が出ます。向くのは、完成条件と届ける相手が見える仕事です。作業を細かくして終わりを作るほど、持ち味が評価と収入につながりやすくなります。';
      return compactForMobile ? _shortText(answer, 180) : answer;
    }
    if (moneyQuestion) {
      final answer = '${profile.name}さんのお金の伸ばし方は、${style(jupiter?.sign)}経験や得意を人に役立つ形へ変えることです。一発で増やすより、続けられる技術・実績・人とのつながりへ時間を使うほど、選べる収入源が育ちやすい傾向です。';
      return compactForMobile ? _shortText(answer, 180) : answer;
    }
    final standout = contextData.natal.stelliums.isNotEmpty
        ? '特に${contextData.natal.stelliums.map((item) => item.theme).join('・')}が人生で繰り返しやすいテーマです。'
        : FortuneScoreCalculator.hasNatalKite(contextData)
            ? '得意なことを外へ向けて動かすほど、才能を実用的な成果に変えやすい出生図です。'
            : '';
    final answer = '${profile.name}さんは、${style(sun?.sign)}自分らしさと、${style(ascendant?.sign)}第一歩の出し方が土台です。心は${style(moon?.sign)}安心感を求めやすく、無理に周囲へ合わせ続けるより、自分のペースを作るほど持ち味が出ます。$standout';
    return compactForMobile ? _shortText(answer, 180) : answer;
  }

  String _currentMoonFlowReading({
    required String question,
    required HoroscopeReadingContext contextData,
    required bool compactForMobile,
  }) {
    final moon = FortuneScoreCalculator._placement(contextData.transit.placements, AstroPlanet.moon);
    final voidMoon = contextData.transit.voidMoon;
    final now = contextData.transit.date;
    final inVoid = voidMoon?.contains(now) ?? false;
    final voidText = switch ((voidMoon, inVoid)) {
      (null, _) => '今日は月ボイドの時間帯は確認されていません。',
      (_, true) => 'いまは月ボイド（${voidMoon!.label}）の時間内なので、気分が散りやすく、結論を急ぐほど疲れを感じやすい流れです。',
      (_, false) when voidMoon!.startTime.isAfter(now) =>
        '月ボイドは${voidMoon.label}からです。今の時点では主な原因とまでは言えません。',
      (_, false) => '月ボイドは${voidMoon!.label}で、いまはその時間帯を過ぎています。',
    };
    if (moon == null) return compactForMobile ? _shortText(voidText, 170) : voidText;

    final lateSign = moon.degree >= 24.0;
    final signText = lateSign
        ? '月は${moon.sign.label}${moon.degree.toStringAsFixed(0)}度でサイン終盤です。次のサインへ切り替わる前は、気持ちが一度落ち着かず、今までの疲れが出やすいことがあります。'
        : '月は${moon.sign.label}${moon.degree.toStringAsFixed(0)}度で、まだサイン終盤ではありません。';
    final conclusion = inVoid && lateSign
        ? '今回は月ボイドと月のサイン終盤が重なっているため、両方が気分の下がりやすさに関係していそうです。'
        : inVoid
            ? '今回は月ボイドの影響が中心です。'
            : lateSign
                ? '今回は月のサイン終盤による切り替わり疲れの方が近そうです。'
                : '月ボイドやサイン終盤だけで決めず、睡眠・食事・予定の詰め込みも一緒に整える方がよさそうです。';
    final action = '今日は無理に理由を決めず、返信や判断を一つだけ後回しにして、温かいものと短い休憩で整えるのが向きます。';
    final answer = '$conclusion $voidText $signText $action';
    return compactForMobile ? _shortText(answer, 180) : answer;
  }

  bool _isChatFollowUp(String question, List<CustomFortuneLog> previousLogs) {
    if (previousLogs.isEmpty) return false;
    final value = question.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    if (value.isEmpty || value.length > 80) return false;
    const followUpWords = [
      'どういうこと', '詳しく', 'それ', 'じゃあ', 'つまり', 'なんで', 'なぜ', '本当', 'ほんと',
      '教えて', 'もう少し', '具体的に', '例えば', 'どのへん', 'どうして',
    ];
    return followUpWords.any(value.contains) || _isReplyToAssistantQuestion(value, previousLogs);
  }

  bool _isReplyToAssistantQuestion(String value, List<CustomFortuneLog> previousLogs) {
    if (value.length > 48) return false;
    final lastAnswer = previousLogs.first.answer;
    if (!lastAnswer.contains('？') && !lastAnswer.contains('?')) return false;
    const standaloneReplies = [
      '時間', '移動', '人とのやり取り', '人間関係', 'お金', '体調', 'はい', 'いいえ', 'そう', '違う',
    ];
    return standaloneReplies.any(value.contains) || value.endsWith('かな') || value.endsWith('です');
  }

  Future<String> _createChatFollowUp({
    required String question,
    required HoroscopeReadingContext contextData,
    required List<CustomFortuneLog> previousLogs,
  }) async => _chatFollowUpFallback(question);
  String _chatFollowUpFallback(String question) {
    final value = question.replaceAll(RegExp(r'\s+'), '');
    if (value.contains('なんで') || value.contains('なぜ') || value.contains('どうして')) {
      return '前の答えは、今の流れを急いで結論にするより、動きやすい時期と条件を見て判断した方がいい、という意味です。';
    }
    if (value.contains('詳しく') || value.contains('具体的に') || value.contains('例えば')) {
      return '前の答えの中で気になる一文をそのまま送ってくれれば、その部分だけ短く具体化して説明します。';
    }
    return '前の鑑定の流れを、今回の質問に合わせて短く言い直します。気になる言葉を一つ挙げてくれれば、そこを中心に説明します。';
  }

  bool _isLightCustomQuestion(String question) {
    final value = question.replaceAll(RegExp(r'\s+'), '').trim();
    if (value.isEmpty || value.length > 40) return false;
    const seriousWords = [
      '仕事', '収入', 'お金', '金運', '恋愛', '好き', '相手', '将来', '人生', '健康', '体調',
      '病院', '不安', '転職', '試合', '勝ち', '家族', '結婚', '動画', 'Youtube', '再生数',
      '彼女', '彼氏', '出会', '付き合', 'パートナー', '離婚', '妊娠', '合格', '進学',
    ];
    if (seriousWords.any(value.contains)) return false;
    const playfulWords = [
      '食べ', '飲み', '眠い', '寝たい', 'だるい', '暇', '風呂', 'ゲーム', 'ガチャ', 'ラーメン',
      'カレー', 'おやつ', 'アイス', '行くべき', 'やめとく', 'どっち', 'くだら', 'どうでも',
      'うんこ', 'うんち', '色いい', '色がいい', '似合', 'かわいい', 'かっこいい', 'きれい',
    ];
    // 疑問符や短さだけで人生相談を軽い返答へ落とさない。
    return playfulWords.any(value.contains);
  }

  bool _isCareerFitQuestion(String question) {
    final value = question.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    const expressionJobs = [
      'ミュージシャン', '音楽家', '歌手', 'バンド', '演奏', '作曲', '編曲', '音楽制作',
      'アーティスト', '俳優', '声優', '作家', '小説家', 'イラスト', 'デザイナー',
    ];
    final workQuestion = value.contains('仕事') ||
        value.contains('職業') ||
        value.contains('働') ||
        value.contains('天職') ||
        value.contains('起業') ||
        value.contains('独立') ||
        value.contains('社長') ||
        value.contains('経営') ||
        expressionJobs.any(value.contains);
    final fitQuestion = value.contains('向いて') ||
        value.contains('適職') ||
        value.contains('天職') ||
        value.contains('合って') ||
        value.contains('あって') ||
        value.contains('続けて') ||
        value.contains('適性') ||
        value.contains('どんな仕事') ||
        value.contains('どの仕事');
    final careerSentence = RegExp(
      r'(どんな|どの|何).{0,8}(仕事|職業)|(?:仕事|職業).{0,12}(向|合|あ|続|いい|どう|適)',
    ).hasMatch(value);
    final namedJobFit = _jobTargetFromQuestion(value) != null;
    return (workQuestion && (fitQuestion || careerSentence || expressionJobs.any(value.contains))) ||
        namedJobFit;
  }

  bool _isHealthIncomeQuestion(String question) {
    final value = question.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    const healthWords = ['病気', '持病', '療養', '通院', '体調', '健康', '症状', '痛み', '障害'];
    const incomeWords = ['稼げ', '収入', 'お金', '生活費', '働け', '仕事', '就労'];
    return healthWords.any(value.contains) && incomeWords.any(value.contains);
  }

  bool _isMoneyHardshipQuestion(String question) {
    final value = question.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    const hardshipWords = ['お金がない', '金がない', '金欠', '生活費', '支払い', '払えない', '借金', '赤字'];
    return hardshipWords.any(value.contains);
  }

  bool _isTodayFortuneQuestion(String question) {
    final value = question.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    final hasToday = value.contains('今日') || value.contains('きょう');
    final asksFortune = ['運', '占い', 'どう', '良い', '悪い', '向いて', '始め', '続け', 'やめ']
        .any(value.contains);
    return hasToday && (asksFortune || _questionTopic(value) != 'overall');
  }

  bool _isPeriodFortuneQuestion(String question) {
    final value = question.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    const periodWords = ['今週', '来週', '今月', '来月', '今年', '来年', '1か月', '1ヶ月', '3か月', '3ヶ月', '半年', '6か月', '6ヶ月', '2年', '3年', '5年', '数年', '長期'];
    const fortuneWords = [
      '運', '占い', 'どう', '良い', '悪い', '向いて', '始め', '続け', 'やめ', '成果',
      '成功', '注意', 'チャンス', '転機', '飛躍',
    ];
    return periodWords.any(value.contains) &&
        (fortuneWords.any(value.contains) || _questionTopic(value) != 'overall');
  }

  bool _isStartTimingComparisonQuestion(String question) {
    final value = question.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    return value.contains('今月始め') && value.contains('来月始め') &&
        ['どちら', '比較', 'どっち'].any(value.contains);
  }

  String _startTimingComparisonReading({
    required AstroProfile profile,
    required String question,
    required bool compactForMobile,
  }) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 12);
    final nextMonthLastDay = DateTime(now.year, now.month + 2, 0).day;
    final nextMonth = DateTime(now.year, now.month + 1, math.min(now.day, nextMonthLastDay), 12);
    final area = _fortuneAreaForQuestion(question);
    int score(DateTime date) {
      final context = const AstrologyEngine().buildPreviewContext(profile: profile, date: date);
      return area == FortuneArea.overall
          ? FortuneScoreCalculator.dailyOverall(context)
          : FortuneScoreCalculator.dailyArea(context, area, FortuneScoreCalculator.standardBase(area));
    }
    final nowScore = score(today);
    final nextScore = score(nextMonth);
    final label = area == FortuneArea.overall ? '総合運' : _questionTopicLabel(_questionTopic(question));
    final nowLabel = '${today.month}/${today.day}頃';
    final nextLabel = '${nextMonth.month}/${nextMonth.day}頃';
    final chooseNow = nowScore >= nextScore;
    final selectedLabel = chooseNow ? '今月' : '来月';
    final selectedDate = chooseNow ? nowLabel : nextLabel;
    final selectedScore = chooseNow ? nowScore : nextScore;
    final otherScore = chooseNow ? nextScore : nowScore;
    final answer = '結論: $labelで始めるなら$selectedLabel（$selectedDate、${selectedScore}点）寄りです。${chooseNow ? '今月は準備と最初の一歩を形にしやすい流れです。' : '今月は下準備に回し、来月に公開・申込み・本格始動を置く方が流れを使いやすいです。'} もう一方は${otherScore}点なので、完全に止めるのではなく、情報集めや条件整理へ使うと無駄になりません。';
    return compactForMobile ? _shortText(answer, 180) : answer;
  }

  bool _isRelativeDayFortuneQuestion(String question) {
    final value = question.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    final hasRelativeDay = value.contains('明日') ||
        value.contains('あした') ||
        value.contains('明後日') ||
        value.contains('あさって');
    return hasRelativeDay &&
        (['運', 'どう', '良い', '悪い', '向いて', '始め', '続け'].any(value.contains) ||
            _questionTopic(value) != 'overall');
  }

  bool _isRecentFortuneQuestion(String question) {
    final value = question.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    const recentWords = ['最近', '近頃', '直近', 'ここ数日', 'この頃', '今の'];
    const fortuneWords = ['運', '運勢', '運気', '流れ', '調子', 'どう', '良い', '悪い'];
    return recentWords.any(value.contains) && fortuneWords.any(value.contains);
  }

  bool _isAreaFortuneQuestion(String question) {
    final value = question.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    const fortuneWords = ['運', '運勢', '運気', '流れ', '調子', 'どう', '良い', '悪い'];
    return _questionTopic(value) != 'overall' && fortuneWords.any(value.contains);
  }

  String _relativeDayFortuneReading({
    required AstroProfile profile,
    required String question,
    required bool compactForMobile,
  }) {
    final value = question.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    final offset = value.contains('明後日') || value.contains('あさって') ? 2 : 1;
    final date = DateTime.now().add(Duration(days: offset));
    final context = const AstrologyEngine().buildPreviewContext(
      profile: profile,
      date: DateTime(date.year, date.month, date.day, 12),
    );
    final topic = _questionTopic(value);
    final area = _fortuneAreaForQuestion(question);
    final score = area == FortuneArea.overall
        ? FortuneScoreCalculator.dailyOverall(context)
        : FortuneScoreCalculator.dailyArea(context, area, FortuneScoreCalculator.standardBase(area));
    final label = topic == 'overall' ? '総合運' : _questionTopicLabel(topic);
    final action = '${_questionPeriodAction(topic)}。';
    final dayLabel = offset == 1 ? '明日' : '明後日';
    final core = '$dayLabelの$labelは${score}点です。${score >= 80 ? '追い風を使いやすい日。' : score < 62 ? '無理な決定は避けたい日。' : '確認しながら動くと安定する日。'}$action';
    return compactForMobile ? '結論: $core' : '結論: $core 今の出生図とその日の星の動きが重なるため、この分野を優先すると流れを使いやすくなります。';
  }

  FortuneArea _fortuneAreaForQuestion(String question) {
    final value = question.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    return _questionTopicArea(_questionTopic(value));
  }

  String _recentFortuneReading({
    required AstroProfile profile,
    required String question,
    required bool compactForMobile,
  }) {
    final value = question.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    final topic = _questionTopic(value);
    final area = _fortuneAreaForQuestion(question);
    final now = DateTime.now();
    final dates = List.generate(
      7,
      (index) => DateTime(now.year, now.month, now.day + index, 12),
    );
    final candidates = dates.map((date) {
      final context = const AstrologyEngine().buildPreviewContext(profile: profile, date: date);
      final score = area == FortuneArea.overall
          ? FortuneScoreCalculator.dailyOverall(context)
          : FortuneScoreCalculator.dailyArea(context, area, FortuneScoreCalculator.standardBase(area));
      return MapEntry(date, score);
    }).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final peak = candidates.first;
    final careful = candidates.last;
    final label = topic == 'overall' ? '総合運' : _questionTopicLabel(topic);
    final peakLabel = '${peak.key.month}/${peak.key.day}頃';
    final carefulLabel = '${careful.key.month}/${careful.key.day}頃';
    final action = _questionPeriodAction(topic);
    final core = '直近7日の$labelは、$peakLabel頃が${peak.value}点で最も動かしやすい時です。$carefulLabel頃は${careful.value}点なので、結論を急がず確認を優先して。';
    if (compactForMobile) return '結論: $core 強い日は、$action と流れを使えます。';
    return '結論: $core 進め方: 強い日は、$action と流れを使えます。気をつけること: 注意日に大きな決定を詰め込まず、連絡・締切・体力配分を一度見直してください。';
  }

  String _periodFortuneReading({
    required AstroProfile profile,
    required String question,
    required bool compactForMobile,
  }) {
    final value = question.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    final topic = _questionTopic(value);
    final area = _fortuneAreaForQuestion(question);
    final now = DateTime.now();
    late final List<DateTime> dates;
    late final String periodLabel;
    late final String Function(DateTime) peakLabel;
    if (value.contains('今週') || value.contains('来週')) {
      final monday = DateTime(now.year, now.month, now.day, 12)
          .subtract(Duration(days: now.weekday - 1));
      final start = monday.add(Duration(days: value.contains('来週') ? 7 : 0));
      dates = List.generate(7, (index) => start.add(Duration(days: index)));
      periodLabel = value.contains('来週') ? '来週' : '今週';
      peakLabel = (date) => '${date.month}/${date.day}頃';
    } else if (value.contains('今月') || value.contains('来月')) {
      final monthOffset = value.contains('来月') ? 1 : 0;
      final start = DateTime(now.year, now.month + monthOffset, 1, 12);
      final end = DateTime(start.year, start.month + 1, 1, 12);
      dates = <DateTime>[];
      for (var date = start; date.isBefore(end); date = date.add(const Duration(days: 1))) {
        dates.add(date);
      }
      periodLabel = '${start.month}月';
      peakLabel = (date) => '${date.month}/${date.day}頃';
    } else if (value.contains('1か月') || value.contains('1ヶ月') || value.contains('3か月') || value.contains('3ヶ月')) {
      final months = value.contains('3か月') || value.contains('3ヶ月') ? 3 : 1;
      dates = List.generate(
        months,
        (index) => DateTime(now.year, now.month + index, 15, 12),
      );
      periodLabel = months == 1 ? '今後1か月' : '今後3か月';
      peakLabel = (date) => '${date.month}/${date.day}頃';
    } else {
      final years = value.contains('5年')
          ? 5
          : value.contains('3年') || value.contains('数年') || value.contains('長期')
              ? 3
              : value.contains('2年')
                  ? 2
                  : 1;
      final months = value.contains('半年') || value.contains('6か月') || value.contains('6ヶ月')
          ? 6
          : years * 12;
      final year = now.year + (value.contains('来年') ? 1 : 0);
      dates = List.generate(months, (index) => DateTime(year, index + 1, 15, 12));
      final end = dates.last;
      periodLabel = months <= 12 ? '${year}年' : '${year}年${1}月〜${end.year}年${end.month}月';
      peakLabel = (date) => '${date.year}年${date.month}月';
    }
    final candidates = dates.map((date) {
      final context = const AstrologyEngine().buildPreviewContext(profile: profile, date: date);
      final score = area == FortuneArea.overall
          ? FortuneScoreCalculator.dailyOverall(context)
          : FortuneScoreCalculator.dailyArea(context, area, FortuneScoreCalculator.standardBase(area));
      return MapEntry(date, score);
    }).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final peak = candidates.first;
    final careful = candidates.last;
    final areaLabel = topic == 'overall' ? '総合運' : _questionTopicLabel(topic);
    final action = _questionPeriodAction(topic);
    final longTerm = dates.length > 12;
    final yearlyFlow = <String>[];
    if (longTerm) {
      final grouped = <int, List<int>>{};
      for (final item in candidates) {
        (grouped[item.key.year] ??= <int>[]).add(item.value);
      }
      for (final entry in grouped.entries.toList()..sort((a, b) => a.key.compareTo(b.key))) {
        final average = entry.value.reduce((a, b) => a + b) ~/ entry.value.length;
        yearlyFlow.add('${entry.key}年 ${average}点');
      }
    }
    if (compactForMobile) {
      return '結論: $periodLabelの$areaLabelは、${peakLabel(peak.key)}頃が最も強く${peak.value}点です。${peakLabel(careful.key)}頃は${careful.value}点なので無理な決定は避けて。強い時期は、$action と流れを使えます。';
    }
    return '結論: $periodLabelの$areaLabelは、${peakLabel(peak.key)}頃が最も強く${peak.value}点です。${peakLabel(careful.key)}頃は${careful.value}点で、予定を詰め込みすぎず確認を優先した方が安定します。${yearlyFlow.isEmpty ? '' : ' 年ごとの平均は${yearlyFlow.join(' / ')}です。'} 進め方: 強い時期には、$action と流れを使えます。その前に必要な準備を一つ終え、反応や結果を見て次の一手を決めましょう。気をつけること: 点の低い時期は結論を急がず、連絡・支払い・体力配分を見直してください。';
  }

  String _moneyHardshipReading({
    required AstroProfile profile,
    required HoroscopeReadingContext contextData,
    required bool compactForMobile,
  }) {
    final score = FortuneScoreCalculator.dailyArea(contextData, FortuneArea.money, FortuneScoreCalculator.standardBase(FortuneArea.money));
    final flow = score >= 80
        ? '今は、入る見込みや返ってくるお金を確認して、回収へ動きやすい流れです。'
        : score < 62
            ? '今は、増やす話を急ぐより、支払いの優先順位と期限を見える形にする方が損を減らせます。'
            : '今は、収入を一気に増やすより、出ていくお金を分けて管理すると立て直しやすい流れです。';
    if (compactForMobile) {
      return '結論: ${profile.name}さんの金運は${score}点。$flow 今日中に、今週払う物・待てる物・相談できる物の3つへ分け、最優先の一件だけ連絡か確認をしてください。';
    }
    return '結論: ${profile.name}さんの金運は${score}点で、$flow 進め方: 今日中に、今週払う物・待てる物・相談できる物の3つへ分け、金額と期限を並べてください。最優先の一件だけ連絡か確認をし、収入を作る行動は負担の少ないものを一つに絞りましょう。気をつけること: 焦って高金利の借入や条件の悪い契約へ進まず、必要なら自治体や公的な生活・債務相談窓口へ早めに確認してください。';
  }

  String _todayFortuneReading({
    required AstroProfile profile,
    required String question,
    required HoroscopeReadingContext contextData,
    required bool compactForMobile,
  }) {
    final scores = <FortuneArea, int>{
      FortuneArea.love: FortuneScoreCalculator.dailyArea(contextData, FortuneArea.love, FortuneScoreCalculator.standardBase(FortuneArea.love)),
      FortuneArea.work: FortuneScoreCalculator.dailyArea(contextData, FortuneArea.work, FortuneScoreCalculator.standardBase(FortuneArea.work)),
      FortuneArea.money: FortuneScoreCalculator.dailyArea(contextData, FortuneArea.money, FortuneScoreCalculator.standardBase(FortuneArea.money)),
      FortuneArea.mental: FortuneScoreCalculator.dailyArea(contextData, FortuneArea.mental, FortuneScoreCalculator.standardBase(FortuneArea.mental)),
    };
    final strongest = scores.entries.reduce((a, b) => a.value >= b.value ? a : b);
    final weakest = scores.entries.reduce((a, b) => a.value <= b.value ? a : b);
    final overall = FortuneScoreCalculator.dailyOverall(contextData);
    final areaLabel = strongest.key.label.replaceAll('・メンタル', '');
    final carefulLabel = weakest.key.label.replaceAll('・メンタル', '');
    final topic = _questionTopic(question.replaceAll(RegExp(r'\s+'), '').toLowerCase());
    if (topic != 'overall') {
      final topicArea = _questionTopicArea(topic);
      final topicScore = FortuneScoreCalculator.dailyArea(contextData, topicArea, FortuneScoreCalculator.standardBase(topicArea));
      final label = _questionTopicLabel(topic);
      final state = _decisionReadingState(contextData, topicArea, topicScore);
      final action = _questionTopicAction(topic);
      final caution = _questionTopicCaution(topic);
      final answer = '結論: ${profile.name}さんの今日の$labelは$topicScore点です。${state.decision} ${state.reason} $action $caution';
      return compactForMobile ? _shortText(answer, 180) : answer;
    }
    final action = switch (strongest.key) {
      FortuneArea.love => '連絡したい相手へ短く一言送りましょう。',
      FortuneArea.work => '止まっている作業を一つだけ終わらせましょう。',
      FortuneArea.money => '支出か回収の確認を一件だけ進めましょう。',
      FortuneArea.mental => '予定を一つ減らして回復する時間を取りましょう。',
      FortuneArea.overall => '一番大事なことを先に片づけましょう。',
    };
    if (compactForMobile) {
      return '結論: ${profile.name}さんの今日の総合運は${overall}点。いちばん追い風が強いのは$areaLabel（${strongest.value}点）です。$action 注意は$carefulLabel（${weakest.value}点）なので、ここは急がず確認を。';
    }
    return '結論: ${profile.name}さんの今日の総合運は${overall}点です。いちばん追い風が強いのは$areaLabelで${strongest.value}点、反対に慎重に扱いたいのは$carefulLabelで${weakest.value}点です。進め方: $action 今日の星の流れは、得意な分野を一つ進めてから慎重な分野を整える順番が合います。気をつけること: 低めの分野は勢いだけで決めず、返事・支払い・予定を一度見直してください。';
  }

  String _healthIncomeReading({
    required AstroProfile profile,
    required String question,
    required HoroscopeReadingContext contextData,
    required bool compactForMobile,
  }) {
    final score = FortuneScoreCalculator.dailyOverall(contextData);
    HouseTransit? healthTransit;
    for (final transit in contextData.houseTransits) {
      if (transit.natalHouse == 6 || transit.natalHouse == 12) {
        healthTransit = transit;
        break;
      }
    }
    final astroFocus = switch (healthTransit?.natalHouse) {
      6 => '今は、生活リズムと作業量を整えるほど、働く条件が見えやすくなっています。',
      12 => '今は、表に出る量を増やすより、回復と見えない負担の整理を優先した方が流れに合います。',
      _ => '今は、無理なく続けられる条件を見直すほど、次の働き方を選びやすい流れです。',
    };
    final phase = score < 66
        ? '今は、収入を急いで増やすために無理を重ねるより、体調を崩さず続けられる条件を先に固める時です。'
        : score >= 82
            ? '今は、体調の条件を守りながら小さな収入の入口を作り直す動きに追い風があります。'
            : '今は、回復と収入を一度に取り戻そうとせず、負担の少ない形を一つずつ試すほど流れを立て直しやすい時です。';
    final detailLevel = _customQuestionDetailLevel(question);
    final conclusion = '結論: ${profile.name}さんは、病気の負担を抱えたまま普通の働き方へ合わせにいくより、「できる時間・姿勢や移動の負担・締切への対応」を先に決めて、その範囲で収入の形を選ぶ方が現実も流れも整いやすいです。$astroFocus $phase';
    final practical = '進め方: まず一週間だけ、体調が比較的動ける時間帯と、15〜30分で終えられる作業を書き出してください。その中から在宅でできる連絡、整理、制作、入力など、途中で休める作業を一つだけ試し、終えた後の疲れ方も記録します。';
    final support = '主治医や自治体・就労相談の窓口へ「今の体調で可能な働き方と使える支援」を確認し、求人や制度は条件を比べてから選びましょう。治療や働ける量、制度利用の可否は占いで決めず、医療者・公的な相談先と一緒に判断してください。';
    const followUp = '差し支えなければ、今いちばん負担が大きいのは「時間・移動・人とのやり取り」のどれに近いですか？';
    if (compactForMobile) {
      return '結論: ${profile.name}さんは、無理に普通の働き方へ合わせるより、体調を崩さない時間・移動・締切の条件を決めて収入の形を選ぶ方が整います。$astroFocus まず15〜30分で終わる作業を一つだけ試してください。$followUp';
    }
    if (detailLevel >= 2) return '$conclusion\n\n$practical\n\n$support\n\n$followUp';
    return '$conclusion\n\n$practical $support\n\n$followUp';
  }

  String _careerFitReading({
    required AstroProfile profile,
    required HoroscopeReadingContext contextData,
    required String question,
    required bool compactForMobile,
  }) {
    PlanetPlacement? placementFor(AstroPlanet planet) {
      for (final placement in contextData.natal.placements) {
        if (placement.planet == planet) return placement;
      }
      return null;
    }

    final careerAxis = placementFor(AstroPlanet.midheaven) ??
        placementFor(AstroPlanet.sun) ??
        contextData.natal.placements.first;
    final mercury = placementFor(AstroPlanet.mercury) ?? careerAxis;
    final role = _careerRoleForSign(careerAxis.sign);
    final fields = _careerFieldsForSign(careerAxis.sign);
    final skill = _careerSkillForSign(mercury.sign);
    final currentJob = _currentJobFromQuestion(question);
    HouseTransit? currentWorkTransit;
    for (final transit in contextData.houseTransits) {
      if (transit.natalHouse == 6 || transit.natalHouse == 10 || transit.natalHouse == 11) {
        currentWorkTransit = transit;
        break;
      }
    }
    final currentFlow = switch (currentWorkTransit?.natalHouse) {
      6 => '今は仕事の手順、技術、続け方を整えるほど適性が見えやすい時期です。',
      10 => '今は役割や評価につながるものを外へ出し、任される範囲を広げやすい時期です。',
      11 => '今は一人で完結させるより、仲間・紹介・共同作業から仕事の入口を増やしやすい時期です。',
      _ => '今は大きく決め打ちするより、興味のある役割を小さく試し、反応から適性を絞る時期です。',
    };
    final jobReading = currentJob == null
        ? '特に$fieldsのように、結果や相手の反応が見えやすい仕事を候補にしてください。'
        : _currentJobFitReading(currentJob, careerAxis.sign, mercury.sign);
    if (compactForMobile) {
      final compactJob = currentJob == null
          ? '$fieldsのように、相手の反応や完成が見える仕事が向きます。'
          : _compactCurrentJobReading(currentJob, careerAxis.sign);
      return '結論: ${profile.name}さんは、$role を担う形で適性が出ます。$compactJob $currentFlow 今週は、いちばん続けやすい役割を一つに絞り、小さな成果物か発信を一つ残してください。';
    }
    return '結論: ${profile.name}さんは、$role を担う仕事で力が出やすいタイプです。$jobReading $skill 合う働き方は、任される範囲と完成条件が見える環境で、自分の工夫を一つずつ形にしていくことです。避けたいのは、役割が曖昧なまま雑務だけを抱え続ける環境です。$currentFlow まず候補を三つに絞り、それぞれで必要な作業を一日だけ試して、続けやすさ・人との相性・成果の出方を比べると、向く方向が具体化します。';
  }

  String? _currentJobFromQuestion(String question) {
    final value = question.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    const jobs = ['ミュージシャン', '音楽家', '歌手', '作曲家', '配信者', 'youtuber', 'ユーチューバー', '会社員', '接客', '営業', '教師', '看護師', '介護', 'デザイナー', '美容師', '事務'];
    for (final job in jobs) {
      if (value.contains(job)) return job;
    }
    return _jobTargetFromQuestion(value);
  }

  String? _jobTargetFromQuestion(String value) {
    final match = RegExp(
      r'^(.{2,18}?)(?:は|が|を)(?:自分に)?(?:向いて|合って|あって|続けて|続けるべき|辞めるべき|やめるべき|いい|どう)',
    ).firstMatch(value);
    if (match == null) return null;
    final target = match.group(1)!
        .replaceFirst(RegExp(r'^(今の|この|僕の|私の|おいらの)'), '')
        .replaceAll(RegExp(r'(仕事|職業)$'), '')
        .trim();
    const unsuitable = ['それ', 'これ', 'あれ', '彼', '彼女', '自分', '人生', '将来'];
    if (target.length < 2 || unsuitable.contains(target)) return null;
    return target;
  }

  String _currentJobFitReading(
    String job,
    ZodiacSign careerSign,
    ZodiacSign mercurySign,
  ) {
    if (job == 'ミュージシャン' || job == '音楽家' || job == '歌手' || job == '作曲家') {
      final emphasis = switch (careerSign) {
        ZodiacSign.aries || ZodiacSign.leo || ZodiacSign.sagittarius => '演奏や表現を前に出し、ライブ・発信・企画で人を動かす形',
        ZodiacSign.taurus || ZodiacSign.virgo || ZodiacSign.capricorn => '演奏・制作の完成度を上げ、作品や継続的な活動を積み上げる形',
        ZodiacSign.gemini || ZodiacSign.libra || ZodiacSign.aquarius => '言葉、企画、コラボ、SNSで作品と人をつなぐ形',
        ZodiacSign.cancer || ZodiacSign.scorpio || ZodiacSign.pisces => '感情に届く表現、世界観づくり、少人数でも深い支持を育てる形',
      };
      final skill = switch (mercurySign) {
        ZodiacSign.aries || ZodiacSign.leo || ZodiacSign.sagittarius => '自分の言葉で作品の意図を語ること',
        ZodiacSign.taurus || ZodiacSign.virgo || ZodiacSign.capricorn => '制作工程や音の細部を整えること',
        ZodiacSign.gemini || ZodiacSign.libra || ZodiacSign.aquarius => '発信、説明、共作相手とのやり取りを回すこと',
        ZodiacSign.cancer || ZodiacSign.scorpio || ZodiacSign.pisces => '作品の背景や聴き手の感情を丁寧に扱うこと',
      };
      return '今の$jobの仕事は、$emphasis なら適性に合っています。特に$skill が、活動を続けるほど強い武器になります。逆に、演奏・制作・発信のどれも自分で選べず、他人の型だけをこなす状態が長いと力を出しにくくなります。';
    }
    return '今の$jobについても、自分が担う役割と得意な作業が成果へつながっているかで適性を判断してください。';
  }

  String _compactCurrentJobReading(String job, ZodiacSign careerSign) {
    if (job == 'ミュージシャン' || job == '音楽家' || job == '歌手' || job == '作曲家') {
      final style = switch (careerSign) {
        ZodiacSign.aries || ZodiacSign.leo || ZodiacSign.sagittarius => '演奏や発信を前へ出す形',
        ZodiacSign.taurus || ZodiacSign.virgo || ZodiacSign.capricorn => '制作の完成度を積み上げる形',
        ZodiacSign.gemini || ZodiacSign.libra || ZodiacSign.aquarius => '企画やコラボで作品を広げる形',
        ZodiacSign.cancer || ZodiacSign.scorpio || ZodiacSign.pisces => '世界観と深い支持を育てる形',
      };
      return 'ミュージシャンは、$style なら向いています。';
    }
    return '今の$jobは、得意な役割と成果が結びつく形なら続ける価値があります。';
  }

  String _careerRoleForSign(ZodiacSign sign) {
    return switch (sign) {
      ZodiacSign.aries || ZodiacSign.leo || ZodiacSign.sagittarius => '企画を立ち上げ、人を前へ動かす役割',
      ZodiacSign.taurus || ZodiacSign.virgo || ZodiacSign.capricorn => '仕組みを整え、品質と結果を積み上げる役割',
      ZodiacSign.gemini || ZodiacSign.libra || ZodiacSign.aquarius => '情報を伝え、人や仕事をつなぐ役割',
      ZodiacSign.cancer || ZodiacSign.scorpio || ZodiacSign.pisces => '相手の気持ちや必要をくみ取り、支える役割',
    };
  }

  String _careerFieldsForSign(ZodiacSign sign) {
    return switch (sign) {
      ZodiacSign.aries || ZodiacSign.leo || ZodiacSign.sagittarius => '営業企画、イベント運営、広報、講師、リーダー補佐',
      ZodiacSign.taurus || ZodiacSign.virgo || ZodiacSign.capricorn => '事務管理、経理補助、編集・校正、品質管理、制作進行',
      ZodiacSign.gemini || ZodiacSign.libra || ZodiacSign.aquarius => '営業、接客、広報、ライター、編集、カスタマーサポート、教育',
      ZodiacSign.cancer || ZodiacSign.scorpio || ZodiacSign.pisces => '福祉・支援、相談業務、接客、デザイン、写真・映像、企画制作',
    };
  }

  String _careerSkillForSign(ZodiacSign sign) {
    return switch (sign) {
      ZodiacSign.aries || ZodiacSign.leo || ZodiacSign.sagittarius => '考えを先に形にして、提案や発信で周囲を動かす力を仕事の武器にできます。',
      ZodiacSign.taurus || ZodiacSign.virgo || ZodiacSign.capricorn => '細部を見て、手順を整え、完成度を上げる力を仕事の武器にできます。',
      ZodiacSign.gemini || ZodiacSign.libra || ZodiacSign.aquarius => '説明、比較、連絡、学びを早く回す力を仕事の武器にできます。',
      ZodiacSign.cancer || ZodiacSign.scorpio || ZodiacSign.pisces => '相手の言葉にならない要望を受け取り、安心できる形へ直す力を仕事の武器にできます。',
    };
  }

  bool _isStructuredDecisionQuestion(String question) {
    final value = question.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    if (_questionTopic(value) == 'overall') return false;
    const decisionWords = [
      '今', '始め', '続け', 'やめ', '向いて', '可能性', '成功', '成果', '好転', '後悔',
      '選択', 'どちら', '流れ', 'チャンス', '注意', '避け', '運気', '運勢', '開運',
      'ラッキー', '幸運', '未来', '転機', '飛躍', '行動', '待っ', '大丈夫', '良い結果',
      'なれ', 'できる', 'できます', 'した方が良い', 'したほうが良い', '恵まれ', '幸せ',
    ];
    return decisionWords.any(value.contains);
  }

  String _questionTopic(String value) {
    if (['恋愛', '好き', '彼女', '彼氏', '恋人', '出会', '復縁', '結婚', '婚活', 'マッチング', '運命の人', '独身', '付き合'].any(value.contains)) return 'love';
    if (['金運', 'nisa', '投資', '貯金', '資産', '株', 'お金', '収入', '年収', '家計', '億万長者', '資産家', '経済的自由'].any(value.contains)) return 'money';
    if (['健康', '体調', '睡眠', 'ダイエット', '運動', '疲れ', 'メンタル', '精神', 'ストレス', '長生き', '寿命'].any(value.contains)) return 'health';
    if (['勉強', '学習', '資格', '受験', '学校', '試験', '課題'].any(value.contains)) return 'study';
    if (['youtube', 'sns', '作曲', '音楽', '創作', 'ai活動', 'ai音楽', 'suno', '動画', '発信', '配信'].any(value.contains)) return 'creative';
    if (['友達', '友人', '家族', '人間関係', '対人', '職場', '上司', '同僚'].any(value.contains)) return 'relationship';
    if (['引っ越し', '旅行', '将来', '人生', '夢', '進路'].any(value.contains)) return 'life';
    if (['仕事', '転職', '就職', '退職', '昇進', '副業', '働', '会社', '起業', '独立', '社長', '経営', '天職', '有名'].any(value.contains)) return 'work';
    return 'overall';
  }

  FortuneArea _questionTopicArea(String topic) {
    return switch (topic) {
      'love' => FortuneArea.love,
      'money' => FortuneArea.money,
      'health' => FortuneArea.mental,
      'work' || 'study' || 'creative' => FortuneArea.work,
      _ => FortuneArea.overall,
    };
  }

  String _questionTopicLabel(String topic) {
    return switch (topic) {
      'love' => '恋愛・対人関係',
      'money' => 'お金と収支',
      'health' => '健康と生活リズム',
      'study' => '学びと資格',
      'creative' => '創作・発信',
      'relationship' => '人間関係',
      'life' => '人生の選択',
      'work' => '仕事',
      _ => '今の流れ',
    };
  }

  String _questionTopicAction(String topic) {
    return switch (topic) {
      'love' => '連絡は一通を短くし、返事があれば具体的な予定へつなげる',
      'money' => '金額・期限・目的を先に書き出し、見送る条件も決めておく',
      'health' => '睡眠、食事、水分、休憩のどれか一つを今日から整える',
      'study' => '学ぶ範囲を小さく区切り、25分だけ着手して記録を残す',
      'creative' => '企画、制作、公開、振り返りを混ぜず、今日は一工程だけ終える',
      'relationship' => '相手の反応を決めつけず、事実確認できる短い会話を一度作る',
      'life' => '候補を二つか三つに絞り、必要な条件を並べて一つだけ試す',
      'work' => '最初の15分で終わる作業を着手し、条件や締切を一度確認する',
      _ => '今日できる小さな一手を一つ決める',
    };
  }

  String _questionPeriodAction(String topic) {
    return switch (topic) {
      'love' => '連絡、出会いの場、会う約束のどれかを一つ進める',
      'money' => '買い物、貯蓄、支払いのうち一つを数字で確認する',
      'health' => '睡眠、食事、運動のうち一つを整える',
      'study' => '勉強範囲を絞り、短い演習か復習を一回終える',
      'creative' => '企画、制作、公開、分析のうち一工程だけ進める',
      'relationship' => '相手を決めつけず、短い確認か会話を一度作る',
      'life' => '候補と現実の条件を並べ、後から戻せる一手を試す',
      'work' => '応募、相談、作業、条件確認のどれかを一件進める',
      _ => '最優先の予定を一つだけ終わらせる',
    };
  }

  String _questionTopicCaution(String topic) {
    return switch (topic) {
      'love' => '返信の速さだけで相手の気持ちを決めず、追い連絡は重ねないことも大切です。',
      'money' => '投資や契約の可否を占いだけで決めず、仕組み・手数料・損失の可能性を確認してください。',
      'health' => '強い痛みや不調が続く時は、占いで判断せず医療機関へ相談してください。',
      'study' => '一度に完璧を目指さず、続けられる量から始める方が成果になりやすいです。',
      'creative' => '反応の数字だけで作品の価値を決めず、次に直す一点を見つけることが近道です。',
      'relationship' => '相手の事情を想像だけで決めず、境界線と自分の休息も守ってください。',
      'life' => '大きな決断は、気分だけで急がず現実の条件も照合してください。',
      'work' => '条件が曖昧な話は即答せず、役割・報酬・期限を確認してから決めましょう。',
      _ => '急いで結論を出さず、確認できる材料を一つ増やしてください。',
    };
  }

  List<String> _questionTopics(String value) {
    const keywords = <String, List<String>>{
      'love': ['恋愛', '好き', '彼女', '彼氏', '恋人', '出会', '復縁', '結婚', '婚活', 'マッチング'],
      'money': ['金運', 'nisa', '投資', '貯金', '資産', '株', 'お金', '収入', '家計'],
      'health': ['健康', '体調', '睡眠', 'ダイエット', '運動', '疲れ', 'メンタル', '精神', 'ストレス'],
      'study': ['勉強', '学習', '資格', '受験', '学校', '試験', '課題'],
      'creative': ['youtube', 'sns', '作曲', '音楽', '創作', 'ai活動', 'ai音楽', 'suno', '動画', '発信', '配信'],
      'relationship': ['友達', '友人', '家族', '人間関係', '対人', '職場', '上司', '同僚'],
      'life': ['引っ越し', '旅行', '将来', '人生', '夢', '進路'],
      'work': ['仕事', '転職', '就職', '退職', '昇進', '副業', '働', '会社'],
    };
    return keywords.entries
        .where((entry) => entry.value.any(value.contains))
        .map((entry) => entry.key)
        .toList();
  }

  bool _isMultiTopicDecisionQuestion(String question) {
    final value = question.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    if (_questionTopics(value).length < 2) return false;
    return ['どちら', '優先', '比べ', '比較', '両方', 'どっち', '先に', '選択']
        .any(value.contains);
  }

  Future<String> _multiTopicDecisionReading({
    required AstroProfile profile,
    required String question,
    required HoroscopeReadingContext contextData,
    required bool compactForMobile,
  }) async {
    final value = question.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    final topics = _questionTopics(value).take(2).toList();
    final first = topics.first;
    final second = topics.last;
    final firstScore = FortuneScoreCalculator.dailyArea(
      contextData,
      _questionTopicArea(first),
      70,
    );
    final secondScore = FortuneScoreCalculator.dailyArea(
      contextData,
      _questionTopicArea(second),
      70,
    );
    final preferred = firstScore >= secondScore ? first : second;
    final other = preferred == first ? second : first;
    final preferredScore = preferred == first ? firstScore : secondScore;
    final otherScore = preferred == first ? secondScore : firstScore;
    final timing = await _questionTimingWindow(
      profile,
      _questionTopicArea(preferred),
      topic: preferred,
      contextData: contextData,
    );
    final answer = '結論: 今日は${_questionTopicLabel(preferred)}を先にすると流れを使いやすいです。${_questionTopicLabel(preferred)}は${preferredScore}点、${_questionTopicLabel(other)}は${otherScore}点です。${_questionTopicAction(preferred)}。$timing もう一方は、結論を急がず確認や下準備に回すと両方を崩しにくくなります。';
    return compactForMobile ? _shortText(answer, 180) : answer;
  }

  Future<String> _structuredDecisionReading({
    required AstroProfile profile,
    required String question,
    required HoroscopeReadingContext contextData,
    required bool compactForMobile,
  }) async {
    final value = question.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    final topic = _questionTopic(value);
    final area = _questionTopicArea(topic);
    final score = FortuneScoreCalculator.dailyArea(contextData, area, FortuneScoreCalculator.standardBase(area));
    final label = _questionTopicLabel(topic);
    final state = _decisionReadingState(contextData, area, score);
    final timing = await _questionTimingWindow(
      profile,
      area,
      topic: topic,
      contextData: contextData,
    );
    final action = _questionTopicAction(topic);
    final caution = _questionTopicCaution(topic);
    final answer = '結論: ${profile.name}さんの今日の$labelは$score点です。${state.decision} ${state.reason} 今後6週間では$timing $action ${state.actNow ? '最初は一件・一工程・一回の連絡までに絞ると、結果を読み違えにくくなります。' : '今日やるなら、資料集めや予定調整など、後からやり直せる一手にしてください。'} $caution';
    return compactForMobile ? _shortText(answer, 180) : answer;
  }

  ({bool actNow, String decision, String reason}) _decisionReadingState(
    HoroscopeReadingContext contextData,
    FortuneArea area,
    int score,
  ) {
    final voidMoon = contextData.transit.voidMoon;
    final voidActive = voidMoon?.contains(contextData.transit.date) ?? false;
    final retrogradeRelevant =
        (contextData.retrogradePlanets.contains(AstroPlanet.mercury) &&
            (area == FortuneArea.love || area == FortuneArea.work || area == FortuneArea.money)) ||
        (contextData.retrogradePlanets.contains(AstroPlanet.venus) &&
            (area == FortuneArea.love || area == FortuneArea.money)) ||
        (contextData.retrogradePlanets.contains(AstroPlanet.mars) &&
            (area == FortuneArea.work || area == FortuneArea.mental));
    final aspects = contextData.aspectsFor(area).toList()
      ..sort((a, b) => a.orb.compareTo(b.orb));
    final aspect = aspects.isEmpty ? null : aspects.first;
    final phase = aspect == null ? '' : _natalAspectPhase(contextData, aspect);
    final supportive = aspect != null &&
        (aspect.type == AspectType.trine ||
            aspect.type == AspectType.sextile ||
            (aspect.type == AspectType.conjunction && score >= 72));
    final challenging = aspect != null &&
        (aspect.type == AspectType.square || aspect.type == AspectType.opposition);
    final activeReturns = contextData
        .returnsFor(area)
        .where((event) => event.phase == AspectPhase.applying || event.phase == AspectPhase.exact)
        .toList();
    final expansionReturn = activeReturns.any(
      (event) => event.planet == AstroPlanet.jupiter || event.planet == AstroPlanet.venus,
    );
    final restructuringReturn = activeReturns.any(
      (event) => event.planet == AstroPlanet.saturn || event.planet == AstroPlanet.pluto,
    );

    if (voidActive) {
      return (
        actNow: false,
        decision: '今は即決より、確認と下準備を先にする方が合います。',
        reason: '月の流れが切り替わる時間内なので、結論より見直しを優先する判定です。',
      );
    }
    if (challenging && phase != '余韻' && score < 82) {
      return (
        actNow: false,
        decision: '今は大きく動かず、引っかかる条件を一つ直す方が合います。',
        reason: '注意を促す角度が$phaseで強まり、勢いより調整が結果につながるためです。',
      );
    }
    if (retrogradeRelevant && score < 78) {
      return (
        actNow: false,
        decision: '今は新規の結論より、やり直しと再確認を優先する方が合います。',
        reason: 'この分野に関係する星が逆行中で、過去の内容を整える力が強いためです。',
      );
    }
    if (restructuringReturn && score < 82) {
      return (
        actNow: false,
        decision: '今は大きく賭けるより、土台を組み替えてから動く方が合います。',
        reason: '長期の責任や環境の更新を促す節目なので、勢いより条件・役割・続け方を固めるほど後悔を減らせるためです。',
      );
    }
    if ((supportive && phase != '余韻' && score >= 66) || expansionReturn || score >= 78) {
      return (
        actNow: true,
        decision: '今は小さく動いて反応を確かめる方が、流れを使いやすい時です。',
        reason: aspect == null
            ? '点数だけでなく、現在の通過と広がりを後押しする節目が働いています。'
            : '追い風になる角度が$phaseで働き、試した結果を次へつなげやすいためです。',
      );
    }
    return (
      actNow: false,
      decision: '今は結論を急ぐより、準備と見直しを先にすると安定しやすい時です。',
      reason: '強い追い風がピークになる前なので、後から直せる準備へ使う判定です。',
    );
  }

  Future<String> _questionTimingWindow(
    AstroProfile profile,
    FortuneArea area, {
    required String topic,
    required HoroscopeReadingContext contextData,
  }) {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day, 12);
    final cacheKey = [
      profile.name,
      profile.birthDate,
      profile.birthTime,
      profile.birthPlace,
      area.name,
      topic,
      contextData.houseSystem.name,
      contextData.ephemerisSourceName,
      contextData.usesHighPrecisionAstroData,
      today.year,
      today.month,
      today.day,
    ].join('|');
    final cached = _questionTimingCache[cacheKey];
    if (cached != null) return Future.value(cached);
    return _buildQuestionTimingWindow(
      profile: profile,
      area: area,
      topic: topic,
      start: start,
      cacheKey: cacheKey,
    );
  }

  Future<String> _buildQuestionTimingWindow({
    required AstroProfile profile,
    required FortuneArea area,
    required String topic,
    required DateTime start,
    required String cacheKey,
  }) async {
    ({DateTime start, DateTime end, int average, DateTime peakDate, int peakScore})? best;
    for (var week = 0; week < 6; week++) {
      final weekStart = start.add(Duration(days: week * 7));
      final values = <MapEntry<DateTime, int>>[];
      for (var day = 0; day < 7; day++) {
        final date = weekStart.add(Duration(days: day));
        final preview = const AstrologyEngine().buildPreviewContext(profile: profile, date: date);
        final score = area == FortuneArea.overall
            ? FortuneScoreCalculator.dailyOverall(preview)
            : FortuneScoreCalculator.dailyArea(preview, area, FortuneScoreCalculator.standardBase(area));
        values.add(MapEntry(date, score));
        // 低スペック端末でも入力・描画を長時間止めないため、日ごとに処理を戻す。
        await Future<void>.delayed(Duration.zero);
      }
      final average = (values.fold<int>(0, (sum, item) => sum + item.value) / values.length).round();
      final peak = values.reduce((a, b) => a.value >= b.value ? a : b);
      final candidate = (
        start: weekStart,
        end: weekStart.add(const Duration(days: 6)),
        average: average,
        peakDate: peak.key,
        peakScore: peak.value,
      );
      if (best == null ||
          candidate.average > best.average ||
          (candidate.average == best.average && candidate.peakScore > best.peakScore)) {
        best = candidate;
      }
    }
    final window = best!;
    final label = topic == 'overall' ? '総合運' : _questionTopicLabel(topic);
    final result = '${window.start.month}/${window.start.day}〜${window.end.month}/${window.end.day}が平均${window.average}点で比較的使いやすく、中でも${window.peakDate.month}/${window.peakDate.day}が$label${window.peakScore}点です。';
    if (_questionTimingCache.length >= 32) {
      _questionTimingCache.remove(_questionTimingCache.keys.first);
    }
    _questionTimingCache[cacheKey] = result;
    return result;
  }

  bool _isLoveTimingQuestion(String question) {
    final value = question.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    if (!_isLoveCustomQuestion(value)) return false;
    return value.contains('いつ') ||
        value.contains('時期') ||
        value.contains('ころ') ||
        value.contains('頃') ||
        value.contains('タイミング') ||
        value.contains('何月') ||
        value.contains('何日') ||
        value.contains('今年') ||
        value.contains('来年') ||
        value.contains('出会える') ||
        value.contains('運命の人') ||
        value.contains('一生独身') ||
        (value.contains('結婚') && value.contains('でき')) ||
        (value.contains('復縁') && value.contains('でき')) ||
        (value.contains('付き合') && value.contains('でき')) ||
        (value.contains('彼女') && value.contains('でき')) ||
        (value.contains('彼氏') && value.contains('でき'));
  }

  String _loveTimingReading({
    required AstroProfile profile,
    required HoroscopeReadingContext contextData,
    required bool compactForMobile,
  }) {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day, 12);
    final candidates = <MapEntry<DateTime, int>>[];
    for (var week = 0; week < 26; week++) {
      final date = start.add(Duration(days: week * 7));
      final weekContext = const AstrologyEngine().buildPreviewContext(
        profile: profile,
        date: date,
      );
      candidates.add(
        MapEntry(
          date,
          FortuneScoreCalculator.dailyArea(weekContext, FortuneArea.love, FortuneScoreCalculator.standardBase(FortuneArea.love)),
        ),
      );
    }
    candidates.sort((a, b) => b.value.compareTo(a.value));
    final windows = <MapEntry<DateTime, int>>[];
    for (final candidate in candidates) {
      final overlaps = windows.any(
        (selected) => candidate.key.difference(selected.key).inDays.abs() < 21,
      );
      if (!overlaps) windows.add(candidate);
      if (windows.length == 3) break;
    }
    windows.sort((a, b) => a.key.compareTo(b.key));
    final first = windows.first;
    final periodLabels = windows
        .map(
          (window) => '${window.key.month}/${window.key.day}頃から1週間（恋愛運${window.value}点）',
        )
        .join('、');
    final strongest = candidates.first;
    final focus = _loveTimingFocus(profile, strongest.key);
    final currentScore = FortuneScoreCalculator.dailyArea(contextData, FortuneArea.love, FortuneScoreCalculator.standardBase(FortuneArea.love));
    if (compactForMobile) {
      return '結論: ${profile.name}さんの恋愛運が最も上がるのは${strongest.key.month}/${strongest.key.day}頃から1週間で、${strongest.value}点です。$focus その週までに、誘える相手か参加する場を一つ決めておきましょう。';
    }
    return '結論: ${profile.name}さんの出会いと関係が進みやすい波は、今後6か月では$periodLabelsです。中でも${strongest.key.month}/${strongest.key.day}頃からの1週間が最も強く、恋愛運は${strongest.value}点まで上がります。彼女ができる日を断定する占いではありませんが、この期間は出会い、連絡、会う約束を関係へつなげやすい時です。$focus 今週の恋愛運は${currentScore}点なので、待つだけでなく、強い週の前までにプロフィール、誘える相手、参加する場を一つ整えておくと波を使えます。';
  }

  String _loveTimingFocus(AstroProfile profile, DateTime date) {
    final context = const AstrologyEngine().buildPreviewContext(profile: profile, date: date);
    for (final transit in context.houseTransits) {
      switch (transit.natalHouse) {
        case 5:
          return 'その時期は、楽しみや趣味の場から自然な出会いが生まれやすくなります。';
        case 7:
          return 'その時期は、一対一の会話や紹介から関係を深めやすくなります。';
        case 8:
          return 'その時期は、表面的なやり取りよりも気持ちを少し深く話せる相手との縁が動きやすくなります。';
      }
    }
    return 'その時期は、普段より人と接する予定を増やすほど恋愛の入口をつかみやすくなります。';
  }

  String _lightCustomFallback(String question) {
    final value = question.trim();
    if (value.contains('食べ') || value.contains('飲み')) {
      return '今日は食べたいなら、無理に理由を探さず楽しんで大丈夫です。量だけ無理のない範囲にして、好きな薬味を一つ足すと満足しやすそうです。';
    }
    if (value.endsWith('たい')) {
      return 'やりたい気持ちがあるなら、まず少しだけ試してみて大丈夫です。終わったあとに気分がどう変わったかを見て、続けるか決めましょう。';
    }
    if (value.contains('眠') || value.contains('寝')) {
      return '眠いなら今日は睡眠運の圧勝です。あと一つだけ用事を片づけたら、堂々と布団へ向かいましょう。';
    }
    if (value.contains('ゲーム') || value.contains('ガチャ')) {
      return '遊ぶのは大賛成。ただし熱くなったら星より先に予算を見ましょう。時間か上限を決めれば、気持ちよく楽しめます。';
    }
    final variants = [
      '今日は「ちょっと試す」が吉です。くだらなさも立派な気分転換なので、笑えそうな方を選びましょう。',
      'その質問、星も少し笑っています。迷惑がかからず後悔も小さいなら、面白そうな方へ一票です。',
      '大げさな運命判定はいりません。今ちょっと気分が上がる方を選んで、合わなければすぐ戻れば大丈夫です。',
    ];
    final index = value.codeUnits.fold<int>(0, (sum, unit) => sum + unit) % variants.length;
    return variants[index];
  }

  bool _looksLikeHeavyCustomAnswer(String value) {
    const heavyWords = ['結論:', '結論：', '進め方:', '進め方：', '気をつけること:', '気をつけること：', '星座', '天体', 'ハウス'];
    return heavyWords.any(value.contains);
  }

  String _customProposalFallback({
    required AstroProfile profile,
    required String question,
    required HoroscopeReadingContext contextData,
  }) {
    final questionLower = question.toLowerCase();
    final score = FortuneScoreCalculator.dailyOverall(contextData);
    final flow = score >= 82
        ? '今の流れには追い風があります。ただ待つだけではなく、準備したことを小さく外へ出すほど結果につながりやすいです。'
        : score < 66
            ? '今は無理に結論を急ぐより、崩れやすい部分を整えてから動く方が結果を安定させやすい流れです。'
            : '今は大きく賭けるより、確認と小さな実行を重ねることで結果を育てやすい流れです。';

    if (questionLower.contains('バドミントン') ||
        questionLower.contains('試合') ||
        questionLower.contains('勝ち') ||
        questionLower.contains('スポーツ')) {
      return '結論: ${profile.name}さんは、勝ち進める可能性を高められる流れです。ただし一発で決めようとするより、相手を見てラリーを組み立てることが条件になります。$flow 進め方: 試合前に水分、ラケット、開始時間を確認し、最初の数点は無理な決め球を減らして相手の苦手な場所を探してください。ミスが続いた時は、次の1点だけを目標にして深呼吸を一度入れます。練習では、苦手なショットを10本続けて入れる練習と、試合終盤を想定した短いゲーム練習を一つずつ行うと、本番の崩れを減らせます。気をつけること: 勝敗を先読みして焦らず、相手の強さより自分の次の動きへ意識を戻してください。';
    }
    if (questionLower.contains('仕事') || questionLower.contains('収入') || questionLower.contains('稼') || questionLower.contains('転職')) {
      return '結論: ${profile.name}さんは、いきなり大きく環境を変えるより、収入や働き方につながる材料を一つ増やすことで状況を動かしやすいです。$flow 進め方: まず今できる仕事、増やしたい収入、使える時間を紙に分けて書き、今週中に実績になる作業を一つ完成させてください。その後、求人や依頼を三件だけ比較し、条件、必要な経験、連絡先を表にします。応募や相談をする時は、できることを三つに絞って伝えると話が具体化します。気をつけること: 焦って条件の悪い話へ飛びつかず、報酬、作業時間、支払い時期を確認してから返事をしましょう。';
    }
    if (_isLoveCustomQuestion(questionLower)) {
      return '結論: ${profile.name}さんは、いつ出会えるかを待つより、出会いにつながる行動を一つ増やすことで恋愛の流れを動かしやすいです。$flow 進め方: 今週は友人の集まり、趣味の場、マッチングサービスなど、自分に合う出会いの入口を一つだけ選んでください。気になる人がいる場合は、近況や共通の話題を短く送り、返事が良ければ候補日を二つ出して30分から1時間程度の予定へつなげます。反応が薄い時は追い連絡を重ねず、数日あけて別の予定を楽しむ方が関係を守れます。気をつけること: 返事の速さだけで脈あり・なしを決めず、会話が続くか、相手からも質問が返るかを見て判断しましょう。';
    }
    if (questionLower.contains('体調') || questionLower.contains('健康') || questionLower.contains('不安') || questionLower.contains('眠')) {
      return '結論: ${profile.name}さんは、頑張って一気に変えるより、生活の乱れを一つ減らすことで気持ちと体調を整えやすいです。$flow 進め方: 今日から三日間、起床時間と就寝前の過ごし方だけを記録してください。食事を抜かず、長く同じ姿勢が続いたら短い休憩を入れ、夜は画面を早めに閉じるなど、続けられる変更を一つ選びます。症状が続く、強い、生活に支障がある場合は占いで判断せず、医療機関や公的な相談先へつないでください。気をつけること: 自分を責めて無理に取り戻そうとせず、できた日を確認しながら整えていきましょう。';
    }
    return '結論: ${profile.name}さんの相談は、すぐに白黒を決めるより、結果を左右する条件を整理して一つずつ動くことで答えに近づけます。$flow 進め方: まず望む状態を一文で書き、次に必要な情報を三つ集めてください。その中から今日確認できる相手、期限、費用や時間のどれか一つを決め、15分だけ実行します。実行後は分かったこととまだ不明なことを分け、次の一手を一つに絞ります。気をつけること: 不安だけで決めず、事実、相手の反応、自分の希望を分けて見直しましょう。';
  }

  bool _isClearCustomProposal(
    String value,
    String question, {
    required bool compactForMobile,
  }) {
    final maximumCharacters = compactForMobile ? 190 : 720;
    if (value.length < _customMinimumCharacters(question, compactForMobile: compactForMobile) ||
        value.length > maximumCharacters) {
      return false;
    }
    const banned = [
      '占い師', '日本語で', '相談内容', '以下の通り', '教えてください', '具体的な情報', '質問', '星座', '星', '天体',
      '金星', '水星', '火星', '木星', '土星', '天王星', '海王星', '冥王星', 'アスペクト', 'ハウス', 'ホロスコープ',
      '出生図', 'トランジット', 'リターン', 'ボイド', '順番に整えましょう', '質問を言い換',
    ];
    if (banned.any(value.contains)) return false;
    final questionFragment = _shortText(question, 24);
    if (questionFragment.length >= 12 && value.contains(questionFragment)) return false;
    final hasMetaFormatting = RegExp(
      r'提案|対象\s*[:：]|日付\s*[:：]|\d{4}\s*[年/]\s*\d{1,2}|\d+\s*[〜～-]\s*\d+\s*字|【|】|^\s*[-・•]',
    ).hasMatch(value);
    if (hasMetaFormatting) return false;
    const lowQualityPhrases = [
      '時間や努力にかか',
      '少しでも早くできるように頑張って',
      'まだ出会うのは',
      'いつかきっと',
      '人生には100年',
      '人生の中で瞬間に変化',
      'あなたの一生は',
      '未来を決定します',
      '幸せや成功、失敗',
      '出生時間を入力',
      '時間を入力',
      '生年月日を入力',
      '出生地を入力',
      '教えてください',
      '追加情報が必要',
    ];
    if (lowQualityPhrases.any(value.contains)) return false;
    if (RegExp(r'\d{1,2}年(?:も|後|以内|かか|経)').hasMatch(value)) return false;
    if (_isLoveCustomQuestion(question.toLowerCase())) {
      const loveContextWords = ['彼女', '彼氏', '恋', '好意', '相手', '出会', '関係'];
      const loveActionWords = ['出会', '連絡', '会う', '誘', '関係を進め', '会話', '予定'];
      if (!loveContextWords.any(value.contains) || !loveActionWords.any(value.contains)) {
        return false;
      }
    }
    if (!_hasCustomTopicAction(value, question)) return false;
    if (!_hasCustomFortuneJudgement(value)) return false;
    const actionWords = ['する', 'しましょう', 'メモ', '確認', '送', '決め', '見直'];
    return actionWords.where(value.contains).length >= 2;
  }

  bool _hasCustomFortuneJudgement(String value) {
    const judgementWords = [
      '今は', '流れ', '追い風', '時期', '動きやす', '慎重', '整えやす', '強まり', '乱れやす', '向いて',
    ];
    return judgementWords.any(value.contains);
  }

  bool _hasCustomTopicAction(String value, String question) {
    final normalized = question.toLowerCase();
    List<String>? requiredWords;
    if (normalized.contains('仕事') ||
        normalized.contains('転職') ||
        normalized.contains('収入') ||
        normalized.contains('稼') ||
        normalized.contains('発信') ||
        normalized.contains('動画')) {
      requiredWords = ['作業', '完成', '応募', '比較', '確認', '連絡', '公開', '予定', '実績'];
    } else if (normalized.contains('体調') ||
        normalized.contains('健康') ||
        normalized.contains('眠') ||
        normalized.contains('不安')) {
      requiredWords = ['休', '眠', '記録', '体調', '整', '医療', '相談', '休憩'];
    } else if (normalized.contains('お金') ||
        normalized.contains('投資') ||
        normalized.contains('買')) {
      requiredWords = ['予算', '比較', '確認', '支出', '収入', '貯', '見送', '金額'];
    } else if (normalized.contains('家族') ||
        normalized.contains('友達') ||
        normalized.contains('人間関係') ||
        normalized.contains('職場')) {
      requiredWords = ['会話', '連絡', '距離', '約束', '相手', '伝え', '確認'];
    } else if (normalized.contains('勉強') ||
        normalized.contains('試験') ||
        normalized.contains('受験') ||
        normalized.contains('合格')) {
      requiredWords = ['勉強', '復習', '問題', '予定', '準備', '確認', '時間'];
    } else if (normalized.contains('試合') ||
        normalized.contains('勝ち') ||
        normalized.contains('スポーツ') ||
        normalized.contains('練習')) {
      requiredWords = ['練習', '準備', '確認', '休憩', '作戦', '記録', '相手'];
    }
    return requiredWords == null || requiredWords.any(value.contains);
  }

  int _customQuestionDetailLevel(String question) {
    final normalized = question.replaceAll(RegExp(r'\s+'), ' ').trim();
    final questionMarks = RegExp(r'[？?]').allMatches(normalized).length;
    if (normalized.length > 180 || questionMarks >= 2 || normalized.contains('\n')) {
      return 2;
    }
    if (normalized.length <= 60) return 0;
    return 1;
  }

  String _customAnswerLengthGuide(
    String question, {
    required bool localRuntime,
    required bool compactForMobile,
  }) {
    if (compactForMobile) return localRuntime ? '120〜160字' : '130〜180字';
    switch (_customQuestionDetailLevel(question)) {
      case 0:
        return localRuntime ? '200〜280字' : '220〜360字';
      case 2:
        return localRuntime ? '320〜420字' : '460〜700字';
      default:
        return localRuntime ? '250〜360字' : '340〜520字';
    }
  }

  int _customMaxOutputTokens(
    String question, {
    required bool localRuntime,
    required bool compactForMobile,
  }) {
    if (compactForMobile) return localRuntime ? 240 : 320;
    switch (_customQuestionDetailLevel(question)) {
      case 0:
        return localRuntime ? 360 : 520;
      case 2:
        return localRuntime ? 480 : 900;
      default:
        return localRuntime ? 440 : 720;
    }
  }

  int _customMaxCharacters(String question, {required bool compactForMobile}) {
    if (compactForMobile) return 190;
    switch (_customQuestionDetailLevel(question)) {
      case 0:
        return 360;
      case 2:
        return 720;
      default:
        return 540;
    }
  }

  int _customMinimumCharacters(String question, {required bool compactForMobile}) {
    if (compactForMobile) return 100;
    switch (_customQuestionDetailLevel(question)) {
      case 0:
        return 180;
      case 2:
        return 280;
      default:
        return 220;
    }
  }

  String _customResponseFocus(String question) {
    final normalized = question.toLowerCase();
    if (_isLoveCustomQuestion(normalized)) {
      return '見込みをぼかさず答え、出会い・連絡・会う約束のどれを今進めるかと、避ける行動を書く';
    }
    if (normalized.contains('仕事') ||
        normalized.contains('転職') ||
        normalized.contains('収入') ||
        normalized.contains('稼') ||
        normalized.contains('発信') ||
        normalized.contains('動画')) {
      return '優先する判断、今日から進める作業、成果を確認する目安と、避ける判断を書く';
    }
    if (normalized.contains('体調') ||
        normalized.contains('健康') ||
        normalized.contains('眠') ||
        normalized.contains('不安')) {
      return '負担を増やしやすい行動、整え方、受診や相談が必要な目安を穏やかに書く';
    }
    if (normalized.contains('お金') || normalized.contains('投資') || normalized.contains('買')) {
      return 'お金を動かす前の確認、使う優先順位、見送る基準を書く。利益や損失は断定しない';
    }
    return '相談への結論、今できる具体策、判断を急がない方がよい点を書く';
  }

  bool _isLoveCustomQuestion(String question) {
    const loveWords = [
      '恋愛', '好き', '相手', '付き合', '彼女', '彼氏', '恋人', '出会い', '出逢い',
      'パートナー', '結婚', '婚活', '復縁', '運命の人', '独身',
    ];
    return loveWords.any(question.contains);
  }

  String _shortText(String value, int maxLength) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxLength) return normalized;
    // 鑑定文を文字数だけで切ると「〜です」の途中で終わる。
    // 上限内に完結した文があればそこまで縮め、なければ全文を返す。
    final bounded = normalized.substring(0, maxLength);
    Match? lastSentence;
    for (final match in RegExp(r'[。！？!?]').allMatches(bounded)) {
      lastSentence = match;
    }
    if (lastSentence != null && lastSentence.end >= 24) {
      return bounded.substring(0, lastSentence.end).trim();
    }
    return normalized;
  }

  Map<String, String> _parseFortuneMap(String value, List<TodayFortuneItem> items) {
    final normalized = _normalize(value);
    final start = normalized.indexOf('{');
    final end = normalized.lastIndexOf('}');
    if (start >= 0 && end > start) {
      final jsonText = normalized.substring(start, end + 1);
      try {
        final decoded = jsonDecode(jsonText);
        if (decoded is Map<String, dynamic>) {
          final result = {
            for (final item in items) item.title: _fortuneMapValue(decoded[item.title]),
          }..removeWhere((_, text) => text.trim().isEmpty);
          final overall = _fortuneMapValue(decoded['総合運']);
          if (overall.trim().isNotEmpty) result['総合運'] = overall;
          return result;
        }
      } on FormatException {
        // Fall back to showing the raw text when the model returns prose instead of JSON.
      }
    }

    return const <String, String>{};
  }

  String _fortuneMapValue(Object? raw) {
    if (raw is String) return _normalize(raw);
    if (raw is Map) {
      final body = raw['内容'] ?? raw['本文'] ?? raw['文章'] ?? raw['提案'];
      final action = raw['行動'] ?? raw['行動提案'] ?? raw['具体策'];
      return _normalize([
        if (body != null) body.toString(),
        if (action != null) action.toString(),
      ].join(' '));
    }
    return '';
  }

  Map<String, String> _parseLongFortuneMap(String value, List<LongFortuneData> items) {
    final normalized = _normalize(value);
    final start = normalized.indexOf('{');
    final end = normalized.lastIndexOf('}');
    if (start >= 0 && end > start) {
      final jsonText = normalized.substring(start, end + 1);
      try {
        final decoded = jsonDecode(jsonText);
        if (decoded is Map<String, dynamic>) {
          return {
            for (final item in items)
              item.title: _fortuneMapValue(decoded[item.title]),
          }..removeWhere((_, text) => text.trim().isEmpty);
        }
      } on FormatException {
        // Fall back to showing the raw text when the model returns prose instead of JSON.
      }
    }

    return const <String, String>{};
  }

  String _normalize(String value) {
    return value
        .trim()
        .replaceAll(RegExp(r'^["「\s]+'), '')
        .replaceAll(RegExp(r'["」\s]+$'), '');
  }

  String _completeLocalReading(
    String value, {
    required int maxCharacters,
    required String fallback,
  }) {
    final normalized = _normalize(value)
        .replaceAll('**', '')
        .replaceAll('---', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) return fallback;

    final bounded = normalized.length > maxCharacters
        ? normalized.substring(0, maxCharacters)
        : normalized;
    Match? lastSentence;
    for (final match in RegExp(r'[。！？]').allMatches(bounded)) {
      lastSentence = match;
    }
    if (lastSentence != null && lastSentence.end >= 24) {
      return bounded.substring(0, lastSentence.end).trim();
    }
    if (normalized.length > maxCharacters) return fallback;
    return normalized;
  }

  String _cacheKey(String prefix, List<Object?> parts) {
    final raw = parts.join('|');
    final hash = raw.codeUnits.fold<int>(0, (value, code) => (value * 31 + code) & 0x3fffffff);
    return 'ai_cache.$prefix.$hash';
  }
}

enum _SafetyQuestionKind { traffic, abuse, immediate }

class _AstroBasisChip extends StatelessWidget {
  const _AstroBasisChip({
    required this.prefix,
    required this.text,
    required this.color,
  });

  final String prefix;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        '$prefix: ${_cleanText(text)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color.withValues(alpha: 0.88),
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  String _cleanText(String value) {
    if (value.startsWith('$prefix: ')) {
      return value.substring(prefix.length + 2);
    }
    return value;
  }
}

class DailyReading extends StatefulWidget {
  const DailyReading({
    super.key,
    required this.profile,
    required this.details,
    required this.depth,
  });

  final AstroProfile profile;
  final UserProfileDetails details;
  final ReadingDepth depth;

  @override
  State<DailyReading> createState() => _DailyReadingState();
}

class _DailyReadingState extends State<DailyReading> {
  int _dayOffset = 0;
  final _contextCache = <String, HoroscopeReadingContext>{};

  // 日付を長く送り続けた場合も、画面を開いたままのメモリが増え続けないようにする。
  // 直近の日付を行き来する通常利用には十分な件数を残す。
  static const _maxContextCacheEntries = 90;

  @override
  void didUpdateWidget(covariant DailyReading oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile != widget.profile) _contextCache.clear();
  }

  HoroscopeReadingContext _contextFor(DateTime date) {
    final key = '${date.toIso8601String()}|${HouseSystemSettings.current.value.name}';
    if (!_contextCache.containsKey(key) &&
        _contextCache.length >= _maxContextCacheEntries) {
      _contextCache.clear();
    }
    return _contextCache.putIfAbsent(
        key,
        () => const AstrologyEngine().buildPreviewContext(
          profile: widget.profile,
          date: date,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final targetDay = DateTime(now.year, now.month, now.day).add(Duration(days: _dayOffset));
    final selectedDate = DateTime(targetDay.year, targetDay.month, targetDay.day, 12);
    final detailed = widget.depth == ReadingDepth.detailed;
    final readingContext = _contextFor(selectedDate);

    return ReadingPage(
      title: '毎日の占い',
      subtitle: detailed
          ? '${widget.profile.name}さんのネイタルとトランジットを日付ごとに読む（12:00基準）'
          : '${widget.profile.name}さんの指定日の結果を短く読む（12:00基準）',
      children: [
        DailyDateNavigator(
          date: selectedDate,
          offset: _dayOffset,
          hasProfileDetails: widget.details.hasAny,
          onPrevious: () => setState(() => _dayOffset--),
          onNext: () => setState(() => _dayOffset++),
          onToday: () => setState(() => _dayOffset = 0),
          onSelectDate: (value) => setState(() {
            final today = DateTime.now();
            _dayOffset = DateTime(value.year, value.month, value.day)
                .difference(DateTime(today.year, today.month, today.day))
                .inDays;
          }),
        ),
        if (!widget.details.hasExactBirthBase) const BirthPrecisionNotice(),
        if (detailed && !readingContext.usesHighPrecisionAstroData)
          AstroDataSourceNotice(contextData: readingContext),
        if (detailed) VoidTimeNotice(period: readingContext.transit.voidMoon),
        DailyAstroEventsCard(date: selectedDate, contextData: readingContext),
        DailyFortuneTrendChart(
          startDate: selectedDate,
          contextFor: _contextFor,
        ),
        DailyTimeFlowCard(date: selectedDate, contextData: readingContext),
        const OverallScoreMethodNotice(
          text: '総合運について：恋愛・仕事・金運・健康・メンタルの4分野を平均して表示しています。',
        ),
        OverallFortuneCard(
          detailed: detailed,
          contextData: readingContext,
          date: selectedDate,
          onShare: () {
            showFortuneShareComposer(
              context,
              periodLabel: '${selectedDate.year}/${selectedDate.month}/${selectedDate.day}の毎日占い',
              score: FortuneScoreCalculator.dailyOverall(readingContext),
              body: OverallFortuneCard(detailed: detailed, contextData: readingContext).body,
            );
          },
        ),
        TodayFortuneGrid(
          key: ValueKey(
            'daily-fortune-${selectedDate.year}-${selectedDate.month}-${selectedDate.day}|${widget.profile.name}|${widget.details.concerns}|${widget.details.readingStyle}',
          ),
          detailed: detailed,
          profile: widget.profile,
          details: widget.details,
          date: selectedDate,
          contextData: readingContext,
        ),
        if (detailed) TodayAstroDataPanel(contextData: readingContext),
        if (detailed) NatalSensitivityPanel(contextData: readingContext),
        ReadingCard(
          title: 'この日のヒント',
          body: _dailyHint(readingContext),
          icon: Icons.auto_awesome,
        ),
      ],
    );
  }

  String _dailyHint(HoroscopeReadingContext contextData) {
    if (widget.depth == ReadingDepth.simple) {
      final voidMoon = contextData.transit.voidMoon;
      if (voidMoon != null) {
        return '${widget.profile.theme}については、気持ちや予定が定まりにくい${_simpleVoidTimeRange(voidMoon)}があります。大きな決断は急がず、見直しや休憩に回すと整いやすい日です。';
      }
      final aspect = contextData.aspects.isEmpty ? null : contextData.aspects.first;
      if (aspect != null) {
        return '${widget.profile.theme}については、${_simpleDailyFlow(aspect.type)}。今日できる小さな一歩を一つ選ぶと、流れを活かしやすくなります。';
      }
      final transit = contextData.houseTransits.isEmpty ? null : contextData.houseTransits.first;
      if (transit != null) {
        return '${widget.profile.theme}については、${_simpleDailyScene(transit.natalHouse)}を整えるほど、今日の流れを使いやすくなります。';
      }
      return '${widget.profile.theme}については、急いで答えを決めず、本当に大切にしたいことを一度だけ言葉にすると流れが整います。';
    }
    final voidMoon = contextData.transit.voidMoon;
    if (voidMoon != null) {
      return '${widget.profile.theme}については、${voidMoon.label}の間は大きな決断を急がず、見直しや休憩に回すと流れが整います。';
    }
    final aspect = contextData.aspects.isEmpty ? null : contextData.aspects.first;
    if (aspect != null) {
      return '${widget.profile.theme}については、現在の${aspect.transitPlanet.label}と出生図の${aspect.natalPlanet.label}の${aspect.type.label}を意識すると動きやすい日です。${aspect.meaning}';
    }
    final transit = contextData.houseTransits.isEmpty ? null : contextData.houseTransits.first;
    if (transit != null) {
      return '${widget.profile.theme}については、${transit.planet.label}が出生図の第${transit.natalHouse}ハウスを通過する流れを使う日です。${transit.meaning}';
    }
    return '${widget.profile.theme}については、急いで答えを決めるより「本当は何を大切にしたいか」を一度だけ言葉にしてみると流れが整います。';
  }

  String _simpleDailyFlow(AspectType type) {
    return switch (type) {
      AspectType.conjunction => '気持ちと行動を一つに絞りやすい日です',
      AspectType.sextile => '小さな連絡や準備がきっかけになりやすい日です',
      AspectType.trine => '得意なやり方を自然に使いやすい日です',
      AspectType.square => '急ぎと現実のズレを調整すると進みやすい日です',
      AspectType.opposition => '相手や予定との折り合いをつけると安定する日です',
    };
  }

  String _simpleDailyScene(int house) {
    return switch (house) {
      1 => '自分の見せ方や始め方', 2 => 'お金や大切なもの', 3 => '連絡や身近な用事',
      4 => '家や安心できる場所', 5 => '恋愛や楽しみ', 6 => '仕事、体調、生活リズム',
      7 => '人との約束や関係', 8 => '深い関係や共有すること', 9 => '学びや新しい視野',
      10 => '仕事や評価', 11 => '仲間や計画', 12 => '休息や心の整理',
      _ => '今日の優先順位',
    };
  }

  String _simpleVoidTimeRange(VoidMoonPeriod period) {
    String time(DateTime value) => '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
    if (period.startTime.year == period.endTime.year &&
        period.startTime.month == period.endTime.month &&
        period.startTime.day == period.endTime.day) {
      return '${time(period.startTime)}〜${time(period.endTime)}';
    }
    return '${period.startTime.month}/${period.startTime.day} ${time(period.startTime)}〜${period.endTime.month}/${period.endTime.day} ${time(period.endTime)}';
  }
}

/// 毎日占いの上部に置く、選択日から7日間の実点数グラフ。
class DailyFortuneTrendChart extends StatelessWidget {
  const DailyFortuneTrendChart({
    super.key,
    required this.startDate,
    required this.contextFor,
  });

  final DateTime startDate;
  final HoroscopeReadingContext Function(DateTime) contextFor;

  @override
  Widget build(BuildContext context) {
    final dates = List<DateTime>.generate(
      7,
      (index) => DateTime(startDate.year, startDate.month, startDate.day + index, 12),
    );
    const bases = {
      FortuneArea.love: 70,
      FortuneArea.work: 74,
      FortuneArea.money: 68,
      FortuneArea.mental: 72,
    };
    final values = <FortuneArea, List<int>>{
      for (final area in bases.keys) area: [],
    };
    final overall = <int>[];
    for (final date in dates) {
      final reading = contextFor(date);
      final dayScores = <int>[];
      for (final area in bases.keys) {
        final score = FortuneScoreCalculator.dailyArea(reading, area, bases[area]!);
        values[area]!.add(score);
        dayScores.add(score);
      }
      overall.add(FortuneScoreCalculator.overallWithReturnBonus(dayScores, reading));
    }
    final labels = dates.map((date) => '${date.month}/${date.day}').toList();
    final series = [
      FortuneFlowSeries(label: '総合', color: const Color(0xFFF6D77A), values: overall),
      FortuneFlowSeries(label: '恋愛', color: const Color(0xFFFF82B2), values: values[FortuneArea.love]!),
      FortuneFlowSeries(label: '仕事', color: const Color(0xFF57D6D1), values: values[FortuneArea.work]!),
      FortuneFlowSeries(label: '金運', color: const Color(0xFF9BE06D), values: values[FortuneArea.money]!),
      FortuneFlowSeries(label: 'メンタル', color: const Color(0xFFB58CFF), values: values[FortuneArea.mental]!),
    ];
    return GlassPanel(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('7日間の運勢の流れ', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text('各日の占いカードと同じ12:00 JSTの点数です。', style: TextStyle(color: Colors.white.withValues(alpha: 0.62), fontSize: 11)),
        const SizedBox(height: 12),
        SizedBox(height: 220, child: CustomPaint(painter: FortuneFlowPainter(series: series, labels: labels), child: const SizedBox.expand())),
        const SizedBox(height: 12),
        Wrap(spacing: 12, runSpacing: 8, children: series.map((item) => _FlowLegend(label: item.label, color: item.color)).toList()),
      ]),
    );
  }
}

Map<String, Object?> _transitConfigurationSnapshot(HoroscopeReadingContext contextData) {
  final bySign = <ZodiacSign, List<AstroPlanet>>{};
  for (final placement in contextData.transit.placements) {
    if (placement.planet == AstroPlanet.ascendant || placement.planet == AstroPlanet.midheaven) continue;
    bySign.putIfAbsent(placement.sign, () => []).add(placement.planet);
  }
  final stelliums = bySign.entries
      .where((entry) => entry.value.length >= 3)
      .map(
        (entry) => <String, Object?>{
          'sign': entry.key.label,
          'planets': entry.value.map((planet) => planet.label).toList(),
          'planet_details': contextData.transit.placements
              .where((item) => entry.value.contains(item.planet))
              .map((item) => <String, Object?>{
                    'planet': item.planet.label,
                    'sign': item.sign.label,
                    'degree': item.degree,
                    'house': item.house,
                  })
              .toList(),
        },
      )
      .toList();
  return {
    'reference_time': '12:00 JST',
    'transit_stelliums': stelliums,
    'transit_grand_trines': FortuneScoreCalculator.transitGrandTrineLabels(contextData),
    'transit_rare_patterns': FortuneScoreCalculator.transitRarePatternLabels(contextData),
    'transit_rare_pattern_details': FortuneScoreCalculator.transitRarePatternDetails(contextData).map((item) => item.toJson()).toList(),
    'natal_rare_patterns': FortuneScoreCalculator.natalRarePatternLabels(contextData),
    'natal_rare_pattern_details': FortuneScoreCalculator.natalRarePatternDetails(contextData).map((item) => item.toJson()).toList(),
  };
}

/// トランジットのハウス番号は、現在地の瞬間図ではなく出生図のカスプを
/// 基準にしている。外部AIや別サービスの「東京の瞬間図」と取り違えないよう、
/// JSONには方式・基準・検算用カスプを必ず添える。
Map<String, Object?> _houseCalculationSnapshot(HoroscopeReadingContext contextData) {
  Map<String, Object?> cusp(int index, double longitude) {
    final normalized = longitude % 360 < 0 ? longitude % 360 + 360 : longitude % 360;
    final sign = ZodiacSign.values[(normalized / 30).floor()];
    return {
      'house': index + 1,
      'sign': sign.label,
      'degree': double.parse((normalized % 30).toStringAsFixed(4)),
      'longitude': double.parse(normalized.toStringAsFixed(4)),
    };
  }

  return {
    'house_system': contextData.houseSystem.name,
    'reference': 'natal_chart',
    'reference_note': 'トランジット天体のhouseは、出生時刻・出生地から作成した出生図のハウスを基準に判定しています。現在地・東京などの瞬間図のハウスではありません。',
    'natal_chart_basis': {
      'birth_date': contextData.natal.profile.birthDate,
      'birth_time': contextData.natal.profile.birthTime,
      'birth_place': contextData.natal.profile.birthPlace,
      'calculation_place': contextData.birthPlace.label,
      'latitude': contextData.birthPlace.latitude,
      'longitude': contextData.birthPlace.longitude,
    },
    'natal_house_cusps': List<Map<String, Object?>>.generate(
      contextData.houseCusps.length,
      (index) => cusp(index, contextData.houseCusps[index]),
    ),
  };
}

Map<String, Object?> _transitHouseReferenceSnapshot() => {
      'reference': 'natal_chart',
      'note': '各天体のhouseは出生図のハウス通過を表します。現在地の瞬間図のハウスではありません。方式・出生図カスプはトップレベルのhouse_calculationを参照してください。',
    };

class DailyAstroDataExportCard extends StatelessWidget {
  const DailyAstroDataExportCard({
    super.key,
    required this.date,
    required this.profile,
    required this.details,
    required this.contextData,
  });

  final DateTime date;
  final AstroProfile profile;
  final UserProfileDetails details;
  final HoroscopeReadingContext contextData;

  String _jst(DateTime value) {
    final jst = value.toUtc().add(const Duration(hours: 9));
    return '${jst.year.toString().padLeft(4, '0')}-${jst.month.toString().padLeft(2, '0')}-${jst.day.toString().padLeft(2, '0')} ${jst.hour.toString().padLeft(2, '0')}:${jst.minute.toString().padLeft(2, '0')}:00+09:00';
  }

  Map<String, Object?> _data() {
    final voidMoon = contextData.transit.voidMoon;
    final overallReturnBonus = FortuneScoreCalculator.overallReturnBonus(contextData);
    final love = FortuneScoreCalculator.dailyArea(contextData, FortuneArea.love, FortuneScoreCalculator.standardBase(FortuneArea.love));
    final work = FortuneScoreCalculator.dailyArea(contextData, FortuneArea.work, FortuneScoreCalculator.standardBase(FortuneArea.work));
    final money = FortuneScoreCalculator.dailyArea(contextData, FortuneArea.money, FortuneScoreCalculator.standardBase(FortuneArea.money));
    final mental = FortuneScoreCalculator.dailyArea(contextData, FortuneArea.mental, FortuneScoreCalculator.standardBase(FortuneArea.mental));
    final dayStart = DateTime(date.year, date.month, date.day);
    final stationEvents = DailyAstroEventsCard(date: date, contextData: contextData)
        ._stationEvents(dayStart, dayStart.add(const Duration(days: 1)), AstrologyDataSources.current);
    final dailyEvents = DailyAstroEventsCard(date: date, contextData: contextData)
        ._dailyEvents(dayStart, dayStart.add(const Duration(days: 1)), AstrologyDataSources.current);
    return {
      'schema': 'pancyo_astrology_daily_consult_v1',
      'generated_at': DateTime.now().toIso8601String(),
      'date_time_jst': _jst(date),
      'timezone': 'Asia/Tokyo',
      'calculation_time': '12:00 JST',
      'profile': {
        'birth_date': profile.birthDate,
        'birth_time': profile.birthTime,
        'birth_place': profile.birthPlace,
        'theme': profile.theme,
        'concerns': details.concerns,
        'reading_style': details.readingStyle,
      },
      'house_calculation': _houseCalculationSnapshot(contextData),
      'fortune_scores': {
        'overall': FortuneScoreCalculator.dailyOverall(contextData),
        'love': love,
        'work': work,
        'money': money,
        'mental': mental,
      },
      'overall_return_bonus': overallReturnBonus == null
          ? null
          : {
              'planet': overallReturnBonus.planet.label,
              'value': double.parse(overallReturnBonus.value.toStringAsFixed(2)),
              'detail': overallReturnBonus.detail,
              'formula': overallReturnBonus.formula,
              'rule': '星別上限・近さ・位相で計算し、最強1件のみを4分野平均後に加算',
            },
      'natal_placements': contextData.natal.placements
          .map((item) => {'planet': item.planet.label, 'sign': item.sign.label, 'degree': item.degree, 'house': item.house})
          .toList(),
      'natal_retrograde_planets': contextData.natal.retrogradePlanets.map((item) => item.label).toList(),
      'transit_placements': contextData.transit.placements
          .map((item) => {'planet': item.planet.label, 'sign': item.sign.label, 'degree': item.degree, 'house': item.house})
          .toList(),
      'transit_house_reference': _transitHouseReferenceSnapshot(),
      'void_moon': voidMoon == null ? null : {'start_jst': _jst(voidMoon.startTime), 'end_jst': _jst(voidMoon.endTime)},
      'lunar_phase': DailyAstroEventsCard(date: date, contextData: contextData)
          ._lunarPhaseSnapshot(DateTime(date.year, date.month, date.day, 12), AstrologyDataSources.current),
      'lunar_phase_score_effects': FortuneScoreCalculator.lunarPhaseScoreEffects(contextData),
      'planetary_sign_dignity_effects': FortuneScoreCalculator.planetarySignDignityEffects(contextData),
      'retrograde_planets': {
        ...contextData.retrogradePlanets,
        ...DailyAstroEventsCard.verifiedRetrogradesAt(date),
      }.map((item) => item.label).toList(),
      'station_events_jst': stationEvents,
      if (dailyEvents.isNotEmpty) 'daily_events_jst': dailyEvents,
      'special_configurations_at_reference_time': _transitConfigurationSnapshot(contextData),
    };
  }

  Future<void> _export(BuildContext context) async {
    var progressOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(children: [SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 14), Expanded(child: Text('鑑定データを出力中…'))]),
        ),
      ),
    );
    try {
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 120));
      final directory = await getTemporaryDirectory();
      final day = '${date.year.toString().padLeft(4, '0')}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
      final createdAt = DateTime.now();
      final timestamp = '${createdAt.year.toString().padLeft(4, '0')}${createdAt.month.toString().padLeft(2, '0')}${createdAt.day.toString().padLeft(2, '0')}_${createdAt.hour.toString().padLeft(2, '0')}${createdAt.minute.toString().padLeft(2, '0')}${createdAt.second.toString().padLeft(2, '0')}_${createdAt.millisecond.toString().padLeft(3, '0')}';
      final data = _data();
      final scores = data['fortune_scores']! as Map<String, Object?>;
      final file = File('${directory.path}${Platform.pathSeparator}pancyo_astrology_daily_${day}_$timestamp.json');
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data), flush: true);
      if (context.mounted && progressOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        progressOpen = false;
      }
      await Share.shareXFiles([XFile(file.path)], subject: 'ぱんちょ式星占い AIチャット相談用データ');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('JSONを作成しました（総合${scores['overall']}・恋愛${scores['love']}・仕事${scores['work']}・金運${scores['money']}・健康${scores['mental']}点）。共有先または保存先を選んでください。')),
        );
      }
    } catch (_) {
      if (context.mounted && progressOpen) Navigator.of(context, rootNavigator: true).pop();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('JSON出力に失敗しました。もう一度お試しください。')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.save_alt_outlined, color: Color(0xFF57D6D1), size: 20),
              const SizedBox(width: 10),
              const Expanded(child: Text('AIチャット相談用データ', style: TextStyle(fontWeight: FontWeight.w900))),
              OutlinedButton(onPressed: () => _export(context), child: const Text('JSONを保存')),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'この1日の出生図・天体配置・月ボイド・5運勢点数を保存できます。AIチャットへ添えて「今日、仕事で注意することは？」のように詳しく相談できます。',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.70), fontSize: 12, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class DailyAstroEventsCard extends StatelessWidget {
  const DailyAstroEventsCard({super.key, required this.date, required this.contextData});

  final DateTime date;
  final HoroscopeReadingContext contextData;

  static const _verifiedStationRecords = <({AstroPlanet planet, int year, int month, int day, int hour, int minute, bool startsRetrograde})>[
    // Swiss Ephemeris系の外部暦と照合したJST。近似計算で留を取り逃がす場合だけ補完する。
    (planet: AstroPlanet.saturn, year: 2026, month: 7, day: 27, hour: 4, minute: 56, startsRetrograde: true),
    (planet: AstroPlanet.saturn, year: 2026, month: 12, day: 11, hour: 8, minute: 31, startsRetrograde: false),
  ];

  /// 端末内の近似計算で留直後の遅い惑星を取り逃がす場合に補う、
  /// 外部暦で照合済みの逆行期間。日時はJST。
  static Set<AstroPlanet> verifiedRetrogradesAt(DateTime date) {
    final result = <AstroPlanet>{};
    if (!date.isBefore(DateTime(2026, 7, 27, 4, 56)) &&
        date.isBefore(DateTime(2026, 12, 11, 8, 31))) {
      result.add(AstroPlanet.saturn);
    }
    return result;
  }

  // 星計算の瞬間を端末のタイムゾーン表記に依存させず、日本時間で表示する。
  String _time(DateTime value) {
    final jst = value.toUtc().add(const Duration(hours: 9));
    return '${jst.hour.toString().padLeft(2, '0')}:${jst.minute.toString().padLeft(2, '0')}';
  }

  double? _longitudeAt(
    EphemerisProvider ephemeris,
    AstroPlanet planet,
    DateTime time,
    Map<DateTime, List<PlanetPlacement>> cache,
  ) {
    final placements = cache.putIfAbsent(time, () => ephemeris.placementsFor(time));
    for (final placement in placements) {
      if (placement.planet == planet) {
        return placement.sign.index * 30.0 + placement.degree;
      }
    }
    return null;
  }

  int _motionDirection(
    EphemerisProvider ephemeris,
    AstroPlanet planet,
    DateTime time,
    Map<DateTime, List<PlanetPlacement>> cache,
  ) {
    // 留の時刻は分単位で表示するため、前後5分の移動量で方向を判定する。
    final before = _longitudeAt(ephemeris, planet, time.subtract(const Duration(minutes: 5)), cache);
    final after = _longitudeAt(ephemeris, planet, time.add(const Duration(minutes: 5)), cache);
    if (before == null || after == null) return 0;
    var delta = after - before;
    if (delta > 180) delta -= 360;
    if (delta < -180) delta += 360;
    if (delta.abs() < 0.0001) return 0;
    return delta > 0 ? 1 : -1;
  }

  List<String> _stationEvents(DateTime start, DateTime end, EphemerisProvider ephemeris) {
    final cache = <DateTime, List<PlanetPlacement>>{};
    final events = <String>[];
    for (final planet in const [
      AstroPlanet.mercury,
      AstroPlanet.venus,
      AstroPlanet.mars,
      AstroPlanet.jupiter,
      AstroPlanet.saturn,
      AstroPlanet.uranus,
      AstroPlanet.neptune,
      AstroPlanet.pluto,
    ]) {
      // 日付の0時付近で留になると、当日内だけの比較では開始・終了を
      // 取り逃がす。そのため前後3時間も含めて5分刻みで方向転換を探す。
      var previous = _motionDirection(
        ephemeris,
        planet,
        start.subtract(const Duration(hours: 3)),
        cache,
      );
      DateTime? station;
      var beforeDirection = previous;
      var afterDirection = 0;
      // 当日の全時間帯（前後3時間を含む）を探索する。
      // 7/27早朝のような留を、午前3時までの探索で落とさない。
      for (var minute = -180; minute <= 1620; minute += 5) {
        final probe = start.add(Duration(minutes: minute));
        final current = _motionDirection(ephemeris, planet, probe, cache);
        if (current == 0) continue;
        if (previous != 0 && current != previous) {
          // 粗い5分探索で見つけた区間だけを、1分刻みで詰める。
          var minutePrevious = _motionDirection(
            ephemeris,
            planet,
            probe.subtract(const Duration(minutes: 5)),
            cache,
          );
          for (var offset = -4; offset <= 0; offset++) {
            final minuteProbe = probe.add(Duration(minutes: offset));
            final minuteCurrent = _motionDirection(ephemeris, planet, minuteProbe, cache);
            if (minuteCurrent != 0 && minutePrevious != 0 && minuteCurrent != minutePrevious) {
              station = minuteProbe;
              beforeDirection = minutePrevious;
              afterDirection = minuteCurrent;
              break;
            }
            if (minuteCurrent != 0) minutePrevious = minuteCurrent;
          }
          station ??= probe;
          beforeDirection = beforeDirection == 0 ? previous : beforeDirection;
          afterDirection = afterDirection == 0 ? current : afterDirection;
          break;
        }
        previous = current;
      }
      if (station == null || station.isBefore(start) || !station.isBefore(end)) continue;
      final label = beforeDirection < afterDirection ? '逆行終了（留）' : '逆行開始（留）';
      final action = planet == AstroPlanet.mercury
          ? '連絡・契約・文章は仕上げと最終確認を優先'
          : '切替直後は急いで結論を出さず、方針を見直す';
      events.add('${_time(station)}頃　${planet.label}$label：$action');
    }
    // Moshierの近似計算では、非常に遅い土星の留が分単位の差分で
    // 判定不能になる端末がある。外部暦で照合した確定時刻は補助表で
    // 補完し、画面・総合運・JSONのすべてで同じイベントとして扱う。
    for (final item in _verifiedStationRecords) {
      final time = DateTime(item.year, item.month, item.day, item.hour, item.minute);
      if (time.isBefore(start) || !time.isBefore(end) || events.any((event) => event.contains(item.planet.label))) continue;
      final label = item.startsRetrograde ? '逆行開始（留）' : '逆行終了（留）';
      events.add('${_time(time)}頃　${item.planet.label}$label：切替直後は急いで結論を出さず、方針を見直す');
    }
    events.sort();
    return events;
  }

  PlanetPlacement? _placementAt(EphemerisProvider ephemeris, AstroPlanet planet, DateTime time) {
    for (final placement in ephemeris.placementsFor(time)) {
      if (placement.planet == planet) return placement;
    }
    return null;
  }

  /// AIが度数だけからサイン移動を推測しなくて済むよう、当日に確定した
  /// 天文イベントだけを時刻付きでまとめる。通常日はJSONへ出力しない。
  List<Map<String, Object?>> _dailyEvents(DateTime start, DateTime end, EphemerisProvider ephemeris) {
    final events = <Map<String, Object?>>[];
    for (final planet in const [
      AstroPlanet.sun,
      AstroPlanet.moon,
      AstroPlanet.mercury,
      AstroPlanet.venus,
      AstroPlanet.mars,
      AstroPlanet.jupiter,
      AstroPlanet.saturn,
      AstroPlanet.uranus,
      AstroPlanet.neptune,
      AstroPlanet.pluto,
    ]) {
      final ingress = ephemeris.nextSignIngress(planet, start);
      if (ingress == null || ingress.time.isBefore(start) || !ingress.time.isBefore(end)) continue;
      final before = _placementAt(ephemeris, planet, ingress.time.subtract(const Duration(minutes: 1)));
      events.add({
        'event_type': 'sign_ingress',
        'time_jst': _dateTimeJst(ingress.time),
        'planet': planet.label,
        'from_sign': before?.sign.label,
        'to_sign': ingress.sign.label,
        'label': '${planet.label}: ${before?.sign.label ?? '移動前の星座'} → ${ingress.sign.label}',
      });
    }

    final lunarPhase = _lunarPhaseSnapshot(start.add(const Duration(hours: 12)), ephemeris);
    final majorPhase = lunarPhase['major_phase_event_jst'] as Map<String, Object?>?;
    if (majorPhase != null) {
      events.add({
        'event_type': 'major_lunar_phase',
        'time_jst': majorPhase['time_jst'],
        'phase_key': majorPhase['key'],
        'label': majorPhase['label'],
      });
    }

    for (final station in _stationEvents(start, end, ephemeris)) {
      events.add({
        'event_type': 'station',
        'description_jst': station,
      });
    }
    events.sort((left, right) => (left['time_jst'] as String? ?? '').compareTo(right['time_jst'] as String? ?? ''));
    return events;
  }

  String? _lunarPhaseEvent(DateTime start, EphemerisProvider ephemeris) {
    final phase = _lunarPhaseSnapshot(start.add(const Duration(hours: 12)), ephemeris);
    final event = phase['major_phase_event_jst'] as Map<String, Object?>?;
    if (event == null) return null;
    final label = event['label'] as String;
    final time = event['time_jst'] as String;
    final shortTime = time.substring(11, 16);
    return switch (label) {
      '新月' => '$shortTime頃　新月：新しいことは小さく始め、意図を一つ決める',
      '上弦の月' => '$shortTime頃　上弦の月：育てたいことを一つ行動に移す',
      '満月' => '$shortTime頃　満月：結果と気持ちが表れやすいので、振り返りと調整を',
      '下弦の月' => '$shortTime頃　下弦の月：手放すことを一つ決め、次の準備をする',
      _ => null,
    };
  }

  double? _lunarElongation(
    EphemerisProvider ephemeris,
    DateTime time,
    Map<DateTime, List<PlanetPlacement>> cache,
  ) {
    final sun = _longitudeAt(ephemeris, AstroPlanet.sun, time, cache);
    final moon = _longitudeAt(ephemeris, AstroPlanet.moon, time, cache);
    if (sun == null || moon == null) return null;
    return (moon - sun + 360) % 360;
  }

  double _forwardAngle(double from, double to) => (to - from + 360) % 360;

  double _shortestAngle(double first, double second) {
    final forward = _forwardAngle(first, second);
    return forward > 180 ? 360 - forward : forward;
  }

  ({String key, String label}) _lunarPhaseLabel(double elongation) {
    if (elongation < 22.5 || elongation >= 337.5) return (key: 'new_moon', label: '新月');
    if (elongation < 67.5) return (key: 'waxing_crescent', label: '満ちていく三日月');
    if (elongation < 112.5) return (key: 'first_quarter', label: '上弦の月');
    if (elongation < 157.5) return (key: 'waxing_gibbous', label: '満ちていく凸月');
    if (elongation < 202.5) return (key: 'full_moon', label: '満月');
    if (elongation < 247.5) return (key: 'waning_gibbous', label: '欠けていく凸月');
    if (elongation < 292.5) return (key: 'last_quarter', label: '下弦の月');
    return (key: 'waning_crescent', label: '欠けていく三日月');
  }

  String _lunarPhaseKey(double target) => switch (target.toInt()) {
        0 => 'new_moon',
        90 => 'first_quarter',
        180 => 'full_moon',
        _ => 'last_quarter',
      };

  String _lunarPhaseName(double target) => switch (target.toInt()) {
        0 => '新月',
        90 => '上弦の月',
        180 => '満月',
        _ => '下弦の月',
      };

  DateTime? _majorLunarPhaseTime(
    DateTime start,
    DateTime end,
    double target,
    EphemerisProvider ephemeris,
    Map<DateTime, List<PlanetPlacement>> cache,
  ) {
    var previousTime = start;
    var previous = _lunarElongation(ephemeris, previousTime, cache);
    if (previous == null) return null;
    for (var minutes = 30; minutes <= 24 * 60; minutes += 30) {
      final currentTime = start.add(Duration(minutes: minutes));
      final current = _lunarElongation(ephemeris, currentTime, cache);
      if (current == null) continue;
      final previousAngle = previous ?? 0;
      final traveled = _forwardAngle(previousAngle, current);
      final distance = _forwardAngle(previousAngle, target);
      if (traveled <= 3 && distance <= traveled) {
        final estimatedMinutes = (distance / traveled * 30).round();
        final center = previousTime.add(Duration(minutes: estimatedMinutes));
        DateTime? closest;
        var closestError = double.infinity;
        for (var offset = -3; offset <= 3; offset++) {
          final candidate = center.add(Duration(minutes: offset));
          if (candidate.isBefore(start) || !candidate.isBefore(end)) continue;
          final angle = _lunarElongation(ephemeris, candidate, cache);
          if (angle == null) continue;
          final error = _shortestAngle(angle, target);
          if (error < closestError) {
            closestError = error;
            closest = candidate;
          }
        }
        return closest;
      }
      previousTime = currentTime;
      previous = current;
    }
    return null;
  }

  String _dateTimeJst(DateTime value) {
    final jst = value.toUtc().add(const Duration(hours: 9));
    return '${jst.year.toString().padLeft(4, '0')}-${jst.month.toString().padLeft(2, '0')}-${jst.day.toString().padLeft(2, '0')} '
        '${jst.hour.toString().padLeft(2, '0')}:${jst.minute.toString().padLeft(2, '0')}:00+09:00';
  }

  Map<String, Object?> _lunarPhaseSnapshot(DateTime reference, EphemerisProvider ephemeris) {
    final cache = <DateTime, List<PlanetPlacement>>{};
    final elongation = _lunarElongation(ephemeris, reference, cache) ?? 0;
    final phase = _lunarPhaseLabel(elongation);
    final illumination = ((1 - math.cos(elongation * math.pi / 180)) / 2 * 100).clamp(0, 100);
    final start = DateTime(reference.year, reference.month, reference.day);
    final end = start.add(const Duration(days: 1));
    Map<String, Object?>? majorEvent;
    for (final target in const [0.0, 90.0, 180.0, 270.0]) {
      final eventTime = _majorLunarPhaseTime(start, end, target, ephemeris, cache);
      if (eventTime != null) {
        majorEvent = {
          'key': _lunarPhaseKey(target),
          'label': _lunarPhaseName(target),
          'time_jst': _dateTimeJst(eventTime),
          'calculation': '太陽と月の地心黄経差が${target.toInt()}°になる時刻を30分探索後、分単位で絞り込み',
        };
        break;
      }
    }
    return {
      'reference_time_jst': _dateTimeJst(reference),
      'phase_key': phase.key,
      'phase_label': phase.label,
      'elongation_degrees': double.parse(elongation.toStringAsFixed(3)),
      'illumination_percent': double.parse(illumination.toStringAsFixed(1)),
      'lunar_age_days_approx': double.parse((elongation / 360 * 29.530588).toStringAsFixed(2)),
      'is_waxing': elongation > 0 && elongation < 180,
      'major_phase_event_jst': majorEvent,
    };
  }

  List<String> _configurationEvents(HoroscopeReadingContext contextData) {
    final events = <String>[];
    final bySign = <ZodiacSign, List<AstroPlanet>>{};
    for (final placement in contextData.transit.placements) {
      if (placement.planet == AstroPlanet.ascendant || placement.planet == AstroPlanet.midheaven) continue;
      bySign.putIfAbsent(placement.sign, () => []).add(placement.planet);
    }
    for (final entry in bySign.entries) {
      if (entry.value.length >= 3) {
        events.add('12:00　空の${entry.key.label}のステリウム（${entry.value.map((planet) => planet.label).join('・')}）：そのテーマを一つに絞ると力にしやすい');
      }
    }
    for (final label in FortuneScoreCalculator.transitGrandTrineLabels(contextData)) {
      events.add('12:00　グランドトライン（$label）：得意なことを具体的な行動へつなげる');
    }
    for (final pattern in FortuneScoreCalculator.transitRarePatternDetails(contextData)) {
      events.add('12:00　${pattern.label}（${pattern.planets.map((planet) => planet.label).join('・')}）：${FortuneScoreCalculator.rarePatternGuidance(pattern.label)}');
    }
    return events;
  }

  @override
  Widget build(BuildContext context) {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    final events = <String>[];
    PlanetPlacement? moon;
    for (final placement in contextData.transit.placements) {
      if (placement.planet == AstroPlanet.moon) {
        moon = placement;
        break;
      }
    }
    if (moon != null) {
      events.add('12:00　月は${moon.sign.label}：気分と行動のペースをここで確認');
    }
    final ephemeris = AstrologyDataSources.current;
    final lunarPhase = _lunarPhaseSnapshot(DateTime(date.year, date.month, date.day, 12), ephemeris);
    events.add(
      '12:00　月相：${lunarPhase['phase_label']}（照度${lunarPhase['illumination_percent']}%・月齢目安${lunarPhase['lunar_age_days_approx']}日）',
    );
    final stationEvents = _stationEvents(start, end, ephemeris);
    events.addAll(stationEvents);
    final phaseEvent = _lunarPhaseEvent(start, ephemeris);
    if (phaseEvent != null) events.add(phaseEvent);
    final personalRetrogrades = {
      ...contextData.retrogradePlanets,
      ...verifiedRetrogradesAt(DateTime(date.year, date.month, date.day, 12)),
    }.toList()
      ..sort((left, right) => left.index.compareTo(right.index));
    final ongoingRetrogrades = personalRetrogrades
        .where((planet) => !stationEvents.any((event) => event.contains(planet.label)))
        .toList();
    if (ongoingRetrogrades.isNotEmpty) {
      events.add('12:00　${ongoingRetrogrades.map((planet) => planet.label).join('・')}逆行中：連絡、予定、判断は見直してから確定');
    }
    for (final planet in [
      AstroPlanet.sun,
      AstroPlanet.moon,
      AstroPlanet.mercury,
      AstroPlanet.venus,
      AstroPlanet.mars,
      AstroPlanet.jupiter,
      AstroPlanet.saturn,
      AstroPlanet.uranus,
      AstroPlanet.neptune,
      AstroPlanet.pluto,
    ]) {
      final ingress = ephemeris.nextSignIngress(planet, start);
      if (ingress != null && !ingress.time.isBefore(start) && ingress.time.isBefore(end)) {
        events.add('${_time(ingress.time)}　${planet.label}が${ingress.sign.label}へ：${planet == AstroPlanet.moon ? '気分の切替' : '${planet.label}のテーマが切替'}');
      }
    }
    final voidMoon = contextData.transit.voidMoon;
    if (voidMoon != null && voidMoon.startTime.isBefore(end) && voidMoon.endTime.isAfter(start)) {
      events.add('${_time(voidMoon.startTime)}〜${_time(voidMoon.endTime)}　月ボイド：大きな決定は急がず確認を');
    }
    events.addAll(_configurationEvents(contextData));
    if (events.isEmpty) return const SizedBox.shrink();
    return GlassPanel(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [Icon(Icons.event_note_outlined, color: Color(0xFFF6D77A), size: 18), SizedBox(width: 8), Text('今日の星イベント（JST）', style: TextStyle(fontWeight: FontWeight.w900))]),
          const SizedBox(height: 8),
          ...events.map((event) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(event, style: TextStyle(color: Colors.white.withValues(alpha: 0.78), fontSize: 12, height: 1.4)),
              )),
        ],
      ),
    );
  }
}

String? _stationReadingHint(DateTime? date, HoroscopeReadingContext contextData) {
  if (date == null) return null;
  final start = DateTime(date.year, date.month, date.day);
  final end = start.add(const Duration(days: 1));
  final events = DailyAstroEventsCard(date: date, contextData: contextData)
      ._stationEvents(start, end, AstrologyDataSources.current);
  if (events.isEmpty) return null;

  final labels = <String>[];
  final themes = <String>[];
  for (final event in events) {
    final title = event.contains('　') ? event.split('　').last.split('：').first : event;
    labels.add(title);
    if (title.contains('水星')) {
      themes.add('連絡・契約・文章は仕上げと最終確認を優先');
    } else if (title.contains('金星')) {
      themes.add('恋愛・お金・好みは結論を急がず、納得できる条件を見直す');
    } else if (title.contains('火星')) {
      themes.add('行動や対立は勢いで進めず、手順と体力配分を整える');
    } else if (title.contains('木星')) {
      themes.add('学び・挑戦・広げる話は、方向性を確認してから再始動する');
    } else if (title.contains('土星')) {
      themes.add('責任・仕事の土台は、負担と期限を組み直してから進める');
    } else if (title.contains('天王星')) {
      themes.add('変化や新しい方法は、急な切替より試しながら調整する');
    } else if (title.contains('海王星')) {
      themes.add('理想や気持ちは曖昧なまま決めず、事実と境界線を確かめる');
    } else if (title.contains('冥王星')) {
      themes.add('深い変化は無理に動かさず、手放すことと優先順位を整える');
    }
  }
  return '今日は${labels.join('・')}の留です。${themes.join('。')}。切替直後は一度見直してから次へ進むと安定します';
}

String? _lunarPhaseReadingHint(DateTime? date, HoroscopeReadingContext contextData) {
  if (date == null) return null;
  final start = DateTime(date.year, date.month, date.day);
  final event = DailyAstroEventsCard(date: date, contextData: contextData)
      ._lunarPhaseEvent(start, AstrologyDataSources.current);
  if (event == null) return null;
  if (event.contains('新月')) {
    return '今日は新月です。これから育てたいことを一つ決め、小さく始めると流れを作りやすい日です';
  }
  if (event.contains('上弦の月')) {
    return '今日は上弦の月です。育てたいことを一つ行動に移し、進み具合を確かめると流れを活かせます';
  }
  if (event.contains('満月')) {
    return '今日は満月です。結果と気持ちが表れやすいので、振り返りと調整に使うと整います';
  }
  if (event.contains('下弦の月')) {
    return '今日は下弦の月です。負担や不要なことを一つ手放し、次の準備を整えると気持ちが軽くなります';
  }
  return null;
}

String? _majorIngressReadingHint(DateTime? date) {
  if (date == null) return null;
  final start = DateTime(date.year, date.month, date.day);
  final end = start.add(const Duration(days: 1));
  final ephemeris = AstrologyDataSources.current;
  for (final planet in const [
    AstroPlanet.sun,
    AstroPlanet.mercury,
    AstroPlanet.venus,
    AstroPlanet.mars,
  ]) {
    final ingress = ephemeris.nextSignIngress(planet, start);
    if (ingress == null || ingress.time.isBefore(start) || !ingress.time.isBefore(end)) continue;
    return switch (planet) {
      AstroPlanet.sun => '今日は太陽が${ingress.sign.label}へ移ります。これから約1か月の軸を一つ決めると、行動にまとまりが出ます',
      AstroPlanet.mercury => '今日は水星が${ingress.sign.label}へ移ります。連絡や学びの進め方を、その星座らしい視点へ切り替えると役立ちます',
      AstroPlanet.venus => '今日は金星が${ingress.sign.label}へ移ります。人間関係・お金・楽しみの基準を、心地よさだけでなく長く続く形へ整えましょう',
      AstroPlanet.mars => '今日は火星が${ingress.sign.label}へ移ります。行動の勢いを新しいテーマへ向ける前に、最初の一歩を具体的に決めましょう',
      _ => null,
    };
  }
  return null;
}

List<String> _transitStelliumLabels(HoroscopeReadingContext contextData) {
  final bySign = <ZodiacSign, List<AstroPlanet>>{};
  for (final placement in contextData.transit.placements) {
    if (placement.planet == AstroPlanet.ascendant || placement.planet == AstroPlanet.midheaven) continue;
    bySign.putIfAbsent(placement.sign, () => []).add(placement.planet);
  }
  return bySign.entries
      .where((entry) => entry.value.length >= 3)
      .map((entry) => '${entry.key.label}（${entry.value.map((planet) => planet.label).join('・')}）')
      .toList();
}

class DailyTimeFlowCard extends StatelessWidget {
  const DailyTimeFlowCard({super.key, required this.date, required this.contextData});

  final DateTime date;
  final HoroscopeReadingContext contextData;

  String _line(String period, int hour, String good, String steady, String careful) {
    final moment = DateTime(date.year, date.month, date.day, hour);
    // 時間帯表示のために出生図・アスペクト・月ボイド探索を4回作り直さない。
    // 月の位置だけをその時刻で読み、日全体の点数は上部で作成済みの文脈を使う。
    final placements = AstrologyDataSources.current.placementsFor(moment);
    PlanetPlacement? moon;
    for (final placement in placements) {
      if (placement.planet == AstroPlanet.moon) {
        moon = placement;
        break;
      }
    }
    final score = FortuneScoreCalculator.dailyOverall(contextData);
    final advice = score >= 80 ? good : score >= 68 ? steady : careful;
    final moonAction = moon == null ? '' : '月が${moon.sign.label}。行動目安は「${moonSignTimeActionHint(moon.sign)}」。';
    final voidMoon = contextData.transit.voidMoon;
    if (voidMoon != null && voidMoon.contains(moment)) {
      return '$period　$moonAction 月ボイド中なので、大きな決定は急がず確認を。';
    }
    return '$period　$moonAction $advice';
  }

  @override
  Widget build(BuildContext context) {
    final lines = [
      _line('深夜', 1, '明日の準備を一つ決めて、睡眠を削らず終える。', '頭の中をメモに出して、早めに休む。', '考え込みやすいので結論を出さず、休息を優先する。'),
      _line('朝', 8, '連絡・予約・着手のうち一つを最初に済ませる。', '予定を二つに絞り、優先順を決めて始める。', '急いで返事をせず、予定と相手を確認してから動く。'),
      _line('日中', 13, '重要な作業や提案を前へ進め、反応を見て仕上げる。', '一つずつ片づけ、途中で休憩を入れてペースを保つ。', '抱え込まず相談し、締切や金額は二度確認する。'),
      _line('夜', 20, '楽しい予定や振り返りで、明日の力をためる。', '今日の達成を一つ確認し、明日の準備だけして終える。', '大きな決断は持ち越し、画面から離れて気持ちを整える。'),
    ];
    return GlassPanel(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [Icon(Icons.schedule_outlined, color: Color(0xFF57D6D1), size: 18), SizedBox(width: 8), Text('今日の時間帯ごとの流れ（JST）', style: TextStyle(fontWeight: FontWeight.w900))]),
          const SizedBox(height: 8),
          ...lines.map((line) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(line, style: TextStyle(color: Colors.white.withValues(alpha: 0.78), fontSize: 12, height: 1.4)),
              )),
        ],
      ),
    );
  }
}

class DailyDateNavigator extends StatelessWidget {
  const DailyDateNavigator({
    super.key,
    required this.date,
    required this.offset,
    required this.hasProfileDetails,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
    required this.onSelectDate,
  });

  final DateTime date;
  final int offset;
  final bool hasProfileDetails;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final ValueChanged<DateTime> onSelectDate;

  @override
  Widget build(BuildContext context) {
    final dateLabel = '${date.year}年${date.month}月${date.day}日';
    final offsetLabel = offset == 0
        ? '今日'
        : offset > 0
            ? '$offset日後'
            : '${offset.abs()}日前';

    return GlassPanel(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 360dp級だけ二段にして、390dp以上の一般的なスマホでは
          // 前後移動・日付・操作を一行で見渡せる従来配置を保つ。
          final compact = MediaQuery.sizeOf(context).width < 390;
          final dateSummary = Column(
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  dateLabel,
                  maxLines: 1,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                offsetLabel,
                style: TextStyle(
                  color: const Color(0xFFF6D77A).withValues(alpha: 0.86),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          );
          final datePicker = IconButton(
            tooltip: '日付を選ぶ',
            onPressed: () async {
              final selected = await showDatePicker(
                context: context,
                initialDate: date,
                firstDate: DateTime(1900),
                lastDate: DateTime(2100),
                helpText: '占う日を選択',
              );
              if (selected != null) onSelectDate(selected);
            },
            icon: const Icon(Icons.calendar_month_outlined),
          );
          return Column(
            children: [
              if (compact) ...[
                Row(
                  children: [
                    IconButton(
                      tooltip: '前の日',
                      onPressed: onPrevious,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(child: dateSummary),
                    IconButton(
                      tooltip: '次の日',
                      onPressed: onNext,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(onPressed: onToday, child: const Text('今日')),
                    datePicker,
                  ],
                ),
              ] else
                Row(
                  children: [
                    IconButton(
                      tooltip: '前の日',
                      onPressed: onPrevious,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(child: dateSummary),
                    TextButton(onPressed: onToday, child: const Text('今日')),
                    datePicker,
                    IconButton(
                      tooltip: '次の日',
                      onPressed: onNext,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              Divider(color: Colors.white.withValues(alpha: 0.08), height: 12),
              Row(
                children: [
                  Icon(
                    Icons.person_outline,
                    size: 14,
                    color: const Color(0xFF57D6D1).withValues(alpha: 0.78),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      hasProfileDetails
                          ? 'プロフィール情報を反映して、占いの使い方を個人向けに整えます。'
                          : 'プロフィールを書くと、占いの使い方がより自分向けになります。',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.50),
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class ProfileReflectionNotice extends StatelessWidget {
  const ProfileReflectionNotice({super.key, required this.hasProfileDetails});

  final bool hasProfileDetails;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10, bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF57D6D1).withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          Icon(
            hasProfileDetails ? Icons.person_pin_circle_outlined : Icons.person_add_alt,
            color: const Color(0xFF57D6D1),
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hasProfileDetails
                  ? 'プロフィール補足を、通常占いの使い方に反映しています。'
                  : 'プロフィールを書くと、通常占いの使い方が性格・悩みに合わせて変わります。',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.58),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
            ],
          ),
        );
  }
}

class BirthPrecisionNotice extends StatelessWidget {
  const BirthPrecisionNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF6D77A).withValues(alpha: 0.075),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFF6D77A).withValues(alpha: 0.20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: Color(0xFFF6D77A), size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'プロフィール未保存時はサンプル仮データとして12:00・北海道札幌市で計算しています。正確に見る場合は、出生時間と出生地をプロフィールに保存してください。',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.70),
                fontSize: 12,
                height: 1.45,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AstroDataSourceNotice extends StatelessWidget {
  const AstroDataSourceNotice({super.key, required this.contextData});

  final HoroscopeReadingContext contextData;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF57D6D1).withValues(alpha: 0.075),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF57D6D1).withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.travel_explore_outlined, color: Color(0xFF57D6D1), size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '星データ: ${contextData.ephemerisSourceName}。${contextData.ephemerisPrecisionNotice}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 12,
                height: 1.45,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum LongRangeMode { week, month, year }

class LongRangeReading extends StatefulWidget {
  const LongRangeReading({
    super.key,
    required this.profile,
    required this.details,
    required this.depth,
  });

  final AstroProfile profile;
  final UserProfileDetails details;
  final ReadingDepth depth;

  @override
  State<LongRangeReading> createState() => _LongRangeReadingState();
}

class _LongRangeReadingState extends State<LongRangeReading> {
  LongRangeMode _mode = LongRangeMode.week;
  String? _aiRequestKey;
  int _aiRequestRevision = 0;
  int _monthOffset = 0;
  int _yearOffset = 0;
  int _weekOffset = 0;
  bool _navigationBusy = false;
  bool _chartLoaded = false;
  final _contextCache = <String, HoroscopeReadingContext>{};
  final _cardsCache = <String, List<LongFortuneData>>{};

  // 10年グラフ（最大240基準時刻）を一度読んでも、長時間の期間移動で
  // キャッシュが無限に増えないようにする。通常の再訪問は十分に保持する。
  static const _maxContextCacheEntries = 384;
  static const _maxCardsCacheEntries = 48;

  Future<void> _startNavigation(VoidCallback action) async {
    if (_navigationBusy) return;
    setState(() => _navigationBusy = true);
    // 押下表示と「読み替え中…」を先に1フレーム描画してから計算する。
    // 重い年・月の集計でも、押せたか分からない状態を作らない。
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 16));
    if (!mounted) return;
    setState(action);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) setState(() => _navigationBusy = false);
  }

  @override
  void didUpdateWidget(covariant LongRangeReading oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile != widget.profile) {
      _contextCache.clear();
      _cardsCache.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final currentWeekStart = today.subtract(Duration(days: today.weekday - 1));
    final targetWeek = currentWeekStart.add(Duration(days: _weekOffset * 7));
    final targetWeekEnd = targetWeek.add(const Duration(days: 6));
    final targetMonth = DateTime(now.year, now.month + _monthOffset);
    final targetYear = now.year + _yearOffset;
    final title = switch (_mode) {
      LongRangeMode.week => '週間占い',
      LongRangeMode.month => '月間占い',
      LongRangeMode.year => '年間占い',
    };
    final subtitle = switch (_mode) {
      LongRangeMode.week => '${widget.profile.name}さんの${targetWeek.month}/${targetWeek.day}〜${targetWeekEnd.month}/${targetWeekEnd.day}の流れ',
      LongRangeMode.month => '${widget.profile.name}さんの${targetMonth.year}年${targetMonth.month}月の流れ',
      LongRangeMode.year => '${widget.profile.name}さんの$targetYear年の大きな星回り',
    };
    final detailed = widget.depth == ReadingDepth.detailed;
    final periodContext = _contextFor(
      _atNoon(_mode == LongRangeMode.year ? DateTime(targetYear) : _mode == LongRangeMode.week ? targetWeek : targetMonth),
    );
    final periodIdentity = _periodIdentity(targetWeek, targetMonth, targetYear);
    final cards = _cardsFor(targetWeek, targetMonth, targetYear);
    final shareLabel = switch (_mode) {
      LongRangeMode.week => '${targetWeek.year}/${targetWeek.month}/${targetWeek.day}〜${targetWeekEnd.month}/${targetWeekEnd.day}',
      LongRangeMode.month => '${targetMonth.year}年${targetMonth.month}月',
      LongRangeMode.year => '$targetYear年',
    };

    return ReadingPage(
      title: title,
      subtitle: subtitle,
      children: [
        LongRangeNavigator(
          mode: _mode,
          weekStart: targetWeek,
          month: targetMonth,
          year: targetYear,
          busy: _navigationBusy,
          onModeChanged: (value) => _startNavigation(() {
            _mode = value;
            _chartLoaded = false;
          }),
          onPrevious: () => _startNavigation(() {
            if (_mode == LongRangeMode.year) {
              _yearOffset--;
            } else if (_mode == LongRangeMode.week) {
              _weekOffset--;
            } else {
              _monthOffset--;
            }
            _chartLoaded = false;
          }),
          onNext: () => _startNavigation(() {
            if (_mode == LongRangeMode.year) {
              _yearOffset++;
            } else if (_mode == LongRangeMode.week) {
              _weekOffset++;
            } else {
              _monthOffset++;
            }
            _chartLoaded = false;
          }),
          onCurrent: () => _startNavigation(() {
            if (_mode == LongRangeMode.year) {
              _yearOffset = 0;
            } else if (_mode == LongRangeMode.week) {
              _weekOffset = 0;
            } else {
              _monthOffset = 0;
            }
            _chartLoaded = false;
          }),
          onSelectDate: (value) => _startNavigation(() {
            if (_mode == LongRangeMode.year) {
              _yearOffset = value.year - now.year;
            } else if (_mode == LongRangeMode.month) {
              _monthOffset = (value.year - now.year) * 12 + value.month - now.month;
            } else {
              final selectedDay = DateTime(value.year, value.month, value.day);
              final selectedWeek = selectedDay.subtract(Duration(days: selectedDay.weekday - 1));
              _weekOffset = selectedWeek.difference(currentWeekStart).inDays ~/ 7;
            }
            _chartLoaded = false;
          }),
        ),
        ProfileReflectionNotice(hasProfileDetails: widget.details.hasAny),
        if (!widget.details.hasExactBirthBase) const BirthPrecisionNotice(),
        if (detailed && !periodContext.usesHighPrecisionAstroData)
          AstroDataSourceNotice(contextData: periodContext),
        if (detailed) LongRangeAstroNotice(mode: _mode),
        SizedBox(height: detailed ? 14 : 10),
        if (_chartLoaded)
          LongRangeChart(
            mode: _mode,
            weekStart: targetWeek,
            yearMode: _mode == LongRangeMode.year,
            month: targetMonth,
            year: targetYear,
            contextFor: _contextFor,
            cardsForStart: (date) => switch (_mode) {
              LongRangeMode.week => _weekCards(DateTime(date.year, date.month, date.day)),
              LongRangeMode.month => _monthCards(DateTime(date.year, date.month)),
              LongRangeMode.year => _yearCards(date.year),
            },
          )
        else
          GlassPanel(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Expanded(child: Text(
                _mode == LongRangeMode.year
                    ? '10年分を計算するため、読み込みに少し時間がかかります。'
                    : _mode == LongRangeMode.month
                        ? '同じ年の12か月分を計算するため、読み込みに少し時間がかかります。'
                        : '運勢の流れグラフは必要なときだけ読み込みます。',
                style: const TextStyle(fontWeight: FontWeight.w700),
              )),
              OutlinedButton.icon(onPressed: () => setState(() => _chartLoaded = true), icon: const Icon(Icons.show_chart_outlined, size: 18), label: const Text('グラフを読む')),
            ]),
          ),
        const SizedBox(height: 14),
        OverallScoreMethodNotice(
          text: switch (_mode) {
            LongRangeMode.week => '総合運について：4分野の平均を7日分で集計しています。',
            LongRangeMode.month => '総合運について：4分野の平均を月内5時点で集計しています。',
            LongRangeMode.year => '総合運について：4分野の平均を年内24時点で集計しています。',
          },
        ),
        LongFortuneCard(
          data: cards.first,
          detailed: detailed,
          details: widget.details,
          shareLabel: shareLabel,
          onShare: () {
            showFortuneShareComposer(
              context,
              periodLabel: '$title / $shareLabel',
              score: cards.first.score,
              body: detailed ? cards.first.detailedText : cards.first.text,
            );
          },
        ),
        LongRangeFortuneList(
          key: ValueKey(
            'long-ai-items-$periodIdentity-$_aiRequestRevision',
          ),
          cards: cards,
          detailed: detailed,
          profile: widget.profile,
          details: widget.details,
          yearMode: _mode == LongRangeMode.year,
          weekStart: _mode == LongRangeMode.week ? targetWeek : null,
          month: targetMonth,
          year: targetYear,
          aiRequested: _aiRequestedFor(targetWeek, targetMonth, targetYear),
          requestRevision: _aiRequestRevision,
        ),
      ],
    );
  }

  String _periodIdentity(DateTime weekStart, DateTime month, int year) {
    return switch (_mode) {
      LongRangeMode.week => 'week-${weekStart.year}-${weekStart.month}-${weekStart.day}',
      LongRangeMode.month => 'month-${month.year}-${month.month}',
      LongRangeMode.year => 'year-$year',
    };
  }

  String _aiKey(DateTime weekStart, DateTime month, int year) {
    return '${_periodIdentity(weekStart, month, year)}|${widget.profile.name}|${widget.profile.birthDate}|${widget.profile.birthTime}|${widget.profile.birthPlace}';
  }

  bool _aiRequestedFor(DateTime weekStart, DateTime month, int year) {
    return _aiRequestKey == _aiKey(weekStart, month, year);
  }

  HoroscopeReadingContext _contextFor(DateTime date) {
    final key = '${date.toIso8601String()}|${HouseSystemSettings.current.value.name}';
    if (!_contextCache.containsKey(key) &&
        _contextCache.length >= _maxContextCacheEntries) {
      _contextCache.clear();
    }
    return _contextCache.putIfAbsent(
      key,
      () => const AstrologyEngine().buildPreviewContext(
        profile: widget.profile,
        date: date,
      ),
    );
  }

  List<LongFortuneData> _cardsFor(DateTime weekStart, DateTime month, int year) {
    final key = [
      _mode.name,
      weekStart.year,
      weekStart.month,
      weekStart.day,
      month.year,
      month.month,
      year,
      widget.profile.name,
      widget.profile.birthDate,
      widget.profile.birthTime,
      widget.profile.birthPlace,
      widget.details.personality,
      widget.details.concerns,
      widget.details.readingStyle,
      HouseSystemSettings.current.value.name,
    ].join('|');
    if (!_cardsCache.containsKey(key) &&
        _cardsCache.length >= _maxCardsCacheEntries) {
      _cardsCache.clear();
    }
    return _cardsCache.putIfAbsent(
      key,
      () => switch (_mode) {
        LongRangeMode.week => _weekCards(weekStart),
        LongRangeMode.month => _monthCards(month),
        LongRangeMode.year => _yearCards(year),
      },
    );
  }

  DateTime _atNoon(DateTime date) => DateTime(date.year, date.month, date.day, 12);

  String _periodSign(AstroPlanet planet, DateTime start, {required bool monthMode}) {
    final ephemeris = AstrologyDataSources.current;
    final placement = ephemeris.placementsFor(start).firstWhere(
          (item) => item.planet == planet,
        );
    final ingress = ephemeris.nextSignIngress(planet, start);
    final end = monthMode ? DateTime(start.year, start.month + 1) : DateTime(start.year + 1);
    final moveLabel = ingress != null && ingress.time.isBefore(end)
        ? ' → ${ingress.sign.label} ${ingress.time.month}/${ingress.time.day}'
        : '';
    return '${planet.label}: ${placement.sign.label}$moveLabel';
  }

  String _transitHouseFor(HoroscopeReadingContext contextData, AstroPlanet planet) {
    for (final transit in contextData.houseTransits) {
      if (transit.planet == planet) {
        return '${planet.label}: 第${transit.natalHouse}ハウス通過';
      }
    }
    return '${planet.label}: 出生図全体';
  }

  String _natalHouseFor(HoroscopeReadingContext contextData, AstroPlanet planet) {
    final placement = contextData.natal.placementOf(planet);
    if (placement == null) return '出生図の${planet.label}';
    return '出生図の${planet.label}: 第${placement.house}ハウス';
  }

  int _periodScore(
    FortuneArea area,
    HoroscopeReadingContext contextData,
    DateTime periodStart,
    int base,
  ) {
    return FortuneScoreCalculator.periodArea(area, contextData, periodStart, base);
  }

  String _aspectBasisFor(
    HoroscopeReadingContext contextData,
    FortuneArea area,
    String fallback,
  ) {
    final aspects = contextData.aspectsFor(area).take(2).map((item) => item.label).toList();
    final returns = contextData.returns
        .where((item) => item.area == area)
        .take(1)
        .map((item) => item.label)
        .toList();
    final basis = [...aspects, ...returns];
    return basis.isEmpty ? fallback : basis.join(' / ');
  }

  String _periodSimpleText({
    required String title,
    required FortuneArea area,
    required int score,
    required HoroscopeReadingContext contextData,
    required bool yearMode,
    required String periodLabel,
    bool? hasOverallReturnBonus,
  }) {
    final period = periodLabel;
    final hasAspect = contextData.aspectsFor(area).isNotEmpty;
    final hasReturn = contextData.returnsFor(area).isNotEmpty;
    final houseHint = _periodHouseHint(contextData, area);
    final useCaseHint = _periodQuestionDatabaseHint(
      area,
      score,
      periodLabel,
      yearMode: yearMode,
    );
    final reason = hasReturn
        ? '大きな節目の流れが重なり、$houseHint過去のやり方を更新するほど動きます。'
        : hasAspect
            ? '星の動きがこの分野を刺激し、$houseHint停滞していたことにも変化が出やすい時期です。'
            : '$houseHint強い変化を急ぐより、期間を通じた積み重ねが結果につながります。';
    final caution = yearMode
        ? '大きな契約や方針転換は、各月の詳細も見ながら確認を重ねると安定します。'
        : '時期ごとの波を見ながら、月ボイドの時間帯は即決より確認と見直しを優先しましょう。';

    if (title == '総合運') {
      final overallReturnBonus = FortuneScoreCalculator.overallReturnBonus(contextData);
      if (yearMode) {
        if (score >= 82) return '$periodの総合運は追い風です。$reason 春から初夏に整えた土台を夏以降に広げ、秋は成果を選び取るほど手応えが残ります。$caution';
        if (score < 66) return '$periodの総合運は慎重な整え直しがテーマです。$reason 季節ごとに生活と約束を見直し、年末へ向けて無理のない形へ整えると余裕が戻ります。$caution';
        return '$periodの総合運は安定寄りです。$reason 春から夏は整理と育成、秋から年末は整ったものを広げる流れが合います。$caution';
      }
      if (score >= 82) return '$periodの総合運は追い風です。$reason 前半で準備したことを後半へ広げるほど、手応えが残ります。$caution';
      if (score < 66) return '$periodの総合運は慎重な整え直しがテーマです。$reason 大きな変更は急がず、生活と約束を一つずつ安定させると後半に余裕が戻ります。$caution';
      return '$periodの総合運は安定寄りです。$reason 前半は整理、後半は整ったものを少し広げる流れが合います。$caution';
    }

    final focus = switch (title) {
      '恋愛運' => score >= 82
          ? '連絡や出会いの機会を逃さず、安心できる相手との関係を一段進めやすい時期です。'
          : score < 66
              ? '相手の反応を急いで決めつけず、距離感と言葉をゆっくり整える時期です。'
              : '小さな気遣いと率直な会話が、関係を落ち着いて育てる力になります。',
      '仕事運' => score >= 82
          ? '提案、連絡、役割の拡大に追い風があり、準備していたことを表へ出しやすい時期です。'
          : score < 66
              ? '責任を抱え込みやすいので、期限と確認先を整理し、無理な引き受けを減らす時期です。'
              : '整理、調整、継続に強く、止まっていた仕事を形にするほど評価につながります。',
      '金運' => score >= 82
          ? '収入や価値につながる学び・道具への投資を選びやすい時期です。予算を決めて動くほど実りが残ります。'
          : score < 66
              ? '気分による大きな支出に注意し、固定費と契約を見直して安心を先に作る時期です。'
              : '使う目的を整理すると、生活を整える出費と控える出費を分けやすい時期です。',
      _ => score >= 82
          ? '心身の調子を上げる習慣を始めやすく、休む時間も予定に入れるほど活動の幅が広がる時期です。'
          : score < 66
              ? '体調・メンタルを気にかける時期です。疲れを後回しにせず、予定を減らして生活リズムを守るほど整いやすくなります。'
              : '休息と活動のバランスを取り直すと、気持ちの波に振り回されにくくなる時期です。',
    };
    final profileTail = useCaseHint.isEmpty ? '' : ' $useCaseHint';
    return '$periodの$titleは、$focus $reason$profileTail';
  }

  String _periodQuestionDatabaseHint(
    FortuneArea area,
    int score,
    String periodLabel, {
    required bool yearMode,
  }) {
    final hasProfileGuidance =
        widget.details.personality.trim().isNotEmpty ||
        widget.details.concerns.trim().isNotEmpty ||
        widget.details.readingStyle.trim().isNotEmpty;
    if (!hasProfileGuidance) return '';
    final raw =
        '${widget.profile.theme} ${widget.details.personality} ${widget.details.concerns} ${widget.details.readingStyle}'
            .toLowerCase();
    final favorable = score >= 78;
    if (yearMode) {
      return switch (area) {
        FortuneArea.love => favorable
            ? '春から夏は出会いや会う機会を広げ、秋以降は残したい関係を選びましょう。'
            : '前半は距離感を整え、後半は安心して続く関係を見極めましょう。',
        FortuneArea.work when raw.contains('youtube') || raw.contains('動画') || raw.contains('創作') || raw.contains('発信') =>
          favorable
              ? '上半期は制作の型を作り、夏以降は公開と反応の分析を繰り返しましょう。'
              : '上半期は題材と制作手順を整え、秋以降に公開の量と質を見直しましょう。',
        FortuneArea.work when raw.contains('転職') =>
          favorable
              ? '上半期に条件と実績を整え、夏から秋に応募や面談の機会を広げましょう。'
              : '焦って環境を変えず、前半は条件を比べ、後半に続けられる働き方を選びましょう。',
        FortuneArea.work when raw.contains('資格') || raw.contains('勉強') || raw.contains('学習') =>
          favorable
              ? '前半で学習計画を作り、後半は演習と申し込みの節目を置きましょう。'
              : '学ぶ範囲を広げすぎず、季節ごとに復習と理解の確認を重ねましょう。',
        FortuneArea.work => favorable
            ? '前半は実績を形にし、夏以降は提案や発信など外へ見せる機会を増やしましょう。'
            : '役割と期限を季節ごとに見直し、年末に残す仕事を選びましょう。',
        FortuneArea.money => favorable
            ? '季節ごとに予算を決め、夏以降は収入や長く役立つ学びへ配分を見直しましょう。'
            : '固定費、貯蓄、使うお金を季節ごとに分け、年末へ向けて余裕を残しましょう。',
        FortuneArea.mental => favorable
            ? '活動量を上げる季節と休養を優先する季節を分け、生活リズムを守りましょう。'
            : '忙しい季節ほど休養を予定し、睡眠と食事の土台を一年通して守りましょう。',
        FortuneArea.overall => '季節ごとに優先順位を見直し、年末に残したいことへ時間を寄せましょう。',
      };
    }
    String choose(List<String> values) {
      final seed = periodLabel.codeUnits.fold<int>(area.index, (sum, unit) => sum + unit);
      return values[seed % values.length];
    }
    return switch (area) {
      FortuneArea.love when raw.contains('復縁') =>
        favorable ? '復縁は近況確認から。' : '復縁は距離の整理を先に。',
      FortuneArea.love when raw.contains('マッチング') || raw.contains('出会') =>
        favorable ? '出会いの入口を一つ試して。' : '出会い探しは準備を先に。',
      FortuneArea.love => choose(
          favorable
              ? const ['連絡を一つ進めて。', '会う予定を一つ作って。', '出会いの場を一つ試して。']
              : const ['追い連絡は控えて。', '返事を待つ余白を作って。', '距離感を整えて。'],
        ),
      FortuneArea.work when raw.contains('youtube') || raw.contains('動画') || raw.contains('創作') || raw.contains('発信') =>
        favorable ? '公開か告知を一件進めて。' : '制作と分析を先に。',
      FortuneArea.work when raw.contains('転職') =>
        favorable ? '応募を一件進めて。' : '転職条件を比べて。',
      FortuneArea.work when raw.contains('副業') =>
        favorable ? '副業の実績を一つ作って。' : '報酬条件を確認して。',
      FortuneArea.work when raw.contains('資格') || raw.contains('勉強') || raw.contains('学習') =>
        favorable ? '演習を一回終えて。' : '勉強範囲を絞って。',
      FortuneArea.work => choose(
          favorable
              ? const ['提出を一件進めて。', '相談を一件進めて。', '作業を一つ完成させて。']
              : const ['期限を確認して。', '手順を整えて。', '抱える仕事を減らして。'],
        ),
      FortuneArea.money when raw.contains('投資') || raw.contains('nisa') =>
        favorable ? '投資は上限を決めて判断を。' : '投資条件の確認を先に。',
      FortuneArea.money when raw.contains('貯金') || raw.contains('節約') =>
        favorable ? '残す額を先に決めて。' : '固定費を一件見直して。',
      FortuneArea.money => choose(
          favorable
              ? const ['予算内の買い物を選んで。', '必要な支払いを進めて。', '使う目的を一つ決めて。']
              : const ['大きな買い物は保留して。', '契約条件を確認して。', '支出を一度見直して。'],
        ),
      FortuneArea.mental when raw.contains('睡眠') || raw.contains('眠') =>
        favorable ? '睡眠時間を固定して。' : '夜の予定を一つ減らして。',
      FortuneArea.mental when raw.contains('ダイエット') || raw.contains('運動') =>
        favorable ? '軽い運動を習慣にして。' : '運動強度を下げて。',
      FortuneArea.mental => choose(
          favorable
              ? const ['整えたい習慣を一つ始めて。', '休憩を予定に入れて。', '食事時間を守って。']
              : const ['休息を先に確保して。', '予定を一つ減らして。', '活動量を落として。'],
        ),
      FortuneArea.overall => '',
    };
  }

  String _periodHouseHint(HoroscopeReadingContext contextData, FortuneArea area) {
    HouseTransit? transit;
    for (final item in contextData.houseTransitsFor(area)) {
      transit = item;
      break;
    }
    if (transit == null) return '';
    final theme = switch (area) {
      FortuneArea.love => switch (transit!.natalHouse) {
          5 => '楽しみや自己表現、出会いに',
          7 => '対人関係やパートナーシップに',
          8 => '深い結びつきや共有に',
          _ => '人との関わりに',
        },
      FortuneArea.work => switch (transit!.natalHouse) {
          6 => '日々の仕事と習慣に',
          10 => '評価や役割に',
          11 => '仲間や将来の目標に',
          _ => '仕事の進め方に',
        },
      FortuneArea.money => switch (transit!.natalHouse) {
          2 => '収入と支出、持ち物に',
          8 => '共有のお金や契約に',
          11 => '収益につながる仲間や計画に',
          _ => 'お金の使い方に',
        },
      FortuneArea.mental => switch (transit!.natalHouse) {
          4 => '居場所や安心感に',
          6 => '生活リズムと体調管理に',
          12 => '休息や心の整理に',
          _ => '心身の整え方に',
        },
      FortuneArea.overall => switch (transit!.natalHouse) {
          1 => '自分自身の打ち出し方に',
          5 => '創作や自己表現に',
          9 => '学びや視野の広がりに',
          10 => '社会的な役割に',
          _ => '人生全体のテーマに',
        },
    };
    return '$theme '; 
  }

  List<LongFortuneData> _weekCards(DateTime weekStart) {
    final dates = List<DateTime>.generate(7, (index) => _atNoon(weekStart.add(Duration(days: index))));
    final contexts = dates.map(_contextFor).toList();
    final baseContext = contexts.first;
    List<int> scores(FortuneArea area, int base) => List<int>.generate(
          7,
          (index) => _periodScore(area, contexts[index], dates[index], base),
        );
    int average(List<int> values) => (values.reduce((a, b) => a + b) / values.length).round();
    int bestIndex(List<int> values) => List<int>.generate(values.length, (i) => i)
      .reduce((a, b) => values[a] >= values[b] ? a : b);
    int lowIndex(List<int> values) => List<int>.generate(values.length, (i) => i)
      .reduce((a, b) => values[a] <= values[b] ? a : b);
    String dayLabel(int index) => '${dates[index].month}/${dates[index].day}';
    final love = scores(FortuneArea.love, 70);
    final work = scores(FortuneArea.work, 74);
    final money = scores(FortuneArea.money, 68);
    final mental = scores(FortuneArea.mental, 72);
    final overallDaily = List<int>.generate(
      7,
      (index) => FortuneScoreCalculator.overallWithReturnBonus(
        [love[index], work[index], money[index], mental[index]],
        contexts[index],
      ),
    );
    final overallReturnBonuses = contexts
        .map(FortuneScoreCalculator.overallReturnBonus)
        .whereType<({AstroPlanet planet, double value, String detail, String formula})>()
        .toList();
    final overallReturnLabels = overallReturnBonuses.map((bonus) => bonus.planet.label).toSet();
    final periodReturnPeak = FortuneScoreCalculator.periodReturnPeakBonus(contexts);
    LongFortuneData makeCard({
      required String title,
      required FortuneArea area,
      required AstroPlanet planet,
      required List<int> values,
      required IconData icon,
      required String action,
      required String frontPlan,
      required String backPlan,
      required String carefulPlan,
    }) {
      final score = (average(values) + (title == '総合運' ? (periodReturnPeak?.value ?? 0) : 0)).round().clamp(50, 99).toInt();
      final best = bestIndex(values);
      final low = lowIndex(values);
      final highestScore = values.reduce(math.max);
      final lowestScore = values.reduce(math.min);
      final hasDailyDifference = highestScore - lowestScore >= 2;
      final period = '${weekStart.month}/${weekStart.day}週';
      final dignityDetails = <String>[];
      String? dignityFormula;
      for (final context in contexts) {
        final targetAreas = area == FortuneArea.overall
            ? const [FortuneArea.love, FortuneArea.work, FortuneArea.money, FortuneArea.mental]
            : [area];
        for (final targetArea in targetAreas) {
          final dignity = FortuneScoreCalculator.planetarySignDignityFor(context, targetArea);
          if (dignity.value == 0) continue;
          dignityDetails.add('${targetArea.label}: ${dignity.detail}');
          dignityFormula ??= dignity.formula;
        }
      }
      final placement = baseContext.transit.placements.firstWhere((item) => item.planet == planet);
      final outlook = score >= 82
          ? '追い風を使いやすい週です。'
          : score < 66
              ? '無理を減らすほど整う週です。'
              : '小さく動いて反応を見る週です。';
      final overallMethod = title == '総合運'
          ? '${periodReturnPeak == null ? '' : '${periodReturnPeak.planet.label}リターンの期間ピーク+${periodReturnPeak.value.toStringAsFixed(1)}点も反映しています。'}'
          : '';
      return LongFortuneData(
        title: title,
        score: score,
        sign: '${planet.label}: ${placement.sign.label}',
        transitHouse: _transitHouseFor(baseContext, planet),
        natalHouse: _natalHouseFor(baseContext, planet),
        aspectBasis: _aspectBasisFor(baseContext, area, '7日分の星配置と点数を集計'),
        text: hasDailyDifference
            ? '$periodの$titleは$outlook$overallMethod$frontPlan ${dayLabel(best)}は流れが強く、$action。${dayLabel(low)}は$carefulPlan'
            : '$periodの$titleは$outlook$overallMethod$frontPlan 日ごとの差は小さいため、$backPlan',
        detailedText: hasDailyDifference
            ? '$overallMethod週前半は$frontPlan 週後半は$backPlan ${dayLabel(best)}は$titleの動く日なので、$action。${dayLabel(low)}は慎重日にあたり、$carefulPlan'
            : '$overallMethod週前半は$frontPlan 週後半は$backPlan この週は日ごとの上下が小さく、特定の日へ勝負を寄せるより、同じペースを保つ方が$titleを活かせます。',
        evidence: [
          if (title == '総合運') '総合運: 4分野平均を7日分で集計',
          if (title == '総合運' && overallReturnBonuses.isNotEmpty)
            '総合リターン特例: 各日の最強1件のみ（${overallReturnLabels.join('・')}）。例: ${overallReturnBonuses.first.planet.label} ${overallReturnBonuses.first.detail} / ${overallReturnBonuses.first.formula}',
          if (dignityDetails.isNotEmpty)
            '天体のサイン品位: ${dignityDetails.take(3).join(' / ')}${dignityDetails.length > 3 ? ' ほか${dignityDetails.length - 3}件' : ''} / $dignityFormula',
          hasDailyDifference ? '動く日: ${dayLabel(best)} ${values[best]}点' : '動く日: 目立つ突出なし',
          hasDailyDifference ? '慎重な日: ${dayLabel(low)} ${values[low]}点' : '慎重な日: 目立つ落ち込みなし',
          '7日平均: $score点',
        ],
        icon: icon,
      );
    }
    return [
      makeCard(title: '総合運', area: FortuneArea.overall, planet: AstroPlanet.sun, values: overallDaily, icon: Icons.auto_awesome_outlined, action: '一番優先したいことを外へ出すと進みやすいです', frontPlan: '予定を二つまでに絞り、先に土台を整えると余裕が生まれます。', backPlan: '前半で手応えのあった一つへ力を寄せると成果が残ります。', carefulPlan: '大きな決断を急がず、予定と体力を見直すと安定します。'),
      makeCard(title: '恋愛運', area: FortuneArea.love, planet: AstroPlanet.venus, values: love, icon: Icons.favorite_border, action: '連絡や会う提案を一つ進めると関係が動きやすいです', frontPlan: '短い会話で相手の温度を確かめ、連絡を増やしすぎないことが大切です。', backPlan: '反応が良い相手には具体的な候補日を一つ出すと関係が進みます。', carefulPlan: '返事を急かさず、重い確認や結論を別の日へ回しましょう。'),
      makeCard(title: '仕事運', area: FortuneArea.work, planet: AstroPlanet.mercury, values: work, icon: Icons.work_outline, action: '応募、提出、公開、相談のどれかを一つ実行すると成果につながりやすいです', frontPlan: '締切と完成条件を確認し、資料や下書きを先に整えると進みます。', backPlan: '整えたものを提出・公開し、相手の反応から次の修正点を決めましょう。', carefulPlan: '送信、契約、公開前に日時・相手・内容をもう一度確認しましょう。'),
      makeCard(title: '金運', area: FortuneArea.money, planet: AstroPlanet.jupiter, values: money, icon: Icons.savings_outlined, action: '収入につながる確認や必要な支出を一つ進めると流れを使えます', frontPlan: '今週使える額と固定の支払いを分け、先に残すお金を確保しましょう。', backPlan: '必要な支出と回収できる行動を選び、数字を見て次の一手を決めます。', carefulPlan: '高額な買い物や勢いの投資を避け、予算内か一晩置いて確認しましょう。'),
      makeCard(title: '健康・メンタル運', area: FortuneArea.mental, planet: AstroPlanet.moon, values: mental, icon: Icons.self_improvement_outlined, action: '活動する予定を早めに済ませ、夜は回復へ切り替えると整います', frontPlan: '睡眠、食事、休憩の崩れている一つを戻すと体力を保ちやすくなります。', backPlan: '疲れが少ない時間に用事を済ませ、夜は予定を増やさず回復を優先します。', carefulPlan: '冷えと寝不足を重ねず、疲れのサインが出たら早めに切り上げましょう。'),
    ];
  }

  List<LongFortuneData> _monthCards(DateTime targetMonth) {
    final monthStart = DateTime(targetMonth.year, targetMonth.month, 1, 12);
    final daysInMonth = DateTime(targetMonth.year, targetMonth.month + 1)
        .difference(DateTime(targetMonth.year, targetMonth.month))
        .inDays;
    final sampleDays = <int>{1, 8, 15, 22, daysInMonth}.toList()..sort();
    final sampleDates = sampleDays
        .map((day) => DateTime(targetMonth.year, targetMonth.month, day, 12))
        .toList();
    final contexts = sampleDates.map(_contextFor).toList();
    final contextData = contexts[contexts.length ~/ 2];
    List<int> scores(FortuneArea area, int base) => List<int>.generate(
          contexts.length,
          (index) => _periodScore(area, contexts[index], sampleDates[index], base),
        );
    int average(List<int> values) => (values.reduce((a, b) => a + b) / values.length).round();
    final loveScores = scores(FortuneArea.love, 70);
    final workScores = scores(FortuneArea.work, 74);
    final moneyScores = scores(FortuneArea.money, 68);
    final mentalScores = scores(FortuneArea.mental, 72);
    final loveScore = average(loveScores);
    final workScore = average(workScores);
    final moneyScore = average(moneyScores);
    final mentalScore = average(mentalScores);
    final venus = _periodSign(AstroPlanet.venus, monthStart, monthMode: true);
    final mercury = _periodSign(AstroPlanet.mercury, monthStart, monthMode: true);
    final sun = _periodSign(AstroPlanet.sun, monthStart, monthMode: true);
    final moon = _periodSign(AstroPlanet.moon, monthStart, monthMode: true);
    final jupiter = _periodSign(AstroPlanet.jupiter, monthStart, monthMode: true);
    final retrogrades = contexts.expand((item) => item.retrogradePlanets).toSet();
    final retrogradeNote = retrogrades.isEmpty
        ? ''
        : '月内の確認日で${retrogrades.map((planet) => planet.label).join('・')}の逆行が重なります。該当時期は送信、契約、予定の再確認を優先しましょう。';
    final overallScores = List<int>.generate(
      loveScores.length,
      (index) => FortuneScoreCalculator.overallWithReturnBonus(
        [loveScores[index], workScores[index], moneyScores[index], mentalScores[index]],
        contexts[index],
      ),
    );
    final periodReturnPeak = FortuneScoreCalculator.periodReturnPeakBonus(contexts);
    final overallScore = (average(overallScores) + (periodReturnPeak?.value ?? 0)).round().clamp(50, 99).toInt();
    final overallReturnBonuses = contexts
        .map(FortuneScoreCalculator.overallReturnBonus)
        .whereType<({AstroPlanet planet, double value, String detail, String formula})>()
        .toList();
    final overallReturnLabels = overallReturnBonuses.map((bonus) => bonus.planet.label).toSet();

    String detailedText(String title, FortuneArea area, List<int> values) {
      final firstHalf = average(values.take((values.length + 1) ~/ 2).toList());
      final secondHalf = average(values.skip(values.length ~/ 2).toList());
      final flow = secondHalf >= firstHalf + 2
          ? '後半へ向かうほど動きやすくなる流れです。'
          : firstHalf >= secondHalf + 2
              ? '前半の方が動きやすく、後半は整え直しが大切です。'
              : '前半と後半の差は小さく、同じペースを保つほど安定します。';
      final returns = contexts
          .expand((item) => item.returnsFor(area))
          .map((event) => event.planet.label)
          .toSet();
      final aspects = contexts
          .expand((item) => area == FortuneArea.overall ? item.aspects : item.aspectsFor(area))
          .toList()
        ..sort((left, right) => left.orb.compareTo(right.orb));
      final signal = returns.isNotEmpty
          ? '${returns.join('・')}リターンの影響が確認日に重なるため、過去のやり方を更新する好機です。'
          : aspects.isNotEmpty
              ? '${aspects.first.transitPlanet.label}と出生図の${aspects.first.natalPlanet.label}の${aspects.first.type.label}が月内の主な変動要因です。'
              : '月内の強い突出は少なめで、日々の積み重ねが結果につながります。';
      final action = switch (title) {
        '総合運' => '予定を詰め込まず、月の前半と後半で優先順位を一つずつ決めましょう。',
        '恋愛運' => '連絡、会う提案、待つのどれかを相手の反応に合わせて選びましょう。',
        '仕事運' => '企画・作業・提出のどこまで進めるかを週単位で決めましょう。',
        '金運' => '使う額と残す額を先に分け、数字を見て調整しましょう。',
        _ => '活動日と休養日を分け、睡眠と食事の崩れを先に戻しましょう。',
      };
      final healthNote = title == '健康・メンタル運' && average(values) <= 65
          ? 'この月は体調・メンタルを気にかけ、睡眠・食事・休憩の土台を先に整えましょう。'
          : '';
      final overallMethod = title == '総合運'
          ? ''
          : '';
      return '${targetMonth.year}年${targetMonth.month}月の$titleは5時点の星配置で判定しています。$overallMethod$flow$signal$action$retrogradeNote$healthNote';
    }

    List<String> evidence(FortuneArea area, List<int> values) {
      final returns = contexts
          .expand((item) => item.returnsFor(area))
          .map((event) => event.planet.label)
          .toSet();
      final aspects = contexts
          .expand((item) => area == FortuneArea.overall ? item.aspects : item.aspectsFor(area))
          .toList()
        ..sort((left, right) => left.orb.compareTo(right.orb));
      final dignityDetails = <String>[];
      String? dignityFormula;
      for (final context in contexts) {
        final targetAreas = area == FortuneArea.overall
            ? const [FortuneArea.love, FortuneArea.work, FortuneArea.money, FortuneArea.mental]
            : [area];
        for (final targetArea in targetAreas) {
          final dignity = FortuneScoreCalculator.planetarySignDignityFor(context, targetArea);
          if (dignity.value == 0) continue;
          dignityDetails.add('${targetArea.label}: ${dignity.detail}');
          dignityFormula ??= dignity.formula;
        }
      }
      return [
        if (area == FortuneArea.overall) '総合運: 4分野平均を月内5時点で集計',
        if (area == FortuneArea.overall && overallReturnBonuses.isNotEmpty)
          '総合リターン特例: 各確認日の最強1件のみ（${overallReturnLabels.join('・')}）。例: ${overallReturnBonuses.first.planet.label} ${overallReturnBonuses.first.detail} / ${overallReturnBonuses.first.formula}',
        if (dignityDetails.isNotEmpty)
          '天体のサイン品位: ${dignityDetails.take(3).join(' / ')}${dignityDetails.length > 3 ? ' ほか${dignityDetails.length - 3}件' : ''} / $dignityFormula',
        '月内${sampleDays.join('・')}日の12:00を集計: ${average(values)}点',
        if (aspects.isNotEmpty) '主要: ${aspects.first.label}',
        if (returns.isNotEmpty) '実際のリターン: ${returns.join('・')}',
        if (retrogrades.isNotEmpty) '逆行確認: ${retrogrades.map((planet) => planet.label).join('・')}',
      ];
    }

    return [
      LongFortuneData(
        title: '総合運',
        score: overallScore,
        sign: sun,
        transitHouse: _transitHouseFor(contextData, AstroPlanet.sun),
        natalHouse: _natalHouseFor(contextData, AstroPlanet.sun),
        aspectBasis: _aspectBasisFor(
          contextData,
          FortuneArea.overall,
          '月内5時点の太陽と木星の流れを集計。',
        ),
        text: _periodSimpleText(
          title: '総合運', area: FortuneArea.overall, score: overallScore,
          contextData: contextData, yearMode: false, periodLabel: '${targetMonth.month}月',
        ),
        detailedText: detailedText('総合運', FortuneArea.overall, overallScores),
        evidence: evidence(FortuneArea.overall, overallScores),
        icon: Icons.auto_awesome,
      ),
      LongFortuneData(
        title: '恋愛運',
        score: loveScore,
        sign: venus,
        transitHouse: _transitHouseFor(contextData, AstroPlanet.venus),
        natalHouse: _natalHouseFor(contextData, AstroPlanet.venus),
        aspectBasis: _aspectBasisFor(
          contextData,
          FortuneArea.love,
          '月内5時点の金星と対人アスペクトを集計。',
        ),
        text: _periodSimpleText(
          title: '恋愛運', area: FortuneArea.love, score: loveScore,
          contextData: contextData, yearMode: false, periodLabel: '${targetMonth.month}月',
        ),
        detailedText: detailedText('恋愛運', FortuneArea.love, loveScores),
        evidence: evidence(FortuneArea.love, loveScores),
        icon: Icons.favorite_border,
      ),
      LongFortuneData(
        title: '仕事運',
        score: workScore,
        sign: mercury,
        transitHouse: _transitHouseFor(contextData, AstroPlanet.mercury),
        natalHouse: _natalHouseFor(contextData, AstroPlanet.midheaven),
        aspectBasis: _aspectBasisFor(
          contextData,
          FortuneArea.work,
          '月内5時点の水星と仕事アスペクトを集計。',
        ),
        text: _periodSimpleText(
          title: '仕事運', area: FortuneArea.work, score: workScore,
          contextData: contextData, yearMode: false, periodLabel: '${targetMonth.month}月',
        ),
        detailedText: detailedText('仕事運', FortuneArea.work, workScores),
        evidence: evidence(FortuneArea.work, workScores),
        icon: Icons.work_outline,
      ),
      LongFortuneData(
        title: '金運',
        score: moneyScore,
        sign: venus,
        secondarySign: jupiter,
        transitHouse: '${_transitHouseFor(contextData, AstroPlanet.venus)} / ${_transitHouseFor(contextData, AstroPlanet.jupiter)}',
        natalHouse: '${_natalHouseFor(contextData, AstroPlanet.venus)} / ${_natalHouseFor(contextData, AstroPlanet.jupiter)}',
        aspectBasis: _aspectBasisFor(
          contextData,
          FortuneArea.money,
          '月内5時点の金星・木星と金銭アスペクトを集計。',
        ),
        text: _periodSimpleText(
          title: '金運', area: FortuneArea.money, score: moneyScore,
          contextData: contextData, yearMode: false, periodLabel: '${targetMonth.month}月',
        ),
        detailedText: detailedText('金運', FortuneArea.money, moneyScores),
        evidence: evidence(FortuneArea.money, moneyScores),
        icon: Icons.savings_outlined,
      ),
      LongFortuneData(
        title: '健康・メンタル運',
        score: mentalScore,
        sign: moon,
        transitHouse: _transitHouseFor(contextData, AstroPlanet.moon),
        natalHouse: _natalHouseFor(contextData, AstroPlanet.moon),
        aspectBasis: _aspectBasisFor(
          contextData,
          FortuneArea.mental,
          '現在の月と出生図の月を中心に、月ボイドは休息寄りに補正。',
        ),
        text: _periodSimpleText(
          title: '健康・メンタル運', area: FortuneArea.mental, score: mentalScore,
          contextData: contextData, yearMode: false, periodLabel: '${targetMonth.month}月',
        ),
        detailedText: detailedText('健康・メンタル運', FortuneArea.mental, mentalScores),
        evidence: evidence(FortuneArea.mental, mentalScores),
        icon: Icons.spa_outlined,
      ),
    ];
  }

  List<LongFortuneData> _yearCards(int targetYear) {
    final yearStart = DateTime(targetYear, 1, 1, 12);
    final contextData = _contextFor(yearStart);
    final venus = _periodSign(AstroPlanet.venus, yearStart, monthMode: false);
    final moon = _periodSign(AstroPlanet.moon, yearStart, monthMode: false);
    final jupiter = _periodSign(AstroPlanet.jupiter, yearStart, monthMode: false);
    final saturn = _periodSign(AstroPlanet.saturn, yearStart, monthMode: false);
    final monthlyContexts = List<HoroscopeReadingContext>.generate(
      12,
      (index) => _contextFor(DateTime(targetYear, index + 1, 1, 12)),
    );
    final midMonthContexts = List<HoroscopeReadingContext>.generate(
      12,
      (index) => _contextFor(DateTime(targetYear, index + 1, 15, 12)),
    );
    final annualContexts = [...monthlyContexts, ...midMonthContexts];
    int yearlyAreaScore(FortuneArea area, int base) {
      final average = FortuneScoreCalculator.overallFromAreas(
        List<int>.generate(
          12,
          (index) => ((
                    _periodScore(
                      area,
                      monthlyContexts[index],
                      DateTime(targetYear, index + 1, 1, 12),
                      base,
                    ) +
                    _periodScore(
                      area,
                      midMonthContexts[index],
                      DateTime(targetYear, index + 1, 15, 12),
                      base,
                    )) /
                2)
              .round(),
        ),
      );
      return average;
    }

    final baseLoveScore = yearlyAreaScore(FortuneArea.love, FortuneScoreCalculator.standardBase(FortuneArea.love));
    final baseWorkScore = yearlyAreaScore(FortuneArea.work, FortuneScoreCalculator.standardBase(FortuneArea.work));
    final baseMoneyScore = yearlyAreaScore(FortuneArea.money, FortuneScoreCalculator.standardBase(FortuneArea.money));
    final baseMentalScore = yearlyAreaScore(FortuneArea.mental, FortuneScoreCalculator.standardBase(FortuneArea.mental));
    final annualOverallBaseScores = annualContexts.map((context) {
      return FortuneScoreCalculator.overallFromAreas([
        _periodScore(FortuneArea.love, context, context.transit.date, FortuneScoreCalculator.standardBase(FortuneArea.love)),
        _periodScore(FortuneArea.work, context, context.transit.date, FortuneScoreCalculator.standardBase(FortuneArea.work)),
        _periodScore(FortuneArea.money, context, context.transit.date, FortuneScoreCalculator.standardBase(FortuneArea.money)),
        _periodScore(FortuneArea.mental, context, context.transit.date, FortuneScoreCalculator.standardBase(FortuneArea.mental)),
      ]);
    }).toList();
    final baseOverallScore = FortuneScoreCalculator.overallFromAreas(annualOverallBaseScores);
    final annualReturnBonuses = annualContexts
        .map(FortuneScoreCalculator.overallReturnBonus)
        .whereType<({AstroPlanet planet, double value, String detail, String formula})>()
        .toList();
    final annualReturnBonus = annualReturnBonuses.isEmpty
        ? 0.0
        : annualReturnBonuses.fold<double>(0, (sum, bonus) => sum + bonus.value) / annualContexts.length;
    final annualReturnLabels = annualReturnBonuses.map((bonus) => bonus.planet.label).toSet();
    final annualReturnExample = annualReturnBonuses.isEmpty ? null : annualReturnBonuses.first;
    final annualLifeEventBoost = FortuneScoreCalculator.annualLifeEventBoost(annualContexts);
    int withAnnualLifeEvent(int score, FortuneArea area) {
      return (score + (annualLifeEventBoost?.effectFor(area) ?? 0)).round().clamp(50, 99).toInt();
    }

    final loveScore = withAnnualLifeEvent(baseLoveScore, FortuneArea.love);
    final workScore = withAnnualLifeEvent(baseWorkScore, FortuneArea.work);
    final moneyScore = withAnnualLifeEvent(baseMoneyScore, FortuneArea.money);
    final mentalScore = withAnnualLifeEvent(baseMentalScore, FortuneArea.mental);
    final overallScore = FortuneScoreCalculator.overallFromAreas([
      loveScore,
      workScore,
      moneyScore,
      mentalScore,
    ]);

    String yearDetailedText(String title, FortuneArea area, int score) {
      final returns = annualContexts
          .expand((item) => area == FortuneArea.overall ? item.returns : item.returnsFor(area))
          .map((event) => event.planet.label)
          .toSet();
      final aspects = annualContexts
          .expand((item) => area == FortuneArea.overall ? item.aspects : item.aspectsFor(area))
          .toList()
        ..sort((left, right) => left.orb.compareTo(right.orb));
      final retrogrades = annualContexts.expand((item) => item.retrogradePlanets).toSet();
      final outlook = score >= 82
          ? '年間を通して追い風を使いやすい流れです。'
          : score < 66
              ? '急いで広げず、土台を整え直すほど安定する流れです。'
              : '大きな上下に振り回されず、継続したことが残りやすい流れです。';
      final signal = returns.isNotEmpty
          ? '${returns.join('・')}リターンが24時点の確認範囲に入り、過去のやり方を更新する節目になります。'
          : aspects.isNotEmpty
              ? '${aspects.first.transitPlanet.label}と出生図の${aspects.first.natalPlanet.label}の${aspects.first.type.label}が年間の主な変動要因です。'
              : '強い突出は少なめで、季節ごとの見直しが成果につながります。';
      final annualAreaEffect = area == FortuneArea.overall
          ? annualLifeEventBoost?.value ?? 0
          : annualLifeEventBoost?.effectFor(area) ?? 0;
      final annualPeakHint = annualLifeEventBoost != null && annualAreaEffect > 0
          ? '${annualLifeEventBoost.detail}が、この年の$titleへ+${annualAreaEffect.toStringAsFixed(1)}点として反映される山です。'
          : '';
      final narrativeSignal = annualAreaEffect > 0 ? '' : signal;
      final action = switch (title) {
        '総合運' => '季節ごとに優先テーマを定め、負担と成果を見直しましょう。',
        '恋愛運' => '関係を進める時期と距離を整える時期を分け、相手の反応を確かめましょう。',
        '仕事運' => '実績を形にする期間と外へ出す期間を分け、四半期ごとに見直しましょう。',
        '金運' => '固定費、貯蓄、増やす行動を分け、季節ごとに予算を更新しましょう。',
        _ => '忙しい時期ほど休養を先に予定し、生活リズムを季節ごとに点検しましょう。',
      };
      final retrogradeText = retrogrades.isEmpty
          ? ''
          : '年内の確認日で${retrogrades.map((planet) => planet.label).join('・')}の逆行が重なる時期は、契約や予定を再確認しましょう。';
      final healthNote = title == '健康・メンタル運' && score <= 65
          ? 'この年は体調・メンタルを気にかけ、忙しい季節ほど休養を先に予定しましょう。'
          : '';
      final overallMethod = area == FortuneArea.overall
          ? '年全体を24時点で読み、強い節目を重ねています。点数と式は下の「この点数の理由」で確認できます。'
          : '';
      return '$targetYear年の$title。$overallMethod$outlook$narrativeSignal$annualPeakHint$action$retrogradeText$healthNote';
    }

    List<String> yearEvidence(FortuneArea area, int score) {
      final returns = annualContexts
          .expand((item) => area == FortuneArea.overall ? item.returns : item.returnsFor(area))
          .map((event) => event.planet.label)
          .toSet();
      final aspects = annualContexts
          .expand((item) => area == FortuneArea.overall ? item.aspects : item.aspectsFor(area))
          .toList()
        ..sort((left, right) => left.orb.compareTo(right.orb));
      final annualAreaEffect = area == FortuneArea.overall
          ? annualLifeEventBoost?.value ?? 0
          : annualLifeEventBoost?.effectFor(area) ?? 0;
      final dignityDetails = <String>[];
      String? dignityFormula;
      for (final context in annualContexts) {
        final targetAreas = area == FortuneArea.overall
            ? const [FortuneArea.love, FortuneArea.work, FortuneArea.money, FortuneArea.mental]
            : [area];
        for (final targetArea in targetAreas) {
          final dignity = FortuneScoreCalculator.planetarySignDignityFor(context, targetArea);
          if (dignity.value == 0) continue;
          dignityDetails.add('${targetArea.label}: ${dignity.detail}');
          dignityFormula ??= dignity.formula;
        }
      }
      return [
        if (area == FortuneArea.overall) '4分野の年点数平均: $baseOverallScore点',
        if (area == FortuneArea.overall && annualReturnLabels.isNotEmpty)
          '総合リターン特例の24時点平均: +${annualReturnBonus.toStringAsFixed(1)}点（${annualReturnLabels.join('・')}）',
        if (area == FortuneArea.overall && annualReturnExample != null)
          '特例の式（例）: ${annualReturnExample.planet.label} ${annualReturnExample.detail} / ${annualReturnExample.formula}',
        if (annualLifeEventBoost != null && annualAreaEffect > 0)
          '年専用の人生イベント補正: +${annualAreaEffect.toStringAsFixed(1)}点（${annualLifeEventBoost.detail}） / ${annualLifeEventBoost.formula}',
        if (dignityDetails.isNotEmpty)
          '天体のサイン品位: ${dignityDetails.take(3).join(' / ')}${dignityDetails.length > 3 ? ' ほか${dignityDetails.length - 3}件' : ''} / $dignityFormula',
        if (area == FortuneArea.overall) '最終: 特例反映後の4分野（恋愛$loveScore・仕事$workScore・金運$moneyScore・健康/メンタル$mentalScore）の平均 → $score点（50〜99点）',
        '$targetYear年の24時点を集計: $score点',
        if (aspects.isNotEmpty) '主要: ${aspects.first.label}',
        if (returns.isNotEmpty) '実際のリターン: ${returns.join('・')}',
      ];
    }

    return [
      LongFortuneData(
        title: '総合運',
        score: overallScore,
        sign: jupiter,
        transitHouse: _transitHouseFor(contextData, AstroPlanet.jupiter),
        natalHouse: _natalHouseFor(contextData, AstroPlanet.sun),
        aspectBasis: _aspectBasisFor(
          contextData,
          FortuneArea.overall,
          '年内24時点の4分野平均と総合リターン特例を集計。',
        ),
        text: _periodSimpleText(
          title: '総合運', area: FortuneArea.overall, score: overallScore,
          contextData: contextData, yearMode: true, periodLabel: '${targetYear}年',
          hasOverallReturnBonus: annualReturnBonuses.isNotEmpty,
        ),
        detailedText: yearDetailedText('総合運', FortuneArea.overall, overallScore),
        evidence: yearEvidence(FortuneArea.overall, overallScore),
        icon: Icons.auto_graph_outlined,
      ),
      LongFortuneData(
        title: '恋愛運',
        score: loveScore,
        sign: venus,
        transitHouse: _transitHouseFor(contextData, AstroPlanet.venus),
        natalHouse: _natalHouseFor(contextData, AstroPlanet.venus),
        aspectBasis: _aspectBasisFor(
          contextData,
          FortuneArea.love,
          '年内24時点の金星と対人アスペクトを集計。',
        ),
        text: _periodSimpleText(
          title: '恋愛運', area: FortuneArea.love, score: loveScore,
          contextData: contextData, yearMode: true, periodLabel: '${targetYear}年',
        ),
        detailedText: yearDetailedText('恋愛運', FortuneArea.love, loveScore),
        evidence: yearEvidence(FortuneArea.love, loveScore),
        icon: Icons.favorite_border,
      ),
      LongFortuneData(
        title: '仕事運',
        score: workScore,
        sign: saturn,
        transitHouse: _transitHouseFor(contextData, AstroPlanet.saturn),
        natalHouse: _natalHouseFor(contextData, AstroPlanet.midheaven),
        aspectBasis: _aspectBasisFor(
          contextData,
          FortuneArea.work,
          '年内24時点の土星と仕事アスペクトを集計。',
        ),
        text: _periodSimpleText(
          title: '仕事運', area: FortuneArea.work, score: workScore,
          contextData: contextData, yearMode: true, periodLabel: '${targetYear}年',
        ),
        detailedText: yearDetailedText('仕事運', FortuneArea.work, workScore),
        evidence: yearEvidence(FortuneArea.work, workScore),
        icon: Icons.work_outline,
      ),
      LongFortuneData(
        title: '金運',
        score: moneyScore,
        sign: venus,
        secondarySign: jupiter,
        transitHouse: '${_transitHouseFor(contextData, AstroPlanet.venus)} / ${_transitHouseFor(contextData, AstroPlanet.jupiter)}',
        natalHouse: '${_natalHouseFor(contextData, AstroPlanet.venus)} / ${_natalHouseFor(contextData, AstroPlanet.jupiter)}',
        aspectBasis: _aspectBasisFor(
          contextData,
          FortuneArea.money,
          '現在の金星と木星を分けて読み、ステリウムや強調ハウスも補正。',
        ),
        text: _periodSimpleText(
          title: '金運', area: FortuneArea.money, score: moneyScore,
          contextData: contextData, yearMode: true, periodLabel: '${targetYear}年',
        ),
        detailedText: yearDetailedText('金運', FortuneArea.money, moneyScore),
        evidence: yearEvidence(FortuneArea.money, moneyScore),
        icon: Icons.savings_outlined,
      ),
      LongFortuneData(
        title: '健康・メンタル運',
        score: mentalScore,
        sign: moon,
        transitHouse: _transitHouseFor(contextData, AstroPlanet.moon),
        natalHouse: _natalHouseFor(contextData, AstroPlanet.moon),
        aspectBasis: _aspectBasisFor(
          contextData,
          FortuneArea.mental,
          '年内24時点の月と心身アスペクトを集計。',
        ),
        text: _periodSimpleText(
          title: '健康・メンタル運', area: FortuneArea.mental, score: mentalScore,
          contextData: contextData, yearMode: true, periodLabel: '${targetYear}年',
        ),
        detailedText: yearDetailedText('健康・メンタル運', FortuneArea.mental, mentalScore),
        evidence: yearEvidence(FortuneArea.mental, mentalScore),
        icon: Icons.self_improvement_outlined,
      ),
    ];
  }
}

class LongRangeNavigator extends StatelessWidget {
  const LongRangeNavigator({
    super.key,
    required this.mode,
    required this.weekStart,
    required this.month,
    required this.year,
    required this.onModeChanged,
    required this.onPrevious,
    required this.onNext,
    required this.onCurrent,
    required this.busy,
    required this.onSelectDate,
  });

  final LongRangeMode mode;
  final DateTime weekStart;
  final DateTime month;
  final int year;
  final ValueChanged<LongRangeMode> onModeChanged;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onCurrent;
  final bool busy;
  final ValueChanged<DateTime> onSelectDate;

  @override
  Widget build(BuildContext context) {
    final weekEnd = weekStart.add(const Duration(days: 6));
    final label = switch (mode) {
      LongRangeMode.week => '${weekStart.year}年 ${weekStart.month}/${weekStart.day}〜${weekEnd.month}/${weekEnd.day}',
      LongRangeMode.month => '${month.year}年${month.month}月',
      LongRangeMode.year => '$year年',
    };

    return GlassPanel(
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 日付ナビゲーションと同じく、360dp級だけを二段配置にする。
          final compact = MediaQuery.sizeOf(context).width < 390;
          final periodSummary = FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
          );
          final selectPeriod = IconButton(
            tooltip: '期間を選ぶ',
            onPressed: busy
                ? null
                : () async {
                    final initial = mode == LongRangeMode.year
                        ? DateTime(year)
                        : mode == LongRangeMode.week
                            ? weekStart
                            : month;
                    final selected = await showDatePicker(
                      context: context,
                      initialDate: initial,
                      firstDate: DateTime(1900),
                      lastDate: DateTime(2100),
                      helpText: '占う期間を選択',
                    );
                    if (selected != null) onSelectDate(selected);
                  },
            icon: const Icon(Icons.calendar_month_outlined),
          );
          final previous = IconButton(
            tooltip: mode == LongRangeMode.year ? '前年' : mode == LongRangeMode.week ? '前週' : '前月',
            onPressed: busy ? null : onPrevious,
            icon: busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.chevron_left),
          );
          final next = IconButton(
            tooltip: mode == LongRangeMode.year ? '翌年' : mode == LongRangeMode.week ? '翌週' : '翌月',
            onPressed: busy ? null : onNext,
            icon: busy ? const SizedBox(width: 22, height: 22) : const Icon(Icons.chevron_right),
          );
          final current = TextButton(
            onPressed: busy ? null : onCurrent,
            child: Text(busy ? '読み替え中…' : mode == LongRangeMode.year ? '今年' : mode == LongRangeMode.week ? '今週' : '今月'),
          );
          return Column(
            children: [
          Row(
            children: [
              Expanded(
                child: SegmentedButton<LongRangeMode>(
                  segments: const [
                    ButtonSegment(value: LongRangeMode.week, label: Text('週')),
                    ButtonSegment(value: LongRangeMode.month, label: Text('月')),
                    ButtonSegment(value: LongRangeMode.year, label: Text('年')),
                  ],
                  selected: {mode},
                  onSelectionChanged: busy ? null : (value) => onModeChanged(value.first),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (compact) ...[
            Row(children: [previous, Expanded(child: periodSummary), next]),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [current, selectPeriod]),
          ] else
            Row(children: [previous, Expanded(child: periodSummary), current, selectPeriod, next]),
          if (busy) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(minHeight: 3),
          ],
            ],
          );
        },
      ),
    );
  }
}

class LongRangeAstroNotice extends StatelessWidget {
  const LongRangeAstroNotice({super.key, required this.mode});

  final LongRangeMode mode;

  @override
  Widget build(BuildContext context) {
    final text = switch (mode) {
      LongRangeMode.week => '4週間分の週間占いカードと同じ点数から、週ごとの流れを反映。',
      LongRangeMode.month => '同じ年の12か月分の月間占いカードと同じ点数から、月ごとの流れを反映。',
      LongRangeMode.year => '10年分の年間占いカードと同じ点数から、長期の流れを反映。',
    };

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFB58CFF).withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome_motion, color: Color(0xFFB58CFF), size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.62),
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LongRangeChart extends StatefulWidget {
  const LongRangeChart({
    super.key,
    required this.mode,
    required this.weekStart,
    required this.yearMode,
    required this.month,
    required this.year,
    required this.contextFor,
    required this.cardsForStart,
  });

  final bool yearMode;
  final LongRangeMode mode;
  final DateTime weekStart;
  final DateTime month;
  final int year;
  final HoroscopeReadingContext Function(DateTime) contextFor;
  final List<LongFortuneData> Function(DateTime) cardsForStart;

  @override
  State<LongRangeChart> createState() => _LongRangeChartState();
}

class _LongRangeChartState extends State<LongRangeChart> {
  bool get _showDecade => widget.mode == LongRangeMode.year;
  String? _cachedSeriesKey;
  List<FortuneFlowSeries>? _cachedSeries;

  @override
  Widget build(BuildContext context) {
    final labels = _showDecade
        ? List<String>.generate(10, (index) => '${widget.year + index}')
        : widget.mode == LongRangeMode.week
            ? List<String>.generate(4, (index) {
                final date = widget.weekStart.add(Duration(days: index * 7));
                return '${date.month}/${date.day}週';
              })
            : List<String>.generate(12, (index) => '${index + 1}月');
    final series = _seriesForCurrentPeriod();

    return GlassPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '運勢の流れ',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                _showDecade
                    ? '${widget.year}〜${widget.year + 9}年'
                    : widget.mode == LongRangeMode.week
                        ? '1週間ごとの4週間'
                        : '${widget.month.year}年の月ごとの推移',
                style: TextStyle(
                  color: const Color(0xFFF6D77A).withValues(alpha: 0.86),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          if (widget.mode == LongRangeMode.month) ...[
            const SizedBox(height: 8),
            Text(
              '選択した月と同じ年の、各月の月間占い点数を表示しています。',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.62),
                fontSize: 11,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: CustomPaint(
              painter: FortuneFlowPainter(series: series, labels: labels),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: series
                .map(
                  (item) => _FlowLegend(label: item.label, color: item.color),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  List<FortuneFlowSeries> _periodSeries() {
    // グラフは近似値を再計算せず、各期間カードに出す実点数をそのまま使う。
    // これで「カードは91点、グラフは82点」のような食い違いをなくす。
    final points = _showDecade
        ? List<DateTime>.generate(10, (index) => DateTime(widget.year + index, 1, 1, 12))
        : widget.mode == LongRangeMode.week
            ? List<DateTime>.generate(4, (index) => widget.weekStart.add(Duration(days: index * 7)))
            : List<DateTime>.generate(12, (index) => DateTime(widget.month.year, index + 1, 1, 12));
    final cards = points.map(widget.cardsForStart).toList();
    List<int> values(String title) => cards
        .map((items) => items.firstWhere((item) => item.title == title).score)
        .toList();
    return [
      FortuneFlowSeries(
        label: '総合',
        color: const Color(0xFFF6D77A),
        values: values('総合運'),
      ),
      FortuneFlowSeries(
        label: '恋愛',
        color: const Color(0xFFFF82B2),
        values: values('恋愛運'),
      ),
      FortuneFlowSeries(
        label: '仕事',
        color: const Color(0xFF57D6D1),
        values: values('仕事運'),
      ),
      FortuneFlowSeries(
        label: '金運',
        color: const Color(0xFF9BE06D),
        values: values('金運'),
      ),
      FortuneFlowSeries(
        label: 'メンタル',
        color: const Color(0xFFB58CFF),
        values: values('健康・メンタル運'),
      ),
    ];
  }

  List<FortuneFlowSeries> _seriesForCurrentPeriod() {
    final key = [
      widget.mode.name,
      widget.weekStart.toIso8601String(),
      widget.month.year,
      widget.month.month,
      widget.year,
    ].join('|');
    if (_cachedSeriesKey == key && _cachedSeries != null) {
      return _cachedSeries!;
    }
    final series = _periodSeries();
    _cachedSeriesKey = key;
    _cachedSeries = series;
    return series;
  }

}

class FortuneFlowSeries {
  const FortuneFlowSeries({
    required this.label,
    required this.color,
    required this.values,
  });

  final String label;
  final Color color;
  final List<int> values;
}

class _FlowLegend extends StatelessWidget {
  const _FlowLegend({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.72),
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class FortuneFlowPainter extends CustomPainter {
  FortuneFlowPainter({
    required this.series,
    required this.labels,
  });

  final List<FortuneFlowSeries> series;
  final List<String> labels;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 34.0;
    const right = 12.0;
    const top = 12.0;
    const bottom = 42.0;
    final chart = Rect.fromLTWH(
      left,
      top,
      size.width - left - right,
      size.height - top - bottom,
    );

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..strokeWidth = 1;
    final labelPainter = TextPainter(textDirection: TextDirection.ltr);

    for (final value in [60, 70, 80, 90]) {
      final y = _yForValue(value, chart);
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
      labelPainter.text = TextSpan(
        text: '$value',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.42),
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      );
      labelPainter.layout();
      labelPainter.paint(canvas, Offset(4, y - labelPainter.height / 2));
    }

    for (var i = 0; i < labels.length; i++) {
      final x = chart.left + chart.width * i / (labels.length - 1);
      labelPainter.text = TextSpan(
        text: labels[i],
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.50),
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      );
      labelPainter.layout();
      labelPainter.paint(canvas, Offset(x - labelPainter.width / 2, chart.bottom + 8));
    }

    for (final item in series) {
      final path = Path();
      for (var i = 0; i < item.values.length; i++) {
        final x = chart.left + chart.width * i / (item.values.length - 1);
        final y = _yForValue(item.values[i], chart);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }

      canvas.drawPath(
        path,
        Paint()
          ..color = item.color
          ..strokeWidth = 2.6
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );

      for (var i = 0; i < item.values.length; i++) {
        final x = chart.left + chart.width * i / (item.values.length - 1);
        final y = _yForValue(item.values[i], chart);
        canvas.drawCircle(Offset(x, y), 3.4, Paint()..color = item.color);
      }
    }
  }

  double _yForValue(int value, Rect chart) {
    final normalized = ((value - 50) / 49).clamp(0.0, 1.0).toDouble();
    return chart.bottom - chart.height * normalized;
  }

  @override
  bool shouldRepaint(covariant FortuneFlowPainter oldDelegate) {
    return oldDelegate.series != series || oldDelegate.labels != labels;
  }
}

class LongFortuneData {
  const LongFortuneData({
    required this.title,
    required this.score,
    required this.sign,
    this.secondarySign,
    required this.transitHouse,
    required this.natalHouse,
    required this.aspectBasis,
    this.chartBasis = '出生図全体: ハウス集中も補正',
    required this.text,
    required this.detailedText,
    required this.evidence,
    required this.icon,
  });

  final String title;
  final int score;
  final String sign;
  final String? secondarySign;
  final String transitHouse;
  final String natalHouse;
  final String aspectBasis;
  final String chartBasis;
  final String text;
  final String detailedText;
  final List<String> evidence;
  final IconData icon;
}

class ExternalAstroDataExportCard extends StatelessWidget {
  const ExternalAstroDataExportCard({
    super.key,
    required this.mode,
    required this.periodLabel,
    required this.weekStart,
    required this.month,
    required this.year,
    required this.profile,
    required this.details,
    required this.contextData,
    required this.cards,
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
        .map((item) => <String, Object?>{
              'planet': item.planet.label,
              'sign': item.sign.label,
              'degree': item.degree,
              'house': item.house,
            })
        .toList();
  }

  Map<String, Object?> _transitSnapshot(HoroscopeReadingContext context) {
    final dayStart = DateTime(context.transit.date.year, context.transit.date.month, context.transit.date.day);
    final stationEvents = DailyAstroEventsCard(date: context.transit.date, contextData: context)
        ._stationEvents(dayStart, dayStart.add(const Duration(days: 1)), AstrologyDataSources.current);
    final dailyEvents = DailyAstroEventsCard(date: context.transit.date, contextData: context)
        ._dailyEvents(dayStart, dayStart.add(const Duration(days: 1)), AstrologyDataSources.current);
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
      'lunar_phase': DailyAstroEventsCard(date: context.transit.date, contextData: context)
          ._lunarPhaseSnapshot(context.transit.date, AstrologyDataSources.current),
      'lunar_phase_score_effects': FortuneScoreCalculator.lunarPhaseScoreEffects(context),
      'planetary_sign_dignity_effects': FortuneScoreCalculator.planetarySignDignityEffects(context),
      'overall_return_bonus': _overallReturnBonusSnapshot(context),
      'retrograde_planets': {
        ...context.retrogradePlanets,
        ...DailyAstroEventsCard.verifiedRetrogradesAt(context.transit.date),
      }.map((item) => item.label).toList(),
      'station_events_jst': stationEvents,
      if (dailyEvents.isNotEmpty) 'daily_events_jst': dailyEvents,
      'special_configurations_at_reference_time': _transitConfigurationSnapshot(context),
    };
  }

  Map<String, Object?>? _overallReturnBonusSnapshot(HoroscopeReadingContext context) {
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
    final daily = const AstrologyEngine().buildPreviewContext(profile: profile, date: date);
    final dayStart = DateTime(date.year, date.month, date.day);
    final eventCard = DailyAstroEventsCard(date: date, contextData: daily);
    final stationEvents = eventCard._stationEvents(dayStart, dayStart.add(const Duration(days: 1)), AstrologyDataSources.current);
    final dailyEvents = eventCard._dailyEvents(dayStart, dayStart.add(const Duration(days: 1)), AstrologyDataSources.current);
    return {
      'date': '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      'date_time_jst': _dateTimeJst(date),
      'overall': FortuneScoreCalculator.dailyOverall(daily),
      'love': FortuneScoreCalculator.dailyArea(daily, FortuneArea.love, FortuneScoreCalculator.standardBase(FortuneArea.love)),
      'work': FortuneScoreCalculator.dailyArea(daily, FortuneArea.work, FortuneScoreCalculator.standardBase(FortuneArea.work)),
      'money': FortuneScoreCalculator.dailyArea(daily, FortuneArea.money, FortuneScoreCalculator.standardBase(FortuneArea.money)),
      'mental': FortuneScoreCalculator.dailyArea(daily, FortuneArea.mental, FortuneScoreCalculator.standardBase(FortuneArea.mental)),
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
      'lunar_phase': DailyAstroEventsCard(date: date, contextData: daily)
          ._lunarPhaseSnapshot(date, AstrologyDataSources.current),
      'lunar_phase_score_effects': FortuneScoreCalculator.lunarPhaseScoreEffects(daily),
      'planetary_sign_dignity_effects': FortuneScoreCalculator.planetarySignDignityEffects(daily),
      'overall_return_bonus': _overallReturnBonusSnapshot(daily),
      'retrograde_planets': {
        ...daily.retrogradePlanets,
        ...DailyAstroEventsCard.verifiedRetrogradesAt(date),
      }.map((item) => item.label).toList(),
      'station_events_jst': stationEvents,
      if (dailyEvents.isNotEmpty) 'daily_events_jst': dailyEvents,
      'special_configurations_at_reference_time': _transitConfigurationSnapshot(daily),
    };
  }

  List<Map<String, Object?>> _annualMonths() {
    return List.generate(12, (index) {
      final month = index + 1;
      final firstDate = DateTime(year, month, 1, 12);
      final middleDate = DateTime(year, month, 15, 12);
      final first = const AstrologyEngine().buildPreviewContext(profile: profile, date: firstDate);
      final middle = const AstrologyEngine().buildPreviewContext(profile: profile, date: middleDate);
      List<int> scorePair(FortuneArea area, int base) => [
        FortuneScoreCalculator.periodArea(area, first, firstDate, base),
        FortuneScoreCalculator.periodArea(area, middle, middleDate, base),
      ];
      int average(List<int> values) => ((values[0] + values[1]) / 2).round();
      final lovePair = scorePair(FortuneArea.love, FortuneScoreCalculator.standardBase(FortuneArea.love));
      final workPair = scorePair(FortuneArea.work, FortuneScoreCalculator.standardBase(FortuneArea.work));
      final moneyPair = scorePair(FortuneArea.money, FortuneScoreCalculator.standardBase(FortuneArea.money));
      final mentalPair = scorePair(FortuneArea.mental, FortuneScoreCalculator.standardBase(FortuneArea.mental));
      final love = average(lovePair);
      final work = average(workPair);
      final money = average(moneyPair);
      final mental = average(mentalPair);
      return {
        'month': '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}',
        'transit_samples': [_transitSnapshot(first), _transitSnapshot(middle)],
        'scores': {
          'overall': ((
                    FortuneScoreCalculator.overallWithReturnBonus([lovePair[0], workPair[0], moneyPair[0], mentalPair[0]], first) +
                    FortuneScoreCalculator.overallWithReturnBonus([lovePair[1], workPair[1], moneyPair[1], mentalPair[1]], middle)) /
                  2)
              .round(),
          'love': love,
          'work': work,
          'money': money,
          'mental': mental,
        },
      };
    });
  }

  Map<String, Object?>? _annualLifeEventBoostSnapshot() {
    if (mode != LongRangeMode.year) return null;
    final contexts = <HoroscopeReadingContext>[
      for (var monthIndex = 1; monthIndex <= 12; monthIndex++)
        const AstrologyEngine().buildPreviewContext(profile: profile, date: DateTime(year, monthIndex, 1, 12)),
      for (var monthIndex = 1; monthIndex <= 12; monthIndex++)
        const AstrologyEngine().buildPreviewContext(profile: profile, date: DateTime(year, monthIndex, 15, 12)),
    ];
    final boost = FortuneScoreCalculator.annualLifeEventBoost(contexts);
    if (boost == null) return null;
    return {
      'value': double.parse(boost.value.toStringAsFixed(2)),
      'detail': boost.detail,
      'formula': boost.formula,
      'area_effects': {
        'love': double.parse(boost.effectFor(FortuneArea.love).toStringAsFixed(2)),
        'work': double.parse(boost.effectFor(FortuneArea.work).toStringAsFixed(2)),
        'money': double.parse(boost.effectFor(FortuneArea.money).toStringAsFixed(2)),
        'mental': double.parse(boost.effectFor(FortuneArea.mental).toStringAsFixed(2)),
      },
      'rule': '年運のみ。木星・土星・外惑星などのリターン、出生図の全天体・ASC・MCへのタイトな調和アスペクト、良いレア配置から最強1件だけを選び、関係する分野へ配分します。総合運は4分野への配分の平均で、各分野は最大+3.5点です。',
    };
  }

  /// プロフィール画面からの出力には画面カードを渡さないため、ここで同じ集計値を
  /// 作る。日別・月別の明細だけでなく、先頭の期間スコアも空にしない。
  List<Map<String, Object?>> _periodScores() {
    // 画面カードをそのままJSON化する経路でも、年専用補正の分野別根拠を
    // 落とさない。外部AIが「なぜ仕事だけ高いか」を読み取れるようにする。
    AnnualLifeEventBoost? annualLifeEventBoostForOutput;
    if (mode == LongRangeMode.year) {
      final annualContextsForOutput = <HoroscopeReadingContext>[
        for (var monthIndex = 1; monthIndex <= 12; monthIndex++)
          const AstrologyEngine().buildPreviewContext(
            profile: profile,
            date: DateTime(year, monthIndex, 1, 12),
          ),
        for (var monthIndex = 1; monthIndex <= 12; monthIndex++)
          const AstrologyEngine().buildPreviewContext(
            profile: profile,
            date: DateTime(year, monthIndex, 15, 12),
          ),
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
      final effect = area == FortuneArea.overall ? boost.value : boost.effectFor(area);
      if (effect <= 0) return null;
      return '年専用の人生イベント補正: +${effect.toStringAsFixed(2)}点（${boost.detail}） / ${boost.formula}';
    }

    List<String> evidenceWithAnnualLifeEvent(List<String> evidence, String title) {
      final annualEvidence = annualLifeEventEvidenceForTitle(title);
      if (annualEvidence == null || evidence.any((item) => item.startsWith('年専用の人生イベント補正:'))) {
        return evidence;
      }
      return [...evidence, annualEvidence];
    }

    if (cards.isNotEmpty) {
      return cards.map((item) => {
            'area': item.title,
            'score': item.score,
            'sign': item.sign,
            'secondary_sign': item.secondarySign,
            'transit_house': item.transitHouse,
            'natal_house': item.natalHouse,
            'aspect_basis': '代表日（${_dateTimeJst(contextData.transit.date)}）: ${item.aspectBasis.replaceFirst('現在の', '')}',
            'evidence': evidenceWithAnnualLifeEvent(item.evidence, item.title),
            'score_aggregation': _scoreAggregation,
            'representative_transit_scope': 'sign・transit_house・natal_house・aspect_basisは期間開始日12:00 JSTの代表配置',
            'basis_note': 'scoreは${_scoreAggregation}です。日別の配置と点数はdaily_scores、年間の月別データはannual_monthsを参照してください。',
            'representative_transit_date_jst': _dateTimeJst(contextData.transit.date),
          }).toList();
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
    }) => [
      _periodScoreEntry(area: '総合運', score: overall, evidence: [
        '総合運: 4分野平均を${_scoreAggregation}で集計',
        if (overallEvidence != null) overallEvidence,
      ]),
      _periodScoreEntry(area: '恋愛運', score: love, evidence: areaEvidence['恋愛運'] ?? const []),
      _periodScoreEntry(area: '仕事運', score: work, evidence: areaEvidence['仕事運'] ?? const []),
      _periodScoreEntry(area: '金運', score: money, evidence: areaEvidence['金運'] ?? const []),
      _periodScoreEntry(area: '健康・メンタル運', score: mental, evidence: areaEvidence['健康・メンタル運'] ?? const []),
    ];

    if (mode == LongRangeMode.week) {
      final contexts = List.generate(7, (index) {
        final date = weekStart.add(Duration(days: index));
        return const AstrologyEngine().buildPreviewContext(
          profile: profile,
          date: DateTime(date.year, date.month, date.day, 12),
        );
      });
      List<int> scores(FortuneArea area) => contexts
          .map((context) => FortuneScoreCalculator.dailyArea(
                context,
                area,
                FortuneScoreCalculator.standardBase(area),
              ))
          .toList();
      final loveScores = scores(FortuneArea.love);
      final workScores = scores(FortuneArea.work);
      final moneyScores = scores(FortuneArea.money);
      final mentalScores = scores(FortuneArea.mental);
      final overallSamples = List.generate(contexts.length, (index) =>
          FortuneScoreCalculator.overallWithReturnBonus([
            loveScores[index], workScores[index], moneyScores[index], mentalScores[index],
          ], contexts[index]));
      final peak = FortuneScoreCalculator.periodReturnPeakBonus(contexts);
      return entries(
        overall: (average(overallSamples) + (peak?.value ?? 0)).round().clamp(50, 99).toInt(),
        love: average(loveScores),
        work: average(workScores),
        money: average(moneyScores),
        mental: average(mentalScores),
        overallEvidence: peak == null ? null : '期間ピーク補正: ${peak.planet.label}+${peak.value.toStringAsFixed(1)}点（${peak.detail}）',
      );
    }

    if (mode == LongRangeMode.month) {
      final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
      final dates = <int>{1, 8, 15, 22, daysInMonth}
          .map((day) => DateTime(month.year, month.month, day, 12))
          .toList()
        ..sort();
      final contexts = dates.map((date) => const AstrologyEngine().buildPreviewContext(
            profile: profile,
            date: date,
          )).toList();
      List<int> scores(FortuneArea area) => List.generate(contexts.length, (index) =>
          FortuneScoreCalculator.periodArea(
            area,
            contexts[index],
            dates[index],
            FortuneScoreCalculator.standardBase(area),
          ));
      final loveScores = scores(FortuneArea.love);
      final workScores = scores(FortuneArea.work);
      final moneyScores = scores(FortuneArea.money);
      final mentalScores = scores(FortuneArea.mental);
      final overallSamples = List.generate(contexts.length, (index) =>
          FortuneScoreCalculator.overallWithReturnBonus([
            loveScores[index], workScores[index], moneyScores[index], mentalScores[index],
          ], contexts[index]));
      final peak = FortuneScoreCalculator.periodReturnPeakBonus(contexts);
      return entries(
        overall: (average(overallSamples) + (peak?.value ?? 0)).round().clamp(50, 99).toInt(),
        love: average(loveScores),
        work: average(workScores),
        money: average(moneyScores),
        mental: average(mentalScores),
        overallEvidence: peak == null ? null : '期間ピーク補正: ${peak.planet.label}+${peak.value.toStringAsFixed(1)}点（${peak.detail}）',
      );
    }

    final contexts = <HoroscopeReadingContext>[
      for (var monthIndex = 1; monthIndex <= 12; monthIndex++)
        const AstrologyEngine().buildPreviewContext(profile: profile, date: DateTime(year, monthIndex, 1, 12)),
      for (var monthIndex = 1; monthIndex <= 12; monthIndex++)
        const AstrologyEngine().buildPreviewContext(profile: profile, date: DateTime(year, monthIndex, 15, 12)),
    ];
    int annualArea(FortuneArea area) => FortuneScoreCalculator.overallFromAreas(
          List.generate(12, (index) {
            final first = contexts[index];
            final middle = contexts[index + 12];
            final firstScore = FortuneScoreCalculator.periodArea(area, first, first.transit.date, FortuneScoreCalculator.standardBase(area));
            final middleScore = FortuneScoreCalculator.periodArea(area, middle, middle.transit.date, FortuneScoreCalculator.standardBase(area));
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
      return (score + (annualBoost?.effectFor(area) ?? 0)).round().clamp(50, 99).toInt();
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
      overallEvidence: annualBoost == null ? null : '年専用の人生イベント補正: +${annualBoost.value.toStringAsFixed(1)}点（${annualBoost.detail}）',
      areaEvidence: annualAreaEvidence,
    );
  }

  Map<String, Object?> _periodScoreEntry({
    required String area,
    required int score,
    List<String> evidence = const [],
  }) => {
        'area': area,
        'score': score,
        'evidence': evidence,
        'score_aggregation': _scoreAggregation,
        'basis_note': 'scoreは${_scoreAggregation}です。日別の配置と点数はdaily_scores、年間の月別データはannual_monthsを参照してください。',
        'representative_transit_date_jst': _dateTimeJst(contextData.transit.date),
      };

  Map<String, Object?> _data() => {
        'schema': 'pancyo_astrology_external_consult_v2',
        'generated_at': DateTime.now().toIso8601String(),
        'period': {
          'type': mode.name,
          'label': periodLabel,
          'timezone': 'Asia/Tokyo',
          'calculation_time': '12:00 JST',
          'notice': '月間は日別配置、年間は各月1日・15日の配置を参照してください。period_start_transitは期間開始日の値です。',
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
        'natal_placements': contextData.natal.placements.map((item) => {
              'planet': item.planet.label,
              'sign': item.sign.label,
              'degree': item.degree,
              'house': item.house,
            }).toList(),
        'natal_retrograde_planets': contextData.natal.retrogradePlanets.map((item) => item.label).toList(),
        // 旧v1のtransit_placementsは月初日の値を日付なしで出していた。
        // v2では期間開始日を明示し、月間は日別、年間は月別の配置を併記する。
        'period_start_transit': _transitSnapshot(contextData),
        'period_scores': _periodScores(),
        if (mode == LongRangeMode.year) 'annual_life_event_boost': _annualLifeEventBoostSnapshot(),
        if (mode == LongRangeMode.week)
          'daily_scores': List.generate(
            7,
            (index) {
              final day = weekStart.add(Duration(days: index));
              return _dailySnapshot(DateTime(day.year, day.month, day.day, 12));
            },
          ),
        if (mode == LongRangeMode.month)
          'daily_scores': List.generate(
            DateTime(month.year, month.month + 1, 0).day,
            (index) => _dailySnapshot(DateTime(month.year, month.month, index + 1, 12)),
          ),
        if (mode == LongRangeMode.year) 'annual_months': _annualMonths(),
      };

  Future<void> _export(BuildContext context) async {
    var progressOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(children: [SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 14), Expanded(child: Text('鑑定データを出力中…'))]),
        ),
      ),
    );
    try {
      // ダイアログが確実に見えてから、重いJSON組み立てを始める。
      // endOfFrameだけでは、端末によってはダイアログの初回描画前に
      // 同期的なJSON生成へ入ってしまうことがある。
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 120));
      final directory = await getTemporaryDirectory();
      final prefix = mode == LongRangeMode.year ? 'year' : 'month';
      final safeLabel = periodLabel.replaceAll(RegExp(r'[^0-9A-Za-z_-]'), '_');
      final file = File('${directory.path}${Platform.pathSeparator}pancyo_astrology_${prefix}_$safeLabel.json');
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(_data()), flush: true);
      if (context.mounted && progressOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        progressOpen = false;
      }
      await Share.shareXFiles([XFile(file.path)], subject: 'ぱんちょ式星占い AIチャット相談用データ');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('JSONを作成しました。共有先または保存先を選んでください。')));
      }
    } catch (_) {
      if (context.mounted && progressOpen) Navigator.of(context, rootNavigator: true).pop();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('JSON出力に失敗しました。もう一度お試しください。')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final description = switch (mode) {
      LongRangeMode.week => 'この週の7日分の星配置と5運勢点数を保存できます。AIチャットへ添えて「${weekStart.month}/${weekStart.day + 2}を詳しく占って」のように日付を指定して相談できます。',
      LongRangeMode.month => 'この月の毎日の星配置と5運勢点数を保存できます。AIチャットへ添えて「${month.month}/${month.day + 14}を詳しく占って」のように日付を指定して相談できます。',
      LongRangeMode.year => 'この年の各月1日・15日の星配置と月別の5運勢点数を保存できます。AIチャットへ添えて、時期ごとの流れを詳しく相談できます。',
    };
    return GlassPanel(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.save_alt_outlined, color: Color(0xFF57D6D1), size: 20),
              const SizedBox(width: 10),
              const Expanded(child: Text('AIチャット相談用データ', style: TextStyle(fontWeight: FontWeight.w900))),
              OutlinedButton(onPressed: () => _export(context), child: const Text('JSONを保存')),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.70), fontSize: 12, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class LongRangeFortuneList extends StatelessWidget {
  const LongRangeFortuneList({
    super.key,
    required this.cards,
    required this.detailed,
    required this.profile,
    required this.details,
    required this.yearMode,
    required this.month,
    required this.year,
    this.weekStart,
    required this.aiRequested,
    required this.requestRevision,
  });

  final List<LongFortuneData> cards;
  final bool detailed;
  final AstroProfile profile;
  final UserProfileDetails details;
  final bool yearMode;
  final DateTime month;
  final int year;
  final DateTime? weekStart;
  final bool aiRequested;
  final int requestRevision;

  @override
  Widget build(BuildContext context) => Column(
    children: cards.where((card) => card.title != '総合運').map(
      (card) => LongFortuneCard(
        data: card,
        detailed: detailed,
        details: details,
      ),
    ).toList(),
  );
}
class LongFortuneCard extends StatelessWidget {
  const LongFortuneCard({
    super.key,
    required this.data,
    required this.detailed,
    required this.details,
    this.aiText,
    this.aiLoading = false,
    this.aiFailed = false,
    this.shareLabel,
    this.onShare,
  });

  final LongFortuneData data;
  final bool detailed;
  final UserProfileDetails details;
  final String? aiText;
  final bool aiLoading;
  final bool aiFailed;
  final String? shareLabel;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (compact)
                Row(
                  children: [
                    FortuneNumber(score: data.score, compact: true),
                    const SizedBox(width: 14),
                    Icon(data.icon, color: const Color(0xFFF6D77A), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        data.title,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                      ),
                    ),
                    if (onShare != null)
                      IconButton(
                        tooltip: 'この結果を画像で共有',
                        onPressed: onShare,
                        icon: const Icon(Icons.ios_share_outlined, size: 20),
                      ),
                  ],
                )
              else
                Row(
                  children: [
                    Icon(data.icon, color: const Color(0xFFF6D77A), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        data.title,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                      ),
                    ),
                    if (onShare != null)
                      IconButton(
                        tooltip: 'この結果を画像で共有',
                        onPressed: onShare,
                        icon: const Icon(Icons.ios_share_outlined, size: 20),
                      ),
                  ],
                ),
              if (shareLabel != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'ぱんちょ式星占い / $shareLabel',
                    style: const TextStyle(fontSize: 10, color: Color(0xFF57D6D1), fontWeight: FontWeight.w800),
                  ),
                ),
              const SizedBox(height: 4),
              if (detailed)
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _AstroBasisChip(
                      prefix: '現在',
                      text: data.sign,
                      color: const Color(0xFF57D6D1),
                    ),
                    if (data.secondarySign != null)
                      _AstroBasisChip(
                        prefix: '現在',
                        text: data.secondarySign!,
                        color: const Color(0xFF57D6D1),
                      ),
                    _AstroBasisChip(
                      prefix: '通過',
                      text: data.transitHouse,
                      color: const Color(0xFFB58CFF),
                    ),
                    _AstroBasisChip(
                      prefix: '出生図',
                      text: data.natalHouse,
                      color: const Color(0xFFF6D77A),
                    ),
                  ],
                ),
              const SizedBox(height: 10),
              Text(
                detailed ? data.detailedText : data.text,
                maxLines: null,
                overflow: TextOverflow.visible,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.76),
                  height: 1.55,
                ),
              ),
              if (detailed) ...[
                const SizedBox(height: 9),
                Text(
                  '星の見方: ${data.aspectBasis}',
                  style: TextStyle(
                    color: const Color(0xFF57D6D1).withValues(alpha: 0.86),
                    fontSize: 12,
                    height: 1.45,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (detailed) ...[
                const SizedBox(height: 12),
                const Text('この点数の理由', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                ...data.evidence.map((line) => Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text('・$line', style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 12, height: 1.4)),
                )),
                const SizedBox(height: 8),
                LongFortuneEvidencePanel(
                  current: data.evidence.isNotEmpty ? data.evidence[0] : data.sign,
                  transitHouse: data.transitHouse,
                  natal: data.evidence.length > 1 ? data.evidence[1] : data.natalHouse,
                  correction: [
                    data.evidence.length > 2 ? data.evidence[2] : data.chartBasis,
                    'アスペクト: ${data.aspectBasis}',
                  ].join(' / '),
                ),
              ],
            ],
          );

          if (compact) return content;

          return Row(
            crossAxisAlignment: detailed ? CrossAxisAlignment.start : CrossAxisAlignment.center,
            children: [
              Padding(
                padding: EdgeInsets.only(top: detailed ? 24 : 0),
                child: SizedBox(
                  width: 90,
                  child: FortuneNumber(score: data.score),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(child: content),
            ],
          );
        },
      ),
    );
  }
}

class ProfileFortuneHint extends StatelessWidget {
  const ProfileFortuneHint({
    super.key,
    required this.details,
    required this.title,
  });

  final UserProfileDetails details;
  final String title;

  @override
  Widget build(BuildContext context) {
    final concern = details.concerns.trim();
    final personality = details.personality.trim();
    final style = details.readingStyle.trim();
    final text = _profileText(concern, personality, style);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFF57D6D1).withValues(alpha: 0.075),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF57D6D1).withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.person_pin_circle_outlined, size: 16, color: Color(0xFF57D6D1)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.68),
                fontSize: 12,
                height: 1.45,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _profileText(String concern, String personality, String style) {
    final base = concern.isNotEmpty
        ? '悩み「$concern」を反映。$titleは時期の波に合わせて一手ずつ動く方が合います。'
        : '$titleはプロフィール内容を反映し、無理なく続く動き方を優先します。';
    final tone = personality.isNotEmpty ? '性格「$personality」は強みとして読みます。' : '';
    final reading = style.isNotEmpty ? '重視点「$style」も加味します。' : '';
    return [base, tone, reading].where((part) => part.isNotEmpty).join(' ');
  }
}

class LongFortuneEvidencePanel extends StatefulWidget {
  const LongFortuneEvidencePanel({
    super.key,
    required this.current,
    required this.transitHouse,
    required this.natal,
    required this.correction,
  });

  final String current;
  final String transitHouse;
  final String natal;
  final String correction;

  @override
  State<LongFortuneEvidencePanel> createState() => _LongFortuneEvidencePanelState();
}

class _LongFortuneEvidencePanelState extends State<LongFortuneEvidencePanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final current = widget.current;
    final transitHouse = widget.transitHouse;
    final natal = widget.natal;
    final correction = widget.correction;

    return Column(
      children: [
        _EvidenceGroup(
          title: '現在の流れ',
          icon: Icons.auto_awesome_motion,
          summary: _compactSummary(
            _impactForCurrent(current),
            _impactForTransitHouse(transitHouse),
          ),
          expanded: _expanded,
          onToggle: () => setState(() => _expanded = !_expanded),
          rows: [
            _EvidenceLine('星', _impactForCurrent(current), _detailsForCurrent(current)),
            _EvidenceLine('通過', _impactForTransitHouse(transitHouse), _detailsForTransitHouse(transitHouse)),
          ],
        ),
        const SizedBox(height: 10),
        _EvidenceGroup(
          title: '出生図への効き方',
          icon: Icons.account_tree_outlined,
          summary: _compactSummary(
            _impactForNatal(natal),
            _impactForCorrection(correction),
          ),
          expanded: _expanded,
          onToggle: () => setState(() => _expanded = !_expanded),
          rows: [
            _EvidenceLine('出生', _impactForNatal(natal), _detailsForNatal(natal)),
            _EvidenceLine('補正', _impactForCorrection(correction), _detailsForCorrection(correction)),
          ],
        ),
      ],
    );
  }

  String _clean(String value) {
    return value
        .replaceFirst('現在: ', '')
        .replaceFirst('通過: ', '')
        .replaceFirst('出生図: ', '')
        .replaceFirst('出生図の', '')
        .replaceFirst('補正: ', '');
  }

  String _compactSummary(String first, String second) {
    return '${_afterArrow(first)} / ${_afterArrow(second)}';
  }

  String _afterArrow(String value) {
    final parts = value.split('->');
    return parts.length > 1 ? parts.last.trim() : value;
  }

  List<String> _segments(String value) {
    return _clean(value)
        .split(RegExp(r'[/、。]'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
  }

  String _impactForCurrent(String value) {
    final cleaned = _clean(value);
    if (cleaned.contains('太陽')) return '$cleaned -> 自分を出す流れが強まる';
    if (cleaned.contains('金星') && cleaned.contains('木星')) {
      return '$cleaned -> 楽しみと拡大が金運を動かす';
    }
    if (cleaned.contains('金星')) return '$cleaned -> 関係性と好みが動きやすい';
    if (cleaned.contains('水星')) return '$cleaned -> 判断と連絡が整いやすい';
    if (cleaned.contains('土星')) return '$cleaned -> 責任と課題が表に出る';
    if (cleaned.contains('月')) return '$cleaned -> 気分の波が運勢に出やすい';
    if (cleaned.contains('木星')) return '$cleaned -> 広げる力が働く';
    return '$cleaned -> 今期の流れに影響';
  }

  String _impactForNatal(String value) {
    final cleaned = _clean(value);
    final natalImpact = _shortHouseImpact(cleaned, natal: true);
    if (natalImpact != null) return natalImpact;
    if (cleaned.contains('第1ハウス')) return '$cleaned -> 自分らしさと選択に出る';
    if (cleaned.contains('第2ハウス')) return '$cleaned -> 収入と価値観に出る';
    if (cleaned.contains('第4ハウス')) return '$cleaned -> 心の安定と居場所に出る';
    if (cleaned.contains('第7ハウス')) return '$cleaned -> 対人関係と約束に出る';
    if (cleaned.contains('第8ハウス')) return '$cleaned -> 共有財産や援助に出る';
    if (cleaned.contains('第10ハウス')) return '$cleaned -> 仕事の評価と役割に出る';
    if (cleaned.contains('第12ハウス')) return '$cleaned -> 休息と無意識に出る';
    return '$cleaned -> 出生図のテーマに出る';
  }

  String _impactForTransitHouse(String value) {
    final cleaned = _clean(value);
    final transitImpact = _shortHouseImpact(cleaned, natal: false);
    if (transitImpact != null) return transitImpact;
    if (cleaned.contains('第1ハウス')) return '$cleaned -> 自分の動きに出る';
    if (cleaned.contains('第2ハウス')) return '$cleaned -> 収入と価値観に出る';
    if (cleaned.contains('第4ハウス')) return '$cleaned -> 家と安心感に出る';
    if (cleaned.contains('第7ハウス')) return '$cleaned -> 対人関係に出る';
    if (cleaned.contains('第8ハウス')) return '$cleaned -> 共有や深い結びつきに出る';
    if (cleaned.contains('第10ハウス')) return '$cleaned -> 仕事と評価に出る';
    if (cleaned.contains('第11ハウス')) return '$cleaned -> 仲間と未来計画に出る';
    if (cleaned.contains('第12ハウス')) return '$cleaned -> 休息と内面に出る';
    return '$cleaned -> 現在の星が触れる場面に出る';
  }

  String? _shortHouseImpact(String cleaned, {required bool natal}) {
    final houses = _housesIn(cleaned);
    if (houses.isEmpty) return null;
    final topic = _houseTopics(houses);
    return natal ? '$cleaned -> $topicに出る' : '$cleaned -> $topicが動く';
  }

  String _impactForCorrection(String value) {
    final cleaned = _clean(value);
    if (cleaned.contains('トライン')) return '$cleaned -> 流れを後押しする';
    if (cleaned.contains('セクスタイル')) return '$cleaned -> 小さな機会を作る';
    if (cleaned.contains('スクエア')) return '$cleaned -> 課題として強く出る';
    if (cleaned.contains('コンジャンクション')) return '$cleaned -> 影響が直接出やすい';
    if (cleaned.contains('月ボイド')) return '$cleaned -> 決断を弱め、調整を強める';
    if (cleaned.contains('金星リターン')) return '$cleaned -> 好みと愛情の再確認';
    if (cleaned.contains('水星リターン')) return '$cleaned -> 考え方と伝え方を更新';
    if (cleaned.contains('木星リターン')) return '$cleaned -> 拡大運を強める';
    if (cleaned.contains('土星リターン')) return '$cleaned -> 責任と節目を強める';
    if (cleaned.contains('ステリウム')) return '$cleaned -> 特定テーマを強調';
    if (cleaned.contains('月の波')) return '$cleaned -> 心身の波を反映';
    return '$cleaned -> 運勢の強弱を調整';
  }

  List<String> _detailsForCurrent(String value) {
    final cleaned = _clean(value);
    final details = <String>[];
    for (final segment in _segments(value)) {
      if (segment.contains('太陽')) {
        details.add('$segment: 自分らしさ、目的、表に出る力');
      } else if (segment.contains('月')) {
        details.add('$segment: 気分、安心感、日々のコンディション');
      } else if (segment.contains('水星')) {
        details.add('$segment: 判断、連絡、言葉、学び');
      } else if (segment.contains('金星')) {
        details.add('$segment: 好み、愛情、お金の使い方');
      } else if (segment.contains('木星')) {
        details.add('$segment: 拡大、チャンス、増える流れ');
      } else if (segment.contains('土星')) {
        details.add('$segment: 責任、制限、続ける課題');
      }
    }
    if (details.isNotEmpty) return details;
    if (cleaned.contains('太陽')) details.add('太陽: 自分らしさ、目的、表に出る力');
    if (cleaned.contains('月')) details.add('月: 気分、安心感、日々のコンディション');
    if (cleaned.contains('水星')) details.add('水星: 判断、連絡、言葉、学び');
    if (cleaned.contains('金星')) details.add('金星: 好み、愛情、お金の使い方');
    if (cleaned.contains('木星')) details.add('木星: 拡大、チャンス、増える流れ');
    if (cleaned.contains('土星')) details.add('土星: 責任、制限、続ける課題');
    return details.isEmpty ? ['現在の星: 今期の空気を作る'] : details;
  }

  List<String> _detailsForTransitHouse(String value) {
    final cleaned = _clean(value);
    final details = <String>[];
    for (final segment in _segments(value)) {
      final impact = _planetHouseImpact(segment, natal: false);
      if (impact != null) {
        details.add(impact);
      }
    }
    return details.isEmpty ? ['通過: 星がどの生活領域を動かすかで判断'] : details;
  }

  List<String> _detailsForNatal(String value) {
    final cleaned = _clean(value);
    final details = <String>[];
    for (final segment in _segments(value)) {
      final impact = _planetHouseImpact(segment, natal: true);
      if (impact != null) {
        details.add(impact);
      } else if (segment.contains('第')) {
        details.add(_natalHouseAnchor(segment));
      }
    }
    if (cleaned.contains('太陽')) details.add('出生図の太陽: 人生の方向性');
    if (cleaned.contains('月')) details.add('出生図の月: 心の癖と安心感');
    if (cleaned.contains('金星')) details.add('出生図の金星: 好きなものと愛情表現');
    if (cleaned.contains('ASC')) details.add('ASC: 第一印象と自分の出し方');
    if (cleaned.contains('MC')) details.add('MC: 社会的な役割と評価');
    return details.isEmpty ? ['出生図: もともと強く出る人生テーマ'] : details;
  }

  String? _planetHouseImpact(String value, {required bool natal}) {
    final cleaned = _clean(value);
    final planet = _planetIn(cleaned);
    final houses = _housesIn(cleaned);
    if (planet == null || houses.isEmpty) return null;
    final timing = natal ? '出生図で' : '通過中は';
    final effect = _planetHouseEffect(planet, houses);
    return '$cleaned: $timing$effect';
  }

  String? _planetIn(String value) {
    for (final planet in ['太陽', '月', '水星', '金星', '火星', '木星', '土星', '天王星', '海王星', '冥王星', 'ASC', 'MC']) {
      if (value.contains(planet)) return planet;
    }
    return null;
  }

  List<String> _housesIn(String value) {
    final houses = RegExp(r'第\d+')
        .allMatches(value)
        .map((match) => match.group(0)!)
        .toSet()
        .toList();
    return houses;
  }

  String _planetHouseEffect(String planet, List<String> houses) {
    final topic = _houseTopics(houses);
    switch (planet) {
      case '太陽':
        return '$topicで自分を出す力が強まる';
      case '月':
        return '$topicに気分や安心感が左右されやすい';
      case '水星':
        return '$topicで判断、連絡、調整が動きやすい';
      case '金星':
        return '$topicで愛情、お金、楽しみが動きやすい';
      case '木星':
        return '$topicで拡大、支援、チャンスが出やすい';
      case '土星':
        return '$topicで責任、制限、積み上げが出やすい';
      case '天王星':
        return '$topicで変化、独立、急な切り替えが出やすい';
      case '海王星':
        return '$topicで直感、曖昧さ、理想が出やすい';
      case '冥王星':
        return '$topicで深い変容、執着、再生が出やすい';
      case 'ASC':
        return '$topicで第一印象、自分の出し方、始め方が出やすい';
      case 'MC':
        return '$topicで肩書き、評価、社会的な役割が出やすい';
    }
    return '$topicに影響が出る';
  }

  String _houseTopics(List<String> houses) {
    final topics = houses.map(_houseTopic).toSet().toList();
    return topics.join('、');
  }

  String _houseTopic(String house) {
    if (house.contains('10')) return '仕事、評価、肩書き';
    if (house.contains('11')) return '仲間、未来計画、広がり';
    if (house.contains('12')) return '休息、内面、見えない疲れ';
    if (house.contains('1')) return '自分の動きや見せ方';
    if (house.contains('2')) return '収入、所有、価値観';
    if (house.contains('4')) return '家、安心感、心の土台';
    if (house.contains('7')) return '対人関係、恋愛、約束';
    if (house.contains('8')) return '共有、深い関係、受け取るもの';
    return 'そのハウスのテーマ';
  }

  String _natalHouseAnchor(String value) {
    final cleaned = _clean(value);
    final houses = _housesIn(cleaned);
    if (houses.isEmpty) return '$cleaned: 出生図で重く見るテーマ';
    return '$cleaned: ${_houseTopics(houses)}が生まれ持った運の出どころ';
  }

  List<String> _detailsForCorrection(String value) {
    final cleaned = _clean(value);
    final details = <String>[
      ..._aspectDetailLines(cleaned),
    ];
    if (cleaned.contains('金星リターン')) details.add('金星リターン: 好み、愛情、お金の使い方を再確認');
    if (cleaned.contains('水星リターン')) details.add('水星リターン: 考え方、言葉、判断を更新');
    if (cleaned.contains('木星リターン')) details.add('木星リターン: 拡大運、チャンス、成長を強める');
    if (cleaned.contains('土星リターン')) details.add('土星リターン: 責任、節目、現実化を強める');
    if (cleaned.contains('月ボイド')) details.add('月ボイド: 決断より確認、休息、調整向き');
    if (cleaned.contains('ステリウム')) details.add('ステリウム: 星が集中するテーマを強調');
    if (cleaned.contains('月の波')) details.add('月の波: 心身のリズムを運勢に反映');
    return details.isEmpty ? ['補正: 運勢の強弱を調整'] : details;
  }

  List<String> _aspectDetailLines(String value) {
    final details = <String>[];
    final aspectPattern = RegExp(
      r'(現在の)?(太陽|月|水星|金星|火星|木星|土星|天王星|海王星|冥王星|ASC|MC)\s*(コンジャンクション|セクスタイル|スクエア|トライン|オポジション)\s*(出生図の)?(太陽|月|水星|金星|火星|木星|土星|天王星|海王星|冥王星|ASC|MC)',
    );

    for (final match in aspectPattern.allMatches(value)) {
      final transitPlanet = match.group(2)!;
      final aspect = match.group(3)!;
      final natalPlanet = match.group(5)!;
      details.add(
        '現在の$transitPlanet $aspect 出生図の$natalPlanet: ${_aspectEffect(aspect)}',
      );
    }

    if (details.isEmpty) {
      for (final segment in _segments(value)) {
        final aspect = _aspectIn(segment);
        if (aspect == null) continue;
        final parts = segment.split(aspect);
        if (parts.length >= 2 && parts.first.trim().isNotEmpty && parts.last.trim().isNotEmpty) {
          details.add(
            '${parts.first.trim()} $aspect ${parts.last.trim()}: ${_aspectEffect(aspect)}',
          );
        } else {
          details.add('$segment: ${_aspectEffect(aspect)}');
        }
      }
    }
    return details.toSet().toList();
  }

  String? _aspectIn(String value) {
    for (final aspect in ['コンジャンクション', 'セクスタイル', 'スクエア', 'トライン', 'オポジション']) {
      if (value.contains(aspect)) return aspect;
    }
    return null;
  }

  String _aspectEffect(String aspect) {
    switch (aspect) {
      case 'トライン':
        return '無理なく伸びる追い風';
      case 'セクスタイル':
        return '意識して使うと開く機会';
      case 'スクエア':
        return '葛藤や負荷が成長点になる';
      case 'コンジャンクション':
        return '星の意味が重なり強く出る';
      case 'オポジション':
        return '相手や外側から刺激が入る';
    }
    return '運勢の強弱を調整';
  }
}

class _EvidenceLine {
  const _EvidenceLine(this.title, this.body, this.details);

  final String title;
  final String body;
  final List<String> details;
}

class _EvidenceGroup extends StatelessWidget {
  const _EvidenceGroup({
    required this.title,
    required this.icon,
    required this.summary,
    required this.expanded,
    required this.onToggle,
    required this.rows,
  });

  final String title;
  final IconData icon;
  final String summary;
  final bool expanded;
  final VoidCallback onToggle;
  final List<_EvidenceLine> rows;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: const Color(0xFFB58CFF).withValues(alpha: 0.075),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFB58CFF).withValues(alpha: 0.32)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 15, color: const Color(0xFFB58CFF)),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFFF6D77A),
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: onToggle,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 28),
                    ),
                    child: Text(expanded ? '閉じる' : '詳しく'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                summary,
                maxLines: expanded ? null : 3,
                overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFEDE7FF),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  height: 1.35,
                ),
              ),
              if (expanded) ...[
                const SizedBox(height: 8),
                ...rows.map((row) => _EvidenceDetailRow(row: row, compact: compact)),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _EvidenceDetailRow extends StatelessWidget {
  const _EvidenceDetailRow({
    required this.row,
    required this.compact,
  });

  final _EvidenceLine row;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFB58CFF).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFFB58CFF).withValues(alpha: 0.22)),
                ),
                child: Text(
                  row.title,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.70),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ...row.details.map(
            (detail) => Padding(
              padding: EdgeInsets.only(left: compact ? 8 : 12, bottom: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    margin: const EdgeInsets.only(top: 6, right: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFB58CFF).withValues(alpha: 0.78),
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      detail,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.64),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LearningReading extends StatefulWidget {
  const LearningReading({
    super.key,
    required this.profile,
    required this.details,
    required this.depth,
    required this.onAskInChat,
  });

  final AstroProfile profile;
  final UserProfileDetails details;
  final ReadingDepth depth;
  final ValueChanged<String> onAskInChat;

  @override
  State<LearningReading> createState() => _LearningReadingState();
}

class _LearningReadingState extends State<LearningReading> {
  bool _showTransit = false;
  LearningView _view = LearningView.stars;
  final _readingContexts = <String, HoroscopeReadingContext>{};

  HoroscopeReadingContext _contextFor(AstroProfile profile, [DateTime? targetDate]) {
    final date = targetDate ?? DateTime.now();
    final normalized = DateTime(date.year, date.month, date.day, date.hour, date.minute);
    final key = '${profile.name}|${profile.birthDate}|${profile.birthTime}|${profile.birthPlace}|${normalized.toIso8601String()}';
    return _readingContexts.putIfAbsent(
      key,
      () => const AstrologyEngine().buildPreviewContext(profile: profile, date: normalized),
    );
  }

  @override
  void didUpdateWidget(covariant LearningReading oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile != widget.profile) _readingContexts.clear();
  }

  @override
  Widget build(BuildContext context) {
    final readingContext = _contextFor(widget.profile);
    final detailed = widget.depth == ReadingDepth.detailed;

    return ReadingPage(
      title: detailed ? '本格・星の解説' : '星の解説',
      subtitle: detailed
          ? '占いで使う星の配置を読む'
          : switch (_view) {
              LearningView.stars => '主要な星をやさしく読む',
              LearningView.profile => '出生図から読む、あなたらしい傾向',
              LearningView.lifeFlow => '出生図から読む、10年ごとの長い流れ',
            },
      children: [
        if (!widget.details.hasExactBirthBase) const BirthPrecisionNotice(),
        if (!detailed)
          LearningViewSwitch(
            view: _view,
            onChanged: (value) => setState(() => _view = value),
          ),
        if (!detailed &&
            _view != LearningView.stars &&
            _hasProfileGuidance(widget.details))
          AstrologyProfileContextNotice(
            details: widget.details,
            view: _view,
          ),
        if (detailed && !readingContext.usesHighPrecisionAstroData)
          AstroDataSourceNotice(contextData: readingContext),
        if (detailed) HoroscopeEngineSummary(contextData: readingContext),
        if (detailed)
          const ReadingCard(
            title: 'ネイタル + トランジット',
            body:
                'この鑑定は、生まれた瞬間のホロスコープと、今日動いている星の配置を重ねて読みます。現在の星が出生図のどのハウスを通るか、出生図の星へどんな角度を作るかを占いに反映します。',
            icon: Icons.auto_awesome_motion,
          ),
        if (detailed)
          AstroPlacementModeSwitch(
            showTransit: _showTransit,
            onChanged: (value) => setState(() => _showTransit = value),
          ),
        if (!detailed && _view == LearningView.stars)
          MoonInfluenceForecastPanel(
            profile: widget.profile,
            contextFor: (date) => _contextFor(widget.profile, date),
          ),
        if (detailed || _view == LearningView.stars)
          AstroPlacementExplanationPanel(
            contextData: readingContext,
            mode: detailed
                ? (_showTransit ? PlacementExplanationMode.transit : PlacementExplanationMode.natal)
                : PlacementExplanationMode.simple,
          ),
        if (!detailed && _view == LearningView.profile)
          NatalProfilePanel(contextData: readingContext, profile: widget.profile),
        if (!detailed && _view == LearningView.lifeFlow)
          LifeDecadePanel(
            contextData: readingContext,
            profile: widget.profile,
            hasExactBirthBase: widget.details.hasExactBirthBase,
            onAskInChat: widget.onAskInChat,
          ),
      ],
    );
  }

  bool _hasProfileGuidance(UserProfileDetails details) {
    return details.personality.trim().isNotEmpty ||
        details.concerns.trim().isNotEmpty ||
        details.readingStyle.trim().isNotEmpty;
  }
}

enum LearningView { stars, profile, lifeFlow }

class LearningViewSwitch extends StatelessWidget {
  const LearningViewSwitch({super.key, required this.view, required this.onChanged});

  final LearningView view;
  final ValueChanged<LearningView> onChanged;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(10),
      child: SegmentedButton<LearningView>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: LearningView.stars, icon: Icon(Icons.public_outlined), label: Text('星の解説')),
          ButtonSegment(value: LearningView.profile, icon: Icon(Icons.person_search_outlined), label: Text('あなた')),
          ButtonSegment(value: LearningView.lifeFlow, icon: Icon(Icons.timeline_outlined), label: Text('人生の流れ')),
        ],
        selected: {view},
        onSelectionChanged: (value) => onChanged(value.first),
      ),
    );
  }
}

class AstrologyProfileContextNotice extends StatelessWidget {
  const AstrologyProfileContextNotice({
    super.key,
    required this.details,
    required this.view,
  });

  final UserProfileDetails details;
  final LearningView view;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF57D6D1).withValues(alpha: 0.075),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF57D6D1).withValues(alpha: 0.20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.person_pin_circle_outlined, size: 18, color: Color(0xFF57D6D1)),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  view == LearningView.profile ? 'プロフィールを重ねた読み方' : 'プロフィールを重ねた人生の見方',
                  style: const TextStyle(color: Color(0xFFF6D77A), fontSize: 13, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  _body(),
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.76), fontSize: 12, height: 1.45, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _body() {
    final raw = '${details.personality} ${details.concerns} ${details.readingStyle}'.toLowerCase();
    final life = view == LearningView.lifeFlow;
    if (raw.contains('youtube') || raw.contains('動画') || raw.contains('発信') || raw.contains('創作') || raw.contains('配信')) {
      return life
          ? '発信や創作を続けたい関心に重ねると、各10年の仕事・学び・仲間のテーマは、企画を育てる時期、外へ見せる時期、続け方を整える時期として使えます。'
          : '発信や創作を続けたい関心に重ねると、下の仕事・お金の資質は、企画の選び方、見せ方、続けられる制作量を決めるヒントとして使えます。';
    }
    if (raw.contains('転職') || raw.contains('仕事') || raw.contains('働') || raw.contains('資格') || raw.contains('勉強')) {
      return life
          ? '仕事や学びの関心に重ねると、各10年のテーマは、力を蓄える時期、役割を広げる時期、働き方を見直す時期として読むと活かしやすくなります。'
          : '仕事や学びの関心に重ねると、下の資質は、得意な進め方、無理なく続く役割、学びを成果へつなげる方法として使えます。';
    }
    if (raw.contains('恋愛') || raw.contains('出会') || raw.contains('復縁') || raw.contains('結婚') || raw.contains('人間関係')) {
      return life
          ? '人との関係を大切にしたい関心に重ねると、各10年のテーマは、出会いを広げる時期、安心できる関係を選ぶ時期、自分の居場所を整える時期として読めます。'
          : '人との関係を大切にしたい関心に重ねると、下の恋愛・心の項目は、安心できる距離感と、無理をしない関係の選び方として使えます。';
    }
    if (raw.contains('お金') || raw.contains('収入') || raw.contains('金運') || raw.contains('貯金') || raw.contains('投資')) {
      return life
          ? 'お金と生活を整えたい関心に重ねると、各10年のテーマは、収入の土台を作る時期、学びや経験へ配分する時期、守る仕組みを整える時期として使えます。'
          : 'お金と生活を整えたい関心に重ねると、下の仕事・お金の資質は、得意を収入へつなげる方法と、無理のない使い方の目安になります。';
    }
    if (raw.contains('疲れ') || raw.contains('体調') || raw.contains('睡眠') || raw.contains('不安') || raw.contains('ストレス')) {
      return life
          ? '心身の余力を大切にしたい関心に重ねると、各10年のテーマは、広げる時期と休む時期を分け、生活の土台を守りながら進むための目安になります。'
          : '心身の余力を大切にしたい関心に重ねると、下の心のクセ・休み方は、頑張る量と回復の仕方を自分に合う形へ整えるヒントになります。';
    }
    return life
        ? '入力した性格や大切にしたいことに重ねると、各10年のテーマは、今の自分にとって何を育て、何を見直す時期かを選ぶ目安になります。'
        : '入力した性格や大切にしたいことに重ねると、下の出生図プロフィールは、得意な使い方と無理をしやすい場面を見分けるヒントになります。';
  }
}

class NatalProfilePanel extends StatelessWidget {
  const NatalProfilePanel({
    super.key,
    required this.contextData,
    required this.profile,
  });

  final HoroscopeReadingContext contextData;
  final AstroProfile profile;

  @override
  Widget build(BuildContext context) {
    final sun = contextData.natal.placementOf(AstroPlanet.sun);
    final moon = contextData.natal.placementOf(AstroPlanet.moon);
    final ascendant = contextData.natal.placementOf(AstroPlanet.ascendant);
    final mercury = contextData.natal.placementOf(AstroPlanet.mercury);
    final venus = contextData.natal.placementOf(AstroPlanet.venus);
    final mars = contextData.natal.placementOf(AstroPlanet.mars);
    final jupiter = contextData.natal.placementOf(AstroPlanet.jupiter);
    final midheaven = contextData.natal.placementOf(AstroPlanet.midheaven);
    final items = <_NatalProfileItem>[
      _NatalProfileItem(
        icon: Icons.auto_awesome_outlined,
        title: '人生の軸・第一印象',
        positions: [_position(sun), _position(ascendant)],
        body: '${_signStyle(sun?.sign)}自分らしさを大切にし、${_signStyle(ascendant?.sign)}第一歩を出すタイプです。自分の方針を言葉にしてから動くと、周囲にも伝わりやすくなります。',
      ),
      _NatalProfileItem(
        icon: Icons.dark_mode_outlined,
        title: '心のクセ・休み方',
        positions: [_position(moon)],
        body: '${_signStyle(moon?.sign)}安心感を求めやすい傾向。気分が揺れる時ほど、予定を増やすより、落ち着ける場所・人・習慣を一つ戻すと本来の調子が出やすくなります。',
      ),
      _NatalProfileItem(
        icon: Icons.favorite_border,
        title: '恋愛・人との距離',
        positions: [_position(venus), _position(mars)],
        body: '好意は${_signStyle(venus?.sign)}形で表れ、行動は${_signStyle(mars?.sign)}形になりやすい配置です。好きかどうかだけで急がず、会話と行動の両方が続く相手を選ぶほど関係が育ちます。',
      ),
      _NatalProfileItem(
        icon: Icons.work_outline,
        title: '仕事・得意な進め方',
        positions: [_position(mercury), _position(midheaven)],
        body: '${_signStyle(mercury?.sign)}考えを整理し、${_signStyle(midheaven?.sign)}社会で役割を作るほど力が出ます。仕事は「何を完成させるか」と「誰へ届けるか」を決めると、持ち味が成果になりやすいです。',
      ),
      _NatalProfileItem(
        icon: Icons.savings_outlined,
        title: 'お金・伸び方',
        positions: [_position(jupiter)],
        body: '${_signStyle(jupiter?.sign)}学びや経験を広げることで、収入や選択肢を育てやすい配置です。勢いで増やすより、自分の得意を人に役立つ形へ整えるほど、長く回収しやすくなります。',
      ),
      _NatalProfileItem(
        icon: Icons.hub_outlined,
        title: '出生図の目立つテーマ',
        positions: const [],
        body: contextData.natal.stelliums.isNotEmpty
            ? '${contextData.natal.stelliums.map((item) => item.label).join(' / ')}が目立つ出生図です。星が集まるテーマを一点集中で磨くほど、人生の軸になります。'
            : FortuneScoreCalculator.hasNatalKite(contextData)
                ? 'グランドトラインを土台にしたカイトがあり、得意なことを外へ向けて動かすほど、才能が実用的な成果につながりやすい出生図です。'
                : '一つだけの型に決めつけず、経験しながら自分に合う役割を選び直せる出生図です。大事な時ほど、得意・疲れにくさ・続けられるかの三つで選ぶとぶれにくくなります。',
      ),
    ];

    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SmallSectionLabel(icon: Icons.person_search_outlined, text: 'あなたの出生図プロフィール'),
          const SizedBox(height: 8),
          Text(
            '${profile.name}さんの出生図を、性格だけでなく恋愛・仕事・お金・休み方まで、日常で使える言葉にまとめています。',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.68), fontSize: 12, height: 1.45, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 720;
              final width = wide ? (constraints.maxWidth - 10) / 2 : constraints.maxWidth;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: items.map((item) => SizedBox(width: width, child: _NatalProfileTile(item: item))).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  String _position(PlanetPlacement? placement) {
    if (placement == null) return '';
    return '${placement.planet.label} ${placement.sign.label}・第${placement.house}ハウス';
  }

  String _signStyle(ZodiacSign? sign) {
    return switch (sign) {
      ZodiacSign.aries => '自分から先に動く',
      ZodiacSign.taurus => 'じっくり安定させる',
      ZodiacSign.gemini => '会話と情報を使う',
      ZodiacSign.cancer => '安心できる人や場所を守る',
      ZodiacSign.leo => '自信を持って表現する',
      ZodiacSign.virgo => '整理して役立てる',
      ZodiacSign.libra => '人とのバランスを取る',
      ZodiacSign.scorpio => '深く集中して本音を扱う',
      ZodiacSign.sagittarius => '学びや挑戦へ広げる',
      ZodiacSign.capricorn => '目標へ着実に積み上げる',
      ZodiacSign.aquarius => '自分らしい新しい方法を選ぶ',
      ZodiacSign.pisces => '想像力と思いやりを使う',
      null => '自分に合う形を選び直す',
    };
  }
}

class _NatalProfileItem {
  const _NatalProfileItem({
    required this.icon,
    required this.title,
    required this.positions,
    required this.body,
  });

  final IconData icon;
  final String title;
  final List<String> positions;
  final String body;
}

class _NatalProfileTile extends StatelessWidget {
  const _NatalProfileTile({required this.item});

  final _NatalProfileItem item;

  @override
  Widget build(BuildContext context) {
    final positions = item.positions.where((value) => value.isNotEmpty).join(' / ');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF57D6D1).withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF57D6D1).withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Icon(item.icon, size: 18, color: const Color(0xFFF6D77A)), const SizedBox(width: 8), Expanded(child: Text(item.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900)))]),
          if (positions.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(positions, style: TextStyle(color: const Color(0xFF57D6D1).withValues(alpha: 0.86), fontSize: 11, fontWeight: FontWeight.w800)),
          ],
          const SizedBox(height: 8),
          Text(item.body, style: TextStyle(color: Colors.white.withValues(alpha: 0.76), fontSize: 12, height: 1.45, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class LifeDecadePanel extends StatelessWidget {
  const LifeDecadePanel({
    super.key,
    required this.contextData,
    required this.profile,
    required this.hasExactBirthBase,
    required this.onAskInChat,
  });

  final HoroscopeReadingContext contextData;
  final AstroProfile profile;
  final bool hasExactBirthBase;
  final ValueChanged<String> onAskInChat;

  @override
  Widget build(BuildContext context) {
    final birthParts = RegExp(r'(\d{4})\D+(\d{1,2})\D+(\d{1,2})').firstMatch(profile.birthDate);
    final now = DateTime.now();
    final birthDate = birthParts == null
        ? null
        : DateTime(
            int.parse(birthParts.group(1)!),
            int.parse(birthParts.group(2)!),
            int.parse(birthParts.group(3)!),
          );
    var age = birthDate == null ? null : now.year - birthDate.year;
    if (age != null && birthDate != null &&
        (now.month < birthDate.month ||
            (now.month == birthDate.month && now.day < birthDate.day))) {
      age--;
    }
    final decades = const [
      (0, 9), (10, 19), (20, 29), (30, 39), (40, 49),
      (50, 59), (60, 69), (70, 79), (80, 89),
    ];
    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SmallSectionLabel(icon: Icons.timeline_outlined, text: '10年ごとの人生の流れ'),
          const SizedBox(height: 8),
          Text(
            '出生図の実際の配置から、その年代で中心になりやすい人生分野を読みます。出来事を断定する年表ではありません。${age == null ? '' : '現在は${age}歳前後の流れを強調表示しています。'}',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.68), fontSize: 12, height: 1.45, fontWeight: FontWeight.w700),
          ),
          if (!hasExactBirthBase) ...[
            const SizedBox(height: 10),
            Text(
              '出生時間・出生地が未入力のため、年代の人生分野は目安です。入力すると、仕事・対人・居場所などの読み分けがより正確になります。',
              style: TextStyle(color: const Color(0xFFF6D77A).withValues(alpha: 0.82), fontSize: 11, height: 1.4, fontWeight: FontWeight.w800),
            ),
          ],
          if (age != null) ...[
            const SizedBox(height: 14),
            _LifeFlowNowNextSummary(
              currentAge: age,
              current: _currentDecadeSummary((age ~/ 10) * 10),
              next: _nextDecadeSummary(((age ~/ 10) + 1) * 10),
            ),
          ],
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 720;
              final width = wide ? (constraints.maxWidth - 10) / 2 : constraints.maxWidth;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: decades.map((decade) {
                  final current = age != null && age >= decade.$1 && age <= decade.$2;
                  final reading = _decadeReading(decade.$1);
                  return SizedBox(
                    width: width,
                    child: _LifeDecadeTile(
                      label: '${decade.$1}〜${decade.$2}歳',
                      theme: reading.$1,
                      body: reading.$2,
                      current: current,
                      onAskInChat: () => onAskInChat(
                        '${decade.$1}代の人生の流れを、仕事・恋愛・お金の順にもう少し詳しく見て',
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  (String, String) _decadeReading(int start) {
    final driver = _decadeDriver(start);
    final focus = _planetFocus(driver?.planet);
    final scene = _houseScene(driver?.house);
    final style = _signStyle(driver?.sign);
    final direction = switch (start) {
      0 => '安心の土台を作る',
      10 => '得意なことと言葉を育てる',
      20 => '好きなことと人との距離を形にする',
      30 => '社会での役割と生活を組み立てる',
      40 => '選択肢を広げ、進む方向を選び直す',
      50 => '経験を責任と信頼へ変える',
      60 => '自分らしい変化を受け入れる',
      70 => '心の豊かさと受け取ったものを深める',
      _ => '人生で育てた力を周囲へ渡す',
    };
    final title = '$direction: $focus';
    if (driver == null) {
      return (title, '$sceneを大切にしながら、自分に合うペースを選び直す時期です。');
    }
    return (
      title,
      '出生図では$focusが$sceneに表れやすい配置です。$style形で取り組むほど、この年代のテーマが自分らしい成果や安心感につながります。',
    );
  }

  LifeDecadeSummaryData _currentDecadeSummary(int start) {
    final driver = _decadeDriver(start);
    final focus = _planetFocus(driver?.planet);
    final scene = _houseScene(driver?.house);
    final style = _signStyle(driver?.sign);
    return LifeDecadeSummaryData(
      title: '現在の主題: $focus',
      body: '今の10年は、$focusを$sceneで具体的な形にしていく時期です。',
      points: [
        '取り組む: $style形で、今いちばん続けたいことを一つ決める。',
        '強み: $sceneに関する経験を、役割や得意分野として見せていく。',
        '慎重: 周囲の期待だけで選ばず、生活の余力を残して進める。',
      ],
    );
  }

  LifeDecadeSummaryData _nextDecadeSummary(int start) {
    final driver = _decadeDriver(start);
    final focus = _planetFocus(driver?.planet);
    final scene = _houseScene(driver?.house);
    final style = _signStyle(driver?.sign);
    return LifeDecadeSummaryData(
      title: '次に育つ主題: $focus',
      body: '次の10年は、$focusを$sceneへ広げる準備が始まる流れです。',
      points: [
        '準備: 今のうちに$sceneで必要になる知識、人、時間の余白を作る。',
        '育てる: $style形で続けられる方法を試し、次の土台にする。',
        '手放す: 役目を終えた予定や、無理を前提にしたやり方を少しずつ減らす。',
      ],
    );
  }

  PlanetPlacement? _decadeDriver(int start) {
    final planet = switch (start) {
      0 => AstroPlanet.moon,
      10 => AstroPlanet.mercury,
      20 => AstroPlanet.venus,
      30 => AstroPlanet.midheaven,
      40 => AstroPlanet.jupiter,
      50 => AstroPlanet.saturn,
      60 => AstroPlanet.uranus,
      70 => AstroPlanet.neptune,
      _ => AstroPlanet.pluto,
    };
    return contextData.natal.placementOf(planet) ??
        (planet == AstroPlanet.midheaven
            ? contextData.natal.placementOf(AstroPlanet.sun)
            : null);
  }

  String _planetFocus(AstroPlanet? planet) {
    return switch (planet) {
      AstroPlanet.moon => '安心感と心の土台',
      AstroPlanet.mercury => '学び、言葉、得意な伝え方',
      AstroPlanet.venus => '好み、人との距離、楽しみ',
      AstroPlanet.midheaven => '仕事、評価、社会での役割',
      AstroPlanet.jupiter => '成長、学び、選択肢の広がり',
      AstroPlanet.saturn => '責任、継続、長く残る土台',
      AstroPlanet.uranus => '変化、自由、自分らしい選び方',
      AstroPlanet.neptune => '共感、想像力、心の豊かさ',
      AstroPlanet.pluto => '深い変化、集中、受け渡す力',
      _ => '自分らしい人生の軸',
    };
  }

  String _houseScene(int? house) {
    return switch (house) {
      1 => '自分の見せ方や始め方', 2 => 'お金と大切にするもの',
      3 => '学び、会話、身近な行動', 4 => '家、居場所、安心できる基盤',
      5 => '恋愛、創作、楽しみ', 6 => '日々の仕事、体調、習慣',
      7 => '対人関係や約束', 8 => '深い関係や共有すること',
      9 => '学び、旅、視野を広げること', 10 => '仕事、評価、社会での役割',
      11 => '仲間、目標、これからの計画', 12 => '休息、心の整理、表に出ない準備',
      _ => '日常の選び方',
    };
  }

  String _signStyle(ZodiacSign? sign) {
    return switch (sign) {
      ZodiacSign.aries => '自分から先に動く', ZodiacSign.taurus => 'じっくり安定させる',
      ZodiacSign.gemini => '会話と情報を使う', ZodiacSign.cancer => '安心できる人や場所を守る',
      ZodiacSign.leo => '自信を持って表現する', ZodiacSign.virgo => '整理して役立てる',
      ZodiacSign.libra => '人とのバランスを取る', ZodiacSign.scorpio => '深く集中して本音を扱う',
      ZodiacSign.sagittarius => '学びや挑戦へ広げる', ZodiacSign.capricorn => '目標へ着実に積み上げる',
      ZodiacSign.aquarius => '自分らしい新しい方法を選ぶ', ZodiacSign.pisces => '想像力と思いやりを使う',
      null => '自分に合う形を選び直す',
    };
  }
}

class LifeDecadeSummaryData {
  const LifeDecadeSummaryData({required this.title, required this.body, required this.points});
  final String title;
  final String body;
  final List<String> points;
}

class _LifeFlowNowNextSummary extends StatelessWidget {
  const _LifeFlowNowNextSummary({
    required this.currentAge,
    required this.current,
    required this.next,
  });

  final int currentAge;
  final LifeDecadeSummaryData current;
  final LifeDecadeSummaryData next;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final items = [
          _LifeFlowSummaryItem(label: '今の10年', data: current, current: true),
          _LifeFlowSummaryItem(label: '次の10年', data: next, current: false),
        ];
        return Wrap(
          spacing: 14,
          runSpacing: 10,
          children: items
              .map((item) => SizedBox(
                    width: wide ? (constraints.maxWidth - 14) / 2 : constraints.maxWidth,
                    child: item,
                  ))
              .toList(),
        );
      },
    );
  }
}

class _LifeFlowSummaryItem extends StatelessWidget {
  const _LifeFlowSummaryItem({required this.label, required this.data, required this.current});

  final String label;
  final LifeDecadeSummaryData data;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final color = current ? const Color(0xFFF6D77A) : const Color(0xFF57D6D1);
    return Container(
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(border: Border(left: BorderSide(color: color, width: 3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900)),
        const SizedBox(height: 3),
        Text(data.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(data.body, style: TextStyle(color: Colors.white.withValues(alpha: 0.70), fontSize: 11, height: 1.4, fontWeight: FontWeight.w700)),
        const SizedBox(height: 7),
        ...data.points.map((point) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text('・$point', style: TextStyle(color: Colors.white.withValues(alpha: 0.80), fontSize: 11, height: 1.38, fontWeight: FontWeight.w700)),
        )),
      ]),
    );
  }
}

class _LifeDecadeTile extends StatelessWidget {
  const _LifeDecadeTile({required this.label, required this.theme, required this.body, required this.current, required this.onAskInChat});

  final String label;
  final String theme;
  final String body;
  final bool current;
  final VoidCallback onAskInChat;

  @override
  Widget build(BuildContext context) {
    final accent = current ? const Color(0xFFF6D77A) : const Color(0xFFB58CFF);
    return InkWell(
      onTap: onAskInChat,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: current ? 0.14 : 0.065),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: accent.withValues(alpha: current ? 0.62 : 0.22), width: current ? 1.4 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Text(label, style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w900)), const Spacer(), if (current) const Text('今ここ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900)), const SizedBox(width: 4), Icon(Icons.chat_bubble_outline, size: 16, color: Colors.white.withValues(alpha: 0.64))]),
          const SizedBox(height: 6),
          Text(theme, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
          const SizedBox(height: 7),
          Text(body, style: TextStyle(color: Colors.white.withValues(alpha: 0.76), fontSize: 12, height: 1.45, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

enum PlacementExplanationMode { simple, natal, transit }

class AstroPlacementModeSwitch extends StatelessWidget {
  const AstroPlacementModeSwitch({
    super.key,
    required this.showTransit,
    required this.onChanged,
  });

  final bool showTransit;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      child: SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: false, icon: Icon(Icons.person_pin_circle_outlined), label: Text('ネイタル')),
          ButtonSegment(value: true, icon: Icon(Icons.public_outlined), label: Text('トランジット')),
        ],
        selected: {showTransit},
        onSelectionChanged: (value) => onChanged(value.first),
      ),
    );
  }
}

class AstroSensitivityReading {
  const AstroSensitivityReading({
    required this.score,
    required this.moonScore,
    required this.primaryPlanet,
    required this.secondaryPlanet,
    required this.level,
    required this.body,
  });

  final int score;
  final int moonScore;
  final AstroPlanet primaryPlanet;
  final AstroPlanet secondaryPlanet;
  final String level;
  final String body;
}

class AstroSensitivityCalculator {
  const AstroSensitivityCalculator._();

  static AstroSensitivityReading calculate(HoroscopeReadingContext contextData) {
    final natal = contextData.natal;
    final moon = natal.placementOf(AstroPlanet.moon);
    final personalPlanets = [
      AstroPlanet.moon,
      AstroPlanet.mercury,
      AstroPlanet.venus,
      AstroPlanet.mars,
      AstroPlanet.sun,
    ];
    final angularCount = natal.placements
        .where((placement) => personalPlanets.contains(placement.planet) && _isAngular(placement.house))
        .length;
    final waterCount = natal.placements
        .where((placement) => personalPlanets.contains(placement.planet) && _isWater(placement.sign))
        .length;
    final moonScore = moon == null ? 50 : _planetScore(moon, natal, isMoon: true);
    final planetScores = <AstroPlanet, int>{
      for (final planet in [
        AstroPlanet.moon,
        AstroPlanet.mercury,
        AstroPlanet.venus,
        AstroPlanet.mars,
        AstroPlanet.sun,
        AstroPlanet.neptune,
      ])
        if (natal.placementOf(planet) case final placement?)
          planet: _planetScore(placement, natal, isMoon: planet == AstroPlanet.moon),
    };
    final ranked = planetScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final primary = ranked.isEmpty ? AstroPlanet.moon : ranked.first.key;
    final secondary = ranked.length > 1 ? ranked[1].key : AstroPlanet.venus;
    final stelliumBoost = natal.stelliums.isEmpty
        ? 0
        : natal.stelliums.fold<int>(0, (sum, item) => sum + math.min(4, item.planets.length));
    final score = (45 +
            ((moonScore - 45) * 0.52).round() +
            math.min(12, angularCount * 4) +
            math.min(10, waterCount * 3) +
            math.min(9, stelliumBoost))
        .clamp(45, 95)
        .toInt();
    final level = switch (score) {
      >= 84 => 'かなり感じ取りやすい',
      >= 72 => '感じ取りやすい',
      >= 60 => 'やや感じ取りやすい',
      _ => '安定して受け止めやすい',
    };
    final moonPhrase = moonScore >= 78
        ? '月の変化を気分、眠り、対人の空気として受け取りやすい傾向があります'
        : moonScore >= 64
            ? '月の変化が生活リズムや気分に表れやすい方です'
            : '月の変化は、意識して予定や休息を整える時に役立てやすい方です';
    final primaryLabel = primary == AstroPlanet.moon ? '月' : primary.label;
    final secondaryLabel = secondary.label;
    return AstroSensitivityReading(
      score: score,
      moonScore: moonScore,
      primaryPlanet: primary,
      secondaryPlanet: secondary,
      level: level,
      body: '$moonPhrase。特に$primaryLabel、次いで$secondaryLabelのテーマで、星の流れを自分事として感じやすい配置です。疲れや迷いを感じる日は、予定を減らす、休息を先に取る、気持ちを言葉にするなど、小さく整える使い方が合います。',
    );
  }

  static int _planetScore(PlanetPlacement placement, NatalChart natal, {required bool isMoon}) {
    var value = isMoon ? 52 : 40;
    if (_isAngular(placement.house)) value += 15;
    if (placement.house == 8 || placement.house == 12) value += 10;
    if (_isWater(placement.sign)) value += isMoon ? 10 : 6;
    if (placement.sign == ZodiacSign.cancer && isMoon) value += 8;
    if (natal.stelliums.any((item) => item.planets.contains(placement.planet))) value += 8;
    return value.clamp(38, 95).toInt();
  }

  static bool _isAngular(int house) => house == 1 || house == 4 || house == 7 || house == 10;

  static bool _isWater(ZodiacSign sign) =>
      sign == ZodiacSign.cancer || sign == ZodiacSign.scorpio || sign == ZodiacSign.pisces;
}

class AstroSensitivityCard extends StatelessWidget {
  const AstroSensitivityCard({super.key, required this.reading});

  final AstroSensitivityReading reading;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 74,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFB58CFF).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFB58CFF).withValues(alpha: 0.40)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${reading.score}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFFB58CFF))),
            const Text('/ 100', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
          ]),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(child: Text('星の影響度', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
              IconButton(
                tooltip: 'この指標を画像で共有',
                onPressed: () {
                  showFortuneShareComposer(
                    context,
                    periodLabel: '生まれた星の影響度',
                    score: reading.score,
                    body: '月の感じやすさは${reading.moonScore}/100。${reading.body}',
                    metricLabel: '星の影響度',
                  );
                },
                icon: const Icon(Icons.ios_share_outlined, size: 20),
              ),
            ]),
            Text(reading.level, style: const TextStyle(color: Color(0xFFF6D77A), fontSize: 13, fontWeight: FontWeight.w900)),
            const SizedBox(height: 5),
            Text('月の感じやすさ ${reading.moonScore}/100  |  反応しやすい星: ${reading.primaryPlanet.label}・${reading.secondaryPlanet.label}', style: TextStyle(color: const Color(0xFF57D6D1).withValues(alpha: 0.9), fontSize: 11, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(reading.body, style: TextStyle(color: Colors.white.withValues(alpha: 0.78), fontSize: 12, height: 1.5, fontWeight: FontWeight.w700)),
          ]),
        ),
      ]),
    );
  }
}

class MoonInfluenceForecastPanel extends StatelessWidget {
  const MoonInfluenceForecastPanel({super.key, required this.profile, required this.contextFor});

  final AstroProfile profile;
  final HoroscopeReadingContext Function(DateTime date) contextFor;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final entries = List.generate(7, (index) {
      final date = DateTime(today.year, today.month, today.day + index, 12);
      final data = contextFor(date);
      final moonAspects = data.aspects.where((item) => item.transitPlanet == AstroPlanet.moon).toList();
      PlanetPlacement? moon;
      for (final placement in data.transit.placements) {
        if (placement.planet == AstroPlanet.moon) {
          moon = placement;
          break;
        }
      }
      final base = AstroSensitivityCalculator.calculate(data).moonScore;
      final aspectBoost = moonAspects.fold<int>(0, (sum, item) => sum + (item.orb <= 1.5 ? 9 : 5));
      final waterBoost = moon != null && (moon.sign == ZodiacSign.cancer || moon.sign == ZodiacSign.scorpio || moon.sign == ZodiacSign.pisces) ? 5 : 0;
      final score = ((base * 0.55) + 24 + math.min(18, aspectBoost) + waterBoost).round().clamp(45, 95).toInt();
      return _MoonForecastEntry(date, score, moonAspects.isNotEmpty);
    })..sort((a, b) => b.score.compareTo(a.score));
    final strong = entries.take(2).toList();
    final careful = entries.last;
    String label(_MoonForecastEntry entry) => '${entry.date.month}/${entry.date.day}';
    return GlassPanel(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: _SmallSectionLabel(icon: Icons.nights_stay_outlined, text: '今週の月の影響予報')),
          IconButton(
            tooltip: '月の影響予報を画像で共有',
            onPressed: () {
              showFortuneShareComposer(
                context,
                periodLabel: '今週の月の影響予報',
                score: strong.first.score,
                metricLabel: '月の影響度',
                body: '感じやすい日: ${strong.map(label).join('・')}。整えやすい日: ${label(careful)}。月の動きは良い悪いではなく、予定の組み方に使う目安です。',
              );
            },
            icon: const Icon(Icons.ios_share_outlined, size: 20),
          ),
        ]),
        const SizedBox(height: 7),
        Text('月の動きが気分や生活リズムへ表れやすい日を先に示します。良い悪いではなく、予定の組み方に使う目安です。', style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 12, height: 1.45)),
        const SizedBox(height: 12),
        Text('感じやすい日: ${strong.map(label).join('・')}', style: const TextStyle(color: Color(0xFFF6D77A), fontSize: 13, fontWeight: FontWeight.w900)),
        Text('直感、創作、休息、気持ちの整理に使いやすい日です。予定を詰めすぎず、余白を先に置くと整います。', style: TextStyle(color: Colors.white.withValues(alpha: 0.78), fontSize: 12, height: 1.45)),
        const SizedBox(height: 8),
        Text('整えやすい日: ${label(careful)}', style: const TextStyle(color: Color(0xFF57D6D1), fontSize: 13, fontWeight: FontWeight.w900)),
        Text('気分が安定しやすいので、決めることや続けたい習慣を一つ進めるのに向きます。', style: TextStyle(color: Colors.white.withValues(alpha: 0.78), fontSize: 12, height: 1.45)),
      ]),
    );
  }
}

class _MoonForecastEntry {
  const _MoonForecastEntry(this.date, this.score, this.hasAspect);
  final DateTime date;
  final int score;
  final bool hasAspect;
}

class AstroPlacementExplanationPanel extends StatefulWidget {
  const AstroPlacementExplanationPanel({
    super.key,
    required this.contextData,
    required this.mode,
  });

  final HoroscopeReadingContext contextData;
  final PlacementExplanationMode mode;

  @override
  State<AstroPlacementExplanationPanel> createState() => _AstroPlacementExplanationPanelState();
}

class _AstroPlacementExplanationPanelState extends State<AstroPlacementExplanationPanel> {
  AstroPlanet? _expandedPlanet;

  @override
  Widget build(BuildContext context) {
    final placements = _placements();
    final sensitivity = widget.mode == PlacementExplanationMode.simple
        ? AstroSensitivityCalculator.calculate(widget.contextData)
        : null;
    final title = switch (widget.mode) {
      PlacementExplanationMode.simple => '生まれた星の読み方',
      PlacementExplanationMode.natal => 'ネイタルの星',
      PlacementExplanationMode.transit => '現在動いている星',
    };
    final subtitle = switch (widget.mode) {
      PlacementExplanationMode.simple => '占い初心者向けに、性格や人生テーマに出やすい星だけを表示します。',
      PlacementExplanationMode.natal => '生まれた時の星。もともとの性質や人生テーマとして読みます。',
      PlacementExplanationMode.transit => '現在の星。今日から近い時期に動く流れとして読みます。',
    };

    return Column(
      children: [
        if (sensitivity != null) AstroSensitivityCard(reading: sensitivity),
        GlassPanel(
          padding: const EdgeInsets.all(16),
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SmallSectionLabel(
            icon: widget.mode == PlacementExplanationMode.transit
                ? Icons.public_outlined
                : Icons.auto_awesome_motion,
            text: title,
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.62),
              height: 1.45,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (widget.mode == PlacementExplanationMode.transit) ...[
            const SizedBox(height: 12),
            TransitSkySummaryCard(contextData: widget.contextData),
          ],
          if (widget.mode == PlacementExplanationMode.natal) ...[
            const SizedBox(height: 12),
            NatalSkySummaryCard(contextData: widget.contextData),
          ],
          if (widget.mode != PlacementExplanationMode.simple) ...[
            const SizedBox(height: 8),
            Text(
              widget.mode == PlacementExplanationMode.natal
                  ? '「逆行」は出生時にその星が逆向きに見えていた印です。該当する星だけに表示します。'
                  : '「逆行」は現在その星が逆向きに見えている期間です。該当する星だけに表示します。',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 11, height: 1.35),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF57D6D1).withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF57D6D1).withValues(alpha: 0.28)),
            ),
            child: Row(
              children: [
                const Icon(Icons.touch_app_outlined, size: 17, color: Color(0xFF57D6D1)),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    '気になる星のカードをタップすると、意味をやさしく詳しく読めます',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.82), fontSize: 11, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 720;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: placements
                    .map(
                      (placement) => SizedBox(
                        width: isWide ? (constraints.maxWidth - 10) / 2 : constraints.maxWidth,
                        child: AstroPlacementTile(
                          placement: placement,
                          mode: widget.mode,
                          retrograde: widget.mode == PlacementExplanationMode.transit
                              ? widget.contextData.retrogradePlanets.contains(placement.planet)
                              : widget.contextData.natal.retrogradePlanets.contains(placement.planet),
                          expanded: _expandedPlanet == placement.planet,
                          onTap: () => setState(() {
                            _expandedPlanet = _expandedPlanet == placement.planet
                                ? null
                                : placement.planet;
                          }),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
          ),
        ),
      ],
    );
  }

  List<PlanetPlacement> _placements() {
    final source = widget.mode == PlacementExplanationMode.transit
        ? widget.contextData.transit.placements
        : widget.contextData.natal.placements;
    final planets = switch (widget.mode) {
      PlacementExplanationMode.simple => const [
          AstroPlanet.sun,
          AstroPlanet.moon,
          AstroPlanet.venus,
          AstroPlanet.mercury,
          AstroPlanet.jupiter,
          AstroPlanet.ascendant,
          AstroPlanet.midheaven,
        ],
      PlacementExplanationMode.natal => const [
          AstroPlanet.sun,
          AstroPlanet.moon,
          AstroPlanet.mercury,
          AstroPlanet.venus,
          AstroPlanet.mars,
          AstroPlanet.jupiter,
          AstroPlanet.saturn,
          AstroPlanet.uranus,
          AstroPlanet.neptune,
          AstroPlanet.pluto,
          AstroPlanet.ascendant,
          AstroPlanet.midheaven,
        ],
      PlacementExplanationMode.transit => const [
          AstroPlanet.sun,
          AstroPlanet.moon,
          AstroPlanet.mercury,
          AstroPlanet.venus,
          AstroPlanet.mars,
          AstroPlanet.jupiter,
          AstroPlanet.saturn,
          AstroPlanet.uranus,
          AstroPlanet.neptune,
          AstroPlanet.pluto,
        ],
    };
    return [
      for (final planet in planets)
        for (final placement in source)
          if (placement.planet == planet) placement,
    ];
  }
}

class NatalSkySummaryCard extends StatelessWidget {
  const NatalSkySummaryCard({super.key, required this.contextData});

  final HoroscopeReadingContext contextData;

  @override
  Widget build(BuildContext context) {
    final natal = contextData.natal;
    final sun = natal.placementOf(AstroPlanet.sun);
    final moon = natal.placementOf(AstroPlanet.moon);
    final asc = natal.placementOf(AstroPlanet.ascendant);
    final mc = natal.placementOf(AstroPlanet.midheaven);
    final rarePatterns = FortuneScoreCalculator.natalRarePatternLabels(contextData);
    final lines = <String>[
      if (sun != null && moon != null) '太陽 ${sun.sign.label} × 月 ${moon.sign.label}：自分らしさと安心の土台',
      if (asc != null) 'ASC ${asc.sign.label}：第一印象と人生の始め方',
      if (mc != null) 'MC ${mc.sign.label}：仕事・社会で目指しやすい方向',
      if (natal.retrogradePlanets.isNotEmpty)
        '${natal.retrogradePlanets.map((planet) => planet.label).join('・')}が出生時に逆行：内側で育てる持ち味',
      ...natal.stelliums.map((item) => '${item.label}：一点を深める人生テーマ'),
      if (FortuneScoreCalculator.hasNatalKite(contextData))
        'カイト：得意なことを外へ向けるほど、才能を成果に結びつけやすい配置',
      ...rarePatterns.map((label) => '$label：${FortuneScoreCalculator.rarePatternGuidance(label, natal: true)}'),
    ];
    final visibleLines = lines.take(6).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF6D77A).withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFF6D77A).withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SmallSectionLabel(
            icon: Icons.auto_awesome_motion,
            text: '生まれ持った主要配置',
          ),
          const SizedBox(height: 7),
          Text(
            visibleLines.join('\n'),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.80),
              fontSize: 12,
              height: 1.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (lines.length > visibleLines.length) ...[
            const SizedBox(height: 5),
            Text(
              '詳しい意味は下の各星カードで確認できます。',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 10, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }
}

class TransitSkySummaryCard extends StatelessWidget {
  const TransitSkySummaryCard({super.key, required this.contextData});

  final HoroscopeReadingContext contextData;

  @override
  Widget build(BuildContext context) {
    final retrogrades = contextData.retrogradePlanets;
    final pairAspects = [...contextData.transitPairAspects]
      ..sort((a, b) => a.orb.compareTo(b.orb));
    final tightAspects = pairAspects.take(3).toList();
    final bySign = <ZodiacSign, List<AstroPlanet>>{};
    for (final placement in contextData.transit.placements) {
      if (placement.planet == AstroPlanet.ascendant || placement.planet == AstroPlanet.midheaven) continue;
      bySign.putIfAbsent(placement.sign, () => []).add(placement.planet);
    }
    final stelliums = bySign.entries
        .where((entry) => entry.value.length >= 3)
        .map((entry) => '${entry.key.label}に${entry.value.map((planet) => planet.label).join('・')}が集中')
        .toList();
    final grandTrines = FortuneScoreCalculator.transitGrandTrineLabels(contextData);
    final rarePatterns = FortuneScoreCalculator.transitRarePatternLabels(contextData)
        .where((label) => !label.startsWith('グランドトライン'))
        .toList();
    final lines = <String>[
      if (retrogrades.isNotEmpty)
        '${retrogrades.map((planet) => planet.label).join('・')}が逆行中。見直し・再調整を優先。',
      ...tightAspects.map(
        (aspect) => '${aspect.firstPlanet.label} ${aspect.type.label} ${aspect.secondPlanet.label}（${aspect.orb.toStringAsFixed(1)}°・${aspect.phase.label}）',
      ),
      ...stelliums,
      ...grandTrines.map((label) => 'グランドトライン（$label）'),
      ...rarePatterns.map((label) => '$label：${FortuneScoreCalculator.rarePatternGuidance(label)}'),
      if (contextData.transit.voidMoon != null)
        'ボイドタイム ${contextData.transit.voidMoon!.label}：即決より確認を。',
    ];
    final visibleLines = lines.take(6).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF57D6D1).withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF57D6D1).withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SmallSectionLabel(
            icon: Icons.hub_outlined,
            text: '本日の主要配置',
          ),
          const SizedBox(height: 7),
          Text(
            visibleLines.isEmpty
                ? '強い主要配置は少なめです。普段のペースを整えるほど、星の流れを使いやすい日です。'
                : visibleLines.join('\n'),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.80),
              fontSize: 12,
              height: 1.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (lines.length > visibleLines.length) ...[
            const SizedBox(height: 5),
            Text(
              'ほかの配置は下の各カードと「全アスペクト表」で確認できます。',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 10, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }
}

class AstroPlacementTile extends StatelessWidget {
  const AstroPlacementTile({
    super.key,
    required this.placement,
    required this.mode,
    required this.retrograde,
    required this.expanded,
    required this.onTap,
  });

  final PlanetPlacement placement;
  final PlacementExplanationMode mode;
  final bool retrograde;
  final bool expanded;
  final VoidCallback onTap;

  bool get _isSimple => mode == PlacementExplanationMode.simple;

  String _retrogradeMeaning() {
    final theme = switch (placement.planet) {
      AstroPlanet.mercury => '考え方・言葉・連絡',
      AstroPlanet.venus => '愛情・好み・お金の使い方',
      AstroPlanet.mars => '行動力・怒り・進め方',
      AstroPlanet.jupiter => '成長・学び・広げ方',
      AstroPlanet.saturn => '責任・課題・続け方',
      AstroPlanet.uranus => '変化・独自性・自由',
      AstroPlanet.neptune => '理想・想像力・境界線',
      AstroPlanet.pluto => '深い変化・手放し・再生',
      AstroPlanet.sun => '自分らしさ・目的',
      AstroPlanet.moon => '気分・安心感',
      AstroPlanet.ascendant => '自分の見せ方・始め方',
      AstroPlanet.midheaven => '仕事・社会での役割',
    };
    if (mode == PlacementExplanationMode.natal) {
      return '出生時の${placement.planet.label}は逆行です。$themeは、外から急いで答えを得るより、自分の中で考え直しながら育てるほど持ち味になりやすい配置です。';
    }
    return '現在の${placement.planet.label}は逆行中です。$themeは、新しく急ぐより、見直し・再調整・やり直しに力を使うと活かしやすい時期です。';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFB58CFF).withValues(alpha: 0.075),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFB58CFF).withValues(alpha: 0.22)),
        ),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_iconFor(placement.planet), size: 18, color: const Color(0xFFF6D77A)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _isSimple
                      ? '${placement.planet.label} / ${placement.sign.label}${retrograde ? ' / 逆行' : ''}'
                      : '${placement.planet.label} / ${placement.sign.label} / 第${placement.house}ハウス${retrograde ? ' / 逆行' : ''}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
                ),
              ),
              if (retrograde)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6D77A).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: const Color(0xFFF6D77A).withValues(alpha: 0.48)),
                  ),
                  child: const Text('逆行', style: TextStyle(color: Color(0xFFF6D77A), fontSize: 10, fontWeight: FontWeight.w900)),
                ),
            ],
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 180),
            crossFadeState: expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('あなたの場合: ${_summary(placement)}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha: 0.76), fontSize: 12, height: 1.4, fontWeight: FontWeight.w700)),
                const SizedBox(height: 7),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text('タップして詳しく読む', style: TextStyle(color: const Color(0xFF57D6D1).withValues(alpha: 0.9), fontSize: 11, fontWeight: FontWeight.w900)),
                  const Icon(Icons.expand_more, size: 17, color: Color(0xFF57D6D1)),
                ]),
              ]),
            ),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_planetMeaning(placement.planet), style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 12, height: 1.45, fontWeight: FontWeight.w700)),
                const SizedBox(height: 7),
                Text(_isSimple ? '星座の雰囲気: ${_signMeaning(placement.sign)}' : '${placement.sign.label}: ${_signMeaning(placement.sign)}', style: TextStyle(color: const Color(0xFF57D6D1).withValues(alpha: 0.88), fontSize: 12, height: 1.4, fontWeight: FontWeight.w800)),
                const SizedBox(height: 5),
                Text(_isSimple ? '表れやすい場面: ${_houseMeaning(placement.house)}' : '第${placement.house}ハウス: ${_houseMeaning(placement.house)}', style: TextStyle(color: const Color(0xFFF6D77A).withValues(alpha: 0.88), fontSize: 12, height: 1.4, fontWeight: FontWeight.w800)),
                if (retrograde) ...[
                  const SizedBox(height: 7),
                  Text(_retrogradeMeaning(), style: TextStyle(color: const Color(0xFFF6D77A).withValues(alpha: 0.92), fontSize: 12, height: 1.45, fontWeight: FontWeight.w800)),
                ],
                const SizedBox(height: 7),
                Text('あなたの場合: ${_summary(placement)}', style: TextStyle(color: Colors.white.withValues(alpha: 0.90), fontSize: 12, height: 1.45, fontWeight: FontWeight.w800)),
                const SizedBox(height: 7),
                Text('活かし方: ${_actionHint(placement)}', style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 12, height: 1.45, fontWeight: FontWeight.w700)),
                const SizedBox(height: 7),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text('閉じる', style: TextStyle(color: const Color(0xFF57D6D1).withValues(alpha: 0.9), fontSize: 11, fontWeight: FontWeight.w900)),
                  const Icon(Icons.expand_less, size: 17, color: Color(0xFF57D6D1)),
                ]),
              ]),
            ),
          ),
        ],
        ),
      ),
    );
  }

  String _actionHint(PlanetPlacement value) {
    return switch (value.planet) {
      AstroPlanet.moon => '気分が揺れる日は、予定を一つ減らして安心できる習慣を先に置くと整いやすいです。',
      AstroPlanet.mercury => '考えを頭の中だけで回さず、短く書く・話すことで判断がまとまりやすくなります。',
      AstroPlanet.venus => '好きなものや心地よい人との時間を予定に入れると、対人やお金の選び方が安定します。',
      AstroPlanet.mars => '勢いが出た時ほど、最初の一手を小さく決めてから動くと力を使いやすいです。',
      AstroPlanet.sun => '自分で決めた優先順位を一つ表に出すと、自信と行動がかみ合いやすくなります。',
      AstroPlanet.jupiter => '学びや人とのつながりを少し広げると、次の選択肢を見つけやすくなります。',
      AstroPlanet.saturn => '負担を抱え込まず、期限と役割を小さく区切るほど続けやすくなります。',
      AstroPlanet.uranus => 'いつもと違う方法を一つだけ試すと、変化を味方にしやすくなります。',
      AstroPlanet.neptune => '気持ちが曖昧な時は、休息と事実確認を分けると迷いが薄れます。',
      AstroPlanet.pluto => '手放すことを一つ決め、深く取り組む対象を絞ると変化を活かせます。',
      AstroPlanet.ascendant => '人に見せる最初の一歩を整えると、その日の流れを作りやすくなります。',
      AstroPlanet.midheaven => '仕事や目標を一文で言える形にすると、進む方向がぶれにくくなります。',
    };
  }

  IconData _iconFor(AstroPlanet planet) {
    switch (planet) {
      case AstroPlanet.sun:
        return Icons.wb_sunny_outlined;
      case AstroPlanet.moon:
        return Icons.dark_mode_outlined;
      case AstroPlanet.mercury:
        return Icons.forum_outlined;
      case AstroPlanet.venus:
        return Icons.favorite_border;
      case AstroPlanet.mars:
        return Icons.local_fire_department_outlined;
      case AstroPlanet.jupiter:
        return Icons.savings_outlined;
      case AstroPlanet.saturn:
        return Icons.account_tree_outlined;
      case AstroPlanet.ascendant:
        return Icons.person_pin_circle_outlined;
      case AstroPlanet.midheaven:
        return Icons.work_outline;
      case AstroPlanet.uranus:
      case AstroPlanet.neptune:
      case AstroPlanet.pluto:
        return Icons.auto_awesome_motion;
    }
  }

  String _summary(PlanetPlacement value) {
    final focus = switch (value.planet) {
      AstroPlanet.sun => '自分らしさ',
      AstroPlanet.moon => '安心できる感情の扱い',
      AstroPlanet.mercury => '考え方と言葉',
      AstroPlanet.venus => '好きなものと人との距離',
      AstroPlanet.mars => '行動の勢い',
      AstroPlanet.jupiter => '成長と広がり',
      AstroPlanet.saturn => '責任と積み重ね',
      AstroPlanet.uranus => '変化と独自性',
      AstroPlanet.neptune => '想像力と共感',
      AstroPlanet.pluto => '深い変化',
      AstroPlanet.ascendant => '第一印象と始め方',
      AstroPlanet.midheaven => '社会での役割',
    };
    final style = switch (value.sign) {
      ZodiacSign.aries => '自分から先に動く形で',
      ZodiacSign.taurus => 'じっくり安定させる形で',
      ZodiacSign.gemini => '会話や情報を使う形で',
      ZodiacSign.cancer => '安心できる人や場所を守る形で',
      ZodiacSign.leo => '自信を持って表現する形で',
      ZodiacSign.virgo => '整理して役立てる形で',
      ZodiacSign.libra => '人とのバランスを取る形で',
      ZodiacSign.scorpio => '深く集中する形で',
      ZodiacSign.sagittarius => '学びや挑戦へ広げる形で',
      ZodiacSign.capricorn => '目標へ着実に積み上げる形で',
      ZodiacSign.aquarius => '自分らしい新しい方法で',
      ZodiacSign.pisces => '想像力や思いやりを使う形で',
    };
    final scene = switch (value.house) {
      1 => '自分の見せ方や新しい始まり',
      2 => 'お金や大切にするもの',
      3 => '会話、学び、身近な行動',
      4 => '家や安心できる居場所',
      5 => '恋愛、創作、楽しみ',
      6 => '日々の仕事、健康、習慣',
      7 => '恋愛や対人関係',
      8 => '深い関係や共有するお金',
      9 => '学び、旅行、視野を広げること',
      10 => '仕事、評価、社会での役割',
      11 => '仲間、目標、これからの計画',
      12 => '休息、心の整理、表に出ない準備',
      _ => '日常の場面',
    };
    return '$focusが、$style、$sceneに表れやすい配置です。';
  }

  String _planetMeaning(AstroPlanet planet) {
    switch (planet) {
      case AstroPlanet.sun:
        return '自分らしさ、目的、表に出る力。総合運の中心。';
      case AstroPlanet.moon:
        return '気分、安心感、日々のコンディション。毎日の運勢で重要。';
      case AstroPlanet.mercury:
        return '言葉、判断、連絡、学び。仕事運や予定整理を見る。';
      case AstroPlanet.venus:
        return '愛情、好み、楽しみ、お金の使い方。恋愛運と金運で重要。';
      case AstroPlanet.mars:
        return '行動力、勝負、欲求。動く力や衝突の出方を見る。';
      case AstroPlanet.jupiter:
        return '拡大、チャンス、増える流れ。金運と総合運を押し上げる。';
      case AstroPlanet.saturn:
        return '責任、制限、継続。仕事運や現実的な課題を見る。';
      case AstroPlanet.uranus:
        return '変化、自由、切り替え。急な展開や改革の流れ。';
      case AstroPlanet.neptune:
        return '夢、直感、曖昧さ。理想や迷いやすさを見る。';
      case AstroPlanet.pluto:
        return '深い変化、集中、再生。避けられない変容のテーマ。';
      case AstroPlanet.ascendant:
        return '第一印象、自分の出し方、始め方。簡易でも重要。';
      case AstroPlanet.midheaven:
        return '社会的な役割、仕事の方向性、評価。仕事運で重要。';
    }
  }

  String _signMeaning(ZodiacSign sign) {
    switch (sign) {
      case ZodiacSign.aries:
        return '勢いよく始める、直感で動く';
      case ZodiacSign.taurus:
        return '安定、五感、じっくり育てる';
      case ZodiacSign.gemini:
        return '情報、会話、軽やかな切り替え';
      case ZodiacSign.cancer:
        return '安心感、身内、守る力';
      case ZodiacSign.leo:
        return '表現、自信、主役になる力';
      case ZodiacSign.virgo:
        return '整理、改善、実務力';
      case ZodiacSign.libra:
        return '調和、対人、バランス';
      case ZodiacSign.scorpio:
        return '深い関係、集中、本音';
      case ZodiacSign.sagittarius:
        return '探求、遠くへ広げる、学び';
      case ZodiacSign.capricorn:
        return '責任、成果、積み上げ';
      case ZodiacSign.aquarius:
        return '自由、仲間、未来志向';
      case ZodiacSign.pisces:
        return '共感、直感、境界を溶かす';
    }
  }

  String _houseMeaning(int house) {
    switch (house) {
      case 1:
        return '自分自身、第一印象、始め方に出る';
      case 2:
        return '収入、所有、価値観、お金の使い方に出る';
      case 3:
        return '会話、学び、近い移動、情報に出る';
      case 4:
        return '家、安心感、心の土台に出る';
      case 5:
        return '恋愛、創作、楽しみ、自己表現に出る';
      case 6:
        return '仕事の段取り、健康、日課に出る';
      case 7:
        return '対人関係、恋愛、約束に出る';
      case 8:
        return '共有、深い関係、受け取るものに出る';
      case 9:
        return '学び、遠方、信念、専門性に出る';
      case 10:
        return '仕事、評価、肩書き、社会的役割に出る';
      case 11:
        return '仲間、未来計画、コミュニティに出る';
      case 12:
        return '休息、無意識、見えない疲れに出る';
      default:
        return 'その星のテーマが第$houseハウス領域に出る';
    }
  }
}

class HoroscopeEngineSummary extends StatelessWidget {
  const HoroscopeEngineSummary({super.key, required this.contextData});

  final HoroscopeReadingContext contextData;

  @override
  Widget build(BuildContext context) {
    final natalSun = contextData.natal.placementOf(AstroPlanet.sun);
    final natalMoon = contextData.natal.placementOf(AstroPlanet.moon);
    final natalVenus = contextData.natal.placementOf(AstroPlanet.venus);
    final natalAsc = contextData.natal.placementOf(AstroPlanet.ascendant);
    final natalMc = contextData.natal.placementOf(AstroPlanet.midheaven);
    final transitVenus = _placementOf(contextData.transit.placements, AstroPlanet.venus);
    final stellium = contextData.natal.stelliums.isEmpty
        ? null
        : contextData.natal.stelliums.first;
    final voidMoon = contextData.transit.voidMoon;

    return GlassPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SmallSectionLabel(
            icon: Icons.schema_outlined,
            text: '鑑定エンジンの見る範囲',
          ),
          const SizedBox(height: 12),
          _EngineSummaryRow(
            label: '出生図の太陽',
            value: natalSun?.compactLabel ?? '出生時刻と出生地から算出',
          ),
          _EngineSummaryRow(
            label: '出生図の月',
            value: natalMoon?.compactLabel ?? '出生時刻と出生地から算出',
          ),
          _EngineSummaryRow(
            label: '出生図の金星',
            value: natalVenus?.compactLabel ?? '出生時刻と出生地から算出',
          ),
          _EngineSummaryRow(
            label: '入力出生地',
            value: contextData.natal.profile.birthPlace,
          ),
          _EngineSummaryRow(
            label: '計算地点',
            value:
                '${contextData.birthPlace.label} / 緯度${contextData.birthPlace.latitude.toStringAsFixed(3)} 経度${contextData.birthPlace.longitude.toStringAsFixed(3)}',
          ),
          _EngineSummaryRow(
            label: 'ASC/MC',
            value: [
              natalAsc?.compactLabel ?? 'ASC算出中',
              natalMc?.compactLabel ?? 'MC算出中',
            ].join(' / '),
          ),
          _EngineSummaryRow(
            label: 'ハウス',
            value: contextData.houseSystem == HouseSystem.placidus
                ? 'Placidus。出生地・出生時刻から各カスプを計算。'
                : 'Whole Sign。ASCのある星座全体を第1ハウスとして計算。',
          ),
          _EngineSummaryRow(
            label: '星データ',
            value: contextData.ephemerisSourceName,
          ),
          _EngineSummaryRow(
            label: '計算精度',
            value: contextData.ephemerisPrecisionNotice,
          ),
          _EngineSummaryRow(
            label: '現在の星',
            value: transitVenus?.compactLabel ?? '指定日の天体位置から算出',
          ),
          _EngineSummaryRow(
            label: 'トランジット',
            value: contextData.aspects.isEmpty
                ? '出生図との角度を確認'
                : contextData.aspects.first.label,
          ),
          _EngineSummaryRow(
            label: 'ハウス通過',
            value: contextData.houseTransits.isEmpty
                ? '現在の星が出生図の何ハウスを通過するか確認'
                : '現在の${contextData.houseTransits.first.planet.label}: 第${contextData.houseTransits.first.natalHouse}ハウス',
          ),
          _EngineSummaryRow(
            label: '集中補正',
            value: stellium?.label ?? 'ステリウムや強調ハウスを確認',
          ),
          _EngineSummaryRow(
            label: 'ボイド/リターン',
            value: [
              if (voidMoon != null) '月ボイド ${voidMoon.label}',
              if (contextData.returns.isNotEmpty) contextData.returns.first.label,
            ].join(' / '),
          ),
        ],
      ),
    );
  }

  PlanetPlacement? _placementOf(List<PlanetPlacement> placements, AstroPlanet planet) {
    for (final placement in placements) {
      if (placement.planet == planet) return placement;
    }
    return null;
  }
}

class _EngineSummaryRow extends StatelessWidget {
  const _EngineSummaryRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFFF6D77A),
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum ConsultationTopic {
  overall('総合'),
  love('恋愛'),
  work('仕事'),
  money('お金'),
  mental('心と体');

  const ConsultationTopic(this.label);
  final String label;
}

enum ConsultationPromptMode {
  action('今どう動く？'),
  caution('注意点'),
  timing('良い時期'),
  compare('比較する'),
  longTerm('長期の流れ');

  const ConsultationPromptMode(this.label);
  final String label;
}

enum ConsultationSituation {
  start('新しく始めること'),
  continueThing('続けていること'),
  relationship('人との関係'),
  result('結果・評価'),
  balance('お金・生活の整え方');

  const ConsultationSituation(this.label);
  final String label;
}

enum ConsultationPeriod {
  today('今日'),
  week('今週'),
  month('今月'),
  threeMonths('今後3か月'),
  year('今後1年'),
  fiveYears('今後5年');

  const ConsultationPeriod(this.label);
  final String label;
}

class CustomReading extends StatefulWidget {
  const CustomReading({
    super.key,
    required this.profile,
    required this.details,
    required this.contextData,
    this.initialQuestion = '',
    this.onInitialQuestionConsumed,
  });

  final AstroProfile profile;
  final UserProfileDetails details;
  final HoroscopeReadingContext contextData;
  final String initialQuestion;
  final VoidCallback? onInitialQuestionConsumed;

  @override
  State<CustomReading> createState() => _CustomReadingState();
}

class _CustomReadingState extends State<CustomReading> {
  static const _maxQuestionLength = 1000;

  final _controller = TextEditingController();
  final _questionFocusNode = FocusNode();
  final _chatScrollController = ScrollController();
  bool _loading = false;
  bool _showNavigator = true;
  List<CustomFortuneLog> _chatLogs = const [];
  String? _activeQuestion;
  ConsultationTopic _navigatorTopic = ConsultationTopic.overall;
  ConsultationPromptMode _navigatorMode = ConsultationPromptMode.action;
  ConsultationSituation _navigatorSituation = ConsultationSituation.start;
  ConsultationPeriod _navigatorPeriod = ConsultationPeriod.today;
  DateTime _navigatorDate = DateTime.now();

  List<String> get _questionExamples {
    final scores = <FortuneArea, int>{
      FortuneArea.love: FortuneScoreCalculator.dailyArea(widget.contextData, FortuneArea.love, FortuneScoreCalculator.standardBase(FortuneArea.love)),
      FortuneArea.work: FortuneScoreCalculator.dailyArea(widget.contextData, FortuneArea.work, FortuneScoreCalculator.standardBase(FortuneArea.work)),
      FortuneArea.money: FortuneScoreCalculator.dailyArea(widget.contextData, FortuneArea.money, FortuneScoreCalculator.standardBase(FortuneArea.money)),
      FortuneArea.mental: FortuneScoreCalculator.dailyArea(widget.contextData, FortuneArea.mental, FortuneScoreCalculator.standardBase(FortuneArea.mental)),
    };
    final strongest = scores.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    final focus = switch (strongest) {
      FortuneArea.love => '今日の恋愛運と連絡のタイミングは？',
      FortuneArea.work => '今日、いちばん進めると良い作業は？',
      FortuneArea.money => '今日、大きな買い物をしてもいい？',
      FortuneArea.mental => '今日、疲れをためない過ごし方は？',
      FortuneArea.overall => '今日の流れを活かす一手は？',
    };
    final profileText = '${widget.profile.theme} ${widget.details.concerns}'.toLowerCase();
    final profileExample = profileText.contains('youtube') || profileText.contains('動画') || profileText.contains('発信')
        ? '今日、動画を公開していい？'
        : profileText.contains('資格') || profileText.contains('勉強')
            ? '今週、資格の勉強を始めてもいい？'
            : profileText.contains('恋愛')
                ? '今月、出会いに向く時期は？'
                : '恋愛と仕事、今はどちらを優先する？';
    return [
      focus,
      profileExample,
      '今週、副業を始めてもいい？',
      '今月の金運と大きな買い物は？',
      '睡眠を整えるのに向く時期は？',
      '太陽が第1ハウスだと恋愛運は？',
    ].toSet().toList();
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialQuestion.trim().isNotEmpty) {
      _controller.text = widget.initialQuestion.trim();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _openQuestionKeyboard();
        widget.onInitialQuestionConsumed?.call();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _questionFocusNode.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  void _onQuestionChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _openQuestionKeyboard() {
    FocusScope.of(context).requestFocus(_questionFocusNode);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _questionFocusNode.hasFocus) {
        SystemChannels.textInput.invokeMethod<void>('TextInput.show');
      }
    });
  }

  @override
  void didUpdateWidget(covariant CustomReading oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldProfile = oldWidget.profile;
    final profileChanged = oldProfile.name != widget.profile.name ||
        oldProfile.birthDate != widget.profile.birthDate ||
        oldProfile.birthTime != widget.profile.birthTime ||
        oldProfile.birthPlace != widget.profile.birthPlace;
    if (profileChanged) {
      _controller.clear();
      _activeQuestion = null;
      setState(() => _chatLogs = const []);
    }
    if (oldWidget.initialQuestion != widget.initialQuestion && widget.initialQuestion.trim().isNotEmpty) {
      _controller.text = widget.initialQuestion.trim();
      _openQuestionKeyboard();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onInitialQuestionConsumed?.call();
      });
    }
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_chatScrollController.hasClients) return;
      _chatScrollController.animateTo(
        _chatScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _readCustomFortune() async {
    final question = _controller.text.trim();
    if (question.isEmpty || _loading) return;
    setState(() {
      _loading = true;
      _activeQuestion = question;
      _showNavigator = false;
    });
    _scrollToLatest();
    try {
      final contextHistory = CustomFortuneLog.forConversation(_chatLogs);
      // 画面の大きさで鑑定文の長さや処理内容を変えない。
      // タブレットでも、短く結論が分かるルールベース鑑定を返す。
      const compactForMobile = true;
      final answer = await const FortuneRuleService().createCustomFortune(
        profile: widget.profile,
        details: widget.details,
        question: question,
        contextData: widget.contextData,
        previousLogs: contextHistory,
        compactForMobile: compactForMobile,
      );
      final log = CustomFortuneLog(
        createdAt: DateTime.now(),
        question: question,
        answer: answer,
      );
      if (!mounted) return;
      setState(() {
        _chatLogs = [log, ..._chatLogs];
        _loading = false;
        _activeQuestion = null;
        _controller.clear();
      });
      _scrollToLatest();
    } catch (_) {
      if (!mounted) return;
      final failedLog = CustomFortuneLog(
        createdAt: DateTime.now(),
        question: question,
        answer: '鑑定を作成できませんでした。星データの計算中に問題が起きた可能性があります。もう一度送信しても直らない場合は、プロフィールを開き直してからお試しください。',
      );
      setState(() {
        _chatLogs = [failedLog, ..._chatLogs];
        _loading = false;
        _activeQuestion = null;
      });
      _scrollToLatest();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('鑑定を作成できませんでした。会話欄の案内をご確認ください。')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.sizeOf(context).shortestSide >= 600;
    final chronologicalLogs = _chatLogs.reversed.toList();
    return Padding(
      padding: EdgeInsets.fromLTRB(isTablet ? 24 : 16, 10, isTablet ? 24 : 16, 14),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.forum_outlined, color: Color(0xFF57D6D1)),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      '鑑定ナビ（会話式）',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                    ),
                  ),
                  IconButton(
                    tooltip: _showNavigator ? '鑑定ナビを閉じる' : '鑑定ナビを開く',
                    onPressed: () => setState(() => _showNavigator = !_showNavigator),
                    icon: Icon(_showNavigator ? Icons.expand_less : Icons.auto_awesome_outlined),
                  ),
                  IconButton(
                    tooltip: '質問例',
                    onPressed: _openQuestionExamples,
                    icon: const Icon(Icons.lightbulb_outline),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 初回はナビを表示し、送信後は回答を広く見せる。
              if (_showNavigator) ...[
                _consultationNavigator(isTablet),
                const SizedBox(height: 8),
              ],
              if (isTablet && chronologicalLogs.isEmpty && !_loading)
                const SizedBox(height: 0)
              else
                Expanded(
                  child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFF11172F).withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                  ),
                  child: ListView(
                    controller: _chatScrollController,
                    padding: EdgeInsets.all(isTablet ? 18 : 12),
                    children: [
                      if (chronologicalLogs.isEmpty)
                        ...[
                          _chatBubble(
                            text: '星の流れを踏まえて、続けて相談できます。恋愛の時期、向く仕事、今の選択などを聞いてください。',
                            isUser: false,
                            centered: true,
                          ),
                          // 鑑定ナビと重複する初期質問例は出さない。
                          // 追加の質問例は右上の電球ボタンから開ける。
                        ],
                      for (final log in chronologicalLogs) ...[
                        _chatBubble(text: log.question, isUser: true),
                        _chatBubble(
                          text: log.answer,
                          isUser: false,
                        ),
                      ],
                      if (_loading && _activeQuestion != null) ...[
                        _chatBubble(text: _activeQuestion!, isUser: true),
                        _chatBubble(text: '星の配置を確認しています…', isUser: false, waiting: true),
                      ],
                    ],
                  ),
                  ),
                ),
              const SizedBox(height: 10),
              Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (_) => _openQuestionKeyboard(),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _openQuestionKeyboard,
                  child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                  ),
                  padding: EdgeInsets.fromLTRB(12, isTablet ? 4 : 2, 4, isTablet ? 4 : 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          focusNode: _questionFocusNode,
                          onChanged: (_) => _onQuestionChanged(),
                          minLines: 1,
                          maxLines: isTablet ? 4 : 2,
                          maxLength: _maxQuestionLength,
                          keyboardType: isTablet ? TextInputType.multiline : TextInputType.text,
                          textInputAction: isTablet ? TextInputAction.newline : TextInputAction.send,
                          onSubmitted: isTablet ? null : (_) => _readCustomFortune(),
                          scrollPadding: const EdgeInsets.only(bottom: 92),
                          decoration: InputDecoration(
                            hintText: '${widget.profile.theme}について聞く',
                            counterText: '',
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      Tooltip(
                        message: '鑑定を送信',
                        child: IconButton.filled(
                          onPressed: _loading || _controller.text.trim().isEmpty
                              ? null
                              : _readCustomFortune,
                          icon: _loading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.send),
                        ),
                      ),
                    ],
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

  String _navigatorTopicLabel(ConsultationTopic topic) => switch (topic) {
        ConsultationTopic.overall => '総合運',
        ConsultationTopic.love => '恋愛',
        ConsultationTopic.work => '仕事',
        ConsultationTopic.money => '金運',
        ConsultationTopic.mental => '心と体',
      };

  String _navigatorQuestion({bool detailed = false}) {
    final topic = _navigatorTopicLabel(_navigatorTopic);
    final date = _navigatorDate;
    final dateLabel = '${date.year}/${date.month}/${date.day}';
    final situation = _navigatorSituation.label;
    final period = _navigatorPeriod.label;
    if (!detailed) {
      return switch (_navigatorMode) {
        ConsultationPromptMode.action => '今日の$topicで、今どう動くと良い？',
        ConsultationPromptMode.caution => '$dateLabelの$topicで、何に気をつけたらいい？',
        ConsultationPromptMode.timing => '今後3か月で$topicが動きやすい時期は？',
        ConsultationPromptMode.compare => '$topicで「今月始める」と「来月始める」は、どちらが良い？',
        ConsultationPromptMode.longTerm => '今後5年の$topicの流れと、育てるべきことは？',
      };
    }
    return switch (_navigatorMode) {
      ConsultationPromptMode.action => '$periodの$topicで、$situationを進めるために今どう動くと良い？',
      ConsultationPromptMode.caution => '$dateLabelの$topicで、$situationについて何に気をつけたらいい？',
      ConsultationPromptMode.timing => '$periodで、$topicの$situationが動きやすい時期は？',
      ConsultationPromptMode.compare => '$topicの$situationで「今月始める」と「来月始める」は、どちらが良い？',
      ConsultationPromptMode.longTerm => '$periodの$topicで、$situationの流れと育てるべきことは？',
    };
  }

  ConsultationPeriod _defaultPeriodFor(ConsultationPromptMode mode) => switch (mode) {
        ConsultationPromptMode.action => ConsultationPeriod.today,
        ConsultationPromptMode.caution => ConsultationPeriod.today,
        ConsultationPromptMode.timing => ConsultationPeriod.threeMonths,
        ConsultationPromptMode.compare => ConsultationPeriod.month,
        ConsultationPromptMode.longTerm => ConsultationPeriod.fiveYears,
      };

  Future<void> _selectNavigatorDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _navigatorDate,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 10),
      helpText: '注意点を見たい日を選択',
      cancelText: '閉じる',
      confirmText: '決定',
    );
    if (selected == null || !mounted) return;
    setState(() => _navigatorDate = selected);
  }

  void _sendNavigatorQuestion() {
    final question = _navigatorQuestion(
      detailed: MediaQuery.sizeOf(context).shortestSide >= 600,
    );
    _controller.text = question;
    _controller.selection = TextSelection.collapsed(offset: question.length);
    _readCustomFortune();
  }

  Widget _consultationNavigator(bool isTablet) {
    final preview = _navigatorQuestion(detailed: isTablet);
    final topicChips = Wrap(
      spacing: 6,
      runSpacing: 6,
      children: ConsultationTopic.values.map((topic) => ChoiceChip(
        label: Text(topic.label),
        selected: _navigatorTopic == topic,
        onSelected: (_) => setState(() => _navigatorTopic = topic),
        visualDensity: VisualDensity.compact,
      )).toList(),
    );
    final situationChips = Wrap(
      spacing: 6,
      runSpacing: 6,
      children: ConsultationSituation.values.map((situation) => ChoiceChip(
        label: Text(situation.label),
        selected: _navigatorSituation == situation,
        onSelected: (_) => setState(() => _navigatorSituation = situation),
        visualDensity: VisualDensity.compact,
      )).toList(),
    );
    final modeChips = Wrap(
      spacing: 6,
      runSpacing: 6,
      children: ConsultationPromptMode.values.map((mode) => ChoiceChip(
        label: Text(mode.label),
        selected: _navigatorMode == mode,
        onSelected: (_) => setState(() {
          _navigatorMode = mode;
          _navigatorPeriod = _defaultPeriodFor(mode);
        }),
        visualDensity: VisualDensity.compact,
      )).toList(),
    );
    final periodChips = Wrap(
      spacing: 6,
      runSpacing: 6,
      children: ConsultationPeriod.values.map((period) => ChoiceChip(
        label: Text(period.label),
        selected: _navigatorPeriod == period,
        onSelected: (_) => setState(() => _navigatorPeriod = period),
        visualDensity: VisualDensity.compact,
      )).toList(),
    );
    return GlassPanel(
      padding: EdgeInsets.all(isTablet ? 16 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome_outlined, color: Color(0xFFF6D77A), size: 20),
              SizedBox(width: 8),
              Text('鑑定ナビ', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'テーマ・期間・知りたい結論を選ぶと、会話のまま星の根拠と行動まで詳しく読めます。',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.66), fontSize: 12, height: 1.35),
          ),
          const SizedBox(height: 10),
          const SizedBox(height: 10),
          if (isTablet)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('テーマ', style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 12, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 5),
                  topicChips,
                  const SizedBox(height: 9),
                  Text('いまの状況', style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 12, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 5),
                  situationChips,
                ])),
                const SizedBox(width: 22),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('知りたい結論', style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 12, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 5),
                  modeChips,
                  const SizedBox(height: 9),
                  Text('対象期間', style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 12, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 5),
                  periodChips,
                ])),
              ],
            )
          else ...[
            Text('テーマ', style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 12, fontWeight: FontWeight.w800)),
            const SizedBox(height: 5),
            topicChips,
            const SizedBox(height: 9),
            Text('聞きたいこと', style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 12, fontWeight: FontWeight.w800)),
            const SizedBox(height: 5),
            modeChips,
            const SizedBox(height: 9),
            Text('対象期間', style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 12, fontWeight: FontWeight.w800)),
            const SizedBox(height: 5),
            periodChips,
          ],
          if (_navigatorMode == ConsultationPromptMode.caution) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _selectNavigatorDate,
              icon: const Icon(Icons.calendar_today_outlined, size: 16),
              label: Text('${_navigatorDate.year}/${_navigatorDate.month}/${_navigatorDate.day} を選択中'),
            ),
          ],
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: const Color(0xFF0D2745).withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text('質問: $preview', style: const TextStyle(fontSize: 12, height: 1.35)),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _loading ? null : _sendNavigatorQuestion,
              icon: const Icon(Icons.auto_awesome_outlined, size: 18),
              label: const Text('この内容で鑑定'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chatBubble({
    required String text,
    required bool isUser,
    bool waiting = false,
    Widget? action,
    bool centered = false,
  }) {
    return Align(
      alignment: centered
          ? Alignment.center
          : isUser
              ? Alignment.centerRight
              : Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: centered ? 0.86 : isUser ? 0.82 : 0.92,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isUser
                ? const Color(0xFF315C93).withValues(alpha: 0.86)
                : const Color(0xFF252A4A).withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(8),
          ),
          child: action == null
              ? Text(
                  text,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: waiting ? 0.72 : 0.94),
                    height: 1.55,
                    fontSize: 14,
                  ),
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        text,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: waiting ? 0.72 : 0.94),
                          height: 1.55,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    action,
                  ],
                ),
        ),
      ),
    );
  }

  Widget _questionExampleChips() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _questionExamples
            .map(
              (example) => ActionChip(
                label: Text(example),
                labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                visualDensity: VisualDensity.compact,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
                backgroundColor: const Color(0xFF1B3455).withValues(alpha: 0.72),
                onPressed: () => _selectQuestionExample(example),
              ),
            )
            .toList(),
      ),
    );
  }

  void _selectQuestionExample(String example) {
    _controller.text = example;
    _controller.selection = TextSelection.collapsed(offset: example.length);
    _onQuestionChanged();
    _openQuestionKeyboard();
  }

  Future<void> _openQuestionExamples() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF151B35),
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          children: [
            const ListTile(
              leading: Icon(Icons.lightbulb_outline, color: Color(0xFFF6D77A)),
              title: Text('質問例', style: TextStyle(fontWeight: FontWeight.w900)),
              subtitle: Text('選ぶと入力欄へ入ります。送信前に自由に直せます。'),
            ),
            for (final example in _questionExamples)
              ListTile(
                leading: const Icon(Icons.chat_bubble_outline, size: 20),
                title: Text(example),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).pop(example),
              ),
          ],
        ),
      ),
    );
    if (!mounted || selected == null) return;
    _selectQuestionExample(selected);
  }

}

class ProfileView extends StatelessWidget {
  const ProfileView({
    super.key,
    required this.profile,
    required this.details,
    required this.onSaved,
  });

  final AstroProfile profile;
  final UserProfileDetails details;
  final ValueChanged<SavedUserProfile> onSaved;

  @override
  Widget build(BuildContext context) {
    return ReadingPage(
      title: 'プロフィール',
      subtitle: '占星術の読みをあなた向けに整える情報',
      children: [
        ReadingCard(
          title: '${profile.name}さんの基本情報',
          body:
              '生年月日 ${profile.birthDate} / 出生時間 ${profile.birthTime}${details.hasBirthTime ? '' : '（仮）'} / 出生地 ${profile.birthPlace}${details.hasBirthPlace ? '' : '（仮）'}。出生時間と出生地を保存すると、月とハウスの読みが安定します。',
          icon: Icons.badge_outlined,
        ),
        const FortuneSafetyNoticeCard(),
        ProfileForm(
          profile: profile,
          initialDetails: details,
          onSaved: onSaved,
        ),
        const HouseSystemSelector(),
        ProfileAstroJsonExportCard(profile: profile, details: details),
        ProfileDataUtilityCard(profile: profile),
        const AppLicenseInfoCard(),
        const CreatorProfileCard(),
      ],
    );
  }
}

class ProfileAstroJsonExportCard extends StatefulWidget {
  const ProfileAstroJsonExportCard({super.key, required this.profile, required this.details});
  final AstroProfile profile;
  final UserProfileDetails details;

  @override
  State<ProfileAstroJsonExportCard> createState() => _ProfileAstroJsonExportCardState();
}

class _ProfileAstroJsonExportCardState extends State<ProfileAstroJsonExportCard> {
  late DateTime _selectedDay;
  late DateTime _selectedMonth;
  late int _selectedYear;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDay = DateTime(now.year, now.month, now.day);
    _selectedMonth = DateTime(now.year, now.month);
    _selectedYear = now.year;
  }

  HoroscopeReadingContext _context(DateTime date) => const AstrologyEngine().buildPreviewContext(
        profile: widget.profile,
        date: DateTime(date.year, date.month, date.day, 12),
      );

  Future<void> _pickDay() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedDay,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100, 12, 31),
      helpText: '詳しく相談したい日を選択',
      cancelText: '閉じる',
      confirmText: '決定',
    );
    if (selected != null && mounted) {
      setState(() => _selectedDay = DateTime(selected.year, selected.month, selected.day));
    }
  }

  Future<void> _pickMonth() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100, 12, 31),
      helpText: '相談したい月を選択',
      cancelText: '閉じる',
      confirmText: 'この月にする',
    );
    if (selected != null && mounted) {
      setState(() => _selectedMonth = DateTime(selected.year, selected.month));
    }
  }

  Future<void> _pickYear() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: DateTime(_selectedYear),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100, 12, 31),
      initialDatePickerMode: DatePickerMode.year,
      helpText: '相談したい年を選択',
      cancelText: '閉じる',
      confirmText: 'この年にする',
    );
    if (selected != null && mounted) setState(() => _selectedYear = selected.year);
  }

  Future<void> _daily() {
    final date = DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day, 12);
    return DailyAstroDataExportCard(
      date: date,
      profile: widget.profile,
      details: widget.details,
      contextData: _context(date),
    )._export(context);
  }

  Future<void> _period(LongRangeMode mode) {
    final month = DateTime(_selectedMonth.year, _selectedMonth.month, 1, 12);
    final year = _selectedYear;
    return ExternalAstroDataExportCard(
      mode: mode,
      periodLabel: mode == LongRangeMode.month ? '${month.year}年${month.month}月' : '$year年',
      weekStart: month,
      month: month,
      year: year,
      profile: widget.profile,
      details: widget.details,
      contextData: _context(mode == LongRangeMode.month ? month : DateTime(year, 1, 1, 12)),
      cards: const [],
    )._export(context);
  }

  String _dayLabel(DateTime value) => '${value.year}年${value.month}月${value.day}日';
  String _monthLabel(DateTime value) => '${value.year}年${value.month}月';

  @override
  Widget build(BuildContext context) => GlassPanel(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _SmallSectionLabel(icon: Icons.chat_bubble_outline, text: 'AIチャットで詳しく相談するための占いデータ'),
          const SizedBox(height: 8),
          Text('ChatGPTなどへファイルを添えて相談したい時に使います。日・月・年を選ぶと、その期間の詳しい占いデータを作れます。', style: TextStyle(color: Colors.white.withValues(alpha: 0.68), fontSize: 12, height: 1.45)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(onPressed: _pickDay, icon: const Icon(Icons.event_outlined, size: 18), label: Text('対象日: ${_dayLabel(_selectedDay)}')),
            FilledButton.icon(onPressed: _daily, icon: const Icon(Icons.today_outlined, size: 18), label: const Text('この日の詳しい占いデータを作る')),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(onPressed: _pickMonth, icon: const Icon(Icons.event_note_outlined, size: 18), label: Text('対象月: ${_monthLabel(_selectedMonth)}')),
            FilledButton.icon(onPressed: () => _period(LongRangeMode.month), icon: const Icon(Icons.calendar_month_outlined, size: 18), label: const Text('この月の毎日占いデータを作る')),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(onPressed: _pickYear, icon: const Icon(Icons.date_range_outlined, size: 18), label: Text('対象年: $_selectedYear年')),
            FilledButton.icon(onPressed: () => _period(LongRangeMode.year), icon: const Icon(Icons.auto_graph_outlined, size: 18), label: const Text('この年の年運データを作る')),
          ]),
        ]),
      );
}

class ProfileDataUtilityCard extends StatelessWidget {
  const ProfileDataUtilityCard({super.key, required this.profile});
  final AstroProfile profile;

  Future<void> _export(BuildContext context) async {
    var progressOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(children: [SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 14), Expanded(child: Text('バックアップJSONを出力中…'))]),
        ),
      ),
    );
    try {
      // ダイアログが確実に見えてからバックアップを組み立てる。
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 120));
      final text = await AppDataBackup.exportJson();
      await Clipboard.setData(ClipboardData(text: text));
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}${Platform.pathSeparator}pancyo_ai_astrology_backup_${DateTime.now().millisecondsSinceEpoch}.json');
      await file.writeAsString(text, flush: true);
      if (context.mounted && progressOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        progressOpen = false;
      }
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'ぱんちょ式星占い バックアップ',
        text: 'ぱんちょ式星占いのバックアップです。',
      );
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('バックアップJSONを共有しました。内容はクリップボードにもコピー済みです。')));
    } catch (_) {
      if (context.mounted && progressOpen) Navigator.of(context, rootNavigator: true).pop();
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('バックアップJSONを出力できませんでした。')));
    }
  }

  Future<void> _restore(BuildContext context) async {
    final controller = TextEditingController();
    final pasted = await Clipboard.getData(Clipboard.kTextPlain);
    controller.text = pasted?.text ?? '';
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('バックアップを復元'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('バックアップJSONの中身を全選択して貼り付けます。現在の保存プロフィールと共有設定はバックアップ内容で置き換わります。', style: TextStyle(fontSize: 13, height: 1.4)),
          const SizedBox(height: 12),
          TextField(controller: controller, maxLines: 8, decoration: const InputDecoration(hintText: 'バックアップJSONを貼り付け')),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')), FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('置き換えて復元'))],
      ),
    );
    controller.dispose();
    if (value == null || value.trim().isEmpty) return;
    try {
      await AppDataBackup.restoreJson(value);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('復元しました。プロフィール画面を開き直すと反映されます。')));
    } catch (_) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('バックアップを確認できませんでした。')));
    }
  }

  Future<void> _copyBugReport(BuildContext context) async {
    final size = MediaQuery.sizeOf(context);
    final report = [
      'ぱんちょ式星占い 不具合報告',
      '日時: ${DateTime.now().toIso8601String()}',
      '画面: プロフィール',
      '人物: ${profile.name}',
      'Android: ${Platform.operatingSystemVersion}',
      '端末CPU: ${Platform.numberOfProcessors} cores',
      '画面: ${size.width.toStringAsFixed(0)} x ${size.height.toStringAsFixed(0)} dp',
      '起きたこと: ',
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: report));
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('不具合報告のひな形をコピーしました。')));
  }

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      margin: const EdgeInsets.only(bottom: 14), padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _SmallSectionLabel(icon: Icons.folder_copy_outlined, text: 'データと不具合報告'),
        const SizedBox(height: 8),
        Text('保存プロフィールと共有カード設定をJSONファイルへバックアップできます。復元はファイル内の文字を全選択して貼り付けます。', style: TextStyle(color: Colors.white.withValues(alpha: 0.68), fontSize: 12, height: 1.45)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(onPressed: () => _export(context), icon: const Icon(Icons.upload_file_outlined, size: 18), label: const Text('バックアップ')),
          OutlinedButton.icon(onPressed: () => _restore(context), icon: const Icon(Icons.settings_backup_restore_outlined, size: 18), label: const Text('復元')),
          OutlinedButton.icon(onPressed: () => _copyBugReport(context), icon: const Icon(Icons.bug_report_outlined, size: 18), label: const Text('不具合報告をコピー')),
        ]),
        const SizedBox(height: 10),
        Text('不具合報告: コピー後に、このチャットや連絡先へ貼り付けてください。起きたこと、操作手順、可能ならスクリーンショットも添えると確認が早くなります。', style: TextStyle(color: Colors.white.withValues(alpha: 0.62), fontSize: 11, height: 1.45)),
      ]),
    );
  }
}

class AppDataBackup {
  const AppDataBackup._();
  static const _keys = [
    SavedUserProfile._storageKey,
    UserProfileDetails._birthTimeKey,
    UserProfileDetails._birthPlaceKey,
    UserProfileDetails._personalityKey,
    UserProfileDetails._concernsKey,
    UserProfileDetails._readingStyleKey,
    'share_card_display_name', 'share_card_show_score', 'share_card_show_body', 'share_card_theme',
    'astrology.house_system',
  ];
  static Future<String> exportJson() async {
    final prefs = await SharedPreferences.getInstance();
    final values = <String, dynamic>{};
    for (final key in _keys) {
      if (prefs.containsKey(key)) values[key] = prefs.get(key);
    }
    return jsonEncode({'format': 'pancyo-astrology-backup', 'version': 1, 'createdAt': DateTime.now().toIso8601String(), 'values': values});
  }
  static Future<void> restoreJson(String source) async {
    final decoded = jsonDecode(source);
    final format = decoded is Map ? decoded['format'] : null;
    // 旧バックアップは復元できるようにしつつ、新規出力はAI表記を使わない。
    if (decoded is! Map ||
        (format != 'pancyo-astrology-backup' && format != 'pancyo-ai-astrology-backup') ||
        decoded['values'] is! Map) {
      throw const FormatException();
    }
    final prefs = await SharedPreferences.getInstance();
    final values = Map<String, dynamic>.from(decoded['values'] as Map);
    for (final key in _keys) {
      await prefs.remove(key);
      final value = values[key];
      if (value == null) continue;
      if (value is String) await prefs.setString(key, value);
      if (value is bool) await prefs.setBool(key, value);
      if (value is int) await prefs.setInt(key, value);
      if (value is double) await prefs.setDouble(key, value);
    }
    await prefs.reload();
    await HouseSystemSettings.restore();
  }
}

class FortuneSafetyNoticeCard extends StatelessWidget {
  const FortuneSafetyNoticeCard({super.key});

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SmallSectionLabel(
            icon: Icons.volunteer_activism_outlined,
            text: '占いとの付き合い方',
          ),
          const SizedBox(height: 10),
          Text(
            'このアプリの占いは、毎日を少し見つめ直すためのヒントです。結果の通りにしなければいけないものではなく、人生の大切な判断を代わりに決めるものでもありません。',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.74),
              height: 1.48,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          _SafetyNoticeLine(
            icon: Icons.balance_outlined,
            text: '恋愛、仕事、お金、人間関係の判断は、現実の状況と自分の意思を優先してください。',
          ),
          _SafetyNoticeLine(
            icon: Icons.health_and_safety_outlined,
            text: '医療、法律、投資、緊急性のある悩みは、必ず専門家や公的な相談先を頼ってください。',
          ),
          _SafetyNoticeLine(
            icon: Icons.self_improvement_outlined,
            text: '不安が強い時、占いを見るほど苦しくなる時は、少し距離を置いて休むことも大切です。',
          ),
        ],
      ),
    );
  }
}

class _SafetyNoticeLine extends StatelessWidget {
  const _SafetyNoticeLine({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: const Color(0xFFF6D77A).withValues(alpha: 0.84)),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.64),
                fontSize: 12,
                height: 1.45,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ProfileForm extends StatefulWidget {
  const ProfileForm({
    super.key,
    required this.profile,
    required this.initialDetails,
    required this.onSaved,
  });

  final AstroProfile profile;
  final UserProfileDetails initialDetails;
  final ValueChanged<SavedUserProfile> onSaved;

  @override
  State<ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends State<ProfileForm> {
  late final TextEditingController _birthTimeController;
  late final TextEditingController _birthPlaceController;
  late final TextEditingController _personalityController;
  late final TextEditingController _concernsController;
  late final TextEditingController _readingStyleController;
  late bool _useSupplement;
  bool _saving = false;

  static const _placeSuggestions = [
    '北海道札幌市',
    '東京都',
    '大阪府大阪市',
    '神奈川県横浜市',
    '愛知県名古屋市',
  ];

  static const _regionalPlaceSuggestions = <String, List<String>>{
    '北海道': [
      '北海道札幌市', '北海道旭川市', '北海道函館市', '北海道釧路市',
      '北海道帯広市', '北海道北見市', '北海道苫小牧市', '北海道小樽市',
      '北海道千歳市', '北海道網走市', '北海道稚内市', '北海道根室市',
    ],
    '東北': [
      '青森県青森市', '青森県八戸市', '岩手県盛岡市', '宮城県仙台市',
      '秋田県秋田市', '山形県山形市', '福島県福島市', '福島県郡山市', '福島県いわき市',
    ],
    '関東': [
      '茨城県水戸市', '茨城県つくば市', '栃木県宇都宮市', '群馬県高崎市',
      '埼玉県さいたま市', '埼玉県川越市', '千葉県千葉市', '千葉県船橋市',
      '東京都', '東京都八王子市', '神奈川県横浜市', '神奈川県川崎市', '神奈川県相模原市',
    ],
    '中部': [
      '新潟県新潟市', '新潟県長岡市', '富山県富山市', '石川県金沢市',
      '福井県福井市', '山梨県甲府市', '長野県松本市', '岐阜県岐阜市',
      '静岡県静岡市', '静岡県浜松市', '愛知県名古屋市', '愛知県豊田市',
    ],
    '近畿': [
      '三重県津市', '滋賀県大津市', '京都府京都市', '大阪府大阪市',
      '大阪府堺市', '兵庫県神戸市', '兵庫県姫路市', '奈良県奈良市', '和歌山県和歌山市',
    ],
    '中国': [
      '鳥取県鳥取市', '島根県松江市', '島根県出雲市', '岡山県岡山市',
      '岡山県倉敷市', '広島県広島市', '広島県福山市', '山口県山口市', '山口県下関市',
    ],
    '四国': [
      '徳島県徳島市', '香川県高松市', '愛媛県松山市', '高知県高知市',
    ],
    '九州・沖縄': [
      '福岡県福岡市', '佐賀県佐賀市', '長崎県長崎市', '熊本県熊本市',
      '大分県大分市', '宮崎県宮崎市', '鹿児島県鹿児島市', '沖縄県那覇市',
    ],
  };

  @override
  void initState() {
    super.initState();
    _birthTimeController = TextEditingController(text: widget.initialDetails.birthTime);
    _birthPlaceController = TextEditingController(
      text: widget.initialDetails.hasBirthPlace
          ? widget.initialDetails.birthPlace
          : widget.profile.birthPlace,
    );
    _personalityController = TextEditingController(text: widget.initialDetails.storedPersonality);
    _concernsController = TextEditingController(text: widget.initialDetails.storedConcerns);
    _readingStyleController = TextEditingController(text: widget.initialDetails.storedReadingStyle);
    _useSupplement = widget.initialDetails.useSupplement;
    _birthPlaceController.addListener(_refreshPlaceState);
  }

  @override
  void didUpdateWidget(covariant ProfileForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialDetails != widget.initialDetails) {
      _birthTimeController.text = widget.initialDetails.birthTime;
      _birthPlaceController.text = widget.initialDetails.hasBirthPlace
          ? widget.initialDetails.birthPlace
          : widget.profile.birthPlace;
      _personalityController.text = widget.initialDetails.storedPersonality;
      _concernsController.text = widget.initialDetails.storedConcerns;
      _readingStyleController.text = widget.initialDetails.storedReadingStyle;
      _useSupplement = widget.initialDetails.useSupplement;
    }
  }

  @override
  void dispose() {
    _birthPlaceController.removeListener(_refreshPlaceState);
    _birthTimeController.dispose();
    _birthPlaceController.dispose();
    _personalityController.dispose();
    _concernsController.dispose();
    _readingStyleController.dispose();
    super.dispose();
  }

  void _refreshPlaceState() {
    if (mounted) setState(() {});
  }

  Future<void> _pickBirthTime() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final initial = _timeFromText() ?? const TimeOfDay(hour: 12, minute: 0);
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: '出生時間を選択',
      cancelText: '閉じる',
      confirmText: '決定',
    );
    if (picked == null) return;
    if (!mounted) return;
    _birthTimeController.text =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
  }

  TimeOfDay? _timeFromText() {
    final match = RegExp(r'(\d{1,2})\D+(\d{1,2})').firstMatch(_birthTimeController.text);
    if (match == null) return null;
    final hour = int.tryParse(match.group(1) ?? '');
    final minute = int.tryParse(match.group(2) ?? '');
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  void _setBirthPlace(String place) {
    _birthPlaceController.text = place;
  }

  void _finishBirthPlaceInput(String _) {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_saving) _save();
  }

  bool get _birthPlaceNeedsWarning {
    final value = _birthPlaceController.text.trim();
    if (value.isEmpty) return false;
    return !_birthPlaceIsKnown(value);
  }

  bool _birthPlaceIsKnown(String value) {
    if (_coordinateFromText(value)) return true;
    for (final place in _placeSuggestions) {
      if (value.contains(place) || place.contains(value)) return true;
    }
    return RegExp(
      r'(北海道|札幌|旭川|函館|釧路|帯広|北見|苫小牧|小樽|江別|千歳|北広島|室蘭|岩見沢|網走|稚内|根室|小清水|美和|青森県|岩手県|宮城県|秋田県|山形県|福島県|茨城県|栃木県|群馬県|埼玉県|千葉県|東京都|神奈川県|新潟県|富山県|石川県|福井県|山梨県|長野県|岐阜県|静岡県|愛知県|三重県|滋賀県|京都府|大阪府|兵庫県|奈良県|和歌山県|鳥取県|島根県|岡山県|広島県|山口県|徳島県|香川県|愛媛県|高知県|福岡県|佐賀県|長崎県|熊本県|大分県|宮崎県|鹿児島県|沖縄県|東京|大阪|福岡)',
    ).hasMatch(value);
  }

  bool _coordinateFromText(String value) {
    final match = RegExp(r'(-?\d+(?:\.\d+)?)\s*[,、]\s*(-?\d+(?:\.\d+)?)').firstMatch(value);
    if (match == null) return false;
    final latitude = double.tryParse(match.group(1)!);
    final longitude = double.tryParse(match.group(2)!);
    if (latitude == null || longitude == null) return false;
    return latitude.abs() <= 90 && longitude.abs() <= 180;
  }

  Future<bool> _save({String successMessage = 'プロフィールを保存しました'}) async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_birthTimeController.text.trim().isNotEmpty && _timeFromText() == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('出生時間を00:00〜23:59で入力してください。')),
      );
      return false;
    }
    setState(() => _saving = true);
    final details = UserProfileDetails(
      birthTime: _birthTimeController.text.trim(),
      birthPlace: _birthPlaceController.text.trim(),
      personality: _personalityController.text.trim(),
      concerns: _concernsController.text.trim(),
      readingStyle: _readingStyleController.text.trim(),
      useSupplement: _useSupplement,
    );
    try {
      await details.save();
      final savedProfile = SavedUserProfile.fromProfile(
        widget.profile.copyWith(
          birthTime: details.effectiveBirthTime,
          birthPlace: details.effectiveBirthPlace,
        ),
        details,
      );
      await savedProfile.save();
      if (!mounted) return false;
      setState(() => _saving = false);
      widget.onSaved(savedProfile);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMessage)),
      );
      return true;
    } catch (_) {
      if (!mounted) return false;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('プロフィールを保存できませんでした。もう一度お試しください。')),
      );
      return false;
    }
  }

  Future<void> _setUseSupplement(bool value) async {
    if (_saving || value == _useSupplement) return;
    setState(() => _useSupplement = value);
    // この切替は「占い文を今すぐ切り替える」ための設定なので、
    // 下の保存ボタンを押し忘れても元に戻らないよう即時保存する。
    final saved = await _save(
      successMessage: value
          ? '趣味・悩みなどの反映をオンにしました'
          : '趣味・悩みなどの反映をオフにしました',
    );
    if (!saved && mounted) setState(() => _useSupplement = !value);
  }

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'あとで追加するプロフィール',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            '出生時間と出生地を書くと、月とハウスの読みが安定します。北海道の主要都市名は内部座標へ自動変換します。未入力や未対応住所の時は12:00・北海道札幌市で仮計算します。',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.68), height: 1.45),
          ),
          const SizedBox(height: 16),
          ProfileTextField(
            controller: _birthTimeController,
            label: '出生時間',
            hint: 'タップして選択 / 不明なら空欄',
            onTap: _pickBirthTime,
            suffixIcon: Icons.schedule_outlined,
          ),
          ProfileTextField(
            controller: _birthPlaceController,
            label: '出生地',
            hint: '市区町村名・住所・緯度経度 / 例）北海道釧路市',
            minLines: 1,
            maxLines: 1,
            textInputAction: TextInputAction.done,
            onSubmitted: _finishBirthPlaceInput,
          ),
          BirthPlaceQuickSelect(
            suggestions: _placeSuggestions,
            regionalSuggestions: _regionalPlaceSuggestions,
            onSelected: _setBirthPlace,
          ),
          if (_birthPlaceNeedsWarning) const BirthPlaceWarning(),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _useSupplement,
            onChanged: _saving ? null : _setUseSupplement,
            title: const Text('趣味・悩みなどを占いへ反映する'),
            subtitle: Text(
              _useSupplement
                  ? 'オン：趣味・悩み・希望する文体を占い文へ加えます。切替は自動保存されます。'
                  : 'オフ：入力内容は残しますが、占い文には使いません。切替は自動保存されます。',
            ),
          ),
          ProfileTextField(
            controller: _personalityController,
            label: '性格・大切にしていること',
            hint: '例）慎重だけど、好きなことには一気に集中する',
          ),
          ProfileTextField(
            controller: _concernsController,
            label: '今の悩み・気になっているテーマ',
            hint: '例）仕事の方向性、恋愛、人間関係、お金の使い方',
          ),
          ProfileTextField(
            controller: _readingStyleController,
            label: '占いで特に見てほしいこと',
            hint: '例）背中を押してほしい / 現実的に整理してほしい',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_saving ? '保存中' : 'プロフィールを保存'),
          ),
        ],
      ),
    );
  }
}

class HouseSystemSelector extends StatelessWidget {
  const HouseSystemSelector({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<HouseSystem>(
      valueListenable: HouseSystemSettings.current,
      builder: (context, selected, _) {
        return GlassPanel(
          margin: const EdgeInsets.only(top: 14),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SmallSectionLabel(
                icon: Icons.grid_view_outlined,
                text: 'ハウス方式',
              ),
              const SizedBox(height: 8),
              Text(
                '出生地と出生時刻が入力されている時の、天体が入るハウスの計算方法です。Placidusを標準にしています。',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.70),
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<HouseSystem>(
                segments: HouseSystem.values
                    .map(
                      (system) => ButtonSegment<HouseSystem>(
                        value: system,
                        label: Text(system.label),
                      ),
                    )
                    .toList(),
                selected: {selected},
                onSelectionChanged: (value) => HouseSystemSettings.save(value.first),
              ),
              const SizedBox(height: 8),
              Text(
                selected.description,
                style: const TextStyle(
                  color: Color(0xFFF6D77A),
                  fontSize: 12,
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SmallStatusPill extends StatelessWidget {
  const _SmallStatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF57D6D1).withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF57D6D1),
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class AppLicenseInfoCard extends StatelessWidget {
  const AppLicenseInfoCard({super.key});

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _LicenseHeader(),
          const SizedBox(height: 10),
          const Text(
            'Android版の星計算にはSwiss Ephemeris Free Editionを使います。このアプリはAGPL条件に合わせ、ソース公開前提で整備しています。',
            style: TextStyle(
              color: Color(0xB8FFFFFF),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          const SizedBox(height: 12),
          const _LicenseStatusRow(
            title: '星データ',
            status: 'AGPL',
            note: 'Swiss Ephemeris Free EditionをAndroidネイティブ組み込み。公式ソースはthird_party/swissephに配置済み。',
          ),
          const _LicenseStatusRow(
            title: 'アプリ本体',
            status: 'AGPL',
            note: 'Swiss EphemerisのAGPL条件に合わせ、配布時は対応するソースコードを公開します。',
          ),
          const _LicenseStatusRow(
            title: 'Flutter / ライブラリ',
            status: '確認対象',
            note: '使用パッケージとライセンス表記をリリース前に一覧化します。',
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              _CreatorLinkButton(
                icon: Icons.travel_explore_outlined,
                label: 'Swiss公式',
                url: 'https://www.astro.com/swisseph/',
              ),
              _CreatorLinkButton(
                icon: Icons.code_outlined,
                label: 'アプリのソース',
                url: 'https://github.com/pancyo/pancyo_ai_astrology',
              ),
              _CreatorLinkButton(
                icon: Icons.code_outlined,
                label: 'Swissソース',
                url: 'https://github.com/aloistr/swisseph',
              ),
              _CreatorLinkButton(
                icon: Icons.policy_outlined,
                label: 'AGPL',
                url: 'https://www.gnu.org/licenses/agpl-3.0.html',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LicenseHeader extends StatelessWidget {
  const _LicenseHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        Icon(Icons.verified_user_outlined, color: Color(0xFFF6D77A)),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'ライセンス情報',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

class _LicenseStatusRow extends StatelessWidget {
  const _LicenseStatusRow({
    required this.title,
    required this.status,
    required this.note,
  });

  final String title;
  final String status;
  final String note;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFF6D77A).withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF6D77A).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              status,
              style: const TextStyle(
                color: Color(0xFFF6D77A),
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  note,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.58),
                    fontSize: 12,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CustomFortuneLogPanel extends StatefulWidget {
  const CustomFortuneLogPanel({super.key, required this.profile});

  final AstroProfile profile;

  @override
  State<CustomFortuneLogPanel> createState() => _CustomFortuneLogPanelState();
}

class _CustomFortuneLogPanelState extends State<CustomFortuneLogPanel>
    with WidgetsBindingObserver {
  late Future<List<CustomFortuneLog>> _future;
  List<CustomFortuneLog>? _visibleLogs;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _future = CustomFortuneLog.loadAll(profileId: CustomFortuneLog.profileIdFor(widget.profile));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reloadLogs();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CustomFortuneLogPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (CustomFortuneLog.profileIdFor(oldWidget.profile) !=
        CustomFortuneLog.profileIdFor(widget.profile)) {
      _reloadLogs();
    }
  }

  Future<void> _reloadLogs() async {
    final logs = await CustomFortuneLog.loadAll(
      profileId: CustomFortuneLog.profileIdFor(widget.profile),
    );
    if (!mounted) return;
    setState(() {
      _visibleLogs = logs;
      _future = Future.value(logs);
    });
  }

  Future<void> _clearLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${widget.profile.name}さんの鑑定ログを消去しますか？'),
        content: const Text('この人物のチャット式カスタム鑑定ログだけをすべて削除します。この操作は元に戻せません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('消去'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await CustomFortuneLog.clear(profileId: CustomFortuneLog.profileIdFor(widget.profile));
    if (!mounted) return;
    await _reloadLogs();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('チャット式カスタム鑑定ログを消去しました')),
    );
  }

  Future<void> _openHistory(List<CustomFortuneLog> logs) async {
    final remaining = await showModalBottomSheet<List<CustomFortuneLog>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CustomFortuneLogHistorySheet(
        initialLogs: logs,
        profileName: widget.profile.name,
        onChanged: (remaining) async {
          if (!mounted) return;
          final next = List.of(remaining);
          setState(() {
            _visibleLogs = next;
            _future = Future.value(next);
          });
        },
      ),
    );
    if (!mounted) return;
    if (remaining != null) {
      final next = List.of(remaining);
      setState(() {
        _visibleLogs = next;
        _future = Future.value(next);
      });
    }
    // 履歴シートを閉じた後は、端末保存側の最新状態でも再確認する。
    await _reloadLogs();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CustomFortuneLog>>(
      key: ValueKey(_future),
      future: _future,
      builder: (context, snapshot) {
        final logs = _visibleLogs ?? snapshot.data ?? const <CustomFortuneLog>[];
        return GlassPanel(
          margin: const EdgeInsets.only(top: 14),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.history, color: Color(0xFFF6D77A)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${widget.profile.name}さんのチャット式カスタム鑑定ログ',
                      maxLines: 2,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                  ),
                  if (logs.isNotEmpty)
                    TextButton.icon(
                      onPressed: _clearLogs,
                      icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                      label: const Text('全消去'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFFF82B2),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                logs.isEmpty
                    ? 'この人物のチャット式カスタム鑑定を使うと、ここに相談内容と鑑定結果が残ります。'
                    : 'この人物のログだけを最大${CustomFortuneLog.maxEntries}件保存します。全件を開くと、質問と回答を最後まで読み返せます。',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.66), height: 1.45),
              ),
              if (logs.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  '保存: ${logs.length}/${CustomFortuneLog.maxEntries}件',
                  style: TextStyle(
                    color: const Color(0xFFF6D77A).withValues(alpha: 0.78),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _openHistory(logs),
                    icon: const Icon(Icons.open_in_full, size: 18),
                    label: const Text('すべて見る'),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class CustomFortuneLogTile extends StatelessWidget {
  const CustomFortuneLogTile({
    super.key,
    required this.log,
    this.expanded = false,
    this.onDelete,
  });

  final CustomFortuneLog log;
  final bool expanded;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final date =
        '${log.createdAt.year}/${log.createdAt.month}/${log.createdAt.day} ${log.createdAt.hour.toString().padLeft(2, '0')}:${log.createdAt.minute.toString().padLeft(2, '0')}';
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFB58CFF).withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  date,
                  style: TextStyle(
                    color: const Color(0xFFF6D77A).withValues(alpha: 0.78),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (onDelete != null)
                IconButton(
                  onPressed: onDelete,
                  tooltip: 'このログを削除',
                  icon: const Icon(Icons.delete_outline, size: 19),
                  color: const Color(0xFFFF82B2),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '相談: ${log.question}',
            maxLines: expanded ? null : 2,
            overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          Text(
            log.answer,
            maxLines: expanded ? null : 3,
            overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.68),
              fontSize: 12,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class CustomFortuneLogHistorySheet extends StatefulWidget {
  const CustomFortuneLogHistorySheet({
    super.key,
    required this.initialLogs,
    required this.profileName,
    required this.onChanged,
  });

  final List<CustomFortuneLog> initialLogs;
  final String profileName;
  final Future<void> Function(List<CustomFortuneLog> remaining) onChanged;

  @override
  State<CustomFortuneLogHistorySheet> createState() => _CustomFortuneLogHistorySheetState();
}

class _CustomFortuneLogHistorySheetState extends State<CustomFortuneLogHistorySheet> {
  late List<CustomFortuneLog> _logs;

  @override
  void initState() {
    super.initState();
    _logs = List.of(widget.initialLogs);
  }

  Future<void> _deleteLog(CustomFortuneLog log) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('この鑑定ログを削除しますか？'),
        content: const Text('この1件の相談内容と回答を削除します。この操作は元に戻せません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await CustomFortuneLog.delete(log);
    final refreshed = await CustomFortuneLog.loadAll(profileId: log.profileId);
    if (!mounted) return;
    setState(() => _logs = refreshed);
    await widget.onChanged(List.of(refreshed));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('チャット式カスタム鑑定ログを削除しました')),
    );
    // 親画面が必ず削除後の一覧を受け取れるよう、結果を返して閉じる。
    Navigator.of(context).pop(refreshed);
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    return SafeArea(
      top: false,
      child: Container(
        height: screenHeight * 0.84,
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
        decoration: const BoxDecoration(
          color: Color(0xFF171A36),
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.34),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${widget.profileName}さんのチャット式カスタム鑑定ログ',
                    maxLines: 2,
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
                  ),
                ),
                Text(
                  '${_logs.length}/${CustomFortuneLog.maxEntries}件',
                  style: TextStyle(
                    color: const Color(0xFFF6D77A).withValues(alpha: 0.84),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: '閉じる',
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Expanded(
              child: _logs.isEmpty
                  ? const Center(child: Text('保存されているチャット式カスタム鑑定ログはありません。'))
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: _logs.length,
                      itemBuilder: (context, index) {
                        final log = _logs[index];
                        return CustomFortuneLogTile(
                          log: log,
                          expanded: true,
                          onDelete: () => _deleteLog(log),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class CreatorProfileCard extends StatelessWidget {
  const CreatorProfileCard({super.key});

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          final imageSize = compact ? math.min(constraints.maxWidth, 220.0) : 132.0;
          final image = Container(
            width: imageSize,
            height: imageSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFB58CFF).withValues(alpha: 0.32),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.asset(
              'assets/images/pancyo_profile.png',
              fit: BoxFit.contain,
            ),
          );
          final text = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                const Text(
                  '作者プロフィール',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  'ぱんちょ\n\n'
                  '北海道出身のミュージシャン兼小説家。\n\n'
                  '音楽、小説、そして占星術を愛し、日々の出来事や創作活動とホロスコープを照らし合わせながら、独自の「ぱんちょ式 超本格占星術」を研究・構築しています。\n\n'
                  'このアプリでは、「当たる占い」だけではなく、「納得できる占い」を目指しています。\n\n'
                  'あなたの人生を照らす、星の声を一緒に探してみませんか。',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 28),
                const Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _CreatorLinkButton(
                      icon: Icons.play_circle_outline,
                      label: 'YouTube',
                      url: 'https://www.youtube.com/@pancyo924',
                    ),
                    _CreatorLinkButton(
                      icon: Icons.menu_book_outlined,
                      label: 'Kindle作品一覧',
                      url: 'https://www.amazon.co.jp/stores/author/B0GJFN5HX8',
                    ),
                    _CreatorLinkButton(
                      icon: Icons.privacy_tip_outlined,
                      label: 'プライバシーポリシー',
                      url: 'https://pancyo-astrology.netlify.app/privacy.html',
                    ),
                  ],
                ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: image),
                const SizedBox(height: 16),
                text,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              image,
              const SizedBox(width: 18),
              Expanded(child: text),
            ],
          );
        },
      ),
    );
  }
}

class _CreatorLinkButton extends StatelessWidget {
  const _CreatorLinkButton({
    required this.icon,
    required this.label,
    required this.url,
  });

  final IconData icon;
  final String label;
  final String url;

  Future<void> _open(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.parse(url);
    final opened = await launchUrl(uri, mode: LaunchMode.platformDefault);
    if (!opened) {
      messenger.showSnackBar(
        SnackBar(content: Text('$label のリンクを開けませんでした')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => _open(context),
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFFF6D77A),
        side: BorderSide(color: const Color(0xFFF6D77A).withValues(alpha: 0.42)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

class BirthPlaceQuickSelect extends StatelessWidget {
  const BirthPlaceQuickSelect({
    super.key,
    required this.suggestions,
    required this.regionalSuggestions,
    required this.onSelected,
  });

  final List<String> suggestions;
  final Map<String, List<String>> regionalSuggestions;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ...suggestions.map(
            (place) => ActionChip(
              label: Text(_shortLabel(place)),
              avatar: const Icon(Icons.place_outlined, size: 16),
              onPressed: () => onSelected(place),
            ),
          ),
          ActionChip(
            label: const Text('主な都市から選ぶ'),
            avatar: const Icon(Icons.map_outlined, size: 16),
            onPressed: () => _showRegionalPicker(context),
          ),
          ActionChip(
            label: const Text('緯度経度例'),
            avatar: const Icon(Icons.explore_outlined, size: 16),
            onPressed: () => onSelected('43.8560,144.4620'),
          ),
        ],
      ),
    );
  }

  Future<void> _showRegionalPicker(BuildContext context) async {
    final regions = regionalSuggestions.entries.toList(growable: false);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DefaultTabController(
        length: regions.length,
        child: SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * 0.76,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(18, 18, 18, 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '出生地の主な都市',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                  child: Text(
                    '地域を選んでから都市を選びます。選んだ市名は、ハウス計算用の内部座標へ自動変換されます。',
                    style: TextStyle(color: Colors.black.withValues(alpha: 0.62), height: 1.4),
                  ),
                ),
                TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white.withValues(alpha: 0.76),
                  labelStyle: const TextStyle(fontWeight: FontWeight.w900),
                  unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
                  indicatorColor: const Color(0xFF77D8FF),
                  dividerColor: Colors.transparent,
                  tabs: [
                    for (final entry in regions)
                      Tab(
                        child: Text(
                          entry.key,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      for (final entry in regions)
                        ListView(
                          padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
                          children: [
                            Text(
                              '${entry.key}の主な都市',
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: entry.value
                                  .map(
                                    (place) => ActionChip(
                                      label: Text(_shortLabel(place)),
                                      onPressed: () {
                                        Navigator.pop(sheetContext);
                                        onSelected(place);
                                      },
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _shortLabel(String place) {
    if (place == '東京都') return '東京';
    return place
        .replaceFirst(RegExp(r'^北海道'), '')
        // 「京都府京都市」は先頭の「京都」の「都」で切らない。
        .replaceFirst(RegExp(r'^(?:東京都|京都府|大阪府|.{2,3}県)'), '')
        .replaceFirst(RegExp(r'市$'), '');
  }
}

class BirthPlaceWarning extends StatelessWidget {
  const BirthPlaceWarning({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFF6D77A).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFF6D77A).withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: Color(0xFFF6D77A), size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '住所や市区町村名も入力できますが、未対応の出生地は北海道札幌市として仮計算します。正確にしたい時は候補を選ぶか、緯度経度を「43.0618,141.3545」の形で入力してください。',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.70),
                fontSize: 12,
                height: 1.45,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ProfileTextField extends StatelessWidget {
  const ProfileTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    this.onTap,
    this.onChanged,
    this.suffixIcon,
    this.minLines,
    this.maxLines,
    this.textInputAction,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final VoidCallback? onTap;
  final ValueChanged<String>? onChanged;
  final IconData? suffixIcon;
  final int? minLines;
  final int? maxLines;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        onTap: onTap,
        onChanged: onChanged,
        readOnly: onTap != null,
        minLines: minLines ?? (onTap == null ? 2 : 1),
        maxLines: maxLines ?? (onTap == null ? 4 : 2),
        textInputAction: textInputAction,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          suffixIcon: suffixIcon == null ? null : Icon(suffixIcon),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.08),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}

class ReadingPage extends StatelessWidget {
  const ReadingPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.68))),
              const SizedBox(height: 18),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class FortuneScore extends StatelessWidget {
  const FortuneScore({super.key, required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      margin: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 92,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: score / 100,
                  strokeWidth: 8,
                  backgroundColor: Colors.white.withValues(alpha: 0.12),
                  color: const Color(0xFF57D6D1),
                ),
                Center(
                  child: Text(
                    '$score',
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('星の追い風', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                SizedBox(height: 6),
                Text('今日は自分の感覚を信じつつ、確認を一つ挟むと良い日です。'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ReadingCard extends StatelessWidget {
  const ReadingCard({
    super.key,
    required this.title,
    required this.body,
    required this.icon,
  });

  final String title;
  final String body;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      margin: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF57D6D1)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(
                  body,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.78),
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TimelineCard extends StatelessWidget {
  const TimelineCard({
    super.key,
    required this.day,
    required this.text,
    this.icon = Icons.nights_stay_outlined,
  });

  final String day;
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ReadingCard(title: day, body: text, icon: icon);
  }
}

class AstroTextField extends StatelessWidget {
  const AstroTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.onTap,
    this.onChanged,
    this.suffixIcon,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final VoidCallback? onTap;
  final ValueChanged<String>? onChanged;
  final IconData? suffixIcon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            onTap: onTap,
            onChanged: onChanged,
            readOnly: onTap != null,
            decoration: InputDecoration(
              prefixIcon: Icon(icon),
              suffixIcon: suffixIcon == null ? null : Icon(suffixIcon),
              hintText: hint,
              filled: true,
              fillColor: const Color(0xFF050A1D).withValues(alpha: 0.64),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.20)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFF6D77A)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.margin = EdgeInsets.zero,
    this.padding = const EdgeInsets.all(18),
  });

  final Widget child;
  final EdgeInsets margin;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xFF070D24).withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.30),
            blurRadius: 32,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: child,
    );
  }
}

class StarScaffold extends StatelessWidget {
  const StarScaffold({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/astro_lake_hero.png',
              fit: BoxFit.cover,
              alignment: Alignment.center,
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.14),
                    const Color(0xFF050817).withValues(alpha: 0.10),
                    const Color(0xFF020617).withValues(alpha: 0.34),
                  ],
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _HeroConstellation extends StatelessWidget {
  const _HeroConstellation();

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF57D6D1).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: const Color(0xFF57D6D1).withValues(alpha: 0.28),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.nights_stay_outlined,
                    size: 16,
                    color: Color(0xFFF6D77A),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Today\'s Horoscope',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            '今日のホロスコープを、あなたの物語として読む。',
            style: TextStyle(
              fontSize: 38,
              fontWeight: FontWeight.w900,
              height: 1.15,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '生まれた瞬間の星と、今日動いている星。その重なりから、恋愛・仕事・心の流れをやさしく深く読みます。',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 16,
              height: 1.65,
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: SizedBox(
              width: 320,
              height: 320,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    painter: AstroPulsePainter(0.2),
                    size: const Size.square(320),
                  ),
                  CustomPaint(
                    painter: HoroscopePainter(0.12),
                    size: const Size.square(260),
                  ),
                  Container(
                    width: 86,
                    height: 86,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFFF6D77A).withValues(alpha: 0.45),
                          const Color(0xFF57D6D1).withValues(alpha: 0.18),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: const Icon(
                      Icons.auto_awesome,
                      color: Color(0xFFF6D77A),
                      size: 34,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          const _TodayStarPanel(),
        ],
      ),
    );
  }
}

class _TodayStarPanel extends StatelessWidget {
  const _TodayStarPanel();

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.public_outlined, color: Color(0xFF57D6D1)),
              SizedBox(width: 10),
              Text(
                '今日の星読みプレビュー',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '月は気持ちの奥にある本音を照らし、金星は人との距離感をやわらかく整えます。今日は「急がず、でも曖昧にしない」が合図です。',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.74),
              height: 1.55,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              _AstroTag(label: '月の感情'),
              _AstroTag(label: '金星の調和'),
              _AstroTag(label: '火星の行動力'),
            ],
          ),
        ],
      ),
    );
  }
}

class _AstroTag extends StatelessWidget {
  const _AstroTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class HoroscopePainter extends CustomPainter {
  HoroscopePainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 12;
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14)
      ..color = const Color(0xFF57D6D1).withValues(alpha: 0.18);
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = Colors.white.withValues(alpha: 0.26);
    final accentPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFF57D6D1).withValues(alpha: 0.72);
    final goldPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = const Color(0xFFF6D77A).withValues(alpha: 0.58);

    canvas.drawCircle(center, radius * 0.98, glowPaint);
    for (final scale in [1.0, 0.74, 0.48]) {
      canvas.drawCircle(center, radius * scale, ringPaint);
    }

    for (var i = 0; i < 12; i++) {
      final angle = (math.pi * 2 / 12) * i + progress * math.pi * 2;
      final inner = Offset(
        center.dx + math.cos(angle) * radius * 0.48,
        center.dy + math.sin(angle) * radius * 0.48,
      );
      final outer = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      canvas.drawLine(inner, outer, ringPaint);
    }

    for (var i = 0; i < 12; i++) {
      final angle = (math.pi * 2 / 12) * i - progress * math.pi * 2.4;
      final point = Offset(
        center.dx + math.cos(angle) * radius * 0.88,
        center.dy + math.sin(angle) * radius * 0.88,
      );
      canvas.drawCircle(point, i % 3 == 0 ? 3.6 : 2.3, goldPaint..style = PaintingStyle.fill);
      goldPaint.style = PaintingStyle.stroke;
    }

    final points = List<Offset>.generate(7, (index) {
      final angle = progress * math.pi * 2 + index * 0.92;
      final distance = radius * (0.28 + (index % 4) * 0.14);
      return Offset(
        center.dx + math.cos(angle) * distance,
        center.dy + math.sin(angle) * distance,
      );
    });

    for (var i = 0; i < points.length - 1; i++) {
      canvas.drawLine(points[i], points[i + 1], accentPaint);
    }

    final dotPaint = Paint()..color = const Color(0xFFF6D77A);
    for (final point in points) {
      canvas.drawCircle(point, 4.5, dotPaint);
      canvas.drawCircle(
        point,
        9,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0xFFF6D77A).withValues(alpha: 0.28),
      );
    }
  }

  @override
  bool shouldRepaint(covariant HoroscopePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class ReadingScanPainter extends CustomPainter {
  ReadingScanPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 10;
    final scanPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = const Color(0xFF57D6D1).withValues(alpha: 0.18);
    final goldPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = const Color(0xFFF6D77A).withValues(alpha: 0.22);

    for (var i = 0; i < 7; i++) {
      final scale = 0.30 + i * 0.105;
      canvas.drawCircle(center, radius * scale, i.isEven ? scanPaint : goldPaint);
    }

    final sweep = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        colors: [
          Colors.transparent,
          const Color(0xFFF6D77A).withValues(alpha: 0.70),
          const Color(0xFF57D6D1).withValues(alpha: 0.40),
          Colors.transparent,
        ],
        stops: const [0.0, 0.08, 0.16, 1.0],
        transform: GradientRotation(progress * math.pi * 2),
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius * 0.96, sweep);

    final lineAngle = progress * math.pi * 2;
    final lineEnd = Offset(
      center.dx + math.cos(lineAngle) * radius * 0.94,
      center.dy + math.sin(lineAngle) * radius * 0.94,
    );
    canvas.drawLine(
      center,
      lineEnd,
      Paint()
        ..strokeWidth = 1.2
        ..color = const Color(0xFFF6D77A).withValues(alpha: 0.26),
    );
  }

  @override
  bool shouldRepaint(covariant ReadingScanPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class ReadingConstellationPainter extends CustomPainter {
  ReadingConstellationPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 16;
    final points = List<Offset>.generate(9, (index) {
      final angle = progress * math.pi * 2 * (index.isEven ? 1 : -0.7) + index * 0.74;
      final distance = radius * (0.22 + (index % 5) * 0.15);
      return Offset(
        center.dx + math.cos(angle) * distance,
        center.dy + math.sin(angle) * distance,
      );
    });

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = const Color(0xFFB58CFF).withValues(alpha: 0.42);
    final dotPaint = Paint()..color = const Color(0xFFEDE7FF).withValues(alpha: 0.86);

    for (var i = 0; i < points.length - 1; i++) {
      canvas.drawLine(points[i], points[i + 1], linePaint);
    }
    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      canvas.drawCircle(point, i % 3 == 0 ? 3.6 : 2.4, dotPaint);
      canvas.drawCircle(
        point,
        7.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = const Color(0xFFF6D77A).withValues(alpha: 0.20),
      );
    }
  }

  @override
  bool shouldRepaint(covariant ReadingConstellationPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class AstroPulsePainter extends CustomPainter {
  AstroPulsePainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 8;
    final pulse = (math.sin(progress * math.pi * 2) + 1) / 2;

    for (var i = 0; i < 4; i++) {
      final scale = 0.55 + i * 0.16 + pulse * 0.04;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = (i.isEven ? const Color(0xFF57D6D1) : const Color(0xFFF6D77A))
            .withValues(alpha: 0.22 - i * 0.035);
      canvas.drawCircle(center, radius * scale, paint);
    }

    final cometPaint = Paint()
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        colors: [Color(0xFFF6D77A), Color(0xFF57D6D1)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    for (var i = 0; i < 3; i++) {
      final angle = progress * math.pi * 2 + i * math.pi * 2 / 3;
      final start = Offset(
        center.dx + math.cos(angle) * radius * 0.78,
        center.dy + math.sin(angle) * radius * 0.78,
      );
      final end = Offset(
        center.dx + math.cos(angle + 0.22) * radius * 0.92,
        center.dy + math.sin(angle + 0.22) * radius * 0.92,
      );
      canvas.drawLine(start, end, cometPaint);
    }
  }

  @override
  bool shouldRepaint(covariant AstroPulsePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class StarFieldPainter extends CustomPainter {
  const StarFieldPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.62);
    for (var i = 0; i < 90; i++) {
      final x = ((i * 47) % 100) / 100 * size.width;
      final y = ((i * 83) % 100) / 100 * size.height;
      final radius = i % 9 == 0 ? 1.7 : 0.8;
      canvas.drawCircle(Offset(x, y), radius, paint);
    }

    final shootingStar = Paint()
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        colors: [
          Colors.white.withValues(alpha: 0.92),
          const Color(0xFF8A4DFF).withValues(alpha: 0.62),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromLTWH(size.width * 0.78, size.height * 0.16, size.width * 0.16, 60),
      );
    canvas.drawLine(
      Offset(size.width * 0.86, size.height * 0.18),
      Offset(size.width * 0.76, size.height * 0.27),
      shootingStar,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class NightHorizonPainter extends CustomPainter {
  const NightHorizonPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final horizonY = size.height * 0.76;
    final sunsetPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, 0.72),
        radius: 0.78,
        colors: [
          const Color(0xFFF6A44D).withValues(alpha: 0.34),
          const Color(0xFF8A4DFF).withValues(alpha: 0.12),
          Colors.transparent,
        ],
      ).createShader(Offset.zero & size);

    canvas.drawRect(Offset.zero & size, sunsetPaint);

    final mountainPaint = Paint()..color = const Color(0xFF030817).withValues(alpha: 0.88);
    final mountain = Path()
      ..moveTo(0, horizonY + 20)
      ..lineTo(size.width * 0.12, horizonY - 6)
      ..lineTo(size.width * 0.26, horizonY + 12)
      ..lineTo(size.width * 0.42, horizonY - 14)
      ..lineTo(size.width * 0.58, horizonY + 8)
      ..lineTo(size.width * 0.74, horizonY - 10)
      ..lineTo(size.width * 0.9, horizonY + 4)
      ..lineTo(size.width, horizonY - 8)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(mountain, mountainPaint);

    final waterPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF241747).withValues(alpha: 0.42),
          const Color(0xFF020617).withValues(alpha: 0.82),
        ],
      ).createShader(Rect.fromLTWH(0, horizonY, size.width, size.height - horizonY));
    canvas.drawRect(Rect.fromLTWH(0, horizonY, size.width, size.height - horizonY), waterPaint);

    final reflection = Paint()
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFF6D77A).withValues(alpha: 0.20);
    for (var i = 0; i < 18; i++) {
      final y = horizonY + 18 + i * 9;
      final width = size.width * (0.14 + (i % 5) * 0.035);
      canvas.drawLine(
        Offset(size.width / 2 - width / 2, y),
        Offset(size.width / 2 + width / 2, y),
        reflection,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class AstroProfile {
  const AstroProfile({
    required this.name,
    required this.birthDate,
    required this.birthTime,
    required this.birthPlace,
    required this.theme,
    this.savedProfileId,
  });

  final String name;
  final String birthDate;
  final String birthTime;
  final String birthPlace;
  final String theme;
  final String? savedProfileId;

  AstroProfile copyWith({
    String? name,
    String? birthDate,
    String? birthTime,
    String? birthPlace,
    String? theme,
    String? savedProfileId,
  }) {
    return AstroProfile(
      name: name ?? this.name,
      birthDate: birthDate ?? this.birthDate,
      birthTime: birthTime ?? this.birthTime,
      birthPlace: birthPlace ?? this.birthPlace,
      theme: theme ?? this.theme,
      savedProfileId: savedProfileId ?? this.savedProfileId,
    );
  }
}

enum AstroPlanet {
  sun('太陽'),
  moon('月'),
  mercury('水星'),
  venus('金星'),
  mars('火星'),
  jupiter('木星'),
  saturn('土星'),
  uranus('天王星'),
  neptune('海王星'),
  pluto('冥王星'),
  ascendant('ASC'),
  midheaven('MC');

  const AstroPlanet(this.label);

  final String label;
}

enum ZodiacSign {
  aries('牡羊座'),
  taurus('牡牛座'),
  gemini('双子座'),
  cancer('蟹座'),
  leo('獅子座'),
  virgo('乙女座'),
  libra('天秤座'),
  scorpio('蠍座'),
  sagittarius('射手座'),
  capricorn('山羊座'),
  aquarius('水瓶座'),
  pisces('魚座');

  const ZodiacSign(this.label);

  final String label;
}

enum AspectType {
  conjunction('コンジャンクション', '0°'),
  sextile('セクスタイル', '60°'),
  square('スクエア', '90°'),
  trine('トライン', '120°'),
  opposition('オポジション', '180°');

  const AspectType(this.label, this.angle);

  final String label;
  final String angle;
}

enum AspectPhase {
  applying('接近中'),
  exact('ピーク'),
  separating('余韻');

  const AspectPhase(this.label);

  final String label;
}

class TransitPairAspect {
  const TransitPairAspect({
    required this.firstPlanet,
    required this.secondPlanet,
    required this.type,
    required this.orb,
    required this.phase,
  });

  final AstroPlanet firstPlanet;
  final AstroPlanet secondPlanet;
  final AspectType type;
  final double orb;
  final AspectPhase phase;

  bool involves(AstroPlanet planet) => firstPlanet == planet || secondPlanet == planet;

  String get label =>
      '現在の${firstPlanet.label} ${type.label} 現在の${secondPlanet.label} / ${orb.toStringAsFixed(1)}°・${phase.label}';
}

enum DailyConcernTag {
  romance,
  family,
  career,
  jobChange,
  study,
  creator,
  business,
  income,
  saving,
  investment,
  physicalHealth,
  sleep,
  mental,
  lifeChange,
  home,
}

enum FortuneArea {
  overall('総合運'),
  love('恋愛運'),
  work('仕事運'),
  money('金運'),
  mental('健康・メンタル運');

  const FortuneArea(this.label);

  final String label;
}

class PlanetPlacement {
  const PlanetPlacement({
    required this.planet,
    required this.sign,
    required this.degree,
    required this.house,
  });

  final AstroPlanet planet;
  final ZodiacSign sign;
  final double degree;
  final int house;

  String get compactLabel =>
      '${planet.label}: ${sign.label} ${degree.toStringAsFixed(1)}° / 第$houseハウス';
}

class GeoPoint {
  const GeoPoint({
    required this.label,
    required this.latitude,
    required this.longitude,
  });

  final String label;
  final double latitude;
  final double longitude;
}

class ChartAngles {
  const ChartAngles({
    required this.ascendant,
    required this.midheaven,
  });

  final double ascendant;
  final double midheaven;
}

enum HouseSystem {
  placidus('Placidus', '出生地・出生時刻から不均等なカスプを計算'),
  wholeSign('Whole Sign', 'ASCのある星座全体を第1ハウスにする');

  const HouseSystem(this.label, this.description);

  final String label;
  final String description;
}

class HouseSystemSettings {
  HouseSystemSettings._();

  static const _storageKey = 'astrology.house_system';
  static final ValueNotifier<HouseSystem> current =
      ValueNotifier(HouseSystem.placidus);

  static Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_storageKey);
    current.value = value == HouseSystem.wholeSign.name
        ? HouseSystem.wholeSign
        : HouseSystem.placidus;
  }

  static Future<void> save(HouseSystem value) async {
    current.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, value.name);
  }
}

class HouseFrame {
  const HouseFrame({
    required this.system,
    required this.cusps,
  });

  final HouseSystem system;
  final List<double> cusps;

  factory HouseFrame.wholeSign(double ascendantLongitude) {
    final firstCusp = (ascendantLongitude / 30).floor() * 30.0;
    return HouseFrame(
      system: HouseSystem.wholeSign,
      cusps: List<double>.generate(12, (index) => (firstCusp + index * 30) % 360),
    );
  }

  int houseForLongitude(double longitude) {
    for (var index = 0; index < cusps.length; index++) {
      final start = cusps[index];
      final end = cusps[(index + 1) % cusps.length];
      final span = _distance(end, start);
      final distance = _distance(longitude, start);
      if (distance < span || (index == cusps.length - 1 && distance == span)) {
        return index + 1;
      }
    }
    return 1;
  }

  static double _distance(double value, double from) {
    final result = (value - from) % 360;
    return result < 0 ? result + 360 : result;
  }
}

class SignIngress {
  const SignIngress({
    required this.sign,
    required this.time,
  });

  final ZodiacSign sign;
  final DateTime time;

  String get label {
    final timeLabel = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    return '${time.month}/${time.day} $timeLabel';
  }
}

class NatalChart {
  const NatalChart({
    required this.profile,
    required this.placements,
    required this.stelliums,
    required this.retrogradePlanets,
  });

  final AstroProfile profile;
  final List<PlanetPlacement> placements;
  final List<HouseEmphasis> stelliums;
  /// 出生時点で逆行していた惑星。出生図の解説でのみ使う。
  final Set<AstroPlanet> retrogradePlanets;

  PlanetPlacement? placementOf(AstroPlanet planet) {
    for (final placement in placements) {
      if (placement.planet == planet) return placement;
    }
    return null;
  }
}

class TransitChart {
  const TransitChart({
    required this.date,
    required this.placements,
    required this.voidMoon,
  });

  final DateTime date;
  final List<PlanetPlacement> placements;
  final VoidMoonPeriod? voidMoon;
}

class HouseEmphasis {
  const HouseEmphasis({
    required this.house,
    required this.planets,
    required this.theme,
  });

  final int house;
  final List<AstroPlanet> planets;
  final String theme;

  String get label =>
      '第$houseハウス集中: ${planets.map((planet) => planet.label).join('・')}';
}

class TransitAspect {
  const TransitAspect({
    required this.transitPlanet,
    required this.natalPlanet,
    required this.type,
    required this.orb,
    required this.area,
    required this.meaning,
  });

  final AstroPlanet transitPlanet;
  final AstroPlanet natalPlanet;
  final AspectType type;
  final double orb;
  final FortuneArea area;
  final String meaning;

  String get label =>
      '現在の${transitPlanet.label} ${type.label} 出生図の${natalPlanet.label} / ${orb.toStringAsFixed(1)}°';
}

class HouseTransit {
  const HouseTransit({
    required this.planet,
    required this.natalHouse,
    required this.area,
    required this.meaning,
  });

  final AstroPlanet planet;
  final int natalHouse;
  final FortuneArea area;
  final String meaning;
}

class VoidMoonPeriod {
  const VoidMoonPeriod({
    required this.start,
    required this.end,
    required this.startTime,
    required this.endTime,
    required this.guidance,
  });

  final String start;
  final String end;
  final DateTime startTime;
  final DateTime endTime;
  final String guidance;

  String get label => '$start - $end';

  bool contains(DateTime date) => !date.isBefore(startTime) && date.isBefore(endTime);

  double dayShare(DateTime date) {
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final overlapStart = startTime.isAfter(dayStart) ? startTime : dayStart;
    final overlapEnd = endTime.isBefore(dayEnd) ? endTime : dayEnd;
    if (!overlapEnd.isAfter(overlapStart)) return 0;
    return (overlapEnd.difference(overlapStart).inSeconds / const Duration(days: 1).inSeconds)
        .clamp(0.0, 1.0)
        .toDouble();
  }
}

class PlanetReturnEvent {
  const PlanetReturnEvent({
    required this.planet,
    required this.natalHouse,
    required this.status,
    required this.orb,
    required this.window,
    this.phase = AspectPhase.applying,
    required this.area,
    required this.meaning,
  });

  final AstroPlanet planet;
  final int natalHouse;
  final String status;
  final double orb;
  final double window;
  final AspectPhase phase;
  final FortuneArea area;
  final String meaning;

  String get label => '${planet.label}リターン: $status・${phase.label}';

  PlanetReturnEvent copyWith({
    String? status,
    double? orb,
    AspectPhase? phase,
  }) {
    return PlanetReturnEvent(
      planet: planet,
      natalHouse: natalHouse,
      status: status ?? this.status,
      orb: orb ?? this.orb,
      window: window,
      phase: phase ?? this.phase,
      area: area,
      meaning: meaning,
    );
  }
}

class HoroscopeReadingContext {
  const HoroscopeReadingContext({
    required this.natal,
    required this.transit,
    required this.nextTransitPlacements,
    required this.aspects,
    required this.fullAspects,
    required this.nextAspects,
    required this.transitPairAspects,
    required this.retrogradePlanets,
    required this.houseTransits,
    required this.returns,
    required this.birthPlace,
    required this.ephemerisSourceName,
    required this.ephemerisPrecisionNotice,
    required this.usesHighPrecisionAstroData,
    required this.houseSystem,
    required this.houseCusps,
  });

  final NatalChart natal;
  final TransitChart transit;
  final List<PlanetPlacement> nextTransitPlacements;
  // 通常画面用の強い8件と、タブレット一覧用の出生図との全アスペクトを分けて保持する。
  final List<TransitAspect> aspects;
  final List<TransitAspect> fullAspects;
  final List<TransitAspect> nextAspects;
  final List<TransitPairAspect> transitPairAspects;
  final Set<AstroPlanet> retrogradePlanets;
  final List<HouseTransit> houseTransits;
  final List<PlanetReturnEvent> returns;
  final GeoPoint birthPlace;
  final String ephemerisSourceName;
  final String ephemerisPrecisionNotice;
  final bool usesHighPrecisionAstroData;
  final HouseSystem houseSystem;
  final List<double> houseCusps;

  Iterable<TransitAspect> aspectsFor(FortuneArea area) =>
      aspects.where((aspect) => aspect.area == area);

  Iterable<HouseTransit> houseTransitsFor(FortuneArea area) =>
      houseTransits.where((transit) => transit.area == area);

  Iterable<PlanetReturnEvent> returnsFor(FortuneArea area) =>
      returns.where((event) => event.area == area);
}

abstract class EphemerisProvider {
  String get sourceName;

  String get precisionNotice;

  bool get usesHighPrecisionAstroData;

  GeoPoint placeForProfile(AstroProfile profile);

  DateTime dateFromProfile(AstroProfile profile);

  HouseFrame houseFrameFor(
    DateTime date,
    GeoPoint place,
    HouseSystem requestedSystem,
  );

  List<PlanetPlacement> placementsFor(
    DateTime date, {
    GeoPoint? place,
    ZodiacSign? firstHouseSign,
    HouseFrame? houseFrame,
  });

  List<TransitAspect> aspects({
    required List<PlanetPlacement> transit,
    required List<PlanetPlacement> natal,
  });

  List<HouseTransit> houseTransits(List<PlanetPlacement> transit);

  List<HouseEmphasis> stelliums(List<PlanetPlacement> placements);

  List<PlanetReturnEvent> returns({
    required List<PlanetPlacement> transit,
    required List<PlanetPlacement> natal,
  });

  VoidMoonPeriod? voidMoonFor(DateTime date);

  SignIngress? nextSignIngress(AstroPlanet planet, DateTime date);
}

class AstrologyDataSources {
  const AstrologyDataSources._();

  static final EphemerisProvider current = SwissEphemerisProvider.isAvailable
      ? const SwissEphemerisProvider()
      : const SimpleEphemeris();
}

class SimpleEphemeris implements EphemerisProvider {
  const SimpleEphemeris();

  @override
  String get sourceName => 'アプリ内簡易計算';

  @override
  String get precisionNotice => 'Swiss Ephemeris未読込のため、星座境界付近、月、ハウス、ボイドは目安です。Android版では高精度アストロデータを優先して使います。';

  @override
  bool get usesHighPrecisionAstroData => false;

  static const _knownPlaces = [
    GeoPoint(label: '北海道札幌市', latitude: 43.0618, longitude: 141.3545),
    GeoPoint(label: '北海道旭川市', latitude: 43.7706, longitude: 142.3650),
    GeoPoint(label: '北海道函館市', latitude: 41.7687, longitude: 140.7290),
    GeoPoint(label: '北海道釧路市', latitude: 42.9849, longitude: 144.3814),
    GeoPoint(label: '北海道帯広市', latitude: 42.9239, longitude: 143.1960),
    GeoPoint(label: '北海道北見市', latitude: 43.8030, longitude: 143.8957),
    GeoPoint(label: '北海道苫小牧市', latitude: 42.6343, longitude: 141.6054),
    GeoPoint(label: '北海道小樽市', latitude: 43.1907, longitude: 140.9947),
    GeoPoint(label: '北海道江別市', latitude: 43.1039, longitude: 141.5360),
    GeoPoint(label: '北海道千歳市', latitude: 42.8219, longitude: 141.6510),
    GeoPoint(label: '北海道北広島市', latitude: 42.9848, longitude: 141.5677),
    GeoPoint(label: '北海道室蘭市', latitude: 42.3152, longitude: 140.9738),
    GeoPoint(label: '北海道岩見沢市', latitude: 43.1960, longitude: 141.7759),
    GeoPoint(label: '北海道網走市', latitude: 44.0206, longitude: 144.2734),
    GeoPoint(label: '北海道稚内市', latitude: 45.4157, longitude: 141.6731),
    GeoPoint(label: '北海道根室市', latitude: 43.3301, longitude: 145.5828),
    GeoPoint(label: '北海道斜里郡小清水町美和', latitude: 43.874881, longitude: 144.451408),
    GeoPoint(label: '青森県青森市', latitude: 40.8244, longitude: 140.7400),
    GeoPoint(label: '青森県八戸市', latitude: 40.5123, longitude: 141.4883),
    GeoPoint(label: '岩手県盛岡市', latitude: 39.7036, longitude: 141.1527),
    GeoPoint(label: '宮城県仙台市', latitude: 38.2682, longitude: 140.8694),
    GeoPoint(label: '秋田県秋田市', latitude: 39.7186, longitude: 140.1024),
    GeoPoint(label: '山形県山形市', latitude: 38.2404, longitude: 140.3633),
    GeoPoint(label: '福島県福島市', latitude: 37.7608, longitude: 140.4747),
    GeoPoint(label: '福島県郡山市', latitude: 37.4005, longitude: 140.3597),
    GeoPoint(label: '福島県いわき市', latitude: 37.0505, longitude: 140.8877),
    GeoPoint(label: '茨城県水戸市', latitude: 36.3418, longitude: 140.4468),
    GeoPoint(label: '茨城県つくば市', latitude: 36.0835, longitude: 140.0764),
    GeoPoint(label: '栃木県宇都宮市', latitude: 36.5551, longitude: 139.8828),
    GeoPoint(label: '群馬県前橋市', latitude: 36.3895, longitude: 139.0634),
    GeoPoint(label: '群馬県高崎市', latitude: 36.3219, longitude: 139.0033),
    GeoPoint(label: '埼玉県さいたま市', latitude: 35.8617, longitude: 139.6455),
    GeoPoint(label: '埼玉県川越市', latitude: 35.9251, longitude: 139.4858),
    GeoPoint(label: '千葉県千葉市', latitude: 35.6074, longitude: 140.1065),
    GeoPoint(label: '千葉県船橋市', latitude: 35.6940, longitude: 139.9820),
    GeoPoint(label: '東京都', latitude: 35.6762, longitude: 139.6503),
    GeoPoint(label: '東京都八王子市', latitude: 35.6664, longitude: 139.3160),
    GeoPoint(label: '神奈川県横浜市', latitude: 35.4437, longitude: 139.6380),
    GeoPoint(label: '神奈川県川崎市', latitude: 35.5308, longitude: 139.7036),
    GeoPoint(label: '神奈川県相模原市', latitude: 35.5713, longitude: 139.3732),
    GeoPoint(label: '新潟県新潟市', latitude: 37.9161, longitude: 139.0364),
    GeoPoint(label: '新潟県長岡市', latitude: 37.4462, longitude: 138.8512),
    GeoPoint(label: '富山県富山市', latitude: 36.6953, longitude: 137.2113),
    GeoPoint(label: '石川県金沢市', latitude: 36.5613, longitude: 136.6562),
    GeoPoint(label: '福井県福井市', latitude: 36.0641, longitude: 136.2195),
    GeoPoint(label: '山梨県甲府市', latitude: 35.6621, longitude: 138.5683),
    GeoPoint(label: '長野県長野市', latitude: 36.6486, longitude: 138.1948),
    GeoPoint(label: '長野県松本市', latitude: 36.2381, longitude: 137.9719),
    GeoPoint(label: '岐阜県岐阜市', latitude: 35.4233, longitude: 136.7607),
    GeoPoint(label: '静岡県静岡市', latitude: 34.9756, longitude: 138.3828),
    GeoPoint(label: '静岡県浜松市', latitude: 34.7108, longitude: 137.7261),
    GeoPoint(label: '愛知県名古屋市', latitude: 35.1815, longitude: 136.9066),
    GeoPoint(label: '愛知県豊田市', latitude: 35.0825, longitude: 137.1563),
    GeoPoint(label: '三重県津市', latitude: 34.7186, longitude: 136.5057),
    GeoPoint(label: '滋賀県大津市', latitude: 35.0179, longitude: 135.8546),
    GeoPoint(label: '京都府京都市', latitude: 35.0116, longitude: 135.7681),
    GeoPoint(label: '大阪府大阪市', latitude: 34.6937, longitude: 135.5023),
    GeoPoint(label: '大阪府堺市', latitude: 34.5733, longitude: 135.4830),
    GeoPoint(label: '兵庫県神戸市', latitude: 34.6901, longitude: 135.1955),
    GeoPoint(label: '兵庫県姫路市', latitude: 34.8151, longitude: 134.6853),
    GeoPoint(label: '奈良県奈良市', latitude: 34.6851, longitude: 135.8048),
    GeoPoint(label: '和歌山県和歌山市', latitude: 34.2305, longitude: 135.1708),
    GeoPoint(label: '鳥取県鳥取市', latitude: 35.5011, longitude: 134.2351),
    GeoPoint(label: '島根県松江市', latitude: 35.4723, longitude: 133.0505),
    GeoPoint(label: '島根県出雲市', latitude: 35.3670, longitude: 132.7547),
    GeoPoint(label: '岡山県岡山市', latitude: 34.6551, longitude: 133.9195),
    GeoPoint(label: '岡山県倉敷市', latitude: 34.5850, longitude: 133.7721),
    GeoPoint(label: '広島県広島市', latitude: 34.3853, longitude: 132.4553),
    GeoPoint(label: '広島県福山市', latitude: 34.4859, longitude: 133.3623),
    GeoPoint(label: '山口県山口市', latitude: 34.1785, longitude: 131.4737),
    GeoPoint(label: '山口県下関市', latitude: 33.9578, longitude: 130.9415),
    GeoPoint(label: '徳島県徳島市', latitude: 34.0703, longitude: 134.5548),
    GeoPoint(label: '香川県高松市', latitude: 34.3428, longitude: 134.0466),
    GeoPoint(label: '愛媛県松山市', latitude: 33.8392, longitude: 132.7657),
    GeoPoint(label: '高知県高知市', latitude: 33.5597, longitude: 133.5311),
    GeoPoint(label: '福岡県福岡市', latitude: 33.5902, longitude: 130.4017),
    GeoPoint(label: '佐賀県佐賀市', latitude: 33.2494, longitude: 130.2988),
    GeoPoint(label: '長崎県長崎市', latitude: 32.7503, longitude: 129.8777),
    GeoPoint(label: '熊本県熊本市', latitude: 32.8031, longitude: 130.7079),
    GeoPoint(label: '大分県大分市', latitude: 33.2396, longitude: 131.6093),
    GeoPoint(label: '宮崎県宮崎市', latitude: 31.9077, longitude: 131.4202),
    GeoPoint(label: '鹿児島県鹿児島市', latitude: 31.5966, longitude: 130.5571),
    GeoPoint(label: '沖縄県那覇市', latitude: 26.2124, longitude: 127.6792),
  ];

  GeoPoint placeForProfile(AstroProfile profile) {
    final value = profile.birthPlace.trim();
    final coordinate = _coordinateFromText(value);
    if (coordinate != null) return coordinate;
    final matchingPlaces = _knownPlaces
        .where((place) => value.contains(place.label) || place.label.contains(value))
        .toList()
      ..sort((left, right) => right.label.length.compareTo(left.label.length));
    if (matchingPlaces.isNotEmpty) {
      return matchingPlaces.first;
    }
    final keywordPlace = _placeByKeyword(value);
    if (keywordPlace != null) return keywordPlace;
    final prefecturePlace = _placeByPrefecture(value);
    if (prefecturePlace != null) return prefecturePlace;
    return _knownPlaces[0];
  }

  GeoPoint? _placeByKeyword(String value) {
    const keywords = {
      '札幌': '北海道札幌市',
      '旭川': '北海道旭川市',
      '函館': '北海道函館市',
      '釧路': '北海道釧路市',
      '帯広': '北海道帯広市',
      '北見': '北海道北見市',
      '苫小牧': '北海道苫小牧市',
      '小樽': '北海道小樽市',
      '江別': '北海道江別市',
      '千歳': '北海道千歳市',
      '北広島': '北海道北広島市',
      '室蘭': '北海道室蘭市',
      '岩見沢': '北海道岩見沢市',
      '網走': '北海道網走市',
      '稚内': '北海道稚内市',
      '根室': '北海道根室市',
      '小清水': '北海道斜里郡小清水町美和',
      '美和': '北海道斜里郡小清水町美和',
      '青森': '青森県青森市',
      '八戸': '青森県八戸市',
      '盛岡': '岩手県盛岡市',
      '仙台': '宮城県仙台市',
      '秋田': '秋田県秋田市',
      '山形': '山形県山形市',
      '福島': '福島県福島市',
      '郡山': '福島県郡山市',
      'いわき': '福島県いわき市',
      '水戸': '茨城県水戸市',
      'つくば': '茨城県つくば市',
      '宇都宮': '栃木県宇都宮市',
      '前橋': '群馬県前橋市',
      '高崎': '群馬県高崎市',
      'さいたま': '埼玉県さいたま市',
      '川越': '埼玉県川越市',
      '千葉': '千葉県千葉市',
      '船橋': '千葉県船橋市',
      '東京': '東京都',
      '八王子': '東京都八王子市',
      '横浜': '神奈川県横浜市',
      '川崎': '神奈川県川崎市',
      '相模原': '神奈川県相模原市',
      '新潟': '新潟県新潟市',
      '長岡': '新潟県長岡市',
      '富山': '富山県富山市',
      '金沢': '石川県金沢市',
      '福井': '福井県福井市',
      '甲府': '山梨県甲府市',
      '長野': '長野県長野市',
      '松本': '長野県松本市',
      '岐阜': '岐阜県岐阜市',
      '静岡': '静岡県静岡市',
      '浜松': '静岡県浜松市',
      '名古屋': '愛知県名古屋市',
      '豊田': '愛知県豊田市',
      '津市': '三重県津市',
      '大津': '滋賀県大津市',
      '京都': '京都府京都市',
      '大阪': '大阪府大阪市',
      '堺': '大阪府堺市',
      '神戸': '兵庫県神戸市',
      '姫路': '兵庫県姫路市',
      '奈良': '奈良県奈良市',
      '和歌山': '和歌山県和歌山市',
      '鳥取': '鳥取県鳥取市',
      '松江': '島根県松江市',
      '出雲': '島根県出雲市',
      '岡山': '岡山県岡山市',
      '倉敷': '岡山県倉敷市',
      '広島': '広島県広島市',
      '福山': '広島県福山市',
      '山口': '山口県山口市',
      '下関': '山口県下関市',
      '徳島': '徳島県徳島市',
      '高松': '香川県高松市',
      '松山': '愛媛県松山市',
      '高知': '高知県高知市',
      '福岡': '福岡県福岡市',
      '佐賀': '佐賀県佐賀市',
      '長崎': '長崎県長崎市',
      '熊本': '熊本県熊本市',
      '大分': '大分県大分市',
      '宮崎': '宮崎県宮崎市',
      '鹿児島': '鹿児島県鹿児島市',
      '那覇': '沖縄県那覇市',
      '沖縄': '沖縄県那覇市',
    };
    for (final entry in keywords.entries) {
      if (!value.contains(entry.key)) continue;
      for (final place in _knownPlaces) {
        if (place.label == entry.value) return place;
      }
    }
    return null;
  }

  GeoPoint? _placeByPrefecture(String value) {
    for (final place in _knownPlaces) {
      final prefecture = _prefectureLabel(place.label);
      if (prefecture != null && value.contains(prefecture)) return place;
    }
    return null;
  }

  String? _prefectureLabel(String label) {
    final match = RegExp(r'^(.+?[都道府県])').firstMatch(label);
    return match?.group(1);
  }

  GeoPoint? _coordinateFromText(String value) {
    final match = RegExp(r'(-?\d+(?:\.\d+)?)\s*[,、]\s*(-?\d+(?:\.\d+)?)').firstMatch(value);
    if (match == null) return null;
    final latitude = double.tryParse(match.group(1)!);
    final longitude = double.tryParse(match.group(2)!);
    if (latitude == null || longitude == null) return null;
    if (latitude.abs() > 90 || longitude.abs() > 180) return null;
    return GeoPoint(
      label: '緯度経度指定',
      latitude: latitude,
      longitude: longitude,
    );
  }

  List<PlanetPlacement> placementsFor(
    DateTime date, {
    GeoPoint? place,
    ZodiacSign? firstHouseSign,
    HouseFrame? houseFrame,
  }) {
    final d = _daysSinceJ2000(date.toUtc());
    final longitudes = <AstroPlanet, double>{
      AstroPlanet.sun: _sunLongitude(d),
      AstroPlanet.moon: _moonLongitude(d),
      AstroPlanet.mercury: _planetLongitude(d, _mercury(d)),
      AstroPlanet.venus: _planetLongitude(d, _venus(d)),
      AstroPlanet.mars: _planetLongitude(d, _mars(d)),
      AstroPlanet.jupiter: _planetLongitude(d, _jupiter(d)),
      AstroPlanet.saturn: _planetLongitude(d, _saturn(d)),
      AstroPlanet.uranus: _planetLongitude(d, _uranus(d)),
      AstroPlanet.neptune: _planetLongitude(d, _neptune(d)),
      AstroPlanet.pluto: _planetLongitude(d, _pluto(d)),
    };
    if (place != null) {
      final angles = chartAngles(date, place);
      longitudes[AstroPlanet.ascendant] = angles.ascendant;
      longitudes[AstroPlanet.midheaven] = angles.midheaven;
    }

    final resolvedFirstHouseSign = firstHouseSign ??
        (place != null
            ? _signForLongitude(longitudes[AstroPlanet.ascendant]!)
            : _signForLongitude(longitudes[AstroPlanet.sun]!));

    return longitudes.entries.map((entry) {
      final sign = _signForLongitude(entry.value);
      return PlanetPlacement(
        planet: entry.key,
        sign: sign,
        degree: entry.value % 30,
        house: houseFrame?.houseForLongitude(entry.value) ??
            _wholeSignHouse(sign, resolvedFirstHouseSign),
      );
    }).toList();
  }

  @override
  HouseFrame houseFrameFor(
    DateTime date,
    GeoPoint place,
    HouseSystem requestedSystem,
  ) {
    final angles = chartAngles(date, place);
    return HouseFrame.wholeSign(angles.ascendant);
  }

  ChartAngles chartAngles(DateTime localDate, GeoPoint place) {
    final utc = localDate.subtract(const Duration(hours: 9));
    final d = _daysSinceJ2000(utc);
    final lst = _norm(_greenwichSiderealTime(d) + place.longitude);
    final eps = _rad(23.439291 - 0.0000003563 * d);
    final theta = _rad(lst);
    final lat = _rad(place.latitude);

    final mc = _norm(_deg(math.atan2(math.sin(theta) / math.cos(eps), math.cos(theta))));
    final asc = _norm(
      _deg(
        math.atan2(
          -math.cos(theta),
          math.sin(theta) * math.cos(eps) + math.tan(lat) * math.sin(eps),
        ),
      ),
    );

    return ChartAngles(ascendant: asc, midheaven: mc);
  }

  DateTime dateFromProfile(AstroProfile profile) {
    final dateMatch = RegExp(r'(\d{4})\D+(\d{1,2})\D+(\d{1,2})').firstMatch(profile.birthDate);
    final timeMatch = RegExp(r'(\d{1,2})\D+(\d{1,2})').firstMatch(profile.birthTime);
    final now = DateTime.now();
    final year = int.tryParse(dateMatch?.group(1) ?? '') ?? now.year;
    final month = int.tryParse(dateMatch?.group(2) ?? '') ?? now.month;
    final day = int.tryParse(dateMatch?.group(3) ?? '') ?? now.day;
    final hour = int.tryParse(timeMatch?.group(1) ?? '') ?? 12;
    final minute = int.tryParse(timeMatch?.group(2) ?? '') ?? 0;
    try {
      return DateTime(year, month, day, hour, minute);
    } on ArgumentError {
      return DateTime(now.year, now.month, now.day, 12);
    }
  }

  List<TransitAspect> aspects({
    required List<PlanetPlacement> transit,
    required List<PlanetPlacement> natal,
  }) {
    final result = <TransitAspect>[];
    for (final t in transit) {
      for (final n in natal) {
        final type = _aspectType(_angleDistance(_absoluteLongitude(t), _absoluteLongitude(n)));
        if (type == null) continue;
        final exact = double.parse(type.angle.replaceAll('°', ''));
        final orb = (_angleDistance(_absoluteLongitude(t), _absoluteLongitude(n)) - exact).abs();
        result.add(
          TransitAspect(
            transitPlanet: t.planet,
            natalPlanet: n.planet,
            type: type,
            orb: orb,
            area: _areaForAspect(t.planet, n.planet),
            meaning: _aspectMeaning(type),
          ),
        );
      }
    }
    result.sort((a, b) => a.orb.compareTo(b.orb));
    return result;
  }

  List<HouseTransit> houseTransits(List<PlanetPlacement> transit) {
    return transit.map((placement) {
      return HouseTransit(
        planet: placement.planet,
        natalHouse: placement.house,
        area: _areaForPlanet(placement.planet),
        meaning: '${placement.planet.label}が第${placement.house}ハウスのテーマを刺激',
      );
    }).toList();
  }

  List<HouseEmphasis> stelliums(List<PlanetPlacement> placements) {
    final byHouse = <int, List<AstroPlanet>>{};
    for (final placement in placements) {
      byHouse.putIfAbsent(placement.house, () => []).add(placement.planet);
    }
    return byHouse.entries
        .where((entry) => entry.value.length >= 3)
        .map(
          (entry) => HouseEmphasis(
            house: entry.key,
            planets: entry.value,
            theme: _houseTheme(entry.key),
          ),
        )
        .toList();
  }

  List<PlanetReturnEvent> returns({
    required List<PlanetPlacement> transit,
    required List<PlanetPlacement> natal,
  }) {
    final result = <PlanetReturnEvent>[];
    for (final t in transit) {
      PlanetPlacement? n;
      for (final placement in natal) {
        if (placement.planet == t.planet) {
          n = placement;
          break;
        }
      }
      if (n == null) continue;
      final distance = _angleDistance(_absoluteLongitude(t), _absoluteLongitude(n));
      final window = _returnWindow(t.planet);
      if (distance <= window) {
        result.add(
          PlanetReturnEvent(
            planet: t.planet,
            natalHouse: n.house,
            status: distance <= 3 ? '接近中' : '近い',
            orb: distance,
            window: window,
            area: _areaForPlanet(t.planet),
            meaning: '${t.planet.label}が出生図の第${n.house}ハウスのテーマを再確認する時期',
          ),
        );
      }
    }
    return result;
  }

  double _returnWindow(AstroPlanet planet) {
    return switch (planet) {
      AstroPlanet.moon => 3.0,
      AstroPlanet.sun || AstroPlanet.mercury || AstroPlanet.venus || AstroPlanet.mars => 6.0,
      AstroPlanet.jupiter || AstroPlanet.saturn => 10.0,
      AstroPlanet.uranus || AstroPlanet.neptune || AstroPlanet.pluto => 12.0,
      AstroPlanet.ascendant || AstroPlanet.midheaven => 4.0,
    };
  }

  VoidMoonPeriod? voidMoonFor(DateTime date) {
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    var segmentStart = _moonSignSegmentStart(dayStart);

    while (segmentStart.isBefore(dayEnd)) {
      final segmentEnd = _moonSignSegmentEnd(segmentStart);
      final lastAspect = _lastMoonMajorAspectTime(segmentStart, segmentEnd);
      final voidStart = lastAspect ?? segmentStart;
      final overlapStart = voidStart.isBefore(dayStart) ? dayStart : voidStart;
      final overlapEnd = segmentEnd.isAfter(dayEnd) ? dayEnd : segmentEnd;

      if (overlapEnd.isAfter(overlapStart.add(const Duration(minutes: 5)))) {
        return VoidMoonPeriod(
          start: _timeLabel(overlapStart),
          end: _timeLabel(overlapEnd),
          startTime: overlapStart,
          endTime: overlapEnd,
          guidance: '月が次の星座へ入る前の空白時間。新規決定より見直し、休息、準備向き。',
        );
      }
      segmentStart = segmentEnd.add(const Duration(minutes: 1));
    }
    return null;
  }

  SignIngress? nextSignIngress(AstroPlanet planet, DateTime date) {
    if (planet == AstroPlanet.ascendant || planet == AstroPlanet.midheaven) return null;
    final startSign = _signForLongitude(_longitudeForPlanet(planet, date));
    final searchLimit = _ingressSearchLimit(planet);
    var cursor = date.add(const Duration(hours: 1));
    final end = date.add(searchLimit);

    while (cursor.isBefore(end)) {
      if (_signForLongitude(_longitudeForPlanet(planet, cursor)) != startSign) {
        final exact = _bisectPlanetIngress(
          planet,
          cursor.subtract(const Duration(hours: 1)),
          cursor,
          startSign,
        );
        return SignIngress(
          sign: _signForLongitude(_longitudeForPlanet(planet, exact)),
          time: exact,
        );
      }
      cursor = cursor.add(const Duration(hours: 1));
    }
    return null;
  }

  double _daysSinceJ2000(DateTime utc) {
    return utc.difference(DateTime.utc(2000, 1, 1, 12)).inMinutes / 1440;
  }

  double _greenwichSiderealTime(double daysSinceJ2000) {
    return _norm(280.46061837 + 360.98564736629 * daysSinceJ2000);
  }

  double _sunLongitude(double d) {
    final w = _norm(282.9404 + 4.70935e-5 * d);
    final e = 0.016709 - 1.151e-9 * d;
    final m = _norm(356.0470 + 0.9856002585 * d);
    final eAnomaly = _eccentricAnomaly(m, e);
    final xv = math.cos(_rad(eAnomaly)) - e;
    final yv = math.sqrt(1 - e * e) * math.sin(_rad(eAnomaly));
    final v = _deg(math.atan2(yv, xv));
    return _norm(v + w);
  }

  double _longitudeForPlanet(AstroPlanet planet, DateTime date) {
    final d = _daysSinceJ2000(date.toUtc());
    switch (planet) {
      case AstroPlanet.sun:
        return _sunLongitude(d);
      case AstroPlanet.moon:
        return _moonLongitude(d);
      case AstroPlanet.mercury:
        return _planetLongitude(d, _mercury(d));
      case AstroPlanet.venus:
        return _planetLongitude(d, _venus(d));
      case AstroPlanet.mars:
        return _planetLongitude(d, _mars(d));
      case AstroPlanet.jupiter:
        return _planetLongitude(d, _jupiter(d));
      case AstroPlanet.saturn:
        return _planetLongitude(d, _saturn(d));
      case AstroPlanet.uranus:
        return _planetLongitude(d, _uranus(d));
      case AstroPlanet.neptune:
        return _planetLongitude(d, _neptune(d));
      case AstroPlanet.pluto:
        return _planetLongitude(d, _pluto(d));
      case AstroPlanet.ascendant:
      case AstroPlanet.midheaven:
        return 0;
    }
  }

  double _moonLongitude(double d) {
    final elements = _OrbitalElements(
      n: 125.1228 - 0.0529538083 * d,
      i: 5.1454,
      w: 318.0634 + 0.1643573223 * d,
      a: 60.2666,
      e: 0.054900,
      m: 115.3654 + 13.0649929509 * d,
    );
    final rect = _heliocentricRect(elements);
    return _norm(_deg(math.atan2(rect.y, rect.x)));
  }

  double _planetLongitude(double d, _OrbitalElements planet) {
    final planetRect = _heliocentricRect(planet);
    final sunLon = _sunLongitude(d);
    final sunDistance = _sunDistance(d);
    final xs = sunDistance * math.cos(_rad(sunLon));
    final ys = sunDistance * math.sin(_rad(sunLon));
    return _norm(_deg(math.atan2(planetRect.y + ys, planetRect.x + xs)));
  }

  double _sunDistance(double d) {
    final e = 0.016709 - 1.151e-9 * d;
    final m = _norm(356.0470 + 0.9856002585 * d);
    final eAnomaly = _eccentricAnomaly(m, e);
    final xv = math.cos(_rad(eAnomaly)) - e;
    final yv = math.sqrt(1 - e * e) * math.sin(_rad(eAnomaly));
    return math.sqrt(xv * xv + yv * yv);
  }

  _Rect3 _heliocentricRect(_OrbitalElements elements) {
    final eAnomaly = _eccentricAnomaly(elements.m, elements.e);
    final xv = elements.a * (math.cos(_rad(eAnomaly)) - elements.e);
    final yv = elements.a * (math.sqrt(1 - elements.e * elements.e) * math.sin(_rad(eAnomaly)));
    final v = _deg(math.atan2(yv, xv));
    final r = math.sqrt(xv * xv + yv * yv);
    final n = _rad(elements.n);
    final i = _rad(elements.i);
    final vw = _rad(v + elements.w);
    final x = r * (math.cos(n) * math.cos(vw) - math.sin(n) * math.sin(vw) * math.cos(i));
    final y = r * (math.sin(n) * math.cos(vw) + math.cos(n) * math.sin(vw) * math.cos(i));
    final z = r * (math.sin(vw) * math.sin(i));
    return _Rect3(x, y, z);
  }

  _OrbitalElements _mercury(double d) => _OrbitalElements(
        n: 48.3313 + 3.24587e-5 * d,
        i: 7.0047 + 5.00e-8 * d,
        w: 29.1241 + 1.01444e-5 * d,
        a: 0.387098,
        e: 0.205635 + 5.59e-10 * d,
        m: 168.6562 + 4.0923344368 * d,
      );

  _OrbitalElements _venus(double d) => _OrbitalElements(
        n: 76.6799 + 2.46590e-5 * d,
        i: 3.3946 + 2.75e-8 * d,
        w: 54.8910 + 1.38374e-5 * d,
        a: 0.723330,
        e: 0.006773 - 1.302e-9 * d,
        m: 48.0052 + 1.6021302244 * d,
      );

  _OrbitalElements _mars(double d) => _OrbitalElements(
        n: 49.5574 + 2.11081e-5 * d,
        i: 1.8497 - 1.78e-8 * d,
        w: 286.5016 + 2.92961e-5 * d,
        a: 1.523688,
        e: 0.093405 + 2.516e-9 * d,
        m: 18.6021 + 0.5240207766 * d,
      );

  _OrbitalElements _jupiter(double d) => _OrbitalElements(
        n: 100.4542 + 2.76854e-5 * d,
        i: 1.3030 - 1.557e-7 * d,
        w: 273.8777 + 1.64505e-5 * d,
        a: 5.20256,
        e: 0.048498 + 4.469e-9 * d,
        m: 19.8950 + 0.0830853001 * d,
      );

  _OrbitalElements _saturn(double d) => _OrbitalElements(
        n: 113.6634 + 2.38980e-5 * d,
        i: 2.4886 - 1.081e-7 * d,
        w: 339.3939 + 2.97661e-5 * d,
        a: 9.55475,
        e: 0.055546 - 9.499e-9 * d,
        m: 316.9670 + 0.0334442282 * d,
      );

  _OrbitalElements _uranus(double d) => _OrbitalElements(
        n: 74.0005 + 1.3978e-5 * d,
        i: 0.7733 + 1.9e-8 * d,
        w: 96.6612 + 3.0565e-5 * d,
        a: 19.18171 - 1.55e-8 * d,
        e: 0.047318 + 7.45e-9 * d,
        m: 142.5905 + 0.011725806 * d,
      );

  _OrbitalElements _neptune(double d) => _OrbitalElements(
        n: 131.7806 + 3.0173e-5 * d,
        i: 1.7700 - 2.55e-7 * d,
        w: 272.8461 - 6.027e-6 * d,
        a: 30.05826 + 3.313e-8 * d,
        e: 0.008606 + 2.15e-9 * d,
        m: 260.2471 + 0.005995147 * d,
      );

  _OrbitalElements _pluto(double d) => _OrbitalElements(
        n: 110.30347,
        i: 17.14175,
        w: 113.76329,
        a: 39.48168677,
        e: 0.24880766,
        m: 14.53 + 0.0039757 * d,
      );

  double _eccentricAnomaly(double m, double e) {
    var eAnomaly = m + _deg(e * math.sin(_rad(m)) * (1 + e * math.cos(_rad(m))));
    for (var i = 0; i < 4; i++) {
      eAnomaly -= (eAnomaly - _deg(e * math.sin(_rad(eAnomaly))) - m) /
          (1 - e * math.cos(_rad(eAnomaly)));
    }
    return eAnomaly;
  }

  ZodiacSign _signForLongitude(double longitude) {
    final index = (_norm(longitude) / 30).floor() % 12;
    return ZodiacSign.values[index];
  }

  int _wholeSignHouse(ZodiacSign sign, ZodiacSign firstHouseSign) {
    return ((sign.index - firstHouseSign.index) % 12) + 1;
  }

  double _absoluteLongitude(PlanetPlacement placement) {
    return placement.sign.index * 30 + placement.degree;
  }

  AspectType? _aspectType(double angle) {
    const orb = 6.0;
    for (final aspect in AspectType.values) {
      final exact = double.parse(aspect.angle.replaceAll('°', ''));
      if ((angle - exact).abs() <= orb) return aspect;
    }
    return null;
  }

  DateTime _moonSignSegmentStart(DateTime time) {
    final sign = _moonSignAt(time);
    var probe = time;
    while (_moonSignAt(probe) == sign) {
      probe = probe.subtract(const Duration(hours: 6));
    }
    return _bisectMoonSignChange(probe, probe.add(const Duration(hours: 6)), sign, forward: true);
  }

  DateTime _moonSignSegmentEnd(DateTime time) {
    final sign = _moonSignAt(time);
    var probe = time;
    while (_moonSignAt(probe) == sign) {
      probe = probe.add(const Duration(hours: 6));
    }
    return _bisectMoonSignChange(probe.subtract(const Duration(hours: 6)), probe, sign, forward: false);
  }

  DateTime _bisectPlanetIngress(
    AstroPlanet planet,
    DateTime low,
    DateTime high,
    ZodiacSign originalSign,
  ) {
    var left = low;
    var right = high;
    for (var i = 0; i < 24; i++) {
      final middle = left.add(Duration(milliseconds: right.difference(left).inMilliseconds ~/ 2));
      if (_signForLongitude(_longitudeForPlanet(planet, middle)) == originalSign) {
        left = middle;
      } else {
        right = middle;
      }
    }
    return right;
  }

  Duration _ingressSearchLimit(AstroPlanet planet) {
    switch (planet) {
      case AstroPlanet.moon:
        return const Duration(days: 3);
      case AstroPlanet.mercury:
      case AstroPlanet.venus:
        return const Duration(days: 45);
      case AstroPlanet.sun:
      case AstroPlanet.mars:
        return const Duration(days: 70);
      case AstroPlanet.jupiter:
        return const Duration(days: 220);
      case AstroPlanet.saturn:
      case AstroPlanet.uranus:
      case AstroPlanet.neptune:
      case AstroPlanet.pluto:
        return const Duration(days: 0);
      case AstroPlanet.ascendant:
      case AstroPlanet.midheaven:
        return const Duration(days: 0);
    }
  }

  DateTime _bisectMoonSignChange(
    DateTime low,
    DateTime high,
    ZodiacSign originalSign, {
    required bool forward,
  }) {
    var left = low;
    var right = high;
    for (var i = 0; i < 24; i++) {
      final middle = left.add(Duration(milliseconds: right.difference(left).inMilliseconds ~/ 2));
      final same = _moonSignAt(middle) == originalSign;
      if (forward) {
        if (same) {
          right = middle;
        } else {
          left = middle;
        }
      } else {
        if (same) {
          left = middle;
        } else {
          right = middle;
        }
      }
    }
    return forward ? right : left;
  }

  DateTime? _lastMoonMajorAspectTime(DateTime start, DateTime end) {
    DateTime? last;
    var previousTime = start;
    var previousError = _moonMajorAspectError(previousTime);
    var currentTime = start.add(const Duration(minutes: 5));
    var currentError = _moonMajorAspectError(currentTime);

    while (currentTime.isBefore(end)) {
      final nextTime = currentTime.add(const Duration(minutes: 5));
      final boundedNext = nextTime.isAfter(end) ? end : nextTime;
      final nextError = _moonMajorAspectError(boundedNext);
      if (currentError <= previousError &&
          currentError <= nextError &&
          currentError <= 0.12) {
        final exact = _refineMoonMajorAspectTime(previousTime, boundedNext);
        if (_moonMajorAspectError(exact) <= 0.01) last = exact;
      }
      previousTime = currentTime;
      previousError = currentError;
      currentTime = boundedNext;
      currentError = nextError;
    }
    return last;
  }

  DateTime _refineMoonMajorAspectTime(DateTime start, DateTime end) {
    var left = start;
    var right = end;
    for (var i = 0; i < 18; i++) {
      final span = right.difference(left).inMicroseconds;
      final first = left.add(Duration(microseconds: span ~/ 3));
      final second = left.add(Duration(microseconds: span * 2 ~/ 3));
      if (_moonMajorAspectError(first) <= _moonMajorAspectError(second)) {
        right = second;
      } else {
        left = first;
      }
    }
    return left.add(Duration(microseconds: right.difference(left).inMicroseconds ~/ 2));
  }

  double _moonMajorAspectError(DateTime time) {
    final placements = placementsFor(time);
    final moon = placements.where((item) => item.planet == AstroPlanet.moon).first;
    var minimum = double.infinity;
    for (final placement in placements) {
      if (placement.planet == AstroPlanet.moon) continue;
      final angle = _angleDistance(_absoluteLongitude(moon), _absoluteLongitude(placement));
      for (final aspect in AspectType.values) {
        final exact = double.parse(aspect.angle.replaceAll('°', ''));
        minimum = math.min(minimum, (angle - exact).abs());
      }
    }
    return minimum;
  }

  ZodiacSign _moonSignAt(DateTime time) {
    final d = _daysSinceJ2000(time.toUtc());
    return _signForLongitude(_moonLongitude(d));
  }

  String _timeLabel(DateTime time) {
    final roundUp = time.second >= 30;
    final rounded = roundUp ? time.add(const Duration(minutes: 1)) : time;
    return '${rounded.hour.toString().padLeft(2, '0')}:${rounded.minute.toString().padLeft(2, '0')}';
  }

  FortuneArea _areaForPlanet(AstroPlanet planet) {
    switch (planet) {
      case AstroPlanet.moon:
        return FortuneArea.mental;
      case AstroPlanet.venus:
      case AstroPlanet.mars:
        return FortuneArea.love;
      case AstroPlanet.mercury:
      case AstroPlanet.saturn:
      case AstroPlanet.midheaven:
        return FortuneArea.work;
      case AstroPlanet.jupiter:
        return FortuneArea.money;
      case AstroPlanet.sun:
      case AstroPlanet.ascendant:
      case AstroPlanet.uranus:
      case AstroPlanet.neptune:
      case AstroPlanet.pluto:
        return FortuneArea.overall;
    }
  }

  FortuneArea _areaForAspect(AstroPlanet transit, AstroPlanet natal) {
    if (transit == AstroPlanet.venus || natal == AstroPlanet.venus) return FortuneArea.love;
    if (transit == AstroPlanet.jupiter || natal == AstroPlanet.jupiter) return FortuneArea.money;
    if (transit == AstroPlanet.mercury || transit == AstroPlanet.saturn) return FortuneArea.work;
    if (transit == AstroPlanet.moon || natal == AstroPlanet.moon) return FortuneArea.mental;
    return FortuneArea.overall;
  }

  String _aspectMeaning(AspectType type) {
    switch (type) {
      case AspectType.conjunction:
        return '星の意味が重なり強く出る';
      case AspectType.sextile:
        return '意識して使うと開く機会';
      case AspectType.square:
        return '葛藤や負荷が成長点になる';
      case AspectType.trine:
        return '無理なく伸びる追い風';
      case AspectType.opposition:
        return '相手や外側から刺激が入る';
    }
  }

  String _houseTheme(int house) {
    switch (house) {
      case 1:
        return '自分らしさ、始め方、印象';
      case 2:
        return '収入、所有、価値観';
      case 4:
        return '家、安心感、心の土台';
      case 7:
        return '対人関係、恋愛、約束';
      case 10:
        return '仕事、評価、肩書き';
      default:
        return '第$houseハウスのテーマが強い';
    }
  }

  double _angleDistance(double a, double b) {
    final diff = (_norm(a - b)).abs();
    return diff > 180 ? 360 - diff : diff;
  }

  double _norm(double value) => value % 360 < 0 ? value % 360 + 360 : value % 360;
  double _rad(double value) => value * math.pi / 180;
  double _deg(double value) => value * 180 / math.pi;
}

class SwissEphemerisProvider implements EphemerisProvider {
  const SwissEphemerisProvider();

  static const _fallback = SimpleEphemeris();
  static const _swissPlanets = [
    AstroPlanet.sun,
    AstroPlanet.moon,
    AstroPlanet.mercury,
    AstroPlanet.venus,
    AstroPlanet.mars,
    AstroPlanet.jupiter,
    AstroPlanet.saturn,
    AstroPlanet.uranus,
    AstroPlanet.neptune,
    AstroPlanet.pluto,
  ];
  static final Map<String, VoidMoonPeriod?> _voidMoonCache = {};
  static final Map<String, SignIngress?> _ingressCache = {};

  static bool get isAvailable => SwissEphemerisBridge.isAvailable;

  @override
  String get sourceName => 'Swiss Ephemeris Free Edition';

  @override
  String get precisionNotice =>
      'Swiss Ephemeris Free Edition/AGPLをAndroidネイティブで使用しています。アプリ同梱のMoshier計算で星の位置を算出し、月ボイド開始は5分探索後に最後の主要アスペクトの正確時刻へ絞り込みます。';

  @override
  bool get usesHighPrecisionAstroData => true;

  @override
  GeoPoint placeForProfile(AstroProfile profile) => _fallback.placeForProfile(profile);

  @override
  DateTime dateFromProfile(AstroProfile profile) => _fallback.dateFromProfile(profile);

  @override
  HouseFrame houseFrameFor(
    DateTime date,
    GeoPoint place,
    HouseSystem requestedSystem,
  ) {
    if (requestedSystem == HouseSystem.wholeSign) {
      final ascendant = _longitudesFor(date, place: place)?[AstroPlanet.ascendant];
      if (ascendant != null) return HouseFrame.wholeSign(ascendant);
      return _fallback.houseFrameFor(date, place, requestedSystem);
    }

    final julianDayUt = _julianDayUt(date);
    if (julianDayUt == null) return _fallback.houseFrameFor(date, place, requestedSystem);
    final cusps = <double>[];
    for (var house = 1; house <= 12; house++) {
      final cusp = SwissEphemerisBridge.houseCuspUtc(
        julianDayUt,
        place.latitude,
        place.longitude,
        house,
        1,
      );
      if (cusp == null) return _fallback.houseFrameFor(date, place, requestedSystem);
      cusps.add(cusp);
    }
    return HouseFrame(system: HouseSystem.placidus, cusps: cusps);
  }

  @override
  List<PlanetPlacement> placementsFor(
    DateTime date, {
    GeoPoint? place,
    ZodiacSign? firstHouseSign,
    HouseFrame? houseFrame,
  }) {
    final longitudes = _longitudesFor(date, place: place);
    if (longitudes == null) {
      return _fallback.placementsFor(
        date,
        place: place,
        firstHouseSign: firstHouseSign,
        houseFrame: houseFrame,
      );
    }

    final resolvedFirstHouseSign = firstHouseSign ??
        (place != null
            ? _fallback._signForLongitude(longitudes[AstroPlanet.ascendant]!)
            : _fallback._signForLongitude(longitudes[AstroPlanet.sun]!));

    return longitudes.entries.map((entry) {
      final sign = _fallback._signForLongitude(entry.value);
      return PlanetPlacement(
        planet: entry.key,
        sign: sign,
        degree: _fallback._norm(entry.value) % 30,
        house: houseFrame?.houseForLongitude(entry.value) ??
            _fallback._wholeSignHouse(sign, resolvedFirstHouseSign),
      );
    }).toList();
  }

  @override
  List<TransitAspect> aspects({
    required List<PlanetPlacement> transit,
    required List<PlanetPlacement> natal,
  }) =>
      _fallback.aspects(transit: transit, natal: natal);

  @override
  List<HouseTransit> houseTransits(List<PlanetPlacement> transit) =>
      _fallback.houseTransits(transit);

  @override
  List<HouseEmphasis> stelliums(List<PlanetPlacement> placements) =>
      _fallback.stelliums(placements);

  @override
  List<PlanetReturnEvent> returns({
    required List<PlanetPlacement> transit,
    required List<PlanetPlacement> natal,
  }) =>
      _fallback.returns(transit: transit, natal: natal);

  @override
  VoidMoonPeriod? voidMoonFor(DateTime date) {
    final key = '${date.year}-${date.month}-${date.day}';
    if (_voidMoonCache.containsKey(key)) return _voidMoonCache[key];
    final result = _findVoidMoonFor(date);
    _voidMoonCache[key] = result;
    return result;
  }

  VoidMoonPeriod? _findVoidMoonFor(DateTime date) {
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    var segmentStart = _moonSignSegmentStart(dayStart);

    while (segmentStart.isBefore(dayEnd)) {
      final segmentEnd = _moonSignSegmentEnd(segmentStart);
      final lastAspect = _lastMoonMajorAspectTime(segmentStart, segmentEnd);
      final voidStart = lastAspect ?? segmentStart;
      final overlapStart = voidStart.isBefore(dayStart) ? dayStart : voidStart;
      final overlapEnd = segmentEnd.isAfter(dayEnd) ? dayEnd : segmentEnd;

      if (overlapEnd.isAfter(overlapStart.add(const Duration(minutes: 5)))) {
        return VoidMoonPeriod(
          start: _fallback._timeLabel(overlapStart),
          end: _fallback._timeLabel(overlapEnd),
          startTime: overlapStart,
          endTime: overlapEnd,
          guidance: '月が次の星座へ入る前の空白時間。新規決定より見直し、休息、準備向き。',
        );
      }
      segmentStart = segmentEnd.add(const Duration(minutes: 1));
    }
    return null;
  }

  @override
  SignIngress? nextSignIngress(AstroPlanet planet, DateTime date) {
    if (planet == AstroPlanet.ascendant || planet == AstroPlanet.midheaven) return null;
    final key = '${planet.index}|${date.toIso8601String()}';
    if (_ingressCache.containsKey(key)) return _ingressCache[key];
    final result = _findNextSignIngress(planet, date);
    _ingressCache[key] = result;
    return result;
  }

  SignIngress? _findNextSignIngress(AstroPlanet planet, DateTime date) {
    final startLongitude = _longitudeForPlanet(planet, date);
    if (startLongitude == null) return _fallback.nextSignIngress(planet, date);

    final startSign = _fallback._signForLongitude(startLongitude);
    final searchLimit = _fallback._ingressSearchLimit(planet);
    var cursor = date.add(const Duration(hours: 1));
    final end = date.add(searchLimit);

    while (cursor.isBefore(end)) {
      final cursorLongitude = _longitudeForPlanet(planet, cursor);
      if (cursorLongitude == null) return _fallback.nextSignIngress(planet, date);
      if (_fallback._signForLongitude(cursorLongitude) != startSign) {
        final exact = _bisectPlanetIngress(
          planet,
          cursor.subtract(const Duration(hours: 1)),
          cursor,
          startSign,
        );
        final exactLongitude = _longitudeForPlanet(planet, exact);
        if (exactLongitude == null) return _fallback.nextSignIngress(planet, date);
        return SignIngress(
          sign: _fallback._signForLongitude(exactLongitude),
          time: exact,
        );
      }
      cursor = cursor.add(const Duration(hours: 1));
    }
    return null;
  }

  Map<AstroPlanet, double>? _longitudesFor(DateTime date, {GeoPoint? place}) {
    final julianDayUt = _julianDayUt(date);
    if (julianDayUt == null) return null;

    final result = <AstroPlanet, double>{};
    for (final planet in _swissPlanets) {
      final longitude = SwissEphemerisBridge.planetLongitudeUtc(julianDayUt, planet.index);
      if (longitude == null) return null;
      result[planet] = longitude;
    }

    if (place != null) {
      final ascendant = SwissEphemerisBridge.ascendantUtc(
        julianDayUt,
        place.latitude,
        place.longitude,
      );
      final midheaven = SwissEphemerisBridge.midheavenUtc(
        julianDayUt,
        place.latitude,
        place.longitude,
      );
      if (ascendant == null || midheaven == null) return null;
      result[AstroPlanet.ascendant] = ascendant;
      result[AstroPlanet.midheaven] = midheaven;
    }

    return result;
  }

  double? _julianDayUt(DateTime localDate) {
    final utc = localDate.subtract(const Duration(hours: 9));
    final hour = utc.hour +
        utc.minute / 60 +
        utc.second / 3600 +
        utc.millisecond / 3600000 +
        utc.microsecond / 3600000000;
    return SwissEphemerisBridge.julianDayUtc(utc.year, utc.month, utc.day, hour);
  }

  double? _longitudeForPlanet(AstroPlanet planet, DateTime date) {
    if (planet == AstroPlanet.ascendant || planet == AstroPlanet.midheaven) return null;
    final julianDayUt = _julianDayUt(date);
    if (julianDayUt == null) return null;
    return SwissEphemerisBridge.planetLongitudeUtc(julianDayUt, planet.index);
  }

  DateTime _moonSignSegmentStart(DateTime time) {
    final sign = _moonSignAt(time);
    var probe = time;
    while (_moonSignAt(probe) == sign) {
      probe = probe.subtract(const Duration(hours: 6));
    }
    return _bisectMoonSignChange(probe, probe.add(const Duration(hours: 6)), sign, forward: true);
  }

  DateTime _moonSignSegmentEnd(DateTime time) {
    final sign = _moonSignAt(time);
    var probe = time;
    while (_moonSignAt(probe) == sign) {
      probe = probe.add(const Duration(hours: 6));
    }
    return _bisectMoonSignChange(probe.subtract(const Duration(hours: 6)), probe, sign, forward: false);
  }

  DateTime _bisectPlanetIngress(
    AstroPlanet planet,
    DateTime low,
    DateTime high,
    ZodiacSign originalSign,
  ) {
    var left = low;
    var right = high;
    for (var i = 0; i < 24; i++) {
      final middle = left.add(Duration(milliseconds: right.difference(left).inMilliseconds ~/ 2));
      final longitude = _longitudeForPlanet(planet, middle);
      if (longitude != null && _fallback._signForLongitude(longitude) == originalSign) {
        left = middle;
      } else {
        right = middle;
      }
    }
    return right;
  }

  DateTime _bisectMoonSignChange(
    DateTime low,
    DateTime high,
    ZodiacSign originalSign, {
    required bool forward,
  }) {
    var left = low;
    var right = high;
    for (var i = 0; i < 24; i++) {
      final middle = left.add(Duration(milliseconds: right.difference(left).inMilliseconds ~/ 2));
      final same = _moonSignAt(middle) == originalSign;
      if (forward) {
        if (same) {
          right = middle;
        } else {
          left = middle;
        }
      } else {
        if (same) {
          left = middle;
        } else {
          right = middle;
        }
      }
    }
    return forward ? right : left;
  }

  DateTime? _lastMoonMajorAspectTime(DateTime start, DateTime end) {
    DateTime? last;
    var previousTime = start;
    var previousError = _moonMajorAspectError(previousTime);
    var currentTime = start.add(const Duration(minutes: 5));
    var currentError = _moonMajorAspectError(currentTime);

    while (currentTime.isBefore(end)) {
      final nextTime = currentTime.add(const Duration(minutes: 5));
      final boundedNext = nextTime.isAfter(end) ? end : nextTime;
      final nextError = _moonMajorAspectError(boundedNext);
      if (currentError <= previousError &&
          currentError <= nextError &&
          currentError <= 0.12) {
        final exact = _refineMoonMajorAspectTime(previousTime, boundedNext);
        if (_moonMajorAspectError(exact) <= 0.01) last = exact;
      }
      previousTime = currentTime;
      previousError = currentError;
      currentTime = boundedNext;
      currentError = nextError;
    }
    return last;
  }

  DateTime _refineMoonMajorAspectTime(DateTime start, DateTime end) {
    var left = start;
    var right = end;
    for (var i = 0; i < 18; i++) {
      final span = right.difference(left).inMicroseconds;
      final first = left.add(Duration(microseconds: span ~/ 3));
      final second = left.add(Duration(microseconds: span * 2 ~/ 3));
      if (_moonMajorAspectError(first) <= _moonMajorAspectError(second)) {
        right = second;
      } else {
        left = first;
      }
    }
    return left.add(Duration(microseconds: right.difference(left).inMicroseconds ~/ 2));
  }

  double _moonMajorAspectError(DateTime time) {
    final placements = placementsFor(time);
    final moon = placements.where((item) => item.planet == AstroPlanet.moon).first;
    var minimum = double.infinity;
    for (final placement in placements) {
      if (placement.planet == AstroPlanet.moon) continue;
      final angle = _fallback._angleDistance(
        _fallback._absoluteLongitude(moon),
        _fallback._absoluteLongitude(placement),
      );
      for (final aspect in AspectType.values) {
        final exact = double.parse(aspect.angle.replaceAll('°', ''));
        minimum = math.min(minimum, (angle - exact).abs());
      }
    }
    return minimum;
  }

  ZodiacSign _moonSignAt(DateTime time) {
    final longitude = _longitudeForPlanet(AstroPlanet.moon, time);
    if (longitude == null) return _fallback._moonSignAt(time);
    return _fallback._signForLongitude(longitude);
  }
}

class _OrbitalElements {
  const _OrbitalElements({
    required this.n,
    required this.i,
    required this.w,
    required this.a,
    required this.e,
    required this.m,
  });

  final double n;
  final double i;
  final double w;
  final double a;
  final double e;
  final double m;
}

class _Rect3 {
  const _Rect3(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;
}

class _NatalComputation {
  const _NatalComputation({
    required this.natal,
    required this.houseFrame,
    required this.birthPlace,
  });

  final NatalChart natal;
  final HouseFrame houseFrame;
  final GeoPoint birthPlace;
}

class AstrologyEngine {
  const AstrologyEngine();

  static final Map<String, _NatalComputation> _natalCache = {};

  HoroscopeReadingContext buildPreviewContext({
    required AstroProfile profile,
    required DateTime date,
  }) {
    final ephemeris = AstrologyDataSources.current;
    final houseSystem = HouseSystemSettings.current.value;
    final natalKey = [
      profile.birthDate,
      profile.birthTime,
      profile.birthPlace,
      houseSystem.name,
      ephemeris.sourceName,
    ].join('|');
    final natalComputation = _natalCache.putIfAbsent(natalKey, () {
      final natalDate = ephemeris.dateFromProfile(profile);
      final birthPlace = ephemeris.placeForProfile(profile);
      final houseFrame = ephemeris.houseFrameFor(natalDate, birthPlace, houseSystem);
      final natalPlacements = ephemeris.placementsFor(
        natalDate,
        place: birthPlace,
        houseFrame: houseFrame,
      );
      final nextNatalPlacements = ephemeris.placementsFor(
        natalDate.add(const Duration(days: 1)),
        place: birthPlace,
        houseFrame: houseFrame,
      );
      final natalRetrogrades = <AstroPlanet>{
        for (final planet in const [
          AstroPlanet.mercury,
          AstroPlanet.venus,
          AstroPlanet.mars,
          AstroPlanet.jupiter,
          AstroPlanet.saturn,
          AstroPlanet.uranus,
          AstroPlanet.neptune,
          AstroPlanet.pluto,
        ])
          if (_isRetrograde(planet, natalPlacements, nextNatalPlacements)) planet,
      };
      return _NatalComputation(
        natal: NatalChart(
          profile: profile,
          placements: natalPlacements,
          stelliums: ephemeris.stelliums(natalPlacements),
          retrogradePlanets: natalRetrogrades,
        ),
        houseFrame: houseFrame,
        birthPlace: birthPlace,
      );
    });
    final houseFrame = natalComputation.houseFrame;
    final natal = natalComputation.natal;
    final birthPlace = natalComputation.birthPlace;
    final natalPlacements = natal.placements;
    final transitPlacements = ephemeris.placementsFor(date, houseFrame: houseFrame);
    final nextTransitPlacements = ephemeris.placementsFor(
      date.add(const Duration(days: 1)),
      houseFrame: houseFrame,
    );
    final retrogradePlanets = <AstroPlanet>{
      for (final planet in const [
        AstroPlanet.mercury,
        AstroPlanet.venus,
        AstroPlanet.mars,
        AstroPlanet.jupiter,
        AstroPlanet.saturn,
        AstroPlanet.uranus,
        AstroPlanet.neptune,
        AstroPlanet.pluto,
        ])
          if (_isRetrograde(planet, transitPlacements, nextTransitPlacements)) planet,
      // 留直後の非常に遅い惑星は近似計算の一日差分で見失う場合がある。
      // 表示だけでなくスコア計算に渡す集合そのものへ補完する。
      ...DailyAstroEventsCard.verifiedRetrogradesAt(date),
    };

    final transit = TransitChart(
      date: date,
      placements: transitPlacements,
      voidMoon: ephemeris.voidMoonFor(date),
    );
    final returns = ephemeris
        .returns(transit: transitPlacements, natal: natalPlacements)
        .map(
          (event) => _withReturnPhase(
            event,
            current: transitPlacements,
            next: nextTransitPlacements,
            natal: natalPlacements,
          ),
        )
        .toList();
    final fullAspects = ephemeris.aspects(transit: transitPlacements, natal: natalPlacements);
    final nextAspects = ephemeris.aspects(transit: nextTransitPlacements, natal: natalPlacements);

    return HoroscopeReadingContext(
      natal: natal,
      transit: transit,
      nextTransitPlacements: nextTransitPlacements,
      aspects: fullAspects.take(8).toList(),
      fullAspects: fullAspects,
      nextAspects: nextAspects,
      transitPairAspects: FortuneScoreCalculator.transitPairAspects(
        current: transitPlacements,
        next: nextTransitPlacements,
      ),
      retrogradePlanets: retrogradePlanets,
      houseTransits: ephemeris.houseTransits(transitPlacements),
      returns: returns,
      birthPlace: birthPlace,
      ephemerisSourceName: ephemeris.sourceName,
      ephemerisPrecisionNotice: ephemeris.precisionNotice,
      usesHighPrecisionAstroData: ephemeris.usesHighPrecisionAstroData,
      houseSystem: houseFrame.system,
      houseCusps: houseFrame.cusps,
    );
  }

  PlanetReturnEvent _withReturnPhase(
    PlanetReturnEvent event, {
    required List<PlanetPlacement> current,
    required List<PlanetPlacement> next,
    required List<PlanetPlacement> natal,
  }) {
    PlanetPlacement? find(List<PlanetPlacement> placements) {
      for (final placement in placements) {
        if (placement.planet == event.planet) return placement;
      }
      return null;
    }

    final currentPlacement = find(current);
    final nextPlacement = find(next);
    final natalPlacement = find(natal);
    if (currentPlacement == null || nextPlacement == null || natalPlacement == null) return event;
    final currentOrb = _distance(_longitude(currentPlacement), _longitude(natalPlacement));
    final nextOrb = _distance(_longitude(nextPlacement), _longitude(natalPlacement));
    final phase = currentOrb <= 0.7
        ? AspectPhase.exact
        : nextOrb < currentOrb
            ? AspectPhase.applying
            : AspectPhase.separating;
    final status = switch (phase) {
      AspectPhase.applying => currentOrb <= 3 ? '接近中' : '近い',
      AspectPhase.exact => 'ピーク',
      AspectPhase.separating => '余韻',
    };
    return event.copyWith(status: status, orb: currentOrb, phase: phase);
  }

  double _longitude(PlanetPlacement placement) => placement.sign.index * 30.0 + placement.degree;

  bool _isRetrograde(
    AstroPlanet planet,
    List<PlanetPlacement> current,
    List<PlanetPlacement> next,
  ) {
    PlanetPlacement? find(List<PlanetPlacement> placements) {
      for (final placement in placements) {
        if (placement.planet == planet) return placement;
      }
      return null;
    }

    final now = find(current);
    final tomorrow = find(next);
    if (now == null || tomorrow == null) return false;
    var delta = _longitude(tomorrow) - _longitude(now);
    if (delta > 180) delta -= 360;
    if (delta < -180) delta += 360;
    return delta < -0.01;
  }

  double _distance(double first, double second) {
    var value = (first - second).abs() % 360.0;
    if (value > 180.0) value = 360.0 - value;
    return value;
  }
}

class CustomFortuneLog {
  const CustomFortuneLog({
    required this.createdAt,
    this.profileId = '',
    this.profileName = '',
    required this.question,
    required this.answer,
  });

  static const _storageKey = 'custom_fortune.logs';
  static const maxEntries = 30;

  final DateTime createdAt;
  final String profileId;
  final String profileName;
  final String question;
  final String answer;

  Map<String, dynamic> toJson() => {
        'createdAt': createdAt.toIso8601String(),
        'profileId': profileId,
        'profileName': profileName,
        'question': question,
        'answer': answer,
      };

  static CustomFortuneLog fromJson(Map<String, dynamic> json) {
    return CustomFortuneLog(
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
      profileId: json['profileId']?.toString().trim() ?? '',
      profileName: json['profileName']?.toString().trim() ?? '',
      question: json['question']?.toString() ?? '',
      answer: _completeStoredAnswer(json['answer']?.toString() ?? ''),
    );
  }

  static String _completeStoredAnswer(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || RegExp(r'[。！？!?]$').hasMatch(normalized)) return normalized;
    Match? lastSentence;
    for (final match in RegExp(r'[。！？!?]').allMatches(normalized)) {
      lastSentence = match;
    }
    if (lastSentence != null && lastSentence.end >= 24) {
      return normalized.substring(0, lastSentence.end).trim();
    }
    return normalized;
  }

  static String profileIdFor(AstroProfile profile) {
    final savedId = profile.savedProfileId?.trim() ?? '';
    if (savedId.isNotEmpty) return savedId;
    return 'session:${profile.name}|${profile.birthDate}|${profile.birthTime}|${profile.birthPlace}';
  }

  static Future<List<CustomFortuneLog>> loadAll({String? profileId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final logs = decoded
            .whereType<Map<String, dynamic>>()
            .map(CustomFortuneLog.fromJson)
            .where((log) => log.question.trim().isNotEmpty || log.answer.trim().isNotEmpty)
            .toList();
        if (profileId != null) {
          logs.removeWhere((log) => log.profileId != profileId);
        }
        logs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return logs;
      }
    } on FormatException {
      await prefs.remove(_storageKey);
    }
    return const [];
  }

  static List<CustomFortuneLog> forConversation(Iterable<CustomFortuneLog> logs) {
    const casualWords = [
      'うんこ', 'うんち', 'おはよう', 'こんにちは', 'こんばんは', 'ありがとう', '色いい', '似合',
      'かわいい', 'かっこいい', 'きれい',
    ];
    const legacyGenericAnswers = [
      '求人や依頼を三件だけ比較',
      '増やしたい収入、使える時間を紙に分けて書き',
      '出会いにつながる行動を一つ増やすことで',
      'すぐに白黒を決めるより',
      '結果を左右する条件を整理して',
    ];
    return logs.where((log) {
      final question = log.question.replaceAll(RegExp(r'\s+'), '').toLowerCase();
      if (casualWords.any(question.contains)) return false;
      // 短文でも、鑑定文が最後に任意の質問を返している時は会話の続きに必要。
      if (log.answer.length < 120 &&
          !log.answer.contains('？') &&
          !log.answer.contains('?')) {
        return false;
      }
      return !legacyGenericAnswers.any(log.answer.contains);
    }).take(3).toList();
  }

  static Future<void> add(CustomFortuneLog log) async {
    final prefs = await SharedPreferences.getInstance();
    final logs = await loadAll();
    final sameProfile = [
      log,
      ...logs.where((item) => item.profileId == log.profileId),
    ].take(maxEntries);
    final otherProfiles = logs.where((item) => item.profileId != log.profileId);
    final next = [...sameProfile, ...otherProfiles]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await prefs.setString(_storageKey, jsonEncode(next.map((item) => item.toJson()).toList()));
  }

  static Future<void> delete(CustomFortuneLog target) async {
    final prefs = await SharedPreferences.getInstance();
    final logs = await loadAll();
    final targetTime = target.createdAt.millisecondsSinceEpoch;
    final targetProfileId = target.profileId.trim();
    bool exactMatch(CustomFortuneLog log) {
      final sameTime = log.createdAt.millisecondsSinceEpoch == targetTime;
      final sameQuestion = log.question.trim() == target.question.trim();
      final sameProfile = targetProfileId.isEmpty
          ? log.profileId.trim().isEmpty
          : log.profileId.trim() == targetProfileId;
      return sameTime && sameQuestion && sameProfile;
    }

    final exactCount = logs.where(exactMatch).length;
    final targetMinute = target.createdAt.year * 525600 +
        target.createdAt.month * 44640 +
        target.createdAt.day * 1440 +
        target.createdAt.hour * 60 +
        target.createdAt.minute;
    bool sameDisplayedLog(CustomFortuneLog log) {
      final logMinute = log.createdAt.year * 525600 +
          log.createdAt.month * 44640 +
          log.createdAt.day * 1440 +
          log.createdAt.hour * 60 +
          log.createdAt.minute;
      final sameQuestion = log.question.trim() == target.question.trim();
      final sameProfile = targetProfileId.isEmpty
          ? log.profileName.trim() == target.profileName.trim()
          : log.profileId.trim() == targetProfileId ||
              log.profileName.trim() == target.profileName.trim();
      return logMinute == targetMinute && sameQuestion && sameProfile;
    }

    if (exactCount > 0) {
      // 同じ鑑定が重複保存されていた場合も、画面に残らないよう全件削除する。
      logs.removeWhere((log) => exactMatch(log) || sameDisplayedLog(log));
    } else {
      // 古い保存データや端末側の時刻丸めに対応し、表示上の同じ分を人物名で補完する。
      logs.removeWhere(sameDisplayedLog);
    }
    final next = logs.map((item) => item.toJson()).toList();
    if (next.isEmpty) {
      await prefs.remove(_storageKey);
    } else {
      await prefs.setString(_storageKey, jsonEncode(next));
    }
  }

  static Future<void> clear({String? profileId}) async {
    final prefs = await SharedPreferences.getInstance();
    if (profileId == null) {
      await prefs.remove(_storageKey);
      return;
    }
    final logs = await loadAll();
    final next = logs.where((log) => log.profileId != profileId).toList();
    if (next.isEmpty) {
      await prefs.remove(_storageKey);
    } else {
      await prefs.setString(_storageKey, jsonEncode(next.map((item) => item.toJson()).toList()));
    }
  }
}

class SavedUserProfile {
  const SavedUserProfile({
    required this.id,
    required this.name,
    required this.birthDate,
    required this.details,
    required this.updatedAt,
  });

  static const _storageKey = 'saved_profiles.list';

  final String id;
  final String name;
  final String birthDate;
  final UserProfileDetails details;
  final DateTime updatedAt;

  factory SavedUserProfile.fromProfile(AstroProfile profile, UserProfileDetails details) {
    final name = profile.name.trim().isEmpty ? 'あなた' : profile.name.trim();
    final birthDate = profile.birthDate.trim().isEmpty ? '1980/9/24' : profile.birthDate.trim();
    final profilePlace = profile.birthPlace.trim();
    final savedDetails = details.hasBirthPlace || profilePlace.isEmpty
        ? details
        : UserProfileDetails(
            birthTime: details.birthTime,
            birthPlace: profilePlace,
            personality: details.storedPersonality,
            concerns: details.storedConcerns,
            readingStyle: details.storedReadingStyle,
            useSupplement: details.useSupplement,
          );
    return SavedUserProfile(
      id: profile.savedProfileId?.trim().isNotEmpty == true
          ? profile.savedProfileId!.trim()
          : createId(),
      name: name,
      birthDate: birthDate,
      details: savedDetails,
      updatedAt: DateTime.now(),
    );
  }

  factory SavedUserProfile.fromJson(Map<String, dynamic> json) {
    final name = json['name']?.toString().trim() ?? '';
    final birthDate = json['birthDate']?.toString().trim() ?? '';
    final decodedDetails = UserProfileDetails.fromJson(json['details']);
    final legacyBirthPlace = json['birthPlace']?.toString().trim() ?? '';
    final details = decodedDetails.hasBirthPlace || legacyBirthPlace.isEmpty
        ? decodedDetails
        : UserProfileDetails(
            birthTime: decodedDetails.birthTime,
            birthPlace: legacyBirthPlace,
            personality: decodedDetails.storedPersonality,
            concerns: decodedDetails.storedConcerns,
            readingStyle: decodedDetails.storedReadingStyle,
            useSupplement: decodedDetails.useSupplement,
          );
    return SavedUserProfile(
      id: json['id']?.toString().trim().isNotEmpty == true
          ? json['id'].toString().trim()
          : _idFor(name.isEmpty ? 'あなた' : name, birthDate.isEmpty ? '1980/9/24' : birthDate),
      name: name.isEmpty ? 'あなた' : name,
      birthDate: birthDate.isEmpty ? '1980/9/24' : birthDate,
      details: details,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'birthDate': birthDate,
      'details': details.toJson(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    final profiles = await loadAll();
    final next = [
      this,
      ...profiles.where((profile) => profile.id != id),
    ].take(20).map((profile) => profile.toJson()).toList();
    final encoded = jsonEncode(next);
    final saved = await prefs.setString(_storageKey, encoded);
    if (!saved || prefs.getString(_storageKey) != encoded) {
      throw StateError('保存プロフィールを確認できませんでした。');
    }
  }

  static Future<List<SavedUserProfile>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final profiles = <SavedUserProfile>[];
        for (final item in decoded) {
          if (item is! Map) continue;
          try {
            final profile = SavedUserProfile.fromJson(Map<String, dynamic>.from(item));
            if (profile.name.trim().isNotEmpty) {
              profiles.add(profile);
            }
          } catch (_) {
            continue;
          }
        }
        return profiles..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      }
      if (decoded is Map) {
        final profile = SavedUserProfile.fromJson(Map<String, dynamic>.from(decoded));
        return [profile];
      }
    } on FormatException {
      await prefs.remove(_storageKey);
    } catch (_) {
      return const [];
    }
    return const [];
  }

  static Future<void> delete(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final profiles = await loadAll();
    final next = profiles
        .where((profile) => profile.id != id)
        .map((profile) => profile.toJson())
        .toList();
    if (next.isEmpty) {
      await prefs.remove(_storageKey);
    } else {
      await prefs.setString(_storageKey, jsonEncode(next));
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  static String _idFor(String name, String birthDate) {
    final source = '${name.trim()}|${birthDate.trim()}';
    var hash = 0;
    for (final unit in source.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return 'profile_$hash';
  }

  static String createId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final random = math.Random().nextInt(1 << 31);
    return 'profile_${now}_$random';
  }
}

class UserProfileDetails {
  const UserProfileDetails({
    required this.birthTime,
    required this.birthPlace,
    required String personality,
    required String concerns,
    required String readingStyle,
    this.useSupplement = true,
  })  : _personality = personality,
        _concerns = concerns,
        _readingStyle = readingStyle;

  const UserProfileDetails.empty()
      : birthTime = '',
        birthPlace = '',
        _personality = '',
        _concerns = '',
        _readingStyle = '',
        useSupplement = true;

  factory UserProfileDetails.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return const UserProfileDetails.empty();
    return UserProfileDetails(
      birthTime: json['birthTime']?.toString() ?? '',
      birthPlace: json['birthPlace']?.toString() ?? '',
      personality: json['personality']?.toString() ?? '',
      concerns: json['concerns']?.toString() ?? '',
      readingStyle: json['readingStyle']?.toString() ?? '',
      useSupplement: json['useSupplement'] != false,
    );
  }

  static const _birthTimeKey = 'profile.birthTime';
  static const _birthPlaceKey = 'profile.birthPlace';
  static const _personalityKey = 'profile.personality';
  static const _concernsKey = 'profile.concerns';
  static const _readingStyleKey = 'profile.readingStyle';
  static const _useSupplementKey = 'profile.useSupplement';

  final String birthTime;
  final String birthPlace;
  final String _personality;
  final String _concerns;
  final String _readingStyle;
  final bool useSupplement;

  String get personality => useSupplement ? _personality : '';
  String get concerns => useSupplement ? _concerns : '';
  String get readingStyle => useSupplement ? _readingStyle : '';
  String get storedPersonality => _personality;
  String get storedConcerns => _concerns;
  String get storedReadingStyle => _readingStyle;

  bool get hasBirthTime => birthTime.trim().isNotEmpty;
  bool get hasBirthPlace => birthPlace.trim().isNotEmpty;
  bool get hasExactBirthBase => hasBirthTime && hasBirthPlace;
  String get effectiveBirthTime => hasBirthTime ? birthTime.trim() : '12:00';
  String get effectiveBirthPlace => hasBirthPlace ? birthPlace.trim() : '北海道札幌市';

  bool get hasSupplement =>
      personality.trim().isNotEmpty ||
      concerns.trim().isNotEmpty ||
      readingStyle.trim().isNotEmpty;

  bool get hasAny =>
      birthTime.trim().isNotEmpty ||
      birthPlace.trim().isNotEmpty ||
      hasSupplement;

  Map<String, dynamic> toJson() {
    return {
      'birthTime': birthTime,
      'birthPlace': birthPlace,
      'personality': _personality,
      'concerns': _concerns,
      'readingStyle': _readingStyle,
      'useSupplement': useSupplement,
    };
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_birthTimeKey, birthTime);
    await prefs.setString(_birthPlaceKey, birthPlace);
    await prefs.setString(_personalityKey, _personality);
    await prefs.setString(_concernsKey, _concerns);
    await prefs.setString(_readingStyleKey, _readingStyle);
    await prefs.setBool(_useSupplementKey, useSupplement);
  }

  static Future<UserProfileDetails> load() async {
    final prefs = await SharedPreferences.getInstance();
    return UserProfileDetails(
      birthTime: prefs.getString(_birthTimeKey) ?? '',
      birthPlace: prefs.getString(_birthPlaceKey) ?? '',
      personality: prefs.getString(_personalityKey) ?? '',
      concerns: prefs.getString(_concernsKey) ?? '',
      readingStyle: prefs.getString(_readingStyleKey) ?? '',
      useSupplement: prefs.getBool(_useSupplementKey) ?? true,
    );
  }
}

class _TabItem {
  const _TabItem(this.label, this.icon, this.view, {this.compactLabel});

  final String label;
  final IconData icon;
  final Widget view;
  final String? compactLabel;
}



