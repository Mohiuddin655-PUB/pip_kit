import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// The shape of the floating window, as a whole-number ratio.
///
/// Android only accepts ratios between 1:2.39 and 2.39:1 and clamps anything
/// outside that range. iOS takes the shape from the content itself (the video,
/// or the captured widget), so there it only sizes the widget capture.
@immutable
class PipAspectRatio {
  const PipAspectRatio(this.width, this.height)
      : assert(width > 0 && height > 0, 'An aspect ratio needs positive sides');

  /// The nearest whole-number ratio to [size].
  factory PipAspectRatio.fromSize(Size size) {
    if (size.width <= 0 || size.height <= 0) return portrait;
    return PipAspectRatio(size.width.round(), size.height.round());
  }

  static const PipAspectRatio portrait = PipAspectRatio(9, 16);
  static const PipAspectRatio landscape = PipAspectRatio(16, 9);
  static const PipAspectRatio square = PipAspectRatio(1, 1);

  final int width;
  final int height;

  double get value => width / height;

  @override
  bool operator ==(Object other) =>
      other is PipAspectRatio && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'PipAspectRatio($width:$height)';
}

/// The picture on a [PipAction] button.
///
/// Android draws window actions from drawable resources only, so an icon is
/// either one of the built-in system glyphs below or a drawable that ships in
/// the host app (`android/app/src/main/res/drawable`).
@immutable
class PipActionIcon {
  const PipActionIcon._(this.name);

  /// A drawable resource of the host app, by name without extension.
  const PipActionIcon.drawable(String resourceName) : name = 'res:$resourceName';

  static const PipActionIcon play = PipActionIcon._('play');
  static const PipActionIcon pause = PipActionIcon._('pause');
  static const PipActionIcon next = PipActionIcon._('next');
  static const PipActionIcon previous = PipActionIcon._('previous');
  static const PipActionIcon rewind = PipActionIcon._('rewind');
  static const PipActionIcon fastForward = PipActionIcon._('fastForward');
  static const PipActionIcon close = PipActionIcon._('close');
  static const PipActionIcon add = PipActionIcon._('add');
  static const PipActionIcon delete = PipActionIcon._('delete');
  static const PipActionIcon info = PipActionIcon._('info');
  static const PipActionIcon share = PipActionIcon._('share');
  static const PipActionIcon send = PipActionIcon._('send');

  final String name;

  @override
  bool operator ==(Object other) => other is PipActionIcon && other.name == name;

  @override
  int get hashCode => name.hashCode;
}

/// A button on the floating window.
///
/// Android only. The window itself takes no touches, so these buttons are the
/// one way a user can act on it without returning to the app. A tap arrives on
/// [PipController.actions] as [id]. The system decides how many it shows
/// (usually three); extra actions are dropped.
@immutable
class PipAction {
  const PipAction({
    required this.id,
    required this.label,
    required this.icon,
    this.enabled = true,
  });

  final String id;

  /// Read by accessibility services; not drawn.
  final String label;
  final PipActionIcon icon;
  final bool enabled;

  Map<String, Object?> toMap() => {
        'id': id,
        'label': label,
        'icon': icon.name,
        'enabled': enabled,
      };

  @override
  bool operator ==(Object other) =>
      other is PipAction &&
      other.id == id &&
      other.label == label &&
      other.icon == icon &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(id, label, icon, enabled);
}

/// How the floating window looks and behaves.
@immutable
class PipOptions {
  const PipOptions({
    this.aspectRatio = PipAspectRatio.portrait,
    this.autoEnter = false,
    this.actions = const <PipAction>[],
    this.seamlessResize = true,
    this.title,
    this.subtitle,
    this.widgetFrameRate = 15,
    this.widgetCaptureWidth = 360,
    this.widgetPixelRatio = 2,
  })  : assert(widgetFrameRate > 0 && widgetFrameRate <= 60),
        assert(widgetCaptureWidth > 0),
        assert(widgetPixelRatio > 0);

  final PipAspectRatio aspectRatio;

  /// Open the window by itself when the user leaves the app, the way a video
  /// app does. When false the window only opens through [PipController.enter].
  final bool autoEnter;

  /// Android only. See [PipAction].
  final List<PipAction> actions;

  /// Android 12+. Lets the system resize the window smoothly; turn it off for
  /// content that does not scale cleanly, such as text-heavy layouts.
  final bool seamlessResize;

  /// Android 13+. Shown by launchers that surface a window title.
  final String? title;
  final String? subtitle;

  /// iOS widget content only: how many times a second the widget is captured
  /// and handed to the system.
  final int widgetFrameRate;

  /// iOS widget content only: the logical width the widget is laid out at for
  /// capture. Its height follows [aspectRatio].
  final double widgetCaptureWidth;

  /// iOS widget content only: capture resolution multiplier.
  final double widgetPixelRatio;

  PipOptions copyWith({
    PipAspectRatio? aspectRatio,
    bool? autoEnter,
    List<PipAction>? actions,
    bool? seamlessResize,
    String? title,
    String? subtitle,
    int? widgetFrameRate,
    double? widgetCaptureWidth,
    double? widgetPixelRatio,
  }) {
    return PipOptions(
      aspectRatio: aspectRatio ?? this.aspectRatio,
      autoEnter: autoEnter ?? this.autoEnter,
      actions: actions ?? this.actions,
      seamlessResize: seamlessResize ?? this.seamlessResize,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      widgetFrameRate: widgetFrameRate ?? this.widgetFrameRate,
      widgetCaptureWidth: widgetCaptureWidth ?? this.widgetCaptureWidth,
      widgetPixelRatio: widgetPixelRatio ?? this.widgetPixelRatio,
    );
  }

  Map<String, Object?> toMap() => {
        'aspectRatioWidth': aspectRatio.width,
        'aspectRatioHeight': aspectRatio.height,
        'autoEnter': autoEnter,
        'actions': [for (final action in actions) action.toMap()],
        'seamlessResize': seamlessResize,
        'title': title,
        'subtitle': subtitle,
      };
}
