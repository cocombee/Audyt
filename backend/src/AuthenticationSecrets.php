<?php
declare(strict_types=1);
namespace Audyt;

/** Server-only keyed password/challenge hashing and authenticated mail sealing. */
final class AuthenticationSecrets
{
    public function __construct(private string $key, private string $mailKey) {
        if (strlen($key)<32 || strlen($mailKey)!==32 || hash_equals($key,$mailKey)) throw new \InvalidArgumentException('invalid_authentication_keys');
    }
    public function digest(string $kind,string $value): string { return hash_hmac('sha256',$kind.':'.$value,$this->key); }
    public function password(string $value): string {
        if (preg_match('//u',$value)!==1 || mb_strlen($value)<15 || mb_strlen($value)>128 || str_contains($value,"\0")) throw new \DomainException('weak_password');
        $algorithm=defined('PASSWORD_ARGON2ID') ? PASSWORD_ARGON2ID : PASSWORD_BCRYPT;
        $options=$algorithm===PASSWORD_BCRYPT ? ['cost'=>12] : ['memory_cost'=>19456,'time_cost'=>2,'threads'=>1];
        // Keyed fixed-size prehash also prevents bcrypt's 72-byte truncation.
        return password_hash($this->digest('password',$value),$algorithm,$options);
    }
    public function matches(string $password,string $hash): bool {
        if (strlen($password)>1024) $password='invalid-oversized';
        return password_verify($this->digest('password',$password),$hash);
    }
    public function seal(array $value): string {
        $nonce=random_bytes(12); $tag='';
        $data=openssl_encrypt(json_encode($value,JSON_THROW_ON_ERROR),'aes-256-gcm',$this->mailKey,OPENSSL_RAW_DATA,$nonce,$tag,'audyt-mail-v1');
        if ($data===false) throw new \RuntimeException('mail_sealing_failed');
        return base64_encode($nonce.$tag.$data);
    }
    public function open(string $sealed): array {
        $bytes=base64_decode($sealed,true);
        if ($bytes===false || strlen($bytes)<29) throw new \RuntimeException('invalid_mail_payload');
        $plain=openssl_decrypt(substr($bytes,28),'aes-256-gcm',$this->mailKey,OPENSSL_RAW_DATA,substr($bytes,0,12),substr($bytes,12,16),'audyt-mail-v1');
        if ($plain===false) throw new \RuntimeException('invalid_mail_payload');
        $value=json_decode($plain,true,8,JSON_THROW_ON_ERROR);
        if (!is_array($value) || array_is_list($value)) throw new \RuntimeException('invalid_mail_payload');
        return $value;
    }
}
