"""Local PostgreSQL integration; synthetic European quotes, no network or live writes."""
import copy,json,secrets,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from scripts.deploy_managed import literal,jsql,import_sql
from scripts.company_entries import protocol
from managed.tests.test_database import query as admin,command,environment

def main():
 name='paperlab_company_'+secrets.token_hex(4);admin('create database '+name)
 def q(text,error=None):
  r=subprocess.run(command+['-d',name],input=text.encode(),capture_output=True,env=environment)
  if error:assert r.returncode and error in r.stderr.decode(),r.stderr.decode()
  elif r.returncode:raise RuntimeError(r.stderr.decode()[-4000:])
  return r.stdout.decode().strip().splitlines()[-1]if r.stdout.strip()else''
 def get(s):return json.loads(q(s)or'null')
 def node(code,x=None):return json.loads(subprocess.run(['node','--input-type=module','-e',code],input=json.dumps(x).encode(),cwd=ROOT,capture_output=True,check=True).stdout)
 try:
  for p in sorted((ROOT/'managed/sql').glob('*.sql')):q(p.read_text())
  f=node("""import{capitalFixture}from'./managed/tests/capital-fixture.mjs';import{dossier,daily}from'./managed/tests/company-fixture.mjs';import{MULTIDAY_POLICY}from'./managed/functions/_shared/capital-multiday.js';import{MULTIDAY_IMPLEMENTATION_SHA}from'./managed/functions/_shared/multiday-implementation.js';import{CAPITAL_IMPLEMENTATION_SHA}from'./managed/functions/_shared/capital-implementation.js';const t=Date.now(),f=await capitalFixture(['AZN.L'],t-300000),d=dossier(t);d.symbol='AZN.L';d.financial.currency='GBP';d.market_closes=daily(t);f.dossier=d;f.horizon={...MULTIDAY_POLICY,implementation_sha256:MULTIDAY_IMPLEMENTATION_SHA,base_implementation_sha256:CAPITAL_IMPLEMENTATION_SHA};console.log(JSON.stringify(f));""")
  q(import_sql(f['market'],{'trades':[],'events':[],'equity':[],'observations':[]}));q('select public.paper_capital_configure('+jsql(f['policy'])+','+jsql(f['state'])+')');q("select public.paper_capital_action(null,'pause')");q('select public.paper_capital_set_horizon('+jsql(f['horizon'])+')');q("select public.paper_capital_action(null,'resume')")
  before=get('select state from paperlab.capital_runtime');base=get('select state from paperlab.portfolio');p=protocol();cfg='select public.paper_company_configure('+jsql(p['policy'])+','+jsql(p['catalogue'])+')';profile=q(cfg);assert q(cfg)==profile
  assert get('select state from paperlab.capital_runtime')==before;assert get('select state from paperlab.portfolio')==base
  changed=copy.deepcopy(p['policy']);changed['max_pe']=99;q('select public.paper_company_configure('+jsql(changed)+','+jsql(p['catalogue'])+')','Existing company policy frozen')
  owner='11111111-1111-4111-8111-111111111111';q('update paperlab.settings set owner_id='+literal(owner))
  for role in['anon','authenticated']:
   q('set role '+role+';select public.paper_company_read(null)','permission denied');q('set role '+role+';select public.paper_company_claim(null,1)','permission denied');q('set role '+role+';select *from paperlab.company_dossiers','permission denied')
  q('select public.paper_company_read(null)','Owner required');q('set role service_role;'+cfg,'permission denied');q("set role service_role;select public.paper_company_review_save('{}')",'permission denied')
  doc=f['dossier'];doc['known_at']=doc['checked_at'];did=q('select public.paper_company_save('+jsql(doc)+')');assert q('select public.paper_company_save('+jsql(doc)+')')==did
  review=doc['review'];review['symbol']='AZN.L';q('select public.paper_company_review_save('+jsql(review)+')')
  # Every stage uses the real private leases and original ledger conservation.
  for stage in[0,1]:
   q("update paperlab.portfolio set last_attempt=null,lease=null,lease_until=null;update paperlab.capital_runtime set last_attempt=null,token=null,lease_until=null")
   m=get('select public.paper_claim_tick(true)');assert m
   args=literal(m['token'])+'::uuid,'+str(m['revision']);c=get('select public.paper_company_claim('+args+')');assert c and'AZN.L'in c['company_dossiers'];assert get('select public.paper_company_claim('+args+')')is None
   now_offset=300000 if stage==0 else 0
   out=node("""import fs from'node:fs';import{stepCapitalCompany}from'./managed/functions/_shared/capital-company.js';import{tick}from'./managed/functions/_shared/engine.js';const x=JSON.parse(fs.readFileSync(0,'utf8')),t=Date.now()-x.offset,b=x.batch;b.quotes['AZN.L'].time=new Date(t-1000).toISOString();b.quotes['AZN.L'].session_start=new Date(t-3600000).toISOString();b.quotes['AZN.L'].session_end=new Date(t+3600000).toISOString();console.log(JSON.stringify({capital:await stepCapitalCompany(x.capital,x.market,b,t),main:tick(x.market,b,t)}));""",{'capital':c,'market':m['state'],'batch':f['batch'],'offset':now_offset})
   assert q('select public.paper_commit_tick('+literal(m['token'])+'::uuid,'+str(m['revision'])+','+jsql(out['main'])+')')=='t'
   commit=lambda obj:'select public.paper_company_commit('+literal(c['token'])+'::uuid,'+jsql(obj)+')'
   if stage:
    assert len(out['capital']['trades'])==1
    bad=copy.deepcopy(out['capital']);bad['trades'][0]['snapshot']['purchase_rationale']['company_execution_check']['assessment']['pillars']['moat']['status']='unknown';q(commit(bad),'Five-pillar entry evidence required')
    bad=copy.deepcopy(out['capital']);bad['state']['cash']+=1;q(commit(bad),'Capital ledger mismatch')
   assert q(commit(out['capital']))=='t';assert q(commit(out['capital']))=='f'
  assert int(q('select count(*)from paperlab.capital_trades'))==1
  assert get('select state from paperlab.capital_runtime')['cash']==1900
  # Older workers receive an explicit entry prohibition after the transition.
  q('update paperlab.portfolio set last_attempt=null;update paperlab.capital_runtime set last_attempt=null');m=get('select public.paper_claim_tick(true)');c=get('select public.paper_capital_claim_multiday('+literal(m['token'])+'::uuid,'+str(m['revision'])+')');assert c['allow_entries']is False
  q('select public.paper_capital_fail('+literal(c['token'])+'::uuid)')
  # Collection reserves before access, then invalidates current evidence on failure.
  cl=get('select public.paper_company_collect_claim()');assert cl;assert get('select public.paper_company_collect_claim()')is None;q('select public.paper_company_collect_fail('+literal(cl['token'])+'::uuid)');assert q('select status from paperlab.company_runtime')=='source_unavailable'
  q('update paperlab.company_usage set attempts=2');assert get('select public.paper_company_collect_claim()')is None
  print('Company DB passed: preserved capital/risk, immutable phase, private owner evidence, qualitative approval restricted, lease idempotence, genuine 500 EUR ledger fill, unknown-pillar rejection, legacy-worker gate and bounded collection.')
 finally:admin('drop database '+name+' with(force)')
if __name__=='__main__':main()
