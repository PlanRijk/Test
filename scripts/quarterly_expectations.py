"""Activate continuous free numerical expectations without changing trading."""
import json,sys,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts import managed_api as api
from scripts.deploy_managed import literal,jsql
from scripts.compact_transport import SNAPSHOT
def configure(ref):
 api.ROOT=ROOT;before=api.sql(ref,SNAPSHOT,True)[0]['frozen'];jobs=api.sql(ref,"select jobid,jobname,schedule,command,active from cron.job where jobname<>'paperlab-quarterly-expectations'order by jobid",True)
 api.sql(ref,(ROOT/'managed/sql/029_private_archives.sql').read_text());api.sql(ref,(ROOT/'managed/sql/034_quarterly_expectations.sql').read_text())
 inputs=api.sql(ref,'select paperlab.quarterly_inputs()as inputs')[0]['inputs']
 code="import fs from'node:fs';import{quarterlyBaseline}from'./managed/functions/_shared/quarterly-expectations.js';console.log(JSON.stringify(JSON.parse(fs.readFileSync(0,'utf8')).map(x=>quarterlyBaseline(x))));"
 r=subprocess.run(['node','--input-type=module','-e',code],cwd=ROOT,input=json.dumps(inputs),text=True,capture_output=True,check=True);rows=json.loads(r.stdout)
 for offset in range(0,len(rows),20):api.sql(ref,'select public.paper_quarterly_seed('+jsql(rows[offset:offset+20])+')')
 api.deploy_function(ref,'paper-quarterly-expectations')
 command="select net.http_post(url:="+literal('https://'+ref+'.supabase.co/functions/v1/paper-quarterly-expectations')+",headers:=jsonb_build_object('Content-Type','application/json','X-PaperLab-Cron',(select decrypted_secret from vault.decrypted_secrets where name='paperlab_cron_token')),body:='{}'::jsonb,timeout_milliseconds:=120000);"
 prior=api.sql(ref,"select schedule,command,active from cron.job where jobname='paperlab-quarterly-expectations'",True)
 if not prior:api.sql(ref,"select cron.schedule('paperlab-quarterly-expectations','20 7 * * *',"+literal(command)+')')
 elif len(prior)!=1 or prior[0]['schedule']!='20 7 * * *'or prior[0]['command']!=command or not prior[0]['active']:raise RuntimeError('Unexpected recurring research schedule')
 assert before==api.sql(ref,SNAPSHOT,True)[0]['frozen'];assert jobs==api.sql(ref,"select jobid,jobname,schedule,command,active from cron.job where jobname<>'paperlab-quarterly-expectations'order by jobid",True)
 print(json.dumps({'registered':len(rows),'initial_baselines':sum(r['status']=='baseline_available'for r in rows),'eligible':sum(r['eligible']for r in rows),'schedule_utc':'07:20','paid_calls':False,'trading_profiles_unchanged':True,'existing_jobs_unchanged':True}))
if __name__=='__main__':
 if len(sys.argv)!=2:raise SystemExit('quarterly_expectations.py PROJECT_REF')
 configure(sys.argv[1])
