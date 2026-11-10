"""Synthetic, network-disabled integration for broad financial evidence; no production reads."""
import copy,json,secrets,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from scripts.deploy_managed import jsql,literal
from managed.tests.test_database import query as admin,command,environment

def main():
 name='paperlab_coverage_'+secrets.token_hex(4);admin('create database '+name)
 def q(s,error=None):
  r=subprocess.run(command+['-d',name],input=s.encode(),capture_output=True,env=environment)
  if error:assert r.returncode and error in r.stderr.decode(),r.stderr.decode()
  elif r.returncode:raise RuntimeError(r.stderr.decode()[-3500:])
  return r.stdout.decode().strip().splitlines()[-1]if r.stdout.strip()else''
 def get(s):return json.loads(q(s)or'null')
 try:
  for p in sorted((ROOT/'managed/sql').glob('*.sql')):q(p.read_text())
  d=json.loads(subprocess.check_output(['node','--input-type=module','-e',"import{COVERAGE_POLICY}from'./managed/functions/_shared/company-coverage.js';import{COMPANY_SOURCES}from'./managed/functions/_shared/company-source-catalogue.js';console.log(JSON.stringify({p:COVERAGE_POLICY,c:COMPANY_SOURCES}));"],cwd=ROOT));cfg='select public.paper_company_coverage_configure('+jsql(d['p'])+','+jsql(d['c'])+')';q(cfg)
  q('update paperlab.company_runtime set catalogue='+jsql(d['c']));owner='11111111-1111-4111-8111-111111111111';q('update paperlab.settings set owner_id='+literal(owner));at=q('select now()::text')
  for role in['anon','authenticated']:
   q('set role '+role+';select public.paper_company_coverage_read(null)','permission denied');q('set role '+role+';select *from paperlab.company_coverage','permission denied');q('set role '+role+';select public.paper_company_coverage_claim()','permission denied')
  q('set role service_role;'+cfg,'permission denied');q("set role service_role;select public.paper_company_coverage_import('[]')",'permission denied');q("set role service_role;select public.paper_company_coverage_stage('AAPL')",'permission denied');q('select public.paper_company_coverage_read(null)','Owner required')
  records=[{'symbol':c['symbol'],'primary':{'url':c['primary_url'],'status':200},'observation':{'known_at':at,'values':{},'financial':{'revenue':100,'period_end':'2025-12-31'}},'financial_fingerprint':'0'*64,'secondary_status':'observed'}for c in d['c']]
  for i in range(0,100,10):assert q('select public.paper_company_coverage_import('+jsql(records[i:i+10])+')')=='10'
  v=get('select public.paper_company_coverage_read('+literal(owner)+'::uuid)');assert v['counts']['companies']==100;assert v['counts']['primary_reachable']==100;assert v['records']==[]
  assert len(get('select public.paper_company_coverage_read('+literal(owner)+"::uuid,'AAPL')")['records'])==1
  q("select public.paper_company_coverage_stage('AAPL')",'Official financial evidence required');assert get('select public.paper_company_coverage_claim()')is None
  dossier={'version':'company-dossier-v1','symbol':'AAPL','known_at':at,'checked_at':at,'financial':{'revenue':100}};q('select public.paper_company_save('+jsql(dossier)+')')
  before_usage=int(q('select sum(estimated_bytes)from paperlab.company_coverage_usage'));first=get('select public.paper_company_coverage_claim(true)');assert len(first['targets'])==6;assert get('select public.paper_company_coverage_claim(true)')is None;assert int(q('select sum(estimated_bytes)from paperlab.company_coverage_usage'))==before_usage+1000000
  row={'symbol':'AAPL','source_bytes':1000,'financial_fingerprint':'0'*64,'observation':records[0]['observation']};commit=lambda token,row:'select public.paper_company_coverage_commit('+literal(token)+'::uuid,'+jsql([row])+')'
  assert q(commit(first['token'],row))=='t';assert q(commit(first['token'],row))=='f';assert int(q('select sum(estimated_bytes)from paperlab.company_coverage_usage'))<before_usage+1000000
  assert get('select record from paperlab.company_dossiers order by known_at desc limit 1')['financial']['revenue']==100
  second=get('select public.paper_company_coverage_claim(true)');row['financial_fingerprint']='1'*64;assert q(commit(second['token'],row))=='t';assert q('select count(*)from paperlab.company_coverage_events')=='1'
  assert get('select record from paperlab.company_dossiers order by known_at desc limit 1')['status']=='financial_source_change_requires_review'
  q('update paperlab.company_coverage_usage set batches=4');assert get('select public.paper_company_coverage_claim(true)')is None
  q('update paperlab.company_coverage_usage set batches=0,estimated_bytes=19999999');assert get('select public.paper_company_coverage_claim(true)')is None
  assert q('select count(*)from paperlab.capital_trades')=='0';assert q('select count(*)from paperlab.trades')=='0'
  print('Coverage DB passed: 100 private source cards, no overview payload inflation, owner/MFA RPC boundary, bounded claims and refund, duplicate protection, financial revision invalidates cached approval, budget guards and zero trades.')
 finally:admin('drop database '+name+' with(force)')
if __name__=='__main__':main()
