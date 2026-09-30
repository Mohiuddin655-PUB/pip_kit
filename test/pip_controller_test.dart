import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pip_kit/pip_kit.dart';

import 'fake_pip_platform.dart';

void main() {
  late FakePipPlatform platform;

  PipController build({TargetPlatform target = TargetPlatform.android}) =>
      PipController.forTesting(platform, targetPlatform: target);

  final content = PipContent.widget((context) => const SizedBox());

  setUp(() => platform = FakePipPlatform());

  test('reports no support off Android and iOS without asking the platform',
      () async {
    platform.supported = true;
    expect(await build(target: TargetPlatform.macOS).isSupported(), isFalse);
    expect(await build(target: TargetPlatform.android).isSupported(), isTrue);
  });

  test('arming hands the options and the content kind to the system', () async {
    final pip = build();
    await pip.arm(
      content,
      options: const PipOptions(
        aspectRatio: PipAspectRatio.square,
        autoEnter: true,
        actions: [
          PipAction(id: 'next', label: 'Next', icon: PipActionIcon.next),
        ],
      ),
    );

    final sent = platform.configurations.single;
    expect(sent['mode'], 'widget');
    expect(sent['autoEnter'], isTrue);
    expect(sent['aspectRatioWidth'], 1);
    expect(sent['aspectRatioHeight'], 1);
    expect(sent['actions'], [
      {'id': 'next', 'label': 'Next', 'icon': 'next', 'enabled': true},
    ]);
    expect(pip.content.value, same(content));
  });

  test('video content is armed in video mode', () async {
    final pip = build();
    await pip.arm(PipContent.video((context) => const SizedBox()));

    expect(platform.configurations.single['mode'], 'video');
  });

  test('entering without content is a programming error', () {
    expect(build().enter, throwsStateError);
    expect(platform.enterCalls, 0);
  });

  test('enter arms the given content then opens the window', () async {
    final pip = build();
    final opened = await pip.enter(content: content);

    expect(opened, isTrue);
    expect(platform.configurations, hasLength(1));
    expect(platform.enterCalls, 1);
    expect(pip.status.value, PipStatus.open);
  });

  test('a refused window leaves the status closed', () async {
    platform.enterSucceeds = false;
    final pip = build();

    expect(await pip.enter(content: content), isFalse);
    expect(pip.isOpen, isFalse);
  });

  test('entering an open window does not ask the system twice', () async {
    final pip = build();
    await pip.enter(content: content);
    await pip.enter();

    expect(platform.enterCalls, 1);
  });

  test('follows a window the user closes themselves', () async {
    final pip = build();
    await pip.enter(content: content);
    platform.reportOpen(false);

    expect(pip.status.value, PipStatus.closed);
    // Still armed: closing the window is not the same as giving it up.
    expect(pip.content.value, same(content));
  });

  test('action taps arrive on the stream', () async {
    final pip = build();
    final taps = <String>[];
    final subscription = pip.actions.listen(taps.add);
    platform.tapAction('next');
    platform.tapAction('back');
    await Future<void>.delayed(Duration.zero);

    expect(taps, ['next', 'back']);
    await subscription.cancel();
  });

  test('options can change while armed', () async {
    final pip = build();
    await pip.arm(content);
    await pip.updateOptions(const PipOptions(autoEnter: true));

    expect(platform.configurations, hasLength(2));
    expect(platform.configurations.last['autoEnter'], isTrue);
  });

  test('updating options with nothing armed does nothing', () async {
    expect(await build().updateOptions(const PipOptions()), isFalse);
    expect(platform.configurations, isEmpty);
  });

  test('disarming forgets the content and releases the system', () async {
    final pip = build();
    await pip.arm(content);
    await pip.disarm();

    expect(pip.content.value, isNull);
    expect(platform.releaseCalls, 1);
  });

  test('only iOS widget content is streamed as frames', () async {
    final android = build();
    await android.arm(content);
    expect(android.streamsWidgetFrames, isFalse);
    expect(android.drawsContentInApp, isTrue);

    final ios = build(target: TargetPlatform.iOS);
    await ios.arm(content);
    expect(ios.streamsWidgetFrames, isTrue);
    expect(ios.drawsContentInApp, isFalse);

    await ios.arm(PipContent.video((context) => const SizedBox()));
    expect(ios.streamsWidgetFrames, isFalse);
  });

  test('iOS widget content waits for a frame before asking for a window',
      () async {
    final pip = build(target: TargetPlatform.iOS);
    await pip.arm(content);

    var entered = false;
    final pending = pip.enter().then((_) => entered = true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(entered, isFalse);
    expect(platform.enterCalls, 0);

    pip.markFrameDelivered();
    await pending;
    expect(platform.enterCalls, 1);
  });

  test('aspect ratios compare by value', () {
    expect(const PipAspectRatio(9, 16), PipAspectRatio.portrait);
    expect(PipAspectRatio.fromSize(const Size(720, 1600)).value, 0.45);
    expect(PipAspectRatio.fromSize(Size.zero), PipAspectRatio.portrait);
  });
}
