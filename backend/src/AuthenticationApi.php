<?php
declare(strict_types=1);
namespace Audyt;

final class AuthenticationApi
{
    public function __construct(private AuthenticationRepository $store,private IdentityVerifier $google) {}
    public function handle(string $method,string $path,string $authorization='',string $body=''): array {
        $started=microtime(true); $neutral=false;
        try {
            if (!preg_match('#^/v1/auth/(register|sign-in|forgot-password|resend|verify|reset-password|google|session|sign-out|change-password)$#D',$path,$match)) return self::error(404,'not_found');
            if ($method!=='POST') return self::error(405,'method_not_allowed');
            if (strlen($body)>32768) return self::error(413,'request_too_large');
            $input=json_decode($body,true,8,JSON_THROW_ON_ERROR);
            if (!is_array($input) || (array_is_list($input) && $input!==[])) throw new \DomainException('invalid_credentials');
            $action=$match[1];
            $fields=match($action) {
                'register'=>['name','email','phone','password','termsVersion'],
                'sign-in'=>['email','password'], 'forgot-password'=>['email'],
                'resend'=>['challengeId'], 'verify'=>['challengeId','code'],
                'reset-password'=>['challengeId','code','password'], 'google'=>['idToken','termsVersion'],
                'change-password'=>['currentPassword','password'], default=>[],
            };
            if (array_diff(array_keys($input),$fields)) throw new \DomainException('invalid_credentials');
            foreach ($fields as $field) {
                if (!is_string($input[$field] ?? null) || strlen($input[$field])>16384 || preg_match('//u',$input[$field])!==1) throw new \DomainException('invalid_credentials');
            }
            $token='';
            if (in_array($action,['session','sign-out','change-password'],true)) {
                if (!preg_match('/^Bearer (audyt_[a-f0-9]{64})$/D',$authorization,$matches)) throw new \DomainException('authentication_required');
                $token=$matches[1];
            }
            $neutral=in_array($action,['forgot-password','register'],true);
            $result=match($action) {
                'register'=>$this->store->register($input['name'],$input['email'],$input['phone'],$input['password'],$input['termsVersion']),
                'sign-in'=>$this->store->signIn($input['email'],$input['password']),
                'forgot-password'=>$this->store->forgotPassword($input['email']),
                'resend'=>$this->store->resend($input['challengeId']),
                'verify'=>$this->store->verify($input['challengeId'],$input['code']),
                'reset-password'=>$this->store->resetPassword($input['challengeId'],$input['code'],$input['password']),
                'google'=>$this->store->google($this->google->verify($input['idToken']),$input['termsVersion']),
                'session'=>$this->store->session($token), 'sign-out'=>$this->store->signOut($token),
                'change-password'=>$this->store->changePassword($token,$input['currentPassword'],$input['password']),
            };
            return ['status'=>200,'body'=>$result];
        } catch (\DomainException $error) {
            $code=$error->getMessage();
            if ($code==='invalid_google_token') $code='authentication_required';
            $safe=['invalid_credentials','invalid_code','rate_limited','authentication_required','password_required','weak_password','link_conflict','terms_required'];
            if (!in_array($code,$safe,true)) $code='service_unavailable';
            return self::error(match($code) {'rate_limited'=>429,'authentication_required','invalid_credentials'=>401,'service_unavailable'=>503,default=>400},$code);
        } catch (\JsonException $error) { return self::error(400,'invalid_credentials'); }
        catch (\Throwable $error) { return self::error(503,'service_unavailable'); }
        finally {
            // Known and unknown registration/recovery requests do comparable
            // work. A floor hides small outbox-write timing differences.
            if ($neutral) { $remaining=200000-(int)((microtime(true)-$started)*1000000); if ($remaining>0) usleep($remaining); }
        }
    }
    private static function error(int $status,string $code): array { return ['status'=>$status,'body'=>['error'=>$code]]; }
}
