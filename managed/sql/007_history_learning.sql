begin;
create table if not exists paperlab.history_runtime(
 singleton boolean primary key default true check(singleton),enabled boolean not null default true,profile text,protocol jsonb,config jsonb,symbols jsonb,cutoff date,
 token uuid,lease_until timestamptz,stage text,status text not null default 'waiting',calls_day date,calls integer not null default 0,source_calls integer not null default 0,compute_calls integer not null default 0,last_forward date,
 last_success timestamptz,connections jsonb not null default '[]',context jsonb not null default '[]',checks jsonb not null default '[]',report jsonb not null default '{}'
);
alter table paperlab.history_runtime add column if not exists source_calls integer not null default 0;
alter table paperlab.history_runtime add column if not exists compute_calls integer not null default 0;
insert into paperlab.history_runtime(singleton) values(true) on conflict do nothing;
create table if not exists paperlab.history_snapshots(
 symbol text primary key,status text not null check(status in('available','unavailable')),created_at timestamptz not null default now(),hash text,raw_hash text,
 data jsonb not null check(octet_length(data::text)<=2000000),tail jsonb,examples jsonb,counts jsonb,source_bytes bigint not null default 0
);
create table if not exists paperlab.history_models(
 id text primary key check(id ~ '^hm-[a-f0-9]{24}$'),created_at timestamptz not null default now(),artifact jsonb not null check(octet_length(artifact::text)<=100000),
 dataset jsonb not null check(octet_length(dataset::text)<=6000000),final_report jsonb,final_at timestamptz
);
create table if not exists paperlab.history_forecasts(
 id text primary key check(id ~ '^hf-[a-f0-9]{24}$'),model_id text not null references paperlab.history_models(id),symbol text not null,day date not null,
 status text not null check(status in('pending','following','complete','missing')),record jsonb not null check(octet_length(record::text)<=16000),unique(model_id,symbol,day)
);
create index if not exists history_forecasts_active on paperlab.history_forecasts(status) where status in('pending','following');
create index if not exists history_forecasts_day on paperlab.history_forecasts(day);
do $$declare n text;begin foreach n in array array['history_runtime','history_snapshots','history_models','history_forecasts'] loop
 execute format('alter table paperlab.%I enable row level security',n);execute format('revoke all on paperlab.%I from public,anon,authenticated,service_role',n);end loop;end$$;

create or replace function public.paper_history_configure(p_protocol jsonb,p_symbols jsonb) returns text
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare c jsonb;fp text;prior text;
begin
 if p_protocol->>'version' is distinct from 'historical-day-v1' or jsonb_array_length(p_symbols)<>153 or (select count(distinct value) from jsonb_array_elements(p_symbols))<>153 then raise exception 'Invalid historical protocol';end if;
 select config into c from paperlab.daily_study_runtime where singleton;if c is null then raise exception 'Daily study required';end if;
 fp:=encode(sha256(convert_to(jsonb_build_object('protocol',p_protocol,'symbols',p_symbols,'config',c)::text,'UTF8')),'hex');
 select profile into prior from paperlab.history_runtime where singleton for update;
 if prior is not null and prior<>fp then
  if exists(select 1 from paperlab.history_models) or exists(select 1 from paperlab.history_forecasts) or exists(select 1 from paperlab.history_runtime where lease_until>now()) then raise exception 'Frozen history profile differs';end if;
  -- Pre-model repair only: retain every original source/hash and its cutoff.
  update paperlab.history_snapshots set examples=null,counts=null where symbol<>'__base__' and symbol not like '^%';
  update paperlab.history_runtime set profile=fp,protocol=p_protocol,status='bootstrapping',source_calls=case when calls_day=current_date then greatest(source_calls,least(calls,14)) else 0 end where singleton;
 end if;
 if prior is null then update paperlab.history_runtime set profile=fp,protocol=p_protocol,config=c,symbols=p_symbols,cutoff=(now() at time zone 'UTC')::date,status='bootstrapping' where singleton;end if;
 return fp;
end$$;

