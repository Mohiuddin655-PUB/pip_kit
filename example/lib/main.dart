import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pip_kit/pip_kit.dart';
import 'package:video_player/video_player.dart';

void main() => runApp(const PipKitExampleApp());

class PipKitExampleApp extends StatelessWidget {
  const PipKitExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'pip_kit example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple, useMaterial3: true),
      // The host goes above the Navigator so the window can show something
      // other than the current route.
      builder: (context, child) => PipHost(child: child!),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final PipController _pip = PipController.instance;
  final ValueNotifier<int> _counter = ValueNotifier<int>(0);
  final GlobalKey<NavigatorState> _flowKey = GlobalKey<NavigatorState>();

  StreamSubscription<String>? _actions;
  VideoPlayerController? _video;
  bool _supported = false;
  bool _autoEnter = false;
  int _flowStep = 1;
  String _lastAction = '-';

  static const int _flowSteps = 3;

  @override
  void initState() {
    super.initState();
    _pip.status.addListener(_refresh);
    _actions = _pip.actions.listen(_onAction);
    unawaited(_boot());
  }

  Future<void> _boot() async {
    final supported = await _pip.isSupported();

    // iOS can only lift a real AVPlayerLayer into the window, which
    // video_player provides in platform-view mode.
    final video = VideoPlayerController.asset(
      'assets/sample.mp4',
      viewType: defaultTargetPlatform == TargetPlatform.iOS
          ? VideoViewType.platformView
          : VideoViewType.textureView,
    );
    await video.initialize();
    await video.setLooping(true);
    await video.setVolume(0);
    await video.play();

    if (!mounted) {
      await video.dispose();
      return;
    }
    setState(() {
      _supported = supported;
      _video = video;
    });
  }

  @override
  void dispose() {
    _pip.status.removeListener(_refresh);
    unawaited(_actions?.cancel());
    unawaited(_pip.disarm());
    unawaited(_video?.dispose());
    _counter.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _onAction(String id) {
    setState(() => _lastAction = id);
    switch (id) {
      case 'increment':
        _counter.value++;
      case 'reset':
        _counter.value = 0;
      case 'next':
        if (_flowStep < _flowSteps) {
          _flowStep++;
          _flowKey.currentState?.pushNamed('/step$_flowStep');
          unawaited(_pip.updateOptions(_flowOptions()));
        }
      case 'back':
        if (_flowStep > 1) {
          _flowStep--;
          _flowKey.currentState?.pop();
          unawaited(_pip.updateOptions(_flowOptions()));
        }
    }
  }

  // ---------------------------------------------------------------------------
  // The three kinds of content
  // ---------------------------------------------------------------------------

  /// Any widget, live, with buttons on the window that change it.
  Future<void> _openWidget() async {
    await _pip.enter(
      content: PipContent.widget(
        (context) => CounterCard(counter: _counter),
        background: const Color(0xFF1B1033),
      ),
      options: PipOptions(
        aspectRatio: PipAspectRatio.square,
        autoEnter: _autoEnter,
        actions: const [
          PipAction(id: 'reset', label: 'Reset', icon: PipActionIcon.delete),
          PipAction(id: 'increment', label: 'Add one', icon: PipActionIcon.add),
        ],
      ),
    );
  }

  /// A playing video. iOS lifts the on-screen player layer; Android draws the
  /// builder.
  Future<void> _openVideo() async {
    final video = _video;
    if (video == null) return;
    await _pip.enter(
      content: PipContent.video(
        (context) => Center(
          child: AspectRatio(
            aspectRatio: video.value.aspectRatio,
            child: VideoPlayer(video),
          ),
        ),
      ),
      options: PipOptions(
        aspectRatio: PipAspectRatio.fromSize(video.value.size),
        autoEnter: _autoEnter,
      ),
    );
  }

  PipOptions _flowOptions() => PipOptions(
        aspectRatio: PipAspectRatio.portrait,
        autoEnter: _autoEnter,
        actions: [
          PipAction(
            id: 'back',
            label: 'Previous step',
            icon: PipActionIcon.previous,
            enabled: _flowStep > 1,
          ),
          PipAction(
            id: 'next',
            label: 'Next step',
            icon: PipActionIcon.next,
            enabled: _flowStep < _flowSteps,
          ),
        ],
      );

  /// A separate route stack that only exists in the window.
  Future<void> _openFlow() async {
    _flowStep = 1;
    await _pip.enter(
      content: PipContent.navigator(
        navigatorKey: _flowKey,
        initialRoute: '/step1',
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (context) => FlowStep(name: settings.name ?? '/step1'),
        ),
      ),
      options: _flowOptions(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final video = _video;
    return Scaffold(
      appBar: AppBar(title: const Text('pip_kit')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Supported: $_supported   Window: ${_pip.status.value.name}   '
            'Last action: $_lastAction',
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Open automatically when leaving the app'),
            value: _autoEnter,
            onChanged: (value) => setState(() => _autoEnter = value),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _supported ? _openWidget : null,
            child: const Text('Widget in the window'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _supported && video != null ? _openVideo : null,
            child: const Text('Video in the window'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _supported ? _openFlow : null,
            child: const Text('Route flow in the window'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => unawaited(_pip.disarm()),
            child: const Text('Disarm'),
          ),
          const SizedBox(height: 24),
          const Text('The video, playing in the app:'),
          const SizedBox(height: 8),
          SizedBox(
            height: 240,
            child: video == null
                ? const Center(child: CircularProgressIndicator())
                : Center(
                    child: AspectRatio(
                      aspectRatio: video.value.aspectRatio,
                      child: VideoPlayer(video),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// A widget that keeps changing, to show the window is live.
class CounterCard extends StatelessWidget {
  const CounterCard({super.key, required this.counter});

  final ValueListenable<int> counter;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FittedBox(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'COUNTER',
                style: TextStyle(color: Colors.white70, letterSpacing: 2),
              ),
              ValueListenableBuilder<int>(
                valueListenable: counter,
                builder: (context, value, _) => Text(
                  '$value',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 64,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const _Clock(),
            ],
          ),
        ),
      ),
    );
  }
}

class _Clock extends StatefulWidget {
  const _Clock();

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  late final Timer _timer =
      Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));

  @override
  void initState() {
    super.initState();
    _timer; // Start ticking.
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return Text(
      '${two(now.hour)}:${two(now.minute)}:${two(now.second)}',
      style: const TextStyle(color: Colors.white70, fontSize: 18),
    );
  }
}

/// One screen of the flow that runs inside the window.
class FlowStep extends StatelessWidget {
  const FlowStep({super.key, required this.name});

  final String name;

  static const Map<String, (String, Color)> _steps = {
    '/step1': ('Step 1\nOpen Settings', Color(0xFF0D47A1)),
    '/step2': ('Step 2\nTap Display', Color(0xFF1B5E20)),
    '/step3': ('Step 3\nDone!', Color(0xFFB71C1C)),
  };

  @override
  Widget build(BuildContext context) {
    final (label, color) = _steps[name] ?? ('Unknown', Colors.black);
    return ColoredBox(
      color: color,
      child: Center(
        child: FittedBox(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
