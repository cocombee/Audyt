enum FailureCategory { validation, adapter, conflict, authorization }

abstract base class AppFailure implements Exception {
  const AppFailure({
    required this.category,
    required this.code,
    required this.message,
    required this.retryable,
  });

  final FailureCategory category;
  final String code;
  final String message;
  final bool retryable;

  @override
  String toString() => '$category [$code]: $message';
}

final class ValidationFailure extends AppFailure {
  const ValidationFailure({
    required super.code,
    required super.message,
    super.retryable = false,
  }) : super(category: FailureCategory.validation);
}

final class AdapterFailure extends AppFailure {
  const AdapterFailure({
    required super.code,
    required super.message,
    super.retryable = true,
  }) : super(category: FailureCategory.adapter);
}

final class ConflictFailure extends AppFailure {
  const ConflictFailure({
    required super.code,
    required super.message,
    super.retryable = false,
  }) : super(category: FailureCategory.conflict);
}

final class AuthorizationFailure extends AppFailure {
  const AuthorizationFailure({
    required super.code,
    required super.message,
    super.retryable = false,
  }) : super(category: FailureCategory.authorization);
}
