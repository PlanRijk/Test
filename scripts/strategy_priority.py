"""Activate the research-first entry supervisor; never resets holdings or exits."""
import json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts import managed_api as api
from scripts.compact_transport import SNAPSHOT
def configure(ref):
 before=api.sql(ref,SNAPSHOT,True)[0]['frozen'];jobs=api.sql(ref,'select jobid,jobname,schedule,active from cron.job order by jobid',True)
 api.sql(ref,(ROOT/'managed/sql/029_private_archives.sql').read_text())
 api.sql(ref,(ROOT/'managed/sql/031_strategy_priority.sql').read_text())
 proof=api.sql(ref,"""begin;
 do $verify$declare before_state jsonb;after_state jsonb;before_count bigint;begin
 select state into before_state from paperlab.capital_runtime where singleton for update;
 select count(*)into before_count from paperlab.capital_trades;
 perform public.paper_priority_configure();
 select state into after_state from paperlab.capital_runtime where singleton;
 if before_state-'pending'is distinct from after_state-'pending'or before_count<>(select count(*)from paperlab.capital_trades)
  or exists(select 1 from jsonb_array_elements(after_state->'pending')o where o->>'side'='koop')then raise exception'Priority transition changed financial state';end if;
 end$verify$;
 commit;
 select jsonb_build_object('mode',policy->>'mode','new_entries_allowed',new_entries_allowed,'started_at',started_at)as result from paperlab.strategy_priority;
 """)
 assert before==api.sql(ref,SNAPSHOT,True)[0]['frozen'];assert jobs==api.sql(ref,'select jobid,jobname,schedule,active from cron.job order by jobid',True)
 print(json.dumps({'priority':proof[-1]['result'],'financial_state_preserved':True,'existing_jobs_unchanged':True,'frozen_models_unchanged':True,'forced_sales':False}))
if __name__=='__main__':
 if len(sys.argv)!=2:raise SystemExit('strategy_priority.py PROJECT_REF')
 configure(sys.argv[1])
