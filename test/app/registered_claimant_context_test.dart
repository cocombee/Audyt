import 'dart:async';
import 'dart:convert';

import 'package:audyt/app/connected_user_directory.dart';
import 'package:audyt/app/membership_service.dart';
import 'package:audyt/app/user_directory.dart';
import 'package:flutter_test/flutter_test.dart';

import 'membership_service_test.dart'
    show FakeTransport, business, otherBusiness, member, token;

const claimant = '44444444-4444-4444-8444-444444444444';

Map<String, dynamic> identity(String id, String role) => {
  'id': id,
  'name': 'Fictional Registered $role',
  'role': role,
  'revision': 2,
};

Map<String, dynamic> context(String role) => {
  'businessId': business,
  'actor': identity(member, role),
  'claimants': [
    identity(member, role),
    if (role != 'employee') identity(claimant, 'employee'),
  ],
};

void main() {
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

  for (final role in ['employee', 'accountant', 'director']) {
    test(
      '$role claimant lookup uses registration and verified actor snapshot',
      () async {
        transport.response = MembershipResponse(200, jsonEncode(context(role)));
        final directory = ConnectedUserDirectory(service);
        addTearDown(directory.dispose);
        final result = (await directory.findClaimants('%_!'))!;
        expect(result.businessId, business);
        expect(result.actor.identityId, member);
        expect(result.actor.role, role);
        expect(result.actor.revision, 2);
        expect(result.canChooseOnBehalf, role != 'employee');
        expect(
          result.claimants.map((c) => c.identityId),
          role == 'employee' ? [member] : [member, claimant],
        );
        expect(() => result.claimants.clear(), throwsUnsupportedError);
        expect(directory.canManageUsers, isFalse);
        expect(directory.users, isEmpty);
        final request = transport.calls.single;
        expect(request.method, 'GET');
        expect(request.uri.path, '/v1/businesses/$business/claimants');
        expect(request.uri.queryParameters, {'search': '%_!'});
        expect(request.body, isNull);
        expect(request.token, token);
      },
    );
  }

  test(
    'malformed or over-broad claimant projections cannot enter the form',
    () async {
      final valid = context('employee');
      final actor = identity(member, 'employee');
      final bad = <Map<String, dynamic>>[
        {...valid, 'businessId': otherBusiness},
        {
          ...valid,
          'actor': {...actor, 'role': 'owner'},
        },
        {
          ...valid,
          'actor': {...actor, 'email': 'private@example.test'},
        },
        {
          ...valid,
          'actor': {...actor, 'name': '  '},
        },
        {
          ...valid,
          'actor': {...actor, 'revision': -1},
        },
        {
          ...valid,
          'actor': {...actor, 'revision': 1.5},
        },
        {
          ...valid,
          'actor': {...actor, 'id': 'local-payee'},
        },
        {
          ...valid,
          'claimants': [actor, actor],
        },
        {
          ...valid,
          'claimants': [identity(claimant, 'employee')],
        },
        {
          ...valid,
          'claimants': [
            {...actor, 'revision': 3},
          ],
        },
        {
          ...valid,
          'claimants': [
            {...actor, 'role': 'director'},
          ],
        },
        {
          ...valid,
          'claimants': [
            {...actor, 'name': 'Changed'},
          ],
        },
        {
          ...valid,
          'claimants': [
            {...actor, 'email': 'private@example.test'},
          ],
        },
        {...valid, 'claimants': List.filled(101, actor)},
        {...valid, 'claimants': 'not-a-list'},
        {...valid, 'canChooseOnBehalf': true},
        {...valid, 'actor': null},
      ];
      for (final body in bad) {
        transport.response = MembershipResponse(200, jsonEncode(body));
        await expectLater(
          service.claimants(''),
          throwsA(
            isA<MembershipFailure>().having(
              (e) => e.code,
              'code',
              'invalid_response',
            ),
          ),
        );
      }
      await expectLater(service.claimants('é' * 321), throwsArgumentError);
      expect(transport.calls, hasLength(bad.length));
    },
  );

  test('no search matches still retains the verified actor', () async {
    transport.response = MembershipResponse(
      200,
      jsonEncode({...context('employee'), 'claimants': []}),
    );
    final result = await service.claimants('no matches');
    expect(result.claimants, isEmpty);
    expect(result.actor.identityId, member);
    expect(result.canChooseOnBehalf, isFalse);
  });

  test(
    'revoked access is reported without a cached or local claimant fallback',
    () async {
      final directory = ConnectedUserDirectory(service);
      addTearDown(directory.dispose);
      transport.response = MembershipResponse(
        200,
        jsonEncode(context('accountant')),
      );
      expect((await directory.findClaimants(''))!.claimants, hasLength(2));
      transport.response = const MembershipResponse(
        403,
        '{"error":"claim_access_required"}',
      );
      await expectLater(
        directory.findClaimants(''),
        throwsA(
          isA<MembershipFailure>().having(
            (e) => e.code,
            'code',
            'claim_access_required',
          ),
        ),
      );
    },
  );

  test(
    'late lookup cannot survive a disposed account or company session',
    () async {
      final directory = ConnectedUserDirectory(service);
      transport.pending = Completer<MembershipResponse>();
      final pending = directory.findClaimants('');
      await Future<void>.delayed(Duration.zero);
      expect(transport.calls, hasLength(1));
      directory.dispose();
      transport.pending!.complete(
        MembershipResponse(200, jsonEncode(context('director'))),
      );
      expect(await pending, isNull);
      expect(await directory.findClaimants(''), isNull);
      expect(transport.calls, hasLength(1));
      expect(transport.closed, isTrue);
    },
  );

  test(
    'fictional preview directory does not grant live Claim context',
    () async {
      final preview = PreviewUserDirectory();
      addTearDown(preview.dispose);
      expect(await preview.findClaimants(''), isNull);
    },
  );
}
