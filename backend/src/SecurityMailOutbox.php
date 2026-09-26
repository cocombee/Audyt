<?php
declare(strict_types=1);
namespace Audyt;

final class SecurityMailOutbox
{
    public function __construct(private \PDO $db,private AuthenticationSecrets $secrets,private SecurityMailTransport $transport) {}
    public function drain(int $limit=10): array {
        if ($limit<1 || $limit>50) throw new \InvalidArgumentException('invalid_mail_batch');
        $accepted=0; $failed=0;
        for ($i=0;$i<$limit;$i++) {
            $this->db->beginTransaction();
            try {
                $row=$this->db->query("SELECT * FROM audyt_mail_outbox WHERE state='queued' AND next_attempt_at<=UTC_TIMESTAMP(6) ORDER BY created_at,id LIMIT 1 FOR UPDATE SKIP LOCKED")->fetch(\PDO::FETCH_ASSOC);
                if (!$row) { $this->db->commit(); break; }
                $state='queued'; $payload=$row['encrypted_payload']; $acceptedAt=null;
                if ($row['expires_at']<=gmdate('Y-m-d H:i:s')) { $state='cancelled'; $payload=null; }
                else {
                    try { $this->transport->send($row['id'],$this->secrets->open($payload)); $state='accepted'; $payload=null; $acceptedAt=gmdate('Y-m-d H:i:s'); $accepted++; }
                    catch (\Throwable $error) { $failed++; }
                }
                $delay=min(3600,60*(2**min(6,(int)$row['attempts'])));
                $s=$this->db->prepare('UPDATE audyt_mail_outbox SET state=?,encrypted_payload=?,attempts=attempts+1,next_attempt_at=?,accepted_at=? WHERE id=?');
                $s->execute([$state,$payload,gmdate('Y-m-d H:i:s',time()+$delay),$acceptedAt,$row['id']]);
                $this->db->commit();
            } catch (\Throwable $error) { if ($this->db->inTransaction()) $this->db->rollBack(); throw new \RuntimeException('mail_worker_unavailable'); }
        }
        return ['accepted'=>$accepted,'failed'=>$failed];
    }
}
