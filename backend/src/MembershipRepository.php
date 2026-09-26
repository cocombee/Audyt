<?php
declare(strict_types=1);
namespace Audyt;

/** MariaDB/InnoDB adapter. Receives an actor ID only from verified authentication. */
final class MembershipRepository implements MembershipStore
{
    public function __construct(private \PDO $db)
    {
        $db->setAttribute(\PDO::ATTR_ERRMODE, \PDO::ERRMODE_EXCEPTION);
        $db->setAttribute(\PDO::ATTR_EMULATE_PREPARES, false);
    }

    /** Identity must be the result of GoogleIdentityVerifier, never request JSON. */
    public function register(string $businessId, array $verifiedIdentity, string $requestId, array $profile): array
    {
        CommandInput::validate($requestId, [0]);
        $profile = RegistrationInput::profile($profile);
        $subject = $verifiedIdentity['googleSubject'];
        $verifiedEmail = $verifiedIdentity['verifiedEmail'];
        $digest = hash('sha256', json_encode(['register', $profile], JSON_THROW_ON_ERROR));
        $this->db->beginTransaction();
        try {
            if ($this->query('SELECT id FROM audyt_businesses WHERE id=? FOR UPDATE', [$businessId])->fetchColumn() === false) {
                throw new \DomainException('business_not_found');
            }
            // The unique provider subject prevents duplicate identities across businesses.
            $this->query('INSERT INTO audyt_identities (id,google_subject,verified_google_email) VALUES (?,?,?) ON DUPLICATE KEY UPDATE verified_google_email=VALUES(verified_google_email)', [self::uuid(),$subject,$verifiedEmail]);
            $actorId = $this->query('SELECT id FROM audyt_identities WHERE google_subject=?', [$subject])->fetchColumn();
            $receipt = $this->query('SELECT payload_sha256,result_json FROM audyt_commands WHERE business_id=? AND actor_id=? AND request_id=?', [$businessId,$actorId,$requestId])->fetch(\PDO::FETCH_ASSOC);
            if ($receipt) {
                if (!hash_equals($receipt['payload_sha256'], $digest)) throw new \DomainException('request_id_reused');
                $result = json_decode($receipt['result_json'], true, 512, JSON_THROW_ON_ERROR);
                $this->db->commit();
                return $result;
            }
            $membership = $this->query('SELECT status,role,revision FROM audyt_memberships WHERE business_id=? AND identity_id=?', [$businessId,$actorId])->fetch(\PDO::FETCH_ASSOC);
            if (!$membership) {
                // Only an explicitly seeded, unbound owner allowlist can grant Director.
                // Contact email and requestedRole cannot satisfy this comparison.
                $bootstrap = $this->query('SELECT expected_verified_email,bound_identity_id FROM audyt_owner_bootstrap WHERE business_id=? FOR UPDATE', [$businessId])->fetch(\PDO::FETCH_ASSOC);
                $owner = $bootstrap && $bootstrap['bound_identity_id'] === null
                    && strcasecmp($bootstrap['expected_verified_email'], $verifiedEmail) === 0;
                $membership = ['status'=>$owner ? 'approved' : 'pending', 'role'=>$owner ? 'director' : null, 'revision'=>0];
                $this->query('INSERT INTO audyt_memberships (business_id,identity_id,display_name,contact_email,status,role,requested_role) VALUES (?,?,?,?,?,?,?)', [$businessId,$actorId,$profile['name'],$profile['email'],$membership['status'],$membership['role'],$profile['requestedRole']]);
                if ($owner) {
                    $this->query('UPDATE audyt_owner_bootstrap SET bound_identity_id=?,bound_at=CURRENT_TIMESTAMP(6) WHERE business_id=? AND bound_identity_id IS NULL', [$actorId,$businessId]);
                }
                $this->query('INSERT INTO audyt_access_events (business_id,actor_id,target_id,request_id,action,after_status,after_role,revision) VALUES (?,?,?,?,?,?,?,0)', [$businessId,$actorId,$actorId,$requestId,$owner ? 'bootstrap' : 'register',$membership['status'],$membership['role']]);
                $this->query('UPDATE audyt_businesses SET revision=revision+1 WHERE id=?', [$businessId]);
            }
            // Re-submitting never restores rejected/revoked access or overwrites a role.
            $membership['revision'] = (int)$membership['revision'];
            $result = ['requestId'=>$requestId, 'businessId'=>$businessId, 'identityId'=>$actorId, 'membership'=>$membership];
            $this->query('INSERT INTO audyt_commands (business_id,actor_id,request_id,payload_sha256,result_json) VALUES (?,?,?,?,?)', [$businessId,$actorId,$requestId,$digest,json_encode($result,JSON_THROW_ON_ERROR)]);
            $this->db->commit();
            return $result;
        } catch (\Throwable $error) {
            if ($this->db->inTransaction()) $this->db->rollBack();
            throw $error;
        }
    }

