"""Synthetic leases and genuine ledger commits in an isolated local database."""
import copy,json,secrets,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from scripts.deploy_managed import literal,jsql,import_sql
from scripts.company_entries import protocol as company_protocol
from scripts.net_profit_exits import protocol
from managed.tests.test_database import query as admin,command,environment
def main():
 name='paperlab_net_exit_'+secrets.token_hex(4);admin('create database '+name)
 def q(s,error=None):
  r=subprocess.run(command+['-d',name],input=s.encode(),capture_output=True,env=environment)
  if error:assert r.returncode and error in r.stderr.decode(),r.stderr.decode()
  elif r.returncode:raise RuntimeError(r.stderr.decode()[-3500:])
  return r.stdout.decode().strip().splitlines()[-1]if r.stdout.strip()else''
 def get(s):return json.loads(q(s)or'null')
 def node(code,x=None):
  r=subprocess.run(['node','--input-type=module','-e',code],input=json.dumps(x).encode(),cwd=ROOT,capture_output=True)
  if r.returncode:raise RuntimeError(r.stderr.decode()[-2500:])
  return json.loads(r.stdout)
 try:
  for p in sorted((ROOT/'managed/sql').glob('*.sql')):q(p.read_text())
  cp=company_protocol();p=protocol()
  f=node("""import{capitalFixture}from'./managed/tests/capital-fixture.mjs';import{dossier,daily}from'./managed/tests/company-fixture.mjs';import{MULTIDAY_POLICY}from'./managed/functions/_shared/capital-multiday.js';import{MULTIDAY_IMPLEMENTATION_SHA}from'./managed/functions/_shared/multiday-implementation.js';import{CAPITAL_IMPLEMENTATION_SHA}from'./managed/functions/_shared/capital-implementation.js';const t=Date.now(),f=await capitalFixture(['AZN.L'],t-120000),d=dossier(t);d.symbol='AZN.L';d.financial.currency='GBP';d.market_closes=daily(t);f.dossier=d;f.horizon={...MULTIDAY_POLICY,implementation_sha256:MULTIDAY_IMPLEMENTATION_SHA,base_implementation_sha256:CAPITAL_IMPLEMENTATION_SHA};console.log(JSON.stringify(f));""")
  q(import_sql(f['market'],{'trades':[],'events':[],'equity':[],'observations':[]}));q('select public.paper_capital_configure('+jsql(f['policy'])+','+jsql(f['state'])+')');q("select public.paper_capital_action(null,'pause')");q('select public.paper_capital_set_horizon('+jsql(f['horizon'])+')');q("select public.paper_capital_action(null,'resume')");company_profile=q('select public.paper_company_configure('+jsql(cp['policy'])+','+jsql(cp['catalogue'])+')')
  owner='11111111-1111-4111-8111-111111111111';q('update paperlab.settings set owner_id='+literal(owner))
  doc=f['dossier'];doc['known_at']=doc['checked_at'];q('select public.paper_company_save('+jsql(doc)+')');review=doc['review'];review['symbol']='AZN.L';q('select public.paper_company_review_save('+jsql(review)+')')
  c=get('select public.paper_company_read('+literal(owner)+'::uuid)')
  # Seed a carried holding in the isolated fixture, before the policy transition.
  seeded=node("""import fs from'node:fs';import{stepCapitalCompany}from'./managed/functions/_shared/capital-company.js';const x=JSON.parse(fs.readFileSync(0,'utf8')),t=Date.now()-1000,b=x.f.batch;const input={...x.f,execution_policy:x.f.horizon,execution_profile:'test-horizon',execution_revision:1,company_policy:x.company.runtime.policy,company_profile:x.company.runtime.profile,company_dossiers:x.company.dossiers,company_daily:{'AZN.L':x.f.dossier.market_closes}};b.quotes['AZN.L'].time=new Date(t-61000).toISOString();b.quotes['AZN.L'].session_start=new Date(t-3600000).toISOString();b.quotes['AZN.L'].session_end=new Date(t+3600000).toISOString();const a=await stepCapitalCompany(input,x.f.market,b,t-60000);b.quotes['AZN.L'].time=new Date(t-1000).toISOString();const z=await stepCapitalCompany({...input,state:a.state},x.f.market,b,t);if(z.summary.positions!==1)throw Error('Missing carried fixture');console.log(JSON.stringify(z));""",{'f':f,'company':c})
  q('update paperlab.capital_runtime set state='+jsql(seeded['state'])+',summary='+jsql(seeded['summary']))
  q("update paperlab.capital_runtime set state=jsonb_set(state,'{pending}','[{\"symbol\":\"AZN.L\",\"side\":\"verkoop\",\"risk_exit\":false},{\"symbol\":\"AAPL\",\"side\":\"koop\",\"risk_exit\":false},{\"symbol\":\"AZN.L\",\"side\":\"verkoop\",\"risk_exit\":true}]')")
  before=get('select state from paperlab.capital_runtime');control=get('select state from paperlab.portfolio')
  cfg='select public.paper_net_exit_configure('+jsql(p)+')';profile=q(cfg);assert q(cfg)==profile
  after=get('select state from paperlab.capital_runtime');expected=copy.deepcopy(before);expected['pending']=[o for o in before['pending']if o.get('risk_exit')];assert expected==after;assert q("select jsonb_array_length(cancelled_orders)from paperlab.net_exit_runtime")=='2';q("update paperlab.capital_runtime set state=jsonb_set(state,'{pending}','[]')");assert control==get('select state from paperlab.portfolio')
  bad=copy.deepcopy(p);bad['implementation_sha256']='0'*64;q('select public.paper_net_exit_configure('+jsql(bad)+')','Net exit epoch frozen')
  assert get('select public.paper_company_claim(null,1)')is None;assert q("select public.paper_company_commit(null,'{}')")=='f'
  for role in['anon','authenticated']:
   for cmd in['select *from paperlab.net_exit_runtime','select public.paper_net_exit_read(null)','select public.paper_net_exit_claim(null,1)']:
    q('set role '+role+';'+cmd,'permission denied')
  q('set role service_role;'+cfg,'permission denied');q('set role service_role;select public.paper_company_claim_entry_v1(null,1)','permission denied');q('select public.paper_net_exit_read(null)','Owner required')
  def round(factor):
   q('update paperlab.portfolio set last_attempt=null,lease=null,lease_until=null;update paperlab.capital_runtime set last_attempt=null,token=null,lease_until=null')
   m=get('select public.paper_claim_tick(true)');assert m
   args=literal(m['token'])+'::uuid,'+str(m['revision']);c=get('select public.paper_net_exit_claim('+args+')');assert c and c['exit_profile']==profile
   assert get('select public.paper_net_exit_claim('+args+')')is None
   out=node("""import fs from'node:fs';import{stepCapitalNetExits}from'./managed/functions/_shared/capital-net-exits.js';import{tick}from'./managed/functions/_shared/engine.js';const x=JSON.parse(fs.readFileSync(0,'utf8')),t=Date.now(),b=x.batch,q=b.quotes['AZN.L'];q.bid*=x.factor;q.ask*=x.factor;q.time=new Date(t-2).toISOString();q.session_start=new Date(t-3600000).toISOString();q.session_end=new Date(t+3600000).toISOString();console.log(JSON.stringify({capital:await stepCapitalNetExits(x.capital,x.market,b,t),main:tick(x.market,b,t)}));""",{'capital':c,'market':m['state'],'batch':f['batch'],'factor':factor})
   assert q('select public.paper_commit_tick('+literal(m['token'])+'::uuid,'+str(m['revision'])+','+jsql(out['main'])+')')=='t'
   return c,out['capital']
  c,out=round(1.15);assert len(out['state']['pending'])==1
  commit=lambda lease,obj:'select public.paper_net_exit_commit('+literal(lease['token'])+'::uuid,'+jsql(obj)+')'
  assert q(commit(c,out))=='t'
  c,out=round(1.15);assert len(out['trades'])==1
  bad=copy.deepcopy(out);bad['trades'][0]['pnl']=1;q(commit(c,bad),'Ordinary sale below net target')
  bad=copy.deepcopy(out);bad['trades'][0]['snapshot']['profit_exit']['required_net_profit_eur']=.01;q(commit(c,bad),'Invalid position-linked net target')
  bad=copy.deepcopy(out);bad['trades'][0]['snapshot']['profit_exit']['protective_exception']=True;q(commit(c,bad),'Protective exit evidence mismatch')
  bad=copy.deepcopy(out);bad['state']['cash']+=1;q(commit(c,bad),'Capital ledger mismatch')
  assert q(commit(c,out))=='t';assert q(commit(c,out))=='f';assert out['trades'][0]['pnl']>=out['trades'][0]['snapshot']['profit_exit']['required_net_profit_eur']
  assert q('select count(*)from paperlab.capital_trades')=='1'
  # A separate carried fixture verifies the protective exception through SQL.
  q('update paperlab.capital_runtime set state='+jsql(seeded['state'])+',summary='+jsql(seeded['summary']))
  c,out=round(.98);assert out['state']['pending'][0]['risk_exit'];assert q(commit(c,out))=='t'
  c,out=round(.9);assert out['trades'][0]['pnl']<0;assert out['trades'][0]['snapshot']['profit_exit']['protective_exception'];assert q(commit(c,out))=='t'
  print('Net exits DB passed: unchanged carried ledger and reference, immutable epoch, no legacy worker bypass, private policy, one-use leases, net target rejection, protective proof, genuine positive and protective negative ledger commits.')
 finally:admin('drop database '+name+' with(force)')
if __name__=='__main__':main()
