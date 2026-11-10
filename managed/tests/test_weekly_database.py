"""Synthetic SQL-only tests; isolated database, no production reads or writes."""
import json,secrets,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from scripts.deploy_managed import literal
from managed.tests.test_database import query as admin,command,environment
def main():
 name='paperlab_weekly_'+secrets.token_hex(4);admin('create database '+name)
 def q(s,error=None):
  r=subprocess.run(command+['-d',name],input=s.encode(),capture_output=True,env=environment)
  if error:assert r.returncode and error in r.stderr.decode(),r.stderr.decode()
  elif r.returncode:raise RuntimeError(r.stderr.decode()[-3000:])
  return r.stdout.decode().strip().splitlines()[-1]if r.stdout.strip()else''
 def get(s):return json.loads(q(s)or'null')
 try:
  for p in sorted((ROOT/'managed/sql').glob('*.sql')):q(p.read_text())
  owner='11111111-1111-4111-8111-111111111111';q('update paperlab.settings set owner_id='+literal(owner))
  for role in['anon','authenticated']:
   for cmd in['select *from paperlab.weekly_reports','select public.paper_weekly_read(null)','select public.paper_weekly_run(true)']:
    q('set role '+role+';'+cmd,'permission denied')
  q('set role service_role;select public.paper_weekly_run(true)','permission denied')
  q('set role service_role;select paperlab.weekly_build(now(),true)','permission denied')
  q('select public.paper_weekly_read(null)','Owner required')
  # Winter, summer, asymmetric US/EU DST weeks, Saturday catchup and Sunday cutoff.
  for at,expected in [('2026-11-13 22:14Z','f'),('2026-11-13 22:15Z','t'),('2026-07-10 21:14Z','f'),('2026-07-10 21:15Z','t'),('2026-03-13 22:15Z','t'),('2026-10-30 22:15Z','t'),('2026-11-14 06:15Z','t'),('2026-11-14 23:00Z','f')]:
   assert q('select paperlab.weekly_due('+literal(at)+'::timestamptz)')==expected,at
  before=q("select md5(coalesce((select state::text from paperlab.capital_runtime),'')||coalesce((select state::text from paperlab.portfolio),''))")
  assert get("select paperlab.weekly_build('2026-11-10 13:00Z',false)")['status']=='not_due'
  a=get("select paperlab.weekly_build('2026-11-10 13:00Z',true)");assert a['baseline_only']and a['net_count_changes']is None
  # No lookahead: a later observed close cannot explain a past reflection.
  q("insert into paperlab.daily_study_bars values('TEST','2026-11-09','2026-11-09 22:00Z',100,'{}'),('TEST','2026-11-10','2026-11-10 22:00Z',90,'{}'),('TEST','2026-11-11','2026-11-14 23:00Z',200,'{}')")
  b=get("select paperlab.weekly_build('2026-11-13 22:15Z',false)");assert not b['baseline_only'];assert b['market_observations']['companies']==1;assert abs(b['market_observations']['mean_local_change_percent']+10)<1e-8
  assert b['assessment']['automatic_strategy_change']is False;assert b['assessment']['paid_model_calls']==0
  assert get("select paperlab.weekly_build('2026-11-14 06:15Z',false)")==b
  c=get("select paperlab.weekly_build('2026-11-21 06:15Z',false)");assert c['snapshot_at'].startswith('2026-11-21');assert c['period_end'].startswith('2026-11-20T22:15');assert c['baseline_at']==b['generated_at']
  assert q("select count(*)from paperlab.weekly_reports where kind='final'")=='2'
  q("insert into paperlab.weekly_reports select '2020-01-06'::date+i*7,'final','2020-01-06'::timestamptz+i*interval'7 days','{}'from generate_series(0,105)i")
  get("select paperlab.weekly_build('2026-11-27 22:15Z',false)");assert q("select count(*)from paperlab.weekly_reports where kind='final'")=='104'
  get("select paperlab.weekly_build('2026-11-30 12:00Z',true)");assert q("select count(*)from paperlab.weekly_reports where kind='preview'")=='1'
  assert before==q("select md5(coalesce((select state::text from paperlab.capital_runtime),'')||coalesce((select state::text from paperlab.portfolio),''))")
  assert q('select count(*)from paperlab.capital_trades')=='0'
  view=get('set role service_role;select public.paper_weekly_read('+literal(owner)+'::uuid)');assert len(view['history'])==8
  q("update paperlab.weekly_runtime set enabled=false");assert get("select paperlab.weekly_build('2026-12-04 22:15Z',false)")['status']=='paused'
  q((ROOT/'managed/sql/019_weekly_reflection.sql').read_text());assert q('select enabled from paperlab.weekly_runtime')=='f'
  print('Weekly SQL passed: EU DST, US transition weeks, no early run, Saturday catchup, truthful snapshots, baseline, idempotence, source observation cutoff, bounded retention, owner-only reports, no browser generation and no portfolio writes.')
 finally:admin('drop database '+name+' with(force)')
if __name__=='__main__':main()
