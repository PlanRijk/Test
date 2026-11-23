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
 api.sql(ref,(ROOT/'managed/sql/042_dossier_automation.sql').read_text())
 api.sql(ref,(ROOT/'managed/sql/043_audit_repairs.sql').read_text())
 api.deploy_function(ref,'paper-deep-research')
 # Preserve today's legacy reservations once. Subsequent installs never reset counters.
 api.sql(ref,"update paperlab.deep_models set day=(now()at time zone'America/Los_Angeles')::date,used=case when model='gemini-3.5-flash-lite'then coalesce((select daily_reserved from paperlab.gemini_runtime where day=(now()at time zone'America/Los_Angeles')::date),0)else 0 end where day is null")
 owner=api.sql(ref,'select owner_id from paperlab.settings where singleton',True)[0]['owner_id']
 api.sql(ref,'select public.paper_deep_enable('+literal(owner)+'::uuid)')
 command="select net.http_post(url:="+literal('https://'+ref+'.supabase.co/functions/v1/paper-deep-research')+",headers:=jsonb_build_object('Content-Type','application/json','X-PaperLab-Cron',(select decrypted_secret from vault.decrypted_secrets where name='paperlab_cron_token')),body:='{}'::jsonb,timeout_milliseconds:=120000);"
 prior=api.sql(ref,"select jobid from cron.job where jobname='paperlab-deep-research'",True)
 if not prior:api.sql(ref,"select cron.schedule('paperlab-deep-research','* * * * *',"+literal(command)+')')
 elif len(prior)==1:api.sql(ref,"select cron.alter_job("+str(prior[0]['jobid'])+",schedule:='* * * * *',command:="+literal(command)+",active:=true)")
 else:raise RuntimeError('Duplicate deep research scheduler')
 api.sql(ref,"update paperlab.gemini_runtime set enabled=false;do $$declare j int;begin for j in select jobid from cron.job where jobname='paperlab-gemini-research'loop perform cron.alter_job(j,active:=false);end loop;end$$")
 assert before==api.sql(ref,SNAPSHOT,True)[0]['frozen'];assert jobs==api.sql(ref,query,True)
 print(json.dumps({'enabled':True,'model_limits':{'gemini-3.5-flash-lite':500,'gemini-3.8-flash':20},'cron':'every minute','frozen_trading_profiles_and_other_jobs_unchanged':True}))
if __name__=='__main__':configure(sys.argv[1])
