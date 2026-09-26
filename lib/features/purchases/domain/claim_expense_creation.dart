import 'dart:convert';

import 'package:audyt/app/membership_service.dart';
import 'package:audyt/core/ids/entity_id.dart';

import '../../accounting/domain/expense_draft.dart';
import 'claim.dart';

enum ClaimCreationIntent { saveDraft, submitForReview }

/// A new Claim command, distinct from a membership read or a local Payee save.
/// The service must resolve the authenticated actor, recheck both memberships
/// and their revisions at commit, and acknowledge this request idempotently.
/// Original bytes need a durable service receipt before submission is accepted.
/// No production implementation is supplied by a registration lookup alone.
abstract class ClaimExpenseCreationGateway {
  String get businessId;
  Future<ServiceClaimantContext> claimants(String search);
  Future<void> execute(ClaimExpenseCreationCommand command);
}

class ClaimExpenseCreationCommand {
  ClaimExpenseCreationCommand({
    required this.requestId,
    required this.claimId,
    required this.intent,
    required ServiceClaimantContext context,
    required ServiceClaimant claimant,
    required RecordExpenseDraft draft,
  }) : businessId = context.businessId,
       expectedActor = context.actor,
       selectedClaimant = claimant,
       _draftJson = jsonEncode(draft.toJson()) {
    final current = [
      context.actor,
      ...context.claimants,
    ].where((choice) => choice.identityId == claimant.identityId);
    if (current.isEmpty ||
        current.any((choice) => !_sameIdentity(choice, claimant)) ||
        (!context.canChooseOnBehalf &&
            claimant.identityId != context.actor.identityId) ||
        draft.paymentAccount.isNotEmpty ||
        draft.paymentAccountId != null ||
        draft.claimSource != null ||
        draft.submissionId == null) {
      throw ArgumentError('Invalid new Claim command context.');
    }
  }

  final EntityId requestId, claimId;
  final ClaimCreationIntent intent;
  final String businessId;
  final ServiceClaimant expectedActor, selectedClaimant;
  final String _draftJson;
  RecordExpenseDraft get draft => RecordExpenseDraft.fromJson(
    jsonDecode(_draftJson) as Map<String, dynamic>,
  );

  /// Client validation only. This is not an authoritative receipt or posting.
  Claim get validationClaim => Claim.expense(
    id: claimId,
    draft: draft,
    claimantName: selectedClaimant.name,
    claimantIdentity: ClaimantIdentity(
      payeeId: selectedClaimant.identityId,
      type: selectedClaimant.role == 'director'
          ? ClaimantType.director
          : ClaimantType.staff,
    ),
  );
}

bool sameClaimActor(
  ServiceClaimantContext first,
  ServiceClaimantContext next,
) =>
    first.businessId == next.businessId &&
    _sameIdentity(first.actor, next.actor);

bool _sameIdentity(ServiceClaimant first, ServiceClaimant second) =>
    first.identityId == second.identityId &&
    first.revision == second.revision &&
    first.role == second.role &&
    first.name == second.name;
