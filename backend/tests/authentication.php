<?php
declare(strict_types=1);
require __DIR__.'/../vendor/autoload.php';
use Audyt\{AuthenticationRepository,AuthenticationSecrets,AuthenticationApi,IdentityVerifier,SecurityMailOutbox,SecurityMailTransport,AuthenticatedIdentityVerifier};
$config=json_decode(file_get_contents($argv[1] ?? ''),true,16,JSON_THROW_ON_ERROR);
if (!preg_match('/^mysql:host=127\.0\.0\.1;port=\d+;dbname=audyt_test_[a-f0-9]{12};charset=utf8mb4$/D',$config['dsn'] ?? '')) throw new RuntimeException('Disposable loopback database required');
function connect(bool $admin=false): PDO {
    global $config;
    return new PDO($config['dsn'],$admin ? 'root' : 'audyt_test_runtime',$admin ? $config['rootPassword'] : $config['runtimePassword'],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_EMULATE_PREPARES=>false]);
}
if (($argv[2] ?? '')==='worker') {
    $job=json_decode(file_get_contents($argv[3]),true,16,JSON_THROW_ON_ERROR);
    $secrets=new AuthenticationSecrets(base64_decode($job['key'],true),base64_decode($job['mailKey'],true));
    $store=new AuthenticationRepository(connect(),$secrets,$job['dummyHash'],'fixture-v1');
    $deadline=microtime(true)+15;
    while (!file_exists($job['gate'])) { if (microtime(true)>$deadline) exit(2); usleep(1000); }
    try { $store->verify($job['challenge'],$job['code']); echo 'ok'; }
    catch (DomainException $error) { echo $error->getMessage()==='invalid_code' ? 'invalid_code' : 'safe_failure'; }
    exit;
}
$admin=connect(true);
if ((int)$admin->query('SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=DATABASE()')->fetchColumn()!==0) throw new RuntimeException('Refusing nonempty test schema');
$admin->exec(file_get_contents(__DIR__.'/../migrations/001_membership.sql'));
$admin->exec(file_get_contents(__DIR__.'/../migrations/002_authentication.sql'));
$key=random_bytes(32); $mailKey=random_bytes(32);
$secrets=new AuthenticationSecrets($key,$mailKey);
$dummy=$secrets->password('Fictional random dummy password 0123456789');
$now=time(); $store=new AuthenticationRepository(connect(),$secrets,$dummy,'fixture-v1',static function() use(&$now): int { return $now; });
$count=0;
function check(bool $value,string $label): void { global $count; if (!$value) throw new RuntimeException($label); $count++; }
function denied(callable $operation,string $expected): void { try { $operation(); } catch (DomainException $e) { check($e->getMessage()===$expected,'Unexpected safe denial'); return; } throw new RuntimeException('Expected denial'); }
function sql(string $query,array $values=[]): PDOStatement { global $admin; $s=$admin->prepare($query); $s->execute($values); return $s; }
function codeFor(string $id): string {
    global $secrets;
    $payload=sql("SELECT encrypted_payload FROM audyt_mail_outbox WHERE challenge_id=? AND state='queued' ORDER BY created_at DESC",[$id])->fetchColumn();
    $data=$secrets->open($payload); if (!preg_match('/\b([0-9]{6})\b/',$data['text'],$code)) throw new RuntimeException('Fixture code unavailable'); return $code[1];
}
$password='A fictional long passphrase 1234';
$challenge=$store->register('Fictional Owner','Owner@example.test','',$password,'fixture-v1')['challengeId'];
check((int)sql('SELECT COUNT(*) FROM audyt_auth_accounts')->fetchColumn()===0,'No active account before verification');
$code=codeFor($challenge);
check(!str_contains(sql('SELECT payload_json FROM audyt_auth_challenges WHERE id=?',[$challenge])->fetchColumn(),$password),'No raw password retained');
check(!str_contains(sql('SELECT code_digest FROM audyt_auth_challenges WHERE id=?',[$challenge])->fetchColumn(),$code),'No raw challenge code retained');
denied(fn()=>$store->verify($challenge,'000000'),'invalid_code');
$owner=$store->verify($challenge,$code); $id=$owner['account']['id']; $token=$owner['token'];
check($owner['account']['email']==='owner@example.test' && $owner['account']['hasPassword']===true,'Verified canonical password account');
check(!array_key_exists('role',$owner['account']),'Authentication never grants role');
check((int)sql('SELECT attempts FROM audyt_auth_challenges WHERE id=?',[$challenge])->fetchColumn()===2,'Failed attempt and success durable');
denied(fn()=>$store->verify($challenge,$code),'invalid_code');
check($store->session($token)['account']['id']===$id,'Restored same identity');
$business=AuthenticationRepository::uuid();
sql('INSERT INTO audyt_businesses (id,name) VALUES (?,?)',[$business,'Fictional Business']);
sql("INSERT INTO audyt_memberships (business_id,identity_id,display_name,contact_email,status,role) VALUES (?,?,?,?,'approved','accountant')",[$business,$id,'Fictional Owner','contact@example.test']);
$bad=$store->register('Replacement','owner@example.test','','A replacement long password 9999','fixture-v1')['challengeId'];
check((int)sql("SELECT COUNT(*) FROM audyt_mail_outbox WHERE challenge_id=? AND state='queued'",[$bad])->fetchColumn()===0,'Duplicate registration does not replace password or send a verification');
denied(fn()=>$store->verify($bad,'123456'),'invalid_code');
denied(fn()=>$store->signIn('owner@example.test','wrong password'),'invalid_credentials');
denied(fn()=>$store->signIn('unknown@example.test',$password),'invalid_credentials');
$login=$store->signIn('OWNER@example.test',$password);
check($login['account']['id']===$id,'Sign-in preserves identity');
$google=new class implements IdentityVerifier { public function verify(string $token): array { if ($token!=='verified.google.fixture') throw new DomainException('invalid_google_token'); return ['googleSubject'=>'google-owner-subject','verifiedEmail'=>'OWNER@example.test']; } };
$api=new AuthenticationApi($store,$google);
$link=$api->handle('POST','/v1/auth/google','',json_encode(['idToken'=>'verified.google.fixture','termsVersion'=>'']));
check($link['status']===200 && $link['body']['linkRequired']===true,'Google email-first sign-in requests existing email proof');
$linkId=$link['body']['challengeId'];
check((int)sql('SELECT COUNT(*) FROM audyt_auth_accounts')->fetchColumn()===1,'No duplicate identity before linking');
$linked=$store->verify($linkId,codeFor($linkId));
check($linked['account']['id']===$id && $linked['account']['hasPassword']===true,'Google links same account and preserves password');
check(sql('SELECT google_subject FROM audyt_identities WHERE id=?',[$id])->fetchColumn()==='google-owner-subject','Verified Google subject durable');
$after=$store->google(['googleSubject'=>'google-owner-subject','verifiedEmail'=>'owner@example.test'],'');
check($after['account']['id']===$id,'Google sign-in and sign-up reuse linked account');
check($store->signIn('owner@example.test',$password)['account']['id']===$id,'Original password still works after link');
check(sql('SELECT status,role FROM audyt_memberships WHERE identity_id=?',[$id])->fetch(PDO::FETCH_ASSOC)===['status'=>'approved','role'=>'accountant'],'Link preserves memberships');
check((int)sql('SELECT COUNT(*) FROM audyt_identities')->fetchColumn()===1,'Only one durable identity');
$verifier=new AuthenticatedIdentityVerifier($google,$store);
check($verifier->verify($token)['googleSubject']==='google-owner-subject','Session membership lookup follows stable identity after link');
denied(fn()=>$verifier->verify('verified.google.fixture'),'authentication_required');
$reset=$store->forgotPassword('owner@example.test')['challengeId'];
$unknown=$store->forgotPassword('unknown@example.test')['challengeId'];
check(strlen($reset)===strlen($unknown),'Neutral known and unknown recovery shape');
check((int)sql('SELECT COUNT(*) FROM audyt_mail_outbox WHERE challenge_id=?',[$unknown])->fetchColumn()===0,'Unknown recovery sends nothing');
$newPassword='Another fictional passphrase 4567';
$resetCode=codeFor($reset); $store->resetPassword($reset,$resetCode,$newPassword);
denied(fn()=>$store->session($token),'authentication_required');
denied(fn()=>$store->session($login['token']),'authentication_required');
denied(fn()=>$store->session($linked['token']),'authentication_required');
denied(fn()=>$store->resetPassword($reset,$resetCode,$newPassword),'invalid_code');
denied(fn()=>$store->signIn('owner@example.test',$password),'invalid_credentials');
$newLogin=$store->signIn('owner@example.test',$newPassword);
check($newLogin['account']['id']===$id,'Reset keeps same identity');
check(sql('SELECT role FROM audyt_memberships WHERE identity_id=?',[$id])->fetchColumn()==='accountant','Reset never changes permissions');
denied(fn()=>$store->changePassword($newLogin['token'],'wrong current',str_repeat('a',20)),'invalid_credentials');
$store->changePassword($newLogin['token'],$newPassword,'Third fictional passphrase 6789');
denied(fn()=>$store->session($newLogin['token']),'authentication_required');
$final=$store->signIn('owner@example.test','Third fictional passphrase 6789');
$store->signOut($final['token']); denied(fn()=>$store->session($final['token']),'authentication_required');
$googleOnly=$store->google(['googleSubject'=>'other-google','verifiedEmail'=>'google-only@example.test','authoritativeEmail'=>true],'fixture-v1');
check($googleOnly['account']['hasPassword']===false,'Google-only account has no implicit local password');
denied(fn()=>$store->changePassword($googleOnly['token'],'anything',str_repeat('b',20)),'password_required');
$googleRecovery=$store->forgotPassword('google-only@example.test')['challengeId'];
check(sql('SELECT purpose FROM audyt_auth_challenges WHERE id=?',[$googleRecovery])->fetchColumn()==='unavailable','Google-only recovery stays with provider');
denied(fn()=>$store->google(['googleSubject'=>'another-provider-subject','verifiedEmail'=>'google-only@example.test','authoritativeEmail'=>true],'fixture-v1'),'link_conflict');
$thirdParty=$store->google(['googleSubject'=>'third-party-google','verifiedEmail'=>'third-party@example.test'],'fixture-v1');
check(($thirdParty['verificationRequired'] ?? false)===true,'Third-party Google email requires fresh mailbox proof');
check($store->verify($thirdParty['challengeId'],codeFor($thirdParty['challengeId']))['account']['hasPassword']===false,'Fresh proof creates Google-only account');
$attempt=$store->register('Attempt User','attempt@example.test','',$password,'fixture-v1')['challengeId']; $attemptCode=codeFor($attempt);
for ($i=0;$i<5;$i++) denied(fn()=>$store->verify($attempt,'000000'),'invalid_code');
denied(fn()=>$store->verify($attempt,$attemptCode),'invalid_code');
$expired=$store->register('Expiry User','expiry@example.test','',$password,'fixture-v1')['challengeId']; $expiryCode=codeFor($expired);
$now+=601; denied(fn()=>$store->verify($expired,$expiryCode),'invalid_code');
$resend=$store->register('Resend User','resend@example.test','',$password,'fixture-v1')['challengeId']; $oldCode=codeFor($resend);
denied(fn()=>$store->resend($resend),'rate_limited');
$now+=61; $store->resend($resend); $freshCode=codeFor($resend);
if ($oldCode!==$freshCode) denied(fn()=>$store->verify($resend,$oldCode),'invalid_code');
denied(fn()=>$store->resend($resend),'rate_limited');
$store->verify($resend,$freshCode);
check((int)sql("SELECT COUNT(*) FROM audyt_mail_outbox WHERE challenge_id=? AND state='queued'",[$resend])->fetchColumn()===0,'Completed/superseded codes are not sent later');
// Independent PHP workers compete for the same challenge in MariaDB.
$race=$store->register('Race User','race@example.test','',$password,'fixture-v1')['challengeId'];
$directory=sys_get_temp_dir().'/audyt-auth-race-'.bin2hex(random_bytes(6)); mkdir($directory,0700);
$gate=$directory.'/gate'; $job=$directory.'/job.json';
file_put_contents($job,json_encode(['key'=>base64_encode($key),'mailKey'=>base64_encode($mailKey),'dummyHash'=>$dummy,'gate'=>$gate,'challenge'=>$race,'code'=>codeFor($race)],JSON_THROW_ON_ERROR)); chmod($job,0600);
$workers=[];
for ($i=0;$i<2;$i++) {
    $pipes=[]; $process=proc_open([PHP_BINARY,__FILE__,$argv[1],'worker',$job],[0=>['pipe','r'],1=>['pipe','w'],2=>['pipe','w']],$pipes);
    if (!is_resource($process)) throw new RuntimeException('Fixture worker unavailable');
    fclose($pipes[0]); $workers[]=[$process,$pipes];
}
touch($gate); $results=[];
foreach ($workers as [$process,$pipes]) { $results[]=stream_get_contents($pipes[1]); fclose($pipes[1]);
    $errors=stream_get_contents($pipes[2]); fclose($pipes[2]); if (proc_close($process)!==0 || $errors!=='') throw new RuntimeException('Fixture worker failed'); }
