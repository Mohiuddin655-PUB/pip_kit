/// System Picture in Picture for any Flutter content.
///
/// Put a [PipHost] at the root of the app, describe what the floating window
/// should show with a [PipContent], and drive it through [PipController].
library;

export 'src/pip_content.dart';
export 'src/pip_controller.dart';
export 'src/pip_host.dart';
export 'src/pip_options.dart';
export 'src/pip_platform.dart' show PipPlatform, MethodChannelPipPlatform;