create or replace function public.paper_history_claim() returns jsonb
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare r paperlab.history_runtime;payload jsonb;t uuid;current_day date;m date;pending jsonb;charge bigint;model jsonb;base jsonb;stage_name text;
begin
 select * into r from paperlab.history_runtime where singleton for update;current_day:=(now() at time zone 'UTC')::date;
 if not r.enabled or r.profile is null or r.lease_until>now() or r.status='insufficient_history' then return null;end if;
 if not exists(select 1 from paperlab.portfolio where singleton and paperlab.run_open(state)) then return null;end if;
 delete from paperlab.history_forecasts f where f.day<current_day-730 and f.status in('complete','missing') and exists(select 1 from paperlab.history_models m where m.id=f.model_id and m.final_at is not null);
 m:=date_trunc('month',now() at time zone 'UTC')::date;insert into paperlab.free_usage(month) values(m) on conflict do nothing;
 perform 1 from paperlab.free_usage where month=m for update;
 if pg_database_size(current_database())>=180000000 or (select sum(pg_total_relation_size(x::regclass)) from unnest(array['paperlab.history_snapshots','paperlab.history_models','paperlab.history_forecasts'])x)>=64000000 or
  exists(select 1 from paperlab.free_usage where month=m and estimated_worker_egress_bytes>=least(max_worker_egress_bytes,2000000000)) then update paperlab.history_runtime set status='budget_paused' where singleton;return null;end if;
 select s.data into base from paperlab.history_snapshots s where symbol='__base__' and status='available';
 select coalesce(jsonb_agg(value),'[]'::jsonb) into pending from(select value from jsonb_array_elements_text(r.symbols) with ordinality a(value,n) where not exists(select 1 from paperlab.history_snapshots s where s.symbol=a.value) order by n limit 15)p;
 select artifact into model from paperlab.history_models order by created_at limit 1;
 if base is null then stage_name:='base';payload:='{}';
 elsif jsonb_array_length(pending)>0 then stage_name:='collect';payload:=jsonb_build_object('symbols',pending,'derivation_snapshots',(select jsonb_agg(jsonb_build_object('symbol',s.symbol,'status',s.status,'data',s.data,'hash',s.hash)) from paperlab.history_snapshots s where s.symbol='__base__' or s.symbol like '^%'));
 elsif model is null and exists(select 1 from paperlab.history_snapshots where status='available' and symbol<>'__base__' and symbol not like '^%' and examples is null) then
  stage_name:='derive';payload:=jsonb_build_object('snapshots',(select jsonb_agg(jsonb_build_object('symbol',s.symbol,'status',s.status,'data',s.data,'hash',s.hash)) from paperlab.history_snapshots s where s.symbol='__base__' or s.symbol like '^%' or s.symbol in(select symbol from paperlab.history_snapshots where status='available' and symbol<>'__base__' and symbol not like '^%' and examples is null order by symbol limit 15)));
 elsif model is null then stage_name:='train';payload:=jsonb_build_object('snapshots',(select jsonb_agg(jsonb_build_object('symbol',s.symbol,'status',s.status,'examples',s.examples,'counts',s.counts,'hash',s.hash)) from paperlab.history_snapshots s));
 else
  if r.last_forward=current_day then return null;end if;
  stage_name:='forward';payload:=jsonb_build_object('artifact',model,'base',jsonb_build_object('mapping',base->'mapping'),
   'us_symbols',(select jsonb_agg(value->>'symbol') from jsonb_array_elements((select catalogue from paperlab.daily_study_runtime)) where value->>'exchange' in('XNYS','XNAS')),
   'tails',(select jsonb_agg(jsonb_build_object('symbol',symbol,'status',status,'data',tail)) from paperlab.history_snapshots where tail is not null),
   'bars',(select jsonb_agg(jsonb_build_object('symbol',b.symbol,'day',b.day,'close',b.close,'record',(case when b.day=latest.last_day then b.record else b.record-'session_starts' end)||jsonb_build_object('observed_at',b.observed_at))) from paperlab.daily_study_bars b join(select symbol,max(day) as last_day from paperlab.daily_study_bars group by symbol) latest on latest.symbol=b.symbol),
   'active',(select coalesce(jsonb_agg(record),'[]'::jsonb) from paperlab.history_forecasts where status in('pending','following')),
   'reports',(select coalesce(jsonb_agg(record-'context'),'[]'::jsonb) from paperlab.history_forecasts where model_id=model->>'id'),
   'revised_symbols',coalesce((select record->'revised_symbols' from paperlab.daily_study_quality where day=current_day),'[]'::jsonb),
   'max_new_records',greatest(0,least(20,10000-(select count(*)::integer from paperlab.history_forecasts))));
 end if;
 if r.calls_day=current_day and (stage_name in('base','collect') and r.source_calls>=14 or stage_name in('derive','train') and r.compute_calls>=14) then return null;end if;
 payload:=payload||jsonb_build_object('stage',stage_name,'profile',r.profile,'protocol',r.protocol,'config',r.config,'cutoff',r.cutoff);
 charge:=4*octet_length(payload::text)+262144;
 if exists(select 1 from paperlab.free_usage where month=m and estimated_worker_egress_bytes+charge>=least(max_worker_egress_bytes,2000000000)) then update paperlab.history_runtime set status='budget_paused' where singleton;return null;end if;
 update paperlab.free_usage set estimated_worker_egress_bytes=estimated_worker_egress_bytes+charge where month=m;
 t:=gen_random_uuid();update paperlab.history_runtime set token=t,lease_until=now()+interval '150 seconds',stage=stage_name,status='processing',calls_day=current_day,calls=case when calls_day=current_day then calls+1 else 1 end,source_calls=(case when calls_day=current_day then source_calls else 0 end)+case when stage_name in('base','collect') then 1 else 0 end,compute_calls=(case when calls_day=current_day then compute_calls else 0 end)+case when stage_name in('derive','train') then 1 else 0 end where singleton;
 return payload||jsonb_build_object('token',t);
