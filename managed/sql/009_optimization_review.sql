begin;
-- Read-only diagnostic inputs. No trading/model/validation table is changed.
create or replace function public.paper_optimization_input() returns jsonb
language sql security definer set search_path=pg_catalog,pg_temp as $$
 select jsonb_build_object('checked_at',now(),'config',(select config from paperlab.history_runtime where singleton),
  'prices',(select coalesce(jsonb_agg(jsonb_build_object('symbol',b.symbol,'day',b.day,'close',b.close,'fx',b.record->'fx','fx_date',b.record->'fx_date','observed_at',b.observed_at)),'[]')
    from paperlab.daily_study_bars b join(select symbol,max(day) as day from paperlab.daily_study_bars group by symbol)latest on latest.symbol=b.symbol and latest.day=b.day),
  'daily',(select jsonb_build_object('last_success',last_success,'status',status,'summary',summary) from paperlab.daily_study_runtime),
  'history',(select jsonb_build_object('last_success',last_success,'status',status,'context',context,'connections',connections) from paperlab.history_runtime),
  'breadth',(select jsonb_build_object('last_success',last_success,'status',status,'summary',summary,'enabled',enabled) from paperlab.breadth_runtime),
  'audit',(select jsonb_build_object('last_success',last_success,'status',status) from paperlab.reliability_runtime),
  'learning',(select jsonb_build_object('last_success',last_train_check,'enabled',enabled,'training',training_status) from paperlab.learning_runtime),
  'model',(select jsonb_build_object('id',id,'created_at',created_at,'historical_pass',artifact->'offline_pass','test_selected',artifact->'metrics'->'test'->'selected') from paperlab.history_models order by created_at limit 1),
  'progress',jsonb_build_object('reference',(select count(*) from paperlab.history_forecasts),'reference_complete',(select count(*) from paperlab.history_forecasts where status='complete'),
    'extra',(select count(*) from paperlab.breadth_scores),'extra_complete',(select count(*) from paperlab.breadth_scores where status=2),'extra_missing',(select count(*) from paperlab.breadth_scores where status=3),
    'reference_samples',(select count(*) from paperlab.learning_samples)),
  'account',(select jsonb_build_object('cash',state->'cash','risk',state->'risk'->'config','running',state->'running','last_update',state->'last_update','daily_halted',state->'risk'->'daily_halted','global_halted',state->'risk'->'global_halted') from paperlab.portfolio),
  'budget',jsonb_build_object('database_bytes',pg_database_size(current_database()),'monthly_estimated_bytes',coalesce((select estimated_worker_egress_bytes from paperlab.free_usage where month=date_trunc('month',now() at time zone 'UTC')::date),0)),
  'short_outcomes',(select jsonb_build_object('observed',count(*) filter(where h120[1]=1),'positive',count(*) filter(where h120[1]=1 and h120[4]>0),'mean_net_eur',avg(h120[4]) filter(where h120[1]=1)) from paperlab.opportunity_archive));
$$;

create or replace function public.paper_optimization_maintenance() returns jsonb
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare removed integer:=0;disabled integer:=0;completed_job record;bootstrap_inactive boolean;
begin
 if to_regclass('cron.job_run_details') is not null and to_regclass('cron.job') is not null then
  execute $clean$delete from cron.job_run_details where runid in(
   select d.runid from cron.job_run_details d join cron.job j on j.jobid=d.jobid
   where d.end_time<now()-interval '7 days' and j.jobname in('paperlab-tick','paperlab-research','paperlab-learn','paperlab-maintenance','paperlab-audit','paperlab-daily','paperlab-history','paperlab-history-bootstrap','paperlab-breadth')
   order by d.end_time limit 5000)$clean$;
  get diagnostics removed=row_count;
  if exists(select 1 from paperlab.history_models) then
   for completed_job in execute $find$select jobid from cron.job where jobname='paperlab-history-bootstrap' and active$find$ loop
    perform cron.alter_job(completed_job.jobid,active=>false);disabled:=disabled+1;
   end loop;
   execute $state$select not exists(select 1 from cron.job where jobname='paperlab-history-bootstrap' and active)$state$ into bootstrap_inactive;
  end if;
 end if;
 return jsonb_build_object('status','verified','verified_at',now(),'bootstrap_inactive',bootstrap_inactive,'old_job_logs_removed',removed,'completed_bootstrap_jobs_disabled',disabled,'retention_days',7);
end$$;

create or replace function public.paper_optimization_read(p_owner uuid) returns jsonb
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton) then raise exception 'Owner required';end if;
 return coalesce((select report->'optimization' from paperlab.research where report ? 'optimization' order by time desc,id desc limit 1),jsonb_build_object('status','waiting_first_review'));
end$$;
revoke all on function public.paper_optimization_input(),public.paper_optimization_maintenance(),public.paper_optimization_read(uuid) from public,anon,authenticated;
grant execute on function public.paper_optimization_input(),public.paper_optimization_maintenance(),public.paper_optimization_read(uuid) to service_role;
commit;
