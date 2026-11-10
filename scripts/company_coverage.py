"""Bounded broad financial-source monitoring; never approves a paper trade."""
import hashlib,json,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.managed_api import sql,deploy_function,private_json
from scripts.deploy_managed import jsql,literal
from scripts.compact_transport import SNAPSHOT

def setup(ref,records_path=None):
 p=subprocess.run(['node','--input-type=module','-e',"import{COVERAGE_POLICY}from'./managed/functions/_shared/company-coverage.js';import{COMPANY_SOURCES}from'./managed/functions/_shared/company-source-catalogue.js';console.log(JSON.stringify({policy:COVERAGE_POLICY,catalogue:COMPANY_SOURCES}));"],cwd=ROOT,capture_output=True,text=True,check=True);d=json.loads(p.stdout)
 before=sql(ref,SNAPSHOT,True)[0]['frozen'];old_entry=sql(ref,'select profile,policy from paperlab.company_runtime',True)[0]
 sql(ref,(ROOT/'managed/sql/018_company_coverage.sql').read_text());sql(ref,'select public.paper_company_coverage_configure('+jsql(d['policy'])+','+jsql(d['catalogue'])+')')
 if records_path:
  records=json.loads(Path(records_path).read_text());assert len(records)==100 and len({r['symbol']for r in records})==100
  for start in range(0,len(records),10):sql(ref,'select public.paper_company_coverage_import('+jsql(records[start:start+10])+')')
  # Reviewed dossiers retain their execution history window; newly extracted
  # financials can be staged, but never gain a qualitative approval here.
  reviewed={r['symbol']for r in sql(ref,'select distinct symbol from paperlab.company_reviews',True)}
  for record in records:
   if record.get('verified_financials')and record['symbol']not in reviewed:sql(ref,'select public.paper_company_coverage_stage('+literal(record['symbol'])+')')
 deploy_function(ref,'paper-company-coverage');deploy_function(ref,'paper-api')
 existing=sql(ref,"select jobid,schedule,active from cron.job where jobname='paperlab-company-coverage'",True)
 cmd="select net.http_post(url:="+literal('https://'+ref+'.supabase.co/functions/v1/paper-company-coverage')+",headers:=jsonb_build_object('Content-Type','application/json','X-PaperLab-Cron',(select decrypted_secret from vault.decrypted_secrets where name='paperlab_cron_token')),body:='{}'::jsonb,timeout_milliseconds:=60000)where exists(select 1 from paperlab.company_coverage_runtime where singleton and enabled);"
 if not existing:sql(ref,"select cron.schedule('paperlab-company-coverage','40,50 6-7 * * 1-5',"+literal(cmd)+')')
 elif len(existing)!=1 or existing[0]['schedule']!='40,50 6-7 * * 1-5':raise RuntimeError('Existing coverage schedule differs')
 assert before==sql(ref,SNAPSHOT,True)[0]['frozen'];assert old_entry==sql(ref,'select profile,policy from paperlab.company_runtime',True)[0]
 private_json('company-coverage-deployed.json',{'policy':d['policy'],'companies':100,'trade_policy_unchanged':True,'paid_resources':False})
 print(json.dumps({'companies':100,'primary_links':100,'trade_approval':False,'entry_policy_unchanged':True,'max_source_records_per_day':24,'monthly_source_budget_bytes':20000000,'paid_resources':False}))
if __name__=='__main__':
 if len(sys.argv)in[2,3]:setup(sys.argv[1],sys.argv[2]if len(sys.argv)==3 else None)
 else:raise SystemExit('company_coverage.py REF [PRIVATE_100_RECORDS.json]')
