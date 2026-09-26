import 'package:audyt/app/accounting_icons.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/reminder_appearance_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'journal_workspace_integration_test.dart' show captureUi;

void main() {
  testWidgets(
    'review supplied silhouettes at their actual shared caller sizes',
    (tester) async {
      tester.view.physicalSize = const Size(720, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await (FontLoader(
        'Inter',
      )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('workspace-capture'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AccountingTheme.light(),
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(20),
                child: Wrap(
                  spacing: 20,
                  runSpacing: 20,
                  children: [
                    for (final entry in <(String, Widget)>[
                      (
                        'Sidebar Home',
                        const AccountingIcon(Icons.dashboard_outlined),
                      ),
                      (
                        'Sidebar Sales',
                        const AccountingIcon(Icons.shopping_bag_outlined),
                      ),
                      (
                        'Original Profile',
                        const AccountingIcon(Icons.person_outline),
                      ),
                      (
                        'Menu Profile',
                        const AccountingProfileMenuIcon(Icons.person_outline),
                      ),
                      (
                        'Original Switch',
                        const AccountingIcon(Icons.swap_horiz),
                      ),
                      (
                        'Menu Switch',
                        const AccountingProfileMenuIcon(Icons.swap_horiz),
                      ),
                      (
                        'Email Copy',
                        const AccountingProfileMenuIcon(Icons.email_outlined),
                      ),
                      (
                        'Profile Add',
                        const AccountingProfileMenuIcon(Icons.add),
                      ),
                      ('Original Sign Out', const AccountingIcon(Icons.logout)),
                      (
                        'Menu Sign Out',
                        const AccountingProfileMenuIcon(Icons.logout),
                      ),
                      (
                        'Supplied Folder',
                        const OriginalReminderIcon(
                          'Choice:Folder',
                          color: Colors.black,
                        ),
                      ),
                      (
                        'Documents',
                        const AccountingIcon(Icons.description_outlined),
                      ),
                      (
                        'File Action',
                        const AccountingIcon.smallAction(
                          Icons.description_outlined,
                        ),
                      ),
                      (
                        'Document Settings',
                        const AccountingSettingsIcon(
                          Icons.description_outlined,
                        ),
                      ),
                    ])
                      SizedBox(
                        width: 145,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox.square(
                              dimension: 44,
                              child: Center(child: entry.$2),
                            ),
                            const SizedBox(height: 8),
                            Text(entry.$1),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await captureUi(tester, 'Requested Icon Artwork Comparison');
      expect(tester.takeException(), isNull);
    },
  );
}
