-- Separate the historical mixed work meter from an owner-reported provider meter.
-- No historical counter, financial profile, provider cooldown or model quota reset.
begin;
set local lock_timeout='5s';
create table if not exists paperlab.provider_usage_observations(
 id text primary key,recorded_at timestamptz not null default now(),source text not null,
 live_verified boolean not null default false check(not live_verified),
 metrics jsonb not null,raw_checkpoint bigint not null check(raw_checkpoint>=0),
 lag_reserve_bytes bigint not null check(lag_reserve_bytes>=250000000),
 billing_period_known boolean not null default false check(not billing_period_known));
create table if not exists paperlab.provider_usage_runtime(
 singleton boolean primary key default true check(singleton),
 observation_id text not null references paperlab.provider_usage_observations(id),
 charged_since_bytes bigint not null default 0 check(charged_since_bytes>=0));
alter table paperlab.provider_usage_observations enable row level security;
alter table paperlab.provider_usage_runtime enable row level security;
revoke all on paperlab.provider_usage_observations,paperlab.provider_usage_runtime from public,anon,authenticated,service_role;

-- max_worker_egress_bytes is now an admission threshold in RAW WORK coordinates.
-- The independent trigger below always enforces the 4.5 GB safety estimate.
alter table paperlab.free_usage drop constraint if exists free_usage_max_worker_egress_bytes_check;
alter table paperlab.free_usage add constraint free_usage_max_worker_egress_bytes_check check(max_worker_egress_bytes between 1 and 100000000000);
alter table paperlab.free_usage alter column max_worker_egress_bytes set default 4500000000;
update paperlab.traffic_budget_runtime set policy=policy||'{"version":"free-plan-reconciled-v1","hard_bytes":4500000000,"soft_bytes":4000000000,"warning_bytes":3500000000,"month_basis":"provider billing cycle unknown; checkpoint carries across UTC months","provider_meter_verified":false,"other_organization_usage_included":false,"measurement":"owner snapshot plus lag reserve plus subsequent positive work charges"}'::jsonb;
update paperlab.storage_budget_runtime set policy=policy||'{"version":"storage-capacity-v2","object_warning_bytes":700000000,"object_hard_bytes":900000000,"quota_evidence":"Owner Supabase Free screenshot, 26 November 2026","provider_meter_live":false}'::jsonb;

create or replace function paperlab.traffic_safety_bytes()returns bigint language sql stable security definer set search_path=pg_catalog,pg_temp as $$
 select coalesce((select(o.metrics->>'egress_bytes')::bigint+o.lag_reserve_bytes+r.charged_since_bytes from paperlab.provider_usage_runtime r join paperlab.provider_usage_observations o on o.id=r.observation_id where r.singleton),
 (select estimated_worker_egress_bytes from paperlab.free_usage where month=date_trunc('month',now()at time zone'UTC')::date),0)
$$;
create or replace function paperlab.traffic_plan_limit(p_level text)returns bigint language plpgsql stable security definer set search_path=pg_catalog,pg_temp as $$declare n bigint;begin
 if p_level not in('warning','soft','hard')then raise exception 'Unknown traffic limit';end if;
 select(policy->>(p_level||'_bytes'))::bigint into n from paperlab.traffic_budget_runtime where singleton;
 if n is null then raise exception 'Traffic budget unavailable';end if;return n;
end$$;
create or replace function paperlab.traffic_limit(p_level text)returns bigint language plpgsql stable security definer set search_path=pg_catalog,pg_temp as $$declare used bigint;cap bigint;n bigint;begin
 n:=paperlab.traffic_plan_limit(p_level);
 select estimated_worker_egress_bytes,max_worker_egress_bytes into used,cap from paperlab.free_usage where month=date_trunc('month',now()at time zone'UTC')::date;
 -- Equivalent threshold lets existing workers keep their raw charge accounting.
 return least(coalesce(cap,4500000000),greatest(0,coalesce(used,0)+n-paperlab.traffic_safety_bytes()));
