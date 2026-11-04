begin;
create table if not exists paperlab.daily_study_runtime(
 singleton boolean primary key default true check(singleton),enabled boolean not null default true,
 token uuid,lease_until timestamptz,last_claim timestamptz,last_success timestamptz,status text not null default 'waiting',
 profile text,config jsonb,protocol jsonb,catalogue jsonb,summary jsonb not null default '{}'
);
insert into paperlab.daily_study_runtime(singleton) values(true) on conflict do nothing;
create table if not exists paperlab.daily_study_bars(
 symbol text not null,day date not null,observed_at timestamptz not null,close double precision not null check(close>0 and close<'Infinity'::float8),
 record jsonb not null check(octet_length(record::text)<=3000),primary key(symbol,day)
);
create table if not exists paperlab.daily_study_records(
 id text primary key check(id ~ '^dy-[a-f0-9]{24}$'),profile text not null,symbol text not null,week date not null,
 decision_day date not null,decision_at timestamptz not null,status text not null check(status in('pending','following','complete','censored')),
 record jsonb not null check(octet_length(record::text)<=6000),unique(profile,symbol,week)
);
create index if not exists daily_study_day on paperlab.daily_study_records(decision_day);
create index if not exists daily_study_active on paperlab.daily_study_records(status) where status in('pending','following');
create table if not exists paperlab.daily_study_quality(day date primary key,record jsonb not null check(octet_length(record::text)<=60000));
create table if not exists paperlab.daily_study_epochs(
 id bigint generated always as identity primary key,profile text not null,development_start date not null,test_start date not null,test_end date not null,
 release_after date not null,released_at timestamptz,report jsonb,unique(profile,development_start),check(development_start<test_start and test_start<test_end and test_end<release_after)
);
do $$declare n text;begin
 foreach n in array array['daily_study_runtime','daily_study_bars','daily_study_records','daily_study_quality','daily_study_epochs'] loop
  execute format('alter table paperlab.%I enable row level security',n);
  execute format('revoke all on paperlab.%I from public,anon,authenticated,service_role',n);
 end loop;
end$$;

create or replace function public.paper_daily_configure(p_catalogue jsonb,p_protocol jsonb) returns text
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare r paperlab.daily_study_runtime;c jsonb;fp text;d date;
begin
 select * into r from paperlab.daily_study_runtime where singleton for update;
 if jsonb_array_length(p_catalogue)<>150 or (select count(distinct value->>'symbol') from jsonb_array_elements(p_catalogue))<>150
  or p_protocol->>'version'<>'daily-observations-v1' or p_protocol->'horizons'<>'[1,5,20]'::jsonb then raise exception 'Invalid daily protocol';end if;
 select jsonb_build_object('costs',state->'multi_market'->'cost_assumptions','tax',state->'belgian_tax'->'config','tax_enabled',state->'belgian_tax'->'enabled') into c from paperlab.portfolio where singleton;
 if c is null then raise exception 'Portfolio missing';end if;
 fp:=encode(sha256(convert_to(jsonb_build_object('catalogue',p_catalogue,'protocol',p_protocol,'config',c)::text,'UTF8')),'hex');
 if r.profile is not null and r.profile<>fp then raise exception 'Frozen daily protocol differs; create an explicit new study';end if;
 if r.profile=fp then return fp;end if;
 update paperlab.daily_study_runtime set profile=fp,config=c,protocol=p_protocol,catalogue=p_catalogue where singleton;
 d:=(now() at time zone 'UTC')::date+1;
 insert into paperlab.daily_study_epochs(profile,development_start,test_start,test_end,release_after) values(fp,d,d+60,d+119,d+164) on conflict do nothing;
 return fp;
end$$;

