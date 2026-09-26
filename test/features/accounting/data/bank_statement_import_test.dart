import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/bank_statement_import.dart';
import 'package:audyt/features/accounting/domain/payment_account.dart';

BankStatementImport parse(String text, {String currency = 'MYR'}) =>
    BankStatementImport.csv(
      filename: 'Statement.csv',
      currency: currency,
      bytes: Uint8List.fromList(utf8.encode(text)),
    );

void main() {
  test(
    'CSV preserves quoted values and separate identical rows without rounding',
    () {
      final statement = parse(
        '\uFEFFDate,Description,Amount,Reference\r\n2026-09-01,"Shop, ""A""\nbranch",-12.50,001\r\n2026-09-01,Same,5.00,x\r\n2026-09-01,Same,5.00,x\r\n',
      );
      expect(statement.rows, hasLength(3));
      expect(statement.rows.first.description, 'Shop, "A"\nbranch');
      expect(statement.rows.first.amount.minorUnits, -1250);
      expect(statement.rows.first.reference, '001');
      expect(statement.rows.map((r) => r.sourceRow), [2, 3, 4]);
      final bytes = statement.sourceBytes;
      bytes[0] = 0;
      expect(statement.sourceBytes[0], isNot(0));
      expect(() => statement.rows.clear(), throwsUnsupportedError);
      for (final invalid in [
        'Date,Description,Amount\n2026-02-30,Shop,2.00',
        'Date,Description,Amount\n01/09/2026,Shop,2.00',
        'Date,Description,Amount\n2026-09-01,Shop,2.001',
        'Date,Description,Amount\n2026-09-01,"Shop,2.00',
        'Date,Description,Amount\n2026-09-01,"Shop"x,2.00',
        'Date,Date,Amount\n2026-09-01,Shop,2.00',
      ]) {
        expect(() => parse(invalid), throwsFormatException);
      }
      expect(
        () => parse(
          'Date,Description,Amount\n2026-09-01,Shop,1.1',
          currency: 'JPY',
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'original imports deduplicate and survive restart without posting',
    () async {
      final dir = Directory.systemTemp.createTempSync('statement-import-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/ledger.sqlite';
      var workspace = await AccountingWorkspace.open(path);
      final business = workspace.identity.businessId;
      workspace.savePaymentAccount(
        PaymentAccount.create(
          id: 'bank',
          name: 'Bank',
          type: PaymentAccountType.bank,
          currencyCode: 'MYR',
        ),
      );
      final statement = parse(
        'Date,Description,Amount\n2026-09-01,Shop,-10.00',
      );
      EntityId save(
        EntityId scope,
        String payment,
        BankStatementImport source,
      ) => workspace.database.importBankStatement(
        id: EntityId.random(),
        businessId: scope,
        paymentAccountId: payment,
        statement: source,
        importedAt: DateTime.now(),
      );
      expect(
        () => save(EntityId.random(), 'bank', statement),
        throwsStateError,
      );
      expect(() => save(business, 'missing', statement), throwsStateError);
      final id = save(business, 'bank', statement);
      expect(save(business, 'bank', statement), id);
      expect(workspace.unresolvedBankStatementRows, 1);
      expect(workspace.bankStatementsAwaitingApproval, 1);
      expect(workspace.bankReviewNotificationCount, 2);
      expect(
        () => workspace.savePaymentAccount(
          PaymentAccount.create(
            id: 'bank',
            name: 'Bank',
            type: PaymentAccountType.bank,
            currencyCode: 'USD',
          ),
        ),
        throwsStateError,
      );
      final raw = sqlite3.open(path);
      expect(raw.select('SELECT id FROM bank_statement_imports'), hasLength(1));
      expect(
        () => raw.execute('DELETE FROM bank_statement_imports'),
        throwsA(isA<SqliteException>()),
      );
      raw.dispose();
      workspace.dispose();
      workspace = await AccountingWorkspace.open(path);
      final restored = workspace.database.bankStatement(business, id)!;
      expect(restored.sourceBytes, statement.sourceBytes);
      expect(restored.digest, statement.digest);
      expect(restored.rows.single.amount.minorUnits, -1000);
      expect(workspace.database.bankStatement(EntityId.random(), id), isNull);
      expect(save(business, 'bank', statement), id);
      expect(await workspace.journals(), isEmpty);
      workspace.dispose();
    },
  );
}
