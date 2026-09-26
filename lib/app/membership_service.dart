import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../features/accounting/domain/payee.dart';

/// Public endpoint configuration only. No credentials or accounting data belong
/// in the app's configuration. A service instance is bound to one business.
class MembershipService {
  MembershipService({
    required Uri origin,
    required this.businessId,
    required this.tokenProvider,
    MembershipTransport? transport,
  }) : _origin = _validateOrigin(origin),
       _transport = transport ?? NativeMembershipTransport() {
    _requireId(businessId);
  }

  final Uri _origin;
  final String businessId;
  final Future<String?> Function() tokenProvider;
  final MembershipTransport _transport;
  bool _closed = false;

  /// Dispose on account or company change. Late responses then cannot enter the
  /// next account's state. Authorization always remains the server's decision.
  void close() {
    _closed = true;
    _transport.close();
  }

  Future<ServiceMembership?> self() async {
    final result = await _request('GET', 'self');
    if (!result.containsKey('membership')) {
      throw const MembershipFailure('invalid_response');
    }
    final value = result['membership'];
    return value == null ? null : ServiceMembership.fromJson(_object(value));
  }

  Future<ServiceMembership> register(
    MembershipRegistration registration,
  ) async {
    if (registration.businessId != businessId) {
      throw ArgumentError('Registration belongs to another business.');
    }
    final result = await _request(
      'POST',
      'registrations',
      body: registration.body,
    );
    if (result['businessId'] != businessId ||
        result['requestId'] != registration.requestId) {
      throw const MembershipFailure('invalid_response');
    }
    final identityId = _id(result['identityId']);
    final value = _object(result['membership']);
    return ServiceMembership.fromJson({...value, 'identityId': identityId});
  }

  Future<MembershipPage> directory({
    int offset = 0,
    int limit = 5,
    String search = '',
  }) async {
    if (offset < 0 ||
        offset > 1000000 ||
        !const [5, 10, 15, 20, 50, 100].contains(limit) ||
        utf8.encode(search).length > 640) {
      throw ArgumentError('Invalid directory page.');
    }
    final result = await _request(
      'GET',
      'users',
      query: {'offset': '$offset', 'limit': '$limit', 'search': search},
    );
    if (result['businessId'] != businessId ||
        result['offset'] != offset ||
        result['limit'] != limit) {
      throw const MembershipFailure('invalid_response');
    }
    return MembershipPage.fromJson(result);
  }

  /// Minimal approved employee projection; no email or membership management.
  Future<List<Payee>> employeePayees(String search) async {
    if (utf8.encode(search).length > 640) {
      throw ArgumentError('Search is too long.');
    }
    final result = await _request(
      'GET',
      'employee-payees',
      query: {'search': search},
    );
    if (result['businessId'] != businessId ||
        result['payees'] is! List ||
        (result['payees'] as List).length > 100) {
      throw const MembershipFailure('invalid_response');
    }
    final payees = <Payee>[
      for (final raw in result['payees'] as List)
        Payee(
          id: 'registered-employee-${_id(_object(raw)['id'])}',
          name: _text(_object(raw)['name'], 200),
          type: PayeeType.staff,
        ),
    ];
    if (payees.map((p) => p.id).toSet().length != payees.length) {
      throw const MembershipFailure('invalid_response');
    }
    return List.unmodifiable(payees);
  }

  /// Registration identities plus the verified caller in one bounded snapshot.
  /// This read does not authorize posting or replace Claim command checks.
  Future<ServiceClaimantContext> claimants(String search) async {
    if (utf8.encode(search).length > 640) {
      throw ArgumentError('Search is too long.');
    }
    final result = await _request(
      'GET',
      'claimants',
      query: {'search': search},
    );
    if (result['businessId'] != businessId) {
      throw const MembershipFailure('invalid_response');
    }
    return ServiceClaimantContext.fromJson(result);
  }

