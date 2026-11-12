"""End-to-end synthetic guarded buys/sells in an isolated local database."""
import copy,json,secrets,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from scripts.deploy_managed import literal,jsql,import_sql
from scripts.company_entries import protocol as company_protocol
from scripts.net_profit_exits import protocol as exit_protocol
from scripts.strategy_audit import protocol as audit_protocol
from scripts.daily_weekly_swing import protocol
from managed.tests import test_database as db
db.command[db.command.index('paperlab-sql-check')]='paperlab-research-sql'
admin=db.query;command=db.command;environment=db.environment
def main():
 name='paperlab_swing_'+secrets.token_hex(4);admin('create database '+name)
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
  q('create schema cron;create table cron.job(jobid bigint,jobname text,active boolean);create table cron.job_run_details(runid bigint,jobid bigint,start_time timestamptz,end_time timestamptz,status text)')
  for p in sorted((ROOT/'managed/sql').glob('*.sql')):q(p.read_text())
  cp=company_protocol();ep=exit_protocol();ap=audit_protocol();p=protocol()
  f=node("""import{capitalFixture}from'./managed/tests/capital-fixture.mjs';import{dossier,daily}from'./managed/tests/company-fixture.mjs';import{BY_SYMBOL}from'./managed/functions/_shared/catalogue.js';import{possibleSession}from'./managed/functions/_shared/engine.js';import{learningFingerprint}from'./managed/functions/_shared/learning-runtime.js';import{MULTIDAY_POLICY}from'./managed/functions/_shared/capital-multiday.js';import{MULTIDAY_IMPLEMENTATION_SHA}from'./managed/functions/_shared/multiday-implementation.js';import{CAPITAL_IMPLEMENTATION_SHA}from'./managed/functions/_shared/capital-implementation.js';const t=Date.now(),symbol=possibleSession(BY_SYMBOL.AAPL,t)?'AAPL':'AZN.L',f=await capitalFixture([symbol],t-120000),d=dossier(t);f.symbol=symbol;d.symbol=symbol;d.financial.currency=BY_SYMBOL[symbol].currency;d.market_closes=Array.from({length:20},(_,i)=>({day:new Date(t-(20-i)*86400000).toISOString().slice(0,10),close:97+i*.15,observed_at:new Date(t-3600000).toISOString()}));f.dossier=d;f.market.multi_market.cost_assumptions.other_minimum_commission_eur=.5;f.market.multi_market.cost_assumptions.foreign_buy_reserve_rate=0;f.policy.reference_fingerprint=await learningFingerprint(f.market);f.horizon={...MULTIDAY_POLICY,implementation_sha256:MULTIDAY_IMPLEMENTATION_SHA,base_implementation_sha256:CAPITAL_IMPLEMENTATION_SHA};console.log(JSON.stringify(f));""")
  k=f['symbol'];q(import_sql(f['market'],{'trades':[],'events':[],'equity':[],'observations':[]}));q('select public.paper_capital_configure('+jsql(f['policy'])+','+jsql(f['state'])+')');q("select public.paper_capital_action(null,'pause')");q('select public.paper_capital_set_horizon('+jsql(f['horizon'])+')');q("select public.paper_capital_action(null,'resume')");q('select public.paper_company_configure('+jsql(cp['policy'])+','+jsql(cp['catalogue'])+')');q('select public.paper_net_exit_configure('+jsql(ep)+')')
  owner='11111111-1111-4111-8111-111111111111';q('update paperlab.settings set owner_id='+literal(owner));doc=f['dossier'];doc['known_at']=doc['checked_at'];q('select public.paper_company_save('+jsql(doc)+')');doc['review']['symbol']=k;q('select public.paper_company_review_save('+jsql(doc['review'])+')')
  q('select public.paper_strategy_audit_configure('+jsql(ap)+')');q('select public.paper_priority_configure()')
  before=get('select state from paperlab.capital_runtime');cfg='select public.paper_swing_configure('+jsql(p)+')';profile=q(cfg);assert q(cfg)==profile
  after=get('select state from paperlab.capital_runtime');assert before==after
  assert get('select public.paper_audited_claim(null,1)')is None;assert q("select public.paper_audited_commit(null,'{}')")=='f'
  for role in ['anon','authenticated','service_role']:
   q('set role '+role+';'+cfg,'permission denied');q('set role '+role+";select paperlab.swing_ledger_commit(null,'{}')",'permission denied')
  q('select public.paper_priority_read(null)','Owner required')
  def round(stage,factor=1):
   q('update paperlab.portfolio set last_attempt=null,lease=null,lease_until=null;update paperlab.capital_runtime set last_attempt=null,token=null,lease_until=null')
   m=get('select public.paper_claim_tick(true)');assert m
   c=get('select public.paper_swing_claim('+literal(m['token'])+'::uuid,'+str(m['revision'])+')');assert c and c['swing_profile']==profile
   out=node("""import fs from'node:fs';import{stepCapitalSwing}from'./managed/functions/_shared/capital-swing.js';import{tick}from'./managed/functions/_shared/engine.js';const x=JSON.parse(fs.readFileSync(0,'utf8')),t=Date.now()-(x.stage===0?60000:0),b=x.batch,k=x.k,q=b.quotes[k];q.bid*=x.factor;q.ask*=x.factor;q.time=new Date(t-2).toISOString();q.session_start=new Date(t-3600000).toISOString();q.session_end=new Date(t+3600000).toISOString();console.log(JSON.stringify({capital:await stepCapitalSwing(x.capital,x.market,b,t),main:tick(x.market,b,t)}));""",{'capital':c,'market':m['state'],'batch':f['batch'],'stage':stage,'k':k,'factor':factor})
   assert q('select public.paper_commit_tick('+literal(m['token'])+'::uuid,'+str(m['revision'])+','+jsql(out['main'])+')')=='t'
   return c,out['capital']
  commit=lambda lease,obj:'select public.paper_swing_commit('+literal(lease['token'])+'::uuid,'+jsql(obj)+')'
  c,out=round(0);assert out['state']['pending'];assert not out['trades'];assert q(commit(c,out))=='t'
  c,out=round(1);assert len(out['trades'])==1,out['summary'];assert out['trades'][0]['side']=='koop';assert 100<=out['state']['positions'][k]['cost']*5<=500
  bad=copy.deepcopy(out);bad['trades'][0]['snapshot']['swing_entry']['estimated_stop_loss_eur']=21;q(commit(c,bad),'Swing entry risk/cost proof rejected')
  bad=copy.deepcopy(out);bad['trades'][0]['snapshot']['purchase_rationale']['company_execution_check']['assessment']['pillars']['moat']['status']='unknown';q(commit(c,bad),'Current five-pillar evidence required')
  bad=copy.deepcopy(out);bad['state']['cash']+=1;q(commit(c,bad),'Capital ledger mismatch')
  assert q(commit(c,out))=='t';assert q(commit(c,out))=='f'
  bought_state=copy.deepcopy(out['state'])
  # Genuine negative stop sale may bypass profit target, then enforces cooldown.
  c,out=round(2,.94);assert out['state']['pending'][0]['risk_exit'];assert q(commit(c,out))=='t'
  c,out=round(3,.94);assert out['trades'][0]['side']=='verkoop'and out['trades'][0]['pnl']<0
  assert q(commit(c,out))=='t';assert q('select count(*)from paperlab.capital_trades')=='2'
  c,out=round(4);assert not out['trades']and not out['state']['pending'];assert q(commit(c,out))=='t'
  # Additional synthetic scenarios preserve the real profit/time commit validation.
  q('update paperlab.capital_runtime set state='+jsql(bought_state))
  c,out=round(2,1.2);assert out['state']['pending'];assert q(commit(c,out))=='t'
  c,out=round(3,1.2);assert out['trades'][0]['pnl']>=out['trades'][0]['snapshot']['profit_exit']['required_net_profit_eur'];assert q(commit(c,out))=='t'
  old=copy.deepcopy(bought_state);old['positions'][k]['time']='2026-09-01T12:00:00Z';q('update paperlab.capital_runtime set state='+jsql(old))
  c,out=round(2);assert out['state']['pending'][0]['swing_exit_evidence']['kind']=='time';assert q(commit(c,out))=='t'
  c,out=round(3);assert out['trades'][0]['snapshot']['profit_exit']['protective_exception'];assert q(commit(c,out))=='t'
  report=get('select public.paper_strategy_audit_read('+literal(owner)+'::uuid)');assert any(x['entry_cohort']=='quality-swing-paper-v1'for x in report['cohorts'])
  # Immutable epoch refuses a silently edited code fingerprint.
  bad=copy.deepcopy(p);bad['implementation_sha256']='0'*64;q('select public.paper_swing_configure('+jsql(bad)+')','Swing epoch frozen')
  print('Swing SQL integration passed: preserved transition, immutable epoch, private ledger, disabled old route, genuine risk-sized purchase and stop sale, five-pillar/risk/cash corruption rejected, cooldown and one-use leases.')
 finally:admin('drop database '+name+' with(force)')
if __name__=='__main__':main()
