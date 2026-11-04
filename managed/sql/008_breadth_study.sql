begin;
create table if not exists paperlab.breadth_runtime(
 singleton boolean primary key default true check(singleton),enabled boolean not null default true,profile text,policy jsonb,
 model_id text references paperlab.history_models(id),reference_hash text,reference_profile text,reference_implementation text,
 token uuid,lease_until timestamptz,last_day date,last_success timestamptz,status text not null default 'waiting',
 admission_new integer not null default 0,admission_detail integer not null default 0,summary jsonb not null default '{}'
);
insert into paperlab.breadth_runtime(singleton) values(true) on conflict do nothing;
create table if not exists paperlab.breadth_scores(
 model_id text not null references paperlab.history_models(id),symbol text not null,day date not null,decision_at timestamptz not null,known_day date not null,
 probability double precision not null check(probability between 0 and 1),features double precision[] not null check(cardinality(features)=8),
 sector text not null,venue text not null,status smallint not null default 0 check(status between 0 and 3),
 entry double precision[] check(cardinality(entry)=12),outcome double precision[] check(cardinality(outcome) in(1,10)),reason text check(length(reason)<=400),
 primary key(model_id,symbol,day),
 check((status=0 and entry is null and outcome is null or status=1 and entry is not null and outcome is null or status=2 and entry is not null and cardinality(outcome)=10 and outcome[1]=1 or status=3 and outcome=array[2.]::double precision[]) is true)
);
create index if not exists breadth_score_day on paperlab.breadth_scores(day);
create index if not exists breadth_score_active on paperlab.breadth_scores(status) where status in(0,1);
create table if not exists paperlab.breadth_traces(
 model_id text not null,symbol text not null,day date not null,record jsonb not null check(octet_length(record::text)<=6000),
 primary key(model_id,symbol,day),foreign key(model_id,symbol,day) references paperlab.breadth_scores(model_id,symbol,day) on delete cascade
);
create table if not exists paperlab.breadth_days(day date primary key,record jsonb not null check(octet_length(record::text)<=12000));
do $$declare n text;begin foreach n in array array['breadth_runtime','breadth_scores','breadth_traces','breadth_days'] loop
 execute format('alter table paperlab.%I enable row level security',n);execute format('revoke all on paperlab.%I from public,anon,authenticated,service_role',n);end loop;end$$;

create or replace function public.paper_breadth_configure(p_policy jsonb) returns text
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare m paperlab.history_models;r paperlab.breadth_runtime;fp text;implementation text;
begin
 select * into m from paperlab.history_models order by created_at limit 1;if not found then raise exception 'Frozen day model required';end if;
 select protocol->>'implementation_sha256' into implementation from paperlab.history_runtime where singleton;
 if p_policy->>'version' is distinct from 'breadth-study-v1' or p_policy->>'reference_implementation' is distinct from implementation
  or p_policy->>'max_new' is distinct from '150' or p_policy->>'max_active' is distinct from '5000' or p_policy->>'detail_per_day' is distinct from '40'
  or p_policy->>'max_records' is distinct from '50000' or p_policy->>'compact_days' is distinct from '365' then raise exception 'Invalid breadth policy';end if;
 fp:=encode(sha256(convert_to(jsonb_build_object('model',m.id,'hash',m.artifact->>'integrity_hash','policy',p_policy)::text,'UTF8')),'hex');
 select * into r from paperlab.breadth_runtime where singleton for update;
 if r.profile is not null and r.profile<>fp then raise exception 'Existing breadth policy is frozen';end if;
 update paperlab.breadth_runtime set profile=fp,policy=p_policy,model_id=m.id,reference_hash=m.artifact->>'integrity_hash',reference_profile=m.artifact->>'fingerprint',reference_implementation=implementation where singleton;
 return fp;
end$$;

create or replace function public.paper_breadth_claim() returns jsonb
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare r paperlab.breadth_runtime;artifact_json jsonb;payload jsonb;current_day date;month_day date;allocated bigint;budgeted bigint;usage_bytes bigint;db_bytes bigint;
 row_count integer;active_count integer;trace_count integer;new_limit integer;detail_limit integer;charge bigint;t uuid;
