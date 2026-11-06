"""Versioned horizon change on the existing paper ledger; no balance/risk reset."""
import hashlib,json,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.managed_api import sql,deploy_function
from scripts.deploy_managed import jsql,literal

def fingerprint():
 paths=['managed/functions/_shared/engine-multiday.js','managed/functions/_shared/capital-multiday.js','managed/functions/paper-tick-multiday/index.js','managed/sql/013_multiday_capital.sql','managed/functions/_shared/engine.js','managed/functions/_shared/capital-study.js','managed/functions/_shared/learning-runtime.js']
 manifest=[{'path':p,'sha256':hashlib.sha256((ROOT/p).read_bytes()).hexdigest()} for p in paths]
 value=hashlib.sha256(json.dumps(manifest,sort_keys=True,separators=(',',':')).encode()).hexdigest();(ROOT/'managed/functions/_shared/multiday-implementation.js').write_text("export const MULTIDAY_IMPLEMENTATION_SHA = '"+value+"';\n");return value

def policy(base):
 r=subprocess.run(['node','--input-type=module','-e',"import {MULTIDAY_POLICY} from './managed/functions/_shared/capital-multiday.js';console.log(JSON.stringify(MULTIDAY_POLICY));"],capture_output=True,text=True,cwd=ROOT,check=True)
 return {**json.loads(r.stdout),'implementation_sha256':fingerprint(),'base_implementation_sha256':base}

def configure(ref):
 base=sql(ref,"select enabled,policy->>'implementation_sha256' as implementation from paperlab.capital_runtime",True)[0]
 p=policy(base['implementation'])
 cols=sql(ref,"select 1 from information_schema.columns where table_schema='paperlab' and table_name='capital_runtime' and column_name='execution_profile'",True)
 if cols:
  old=sql(ref,'select execution_policy from paperlab.capital_runtime',True)[0]['execution_policy']
  if old and old!=p:raise RuntimeError('Existing multiday policy frozen')
 sql(ref,(ROOT/'managed/sql/013_multiday_capital.sql').read_text())
 profile=sql(ref,'select public.paper_capital_set_horizon('+jsql(p)+') as profile')[0]['profile']
 deploy_function(ref,'paper-tick-multiday');deploy_function(ref,'paper-api')
 command="select net.http_post(url := "+literal('https://'+ref+'.supabase.co/functions/v1/paper-tick-multiday')+",headers := jsonb_build_object('Content-Type','application/json','X-PaperLab-Cron',(select decrypted_secret from vault.decrypted_secrets where name='paperlab_cron_token')),body := '{}'::jsonb,timeout_milliseconds := 80000) where exists(select 1 from paperlab.portfolio where singleton and paperlab.run_open(state) and (state->>'running')::boolean);"
 sql(ref,"select cron.schedule('paperlab-tick','*/5 7-20 * * 1-5',"+literal(command)+');')
 print(json.dumps({'profile':profile,'mode':'multiple_sessions','new_cron_jobs':0,'balance_reset':False,'requires_explicit_resume':True}))
if __name__=='__main__':
 if sys.argv[1:]==['fingerprint']:print(fingerprint())
 elif len(sys.argv)==3 and sys.argv[1]=='configure':configure(sys.argv[2])
 else:raise SystemExit('Use: multiday_study.py fingerprint | configure REF')
