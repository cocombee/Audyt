import 'package:audyt/core/documents/document_placement.dart';
import 'package:audyt/core/documents/folder_placement_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'composes a configured root, year/month folders, and coded filename',
    () {
      final placement = DocumentPlacementPlan.build(
        rootPath: '/Users/example/Accounting',
        folderPlans: [
          DocumentNamingPlan([NamingColumn.year()]),
          DocumentNamingPlan([
            NamingColumn.monthNumber(),
            NamingColumn.separator(NamingSeparator.dot),
            NamingColumn.monthName(),
            NamingColumn.custom(' '),
            NamingColumn.year(),
          ]),
        ],
        filenamePlan: DocumentNamingPlan([
          NamingColumn.custom('F6xF'),
          NamingColumn.separator(NamingSeparator.dash),
          NamingColumn.custom('IN'),
          NamingColumn.separator(NamingSeparator.dash),
          NamingColumn.day(),
          NamingColumn.separator(NamingSeparator.dot),
          NamingColumn.monthNumber(),
          NamingColumn.separator(NamingSeparator.dot),
          NamingColumn.yearShort(),
        ]),
        context: NamingContext(
          date: DateTime.utc(2026, 1, 12),
          fields: const {},
          reference: '12',
        ),
      );

      expect(placement.relativePath, '2026/01.January 2026/F6xF-IN-12.01.26');
      expect(
        placement.absolutePath,
        '/Users/example/Accounting/2026/01.January 2026/F6xF-IN-12.01.26',
      );
    },
  );
}
