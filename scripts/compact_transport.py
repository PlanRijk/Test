"""Switch the existing five-minute job to current-meta transport; no account reset."""
import json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.managed_api import sql,deploy_function,private_json
from scripts.deploy_managed import literal

SNAPSHOT="""select jsonb_build_object(
 'capital',(select jsonb_build_object('policy',policy,'profile',profile,'execution_policy',execution_policy,'execution_profile',execution_profile) from paperlab.capital_runtime),
 'breadth',(select jsonb_build_object('profile',profile,'policy',policy,'reference_hash',reference_hash) from paperlab.breadth_runtime),
 'candidates',(select jsonb_build_object('profile',profile,'policy',policy) from paperlab.candidate_runtime),
 'history',(select jsonb_build_object('profile',profile,'protocol',protocol) from paperlab.history_runtime),
 'reading',(select jsonb_build_object('enabled',enabled,'policy',policy) from paperlab.reading_runtime)) as frozen"""

def configure(ref):
 before=sql(ref,SNAPSHOT,True)[0]['frozen']
 if before['capital']['execution_policy']['version']!='capital-multiday-v2':raise RuntimeError('Expected existing multiday account; no migration is performed.')
 if before['reading']['enabled']:raise RuntimeError('Owner requested the note routine stopped; resolve before deployment.')
 jobs=sql(ref,"select jobid,jobname,schedule,command,active from cron.job order by jobid",True)
 tick=[j for j in jobs if j['jobname']=='paperlab-tick'];reading=[j for j in jobs if j['jobname']=='paperlab-reading']
 if len(tick)!=1 or tick[0]['schedule']!='*/5 7-20 * * 1-5' or not reading or reading[0]['active']:raise RuntimeError('Unexpected job configuration; no scheduling changes applied.')
 old=tick[0]['command'];url='https://'+ref+'.supabase.co/functions/v1/'
 if url+'paper-tick-multiday' in old:new=old.replace(url+'paper-tick-multiday',url+'paper-tick-compact')
 elif url+'paper-tick-compact' in old:new=old
 else:raise RuntimeError('Unrecognized trading route; refusing to replace it.')
 private_json('compact-transport-before.json',{'frozen':before,'jobs':jobs})
 deploy_function(ref,'paper-tick-compact')
 # Same job id, schedule, active state and predicates; only the transport route changes.
 sql(ref,'select cron.alter_job('+str(tick[0]['jobid'])+',command:='+literal(new)+')')
 deploy_function(ref,'paper-api')
 after=sql(ref,SNAPSHOT,True)[0]['frozen'];assert before==after,'Frozen policy changed during deployment'
 current=sql(ref,'select jobid,jobname,schedule,command,active from cron.job order by jobid',True)
 expected=[{**j,'command':new} if j['jobid']==tick[0]['jobid'] else j for j in jobs]
 assert current==expected,'Unexpected cron modification'
 private_json('compact-transport-deployed.json',{'frozen_unchanged':True,'jobs_before':len(jobs),'jobs_after':len(current),'schedule':tick[0]['schedule'],'transport':'yahoo-current-meta-compact-v1','reading_active':False})
 print(json.dumps({'transport':'yahoo-current-meta-compact-v1','cadence_seconds':300,'frozen_policies_unchanged':True,'new_jobs':0,'reading_active':False,'paid_resources':False}))

if __name__=='__main__':
 if len(sys.argv)==3 and sys.argv[1]=='configure':configure(sys.argv[2])
 else:raise SystemExit('Use compact_transport.py configure REF')
