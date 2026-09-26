<?php
declare(strict_types=1);

namespace Audyt;

/** Authorization and transitions only; the repository owns transaction locks. */
final class MembershipPolicy
{
    private const ROLES = ['director', 'accountant', 'employee'];

    /**
     * @param array<string,array<string,mixed>> $members authoritative business snapshot
     * @param array<string,int> $expectedRevisions selected target IDs and revisions
     * @return array<string,array<string,mixed>> changed memberships, not yet committed
     */
    public static function decide(
        string $businessId,
        string $actorId,
        array $members,
        array $expectedRevisions,
        string $action,
        ?string $role = null,
        ?string $masterDirectorId = null,
    ): array {
        $actor = $members[$actorId] ?? null;
        if (!$actor || $actor['businessId'] !== $businessId
            || $actor['status'] !== 'approved' || $actor['role'] !== 'director') {
            throw new \DomainException('director_required');
        }
        if (!in_array($action, ['approve', 'reject', 'changeRole', 'revoke'], true)) {
            throw new \DomainException('invalid_action');
        }
        if (count($expectedRevisions) < 1 || count($expectedRevisions) > 100) {
            throw new \DomainException('invalid_batch_size');
        }
        $needsRole = in_array($action, ['approve', 'changeRole'], true);
        if (($needsRole && !in_array($role, self::ROLES, true)) || (!$needsRole && $role !== null)) {
            throw new \DomainException('invalid_role');
        }
        $changes = [];
        foreach ($expectedRevisions as $id => $revision) {
            $target = $members[$id] ?? null;
            if (!$target || $target['businessId'] !== $businessId) {
                throw new \DomainException('member_not_found');
            }
            if (!is_int($revision) || $target['revision'] !== $revision) {
                throw new \DomainException('stale_revision');
            }
            if (in_array($action, ['approve', 'reject'], true) && $target['status'] !== 'pending') {
                throw new \DomainException('pending_required');
            }
            if ($action === 'changeRole' && $target['status'] !== 'approved') {
                throw new \DomainException('approved_required');
            }
            if ($target['status'] === 'revoked') {
                throw new \DomainException('already_revoked');
            }
            if ($id === $actorId && ($action === 'revoke' || ($action === 'changeRole' && $role !== 'director'))) {
                throw new \DomainException('self_access_change');
            }
            // Demotion cannot be used to bypass protection and then revoke access.
            if ($target['role'] === 'director'
                && ($action === 'revoke' || ($action === 'changeRole' && $role !== 'director'))
                && $actorId !== $masterDirectorId) {
                throw new \DomainException('master_director_required');
            }
            if ($id === $masterDirectorId
                && ($action === 'revoke' || ($action === 'changeRole' && $role !== 'director'))) {
                throw new \DomainException('master_director_protected');
            }
            $next = $target;
            $next['status'] = match ($action) {
                'approve', 'changeRole' => 'approved',
                'reject' => 'rejected',
                'revoke' => 'revoked',
            };
            $next['role'] = $needsRole ? $role : null;
            $next['revision']++;
            $changes[$id] = $next;
        }
        $after = array_replace($members, $changes);
        foreach ($after as $member) {
            if ($member['businessId'] === $businessId && $member['status'] === 'approved' && $member['role'] === 'director') {
                return $changes;
            }
        }
        throw new \DomainException('last_director');
    }
}