create or replace function public.paper_daily_maintenance() returns void
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare epoch_row record;d date;fp text;
begin
 d:=(now() at time zone 'UTC')::date;
 delete from paperlab.daily_study_bars where day<d-45;
 delete from paperlab.daily_study_quality where day<d-365;
 -- Never erase an unreleased test to make room. Admission stops instead.
 delete from paperlab.daily_study_records r where r.decision_day<d-730 and r.status in('complete','censored') and not exists(
  select 1 from paperlab.daily_study_epochs e where e.profile=r.profile and r.decision_day between e.test_start and e.test_end and e.released_at is null);
 for epoch_row in select * from paperlab.daily_study_epochs where release_after<d and released_at is null loop
  update paperlab.daily_study_epochs set released_at=now(),report=(select jsonb_build_object('conclusion','Beschrijvend prospectief onderzoek; geen handelsgoedkeuring.',
    'records',count(*),'company_weeks',count(distinct(symbol,week)),'entry_weeks',count(distinct week),
    'primary_horizon_sessions',20,'observed',count(*) filter(where status<>'censored' and record->'outcomes'->'20'->>'status'='observed'),
    'missing',count(*) filter(where status='censored' or record->'outcomes'->'20'->>'status' is distinct from 'observed'),
    'note','Groepen, beursweken en bedrijven zijn afhankelijk. Geen vooraf bewezen modelvoordeel, dividenden of uitvoerbare slotprijzen.')
   from paperlab.daily_study_records where profile=epoch_row.profile and decision_day between epoch_row.test_start and epoch_row.test_end)
   where id=epoch_row.id and not exists(select 1 from paperlab.daily_study_records r where r.profile=epoch_row.profile and r.decision_day between epoch_row.test_start and epoch_row.test_end and r.status in('pending','following'));
 end loop;
 select profile into fp from paperlab.daily_study_runtime where singleton;
 select max(test_end)+1 into d from paperlab.daily_study_epochs where profile=fp;
 if fp is not null and d<=(now() at time zone 'UTC')::date+1 then
  insert into paperlab.daily_study_epochs(profile,development_start,test_start,test_end,release_after) values(fp,d,d+60,d+119,d+164) on conflict do nothing;
 end if;
end$$;

create or replace function public.paper_daily_claim() returns jsonb
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare r paperlab.daily_study_runtime;t uuid;data jsonb;m date;charge bigint;room integer;
begin
 select * into r from paperlab.daily_study_runtime where singleton for update;
 if not r.enabled or r.profile is null or r.lease_until>now() or (r.last_claim at time zone 'UTC')::date=(now() at time zone 'UTC')::date then return null;end if;
 if not exists(select 1 from paperlab.portfolio where singleton and paperlab.run_open(state)) then return null;end if;
 perform public.paper_daily_maintenance();
 m:=date_trunc('month',now() at time zone 'UTC')::date;
 insert into paperlab.free_usage(month) values(m) on conflict do nothing;
 perform 1 from paperlab.free_usage where month=m for update;
 if pg_database_size(current_database())>=200000000 or
  (select sum(pg_total_relation_size(x::regclass)) from unnest(array['paperlab.daily_study_records','paperlab.daily_study_bars','paperlab.daily_study_quality'])x)>=48000000 or
  exists(select 1 from paperlab.free_usage where month=m and estimated_worker_egress_bytes>=least(max_worker_egress_bytes,2000000000)) then
  update paperlab.daily_study_runtime set status='budget_paused' where singleton;return null;end if;
 room:=greatest(0,least(150,10000-(select count(*)::integer from paperlab.daily_study_records)));
 data:=jsonb_build_object('profile',r.profile,'config',r.config,'protocol',r.protocol,'max_new_records',room,
  'active',(select coalesce(jsonb_agg(record order by decision_at),'[]'::jsonb) from paperlab.daily_study_records where status in('pending','following')),
  'seen',(select coalesce(jsonb_agg(symbol||'|'||week::text),'[]'::jsonb) from paperlab.daily_study_records where week>=current_date-7),
  'bars',(select coalesce(jsonb_agg(jsonb_build_object('symbol',symbol,'day',day,'close',close)),'[]'::jsonb) from paperlab.daily_study_bars));
 charge:=4*octet_length(data::text)+262144;
 if exists(select 1 from paperlab.free_usage where month=m and estimated_worker_egress_bytes+charge>=least(max_worker_egress_bytes,2000000000)) then
  update paperlab.daily_study_runtime set status='budget_paused' where singleton;return null;end if;
 update paperlab.free_usage set estimated_worker_egress_bytes=estimated_worker_egress_bytes+charge where month=m;
 t:=gen_random_uuid();update paperlab.daily_study_runtime set token=t,lease_until=now()+interval '120 seconds',last_claim=now(),status='collecting' where singleton;
 return data||jsonb_build_object('token',t);
