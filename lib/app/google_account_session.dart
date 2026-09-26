import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'email_authentication_service.dart';

/// Identity only. Business memberships and accounting permissions remain server
/// decisions. SDK tokens stay with Google; Audyt session tokens use Keychain.
class GoogleAccountSession extends ChangeNotifier {
  GoogleAccountSession({this.authenticationService, this.termsVersion = ''});
  static GoogleAccountSession _configured() {
    const origin = String.fromEnvironment('AUDYT_AUTH_ORIGIN');
    const terms = String.fromEnvironment('AUDYT_TERMS_VERSION');
    return GoogleAccountSession(
      authenticationService: origin.isEmpty
          ? null
          : EmailAuthenticationService(origin: Uri.parse(origin)),
      termsVersion: terms,
    );
  }

  static final shared = _configured();
  static const credentials = MethodChannel('audyt/auth-session');
  final EmailAuthenticationService? authenticationService;
  final String termsVersion;
  GoogleSignInAccount? account;
  AuthenticationIdentity? _identity;
  String? linkChallenge;
  String? googleVerificationChallenge;
  GoogleSignInAccount? _pendingSwitchAccount;
  String? _switchExcludedId;
  bool busy = false;
  String? error;
  String? switchError;
  bool _switching = false;
  Future<void>? _initialization;
  bool _ready = false;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _events;
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
  bool get signedIn =>
      authenticationService == null ? account != null : _identity != null;
  String? get identityId => signedIn ? _identity?.id ?? account?.id : null;
  String? get loginEmail =>
      signedIn ? _identity?.email ?? account?.email : null;
  String? get displayName => _identity?.name ?? account?.displayName;
  String? get photoUrl =>
      _identity == null || _identity?.googleSubject == account?.id
      ? account?.photoUrl
      : null;
  String get googleSubject => _identity?.googleSubject ?? account?.id ?? '';
  bool get hasPassword => _identity?.hasPassword ?? false;
  bool get emailAvailable => authenticationService != null;

  Future<void> initialize() async {
    await (_initialization ??= _initialize());
    if (!_ready) _initialization = null;
  }

  Future<void> _initialize() async {
    if (!supported) return;
    try {
      final sdk = GoogleSignIn.instance;
      await sdk.initialize();
      _ready = true;
      _events = sdk.authenticationEvents.listen(
        (event) {
          if (_switching) return;
          switch (event) {
            case GoogleSignInAuthenticationEventSignIn():
              account = event.user;
              error = null;
            case GoogleSignInAuthenticationEventSignOut():
              account = null;
          }
          notifyListeners();
        },
        onError: (Object failure) {
          if (_switching) return;
          _setError(failure);
          notifyListeners();
        },
      );
      await sdk.attemptLightweightAuthentication();
      if (authenticationService case final service?) {
        final saved = await credentials.invokeMapMethod<String, String>('load');
        if (saved?['origin'] == service.origin.toString() &&
            saved?['token'] is String) {
          final token = saved!['token']!;
          try {
            _identity = await service.restore(token);
          } on AuthenticationFailure catch (failure) {
            if (failure.code == 'authentication_required') {
              await credentials.invokeMethod<void>('clear');
            }
            rethrow;
          }
        }
      }
    } on MissingPluginException {
      /* Test/non-native host has no credential store. */
    } catch (failure) {
      _setError(failure);
    }
    notifyListeners();
  }

  void cancelPendingAuthentication() {
    linkChallenge = null;
    googleVerificationChallenge = null;
    _pendingSwitchAccount = null;
    _switchExcludedId = null;
    error = null;
    switchError = null;
    notifyListeners();
  }

  Future<void> _accept(AuthenticationIdentity value) async {
    try {
      await credentials.invokeMethod<void>('save', {
        'origin': authenticationService!.origin.toString(),
        'token': value.token,
      });
    } catch (_) {
      // A token whose secure local save failed must not remain an orphaned
      // server session. The existing selected identity stays unchanged.
      try {
        await authenticationService!.signOut(value.token);
      } catch (_) {}
      rethrow;
    }
    _identity = value;
    linkChallenge = null;
    googleVerificationChallenge = null;
    error = null;
  }

  Future<void> signIn({bool acceptTerms = false}) async {
    if (busy || !supported) return;
    busy = true;
    _switching = true;
    error = null;
    switchError = null;
    linkChallenge = null;
    googleVerificationChallenge = null;
    _pendingSwitchAccount = null;
    _switchExcludedId = null;
    notifyListeners();
    try {
      await initialize();
      if (!_ready) return;
      final candidate = await GoogleSignIn.instance.authenticate();
      if (authenticationService case final service?) {
        final token = candidate.authentication.idToken;
        if (token == null) {
          throw const AuthenticationFailure('authentication_required');
        }
        final result = await service.google(
          token,
          termsVersion: acceptTerms ? termsVersion : '',
        );
        if ((result['linkRequired'] == true ||
                result['verificationRequired'] == true) &&
            result['challengeId'] is String) {
          if (result['linkRequired'] == true) {
            linkChallenge = result['challengeId'] as String;
          } else {
            googleVerificationChallenge = result['challengeId'] as String;
          }
          account = candidate;
          return;
        }
        await _accept(AuthenticationIdentity.fromJson(result));
      }
      account = candidate;
      error = null;
    } catch (failure) {
      _setError(failure);
    } finally {
      _switching = false;
      busy = false;
      notifyListeners();
    }
  }

