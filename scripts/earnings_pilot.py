"""Install a bounded free quarterly research pilot; never activates earnings trades."""
import json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts import managed_api as api
from scripts.deploy_managed import literal,jsql
from scripts.compact_transport import SNAPSHOT
def configure(ref):
 api.ROOT=ROOT;before=api.sql(ref,SNAPSHOT,True)[0]['frozen'];jobs=api.sql(ref,"select jobid,jobname,schedule,command,active from cron.job where jobname<>'paperlab-earnings-pilot'order by jobid",True)
 rows=json.loads((ROOT/'managed/knowledge/earnings-pilot.json').read_text())['companies']
 api.sql(ref,(ROOT/'managed/sql/029_private_archives.sql').read_text());api.sql(ref,(ROOT/'managed/sql/033_earnings_pilot.sql').read_text())
 api.sql(ref,"begin;do $proof$declare s jsonb;n bigint;begin select state into s from paperlab.capital_runtime where singleton for update;select count(*)into n from paperlab.capital_trades;perform public.paper_earnings_configure("+jsql(rows)+");if s is distinct from(select state from paperlab.capital_runtime)or n<>(select count(*)from paperlab.capital_trades)then raise exception'Research changed trading account';end if;end$proof$;commit;")
 api.deploy_function(ref,'paper-earnings-pilot');api.deploy_function(ref,'paper-api')
 command="select net.http_post(url:="+literal('https://'+ref+'.supabase.co/functions/v1/paper-earnings-pilot')+",headers:=jsonb_build_object('Content-Type','application/json','X-PaperLab-Cron',(select decrypted_secret from vault.decrypted_secrets where name='paperlab_cron_token')),body:='{}'::jsonb,timeout_milliseconds:=120000);"
 prior=api.sql(ref,"select jobid,schedule,command,active from cron.job where jobname='paperlab-earnings-pilot'",True)
 if not prior:api.sql(ref,"select cron.schedule('paperlab-earnings-pilot','5 7 * * *',"+literal(command)+')')
 elif len(prior)!=1 or prior[0]['schedule']!='5 7 * * *'or prior[0]['command']!=command or not prior[0]['active']:raise RuntimeError('Unexpected earnings schedule; no overwrite')
 assert before==api.sql(ref,SNAPSHOT,True)[0]['frozen'];assert jobs==api.sql(ref,"select jobid,jobname,schedule,command,active from cron.job where jobname<>'paperlab-earnings-pilot'order by jobid",True)
 print(json.dumps({'pilot_companies':10,'utc_schedule':'07:05','belgian_winter_time':'08:05','paid_calls':False,'frozen_trading_profiles_unchanged':True,'existing_jobs_unchanged':True}))
if __name__=='__main__':
 if len(sys.argv)!=2:raise SystemExit('earnings_pilot.py REF')
 configure(sys.argv[1])