end$$;

create or replace function public.paper_history_commit(p_token uuid,p_output jsonb) returns boolean
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare r paperlab.history_runtime;x jsonb;prior paperlab.history_forecasts;new_record jsonb;entry jsonb;outcome jsonb;current_day date;
begin
 select * into r from paperlab.history_runtime where singleton and token=p_token and lease_until>now() for update;if not found then return false;end if;
 if p_output->>'stage' is distinct from r.stage or octet_length(p_output::text)>8000000 then raise exception 'Historical batch outside limits';end if;
 if r.stage in('base','collect') then
  if jsonb_typeof(p_output->'snapshots') is distinct from 'array' or jsonb_array_length(p_output->'snapshots')>15 then raise exception 'Invalid source batch';end if;
  for x in select value from jsonb_array_elements(p_output->'snapshots') loop
   if not(x->>'symbol'='__base__' or r.symbols ? (x->>'symbol')) or exists(select 1 from paperlab.history_models) then raise exception 'Unknown or frozen historical source';end if;
   insert into paperlab.history_snapshots(symbol,status,hash,raw_hash,data,tail,examples,counts,source_bytes) values(x->>'symbol',x->>'status',x->>'hash',x->>'raw_hash',x->'data',x->'tail',x->'examples',x->'counts',coalesce((x->>'source_bytes')::bigint,0)) on conflict do nothing;
  end loop;
 elsif r.stage='derive' then
  if exists(select 1 from paperlab.history_models) or jsonb_typeof(p_output->'derived') is distinct from 'array' or jsonb_array_length(p_output->'derived')>15 then raise exception 'Invalid derived batch';end if;
  for x in select value from jsonb_array_elements(p_output->'derived') loop
   if not exists(select 1 from paperlab.history_snapshots where symbol=x->>'symbol' and status='available' and examples is null) or jsonb_array_length(x->'examples')>48 then raise exception 'Unknown or frozen derived source';end if;
   update paperlab.history_snapshots set examples=x->'examples',counts=x->'counts' where symbol=x->>'symbol';
  end loop;
 elsif r.stage='train' then
  if p_output->>'status'='historical_model_frozen' then
   x:=p_output->'artifact';
   if exists(select 1 from paperlab.history_models) or x->>'protocol' is distinct from 'historical-day-v1' or x->>'fingerprint' is distinct from r.profile
    or x->>'automatic_trading_approval' is distinct from 'false' or jsonb_array_length(p_output->'dataset')>8000 then raise exception 'Invalid or repeated historical model';end if;
   insert into paperlab.history_models(id,artifact,dataset) values(x->>'id',x,p_output->'dataset');
  elsif p_output->>'status' is distinct from 'waiting_history' then raise exception 'Unknown historical training result';end if;
 elsif r.stage='forward' then
  if jsonb_typeof(p_output->'records') is distinct from 'array' or jsonb_array_length(p_output->'records')>20 or jsonb_array_length(p_output->'updates')>500 then raise exception 'Forward batch outside limits';end if;
  current_day:=(now() at time zone 'UTC')::date;
  for x in select value from jsonb_array_elements(p_output->'records') loop
   if x->>'status' is distinct from 'pending' or x->'entry' is distinct from 'null'::jsonb or x->'outcome' is distinct from 'null'::jsonb
    or (x->>'decision_at')::timestamptz<now()-interval '150 seconds' or (x->>'decision_at')::timestamptz>now()+interval '1 minute'
    or x->>'decision_day' is distinct from current_day::text or x->>'origin' is distinct from 'prospective_hypothetical'
    or not exists(select 1 from paperlab.history_models m where m.id=x->>'model_id' and m.created_at<(x->>'decision_at')::timestamptz)
    or not exists(select 1 from paperlab.history_models m where m.id=x->>'model_id' and m.artifact->'symbols' ? (x->>'symbol'))
    or jsonb_array_length(x->'features') is distinct from 8
    or ((x->>'probability')::float8 between 0 and 1) is not true then raise exception 'Invalid prospective prediction';end if;
   if (select count(*) from paperlab.history_forecasts)>=10000 or (select count(*) from paperlab.history_forecasts where status in('pending','following'))>=500 then exit;end if;
   insert into paperlab.history_forecasts values(x->>'id',x->>'model_id',x->>'symbol',current_day,'pending',x) on conflict do nothing;
  end loop;
  for x in select value from jsonb_array_elements(p_output->'updates') loop
   select * into prior from paperlab.history_forecasts where id=x->>'id' for update;
   if not found or prior.status not in('pending','following') then raise exception 'Unknown or completed prediction';end if;
   entry:=x->'entry';outcome:=x->'outcome';
   if x->>'status' not in('following','complete','missing') or
    (x->>'status'='following' and (jsonb_typeof(entry)<>'object' or outcome<>'null'::jsonb)) or
    (x->>'status'='complete' and (jsonb_typeof(entry)<>'object' or outcome->>'status' is distinct from 'observed')) or
    (x->>'status'='missing' and outcome->>'status' is distinct from 'missing') then raise exception 'Invalid prospective transition';end if;
   if prior.record->'entry'<>'null'::jsonb and prior.record->'entry' is distinct from entry then raise exception 'Frozen historical forward entry changed';end if;
   if prior.record->'outcome'<>'null'::jsonb and prior.record->'outcome' is distinct from outcome then raise exception 'Frozen historical forward outcome changed';end if;
   if entry<>'null'::jsonb and ((entry->>'open_time')::timestamptz<=(prior.record->>'decision_at')::timestamptz or
    not exists(select 1 from paperlab.daily_study_bars b where b.symbol=prior.symbol and b.day=(entry->>'day')::date and b.close=(entry->>'close')::float8)) then raise exception 'Unbacked or retrospective forward entry';end if;
   if outcome->>'status'='observed' and ((outcome->>'day')::date<=(entry->>'day')::date or
    ((outcome->>'net_eur')::float8 between -100 and 100000) is not true or ((outcome->>'stressed_net_eur')::float8<=(outcome->>'net_eur')::float8) is not true or
    not exists(select 1 from paperlab.daily_study_bars b where b.symbol=prior.symbol and b.day=(outcome->>'day')::date and b.close=(outcome->>'close')::float8) or
    not exists(select 1 from paperlab.daily_study_bars b cross join lateral jsonb_array_elements(b.record->'session_starts') with ordinality e(value,n)
     cross join lateral jsonb_array_elements(b.record->'session_starts') with ordinality z(value,n) where b.symbol=prior.symbol and b.day=(outcome->>'day')::date
     and (to_timestamp(e.value::text::float8) at time zone 'UTC')::date=(entry->>'day')::date and (to_timestamp(z.value::text::float8) at time zone 'UTC')::date=(outcome->>'day')::date and z.n-e.n=20)) then raise exception 'Unbacked forward outcome';end if;
   new_record:=prior.record||jsonb_build_object('status',x->>'status','entry',entry,'outcome',outcome,'reason',x->'reason');
   update paperlab.history_forecasts set status=x->>'status',record=new_record where id=prior.id;
  end loop;
  update paperlab.history_runtime set last_forward=current_day,context=coalesce(p_output->'context','[]'),checks=coalesce(p_output->'checks','[]'),report=p_output->'report' where singleton;
  if p_output->'report'->>'status'='final' and (select count(distinct day) from paperlab.history_forecasts where status in('complete','missing'))>=60 then
   update paperlab.history_models set final_report=p_output->'report',final_at=now() where final_at is null;
  end if;
 end if;
 update paperlab.free_usage set estimated_worker_egress_bytes=estimated_worker_egress_bytes+4*octet_length(p_output::text) where month=date_trunc('month',now() at time zone 'UTC')::date;
 update paperlab.history_runtime set token=null,lease_until=null,last_success=now(),status=case when p_output->>'status'='waiting_history' then 'insufficient_history' when r.stage='forward' then 'collecting_forward' when r.stage='train' then 'historical_model_frozen' else 'bootstrapping' end,
  connections=coalesce(p_output->'connections',connections),report=case when r.stage='train' then p_output-'dataset'-'artifact' else report end where singleton;
 return true;
