import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/filed_document_version_relocation_test.dart' show FiledFixture;

Future<String>? _nativeBinary;
final _pendingNative = <WidgetTester, Future<dynamic>>{};

Future<String> _compileNative() async {
  final root = Directory.systemTemp.createTempSync(
    'audyt-document-ui-compiler-',
  );
  addTearDown(() {
    _nativeBinary = null;
    root.deleteSync(recursive: true);
  });
  final binary = '${root.path}/document-bridge';
  final result = await Process.run('xcrun', [
    'swiftc',
    '-module-cache-path',
    '${root.path}/ModuleCache',
    '${Directory.current.path}/macos/Runner/ReceiptDestinationWriter.swift',
    '${Directory.current.path}/macos/Runner/DocumentPreviewRenderer.swift',
    '${Directory.current.path}/test/native/filed_document_versions/main.swift',
    '-o',
    binary,
  ]);
  expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  return binary;
}

/// Start a new widget-test host without Futures tied to an earlier fake zone.
void resetGeneratedDocumentAssetCache() {
  // A fresh widget-test host has a fresh async zone. Cached string Futures
  // from an earlier host retain its fake microtask queue, unlike binary loads.
  // Evict only the renderer's SVG text assets; production caching stays intact.
  for (final asset in [
    'assets/icons/document-contact-phone.svg',
    'assets/icons/document-contact-email.svg',
  ]) {
    rootBundle.evict(asset);
  }
}

/// Transport only: production native owners write/read actual files and render
/// the actual generated PDF through PDFKit, with disposable grants/preferences.
Future<FiledFixture> installGeneratedDocumentHost(WidgetTester tester) async {
  resetGeneratedDocumentAssetCache();
  final fixture = (await tester.runAsync(
    () async => FiledFixture.create(await (_nativeBinary ??= _compileNative())),
  ))!;
  for (final name in ['audyt/naming-settings', 'audyt/document-preview']) {
    final channel = MethodChannel(name);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          // Start process I/O outside Flutter's simulated async zone and let
          // the journey await that same operation before pumping its reply.
          return runGeneratedDocumentNativeCall(tester, fixture, call);
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
  }
  addTearDown(() => tester.runAsync(fixture.close));
  addTearDown(() => _pendingNative.remove(tester));
  return fixture;
}

/// Reuse the real transport in journeys that also inspect native requests.
Future<dynamic> runGeneratedDocumentNativeCall(
  WidgetTester tester,
  FiledFixture fixture,
  MethodCall call,
) async {
  final request = tester.runAsync(() => fixture.channel(call));
  _pendingNative[tester] = request;
  try {
    return await request;
  } finally {
    if (identical(_pendingNative[tester], request)) {
      _pendingNative.remove(tester);
    }
  }
}

/// PDF asset loading, native subprocesses and engine decoding need real time.
/// Simulated pumpAndSettle alone cannot finish those asynchronous operations.
Future<void> pumpGeneratedDocumentWork(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  await tester.pump();
  bool busy() =>
      find.text('Preparing…').evaluate().isNotEmpty ||
      find.text('Saving…').evaluate().isNotEmpty ||
      find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
  while (busy() && DateTime.now().isBefore(deadline)) {
    final native = _pendingNative[tester];
    if (native != null) {
      await native;
    } else {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
    }
    // Advance dialog close animations as well as asynchronous replies.
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(
    busy(),
    isFalse,
    reason:
        'Actual document work must finish before asserting the journey. '
        'Preparing=${find.text('Preparing…').evaluate().length}, '
        'Saving=${find.text('Saving…').evaluate().length}, '
        'spinners=${find.byType(CircularProgressIndicator).evaluate().length}, '
        'native=${_pendingNative.containsKey(tester)}.',
  );
  await tester.pumpAndSettle();
}
