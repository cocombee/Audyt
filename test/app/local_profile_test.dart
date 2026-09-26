import 'dart:convert';

import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/local_profile.dart';
import 'package:audyt/app/membership_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as raster;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Google profile storage requests stay scoped to the stable subject',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final profiles = <String, Map<String, String>>{};
      messenger.setMockMethodCallHandler(LocalProfile.channel, (call) async {
        final args = Map<String, String>.from(call.arguments as Map);
        final subject = args['googleSubject'] ?? '';
        if (call.method == 'load') {
          return profiles[subject] ?? <String, String>{};
        }
        profiles[subject] = args;
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(LocalProfile.channel, null),
      );
      await const LocalProfile(
        googleSubject: 'first',
        name: 'Aina',
        email: 'new@example.test',
        role: 'Director',
        department: 'Finance',
        employeeReference: 'F01',
        responsibility: 'Finance Oversight',
      ).save();
      final first = await LocalProfile.load(googleSubject: 'first');
      expect(first.isComplete, isTrue);
      expect(first.email, 'new@example.test');
      expect(first.employeeReference, 'F01');
      expect(first.responsibility, 'Finance Oversight');
      final second = await LocalProfile.load(googleSubject: 'second');
      expect(second.isComplete, isFalse);
      expect(second.role, isEmpty);
      expect(second.email, isEmpty);
    },
  );
  test('missing optional Google photo never blocks setup', () async {
    expect(await loadGoogleProfilePhoto(null), isEmpty);
    expect(await loadGoogleProfilePhoto('https://example.com/photo'), isEmpty);
    expect(
      await loadGoogleProfilePhoto('http://lh3.googleusercontent.com/photo'),
      isEmpty,
    );
  });
  testWidgets(
    'local profile loads, edits, saves and removes duplicate settings',
    (tester) async {
      final photo = base64Encode(
        raster.encodeJpg(raster.Image(width: 4, height: 4)),
      );
      var stored = <String, String>{
        'name': 'Aina',
        'email': 'aina@example.com',
        'photo': photo,
      };
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        LocalProfile.channel,
        (call) async {
          if (call.method == 'load') return stored;
          if (call.method == 'save') {
            stored = Map<String, String>.from(call.arguments as Map);
            return null;
          }
          throw StateError(call.method);
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          LocalProfile.channel,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: const Scaffold(
            body: Align(
              alignment: Alignment.topRight,
              child: LocalProfileMenu(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('global-profile')));
      await tester.pumpAndSettle();
      expect(find.text('Edit Profile'), findsOneWidget);
      expect(
        tester
            .widget<CircleAvatar>(find.byType(CircleAvatar).first)
            .backgroundImage,
        isA<MemoryImage>(),
      );
      expect(find.byKey(const ValueKey('profile-menu-settings')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('profile-menu-profile')));
      await tester.pumpAndSettle();
      expect(
        find.text('Your contact details and accounting responsibilities.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('accounting-form-dialog-footer')),
        findsOneWidget,
      );
      final dialog = find.byType(AlertDialog);
      final close = find
          .descendant(of: dialog, matching: find.byType(IconButton))
          .first;
      final closeBefore = tester.getRect(close);
      final footerBefore = tester.getRect(
        find.byKey(const ValueKey('accounting-form-dialog-footer')),
      );
      await tester.ensureVisible(find.byKey(const ValueKey('profile-role')));
      await tester.pumpAndSettle();
      expect(tester.getRect(close), closeBefore);
      expect(
        tester.getRect(
          find.byKey(const ValueKey('accounting-form-dialog-footer')),
        ),
        footerBefore,
      );
      await tester.enterText(
        find.byKey(const ValueKey('profile-name')),
        'Daniel',
      );
      await tester.enterText(
        find.byKey(const ValueKey('profile-job-title')),
        'Chief Financial Officer',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('profile-role')));
      await tester.pumpAndSettle();
      await tester.drag(
        find
            .descendant(
              of: dialog,
              matching: find.byType(SingleChildScrollView),
            )
            .first,
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(const ValueKey('profile-role'))).bottom,
        lessThan(
          tester
              .getRect(
                find.byKey(const ValueKey('accounting-form-dialog-footer')),
              )
              .top,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('profile-role')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Accountant').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('profile-save')));
      await tester.pumpAndSettle();
      expect(stored['name'], 'Daniel');
      expect(stored['jobTitle'], 'Chief Financial Officer');
      expect(stored['role'], 'Accountant');
      expect(stored['photo'], photo);
      await tester.tap(find.byKey(const ValueKey('global-profile')));
      await tester.pumpAndSettle();
      expect(find.text('Edit Profile'), findsOneWidget);
    },
  );
  testWidgets(
    'profile submission failure preserves saved details and permits retry',
    (tester) async {
      var stored = <String, String>{
        'name': 'Fictional Applicant',
        'email': 'contact@example.test',
        'role': 'Director',
        'googleSubject': 'fictional-first',
      };
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        LocalProfile.channel,
        (call) async {
          if (call.method == 'load') return stored;
          stored = Map<String, String>.from(call.arguments as Map);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          LocalProfile.channel,
          null,
        ),
      );
      var submissions = 0;
      await tester.binding.setSurfaceSize(const Size(1200, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: LocalProfileMenu(
              submitRegistration: (profile) async {
                expect(profile.googleSubject, 'fictional-first');
                expect(profile.role, 'Director');
                submissions++;
                if (submissions == 1) {
                  throw const MembershipFailure('service_unavailable');
                }
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('global-profile')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('profile-menu-profile')));
      await tester.pumpAndSettle();
      expect(find.text('Submit'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('profile-save')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Your profile is saved on this device.'),
        findsOneWidget,
      );
      expect(stored['email'], 'contact@example.test');
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('profile-save')));
      await tester.pumpAndSettle();
      expect(submissions, 2);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
}
