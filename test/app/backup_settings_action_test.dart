import 'dart:convert';
import 'dart:io';

import 'package:audyt/app/app.dart';
import 'package:audyt/app/naming_setup.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/application/workspace_backup.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'journal_workspace_integration_test.dart' show captureUi;
import 'restored_page_routes_test.dart' show tables;

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'saved export format reaches Export Data and Back Up Now at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        if (Platform.environment['AUDYT_UI_CAPTURE_DIR'] != null) {
          await (FontLoader('Inter')
                ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
              .load();
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
        }
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(
          namingSettingsChannel,
          (call) async => null,
        );
        addTearDown(
          () => messenger.setMockMethodCallHandler(namingSettingsChannel, null),
        );
        final exports = <Map<String, Object?>>[];
        final backups = <Map<String, Object?>>[];
        messenger.setMockMethodCallHandler(WorkspaceBackup.channel, (
          call,
        ) async {
          if (call.method == 'info') {
            return {'folder': '/tmp/Audyt Backup Fixture'};
          }
          if (call.method == 'export') {
            final args = Map<String, Object?>.from(call.arguments as Map);
            exports.add(args);
            return '/tmp/export.${args['extension']}';
          }
          if (call.method == 'write') {
            backups.add(Map<String, Object?>.from(call.arguments as Map));
            return '/tmp/verified-backup.audyt.json';
          }
          return null;
        });
        addTearDown(
          () =>
              messenger.setMockMethodCallHandler(WorkspaceBackup.channel, null),
        );

        final root = Directory.systemTemp.createTempSync(
          'audyt-backup-settings-',
        );
        addTearDown(() => root.deleteSync(recursive: true));
        final path = '${root.path}/company.sqlite';
        var workspace = await AccountingWorkspace.open(path);
        addTearDown(() => workspace.dispose());
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: AudytApp(workspace: workspace, showInitialSetup: false),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('accounting-settings')));
        await tester.pumpAndSettle();
        final section = find.text('Backup & Export Preferences').first;
        await tester.ensureVisible(section);
        await tester.tap(section);
        await tester.pumpAndSettle();

        Future<void> chooseFormat(String format) async {
          final selector = find.byKey(
            const ValueKey('design-field-Export Format'),
          );
          await tester.ensureVisible(selector);
          await tester.tap(selector);
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(MenuItemButton, format));
          await tester.pumpAndSettle();
          final save = find.byKey(const ValueKey('design-save-settings'));
          await tester.ensureVisible(save);
          await tester.tap(save);
          await tester.pumpAndSettle();
          expect(
            workspace.preferences.text(
              'Backup & Export Preferences',
              'Export Format',
            ),
            format,
          );
        }

        Future<void> exportData() async {
          final button = find.byKey(const ValueKey('export-data'));
          await tester.ensureVisible(button);
          await tester.tap(button);
          await tester.pumpAndSettle();
        }

        await chooseFormat('CSV');
        await captureUi(tester, 'Backup Settings CSV ${width.toInt()}');
        final afterCsvSave = tables(workspace);
        await exportData();
        expect(exports.last['extension'], 'csv');
        expect(
          exports.last['data'],
          startsWith('date,journal_id,memo,account_code,account_name,'),
        );
        expect(tables(workspace), afterCsvSave);

        await chooseFormat('JSON');
        final afterJsonSave = tables(workspace);
        await exportData();
        await captureUi(tester, 'Backup Settings JSON Export ${width.toInt()}');
        expect(exports.last['extension'], 'audyt.json');
        expect(
          (jsonDecode(exports.last['data'] as String) as Map)['format'],
          'Audyt Data Archive',
        );
        expect(tables(workspace), afterJsonSave);

        final backup = find.byKey(const ValueKey('backup-now'));
        await tester.ensureVisible(backup);
        await tester.tap(backup);
        await tester.pumpAndSettle();
        expect(backups, hasLength(1));
        expect(backups.single['extension'], 'audyt.json');
        expect(backups.single['backup'], true);
        expect(tables(workspace), afterJsonSave);

        await tester.pumpWidget(const SizedBox.shrink());
        workspace.dispose();
        workspace = await AccountingWorkspace.open(path);
        expect(
          workspace.preferences.text(
            'Backup & Export Preferences',
            'Export Format',
          ),
          'JSON',
        );
        expect(tables(workspace), afterJsonSave);
      },
    );
    testWidgets(
      'saved Daily schedule without folder warns in Settings at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        if (Platform.environment['AUDYT_UI_CAPTURE_DIR'] != null) {
          await (FontLoader('Inter')
                ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
              .load();
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
        }
        final root = Directory.systemTemp.createTempSync(
          'audyt-backup-warning-',
        );
        addTearDown(() => root.deleteSync(recursive: true));
        final workspace = await AccountingWorkspace.open(
          '${root.path}/ledger.sqlite',
        );
        addTearDown(workspace.dispose);
        workspace.savePreferences(
          workspace.preferences.change('Backup & Export Preferences', {
            'Backup Frequency': 'Daily',
          }),
        );
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(
          namingSettingsChannel,
          (call) async => null,
        );
        addTearDown(
          () => messenger.setMockMethodCallHandler(namingSettingsChannel, null),
        );
        String? failure;
        messenger.setMockMethodCallHandler(WorkspaceBackup.channel, (
          call,
        ) async {
          if (call.method == 'info') {
            return <String, Object?>{'lastFailure': failure};
          }
          if (call.method == 'recordFailure') {
            failure = (call.arguments as Map)['message'] as String;
            return null;
          }
          fail('Unexpected native backup call: ${call.method}');
        });
        addTearDown(
          () =>
              messenger.setMockMethodCallHandler(WorkspaceBackup.channel, null),
        );
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: AudytApp(workspace: workspace, showInitialSetup: false),
          ),
        );
        await tester.pumpAndSettle();
        expect(failure, contains('backup destination'));
        await tester.tap(find.byKey(const ValueKey('accounting-settings')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        final section = find.text('Backup & Export Preferences').first;
        await tester.ensureVisible(section);
        await tester.tap(section);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          find.textContaining('Last scheduled backup failed:'),
          findsOneWidget,
        );
        expect(find.textContaining('Bad state:'), findsNothing);
        await captureUi(tester, 'Backup Destination Warning ${width.toInt()}');
      },
    );
  }
}
