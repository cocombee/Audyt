<?php
declare(strict_types=1);
// CLI-only cron entrypoint. Configure PHP CLI, private credentials and key first.
if(PHP_SAPI!=='cli') { http_response_code(404); exit; }
ini_set('display_errors','0');
umask(0077);
require dirname(__DIR__).'/vendor/autoload.php';
$lock=null;
try {
    $config=require dirname(__DIR__).'/config.local.php';
    $directory=dirname(__DIR__).'/var/backups';
    if(is_link($directory) || !is_dir($directory) || (fileperms($directory)&0077)!==0) throw new RuntimeException();
    $lockPath=$directory.'/.backup.lock';
    if(is_link($lockPath)) throw new RuntimeException();
    $lock=fopen($lockPath,'c');
    if($lock===false || !flock($lock,LOCK_EX|LOCK_NB)) throw new RuntimeException();
    chmod($lockPath,0600);
    if(($config['databasePassword'] ?? '')==='') throw new RuntimeException();
    $db=new PDO($config['dsn'],$config['databaseUser'],$config['databasePassword'],[
        PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_EMULATE_PREPARES=>false,PDO::ATTR_TIMEOUT=>5,
    ]);
    $snapshot=Audyt\MembershipBackup::snapshot($db);
    $filename=Audyt\MembershipBackup::writeVerified($directory,$snapshot,$config['backupKey'] ?? '');
    // Keep 14 successful daily runs. Only this tool's exact generated filenames qualify.
    $files=[];
    foreach(new DirectoryIterator($directory) as $file) {
        if(!$file->isLink() && $file->isFile() && $file->getFilename()!==$filename && preg_match('/^audyt-membership-\d{8}-\d{6}-[a-f0-9]{16}\.audytbackup$/D',$file->getFilename())) $files[]=$file->getFilename();
    }
    rsort($files,SORT_STRING);
    foreach(array_slice($files,13) as $old) if(!unlink($directory.'/'.$old)) throw new RuntimeException();
    echo gmdate('c')." backup_ok $filename\n";
} catch(Throwable $error) {
    // Never log SQL, configuration, identity details or secret exception messages.
    fwrite(STDERR,gmdate('c')." backup_failed\n"); exit(1);
} finally { if(is_resource($lock)) { flock($lock,LOCK_UN); fclose($lock); } }