end$$;

create or replace function public.paper_history_fail(p_token uuid) returns void
language sql security definer set search_path=pg_catalog,pg_temp as $$
 update paperlab.history_runtime set token=null,lease_until=null,status='error' where singleton and token=p_token;
$$;

create or replace function public.paper_history_read(p_owner uuid) returns jsonb
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton) then raise exception 'Owner required';end if;
 return jsonb_build_object('runtime',(select to_jsonb(r)-'config'-'token'-'lease_until'-'symbols' from paperlab.history_runtime r),
  'sources',(select jsonb_agg(jsonb_build_object('symbol',symbol,'status',status,'hash',hash,'rows',jsonb_array_length(data->'closes'),'reason',data->>'reason')) from paperlab.history_snapshots),
  'model',(select jsonb_build_object('artifact',artifact,'final_report',final_report,'final_at',final_at) from paperlab.history_models order by created_at limit 1),
  'counts',(select jsonb_build_object('predictions',count(*),'active',count(*) filter(where status in('pending','following')),'complete',count(*) filter(where status='complete'),'missing',count(*) filter(where status='missing')) from paperlab.history_forecasts),
  'storage_bytes',(select sum(pg_total_relation_size(x::regclass)) from unnest(array['paperlab.history_snapshots','paperlab.history_models','paperlab.history_forecasts'])x),
  'recent',(select coalesce(jsonb_agg(record order by day desc),'[]'::jsonb) from(select * from paperlab.history_forecasts order by day desc,id limit 20)f));
end$$;

create or replace function public.paper_history_export(p_owner uuid) returns jsonb
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton) then raise exception 'Owner required';end if;
 return(select coalesce(jsonb_agg(record order by day desc),'[]'::jsonb) from(select * from paperlab.history_forecasts order by day desc,id limit 500)f);
end$$;
do $$declare n text;begin for n in select p.oid::regprocedure::text from pg_proc p join pg_namespace s on s.oid=p.pronamespace where s.nspname='public' and p.proname like 'paper_history_%' loop
 execute 'revoke all on function '||n||' from public,anon,authenticated';execute 'grant execute on function '||n||' to service_role';end loop;end$$;
commit;
