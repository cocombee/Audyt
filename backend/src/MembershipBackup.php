<?php
declare(strict_types=1);
namespace Audyt;

/** Private identity-service backup. No ledger, document bytes or raw credentials.
 * V2 includes password hashes, secret digests and encrypted mail payloads, so the
 * authenticated archive and its separately held keys are security-sensitive.
 */
final class MembershipBackup
{
    private const LIMIT = 67108864;
    private const MEMBERSHIP_COLUMNS = [
        'audyt_businesses'=>['id','name','revision','created_at'],
        'audyt_identities'=>['id','google_subject','verified_google_email','created_at'],
        'audyt_memberships'=>['business_id','identity_id','display_name','contact_email','status','role','requested_role','revision','submitted_at','updated_at'],
        'audyt_commands'=>['business_id','actor_id','request_id','payload_sha256','result_json','created_at'],
        'audyt_access_events'=>['sequence_id','business_id','actor_id','target_id','request_id','action','before_status','after_status','before_role','after_role','revision','created_at'],
        'audyt_owner_bootstrap'=>['business_id','expected_verified_email','bound_identity_id','bound_at'],
    ];
    private const AUTHENTICATION_COLUMNS = [
        'audyt_auth_guard'=>['id'],
        'audyt_auth_email_locks'=>['email_key'],
        'audyt_auth_accounts'=>['identity_id','email_key','email','display_name','phone','password_hash','terms_version','terms_accepted_at','created_at'],
        'audyt_auth_challenges'=>['id','email_key','email','purpose','payload_json','code_digest','attempts','resends','last_sent_at','created_at','expires_at','consumed_at'],
        'audyt_auth_sessions'=>['token_digest','identity_id','created_at','expires_at','revoked_at'],
        'audyt_auth_limits'=>['subject_key','action','bucket','attempts'],
        'audyt_auth_events'=>['id','identity_id','event','created_at'],
        'audyt_mail_outbox'=>['id','challenge_id','encrypted_payload','state','attempts','created_at','next_attempt_at','expires_at','accepted_at'],
    ];

    private static function columns(int $version): array
    {
        return match($version) {
            1=>self::MEMBERSHIP_COLUMNS,
            2=>[...self::MEMBERSHIP_COLUMNS,...self::AUTHENTICATION_COLUMNS],
            default=>throw new \RuntimeException('invalid_backup'),
        };
    }

    /** Fail closed when a migration adds data this backup does not yet own. */
    private static function databaseVersion(\PDO $db): int
    {
        $names=$db->query('SELECT table_name FROM information_schema.tables WHERE table_schema=DATABASE() ORDER BY table_name')->fetchAll(\PDO::FETCH_COLUMN);
        foreach([1,2] as $version) {
            $contract=self::columns($version); $expected=array_keys($contract); sort($expected,SORT_STRING);
            if($names!==$expected) continue;
            $statement=$db->prepare('SELECT column_name FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name=? ORDER BY ordinal_position');
            foreach($contract as $table=>$columns) {
                $statement->execute([$table]);
                if($statement->fetchAll(\PDO::FETCH_COLUMN)!==$columns) throw new \RuntimeException('backup_schema_unsupported');
            }
            return $version;
        }
        throw new \RuntimeException('backup_schema_unsupported');
    }

    public static function snapshot(\PDO $db): array
    {
        if ($db->getAttribute(\PDO::ATTR_DRIVER_NAME)!=='mysql' || $db->inTransaction()) {
            throw new \RuntimeException('backup_database_required');
        }
        $db->exec('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ');
        $db->beginTransaction();
        try {
            $version=self::databaseVersion($db);
            $tables=[]; $bytes=0;
            foreach(self::columns($version) as $table=>$columns) {
                $rows=[];
                $order=match($table) {
                    'audyt_memberships'=>'business_id,identity_id',
                    'audyt_commands'=>'business_id,actor_id,request_id',
                    'audyt_auth_limits'=>'subject_key,action,bucket',
                    default=>$columns[0],
                };
                $statement=$db->query('SELECT '.implode(',',$columns).' FROM '.$table.' ORDER BY '.$order);
                while($row=$statement->fetch(\PDO::FETCH_ASSOC)) {
                    $bytes+=strlen(json_encode($row,JSON_THROW_ON_ERROR));
                    if($bytes>self::LIMIT/2) throw new \RuntimeException('backup_too_large');
                    $rows[]=$row;
                }
                $tables[$table]=$rows;
            }
            $snapshot=['kind'=>'audyt-membership','version'=>$version,'createdAt'=>gmdate('c'),'tables'=>$tables];
            self::validate($snapshot);
            $db->commit();
            return $snapshot;
        } catch(\Throwable $error) {
            if($db->inTransaction()) $db->rollBack();
            throw $error;
        }
    }

