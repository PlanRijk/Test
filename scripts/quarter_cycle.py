"""Install proactive recurring quarterly research on the existing free Paperlab project."""
import json,sys,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts import managed_api as api
from scripts.compact_transport import SNAPSHOT
from scripts.deploy_managed import literal
R='kdyzlbknygeqinqduuic'
def configure(ref=R):
 if ref!=R:raise RuntimeError('Existing Paperlab project required')
 api.ROOT=ROOT;before=api.sql(ref,SNAPSHOT,True)[0]['frozen'];frozen=api.sql(ref,"select id,forecast,frozen_at from paperlab.earnings_cycles where frozen_at is not null order by id",True)
 sql=(ROOT/'managed/sql/044_quarter_cycle.sql').read_text();api.sql(ref,sql.rsplit('commit;',1)[0]+'rollback;');api.sql(ref,sql)
 routes=json.loads(subprocess.check_output(['node','--input-type=module','-e',"import{ISSUER_ROUTES}from'./managed/functions/_shared/source-registry.js';console.log(JSON.stringify(ISSUER_ROUTES));"],cwd=ROOT,text=True))
 payload=literal(json.dumps(routes))+'::jsonb'
 api.sql(ref,"update paperlab.quarter_companies q set calendar_url=r->>'issuer_url'from jsonb_array_elements("+payload+")r where q.symbol=r->>'symbol'and(q.calendar_url is null or q.calendar_url~*'fy20[0-9]+-q[1-4]')")
 api.deploy_function(ref,'paper-quarter-cycle');api.deploy_function(ref,'paper-api')
 command="select paperlab.quarter_plan()where exists(select 1 from paperlab.quarter_runtime where singleton and enabled);select net.http_post(url:="+literal('https://'+ref+'.supabase.co/functions/v1/paper-quarter-cycle')+",headers:=jsonb_build_object('Content-Type','application/json','X-PaperLab-Cron',(select decrypted_secret from vault.decrypted_secrets where name='paperlab_cron_token')),body:='{}'::jsonb,timeout_milliseconds:=120000)where exists(select 1 from paperlab.quarter_runtime where singleton and enabled);"
 jobs=api.sql(ref,"select jobid from cron.job where jobname='paperlab-quarter-cycle'",True)
 if jobs:api.sql(ref,"select cron.alter_job("+str(jobs[0]['jobid'])+",schedule:='*/5 * * * *',command:="+literal(command)+",active:=true)")
 else:api.sql(ref,"select cron.schedule('paperlab-quarter-cycle','*/5 * * * *',"+literal(command)+')')
 assert before==api.sql(ref,SNAPSHOT,True)[0]['frozen'];assert frozen==api.sql(ref,"select id,forecast,frozen_at from paperlab.earnings_cycles where frozen_at is not null order by id",True)
 print(json.dumps({'companies':len(routes),'schedule':'every five minutes','pre_research_days':[7,2],'forecast_cutoff_hours':24,'preserved_human_forecasts':True,'financial_profiles_unchanged':True,'shared_lite_daily_limit':500,'paid_services':False}))
if __name__=='__main__':configure(sys.argv[1]if len(sys.argv)>1 else R)
