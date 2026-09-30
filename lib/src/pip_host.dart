import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'pip_content.dart';
import 'pip_controller.dart';

/// Draws the floating window's content. Mount it once, above everything:
///
/// ```dart
/// MaterialApp(
///   builder: (context, child) => PipHost(child: child!),
/// )
/// ```
///
/// Placed there it sits above the app's `Navigator`, which is what lets the
/// window show something other than the current route.
///
/// * On Android the whole Activity becomes the window, so while it is open the
///   host covers the app with the armed [PipContent]. The app stays mounted
///   underneath and is exactly as it was when the window closes.
/// * On iOS with widget content, the host lays the content out behind the app
///   and streams captures of it to the system.
/// * Otherwise it is transparent.
class PipHost extends StatefulWidget {
  const PipHost({super.key, required this.child, this.controller});

  final Widget child;

  /// Defaults to [PipController.instance].
  final PipController? controller;

  @override
  State<PipHost> createState() => _PipHostState();
}

class _PipHostState extends State<PipHost> {
  final GlobalKey _childKey = GlobalKey(debugLabel: 'PipHost child');
  final GlobalKey _captureKey = GlobalKey(debugLabel: 'PipHost capture');

  Timer? _captureTimer;
  bool _capturing = false;

  PipController get _controller => widget.controller ?? PipController.instance;

  @override
  void initState() {
    super.initState();
    _attach(_controller);
  }

  @override
  void didUpdateWidget(PipHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = oldWidget.controller ?? PipController.instance;
    if (!identical(previous, _controller)) {
      _detach(previous);
      _attach(_controller);
    }
  }

  @override
  void dispose() {
    _detach(_controller);
    _stopCapture();
    super.dispose();
  }

  void _attach(PipController controller) {
    controller.status.addListener(_onChanged);
    controller.content.addListener(_onChanged);
    _syncCapture();
  }

  void _detach(PipController controller) {
    controller.status.removeListener(_onChanged);
    controller.content.removeListener(_onChanged);
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
    _syncCapture();
  }

  // ---------------------------------------------------------------------------
  // iOS widget capture
  // ---------------------------------------------------------------------------

  void _syncCapture() {
    if (!_controller.streamsWidgetFrames) {
      _stopCapture();
      return;
    }
    final interval = Duration(
      microseconds:
          Duration.microsecondsPerSecond ~/ _controller.options.widgetFrameRate,
    );
    _captureTimer?.cancel();
    _captureTimer = Timer.periodic(interval, (_) => unawaited(_capture()));
  }

  void _stopCapture() {
    _captureTimer?.cancel();
    _captureTimer = null;
  }

  Future<void> _capture() async {
    // A slow capture must not queue up behind itself.
    if (_capturing || !mounted) return;
    final boundary = _captureKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary || !boundary.hasSize) return;

    _capturing = true;
    ui.Image? image;
    try {
      image = await boundary.toImage(
        pixelRatio: _controller.options.widgetPixelRatio,
      );
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bytes == null) return;
      await _controller.platform.pushFrame(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        image.width,
        image.height,
      );
      _controller.markFrameDelivered();
    } catch (_) {
      // The boundary was not painted yet, or the engine cannot rasterise right
      // now (the app is in the background). The next tick tries again.
    } finally {
      image?.dispose();
      _capturing = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final content = controller.content.value;
    final coversApp =
        content != null && controller.drawsContentInApp && controller.isOpen;
    final captures = content != null && controller.streamsWidgetFrames;

    // The child keeps one GlobalKey across every arrangement, so arming or
    // opening a window never rebuilds the app from scratch.
    return Stack(
      // Non-directional: this sits above the app's own Directionality.
      alignment: Alignment.topLeft,
      fit: StackFit.expand,
      children: [
        if (captures) _buildCaptureLayer(content),
        KeyedSubtree(key: _childKey, child: widget.child),
        if (coversApp) _PipSurface(content: content),
      ],
    );
  }

  /// The content laid out at the window's shape, behind the app. It is painted
  /// like anything else, which is what makes it capturable, but the app on top
  /// hides it.
  Widget _buildCaptureLayer(PipContent content) {
    final options = _controller.options;
    final width = options.widgetCaptureWidth;
    final height = width / options.aspectRatio.value;
    return Positioned(
      left: 0,
      top: 0,
      width: width,
      height: height,
      child: IgnorePointer(
        child: RepaintBoundary(
          key: _captureKey,
          child: _PipSurface(content: content),
        ),
      ),
    );
  }
}

class _PipSurface extends StatelessWidget {
  const _PipSurface({required this.content});

  final PipContent content;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: content.background,
      // Above the Navigator there is no Material, so bare Text would fall back
      // to the framework's red-and-yellow error style.
      child: DefaultTextStyle(
        style: const TextStyle(
          color: Color(0xFFFFFFFF),
          fontSize: 14,
          fontWeight: FontWeight.normal,
          decoration: TextDecoration.none,
        ),
        child: Builder(builder: content.builder),
      ),
    );
  }
}
