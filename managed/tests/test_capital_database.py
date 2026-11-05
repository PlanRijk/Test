"""Separate EUR10k ledger and atomic market-round coupling in an isolated local DB."""
import copy,json,secrets,subprocess,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from scripts.deploy_managed import import_sql,literal,jsql
from scripts.capital_study import fingerprint
from managed.tests.test_database import query as admin_query,command,environment
ROOT=Path(__file__).resolve().parents[2]
def main():
 name='paperlab_capital_'+secrets.token_hex(5);admin_query('create database '+name);checks=[]
 def q(text,error=None):
  r=subprocess.run(command+['-d',name],input=text.encode(),capture_output=True,env=environment)
  if error:assert r.returncode and error in r.stderr.decode(),r.stderr.decode()
  elif r.returncode:raise RuntimeError(r.stderr.decode()[-4500:])
  return r.stdout.decode().strip()
 def get(text):return json.loads((q(text) or 'null').splitlines()[-1])
 def node(code,obj=None):
  r=subprocess.run(['node','--input-type=module','-e',code],input=json.dumps(obj).encode(),capture_output=True,cwd=ROOT);assert not r.returncode,r.stderr.decode();return json.loads(r.stdout)
 def clock(stamp):q((ROOT/'managed/sql/011_capital_study.sql').read_text().replace('now()',literal(stamp)+'::timestamptz'))
 def main_claim():
  q('update paperlab.portfolio set last_attempt=null');return get('select public.paper_claim_tick(true)')
 def claim(m):
  q('update paperlab.capital_runtime set last_attempt=null,token=null,lease_until=null');return get('select public.paper_capital_claim('+literal(m['token'])+'::uuid,'+str(m['revision'])+')')
 def cap_commit(c,out,error=None):return q('select public.paper_capital_commit('+literal(c['token'])+'::uuid,'+jsql(out)+')',error)
 def main_commit(m,out):return q('select public.paper_commit_tick('+literal(m['token'])+'::uuid,'+str(m['revision'])+','+jsql(out)+')')
 def outputs(c,m,b,time):return node("import fs from 'node:fs';import {stepCapital} from './managed/functions/_shared/capital-study.js';import {tick} from './managed/functions/_shared/engine.js';const i=JSON.parse(fs.readFileSync(0,'utf8'));console.log(JSON.stringify({capital:await stepCapital(i.capital,i.market,i.batch,i.time),main:tick(i.market,i.batch,i.time)}));",{'capital':c,'market':m['state'],'batch':b,'time':time})
 main_hash="select md5(state::text),revision,(select count(*) from paperlab.trades),(select count(*) from paperlab.learning_samples),(select count(*) from paperlab.learning_trades),(select count(*) from paperlab.history_forecasts),(select count(*) from paperlab.breadth_scores),(select count(*) from paperlab.candidate_models) from paperlab.portfolio"
 try:
  fingerprint()
  for path in sorted((ROOT/'managed/sql').glob('*.sql')):q(path.read_text())
  clock('2026-11-03T15:00:00Z')
  f=node("import {capitalFixture} from './managed/tests/capital-fixture.mjs';console.log(JSON.stringify(await capitalFixture()));")
  q(import_sql(f['market'],{'trades':[],'events':[],'equity':[],'observations':[]}));before=q(main_hash)
  configure='select public.paper_capital_configure('+jsql(f['policy'])+','+jsql(f['state'])+')';assert q(configure)==q(configure);assert q(main_hash)==before
  bad=copy.deepcopy(f['policy']);bad['reference_fingerprint']='f'*64;q('select public.paper_capital_configure('+jsql(bad)+','+jsql(f['state'])+')','Existing capital policy frozen')
  for role in ['anon','authenticated']:
   for rpc in ['paper_capital_read(null)','paper_capital_receipt(null,null)',"paper_capital_action(null,'pause')",'paper_capital_claim(null,1)']:q('set role '+role+';select public.'+rpc,'permission denied')
  q('set role service_role;select * from paperlab.capital_trades','permission denied')
  q("select public.paper_capital_read('11111111-1111-4111-8111-111111111111')",'Owner required')
  checks.append('idempotent_empty_initialization_private_ledgers_and_owner_only_access_no_original_changes')
  m=main_claim();c=claim(m);assert c and c['allow_entries'];assert get('select public.paper_capital_claim('+literal(m['token'])+'::uuid,'+str(m['revision'])+')') is None
  out=outputs(c,m,f['batch'],f['time']);assert out['capital']['new_orders']==1;assert cap_commit(c,out['capital'])=='f'
  assert main_commit(m,out['main'])=='t';before=q(main_hash);assert cap_commit(c,out['capital'])=='t';assert cap_commit(c,out['capital'])=='f';assert q(main_hash)==before
  current=q('select md5(state::text) from paperlab.capital_runtime');assert q(configure);assert q('select md5(state::text) from paperlab.capital_runtime')==current
  checks.append('capital_waits_for_original_commit_single_lease_and_reconfiguration_never_resets_running_account')
  time=f['time']+300000;clock('2026-11-03T15:05:00Z');batch=copy.deepcopy(f['batch']);batch['quotes']['AAPL']['time']='2026-11-03T15:04:59Z'
  m=main_claim();c=claim(m);out=outputs(c,m,batch,time);assert len(out['capital']['trades'])==1;assert main_commit(m,out['main'])=='t';before=q(main_hash)
  bad=copy.deepcopy(out['capital']);bad['state']['cash']+=1;cap_commit(c,bad,'Capital ledger mismatch')
  bad=copy.deepcopy(out['capital']);del bad['trades'][0]['snapshot']['purchase_rationale'];cap_commit(c,bad,'Capital purchase explanation required')
  assert cap_commit(c,out['capital'])=='t';assert q(main_hash)==before
  visible=get('select public.paper_capital_read(null)');assert abs(visible['runtime']['summary']['cash_eur']-9500)<1e-8;assert visible['counts']['buys']==1
  receipt=get('select public.paper_capital_receipt(null,1)');assert receipt['account']=='capital10k' and receipt['snapshot']['purchase_rationale']['cost_estimate']['budget_eur']==500
  assert len(get('select public.paper_capital_receipt(null,null)'))==1
  checks.append('real_euro_receipt_and_conserved_cash_fees_taxes_bad_ledger_or_missing_motivation_rejected')
  clock('2026-11-03T15:10:00Z');q("update paperlab.capital_runtime set state=jsonb_set(state,'{risk,global_halted}','true')")
  m=main_claim();c=claim(m);batch['quotes']['AAPL']['time']='2026-11-03T15:09:59Z';out=outputs(c,m,batch,f['time']+600000);assert main_commit(m,out['main'])=='t'
  bad=copy.deepcopy(out['capital']);bad['state']['risk']['global_halted']=False;cap_commit(c,bad,'Capital risk stop cannot be reset')
  assert q("select public.paper_capital_action(null,'pause')")=='t';assert cap_commit(c,out['capital'])=='f';assert claim(m) is None
  assert q("select public.paper_capital_action(null,'resume')")=='t';assert q("select state->'risk'->>'global_halted' from paperlab.capital_runtime")=='true';assert q("select public.paper_capital_action(null,'reset')")=='f'
  checks.append('pause_invalidates_inflight_work_resume_does_not_clear_risk_halts')
  m=main_claim();q('update paperlab.capital_usage set estimated_bytes=240000000');c=claim(m);assert c and not c['allow_entries']
  q('select public.paper_capital_fail('+literal(c['token'])+'::uuid)');q('update paperlab.capital_usage set estimated_bytes=300000000');assert claim(m) is None
  q('update paperlab.capital_usage set estimated_bytes=0');q('update paperlab.free_usage set estimated_worker_egress_bytes=1500000000');assert claim(m) is None
  q('update paperlab.free_usage set estimated_worker_egress_bytes=0')
  q("insert into paperlab.capital_trades(time,symbol,side,qty,price,fee,pnl,reason,snapshot) select now(),'D'||i,'verkoop',1,1,0,0,'synthetic storage fixture','{\"fx\":1}' from generate_series(1,1800)i")
  c=claim(m);assert c and not c['allow_entries'];q('select public.paper_capital_fail('+literal(c['token'])+'::uuid)')
  q("insert into paperlab.capital_trades(time,symbol,side,qty,price,fee,pnl,reason,snapshot) select now(),'X'||i,'verkoop',1,1,0,0,'synthetic storage fixture','{\"fx\":1}' from generate_series(1,200)i")
  assert claim(m) is None;assert q('select count(*) from paperlab.capital_trades')=='2001';assert len(get('select public.paper_capital_receipt(null,null)'))==500
  checks.append('soft_limits_stop_entries_hard_limits_pause_and_bounded_exports_keep_original_purchase_evidence')
  print(json.dumps({'checks':checks,'count':len(checks)},indent=2))
 finally:admin_query('drop database '+name+' with(force)')
if __name__=='__main__':main()
