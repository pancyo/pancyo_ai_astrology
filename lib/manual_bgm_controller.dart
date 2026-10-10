import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Ephemeral player state. Neither playback nor volume is persisted.
@immutable
class ManualBgmState {
  const ManualBgmState({
    this.playing = false,
    this.busy = false,
    this.errorCode,
    this.volume = .35,
  });

  final bool playing;
  final bool busy;
  final String? errorCode;
  final double volume;

  static ManualBgmState decode(Object? value) {
    if (value is! Map ||
        value['playing'] is! bool ||
        value['busy'] is! bool ||
        (value['errorCode'] != null && value['errorCode'] is! String) ||
        value['volume'] is! num) {
      throw const FormatException('invalid_state');
    }
    final volume = (value['volume'] as num).toDouble();
    if (!volume.isFinite || volume < 0 || volume > 1) {
      throw const FormatException('invalid_state');
    }
    final error = value['errorCode'] as String?;
    return ManualBgmState(
      playing: value['playing'] as bool,
      busy: value['busy'] as bool,
      errorCode: error == null ? null : _safeError(error),
      volume: volume,
    );
  }

  static String _safeError(String value) =>
      RegExp(r'^[a-z0-9_]{1,80}$').hasMatch(value) ? value : 'playback_failed';
}

/// Android's foreground-only player. Only [play] can request playback.
///
/// Channel/stream injection is for focused tests; it does not prove native
/// playback. Native code also cancels preparation and releases audio focus.
class ManualBgmController extends ChangeNotifier with WidgetsBindingObserver {
  ManualBgmController({
    MethodChannel channel = const MethodChannel(
      'com.pancyo.aiastrology/manual_bgm',
    ),
    EventChannel events = const EventChannel(
      'com.pancyo.aiastrology/manual_bgm/events',
    ),
    bool? supported,
    Stream<Object?>? stateEvents,
  }) : _channel = channel,
       _events = events,
       _stateEvents = stateEvents,
       _supported =
           supported ??
           (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  final MethodChannel _channel;
  final EventChannel _events;
  final Stream<Object?>? _stateEvents;
  bool _supported;
  bool _initialized = false;
  bool _disposed = false;
  bool _foreground = true;
  bool _desiredPlaying = false;
  bool _observing = false;
  bool _safetyStopping = false;
  int _command = 0;
  int _eventRevision = 0;
  int _volumeRevision = 0;
  Future<void>? _initialization;
  StreamSubscription<Object?>? _subscription;
  ManualBgmState _state = const ManualBgmState();

  ManualBgmState get state => _state;
  bool get supported => _supported;
  bool get initialized => _initialized;
  bool get canPlay => _supported && _initialized && _foreground && !_state.busy;

  /// Always resets to OFF and 35%; initialization never calls play.
  Future<void> initialize() {
    if (_disposed || !_supported || _initialized) return Future.value();
    return _initialization ??= _initialize().whenComplete(() {
      _initialization = null;
    });
  }

  Future<void> _initialize() async {
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    }
    final token = ++_command;
    _desiredPlaying = false;
    try {
      ManualBgmState.decode(await _channel.invokeMethod<Object?>('stop'));
      if (_disposed || token != _command) return;
      ManualBgmState.decode(
        await _channel.invokeMethod<Object?>('setVolume', {'value': .35}),
      );
      if (_disposed || token != _command) return;
      final result = ManualBgmState.decode(
        await _channel.invokeMethod<Object?>('getState'),
      );
      if (_disposed || token != _command) return;
      if (result.playing ||
          result.busy ||
          result.errorCode != null ||
          result.volume != .35) {
        throw const FormatException('invalid_state');
      }
      _initialized = true;
      _publish(const ManualBgmState());
      _subscription ??= (_stateEvents ?? _events.receiveBroadcastStream())
          .listen(
            _onEvent,
            onError: (Object error) {
              _fail(error);
              _ensureStopped();
            },
          );
    } catch (error) {
      if (!_disposed && token == _command) _fail(error);
      _ensureStopped();
    }
  }

  /// Invoke only from a user gesture. A stopped/focus-lost player never resumes.
  Future<void> play() async {
    if (_disposed || !canPlay || _state.playing) return;
    final token = ++_command;
    final eventRevision = _eventRevision;
    _desiredPlaying = true;
    _publish(ManualBgmState(busy: true, volume: _state.volume));
    try {
      final result = ManualBgmState.decode(
        await _channel.invokeMethod<Object?>('play', {'loop': true}),
      );
      if (_disposed || token != _command) return;
      // The event channel can deliver preparation completion before the
      // initial busy method return. Keep the more recent event state.
      if (_eventRevision != eventRevision) return;
      _accept(result);
    } catch (error) {
      if (!_disposed && token == _command) {
        _fail(error);
        _ensureStopped();
      }
    }
  }

