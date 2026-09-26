<?php
declare(strict_types=1);
namespace Audyt;

/** MariaDB transactions own identity, challenge redemption, sessions and mail intent.
 * The small single-host auth guard establishes one lock order across all flows.
 * It does not hold a lock while SMTP is contacted and never grants a membership.
 */
final class AuthenticationRepository
{
    private \Closure $clock;
    public function __construct(private \PDO $db,private AuthenticationSecrets $secrets,
        private string $dummyHash,private string $termsVersion,?\Closure $clock=null) {
        if ($dummyHash==='' || strlen($termsVersion)>80) throw new \InvalidArgumentException('authentication_configuration_required');
        $this->clock=$clock ?? static fn(): int=>time();
        $db->setAttribute(\PDO::ATTR_ERRMODE,\PDO::ERRMODE_EXCEPTION);
        $db->setAttribute(\PDO::ATTR_EMULATE_PREPARES,false);
    }
    private function now(): int { return ($this->clock)(); }
    private function stamp(?int $time=null): string { return gmdate('Y-m-d H:i:s',$time ?? $this->now()); }
    private function query(string $sql,array $values=[]): \PDOStatement { $s=$this->db->prepare($sql); $s->execute($values); return $s; }
    private function transaction(callable $action): mixed {
        $this->db->beginTransaction();
        try {
            if ($this->query('SELECT id FROM audyt_auth_guard WHERE id=1 FOR UPDATE')->fetchColumn()===false) throw new \RuntimeException('authentication_configuration_required');
            $result=$action(); $this->db->commit(); return $result;
        } catch (\Throwable $error) { if ($this->db->inTransaction()) $this->db->rollBack(); throw $error; }
    }
    public static function uuid(): string { $h=bin2hex(random_bytes(16)); return substr($h,0,8).'-'.substr($h,8,4).'-4'.substr($h,13,3).'-8'.substr($h,17,3).'-'.substr($h,20); }
    public static function email(string $email): string {
        $email=strtolower(trim($email));
        if (strlen($email)>320 || filter_var($email,FILTER_VALIDATE_EMAIL)===false || preg_match('/[\x00-\x20\x7f]/',$email)) throw new \DomainException('invalid_credentials');
        return $email;
    }
    private function key(string $email): string { return $this->secrets->digest('email',self::email($email)); }
    private function limit(string $key,string $action,int $maximum,int $window): void {
        $bucket=intdiv($this->now(),$window);
        $this->query('INSERT INTO audyt_auth_limits (subject_key,action,bucket,attempts) VALUES (?,?,?,1) ON DUPLICATE KEY UPDATE attempts=LEAST(attempts+1,1000000)',[$key,$action,$bucket]);
        if ((int)$this->query('SELECT attempts FROM audyt_auth_limits WHERE subject_key=? AND action=? AND bucket=?',[$key,$action,$bucket])->fetchColumn()>$maximum) throw new \DomainException('rate_limited');
    }
    private function accountForEmail(string $email): array|false { return $this->query('SELECT * FROM audyt_auth_accounts WHERE email_key=?',[$this->key($email)])->fetch(\PDO::FETCH_ASSOC); }
    private function event(?string $id,string $event): void { $this->query('INSERT INTO audyt_auth_events (id,identity_id,event,created_at) VALUES (?,?,?,?)',[self::uuid(),$id,$event,$this->stamp()]); }
    private function mail(string $email,string $subject,string $text,?string $challenge=null,int $lifetime=86400): void {
        $id=self::uuid();
        $payload=$this->secrets->seal(['to'=>$email,'subject'=>$subject,'text'=>$text]);
        $this->query('INSERT INTO audyt_mail_outbox (id,challenge_id,encrypted_payload,created_at,next_attempt_at,expires_at) VALUES (?,?,?,?,?,?)',[$id,$challenge,$payload,$this->stamp(),$this->stamp(),$this->stamp($this->now()+$lifetime)]);
    }
    private function alert(array $account,string $kind): void {
        $this->mail($account['email'],'Audyt: '.$kind,$kind.' for your Audyt account at '.$this->stamp().' UTC. If this was not you, secure your account and contact support. This email contains no password or business records.');
    }
    private function issue(string $email,string $purpose,array $payload,int $minutes=10): array {
        $id=self::uuid(); $code=(string)random_int(100000,999999); $key=$this->key($email);
        $previous=$this->query('SELECT id FROM audyt_auth_challenges WHERE email_key=? AND purpose=? AND consumed_at IS NULL',[$key,$purpose])->fetchAll(\PDO::FETCH_COLUMN);
        foreach ($previous as $old) $this->query("UPDATE audyt_mail_outbox SET state='cancelled',encrypted_payload=NULL WHERE challenge_id=? AND state='queued'",[$old]);
        $this->query('UPDATE audyt_auth_challenges SET consumed_at=? WHERE email_key=? AND purpose=? AND consumed_at IS NULL',[$this->stamp(),$key,$purpose]);
        $this->query('INSERT INTO audyt_auth_challenges (id,email_key,email,purpose,payload_json,code_digest,created_at,last_sent_at,expires_at) VALUES (?,?,?,?,?,?,?,?,?)',[$id,$key,$email,$purpose,json_encode($payload,JSON_THROW_ON_ERROR),$this->secrets->digest('code',$id.':'.$code),$this->stamp(),$this->stamp(),$this->stamp($this->now()+$minutes*60)]);
        if ($purpose!=='unavailable') $this->mail($email,'Audyt: Verification Code','Your Audyt code is '.$code.'. It expires in '.$minutes.' minutes. Do not share this code. If you did not request it, ignore this email.',$id,$minutes*60);
        return ['challengeId'=>$id];
    }
    public function register(string $name,string $email,string $phone,string $password,string $terms): array {
        $email=self::email($email); $this->limit($this->key($email),'register',5,3600);
        if ($this->termsVersion==='' || !hash_equals($this->termsVersion,$terms)) throw new \DomainException('terms_required');
        $name=trim($name); $phone=trim($phone);
        if (preg_match('//u',$name)!==1 || mb_strlen($name)<1 || mb_strlen($name)>200 || strlen($phone)>40 || preg_match('/[\x00-\x1f\x7f]/',$name.$phone)) throw new \DomainException('invalid_credentials');
        $hash=$this->secrets->password($password);
        return $this->transaction(function() use($email,$name,$phone,$hash,$terms) {
            // Never overwrite a registered password or reveal existence.
            if ($this->accountForEmail($email) || $this->query('SELECT id FROM audyt_identities WHERE LOWER(verified_google_email)=? LIMIT 1',[$email])->fetchColumn()!==false) return $this->issue($email,'unavailable',[]);
            return $this->issue($email,'register',['name'=>$name,'phone'=>$phone,'passwordHash'=>$hash,'terms'=>$terms]);
        });
    }
    public function signIn(string $email,string $password): array {
        $email=self::email($email); $this->limit($this->key($email),'sign-in',10,600);
        return $this->transaction(function() use($email,$password) {
            $account=$this->accountForEmail($email);
            $valid=$this->secrets->matches($password,$account['password_hash'] ?? $this->dummyHash);
            if (!$account || $account['password_hash']===null || !$valid) throw new \DomainException('invalid_credentials');
            return $this->newSession($account,'password_sign_in');
        });
    }
    public function forgotPassword(string $email): array {
        $email=self::email($email); $this->limit($this->key($email),'forgot-password',5,3600);
        return $this->transaction(function() use($email) {
            $account=$this->accountForEmail($email);
            return $this->issue($email,$account && $account['password_hash']!==null ? 'reset' : 'unavailable',
                $account && $account['password_hash']!==null ? ['identityId'=>$account['identity_id']] : [],15);
        });
    }
    public function resend(string $id): array {
        self::challengeId($id);
        $key=$this->query('SELECT email_key FROM audyt_auth_challenges WHERE id=?',[$id])->fetchColumn();
        if ($key!==false) $this->limit($key,'resend',5,3600);
        return $this->transaction(function() use($id) {
            $row=$this->query('SELECT * FROM audyt_auth_challenges WHERE id=?',[$id])->fetch(\PDO::FETCH_ASSOC);
            if (!$row || $row['consumed_at']!==null || $row['expires_at']<=$this->stamp() || (int)$row['resends']>=3) throw new \DomainException('invalid_code');
            if ($this->now()-strtotime($row['last_sent_at'].' UTC')<60) throw new \DomainException('rate_limited');
            $this->query("UPDATE audyt_mail_outbox SET state='cancelled',encrypted_payload=NULL WHERE challenge_id=? AND state='queued'",[$id]);
            $code=(string)random_int(100000,999999); $minutes=$row['purpose']==='reset' ? 15 : 10;
            $this->query('UPDATE audyt_auth_challenges SET code_digest=?,attempts=0,resends=resends+1,last_sent_at=?,expires_at=? WHERE id=?',[$this->secrets->digest('code',$id.':'.$code),$this->stamp(),$this->stamp($this->now()+$minutes*60),$id]);
            if ($row['purpose']!=='unavailable') $this->mail($row['email'],'Audyt: Verification Code','Your new Audyt code is '.$code.'. It expires in '.$minutes.' minutes. Do not share it.',$id,$minutes*60);
            return ['requested'=>true];
        });
    }
    private static function challengeId(string $id): void { if (!preg_match('/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/D',$id)) throw new \DomainException('invalid_code'); }
    private function redeem(string $id,string $code,array $purposes,callable $operation): array {
        self::challengeId($id);
        $result=$this->transaction(function() use($id,$code,$purposes,$operation) {
            $row=$this->query('SELECT * FROM audyt_auth_challenges WHERE id=?',[$id])->fetch(\PDO::FETCH_ASSOC);
            if (!$row || $row['consumed_at']!==null || $row['expires_at']<=$this->stamp() || (int)$row['attempts']>=5 || !in_array($row['purpose'],$purposes,true)) return null;
            $this->query('UPDATE audyt_auth_challenges SET attempts=attempts+1 WHERE id=?',[$id]);
            if (!preg_match('/^[0-9]{6}$/D',$code) || !hash_equals($row['code_digest'],$this->secrets->digest('code',$id.':'.$code))) return null;
            $value=$operation($row,json_decode($row['payload_json'],true,8,JSON_THROW_ON_ERROR));
            $this->query('UPDATE audyt_auth_challenges SET consumed_at=? WHERE id=?',[$this->stamp(),$id]);
            $this->query("UPDATE audyt_mail_outbox SET state='cancelled',encrypted_payload=NULL WHERE challenge_id=? AND state='queued'",[$id]);
            return $value;
        });
        // Commit failed attempts before returning a neutral denial.
        if ($result===null) throw new \DomainException('invalid_code');
        return $result;
    }
    public function verify(string $id,string $code): array {
        return $this->redeem($id,$code,['register','google-register','link'],function($row,$payload) {
            if (in_array($row['purpose'],['register','google-register'],true)) {
                if ($this->accountForEmail($row['email'])) throw new \DomainException('invalid_code');
                $id=self::uuid(); $subject='email:'.$id;
                $bound=false;
                if ($row['purpose']==='google-register') {
                    $subject=$payload['googleSubject'];
                    $bound=$this->query('SELECT id FROM audyt_identities WHERE google_subject=?',[$subject])->fetchColumn();
                    if ($bound!==false) $id=$bound;
                }
                if ($bound===false) $this->query('INSERT INTO audyt_identities (id,google_subject,verified_google_email) VALUES (?,?,?)',[$id,$subject,$row['email']]);
                $this->createAccount($id,$row['email'],$payload['name'],$payload['phone'],$payload['passwordHash'],$payload['terms']);
                $this->event($id,'email_verified');
            } else {
                $id=$payload['identityId']; $subject=$payload['googleSubject'];
                $current=$this->accountForEmail($row['email']);
                if (!$current || $current['identity_id']!==$id) throw new \DomainException('link_conflict');
                $bound=$this->query('SELECT id FROM audyt_identities WHERE google_subject=?',[$subject])->fetchColumn();
                $old=$this->query('SELECT google_subject FROM audyt_identities WHERE id=?',[$id])->fetchColumn();
                if (($bound!==false && $bound!==$id) || (!str_starts_with($old,'email:') && $old!==$subject)) throw new \DomainException('link_conflict');
                $this->query('UPDATE audyt_identities SET google_subject=?,verified_google_email=? WHERE id=?',[$subject,$row['email'],$id]);
                $this->event($id,'google_linked');
                $this->alert($current,'Google Account Linked');
            }
            $account=$this->query('SELECT * FROM audyt_auth_accounts WHERE identity_id=?',[$id])->fetch(\PDO::FETCH_ASSOC);
            return $this->newSession($account,'verified_sign_in');
        });
    }
    public function resetPassword(string $id,string $code,string $password): array {
        $hash=$this->secrets->password($password);
        return $this->redeem($id,$code,['reset'],function($row,$payload) use($hash) {
            $account=$this->accountForEmail($row['email']);
            if (!$account || $account['identity_id']!==$payload['identityId'] || $account['password_hash']===null) throw new \DomainException('invalid_code');
            $this->replacePassword($account,$hash);
            return ['changed'=>true];
        });
    }
    private function replacePassword(array $account,string $hash): void {
        $id=$account['identity_id'];
        $this->query('UPDATE audyt_auth_accounts SET password_hash=? WHERE identity_id=?',[$hash,$id]);
        $this->query('UPDATE audyt_auth_sessions SET revoked_at=? WHERE identity_id=? AND revoked_at IS NULL',[$this->stamp(),$id]);
        $this->query("UPDATE audyt_auth_challenges SET consumed_at=? WHERE email_key=? AND purpose='reset' AND consumed_at IS NULL",[$this->stamp(),$account['email_key']]);
        $this->event($id,'password_changed'); $this->alert($account,'Password Changed');
    }
    public function changePassword(string $token,string $current,string $password): array {
        $hash=$this->secrets->password($password);
        $account=$this->sessionAccount($token);
        $this->limit($account['email_key'],'change-password',5,3600);
        return $this->transaction(function() use($token,$current,$hash) {
            $account=$this->sessionAccount($token);
            if ($account['password_hash']===null) throw new \DomainException('password_required');
            if (!$this->secrets->matches($current,$account['password_hash'])) throw new \DomainException('invalid_credentials');
            $this->replacePassword($account,$hash); return ['changed'=>true];
        });
    }
    public function google(array $verified,string $terms): array {
        $authoritative=($verified['authoritativeEmail'] ?? false)===true;
        $subject=$verified['googleSubject']; $email=self::email($verified['verifiedEmail']);
        if (!is_string($subject) || $subject==='' || strlen($subject)>255 || str_starts_with($subject,'email:') || preg_match('/[\x00-\x20\x7f]/',$subject)) throw new \DomainException('invalid_google_token');
        $this->limit($this->key($email),'google',10,600);
        return $this->transaction(function() use($subject,$email,$terms,$authoritative) {
            $account=$this->accountForEmail($email);
            $bound=$this->query('SELECT id FROM audyt_identities WHERE google_subject=?',[$subject])->fetchColumn();
            if ($bound!==false) {
                $existing=$this->query('SELECT * FROM audyt_auth_accounts WHERE identity_id=?',[$bound])->fetch(\PDO::FETCH_ASSOC);
                if ($existing) return $this->newSession($existing,'google_sign_in');
            }
            if ($account) {
                if ($bound!==false && $bound!==$account['identity_id']) throw new \DomainException('link_conflict');
                $old=$this->query('SELECT google_subject FROM audyt_identities WHERE id=?',[$account['identity_id']])->fetchColumn();
                if (!str_starts_with($old,'email:') && $old!==$subject) throw new \DomainException('link_conflict');
                $challenge=$this->issue($account['email'],'link',['identityId'=>$account['identity_id'],'googleSubject'=>$subject]);
                return ['linkRequired'=>true]+$challenge;
            }
            if ($this->termsVersion==='' || !hash_equals($this->termsVersion,$terms)) throw new \DomainException('terms_required');
            if (!$authoritative) {
                return ['verificationRequired'=>true]+$this->issue($email,'google-register',[
                    'googleSubject'=>$subject,'name'=>$email,'phone'=>'','passwordHash'=>null,'terms'=>$terms]);
            }
            $id=$bound!==false ? $bound : self::uuid();
            if ($bound===false) $this->query('INSERT INTO audyt_identities (id,google_subject,verified_google_email) VALUES (?,?,?)',[$id,$subject,$email]);
            $this->createAccount($id,$email,$email,'',null,$terms);
            $account=$this->accountForEmail($email);
            return $this->newSession($account,'google_sign_in');
        });
    }
    private function createAccount(string $id,string $email,string $name,string $phone,?string $hash,string $terms): void {
        $key=$this->key($email);
        $this->query('INSERT INTO audyt_auth_email_locks (email_key) VALUES (?) ON DUPLICATE KEY UPDATE email_key=VALUES(email_key)',[$key]);
        $this->query('INSERT INTO audyt_auth_accounts (identity_id,email_key,email,display_name,phone,password_hash,terms_version,terms_accepted_at,created_at) VALUES (?,?,?,?,?,?,?,?,?)',[$id,$key,$email,$name,$phone,$hash,$terms,$this->stamp(),$this->stamp()]);
    }
    private function newSession(array $account,string $event): array {
        $token='audyt_'.bin2hex(random_bytes(32));
        $this->query('INSERT INTO audyt_auth_sessions (token_digest,identity_id,created_at,expires_at) VALUES (?,?,?,?)',[hash('sha256',$token),$account['identity_id'],$this->stamp(),$this->stamp($this->now()+604800)]);
        $this->event($account['identity_id'],$event); $this->alert($account,'New Sign In');
        return ['token'=>$token,'account'=>$this->publicAccount($account)];
    }
    private function publicAccount(array $account): array {
        $subject=$this->query('SELECT google_subject FROM audyt_identities WHERE id=?',[$account['identity_id']])->fetchColumn();
        return ['id'=>$account['identity_id'],'email'=>$account['email'],'name'=>$account['display_name'],
            'hasPassword'=>$account['password_hash']!==null,'googleSubject'=>str_starts_with($subject,'email:') ? '' : $subject];
    }
    private function sessionAccount(string $token): array {
        if (!preg_match('/^audyt_[a-f0-9]{64}$/D',$token)) throw new \DomainException('authentication_required');
        $row=$this->query('SELECT a.* FROM audyt_auth_sessions s JOIN audyt_auth_accounts a ON a.identity_id=s.identity_id WHERE s.token_digest=? AND s.revoked_at IS NULL AND s.expires_at>?',[hash('sha256',$token),$this->stamp()])->fetch(\PDO::FETCH_ASSOC);
        if (!$row) throw new \DomainException('authentication_required'); return $row;
    }
    public function session(string $token): array { return ['account'=>$this->publicAccount($this->sessionAccount($token))]; }
    public function verifiedIdentity(string $token): array {
        $account=$this->sessionAccount($token);
        $subject=$this->query('SELECT google_subject FROM audyt_identities WHERE id=?',[$account['identity_id']])->fetchColumn();
        return ['googleSubject'=>$subject,'verifiedEmail'=>$account['email']];
    }
    public function signOut(string $token): array {
        if (!preg_match('/^audyt_[a-f0-9]{64}$/D',$token)) throw new \DomainException('authentication_required');
        return $this->transaction(function() use($token) {
            $row=$this->query('SELECT identity_id FROM audyt_auth_sessions WHERE token_digest=? AND revoked_at IS NULL',[hash('sha256',$token)])->fetch(\PDO::FETCH_ASSOC);
            if ($row) {
                $this->query('UPDATE audyt_auth_sessions SET revoked_at=? WHERE token_digest=?',[$this->stamp(),hash('sha256',$token)]);
                $this->event($row['identity_id'],'sign_out');
            }
            // An uncertain response can be retried without retaining a revoked
            // client session, revealing identity or creating duplicate audit.
            return ['signedOut'=>true];
        });
    }
}
