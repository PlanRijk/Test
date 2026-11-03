"""Integration checks against an isolated, network-disabled PostgreSQL container.

Never connects to Supabase. Run after starting paperlab-sql-check locally.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
from datetime import datetime,timedelta,timezone
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from scripts.deploy_managed import source_export,import_sql

ROOT=Path(__file__).resolve().parents[2]
environment={k:v for k,v in os.environ.items() if k not in ['DOCKER_HOST','DOCKER_CONTEXT','DOCKER_TLS','DOCKER_TLS_VERIFY','DOCKER_CERT_PATH']}
command=['docker','--host=unix:///var/run/docker.sock','exec','-i','paperlab-sql-check','psql','-U','postgres','-v','ON_ERROR_STOP=1','-At']


def query(sql,fail=False,contains=None):
    result=subprocess.run(command,input=sql.encode(),capture_output=True,env=environment)
    if fail:
        assert result.returncode!=0,'Expected permission failure'
        if contains:assert contains in result.stderr.decode(),result.stderr.decode()
    elif result.returncode:
        raise RuntimeError(result.stderr.decode()[-2000:])
    return result.stdout.decode().strip()


def main():
    query("do $$begin create role anon;exception when duplicate_object then null;end$$;do $$begin create role authenticated;exception when duplicate_object then null;end$$;do $$begin create role service_role;exception when duplicate_object then null;end$$;")
    schema=(ROOT/'managed/sql/001_paperlab.sql').read_text()
    query(schema)
    state,records,manifest=source_export()
    # Isolated fixture only: SQL lease checks must not expire with the real trial.
    state['run_until']=(datetime.now(timezone.utc)+timedelta(days=1)).isoformat()
    source=import_sql(state,records);query(source)
    before=query("select count(*),(select state->>'cash' from paperlab.portfolio) from paperlab.trades;")
    query(schema);query(source)
    assert query("select count(*),(select state->>'cash' from paperlab.portfolio) from paperlab.trades;")==before
    checks=['schema_and_import_repeatable']
    for role in ['anon','authenticated']:
        query('set role '+role+';select public.paper_read(null,-1);',True,'permission denied')
        query('set role '+role+';select * from paperlab.trades;',True,'permission denied')
        checks.append(role+'_cannot_read_rpc_or_tables')
    value=query('set role service_role;select public.paper_context();')
    assert 'owner_id' in value;checks.append('service_role_rpc_can_execute')
    tests={
      'no_lease_cannot_commit':"""do $$begin if public.paper_commit_tick(null,1,'{}') then raise exception 'Null lease bypass';end if;end$$;""",
      'paused_does_not_claim':"""do $$begin if public.paper_claim_tick(false) is not null then raise exception 'Paused collector claimed';end if;end$$;""",
      'lease_and_commit_are_single_use':"""begin;update paperlab.portfolio set state=jsonb_set(state,'{running}','true');do $$declare l jsonb;o jsonb;begin
        l:=public.paper_claim_tick(false);if l is null then raise exception 'No lease';end if;
        if public.paper_claim_tick(false) is not null then raise exception 'Duplicate lease';end if;
        o:=jsonb_build_object('state',l->'state','trades','[]'::jsonb,'events','[]'::jsonb,'observations','[]'::jsonb,'equity',null);
        if not public.paper_commit_tick((l->>'token')::uuid,(l->>'revision')::bigint,o) then raise exception 'Commit failed';end if;
        if public.paper_commit_tick((l->>'token')::uuid,(l->>'revision')::bigint,o) then raise exception 'Duplicate commit';end if;
        end$$;rollback;""",
      'pause_invalidates_in_flight_work':"""begin;update paperlab.portfolio set state=jsonb_set(state,'{running}','true');do $$declare l jsonb;o jsonb;begin
        l:=public.paper_claim_tick(false);perform public.paper_action(null,'pause');
        o:=jsonb_build_object('state',l->'state','trades','[]'::jsonb);
        if public.paper_commit_tick((l->>'token')::uuid,(l->>'revision')::bigint,o) then raise exception 'Pause overwritten';end if;
        end$$;rollback;""",
      'corrupt_cash_rolls_back':"""begin;update paperlab.portfolio set state=jsonb_set(state,'{running}','true');do $$declare l jsonb;o jsonb;rejected boolean:=false;begin
        l:=public.paper_claim_tick(false);o:=jsonb_build_object('state',jsonb_set(l->'state','{cash}','999'),'trades','[]'::jsonb);
        begin perform public.paper_commit_tick((l->>'token')::uuid,(l->>'revision')::bigint,o);
        exception when others then if sqlerrm like '%Ledger mismatch%' then rejected:=true;else raise;end if;end;
        if not rejected then raise exception 'Corrupt cash accepted';end if;end$$;rollback;""",
      'non_owner_and_revoked_session_rejected':"""begin;update paperlab.settings set owner_id='11111111-1111-4111-8111-111111111111';do $$declare rejected boolean:=false;begin
        begin perform public.paper_read('22222222-2222-4222-8222-222222222222',-1);exception when others then rejected:=true;end;
        if not rejected then raise exception 'Other owner read accepted';end if;
        if not public.paper_session('11111111-1111-4111-8111-111111111111','33333333-3333-4333-8333-333333333333',false) then raise exception 'Session failed';end if;
        perform public.paper_session('11111111-1111-4111-8111-111111111111','33333333-3333-4333-8333-333333333333',true);
        if public.paper_session('11111111-1111-4111-8111-111111111111','33333333-3333-4333-8333-333333333333',false) then raise exception 'Revoked session accepted';end if;
        end$$;rollback;"""
    }
    for name,change in [('free_attempt_budget','tick_attempts=10000'),('free_transfer_budget','estimated_worker_egress_bytes=3000000000'),('free_storage_budget','max_database_bytes=1')]:
        tests[name]="""begin;
          update paperlab.portfolio set state=jsonb_set(state,'{running}','true'),last_attempt=null,lease=null,lease_until=null;
          insert into paperlab.free_usage(month) values(date_trunc('month',now() at time zone 'UTC')::date) on conflict do nothing;
          update paperlab.free_usage set %s where month=date_trunc('month',now() at time zone 'UTC')::date;
          do $$begin
          if public.paper_claim_tick(false) is not null then raise exception 'Budget bypass';end if;
          if (select (state->>'running')::boolean from paperlab.portfolio) then raise exception 'Budget did not pause';end if;
          if (select last_tick_status from paperlab.portfolio)<>'free_budget_paused' then raise exception 'No budget status';end if;
          end$$;rollback;"""%change
    tests['fresh_month_counts_budget']= """begin;
      update paperlab.portfolio set state=jsonb_set(state,'{running}','true'),last_attempt=null,lease=null,lease_until=null;
      delete from paperlab.free_usage where month=date_trunc('month',now() at time zone 'UTC')::date;
      do $$declare l jsonb;begin
      l:=public.paper_claim_tick(false);if l is null then raise exception 'Fresh budget rejected';end if;
      if (select tick_attempts from paperlab.free_usage where month=date_trunc('month',now() at time zone 'UTC')::date)<>1 then raise exception 'Attempt not counted';end if;
      if (select estimated_worker_egress_bytes from paperlab.free_usage where month=date_trunc('month',now() at time zone 'UTC')::date)<=0 then raise exception 'Transfer not counted';end if;
      end$$;rollback;"""
    tests['daily_quality_is_atomic_and_failure_counted_once']="""begin;
      delete from paperlab.daily_quality where day=(now() at time zone 'UTC')::date;
      update paperlab.portfolio set state=jsonb_set(state,'{running}','true'),last_attempt=null,lease=null,lease_until=null;
      do $$declare l jsonb;o jsonb;begin
      l:=public.paper_claim_tick(false);
      o:=jsonb_build_object('state',l->'state','trades','[]'::jsonb,'quality',jsonb_build_object('day',(now() at time zone 'UTC')::date,'expected',10,'fresh',7,'venues','{"XNAS":{"expected":10,"fresh":7}}'::jsonb));
      if not public.paper_commit_tick((l->>'token')::uuid,(l->>'revision')::bigint,o) then raise exception 'Quality commit failed';end if;
      if public.paper_commit_tick((l->>'token')::uuid,(l->>'revision')::bigint,o) then raise exception 'Duplicate quality commit';end if;
      update paperlab.portfolio set last_attempt=null;
      l:=public.paper_claim_tick(false);o:=jsonb_set(o,'{state}',l->'state');
      if not public.paper_commit_tick((l->>'token')::uuid,(l->>'revision')::bigint,o) then raise exception 'Second quality commit failed';end if;
      if (select rounds<>2 or expected<>20 or fresh<>14 or (venues->'XNAS'->>'fresh')::integer<>14 from paperlab.daily_quality where day=(now() at time zone 'UTC')::date) then raise exception 'Quality aggregation failed';end if;
      update paperlab.portfolio set last_attempt=null;
      l:=public.paper_claim_tick(false);perform public.paper_fail_tick((l->>'token')::uuid,'Synthetic failure');perform public.paper_fail_tick((l->>'token')::uuid,'Duplicate synthetic failure');
      if (select failures from paperlab.daily_quality where day=(now() at time zone 'UTC')::date)<>1 then raise exception 'Failure counted incorrectly';end if;
      end$$;rollback;"""
    for name,sql in tests.items():query(sql);checks.append(name)
    query('set role anon;select public.paper_research_input();',True,'permission denied');checks.append('research_input_is_private')
    query("begin;select public.paper_research(jsonb_build_object('text',repeat('x',128000)));rollback;",True,'Invalid report');checks.append('research_report_size_bounded')
    assert query("select count(*),(select state->>'cash' from paperlab.portfolio) from paperlab.trades;")==before
    print(json.dumps({'result':'passed','database':'isolated PostgreSQL17, no network','checks':checks,
                      'cash_eur':manifest['cash_eur'],'preserved_trade_actions':manifest['trades'],'real_supabase_modified':False},indent=2))


if __name__=='__main__':main()
