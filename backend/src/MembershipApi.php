<?php
declare(strict_types=1);
namespace Audyt;

/** Transport-neutral HTTP boundary. Runtime supplies HTTPS and rate limiting. */
final class MembershipApi
{
    public function __construct(private IdentityVerifier $identity, private MembershipStore $store) {}

    /** @return array{status:int,body:array} */
    public function handle(string $method, string $path, string $authorization, string $body = '', array $query = []): array
    {
        try {
            if (strlen($body) > 65536) return self::error(413,'request_too_large');
            if (!preg_match('#^/v1/businesses/([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})/(self|registrations|users|commands|notifications)$#D',$path,$route)) {
                return self::error(404,'not_found');
            }
            [$unused,$business,$resource] = $route;
            $expectedMethod = in_array($resource,['registrations','commands'],true) ? 'POST' : 'GET';
            if ($method !== $expectedMethod) return self::error(405,'method_not_allowed');
            if (strlen($authorization) > 16400 || !preg_match('/^Bearer ([A-Za-z0-9_.-]+)$/D',$authorization,$bearer)) {
                return self::error(401,'authentication_required');
            }
            $identity = $this->identity->verify($bearer[1]);
            if ($method === 'POST') {
                $input = json_decode($body, true, 8, JSON_THROW_ON_ERROR);
                if (!is_array($input) || array_is_list($input) || $query !== []) throw new \DomainException('invalid_request');
            } else {
                if ($body !== '') throw new \DomainException('invalid_request');
                $input = [];
            }
            if ($resource === 'registrations') {
                self::fields($input,['requestId','profile']);
                if (!is_string($input['requestId'] ?? null) || !is_array($input['profile'] ?? null)) throw new \DomainException('invalid_request');
                return self::ok($this->store->register($business,$identity,$input['requestId'],$input['profile']));
            }
            // Caller IDs, role labels and contact emails never select the actor.
            $actor = $this->store->selfMembership($business,$identity['googleSubject']);
            if ($resource === 'self') {
                if ($query !== []) throw new \DomainException('invalid_request');
                return self::ok(['membership'=>$actor]);
            }
            if (!$actor || $actor['status'] !== 'approved' || $actor['role'] !== 'director') return self::error(403,'director_required');
            if ($resource === 'users') {
                self::fields($query,['offset','limit','search']);
                if (isset($query['search']) && !is_string($query['search'])) throw new \DomainException('invalid_request');
                return self::ok($this->store->directory($business,$actor['identityId'],self::integer($query,'offset',0),self::integer($query,'limit',10),$query['search'] ?? ''));
            }
            if ($resource === 'notifications') {
                self::fields($query,['after','limit']);
                return self::ok($this->store->notifications($business,$actor['identityId'],self::integer($query,'after',0),self::integer($query,'limit',50)));
            }
            self::fields($input,['requestId','expectedRevisions','action','role']);
            if (!is_string($input['requestId'] ?? null) || !is_array($input['expectedRevisions'] ?? null)
                || !is_string($input['action'] ?? null) || (isset($input['role']) && !is_string($input['role']))) throw new \DomainException('invalid_request');
            // Repository repeats authorization under lock, closing revocation races.
            return self::ok($this->store->command($business,$actor['identityId'],$input['requestId'],$input['expectedRevisions'],$input['action'],$input['role'] ?? null));
        } catch (\JsonException $error) {
            return self::error(400,'invalid_json');
        } catch (\DomainException $error) {
            $code=$error->getMessage();
            $status=match ($code) {
                'invalid_google_token','authentication_required'=>401,
                'google_verification_unavailable'=>503,
                'director_required','master_director_required','master_director_protected','self_access_change'=>403,
                'business_not_found','member_not_found'=>404,
                'stale_revision','request_id_reused','pending_required','approved_required','already_revoked','last_director'=>409,
                default=>400,
            };
            $safe = preg_match('/^[a-z_]{1,64}$/D',$code) ? $code : 'invalid_request';
            return self::error($status,$safe);
        } catch (\Throwable $error) {
            // Never disclose SQL, credentials, provider responses or bearer tokens.
            return self::error(503,'service_unavailable');
        }
    }

    private static function fields(array $input,array $allowed): void
    {
        if (array_diff(array_keys($input),$allowed)) throw new \DomainException('unknown_field');
    }

    private static function integer(array $input,string $key,int $default): int
    {
        if (!array_key_exists($key,$input)) return $default;
        $value=$input[$key];
        if (!is_string($value) || !preg_match('/^(0|[1-9][0-9]{0,9})$/D',$value)) throw new \DomainException('invalid_page');
        return (int)$value;
    }

    private static function ok(array $body): array { return ['status'=>200,'body'=>$body]; }
    private static function error(int $status,string $code): array { return ['status'=>$status,'body'=>['error'=>$code]]; }
}