begin
 select * into r from paperlab.breadth_runtime where singleton for update;current_day:=(now() at time zone 'UTC')::date;
 if not r.enabled or r.profile is null or r.lease_until>now() or r.last_day=current_day then return null;end if;
 if not exists(select 1 from paperlab.portfolio where singleton and paperlab.run_open(state)) then return null;end if;
 if not exists(select 1 from paperlab.history_runtime where singleton and last_forward=current_day and protocol->>'implementation_sha256'=r.reference_implementation) then
  update paperlab.breadth_runtime set status='waiting_reference' where singleton;return null;end if;
 select artifact into artifact_json from paperlab.history_models where id=r.model_id and artifact->>'integrity_hash'=r.reference_hash and artifact->>'fingerprint'=r.reference_profile;
 if artifact_json is null then update paperlab.breadth_runtime set status='reference_changed' where singleton;return null;end if;
 delete from paperlab.breadth_traces where day<current_day-90;
 delete from paperlab.breadth_scores where day<current_day-365 and status in(2,3);
 delete from paperlab.breadth_days where day<current_day-730;
 month_day:=date_trunc('month',now() at time zone 'UTC')::date;insert into paperlab.free_usage(month) values(month_day) on conflict do nothing;
 select estimated_worker_egress_bytes into usage_bytes from paperlab.free_usage where month=month_day for update;
 select sum(pg_total_relation_size(x::regclass)) into allocated from unnest(array['paperlab.breadth_scores','paperlab.breadth_traces','paperlab.breadth_days'])x;
 db_bytes:=pg_database_size(current_database());
 if allocated>=40000000 or db_bytes>=180000000 or usage_bytes>=1800000000 then update paperlab.breadth_runtime set status='hard_budget_paused' where singleton;return null;end if;
 select count(*),count(*) filter(where status in(0,1)) into row_count,active_count from paperlab.breadth_scores;
 select count(*) into trace_count from paperlab.breadth_traces;
 -- Reusable database pages are not fresh data: estimate live records and
 -- index overhead for admission, while retaining a separate physical hard cap.
 budgeted:=(select coalesce(sum(pg_column_size(s)),0) from paperlab.breadth_scores s)+(select coalesce(sum(pg_column_size(trace_row)),0) from paperlab.breadth_traces trace_row)+(select coalesce(sum(pg_column_size(d)),0) from paperlab.breadth_days d)+row_count*96+trace_count*80;
 new_limit:=greatest(0,least(150,50000-row_count,5000-active_count,((32000000-budgeted-active_count*256)/768)::integer));
 if budgeted>=32000000 or db_bytes>=150000000 or usage_bytes>=1500000000 then new_limit:=0;
 elsif budgeted>=24000000 or usage_bytes>=1200000000 then new_limit:=least(new_limit,75);end if;
 detail_limit:=greatest(0,least(40,3500-trace_count,((24000000-budgeted-active_count*256)/6000)::integer));
 if new_limit=0 or budgeted>=24000000 or usage_bytes>=1200000000 then detail_limit:=0;end if;
 payload:=jsonb_build_object('artifact',artifact_json,'reference_implementation',r.reference_implementation,'config',(select config from paperlab.history_runtime where singleton),
  'reference_symbols',(select coalesce(jsonb_agg(symbol),'[]') from paperlab.history_forecasts where model_id=r.model_id and day=current_day),
  'seen',(select coalesce(jsonb_agg(symbol),'[]') from paperlab.breadth_scores where model_id=r.model_id and day=current_day),
  'active',(select coalesce(jsonb_agg(jsonb_build_array(symbol,day,extract(epoch from decision_at)*1000,known_day,probability,to_jsonb(features),status,to_jsonb(entry),to_jsonb(outcome),reason)),'[]') from paperlab.breadth_scores where model_id=r.model_id and status in(0,1)),
  'tails',(select jsonb_agg(jsonb_build_object('symbol',symbol,'status',status,'data',tail,'hash',hash,'created_at',created_at)) from paperlab.history_snapshots where tail is not null),
  'bars',(select jsonb_agg(jsonb_build_array(b.symbol,b.day,extract(epoch from (b.record->>'open_time')::timestamptz)*1000,b.close,b.record->'volume',b.record->'fx',b.record->'fx_date',extract(epoch from b.observed_at)*1000,
    case when b.day=latest.last_day then b.record->'session_starts' else null end,
    exists(select 1 from jsonb_array_elements(coalesce(b.record->'actions','[]'))a where a->>'type'='splits')))
    from paperlab.daily_study_bars b join(select symbol,max(day) as last_day from paperlab.daily_study_bars group by symbol)latest on latest.symbol=b.symbol),
  'revised_symbols',coalesce((select record->'revised_symbols' from paperlab.daily_study_quality where day=current_day),'[]'),
  'max_new',new_limit,'max_details',detail_limit,'policy',r.policy);
 charge:=4*octet_length(payload::text)+131072;
 if usage_bytes+charge>=1800000000 then update paperlab.breadth_runtime set status='hard_budget_paused' where singleton;return null;end if;
 update paperlab.free_usage set estimated_worker_egress_bytes=estimated_worker_egress_bytes+charge where month=month_day;
 t:=gen_random_uuid();update paperlab.breadth_runtime set token=t,lease_until=now()+interval '150 seconds',admission_new=new_limit,admission_detail=detail_limit,status=case when new_limit=0 then 'finishing_only' else 'processing' end where singleton;
 return payload||jsonb_build_object('token',t);
