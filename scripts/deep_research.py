"""Install/resume the existing free project's full-text task graph; never change trades."""
import json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts import managed_api as api
from scripts.deploy_managed import literal
from scripts.compact_transport import SNAPSHOT
REF='kdyzlbknygeqinqduuic'
def configure(ref):
 if ref!=REF:raise RuntimeError('Existing Paperlab project required')
 api.ROOT=ROOT;before=api.sql(ref,SNAPSHOT,True)[0]['frozen']
 query="select jobid,jobname,schedule,command,active from cron.job where jobname not in('paperlab-deep-research','paperlab-gemini-research')order by jobid"
 jobs=api.sql(ref,query,True)
 api.sql(ref,(ROOT/'managed/sql/039_deep_research.sql').read_text())
 api.sql(ref,(ROOT/'managed/sql/040_storage_capacity.sql').read_text())
 api.sql(ref,(ROOT/'managed/sql/041_cold_source_archive.sql').read_text())
 api.deploy_function(ref,'paper-deep-research')
 # Preserve today's legacy reservations once. Subsequent installs never reset counters.
 api.sql(ref,"update paperlab.deep_models set day=(now()at time zone'America/Los_Angeles')::date,used=case when model='gemini-3.5-flash-lite'then coalesce((select daily_reserved from paperlab.gemini_runtime where day=(now()at time zone'America/Los_Angeles')::date),0)…564 tokens truncated…OT/'managed/sql/037_gemini_research.sql').read_text());api.sql(ref,(ROOT/'managed/sql/038_gemini_resume.sql').read_text());api.sql(ref,(ROOT/'managed/sql/029_private_archives.sql').read_text())
 api.sql(ref,(ROOT/'managed/sql/040_storage_capacity.sql').read_text())
 if confirm_free:
  owner=api.sql(ref,'select owner_id from paperlab.settings where singleton',True)[0]['owner_id']
  api.sql(ref,'select public.paper_gemini_enable('+literal(owner)+'::uuid,true)')
 api.deploy_function(ref,'paper-gemini-research')
 command="select net.http_post(url:="+literal('https://'+ref+'.supabase.co/functions/v1/paper-gemini-research')+",headers:=jsonb_build_object('Content-Type','application/json','X-PaperLab-Cron',(select decrypted_secret from vault.decrypted_secrets where name='paperlab_cron_token')),body:='{}'::jsonb,timeout_milliseconds:=120000);"
 prior=api.sql(ref,"select jobid,schedule,command,active from cron.job where jobname='paperlab-gemini-research'",True)
 if not prior:api.sql(ref,"select cron.schedule('paperlab-gemini-research','*/10 * * * *',"+literal(command)+')')
 elif len(prior)==1 and prior[0]['command']==command and prior[0]['active']and prior[0]['schedule']in('45 7,15 * * *','45,50 7,15 * * *'):api.sql(ref,"select cron.alter_job("+str(prior[0]['jobid'])+",schedule:='*/10 * * * *')")
 elif len(prior)!=1 or prior[0]['schedule']!='*/10 * * * *'or prior[0]['command']!=command or not prior[0]['active']:raise RuntimeError('Unexpected Gemini schedule; no overwrite')
 assert before==api.sql(ref,SNAPSHOT,True)[0]['frozen'];assert jobs==api.sql(ref,"select jobid,jobname,schedule,command,active from cron.job where jobname<>'paperlab-gemini-research'order by jobid",True)
 state=api.sql(ref,'select enabled,free_tier_confirmed_at,model from paperlab.gemini_runtime',True)[0]
 print(json.dumps({'runtime':state,'schedule_utc':'every 10 minutes; quotas and cooldowns enforced','frozen_profiles_and_original_jobs_unchanged':True,'model_requests_from_installer':0}))
if __name__=='__main__':
 if len(sys.argv)not in(2,3)or(len(sys.argv)==3 and sys.argv[2]!='--confirm-free-tier'):raise SystemExit('gemini_research.py REF [--confirm-free-tier]')
 configure(sys.argv[1],confirm_free=len(sys.argv)==3)
