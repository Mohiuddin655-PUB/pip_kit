import 'dart:async';

import 'package:flutter/foundation.dart';

import 'pip_content.dart';
import 'pip_options.dart';
import 'pip_platform.dart';

/// Whether the system floating window is on screen.
enum PipStatus { closed, open }

/// Drives the system Picture-in-Picture window.
///
/// The usual sequence:
///
/// 1. [arm] with the content and options while the user is still in the app.
///    With [PipOptions.autoEnter] the window then opens by itself when they
///    leave.
/// 2. [enter] to open it right away.
/// 3. Listen to [status] and [actions].
/// 4. [disarm] when the screen that wanted the window goes away.
///
/// There is one window per app, so use [PipController.instance]. A [PipHost]
/// must be mounted at the root of the app for the content to be drawn.
class PipController {
  PipController._(this._platform, this._targetPlatform) {
    _platform.setHandlers(onStatus: _onStatus, onAction: _actions.add);
  }

  /// A controller over a stand-in platform, for tests.
  @visibleForTesting
  factory PipController.forTesting(
    PipPlatform platform, {
    TargetPlatform? targetPlatform,
  }) =>
      PipController._(platform, targetPlatform);

  static final PipController instance =
      PipController._(MethodChannelPipPlatform(), null);

  final PipPlatform _platform;
  final TargetPlatform? _targetPlatform;

  final ValueNotifier<PipStatus> _status =
      ValueNotifier<PipStatus>(PipStatus.closed);
  final ValueNotifier<PipContent?> _content = ValueNotifier<PipContent?>(null);
  final StreamController<String> _actions =
      StreamController<String>.broadcast();

  PipOptions _options = const PipOptions();
  Completer<void>? _firstFrame;

  /// Open or closed, as reported by the system. The window can close without
  /// the app asking — the user dismisses it, or taps it to return.
  ValueListenable<PipStatus> get status => _status;

  bool get isOpen => _status.value == PipStatus.open;

  /// What the window shows, or null while nothing is armed.
  ValueListenable<PipContent?> get content => _content;

  PipOptions get options => _options;

  /// Ids of [PipAction] buttons as the user taps them. Android only.
  Stream<String> get actions => _actions.stream;

  TargetPlatform get _platformKind => _targetPlatform ?? defaultTargetPlatform;

  /// Whether the platform draws the widget itself in the window (Android), as
  /// opposed to being handed frames or a player layer (iOS).
  bool get drawsContentInApp => _platformKind == TargetPlatform.android;

  /// Whether [content] has to be captured and streamed as frames.
  bool get streamsWidgetFrames =>
      _platformKind == TargetPlatform.iOS &&
      _content.value?.kind == PipContentKind.widget;

  PipPlatform get platform => _platform;

  Future<bool> isSupported() {
    if (_platformKind != TargetPlatform.android &&
        _platformKind != TargetPlatform.iOS) {
      return Future<bool>.value(false);
    }
    return _platform.isSupported();
  }

  /// Sets what the window will show and prepares the system for it.
  ///
  /// Returns false when the system is not ready yet. On iOS with
  /// [PipContent.video] that means no playing video layer is on screen; mount
  /// the player first, or call [enter] later, which prepares again.
  Future<bool> arm(
    PipContent content, {
    PipOptions options = const PipOptions(),
  }) {
    final changed = !identical(_content.value, content);
    _options = options;
    if (changed) {
      _firstFrame = Completer<void>();
      _content.value = content;
    }
    return _configure();
  }

  /// Changes the options of an armed or open window — swapping the action
  /// buttons, for instance.
  Future<bool> updateOptions(PipOptions options) {
    _options = options;
    if (_content.value == null) return Future<bool>.value(false);
    return _configure();
  }

  Future<bool> _configure() {
    final content = _content.value;
    if (content == null) return Future<bool>.value(false);
    return _platform.configure({
      ..._options.toMap(),
      'mode': content.kind == PipContentKind.video ? 'video' : 'widget',
    });
  }

  /// Opens the window, arming first when [content] is given.
  ///
  /// Returns whether the system accepted the request. It can refuse: the user
  /// may have turned Picture in Picture off for the app, or on iOS the video
  /// may not be playing.
  Future<bool> enter({PipContent? content, PipOptions? options}) async {
    if (content != null) {
      await arm(content, options: options ?? _options);
    } else if (options != null) {
      await updateOptions(options);
    }
    if (_content.value == null) {
      throw StateError('PipController.enter needs content: pass it here or '
          'call arm() first.');
    }
    if (isOpen) return true;
    if (streamsWidgetFrames) {
      // The system will not open a window over an empty layer, so wait for the
      // host to deliver the first capture.
      await _firstFrame?.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      );
    }
    return _platform.enter();
  }

  /// Closes the window. On Android this brings the app back to full screen,
  /// which is the only way an app can end its own window there.
  Future<bool> exit() => _platform.exit();

  /// Forgets the content and turns automatic entry off.
  Future<void> disarm() async {
    _content.value = null;
    _firstFrame = null;
    await _platform.release();
  }

  /// Called by [PipHost] once a captured frame has reached the system.
  void markFrameDelivered() {
    final pending = _firstFrame;
    if (pending != null && !pending.isCompleted) pending.complete();
  }

  void _onStatus(bool isOpen) {
    _status.value = isOpen ? PipStatus.open : PipStatus.closed;
  }
}
