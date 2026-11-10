"""Isolated SQL regression for source failover, proof, budgets and fail-closed use."""
import copy,json,secrets,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from scripts.deploy_managed import literal,jsql
from scripts.source_resilience import protocol
from managed.tests.test_database import query as admin,command,environment
def main():
 name='paperlab_sources_'+secrets.token_hex(4);admin('create database '+name)
 def q(s,error=None):
  r=subprocess.run(command+['-d',name],input=s.encode(),capture_output=True,env=environment)
  if error:assert r.returncode and error in r.stderr.decode(),r.stderr.decode()
  elif r.returncode:raise RuntimeError(r.stderr.decode()[-3000:])
  return r.stdout.decode().strip().splitlines()[-1]if r.stdout.strip()else''
 def get(s):return json.loads(q(s)or'null')
 try:
  for p in sorted((ROOT/'managed/sql').glob('*.sql')):q(p.read_text())
  d=protocol();old=json.loads(subprocess.check_output(['node','--input-type=module','-e',"import{COVERAGE_POLICY}from'./managed/functions/_shared/company-coverage.js';import{COMPANY_SOURCES}from'./managed/functions/_shared/company-source-catalogue.js';console.log(JSON.stringify({p:COVERAGE_POLICY,c:COMPANY_SOURCES}));"],cwd=ROOT))
  q('select public.paper_company_coverage_configure('+jsql(old['p'])+','+jsql(old['c'])+')');q('update paperlab.company_runtime set catalogue='+jsql(old['c']))
  owner='11111111-1111-4111-8111-111111111111';q('update paperlab.settings set owner_id='+literal(owner));at=q('select now()::text')
  rows=[{'symbol':c['symbol'],'primary':{'url':c['primary_url'],'status':200},'observation':{'known_at':at,'values':{},'financial':{'revenue':100}},'financial_fingerprint':'0'*64,'secondary_status':'observed'}for c in old['c']]
  for i in range(0,100,10):q('select public.paper_company_coverage_import('+jsql(rows[i:i+10])+')')
  cfg='select public.paper_source_configure('+jsql(d['policy'])+','+jsql(d['registry'])+')';profile=q(cfg);assert q(cfg)==profile
  changed=copy.deepcopy(d['policy']);changed['implementation_sha256']='0'*64;q('select public.paper_source_configure('+jsql(changed)+','+jsql(d['registry'])+')','Source protocol frozen')
  reference={'version':'company-dossier-v1','symbol':'AAPL','known_at':at,'checked_at':at,'financial':{'annual_end':'2025-12-31','currency':'USD','revenue':100},'sources':[]};q('select public.paper_company_save('+jsql(reference)+')')
  seed=[{'symbol':c['symbol'],'reference':reference if c['symbol']=='AAPL'else None,'record':{'version':'source-resilience-v1','symbol':c['symbol'],'route':'cached_reference_audit','last_financial_success_at':at,'trade_approval':False,'same_provider_independent':False,'verification':{'status':'missing_primary_or_secondary','critical_conflict':False}}}for c in old['c']]
  for i in range(0,100,10):q('select public.paper_source_seed('+jsql(seed[i:i+10])+')')
  assert get('select public.paper_source_read('+literal(owner)+'::uuid)')['counts']['companies']==100
  for role in['anon','authenticated']:
   for cmd in['select public.paper_source_read(null)','select *from paperlab.source_reliability','select public.paper_source_claim(true)']:q('set role '+role+';'+cmd,'permission denied')
  q('set role service_role;'+cfg,'permission denied');q("set role service_role;select public.paper_source_seed('[]')",'permission denied');q('set role service_role;select public.paper_company_coverage_claim_source_base_v1(true)','permission denied');q('select public.paper_source_read(null)','Owner required')
  assert get('select public.paper_company_coverage_claim(true)')is None;assert q("select public.paper_company_coverage_commit(null,'[]')")=='f'
  a=get('select public.paper_source_claim(true)');assert a and a['source_profile']==profile;assert len(a['targets'])==6;assert get('select public.paper_source_claim(true)')is None
  proof={'version':'source-resilience-v1','symbol':'AAPL','route':'same_provider_failover','last_financial_success_at':at,'attempted_at':at,'trade_approval':False,'same_provider_independent':False,'verification':{'status':'matched_reported_figures','critical_conflict':False}}
  row={'symbol':'AAPL','source_bytes':1000,'financial_fingerprint':'0'*64,'observation':rows[0]['observation'],'reliability':proof}
  commit=lambda token,r:'select public.paper_source_commit('+literal(token)+'::uuid,'+jsql([r])+')'
  bad=copy.deepcopy(row);bad['reliability']['trade_approval']=True;q(commit(a['token'],bad),'Source evidence cannot approve trades')
  assert q(commit(a['token'],row))=='t';assert q(commit(a['token'],row))=='f';assert get('select record from paperlab.company_dossiers order by known_at desc limit 1')['financial']['revenue']==100
  b=get('select public.paper_source_claim(true)');row['financial_fingerprint']='1'*64;row['reliability']['verification']={'status':'conflict','critical_conflict':True,'comparisons':[{'metric':'revenue','status':'difference_requires_review'}]};assert q(commit(b['token'],row))=='t'
  latest=get("select record from paperlab.company_dossiers where symbol='AAPL'order by known_at desc,id desc limit 1");assert latest['status']=='source_conflict_requires_review';assert latest['financial']=={}
  c=get('select public.paper_source_claim(true)');failure={'symbol':'AAPL','source_bytes':2000,'reliability':{**proof,'route':'cached_only'}};assert q(commit(c['token'],failure))=='t'
  cached=get("select record from paperlab.company_coverage where symbol='AAPL'");assert cached['observation']['known_at']==at;assert cached['secondary_status']=='source_unavailable';assert get("select reference from paperlab.source_reliability where symbol='AAPL'")['financial']['revenue']==100
  q('update paperlab.company_coverage_usage set estimated_bytes=19999999');assert get('select public.paper_source_claim(true)')is None
  assert q('select count(*)from paperlab.capital_trades')=='0';assert q('select count(*)from paperlab.trades')=='0'
  print('Source DB passed: 100 private plans, frozen original budgets, operator-only seeding, bounded claims, one-use commits, material mismatch invalidation, preserved cached date/reference and no orders or approval bypass.')
 finally:admin('drop database '+name+' with(force)')
if __name__=='__main__':main()
