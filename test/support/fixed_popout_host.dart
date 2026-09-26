import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Model the desktop window contract for journeys that open a fixed popout.
/// Dedicated native-contract tests install their own request/release assertions.
void installFixedPopoutHost([WidgetTester? tester]) {
  final binding = tester?.binding ?? TestWidgetsFlutterBinding.instance;
  final view = tester?.view ?? binding.platformDispatcher.implicitView!;
  const channel = MethodChannel('audyt/window-layout');
  binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
    call,
  ) async {
    if (call.method == 'acquirePopoutWidth') {
      final width = (call.arguments as Map)['width'] as double;
      final physicalWidth = width * view.devicePixelRatio;
      if (physicalWidth > view.physicalSize.width) {
        view.physicalSize = Size(physicalWidth, view.physicalSize.height);
      }
      return view.physicalSize.width / view.devicePixelRatio;
    }
    if (call.method == 'releasePopoutWidth') return null;
    throw MissingPluginException('Unknown window method ${call.method}');
  });
  addTearDown(
    () =>
        binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
  );
}