    private static function validate(array $snapshot): void
    {
        if(array_keys($snapshot)!==['kind','version','createdAt','tables']
            || $snapshot['kind']!=='audyt-membership' || !in_array($snapshot['version'],[1,2],true)
            || !is_string($snapshot['createdAt']) || !is_array($snapshot['tables'])
            || array_keys($snapshot['tables'])!==array_keys(self::columns($snapshot['version']))) {
            throw new \RuntimeException('invalid_backup');
        }
        foreach(self::columns($snapshot['version']) as $table=>$columns) {
            if(!is_array($snapshot['tables'][$table]) || !array_is_list($snapshot['tables'][$table])) throw new \RuntimeException('invalid_backup');
            foreach($snapshot['tables'][$table] as $row) {
                if(!is_array($row) || array_keys($row)!==$columns) throw new \RuntimeException('invalid_backup');
                foreach($row as $value) if($value!==null && !is_string($value) && !is_int($value)) throw new \RuntimeException('invalid_backup');
            }
        }
        if($snapshot['version']===2) {
            $guard=$snapshot['tables']['audyt_auth_guard'];
            if(count($guard)!==1 || !in_array($guard[0]['id'],[1,'1'],true)) throw new \RuntimeException('invalid_backup');
        }
    }

    private static function key(string $encoded): string
    {
        $key=base64_decode($encoded,true);
        if($key===false || strlen($key)!==32) throw new \RuntimeException('backup_key_required');
        return $key;
    }

    public static function seal(array $snapshot, string $encodedKey): string
    {
        self::validate($snapshot);
        $plain=json_encode($snapshot,JSON_THROW_ON_ERROR|JSON_UNESCAPED_UNICODE);
        if(strlen($plain)>self::LIMIT/2) throw new \RuntimeException('backup_too_large');
        $nonce=random_bytes(12); $tag='';
        $cipher=openssl_encrypt($plain,'aes-256-gcm',self::key($encodedKey),OPENSSL_RAW_DATA,$nonce,$tag,'Audyt membership backup v'.$snapshot['version'],16);
        if($cipher===false) throw new \RuntimeException('backup_encryption_failed');
        return 'AUDYT-MEMBERSHIP-'.$snapshot['version']."\n".base64_encode($nonce.$tag.$cipher);
    }

    public static function open(string $archive, string $encodedKey): array
    {
        if(strlen($archive)>self::LIMIT || !preg_match('/\AAUDYT-MEMBERSHIP-([12])\n/',$archive,$header)) throw new \RuntimeException('invalid_backup');
        $prefix=$header[0]; $version=(int)$header[1];
        $bytes=base64_decode(substr($archive,strlen($prefix)),true);
        if($bytes===false || strlen($bytes)<29) throw new \RuntimeException('invalid_backup');
        $plain=openssl_decrypt(substr($bytes,28),'aes-256-gcm',self::key($encodedKey),OPENSSL_RAW_DATA,substr($bytes,0,12),substr($bytes,12,16),'Audyt membership backup v'.$version);
        if($plain===false) throw new \RuntimeException('backup_authentication_failed');
        $snapshot=json_decode($plain,true,32,JSON_THROW_ON_ERROR);
        if(!is_array($snapshot)) throw new \RuntimeException('invalid_backup');
        self::validate($snapshot);
        if($snapshot['version']!==$version) throw new \RuntimeException('invalid_backup');
        return $snapshot;
    }

