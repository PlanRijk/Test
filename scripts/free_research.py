"""Install the free, native research workbench without changing trading policies."""
import sys,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts import managed_api as api
from scripts.compact_transport import SNAPSHOT
from scripts.deploy_managed import literal
REF='kdyzlbknygeqinqduuic'
def configure(ref=REF):
 if ref!=REF:raise ValueError('Existing Paperlab project required')
 api.ROOT=ROOT;before=api.sql(ref,SNAPSHOT,True)[0]['frozen'];forecasts=api.sql(ref,'select id,forecast,frozen_at from paperlab.earnings_cycles where forecast is not null order by id',True)
 migration=(ROOT/'managed/sql/045_free_research_workbench.sql').read_text();api.sql(ref,migration.rsplit('commit;',1)[0]+'rollback;');api.sql(ref,migration)
 for slug in ['paper-quarter-cycle','paper-deep-research','paper-free-research','paper-api']:api.deploy_function(ref,slug)
 command="select net.http_post(url:="+literal('https://'+ref+'.supabase.co/functions/v1/paper-free-research')+",headers:=jsonb_build_object('Content-Type','application/json','X-PaperLab-Cron',(select decrypted_secret from vault.decrypted_secrets where name='paperlab_cron_token')),body:='{}'::jsonb,timeout_milliseconds:=90000)where exists(select 1 from paperlab.free_research_runtime where singleton and enabled);"
 rows=api.sql(ref,"select jobid from cron.job where jobname='paperlab-free-research'",True)
 if rows:api.sql(ref,'select cron.alter_job('+str(rows[0]['jobid'])+",schedule:='7,37 * * * *',command:="+literal(command)+',active:=true)')
 else:api.sql(ref,"select cron.schedule('paperlab-free-research','7,37 * * * *',"+literal(command)+')')
 assert before==api.sql(ref,SNAPSHOT,True)[0]['frozen'];assert forecasts==api.sql(ref,'select id,forecast,frozen_at from paperlab.earnings_cycles where forecast is not null order by id',True)
 print(json.dumps({'paid_services':False,'additional_external_data_downloads':0,'model_limits_unchanged':True,'native_cached_extraction':True,'replays_per_day_maximum':10,'trade_profiles_unchanged':True,'original_forecasts_unchanged':True}))
if __name__=='__main__':configure(sys.argv[1]if len(sys.argv)>1 else REF)
