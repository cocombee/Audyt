import 'package:audyt/app/demo_company.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Home reads only recent posted expenses and business-owned source labels',
    () async {
      final workspace = await createDemoWorkspace();
      addTearDown(workspace.dispose);
      final businessId = workspace.identity.businessId;
      final through = DateTime.utc(2100);
      final posted = (await workspace.expenses())
          .where((expense) => expense.isPosted)
          .toList();
      expect(posted.length, greaterThan(1));

      final recent = workspace.database.readRecentPostedExpenseIntakes(
        businessId: businessId,
        through: through,
        limit: 2,
      );
      expect(recent, hasLength(2));
      expect(
        recent.map((expense) => expense.id),
        posted.take(2).map((e) => e.id),
      );
      expect(
        workspace.database.readRecentPostedExpenseIntakes(
          businessId: EntityId.random(),
          through: through,
        ),
        isEmpty,
      );

      final labels = workspace.database.expenseSourceLabelsForJournals(
        businessId: businessId,
        journalIds: posted.map((expense) => expense.journalId!),
      );
      for (final expense in posted) {
        expect(labels[expense.journalId!.value]?.payee, expense.payee);
        expect(labels[expense.journalId!.value]?.category, expense.category);
      }
      expect(
        workspace.database.expenseSourceLabelsForJournals(
          businessId: EntityId.random(),
          journalIds: posted.map((expense) => expense.journalId!),
        ),
        isEmpty,
      );
    },
  );
}
