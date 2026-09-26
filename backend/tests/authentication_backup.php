<?php
declare(strict_types=1);
// Fictional disposable loopback schemas only. No live mailbox or host access.
require __DIR__.'/../vendor/autoload.php';
use Audyt\{AuthenticationRepository,AuthenticationSecrets,MembershipRepository,MembershipBackup,SecurityMailOutbox,SecurityMailTransport};
$config=json_decode(file_get_contents($argv[1] ?? ''),true,16,JSON_THROW_ON_ERROR);
function fixtureDsn(string $dsn): void {
    if(!preg_match('/^mysql:host=127\.0\.0\.1;port=\d+;dbname=audyt_test_[a-f0-9]{12};charset=utf8mb4$/D',$dsn)) throw new RuntimeException('Disposable loopback schema required');
}
fixtureDsn($config['dsn']);
function connect(string $dsn,bool $admin=false): PDO {
    global $config;
    fixtureDsn($dsn);
    return new PDO($dsn,$admin ? 'root' : 'audyt_test_runtime',$admin ? $config['rootPassword'] : $config['runtimePassword'],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_EMULATE_PREPARES=>false]);
}
if(($argv[2] ?? '')==='worker') {
    $job=json_decode(file_get_contents($argv[3]),true,32,JSON_THROW_ON_ERROR);
    $deadline=microtime(true)+15;
    while(!file_exists($job['gate'])) { if(microtime(true)>$deadline) exit(2); usleep(1000); }
    try { MembershipBackup::restoreEmpty(connect($job['dsn']),MembershipBackup::open($job['archive'],$job['key'])); echo 'ok'; }
    catch(Throwable $error) { echo $error->getMessage()==='restore_requires_empty_database' ? 'already_restored' : 'worker_failed'; }
    exit;
}
$admin=connect($config['dsn'],true);
if((int)$admin->query('SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=DATABASE()')->fetchColumn()!==0) throw new RuntimeException('Refusing nonempty source test schema');
foreach(['001_membership.sql','002_authentication.sql'] as $file) $admin->exec(file_get_contents(__DIR__.'/../migrations/'.$file));
$db=connect($config['dsn']);
$count=0;
function check(bool $value,string $label): void { global $count; if(!$value) throw new RuntimeException($label); $count++; }
function denied(callable $operation,string $expected): void {
    try { $operation(); } catch(Throwable $error) { check($error->getMessage()===$expected,'Unexpected recovery error'); return; }
    throw new RuntimeException('Expected recovery refusal');
}
function query(PDO $db,string $sql,array $values=[]): PDOStatement { $s=$db->prepare($sql); $s->execute($values); return $s; }
function codeFor(PDO $db,AuthenticationSecrets $secrets,string $challenge): string {
    $sealed=query($db,"SELECT encrypted_payload FROM audyt_mail_outbox WHERE challenge_id=? AND state='queued'",[$challenge])->fetchColumn();
    $payload=$secrets->open($sealed);
    if(!preg_match('/\b([0-9]{6})\b/',$payload['text'],$match)) throw new RuntimeException('Fixture code unavailable');
    return $match[1];
}
function newSchema(bool $authentication=true): string {
    global $admin,$config;
    $name='audyt_test_'.bin2hex(random_bytes(6));
    $admin->exec('CREATE DATABASE '.$name.' CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci');
    $admin->exec("GRANT SELECT,INSERT,UPDATE ON $name.* TO 'audyt_test_runtime'@'%'");
    $dsn=preg_replace('/dbname=audyt_test_[a-f0-9]{12}/','dbname='.$name,$config['dsn']);
    $schema=connect($dsn,true);
    $schema->exec(file_get_contents(__DIR__.'/../migrations/001_membership.sql'));
    if($authentication) $schema->exec(file_get_contents(__DIR__.'/../migrations/002_authentication.sql'));
    return $dsn;
}
function indexed(array $rows,string $key): array { return array_column($rows,null,$key); }