end$$;
create or replace function paperlab.traffic_effective_limit(p_level text)returns bigint language sql stable security definer set search_path=pg_catalog,pg_temp as $$
 select least(paperlab.traffic_plan_limit(p_level),greatest(0,paperlab.traffic_safety_bytes()+coalesce((select max_worker_egress_bytes-estimated_worker_egress_bytes from paperlab.free_usage where month=date_trunc('month',now()at time zone'UTC')::date),4500000000)))
$$;
-- This operator save was introduced after the common traffic policy migration.
do $$declare p regprocedure:=to_regprocedure('public.paper_company_research_save(jsonb)');s text;begin
 if p is not null then s:=pg_get_functiondef(p);
  if strpos(s,'used+charge>3200000000')>0 then execute replace(s,'used+charge>3200000000','used+charge>paperlab.traffic_limit(''soft'')');
  elsif strpos(s,'used+charge>paperlab.traffic_limit(''soft'')')=0 then raise exception 'Unexpected research traffic guard';end if;
 end if;
end$$;
create or replace function paperlab.track_positive_work_charge()returns trigger language plpgsql security definer set search_path=pg_catalog,pg_temp as $$declare delta bigint;charged bigint;baseline bigint;begin
 delta:=greatest(0,new.estimated_worker_egress_bytes-case when tg_op='INSERT'then 0 else old.estimated_worker_egress_bytes end);
 if delta=0 then return new;end if;
 -- Serialize increments. Refunds deliberately grant no new provider capacity.
 select r.charged_since_bytes,(o.metrics->>'egress_bytes')::bigint+o.lag_reserve_bytes into charged,baseline from paperlab.provider_usage_runtime r join paperlab.provider_usage_observations o on o.id=r.observation_id where r.singleton for update of r;
 if not found then return new;end if;
 if baseline+charged+delta>paperlab.traffic_plan_limit('hard')then raise exception 'Reconciled traffic safety ceiling reached';end if;
 update paperlab.provider_usage_runtime set charged_since_bytes=charged_since_bytes+delta where singleton;
 return new;
end$$;
drop trigger if exists provider_positive_work_charge on paperlab.free_usage;
create trigger provider_positive_work_charge before insert or update of estimated_worker_egress_bytes on paperlab.free_usage for each row execute function paperlab.track_positive_work_charge();

-- Administrative SQL only, never exposed through the website or a service RPC.
-- An observation is immutable and repeatable; the provider billing reset is unknown.
create or replace function paperlab.record_provider_usage(p_id text,p_metrics jsonb,p_source text)returns boolean language plpgsql security definer set search_path=pg_catalog,pg_temp as $$declare used bigint;cap bigint;egress bigint;old_metrics jsonb;begin
 if p_id is null or length(p_id)not between 8 and 120 or length(coalesce(p_source,''))<10 then raise exception 'Observation provenance required';end if;
 egress:=(p_metrics->>'egress_bytes')::bigint;
 if egress is null or egress<0 or egress>5000000000 then raise exception 'Invalid Free-plan egress observation';end if;
 -- Same lock order as charge trigger, including the no-current-month case.
 lock table paperlab.free_usage in share row exclusive mode;
 select metrics into old_metrics from paperlab.provider_usage_observations where id=p_id;
 if found then if old_metrics<>p_metrics then raise exception 'Observation frozen';end if;return false;end if;
 select estimated_worker_egress_bytes,max_worker_egress_bytes into used,cap from paperlab.free_usage where month=date_trunc('month',now()at time zone'UTC')::date for update;
 insert into paperlab.provider_usage_observations(id,source,metrics,raw_checkpoint,lag_reserve_bytes)values(p_id,p_source,p_metrics,coalesce(used,0),250000000);
 insert into paperlab.provider_usage_runtime(singleton,observation_id,charged_since_bytes)values(true,p_id,0)on conflict(singleton)do update set observation_id=excluded.observation_id,charged_since_bytes=0;
 -- Respect deliberately lower custom work caps; recalibrate standard caps only.
 if cap in(4000000000,4500000000)then update paperlab.free_usage set max_worker_egress_bytes=greatest(1,coalesce(used,0)+4500000000-egress-250000000)where month=date_trunc('month',now()at time zone'UTC')::date;end if;
 return true;
