"""Install a bounded SQL-only Friday reflection; never changes trading policies."""
import json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.managed_api import sql,deploy_function,private_json
from scripts.deploy_managed import literal
from scripts.compact_transport import SNAPSHOT
def setup(ref):
 before=sql(ref,SNAPSHOT,True)[0]['frozen'];entry=sql(ref,'select profile,policy from paperlab.company_runtime',True)
 jobs=sql(ref,'select jobid,jobname,schedule,command,active from cron.job order by jobid',True)
 sql(ref,(ROOT/'managed/sql/019_weekly_reflection.sql').read_text())
 old=[j for j in jobs if j['jobname']=='paperlab-weekly-reflection'];schedule='15 6,21,22 * * 5,6';command='select public.paper_weekly_run();'
 if not old:sql(ref,"select cron.schedule('paperlab-weekly-reflection',"+literal(schedule)+','+literal(command)+')')
 elif len(old)!=1 or old[0]['schedule']!=schedule or old[0]['command']!=command:raise RuntimeError('Existing weekly schedule differs')
 preview=sql(ref,'select public.paper_weekly_run(true)as report')[0]['report']
 deploy_function(ref,'paper-api')
 assert before==sql(ref,SNAPSHOT,True)[0]['frozen'];assert entry==sql(ref,'select profile,policy from paperlab.company_runtime',True)
 after=sql(ref,'select jobid,jobname,schedule,command,active from cron.job order by jobid',True)
 assert jobs==[j for j in after if old or j['jobname']!='paperlab-weekly-reflection']
 private_json('weekly-reflection-live.json',{'report':preview,'jobs':after,'frozen_unchanged':True})
 print(json.dumps({'status':preview.get('kind',preview.get('status')),'friday_time':'23:15 Europe/Brussels','retained_reports':104,'snapshot':preview.get('snapshot'),'paid_resources':False}))
if __name__=='__main__':setup(sys.argv[1])
