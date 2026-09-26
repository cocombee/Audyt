<?php
declare(strict_types=1);
require __DIR__.'/../vendor/autoload.php';
use Audyt\MembershipBackup;
$count=0;
function check(bool $value,string $label): void { global $count; if(!$value) throw new RuntimeException($label); $count++; }
function denied(callable $operation,string $expected): void {
    try { $operation(); } catch(RuntimeException $error) { check($error->getMessage()===$expected,'Unexpected backup error'); return; }
    throw new RuntimeException('Expected '.$expected);
}
$snapshot=['kind'=>'audyt-membership','version'=>1,'createdAt'=>'2026-09-26T00:00:00+00:00','tables'=>[
    'audyt_businesses'=>[['id'=>'00000000-0000-4000-8000-000000000001','name'=>'Fictional Confidential Business','revision'=>0,'created_at'=>'2026-09-26 00:00:00.000000']],
    'audyt_identities'=>[], 'audyt_memberships'=>[], 'audyt_commands'=>[], 'audyt_access_events'=>[], 'audyt_owner_bootstrap'=>[],
]];
$key=base64_encode(random_bytes(32));
$one=MembershipBackup::seal($snapshot,$key); $two=MembershipBackup::seal($snapshot,$key);
check($one!==$two,'Random nonce for each backup');
check(!str_contains($one,'Fictional Confidential'),'No plaintext business data');
check(MembershipBackup::open($one,$key)===$snapshot,'Authenticated round trip');
denied(fn()=>MembershipBackup::open($one,base64_encode(random_bytes(32))),'backup_authentication_failed');
$prefix="AUDYT-MEMBERSHIP-1\n";
$bytes=base64_decode(substr($one,strlen($prefix)));
foreach([0,12,28,strlen($bytes)-1] as $position) {
    $tampered=$bytes; $tampered[$position]=chr(ord($tampered[$position])^1);
    denied(fn()=>MembershipBackup::open($prefix.base64_encode($tampered),$key),'backup_authentication_failed');
}
denied(fn()=>MembershipBackup::open('plain data',$key),'invalid_backup');
denied(fn()=>MembershipBackup::open($prefix.'%%%',$key),'invalid_backup');
denied(fn()=>MembershipBackup::seal($snapshot,''),'backup_key_required');
denied(fn()=>MembershipBackup::seal($snapshot,base64_encode(random_bytes(31))),'backup_key_required');
$bad=$snapshot; $bad['kind']='accounting-ledger';
denied(fn()=>MembershipBackup::seal($bad,$key),'invalid_backup');
$bad=$snapshot; $bad['tables']['customer_documents']=[];
denied(fn()=>MembershipBackup::seal($bad,$key),'invalid_backup');
$bad=$snapshot; $bad['tables']['audyt_businesses'][0]['databasePassword']='fictional';
denied(fn()=>MembershipBackup::seal($bad,$key),'invalid_backup');
$v2=$snapshot; $v2['version']=2;
$v2['tables'] += [
    'audyt_auth_guard'=>[['id'=>1]], 'audyt_auth_email_locks'=>[],
    'audyt_auth_accounts'=>[], 'audyt_auth_challenges'=>[],
    'audyt_auth_sessions'=>[], 'audyt_auth_limits'=>[],
    'audyt_auth_events'=>[], 'audyt_mail_outbox'=>[],
];
$sealedV2=MembershipBackup::seal($v2,$key);
check(str_starts_with($sealedV2,"AUDYT-MEMBERSHIP-2\n"),'Authentication archive is versioned');
check(MembershipBackup::open($sealedV2,$key)===$v2,'V2 authenticated round trip');
denied(fn()=>MembershipBackup::open(str_replace("AUDYT-MEMBERSHIP-2\n","AUDYT-MEMBERSHIP-1\n",$sealedV2),$key),'backup_authentication_failed');
denied(fn()=>MembershipBackup::open(str_replace("AUDYT-MEMBERSHIP-1\n","AUDYT-MEMBERSHIP-2\n",$one),$key),'backup_authentication_failed');
$bad=$v2; unset($bad['tables']['audyt_auth_sessions']);
denied(fn()=>MembershipBackup::seal($bad,$key),'invalid_backup');
$bad=$v2; $bad['tables']['audyt_auth_guard']=[];
denied(fn()=>MembershipBackup::seal($bad,$key),'invalid_backup');
$bad=$v2; $bad['tables']['audyt_auth_guard'][]=['id'=>2];
denied(fn()=>MembershipBackup::seal($bad,$key),'invalid_backup');
$bad=$v2; $bad['version']=3;
denied(fn()=>MembershipBackup::seal($bad,$key),'invalid_backup');
$directory=sys_get_temp_dir().'/audyt-backup-test-'.bin2hex(random_bytes(8)); mkdir($directory,0700);
try {
    $file=MembershipBackup::writeVerified($directory,$snapshot,$key);
    check(preg_match('/^audyt-membership-\d{8}-\d{6}-[a-f0-9]{16}\.audytbackup$/D',$file)===1,'Generated safe filename');
    check((fileperms($directory.'/'.$file)&0077)===0,'Owner-only backup');
    check(MembershipBackup::open(file_get_contents($directory.'/'.$file),$key)===$snapshot,'Stored backup verified');
    chmod($directory,0755); clearstatcache();
    denied(fn()=>MembershipBackup::writeVerified($directory,$snapshot,$key),'private_backup_directory_required');
    chmod($directory,0700); clearstatcache();
    symlink($directory,$directory.'-link');
    denied(fn()=>MembershipBackup::writeVerified($directory.'-link',$snapshot,$key),'private_backup_directory_required');
} finally {
    if(is_link($directory.'-link')) unlink($directory.'-link');
    foreach(new DirectoryIterator($directory) as $file) if($file->isFile()) unlink($file->getPathname());
    rmdir($directory);
}
echo "$count backup archive checks passed\n";
