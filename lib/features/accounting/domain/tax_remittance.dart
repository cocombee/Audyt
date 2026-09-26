import '../../../core/documents/receipt_document.dart';
import '../../../core/dates/accounting_date.dart';
import '../../../core/ids/entity_id.dart';
import '../../../core/money/money.dart';
import 'company_tax_agency.dart';

enum TaxRemittanceOrigin { recorded, linked }

enum TaxRemittanceCorrectionKind { unlink, reversal }

/// Explicit attribution of an existing liability payment, not a tax return.
final class TaxRemittanceAllocation {
  TaxRemittanceAllocation({
    required this.agency,
    required this.liabilityAccountId,
    required DateTime periodFrom,
    required DateTime periodThrough,
    required this.amount,
  }) : periodFrom = accountingCalendarDate(periodFrom),
       periodThrough = accountingCalendarDate(periodThrough) {
    if (agency.revision < 1 ||
        !amount.isPositive ||
        this.periodFrom.isAfter(this.periodThrough)) {
      throw const FormatException(
        'Review a saved agency, tax period and positive allocation.',
      );
    }
  }
  final CompanyTaxAgency agency;
  final EntityId liabilityAccountId;
  final DateTime periodFrom, periodThrough;
  final Money amount;
  String get key =>
      '${agency.choice}/${liabilityAccountId.value}/${periodFrom.toIso8601String()}/${periodThrough.toIso8601String()}';
  Map<String, Object?> toJson() => {
    'agency': agency.toJson(),
    'account': liabilityAccountId.value,
    'from': periodFrom.toIso8601String(),
    'through': periodThrough.toIso8601String(),
    'amountMinor': amount.minorUnits,
    'currency': amount.currency,
  };
  factory TaxRemittanceAllocation.fromJson(Map<String, dynamic> j) =>
      TaxRemittanceAllocation(
        agency: CompanyTaxAgency.fromJson(
          Map<String, dynamic>.from(j['agency'] as Map),
        ),
        liabilityAccountId: EntityId.parse(j['account'] as String),
        periodFrom: DateTime.parse(j['from'] as String),
        periodThrough: DateTime.parse(j['through'] as String),
        amount: Money.fromMinor(
          j['amountMinor'] as int,
          j['currency'] as String,
        ),
      );
}