  /// Keep [mutation] for retries after an uncertain network result. Never make
  /// a new retry key automatically, and never replay a command on a redirect.
  Future<void> execute(MembershipMutation mutation) async {
    if (mutation.businessId != businessId) {
      throw ArgumentError('Command belongs to a different business.');
    }
    final result = await _request('POST', 'commands', body: mutation.body);
    if (result['requestId'] != mutation.requestId) {
      throw const MembershipFailure('invalid_response');
    }
    final changes = _object(result['memberships']);
    if (changes.length != mutation.revisions.length ||
        changes.keys.any((id) => !mutation.revisions.containsKey(id))) {
      throw const MembershipFailure('invalid_response');
    }
    for (final entry in changes.entries) {
      final member = _object(entry.value);
      if (member['businessId'] != businessId ||
          member['revision'] != mutation.revisions[entry.key]! + 1 ||
          member['status'] != mutation.resultStatus ||
          member['role'] != mutation.role) {
        throw const MembershipFailure('invalid_response');
      }
    }
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String resource, {
    Map<String, String>? query,
    String? body,
  }) async {
    if (_closed) throw const MembershipFailure('session_changed');
    try {
      final token = await tokenProvider().timeout(const Duration(seconds: 15));
      if (_closed) throw const MembershipFailure('session_changed');
      if (token == null ||
          token.length > 16384 ||
          !(RegExp(r'^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$')
                  .hasMatch(token) ||
              RegExp(r'^audyt_[a-f0-9]{64}$').hasMatch(token))) {
        throw const MembershipFailure('authentication_required');
      }
      final uri = _origin.replace(
        path: '/v1/businesses/$businessId/$resource',
        queryParameters: query,
      );
      final response = await _transport.send(
        method: method,
        uri: uri,
        token: token,
        body: body,
      );
      if (_closed) throw const MembershipFailure('session_changed');
      if (response.status != 200) {
        // Never display server HTML, PHP diagnostics, URLs, tokens or SQL.
        final fallback = switch (response.status) {
          401 => 'authentication_required',
          403 => 'director_required',
          404 => 'not_found',
          409 => 'conflict',
          429 => 'rate_limited',
          _ => 'service_unavailable',
        };
        String? code;
        try {
          code = _object(jsonDecode(response.body))['error'] as String?;
        } catch (_) {
          /* Untrusted failure details are intentionally discarded. */
        }
        throw MembershipFailure(
          MembershipFailure.messages.containsKey(code) ? code! : fallback,
        );
      }
      return _object(jsonDecode(response.body));
    } on MembershipFailure {
      rethrow;
    } on FormatException {
      throw const MembershipFailure('invalid_response');
    } catch (_) {
      throw const MembershipFailure('service_unavailable');
    }
  }

  static Uri _validateOrigin(Uri origin) {
    if (origin.scheme != 'https' ||
        origin.host.isEmpty ||
        origin.userInfo.isNotEmpty ||
        origin.hasQuery ||
        origin.hasFragment ||
        (origin.path.isNotEmpty && origin.path != '/') ||
        origin.port != 443) {
      throw ArgumentError(
        'Membership origin must be an HTTPS origin on port 443.',
      );
    }
    return origin;
  }
}

/// Immutable registration retry payload. Requested role is never a role grant.
class MembershipRegistration {
  MembershipRegistration({
    required this.businessId,
    required String name,
    required String email,
    required String requestedRole,
    String? requestId,
  }) : requestId = requestId ?? _newId() {
    _requireId(businessId);
    _requireId(this.requestId);
    final profile = {
      'name': name.trim(),
      'email': email.trim(),
      'requestedRole': requestedRole,
    };
    if (profile['name']!.isEmpty ||
        profile['name']!.runes.length > 200 ||
        profile['email']!.runes.length > 320 ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(profile['email']!) ||
        profile.values.any(
          (value) => value.contains(RegExp(r'[\x00-\x1f\x7f]')),
        ) ||
        !_roles.contains(requestedRole)) {
      throw ArgumentError('Enter valid registration details.');
    }
    profileBody = jsonEncode(profile);
    body = jsonEncode({'requestId': this.requestId, 'profile': profile});
  }
  final String businessId, requestId;
  late final String profileBody, body;
}

class MembershipMutation {
  MembershipMutation({
    required this.businessId,
    required Map<String, int> expectedRevisions,
    required this.action,
    this.role,
    String? requestId,
  }) : requestId = requestId ?? _newId(),
       revisions = Map.unmodifiable(expectedRevisions) {
    _requireId(businessId);
    _requireId(this.requestId);
    if (revisions.isEmpty ||
        revisions.length > 100 ||
        !const ['approve', 'reject', 'changeRole', 'revoke'].contains(action)) {
      throw ArgumentError('Invalid membership command.');
    }
    for (final entry in revisions.entries) {
      _requireId(entry.key);
      if (entry.value < 0 || entry.value >= 9007199254740991) {
        throw ArgumentError('Invalid membership revision.');
      }
    }
    final needsRole = action == 'approve' || action == 'changeRole';
    if (needsRole ? !_roles.contains(role) : role != null) {
      throw ArgumentError('Invalid membership role.');
    }
    body = jsonEncode({
      'requestId': this.requestId,
      'expectedRevisions': revisions,
      'action': action,
      'role': role,
    });
    if (utf8.encode(body).length > 65536) {
      throw ArgumentError('Command too large.');
    }
  }
  final String requestId;
  final String businessId;
  final Map<String, int> revisions;
  final String action;
  final String? role;
  late final String body;
  String get resultStatus => switch (action) {
    'approve' || 'changeRole' => 'approved',
    'reject' => 'rejected',
    _ => 'revoked',
  };
}

