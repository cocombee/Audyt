import 'dart:async';
import 'dart:io';

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_icons.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/field_guidance.dart';
import 'package:audyt/app/field_row_trial.dart';
import 'package:audyt/app/workspace_backup_controls.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/application/workspace_backup.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'claim_receipts_proposal_test.dart' show capture, prepare, tap;
import 'sales_email_settings_dialog_test.dart' show host, keyed;
import 'restored_page_routes_test.dart' show tables;

void main() {
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(WorkspaceBackup.channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('audyt/naming-settings'),
          null,
        );
  });
  for (final width in [720.0, 1162.0]) {
    testWidgets(
      'actual Backup field run fits and preserves commands at $width',
      (t) async {
        var folder = '';
        final calls = <MethodCall>[];
        final folderChoice = Completer<String?>();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(WorkspaceBackup.channel, (call) async {
              calls.add(call);
              return switch (call.method) {
                'info' => <String, Object?>{
                  'folder': folder.isEmpty ? null : folder,
                },
                'chooseFolder' => folderChoice.future,
                'export' => null,
                _ => throw StateError(
                  'Unexpected backup mutation: ${call.method}',
                ),
              };
            });
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('audyt/naming-settings'),
              (_) async => null,
            );
        final w = await host(t, width);
        final before = tables(w);
        await tap(t, keyed('settings-editor-Backup & Export Preferences'));
        await t.ensureVisible(keyed('design-field-Backup Frequency'));
        await t.pumpAndSettle();
        final frequency = t.getRect(keyed('design-field-Backup Frequency'));
        final format = t.getRect(keyed('design-field-Export Format'));
        final destination = t.getRect(keyed('backup-destination'));
        final destinationSlot = t.getRect(keyed('backup-destination-slot'));
        expect(frequency.top, closeTo(format.top, 0.01));
        expect(destination.top, closeTo(frequency.top, 0.01));
        expect(frequency.right, lessThan(format.left));
        expect(format.right, lessThan(destination.left));
        expect(destination.width, closeTo(destinationSlot.width, 0.5));
        expect(destination.left, closeTo(destinationSlot.left, 0.5));
        expect(destination.right, closeTo(destinationSlot.right, 0.5));
        expect(destination.height, closeTo(frequency.height, 0.01));
        final iconRect = t.getRect(
          find.descendant(
            of: keyed('backup-destination'),
            matching: find.byType(AccountingButtonIcon),
          ),
        );
        final labelRect = t.getRect(
          find.descendant(
            of: keyed('backup-destination'),
            matching: find.text('Choose Folder'),
          ),
        );
        expect(
          (iconRect.left + labelRect.right) / 2,
          closeTo(destination.center.dx, 1),
        );
        expect(destination.height, closeTo(accountingControlHeight, 0.5));
        expect(find.byType(WorkspaceBackupControls), findsOneWidget);
        await t.ensureVisible(find.text('Backup & Export Preferences'));
        await t.pumpAndSettle();
        await capture(
          t,
          'Backup Destination Field Fill Three Up ${width.toInt()}',
        );
        await tap(t, keyed('design-preview'));
        final previewSlot = t.getRect(keyed('backup-destination-slot'));
        final previewButton = t.getRect(keyed('backup-destination'));
        expect(previewButton.left, closeTo(previewSlot.left, 0.5));
        expect(previewButton.right, closeTo(previewSlot.right, 0.5));
        expect(previewButton.height, closeTo(accountingControlHeight, 0.5));
        await capture(
          t,
          'Backup Destination Frontend Preview Fill ${width.toInt()}',
        );
        await tap(t, keyed('design-preview'));
        for (final label in [
          'Backup Frequency',
          'Export Format',
          'Backup Destination',
        ]) {
          final message = accountingFieldGuidance(label)!;
          expect(find.text(message), findsNothing);
          final help = find.byWidgetPredicate(
            (widget) => widget is AccountingFieldHelp && widget.label == label,
          );
          await t.ensureVisible(help);
          await t.tap(help);
          await t.pumpAndSettle();
          expect(find.text(message), findsOneWidget);
          await capture(t, 'Backup $label Helper ${width.toInt()}');
          Tooltip.dismissAllToolTips();
          await t.pumpAndSettle();
          expect(find.text(message), findsNothing);
        }
        expect(
          find.textContaining('Scheduled backups run while Audyt is open'),
          findsNothing,
        );
        final button = t.widget<ButtonStyleButton>(keyed('backup-destination'));
        button.onPressed!();
        await t.pump();
        expect(
          t.widget<ButtonStyleButton>(keyed('export-data')).onPressed,
          isNull,
        );
        expect(
          t.widget<ButtonStyleButton>(keyed('backup-now')).onPressed,
          isNull,
        );
        folder = '/A long existing backup destination/With several descriptive folder names/For this company';
        folderChoice.complete(folder);
        await t.pumpAndSettle();
        expect(
          calls.where((call) => call.method == 'chooseFolder'),
          hasLength(1),
        );
        final args = Map<String, Object?>.from(
          calls.singleWhere((call) => call.method == 'chooseFolder').arguments
              as Map,
        );
        expect(args['businessId'], w.identity.businessId.value);
        final retained = t.getRect(keyed('backup-destination'));
        expect(
          retained.top,
          greaterThan(t.getRect(keyed('design-field-Backup Frequency')).bottom),
        );
        expect(
          retained.width,
          lessThanOrEqualTo(
            t.getSize(find.byType(WorkspaceBackupControls)).width,
          ),
        );
        expect(retained.height, closeTo(accountingControlHeight, 0.5));
        await t.ensureVisible(find.text('Backup & Export Preferences'));
        await t.pumpAndSettle();
        await capture(
          t,
          'Backup Destination Field Fill Long Path ${width.toInt()}',
        );
        await tap(t, keyed('export-data'));
        expect(calls.where((call) => call.method == 'export'), hasLength(1));
        expect(tables(w), before);
        expect(
          t.widget<ButtonStyleButton>(keyed('backup-destination')).onPressed,
          isNotNull,
        );
        expect(t.takeException(), isNull);
      },
    );
  }

  testWidgets('Backup Destination fills its stacked popout field slot', (
    t,
  ) async {
    await prepare(t, 720);
    final root = Directory.systemTemp.createTempSync(
      'audyt-backup-stacked-row-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final workspace = await AccountingWorkspace.open(
      '${root.path}/company.sqlite',
    );
    addTearDown(workspace.dispose);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(WorkspaceBackup.channel, (call) async {
      if (call.method == 'info') return <String, Object?>{'folder': null};
      throw StateError('Unexpected backup call: ${call.method}');
    });

    final definitions = [
      (
        label: 'Backup Frequency',
        value: 'Manual',
        choices: ['Manual', 'Daily', 'Weekly', 'Monthly'],
      ),
      (label: 'Export Format', value: 'JSON', choices: ['JSON', 'CSV']),
    ];
    final fields = [
      for (final definition in definitions)
        AccountingOrdinaryFieldSlot(
          label: definition.label,
          choices: definition.choices,
          hasGuidance: true,
          builder: (assignedWidth) => Builder(
            builder: (context) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                accountingFieldLabel(
                  context,
                  definition.label,
                  alignToField: true,
                  guidance: accountingFieldGuidance(definition.label),
                ),
                const SizedBox(height: accountingFieldLabelGap),
                AccountingSelector<String>(
                  triggerKey: ValueKey('stacked-${definition.label}'),
                  options: [
                    for (final choice in definition.choices)
                      AccountingSelectorOption(value: choice, label: choice),
                  ],
                  value: definition.value,
                  onChanged: (_) {},
                  hintText: 'Select ${definition.label}',
                  assignedWidth: assignedWidth,
                ),
              ],
            ),
          ),
        ),
    ];
    const rowWidth = 430.0;
    await t.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('workspace-capture'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: rowWidth,
                child: WorkspaceBackupControls(
                  preferenceFields: fields,
                  preferenceFieldsWidth: rowWidth,
                  backup: WorkspaceBackup(workspace),
                  onOpenRestored: (_) async {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();

    final frequency = t.getRect(keyed('stacked-Backup Frequency'));
    final format = t.getRect(keyed('stacked-Export Format'));
    final slot = t.getRect(keyed('backup-destination-slot'));
    final destination = t.getRect(keyed('backup-destination'));
    expect(frequency.top, closeTo(format.top, 0.5));
    expect(destination.top, greaterThan(format.bottom));
    expect(destination.left, closeTo(slot.left, 0.5));
    expect(destination.right, closeTo(slot.right, 0.5));
    expect(destination.height, closeTo(accountingControlHeight, 0.5));
    final iconRect = t.getRect(
      find.descendant(
        of: keyed('backup-destination'),
        matching: find.byType(AccountingButtonIcon),
      ),
    );
    final labelRect = t.getRect(
      find.descendant(
        of: keyed('backup-destination'),
        matching: find.text('Choose Folder'),
      ),
    );
    expect(
      (iconRect.left + labelRect.right) / 2,
      closeTo(destination.center.dx, 1),
    );
    await capture(t, 'Backup Destination Field Fill Stacked 720');
    expect(t.takeException(), isNull);
  });
}
