import 'dart:async';

import 'package:flutter/material.dart';

import 'app_language.dart';
import 'app_language_settings.dart';
import 'manual_bgm_controller.dart';

bool _english(BuildContext context) =>
    AppLanguageScope.stringsOf(context).language == AppLanguage.en;

/// Reusable accessible entry point; opening this sheet does not start playback.
class ManualBgmButton extends StatelessWidget {
  const ManualBgmButton({
    super.key,
    required this.controller,
    this.showLabel = false,
  });
  final ManualBgmController controller;
  final bool showLabel;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final english = _english(context);
      final tooltip = english ? 'Background music settings' : 'BGM設定';
      final icon = Icon(
        controller.state.playing ? Icons.music_note : Icons.music_off,
      );
      void open() {
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (context) => SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ManualBgmControls(controller: controller),
            ),
          ),
        );
      }

      if (showLabel) {
        return Tooltip(
          message: tooltip,
          child: TextButton.icon(
            onPressed: open,
            icon: icon,
            label: const Text('BGM'),
          ),
        );
      }
      return IconButton(
        tooltip: tooltip,
        isSelected: controller.state.playing,
        icon: icon,
        onPressed: open,
      );
    },
  );
}

/// Embeddable settings controls. All values stay in memory for this session.
class ManualBgmControls extends StatelessWidget {
  const ManualBgmControls({super.key, required this.controller});
  final ManualBgmController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final english = _english(context);
      final state = controller.state;
      final percent = (state.volume * 100).round();
      final status = state.busy
          ? (english ? 'Preparing…' : '準備中…')
          : state.playing
          ? (english ? 'Playing' : '再生中')
          : (english ? 'Stopped' : '停止中');
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            english ? 'Background music' : 'BGM',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Text('SpringWind', style: Theme.of(context).textTheme.titleMedium),
          Text(
            english
                ? 'Lyrics & music: ぱんちょ\nArrangement: Suno 6.0'
                : '作詞・作曲：ぱんちょ\nアレンジ：Suno 6.0',
          ),
          const SizedBox(height: 8),
          Semantics(liveRegion: true, child: Text(status)),
          if (!controller.supported) ...[
            const SizedBox(height: 8),
            Text(
              english
                  ? 'Background music is available in the Android app.'
                  : 'BGMはAndroidアプリで利用できます。',
            ),
          ] else if (state.errorCode != null) ...[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(
                manualBgmErrorText(state.errorCode!, english: english),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: controller.canPlay && !state.playing
                    ? () => unawaited(controller.play())
                    : null,
                icon: const Icon(Icons.play_arrow),
                label: Text(english ? 'Play' : '再生'),
              ),
              OutlinedButton.icon(
                onPressed: controller.supported && (state.playing || state.busy)
                    ? () => unawaited(controller.stop())
                    : null,
                icon: const Icon(Icons.stop),
                label: Text(english ? 'Stop' : '停止'),
              ),
              if (controller.supported && !controller.initialized)
                TextButton(
                  onPressed: () => unawaited(controller.initialize()),
                  child: Text(english ? 'Retry' : '再試行'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(english ? 'Music volume: $percent%' : 'BGM音量：$percent%'),
          Slider(
            value: state.volume,
            min: 0,
            max: 1,
            divisions: 100,
            label: '$percent%',
            semanticFormatterCallback: (value) => '${(value * 100).round()}%',
            onChanged: controller.supported && controller.initialized
                ? (value) => unawaited(controller.setVolume(value))
                : null,
          ),
          Text(
            english
                ? 'Play starts a loop only when you tap it. Music stops when the app leaves the foreground or audio is interrupted. Tap Play to start again.'
                : '再生を押したときだけ繰り返し再生します。アプリが背景に移る場合や音声が中断される場合は停止します。再開には再生を押してください。',
          ),
          const SizedBox(height: 8),
          Text(
            english
                ? 'Volume is for this music only. Playback and volume are not saved.'
                : 'この曲だけの音量です。再生状態と音量は保存しません。',
          ),
        ],
      );
    },
  );
}

String manualBgmErrorText(String code, {required bool english}) {
  if (code == 'audio_focus_denied') {
    return english
        ? 'Audio is in use. Try Play again when it is available.'
        : '音声を使用できません。ほかの音声が終わってから再生をお試しください。';
  }
  if (code == 'invalid_volume' || code == 'volume_out_of_range') {
    return english ? 'Choose a volume from 0 to 100%.' : '音量は0〜100%で指定してください。';
  }
  if (code == 'unsupported') {
    return english
        ? 'Background music is available in the Android app.'
        : 'BGMはAndroidアプリで利用できます。';
  }
  return english
      ? 'Music could not be played. It has stopped. Please try again.'
      : 'BGMを再生できなかったため停止しました。もう一度お試しください。';
}
