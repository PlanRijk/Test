"""Daily reading leases/limits/private evidence, in a disposable local database."""
import json,secrets,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from scripts.deploy_managed import jsql,literal
from scripts.reading_study import policy
from managed.tests.test_database import query as admin_query,command,environment

def main():
 name='paperlab_reading_'+secrets.token_hex(5);admin_query('create database '+name)
 def q(text,error=None):
  r=subprocess.run(command+['-d',name],input=text.encode(),capture_output=True,env=environment)
  if error:assert r.returncode and error in r.stderr.decode(),r.stderr.decode()
  elif r.returncode:raise RuntimeError(r.stderr.decode()[-4500:])
  return r.stdout.decode().strip().splitlines()[-1] if r.stdout.strip() else ''
 def get(text):return json.loads(q(text) or 'null')
 def claim():return get('select public.paper_reading_claim()')
 try:
  for path in sorted((ROOT/'managed/sql').glob('*.sql')):q(path.read_text())
  p=policy();config='select public.paper_reading_configure('+jsql(p)+')';assert q(config)=='t';assert q(config)=='t'
  before=q("select md5(coalesce(string_agg(state::text,''),'')) from paperlab.portfolio")
  for role in ['anon','authenticated']:
   q('set role '+role+';select public.paper_reading_claim()','permission denied');q('set role '+role+';select public.paper_reading_read(null)','permission denied')
  q('set role service_role;select * from paperlab.reading_notes','permission denied')
  q("select public.paper_reading_read('11111111-1111-4111-8111-111111111111')",'Owner required')
  c=claim();assert c and claim() is None
  q("select public.paper_reading_action(null,'pause')");assert q('select public.paper_reading_commit('+literal(c['token'])+"::uuid,'{}')")=='f';assert claim() is None
  q("select public.paper_reading_action(null,'resume')");q('update paperlab.reading_runtime set last_attempt=null');c=claim()
  note={'version':p['version'],'day':c['day'],'card_id':p['library'][0]['id'],'url':p['library'][0]['url'],'read_scope':'selected_passage_verification','analysis_origin':'editor_reviewed_at_setup','automatic_model_training':False,'trading_changes':False,'status':'verified','source_bytes':20000,'content_sha256':'a'*64,'lesson':'test fixture, not a real reading'}
  commit=lambda n:'select public.paper_reading_commit('+literal(c['token'])+'::uuid,'+jsql(n)+')'
  bad={**note,'url':'https://attacker.invalid'};q(commit(bad),'Invalid reading note')
  assert q(commit(note))=='t';assert q(commit(note))=='f';assert claim() is None;assert q('select cursor from paperlab.reading_runtime')=='1'
  assert q(config)=='t';assert q('select cursor from paperlab.reading_runtime')=='1'
  q("update paperlab.reading_runtime set last_day=null,last_attempt=null,attempts=0");c=claim();bad={**note,'card_id':p['library'][1]['id'],'url':p['library'][1]['url'],'status':'source_unavailable'};q(commit(bad),'Failed source has no confirmed lesson')
  q('delete from paperlab.reading_notes');bad.pop('lesson');assert q(commit(bad))=='t';assert q('select cursor from paperlab.reading_runtime')=='1'
  q("update paperlab.reading_runtime set last_day=null,last_attempt=null,attempts=3");assert claim() is None
  q("update paperlab.reading_runtime set attempts=0;update paperlab.reading_usage set estimated_bytes=20000000");assert claim() is None
  q("update paperlab.reading_usage set estimated_bytes=0;update paperlab.free_usage set estimated_worker_egress_bytes=1200000000");assert claim() is None
  q("update paperlab.free_usage set estimated_worker_egress_bytes=0;delete from paperlab.reading_notes;insert into paperlab.reading_notes select (now() at time zone 'UTC')::date-i,'{}' from generate_series(1,140)i")
  c=claim();assert c;assert int(q('select count(*) from paperlab.reading_notes'))==119
  assert q("select md5(coalesce(string_agg(state::text,''),'')) from paperlab.portfolio")==before
  print('Reading database: private owner RPCs, single lease, pause revocation, idempotent config, failed-source honesty, daily and monthly bounds, retention, unchanged portfolio passed.')
 finally:admin_query('drop database '+name+' with(force)')
if __name__=='__main__':main()
