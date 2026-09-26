import 'dart:io';
import 'dart:ui' as ui;

import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/accounting_icons.dart';
import 'package:audyt/app/local_profile.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';

import 'google_account_session_test.dart' show FakeGoogle;

void main() {
  testWidgets('Google dialog supports sign-in, sign-out and narrow layout', (
    tester,
  ) async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
    final originalShadows = debugDisableShadows;
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = originalShadows);
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });
    addTearDown(() => tester.binding.setSurfaceSize(null));
    GoogleSignInPlatform.instance = FakeGoogle();
    final profiles = <String, Map<String, String>>{};
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      LocalProfile.channel,
      (MethodCall call) async {
        final args = Map<String, String>.from(call.arguments as Map);
        final subject = args['googleSubject'] ?? '';
        if (call.method == 'list') {
          return [for (final profile in profiles.values) profile];
        }
        if (call.method == 'load') {
          return profiles[subject] ?? <String, String>{};
        }
        profiles[subject] = args;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        LocalProfile.channel,
        null,
      ),
    );
    await tester.binding.setSurfaceSize(const Size(900, 700));
    const capture = ValueKey('capture');
    await tester.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AccountingTheme.light(),
          home: const Scaffold(
            bottomNavigationBar: Offstage(child: LocalProfileMenu()),
            body: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: EdgeInsets.all(24),
                child: LocalProfileMenu(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('global-profile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('profile-menu-google')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('google-account-action')), findsOneWidget);
    expect(
      find.textContaining('Business access and role approval'),
      findsOneWidget,
    );
    for (final width in [900.0, 390.0]) {
      await tester.binding.setSurfaceSize(Size(width, 700));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      const output = String.fromEnvironment('AUDYT_GOOGLE_RENDER_DIR');
      if (output.isNotEmpty) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(capture),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$output/Google Sign In $width.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    }
    await tester.tap(find.byKey(const ValueKey('google-account-action')));
    await tester.pumpAndSettle();
    expect(find.text('Profile Setup'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('profile-name')))
          .controller!
          .text,
      'Test Person',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('profile-email')))
          .controller!
          .text,
      'person@example.test',
    );
    for (final width in [900.0, 390.0]) {
      await tester.binding.setSurfaceSize(Size(width, 700));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final nameRect = tester.getRect(
        find.byKey(const ValueKey('profile-name')),
      );
      final emailRect = tester.getRect(
        find.byKey(const ValueKey('profile-email')),
      );
      if (width > 600) {
        expect(nameRect.top, emailRect.top);
      } else {
        expect(emailRect.top, greaterThan(nameRect.bottom));
      }
      const output = String.fromEnvironment('AUDYT_GOOGLE_RENDER_DIR');
      if (output.isNotEmpty) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(capture),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$output/Google Profile Setup $width.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    }
    await tester.enterText(
      find.byKey(const ValueKey('profile-department')),
      'Finance',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('profile-role')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('profile-role')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Director').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('profile-save')));
    await tester.pumpAndSettle();
    expect(profiles['google-subject']?['department'], 'Finance');
    expect(profiles['google-subject']?['email'], 'person@example.test');
    for (final width in [1224.0, 720.0]) {
      await tester.binding.setSurfaceSize(Size(width, 700));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('global-profile')));
      await tester.pumpAndSettle();
      final switchRect = tester.getRect(
        find.byKey(const ValueKey('profile-menu-switch-user')),
      );
      final switchButton = tester.widget<SubmenuButton>(
        find.byKey(const ValueKey('profile-menu-switch-user')),
      );
      expect(switchButton.submenuIcon!.resolve({}), isA<SizedBox>());
      await tester.tap(find.byKey(const ValueKey('profile-menu-switch-user')));
      await tester.pumpAndSettle();
      final chooserItem = tester.getRect(
        find.byKey(const ValueKey('switch-account-google-subject')),
      );
      expect(chooserItem.right + 4, closeTo(switchRect.left - 4 - 3, 0.1));
      final anotherUser = tester.widget<Text>(
        find.text('Sign In Another User'),
      );
      final email = tester.widget<Text>(find.text('person@example.test').last);
      expect(anotherUser.style!.color, email.style!.color);
      expect(anotherUser.style!.fontSize, email.style!.fontSize);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('switch-account-google-subject')),
          matching: find.byWidgetPredicate(
            (w) =>
                w is AccountingProfileMenuIcon &&
                w.icon == Icons.email_outlined,
          ),
        ),
        findsOneWidget,
      );
      expect(chooserItem.top - 4, closeTo(switchRect.top, 0.1));
      final chooserButton = tester.widget<MenuItemButton>(
        find.byKey(const ValueKey('switch-account-google-subject')),
      );
      final chooserPadding = chooserButton.style!.padding!
          .resolve({})!
          .resolve(TextDirection.ltr);
      expect(chooserPadding.left, accountingProfileMenuItemInset);
      expect(chooserPadding.right, accountingProfileMenuItemInset);
      final parentPadding = switchButton.style!.padding!
          .resolve({})!
          .resolve(TextDirection.ltr);
      expect(parentPadding.left, chooserPadding.left);
      // The suppressed decoration still owns Flutter's 12px trailing spacer.
      expect(parentPadding.right + 12, chooserPadding.right);
      expect(tester.takeException(), isNull);
      final output = Platform.environment['AUDYT_UI_CAPTURE_DIR'];
      if (output != null) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(capture),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$output/Switch User Chooser ${width.toInt()}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const ValueKey('global-profile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('profile-menu-google')));
    await tester.pumpAndSettle();
    expect(find.text('Sign Out'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sign-out-cancel')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('global-profile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('profile-menu-google')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sign-out-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('person@example.test'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('global-profile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('profile-menu-google')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('google-account-action')));
    await tester.pumpAndSettle();
    expect(find.text('Profile Setup'), findsNothing);
    expect(tester.takeException(), isNull);
    debugDisableShadows = originalShadows;
    debugDefaultTargetPlatformOverride = null;
  });
}