  /// Does not await an outstanding prepare/play/volume call.
  Future<void> stop() async {
    if (_disposed) return;
    final token = ++_command;
    _desiredPlaying = false;
    _publish(ManualBgmState(volume: _state.volume));
    if (!_supported) return;
    try {
      final result = ManualBgmState.decode(
        await _channel.invokeMethod<Object?>('stop'),
      );
      if (_disposed || token != _command) return;
      if (result.playing || result.busy) {
        throw const FormatException('invalid_state');
      }
      _publish(
        ManualBgmState(errorCode: result.errorCode, volume: _state.volume),
      );
    } catch (error) {
      if (!_disposed && token == _command) _fail(error);
    }
  }

  /// This is this track's scalar volume, not the device/system volume.
  Future<void> setVolume(double value) async {
    if (_disposed || !_supported || !_initialized) return;
    if (!value.isFinite) {
      _publish(
        ManualBgmState(
          playing: _state.playing,
          busy: _state.busy,
          errorCode: 'invalid_volume',
          volume: _state.volume,
        ),
      );
      return;
    }
    final clamped = value.clamp(0.0, 1.0);
    final revision = ++_volumeRevision;
    _publish(
      ManualBgmState(
        playing: _state.playing,
        busy: _state.busy,
        volume: clamped,
      ),
    );
    try {
      final result = ManualBgmState.decode(
        await _channel.invokeMethod<Object?>('setVolume', {'value': clamped}),
      );
      if (_disposed || revision != _volumeRevision) return;
      // Playback state is delivered by play/stop/events. A delayed volume
      // response must not resurrect playback after stop.
      _publish(
        ManualBgmState(
          playing: _state.playing,
          busy: _state.busy,
          errorCode: result.errorCode,
          volume: result.volume,
        ),
      );
    } catch (error) {
      if (!_disposed && revision == _volumeRevision) {
        _fail(error);
        _ensureStopped();
      }
    }
  }

  void _onEvent(Object? value) {
    if (_disposed || !_initialized) return;
    _eventRevision++;
    try {
      _accept(ManualBgmState.decode(value));
    } catch (error) {
      _fail(error);
      _ensureStopped();
    }
  }

  void _accept(ManualBgmState next) {
    if ((next.playing || next.busy) && (!_desiredPlaying || !_foreground)) {
      _ensureStopped();
      return;
    }
    if (!next.playing && !next.busy) _desiredPlaying = false;
    _publish(
      ManualBgmState(
        playing: next.playing,
        busy: next.busy,
        errorCode: next.errorCode,
        volume: _state.volume,
      ),
    );
  }

  void _ensureStopped() {
    if (_disposed || !_supported || _safetyStopping) return;
    _safetyStopping = true;
    final error = _state.errorCode;
    unawaited(
      stop().whenComplete(() {
        _safetyStopping = false;
        if (!_disposed &&
            !_desiredPlaying &&
            error != null &&
            _state.errorCode == null) {
          _publish(ManualBgmState(errorCode: error, volume: _state.volume));
        }
      }),
    );
  }

  void _fail(Object error) {
    _desiredPlaying = false;
    final String code;
    if (error is MissingPluginException) {
      _supported = false;
      code = 'unsupported';
      // A method bridge may survive a missing event bridge. Still clean up.
      _stopWithoutState();
    } else if (error is FormatException) {
      code = 'invalid_state';
    } else if (error is PlatformException) {
      code = ManualBgmState._safeError(error.code);
    } else {
      code = 'channel_failure';
    }
    _publish(ManualBgmState(errorCode: code, volume: _state.volume));
  }

  void _publish(ManualBgmState value) {
    if (_disposed) return;
    _state = value;
    notifyListeners();
  }

  void _stopWithoutState() {
    unawaited(
      _channel
          .invokeMethod<Object?>('stop')
          .then<void>((_) {}, onError: (Object _, StackTrace __) {}),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) unawaited(stop());
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _command++;
    _volumeRevision++;
    _desiredPlaying = false;
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription?.cancel());
    if (_supported) _stopWithoutState();
    super.dispose();
  }
}
