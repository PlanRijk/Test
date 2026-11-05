"""Read-only diagnostics and bounded cron housekeeping in a disposable database."""
import json,secrets,subprocess,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from scripts.deploy_managed import source_export,import_sql,literal,jsql
from managed.tests.test_database import query as admin_query,command,environment
ROOT=Path(__file__).resolve().parents[2]
def main():
 name='paperlab_optimization_'+secrets.token_hex(5);admin_query('create database '+name);checks=[]
 def q(text,error=None):
  r=subprocess.run(command+['-d',name],input=text.encode(),capture_output=True,env=environment)
  if error:assert r.returncode and error in r.stderr.decode(),r.stderr.decode()
  elif r.returncode:raise RuntimeError(r.stderr.decode()[-4000:])
  return r.stdout.decode().strip()
 def get(text):return json.loads((q(text) or 'null').splitlines()[-1])
 try:
  for path in sorted((ROOT/'managed/sql').glob('*.sql')):q(path.read_text())
  state,trades,_=source_export();q(import_sql(state,trades))
  frozen="select md5(state::text),revision,(select count(*) from paperlab.trades),(select md5(coalesce(jsonb_agg(record order by id)::text,'')) from paperlab.history_forecasts),(select md5(coalesce(jsonb_agg(artifact::text||dataset::text order by id)::text,'')) from paperlab.history_models) from paperlab.portfolio"
  for role in ['anon','authenticated']:
   for rpc in ['paper_optimization_input()','paper_optimization_maintenance()','paper_optimization_read(null)']:q('set role '+role+';select public.'+rpc,'permission denied')
  q("select public.paper_optimization_read('11111111-1111-4111-8111-111111111111')",'Owner required')
  assert get('select public.paper_optimization_read(null)')['status']=='waiting_first_review'
  checks.append('private_rpcs_and_owner_check')
  before=q(frozen);x=get('set role service_role;select public.paper_optimization_input()');assert x['progress']['reference_complete']==0;assert q(frozen)==before
  q("create schema cron;create table cron.job(jobid bigint primary key,jobname text,active boolean);create table cron.job_run_details(runid bigint primary key,jobid bigint,end_time timestamptz);insert into cron.job values(1,'paperlab-history-bootstrap',true),(2,'paperlab-breadth',true),(3,'foreign-task',true);insert into cron.job_run_details values(1,1,now()-interval '8 days'),(2,2,now()-interval '8 days'),(3,3,now()-interval '8 days'),(4,2,now()),(5,2,null)")
  q("create function cron.alter_job(job_id bigint,active boolean) returns void language sql as $$update cron.job set active=$2 where jobid=$1$$")
  r=get('select public.paper_optimization_maintenance()');assert r['old_job_logs_removed']==2 and r['completed_bootstrap_jobs_disabled']==0
  assert q('select string_agg(runid::text,\',\' order by runid) from cron.job_run_details')=='3,4,5'
  assert q('select active from cron.job where jobid=1')=='t'
  model='hm-'+'a'*24;q('insert into paperlab.history_models(id,artifact,dataset) values('+literal(model)+",'{\"offline_pass\":false,\"metrics\":{\"test\":{\"selected\":5}}}','[]')")
  before=q(frozen);r=get('select public.paper_optimization_maintenance()');assert r['completed_bootstrap_jobs_disabled']==1
  assert q('select active from cron.job where jobid=1')=='f';assert q('select active from cron.job where jobid=2')=='t'
  q("insert into cron.job_run_details select 10+i,2,now()-interval '9 days' from generate_series(1,5001)i")
  assert get('select public.paper_optimization_maintenance()')['old_job_logs_removed']==5000
  assert q('select count(*) from cron.job_run_details where end_time<now()-interval \'7 days\' and jobid=2')=='1'
  assert q(frozen)==before;checks.append('bounded_cleanup_preserves_foreign_recent_running_and_frozen_data_bootstrap_stops_only_after_model')
  report={'optimization':{'status':'reviewed','findings':[]}};q('select public.paper_research('+jsql(report)+')');assert get('set role service_role;select public.paper_optimization_read(null)')['status']=='reviewed'
  x=get('select public.paper_optimization_input()');assert x['model']['test_selected']==5;assert q(frozen)==before;checks.append('private_report_read_and_diagnostics_do_not_touch_trading_or_model')
  print(json.dumps({'checks':checks,'count':len(checks)},indent=2))
 finally:admin_query('drop database '+name+' with(force)')
if __name__=='__main__':main()
