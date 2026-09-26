import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/currency.dart';
import 'package:audyt/core/storage/record_metadata.dart';
import 'package:audyt/features/accounting/domain/customer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('creates an immutable receivables customer master', () {
    final customerId = EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf101');
    final businessId = EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf102');
    final deviceId = EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf103');
    final incomeAccountId = EntityId.parse(
      '018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf104',
    );
    final taxAccountId = EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf105');
    final taxCodeId = EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf106');
    final auditEventId = EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf107');

    final customer = Customer.create(
      metadata: RecordMetadata.initial(
        recordId: customerId,
        businessId: businessId,
        originDeviceId: deviceId,
        createdAt: DateTime.utc(2026, 8, 30, 9),
      ),
      displayName: 'Acme Sdn Bhd',
      contact: const CustomerContact(
        contactName: 'Amina Rahman',
        email: 'accounts@acme.example',
        phone: '+60 3 1234 5678',
      ),
      billingAddress: const CustomerAddress(
        line1: '1 Jalan Akaun',
        city: 'Kuala Lumpur',
        stateOrProvince: 'WP Kuala Lumpur',
        postalCode: '50000',
        countryCode: 'MY',
      ),
      shippingAddress: const CustomerAddress(
        line1: '2 Jalan Hantar',
        city: 'Kuala Lumpur',
        postalCode: '50050',
        countryCode: 'MY',
      ),
      taxProfile: CustomerTaxProfile(
        taxIdentifier: 'MY-123',
        taxCodeId: taxCodeId,
      ),
      currency: Currency.parse('MYR'),
      paymentTerms: PaymentTerms.netDays(30),
      preferredDelivery: CustomerDeliveryMethod.email,
      defaultIncomeAccountId: incomeAccountId,
      defaultTaxAccountId: taxAccountId,
      statementSettings: const CustomerStatementSettings(
        includeAging: true,
        includeUnappliedAmounts: true,
      ),
      auditEventIds: [auditEventId],
    );

    expect(customer.id, customerId);
    expect(customer.displayName, 'Acme Sdn Bhd');
    expect(customer.contact.email, 'accounts@acme.example');
    expect(customer.billingAddress?.countryCode, 'MY');
    expect(customer.shippingAddress?.postalCode, '50050');
    expect(customer.taxProfile.taxCodeId, taxCodeId);
    expect(customer.currency, Currency.parse('MYR'));
    expect(customer.paymentTerms.dueInDays, 30);
    expect(customer.preferredDelivery, CustomerDeliveryMethod.email);
    expect(customer.defaultIncomeAccountId, incomeAccountId);
    expect(customer.defaultTaxAccountId, taxAccountId);
    expect(customer.isActive, isTrue);
    expect(customer.auditEventIds, [auditEventId]);
    expect(
      () => customer.auditEventIds.add(customerId),
      throwsUnsupportedError,
    );
  });

  test('revises customer status immutably with a new metadata revision', () {
    final customer = Customer.create(
      metadata: RecordMetadata.initial(
        recordId: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf111'),
        businessId: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf112'),
        originDeviceId: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf113'),
        createdAt: DateTime.utc(2026, 8, 30, 9),
      ),
      displayName: 'Beta Customer',
      contact: const CustomerContact(),
      taxProfile: const CustomerTaxProfile(),
      currency: Currency.parse('USD'),
      paymentTerms: PaymentTerms.netDays(0),
    );

    final inactive = customer.deactivate(
      updatedAt: DateTime.utc(2026, 8, 30, 10),
    );
    final active = inactive.activate(updatedAt: DateTime.utc(2026, 8, 30, 11));

    expect(customer.isActive, isTrue);
    expect(inactive.isActive, isFalse);
    expect(inactive.id, customer.id);
    expect(inactive.metadata.revision, 2);
    expect(inactive.metadata.updatedAt, DateTime.utc(2026, 8, 30, 10));
    expect(active.isActive, isTrue);
    expect(active.metadata.revision, 3);
    expect(active.metadata.updatedAt, DateTime.utc(2026, 8, 30, 11));
  });
}
