# pip_kit

System Picture in Picture for Flutter, for more than video: put **any widget**,
a **playing video**, or a **self-contained route flow** in the floating window,
on Android and iOS.

<p align="center">
  <img src="https://raw.githubusercontent.com/Mohiuddin655-PUB/pip_kit/main/doc/demo.gif" width="300" alt="pip_kit demo: a live widget with buttons, a route flow and a video in the Picture-in-Picture window" />
</p>

<p align="center">
  <a href="https://github.com/Mohiuddin655-PUB/pip_kit/raw/main/doc/demo.mp4">Watch the demo in full quality</a>
</p>

A live counter driven by buttons on the window, a three-step route flow that
runs only inside the window, and a video — all from the [example app](example/lib/main.dart).

```dart
await PipController.instance.enter(
  content: PipContent.widget((context) => const MyMiniPlayer()),
  options: const PipOptions(aspectRatio: PipAspectRatio.square),
);
```

## Install

```yaml
dependencies:
  pip_kit: ^1.0.1
```

## What each platform can do

The two systems work differently, and the package does not hide that.

| | Android | iOS |
| --- | --- | --- |
| Video | yes | yes |
| Any widget | yes, live | captured as frames (see below) |
| A separate route flow | yes, live | captured as frames |
| Touches inside the window | no | no |
| Custom buttons on the window | yes (`PipAction`) | no — system play/pause only |
| Open automatically on leaving the app | yes | yes |
| Minimum OS | Android 8.0 (API 26) | iOS 15 |

* **Android** shrinks the whole Activity into the window. While it is open,
  `PipHost` covers the app with your content, so anything Flutter can draw
  works and keeps running.
* **iOS** only grants a window to a video layer.
  * `PipContent.video` hands the system the `AVPlayerLayer` already on screen.
  * `PipContent.widget` renders the widget behind the app, captures it, and
    feeds the captures to the system as video frames. It is a picture of the
    widget: **it stops updating once the app is in the background**, because
    Flutter stops producing frames there. Treat it as experimental.
* Neither system delivers touches to the window. On Android, `PipAction`
  buttons are how a user acts on it without returning to the app.

## Setup

### Android

Declare Picture-in-Picture support on the Flutter activity in
`android/app/src/main/AndroidManifest.xml`:

```xml
<activity
    android:name=".MainActivity"
    android:supportsPictureInPicture="true"
    android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
    ...>
```

The `configChanges` list is Flutter's default; it must include `screenSize`,
`smallestScreenSize` and `screenLayout` or the activity restarts when the
window opens.

### iOS

Add the background mode to `ios/Runner/Info.plist`:

```xml
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>
```

The package activates a `.playback` audio session when you arm a window —
iOS requires it even for silent content — so **other audio (music, podcasts)
is interrupted**.

Picture in Picture does not run in the iOS Simulator; `isSupported()` returns
false there. Test on a device.

### Both

Mount the host once, above the app's `Navigator`:

```dart
MaterialApp(
  builder: (context, child) => PipHost(child: child!),
  home: const HomePage(),
);
```

## Usage

```dart
final pip = PipController.instance;

if (!await pip.isSupported()) return;
```

### A widget

```dart
await pip.enter(
  content: PipContent.widget(
    (context) => const TimerCard(),
    background: Colors.black,
  ),
  options: const PipOptions(aspectRatio: PipAspectRatio.square),
);
```

The content is built above the `Navigator`, so there is no `Material` or
`Scaffold` around it. Text gets a plain white default style; wrap the content
in your own `Theme`/`Material` if it needs one.

### A video

```dart
final video = VideoPlayerController.asset(
  'assets/clip.mp4',
  // iOS can only lift a real AVPlayerLayer; video_player provides one in
  // platform-view mode.
  viewType: Platform.isIOS
      ? VideoViewType.platformView
      : VideoViewType.textureView,
);

await pip.enter(
  content: PipContent.video(
    // What Android draws in the window. iOS ignores it and lifts the player
    // that is on screen, so that player must be mounted, visible and playing.
    (context) => Center(
      child: AspectRatio(
        aspectRatio: video.value.aspectRatio,
        child: VideoPlayer(video),
      ),
    ),
  ),
  options: PipOptions(
    aspectRatio: PipAspectRatio.fromSize(video.value.size),
  ),
);
```

`pip_kit` does not depend on a video package; any player works as long as, on
iOS, it renders through an `AVPlayerLayer`. With more than one such layer on
screen the first one found is used.

### A route flow

A nested `Navigator` that exists only in the window. The app's own navigation
stays where the user left it.

```dart
final flow = GlobalKey<NavigatorState>();

await pip.enter(
  content: PipContent.navigator(
    navigatorKey: flow,
    initialRoute: '/step1',
    onGenerateRoute: (settings) => MaterialPageRoute(
      settings: settings,
      builder: (context) => GuideStep(name: settings.name!),
    ),
  ),
  options: const PipOptions(
    actions: [
      PipAction(id: 'next', label: 'Next step', icon: PipActionIcon.next),
    ],
  ),
);

pip.actions.listen((id) {
  if (id == 'next') flow.currentState?.pushNamed('/step2');
});
```

Drive it from outside — an action button, a timer, a stream — since the window
takes no touches.

### Opening automatically

```dart
// Arm while the user is still in the app...
await pip.arm(content, options: const PipOptions(autoEnter: true));
// ...and the window opens by itself when they leave.

// When the screen that wanted it goes away:
await pip.disarm();
```

### Buttons on the window (Android)

```dart
PipOptions(
  actions: const [
    PipAction(id: 'pause', label: 'Pause', icon: PipActionIcon.pause),
    // A drawable from android/app/src/main/res/drawable:
    PipAction(id: 'like', label: 'Like', icon: PipActionIcon.drawable('ic_like')),
  ],
);

// Swap them while the window is open:
await pip.updateOptions(pip.options.copyWith(actions: [...]));
```

The system shows as many as it has room for, usually three.

### Following the window

```dart
pip.status.addListener(() {
  if (pip.status.value == PipStatus.closed) { /* user came back or dismissed */ }
});

await pip.exit(); // Android: brings the app back to full screen.
```

## Options

| `PipOptions` | Applies to | |
| --- | --- | --- |
| `aspectRatio` | both | Android clamps to 1:2.39 – 2.39:1. iOS video takes its shape from the video. |
| `autoEnter` | both | Open when the user leaves the app. |
| `actions` | Android | Buttons on the window. |
| `seamlessResize` | Android 12+ | Turn off for content that does not scale cleanly. |
| `title`, `subtitle` | Android 13+ | |
| `widgetFrameRate` | iOS widget | Captures per second, default 15. |
| `widgetCaptureWidth` | iOS widget | Logical width the widget is laid out at, default 360. |
| `widgetPixelRatio` | iOS widget | Capture resolution multiplier, default 2. |

## Testing your own code

`PipController.forTesting` takes any `PipPlatform`, so screens that use Picture
in Picture can be tested without a device:

```dart
final pip = PipController.forTesting(MyFakePlatform());
await tester.pumpWidget(PipHost(controller: pip, child: const MyApp()));
```

## Verification status

* **Android:** widget, video, route flow, action buttons, automatic entry and
  returning to the app were run on an emulator (API 37, Pixel launcher).
* **iOS:** the plugin compiles and the Dart side is unit tested, but nothing
  has been run on an iPhone. Verify video and widget content on a device
  before relying on them.