sort($results); check($results===['invalid_code','ok'],'Atomic concurrent code redemption has one winner');
check((int)sql("SELECT COUNT(*) FROM audyt_auth_accounts WHERE email='race@example.test'")->fetchColumn()===1,'Concurrent redemption creates one identity');
unlink($gate); unlink($job); rmdir($directory);
// Cipher tampering and key separation, no mail network calls.
$sealed=$secrets->seal(['to'=>'fictional@example.test','subject'=>'Fixture','text'=>'No real email']);
check($secrets->open($sealed)['text']==='No real email','Authenticated encrypted mail payload');
try { $secrets->open(substr($sealed,0,-4).'AAAA'); throw new RuntimeException('Expected cipher failure'); } catch (RuntimeException $e) { check($e->getMessage()==='invalid_mail_payload','Cipher tampering refused'); }
$transport=new class implements SecurityMailTransport { public int $sent=0; public bool $fail=true; public function send(string $id,array $payload): void { if ($this->fail) throw new RuntimeException('No secrets in safe worker output'); $this->sent++; } };
$worker=new SecurityMailOutbox(connect(),$secrets,$transport);
$result=$worker->drain(1); check($result['failed']===1 && $transport->sent===0,'Mail failure remains retryable');
sql("UPDATE audyt_mail_outbox SET next_attempt_at=UTC_TIMESTAMP(6) WHERE state='queued'");
$transport->fail=false; $result=$worker->drain(50);
check($result['accepted']>0,'Retry sends via adapter');
check((int)sql("SELECT COUNT(*) FROM audyt_mail_outbox WHERE state='accepted' AND encrypted_payload IS NOT NULL")->fetchColumn()===0,'Accepted code payload removed from outbox');
$sent=$transport->sent; $worker->drain(50); check($transport->sent===$sent,'Accepted messages not resent');
check($api->handle('GET','/v1/auth/sign-in','', '{}')['status']===405,'Auth method constrained');
check($api->handle('POST','/v1/auth/sign-in','', str_repeat('a',32769))['status']===413,'Auth request bounded');
check($api->handle('POST','/v1/auth/sign-in','', '{bad')['status']===400,'Malformed auth JSON safe');
check($api->handle('POST','/v1/auth/session','Bearer forged-token','{}')['status']===401,'Forged session refused');
check($api->handle('POST','/v1/auth/sign-in','', json_encode(['email'=>'owner@example.test','password'=>$password,'role'=>'director']))['status']===401,'Caller role cannot enter auth');
denied(fn()=>$store->register('Weak','weak@example.test','','short','fixture-v1'),'weak_password');
denied(fn()=>$store->register('Terms','terms@example.test','',$password,'stale-terms'),'terms_required');
for($i=0;$i<5;$i++) $store->forgotPassword('limit@example.test');
denied(fn()=>$store->forgotPassword('limit@example.test'),'rate_limited');
check(AuthenticationRepository::email(' A.B+Tag@Example.Test ')==='a.b+tag@example.test','No plus/dot alias rewriting');
$a=str_repeat('x',100).'A'; $b=str_repeat('x',100).'B'; $hash=$secrets->password($a);
check($secrets->matches($a,$hash) && !$secrets->matches($b,$hash),'No bcrypt 72-byte truncation');
$audit=sql('SELECT event FROM audyt_auth_events')->fetchAll(PDO::FETCH_COLUMN);
check(in_array('google_linked',$audit,true) && in_array('password_changed',$audit,true),'Security audit durable and secret-free');
echo $count," authentication/MariaDB checks passed; no real mail sent.\n";
