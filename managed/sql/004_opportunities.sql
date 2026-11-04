begin;
create table if not exists paperlab.opportunity_runtime (
 singleton boolean primary key default true check(singleton),enabled boolean not null default true,
 revision bigint not null default 1,state jsonb not null default '{}'
);
insert into paperlab.opportunity_runtime(singleton) values(true) on conflict do nothing;
create table if not exists paperlab.opportunity_records (
 id text primary key check(id ~ '^op-[a-f0-9]{24}$'),day date not null,time timestamptz not null,
 symbol text not null,cohort text not null check(cohort in('momentum','control')),fingerprint text not null,
 record jsonb not null check(octet_length(record::text)<=9000)
);
create index if not exists opportunity_day on paperlab.opportunity_records(day);
create index if not exists opportunity_time on paperlab.opportunity_records(time);
create table if not exists paperlab.opportunity_days(day date primary key,record jsonb not null);
create table if not exists paperlab.opportunity_benchmark_days(day date primary key,record jsonb not null);
do $$declare n text;begin
 foreach n in array array['opportunity_runtime','opportunity_records','opportunity_days','opportunity_benchmark_days'] loop
  execute format('alter table paperlab.%I enable row level security',n);
  execute format('revoke all on paperlab.%I from public,anon,authenticated,service_role',n);
 end loop;
end$$;

create or replace function public.paper_opportunity_guard() returns void
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
begin
 if pg_database_size(current_database())>=200000000 or exists(select 1 from paperlab.free_usage where month=date_trunc('month',now() at time zone 'UTC')::date and estimated_worker_egress_bytes>=2000000000) then
  update paperlab.opportunity_runtime set enabled=false,revision=revision+1,state=jsonb_set(jsonb_set(state,'{status}','"budget_paused"'),'{message}','"Kansenonderzoek gepauzeerd om het gratis budget van de hoofdproef te beschermen."') where singleton and enabled;
 end if;
end$$;

create or replace function public.paper_opportunity_payload() returns jsonb
language sql security definer set search_path=pg_catalog,pg_temp as $$
 select case when enabled then jsonb_build_object('enabled',true,'revision',revision,'state',state)
 else jsonb_build_object('enabled',false,'revision',revision) end from paperlab.opportunity_runtime where singleton;
$$;

create or replace function public.paper_opportunity_error() returns void
language sql security definer set search_path=pg_catalog,pg_temp as $$
 update paperlab.opportunity_runtime set enabled=false,revision=revision+1,state=jsonb_set(jsonb_set(state,'{status}','"error"'),'{message}','"Onderzoeksbatch afgewezen; hoofdtransacties behouden. Herbeoordeling nodig."') where singleton;
$$;

create or replace function paperlab.opportunity_day_summary(p_day date) returns jsonb
language sql stable set search_path=pg_catalog,pg_temp as $$
 select jsonb_build_object('day',p_day,'records',count(*),'symbols',count(distinct symbol),
  'expired',count(*) filter(where record->>'status'='expired'),
  'groups',(select coalesce(jsonb_agg(g),'[]'::jsonb) from(
   select r.cohort,o.key as horizon,count(*) filter(where o.value->>'status'='observed') as observed,
    count(*) filter(where o.value->>'status'='missing') as missing,
    sum((o.value->>'net_eur')::double precision) filter(where o.value->>'status'='observed') as net_sum,
    count(*) filter(where o.value->>'status'='observed' and (o.value->>'net_eur')::double precision>0) as positive
   from paperlab.opportunity_records r cross join lateral jsonb_each(r.record->'outcomes') o where r.day=p_day group by r.cohort,o.key)g))
 from paperlab.opportunity_records where day=p_day;
$$;

