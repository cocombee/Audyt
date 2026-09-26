import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audyt/app/membership_service.dart';
import 'package:flutter_test/flutter_test.dart';

const business = '11111111-1111-4111-8111-111111111111';
const otherBusiness = '22222222-2222-4222-8222-222222222222';
const member = '33333333-3333-4333-8333-333333333333';
const token = 'header.payload.signature';

class FakeTransport implements MembershipTransport {
  final calls = <({String method, Uri uri, String token, String? body})>[];
  MembershipResponse response = const MembershipResponse(
    200,
    '{"membership":null}',
  );
  Object? failure;
  Completer<MembershipResponse>? pending;
  bool closed = false;
  @override
  Future<MembershipResponse> send({
    required String method,
    required Uri uri,
    required String token,
    String? body,
  }) async {
    calls.add((method: method, uri: uri, token: token, body: body));
    if (failure != null) throw failure!;
    return pending?.future ?? response;
  }

  @override
  void close() {
    closed = true;
  }
}

class FakeHeaders implements HttpHeaders {
  final values = <String, Object>{};
  @override
  ContentType? contentType = ContentType.json;
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  FakeResponse(this.chunks, {this.statusCode = 200, this.contentLength = -1});
  final List<List<int>> chunks;
  @override
  final int statusCode;
  @override
  final int contentLength;
  @override
  final FakeHeaders headers = FakeHeaders();
  @override
  bool get isRedirect => statusCode == 302;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.fromIterable(chunks).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeRequest implements HttpClientRequest {
  FakeRequest(this.response);
  final FakeResponse response;
  final bytes = <int>[];
  @override
  final FakeHeaders headers = FakeHeaders();
  @override
  bool followRedirects = true;
  @override
  void add(List<int> data) {
    bytes.addAll(data);
  }

  @override
  Future<HttpClientResponse> close() async => response;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeClient implements HttpClient {
  FakeClient(FakeResponse response) : request = FakeRequest(response);
  final FakeRequest request;
  int opens = 0;
  bool forcedClosed = false;
  @override
  Duration? connectionTimeout;
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    opens++;
    return request;
  }

  @override
  void close({bool force = false}) {
    forcedClosed = force;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Matcher failure(String code) =>
    isA<MembershipFailure>().having((e) => e.code, 'code', code);

void main() {
  test('Master capability metadata is bounded and cannot upgrade a role', () {
    const actor = '22222222-2222-4222-8222-222222222222';
    const base = {
      'identityId': actor,
      'status': 'approved',
      'role': 'director',
      'revision': 0,
    };
    expect(
      ServiceMembership.fromJson({...base, 'masterDirectorId': actor})
          .masterDirectorId,
      actor,
    );
    expect(ServiceMembership.fromJson(base).masterDirectorId, isNull);
    expect(
      () => ServiceMembership.fromJson({
        ...base,
        'masterDirectorId': 'not-an-id',
      }),
      throwsA(isA<MembershipFailure>()),
    );
    expect(
      () => ServiceMembership.fromJson({
        ...base,
        'role': 'accountant',
        'masterDirectorId': actor,
      }),
      throwsA(isA<MembershipFailure>()),
    );
  });

  late FakeTransport transport;
  late MembershipService service;
  setUp(() {
    transport = FakeTransport();
    service = MembershipService(
      origin: Uri.parse('https://audyt.example.test'),
      businessId: business,
      tokenProvider: () async => token,
      transport: transport,
    );
  });
  tearDown(() => service.close());

  test('only an HTTPS origin without credentials or path is accepted', () {
    for (final url in [
      'http://example.test',
      'https://a:b@example.test',
      'https://example.test/api',
      'https://example.test?key=secret',
      'https://example.test#part',
      'https://example.test:8443',
    ]) {
      expect(
        () => MembershipService(
          origin: Uri.parse(url),
          businessId: business,
          tokenProvider: () async => token,
        ),
        throwsArgumentError,
      );
    }
  });
  test('registration sends only minimal profile fields and trusts returned approval', () async {
    final request = MembershipRegistration(
      businessId: business,
      name: 'Fictional Applicant',
      email: 'contact@example.test',
      requestedRole: 'director',
    );
    transport.response = MembershipResponse(
      200,
      jsonEncode({
        'businessId': business,
        'requestId': request.requestId,
        'identityId': member,
        'membership': {'status': 'pending', 'role': null, 'revision': 0},
      }),
    );
    final result = await service.register(request);
    expect(result.status, 'pending');
    expect(result.isDirector, false);
    await service.register(request);
    expect(transport.calls[0].body, transport.calls[1].body);
    final body = jsonDecode(transport.calls.first.body!) as Map;
    expect(body.keys.toSet(), {'requestId', 'profile'});
    expect((body['profile'] as Map).keys.toSet(), {
      'name',
      'email',
      'requestedRole',
    });
    expect(transport.calls.first.uri.path, endsWith('/registrations'));
  });
  test(
    'registration receipts cannot switch business or grant malformed roles',
    () async {
      final request = MembershipRegistration(
        businessId: business,
        name: 'Fictional Applicant',
        email: 'contact@example.test',
        requestedRole: 'employee',
      );
      for (final receipt in [
        {
          'businessId': otherBusiness,
          'requestId': request.requestId,
          'identityId': member,
          'membership': {
            'status': 'approved',
            'role': 'director',
            'revision': 0,
          },
        },
        {
          'businessId': business,
          'requestId': request.requestId,
          'identityId': member,
          'membership': {
            'status': 'pending',
            'role': 'director',
            'revision': 0,
          },
        },
      ]) {
        transport.response = MembershipResponse(200, jsonEncode(receipt));
        await expectLater(
          service.register(request),
          throwsA(failure('invalid_response')),
        );
      }
    },
  );
  test('invalid registration fields never become an HTTP request', () {
    for (final entry in [
      ('Bad\nName', 'contact@example.test', 'employee'),
      ('Fictional', 'bad email', 'employee'),
      ('Fictional', 'contact@example.test', 'admin'),
    ]) {
      expect(
        () => MembershipRegistration(
          businessId: business,
          name: entry.$1,
          email: entry.$2,
          requestedRole: entry.$3,
        ),
        throwsArgumentError,
      );
    }
    expect(transport.calls, isEmpty);
  });

  test(
    'self request sends bearer separately and only reads server authority',
    () async {
      transport.response = MembershipResponse(
        200,
        jsonEncode({
          'membership': {
            'identityId': member,
            'status': 'approved',
            'role': 'director',
            'revision': 3,
          },
        }),
      );
      expect((await service.self())!.isDirector, isTrue);
      final call = transport.calls.single;
      expect(
        call.uri.toString(),
        'https://audyt.example.test/v1/businesses/$business/self',
      );
      expect(call.uri.toString(), isNot(contains(token)));
      expect(call.token, token);
      expect(call.body, isNull);
    },
  );
  test('missing and impossible memberships fail closed', () async {
    for (final body in [
      '{}',
      '[]',
      '{"membership":{"identityId":"$member",'
          '"status":"pending","role":"director","revision":0}}',
    ]) {
      transport.response = MembershipResponse(200, body);
      await expectLater(service.self(), throwsA(failure('invalid_response')));
    }
    transport.response = const MembershipResponse(200, '{"membership":null}');
    expect(await service.self(), isNull);
  });
  test(
    'directory uses total rather than current filtered page for search',
    () async {
      transport.response = MembershipResponse(
        200,
        jsonEncode({
          'businessId': business,
          'revision': 4,
          'total': 21,
          'pendingCount': 3,
          'matched': 1,
          'offset': 0,
          'limit': 10,
          'users': [
            {
              'id': member,
              'name': 'Person',
              'email': 'person@example.test',
              'status': 'pending',
              'role': null,
              'revision': 0,
              'submittedAt': '2026-09-26 12:34:56.000000',
            },
          ],
        }),
      );
      final page = await service.directory(limit: 10, search: 'person & 100%');
      expect(page.showSearch, isTrue);
      expect(page.users.length, 1);
      expect(
        transport.calls.single.uri.queryParameters['search'],
        'person & 100%',
      );
      expect(() => page.users.clear(), throwsUnsupportedError);
    },
  );
  test('directory rejects another business and inconsistent counts', () async {
    for (final json in [
      {'businessId': otherBusiness, 'offset': 0, 'limit': 10},
      {
        'businessId': business,
        'offset': 0,
        'limit': 10,
        'revision': 0,
        'total': 2,
        'pendingCount': 3,
        'matched': 0,
        'users': [],
      },
    ]) {
      transport.response = MembershipResponse(200, jsonEncode(json));
      await expectLater(
        service.directory(),
        throwsA(failure('invalid_response')),
      );
    }
  });
  test('bounded page inputs are rejected before transport', () async {
    await expectLater(service.directory(limit: 1000), throwsArgumentError);
    await expectLater(service.directory(offset: -1), throwsArgumentError);
    await expectLater(
      service.directory(search: 'x' * 641),
      throwsArgumentError,
    );
    expect(transport.calls, isEmpty);
  });
  test(
    'retry preserves exact key, revisions and payload after uncertain result',
    () async {
      final revisions = {member: 3};
      final mutation = MembershipMutation(
        businessId: business,
        expectedRevisions: revisions,
        action: 'approve',
        role: 'accountant',
      );
      revisions[member] = 20;
      transport.failure = const SocketException('private backend detail');
      await expectLater(
        service.execute(mutation),
        throwsA(failure('service_unavailable')),
      );
      transport.failure = null;
      transport.response = MembershipResponse(
        200,
        jsonEncode({
          'requestId': mutation.requestId,
          'memberships': {
            member: {
              'businessId': business,
              'status': 'approved',
              'role': 'accountant',
              'revision': 4,
            },
          },
        }),
      );
      await service.execute(mutation);
      expect(transport.calls[0].body, transport.calls[1].body);
      expect(mutation.revisions[member], 3);
      expect(() => mutation.revisions[member] = 4, throwsUnsupportedError);
    },
  );
  test('command cannot move to another business', () async {
    final mutation = MembershipMutation(
      businessId: otherBusiness,
      expectedRevisions: {member: 0},
      action: 'reject',
    );
    await expectLater(service.execute(mutation), throwsArgumentError);
    expect(transport.calls, isEmpty);
  });
  test(
    'command receipt must match both operation and target transition',
    () async {
      final mutation = MembershipMutation(
        businessId: business,
        expectedRevisions: {member: 0},
        action: 'reject',
      );
      for (final receipt in [
        {'requestId': 'wrong', 'memberships': {}},
        {
          'requestId': mutation.requestId,
          'memberships': {
            member: {
              'businessId': otherBusiness,
              'status': 'rejected',
              'role': null,
              'revision': 1,
            },
          },
        },
        {'requestId': mutation.requestId, 'memberships': {}},
      ]) {
        transport.response = MembershipResponse(200, jsonEncode(receipt));
        await expectLater(
          service.execute(mutation),
          throwsA(failure('invalid_response')),
        );
      }
    },
  );
  test('malformed roles, batches, IDs and revisions never become commands', () {
    expect(
      () => MembershipMutation(
        businessId: business,
        expectedRevisions: {member: -1},
        action: 'reject',
      ),
      throwsArgumentError,
    );
    expect(
      () => MembershipMutation(
        businessId: business,
        expectedRevisions: {},
        action: 'reject',
      ),
      throwsArgumentError,
    );
    expect(
      () => MembershipMutation(
        businessId: business,
        expectedRevisions: {member: 0},
        action: 'approve',
        role: 'master',
      ),
      throwsArgumentError,
    );
    expect(
      () => MembershipMutation(
        businessId: business,
        expectedRevisions: {'../other': 0},
        action: 'reject',
      ),
      throwsArgumentError,
    );
  });
  test(
    'error messages cannot reveal backend diagnostics or supplied text',
    () async {
      for (final response in [
        const MembershipResponse(503, '<html>password=secret</html>'),
        const MembershipResponse(403, '{"error":"secret database password"}'),
      ]) {
        transport.response = response;
        try {
          await service.self();
          fail('Expected failure');
        } on MembershipFailure catch (e) {
          expect(e.toString(), isNot(contains('secret')));
        }
      }
      transport.response = const MembershipResponse(
        403,
        '{"error":"master_director_required"}',
      );
      await expectLater(
        service.self(),
        throwsA(failure('master_director_required')),
      );
    },
  );
  test(
    'closing an account rejects late data and subsequent requests',
    () async {
      transport.pending = Completer();
      final pending = service.self();
      await Future<void>.delayed(Duration.zero);
      service.close();
      transport.pending!.complete(
        const MembershipResponse(200, '{"membership":null}'),
      );
      await expectLater(pending, throwsA(failure('session_changed')));
      await expectLater(service.self(), throwsA(failure('session_changed')));
      expect(transport.closed, isTrue);
      expect(transport.calls.length, 1);
    },
  );
  test('closing while token is pending prevents any request', () async {
    final tokenResult = Completer<String?>();
    final isolated = MembershipService(
      origin: Uri.parse('https://audyt.example.test'),
      businessId: business,
      tokenProvider: () => tokenResult.future,
      transport: transport,
    );
    final pending = isolated.self();
    isolated.close();
    tokenResult.complete(token);
    await expectLater(pending, throwsA(failure('session_changed')));
    expect(transport.calls, isEmpty);
  });
  test(
    'native transport disables redirects and force closes its connection',
    () async {
      final client = FakeClient(FakeResponse([], statusCode: 302));
      final native = NativeMembershipTransport(clientFactory: () => client);
      await expectLater(
        native.send(
          method: 'POST',
          uri: Uri.parse('https://audyt.example.test'),
          token: token,
          body: '{}',
        ),
        throwsA(failure('service_unavailable')),
      );
      expect(client.request.followRedirects, isFalse);
      expect(client.opens, 1);
      expect(client.forcedClosed, isTrue);
    },
  );
  test(
    'native transport rejects oversized streaming data and non-JSON replies',
    () async {
      for (final response in [
        FakeResponse([
          List.filled(NativeMembershipTransport.maxResponseBytes, 32),
          [32],
        ]),
        FakeResponse(
          [],
          contentLength: NativeMembershipTransport.maxResponseBytes + 1,
        ),
        FakeResponse([])..headers.contentType = ContentType.html,
      ]) {
        final client = FakeClient(response);
        final native = NativeMembershipTransport(clientFactory: () => client);
        await expectLater(
          native.send(
            method: 'GET',
            uri: Uri.parse('https://audyt.example.test'),
            token: token,
          ),
          throwsA(failure('invalid_response')),
        );
        expect(client.forcedClosed, isTrue);
      }
    },
  );
  test(
    'native transport sends JSON and bearer with cache prevention',
    () async {
      final client = FakeClient(
        FakeResponse([utf8.encode('{"membership":null}')]),
      );
      final native = NativeMembershipTransport(clientFactory: () => client);
      final result = await native.send(
        method: 'POST',
        uri: Uri.parse('https://audyt.example.test'),
        token: token,
        body: '{"action":"reject"}',
      );
      expect(result.status, 200);
      expect(
        client.request.headers.values[HttpHeaders.authorizationHeader],
        'Bearer $token',
      );
      expect(
        client.request.headers.values[HttpHeaders.cacheControlHeader],
        'no-store',
      );
      expect(utf8.decode(client.request.bytes), '{"action":"reject"}');
      expect(client.forcedClosed, isTrue);
      native.close();
    },
  );
}
