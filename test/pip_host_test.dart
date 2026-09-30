import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pip_kit/pip_kit.dart';

import 'fake_pip_platform.dart';

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int builds = 0;
  int value = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => value++),
      child: Text('app $value'),
    );
  }
}

void main() {
  late FakePipPlatform platform;

  Future<PipController> pump(
    WidgetTester tester, {
    TargetPlatform target = TargetPlatform.android,
  }) async {
    final controller =
        PipController.forTesting(platform, targetPlatform: target);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: PipHost(controller: controller, child: const _Counter()),
      ),
    );
    return controller;
  }

  setUp(() => platform = FakePipPlatform());

  testWidgets('shows only the app while no window is open', (tester) async {
    final controller = await pump(tester);
    await controller.arm(PipContent.widget((context) => const Text('window')));
    await tester.pump();

    expect(find.text('app 0'), findsOneWidget);
    expect(find.text('window'), findsNothing);
  });

  testWidgets('Android covers the app with the content while open',
      (tester) async {
    final controller = await pump(tester);
    await controller.enter(
      content: PipContent.widget((context) => const Text('window')),
    );
    await tester.pump();

    expect(find.text('window'), findsOneWidget);

    platform.reportOpen(false);
    await tester.pump();
    expect(find.text('window'), findsNothing);
  });

  testWidgets('the app keeps its state through a window', (tester) async {
    final controller = await pump(tester);
    await tester.tap(find.text('app 0'));
    await tester.pump();
    expect(find.text('app 1'), findsOneWidget);

    await controller.enter(
      content: PipContent.widget((context) => const Text('window')),
    );
    await tester.pump();
    platform.reportOpen(false);
    await tester.pump();
    await controller.disarm();
    await tester.pump();

    // Rebuilt from scratch it would read "app 0" again.
    expect(find.text('app 1'), findsOneWidget);
  });

  testWidgets('a route flow runs on its own navigator inside the window',
      (tester) async {
    final flow = GlobalKey<NavigatorState>();
    final controller = await pump(tester);
    await controller.enter(
      content: PipContent.navigator(
        navigatorKey: flow,
        initialRoute: '/one',
        onGenerateRoute: (settings) => PageRouteBuilder<void>(
          settings: settings,
          pageBuilder: (context, _, _) => Text('step ${settings.name}'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('step /one'), findsOneWidget);

    flow.currentState!.pushNamed('/two');
    await tester.pumpAndSettle();
    expect(find.text('step /two'), findsOneWidget);
    // The app underneath never moved.
    expect(find.text('app 0', skipOffstage: false), findsOneWidget);
  });

  testWidgets('iOS never covers the app, and lays widget content out behind it',
      (tester) async {
    final controller = await pump(tester, target: TargetPlatform.iOS);
    await controller.arm(
      PipContent.widget((context) => const Text('window')),
      options: const PipOptions(
        aspectRatio: PipAspectRatio.square,
        widgetCaptureWidth: 200,
      ),
    );
    await tester.pump();

    expect(find.text('window'), findsOneWidget);
    expect(tester.getSize(find.byType(RepaintBoundary).first),
        const Size(200, 200));
    // The app is painted after the capture layer, so it is what shows.
    final stack = tester.widget<Stack>(find.byType(Stack).first);
    expect(stack.children.last, isA<KeyedSubtree>());

    await controller.disarm();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('window'), findsNothing);
  });

  testWidgets('iOS video content adds nothing to the tree', (tester) async {
    final controller = await pump(tester, target: TargetPlatform.iOS);
    await controller.arm(PipContent.video((context) => const Text('window')));
    platform.reportOpen(true);
    await tester.pump();

    expect(find.text('window'), findsNothing);
    expect(find.text('app 0'), findsOneWidget);
  });
}
