<?php
declare(strict_types=1);
namespace Audyt;

/** Single-host shared limiter. Fixed global bound prevents unbounded client keys. */
final class RequestRateLimiter
{
    public function __construct(private string $directory, private string $key)
    {
        if (strlen($key)<32 || !is_dir($directory) || is_link($directory)
            || (fileperms($directory)&0077)!==0) throw new \InvalidArgumentException('private_rate_config_required');
    }

    public function allow(string $client, ?int $now=null): bool
    {
        $path=$this->directory.'/requests.json';
        if (is_link($path)) throw new \RuntimeException('unsafe_rate_cache');
        $file=fopen($path,'c+');
        if ($file===false) throw new \RuntimeException('rate_cache_unavailable');
        chmod($path,0600);
        try {
            if (!flock($file,LOCK_EX|LOCK_NB)) throw new \RuntimeException('rate_cache_busy');
            $window=intdiv($now ?? time(),60);
            $raw=stream_get_contents($file,100001);
            if (strlen($raw)>100000) throw new \RuntimeException('invalid_rate_cache');
            $data=$raw==='' ? null : json_decode($raw,true,8,JSON_THROW_ON_ERROR);
            if ($data===null || ($data['window'] ?? null)!==$window) $data=['window'=>$window,'total'=>0,'clients'=>[]];
            if (!is_int($data['total'] ?? null) || !is_array($data['clients'] ?? null)) throw new \RuntimeException('invalid_rate_cache');
            $id=hash_hmac('sha256',$client,$this->key);
            $count=$data['clients'][$id] ?? 0;
            if (!is_int($count)) throw new \RuntimeException('invalid_rate_cache');
            if ($data['total']>=600 || $count>=60) return false;
            $data['total']++;
            $data['clients'][$id]=$count+1;
            $encoded=json_encode($data,JSON_THROW_ON_ERROR);
            rewind($file);
            if (fwrite($file,$encoded)!==strlen($encoded) || !ftruncate($file,strlen($encoded)) || !fflush($file)) throw new \RuntimeException('rate_cache_unavailable');
            return true;
        } finally { flock($file,LOCK_UN); fclose($file); }
    }
}