    /** Resolve only the authenticated subject's current membership, including revocation. */
    public function selfMembership(string $businessId, string $verifiedSubject): ?array
    {
        $row = $this->query('SELECT m.identity_id AS identityId,m.status,m.role,m.revision,b.bound_identity_id AS masterDirectorId FROM audyt_memberships m JOIN audyt_identities i ON i.id=m.identity_id LEFT JOIN audyt_owner_bootstrap b ON b.business_id=m.business_id WHERE m.business_id=? AND i.google_subject=?', [$businessId,$verifiedSubject])->fetch(\PDO::FETCH_ASSOC);
        if (!$row) return null;
        $row['revision'] = (int)$row['revision'];
        // UI capability context only; commands still re-authorize under lock.
        if ($row['status'] !== 'approved' || $row['role'] !== 'director') $row['masterDirectorId'] = null;
        return $row;
    }

    /** Durable in-app registration events. A cursor is not permission to approve. */
    public function notifications(string $businessId, string $actorId, int $after = 0, int $limit = 50): array
    {
        if ($after < 0 || $limit < 1 || $limit > 100) throw new \DomainException('invalid_page');
        $this->db->beginTransaction();
        try {
            if ($this->query('SELECT id FROM audyt_businesses WHERE id=? FOR UPDATE', [$businessId])->fetchColumn() === false) {
                throw new \DomainException('business_not_found');
            }
            $this->requireDirector($businessId,$actorId);
            $events = $this->query("SELECT e.sequence_id AS id,e.target_id AS userId,e.created_at AS createdAt,m.display_name AS name,m.status FROM audyt_access_events e JOIN audyt_memberships m ON m.business_id=e.business_id AND m.identity_id=e.target_id WHERE e.business_id=? AND e.action='register' AND e.sequence_id>? ORDER BY e.sequence_id ASC LIMIT $limit", [$businessId,$after])->fetchAll(\PDO::FETCH_ASSOC);
            $cursor = $after;
            foreach ($events as &$event) {
                $event['id'] = (int)$event['id'];
                $cursor = $event['id'];
            }
            unset($event);
            $this->db->commit();
            return ['events'=>$events,'nextCursor'=>$cursor];
        } catch (\Throwable $error) {
            if ($this->db->inTransaction()) $this->db->rollBack();
            throw $error;
        }
    }

    private static function uuid(): string
    {
        $bytes = random_bytes(16);
        $bytes[6] = chr((ord($bytes[6]) & 15) | 64);
        $bytes[8] = chr((ord($bytes[8]) & 63) | 128);
        $hex = bin2hex($bytes);
        return substr($hex,0,8).'-'.substr($hex,8,4).'-'.substr($hex,12,4).'-'.substr($hex,16,4).'-'.substr($hex,20);
    }

    /** Director-only page; total is unfiltered so the client can show search above ten users. */
    public function directory(string $businessId, string $actorId,
        int $offset = 0, int $limit = 10, string $search = ''): array
    {
        if ($offset < 0 || $offset > 1000000 || !in_array($limit, [10, 20, 50, 100], true)
            || strlen($search) > 640 || preg_match('//u', $search) !== 1) {
            throw new \DomainException('invalid_page');
        }
        $this->db->beginTransaction();
        try {
            // Serialize with membership changes, including revoking this Director.
            $revision = $this->query('SELECT revision FROM audyt_businesses WHERE id=? FOR UPDATE', [$businessId])->fetchColumn();
            if ($revision === false) throw new \DomainException('business_not_found');
            $this->requireDirector($businessId, $actorId);
            $counts = $this->query("SELECT COUNT(*) AS total, COALESCE(SUM(status='pending'),0) AS pending FROM audyt_memberships WHERE business_id=? AND status<>'revoked'", [$businessId])->fetch(\PDO::FETCH_ASSOC);
            $where = "business_id=? AND status<>'revoked'";
            $values = [$businessId];
            $search = trim($search);
            if ($search !== '') {
                // Treat %, _ and the escape character literally, not as search wildcards.
                $pattern = '%' . strtr($search, ['!'=>'!!', '%'=>'!%', '_'=>'!_']) . '%';
                $where .= " AND (display_name LIKE ? ESCAPE '!' OR contact_email LIKE ? ESCAPE '!')";
                array_push($values, $pattern, $pattern);
            }
            $matched = (int)$this->query("SELECT COUNT(*) FROM audyt_memberships WHERE $where", $values)->fetchColumn();
            // Integers are validated above; all user text remains bound parameters.
            $rows = $this->query("SELECT identity_id AS id,display_name AS name,contact_email AS email,status,role,requested_role AS requestedRole,revision,submitted_at AS submittedAt FROM audyt_memberships WHERE $where ORDER BY submitted_at DESC,identity_id ASC LIMIT $limit OFFSET $offset", $values)->fetchAll(\PDO::FETCH_ASSOC);
            foreach ($rows as &$row) $row['revision'] = (int)$row['revision'];
            unset($row);
            $result = ['businessId'=>$businessId, 'revision'=>(int)$revision,
                'total'=>(int)$counts['total'], 'pendingCount'=>(int)$counts['pending'],
                'matched'=>$matched, 'offset'=>$offset, 'limit'=>$limit, 'users'=>$rows];
            $this->db->commit();
            return $result;
        } catch (\Throwable $error) {
            if ($this->db->inTransaction()) $this->db->rollBack();
            throw $error;
        }
    }

