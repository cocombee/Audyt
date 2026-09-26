import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/app/app.dart';

import 'journal_workspace_integration_test.dart' show captureUi;

void main() {
  for (final width in [1224.0, 430.0]) {
    testWidgets('preview sections and filters at $width', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      if (Platform.environment['AUDYT_UI_CAPTURE_DIR'] != null) {
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        await (FontLoader('Arial')..addFont(
              Future.value(
                ByteData.sublistView(
                  File('/System/Library/Fonts/Supplemental/Arial.ttf')
                      .readAsBytesSync(),
                ),
              ),
            ))
            .load();
      }
      for (final route in [
        'sales-customers',
        'contacts-items',
        'taxes',
        'documents',
      ]) {
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: AudytApp(key: ValueKey(route), initialPath: '/$route'),
          ),
        );
        await tester.pumpAndSettle();
        final target = find.byKey(
          ValueKey(
            route == 'contacts-items'
                ? 'preview-tab-sales-customers-8'
                : 'preview-tab-$route-1',
          ),
        );
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        await tester.tap(target);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('preview-filter-Date Range')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('preview-record-search')),
          findsNothing,
        );
        await captureUi(tester, 'Design $route ${width.toInt()}');
        expect(tester.takeException(), isNull);
      }
    });
  }
}
