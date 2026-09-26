import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/frontend_review.dart';
import 'package:audyt/app/sample_catalog.dart';

void main() {
  test('every selection is represented by an isolated sample variation', () {
    for (final form in [
      ...settingsForms,
      ...operationalExamples,
      ...frontendAreas.values.expand((f) => f),
    ]) {
      for (final field in form.fields) {
        for (var i = 0; i < field.options.length; i++) {
          expect(
            sampleValues(form, i)[field.label],
            field.options[i],
            reason: '${form.title}: ${field.label}',
          );
        }
      }
      expect(sampleStates(form.title), isNotEmpty);
    }
    expect(sampleStates('Customers'), isNot(contains('Paid')));
    expect(sampleStates('Invoices'), contains('Partially Paid'));
  });
  testWidgets('populated catalog forms render without layout exceptions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1224, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final form in [
      ...settingsForms,
      ...frontendAreas.values.expand((f) => f),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: FrontendFormDialog(
              key: ValueKey(form.title),
              form: form,
              initial: sampleValues(form, 0),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: form.title);
    }
  });
}
