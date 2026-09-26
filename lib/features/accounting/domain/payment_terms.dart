enum PaymentTermKind { daysAfterIssue, dayOfMonth, custom }

/// Contractual due-date calculation. This is not a statutory deadline rule.
final class PaymentTerms {
  factory PaymentTerms.netDays(int days, {String? customText}) =>
      PaymentTerms.daysAfterIssue(days, customText: customText);

  int? get dueInDays => days;
  String get label => switch (kind) {
    PaymentTermKind.daysAfterIssue => 'Net $days',
    PaymentTermKind.dayOfMonth => 'Day $dayOfMonth Each Month',
    PaymentTermKind.custom => customText!,
  };
  String get formChoice => switch (kind) {
    PaymentTermKind.daysAfterIssue => 'Days After Issue',
    PaymentTermKind.dayOfMonth => 'Day Of Month',
    PaymentTermKind.custom => 'Custom',
  };

  DateTime dueDateFor(DateTime issueDate) => dueOn(issueDate);

  PaymentTerms.daysAfterIssue(int days, {String? customText})
    : kind = PaymentTermKind.daysAfterIssue,
      days = days,
      dayOfMonth = null,
      customText = _retainedText(customText),
      rolloverWithinDays = 0 {
    if (days < 0) throw ArgumentError.value(days, 'days');
  }

  PaymentTerms.dayOfMonth(
    int day, {
    this.rolloverWithinDays = 0,
    String? customText,
  }) : kind = PaymentTermKind.dayOfMonth,
       days = null,
       dayOfMonth = day,
       customText = _retainedText(customText) {
    if (day < 1 || day > 31) throw RangeError.range(day, 1, 31);
    if (rolloverWithinDays < 0 || rolloverWithinDays > 31) {
      throw RangeError.range(rolloverWithinDays, 0, 31);
    }
  }

  PaymentTerms.custom(String text)
    : kind = PaymentTermKind.custom,
      days = null,
      dayOfMonth = null,
      rolloverWithinDays = 0,
      customText = text.trim() {
    if (customText!.isEmpty) {
      throw const FormatException('Enter custom payment terms.');
    }
  }

  static String? _retainedText(String? text) =>
      text == null || text.trim().isEmpty ? null : text.trim();

  /// Retain the inactive Custom editor when saving a standard selection.
  /// This text never participates in standard labels or due-date calculation.
  PaymentTerms retainingCustomText(String? text) => switch (kind) {
    PaymentTermKind.custom => this,
    PaymentTermKind.daysAfterIssue => PaymentTerms.netDays(
      days!,
      customText: text,
    ),
    PaymentTermKind.dayOfMonth => PaymentTerms.dayOfMonth(
      dayOfMonth!,
      rolloverWithinDays: rolloverWithinDays,
      customText: text,
    ),
  };

  Map<String, Object?> toJson() => {
    'version': 1,
    'kind': kind.name,
    if (kind == PaymentTermKind.custom) 'text': customText,
    if (kind != PaymentTermKind.custom && customText != null)
      'customText': customText,
    if (kind == PaymentTermKind.daysAfterIssue) 'days': days,
    if (kind == PaymentTermKind.dayOfMonth) ...{
      'dayOfMonth': dayOfMonth,
      'rolloverWithinDays': rolloverWithinDays,
    },
  };

  factory PaymentTerms.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unsupported payment terms version.');
    }
    if (json.containsKey('customText') && json['customText'] is! String) {
      throw const FormatException('Invalid retained custom payment terms.');
    }
    switch (json['kind']) {
      case 'custom':
        if (json['text'] is! String ||
            json.containsKey('days') ||
            json.containsKey('dayOfMonth') ||
            json.containsKey('rolloverWithinDays')) {
          throw const FormatException('Invalid custom payment terms.');
        }
        return PaymentTerms.custom(json['text'] as String);
      case 'daysAfterIssue':
        if (json['days'] is! int ||
            json['days'] < 0 ||
            json.containsKey('dayOfMonth') ||
            json.containsKey('rolloverWithinDays')) {
          throw const FormatException('Invalid net-day payment terms.');
        }
        return PaymentTerms.daysAfterIssue(
          json['days'] as int,
          customText: json['customText'] as String?,
        );
      case 'dayOfMonth':
        final day = json['dayOfMonth'];
        final cutoff = json['rolloverWithinDays'];
        if (day is! int ||
            day < 1 ||
            day > 31 ||
            cutoff is! int ||
            cutoff < 0 ||
            cutoff > 31 ||
            json.containsKey('days')) {
          throw const FormatException('Invalid monthly payment terms.');
        }
        return PaymentTerms.dayOfMonth(
          day,
          rolloverWithinDays: cutoff,
          customText: json['customText'] as String?,
        );
      default:
        throw const FormatException('Unknown payment terms kind.');
    }
  }

  final PaymentTermKind kind;
  final int? days;
  final int? dayOfMonth;
  final int rolloverWithinDays;
  final String? customText;

  /// Returns a date-only UTC representation, preserving the supplied business
  /// calendar date rather than converting the device's instant to UTC.
  DateTime dueOn(DateTime issuedOn) {
    if (kind == PaymentTermKind.custom) {
      throw const FormatException(
        'Enter an explicit due date for custom payment terms.',
      );
    }
    final issue = DateTime.utc(issuedOn.year, issuedOn.month, issuedOn.day);
    if (kind == PaymentTermKind.daysAfterIssue) {
      return issue.add(Duration(days: days!));
    }
    DateTime inMonth(int month) {
      final last = DateTime.utc(issue.year, month + 1, 0);
      final day = dayOfMonth! > last.day ? last.day : dayOfMonth!;
      return DateTime.utc(last.year, last.month, day);
    }

    final candidate = inMonth(issue.month);
    final remaining = candidate.difference(issue).inDays;
    if (remaining < 0 ||
        (rolloverWithinDays > 0 && remaining <= rolloverWithinDays)) {
      return inMonth(issue.month + 1);
    }
    return candidate;
  }
}
