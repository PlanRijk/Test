"""Enable durable finish-first dossier completion on the existing free project."""
import json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts import managed_api as api
from scripts.compact_transport import SNAPSHOT

def configure(ref):
 if ref!='kdyzlbknygeqinqduuic':raise RuntimeError('Existing Paperlab project required')
 api.ROOT=ROOT;before=api.sql(ref,SNAPSHOT,True)[0]['frozen'];jobs=api.sql(ref,"select jobid,jobname,schedule,command,active from cron.job where jobname<>'paperlab-dossier-watchdog'order by jobid",True)
 api.sql(ref,(ROOT/'managed/sql/042_dossier_automation.sql').read_text())
 api.sql(ref,(ROOT/'managed/sql/043_audit_repairs.sql').read_text())
 api.deploy_function(ref,'paper-deep-research')
 existing=api.sql(ref,"select jobid from cron.job where jobname='paperlab-dossier-watchdog'",True)
 if not existing:api.sql(ref,"select cron.schedule('paperlab-dossier-watchdog','*/15 * * * *','select public.paper_dossier_watchdog();')")
 elif len(existing)!=1:raise RuntimeError('Duplicate dossier watchdog')
 else:api.sql(ref,"select cron.alter_job("+str(existing[0]['jobid'])+",schedule:='*/15 * * * *',command:='select public.paper_dossier_watchdog();',active:=true)")
 assert before==api.sql(ref,SNAPSHOT,True)[0]['frozen'];assert jobs==api.sql(ref,"select jobid,jobname,schedule,command,active from cron.job where jobname<>'paperlab-dossier-watchdog'order by jobid",True)
 print(json.dumps({'mode':'finish_first','concurrent_company_focus':2,'exact_code_owned_evidence':True,'separate_transient_and_validation_counters':True,'automatic_split_recovery':True,'in_app_alerts':True,'existing_minute_cron_retained':True,'financial_profiles_unchanged':True,'model_and_transfer_counters_not_reset':True}))
if __name__=='__main__':configure(sys.argv[1])