create or replace function public.paper_opportunity_apply(p_output jsonb) returns boolean
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare r paperlab.opportunity_runtime;s jsonb;x jsonb;old jsonb;e jsonb;o record;d date;due timestamptz;m date;
begin
 select * into r from paperlab.opportunity_runtime where singleton for update;
 if not r.enabled or r.revision is distinct from (p_output->>'revision')::bigint then return false;end if;
 if p_output->>'error'='true' then perform public.paper_opportunity_error();return false;end if;
 s=p_output->'state';
 if jsonb_typeof(s) is distinct from 'object' or octet_length(s::text)>131072 or octet_length(p_output::text)>800000
  or coalesce(jsonb_array_length(p_output->'records'),0)>200 or coalesce(jsonb_array_length(p_output->'updates'),0)>600
  or (select count(*) from jsonb_object_keys(s->'active'))>200 then raise exception 'Study batch outside limits';end if;
 m:=date_trunc('month',now() at time zone 'UTC')::date;
 update paperlab.free_usage set estimated_worker_egress_bytes=estimated_worker_egress_bytes+2*octet_length(p_output::text) where month=m;
 if exists(select 1 from paperlab.free_usage where month=m and estimated_worker_egress_bytes>=least(max_worker_egress_bytes,2000000000)) then
  update paperlab.opportunity_runtime set enabled=false,revision=revision+1,state=jsonb_set(jsonb_set(state,'{status}','"budget_paused"'),'{message}','"Uitgebreid kansenonderzoek bereikt het eigen verbruiksbudget; hoofdproef behouden."') where singleton;return false;
 end if;
 if r.state ? 'fingerprint' and r.state->>'fingerprint' is distinct from s->>'fingerprint' then raise exception 'Study fingerprint changed';end if;
 for x in select value from jsonb_array_elements(p_output->'records') loop
  if x->>'protocol'<>'opportunity-study-v1' or x->>'fingerprint' is distinct from s->>'fingerprint'
   or jsonb_array_length(x->'observations')<>6 or jsonb_array_length(x->'context'->'features')<>7
   or (x->>'decision_quote_time')::timestamptz>(x->>'decision_at')::timestamptz
   or (x->>'decision_at')::timestamptz-(x->>'decision_quote_time')::timestamptz>interval '120 seconds'
   or exists(select 1 from jsonb_array_elements(x->'observations') a where (a->>'time')::timestamptz>(x->>'decision_at')::timestamptz)
   or x->>'statement' is null or x->>'status'<>'watching' or x->'entry' is not null or x->'outcomes'<>'{}'::jsonb then raise exception 'Invalid causal opportunity';end if;
  insert into paperlab.opportunity_records(id,day,time,symbol,cohort,fingerprint,record)
   values(x->>'id',(x->>'day')::date,(x->>'decision_at')::timestamptz,x->>'symbol',x->>'cohort',x->>'fingerprint',x);
 end loop;
 for x in select value from jsonb_array_elements(p_output->'updates') loop
  select record into old from paperlab.opportunity_records where id=x->>'id' for update;
  if not found or old->>'status'<>'watching' then raise exception 'Unknown or finished opportunity';end if;
  if x ? 'entry' then
   e=x->'entry';
   if old ? 'entry' or jsonb_typeof(e->'qty')<>'number' or (e->>'qty')::double precision<=0 or (e->>'cost')::double precision<>100
    or (e->>'time')::timestamptz<=(old->>'decision_at')::timestamptz or (e->>'time')::timestamptz>(old->>'decision_at')::timestamptz+interval '10 minutes'
    or (e->>'quote_time')::timestamptz<=(old->>'decision_at')::timestamptz or (e->>'quote_time')::timestamptz<=(old->>'decision_quote_time')::timestamptz
    or (e->>'quote_time')::timestamptz>(e->>'time')::timestamptz or (e->>'time')::timestamptz-(e->>'quote_time')::timestamptz>interval '120 seconds'
    or (e->>'time')::timestamptz>=(old->>'session_end')::timestamptz then raise exception 'Invalid later study entry';end if;
   old:=old||jsonb_build_object('entry',e);
  end if;
  if x ? 'outcomes' then
   if not old ? 'entry' then raise exception 'Outcome without entry';end if;
   for o in select * from jsonb_each(x->'outcomes') loop
    if o.key not in('30','120') or old->'outcomes' ? o.key or o.value->>'status' not in('observed','missing') then raise exception 'Outcome overwrite or unknown horizon';end if;
    due:=(old->'entry'->>'time')::timestamptz+o.key::integer*interval '1 minute';
    if o.value->>'status'='observed' and (
     jsonb_typeof(o.value->'net_eur') is distinct from 'number' or (o.value->>'net_eur')::double precision not between -1000000 and 1000000
     or (o.value->>'time')::timestamptz<due or (o.value->>'time')::timestamptz>due+interval '10 minutes'
     or (o.value->>'quote_time')::timestamptz<due or (o.value->>'quote_time')::timestamptz>(o.value->>'time')::timestamptz
     or (o.value->>'time')::timestamptz-(o.value->>'quote_time')::timestamptz>interval '120 seconds'
     or (o.value->>'time')::timestamptz>=(old->>'session_end')::timestamptz) then raise exception 'Invalid future study outcome';end if;
    old:=jsonb_set(old,'{outcomes}',(old->'outcomes')||jsonb_build_object(o.key,o.value));
   end loop;
  end if;
  if x ? 'status' then
   if x->>'status'='complete' and not(old->'outcomes' ?& array['30','120']) then raise exception 'Incomplete horizons';end if;
   if x->>'status'='expired' and old ? 'entry' then raise exception 'Entered observation cannot expire';end if;
   if x->>'status' not in('complete','expired') then raise exception 'Invalid study status';end if;
   old:=old||jsonb_build_object('status',x->>'status','finished_at',x->>'finished_at');
   if x ? 'reason' then old:=old||jsonb_build_object('reason',x->>'reason');end if;
  end if;
  update paperlab.opportunity_records set record=old where id=x->>'id';
 end loop;
 if exists(select 1 from jsonb_object_keys(s->'active') a where not exists(select 1 from paperlab.opportunity_records p where p.id=a and p.record->>'status'='watching'))
  or exists(select 1 from paperlab.opportunity_records p where p.record->>'status'='watching' and not(s->'active' ? p.id)) then raise exception 'Active study records inconsistent';end if;
 for d in select distinct day from paperlab.opportunity_records where id in(select value->>'id' from jsonb_array_elements(p_output->'records') union select value->>'id' from jsonb_array_elements(p_output->'updates')) loop
  insert into paperlab.opportunity_days values(d,paperlab.opportunity_day_summary(d)) on conflict(day) do update set record=excluded.record;
 end loop;
 update paperlab.opportunity_runtime set state=s,revision=revision+1 where singleton;
 if s->'basket'->>'stage'='holding' and (s->'basket'->>'current')::boolean then
  insert into paperlab.opportunity_benchmark_days values(((s->>'last_check')::timestamptz at time zone 'UTC')::date,
   jsonb_build_object('time',s->>'last_check','fingerprint',s->>'fingerprint','started_at',s->'basket'->>'started_at','basket_eur',s->'basket'->'liquidation_estimate_eur','basket_return_percent',s->'basket'->'return_percent','main_return_percent',s->'basket'->'main_return_since_anchor_percent')) on conflict(day) do update set record=excluded.record;
 end if;
 return true;
