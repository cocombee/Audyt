import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'support/fixed_popout_host.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(installFixedPopoutHost);
  await testMain();
}
