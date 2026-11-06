"""Versioned horizon migration, preserved balances and guarded commits in local DB."""
import copy,json,secrets,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from scripts.deploy_managed import literal,jsql,import_sql
from scripts.multiday_study import policy,fingerprint
from managed.tests.test_database import query as admin_query,command,environment

def main():
 name='paperlab_multiday_'+secrets.token_hex(5);admin_query('create database '+name)
 def q(text,error=None):
  r=subprocess.run(command+['-d',name],input=text.encode(),capture_output=True,env=environment)
  if error:assert r.returncode and error in r.stderr.decode(),r.stderr.decode()
  elif r.returncode:raise RuntimeError(r.stderr.decode()[-4500:])
  return r.stdout.decode().strip().splitlines()[-1] if r.stdout.strip() else ''
 def get(text):return json.loads(q(text) or 'null')
 def node(code,obj=None):
  r=subprocess.run(['node','--input-type=module','-e',code],input=json.dumps(obj).encode(),capture_output=True,cwd=ROOT,check=True);return json.loads(r.stdout)
 try:
  fingerprint()
  for p in sorted((ROOT/'managed/sql').glob('*.sql')):q(p.read_text())
  code="""import {capitalFixture} from './managed/tests/capital-fixture.mjs';import {stepCapital} from './managed/functions/_shared/capital-study.js';const now=Date.now(),f=await capitalFixture(['AAPL'],now-600000);for(const x of Object.values(f.batch.quotes)){x.session_start=new Date(now).toISOString().slice(0,10)+'T14:30:00Z';x.session_end=new Date(now).toISOString().slice(0,10)+'T21:00:00Z';}const a=await stepCapital(f,f.market,f.batch,now-600000);const b=structuredClone(f.batch);b.quotes.AAPL.time=new Date(now-301000).toISOString();const bought=await stepCapital({...f,state:a.state},f.market,b,now-300000);bought.state.pending=[{symbol:'AAPL',side:'verkoop',time:new Date(now-60000).toISOString(),reason:'Stopverlies van 1,5% bereikt.',risk_exit:true},{symbol:'MSFT',side:'verkoop',time:new Date(now-60000).toISOString(),reason:'Dagsluiting van de eigen beurs.',risk_exit:true},{symbol:'MSFT',side:'koop',time:new Date(now-60000).toISOString(),reason:'old entry',risk_exit:false}];console.log(JSON.stringify({f,bought}));"""
  fixture=node(code);f=fixture['f'];bought=fixture['bought'];assert len(bought['trades'])==1
  q(import_sql(f['market'],{'trades':[],'events':[],'equity':[],'observations':[]}));q('select public.paper_capital_configure('+jsql(f['policy'])+','+jsql(f['state'])+')')
  q('update paperlab.capital_runtime set state='+jsql(bought['state'])+',summary='+jsql(bought['summary']))
  p=policy(f['policy']['implementation_sha256']);configure='select public.paper_capital_set_horizon('+jsql(p)+')';q(configure,'Pause capital before horizon migration')
  before=q("select md5(state::text) from paperlab.portfolio");q("select public.paper_capital_action(null,'pause')");profile=q(configure);assert len(profile)==64;assert q(configure)==profile
  r=get('select to_jsonb(r) from paperlab.capital_runtime r');assert r['state']['cash']==bought['state']['cash'];assert r['state']['positions']==bought['state']['positions'];assert r['state']['fees']==bought['state']['fees'];assert r['state']['risk']==bought['state']['risk'];assert len(r['state']['pending'])==1 and r['state']['pending'][0]['symbol']=='AAPL'
  epoch=get('select to_jsonb(e) from paperlab.capital_policy_epochs e');assert len(epoch['cancelled_orders'])==2;assert len(epoch['carry_positions'])==1;assert q("select md5(state::text) from paperlab.portfolio")==before
  bad=copy.deepcopy(p);bad['review_horizon_sessions']=21;q('select public.paper_capital_set_horizon('+jsql(bad)+')','Invalid multiday policy')
  bad=copy.deepcopy(p);bad['implementation_sha256']='0'*64;q('select public.paper_capital_set_horizon('+jsql(bad)+')','Existing multiday policy frozen')
  for role in ['anon','authenticated','service_role']:
   q('set role '+role+';select public.paper_capital_set_horizon('+jsql(p)+')','permission denied');q('set role '+role+';select * from paperlab.capital_policy_epochs','permission denied');q('set role '+role+';select public.paper_capital_claim_base_v1(null,1)','permission denied');q('set role '+role+";select public.paper_capital_commit_base_v1(null,'{}')",'permission denied')
  for role in ['anon','authenticated']:q('set role '+role+';select public.paper_capital_claim_multiday(null,1)','permission denied')
  q("select public.paper_capital_action(null,'resume')");m=get('select public.paper_claim_tick(true)');assert m
  claim_args=literal(m['token'])+'::uuid,'+str(m['revision']);assert get('select public.paper_capital_claim('+claim_args+')') is None
  c=get('select public.paper_capital_claim_multiday('+claim_args+')');assert c and c['execution_profile']==profile;assert get('select public.paper_capital_claim_multiday('+claim_args+')') is None
  code="""import fs from 'node:fs';import {stepCapitalMultiday} from './managed/functions/_shared/capital-multiday.js';import {tick} from './managed/functions/_shared/engine.js';const x=JSON.parse(fs.readFileSync(0,'utf8')),now=Date.now(),b=x.batch;b.quotes.AAPL.bid*=.90;b.quotes.AAPL.ask*=.90;b.quotes.AAPL.time=new Date(now-1000).toISOString();console.log(JSON.stringify({capital:await stepCapitalMultiday(x.capital,x.market,b,now),main:tick(x.market,b,now)}));"""
  out=node(code,{'capital':c,'market':m['state'],'batch':f['batch']});cap=out['capital'];assert len(cap['trades'])==1;assert cap['trades'][0]['snapshot']['entry_capital_protocol']=='capital-10k-v1'
  commit=lambda value:'select public.paper_capital_commit_multiday('+literal(c['token'])+'::uuid,'+jsql(value)+')'
  assert q(commit(cap))=='f' # Original market commit is still required.
  assert q('select public.paper_commit_tick('+literal(m['token'])+'::uuid,'+str(m['revision'])+','+jsql(out['main'])+')')=='t'
  assert q('select public.paper_capital_commit('+literal(c['token'])+'::uuid,'+jsql(cap)+')')=='f'
  bad=copy.deepcopy(cap);bad['execution_profile']='0'*64;q(commit(bad),'Invalid multiday epoch')
  bad=copy.deepcopy(cap);bad['trades'][0]['reason']='Dagsluiting van de eigen beurs.';q(commit(bad),'Legacy or unexplained multiday receipt')
  bad=copy.deepcopy(cap);bad['state']['cash']+=1;q(commit(bad),'Capital ledger mismatch')
  assert q(commit(cap))=='t';assert q(commit(cap))=='f';assert int(q('select count(*) from paperlab.capital_trades'))==1;assert q('select count(*) from paperlab.capital_policy_epochs')=='1'
  state=q('select md5(state::text) from paperlab.capital_runtime');assert q(configure)==profile;assert q('select md5(state::text) from paperlab.capital_runtime')==state
  # Reapplying the feature migration preserves the private original helpers.
  q((ROOT/'managed/sql/013_multiday_capital.sql').read_text());assert q('select md5(state::text) from paperlab.capital_runtime')==state
  print('Multiday DB passed: immutable migration audit, cash/holdings/risk preservation, pending-order distinction, private base checks, legacy exclusion, phase binding, main-first atomic conservation, repeat-safe setup.')
 finally:admin_query('drop database '+name+' with(force)')
if __name__=='__main__':main()