class ServiceClaimant {
  const ServiceClaimant._(this.identityId, this.name, this.role, this.revision);
  final String identityId, name, role;
  final int revision;
  factory ServiceClaimant.fromJson(Map<String, dynamic> json) {
    if (json.keys.toSet().difference({
          'id',
          'name',
          'role',
          'revision',
        }).isNotEmpty ||
        !const {'director', 'accountant', 'employee'}.contains(json['role'])) {
      throw const MembershipFailure('invalid_response');
    }
    final name = _text(json['name'], 200);
    if (name.trim().isEmpty) throw const MembershipFailure('invalid_response');
    return ServiceClaimant._(
      _id(json['id']),
      name,
      json['role'] as String,
      _integer(json['revision']),
    );
  }
}

class ServiceClaimantContext {
  ServiceClaimantContext._(
    this.businessId,
    this.actor,
    List<ServiceClaimant> choices,
  ) : claimants = List.unmodifiable(choices);
  final String businessId;
  final ServiceClaimant actor;
  final List<ServiceClaimant> claimants;
  bool get canChooseOnBehalf =>
      actor.role == 'director' || actor.role == 'accountant';
  factory ServiceClaimantContext.fromJson(Map<String, dynamic> json) {
    final raw = json['claimants'];
    if (raw is! List ||
        raw.length > 100 ||
        json.keys.toSet().difference({
          'businessId',
          'actor',
          'claimants',
        }).isNotEmpty) {
      throw const MembershipFailure('invalid_response');
    }
    final actor = ServiceClaimant.fromJson(_object(json['actor']));
    final choices = [
      for (final value in raw) ServiceClaimant.fromJson(_object(value)),
    ];
    if (choices.map((c) => c.identityId).toSet().length != choices.length ||
        choices.any(
          (c) => actor.role == 'employee' && c.identityId != actor.identityId,
        ) ||
        choices.any(
          (c) =>
              c.identityId == actor.identityId &&
              (c.name != actor.name ||
                  c.role != actor.role ||
                  c.revision != actor.revision),
        )) {
      throw const MembershipFailure('invalid_response');
    }
    return ServiceClaimantContext._(_id(json['businessId']), actor, choices);
  }
}

class ServiceMembership {
  const ServiceMembership(
    this.identityId,
    this.status,
    this.role,
    this.revision, {
    this.masterDirectorId,
  });
  factory ServiceMembership.fromJson(Map<String, dynamic> json) {
    final id = _id(json['identityId']);
    final status = _status(json['status']);
    final role = _role(json['role'], status);
    final master = json['masterDirectorId'] == null
        ? null
        : _id(json['masterDirectorId']);
    if (master != null && (status != 'approved' || role != 'director')) {
      throw const MembershipFailure('invalid_response');
    }
    return ServiceMembership(
      id,
      status,
      role,
      _integer(json['revision']),
      masterDirectorId: master,
    );
  }
  final String identityId;
  final String status;
  final String? role;
  final int revision;
  final String? masterDirectorId;
  bool get isDirector => status == 'approved' && role == 'director';
}

class ServiceUser {
  ServiceUser.fromJson(Map<String, dynamic> json)
    : id = _id(json['id']),
      name = _text(json['name'], 200),
      email = _text(json['email'], 320),
      status = _status(json['status']),
      role = _role(json['role'], _status(json['status'])),
      revision = _integer(json['revision']),
      submittedAt = _text(json['submittedAt'], 40) {
    if (status == 'revoked' || DateTime.tryParse(submittedAt) == null) {
      throw const MembershipFailure('invalid_response');
    }
  }
  final String id, name, email, status, submittedAt;
  final String? role;
  final int revision;
}

class MembershipPage {
  MembershipPage.fromJson(Map<String, dynamic> json)
    : revision = _integer(json['revision']),
      total = _integer(json['total']),
      pendingCount = _integer(json['pendingCount']),
      matched = _integer(json['matched']),
      offset = _integer(json['offset']),
      limit = _integer(json['limit']),
      users = _users(json['users']) {
    if (pendingCount > total ||
        matched > total ||
        users.length > limit ||
        users.length > max(0, matched - offset) ||
        users.map((u) => u.id).toSet().length != users.length) {
      throw const MembershipFailure('invalid_response');
    }
  }
  final int revision, total, pendingCount, matched, offset, limit;
  final List<ServiceUser> users;
  bool get showSearch => total >= 6;
}