end$$;

create or replace function public.paper_breadth_commit(p_token uuid,p_output jsonb) returns boolean
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare r paperlab.breadth_runtime;x jsonb;prior paperlab.breadth_scores;current_day date;decision_time timestamptz;features_value double precision[];entry_value double precision[];outcome_value double precision[];
 status_value smallint;symbol_value text;day_value date;sector_value text;venue_value text;charge bigint;
begin
 select * into r from paperlab.breadth_runtime where singleton and token=p_token and lease_until>now() for update;if not found then return false;end if;
 current_day:=(now() at time zone 'UTC')::date;
 if p_output->>'protocol' is distinct from 'breadth-study-v1' or p_output->>'model_id' is distinct from r.model_id
  or jsonb_typeof(p_output->'records') is distinct from 'array' or jsonb_typeof(p_output->'updates') is distinct from 'array' or jsonb_typeof(p_output->'traces') is distinct from 'array'
  or jsonb_array_length(p_output->'records')>r.admission_new or jsonb_array_length(p_output->'updates')>5000 or jsonb_array_length(p_output->'traces')>r.admission_detail or octet_length(p_output::text)>4500000 then raise exception 'Breadth batch outside limits';end if;
 charge:=4*octet_length(p_output::text);
 perform 1 from paperlab.free_usage where month=date_trunc('month',now() at time zone 'UTC')::date for update;
 if exists(select 1 from paperlab.free_usage where month=date_trunc('month',now() at time zone 'UTC')::date and estimated_worker_egress_bytes+charge>=1800000000) then
  update paperlab.breadth_runtime set token=null,lease_until=null,status='hard_budget_paused' where singleton;return false;end if;
 for x in select value from jsonb_array_elements(p_output->'records') loop
  symbol_value:=x->>0;day_value:=(x->>1)::date;decision_time:=to_timestamp((x->>2)::double precision/1000);
  select array_agg(value::text::double precision order by n) into features_value from jsonb_array_elements(x->5) with ordinality z(value,n);
  select value->>'sector',value->>'exchange' into sector_value,venue_value from jsonb_array_elements((select catalogue from paperlab.daily_study_runtime)) where value->>'symbol'=symbol_value;
  if jsonb_array_length(x)<>8 or day_value<>current_day or extract(isodow from day_value)>5 or decision_time<now()-interval '150 seconds' or decision_time>now()+interval '1 minute' or (x->>3)::date>=day_value
   or cardinality(features_value)<>8 or exists(select 1 from unnest(features_value)v where (v between -1000000 and 1000000) is not true)
   or ((x->>4)::double precision between 0 and 1) is not true or sector_value is null or sector_value is distinct from x->>6 or venue_value is distinct from x->>7
   or not exists(select 1 from paperlab.history_models m where m.id=r.model_id and m.created_at<decision_time and m.artifact->'symbols' ? symbol_value)
   or exists(select 1 from paperlab.history_forecasts where model_id=r.model_id and symbol=symbol_value and day=day_value) then raise exception 'Invalid or duplicate reference prediction';end if;
  if (select count(*) from paperlab.breadth_scores)>=50000 or (select count(*) from paperlab.breadth_scores where status in(0,1))>=5000 then exit;end if;
  insert into paperlab.breadth_scores(model_id,symbol,day,decision_at,known_day,probability,features,sector,venue) values(r.model_id,symbol_value,day_value,decision_time,(x->>3)::date,(x->>4)::double precision,features_value,sector_value,venue_value) on conflict do nothing;
 end loop;
 for x in select value from jsonb_array_elements(p_output->'updates') loop
  symbol_value:=x->>0;day_value:=(x->>1)::date;status_value:=(x->>2)::smallint;
  select * into prior from paperlab.breadth_scores where model_id=r.model_id and symbol=symbol_value and day=day_value for update;
  if not found or prior.status not in(0,1) or status_value not in(1,2,3) or jsonb_array_length(x)<>6 then raise exception 'Unknown or completed breadth record';end if;
  entry_value:=null;outcome_value:=null;
  if jsonb_typeof(x->3)='array' then select array_agg(value::text::double precision order by n) into entry_value from jsonb_array_elements(x->3) with ordinality z(value,n);end if;
  if jsonb_typeof(x->4)='array' then select array_agg(value::text::double precision order by n) into outcome_value from jsonb_array_elements(x->4) with ordinality z(value,n);end if;
  if prior.entry is not null and prior.entry is distinct from entry_value or prior.outcome is not null and prior.outcome is distinct from outcome_value then raise exception 'Frozen breadth entry or outcome changed';end if;
  if entry_value is not null then
   if cardinality(entry_value)<>12 or exists(select 1 from unnest(entry_value)v where (v between -1000000000000000 and 1000000000000000) is not true) or entry_value[1]<=extract(epoch from prior.decision_at)*1000 or entry_value[12]<>100
    or (entry_value[8]>0 and entry_value[8]<'Infinity'::float8) is not true or entry_value[5]<=0
    or not exists(select 1 from paperlab.daily_study_bars b where b.symbol=symbol_value and b.day=(to_timestamp(entry_value[3]/1000) at time zone 'UTC')::date and b.close=entry_value[4]
      and (b.record->>'fx')::float8=entry_value[5] and abs(extract(epoch from (b.record->>'open_time')::timestamptz)*1000-entry_value[1])<1
      and entry_value[1]=(select min(v::text::double precision)*1000 from jsonb_array_elements(b.record->'session_starts')v where v::text::double precision*1000>extract(epoch from prior.decision_at)*1000)) then raise exception 'Unbacked or retrospective breadth entry';end if;
  end if;
  if outcome_value is not null and outcome_value[1]=1 then
   if cardinality(outcome_value)<>10 or exists(select 1 from unnest(outcome_value)v where (v between -1000000000000000 and 1000000000000000) is not true) or entry_value is null or outcome_value[2]<=entry_value[3] or (outcome_value[7] between -100 and 1000000) is not true or (outcome_value[8]<=outcome_value[7]) is not true
    or not exists(select 1 from paperlab.daily_study_bars b cross join lateral jsonb_array_elements(b.record->'session_starts') with ordinality e(value,n)
     cross join lateral jsonb_array_elements(b.record->'session_starts') with ordinality z(value,n) where b.symbol=symbol_value and b.day=(to_timestamp(outcome_value[2]/1000) at time zone 'UTC')::date
      and b.close=outcome_value[4] and (b.record->>'fx')::float8=outcome_value[5] and (to_timestamp(e.value::text::float8) at time zone 'UTC')::date=(to_timestamp(entry_value[3]/1000) at time zone 'UTC')::date
      and (to_timestamp(z.value::text::float8) at time zone 'UTC')::date=b.day and z.n-e.n=20) then raise exception 'Unbacked breadth outcome or incorrect horizon';end if;
  end if;
  update paperlab.breadth_scores set status=status_value,entry=entry_value,outcome=outcome_value,reason=x->>5 where model_id=r.model_id and symbol=symbol_value and day=day_value;
 end loop;
 for x in select value from jsonb_array_elements(p_output->'traces') loop
  symbol_value:=x->>'symbol';day_value:=(x->>'day')::date;
  if day_value<>current_day or jsonb_array_length(x->'record'->'prices')<>21 or x->'record'->>'codec'<>'1' or exists(select 1 from paperlab.breadth_traces where model_id=r.model_id and symbol=symbol_value and day=day_value)
   or not exists(select 1 from paperlab.breadth_scores where model_id=r.model_id and symbol=symbol_value and day=day_value and status=0 and abs(extract(epoch from decision_at)*1000-extract(epoch from (x->'record'->>'recorded_at')::timestamptz)*1000)<1)
   or exists(select 1 from jsonb_array_elements(x->'record'->'prices')p where (p->>3)::float8>extract(epoch from (x->'record'->>'recorded_at')::timestamptz)*1000)
   or exists(select 1 from jsonb_each(x->'record'->'indices')i cross join lateral jsonb_array_elements(i.value)p where (p->>2)::float8>extract(epoch from (x->'record'->>'recorded_at')::timestamptz)*1000) then raise exception 'Invalid or frozen breadth trace';end if;
  if (select count(*) from paperlab.breadth_traces)>=3500 then exit;end if;
  insert into paperlab.breadth_traces values(r.model_id,symbol_value,day_value,x->'record');
 end loop;
 insert into paperlab.breadth_days values(current_day,p_output->'summary'||jsonb_build_object('admission_new',r.admission_new,'admission_detail',r.admission_detail));
 update paperlab.free_usage set estimated_worker_egress_bytes=estimated_worker_egress_bytes+charge where month=date_trunc('month',now() at time zone 'UTC')::date;
 update paperlab.breadth_runtime set token=null,lease_until=null,last_day=current_day,last_success=now(),summary=p_output->'summary',status=case when admission_new=0 then 'finishing_only' when admission_new<150 or admission_detail<40 then 'reduced_admission' else 'observing' end where singleton;
 return true;
