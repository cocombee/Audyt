import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/features/purchases/domain/claim_store.dart';
import 'package:audyt/features/purchases/domain/payment_voucher_store.dart';
import 'package:audyt/features/purchases/presentation/claims_page.dart';
import 'package:audyt/features/purchases/presentation/payment_vouchers_page.dart';

import 'journal_workspace_integration_test.dart' show captureUi;

void main() {
  for (final width in [430.0, 760.0, 1224.0]) {
    testWidgets('populated record families at $width', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await (FontLoader('Arial')..addFont(
            Future.value(
              ByteData.sublistView(
                File('/System/Library/Fonts/Supplemental/Arial.ttf')
                    .readAsBytesSync(),
              ),
            ),
          ))
          .load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      for (final name in ['Claims', 'Vouchers']) {
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: MaterialApp(
              theme: AccountingTheme.light(),
              home: name == 'Claims'
                  ? ClaimsPage(store: ClaimStore.demo())
                  : PaymentVouchersPage(store: PaymentVoucherStore.demo()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: name);
        await captureUi(tester, '$name ${width.toInt()}');
      }
    });
  }
}
