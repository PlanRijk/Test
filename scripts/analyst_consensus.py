"""Install free public-page provider consensus, never trading approval."""
import sys,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts import managed_api as api
from scripts.compact_transport import SNAPSHOT
from scripts.deploy_managed import literal

def configure(ref):
 api.ROOT=ROOT;before=api.sql(ref,SNAPSHOT,True)[0]['frozen'];jobs=api.sql(ref,"select jobid,jobname,schedule,command,active from cron.job where jobname<>'paperlab-analyst-consensus'order by jobid",True)
 api.sql(ref,(ROOT/'managed/sql/029_private_archives.sql').read_text());api.sql(ref,(ROOT/'managed/sql/035_analyst_consensus.sql').read_text());api.deploy_function(ref,'paper-analyst-consensus')
 command="select net.http_post(url:="+literal('https://'+ref+'.supabase.co/functions/v1/paper-analyst-consensus')+",headers:=jsonb_build_object('Content-Type','application/json','X-PaperLab-Cron',(select decrypted_secret from vault.decrypted_secrets where name='paperlab_cron_token')),body:='{}'::jsonb,timeout_milliseconds:=120000);"
 prior=api.sql(ref,"select schedule,command,active from cron.job where jobname='paperlab-analyst-consensus'",True)
 if not prior:api.sql(ref,"select cron.schedule('paperlab-analyst-consensus','35 7 * * *',"+literal(command)+')')
 elif len(prior)!=1 or prior[0]['schedule']!='35 7 * * *'or prior[0]['command']!=command or not prior[0]['active']:raise RuntimeError('Unexpected consensus schedule')
 assert before==api.sql(ref,SNAPSHOT,True)[0]['frozen'];assert jobs==api.sql(ref,"select jobid,jobname,schedule,command,active from cron.job where jobname<>'paperlab-analyst-consensus'order by jobid",True)
 print(json.dumps({'consensus_schedule_utc':'07:35','paid_services':False,'trading_profiles_unchanged':True,'existing_jobs_unchanged':True}))
if __name__=='__main__':
 if len(sys.argv)!=2:raise SystemExit('analyst_consensus.py PROJECT_REF')
 configure(sys.argv[1])
