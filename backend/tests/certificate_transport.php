<?php
declare(strict_types=1);
require __DIR__.'/../vendor/autoload.php';
use Audyt\GoogleCertificateTransport;
use Google\Auth\AccessToken;
use GuzzleHttp\Psr7\Request;
use GuzzleHttp\Psr7\Response;
$directory = sys_get_temp_dir().'/audyt-cert-test-'.bin2hex(random_bytes(8));
mkdir($directory,0700);
$request = new Request('GET',AccessToken::FEDERATED_SIGNON_CERT_URL);
$body = json_encode(['keys'=>[['kty'=>'RSA','alg'=>'RS256','kid'=>'test','n'=>'test-n','e'=>'AQAB']]]);
$checks = 0;
$assert = function(bool $value) use (&$checks) { if (!$value) throw new RuntimeException('assertion_failed'); $checks++; };
$denied = function(callable $action) use ($assert) {
    try { $action(); } catch (RuntimeException $e) { $assert(true); return; }
    throw new RuntimeException('expected_rejection');
};
try {
    $fetches = 0;
    $fetch = function() use (&$fetches,$body) { $fetches++; return new Response(200,['Cache-Control'=>'public, max-age=7200','Age'=>'100'],$body); };
    $one = new GoogleCertificateTransport($directory,$fetch);
    $assert((string)$one($request)->getBody() === $body);
    $two = new GoogleCertificateTransport($directory,$fetch);
    $assert((string)$two($request)->getBody() === $body && $fetches === 1);
    $assert((fileperms($directory.'/google-certificates.json') & 0077) === 0);
    $cache = json_decode(file_get_contents($directory.'/google-certificates.json'),true);
    $assert($cache['expires'] <= time()+3600);
    $denied(fn() => $one(new Request('GET','https://attacker.example/certs')));
    $denied(fn() => $one(new Request('POST',AccessToken::FEDERATED_SIGNON_CERT_URL)));
    $cache['expires'] = time()-1;
    file_put_contents($directory.'/google-certificates.json',json_encode($cache));
    $offline = new GoogleCertificateTransport($directory,static function() { throw new RuntimeException('offline'); });
    $denied(fn() => $offline($request)); // Never accept expired keys when unavailable.
    foreach ([new Response(302,['Location'=>'https://attacker.example']),new Response(200,[],str_repeat('x',65537)),new Response(200,[],'{}')] as $response) {
        $transport = new GoogleCertificateTransport($directory,fn()=>$response);
        $denied(fn() => $transport($request));
    }
    unlink($directory.'/google-certificates.json');
    $uncached = new GoogleCertificateTransport($directory,fn()=>new Response(200,['Cache-Control'=>'no-store, max-age=1000'],$body));
    $assert($uncached($request)->getHeaderLine('Cache-Control') === 'max-age=0');
    $assert(!is_file($directory.'/google-certificates.json'));
    echo "$checks certificate transport checks passed\n";
} finally {
    foreach (glob($directory.'/*') as $file) unlink($file);
    rmdir($directory);
}
