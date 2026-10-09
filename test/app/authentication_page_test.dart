import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/authentication_page.dart';
import 'package:audyt/app/email_authentication_service.dart';
import 'package:audyt/app/google_account_session.dart';
import 'package:audyt/app/membership_service.dart';
import 'package:audyt/app/password_change_dialog.dart';
import 'package:audyt/app/responsive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';

import 'google_account_session_test.dart' show FakeGoogle;

const identity = '00000000-0000-4000-8000-000000000001';
const challenge = '00000000-0000-4000-8000-000000000002';
final token = 'audyt_${List.filled(64, 'a').join()}';
Map<String, dynamic> account() => {
  'id': identity,
  'email': 'person@example.test',
  'name': 'Fictional Person',
  'hasPassword': true,
  'googleSubject': '',
};

class AuthTransport implements MembershipTransport {
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};
  int status = 200;
  String? failure;
  bool link = false;
  Map<String, dynamic>? nextAccount;
  @override
  Future<MembershipResponse> send({
    required String method,
    required Uri uri,
    required String token,
    String? body,
  }) async {
    expect(method, 'POST');
    expect(uri.scheme, 'https');
    final action = uri.pathSegments.last;
    calls.add(action);
    bodies[action] = jsonDecode(body!) as Map<String, dynamic>;
    if (status != 200) {
      return MembershipResponse(status, jsonEncode({'error': failure}));
    }
    final value = switch (action) {
      'register' || 'forgot-password' => {'challengeId': challenge},
      'google' when link => {'linkRequired': true, 'challengeId': challenge},
      'resend' => {'requested': true},
      'reset-password' || 'change-password' => {'changed': true},
      'sign-out' => {'signedOut': true},
      'session' => {'account': nextAccount ?? account()},
      _ => {
        'token': token.isEmpty ? globalsToken : token,
        'account': nextAccount ?? account(),
      },
    };
    return MembershipResponse(200, jsonEncode(value));
  }

  @override
  void close() {}
}

