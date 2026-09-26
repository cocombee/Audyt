/// The source of a posted statement movement. Credit notes are not receipts.
enum CustomerStatementActivity {
  invoice('Invoice'),
  payment('Payment'),
  credit('Credit');

  const CustomerStatementActivity(this.label);
  final String label;
}
