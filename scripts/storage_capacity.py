"""Align existing project's storage guards to its confirmed Free-plan capacity."""
import json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts import managed_api as api
from scripts.compact_transport import SNAPSHOT
def configure(ref):
 if ref!='kdyzlbknygeqinqduuic':raise RuntimeError('Existing Paperlab project required')
 api.ROOT=ROOT;before=api.sql(ref,SNAPSHOT,True)[0]['frozen'];jobs=api.sql(ref,'select jobid,jobname,schedule,command,active from cron.job order by jobid',True)
 # Reapply backup helper first; capacity overlay is always last for affected guards.
 for name in ['029_private_archives.sql','040_storage_capacity.sql','041_cold_source_archive.sql','042_dossier_automation.sql','043_audit_repairs.sql']:api.sql(ref,(ROOT/'managed/sql'/name).read_text())
 api.deploy_function(ref,'paper-project-followup')
 assert before==api.sql(ref,SNAPSHOT,True)[0]['frozen'];assert jobs==api.sql(ref,'select jobid,jobname,schedule,command,active from cron.job order by jobid',True)
 print(json.dumps({'database_warning_mb':350,'new_source_stop_mb':400,'hard_mb':450,'database_plan_mb':500,'private_object_limit_mb':800,'private_object_plan_mb':1000,'cold_source_archive':'gzip and AES-GCM, exact upload/download/decrypt/hash verification before clearing inactive cache','financial_profiles_and_schedules_unchanged':True,'no_traffic_or_model_counters_reset':True}))
if __name__=='__main__':configure(sys.argv[1])
