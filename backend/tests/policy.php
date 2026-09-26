<?php
declare(strict_types=1);
require __DIR__ . '/../src/MembershipPolicy.php';
use Audyt\MembershipPolicy;
function member(string $status, ?string $role, string $business = 'business'): array {
    return ['businessId' => $business, 'status' => $status, 'role' => $role, 'revision' => 0];
}
$members = ['owner' => member('approved', 'director'), 'accountant' => member('approved', 'accountant'),
    'one' => member('pending', null), 'two' => member('pending', null), 'foreign' => member('pending', null, 'other')];
$count = 0;
function denied(callable $action, string $expected): void {
    global $count;
    try { $action(); } catch (DomainException $e) {
        if ($e->getMessage() !== $expected) throw $e;
        $count++; return;
    }
    throw new RuntimeException('Expected denial: ' . $expected);
}
denied(fn() => MembershipPolicy::decide('business', 'accountant', $members, ['one'=>0], 'approve', 'employee'), 'director_required');
denied(fn() => MembershipPolicy::decide('other', 'owner', $members, ['one'=>0], 'approve', 'employee'), 'director_required');
denied(fn() => MembershipPolicy::decide('business', 'owner', $members, ['foreign'=>0], 'approve', 'employee'), 'member_not_found');
denied(fn() => MembershipPolicy::decide('business', 'owner', $members, ['one'=>1], 'approve', 'employee'), 'stale_revision');
denied(fn() => MembershipPolicy::decide('business', 'owner', $members, ['one'=>0,'accountant'=>0], 'approve', 'employee'), 'pending_required');
denied(fn() => MembershipPolicy::decide('business', 'owner', $members, ['owner'=>0], 'revoke'), 'self_access_change');
denied(fn() => MembershipPolicy::decide('business', 'owner', $members, ['owner'=>0], 'changeRole', 'employee'), 'self_access_change');
denied(fn() => MembershipPolicy::decide('business', 'owner', $members, ['one'=>0], 'approve', 'admin'), 'invalid_role');
$changes = MembershipPolicy::decide('business', 'owner', $members, ['one'=>0,'two'=>0], 'approve', 'employee');
if (count($changes) !== 2 || $changes['one']['revision'] !== 1 || $changes['two']['status'] !== 'approved'
    || $members['one']['status'] !== 'pending') throw new RuntimeException('Batch transition or immutability failed');
$count++;
$removed = MembershipPolicy::decide('business', 'owner', $members, ['accountant'=>0,'one'=>0], 'revoke');
if ($removed['accountant']['status'] !== 'revoked' || $removed['one']['role'] !== null) throw new RuntimeException('Revocation failed');
$count++;
$members['director'] = member('approved','director');
$members['employee'] = member('approved','employee');
foreach (['employee','accountant'] as $actor) {
    foreach (['approve','changeRole'] as $action) {
        denied(fn() => MembershipPolicy::decide('business',$actor,$members,['one'=>0],$action,'director','owner'), 'director_required');
    }
}

denied(fn() => MembershipPolicy::decide('business','director',$members,['owner'=>0],'revoke',null,'owner'), 'master_director_required');
denied(fn() => MembershipPolicy::decide('business','director',$members,['owner'=>0],'changeRole','employee','owner'), 'master_director_required');
denied(fn() => MembershipPolicy::decide('business','accountant',$members,['employee'=>0],'revoke',null,'owner'), 'director_required');
$removed = MembershipPolicy::decide('business','owner',$members,['director'=>0],'revoke',null,'owner');
if ($removed['director']['status'] !== 'revoked') throw new RuntimeException('Master cannot remove Director');
$count++;
$appointed = MembershipPolicy::decide('business','director',$members,['employee'=>0],'changeRole','director','owner');
if ($appointed['employee']['role'] !== 'director') throw new RuntimeException('Director cannot appoint Director');
$count++;
echo "$count policy checks passed\n";
