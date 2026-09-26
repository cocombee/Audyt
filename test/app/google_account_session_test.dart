import 'dart:async';

import 'package:audyt/app/google_account_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';

class FakeGoogle extends GoogleSignInPlatform {
  static const result = AuthenticationResults(
    user: GoogleSignInUserData(
      email: 'person@example.test',
      id: 'google-subject',
      displayName: 'Test Person',
    ),
    authenticationTokens: AuthenticationTokenData(idToken: 'test-token'),
  );
  AuthenticationResults next = result;
  Object? failure;
  bool failInit = false;
  bool restore = false;
  int requests = 0;
  int initializations = 0;
  Completer<AuthenticationResults>? pending;
  @override
  Future<void> init(InitParameters params) async {
    initializations++;
    if (failInit) throw StateError('configuration');
  }

  @override
  Future<AuthenticationResults?> attemptLightweightAuthentication(
    AttemptLightweightAuthenticationParameters params,
  ) async => restore ? result : null;
  @override
  Future<AuthenticationResults> authenticate(
    AuthenticateParameters params,
  ) async {
    requests++;
    expect(params.scopeHint, isEmpty);
    if (failure != null) throw failure!;
    return pending == null ? next : pending!.future;
  }

  @override
  Future<void> signOut(SignOutParams params) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeGoogle platform;
  late GoogleAccountSession session;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    platform = FakeGoogle();
    GoogleSignInPlatform.instance = platform;
    session = GoogleAccountSession();
  });
  tearDown(() {
    session.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
  test('sign-in exposes Google identity and sign-out clears it', () async {
    await session.signIn();
    expect(session.account?.id, 'google-subject');
    expect(session.account?.email, 'person@example.test');
    expect(session.error, isNull);
    await session.signOut();
    expect(session.account, isNull);
  });
  test('restores SDK-owned session without interactive sign-in', () async {
    platform.restore = true;
    await session.initialize();
    await Future<void>.delayed(Duration.zero);
    expect(session.account?.id, 'google-subject');
    expect(platform.requests, 0);
  });
  test('cancel is quiet and does not connect an account', () async {
    platform.failure = const GoogleSignInException(
      code: GoogleSignInExceptionCode.canceled,
    );
    await session.signIn();
    expect(session.account, isNull);
    expect(session.error, isNull);
    expect(session.busy, false);
  });
  test('failure is safe to display and can retry', () async {
    platform.failure = StateError('secret must not be displayed');
    await session.signIn();
    expect(session.error, isNot(contains('secret')));
    expect(session.error, isNotNull);
    platform.failure = null;
    await session.signIn();
    expect(session.account, isNotNull);
    expect(session.error, isNull);
  });
  test('initialization failure retries before authenticating', () async {
    platform.failInit = true;
    await session.signIn();
    expect(platform.requests, 0);
    platform.failInit = false;
    await session.signIn();
    expect(platform.initializations, 2);
    expect(session.account, isNotNull);
  });
  test('duplicate clicks do not launch parallel sign-in', () async {
    platform.pending = Completer();
    final first = session.signIn();
    await Future<void>.delayed(Duration.zero);
    await session.signIn();
    expect(platform.requests, 1);
    platform.pending!.complete(FakeGoogle.result);
    await first;
    expect(session.busy, false);
  });
  test(
    'switch rejects the same email and preserves the selected user',
    () async {
      await session.signIn();
      final before = session.account;
      expect(await session.switchAccount(), false);
      expect(session.account, same(before));
      expect(session.switchError, 'Choose a different Google account.');
      expect(await session.idTokenForAccount('google-subject'), 'test-token');
    },
  );
  test(
    'cancelled switch preserves current identity and membership token',
    () async {
      await session.signIn();
      platform.failure = const GoogleSignInException(
        code: GoogleSignInExceptionCode.canceled,
      );
      expect(await session.switchAccount(), false);
      expect(session.identityId, 'google-subject');
      expect(session.switchError, isNull);
      expect(await session.idTokenForAccount('google-subject'), 'test-token');
    },
  );
  test(
    'accepted switch publishes the new identity only after authentication',
    () async {
      await session.signIn();
      platform.pending = Completer();
      final switching = session.switchAccount();
      await Future<void>.delayed(Duration.zero);
      expect(session.identityId, 'google-subject');
      expect(await session.idTokenForAccount('google-subject'), isNull);
      platform.pending!.complete(
        const AuthenticationResults(
          user: GoogleSignInUserData(
            email: 'second@example.test',
            id: 'second-subject',
            displayName: 'Second User',
          ),
          authenticationTokens: AuthenticationTokenData(
            idToken: 'second-token',
          ),
        ),
      );
      expect(await switching, true);
      expect(session.identityId, 'second-subject');
      expect(await session.idTokenForAccount('google-subject'), isNull);
      expect(await session.idTokenForAccount('second-subject'), 'second-token');
    },
  );
  test(
    'wrong chooser account is not accepted or restored as the selected user',
    () async {
      await session.signIn();
      platform.next = const AuthenticationResults(
        user: GoogleSignInUserData(
          email: 'unexpected@example.test',
          id: 'unexpected-subject',
        ),
        authenticationTokens: AuthenticationTokenData(
          idToken: 'unexpected-token',
        ),
      );
      expect(
        await session.switchAccount(expectedEmail: 'wanted@example.test'),
        false,
      );
      expect(session.identityId, 'google-subject');
      expect(await session.idTokenForAccount('unexpected-subject'), isNull);
      expect(session.switchError, contains('wanted@example.test'));
    },
  );
}
