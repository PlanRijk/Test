"""Private, deterministic IEX research tests in a disposable local PostgreSQL database."""
import json,secrets,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from scripts.deploy_managed import jsql,literal
from scripts.iex_study import policy
from managed.tests.test_database import query as admin_query,command,environment

def main():
 name='paperlab_iex_'+secrets.token_hex(5);admin_query('create database '+name)
 def q(text,error=None):
  r=subprocess.run(command+['-d',name],input=text.encode(),capture_output=True,env=environment)
  if error:assert r.returncode and error in r.stderr.decode(),r.stderr.decode()
  elif r.returncode:raise RuntimeError(r.stderr.decode()[-4000:])
  return r.stdout.decode().strip().splitlines()[-1]if r.stdout.strip()else''
 def get(text):return json.loads(q(text)or'null')
 def clock(t):q('update paperlab.iex_test_clock set t='+literal(t)+'::timestamptz')
 def claim():return get('select public.paper_iex_claim()')
 def output(t='2026-11-09T14:30:01Z',price=100,age=1):
  from datetime import datetime
  ms=int(datetime.fromisoformat(t.replace('Z','+00:00')).timestamp()*1000)
  return {'version':'iex-minute-research-v1','checked_at':t,'points':[[ms-age*1000,price,price+.1,ms-1000,price]for _ in range(53)],'source_calls':2,'source_bytes':12000,'duration_ms':100}
 def commit(c,o):return q('select public.paper_iex_commit('+literal(c['token'])+'::uuid,'+jsql(o)+')')
 try:
  for path in sorted((ROOT/'managed/sql').glob('*.sql')):q(path.read_text())
  q("create table paperlab.iex_test_clock(t timestamptz);insert into paperlab.iex_test_clock values('2026-11-09T14:00Z');create or replace function paperlab.iex_now()returns timestamptz language sql stable as $$select t from paperlab.iex_test_clock$$;")
  owner='11111111-1111-4111-8111-111111111111';q('update paperlab.settings set owner_id='+literal(owner)+'::uuid')
  q("insert into paperlab.free_usage(month)values('2026-11-01')on conflict do nothing")
  p=policy();cfg='select public.paper_iex_configure('+jsql(p)+')';fp=q(cfg);assert len(fp)==64;assert q(cfg)==fp
  for role in['anon','authenticated']:
   q('set role '+role+';select public.paper_iex_claim()','permission denied');q('set role '+role+';select public.paper_iex_read(null)','permission denied');q('set role '+role+';select *from paperlab.iex_minutes','permission denied')
  q('set role service_role;select *from paperlab.iex_daily','permission denied')
  q('set role anon;select public.paper_iex_focus_read(null)','permission denied');q('set role authenticated;select *from paperlab.iex_focus_reviews','permission denied');q('select public.paper_iex_focus_read(null)','Owner required')
  q('select public.paper_iex_read(null)','Owner required')
  assert claim()is None
  focus={'version':'iex-focus-v1','orders':False,'training':False,'causal_or_profitability_evidence':False,'companies':[{'symbol':x}for x in['TM','ICE','AMT','CME','AAPL','MSFT']],'samples':18}
  fq='select public.paper_iex_focus_save('+jsql(focus)+')';fid=q(fq);assert q(fq)==fid;assert get('select public.paper_iex_focus_read('+literal(owner)+'::uuid)')['samples']==18
  clock('2026-11-09T14:30:01Z');c=claim();assert c and claim()is None
  bad=output();bad['points']=[];q('select public.paper_iex_commit('+literal(c['token'])+'::uuid,'+jsql(bad)+')','Invalid IEX batch')
  before=int(q("select estimated_worker_egress_bytes from paperlab.free_usage where month='2026-11-01'"));assert before==50000
  assert commit(c,output())=='t';assert commit(c,output())=='f';assert int(q('select count(*)from paperlab.iex_minutes'))==1
  assert int(q("select sum((stats->>'fresh60')::int)from paperlab.iex_daily"))==53
  assert int(q("select estimated_worker_egress_bytes from paperlab.free_usage where month='2026-11-01'"))<before
  clock('2026-11-09T14:31:01Z');c=claim();assert commit(c,output('2026-11-09T14:31:01Z',102))=='t'
  assert int(q("select sum((stats->>'coarse_n')::int)from paperlab.iex_daily"))==53
  assert int(q("select sum((stats->>'move150')::int)from paperlab.iex_daily"))==53
  report=get('select public.paper_iex_read('+literal(owner)+'::uuid)');assert len(report['companies'])==53;assert report['usage']['successes']==2;assert 'token' not in report['runtime'];assert report['companies'][0]['samples']==2
  clock('2026-11-09T14:32:01Z');c=claim();assert commit(c,output('2026-11-09T14:32:01Z',100,61))=='t'
  assert get('select latest from paperlab.iex_runtime')['fresh60']==0
  assert get('select latest from paperlab.iex_runtime')['mean_spread_bps']is None
  clock('2026-11-09T14:33:01Z');c=claim();q('select public.paper_iex_action('+literal(owner)+"::uuid,'pause')");assert commit(c,output('2026-11-09T14:33:01Z'))=='f';assert claim()is None
  q('select public.paper_iex_action('+literal(owner)+"::uuid,'resume')");assert q('select profile from paperlab.iex_runtime')==fp;assert q(cfg)==fp
  clock('2026-11-09T14:34:01Z');q("update paperlab.iex_usage set estimated_bytes=199950000");assert claim()is None;assert q('select status from paperlab.iex_runtime')=='budget_paused'
  q("update paperlab.iex_usage set estimated_bytes=0;update paperlab.free_usage set estimated_worker_egress_bytes=1049999999");assert claim()is None
  q("update paperlab.free_usage set estimated_worker_egress_bytes=0")
  q("insert into paperlab.iex_minutes select '2026-11-08T14:30Z'::timestamptz-i*interval'1 minute','2026-11-08T14:30Z','[]'::jsonb from generate_series(1,900)i")
  c=claim();assert c;assert int(q('select count(*)from paperlab.iex_minutes'))<=799
  q('select public.paper_iex_fail('+literal(c['token'])+'::uuid)');assert claim()is None
  before=q('select run_until from paperlab.iex_runtime');assert q(cfg)==fp;assert q('select run_until from paperlab.iex_runtime')==before
  clock('2026-11-24T14:30:01Z');assert claim()is None;assert q('select status from paperlab.iex_runtime')=='study_ended'
  assert q('select count(*)from paperlab.trades')=='0';assert q('select count(*)from paperlab.capital_trades')=='0'
  print('IEX database passed: private RPCs, immutable phase, market hours, lease/idempotence, truthful freshness, coarse pairing, budget reservation/refund, pause revocation, raw cap and unchanged empty ledgers.')
 finally:admin_query('drop database '+name+' with(force)')
if __name__=='__main__':main()