    /** Apply one bounded batch and its audit events atomically. */
    public function command(string $businessId, string $actorId, string $requestId,
        array $expectedRevisions, string $action, ?string $role = null): array
    {
        CommandInput::validate($requestId, $expectedRevisions);
        ksort($expectedRevisions);
        $digest = hash('sha256', json_encode([$action, $role, $expectedRevisions], JSON_THROW_ON_ERROR));
        $this->db->beginTransaction();
        try {
            // All membership writers, including bootstrap/registration, take this lock.
            $business = $this->query('SELECT id FROM audyt_businesses WHERE id=? FOR UPDATE', [$businessId])->fetchColumn();
            if (!$business) throw new \DomainException('business_not_found');
            $this->requireDirector($businessId, $actorId);
            $masterId = $this->query('SELECT bound_identity_id FROM audyt_owner_bootstrap WHERE business_id=?', [$businessId])->fetchColumn();
            // Even idempotent retries require current Director authority.
            $receipt = $this->query('SELECT payload_sha256,result_json FROM audyt_commands WHERE business_id=? AND actor_id=? AND request_id=?', [$businessId,$actorId,$requestId])->fetch(\PDO::FETCH_ASSOC);
            if ($receipt) {
                if (!hash_equals($receipt['payload_sha256'], $digest)) throw new \DomainException('request_id_reused');
                $result = json_decode($receipt['result_json'], true, 512, JSON_THROW_ON_ERROR);
                $this->db->commit();
                return $result;
            }
            // Include approved Directors to evaluate the resulting invariant.
            $ids = array_unique([$actorId, ...array_keys($expectedRevisions)]);
            $placeholders = implode(',', array_fill(0, count($ids), '?'));
            $rows = $this->query("SELECT identity_id,business_id,status,role,revision FROM audyt_memberships WHERE business_id=? AND (identity_id IN ($placeholders) OR (status='approved' AND role='director'))", [$businessId,...$ids])->fetchAll(\PDO::FETCH_ASSOC);
            $members = [];
            foreach ($rows as $row) {
                $members[$row['identity_id']] = ['businessId'=>$row['business_id'], 'status'=>$row['status'], 'role'=>$row['role'], 'revision'=>(int)$row['revision']];
            }
            $changes = MembershipPolicy::decide($businessId,$actorId,$members,$expectedRevisions,$action,$role,is_string($masterId) ? $masterId : null);
            foreach ($changes as $id => $next) {
                $before = $members[$id];
                $updated = $this->query('UPDATE audyt_memberships SET status=?,role=?,revision=?,updated_at=CURRENT_TIMESTAMP(6) WHERE business_id=? AND identity_id=? AND revision=?', [$next['status'],$next['role'],$next['revision'],$businessId,$id,$before['revision']]);
                if ($updated->rowCount() !== 1) throw new \DomainException('stale_revision');
                $this->query('INSERT INTO audyt_access_events (business_id,actor_id,target_id,request_id,action,before_status,after_status,before_role,after_role,revision) VALUES (?,?,?,?,?,?,?,?,?,?)', [$businessId,$actorId,$id,$requestId,$action,$before['status'],$next['status'],$before['role'],$next['role'],$next['revision']]);
            }
            $result = ['requestId'=>$requestId,'memberships'=>$changes];
            $this->query('INSERT INTO audyt_commands (business_id,actor_id,request_id,payload_sha256,result_json) VALUES (?,?,?,?,?)', [$businessId,$actorId,$requestId,$digest,json_encode($result,JSON_THROW_ON_ERROR)]);
            $this->query('UPDATE audyt_businesses SET revision=revision+1 WHERE id=?', [$businessId]);
            $this->db->commit();
            return $result;
        } catch (\Throwable $error) {
            if ($this->db->inTransaction()) $this->db->rollBack();
            throw $error;
        }
    }

    private function requireDirector(string $businessId, string $actorId): void
    {
        $actor = $this->query('SELECT status,role FROM audyt_memberships WHERE business_id=? AND identity_id=?', [$businessId, $actorId])->fetch(\PDO::FETCH_ASSOC);
        if (!$actor || $actor['status'] !== 'approved' || $actor['role'] !== 'director') {
            throw new \DomainException('director_required');
        }
    }

    private function query(string $sql, array $values): \PDOStatement
    {
        $statement = $this->db->prepare($sql);
        $statement->execute($values);
        return $statement;
    }
}