  Future<void> signInWithPassword(String email, String password) async {
    if (busy || authenticationService == null) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await _accept(await authenticationService!.signIn(email, password));
      account = null;
    } catch (failure) {
      _setError(failure);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> verifyAccount(String challenge, String code) async {
    if (busy || authenticationService == null) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final value = await authenticationService!.verify(challenge, code);
      if (_pendingSwitchAccount != null && value.id == _switchExcludedId) {
        await authenticationService!.signOut(value.token);
        throw const AuthenticationFailure('link_conflict');
      }
      final old = _identity;
      await _accept(value);
      if (_pendingSwitchAccount != null) {
        account = _pendingSwitchAccount;
        _pendingSwitchAccount = null;
        _switchExcludedId = null;
        if (old != null) {
          try {
            await authenticationService!.signOut(old.token);
          } catch (_) {}
        }
      }
    } catch (failure) {
      _setError(failure);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Saved profiles are labels, never credentials. Authenticate again and do
  /// not publish an unaccepted candidate to membership connections.
  Future<bool> switchAccount({
    String? expectedEmail,
    String? excludedEmail,
    bool acceptTerms = false,
  }) async {
    if (busy || !supported) return false;
    final prior = account;
    final excluded = (excludedEmail ?? loginEmail ?? '').trim().toLowerCase();
    busy = true;
    _switching = true;
    switchError = null;
    error = null;
    linkChallenge = null;
    googleVerificationChallenge = null;
    _pendingSwitchAccount = null;
    _switchExcludedId = null;
    notifyListeners();
    try {
      await initialize();
      if (!_ready) {
        switchError = error;
        return false;
      }
      final candidate = await GoogleSignIn.instance.authenticate();
      final email = candidate.email.trim().toLowerCase();
      if ((excluded.isNotEmpty && email == excluded) ||
          candidate.id == prior?.id ||
          candidate.id == _identity?.googleSubject) {
        switchError = 'Choose a different Google account.';
        return false;
      }
      if (expectedEmail != null &&
          email != expectedEmail.trim().toLowerCase()) {
        // SDK restore must never publish this rejected candidate after restart.
        await GoogleSignIn.instance.signOut();
        // Existing server identity and membership stay selected. Its saved
        // Keychain session remains valid; the rejected Google user cannot restore.
        account = prior;
        switchError = 'Sign in with $expectedEmail to select that user.';
        return false;
      }
      if (authenticationService case final service?) {
        final token = candidate.authentication.idToken;
        if (token == null) {
          throw const AuthenticationFailure('authentication_required');
        }
        final result = await service.google(
          token,
          termsVersion: acceptTerms ? termsVersion : '',
        );
        if (result['linkRequired'] == true ||
            result['verificationRequired'] == true) {
          if (result['linkRequired'] == true) {
            linkChallenge = result['challengeId'] as String;
          } else {
            googleVerificationChallenge = result['challengeId'] as String;
          }
          _pendingSwitchAccount = candidate;
          _switchExcludedId = identityId;
          switchError = null;
          return false;
        }
        final previous = _identity;
        await _accept(AuthenticationIdentity.fromJson(result));
        if (previous != null) {
          // Revoking the previous session cannot authorize the new identity.
          try {
            await service.signOut(previous.token);
          } catch (_) {}
        }
      }
      account = candidate;
      error = null;
      return true;
    } catch (failure) {
      switchError =
          failure is GoogleSignInException &&
              failure.code == GoogleSignInExceptionCode.canceled
          ? null
          : failure is AuthenticationFailure
          ? failure.toString()
          : 'Google sign-in could not be completed. Please try again.';
      return false;
    } finally {
      _switching = false;
      busy = false;
      notifyListeners();
    }
  }

  Future<void> changePassword(String currentPassword, String password) async {
    final identity = _identity;
    if (busy || identity == null || authenticationService == null) return;
    busy = true;
    _switching = true;
    error = null;
    notifyListeners();
    try {
      await authenticationService!.changePassword(
        identity.token,
        currentPassword,
        password,
      );
      // The server has confirmed revocation. Never expose that revoked session
      // as signed in while a local cleanup operation can fail.
      _identity = null;
      account = null;
      linkChallenge = null;
      googleVerificationChallenge = null;
      _pendingSwitchAccount = null;
      _switchExcludedId = null;
      try {
        await credentials.invokeMethod<void>('clear');
        await GoogleSignIn.instance.signOut();
      } catch (_) {
        error = 'Password changed. Your sessions were revoked. Local sign-out cleanup could not be confirmed; sign in again with your new password.';
      }
    } catch (failure) {
      _setError(failure);
    } finally {
      _switching = false;
      busy = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    if (busy) return;
    busy = true;
    error = null;
    switchError = null;
    _switching = true;
    notifyListeners();
    try {
      if (_identity case final identity?) {
        await authenticationService!.signOut(identity.token);
        _identity = null;
        account = null;
      }
      await GoogleSignIn.instance.signOut();
      if (authenticationService != null) {
        await credentials.invokeMethod<void>('clear');
      }
      account = null;
      _identity = null;
      linkChallenge = null;
      googleVerificationChallenge = null;
      _pendingSwitchAccount = null;
      _switchExcludedId = null;
    } catch (failure) {
      _setError(failure);
    } finally {
      _switching = false;
      busy = false;
      notifyListeners();
    }
  }

  Future<String?> idTokenForAccount(String expectedId) async {
    if (busy || error != null || identityId != expectedId) return null;
    return _identity?.token ?? account?.authentication.idToken;
  }

  void _setError(Object failure) {
    error =
        failure is PlatformException &&
            failure.code == 'credentials_unavailable'
        ? 'Your secure session store is unavailable. Please try again.'
        : failure is AuthenticationFailure
        ? failure.toString()
        : failure is GoogleSignInException &&
              failure.code == GoogleSignInExceptionCode.canceled
        ? null
        : 'Google sign-in could not be completed. Please try again.';
  }

  @override
  void dispose() {
    _events?.cancel();
    authenticationService?.close();
    super.dispose();
  }
}
