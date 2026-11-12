"""Apply the authorized 4 GB global traffic overlay without changing finance."""
import json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.managed_api import sql,deploy_function,private_json
from scripts.compact_transport import SNAPSHOT
MORE="""select jsonb_build_object('company',(select jsonb_build_object('profile',profile,'policy',policy)from paperlab.company_runtime),'exits',(select jsonb_build_object('profile',profile,'policy',policy)from paperlab.net_exit_runtime),'audit',(select jsonb_build_object('profile',profile,'policy',policy)from paperlab.strategy_audit_runtime),'coverage',(select policy from paperlab.company_coverage_runtime),'sources',(select jsonb_build_object('profile',profile,'policy',policy)from paperlab.source_runtime))as frozen"""
JOBS='select jobid,jobname,schedule,command,active from cron.job order by jobid'
def ledger(ref,limit=None):
 where=''if limit is None else'where id<='+str(int(limit))
 return sql(ref,"select coalesce(max(id),0)as last_id,count(*)as count,md5(coalesce(jsonb_agg(to_jsonb(t)order by id)::text,'[]'))as fingerprint from paperlab.capital_trades t "+where,True)[0]
def configure(ref):
 if ref!='kdyzlbknygeqinqduuic':raise RuntimeError('Expected the existing PaperLab project')
 before={'base':sql(ref,SNAPSHOT,True)[0]['frozen'],'other':sql(ref,MORE,True)[0]['frozen'],'jobs':sql(ref,JOBS,True),'ledger':ledger(ref),'usage':sql(ref,"select *from paperlab.free_usage where month=date_trunc('month',now())::date",True)}
 private_json('traffic-budget-before.json',before)
 sql(ref,(ROOT/'managed/sql/026_traffic_budget.sql').read_text());deploy_function(ref,'paper-api')
 assert before['base']==sql(ref,SNAPSHOT,True)[0]['frozen'];assert before['other']==sql(ref,MORE,True)[0]['frozen'];assert before['jobs']==sql(ref,JOBS,True)
 assert before['ledger']==ledger(ref,before['ledger']['last_id'])
 d=sql(ref,'select public.paper_traffic_budget_read(owner_id)as data from paperlab.settings')[0]['data'];assert d['effective_hard_bytes']==4000000000;assert d['effective_soft_bytes']==3200000000
 proof={'budget':d,'frozen_financial_profiles_unchanged':True,'existing_ledger_preserved':True,'cron_unchanged':True,'paid_resources':False,'counter_reset':False};private_json('traffic-budget-deployed.json',proof)
 print(json.dumps({'hard_bytes':d['effective_hard_bytes'],'soft_bytes':d['effective_soft_bytes'],'warning_bytes':d['effective_warning_bytes'],'estimated_month_bytes':d['estimated_month_bytes'],'database_bytes':d['database_bytes'],'provider_meter_verified':False,'financial_profiles_unchanged':True,'ledger_preserved':True,'cron_unchanged':True,'paid_resources':False}))
if __name__=='__main__':
 if len(sys.argv)==3 and sys.argv[1]=='configure':configure(sys.argv[2])
 else:raise SystemExit('Use traffic_budget.py configure REF, via access_recovery.py run when necessary')
