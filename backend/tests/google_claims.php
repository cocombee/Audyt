<?php
declare(strict_types=1);
require __DIR__ . '/../src/VerifiedGoogleClaims.php';
use Audyt\VerifiedGoogleClaims;
$claims = ['aud'=>'audyt-client','iss'=>'https://accounts.google.com', 'sub'=>'1234567',
    'email'=>'owner@example.test','email_verified'=>true,'iat'=>1000,'exp'=>2000,'role'=>'director'];
$identity = VerifiedGoogleClaims::identity($claims, 'audyt-client', 1500);
if ($identity !== ['googleSubject'=>'1234567','verifiedEmail'=>'owner@example.test','authoritativeEmail'=>false]) {
    throw new RuntimeException('Unexpected identity or role leakage');
}
$invalid = [ ['aud'=>'other-client'], ['iss'=>'https://attacker.example'], ['exp'=>1500],
    ['exp'=>'2000'], ['iat'=>1561], ['email_verified'=>false], ['email_verified'=>'true'],
    ['sub'=>''], ['sub'=>"123\n"], ['email'=>"owner@example.test\n"] ];
foreach ($invalid as $override) {
    try { VerifiedGoogleClaims::identity(array_replace($claims,$override), 'audyt-client',1500); }
    catch (DomainException $e) { continue; }
    throw new RuntimeException('Expected rejection: '.json_encode(array_keys($override)));
}
echo "11 claim checks passed (signature verification is not covered by this test)\n";