    /** Recovery only, against an empty matching schema and maintenance window.
     * V2 keeps identity/password/permission history, but requires fresh sessions
     * and challenges and cancels queued mail to avoid replaying an old snapshot.
     */
    public static function restoreEmpty(\PDO $db, array $snapshot): void
    {
        self::validate($snapshot);
        if($db->getAttribute(\PDO::ATTR_DRIVER_NAME)!=='mysql' || $db->inTransaction()) throw new \RuntimeException('backup_database_required');
        $db->exec('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ');
        $db->beginTransaction();
        try {
            $version=$snapshot['version']; $contract=self::columns($version);
            if(self::databaseVersion($db)!==$version) throw new \RuntimeException('restore_schema_mismatch');
            if($version===2) {
                // The additive migration creates this one lock row. It is not
                // user data; retain it rather than deleting/reinserting it.
                $guard=$db->query('SELECT id FROM audyt_auth_guard FOR UPDATE')->fetchAll(\PDO::FETCH_COLUMN);
                if(count($guard)!==1 || !in_array($guard[0],[1,'1'],true)) throw new \RuntimeException('restore_schema_mismatch');
            }
            foreach($contract as $table=>$columns) {
                if($table==='audyt_auth_guard') continue;
                // Full range locks prevent an empty-check race with another writer.
                if($db->query('SELECT '.$columns[0].' FROM '.$table.' FOR UPDATE')->fetchColumn()!==false) {
                    throw new \RuntimeException('restore_requires_empty_database');
                }
            }
            foreach($contract as $table=>$columns) {
                if($table==='audyt_auth_guard') continue;
                $insert=$db->prepare('INSERT INTO '.$table.' ('.implode(',',$columns).') VALUES ('.implode(',',array_fill(0,count($columns),'?')).')');
                foreach($snapshot['tables'][$table] as $row) $insert->execute(array_values($row));
            }
            if($version===2) {
                $db->exec('UPDATE audyt_auth_sessions SET revoked_at=UTC_TIMESTAMP(6) WHERE revoked_at IS NULL');
                $db->exec('UPDATE audyt_auth_challenges SET consumed_at=UTC_TIMESTAMP(6) WHERE consumed_at IS NULL');
                $db->exec("UPDATE audyt_mail_outbox SET state='cancelled',encrypted_payload=NULL WHERE state='queued'");
                $event=$db->prepare("INSERT INTO audyt_auth_events (id,identity_id,event,created_at) VALUES (?,NULL,'backup_recovery',UTC_TIMESTAMP(6))");
                $event->execute([AuthenticationRepository::uuid()]);
            }
            $db->commit();
        } catch(\Throwable $error) {
            if($db->inTransaction()) $db->rollBack();
            throw $error;
        }
    }

    /** Caller provisions an owner-only directory outside every website root. */
    public static function writeVerified(string $directory, array $snapshot, string $key): string
    {
        if(is_link($directory) || !is_dir($directory) || (fileperms($directory)&0077)!==0) throw new \RuntimeException('private_backup_directory_required');
        $archive=self::seal($snapshot,$key);
        $name='audyt-membership-'.gmdate('Ymd-His').'-'.bin2hex(random_bytes(8)).'.audytbackup';
        $temporary=tempnam($directory,'.audyt-backup-');
        if($temporary===false) throw new \RuntimeException('backup_write_failed');
        try {
            if(realpath(dirname($temporary))!==realpath($directory)) throw new \RuntimeException('backup_write_failed');
            chmod($temporary,0600);
            $file=fopen($temporary,'wb');
            if($file===false) throw new \RuntimeException('backup_write_failed');
            try {
                $position=0;
                while($position<strlen($archive)) {
                    $written=fwrite($file,substr($archive,$position));
                    if($written===false || $written===0) throw new \RuntimeException('backup_write_failed');
                    $position+=$written;
                }
                if(!fflush($file) || !fsync($file)) throw new \RuntimeException('backup_write_failed');
            } finally { fclose($file); }
            $stored=file_get_contents($temporary);
            if($stored===false || !hash_equals(hash('sha256',$archive),hash('sha256',$stored)) || self::open($stored,$key)!==$snapshot) throw new \RuntimeException('backup_verification_failed');
            if(!rename($temporary,$directory.'/'.$name)) throw new \RuntimeException('backup_write_failed');
            return $name;
        } finally { if(is_file($temporary)) unlink($temporary); }
    }
}
