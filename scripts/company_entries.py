"""Version the five-pillar overlay without resetting balances or frozen studies."""
import hashlib,json,sys,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.managed_api import sql,deploy_function,private_json
from scripts.deploy_managed import jsql,literal
from scripts.compact_transport import SNAPSHOT
PATHS=['managed/functions/_shared/company-policy.js','managed/functions/_shared/company-analysis.js','managed/functions/_shared/company-data.js','managed/functions/_shared/company-catalogue.js','managed/functions/_shared/engine-company.js','managed/functions/_shared/capital-company.js','managed/functions/paper-tick-company/index.js','managed/functions/paper-company-daily/index.js','managed/sql/017_company_entries.sql']
def fingerprint():
 manifest=[{'path':p,'sha256':hashlib.sha256((ROOT/p).read_bytes()).hexdigest()}for p in PATHS]
 h=hashlib.sha256(json.dumps(manifest,sort_keys=True,separators=(',',':')).encode()).hexdigest();(ROOT/'managed/functions/_shared/company-implementation.js').write_text("export const COMPANY_IMPLEMENTATION_SHA='"+h+"';\n");return h

def protocol():
 h=fingerprint();r=subprocess.run(['node','--input-type=module','-e',"import{COMPANY_POLICY}from'./managed/functions/_shared/company-policy.js';import{COMPANY_CATALOGUE}from'./managed/functions/_shared/company-catalogue.js';console.log(JSON.stringify({policy:COMPANY_POLICY,catalogue:COMPANY_CATALOGUE}));"],cwd=ROOT,capture_output=True,text=True,check=True);d=json.loads(r.stdout);d['policy']['implementation_sha256']=h;return d

def configure(ref):
 d=protocol();before=sql(ref,SNAPSHOT,True)[0]['frozen'];private_json('company-frozen-before.json',before)
 exists=sql(ref,"select to_regclass('paperlab.company_runtime')is not null as present",True)[0]['present']
 if exists:
  old=sql(ref,'select policy from paperlab.company_runtime',True)[0]['policy']
  if old and old!=d['policy']:raise RuntimeError('Company policy already frozen; create explicit new epoch')
 sql(ref,(ROOT/'managed/sql/017_company_entries.sql').read_text());profile=sql(ref,'select public.paper_company_configure('+jsql(d['policy'])+','+jsql(d['catalogue'])+')as profile')[0]['profile']
 deploy_function(ref,'paper-tick-company');deploy_function(ref,'paper-company-daily');deploy_function(ref,'paper-api')
 jobs=sql(ref,"select jobid,command from cron.job where jobname='paperlab-tick'",True);assert len(jobs)==1
 old=jobs[0]['command'];new=old.replace('/paper-tick-compact','/paper-tick-company')
 if new==old and'/paper-tick-company'not in old:raise RuntimeError('Unexpected original market route')
 sql(ref,'select cron.alter_job('+str(jobs[0]['jobid'])+',command:='+literal(new)+')')
 command="select net.http_post(url:="+literal('https://'+ref+'.supabase.co/functions/v1/paper-company-daily')+",headers:=jsonb_build_object('Content-Type','application/json','X-PaperLab-Cron',(select decrypted_secret from vault.decrypted_secrets where name='paperlab_cron_token')),body:='{}'::jsonb,timeout_milliseconds:=60000)where exists(select 1 from paperlab.company_runtime where singleton and enabled);"
 existing=sql(ref,"select jobid,schedule,active from cron.job where jobname='paperlab-company-daily'",True)
 if not existing:sql(ref,"select cron.schedule('paperlab-company-daily','5 6,8 * * 1-5',"+literal(command)+')')
 elif len(existing)!=1 or existing[0]['schedule']!='5 6,8 * * 1-5':raise RuntimeError('Existing source schedule differs; no silent replacement')
 # Preserve a deliberate source pause, including the recorded SEC access block.
 after=sql(ref,SNAPSHOT,True)[0]['frozen'];assert before==after
 private_json('company-deployed.json',{'profile':profile,'policy':d['policy'],'frozen_unchanged':True,'balance_reset':False,'new_paid_resources':False})
 print(json.dumps({'profile':profile,'frozen_unchanged':True,'active_account':'capital10k','baseline_reset':False,'daily_collection_attempts':2,'paid_resources':False}))
if __name__=='__main__':
 if sys.argv[1:]==['fingerprint']:print(fingerprint())
 elif len(sys.argv)==3 and sys.argv[1]=='configure':configure(sys.argv[2])
 else:raise SystemExit('company_entries.py fingerprint | configure REF')
