import '../../accounting/domain/company_tax_rate.dart';
import '../../sales/domain/invoice_tax.dart';

/// New Bill rates come from company Tax Settings. A historical unlinked rate
/// may survive only on its original line; it never becomes a new menu choice.
CompanyTaxRate? resolveBillTaxSelection(
  String choice, {
  required List<CompanyTaxRate> codes,
  required DateTime date,
  String? originalChoice,
  CompanyTaxRate? saved,
}) {
  if (choice.isEmpty) {
    throw const FormatException('Select tax for each bill line.');
  }
  if (choice.contains(':')) {
    return resolveTaxChoice(
      choice,
      codes: codes,
      date: date,
      purpose: TaxApplication.purchases,
      saved: saved,
    );
  }
  final rate = InvoiceTaxRate.fromPercent(choice);
  if (rate.units == 0) return null;
  if (saved == null && originalChoice == choice) return null;
  throw const FormatException(
    'Select a configured tax or No Tax for each bill line.',
  );
}