end$$;

create or replace function public.paper_breadth_fail(p_token uuid) returns void
language sql security definer set search_path=pg_catalog,pg_temp as $$
 update paperlab.breadth_runtime set token=null,lease_until=null,status='error' where singleton and token=p_token;
$$;

create or replace function public.paper_breadth_action(p_owner uuid,p_action text) returns boolean
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton) then raise exception 'Owner required';end if;
 if p_action not in('pause','resume') then return false;end if;
 update paperlab.breadth_runtime set enabled=p_action='resume',token=null,lease_until=null,status=case when p_action='pause' then 'owner_paused' else 'waiting' end where singleton;
 return true;
end$$;

create or replace function public.paper_breadth_read(p_owner uuid) returns jsonb
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton) then raise exception 'Owner required';end if;
 return jsonb_build_object('runtime',(select to_jsonb(r)-'token'-'lease_until' from paperlab.breadth_runtime r),
  'counts',(select jsonb_build_object('compact',count(*),'active',count(*) filter(where status in(0,1)),'complete',count(*) filter(where status=2),'missing',count(*) filter(where status=3),'dates',count(distinct day),'companies',count(distinct symbol),
    'traces',(select count(*) from paperlab.breadth_traces),'reference',(select count(*) from paperlab.history_forecasts where model_id=(select model_id from paperlab.breadth_runtime))) from paperlab.breadth_scores),
  'storage_bytes',(select sum(pg_total_relation_size(x::regclass)) from unnest(array['paperlab.breadth_scores','paperlab.breadth_traces','paperlab.breadth_days'])x),
  'budgeted_bytes',(select coalesce(sum(pg_column_size(s)),0)+count(*)*96 from paperlab.breadth_scores s)+(select coalesce(sum(pg_column_size(trace_row)),0)+count(*)*80 from paperlab.breadth_traces trace_row)+(select coalesce(sum(pg_column_size(d)),0) from paperlab.breadth_days d),
  'monthly_estimate_bytes',(select estimated_worker_egress_bytes from paperlab.free_usage where month=date_trunc('month',now() at time zone 'UTC')::date),
  'groups',(select coalesce(jsonb_agg(to_jsonb(g)),'[]') from(select sector,count(*) as records,count(*) filter(where status=2) as observed,count(*) filter(where status=3) as missing,
    avg(outcome[7]) filter(where status=2) as mean_net_eur,avg(outcome[8]) filter(where status=2) as mean_stressed_eur,count(distinct day) as dates from paperlab.breadth_scores group by sector)g),
  'days',(select coalesce(jsonb_agg(record order by day desc),'[]') from(select * from paperlab.breadth_days order by day desc limit 7)d));
end$$;

create or replace function public.paper_breadth_export(p_owner uuid,p_traces boolean default false) returns jsonb
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton) then raise exception 'Owner required';end if;
 if p_traces then return(select coalesce(jsonb_agg(to_jsonb(t) order by day desc,symbol),'[]') from(select * from paperlab.breadth_traces order by day desc,symbol limit 40)t);end if;
 return(select coalesce(jsonb_agg(to_jsonb(s)||jsonb_build_object('origin','exploratory_hypothetical','codec',1) order by day desc,symbol),'[]') from(select * from paperlab.breadth_scores order by day desc,symbol limit 500)s);
end$$;
do $$declare n text;begin for n in select p.oid::regprocedure::text from pg_proc p join pg_namespace s on s.oid=p.pronamespace where s.nspname='public' and p.proname like 'paper_breadth_%' loop
 execute 'revoke all on function '||n||' from public,anon,authenticated';execute 'grant execute on function '||n||' to service_role';end loop;end$$;
commit;
