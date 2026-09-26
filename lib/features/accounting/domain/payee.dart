enum PayeeType { staff, director, supplier, vendor, smallProvider, other }

extension PayeeTypeLabel on PayeeType {
  /// Employee identities come from registration, never an accounting quick-add.
  bool get canQuickCreate => this != PayeeType.staff;

  String get label => switch (this) {
    PayeeType.staff => 'Employee',
    PayeeType.director => 'Director',
    PayeeType.supplier => 'Supplier',
    PayeeType.vendor => 'Vendor',
    PayeeType.smallProvider => 'Small Provider',
    PayeeType.other => 'Other',
  };
}

final class Payee {
  const Payee({required this.id, required this.name, required this.type});

  final String id;
  final String name;
  final PayeeType type;

  String get typeLabel => type.label;
}

final class PayeeCatalog {
  PayeeCatalog._();

  static const isDemo = true;

  static const demo = <Payee>[
    Payee(
      id: 'demo-payee-aina-rahman',
      name: 'Aina Rahman',
      type: PayeeType.staff,
    ),
    Payee(
      id: 'demo-payee-daniel-lim',
      name: 'Daniel Lim',
      type: PayeeType.director,
    ),
    Payee(
      id: 'demo-payee-acme-office-supplies',
      name: 'Acme Office Supplies',
      type: PayeeType.supplier,
    ),
    Payee(
      id: 'demo-payee-northwind-services',
      name: 'Northwind Services',
      type: PayeeType.vendor,
    ),
    Payee(
      id: 'demo-payee-kecil-studio',
      name: 'Kecil Studio',
      type: PayeeType.smallProvider,
    ),
  ];
}

/// Shared in-memory owner for payee mutations across accounting forms.
///
/// Pages may receive a store from the application shell so a payee created in
/// one form is immediately available to the next form without each editor
/// maintaining a private copy.
final class PayeeStore {
  PayeeStore({Iterable<Payee> payees = const <Payee>[], this.persist})
    : _payees = <Payee>[...payees];

  final List<Payee> _payees;

  /// Runs before local mutation; a failed durable write leaves the list unchanged.
  final void Function(Payee)? persist;

  List<Payee> get all => List<Payee>.unmodifiable(_payees);

  /// Refresh the existing shared cache after a separate atomic directory command.
  void reload(Iterable<Payee> saved) {
    final replacement = saved.toList();
    if (replacement.any((p) => p.id.trim().isEmpty || p.name.trim().isEmpty) ||
        replacement.map((p) => p.id).toSet().length != replacement.length) {
      throw StateError('Invalid saved payee directory.');
    }
    _payees
      ..clear()
      ..addAll(replacement);
  }

  Payee? byId(String id) {
    for (final payee in _payees) {
      if (payee.id == id) return payee;
    }
    return null;
  }

  Payee add({required String name, required PayeeType type, String? id}) {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'A payee name is required.');
    }
    final payee = Payee(
      id: id?.trim().isNotEmpty == true ? id!.trim() : _newId(),
      name: normalizedName,
      type: type,
    );
    return save(payee);
  }

  Payee save(Payee payee) {
    if (payee.id.trim().isEmpty) {
      throw ArgumentError.value(payee.id, 'id', 'A payee id is required.');
    }
    if (payee.name.trim().isEmpty) {
      throw ArgumentError.value(
        payee.name,
        'name',
        'A payee name is required.',
      );
    }
    persist?.call(payee);
    final index = _payees.indexWhere((item) => item.id == payee.id);
    if (index < 0) {
      _payees.add(payee);
    } else {
      _payees[index] = payee;
    }
    return payee;
  }

  String _newId() =>
      'payee-${DateTime.now().microsecondsSinceEpoch}-${_payees.length}';
}

List<Payee> filterPayees(Iterable<Payee> payees, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) {
    return List<Payee>.unmodifiable(payees);
  }
  return List<Payee>.unmodifiable(
    payees.where((payee) => payee.name.toLowerCase().contains(needle)),
  );
}