end$$;
create or replace function paperlab.traffic_meter()returns jsonb language sql stable security definer set search_path=pg_catalog,pg_temp as $$
 select jsonb_build_object('used_bytes',paperlab.traffic_safety_bytes(),'entry_limit_bytes',paperlab.traffic_effective_limit('soft'),'hard_limit_bytes',paperlab.traffic_effective_limit('hard'),'blocked',paperlab.traffic_safety_bytes()>=paperlab.traffic_effective_limit('soft'),'next_window_at',null,'provider_verified',false,
 'raw_work_bytes',coalesce((select estimated_worker_egress_bytes from paperlab.free_usage where month=date_trunc('month',now()at time zone'UTC')::date),0),
 'provider_observation',(select to_jsonb(o)||jsonb_build_object('charged_since_bytes',r.charged_since_bytes)from paperlab.provider_usage_runtime r join paperlab.provider_usage_observations o on o.id=r.observation_id where r.singleton))
$$;

do $$begin
 if to_regprocedure('public.paper_traffic_budget_reconcile_base(uuid)')is null then alter function public.paper_traffic_budget_read(uuid)rename to paper_traffic_budget_reconcile_base;end if;
 if to_regprocedure('public.paper_dashboard_reconcile_base(uuid)')is null then alter function public.paper_dashboard_read(uuid)rename to paper_dashboard_reconcile_base;end if;
 if to_regprocedure('public.paper_read_reconcile_base(uuid,bigint)')is null then alter function public.paper_read(uuid,bigint)rename to paper_read_reconcile_base;end if;
end$$;
create or replace function public.paper_traffic_budget_read(p_owner uuid)returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$declare d jsonb;m jsonb;begin
 d:=public.paper_traffic_budget_reconcile_base(p_owner);m:=paperlab.traffic_meter();
 return d||jsonb_build_object('estimated_month_bytes',m->'used_bytes','effective_hard_bytes',m->'hard_limit_bytes','effective_soft_bytes',m->'entry_limit_bytes','effective_warning_bytes',paperlab.traffic_effective_limit('warning'),'meter',m);
end$$;
create or replace function public.paper_dashboard_read(p_owner uuid)returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$declare d jsonb;begin
 d:=public.paper_dashboard_reconcile_base(p_owner);if d?'entry_status'then d:=jsonb_set(d,'{entry_status,traffic}',paperlab.traffic_meter());end if;return d;
end$$;
create or replace function public.paper_read(p_owner uuid,p_revision bigint default -1)returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$declare d jsonb;begin
 d:=public.paper_read_reconcile_base(p_owner,p_revision);
 if d#>'{free_usage,automatic_budget}'is not null and d#>'{free_usage,automatic_budget}'<>'null'::jsonb then
  d:=jsonb_set(d,'{free_usage,automatic_budget}',(d#>'{free_usage,automatic_budget}')||jsonb_build_object('raw_work_bytes',d#>'{free_usage,automatic_budget,estimated_worker_egress_bytes}','estimated_worker_egress_bytes',paperlab.traffic_safety_bytes(),'max_worker_egress_bytes',paperlab.traffic_effective_limit('hard'),'measurement','calibrated safety estimate; not live provider usage'));
 end if;return d;
end$$;
revoke all on function paperlab.traffic_safety_bytes(),paperlab.traffic_plan_limit(text),paperlab.traffic_limit(text),paperlab.traffic_effective_limit(text),paperlab.track_positive_work_charge(),paperlab.record_provider_usage(text,jsonb,text),paperlab.traffic_meter()from public,anon,authenticated,service_role;
revoke all on function public.paper_traffic_budget_reconcile_base(uuid),public.paper_dashboard_reconcile_base(uuid),public.paper_read_reconcile_base(uuid,bigint),public.paper_traffic_budget_read(uuid),public.paper_dashboard_read(uuid),public.paper_read(uuid,bigint)from public,anon,authenticated,service_role;
grant execute on function public.paper_traffic_budget_read(uuid),public.paper_dashboard_read(uuid),public.paper_read(uuid,bigint)to service_role;
commit;
