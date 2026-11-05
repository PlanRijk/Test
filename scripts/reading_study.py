"""Install the bounded Buffett source routine without touching trading studies."""
import hashlib,json,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from scripts.managed_api import sql,deploy_function
from scripts.deploy_managed import jsql,literal

def fingerprint():
 paths=['managed/functions/_shared/reading-plan.js','managed/functions/_shared/reading-study.js','managed/functions/paper-reading/index.js','managed/sql/012_reading_study.sql']
 manifest=[{'path':p,'sha256':hashlib.sha256((ROOT/p).read_bytes()).hexdigest()} for p in paths]
 value=hashlib.sha256(json.dumps(manifest,sort_keys=True,separators=(',',':')).encode()).hexdigest()
 (ROOT/'managed/functions/_shared/reading-implementation.js').write_text("export const READING_IMPLEMENTATION_SHA = '"+value+"';\n")
 return value

def policy():
 r=subprocess.run(['node','--input-type=module','-e',"import {READING_POLICY,READING_PLAN,READING_BOOKS} from './managed/functions/_shared/reading-plan.js';console.log(JSON.stringify({...READING_POLICY,library:READING_PLAN.map(({id,url,year,title})=>({id,url,year,title})),books:READING_BOOKS}));"],capture_output=True,text=True,cwd=ROOT,check=True)
 return {**json.loads(r.stdout),'implementation_sha256':fingerprint()}

def configure(ref):
 p=policy()
 if sql(ref,"select to_regclass('paperlab.reading_runtime') is not null as present",True)[0]['present']:
  rows=sql(ref,'select policy from paperlab.reading_runtime where policy is not null',True)
  if rows and rows[0]['policy']!=p:raise RuntimeError('Existing reading policy frozen')
 sql(ref,(ROOT/'managed/sql/012_reading_study.sql').read_text());sql(ref,'select public.paper_reading_configure('+jsql(p)+')')
 for slug in ['paper-reading','paper-api']:deploy_function(ref,slug)
 command="select net.http_post(url := "+literal('https://'+ref+'.supabase.co/functions/v1/paper-reading')+",headers := jsonb_build_object('Content-Type','application/json','X-PaperLab-Cron',(select decrypted_secret from vault.decrypted_secrets where name='paperlab_cron_token')),body := '{}'::jsonb,timeout_milliseconds := 20000) where exists(select 1 from paperlab.reading_runtime where singleton and enabled);"
 sql(ref,"select cron.schedule('paperlab-reading','0 6 * * *',"+literal(command)+');')
 print(json.dumps({'scheduled_utc':'06:00 daily','full_book_per_day':False,'daily_new_ai_analysis':False,'implementation':p['implementation_sha256']}))
if __name__=='__main__':
 if sys.argv[1:]==['fingerprint']:print(fingerprint())
 elif len(sys.argv)==3 and sys.argv[1]=='configure':configure(sys.argv[2])
 else:raise SystemExit('Use reading_study.py fingerprint | configure REF')
