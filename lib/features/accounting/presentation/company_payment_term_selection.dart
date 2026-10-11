import '../domain/company_payment_term.dart';

const _companyPaymentTermPrefix = '__company_payment_term__:';

/// A transient selector value; documents persist the rule, never this ID.
String companyPaymentTermChoice(CompanyPaymentTerm template) =>
    '$_companyPaymentTermPrefix${template.id.value}';

bool isCompanyPaymentTermChoice(String choice) =>
    choice.startsWith(_companyPaymentTermPrefix);

/// Keeps saved names readable while distinguishing all active names and built-ins.
Map<String, String> companyPaymentTermChoiceLabels(
  List<CompanyPaymentTerm> templates, {
  required Iterable<String> reservedChoices,
}) {
  final active = templates.where((template) => template.active).toList();
  final reserved = {
    for (final choice in reservedChoices) choice.toLowerCase(),
    for (final template in active) template.name.toLowerCase(),
  };
  final assigned = {for (final choice in reservedChoices) choice.toLowerCase()};
  final labels = <String, String>{};
  for (final template in active) {
    var label = template.name;
    if (assigned.contains(label.toLowerCase())) {
      final base = '${template.name} · Saved Term';
      label = base;
      var suffix = 2;
      while (reserved.contains(label.toLowerCase()) ||
          assigned.contains(label.toLowerCase())) {
        label = '$base $suffix';
        suffix++;
      }
    }
    assigned.add(label.toLowerCase());
    labels[companyPaymentTermChoice(template)] = label;
  }
  return labels;
}