String get globalsToken => token;
void authWidgets(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(
      name,
      body,
      variant: TargetPlatformVariant({TargetPlatform.macOS}),
    );
void main() {
  late AuthTransport transport;
  late GoogleAccountSession session;
  Map<String, String>? saved;
  bool failSave = false;
  bool failClear = false;
  setUp(() {
    GoogleSignInPlatform.instance = FakeGoogle();
    transport = AuthTransport();
    session = GoogleAccountSession(
      authenticationService: EmailAuthenticationService(
        origin: Uri.parse('https://account.example.test'),
        transport: transport,
      ),
      termsVersion: 'fixture-v1',
    );
    saved = null;
    failSave = false;
    failClear = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(GoogleAccountSession.credentials, (
          call,
        ) async {
          if (call.method == 'load') return saved ?? <String, String>{};
          if (call.method == 'save') {
            if (failSave) {
              throw PlatformException(code: 'credentials_unavailable');
            }
            saved = Map<String, String>.from(call.arguments as Map);
            return null;
          }
          if (call.method == 'clear') {
            if (failClear) {
              throw PlatformException(code: 'credentials_unavailable');
            }
            saved = null;
            return null;
          }
          return null;
        });
  });
  tearDown(() {
    session.dispose();
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(GoogleAccountSession.credentials, null);
  });
  Future<void> open(
    WidgetTester tester, {
    double width = 720,
    double height = 1000,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, height));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('auth-capture'),
        child: MaterialApp(
          theme: AccountingTheme.light(),
          home: AudytSignInPage(session: session),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  authWidgets(
    'sign-in uses matching button widths and centered primary label',
    (tester) async {
      await open(tester);
      final submit = tester.getRect(find.byKey(const ValueKey('auth-submit')));
      final google = tester.getRect(find.byKey(const ValueKey('auth-google')));
      final card = tester.getRect(
        find.byKey(const ValueKey('authentication-card')),
      );
      expect(google.left, submit.left);
      expect(google.right, card.right - 20);
      expect(submit.right, google.right);
      expect(
        tester.getRect(find.text('Sign In').last).center.dx,
        closeTo(submit.center.dx, 0.1),
      );
      expect(google.height, submit.height);
      expect(google.top - submit.bottom, greaterThan(20));
      expect(find.text('Or'), findsOneWidget);
      expect(submit.left - card.left, 20);
      expect(find.text('Sign In With Google'), findsOneWidget);
      final forgot = tester.widget<TextButton>(
        find.descendant(
          of: find.byKey(const ValueKey('auth-forgot-password')),
          matching: find.byType(TextButton),
        ),
      );
      final terms = tester.widget<TextButton>(
        find.descendant(
          of: find.byKey(const ValueKey('auth-terms')),
          matching: find.byType(TextButton),
        ),
      );
      expect(forgot.style!.textStyle!.resolve({})!.fontWeight, FontWeight.w400);
      expect(forgot.style!.textStyle!.resolve({})!.fontSize, 13);
      expect(terms.style!.textStyle!.resolve({})!.fontWeight, FontWeight.w400);
      expect(terms.style!.textStyle!.resolve({})!.fontSize, 12);
      final tokens = AccountingTheme.of(
        tester.element(find.text('Terms & Conditions')),
      );
      expect(terms.style!.foregroundColor!.resolve({}), tokens.mutedForeground);
      expect(
        terms.style!.foregroundColor!.resolve({WidgetState.hovered}),
        tokens.foreground,
      );
      expect(terms.style!.padding!.resolve({}), EdgeInsets.zero);
      expect(
        tester.getRect(find.text('Forgot Password?')).right,
        card.right - 20,
      );
      final signup = tester.widget<TextButton>(
        find.descendant(
          of: find.byKey(const ValueKey('auth-change-mode')),
          matching: find.byType(TextButton),
        ),
      );
      expect(signup.style!.textStyle!.resolve({})!.fontWeight, FontWeight.w400);
      expect(signup.style!.textStyle!.resolve({})!.fontSize, 13);
      expect(find.text('Don’t have an account?'), findsOneWidget);
      expect(find.text('Sign Up'), findsOneWidget);
      final heading = tester.getRect(find.text('Sign In').first);
      final description = tester.getRect(find.text('Welcome back to Audyt.'));
      expect(heading.center.dx, closeTo(card.center.dx, 0.1));
      expect(
        description.top - heading.bottom,
        AccountingResponsive.titleSubtitleGap,
      );
      expect(
        tester.widget<Text>(find.text('Sign In').first).style!.fontSize,
        22,
      );

      expect(
        tester.getRect(find.text('Welcome back to Audyt.')).center.dx,
        closeTo(card.center.dx, 0.1),
      );
      await tester.tap(find.byKey(const ValueKey('auth-change-mode')));
      await tester.pumpAndSettle();
      expect(find.text('Sign Up With Google'), findsOneWidget);
      expect(find.byKey(const ValueKey('auth-name')), findsOneWidget);
      expect(find.byKey(const ValueKey('auth-phone')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('auth-terms')));
      await tester.pumpAndSettle();
      expect(find.text('Terms & Conditions'), findsWidgets);
      expect(find.text('Licence And Use'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Licence And Use'), findsNothing);
    },
  );
  authWidgets(
    'password sign-in reaches service and secure session persistence',
    (tester) async {
      await session.initialize();
      await open(tester);
      await tester.enterText(
        find.byKey(const ValueKey('auth-email')),
        'person@example.test',
      );
      await tester.enterText(
        find.byKey(const ValueKey('auth-password')),
        'Fictional passphrase 12345',
      );
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const ValueKey('auth-password')),
                matching: find.byType(TextField),
              ),
            )
            .obscureText,
        true,
      );
      await tester.tap(find.byTooltip('Show Password'));
      await tester.pump();
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const ValueKey('auth-password')),
                matching: find.byType(TextField),
              ),
            )
            .obscureText,
        false,
      );
      await tester.tap(find.byKey(const ValueKey('auth-submit')));
      await tester.pumpAndSettle();
      expect(transport.calls, contains('sign-in'));
      expect(session.identityId, identity);
      expect(saved?['token'], token);
      expect(saved?['origin'], 'https://account.example.test');
      expect(saved!.keys.toSet(), {'origin', 'token'});
    },
  );
  authWidgets(
    'registration requires published terms then verifies before signed in',
    (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('auth-change-mode')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('auth-name')),
        'Fictional Person',
      );
      await tester.enterText(
        find.byKey(const ValueKey('auth-email')),
        'person@example.test',
      );
      await tester.enterText(
        find.byKey(const ValueKey('auth-password')),
        'Fictional passphrase 12345',
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('auth-submit')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('auth-submit')));
      await tester.pumpAndSettle();
      expect(session.signedIn, false);
      expect(find.text('Verify Email'), findsOneWidget);
      expect(transport.bodies['register']?['termsVersion'], 'fixture-v1');
      await tester.enterText(find.byKey(const ValueKey('auth-code')), '123456');
      await tester.tap(find.byKey(const ValueKey('auth-submit')));
      await tester.pumpAndSettle();
      expect(session.identityId, identity);
      expect(transport.calls, contains('verify'));
    },
  );
  authWidgets(
    'forgot password saves reset through service and returns to normal sign-in',
    (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('auth-forgot-password')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('auth-email')),
        'person@example.test',
      );
      await tester.tap(find.byKey(const ValueKey('auth-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Check Your Email'), findsOneWidget);
      expect(find.byKey(const ValueKey('auth-password')), findsNothing);
      expect(session.signedIn, false);
      await tester.enterText(find.byKey(const ValueKey('auth-code')), '123456');
      await tester.tap(find.byKey(const ValueKey('auth-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Set A New Password'), findsOneWidget);
      expect(transport.calls, isNot(contains('reset-password')));
      await tester.tap(find.byKey(const ValueKey('auth-change-mode')));
      await tester.pumpAndSettle();
      expect(find.text('Check Your Email'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const ValueKey('auth-code')),
                matching: find.byType(TextField),
              ),
            )
            .controller!
            .text,
        '123456',
      );
      await tester.tap(find.byKey(const ValueKey('auth-submit')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('auth-password')),
        'New fictional passphrase 12345',
      );
      await tester.enterText(
        find.byKey(const ValueKey('auth-confirm-password')),
        'Wrong fictional passphrase 12345',
      );
      await tester.tap(find.byKey(const ValueKey('auth-submit')));
      await tester.pumpAndSettle();
      expect(find.text('The passwords do not match.'), findsOneWidget);
      expect(
        tester
            .getRect(
              find.descendant(
                of: find.byKey(const ValueKey('auth-confirm-password')),
                matching: find.byType(TextField),
              ),
            )
            .height,
        accountingControlHeight,
      );

      expect(transport.calls, isNot(contains('reset-password')));
      await tester.enterText(
        find.byKey(const ValueKey('auth-confirm-password')),
        'New fictional passphrase 12345',
      );
      transport.status = 400;
      transport.failure = 'invalid_code';
      await tester.tap(find.byKey(const ValueKey('auth-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Check Your Email'), findsOneWidget);
      expect(find.text('Password Changed'), findsNothing);
      expect(session.signedIn, false);
      expect(saved, isNull);
      transport.status = 200;
      transport.failure = null;
      await tester.enterText(find.byKey(const ValueKey('auth-code')), '123456');
      await tester.tap(find.byKey(const ValueKey('auth-submit')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('auth-password')),
        'New fictional passphrase 12345',
      );
      await tester.enterText(
        find.byKey(const ValueKey('auth-confirm-password')),
        'New fictional passphrase 12345',
      );
      await tester.tap(find.byKey(const ValueKey('auth-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Sign In'), findsWidgets);
      expect(transport.calls, contains('reset-password'));
      expect(transport.bodies['reset-password']?['code'], '123456');
      expect(find.text('Password Changed'), findsOneWidget);
      expect(session.signedIn, false);
      expect(saved, isNull);
      await tester.tap(find.byKey(const ValueKey('auth-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Welcome back to Audyt.'), findsOneWidget);
    },
  );
  authWidgets(
    'Google email-first linking waits for email proof before accepting a session',
    (tester) async {
      transport.link = true;
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('auth-google')));
      await tester.pumpAndSettle();
      expect(find.text('Link Your Account'), findsOneWidget);
      expect(session.signedIn, false);
      expect(saved, isNull);
      await tester.enterText(find.byKey(const ValueKey('auth-code')), '123456');
      await tester.tap(find.byKey(const ValueKey('auth-submit')));
      await tester.pumpAndSettle();
      expect(session.identityId, identity);
    },
  );
  authWidgets(
    'secure persistence failure never exposes a new session and revokes it',
    (tester) async {
      await session.initialize();
      failSave = true;
      await session.signInWithPassword(
        'person@example.test',
        'Fictional passphrase 12345',
      );
      expect(session.signedIn, false);
      expect(saved, isNull);
      expect(transport.calls, contains('sign-out'));
      expect(session.error, contains('secure session store'));
      expect(await session.idTokenForAccount(identity), isNull);
    },
  );
  authWidgets(
    'Keychain session restore preserves the accepted server identity',
    (tester) async {
      await session.initialize();
      await session.signInWithPassword(
        'person@example.test',
        'Fictional passphrase 12345',
      );
      session.dispose();
      session = GoogleAccountSession(
        authenticationService: EmailAuthenticationService(
          origin: Uri.parse('https://account.example.test'),
          transport: transport,
        ),
        termsVersion: 'fixture-v1',
      );
      await session.initialize();
      expect(session.identityId, identity);
      expect(transport.calls.last, 'session');
      expect(await session.idTokenForAccount(identity), token);
    },
  );
  authWidgets(
    'password change revocation remains signed out when local cleanup fails',
    (tester) async {
      await session.initialize();
      await session.signInWithPassword(
        'person@example.test',
        'Fictional passphrase 12345',
      );
      failClear = true;
      await session.changePassword(
        'Fictional passphrase 12345',
        'New fictional passphrase 12345',
      );
      expect(session.signedIn, false);
      expect(session.error, startsWith('Password changed.'));
      expect(await session.idTokenForAccount(identity), isNull);
    },
  );
  authWidgets(
    'switch email proof preserves the current session until verified',
    (tester) async {
      await session.initialize();
      await session.signInWithPassword(
        'person@example.test',
        'Fictional passphrase 12345',
      );
      final oldSaved = Map<String, String>.from(saved!);
      final platform = GoogleSignInPlatform.instance as FakeGoogle;
      platform.next = const AuthenticationResults(
        user: GoogleSignInUserData(
          email: 'second@example.test',
          id: 'second-subject',
        ),
        authenticationTokens: AuthenticationTokenData(idToken: 'second-token'),
      );
      transport.link = true;
      expect(await session.switchAccount(), false);
      expect(session.linkChallenge, challenge);
      expect(session.identityId, identity);
      expect(saved, oldSaved);
      expect(session.photoUrl, isNull);
      transport.status = 422;
      transport.failure = 'invalid_code';
      await session.verifyAccount(challenge, '000000');
      expect(session.identityId, identity);
      expect(saved, oldSaved);
      transport.status = 200;
      transport.nextAccount = {
        ...account(),
        'id': '00000000-0000-4000-8000-000000000003',
        'email': 'second@example.test',
        'googleSubject': 'second-subject',
      };
      await session.verifyAccount(challenge, '123456');
      expect(session.identityId, '00000000-0000-4000-8000-000000000003');
      expect(session.account?.id, 'second-subject');
      expect(session.linkChallenge, isNull);
      expect(await session.idTokenForAccount(identity), isNull);
      expect(transport.calls.last, 'sign-out');
    },
  );
  authWidgets(
    'password changes reauthenticate and clear sessions after server success',
    (tester) async {
      await session.initialize();
      await session.signInWithPassword(
        'person@example.test',
        'Fictional passphrase 12345',
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showPasswordChange(context, session),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('password-current')),
        'Fictional passphrase 12345',
      );
      await tester.enterText(
        find.byKey(const ValueKey('password-new')),
        'Another fictional passphrase 12345',
      );
      await tester.enterText(
        find.byKey(const ValueKey('password-confirm')),
        'Another fictional passphrase 12345',
      );
      await tester.tap(find.byKey(const ValueKey('password-save')));
      await tester.pumpAndSettle();
      expect(transport.calls, contains('change-password'));
      expect(session.signedIn, false);
      expect(saved, isNull);
      expect(find.byKey(const ValueKey('password-save')), findsNothing);
    },
  );
  for (final width in [1224.0, 1162.0, 720.0, 430.0]) {
    authWidgets('auth flows render with product font at $width', (
      tester,
    ) async {
      if (Platform.environment['AUDYT_UI_CAPTURE_DIR'] == null) return;
      await (FontLoader(
        'Inter',
      )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      await open(
        tester,
        width: width,
        height: width == 720 || width == 1162 ? 809 : 1000,
      );
      Future<void> capture(String label) async {
        expect(tester.takeException(), isNull);
        final card = tester.getRect(
          find.byKey(const ValueKey('authentication-card')),
        );
        final heading = find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              widget.style?.fontSize == 22 &&
              widget.style?.fontWeight == FontWeight.w600,
        );
        if (label != 'Terms Popout') {
          expect(
            tester.getRect(heading).center.dx,
            closeTo(card.center.dx, 0.1),
          );
          expect(
            tester.getRect(heading).top - card.top,
            closeTo(AccountingResponsive.pageTitleOuterGap, 0.1),
          );
          if (label != 'Sign In' &&
              label != 'Register' &&
              label != 'Terms Hover' &&
              label != 'Password Changed') {
            final back = tester.getRect(
              find.byKey(const ValueKey('auth-change-mode')),
            );
            expect(
              back.center.dy,
              closeTo(tester.getRect(heading).center.dy, 0.1),
            );
          }
          final last = find.text(
            label == 'Register' ? 'Sign In' : 'Terms & Conditions',
          );
          expect(
            card.bottom - tester.getRect(last).bottom,
            closeTo(AccountingResponsive.pageTitleOuterGap, 0.1),
          );
        }

        if (label == 'Sign In' || label == 'Register') {
          final card = tester.getRect(
            find.byKey(const ValueKey('authentication-card')),
          );
          final google = tester.getRect(
            find.byKey(const ValueKey('auth-google')),
          );
          final submit = tester.getRect(
            find.byKey(const ValueKey('auth-submit')),
          );
          expect(google.left, card.left + 20);
          expect(google.right, card.right - 20);
          expect(google.height, 44);
          expect(google.top - submit.bottom, greaterThan(20));
          expect(submit.width, google.width);
          expect(
            tester
                .getRect(
                  find.text(label == 'Sign In' ? 'Sign In' : 'Register').last,
                )
                .center
                .dx,
            closeTo(submit.center.dx, 0.1),
          );
        }
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('auth-capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '${Platform.environment['AUDYT_UI_CAPTURE_DIR']}/Authentication Links $label ${width.toInt()}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await capture('Sign In');
      final mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(
        tester.getCenter(find.byKey(const ValueKey('auth-terms'))),
      );
      await tester.pumpAndSettle();
      await capture('Terms Hover');
      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      await mouse.removePointer();

      await tester.tap(find.byKey(const ValueKey('auth-change-mode')));
      await tester.pumpAndSettle();
      await capture('Register');
      await tester.tap(find.byKey(const ValueKey('auth-terms')));
      await tester.pumpAndSettle();
      await capture('Terms Popout');
      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('auth-name')),
        'Fictional Person',
      );
      await tester.enterText(
        find.byKey(const ValueKey('auth-email')),
        'person@example.test',
      );
      await tester.enterText(
        find.byKey(const ValueKey('auth-password')),
        'Fictional passphrase 12345',
      );
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('auth-submit')));
      await tester.pumpAndSettle();
      await capture('Verify Email');
      await tester.tap(find.byKey(const ValueKey('auth-change-mode')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('auth-forgot-password')));
      await tester.pumpAndSettle();
      await capture('Forgot Password');
      await tester.enterText(
        find.byKey(const ValueKey('auth-email')),
        'person@example.test',
      );
      await tester.tap(find.byKey(const ValueKey('auth-submit')));
      await tester.pumpAndSettle();
      await capture('Check Your Email');
      await tester.enterText(find.byKey(const ValueKey('auth-code')), '123456');
      await tester.tap(find.byKey(const ValueKey('auth-submit')));
      await tester.pumpAndSettle();
      await capture('New Password');
      await tester.enterText(
        find.byKey(const ValueKey('auth-password')),
        'New fictional passphrase 12345',
      );
      await tester.enterText(
        find.byKey(const ValueKey('auth-confirm-password')),
        'Wrong fictional passphrase 12345',
      );
      await tester.tap(find.byKey(const ValueKey('auth-submit')));
      await tester.pumpAndSettle();
      await capture('Password Mismatch');
      await tester.enterText(
        find.byKey(const ValueKey('auth-confirm-password')),
        'New fictional passphrase 12345',
      );
      transport.status = 400;
      transport.failure = 'invalid_code';
      await tester.tap(find.byKey(const ValueKey('auth-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Check Your Email'), findsOneWidget);
      expect(find.text('Password Changed'), findsNothing);
      await capture('Code Rejected');
      transport.status = 200;
      transport.failure = null;
      await tester.enterText(find.byKey(const ValueKey('auth-code')), '654321');
      await tester.tap(find.byKey(const ValueKey('auth-submit')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('auth-password')),
        'New fictional passphrase 12345',
      );
      await tester.enterText(
        find.byKey(const ValueKey('auth-confirm-password')),
        'New fictional passphrase 12345',
      );
      await tester.tap(find.byKey(const ValueKey('auth-submit')));
      await tester.pumpAndSettle();
      expect(transport.bodies['reset-password']?['code'], '654321');
      await capture('Password Changed');
    });
  }
}
