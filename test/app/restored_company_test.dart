import 'dart:io';
import 'dart:ui' as ui;

import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/app.dart';
import 'package:audyt/app/company_switcher.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/app/restored_company.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/application/restored_workspaces.dart';
import 'package:audyt/features/accounting/application/workspace_backup.dart';
import 'package:audyt/features/accounting/domain/expense_draft.dart';
import 'package:audyt/features/purchases/domain/payment_voucher.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/accounting/data/archive_upgrade_test.dart'
    show envelope, historical;
import 'journal_workspace_integration_test.dart'
    show captureUi, loadJournalLayoutFonts;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Map<String, Map<String, Object?>> entries;
  late List<MethodCall> backupCalls;
  late String? archive;
  bool rejectRegistration = false;
  bool rejectCleanup = false;
  setUp(() {
    root = Directory.systemTemp.createTempSync('audyt-restore-composition-');
    entries = {};
    backupCalls = [];
    archive = null;
    rejectRegistration = false;
    rejectCleanup = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(RestoredWorkspaces.channel, (call) async {
          final args = call.arguments as Map?;
          switch (call.method) {
            case 'registerRestoredWorkspace':
              if (rejectRegistration) {
                throw PlatformException(code: 'registration_failed');
              }
              final path = args!['path'] as String;
              return entries[path] = {
                'id': path.split('/').reversed.elementAt(1),
                'businessId': args['businessId'],
                'name': args['name'],
                'path': path,
                'createdAt': DateTime.now().toUtc().toIso8601String(),
                'available': true,
                'newTransactionCount': 0,
              };
            case 'listRestoredWorkspaces':
              return {'workspaces': entries.values.toList(), 'issues': 0};
            case 'restoredWorkspace':
              final entry = entries[args!['path']];
              if (entry == null) {
                throw PlatformException(code: 'not_registered');
              }
              return entry;
            default:
              throw MissingPluginException();
          }
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(WorkspaceBackup.channel, (call) async {
          backupCalls.add(call);
          switch (call.method) {
            case 'import':
              return archive == null ? null : {'data': archive};
            case 'newWorkspace':
              final folder = Directory('${root.path}/${EntityId.random()}')
                ..createSync();
              return '${folder.path}/ledger.sqlite';
            case 'discardPreparedWorkspace':
              if (rejectCleanup) {
                throw PlatformException(code: 'cleanup_failed');
              }
              final path = (call.arguments as Map)['path'] as String;
              File(path).parent.deleteSync(recursive: true);
              return null;
            case 'info':
              return <String, Object?>{};
            case 'recordFailure':
              return null;
            default:
              throw MissingPluginException();
          }
        });
  });
  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(RestoredWorkspaces.channel, null);
    messenger.setMockMethodCallHandler(WorkspaceBackup.channel, null);
    root.deleteSync(recursive: true);
  });

  test('import registration and reopen retain all saved company identities and records', () async {
    final source = await createDemoWorkspace(
      databasePath: '${root.path}/original.sqlite',
    );
    final identity = source.identity;
    final journalIds = (await source.journals())
        .map((row) => row.entry.id)
        .toSet();
    final expenseIds = (await source.expenses()).map((row) => row.id).toSet();
    archive = source.database.exportDataArchive(
      identity.businessId,
      DateTime.now(),
    );
    final path = (await WorkspaceBackup(source).import())!;
    expect(
      backupCalls.where((call) => call.method == 'discardPreparedWorkspace'),
      isEmpty,
    );
    source.dispose();
    // Reconstruct the client service after import rather than retain its state.
    final catalog = await const RestoredWorkspaces().list();
    final entry = catalog.entries.single;
    expect(entry.path, path);
    expect(entry.businessId, identity.businessId);
    var restored = await AccountingWorkspace.openExisting(
      path,
      businessId: entry.businessId,
      restoredCopyId: entry.id,
    );
    expect(restored.identity.ownerId, identity.ownerId);
    expect(restored.identity.deviceId, identity.deviceId);
    expect(
      (await restored.journals()).map((row) => row.entry.id).toSet(),
      journalIds,
    );
    expect(
      (await restored.expenses()).map((row) => row.id).toSet(),
      expenseIds,
    );
    expect(restored.postedInvoices(), hasLength(2));
    expect(restored.invoiceDrafts(), hasLength(1));
    expect(restored.reminders, hasLength(3));
    expect(restored.claims.all, hasLength(16));
    expect(restored.vouchers.all, hasLength(15));
    final report = await restored.report(
      from: DateTime(2000),
      through: DateTime(2200),
    );
    expect(report.trialBalanceCredits, report.trialBalanceDebits);
    expect(report.balanceSheetDifference, BigInt.zero);
    final baselineRoots = await restored.database.auditEventCount(
      entry.businessId,
      kind: 'transaction_root_created',
    );
    restored.savePreferences(
      restored.preferences.change('Sales Preferences', {
        'Customer Message': 'Copy only',
      }),
    );
    expect(
      await restored.database.auditEventCount(
        entry.businessId,
        kind: 'transaction_root_created',
      ),
      baselineRoots,
    );
    final sampleJournal = (await restored.journals()).first.entry;
    final newJournalId = await restored.saveJournal(
      date: DateTime.utc(2026, 10, 10),
      memo: 'Fictional new restored journal',
      lines: sampleJournal.lines,
    );
    expect(
      await restored.database.auditEventCount(
        entry.businessId,
        kind: 'transaction_root_created',
      ),
      baselineRoots + 1,
    );
    final voucherSources = restored.vouchers.sources
        .where(
          (source) => source.type == PaymentVoucherSourceType.directExpense,
        )
        .take(2)
        .toList();
    expect(voucherSources, hasLength(2));
    for (final (index, sourceRecord) in voucherSources.indexed) {
      restored.vouchers.save(
        PaymentVoucher.create(
          id: 'lifecycle-voucher-${index + 1}',
          sourceType: sourceRecord.type,
          sourceId: sourceRecord.id,
          payee: sourceRecord.payee,
          amount: sourceRecord.amount,
          paymentAccount: 'Demo Bank',
          paymentAccountId: sourceRecord.paymentAccountId,
          paymentMethod: 'Bank Transfer',
          paymentDate: sourceRecord.date,
          reference: 'LIFECYCLE-${index + 1}',
        ),
      );
    }
    expect(
      await restored.database.auditEventCount(
        entry.businessId,
        kind: 'transaction_root_created',
      ),
      baselineRoots + 3,
    );
    final newExpense = RecordExpenseDraft(
      submissionId: 'lifecycle-expense',
      amount: '10.00',
      date: '10-10-2026',
      payee: 'Fictional Paper Shop',
      paymentAccount: 'Cash',
      category: 'Office Operations',
      tax: 'Review Needed',
      customer: '',
      billable: false,
      dimensions: '',
      itemOrSplitDetails: '',
      notes: '',
    );
    final newExpenseId = await restored.saveExpenseIntake(newExpense);
    expect(await restored.saveExpenseIntake(newExpense), newExpenseId);
    await restored.saveJournal(
      date: DateTime.utc(2026, 10, 11),
      memo: 'Fictional fifth restored transaction',
      lines: sampleJournal.lines,
    );
    expect(
      await restored.database.auditEventCount(
        entry.businessId,
        kind: 'transaction_root_created',
      ),
      baselineRoots + 5,
    );
    final firstVoucher = restored.vouchers.byId('lifecycle-voucher-1')!;
    restored.vouchers.save(
      PaymentVoucher.fromJson({
        ...firstVoucher.toJson(),
        'reference': 'LIFECYCLE-EDITED',
      }),
      expectedCurrent: firstVoucher,
    );
    expect(
      await restored.database.auditEventCount(
        entry.businessId,
        kind: 'transaction_root_created',
      ),
      baselineRoots + 5,
    );
    await WorkspaceBackup(restored).info();
    expect((backupCalls.last.arguments as Map)['workspaceId'], entry.id);
    restored.dispose();
    restored = await AccountingWorkspace.openExisting(
      path,
      businessId: entry.businessId,
      restoredCopyId: entry.id,
    );
    expect(
      restored.preferences.text('Sales Preferences', 'Customer Message'),
      'Copy only',
    );
    expect(
      (await restored.database.auditEventPage(
        entry.businessId,
        kind: 'transaction_root_created',
        subjectId: newJournalId,
      )),
      hasLength(1),
    );
    expect(
      await restored.database.auditEventCount(
        entry.businessId,
        kind: 'transaction_root_created',
      ),
      baselineRoots + 5,
    );
    expect(
      restored.vouchers.byId('lifecycle-voucher-1')?.reference,
      'LIFECYCLE-EDITED',
    );
    restored.dispose();
    final original = await AccountingWorkspace.open(
      '${root.path}/original.sqlite',
    );
    expect(original.identity.businessId, identity.businessId);
    expect(
      original.preferences.text('Sales Preferences', 'Customer Message'),
      isNot('Copy only'),
    );
    expect(
      (await original.journals()).map((row) => row.entry.id).toSet(),
      journalIds,
    );
    final originalAuditRoots = await original.database.auditEventCount(
      identity.businessId,
      kind: 'transaction_root_created',
    );
    final originalJournal = (await original.journals()).first.entry;
    await original.saveJournal(
      date: DateTime.utc(2026, 10, 10),
      memo: 'Fictional original-company journal',
      lines: originalJournal.lines,
    );
    expect(
      await original.database.auditEventCount(
        identity.businessId,
        kind: 'transaction_root_created',
      ),
      originalAuditRoots,
    );
    await WorkspaceBackup(original).info();
    expect(
      (backupCalls.last.arguments as Map).containsKey('workspaceId'),
      false,
    );
    original.dispose();
  });

  test(
    'cancelled, invalid and unregistered imports never advertise success',
    () async {
      final source = await AccountingWorkspace.open(
        '${root.path}/original.sqlite',
      );
      addTearDown(source.dispose);
      expect(await WorkspaceBackup(source).import(), isNull);
      expect(backupCalls.map((call) => call.method), ['import']);
      archive = 'bad json';
      await expectLater(
        WorkspaceBackup(source).import(),
        throwsFormatException,
      );
      expect(
        backupCalls.where((call) => call.method == 'newWorkspace'),
        isEmpty,
      );
      archive = '{"format":"Audyt Data Archive","sha256":"wrong","data":"{}"}';
      await expectLater(
        WorkspaceBackup(source).import(),
        throwsFormatException,
      );
      expect(
        backupCalls.sublist(backupCalls.length - 2).map((call) => call.method),
        ['newWorkspace', 'discardPreparedWorkspace'],
      );
      expect(root.listSync().whereType<Directory>(), isEmpty);
      archive = source.database.exportDataArchive(
        source.identity.businessId,
        DateTime.now(),
      );
      rejectRegistration = true;
      await expectLater(
        WorkspaceBackup(source).import(),
        throwsA(isA<PlatformException>()),
      );
      expect(
        backupCalls.sublist(backupCalls.length - 2).map((call) => call.method),
        ['newWorkspace', 'discardPreparedWorkspace'],
      );
      expect(root.listSync().whereType<Directory>(), isEmpty);
      expect((await const RestoredWorkspaces().list()).entries, isEmpty);
    },
  );

  test('failed cleanup reports an incomplete recovery copy', () async {
    final source = await AccountingWorkspace.open(
      '${root.path}/original.sqlite',
    );
    addTearDown(source.dispose);
    archive = '{"format":"Audyt Data Archive","sha256":"wrong","data":"{}"}';
    rejectCleanup = true;
    await expectLater(
      WorkspaceBackup(source).import(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('incomplete copy could not be removed'),
        ),
      ),
    );
    expect(root.listSync().whereType<Directory>(), hasLength(1));
    expect((await const RestoredWorkspaces().list()).entries, isEmpty);
  });

  test('existing-only recovery rejects missing or different company without replacing data', () async {
    final expected = EntityId.random();
    final missing = '${root.path}/missing.sqlite';
    await expectLater(
      AccountingWorkspace.openExisting(
        missing,
        businessId: expected,
        restoredCopyId: EntityId.random().value,
      ),
      throwsA(isA<Object>()),
    );
    expect(File(missing).existsSync(), false);
    final wrongPath = '${root.path}/wrong.sqlite';
    final wrong = await AccountingWorkspace.open(wrongPath);
    wrong.dispose();
    final before = File(wrongPath).readAsBytesSync();
    await expectLater(
      AccountingWorkspace.openExisting(
        wrongPath,
        businessId: expected,
        restoredCopyId: EntityId.random().value,
      ),
      throwsStateError,
    );
    expect(File(wrongPath).readAsBytesSync(), before);
  });

  for (final width in [1224.0, 720.0]) {
    testWidgets(
      'restart company selector opens imported records and returns to original at $width',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        // Geometry and line-count assertions use the actual app font in every
        // run, including the complete gate without screenshot capture enabled.
        await loadJournalLayoutFonts();
        final source = await createDemoWorkspace(
          databasePath: '${root.path}/original.sqlite',
        );
        final savedBusinessName = width == 1224
            ? 'Fictional Restored Sdn. Bhd.'
            : '';
        if (savedBusinessName.isNotEmpty) {
          source.savePreferences(
            source.preferences.change('Business Profile', {
              'Business Name': savedBusinessName,
            }),
          );
        }
        final selectedName = savedBusinessName.isEmpty
            ? 'Current Company'
            : savedBusinessName;
        final expectedExpenseIds = (await source.expenses())
            .map((row) => row.id)
            .toSet();
        expect(
          expectedExpenseIds,
          hasLength(18),
        ); // Includes two linked approved Claims.
        archive = source.database.exportDataArchive(
          source.identity.businessId,
          DateTime.now(),
        );
        if (width == 720) {
          archive = envelope(historical(archive!, 36));
        }
        final path = (await WorkspaceBackup(source).import())!;
        final secondPath = '$path-second';
        final secondCopyId = EntityId.random().value;
        entries[secondPath] = {
          ...entries[path]!,
          'id': secondCopyId,
          'name': 'Fictional Second Restored Services Sdn. Bhd.',
          'path': secondPath,
        };
        source.dispose();
        final original = await AccountingWorkspace.open(
          '${root.path}/original.sqlite',
        );
        addTearDown(original.dispose);
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: AudytApp(initialPath: '/home', workspace: original),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('company-switcher')));
        await tester.pumpAndSettle();
        final option = find.byKey(
          ValueKey('company-option-restored-${entries[path]!['id']}'),
        );
        final secondOption = find.byKey(
          ValueKey('company-option-restored-$secondCopyId'),
        );
        Rect paintedOption(Finder row) {
          final material = find.descendant(
            of: row,
            matching: find.byType(Material),
          );
          expect(material, findsOneWidget);
          return tester.getRect(material);
        }

        void expectOptionGaps() {
          final current = paintedOption(
            find.byKey(const ValueKey('company-option-current')),
          );
          final demo = paintedOption(
            find.byKey(const ValueKey('company-option-demo')),
          );
          final first = paintedOption(option);
          final second = paintedOption(secondOption);
          final ordinaryGap = demo.top - current.bottom;
          expect(
            ordinaryGap,
            kMinInteractiveDimension - accountingControlHeight,
          );
          expect(first.top - demo.bottom, ordinaryGap);
          expect(second.top - first.bottom, ordinaryGap);
        }

        void expectRestoredOptionClearance(String subtitle) {
          final demoOption = find.byKey(const ValueKey('company-option-demo'));
          final singlePaint = paintedOption(demoOption);
          final singleText = tester.getRect(
            find.descendant(
              of: demoOption,
              matching: find.text('Demo Company'),
            ),
          );
          final multiPaint = paintedOption(option);
          final title = tester.getRect(
            find.descendant(
              of: option,
              matching: find.text(
                savedBusinessName.isEmpty
                    ? 'Restored Company'
                    : savedBusinessName,
              ),
            ),
          );
          final detail = tester.getRect(
            find.descendant(of: option, matching: find.text(subtitle)),
          );
          expect(singlePaint.height, accountingControlHeight);
          expect(
            title.top - multiPaint.top,
            closeTo(singleText.top - singlePaint.top, 1),
          );
          expect(
            multiPaint.bottom - detail.bottom,
            closeTo(singlePaint.bottom - singleText.bottom, 1),
          );
          expect(
            detail.bottom - title.top,
            greaterThan(singleText.height * 1.8),
          );
        }

        Future<void> captureWithHover(Finder row, String label) async {
          if (Platform.environment['AUDYT_UI_CAPTURE_DIR'] == null) return;
          final mouse = await tester.createGesture(
            kind: ui.PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: tester.getCenter(row));
          await mouse.moveTo(tester.getCenter(row));
          await tester.pumpAndSettle();
          await captureUi(tester, label);
          await mouse.removePointer();
          await tester.pumpAndSettle();
        }

        final createdAt = DateTime.parse(entries[path]!['createdAt']! as String)
            .toLocal();
        final createdDate =
            '${createdAt.day.toString().padLeft(2, '0')}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.year}';
        expect(
          find.descendant(
            of: option,
            matching: find.text('Legal Type Not Set (Restored) · $createdDate'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: option,
            matching: find.text(
              savedBusinessName.isEmpty
                  ? 'Restored Company'
                  : savedBusinessName,
            ),
          ),
          findsOneWidget,
        );
        expectRestoredOptionClearance(
          'Legal Type Not Set (Restored) · $createdDate',
        );
        expectOptionGaps();
        if (width == 1224) {
          final title = tester.getRect(
            find.descendant(of: option, matching: find.text(savedBusinessName)),
          );
          final detail = tester.getRect(
            find.descendant(
              of: option,
              matching: find.text(
                'Legal Type Not Set (Restored) · $createdDate',
              ),
            ),
          );
          final singleText = tester.getRect(
            find.descendant(
              of: find.byKey(const ValueKey('company-option-demo')),
              matching: find.text('Demo Company'),
            ),
          );
          expect(title.height, closeTo(singleText.height, 1));
          expect(detail.height, greaterThan(singleText.height * 1.4));
        }
        await tester.tap(option);
        await tester.pumpAndSettle();
        final shell = tester.widget<AccountingShell>(
          find.byType(AccountingShell).last,
        );
        expect(
          RestoredCompany.of(tester.element(find.byType(CompanySelector).last))!
              .path,
          path,
        );
        expect(
          DemoCompany.active(tester.element(find.byType(CompanySelector).last)),
          false,
        );
        final selected = find.byKey(const ValueKey('company-switcher'));
        if (width == 1224) {
          expect(
            find.descendant(of: selected, matching: find.text(selectedName)),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: selected,
              matching: find.text('Legal Type Not Set'),
            ),
            findsOneWidget,
          );
        } else {
          expect(find.byTooltip('Company: $selectedName'), findsOneWidget);
        }
        expect(
          find.descendant(
            of: selected,
            matching: find.textContaining('Restored Copy'),
          ),
          findsNothing,
        );
        await captureUi(tester, 'Restored Company Selected ${width.toInt()}');
        expect(shell.workspace!.reminders, hasLength(3));
        expect(
          (await shell.workspace!.expenses()).map((row) => row.id).toSet(),
          expectedExpenseIds,
        );
        expect(shell.workspace!.postedInvoices(), hasLength(2));
        await tester.tap(find.byKey(const ValueKey('company-switcher')));
        await tester.pumpAndSettle();
        expectRestoredOptionClearance(
          'Legal Type Not Set (Restored) · $createdDate',
        );
        expectOptionGaps();
        await captureWithHover(
          find.byKey(const ValueKey('company-option-demo')),
          'Restored Company Menu ${width.toInt()}',
        );
        await captureWithHover(
          secondOption,
          'Restored Company Adjacent Rows ${width.toInt()}',
        );
        await tester.tap(find.byKey(const ValueKey('company-switcher')));
        await tester.pumpAndSettle();
        entries[path]!['newTransactionCount'] = 5;
        entries[secondPath]!['newTransactionCount'] = 5;
        await tester.tap(find.byKey(const ValueKey('company-switcher')));
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: option,
            matching: find.text('Legal Type Not Set'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: option,
            matching: find.textContaining('(Restored)'),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: option,
            matching: find.textContaining(createdDate),
          ),
          findsNothing,
        );
        expectRestoredOptionClearance('Legal Type Not Set');
        expectOptionGaps();
        await captureWithHover(
          find.byKey(const ValueKey('company-option-demo')),
          'Restored Company Marker Expired ${width.toInt()}',
        );
        await captureWithHover(
          secondOption,
          'Restored Company Adjacent Rows Expired ${width.toInt()}',
        );
        await tester.tap(find.byKey(const ValueKey('company-option-demo')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('company-switcher')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('company-option-current')));
        await tester.pumpAndSettle();
        expect(find.byType(RestoredCompanyPage), findsNothing);
        expect(find.byType(DemoCompany), findsNothing);
        expect(
          tester
              .widget<AccountingShell>(find.byType(AccountingShell))
              .workspace,
          same(original),
        );
        expect(
          (await original.expenses()).map((row) => row.id).toSet(),
          expectedExpenseIds,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final width in [1224.0, 720.0]) {
    testWidgets('recovery failure and chooser render safely at $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final captureDir = Platform.environment['AUDYT_UI_CAPTURE_DIR'];
      final previousShadows = debugDisableShadows;
      if (captureDir != null) {
        debugDisableShadows = false;
        addTearDown(() => debugDisableShadows = previousShadows);
        await (FontLoader('Inter')
              ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
            .load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      }
      final path = '${root.path}/${EntityId.random()}/ledger.sqlite';
      final id = path.split('/').reversed.elementAt(1);
      entries[path] = {
        'id': id,
        'businessId': EntityId.random().value,
        'name': 'Restored Sample Company',
        'path': path,
        'createdAt': '2026-09-27T00:00:00Z',
        'available': true,
      };
      Future<void> capture(String label) async {
        expect(tester.takeException(), isNull);
        if (captureDir == null) return;
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('restore-capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$captureDir/$label ${width.toInt()}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('restore-capture'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AccountingTheme.light(),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 340,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CompanySelector(),
                      Builder(
                        builder: (context) => TextButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => RestoredCompanyPage(path: path),
                            ),
                          ),
                          child: const Text('Open Copy'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CompanySelector));
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('company-option-restored-$id')),
        findsOneWidget,
      );
      await capture('Restored Company Chooser');
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open Copy'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('retry-restored')), findsOneWidget);
      expect(File(path).existsSync(), false);
      await capture('Restored Company Unavailable');
      await tester.tap(find.byKey(const ValueKey('retry-restored')));
      await tester.pumpAndSettle();
      expect(File(path).existsSync(), false);
      await tester.tap(find.byKey(const ValueKey('return-from-restored')));
      await tester.pumpAndSettle();
      expect(find.text('Open Copy'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      // Flutter verifies painting globals before test tearDown callbacks.
      debugDisableShadows = previousShadows;
    });
  }
}
