# Fictional disposable fixture only. Optional last argument: 2 for populated auth schema.
from pathlib import Path
import json,secrets,subprocess,shutil,os,fcntl,tempfile,sys,re
root=Path(__file__).resolve().parents[1]
fixture=tempfile.TemporaryDirectory(prefix='Audyt Backup CLI Test '); test=Path(fixture.name); test.chmod(0o700)
(test/'bin').mkdir(mode=0o700,exist_ok=True); (test/'var').mkdir(mode=0o700,exist_ok=True); directory=test/'var/backups'; directory.mkdir(mode=0o700,exist_ok=True)
(test/'vendor').symlink_to(root/'vendor') if not (test/'vendor').exists() else None
shutil.copy2(root/'bin/backup.php',test/'bin/backup.php')
c=json.loads(Path(sys.argv[2]).read_text())
assert re.fullmatch(r'mysql:host=127\.0\.0\.1;port=\d+;dbname=audyt_test_[a-f0-9]{12};charset=utf8mb4',c['dsn']), 'Disposable loopback schema required'
config={'dsn':c['dsn'],'databaseUser':'audyt_test_runtime','databasePassword':c['runtimePassword'],'backupKey':__import__('base64').b64encode(secrets.token_bytes(32)).decode()}
# JSON is an external data file here; no secret is interpolated into PHP code or logs.
(test/'private.json').write_text(json.dumps(config)); (test/'private.json').chmod(0o600)
(test/'config.local.php').write_text("<?php return json_decode(file_get_contents(__DIR__.'/private.json'),true,16,JSON_THROW_ON_ERROR);\n"); (test/'config.local.php').chmod(0o600)
php=sys.argv[1]
def run(): return subprocess.run([php,str(test/'bin/backup.php')],capture_output=True,text=True)
checks=0
r=run(); assert r.returncode==0 and 'backup_ok' in r.stdout and not r.stderr; checks+=1
first=next(directory.glob('*.audytbackup')); assert first.stat().st_mode&0o077==0; checks+=1
archive=first.read_bytes(); assert b'example.test' not in archive; checks+=1
if len(sys.argv)>3:
    assert sys.argv[3]=='2' and archive.startswith(b'AUDYT-MEMBERSHIP-2\n'); checks+=1
    code="""require $argv[1]; $c=json_decode(file_get_contents($argv[2]),true,16,JSON_THROW_ON_ERROR);
    $s=Audyt\\MembershipBackup::open(file_get_contents($argv[3]),$c['backupKey']);
    echo json_encode(['version'=>$s['version'],'tables'=>count($s['tables']),'accounts'=>count($s['tables']['audyt_auth_accounts'])],JSON_THROW_ON_ERROR);"""
    summary=subprocess.run([php,'-r',code,str(test/'vendor/autoload.php'),str(test/'private.json'),str(first)],capture_output=True,text=True,check=True)
    metadata=json.loads(summary.stdout)
    assert not summary.stderr and metadata['version']==2 and metadata['tables']==14 and metadata['accounts']>0; checks+=1
for i in range(16):
    p=directory/('audyt-membership-20200101-000000-'+f'{i:016x}'+'.audytbackup'); p.write_bytes(archive); p.chmod(0o600)
other=directory/'unrelated-user-backup'; other.write_text('preserve')
outside=test/'outside-marker'; outside.write_text('preserve')
link=directory/'audyt-membership-19990101-000000-0000000000000001.audytbackup'; link.symlink_to(outside)
r=run(); assert r.returncode==0; checks+=1
real=[p for p in directory.glob('*.audytbackup') if not p.is_symlink()]; assert len(real)==14; checks+=1
assert other.read_text()=='preserve' and outside.read_text()=='preserve' and link.is_symlink(); checks+=1
with (directory/'.backup.lock').open('r+') as lock:
    fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB); r=run(); assert r.returncode==1 and 'backup_failed' in r.stderr and not r.stdout; checks+=1
config['backupKey']='invalid'; (test/'private.json').write_text(json.dumps(config))
r=run(); assert r.returncode==1 and 'backup_failed' in r.stderr and 'invalid' not in r.stderr and not r.stdout; checks+=1
assert len([p for p in directory.glob('*.audytbackup') if not p.is_symlink()])==14; checks+=1
config['backupKey']=''; config['databasePassword']=''; (test/'private.json').write_text(json.dumps(config))
r=run(); assert r.returncode==1 and 'backup_failed' in r.stderr; checks+=1
print(str(checks)+' backup CLI checks passed (private files, retention, locks, safe failures).')

fixture.cleanup()
