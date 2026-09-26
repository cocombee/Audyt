<?php
declare(strict_types=1);

// Fictional, disposable MariaDB only. Never point this at cPanel or a live database.
require __DIR__.'/../vendor/autoload.php';
use Audyt\MembershipRepository;

$configPath = $argv[1] ?? '';
$config = json_decode(file_get_contents($configPath), true, 16, JSON_THROW_ON_ERROR);
if (!preg_match('/^mysql:host=127\.0\.0\.1;port=\d+;dbname=audyt_test_[a-f0-9]{12};charset=utf8mb4$/D', $config['dsn'] ?? '')) {
    throw new RuntimeException('Disposable loopback test database required');
}
function connection(bool $admin = false): PDO {
    global $config;
    return new PDO($config['dsn'], $admin ? 'root' : 'audyt_test_runtime',
        $admin ? $config['rootPassword'] : $config['runtimePassword'],
        [PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION, PDO::ATTR_EMULATE_PREPARES=>false]);
}
function uuid(): string {
    $h=bin2hex(random_bytes(16));
    return substr($h,0,8).'-'.substr($h,8,4).'-4'.substr($h,13,3).'-8'.substr($h,17,3).'-'.substr($h,20);
}
// Independent PHP processes use independent database transactions for races.
if (($argv[2] ?? '') === 'worker') {
    $job=json_decode(file_get_contents($argv[3]),true,16,JSON_THROW_ON_ERROR);
    $repository=new MembershipRepository(connection());
    while (!file_exists($job['gate'])) usleep(1000);
    try {
        $repository->command($job['business'],$job['actor'],$job['request'],[$job['target']=>$job['revision']],$job['action'],$job['role']);
        echo 'ok';
    } catch (DomainException $error) { echo $error->getMessage(); }
    exit;
}
$admin=connection(true);
if ((int)$admin->query('SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=DATABASE()')->fetchColumn() !== 0) {
    throw new RuntimeException('Refusing to modify a nonempty database');
}
$admin->exec(file_get_contents(__DIR__.'/../migrations/001_membership.sql'));
$db=connection();
$repository=new MembershipRepository($db);
$count=0;
function check(bool $value, string $label): void {
    global $count;
    if (!$value) throw new RuntimeException($label);
    $count++;
}
function denied(callable $operation, string $expected): void {
    try { $operation(); } catch (DomainException $error) {
        check($error->getMessage()===$expected,'Unexpected denial: '.$error->getMessage()); return;
    }
    throw new RuntimeException('Expected denial: '.$expected);
}
function sql(string $query, array $values=[]): mixed {
    global $admin;
    $s=$admin->prepare($query); $s->execute($values); return $s;
}
function registerUser(string $business, string $subject, string $email, string $name='Fictional User', string $role='director'): array {
    global $repository;
    return $repository->register($business,['googleSubject'=>$subject,'verifiedEmail'=>$email],uuid(),['name'=>$name,'email'=>$email,'requestedRole'=>$role]);
}
$business=uuid(); $other=uuid();
sql('INSERT INTO audyt_businesses (id,name) VALUES (?,?),(?,?)',[$business,'Fictional Test Business',$other,'Other Fictional Business']);
sql('INSERT INTO audyt_owner_bootstrap (business_id,expected_verified_email) VALUES (?,?)',[$business,'owner@example.test']);
$request=uuid();
$profile=['name'=>'Fictional Owner','email'=>'contact@example.test','requestedRole'=>'employee'];
$owner=$repository->register($business,['googleSubject'=>'owner-subject','verifiedEmail'=>'OWNER@example.test'],$request,$profile);
$ownerId=$owner['identityId'];
check($owner['membership']['status']==='approved' && $owner['membership']['role']==='director','Verified owner binding');
check(sql('SELECT bound_identity_id FROM audyt_owner_bootstrap WHERE business_id=?',[$business])->fetchColumn()===$ownerId,'Durable master binding');
check($repository->selfMembership($business,'owner-subject')['masterDirectorId']===$ownerId,'Verified self reports Master binding');
check($repository->register($business,['googleSubject'=>'owner-subject','verifiedEmail'=>'OWNER@example.test'],$request,$profile)===$owner,'Exact registration retry');
check((int)sql('SELECT COUNT(*) FROM audyt_access_events WHERE action="bootstrap"')->fetchColumn()===1,'Retry has no duplicate event');
denied(fn()=>$repository->register($business,['googleSubject'=>'owner-subject','verifiedEmail'=>'OWNER@example.test'],$request,array_replace($profile,['name'=>'Changed'])),'request_id_reused');
$spoof=$repository->register($business,['googleSubject'=>'spoof-subject','verifiedEmail'=>'someone@example.test'],uuid(),['name'=>'Fictional Spoof','email'=>'owner@example.test','requestedRole'=>'director']);
check($spoof['membership']['status']==='pending' && $spoof['membership']['role']===null,'Contact email and requested role cannot bootstrap');
$foreign=registerUser($other,'foreign-subject','foreign@example.test');
denied(fn()=>$repository->directory($business,$foreign['identityId']),'director_required');
denied(fn()=>$repository->command($business,$ownerId,uuid(),[$foreign['identityId']=>0],'approve','employee'),'member_not_found');
$members=[];
for($i=0;$i<12;$i++) $members[]=registerUser($business,'fictional-'.$i,'fictional-'.$i.'@example.test',$i===0?'Literal 50%_! User':'Fictional '.$i);
$page=$repository->directory($business,$ownerId);
check($page['total']===14 && $page['pendingCount']===13 && count($page['users'])===10,'Server counts and bounded page');
check(count($repository->directory($business,$ownerId,10)['users'])===4,'Second page');
check($repository->directory($business,$ownerId,0,10,'%_!')['matched']===1,'Search wildcard escaping');
check($repository->directory($business,$ownerId,0,10,"' OR 1=1 --")['matched']===0,'SQL injection remains literal search');
$notifications=$repository->notifications($business,$ownerId);
check(count($notifications['events'])===13,'Director registration events');
check($repository->notifications($business,$ownerId,$notifications['nextCursor'])['events']===[],'Notification cursor');
$accountant=$members[0]['identityId']; $employee=$members[1]['identityId']; $director=$members[2]['identityId'];
$approve=uuid();
$receipt=$repository->command($business,$ownerId,$approve,[$accountant=>0],'approve','accountant');
check($receipt===$repository->command($business,$ownerId,$approve,[$accountant=>0],'approve','accountant'),'Exact command retry');
check((int)sql('SELECT COUNT(*) FROM audyt_access_events WHERE request_id=?',[$approve])->fetchColumn()===1,'Command retry no duplicate audit');
denied(fn()=>$repository->command($business,$ownerId,$approve,[$accountant=>0],'approve','employee'),'request_id_reused');
check($repository->selfMembership($business,'fictional-0')['masterDirectorId']===null,'Accountant self omits Master capability context');
denied(fn()=>$repository->directory($business,$accountant),'director_required');
denied(fn()=>$repository->notifications($business,$accountant),'director_required');
denied(fn()=>$repository->command($business,$accountant,uuid(),[$employee=>0],'approve','employee'),'director_required');
$before=sql('SELECT revision FROM audyt_businesses WHERE id=?',[$business])->fetchColumn();
$failed=uuid();
denied(fn()=>$repository->command($business,$ownerId,$failed,[$employee=>0,$accountant=>1],'approve','employee'),'pending_required');
check($repository->selfMembership($business,'fictional-1')['status']==='pending','Mixed batch rollback');
check(sql('SELECT revision FROM audyt_businesses WHERE id=?',[$business])->fetchColumn()===$before,'Failed batch business revision unchanged');
check((int)sql('SELECT COUNT(*) FROM audyt_commands WHERE request_id=?',[$failed])->fetchColumn()===0,'Failed batch no receipt');
$repository->command($business,$ownerId,uuid(),[$employee=>0],'approve','employee');
$repository->command($business,$ownerId,uuid(),[$director=>0],'approve','director');
denied(fn()=>$repository->command($business,$director,uuid(),[$ownerId=>0],'revoke'),'master_director_required');
denied(fn()=>$repository->command($business,$director,uuid(),[$ownerId=>0],'changeRole','employee'),'master_director_required');
$appointed=$repository->command($business,$director,uuid(),[$employee=>1],'changeRole','director');
check($appointed['memberships'][$employee]['role']==='director','Director appoints Director');
denied(fn()=>$repository->command($business,$director,uuid(),[$employee=>2],'revoke'),'master_director_required');
$ownCommand=uuid();
$repository->command($business,$director,$ownCommand,[$members[3]['identityId']=>0],'reject');
$repository->command($business,$ownerId,uuid(),[$director=>1],'revoke');
denied(fn()=>$repository->command($business,$director,$ownCommand,[$members[3]['identityId']=>0],'reject'),'director_required');
check($repository->selfMembership($business,'fictional-2')['status']==='revoked','Durable revocation');
check(registerUser($business,'fictional-2','fictional-2@example.test')['membership']['status']==='revoked','Registration cannot restore revoked access');
check(registerUser($business,'fictional-3','fictional-3@example.test')['membership']['status']==='rejected','Registration cannot restore rejected access');
check($repository->directory($business,$ownerId)['total']===13,'Revoked users excluded from directory');
// Runtime privileges match the hosting user: no schema changes or hard deletes.
foreach(['DELETE FROM audyt_memberships','ALTER TABLE audyt_memberships ADD hacked INT'] as $statement) {
    try {$db->exec($statement); throw new RuntimeException('Restricted operation succeeded');}
    catch(PDOException $error) { check($error->getCode()==='42000','Runtime database privilege denied'); }
}
// Two commands race against one revision: exactly one commits and one conflicts.
$gate=sys_get_temp_dir().'/audyt-gate-'.bin2hex(random_bytes(8));
$jobs=[]; $processes=[];
foreach(['approve','reject'] as $action) {
    $path=$gate.'-'.$action.'.json';
    file_put_contents($path,json_encode(['gate'=>$gate,'business'=>$business,'actor'=>$ownerId,'request'=>uuid(),'target'=>$members[4]['identityId'],'revision'=>0,'action'=>$action,'role'=>$action==='approve'?'employee':null],JSON_THROW_ON_ERROR)); chmod($path,0600);
    $pipes=[]; $process=proc_open([PHP_BINARY,__FILE__,$configPath,'worker',$path],[0=>['pipe','r'],1=>['pipe','w'],2=>['pipe','w']],$pipes);
    if(!is_resource($process)) throw new RuntimeException('Worker startup failed');
    fclose($pipes[0]); $jobs[]=$path; $processes[]=[$process,$pipes];
}
touch($gate); $out=[];
foreach($processes as [$process,$pipes]) {
    $out[]=stream_get_contents($pipes[1]); $error=stream_get_contents($pipes[2]); fclose($pipes[1]); fclose($pipes[2]);
    check(proc_close($process)===0 && $error==='','Race worker succeeded');
}
foreach($jobs as $path) unlink($path); unlink($gate);
sort($out); check($out===['ok','stale_revision'],'Concurrent stale commands serialize');
check((int)sql('SELECT COUNT(*) FROM audyt_access_events WHERE target_id=? AND action IN ("approve","reject")',[$members[4]['identityId']])->fetchColumn()===1,'Race records one committed event');
check(!$db->inTransaction(),'No transaction leaked');
// Restore the encrypted snapshot into a second disposable empty schema.
$snapshot=Audyt\MembershipBackup::snapshot($db);
$key=base64_encode(random_bytes(32));
$archive=Audyt\MembershipBackup::seal($snapshot,$key);
$restoreName='audyt_test_'.bin2hex(random_bytes(6));
$admin->exec('CREATE DATABASE '.$restoreName.' CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci');
$restoreDsn=preg_replace('/dbname=audyt_test_[a-f0-9]{12}/','dbname='.$restoreName,$config['dsn']);
$restore=new PDO($restoreDsn,'root',$config['rootPassword'],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_EMULATE_PREPARES=>false]);
$restore->exec(file_get_contents(__DIR__.'/../migrations/001_membership.sql'));
Audyt\MembershipBackup::restoreEmpty($restore,Audyt\MembershipBackup::open($archive,$key));
check(Audyt\MembershipBackup::snapshot($restore)['tables']===$snapshot['tables'],'Every backed-up row restores exactly');
$restoredRepository=new MembershipRepository($restore);
check($restoredRepository->selfMembership($business,'owner-subject')['role']==='director','Master authority survives restore');
check($restoredRepository->selfMembership($business,'fictional-2')['status']==='revoked','Revocation survives restore');
check($restoredRepository->command($business,$ownerId,$approve,[$accountant=>0],'approve','accountant')===$receipt,'Retry receipt survives restore');
try { Audyt\MembershipBackup::restoreEmpty($restore,$snapshot); throw new RuntimeException('Overwrite allowed'); }
catch(RuntimeException $error) { check($error->getMessage()==='restore_requires_empty_database','Existing restore data protected'); }
check(Audyt\MembershipBackup::snapshot($restore)['tables']===$snapshot['tables'],'Refused overwrite changes no data');
check(!$restore->inTransaction(),'Restore transaction closed');
$failureName='audyt_test_'.bin2hex(random_bytes(6));
$admin->exec('CREATE DATABASE '.$failureName.' CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci');
$failureDsn=preg_replace('/dbname=audyt_test_[a-f0-9]{12}/','dbname='.$failureName,$config['dsn']);
$failureDb=new PDO($failureDsn,'root',$config['rootPassword'],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_EMULATE_PREPARES=>false]);
$failureDb->exec(file_get_contents(__DIR__.'/../migrations/001_membership.sql'));
$corrupt=$snapshot; $corrupt['tables']['audyt_memberships'][0]['identity_id']=uuid();
try { Audyt\MembershipBackup::restoreEmpty($failureDb,$corrupt); throw new RuntimeException('Invalid foreign reference restored'); }
catch(PDOException $error) { check($error->getCode()==='23000','Restore enforces relational constraints'); }
$afterFailure=Audyt\MembershipBackup::snapshot($failureDb);
check(array_sum(array_map('count',$afterFailure['tables']))===0,'Failed restore rolls back every table');
check(!$failureDb->inTransaction(),'Failed restore closes transaction');
echo "$count MariaDB integration checks passed\n";