class MembershipFailure implements Exception {
  const MembershipFailure(this.code);
  final String code;
  static const messages = {
    'authentication_required': 'Sign in with Google again to continue.',
    'invalid_google_token': 'Sign in with Google again to continue.',
    'claim_access_required':
        'Only approved registered users can submit claims.',
    'accounting_access_required': 'Approved accounting access is required.',
    'director_required': 'Only approved Directors can manage employees.',
    'master_director_required':
        'Only the Master Director can remove or demote a Director.',
    'master_director_protected': 'The Master Director’s access is protected.',
    'self_access_change': 'You cannot remove your own Director access.',
    'stale_revision':
        'This user changed. Refresh and review the latest details.',
    'request_id_reused': 'This request changed. Refresh before trying again.',
    'conflict': 'User details changed. Refresh and review them again.',
    'not_found': 'This business or user is no longer available.',
    'rate_limited': 'Too many requests. Wait a minute and try again.',
    'invalid_response':
        'The service returned an unexpected response. Please try again.',
    'session_changed': 'Your account or business changed. Please try again.',
    'service_unavailable': 'The service is unavailable. Please try again.',
  };
  @override
  String toString() => messages[code] ?? messages['service_unavailable']!;
}

class MembershipResponse {
  const MembershipResponse(this.status, this.body);
  final int status;
  final String body;
}

abstract interface class MembershipTransport {
  Future<MembershipResponse> send({
    required String method,
    required Uri uri,
    required String token,
    String? body,
  });
  void close();
}

/// Default platform TLS verification is retained. No proxy credentials, custom
/// certificates, cookie persistence, logging or automatic redirects are added.
class NativeMembershipTransport implements MembershipTransport {
  NativeMembershipTransport({HttpClient Function()? clientFactory})
    : _clientFactory = clientFactory ?? HttpClient.new;
  final HttpClient Function() _clientFactory;
  final Set<HttpClient> _active = {};
  bool _closed = false;
  static const maxResponseBytes = 1024 * 1024;

  @override
  Future<MembershipResponse> send({
    required String method,
    required Uri uri,
    required String token,
    String? body,
  }) async {
    if (_closed) throw const MembershipFailure('session_changed');
    final client = _clientFactory();
    _active.add(client);
    client.connectionTimeout = const Duration(seconds: 5);
    try {
      return await (() async {
        final request = await client.openUrl(method, uri);
        request.followRedirects = false;
        if (token.isNotEmpty) {
          request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        }
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        request.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
        if (body != null) {
          request.headers.contentType = ContentType.json;
          request.add(utf8.encode(body));
        }
        final response = await request.close();
        if (response.isRedirect ||
            response.statusCode >= 300 && response.statusCode < 400) {
          throw const MembershipFailure('service_unavailable');
        }
        if (response.contentLength > maxResponseBytes ||
            response.headers.contentType?.mimeType != 'application/json') {
          throw const MembershipFailure('invalid_response');
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          if (bytes.length + chunk.length > maxResponseBytes) {
            throw const MembershipFailure('invalid_response');
          }
          bytes.addAll(chunk);
        }
        return MembershipResponse(response.statusCode, utf8.decode(bytes));
      })().timeout(const Duration(seconds: 15));
    } finally {
      _active.remove(client);
      client.close(force: true);
    }
  }

  @override
  void close() {
    _closed = true;
    for (final client in _active) {
      client.close(force: true);
    }
    _active.clear();
  }
}

const _roles = ['director', 'accountant', 'employee'];
final _uuid = RegExp(
  r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
);
void _requireId(String value) {
  if (!_uuid.hasMatch(value)) {
    throw ArgumentError('Invalid membership identifier.');
  }
}

String _id(dynamic value) {
  if (value is! String || !_uuid.hasMatch(value)) {
    throw const MembershipFailure('invalid_response');
  }
  return value;
}

Map<String, dynamic> _object(dynamic value) {
  if (value is! Map<String, dynamic>) {
    throw const MembershipFailure('invalid_response');
  }
  return value;
}

int _integer(dynamic value) {
  if (value is! int || value < 0 || value > 9007199254740991) {
    throw const MembershipFailure('invalid_response');
  }
  return value;
}

String _text(dynamic value, int maxLength) {
  if (value is! String ||
      value.runes.length > maxLength ||
      value.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
    throw const MembershipFailure('invalid_response');
  }
  return value;
}

String _status(dynamic value) {
  if (value is! String ||
      !const ['pending', 'approved', 'rejected', 'revoked'].contains(value)) {
    throw const MembershipFailure('invalid_response');
  }
  return value;
}

String? _role(dynamic value, String status) {
  if (status == 'approved' ? !_roles.contains(value) : value != null) {
    throw const MembershipFailure('invalid_response');
  }
  return value as String?;
}

List<ServiceUser> _users(dynamic value) {
  if (value is! List || value.length > 100) {
    throw const MembershipFailure('invalid_response');
  }
  return List.unmodifiable(value.map((v) => ServiceUser.fromJson(_object(v))));
}

String _newId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
