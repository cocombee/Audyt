import 'dart:typed_data';

import 'package:audyt/features/accounting/presentation/receipt_attachment_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'requests multi-file native selection and preserves every selected file',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: SizedBox(key: ValueKey('picker-test-context'))),
      );

      var requestedAllowMultiple = false;
      final expected = <PickedExpenseAttachment>[
        PickedExpenseAttachment(
          name: 'receipt.jpg',
          mimeType: 'image/jpeg',
          bytes: Uint8List.fromList(<int>[1, 2]),
        ),
        PickedExpenseAttachment(
          name: 'invoice.pdf',
          mimeType: 'application/pdf',
          bytes: Uint8List.fromList(<int>[3, 4]),
        ),
      ];
      final picker = NativeExpenseAttachmentPicker(
        filePicker: ({required bool allowMultiple}) async {
          requestedAllowMultiple = allowMultiple;
          return expected;
        },
      );

      final selected = await picker.pick(
        tester.element(find.byKey(const ValueKey('picker-test-context'))),
      );

      expect(requestedAllowMultiple, isTrue);
      expect(selected, same(expected));
      expect(selected.map((item) => item.name), <String>[
        'receipt.jpg',
        'invoice.pdf',
      ]);
    },
  );

  test('accepts PDF, DOC, and DOCX as reviewable document types', () {
    expect(
      NativeExpenseAttachmentPicker.supportedExtensions,
      containsAll(<String>['pdf', 'doc', 'docx']),
    );
    expect(
      NativeExpenseAttachmentPicker.mimeTypeForFilename('memo.doc'),
      'application/msword',
    );
    expect(
      NativeExpenseAttachmentPicker.mimeTypeForFilename('memo.docx'),
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    );
  });
}