end$$;

create or replace function public.paper_daily_commit(p_token uuid,p_output jsonb) returns boolean
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare r paperlab.daily_study_runtime;x jsonb;old paperlab.daily_study_records;next jsonb;h text;d date;
begin
 select * into r from paperlab.daily_study_runtime where singleton and token=p_token and lease_until>now() for update;
 if not found then return false;end if;
 if p_output->>'protocol' is distinct from 'daily-observations-v1' or jsonb_typeof(p_output->'records') is distinct from 'array' or jsonb_typeof(p_output->'updates') is distinct from 'array'
  or jsonb_typeof(p_output->'bars') is distinct from 'array' or jsonb_typeof(p_output->'quality') is distinct from 'array'
  or (p_output->>'requests') is null or (p_output->>'download_bytes') is null
  or octet_length(p_output::text)>3000000 or jsonb_array_length(p_output->'records')>150
  or jsonb_array_length(p_output->'updates')>900 or jsonb_array_length(p_output->'bars')>153 or jsonb_array_length(p_output->'quality')<>150
  or (p_output->>'requests')::integer>154 or (p_output->>'download_bytes')::bigint>8500000 then raise exception 'Daily output outside budget';end if;
 for x in select value from jsonb_array_elements(p_output->'bars') loop
  if (x->>'day')::date>=(now() at time zone 'UTC')::date or (x->>'observed_at')::timestamptz>now()+interval '1 minute' then raise exception 'Unfinished or future daily bar';end if;
  insert into paperlab.daily_study_bars values(x->>'symbol',(x->>'day')::date,(x->>'observed_at')::timestamptz,(x->>'close')::double precision,x) on conflict do nothing;
 end loop;
 for x in select value from jsonb_array_elements(p_output->'records') loop
  if x->>'profile' is distinct from r.profile or x->>'status' is distinct from 'pending' or jsonb_typeof(x->'entry') is distinct from 'null' or x->'outcomes' is distinct from '{}'::jsonb
   or (x->>'decision_at')::timestamptz<r.last_claim or (x->>'decision_at')::timestamptz>now()+interval '1 minute'
   or not exists(select 1 from jsonb_array_elements(r.catalogue)c where c->>'symbol'=x->>'symbol' and c->>'sector'=x->>'sector' and c->>'exchange'=x->>'venue')
   then raise exception 'Invalid prospective daily decision';end if;
  if (select count(*) from paperlab.daily_study_records)>=10000 or (select count(*) from paperlab.daily_study_records where status in('pending','following'))>=900 then exit;end if;
  insert into paperlab.daily_study_records values(x->>'id',r.profile,x->>'symbol',(x->>'week')::date,(x->>'decision_day')::date,(x->>'decision_at')::timestamptz,'pending',x) on conflict do nothing;
 end loop;
 for x in select value from jsonb_array_elements(p_output->'updates') loop
  select * into old from paperlab.daily_study_records where id=x->>'id' for update;
  if not found or old.profile<>r.profile or old.status not in('pending','following') then raise exception 'Unknown or frozen daily observation';end if;
  if jsonb_typeof(x->'outcomes') is distinct from 'object' or jsonb_typeof(x->'entry') not in('null','object')
   or x->>'status' not in('following','complete','censored') or exists(select 1 from jsonb_object_keys(x->'outcomes') z(key) where z.key not in('1','5','20'))
   or (x->>'status' in('complete','censored') and not x->'outcomes' ?& array['1','5','20'])
   or (x->>'status'='following' and jsonb_typeof(x->'entry')<>'object') then raise exception 'Invalid daily transition';end if;
  if old.record->'entry'<>'null'::jsonb and old.record->'entry' is distinct from x->'entry' then raise exception 'Frozen daily entry changed';end if;
  if x->'entry'<>'null'::jsonb and (x->'entry'->>'open_time')::timestamptz<=old.decision_at then raise exception 'Retrospective daily entry';end if;
  if x->'entry'<>'null'::jsonb and (not exists(select 1 from paperlab.daily_study_bars b where b.symbol=old.symbol and b.day=(x->'entry'->>'day')::date and b.close=(x->'entry'->>'close')::float8)
   or ((x->'entry'->>'qty')::float8>0 and (x->'entry'->>'qty')::float8<'Infinity'::float8) is not true
   or (x->'entry'->>'budget_eur')::float8 is distinct from 100) then raise exception 'Unbacked daily entry';end if;
  foreach h in array array['1','5','20'] loop
   if old.record->'outcomes' ? h and old.record->'outcomes'->h is distinct from x->'outcomes'->h then raise exception 'Frozen daily result changed';end if;
   if x->'outcomes'->h->>'status'='observed' and ((x->'outcomes'->h->>'day')::date<=(x->'entry'->>'day')::date or
     (x->'outcomes'->h->>'day')::date>=(now() at time zone 'UTC')::date or
     not exists(select 1 from paperlab.daily_study_bars b where b.symbol=old.symbol and b.day=(x->'outcomes'->h->>'day')::date and b.close=(x->'outcomes'->h->>'close')::float8) or
     (x->'outcomes'->h->>'known_at')::timestamptz>now()+interval '1 minute' or (x->'outcomes'->h->>'net_eur')::float8 not between -100 and 100000) then raise exception 'Invalid daily outcome';end if;
  end loop;
  next:=old.record||jsonb_build_object('entry',x->'entry','outcomes',x->'outcomes','status',x->>'status','reason',x->'reason');
  update paperlab.daily_study_records set status=x->>'status',record=next where id=old.id;
 end loop;
 d:=(now() at time zone 'UTC')::date;
 insert into paperlab.daily_study_quality values(d,jsonb_build_object('checked_at',p_output->'checked_at','companies',p_output->'quality','requests',p_output->'requests','source_bytes',p_output->'download_bytes','revised_symbols',p_output->'revised_symbols'));
 update paperlab.free_usage set estimated_worker_egress_bytes=estimated_worker_egress_bytes+4*octet_length(p_output::text) where month=date_trunc('month',now() at time zone 'UTC')::date;
 update paperlab.daily_study_runtime set token=null,lease_until=null,last_success=now(),status='observing',summary=jsonb_build_object('checked_at',p_output->'checked_at',
  'usable',(select count(*) from jsonb_array_elements(p_output->'quality')q where q->>'status'='usable'),'expected',150,'new_records',jsonb_array_length(p_output->'records'),'requests',p_output->'requests','source_bytes',p_output->'download_bytes') where singleton;
 return true;
