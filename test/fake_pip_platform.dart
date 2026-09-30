import 'dart:typed_data';

import 'package:pip_kit/pip_kit.dart';

/// Records what the package asked of the system and lets a test report window
/// state back, the way the platform would.
class FakePipPlatform implements PipPlatform {
  FakePipPlatform({this.supported = true, this.enterSucceeds = true});

  bool supported;
  bool enterSucceeds;

  final List<Map<String, Object?>> configurations = [];
  final List<(int, int)> frames = [];
  int enterCalls = 0;
  int exitCalls = 0;
  int releaseCalls = 0;

  void Function(bool isOpen)? _onStatus;
  void Function(String actionId)? _onAction;

  void reportOpen(bool isOpen) => _onStatus?.call(isOpen);
  void tapAction(String id) => _onAction?.call(id);

  @override
  void setHandlers({
    required void Function(bool isOpen) onStatus,
    required void Function(String actionId) onAction,
  }) {
    _onStatus = onStatus;
    _onAction = onAction;
  }

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<bool> configure(Map<String, Object?> config) async {
    configurations.add(config);
    return true;
  }

  @override
  Future<bool> enter() async {
    enterCalls++;
    if (enterSucceeds) reportOpen(true);
    return enterSucceeds;
  }

  @override
  Future<bool> exit() async {
    exitCalls++;
    reportOpen(false);
    return true;
  }

  @override
  Future<void> release() async => releaseCalls++;

  @override
  Future<void> pushFrame(Uint8List rgba, int width, int height) async {
    frames.add((width, height));
  }
}
