<?php
declare(strict_types=1);
require __DIR__.'/../vendor/autoload.php';
use Audyt\{IdentityVerifier,MembershipStore,MembershipApi};
$verifier=new class implements IdentityVerifier {
    public function verify(string $token): array {
        if ($token !== 'valid.token.fixture') throw new DomainException('invalid_google_token');
        return ['googleSubject'=>'verified-subject','verifiedEmail'=>'login@example.test'];
    }
};
$store=new class implements MembershipStore {
    public ?array $actor=['identityId'=>'server-actor','status'=>'approved','role'=>'director','revision'=>0];
    public array $calls=[];
    public function selfMembership(string $businessId,string $verifiedSubject): ?array {
        if ($verifiedSubject !== 'verified-subject') throw new RuntimeException('unverified_subject');
        return $this->actor;
    }
    public function register(string $businessId,array $verifiedIdentity,string $requestId,array $profile): array {
        $this->calls[]=['register',$verifiedIdentity]; return ['registered'=>true];
    }
    public function directory(string $businessId,string $actorId,int $offset=0,int $limit=10,string $search=''): array {
        $this->calls[]=['users',$actorId]; return ['users'=>[]];
    }
    public function notifications(string $businessId,string $actorId,int $after=0,int $limit=50): array {
        $this->calls[]=['notifications',$actorId]; return ['events'=>[]];
    }
    public function command(string $businessId,string $actorId,string $requestId,array $expectedRevisions,string $action,?string $role=null): array {
        $this->calls[]=['command',$actorId];
        if ($requestId === 'stale') throw new DomainException('stale_revision');
        if ($requestId === 'error') throw new RuntimeException('secret SQL/password details');
        return ['accepted'=>true];
    }
};
$api=new MembershipApi($verifier,$store);
$root='/v1/businesses/00000000-0000-4000-8000-000000000001/';
$auth='Bearer valid.token.fixture';
$count=0;
$check=function(array $result,int $status) use (&$count) {
    if ($result['status'] !== $status) throw new RuntimeException(json_encode($result)); $count++;
};
$check($api->handle('GET',$root.'users',''),401);
$check($api->handle('GET',$root.'users','Bearer forged.token.fixture'),401);
$check($api->handle('POST',$root.'users',$auth),405);
$check($api->handle('GET','/wrong',$auth),404);
$check($api->handle('POST',$root.'registrations',$auth,str_repeat('x',65537)),413);
$check($api->handle('POST',$root.'registrations',$auth,'{'),400);
$check($api->handle('GET',$root.'users',$auth,'',['actorId'=>'forged']),400);
$check($api->handle('GET',$root.'users',$auth,'',['offset'=>['0']]),400);
$command=['requestId'=>'test','expectedRevisions'=>['target'=>0],'action'=>'approve','role'=>'employee'];
$check($api->handle('POST',$root.'commands',$auth,json_encode($command+['actorId'=>'master'])),400);
$store->actor=['identityId'=>'accountant','status'=>'approved','role'=>'accountant','revision'=>0];
foreach (['users','notifications','commands'] as $resource) {
    $check($api->handle($resource==='commands'?'POST':'GET',$root.$resource,$auth,$resource==='commands'?json_encode($command):''),403);
}
if ($store->calls !== []) throw new RuntimeException('unauthorized_repository_call');
$store->actor=null;
$check($api->handle('GET',$root.'users',$auth),403);
$check($api->handle('GET',$root.'self',$auth),200);
$store->actor=['identityId'=>'server-actor','status'=>'approved','role'=>'director','revision'=>0];
$check($api->handle('GET',$root.'users',$auth),200);
$check($api->handle('POST',$root.'commands',$auth,json_encode($command)),200);
if ($store->calls !== [['users','server-actor'],['command','server-actor']]) throw new RuntimeException('actor_not_server_derived');
$command['requestId']='stale';
$check($api->handle('POST',$root.'commands',$auth,json_encode($command)),409);
$command['requestId']='error';
$error=$api->handle('POST',$root.'commands',$auth,json_encode($command));
$check($error,503);
if ($error['body'] !== ['error'=>'service_unavailable']) throw new RuntimeException('private_error_leak');
echo "$count API boundary checks passed with isolated store doubles\n";
