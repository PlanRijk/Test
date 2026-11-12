"""Isolated 4 GB transfer overlay: old counters/profiles/ACLs and storage retained."""
import json,secrets,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from managed.tests.test_database import query as admin,command,environment
from scripts.deploy_managed import jsql,literal
from scripts.source_resilience import protocol

def main():
 name='paperlab_traffic_'+secrets.token_hex(4);admin('create database '+name)
 def q(s,error=None):
  p=subprocess.run(command+['-d',name],input=s.encode(),capture_output=True,env=environment)
  if error:assert p.returncode and error in p.stderr.decode(),p.stderr.decode()
  elif p.returncode:raise RuntimeError(p.stderr.decode()[-3000:])
  return p.stdout.decode().strip().splitlines()[-1]if p.stdout.strip()else''
 def get(s):return json.loads(q(s)or'null')
 snapshot="select jsonb_build_object('capital',(select to_jsonb(r)from paperlab.capital_runtime r),'company',(select to_jsonb(r)from paperlab.company_runtime r),'history',(select to_jsonb(r)from paperlab.history_runtime r),'reading',(select to_jsonb(r)from paperlab.reading_runtime r),'portfolio',(select to_jsonb(r)from paperlab.portfolio r))"
 try:
  for f in sorted((ROOT/'managed/sql').glob('*.sql')):
   if f.name<'026':q(f.read_text())
  owner='11111111-1111-4111-8111-111111111111';q('update paperlab.settings set owner_id='+literal(owner))
  q("insert into paperlab.free_usage(month,estimated_worker_egress_bytes)values(date_trunc('month',now())::date,1130000000);insert into paperlab.free_usage(month,max_worker_egress_bytes)values((date_trunc('month',now())-interval'1 month')::date,2000000000)")
  before=get(snapshot);functions=get("select jsonb_object_agg(p.oid::text,jsonb_build_object('definition',pg_get_functiondef(p.oid),'owner',p.proowner,'acl',p.proacl,'config',p.proconfig))from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'and p.proname like'paper_%'")
  migration=(ROOT/'managed/sql/026_traffic_budget.sql').read_text();q(migration);q(migration);assert get(snapshot)==before
  assert q("select estimated_worker_egress_bytes from paperlab.free_usage where month=date_trunc('month',now())::date")=='1130000000';assert q("select max_worker_egress_bytes from paperlab.free_usage where month=date_trunc('month',now())::date")=='4000000000';assert q("select max_worker_egress_bytes from paperlab.free_usage where month<date_trunc('month',now())::date")=='2000000000'
  assert q('select count(*)from paperlab.traffic_budget_patches')=='20'
  after=get("select jsonb_object_agg(p.oid::text,jsonb_build_object('definition',pg_get_functiondef(p.oid),'owner',p.proowner,'acl',p.proacl,'config',p.proconfig))from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'and p.proname like'paper_%'")
  changed=0
  for oid,old in functions.items():
   new=after[oid];assert all(old[k]==new[k]for k in['owner','acl','config'])
   changed+=old['definition']!=new['definition']
  assert changed==20
  source_oid=next(oid for oid,v in functions.items()if'CREATE OR REPLACE FUNCTION public.paper_source_commit('in v['definition']);q(functions[source_oid]['definition']);q(migration);assert get("select to_json(pg_get_functiondef("+source_oid+"))")==after[source_oid]['definition']
  q(after[source_oid]['definition'].replace('AS $function$','AS $function$\n-- unexpected source edit'));q(migration,'Budget-patched function changed');q(after[source_oid]['definition']);q(migration)
  q("insert into paperlab.free_usage(month)values((date_trunc('month',now())+interval'1 month')::date)");assert q("select max_worker_egress_bytes from paperlab.free_usage where month>date_trunc('month',now())::date")=='4000000000'
  for role in ['anon','authenticated']:
   q('set role '+role+';select *from paperlab.traffic_budget_runtime','permission denied');q('set role '+role+';select public.paper_traffic_budget_read(null)','permission denied')
  q('select public.paper_traffic_budget_read(null)','Owner required')
  p=get('select public.paper_traffic_budget_read('+literal(owner)+'::uuid)');assert p['effective_hard_bytes']==4000000000;assert p['effective_soft_bytes']==3200000000;assert p['policy']['provider_meter_verified']is False
  old=json.loads(subprocess.check_output(['node','--input-type=module','-e',"import{COVERAGE_POLICY}from'./managed/functions/_shared/company-coverage.js';import{COMPANY_SOURCES}from'./managed/functions/_shared/company-source-catalogue.js';console.log(JSON.stringify({p:COVERAGE_POLICY,c:COMPANY_SOURCES}));"],cwd=ROOT));q('select public.paper_company_coverage_configure('+jsql(old['p'])+','+jsql(old['c'])+')');d=protocol();q('select public.paper_source_configure('+jsql(d['policy'])+','+jsql(d['registry'])+')')
  lease=get('select public.paper_source_claim(true)');assert lease and len(lease['targets'])==6;q('select public.paper_source_fail('+literal(lease['token'])+'::uuid)')
  q('update paperlab.free_usage set estimated_worker_egress_bytes=3200000000 where month=date_trunc(\'month\',now())::date');assert get('select public.paper_source_claim(true)')is None
  # New entries/research stop, but the market executor still has closing room.
  q("insert into paperlab.portfolio(singleton,state)values(true,jsonb_build_object('running',true,'operation_mode','continuous','run_until',now()+interval'1 day'));update paperlab.free_usage set estimated_worker_egress_bytes=3300000000 where month=date_trunc('month',now())::date")
  assert get('select public.paper_claim_tick(true)')is not None
  q("update paperlab.portfolio set state=jsonb_set(state,'{running}','true'),last_attempt=null,lease=null,lease_until=null;update paperlab.free_usage set estimated_worker_egress_bytes=4000000000 where month=date_trunc('month',now())::date")
  assert get('select public.paper_claim_tick(true)')is None
  q("update paperlab.free_usage set max_worker_egress_bytes=1000000000 where month=date_trunc('month',now())::date");q(migration);assert q("select paperlab.traffic_limit('hard')")=='1000000000'
  assert q('select count(*)from paperlab.trades')=='0';assert q('select count(*)from paperlab.capital_trades')=='0'
  print('Traffic DB passed: 4 GB cap, 3.2 GB admission stop, closing room, manual lower caps, untouched counters/profiles/storage/ACLs, new-month default, idempotence, private reads and zero orders.')
 finally:admin('drop database '+name+' with(force)')
if __name__=='__main__':main()
