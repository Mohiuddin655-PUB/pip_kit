import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The native half of the package.
///
/// An interface so an app, or this package's own tests, can stand in a fake
/// and exercise Picture in Picture logic with no platform channel.
abstract class PipPlatform {
  /// Whether this device and OS version can show a floating window at all.
  Future<bool> isSupported();

  /// Hands the system everything it needs before a window can open. Safe to
  /// call again to change options while armed or open.
  Future<bool> configure(Map<String, Object?> config);

  Future<bool> enter();

  Future<bool> exit();

  /// Turns automatic entry off and lets go of any native resources.
  Future<void> release();

  /// iOS widget content: one captured frame, as straight RGBA bytes.
  Future<void> pushFrame(Uint8List rgba, int width, int height);

  /// Registers the callbacks the platform reports back on.
  void setHandlers({
    required void Function(bool isOpen) onStatus,
    required void Function(String actionId) onAction,
  });
}

class MethodChannelPipPlatform implements PipPlatform {
  MethodChannelPipPlatform() {
    _channel.setMethodCallHandler(_onCall);
  }

  static const MethodChannel _channel = MethodChannel('pip_kit');

  void Function(bool isOpen)? _onStatus;
  void Function(String actionId)? _onAction;

  Future<void> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'onStatus':
        _onStatus?.call(call.arguments == true);
      case 'onAction':
        final id = call.arguments;
        if (id is String) _onAction?.call(id);
    }
  }

  @override
  void setHandlers({
    required void Function(bool isOpen) onStatus,
    required void Function(String actionId) onAction,
  }) {
    _onStatus = onStatus;
    _onAction = onAction;
  }

  Future<bool> _invokeBool(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<bool>(method, arguments) ?? false;
    } on MissingPluginException {
      // No native side on this platform (web, desktop, a unit test).
      return false;
    } on PlatformException catch (error) {
      debugPrint('pip_kit: $method failed: ${error.message}');
      return false;
    }
  }

  @override
  Future<bool> isSupported() => _invokeBool('isSupported');

  @override
  Future<bool> configure(Map<String, Object?> config) =>
      _invokeBool('configure', config);

  @override
  Future<bool> enter() => _invokeBool('enter');

  @override
  Future<bool> exit() => _invokeBool('exit');

  @override
  Future<void> release() async {
    await _invokeBool('release');
  }

  @override
  Future<void> pushFrame(Uint8List rgba, int width, int height) async {
    await _invokeBool('pushFrame', {
      'bytes': rgba,
      'width': width,
      'height': height,
    });
  }
}
