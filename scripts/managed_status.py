"""Read-only status of the deployed PaperLab trial. Never prints credentials."""
import json
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from scripts.managed_api import sql

REF='kdyzlbknygeqinqduuic'


def status():
    portfolio=sql(REF,"""select now() as server_time,
      (state->>'running')::boolean as running,state->>'run_until' as end_utc,
      (state->>'cash')::float8 as cash_eur,state->>'last_update' as last_measurement,
      state->'data_info'->>'checked_at' as latest_source_check,
      (state->'data_info'->>'fresh_symbols')::integer as fresh_symbols_at_check,
      (state->>'tick')::integer as measurements,revision,last_tick_status,
      state->>'error' as attention,
      (select count(*) from jsonb_object_keys(state->'positions')) as open_positions,
      jsonb_array_length(state->'pending') as pending_orders,
      (select count(*) from paperlab.trades) as trades,
      (select count(*) from paperlab.observations) as stored_quotes,
      pg_database_size(current_database()) as database_bytes,
      lease is null as lease_released
      from paperlab.portfolio where singleton""",True)
    jobs=sql(REF,"""select j.jobname,j.schedule,j.active,
      (select max(start_time) from cron.job_run_details d where d.jobid=j.jobid) as latest_run,
      (select d.status from cron.job_run_details d where d.jobid=j.jobid order by start_time desc limit 1) as latest_run_status
      from cron.job j where j.jobname in ('paperlab-tick','paperlab-research') order by j.jobname""",True)
    budget=sql(REF,"select * from paperlab.free_usage where month=date_trunc('month',now() at time zone 'UTC')::date",True)
    return {'site':'https://paperlab-prive.onrender.com','portfolio':portfolio,'jobs':jobs,
            'automatic_processing_budget':budget,
            'real_broker_connected':False,'source_age_limit_seconds':120,
            'freshness_note':'Fresh count describes the last check, not the current age of those quotes.'}


if __name__=='__main__':
    print(json.dumps(status(),ensure_ascii=False,indent=2))
