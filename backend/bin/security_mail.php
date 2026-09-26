<?php
declare(strict_types=1);
// CLI only. Configure one cPanel minute job after sender/delivery verification.
if (PHP_SAPI!=='cli') { http_response_code(404); exit; }
try {
    require dirname(__DIR__).'/vendor/autoload.php';
    $config=require dirname(__DIR__).'/config.local.php';
    if (($config['authenticationEnabled'] ?? false)!==true) throw new RuntimeException('authentication_not_enabled');
    $db=new PDO($config['dsn'],$config['databaseUser'],$config['databasePassword'],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_EMULATE_PREPARES=>false]);
    $secrets=new Audyt\AuthenticationSecrets(base64_decode($config['authenticationKey'],true),base64_decode($config['mailEncryptionKey'],true));
    $result=(new Audyt\SecurityMailOutbox($db,$secrets,new Audyt\LocalSecurityMailTransport($config['securityMailSender'])))->drain();
    echo json_encode($result,JSON_THROW_ON_ERROR).PHP_EOL;
    exit($result['failed']>0 ? 1 : 0);
} catch (Throwable $error) { fwrite(STDERR,"security_mail_failed\n"); exit(1); }
