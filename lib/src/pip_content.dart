import 'package:flutter/widgets.dart';

/// How a [PipContent] reaches the floating window.
enum PipContentKind {
  /// Any widget tree.
  widget,

  /// A video that is already playing on screen through a native player layer.
  video,
}

/// What the floating window shows.
///
/// The two platforms put content in the window in different ways, and the kind
/// picks the right one for each:
///
/// | | Android | iOS |
/// | --- | --- | --- |
/// | [PipContent.widget] | [builder] drawn live in the window | [builder] captured frame by frame (see below) |
/// | [PipContent.video] | [builder] drawn live in the window | the on-screen `AVPlayerLayer` is lifted by the system |
///
/// On Android the whole Activity shrinks into the window, so [PipHost] swaps
/// the app for [builder] while it is open — any widget, including a nested
/// `Navigator`, works and keeps running.
///
/// iOS only ever grants a window to a video layer. For [PipContent.video] that
/// is the player layer already on screen, and [builder] is not used. For
/// [PipContent.widget] the widget is rendered off to the side, captured, and
/// fed to the system as video frames; it is a picture of the widget, so it
/// takes no touches, and it stops updating once the app is in the background
/// because Flutter stops producing frames there.
@immutable
class PipContent {
  /// Any widget. Interactive nowhere — the system window takes no touches on
  /// either platform — but fully live on Android.
  const PipContent.widget(
    this.builder, {
    this.background = const Color(0xFF000000),
  }) : kind = PipContentKind.widget;

  /// A playing video.
  ///
  /// On iOS the player must be rendering through a real `AVPlayerLayer` that is
  /// mounted and visible when the window is armed — `video_player` does this
  /// with `viewType: VideoViewType.platformView`. [builder] is what Android
  /// draws in the window, normally the same player widget.
  const PipContent.video(
    this.builder, {
    this.background = const Color(0xFF000000),
  }) : kind = PipContentKind.video;

  /// A self-contained flow with its own route stack.
  ///
  /// The window shows a nested [Navigator], separate from the app's own, so a
  /// different sequence of screens can run in the window while the app's
  /// navigation stays where the user left it. Drive it from outside through
  /// [navigatorKey] — for example from a [PipAction], a timer or a stream —
  /// because the window itself takes no touches.
  factory PipContent.navigator({
    required RouteFactory onGenerateRoute,
    GlobalKey<NavigatorState>? navigatorKey,
    String initialRoute = Navigator.defaultRouteName,
    List<NavigatorObserver> observers = const <NavigatorObserver>[],
    Color background = const Color(0xFF000000),
  }) {
    return PipContent.widget(
      (context) => Navigator(
        key: navigatorKey,
        initialRoute: initialRoute,
        onGenerateRoute: onGenerateRoute,
        observers: observers,
      ),
      background: background,
    );
  }

  final WidgetBuilder builder;
  final PipContentKind kind;

  /// Painted behind [builder], and visible wherever it does not fill the
  /// window.
  final Color background;
}
