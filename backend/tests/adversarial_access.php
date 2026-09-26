<?php
declare(strict_types=1);
require __DIR__.'/../vendor/autoload.php';
use Audyt\MembershipPolicy;
use Audyt\RegistrationInput;

$member = fn(string $role, string $status='approved', string $business='a'): array =>
    ['businessId'=>$business,'status'=>$status,'role'=>$role,'revision'=>0];
$base = ['master'=>$member('director'), 'director'=>$member('director'),
    'employee'=>$member('employee'), 'accountant'=>$member('accountant'),
    'pending'=>['businessId'=>'a','status'=>'pending','role'=>null,'revision'=>0],
    'foreign'=>$member('employee','approved','b')];
$count=0;
$deny = function(callable $attack) use (&$count): void {
    try { $attack(); } catch (DomainException $e) { $count++; return; }
    throw new RuntimeException('An unauthorized operation was accepted');
};
// A role string alone is insufficient: actor must be approved in this business.
foreach (['pending','rejected','revoked'] as $status) {
    foreach (['director','accountant','employee'] as $role) {
        $members = $base + ['attacker'=>$member($role,$status)];
        foreach (['approve','reject','changeRole','revoke'] as $action) {
            $target = in_array($action,['approve','reject'],true) ? 'pending' : 'employee';
            $nextRole = in_array($action,['approve','changeRole'],true) ? 'director' : null;
            $deny(fn()=>MembershipPolicy::decide('a','attacker',$members,[$target=>0],$action,$nextRole,'master'));
        }
    }
}
foreach (['employee','accountant'] as $actor) {
    foreach (['approve','reject','changeRole','revoke'] as $action) {
        $target = in_array($action,['approve','reject'],true) ? 'pending' : 'employee';
        $role = in_array($action,['approve','changeRole'],true) ? 'director' : null;
        $deny(fn()=>MembershipPolicy::decide('a',$actor,$base,[$target=>0],$action,$role,'master'));
    }
}
// Guessing a target ID from another company cannot move or delete its record.
$deny(fn()=>MembershipPolicy::decide('a','director',$base,['foreign'=>0],'revoke',null,'master'));
$deny(fn()=>MembershipPolicy::decide('b','director',$base,['foreign'=>0],'revoke',null,'master'));
$deny(fn()=>MembershipPolicy::decide('a','missing',$base,['employee'=>0],'revoke',null,'master'));
// A secondary Director cannot demote the owner first and delete them later.
foreach (['master','director'] as $target) {
    $members=$base+['attacker'=>$member('director')];
    $deny(fn()=>MembershipPolicy::decide('a','attacker',$members,[$target=>0],'revoke',null,'master'));
    $deny(fn()=>MembershipPolicy::decide('a','attacker',$members,[$target=>0],'changeRole','employee','master'));
}
// Mixed batches must fail as a whole, including valid employee + protected owner.
$deny(fn()=>MembershipPolicy::decide('a','director',$base,['employee'=>0,'master'=>0],'revoke',null,'master'));
$deny(fn()=>MembershipPolicy::decide('a','director',$base,['employee'=>1],'revoke',null,'master'));
$deny(fn()=>MembershipPolicy::decide('a','director',$base,['employee'=>0],'changeRole','masterDirector','master'));
// Mass assignment cannot inject provider identity, permission or approved state.
$profile=['name'=>'Applicant','email'=>'contact@example.test','requestedRole'=>'employee'];
foreach (['role'=>'director','status'=>'approved','masterDirectorId'=>'attacker',
    'googleSubject'=>'owner','verifiedEmail'=>'owner@example.test','businessId'=>'b'] as $field=>$value) {
    $deny(fn()=>RegistrationInput::profile($profile+[$field=>$value]));
}
echo "$count adversarial access checks passed; no live customer data used\n";
