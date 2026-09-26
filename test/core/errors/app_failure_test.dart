import 'package:audyt/core/errors/app_failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps failure category, code, and retryability explicit', () {
    const failure = ConflictFailure(
      code: 'revision_conflict',
      message: 'The record changed elsewhere.',
      retryable: true,
    );

    expect(failure.category, FailureCategory.conflict);
    expect(failure.code, 'revision_conflict');
    expect(failure.message, 'The record changed elsewhere.');
    expect(failure.retryable, isTrue);
  });
}
