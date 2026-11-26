"""Isolated reconciliation: no network, credentials, financial or model changes."""
import json,secrets,subprocess,sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from managed.tests import test_database as db
db.command[db.command.index('paperlab-sql-check')]='paperlab-research-sql'
def main():
 name='free_plan_'+secrets.token_hex(4);db.query('create database '+name)
 def q(s,error=None):
  r=subprocess.run(db.command+['-d',name],input=s.encode(),capture_output=True,env=db.environment)
  if error:assert r.returncode and error in r.stderr.decode(),r.stderr.decode()
  elif r.returncode:raise RuntimeError(r.stderr.decode()[-3000:])
  return r.stdout.decode().strip().splitlines()[-1]if r.stdout.strip()else''
 def get(s):return json.loads(q(s))
 owner='11111111-1111-4111-8111-111111111111'
 try:
  q("create schema paperlab;create table paperlab.free_usage(month date primary key,estimated_worker_egress_bytes bigint not null default 0,max_worker_egress_bytes bigint not null default 4000000000 check(max_worker_egress_bytes between 1 and 4000000000));insert into paperlab.free_usage values(date_trunc('month',now())::date,3500000000,4000000000);create table paperlab.traffic_budget_runtime(singleton boolean primary key,policy jsonb);insert into paperlab.traffic_budget_runtime values(true,'{\"provider_uncached_quota_bytes\":5000000000}');create table paperlab.storage_budget_runtime(policy jsonb);insert into paperlab.storage_budget_runtime values('{\"provider_database_bytes\":500000000,\"hard_bytes\":450000000,\"provider_object_bytes\":1000000000}');")
  for fn,args,result in [('paper_traffic_budget_read','p_owner uuid',"'{\"old\":true}'::jsonb||jsonb_build_object('policy',(select policy from paperlab.traffic_budget_runtime))"),('paper_dashboard_read','p_owner uuid',"'{\"entry_status\":{\"reviews\":{\"current\":0}}}'::jsonb"),('paper_read','p_owner uuid,p_revision bigint default -1',"jsonb_build_object('free_usage',jsonb_build_object('automatic_budget',(select to_jsonb(u)from paperlab.free_usage u limit 1)))")]:
   q('create function public.'+fn+'('+args+")returns jsonb language plpgsql as $$begin if p_owner is distinct from '"+owner+"'::uuid then raise exception 'Owner required';end if;return "+result+';end$$;')
  migration=(ROOT/'managed/sql/048_free_plan_reconciliation.sql').read_text();q(migration);q(migration)
  assert q('select paperlab.traffic_safety_bytes()')=='3500000000'
  metrics=json.dumps({'egress_bytes':250000000,'database_bytes':152000000,'file_storage_bytes':20000000})
  record="select paperlab.record_provider_usage('owner-2026-11-26','"+metrics+"','Owner dashboard screenshot, current billing cycle unknown')"
  assert q(record)=='t';assert q(record)=='f'
  assert q('select estimated_worker_egress_bytes from paperlab.free_usage')=='3500000000'
  assert q('select max_worker_egress_bytes from paperlab.free_usage')=='7500000000'
  assert q('select paperlab.traffic_safety_bytes()')=='500000000'
  q(migration);assert q('select paperlab.traffic_safety_bytes()')=='500000000'
  assert q("select paperlab.traffic_limit('soft')")=='7000000000'
  view=get("select public.paper_traffic_budget_read('"+owner+"')");assert view['estimated_month_bytes']==500000000 and view['effective_hard_bytes']==4500000000
  assert view['meter']['provider_observation']['live_verified']is False
  assert view['meter']['next_window_at']is None
  root=get("select public.paper_read('"+owner+"')")['free_usage']['automatic_budget'];assert root['raw_work_bytes']==3500000000 and root['estimated_worker_egress_bytes']==500000000
  dash=get("select public.paper_dashboard_read('"+owner+"')");assert dash['entry_status']['reviews']['current']==0 and not dash['entry_status']['traffic']['blocked']
  for role in ['anon','authenticated','service_role']:
   q('set role '+role+';select *from paperlab.provider_usage_observations','permission denied')
   q('set role '+role+';'+record,'permission denied')
   q('set role '+role+';select public.paper_read_reconcile_base(null,-1)','permission denied')
  q('set role service_role;select public.paper_traffic_budget_read(null)','Owner required')
  q('set role authenticated;select public.paper_traffic_budget_read(null)','permission denied')
  # Positive reservations count once; later refunds do not grant new capacity.
  q('update paperlab.free_usage set estimated_worker_egress_bytes=4000000000');assert q('select paperlab.traffic_safety_bytes()')=='1000000000'
  q('update paperlab.free_usage set estimated_worker_egress_bytes=3900000000');assert q('select paperlab.traffic_safety_bytes()')=='1000000000'
  q('update paperlab.free_usage set estimated_worker_egress_bytes=4000000000');assert q('select paperlab.traffic_safety_bytes()')=='1100000000'
  # A lower owner work cap is respected, never silently expanded.
  q('update paperlab.free_usage set max_worker_egress_bytes=4010000000');assert q("select paperlab.traffic_effective_limit('hard')")=='1110000000';q('update paperlab.free_usage set max_worker_egress_bytes=7500000000')
  # No unverified provider reset when another UTC work month is inserted.
  q("insert into paperlab.free_usage(month)values((date_trunc('month',now())+interval'1 month')::date)");assert q('select paperlab.traffic_safety_bytes()')=='1100000000'
  q("update paperlab.free_usage set estimated_worker_egress_bytes=3399999980 where month>date_trunc('month',now())::date")
  def concurrent_charge(operator):
   return subprocess.run(db.command+['-d',name],input=("update paperlab.free_usage set estimated_worker_egress_bytes=estimated_worker_egress_bytes+15 where month"+operator+"date_trunc('month',now())::date").encode(),capture_output=True,env=db.environment).returncode
  with ThreadPoolExecutor(max_workers=2)as pool:assert sorted(pool.map(concurrent_charge,['=','>']))==[0,3]
  assert q('select paperlab.traffic_safety_bytes()')=='4499999995'
  q("update paperlab.free_usage set estimated_worker_egress_bytes=estimated_worker_egress_bytes+5 where month>date_trunc('month',now())::date");assert q('select paperlab.traffic_safety_bytes()')=='4500000000'
  q("update paperlab.free_usage set estimated_worker_egress_bytes=3400000001 where month>date_trunc('month',now())::date",'safety ceiling reached')
  assert q('select paperlab.traffic_safety_bytes()')=='4500000000'
  q(record.replace('250000000','240000000'),'Observation frozen')
  print('Free-plan SQL passed: private owner observation, repeatable checkpoint, retained raw meter, conservative refunds/rollover, custom cap and concurrent atomic 4.5 GB ceiling, protected reads.')
 finally:db.query('drop database '+name+' with(force)')
if __name__=='__main__':main()
