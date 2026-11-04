begin;
-- Small independent control record; browser roles have no direct access.
create table if not exists paperlab.research_runtime (
 singleton boolean primary key default true check(singleton),
 token uuid,lease_until timestamptz,last_claim timestamptz,
 status text not null default 'waiting',last_success timestamptz
);
insert into paperlab.research_runtime(singleton) values(true) on conflict do nothing;
alter table paperlab.research_runtime enable row level security;
revoke all on paperlab.research_runtime from public,anon,authenticated;

create or replace function public.paper_claim_research() returns uuid
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare r paperlab.research_runtime;m date;t uuid;charge bigint;
begin
 select * into r from paperlab.research_runtime where singleton for update;
 if r.lease_until>now() or r.last_claim>now()-interval '30 minutes' then return null;end if;
 if not exists(select 1 from paperlab.portfolio where singleton and paperlab.run_open(state)) then return null;end if;
 m:=date_trunc('month',now() at time zone 'UTC')::date;
 insert into paperlab.free_usage(month) values(m) on conflict do nothing;
 perform 1 from paperlab.free_usage where month=m for update;
 -- Covers bounded external reads and repeated status/report transfers. Estimate only.
 charge:=2097152+4*(131072+(select octet_length(state::text) from paperlab.portfolio where singleton));
 if pg_database_size(current_database())>=250000000 or exists(select 1 from paperlab.free_usage where month=m and estimated_worker_egress_bytes+charge>least(max_worker_egress_bytes,2400000000)) then
  update paperlab.research_runtime set status='budget_paused' where singleton;return null;
 end if;
 update paperlab.free_usage set estimated_worker_egress_bytes=estimated_worker_egress_bytes+charge where month=m;
 t:=gen_random_uuid();update paperlab.research_runtime set token=t,lease_until=now()+interval '120 seconds',last_claim=now(),status='checking' where singleton;
 return t;
end$$;

create or replace function public.paper_commit_research(p_token uuid,p_report jsonb) returns boolean
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
begin
 perform 1 from paperlab.research_runtime where singleton and token=p_token and lease_until>now() for update;
 if not found then return false;end if;
 perform public.paper_research(p_report);
 update paperlab.research_runtime set token=null,lease_until=null,status='ok',last_success=now() where singleton;
 return true;
end$$;

create or replace function public.paper_maintenance() returns jsonb
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
begin
 -- Runs independently of trading/learning pauses. Never deletes purchase evidence.
 delete from paperlab.observations where received<now()-interval '2 days';
 delete from paperlab.events where kind in('wacht','fout') and time<now()-interval '7 days';
 delete from paperlab.research where time<now()-interval '14 days' or id in(select id from paperlab.research order by id desc offset 40);
 delete from paperlab.daily_quality where day<(now() at time zone 'UTC')::date-90;
 delete from paperlab.learning_samples where available_at<now()-interval '180 days' or id in(select id from paperlab.learning_samples order by available_at desc offset 2000);
 delete from paperlab.learning_days where day<(now() at time zone 'UTC')::date-120;
 delete from paperlab.learning_events where id in(select id from paperlab.learning_events order by id desc offset 500);
 delete from paperlab.learning_trades where trade->>'side'='verkoop' and (time<now()-interval '180 days' or id in(select id from paperlab.learning_trades where trade->>'side'='verkoop' order by id desc offset 5000));
 delete from paperlab.free_usage where month<(date_trunc('month',now() at time zone 'UTC')-interval '24 months')::date;
 if to_regclass('cron.job_run_details') is not null then
  execute $clean$delete from cron.job_run_details where end_time<now()-interval '7 days' and jobid in(select jobid from cron.job where jobname in('paperlab-tick','paperlab-research','paperlab-learn','paperlab-maintenance'))$clean$;
 end if;
 -- Keep four real observations per old day: first, last, low and high.
 delete from paperlab.equity where time<now()-interval '90 days' and id not in(
  select id from (select id,row_number() over(partition by (time at time zone 'UTC')::date order by time,id) a,
   row_number() over(partition by (time at time zone 'UTC')::date order by time desc,id desc) b,
   row_number() over(partition by (time at time zone 'UTC')::date order by value,id) c,
   row_number() over(partition by (time at time zone 'UTC')::date order by value desc,id desc) d
   from paperlab.equity where time<now()-interval '90 days') q where a=1 or b=1 or c=1 or d=1);
 return jsonb_build_object('status','maintained','database_bytes',pg_database_size(current_database()),'purchase_audits_retained',true);
end$$;

revoke all on function public.paper_claim_research(),public.paper_commit_research(uuid,jsonb),public.paper_maintenance() from public,anon,authenticated;
grant execute on function public.paper_claim_research(),public.paper_commit_research(uuid,jsonb),public.paper_maintenance() to service_role;
commit;
