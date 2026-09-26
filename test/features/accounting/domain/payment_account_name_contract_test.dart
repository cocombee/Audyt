import 'package:audyt/features/accounting/domain/payment_account.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'capitalizes first ordinary lowercase letter after a non-letter prefix',
    () {
      expect(capitalizeAccountNameFirstLetter('  123 mYBank'), '  123 MYBank');
      expect(normalizeAccountName('  123 mYBank'), '123 MYBank');
      expect(normalizeAccountName('MYBank'), 'MYBank');
    },
  );
}
