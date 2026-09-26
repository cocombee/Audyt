<?php
declare(strict_types=1);
require __DIR__.'/../vendor/autoload.php';
use Audyt\RequestRateLimiter;
$directory=sys_get_temp_dir().'/audyt-rate-test-'.bin2hex(random_bytes(8));
mkdir($directory,0700);
$key=random_bytes(32);
$count=0;
$check=function(bool $condition) use (&$count) { if (!$condition) throw new RuntimeException('rate_assertion_failed'); $count++; };
try {
    $limiter=new RequestRateLimiter($directory,$key);
    for ($i=0;$i<60;$i++) $check($limiter->allow('192.0.2.1',120));
    $check(!$limiter->allow('192.0.2.1',120));
    $otherWorker=new RequestRateLimiter($directory,$key);
    $check(!$otherWorker->allow('192.0.2.1',120));
    $check($otherWorker->allow('192.0.2.2',120));
    $check($otherWorker->allow('192.0.2.1',180));
    for ($i=0;$i<599;$i++) {
        if (!$limiter->allow('fixture-'.$i,180)) throw new RuntimeException('premature_global_limit');
    }
    $check(!$limiter->allow('new-client',180));
    $raw=file_get_contents($directory.'/requests.json');
    $check(!str_contains($raw,'192.0.2.') && !str_contains($raw,'fixture-'));
    $check(strlen($raw)<100000);
    $check((fileperms($directory.'/requests.json')&0077)===0);
    $lock=fopen($directory.'/requests.json','r+');
    flock($lock,LOCK_EX);
    try { $limiter->allow('client',180); throw new LogicException('lock_bypass'); }
    catch (RuntimeException $error) { $check($error->getMessage()==='rate_cache_busy'); }
    finally { flock($lock,LOCK_UN); fclose($lock); }
    file_put_contents($directory.'/requests.json','broken-json');
    try { $limiter->allow('client',180); throw new LogicException('corruption_bypass'); }
    catch (JsonException $error) { $check(true); }
    echo "$count rate-limiter checks passed\n";
} finally {
    foreach (glob($directory.'/*') as $file) unlink($file);
    rmdir($directory);
}
