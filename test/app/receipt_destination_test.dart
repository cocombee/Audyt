import 'dart:convert';
import 'package:audyt/app/naming_setup.dart';
import 'package:audyt/app/receipt_destination.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('uses saved format and passes exact bytes and accounting date', () async {
    MethodCall? write;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(namingSettingsChannel, (call) async {
      if (call.method == 'load') return jsonEncode([{'type': 'category', 'text': ''}, {'type': 'separator', 'text': '-'}, {'type': 'receiptDate', 'text': ''}]);
      write = call;
      return '/chosen/2026/09. September/RENT-1409.png';
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(namingSettingsChannel, null));
    final path = await saveReceiptDestination(kind: SetupKind.expense, attachmentId: 'one', date: DateTime(2026, 9, 14), categoryCode: 'RENT', mimeType: 'image/png', bytes: Uint8List.fromList([1, 2, 3]));
    expect(path, endsWith('RENT-1409.png'));
    expect(write!.method, 'saveDocument');
    expect(write!.arguments['year'], 2026);
    expect(write!.arguments['month'], 9);
    expect(write!.arguments['filename'], 'RENT-1409.png');
    expect(write!.arguments['bytes'], [1, 2, 3]);
  });
  test('missing naming setup cannot call destination writer', () async {
    var wrote = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(namingSettingsChannel, (call) async { if (call.method != 'load') wrote = true; return null; });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(namingSettingsChannel, null));
    await expectLater(saveReceiptDestination(kind: SetupKind.claims, attachmentId: 'one', date: DateTime(2026), categoryCode: 'RENT', mimeType: 'image/jpeg', bytes: Uint8List(1)), throwsStateError);
    expect(wrote, false);
  });
}