end$$;

create or replace function public.paper_daily_fail(p_token uuid) returns void
language sql security definer set search_path=pg_catalog,pg_temp as $$
 update paperlab.daily_study_runtime set token=null,lease_until=null,status='source_or_processing_error' where singleton and token=p_token;
$$;

create or replace function paperlab.daily_visible(r paperlab.daily_study_records) returns jsonb
language sql stable security definer set search_path=pg_catalog,pg_temp as $$
 select r.record||jsonb_build_object('sealed',exists(select 1 from paperlab.daily_study_epochs e where e.profile=r.profile and r.decision_day between e.test_start and e.test_end and e.released_at is null),
  'outcomes',case when exists(select 1 from paperlab.daily_study_epochs e where e.profile=r.profile and r.decision_day between e.test_start and e.test_end and e.released_at is null) then '{"status":"sealed"}'::jsonb else r.record->'outcomes' end);
$$;

create or replace function public.paper_daily_read(p_owner uuid) returns jsonb
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton) then raise exception 'Owner required';end if;
 return jsonb_build_object('runtime',(select jsonb_build_object('status',status,'enabled',enabled,'last_success',last_success,'summary',summary,'profile',profile,'protocol',protocol) from paperlab.daily_study_runtime),
  'catalogue',(select catalogue from paperlab.daily_study_runtime),'counts',(select jsonb_build_object('records',count(*),'companies',count(distinct symbol),'weeks',count(distinct week),'active',count(*) filter(where status in('pending','following'))) from paperlab.daily_study_records),
  'storage_bytes',(select sum(pg_total_relation_size(x::regclass)) from unnest(array['paperlab.daily_study_records','paperlab.daily_study_bars','paperlab.daily_study_quality'])x),
  'epochs',(select coalesce(jsonb_agg(to_jsonb(e)),'[]'::jsonb) from paperlab.daily_study_epochs e),
  'groups',(select coalesce(jsonb_agg(to_jsonb(g)),'[]'::jsonb) from(
   select r.record->>'cohort' as cohort,o.key as horizon,count(*) as measurements,count(*) filter(where r.status<>'censored' and o.value->>'status'='observed') as observed,
    count(*) filter(where r.status='censored' or o.value->>'status' is distinct from 'observed') as missing,count(distinct week) as weeks,
    count(distinct symbol) as companies,avg((o.value->>'net_eur')::float8) filter(where r.status<>'censored' and o.value->>'status'='observed') as mean_net_eur,
    avg((o.value->>'stressed_net_eur')::float8) filter(where r.status<>'censored' and o.value->>'status'='observed') as mean_stressed_net_eur,
    min((o.value->>'net_eur')::float8) filter(where r.status<>'censored' and o.value->>'status'='observed') as worst_net_eur
   from paperlab.daily_study_records r cross join lateral jsonb_each(paperlab.daily_visible(r)->'outcomes')o
   where o.key in('1','5','20') group by r.record->>'cohort',o.key)g),
  'quality',(select coalesce(jsonb_agg(jsonb_build_object('day',day,'record',record) order by day desc),'[]'::jsonb) from (select * from paperlab.daily_study_quality order by day desc limit 7)q),
  'recent',(select coalesce(jsonb_agg(paperlab.daily_visible(r) order by decision_at desc),'[]'::jsonb) from (select * from paperlab.daily_study_records order by decision_at desc,id limit 20)r));
end$$;

create or replace function public.paper_daily_export(p_owner uuid) returns jsonb
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton) then raise exception 'Owner required';end if;
 return(select coalesce(jsonb_agg(paperlab.daily_visible(r) order by decision_at desc),'[]'::jsonb) from (select * from paperlab.daily_study_records order by decision_at desc,id limit 500)r);
end$$;

revoke all on function paperlab.daily_visible(paperlab.daily_study_records) from public,anon,authenticated,service_role;
do $$declare n text;begin
 for n in select p.oid::regprocedure::text from pg_proc p join pg_namespace s on s.oid=p.pronamespace where s.nspname='public' and p.proname like 'paper_daily_%' loop
  execute 'revoke all on function '||n||' from public,anon,authenticated';
  execute 'grant execute on function '||n||' to service_role';
 end loop;
end$$;
commit;