final class TaxRemittance {
  TaxRemittance({
    required this.id,
    required this.businessId,
    required this.actorId,
    required this.journalId,
    required this.journalRevision,
    required this.journalFingerprint,
    required this.origin,
    required this.bankAccountId,
    required this.paymentAccountId,
    required DateTime paidOn,
    required DateTime recordedAt,
    required String reference,
    required String memo,
    required Iterable<TaxRemittanceAllocation> allocations,
    Iterable<ReceiptAttachment> attachments = const [],
  }) : paidOn = accountingCalendarDate(paidOn),
       recordedAt = recordedAt.toUtc(),
       reference = reference.trim(),
       memo = memo.trim(),
       attachments = List.unmodifiable(
         attachments.map((a) => ReceiptAttachment.fromJson(a.toJson())).toList()
           ..sort((a, b) => a.originalId.compareTo(b.originalId)),
       ),
       allocations = List.unmodifiable(
         allocations.toList()..sort((a, b) => a.key.compareTo(b.key)),
       ) {
    final keys = this.allocations.map((a) => a.key).toSet();
    final currencies = this.allocations.map((a) => a.amount.currency).toSet();
    if (journalRevision < 1 ||
        journalFingerprint.isEmpty ||
        paymentAccountId.isEmpty ||
        this.reference.isEmpty ||
        this.reference.length > 120 ||
        this.memo.length > 2000 ||
        this.attachments.map((a) => a.originalId).toSet().length !=
            this.attachments.length ||
        this.attachments.any((a) => a.isGenerated) ||
        this.allocations.isEmpty ||
        keys.length != this.allocations.length ||
        currencies.length != 1 ||
        totalMinor > BigInt.from(0x7fffffffffffffff)) {
      throw const FormatException(
        'Review distinct tax allocations, currency and payment reference.',
      );
    }
  }
  final EntityId id, businessId, actorId, journalId, bankAccountId;
  final int journalRevision;
  final String journalFingerprint, paymentAccountId, reference, memo;
  final TaxRemittanceOrigin origin;
  final DateTime paidOn, recordedAt;
  final List<TaxRemittanceAllocation> allocations;
  final List<ReceiptAttachment> attachments;
  BigInt get totalMinor => allocations.fold(
    BigInt.zero,
    (v, a) => v + BigInt.from(a.amount.minorUnits),
  );
  Money get total =>
      Money.fromMinor(totalMinor.toInt(), allocations.first.amount.currency);
  Map<String, Object?> toJson() => {
    'version': 1,
    'id': id.value,
    'business': businessId.value,
    'actor': actorId.value,
    'journal': journalId.value,
    'journalRevision': journalRevision,
    'journalFingerprint': journalFingerprint,
    'origin': origin.name,
    'bank': bankAccountId.value,
    'paymentAccount': paymentAccountId,
    'paidOn': paidOn.toIso8601String(),
    'recordedAt': recordedAt.toIso8601String(),
    'reference': reference,
    'memo': memo,
    'allocations': allocations.map((a) => a.toJson()).toList(),
    'attachments': attachments.map((a) => a.toJson()).toList(),
  };
  factory TaxRemittance.fromJson(Map<String, dynamic> j) {
    if (j['version'] != 1) {
      throw const FormatException('Unsupported tax remittance version.');
    }
    return TaxRemittance(
      id: EntityId.parse(j['id'] as String),
      businessId: EntityId.parse(j['business'] as String),
      actorId: EntityId.parse(j['actor'] as String),
      journalId: EntityId.parse(j['journal'] as String),
      journalRevision: j['journalRevision'] as int,
      journalFingerprint: j['journalFingerprint'] as String,
      origin: TaxRemittanceOrigin.values.byName(j['origin'] as String),
      bankAccountId: EntityId.parse(j['bank'] as String),
      paymentAccountId: j['paymentAccount'] as String,
      paidOn: DateTime.parse(j['paidOn'] as String),
      recordedAt: DateTime.parse(j['recordedAt'] as String),
      reference: j['reference'] as String,
      memo: j['memo'] as String,
      attachments: (j['attachments'] as List).map(
        (a) => ReceiptAttachment.fromJson(Map<String, dynamic>.from(a as Map)),
      ),
      allocations: (j['allocations'] as List).map(
        (a) => TaxRemittanceAllocation.fromJson(
          Map<String, dynamic>.from(a as Map),
        ),
      ),
    );
  }
}

/// Unlink changes attribution only. Reversal is an exact correcting journal.
final class TaxRemittanceCorrection {
  TaxRemittanceCorrection({
    required this.id,
    required this.sourceId,
    required this.businessId,
    required this.actorId,
    required this.kind,
    required this.journalId,
    required DateTime on,
    required DateTime recordedAt,
    required String reason,
  }) : on = accountingCalendarDate(on),
       recordedAt = recordedAt.toUtc(),
       reason = reason.trim() {
    if (this.reason.isEmpty ||
        this.reason.length > 500 ||
        (kind == TaxRemittanceCorrectionKind.unlink) != (journalId == null)) {
      throw const FormatException(
        'Review a correction reason and matching correction kind.',
      );
    }
  }
  final EntityId id, sourceId, businessId, actorId;
  final EntityId? journalId;
  final TaxRemittanceCorrectionKind kind;
  final DateTime on, recordedAt;
  final String reason;
  Map<String, Object?> toJson() => {
    'version': 1,
    'id': id.value,
    'source': sourceId.value,
    'business': businessId.value,
    'actor': actorId.value,
    'kind': kind.name,
    'journal': journalId?.value,
    'on': on.toIso8601String(),
    'recordedAt': recordedAt.toIso8601String(),
    'reason': reason,
  };
  factory TaxRemittanceCorrection.fromJson(Map<String, dynamic> j) {
    if (j['version'] != 1) {
      throw const FormatException('Unsupported remittance correction version.');
    }
    return TaxRemittanceCorrection(
      id: EntityId.parse(j['id'] as String),
      sourceId: EntityId.parse(j['source'] as String),
      businessId: EntityId.parse(j['business'] as String),
      actorId: EntityId.parse(j['actor'] as String),
      kind: TaxRemittanceCorrectionKind.values.byName(j['kind'] as String),
      journalId: j['journal'] == null
          ? null
          : EntityId.parse(j['journal'] as String),
      on: DateTime.parse(j['on'] as String),
      recordedAt: DateTime.parse(j['recordedAt'] as String),
      reason: j['reason'] as String,
    );
  }
}