$secrets=new AuthenticationSecrets(random_bytes(32),random_bytes(32));
$dummy=$secrets->password('Fictional recovery dummy password 12345');
$auth=new AuthenticationRepository($db,$secrets,$dummy,'fixture-v1');
$password='Fictional owner recovery passphrase 12345';
$register=$auth->register('Fictional Recovery Owner','owner@example.test','',$password,'fixture-v1')['challengeId'];
$owner=$auth->verify($register,codeFor($db,$secrets,$register));
$id=$owner['account']['id'];
$link=$auth->google(['googleSubject'=>'recovery-owner','verifiedEmail'=>'owner@example.test'],'');
$linked=$auth->verify($link['challengeId'],codeFor($db,$secrets,$link['challengeId']));
$auth->signOut($owner['token']);
$employee=$auth->google(['googleSubject'=>'recovery-employee','verifiedEmail'=>'employee@example.test','authoritativeEmail'=>true],'fixture-v1');
$business=AuthenticationRepository::uuid();
query($admin,'INSERT INTO audyt_businesses (id,name) VALUES (?,?)',[$business,'Fictional Recovery Company']);
query($admin,'INSERT INTO audyt_owner_bootstrap (business_id,expected_verified_email) VALUES (?,?)',[$business,'owner@example.test']);
$memberships=new MembershipRepository($db);
$memberships->register($business,['googleSubject'=>'recovery-owner','verifiedEmail'=>'owner@example.test'],AuthenticationRepository::uuid(),['name'=>'Fictional Owner','email'=>'owner@example.test','requestedRole'=>'director']);
$member=$memberships->register($business,['googleSubject'=>'recovery-employee','verifiedEmail'=>'employee@example.test'],AuthenticationRepository::uuid(),['name'=>'Fictional Employee','email'=>'employee@example.test','requestedRole'=>'employee']);
$approval=AuthenticationRepository::uuid();
$receipt=$memberships->command($business,$id,$approval,[$member['identityId']=>0],'approve','employee');
$memberships->command($business,$id,AuthenticationRepository::uuid(),[$member['identityId']=>1],'revoke',null);
$reset=$auth->forgotPassword('owner@example.test')['challengeId'];
$resetCode=codeFor($db,$secrets,$reset);
$pending=$auth->register('Fictional Pending','pending@example.test','','Fictional pending recovery passphrase 12345','fixture-v1')['challengeId'];
$pendingCode=codeFor($db,$secrets,$pending);
$transport=new class implements SecurityMailTransport {
    public int $sent=0;
    public function send(string $messageId,array $message): void { $this->sent++; }
};
(new SecurityMailOutbox($db,$secrets,$transport))->drain(1);
$before=MembershipBackup::snapshot($db);
check($before['version']===2 && count($before['tables'])===14,'All membership and authentication tables included');
foreach($before['tables'] as $table=>$rows) check(count($rows)>0,'Real fixture populates '.$table);
$key=base64_encode(random_bytes(32));
$archive=MembershipBackup::seal($before,$key);
check(!str_contains($archive,'example.test') && !str_contains($archive,$password) && !str_contains($archive,$linked['token']),'No readable account/password/session data in archive');
check(MembershipBackup::open($archive,$key)===$before,'Exact encrypted authentication snapshot');
$restoredDsn=newSchema();
$restored=connect($restoredDsn);
MembershipBackup::restoreEmpty($restored,MembershipBackup::open($archive,$key));
$after=MembershipBackup::snapshot($restored);
foreach($before['tables'] as $table=>$rows) {
    if(in_array($table,['audyt_auth_sessions','audyt_auth_challenges','audyt_auth_events','audyt_mail_outbox'],true)) continue;
    check($after['tables'][$table]===$rows,$table.' rows and links preserved exactly');
}
foreach(['audyt_auth_sessions'=>['token_digest','revoked_at'],'audyt_auth_challenges'=>['id','consumed_at']] as $table=>$fields) {
    [$primary,$timestamp]=$fields; $old=indexed($before['tables'][$table],$primary);
    foreach($after['tables'][$table] as $row) {
        check($row[$timestamp]!==null,'Restored security proof invalidated');
        if($old[$row[$primary]][$timestamp]===null) $row[$timestamp]=null;
        check($row===$old[$row[$primary]],'Only unused proof invalidation changes retained row');
    }
}
$oldMail=indexed($before['tables']['audyt_mail_outbox'],'id');
foreach($after['tables']['audyt_mail_outbox'] as $row) {
    $old=$oldMail[$row['id']];
    if($old['state']==='queued') {
        check($row['state']==='cancelled' && $row['encrypted_payload']===null,'Queued mail cannot replay after recovery');
        $row['state']=$old['state']; $row['encrypted_payload']=$old['encrypted_payload'];
    }
    check($row===$old,'Retained mail audit and attempts survive');
}
$events=indexed($after['tables']['audyt_auth_events'],'id');
foreach($before['tables']['audyt_auth_events'] as $event) check($events[$event['id']]===$event,'Existing security audit remains unchanged');
check(count($events)===count($before['tables']['audyt_auth_events'])+1,'One recovery audit added');
check((int)query($restored,"SELECT COUNT(*) FROM audyt_auth_events WHERE event='backup_recovery'")->fetchColumn()===1,'Recovery recorded explicitly');
$transport->sent=0;
check((new SecurityMailOutbox($restored,$secrets,$transport))->drain()===['accepted'=>0,'failed'=>0] && $transport->sent===0,'Recovery sends no stale security email');
$auth2=new AuthenticationRepository($restored,$secrets,$dummy,'fixture-v1');
foreach([$owner['token'],$linked['token'],$employee['token']] as $token) denied(fn()=>$auth2->session($token),'authentication_required');
denied(fn()=>$auth2->resetPassword($reset,$resetCode,'A replacement fictional passphrase 9999'),'invalid_code');
denied(fn()=>$auth2->verify($pending,$pendingCode),'invalid_code');
denied(fn()=>$auth2->resend($pending),'invalid_code');
check($auth2->signIn('owner@example.test',$password)['account']['id']===$id,'Password sign-in recovers original account');
check($auth2->google(['googleSubject'=>'recovery-owner','verifiedEmail'=>'owner@example.test'],'')['account']['id']===$id,'Linked Google identity remains the same account');
$memberships2=new MembershipRepository($restored);
check($memberships2->selfMembership($business,'recovery-owner')['masterDirectorId']===$id,'Owner binding and Director authority preserved');
check($memberships2->selfMembership($business,'recovery-employee')['status']==='revoked','Recovery does not restore revoked permissions');
check($memberships2->command($business,$id,$approval,[$member['identityId']=>0],'approve','employee')===$receipt,'Original retry receipt retained');
$occupied=MembershipBackup::snapshot($restored);
denied(fn()=>MembershipBackup::restoreEmpty($restored,$before),'restore_requires_empty_database');
check(MembershipBackup::snapshot($restored)['tables']===$occupied['tables'],'Refused overwrite changes no rows');
check(MembershipBackup::snapshot($db)['tables']===$before['tables'],'Source remains unchanged');

