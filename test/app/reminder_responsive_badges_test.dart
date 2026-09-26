import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/design_samples.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('reminder badges hide only when they would move below content', (
    tester,
  ) async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
    await tester.binding.setSurfaceSize(const Size(900, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: const Scaffold(body: DemoReminderPanel()),
      ),
    );
    expect(find.text('SST Return'), findsOneWidget);
    expect(find.text('Upcoming'), findsOneWidget);
    expect(find.text('Due Soon'), findsNWidgets(2));

    await tester.binding.setSurfaceSize(const Size(800, 800));
    await tester.pump();
    expect(find.text('Upcoming'), findsNothing);
    expect(find.text('Next'), findsOneWidget);
    expect(find.text('Due Soon'), findsNothing);
    expect(find.text('Soon'), findsNWidgets(2));

    await tester.binding.setSurfaceSize(const Size(740, 800));
    await tester.pump();
    expect(find.text('Next'), findsNothing);
    expect(find.text('Soon'), findsNothing);

    await tester.binding.setSurfaceSize(const Size(720, 800));
    await tester.pump();
    expect(find.text('Upcoming'), findsOneWidget);
    expect(find.text('Due Soon'), findsNWidgets(2));

    await tester.binding.setSurfaceSize(const Size(1224, 800));
    await tester.pump();
    expect(find.text('Upcoming'), findsOneWidget);
    expect(find.text('Due Soon'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