end$$;

create or replace function public.paper_opportunity_maintenance() returns void
language sql security definer set search_path=pg_catalog,pg_temp as $$
 delete from paperlab.opportunity_records where record->>'status'<>'watching' and(time<now()-interval '90 days' or id in(select id from paperlab.opportunity_records where record->>'status'<>'watching' order by time desc,id desc offset 5000));
 delete from paperlab.opportunity_days where day<(now() at time zone 'UTC')::date-365;
 delete from paperlab.opportunity_benchmark_days where day<(now() at time zone 'UTC')::date-365;
$$;

create or replace function public.paper_opportunity_read(p_owner uuid) returns jsonb
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton) then raise exception 'Not owner';end if;
 return jsonb_build_object('enabled',(select enabled from paperlab.opportunity_runtime),'state',(select state-'active'-'seen' from paperlab.opportunity_runtime),
  'counts',(select jsonb_build_object('records',count(*),'symbols',count(distinct symbol),'days',count(distinct day),'clusters',count(distinct (symbol,day)),'active',count(*) filter(where record->>'status'='watching'),'expired',count(*) filter(where record->>'status'='expired')) from paperlab.opportunity_records),
  'days',(select coalesce(jsonb_agg(record order by day desc),'[]'::jsonb) from paperlab.opportunity_days where day>=(now() at time zone 'UTC')::date-30),
  'benchmark_days',(select coalesce(jsonb_agg(record order by day desc),'[]'::jsonb) from paperlab.opportunity_benchmark_days where day>=(now() at time zone 'UTC')::date-30),
  'coverage',(select coalesce(jsonb_agg(jsonb_build_object('day',day,'expected',expected,'fresh',fresh,'venues',venues) order by day desc),'[]'::jsonb) from paperlab.daily_quality where day>=(now() at time zone 'UTC')::date-7),
  'recent',(select coalesce(jsonb_agg(q order by q.time desc),'[]'::jsonb) from(select id,time,symbol,cohort,record->>'status' as status,record->>'statement' as statement,record->'main_reasons' as main_reasons,record->'outcomes' as outcomes from paperlab.opportunity_records order by time desc,id desc limit 30)q),
  'is_portfolio',false,'used_for_training',false);
end$$;

create or replace function public.paper_opportunity_records(p_owner uuid,p_id text default null) returns jsonb
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton) then raise exception 'Not owner';end if;
 if p_id is not null then return(select record from paperlab.opportunity_records where id=p_id);end if;
 return(select coalesce(jsonb_agg(record order by time desc),'[]'::jsonb) from(select time,record from paperlab.opportunity_records order by time desc,id desc limit 500)q);
end$$;

create or replace function public.paper_opportunity_action(p_owner uuid,p_action text) returns boolean
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton) then raise exception 'Not owner';end if;
 if p_action not in('pause','resume') then raise exception 'Unsupported study action';end if;
 update paperlab.opportunity_runtime set enabled=p_action='resume',revision=revision+1 where singleton;
 perform public.paper_opportunity_guard();return true;
end$$;

do $$declare f record;begin
 for f in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'paper_opportunity_%' loop
  execute format('revoke all on function %s from public,anon,authenticated',f.signature);
  execute format('grant execute on function %s to service_role',f.signature);
 end loop;
end$$;
commit;
