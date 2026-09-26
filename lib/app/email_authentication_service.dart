import 'dart:convert';

import 'membership_service.dart';

/// Public service configuration only. Tokens belong in the native Keychain;
/// passwords and verification codes are never retained by this adapter.
class EmailAuthenticationService {
  EmailAuthenticationService({
    required Uri origin,
    MembershipTransport? transport,
  }) : origin = _origin(origin),
       transport = transport ?? NativeMembershipTransport();
  final Uri origin;
  final MembershipTransport transport;
  static Uri _origin(Uri value) {
    if (value.scheme != 'https' ||
        value.host.isEmpty ||
        value.userInfo.isNotEmpty ||
        value.hasQuery ||
        value.hasFragment ||
        !['', '/'].contains(value.path)) {
      throw ArgumentError('Authentication requires a dedicated HTTPS origin.');
    }
    return value;
  }

  Future<Map<String, dynamic>> request(
    String action,
    Map<String, dynamic> input, {
    String token = '',
  }) async {
    try {
      final response = await transport.send(
        method: 'POST',
        uri: origin.replace(path: '/v1/auth/$action'),
        token: token,
        body: jsonEncode(input),
      );
      final value = jsonDecode(response.body);
      if (value is! Map<String, dynamic>) {
        throw const AuthenticationFailure('invalid_response');
      }
      if (response.status != 200) {
        const allowed = {
          'invalid_credentials',
          'invalid_code',
          'rate_limited',
          'authentication_required',
          'password_required',
          'weak_password',
          'link_conflict',
          'terms_required',
          'service_unavailable',
        };
        throw AuthenticationFailure(
          allowed.contains(value['error'])
              ? value['error'] as String
              : 'service_unavailable',
        );
      }
      return value;
    } on AuthenticationFailure {
      rethrow;
    } catch (_) {
      throw const AuthenticationFailure('service_unavailable');
    }
  }

  Future<AuthenticationIdentity> signIn(String email, String password) async =>
      AuthenticationIdentity.fromJson(
        await request('sign-in', {'email': email.trim(), 'password': password}),
      );
  Future<String> register({
    required String name,
    required String email,
    required String password,
    required String termsVersion,
    String phone = '',
  }) async => _challenge(
    await request('register', {
      'name': name.trim(),
      'email': email.trim(),
      'phone': phone.trim(),
      'password': password,
      'termsVersion': termsVersion,
    }),
  );
  Future<String> forgotPassword(String email) async =>
      _challenge(await request('forgot-password', {'email': email.trim()}));
  Future<void> resend(String challenge) async {
    await request('resend', {'challengeId': challenge});
  }

  Future<AuthenticationIdentity> verify(String challenge, String code) async =>
      AuthenticationIdentity.fromJson(
        await request('verify', {'challengeId': challenge, 'code': code}),
      );
  Future<void> resetPassword(
    String challenge,
    String code,
    String password,
  ) async {
    final result = await request('reset-password', {
      'challengeId': challenge,
      'code': code,
      'password': password,
    });
    if (result['changed'] != true) {
      throw const AuthenticationFailure('invalid_response');
    }
  }

  Future<Map<String, dynamic>> google(
    String idToken, {
    required String termsVersion,
  }) => request('google', {'idToken': idToken, 'termsVersion': termsVersion});
  Future<AuthenticationIdentity> restore(String token) async =>
      AuthenticationIdentity.fromJson(
        await request('session', {}, token: token),
        token: token,
      );
  Future<void> signOut(String token) async {
    await request('sign-out', {}, token: token);
  }

  Future<void> changePassword(
    String token,
    String currentPassword,
    String password,
  ) async {
    final result = await request('change-password', {
      'currentPassword': currentPassword,
      'password': password,
    }, token: token);
    if (result['changed'] != true) {
      throw const AuthenticationFailure('invalid_response');
    }
  }

  static String _challenge(Map<String, dynamic> value) {
    final id = value['challengeId'];
    if (id is! String || !_uuid.hasMatch(id)) {
      throw const AuthenticationFailure('invalid_response');
    }
    return id;
  }

  void close() => transport.close();
}

final _uuid = RegExp(
  r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
);

class AuthenticationIdentity {
  const AuthenticationIdentity({
    required this.id,
    required this.email,
    required this.name,
    required this.token,
    required this.hasPassword,
    this.googleSubject = '',
  });
  factory AuthenticationIdentity.fromJson(
    Map<String, dynamic> value, {
    String? token,
  }) {
    final account = value['account'];
    if (account is! Map<String, dynamic>) {
      throw const AuthenticationFailure('invalid_response');
    }
    final secret = token ?? value['token'];
    if (secret is! String ||
        !RegExp(r'^audyt_[a-f0-9]{64}$').hasMatch(secret) ||
        account['id'] is! String ||
        !_uuid.hasMatch(account['id'] as String) ||
        account['email'] is! String ||
        (account['email'] as String).length > 320 ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
            .hasMatch(account['email'] as String) ||
        account['name'] is! String ||
        (account['name'] as String).length > 200 ||
        account['hasPassword'] is! bool ||
        (account['googleSubject'] != null &&
            (account['googleSubject'] is! String ||
                (account['googleSubject'] as String).length > 255))) {
      throw const AuthenticationFailure('invalid_response');
    }
    return AuthenticationIdentity(
      id: account['id'] as String,
      email: account['email'] as String,
      name: account['name'] as String,
      token: secret,
      hasPassword: account['hasPassword'] as bool,
      googleSubject: account['googleSubject'] as String? ?? '',
    );
  }
  final String id, email, name, token, googleSubject;
  final bool hasPassword;
}

class AuthenticationFailure implements Exception {
  const AuthenticationFailure(this.code);
  final String code;
  @override
  String toString() => switch (code) {
    'invalid_credentials' => 'The email or password is incorrect.',
    'invalid_code' =>
      'This code is incorrect, expired or already used. Request a new code.',
    'rate_limited' => 'Too many attempts. Wait before trying again.',
    'authentication_required' => 'Sign in again to continue.',
    'password_required' =>
      'This account uses Google. Manage its password with Google.',
    'weak_password' => 'Use a password of 15 to 128 characters.',
    'link_conflict' => 'This Google account is already linked to another user.',
    'terms_required' =>
      'Review the current Terms & Conditions before registering.',
    _ => 'Account services are unavailable. Please try again.',
  };
}