$failed=connect(newSchema()); $corrupt=$before;
$corrupt['tables']['audyt_auth_sessions'][0]['identity_id']=AuthenticationRepository::uuid();
try { MembershipBackup::restoreEmpty($failed,$corrupt); throw new RuntimeException('Invalid reference accepted'); }
catch(PDOException $error) { check($error->getCode()==='23000','Authentication foreign key failure detected'); }
$empty=MembershipBackup::snapshot($failed);
check(array_sum(array_map('count',$empty['tables']))===1,'Failed restore retains only schema guard seed');
check(!$failed->inTransaction(),'Failed recovery closes transaction');
MembershipBackup::restoreEmpty($failed,$before);
check(count(MembershipBackup::snapshot($failed)['tables']['audyt_auth_accounts'])===2,'Failed destination is reusable');

$legacy=connect(newSchema(false)); $v1=MembershipBackup::snapshot($legacy);
check($v1['version']===1,'Legacy membership-only backup remains supported');
denied(fn()=>MembershipBackup::restoreEmpty($legacy,$before),'restore_schema_mismatch');
denied(fn()=>MembershipBackup::restoreEmpty(connect(newSchema()),$v1),'restore_schema_mismatch');
$unknown=connect(newSchema(),true); $unknown->exec('CREATE TABLE future_data (id INT PRIMARY KEY) ENGINE=InnoDB');
denied(fn()=>MembershipBackup::snapshot($unknown),'backup_schema_unsupported');
$unknownColumn=connect(newSchema(),true); $unknownColumn->exec('ALTER TABLE audyt_auth_accounts ADD COLUMN future_value INT NULL');
denied(fn()=>MembershipBackup::snapshot($unknownColumn),'backup_schema_unsupported');

// Independent runtime connections: one restore wins; the second cannot overwrite.
$raceDsn=newSchema(); $folder=sys_get_temp_dir().'/audyt-auth-recovery-'.bin2hex(random_bytes(8)); mkdir($folder,0700);
$job=$folder.'/job.json'; $gate=$folder.'/go';
file_put_contents($job,json_encode(['dsn'=>$raceDsn,'archive'=>$archive,'key'=>$key,'gate'=>$gate],JSON_THROW_ON_ERROR)); chmod($job,0600);
$processes=[];
try {
    for($i=0;$i<2;$i++) {
        $p=proc_open([PHP_BINARY,__FILE__,$argv[1],'worker',$job],[0=>['pipe','r'],1=>['pipe','w'],2=>['pipe','w']],$pipes);
        if(!is_resource($p)) throw new RuntimeException('Fixture worker unavailable');
        fclose($pipes[0]); $processes[]=[$p,$pipes];
    }
    file_put_contents($gate,'go'); chmod($gate,0600); $out=[];
    foreach($processes as [$process,$pipes]) {
        $out[]=stream_get_contents($pipes[1]); $errors=stream_get_contents($pipes[2]); fclose($pipes[1]); fclose($pipes[2]);
        check(proc_close($process)===0 && $errors==='','Recovery worker completed safely');
    }
    sort($out); check($out===['already_restored','ok'],'Concurrent restore cannot overwrite committed data');
    check((int)query(connect($raceDsn),"SELECT COUNT(*) FROM audyt_auth_events WHERE event='backup_recovery'")->fetchColumn()===1,'Concurrent recovery has one committed audit');
} finally { if(is_file($gate)) unlink($gate); unlink($job); rmdir($folder); }
echo "$count authentication backup recovery checks passed\n";
