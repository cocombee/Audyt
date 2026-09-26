import 'package:audyt/core/documents/folder_placement_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'renders arbitrary custom fields, date tokens, and chosen separators',
    () {
      final plan = DocumentNamingPlan([
        NamingColumn.custom('F6xF'),
        NamingColumn.separator(NamingSeparator.dash),
        NamingColumn.custom('ME'),
        NamingColumn.separator(NamingSeparator.dash),
        NamingColumn.day(),
        NamingColumn.separator(NamingSeparator.dot),
        NamingColumn.monthNumber(),
        NamingColumn.separator(NamingSeparator.dot),
        NamingColumn.yearShort(),
        NamingColumn.separator(NamingSeparator.dash),
        NamingColumn.field('type'),
        NamingColumn.separator(NamingSeparator.dash),
        NamingColumn.reference(),
      ]);

      final rendered = plan.render(
        NamingContext(
          date: DateTime.utc(2026, 1, 12),
          fields: const {'type': 'Refreshment'},
          reference: '0512',
        ),
      );

      expect(rendered, 'F6xF-ME-12.01.26-Refreshment-0512');
    },
  );

  test('accepts an unlimited number of ordered columns', () {
    final plan = DocumentNamingPlan([
      for (var index = 0; index < 32; index++) NamingColumn.custom('C$index'),
    ]);

    expect(
      plan.render(
        NamingContext(
          date: DateTime.utc(2026, 1, 12),
          fields: const {},
          reference: 'REF',
        ),
      ),
      List.generate(32, (index) => 'C$index').join(),
    );
  });
}
