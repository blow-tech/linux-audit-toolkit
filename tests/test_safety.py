import os, pathlib, shutil, subprocess, tempfile, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class Safety(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory(); self.d=pathlib.Path(self.tmp.name)
  self.bin=self.d/'bin';self.bin.mkdir();self.logs=self.d/'logs';self.logs.mkdir(mode=0o700)
  self.env={**os.environ,'PATH':str(self.bin)+os.pathsep+os.environ['PATH'],'AUDIT_LOGDIR':str(self.logs),'MAILTO':'never@example.test','AUDIT_WEBHOOK_URL':'https://invalid.test'}
  for n in ['mail','curl','ping','find','du']:
   self.mock(n,'echo forbidden >&2; exit 99')
 def tearDown(self): self.tmp.cleanup()
 def mock(self,n,body):
  p=self.bin/n;p.write_text('#!/bin/bash\n'+body+'\n');p.chmod(0o700)
 def run_script(self,name,*args,source=None):
  return subprocess.run(['bash',str((source or ROOT/'scripts')/name),*args],env=self.env,text=True,capture_output=True,timeout=12)
 def test_syntax(self):
  for p in (ROOT/'scripts').glob('*.sh'):
   self.assertEqual(subprocess.run(['bash','-n',str(p)],capture_output=True).returncode,0,p)
 def df(self,pct): self.mock('df',f"printf 'Filesystem Blocks Used Available Capacity Mounted on\\n/dev/fixture 100 99 1 {pct}%% /fixture space\\n'")
 def test_high_disk_and_inode_counters(self):
  self.df(99);r=self.run_script('01_disk_space_audit.sh');self.assertEqual(r.returncode,2,r.stdout+r.stderr);self.assertIn('High disk',r.stdout);self.assertIn('High inode',r.stdout)
 def test_healthy_disk_no_implicit_walk(self):
  self.df(10);r=self.run_script('01_disk_space_audit.sh');self.assertEqual(r.returncode,0,r.stdout+r.stderr)
 def test_failed_empty_malformed_df(self):
  for body in ['exit 1','exit 0',"echo 'broken data'"]:
   self.mock('df',body);r=self.run_script('01_disk_space_audit.sh');self.assertEqual(r.returncode,3,r.stdout+r.stderr)
 def test_bad_threshold(self): self.assertEqual(self.run_script('01_disk_space_audit.sh','bad').returncode,3)
 def staged(self,rc=None):
  p=self.d/('scripts'+str(rc));p.mkdir();shutil.copy(ROOT/'scripts/lib_common.sh',p);shutil.copy(ROOT/'scripts/10_full_system_report.sh',p)
  if rc is not None:
   for child in (ROOT/'scripts').glob('0[1-9]_*.sh'): (p/child.name).write_text('#!/bin/bash\nexit '+str(rc)+'\n')
  return p
 def test_missing_and_bad_children_fail_closed(self):
  for rc in [None,127,124,3]:
   r=self.run_script('10_full_system_report.sh',source=self.staged(rc));self.assertEqual(r.returncode,3,r.stdout+r.stderr)
 def test_child_statuses_and_no_notifications(self):
  for rc in [0,1,2]:
   r=self.run_script('10_full_system_report.sh',source=self.staged(rc));self.assertEqual(r.returncode,rc,r.stdout+r.stderr);self.assertNotIn('forbidden',r.stderr)
 def test_insecure_output_parent_refused(self):
  self.logs.chmod(0o777);r=self.run_script('01_disk_space_audit.sh');self.assertEqual(r.returncode,3)
 def test_service_unknown_and_failed(self):
  self.mock('systemctl',"if [[ $1 == --failed ]]; then echo 'fixture.service loaded failed failed'; else printf 'LoadState=loaded\\nActiveState=active\\n'; fi")
  self.assertEqual(self.run_script('04_service_status_audit.sh','fixture').returncode,2)
  self.mock('systemctl','exit 1');self.assertEqual(self.run_script('04_service_status_audit.sh','fixture').returncode,3)
 def test_local_logs_and_corrupt_archive(self):
  log=self.d/'with space.log';log.write_text('127.0.0.1 - - [01/Jan/2000:00:00:00 +0000] "GET / HTTP/1.1" 500 1\n')
  self.assertEqual(self.run_script('05_webserver_log_audit.sh',str(log)).returncode,1)
  bad=self.d/'bad.gz';bad.write_text('not gzip');self.assertEqual(self.run_script('05_webserver_log_audit.sh',str(bad)).returncode,3)
if __name__=='__main__': unittest.main()
