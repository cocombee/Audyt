<?php
declare(strict_types=1);
require __DIR__.'/../src/RegistrationInput.php';
use Audyt\RegistrationInput;
$profile = ['name'=>' Test Applicant ', 'email'=>' contact@example.test ', 'requestedRole'=>'director'];
$valid = RegistrationInput::profile($profile);
if ($valid !== ['name'=>'Test Applicant','email'=>'contact@example.test','requestedRole'=>'director']) {
    throw new RuntimeException('profile_normalization_failed');
}
$invalid = [ ['name'=>''], ['name'=>str_repeat('名',201)], ['name'=>"bad\nname"],
    ['name'=>"\xff"], ['email'=>'invalid'], ['email'=>null], ['requestedRole'=>'owner'],
    ['role'=>'director'], ['googleSubject'=>'forged'], ['verifiedEmail'=>'owner@example.test'] ];
foreach ($invalid as $override) {
    try { RegistrationInput::profile(array_replace($profile,$override)); }
    catch (DomainException $e) { continue; }
    throw new RuntimeException('unsafe_profile_accepted');
}
echo "11 registration input checks passed; database transitions require MariaDB integration tests\n";
