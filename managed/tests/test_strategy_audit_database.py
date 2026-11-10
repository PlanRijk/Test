"""End-to-end synthetic guarded buys/sells in an isolated local database."""
import copy,json,secrets,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from scripts.deploy_managed import literal,jsql,import_sql
from scripts.company_entries import protocol as company_protocol
from scripts.net_profit_exits import protocol as exit_protocol
from scripts.strategy_audit import protocol
from managed.tests.test_database import query as admin,command,environment
def main():
 name='paperlab_audited_'+secrets.token_hex(4);admin('create database '+name)
 def q(s,error=None):
  r=subprocess.run(command+['-d',name],input=s.encode(),capture_output=True,env=environment)
  if error:assert r.returncode and error in r.stderr.decode(),r.stderr.decode()
  elif r.returncode:raise RuntimeError(r.stderr.decode()[-2500:])
  return r.stdout.decode().strip().splitlines()[-1]if r.stdout.strip()else''
 def get(s):return json.loads(q(s)or'null')
 def node(code,x=None):
  r=subprocess.run(['node','--input-type=module','-e',code],input=json.dumps(x).encode(),cwd=ROOT,capture_output=True)
  if r.returncode:raise RuntimeError(r.stderr.decode()[-2000:])
  return json.loads(r.stdout)
 try:
  for p in sorted((ROOT/'managed/sql').glob('*.sql')):q(p.read_text())
  cp=company_protocol();ep=exit_protocol();p=protocol()
  f=node("""import{capitalFixture}from'./managed/tests/capital-fixture.mjs';import{dossier,daily}from'./managed/tests/company-fixture.mjs';import{BY_SYMBOL}from'./managed/functions/_shared/catalogue.js';import{possibleSession}from'./managed/functions/_shared/engine.js';import{learningFingerprint}from'./managed/functions/_shared/learning-runtime.js';import{MULTIDAY_POLICY}from'./managed/functions/_shared/capital-multiday.js';import{MULTIDAY_IMPLEMENTATION_SHA}from'./managed/functions/_shared/multiday-implementation.js';import{CAPITAL_IMPLEMENTATION_SHA}from'./managed/functions/_shared/capital-implementation.js';const t=Date.now(),symbol=possibleSession(BY_SYMBOL.AAPL,t)?'AAPL':'AZN.L',f=await capitalFixture([symbol],t-120000),d=dossier(t);f.symbol=symbol;d.symbol=symbol;d.financial.currency=BY_SYMBOL[symbol].currency;d.market_closes=daily(t);f.dossier=d;f.market.multi_market.cost_assumptions.other_minimum_commission_eur=.5;f.market.multi_market.cost_assumptions.foreign_buy_reserve_rate=0;f.policy.reference_fingerprint=await learningFingerprint(f.market);f.horizon={...MULTIDAY_POLICY,implementation_sha256:MULTIDAY_IMPLEMENTATION_SHA,base_implementation_sha256:CAPITAL_IMPLEMENTATION_SHA};console.log(JSON.stringify(f));""")
  k=f['symbol'];q(import_sql(f['market'],{'trades':[],'events':[],'equity':[],'observations':[]}));q('select public.paper_capital_configure('+jsql(f['policy'])+','+jsql(f['state'])+')');q("select public.paper_capital_action(null,'pause')");q('select public.paper_capital_set_horizon('+jsql(f['horizon'])+')');q("select public.paper_capital_action(null,'resume')");q('select public.paper_company_configure('+jsql(cp['policy'])+','+jsql(cp['catalogue'])+')');q('select public.paper_net_exit_configure('+jsql(ep)+')')
  owner='11111111-1111-4111-8111-111111111111';q('update paperlab.settings set owner_id='+literal(owner));doc=f['dossier'];doc['known_at']=doc['checked_at'];q('select public.paper_company_save('+jsql(doc)+')');doc['review']['symbol']=k;q('select public.paper_company_review_save('+jsql(doc['review'])+')')
  before=get('select state from paperlab.capital_runtime');control=get('select state from paperlab.portfolio');cfg='select public.paper_strategy_audit_configure('+jsql(p)+')';profile=q(cfg);assert q(cfg)==profile;assert before==get('select state from paperlab.capital_runtime');assert control==get('select state from paperlab.portfolio')
  bad=copy.deepcopy(p);bad['implementation_sha256']='0'*64;q('select public.paper_strategy_audit_configure('+jsql(bad)+')','Strategy audit epoch frozen');assert get('select public.paper_net_exit_claim(null,1)')is None;assert q("select public.paper_net_exit_commit(null,'{}')")=='f'
  for role in['anon','authenticated']:
   for cmd in['select *from paperlab.strategy_audit_runtime','select public.paper_strategy_audit_read(null)','select public.paper_exit_audit_input(null)','select public.paper_audited_claim(null,1)']:q('set role '+role+';'+cmd,'permission denied')
  q('set role service_role;'+cfg,'permission denied');q('set role service_role;select public.paper_net_exit_claim_audit_base_v1(null,1)','permission denied');q('select public.paper_strategy_audit_read(null)','Owner required')
  for stage,factor in enumerate([1,1,1.15,1.15,1]):
   q('update paperlab.portfolio set last_attempt=null,lease=null,lease_until=null;update paperlab.capital_runtime set last_attempt=null,token=null,lease_until=null')
   m=get('select public.paper_claim_tick(true)');assert m;c=get('select public.paper_audited_claim('+literal(m['token'])+'::uuid,'+str(m['revision'])+')');assert c and c['audit_profile']==profile
   out=node("""import fs from'node:fs';import{stepCapitalAudited}from'./managed/functions/_shared/strategy-entry-audit.js';import{tick}from'./managed/functions/_shared/engine.js';const x=JSON.parse(fs.readFileSync(0,'utf8')),t=Date.now(),b=x.batch,q=b.quotes[x.symbol];q.bid*=x.factor;q.ask*=x.factor;q.time=new Date(t-1).toISOString();q.session_start=new Date(t-3600000).toISOString();q.session_end=new Date(t+3600000).toISOString();console.log(JSON.stringify({capital:await stepCapitalAudited(x.capital,x.market,b,t),main:tick(x.market,b,t)}));""",{'capital':c,'market':m['state'],'batch':f['batch'],'symbol':k,'factor':factor})
   assert q('select public.paper_commit_tick('+literal(m['token'])+'::uuid,'+str(m['revision'])+','+jsql(out['main'])+')')=='t';obj=out['capital'];commit=lambda o:'select public.paper_audited_commit('+literal(c['token'])+'::uuid,'+jsql(o)+')'
   if stage==1:
    assert obj['trades'][0]['side']=='koop'
    for field,value in[('round_trip_cost_fraction',.02),('estimated_stop_loss_eur',30),('held_stop_risk_eur',160)]:
     bad=copy.deepcopy(obj);bad['trades'][0]['snapshot']['entry_audit'][field]=value;q(commit(bad),'Entry cost, risk or cooldown proof rejected')
    bad=copy.deepcopy(obj);bad['state']['cash']+=1;q(commit(bad),'Capital ledger mismatch')
   if stage==3:
    assert obj['trades'][0]['side']=='verkoop';bad=copy.deepcopy(obj);bad['state']['risk']['cooldowns'].pop(k);q(commit(bad),'Post-sale cooldown required')
   if stage==4:assert c['recent_exits'].get(k);assert obj['summary']['entry_audit']['counts']['reentry_cooldown']==1;assert not obj['trades']and not obj['state']['pending']
   assert q(commit(obj))=='t';assert q(commit(obj))=='f'
  view=get('set role service_role;select public.paper_strategy_audit_read('+literal(owner)+'::uuid)');assert view['statistics']['closed']==1;assert view['statistics']['audited_entry_closed']==1;assert view['statistics']['net_exit_closed']==1;assert abs(view['statistics']['gross_before_costs_eur']-view['statistics']['costs_and_reserves_eur']-view['statistics']['net_eur'])<1e-6
  print('Strategy audit DB passed: immutable safe transition, owner-only reports, no old worker bypass, genuine audited EUR500 purchase and sale, cost/risk proof enforcement, one-use leases, conserved ledger, 24h reentry block and correctly separated performance cohorts.')
 finally:admin('drop database '+name+' with(force)')
if __name__=='__main__':main()
