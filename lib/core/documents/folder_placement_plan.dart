enum NamingSeparator { dot, dash }

enum NamingColumnKind {
  custom,
  field,
  day,
  monthNumber,
  monthName,
  year,
  yearShort,
  reference,
  separator,
}

final class NamingContext {
  NamingContext({
    required DateTime date,
    required Map<String, String> fields,
    required this.reference,
  }) : date = date.toUtc(),
       fields = Map.unmodifiable(fields);

  final DateTime date;
  final Map<String, String> fields;
  final String reference;
}

final class NamingColumn {
  const NamingColumn._({required this.kind, this.value, this.separatorValue});

  factory NamingColumn.custom(String value) {
    return NamingColumn._(kind: NamingColumnKind.custom, value: value);
  }

  factory NamingColumn.field(String fieldName) {
    return NamingColumn._(kind: NamingColumnKind.field, value: fieldName);
  }

  factory NamingColumn.day() =>
      const NamingColumn._(kind: NamingColumnKind.day);

  factory NamingColumn.monthNumber() {
    return const NamingColumn._(kind: NamingColumnKind.monthNumber);
  }

  factory NamingColumn.monthName() {
    return const NamingColumn._(kind: NamingColumnKind.monthName);
  }

  factory NamingColumn.year() =>
      const NamingColumn._(kind: NamingColumnKind.year);

  factory NamingColumn.yearShort() {
    return const NamingColumn._(kind: NamingColumnKind.yearShort);
  }

  factory NamingColumn.reference() {
    return const NamingColumn._(kind: NamingColumnKind.reference);
  }

  factory NamingColumn.separator(NamingSeparator separator) {
    return NamingColumn._(
      kind: NamingColumnKind.separator,
      separatorValue: separator,
    );
  }

  final NamingColumnKind kind;
  final String? value;
  final NamingSeparator? separatorValue;

  String resolve(NamingContext context) {
    switch (kind) {
      case NamingColumnKind.custom:
        return value!;
      case NamingColumnKind.field:
        return context.fields[value] ?? '';
      case NamingColumnKind.day:
        return _twoDigits(context.date.day);
      case NamingColumnKind.monthNumber:
        return _twoDigits(context.date.month);
      case NamingColumnKind.monthName:
        return _monthNames[context.date.month - 1];
      case NamingColumnKind.year:
        return context.date.year.toString();
      case NamingColumnKind.yearShort:
        return _twoDigits(context.date.year % 100);
      case NamingColumnKind.reference:
        return context.reference;
      case NamingColumnKind.separator:
        return separatorValue == NamingSeparator.dot ? '.' : '-';
    }
  }

  List<String> validationErrors(NamingContext context) {
    final errors = <String>[];
    final resolved = resolve(context);
    if (kind == NamingColumnKind.field && !context.fields.containsKey(value)) {
      errors.add('Naming field "$value" is missing.');
    }
    if (kind != NamingColumnKind.separator && resolved.isEmpty) {
      errors.add('Naming columns cannot render an empty value.');
    }
    if (kind != NamingColumnKind.separator &&
        resolved.contains(RegExp(r'[/\\]'))) {
      errors.add('Naming values cannot contain path separators.');
    }
    return errors;
  }

  static const _monthNames = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');
}

final class DocumentNamingPlan {
  DocumentNamingPlan(List<NamingColumn> columns)
    : columns = List.unmodifiable(columns);

  final List<NamingColumn> columns;

  List<String> validationErrors(NamingContext context) {
    final errors = <String>[];
    for (final column in columns) {
      errors.addAll(column.validationErrors(context));
    }
    if (columns.isEmpty) {
      errors.add('A naming plan requires at least one column.');
    }
    return List.unmodifiable(errors);
  }

  String render(NamingContext context) {
    final errors = validationErrors(context);
    if (errors.isNotEmpty) {
      throw FormatException(errors.join(' '));
    }
    return columns.map((column) => column.resolve(context)).join();
  }
}
