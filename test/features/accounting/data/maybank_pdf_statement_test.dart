import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/maybank_pdf_statement.dart';
import 'package:audyt/features/accounting/domain/payment_account.dart';
import 'package:flutter_test/flutter_test.dart';

List<Object?> glyph(int x, int y, String text) => [
  x * 10,
  y * 10,
  text.length * 60,
  text,
];

List<Object?> samplePage({int firstBalance = 90}) => [
  glyph(90, 720, 'ACME SDN BHD'),
  glyph(350, 720, '31/08/26'),
  glyph(350, 700, '123456-654321'),
  glyph(40, 610, 'ENTRY DATE'),
  glyph(100, 610, 'TRANSACTION DESCRIPTION'),
  glyph(100, 585, 'BEGINNING BALANCE'),
  glyph(450, 585, '100.00'),
  glyph(40, 560, '01/08/26'),
  glyph(100, 560, 'SALE DEBIT'),
  glyph(360, 560, '10.00-'),
  glyph(450, 560, '$firstBalance.00'),
  glyph(100, 548, 'VILLA GROCER-WANGSA'),
  glyph(100, 536, '12345678'),
  glyph(40, 520, '02/08/26'),
  glyph(100, 520, 'FUND TRANSFER TO A/'),
  glyph(360, 520, '25.00+'),
  glyph(450, 520, '115.00'),
  glyph(100, 508, 'RENTAL'),
  glyph(100, 496, '87654321'),
];

void main() {
  final source = Uint8List.fromList(utf8.encode('%PDF-fictional-test'));

  test(
    'Maybank PDF distinguishes transaction descriptions and validates anchors',
    () {
      parse({
        String accountNumber = '123456-654321',
        String holderName = 'ACME SDN BHD',
        List<Object?>? page,
      }) => MaybankPdfStatement.parse(
        filename: 'statement.pdf',
        currency: 'MYR',
        bytes: source,
        pages: [page ?? samplePage()],
        expectedAccountNumber: accountNumber,
        expectedHolderName: holderName,
      );

      final statement = parse();
      expect(statement.rows, hasLength(2));
      expect(statement.statementDate, DateTime.utc(2026, 8, 31));
      expect(statement.accountHolderName, 'ACME SDN BHD');
      expect(statement.accountNumber, '123456-654321');
      expect(statement.openingBalance!.minorUnits, 10000);
      expect(statement.closingBalance!.minorUnits, 11500);
      expect(statement.rows.first.description, 'VILLA GROCER-WANGSA');
      expect(statement.rows.first.transactionType, 'SALE DEBIT');
      expect(statement.rows.first.reference, '12345678');
      expect(statement.rows.first.amount.minorUnits, -1000);
      expect(statement.rows.last.description, 'RENTAL');
      expect(statement.rows.last.transactionType, 'FUND TRANSFER TO A/C');
      expect(statement.rows.last.amount.minorUnits, 2500);
      expect(statement.rows.last.sourcePage, 1);
      expect(
        () => parse(accountNumber: '999999-999999'),
        throwsFormatException,
      );
      expect(() => parse(holderName: 'OTHER SDN BHD'), throwsFormatException);
      expect(
        () => parse(page: samplePage(firstBalance: 91)),
        throwsFormatException,
      );
      final wrongDate = samplePage()
        ..removeWhere((line) => (line as List)[3] == '31/08/26')
        ..add(glyph(350, 720, '31/07/26'));
      expect(() => parse(page: wrongDate), throwsFormatException);
    },
  );

  test(
    'parsed PDF rows and holder identity survive database restart',
    () async {
      final dir = Directory.systemTemp.createTempSync('maybank-import-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/ledger.sqlite';
      var workspace = await AccountingWorkspace.open(path);
      final businessId = workspace.identity.businessId;
      workspace.savePaymentAccount(
        PaymentAccount.create(
          id: 'bank',
          name: 'Bank',
          type: PaymentAccountType.bank,
          currencyCode: 'MYR',
          accountNumber: '123456-654321',
          accountHolderName: 'ACME SDN BHD',
        ),
      );
      final statement = MaybankPdfStatement.parse(
        filename: 'statement.pdf',
        currency: 'MYR',
        bytes: source,
        pages: [samplePage()],
        expectedAccountNumber: '123456-654321',
        expectedHolderName: 'ACME SDN BHD',
      );
      final id = workspace.database.importBankStatement(
        id: EntityId.random(),
        businessId: businessId,
        paymentAccountId: 'bank',
        statement: statement,
        importedAt: DateTime.utc(2026, 9, 24),
      );
      workspace.dispose();
      workspace = await AccountingWorkspace.open(path);
      expect(
        workspace.paymentAccounts.single.accountHolderName,
        'ACME SDN BHD',
      );
      final restored = workspace.database.bankStatement(businessId, id)!;
      expect(restored.digest, statement.digest);
      expect(restored.statementDate, DateTime.utc(2026, 8, 31));
      expect(restored.openingBalance!.minorUnits, 10000);
      expect(restored.closingBalance!.minorUnits, 11500);
      expect(restored.rows.map((row) => row.description), [
        'VILLA GROCER-WANGSA',
        'RENTAL',
      ]);
      expect(restored.rows.last.rawNarrative, contains('RENTAL'));
      workspace.dispose();
    },
  );
}
