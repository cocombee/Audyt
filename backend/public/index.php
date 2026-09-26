<?php
declare(strict_types=1);

// Configure this public directory as the ONLY web root of the isolated API.
ini_set('display_errors','0');
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');
$send=static function(int $status,array $body): never {
    http_response_code($status);
    echo json_encode($body,JSON_THROW_ON_ERROR);
    exit;
};
try {
    if (($_SERVER['HTTPS'] ?? '')!=='on') $send(426,['error'=>'https_required']);
    require dirname(__DIR__).'/vendor/autoload.php';
    $config=require dirname(__DIR__).'/config.local.php';
    $limiter=new Audyt\RequestRateLimiter($config['rateDirectory'],$config['rateKey']);
    // Only the server's peer address is trusted, not forwarded client headers.
    $peer=$_SERVER['REMOTE_ADDR'] ?? '';
    if (filter_var($peer,FILTER_VALIDATE_IP)===false) $send(400,['error'=>'invalid_client']);
    if (!$limiter->allow($peer)) {
        header('Retry-After: 60');
        $send(429,['error'=>'rate_limited']);
    }
    if ((int)($_SERVER['CONTENT_LENGTH'] ?? 0)>65536) $send(413,['error'=>'request_too_large']);
    $method=$_SERVER['REQUEST_METHOD'] ?? '';
    if ($method==='POST' && strtolower(trim(explode(';',$_SERVER['CONTENT_TYPE'] ?? '')[0]))!=='application/json') {
        $send(415,['error'=>'json_required']);
    }
    $body=file_get_contents('php://input',false,null,0,65537);
    if ($body===false) $send(400,['error'=>'invalid_request']);
    if (strlen($body)>65536) $send(413,['error'=>'request_too_large']);
    $db=new PDO($config['dsn'],$config['databaseUser'],$config['databasePassword'],[
        PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_EMULATE_PREPARES=>false,
        PDO::ATTR_TIMEOUT=>5,
    ]);
    $google=Audyt\GoogleIdentityVerifier::forHosting($config['googleAudience'],$config['certificateDirectory']);
    $path=parse_url($_SERVER['REQUEST_URI'] ?? '',PHP_URL_PATH) ?: '';
    $identity=$google;
    $authentication=null;
    if (($config['authenticationEnabled'] ?? false)===true) {
        if (empty($config['securityMailSender'])) $send(503,['error'=>'service_unavailable']);
        $secrets=new Audyt\AuthenticationSecrets(base64_decode($config['authenticationKey'],true),base64_decode($config['mailEncryptionKey'],true));
        $authentication=new Audyt\AuthenticationRepository($db,$secrets,$config['passwordDummyHash'],$config['termsVersion']);
        $identity=new Audyt\AuthenticatedIdentityVerifier($google,$authentication);
    }
    if (str_starts_with($path,'/v1/auth/')) {
        if ($authentication===null || $_GET!==[]) $send(503,['error'=>'service_unavailable']);
        $result=(new Audyt\AuthenticationApi($authentication,$google))->handle($method,$path,$_SERVER['HTTP_AUTHORIZATION'] ?? '',$body);
        $send($result['status'],$result['body']);
    }
    $api=new Audyt\MembershipApi($identity,new Audyt\MembershipRepository($db));
    $result=$api->handle($method,$path,
        $_SERVER['HTTP_AUTHORIZATION'] ?? '',$body,$_GET);
    $send($result['status'],$result['body']);
} catch (Throwable $error) {
    // Never send or log exception content containing SQL or authentication data.
    $send(503,['error'=>'service_unavailable']);
}
