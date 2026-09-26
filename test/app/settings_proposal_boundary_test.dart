import 'package:audyt/app/field_row_trial.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/frontend_review.dart';
import 'package:audyt/app/live_settings_catalog.dart';
import 'package:audyt/app/naming_setup.dart';
import 'package:audyt/app/workspace_backup_controls.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('actual proposal cannot invoke account or backup actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1224, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final workspace = await AccountingWorkspace.open(':memory:');
    addTearDown(workspace.dispose);
    var openedExternal = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => openAccountingSettings(
                context,
                workspace: workspace,
                proposalOnly: true,
                fields: {
                  'Sign-In & Sessions': {},
                  'Users & Accountant Access': {},
                  'Backup & Export Preferences': {
                    'Backup Frequency',
                    'Export Format',
                  },
                },
                setupKinds: {},
                onManageUsers: () {
                  openedExternal = true;
                },
                onAuditLog: () {
                  openedExternal = true;
                },
                onOpenRestored: (_) async {
                  openedExternal = true;
                },
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    for (final section in [
      'Sign-In & Sessions',
      'Users & Accountant Access',
      'Backup & Export Preferences',
    ]) {
      await tester.ensureVisible(find.text(section).last);
      await tester.tap(find.text(section).last);
      await tester.pumpAndSettle();
    }
    for (final key in ['settings-google-account', 'settings-manage-users']) {
      expect(
        tester.widget<FilledButton>(find.byKey(ValueKey(key))).onPressed,
        isNull,
      );
    }
    expect(find.text('Audit Log'), findsNothing);
    expect(find.byType(WorkspaceBackupControls), findsNothing);
    expect(openedExternal, isFalse);
    expect(workspace.preferences.revision, 0);
    expect(tester.takeException(), isNull);
  });
  for (final width in [480.0, 720.0, 1224.0]) {
    testWidgets('actual Settings proposal never commits at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final workspace = await AccountingWorkspace.open(':memory:');
      addTearDown(workspace.dispose);
      final original = workspace.preferences.toJson();
      final revision = workspace.preferences.revision;
      final nativeCalls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        namingSettingsChannel,
        (call) async {
          nativeCalls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          namingSettingsChannel,
          null,
        ),
      );

      Future<void> open(String title, Map<String, Set<String>> fields) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AccountingTheme.light(),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => openAccountingSettings(
                    context,
                    workspace: workspace,
                    proposalOnly: true,
                    title: '$title · Proposed',
                    fields: fields,
                    setupKinds: {},
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
      }

      for (final source in liveSettingsForms({})) {
        await open(source.title, {
          source.title: source.fields.map((f) => f.label).toSet(),
        });
        await tester.tap(find.text(source.title).last);
        await tester.pumpAndSettle();
        final form = tester.widget<FrontendFormDialog>(
          find.byType(FrontendFormDialog),
        );
        expect(form.onCommit, isNull, reason: source.title);
        expect(form.fieldLayoutOwner, AccountingFieldLayoutOwner.sharedPopup);
        expect(
          find.byKey(const ValueKey('design-save-settings')),
          findsNothing,
        );
        if (source.title == 'Numbering & Document Appearance') {
          final prefix = find.byKey(
            const ValueKey('design-field-Number Prefix'),
          );
          await tester.ensureVisible(prefix);
          await tester.enterText(prefix, 'PROPOSAL');
          final preview = find.byKey(const ValueKey('design-review'));
          await tester.ensureVisible(preview);
          await tester.tap(preview);
          await tester.pumpAndSettle();
          expect(find.text('PROPOSAL'), findsWidgets);
          expect(find.text('Continue Editing'), findsOneWidget);
          await tester.ensureVisible(find.text('Continue Editing'));
          await tester.tap(find.text('Continue Editing'));
          await tester.pumpAndSettle();
          expect(
            tester.widget<TextFormField>(prefix).controller!.text,
            'PROPOSAL',
          );
        }
        expect(workspace.preferences.toJson(), original, reason: source.title);
        expect(workspace.preferences.revision, revision);
        expect(tester.takeException(), isNull, reason: source.title);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }

      for (final title in [
        'Invoices',
        'Quotations',
        'Bills',
        'Record Expense',
        'Products & Services',
      ]) {
        final fields = transactionSettingsFields(title);
        await open(title, fields);
        for (final section in fields.keys) {
          await tester.ensureVisible(find.text(section).last);
          await tester.tap(find.text(section).last);
          await tester.pumpAndSettle();
          final form = tester.widget<FrontendFormDialog>(
            find.byType(FrontendFormDialog).last,
          );
          expect(form.onCommit, isNull);
          expect(form.form.fields.map((f) => f.label).toSet(), fields[section]);
        }
        expect(workspace.preferences.toJson(), original);
        expect(workspace.preferences.revision, revision);
        expect(tester.takeException(), isNull, reason: title);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
      expect(nativeCalls, isEmpty);
    });
  }
}
