begin;
create table if not exists paperlab.study_profiles(
 fingerprint text primary key,created_at timestamptz not null default now(),protocol text not null,parameters jsonb not null check(octet_length(parameters::text)<=16000)
);
-- Typed arrays avoid repeating field names/configuration tens of thousands of times.
create table if not exists paperlab.opportunity_archive(
 id text primary key,profile text not null references paperlab.study_profiles(fingerprint),day date not null,time timestamptz not null,
 symbol text not null,venue text not null,cohort text not null,reason text not null check(length(reason)<=600),
 features double precision[] not null check(cardinality(features)=7),observations double precision[] not null check(cardinality(observations)=18),
 entry double precision[] check(cardinality(entry)=10),h30 double precision[] check(cardinality(h30) in(1,11)),h120 double precision[] check(cardinality(h120) in(1,11)),
 status text not null,flags text[] not null default '{}',main_reasons text[] not null,decision_hash text not null,
 unique(profile,day,symbol,cohort)
);
create index if not exists archive_day_profile on paperlab.opportunity_archive(profile,day);
create index if not exists archive_time on paperlab.opportunity_archive(time);
create table if not exists paperlab.study_epochs(
 id bigint generated always as identity primary key,profile text not null references paperlab.study_profiles(fingerprint),
 development_start date not null,test_start date not null,test_end date not null,
 released_at timestamptz,report jsonb check(octet_length(report::text)<=32000),unique(profile,development_start),check(development_start<test_start and test_start<test_end)
);
create table if not exists paperlab.reliability_runtime(
 singleton boolean primary key default true check(singleton),token uuid,lease_until timestamptz,last_claim timestamptz,last_success timestamptz,status text not null default 'waiting'
);
insert into paperlab.reliability_runtime(singleton) values(true) on conflict do nothing;
create table if not exists paperlab.model_assessments(
 model_id text primary key references paperlab.learning_models(id),created_at timestamptz not null default now(),report jsonb not null check(octet_length(report::text)<=32000)
);
create table if not exists paperlab.learning_inputs(
 token uuid primary key,created_at timestamptz not null default now(),fingerprint text not null,model_id text references paperlab.learning_models(id),
 dataset jsonb not null check(octet_length(dataset::text)<=4000000),checksum text not null
);
create table if not exists paperlab.learning_epochs(
 id bigint generated always as identity primary key,created_at timestamptz not null default now(),reason text not null,old_runtime jsonb not null
);
create table if not exists paperlab.reliability_catalogue(symbol text primary key,sector text not null,venue text not null);
do $$declare n text;begin
 foreach n in array array['study_profiles','opportunity_archive','study_epochs','reliability_runtime','model_assessments','learning_inputs','learning_epochs','reliability_catalogue'] loop
  execute format('alter table paperlab.%I enable row level security',n);
  execute format('revoke all on paperlab.%I from public,anon,authenticated,service_role',n);
 end loop;
end$$;

create or replace function paperlab.ensure_study_epoch(p_profile text) returns void
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare start_day date;
begin
 select max(test_end)+1 into start_day from paperlab.study_epochs where profile=p_profile;
 if start_day is null then start_day:=(now() at time zone 'UTC')::date+1;end if;
 if start_day<=(now() at time zone 'UTC')::date+1 then
  insert into paperlab.study_epochs(profile,development_start,test_start,test_end) values(p_profile,start_day,start_day+60,start_day+119) on conflict do nothing;
 end if;
end$$;

create or replace function paperlab.archive_outcome(p jsonb) returns double precision[]
language sql immutable set search_path=pg_catalog,pg_temp as $$
 select case when p is null then null when p->>'status'<>'observed' then array[2.]::double precision[] else array[
  1.,extract(epoch from(p->>'time')::timestamptz)*1000,extract(epoch from(p->>'quote_time')::timestamptz)*1000,
  (p->>'net_eur')::double precision,(p->>'gross_move_percent')::double precision,(p->>'actual_minutes')::double precision,
  (p->>'price_local')::double precision,(p->>'fx')::double precision,(p->'exit_costs'->>'gross_eur')::double precision,
  (p->'exit_costs'->>'commission_eur')::double precision,
  coalesce((p->'exit_costs'->>'transaction_tax_eur')::double precision,0)+coalesce((p->'exit_costs'->>'capital_gains_reserve_eur')::double precision,0)+coalesce((p->'exit_costs'->>'foreign_tax_reserve_eur')::double precision,0)+coalesce((p->'exit_costs'->>'adr_reserve_eur')::double precision,0)] end;
$$;

create or replace function public.paper_opportunity_archive_sync(p_ids jsonb) returns void
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare r record;x jsonb;e jsonb;entry_values double precision[];observations_values double precision[];hash text;prior paperlab.opportunity_archive;
begin
 for r in select * from paperlab.opportunity_records where p_ids is null or id in(select value->>'id' from jsonb_array_elements(p_ids)) loop
  x:=r.record;
  -- Legacy/incomplete diagnostic fixtures have no causal dossier and are not manufactured.
  if x->'context'->'features' is null or jsonb_array_length(x->'observations')<>6 then continue;end if;
  insert into paperlab.study_profiles values(r.fingerprint,now(),x->>'protocol',jsonb_build_object('tax',x->'cost_estimate'->'tax_config','costs',x->'cost_estimate'->'cost_config','budget_eur',100,'codec',1,'feature_schema','decision-net-v1','horizons_minutes',jsonb_build_array(30,120))) on conflict do nothing;
  perform paperlab.ensure_study_epoch(r.fingerprint);
  hash:=encode(sha256(convert_to((x-'entry'-'outcomes'-'status'-'finished_at'-'reason')::text,'UTF8')),'hex');
  select * into prior from paperlab.opportunity_archive where id=r.id;
  if found and prior.decision_hash<>hash then raise exception 'Immutable opportunity decision changed';end if;
  e:=x->'entry';entry_values:=null;
  if e is not null then entry_values:=array[extract(epoch from(e->>'time')::timestamptz)*1000,extract(epoch from(e->>'quote_time')::timestamptz)*1000,
   (e->>'price_eur')::double precision,(e->>'price_local')::double precision,(e->>'fx')::double precision,(e->>'qty')::double precision,(e->>'cost')::double precision,(e->>'entry_gross_eur')::double precision,(e->>'commission_eur')::double precision,
   (select coalesce(sum(value::text::double precision),0) from jsonb_each(e->'taxes'))];end if;
  select array_agg(v order by ordinal,sub) into observations_values from(
   select ordinality as ordinal,1 as sub,extract(epoch from(value->>'time')::timestamptz)*1000 as v from jsonb_array_elements(x->'observations') with ordinality
   union all select ordinality,2,(value->>'price')::double precision from jsonb_array_elements(x->'observations') with ordinality
   union all select ordinality,3,extract(epoch from coalesce(value->>'quote_time',value->>'time')::timestamptz)*1000 from jsonb_array_elements(x->'observations') with ordinality) q;
  if prior.id is not null and (prior.entry is not null and prior.entry is distinct from entry_values or prior.h30 is not null and prior.h30 is distinct from paperlab.archive_outcome(x->'outcomes'->'30') or prior.h120 is not null and prior.h120 is distinct from paperlab.archive_outcome(x->'outcomes'->'120')) then raise exception 'Frozen opportunity entry or outcome changed';end if;
  insert into paperlab.opportunity_archive(id,profile,day,time,symbol,venue,cohort,reason,features,observations,entry,h30,h120,status,flags,main_reasons,decision_hash)
   values(r.id,r.fingerprint,r.day,r.time,r.symbol,x->>'venue',r.cohort,x->>'statement',
    array(select value::text::double precision from jsonb_array_elements(x->'context'->'features')),observations_values,entry_values,
    paperlab.archive_outcome(x->'outcomes'->'30'),paperlab.archive_outcome(x->'outcomes'->'120'),x->>'status',
    case when exists(select 1 from jsonb_each(x->'outcomes') o where abs((o.value->>'gross_move_percent')::double precision)>30) then array['extreme_price_or_fx'] else '{}' end,
    array(select jsonb_array_elements_text(x->'main_reasons')),hash)
   on conflict(id) do update set entry=excluded.entry,h30=excluded.h30,h120=excluded.h120,status=excluded.status,flags=excluded.flags;
 end loop;
end$$;

create or replace function public.paper_opportunity_payload() returns jsonb
language sql security definer set search_path=pg_catalog,pg_temp as $$
 select case when enabled then jsonb_build_object('enabled',true,'revision',revision,'state',state,'max_new_records',
  case when pg_total_relation_size('paperlab.opportunity_archive')>=88000000 and (select coalesce(sum(pg_column_size(a)),0) from paperlab.opportunity_archive a)>=70000000 then 0 else greatest(0,least(200,50000-(select count(*)::integer from paperlab.opportunity_archive))) end)
 else jsonb_build_object('enabled',false,'revision',revision) end from paperlab.opportunity_runtime where singleton;
$$;

create or replace function paperlab.study_sealed(p_profile text,p_day date) returns boolean
language sql stable security definer set search_path=pg_catalog,pg_temp as $$
 select exists(select 1 from paperlab.study_epochs where profile=p_profile and p_day between test_start and test_end and released_at is null);
$$;
create or replace function paperlab.visible_study_record(p_record jsonb) returns jsonb
language sql stable security definer set search_path=pg_catalog,pg_temp as $$
 select case when paperlab.study_sealed(p_record->>'fingerprint',(p_record->>'day')::date) then jsonb_set(p_record,'{outcomes}',
  '{"30":{"status":"sealed","reason":"Afgeschermd toetsvak; vrijgave pas na de vooraf vastgelegde einddatum."},"120":{"status":"sealed","reason":"Afgeschermd toetsvak; vrijgave pas na de vooraf vastgelegde einddatum."}}') else p_record end;
$$;

create or replace function public.paper_learning_requirements() returns jsonb
language sql stable security definer set search_path=pg_catalog,pg_temp as $$
 select '{"samples":300,"days":60,"forward_days":60,"forward_closes":120,"version":"reliability-v1"}'::jsonb;
$$;
create or replace function public.paper_learning_can_train() returns boolean
language sql stable security definer set search_path=pg_catalog,pg_temp as $$
 select not exists(select 1 from paperlab.learning_models m where m.status in('shadow','eligible','active') and m.created_at>now()-interval '180 days')
 and (select count(*) from paperlab.learning_inputs where model_id is not null)<12
 and (select coalesce(sum(octet_length(dataset::text)),0) from paperlab.learning_inputs)<20000000;
$$;
create or replace function public.paper_learning_capture_input(p_token uuid,p_fingerprint text,p_data jsonb) returns void
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
begin
 if octet_length(p_data::text)>4000000 or (select coalesce(sum(octet_length(dataset::text)),0) from paperlab.learning_inputs)+octet_length(p_data::text)>24000000 then raise exception 'Frozen dataset storage budget';end if;
 insert into paperlab.learning_inputs values(p_token,now(),p_fingerprint,null,p_data,encode(sha256(convert_to(p_data::text,'UTF8')),'hex'));
end$$;
create or replace function public.paper_learning_artifact_allowed(p_artifact jsonb) returns boolean
language sql stable security definer set search_path=pg_catalog,pg_temp as $$
 select coalesce(p_artifact->>'protocol'='paper-learning-v2' and p_artifact->'reliability'->>'version'='reliability-v1'
 and (p_artifact->'reliability'->>'samples')::integer>=300 and (p_artifact->'reliability'->>'days')::integer>=60
 and (p_artifact->'reliability'->>'symbols')::integer>=10 and (p_artifact->'reliability'->>'sectors')::integer>=5
 and (p_artifact->'reliability'->>'validation_rows')::integer>=30 and (p_artifact->'reliability'->>'test_rows')::integer>=30,false);
$$;
create or replace function public.paper_learning_record_dataset(p_token uuid,p_artifact jsonb) returns void
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
begin
 update paperlab.learning_inputs set model_id=p_artifact->>'id' where token=p_token and fingerprint=p_artifact->>'fingerprint';
 if not found then raise exception 'Original frozen training input missing';end if;
end$$;

create or replace function paperlab.model_audit_case(p_id text) returns jsonb
language sql stable security definer set search_path=pg_catalog,pg_temp as $$
 with model as(select * from paperlab.learning_models where id=p_id), paired as(
  select a.day,a.record as reference,b.record as learned from paperlab.learning_days a join paperlab.learning_days b on a.day=b.day and a.phase=b.phase,model m
  where a.account='reference' and b.account='learned' and a.model_id=m.id and b.model_id=m.id and a.day<(now() at time zone 'UTC')::date
   and a.day>greatest((m.artifact->>'training_cutoff')::date,(m.created_at at time zone 'UTC')::date) and extract(isodow from a.day) between 1 and 5
   and (a.record->>'complete')::boolean and (b.record->>'complete')::boolean
   and (a.record->>'unique_rounds')::integer>=160 and (b.record->>'unique_rounds')::integer>=160 order by a.day limit 60),
 trades as(select t.* from paperlab.learning_trades t where t.account='learned' and t.phase=p_id and (t.time at time zone 'UTC')::date in(select day from paired)),
 quality as(select d.day,min((v.value->>'fresh')::double precision/nullif((v.value->>'expected')::double precision,0)) coverage
  from paperlab.daily_quality d cross join lateral jsonb_each(d.venues) v,model m where d.day in(select day from paired) and v.key in(select jsonb_array_elements_text(m.artifact->'venues')) group by d.day)
 select jsonb_build_object('artifact',m.artifact,'status',m.status,
  'records',(select coalesce(jsonb_agg(record order by record->>'date',record->>'account'),'[]'::jsonb) from(select reference as record from paired union all select learned from paired)q),
  'window',(select coalesce(jsonb_agg(day order by day),'[]'::jsonb) from paired),
  'meta',jsonb_build_object('closes',(select count(*) from trades where trade->>'side'='verkoop'),
   'symbols',(select count(distinct trade->>'symbol') from trades where trade->>'side'='verkoop'),
   'sectors',(select count(distinct c.sector) from trades t join paperlab.reliability_catalogue c on c.symbol=t.trade->>'symbol' where trade->>'side'='verkoop'),
   'flagged_trades',(select count(*) from trades where trade->>'side'='verkoop' and abs((trade->>'pnl')::double precision)>30),
   'quality_days',(select count(*) from quality),'min_source_coverage',(select coalesce(min(coverage),0) from quality),
   'calendar_coverage',coalesce((select count(*) from paired)::double precision/nullif((select count(*) from generate_series((m.created_at at time zone 'UTC')::date+1,(select max(day) from paired),'1 day')d where extract(isodow from d) between 1 and 5),0),0)))
 from model m;
$$;

create or replace function paperlab.epoch_audit_case(p_id bigint) returns jsonb
language sql stable security definer set search_path=pg_catalog,pg_temp as $$
 with e as(select * from paperlab.study_epochs where id=p_id), pairs as(
  select m.day,m.symbol,m.venue,m.h120 as mh,c.h120 as ch,m.entry as me,m.flags from paperlab.opportunity_archive m
  left join paperlab.opportunity_archive c on c.profile=m.profile and c.day=m.day and c.symbol=m.symbol and c.cohort='control',e
  where m.profile=e.profile and m.cohort='momentum' and m.day between e.test_start and e.test_end), daily as(
  select day,count(*) expected,count(*) filter(where mh[1]=1 and ch[1]=1) observed,
   avg(mh[4]-ch[4]) filter(where mh[1]=1 and ch[1]=1) mean_difference_eur,
   avg(mh[4]-ch[4]-me[9]-mh[10]-.001*(me[8]+mh[9])) filter(where mh[1]=1 and ch[1]=1) mean_stressed_difference_eur,
   avg(case when mh[1]=1 and ch[1]=1 then mh[4]-ch[4] else -100 end) adverse_mean_eur,
   avg(ch[5]) filter(where ch[1]=1) control_gross_mean from pairs group by day)
 select jsonb_build_object('id',e.id,'test_end',e.test_end,'days',(select coalesce(jsonb_agg(d order by day),'[]'::jsonb) from daily d),
  'sectors',(select count(distinct c.sector) from pairs p join paperlab.reliability_catalogue c on c.symbol=p.symbol),
  'venues',(select count(distinct venue) from pairs),'flagged',(select count(*) from pairs where cardinality(flags)>0)) from e;
$$;

create or replace function public.paper_audit_input() returns jsonb
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare r paperlab.reliability_runtime;t uuid;data jsonb;m date;charge bigint;
begin
 select * into r from paperlab.reliability_runtime where singleton for update;
 if r.lease_until>now() or r.last_claim>now()-interval '4 hours' then return null;end if;
 if not exists(select 1 from paperlab.portfolio where singleton and paperlab.run_open(state)) then return null;end if;
 data:=jsonb_build_object('models',(select coalesce(jsonb_agg(paperlab.model_audit_case(id)),'[]'::jsonb) from paperlab.learning_models m where status in('shadow','eligible','active') and not exists(select 1 from paperlab.model_assessments a where a.model_id=m.id)),
  'epochs',(select coalesce(jsonb_agg(paperlab.epoch_audit_case(id)),'[]'::jsonb) from paperlab.study_epochs where test_end<(now() at time zone 'UTC')::date and released_at is null));
 m:=date_trunc('month',now() at time zone 'UTC')::date;charge:=4*(octet_length(data::text)+16384);
 insert into paperlab.free_usage(month) values(m) on conflict do nothing;
 perform 1 from paperlab.free_usage where month=m for update;
 if pg_database_size(current_database())>=250000000 or exists(select 1 from paperlab.free_usage where month=m and estimated_worker_egress_bytes+charge>least(max_worker_egress_bytes,2400000000)) then
  update paperlab.reliability_runtime set status='budget_paused' where singleton;return null;end if;
 update paperlab.free_usage set estimated_worker_egress_bytes=estimated_worker_egress_bytes+charge where month=m;
 t:=gen_random_uuid();update paperlab.reliability_runtime set token=t,lease_until=now()+interval '120 seconds',last_claim=now(),status='checking' where singleton;
 return data||jsonb_build_object('token',t);
end$$;

create or replace function public.paper_audit_fail(p_token uuid) returns void
language sql security definer set search_path=pg_catalog,pg_temp as $$
 update paperlab.reliability_runtime set token=null,lease_until=null,status='error' where singleton and token=p_token;
$$;

create or replace function public.paper_audit_store(p_token uuid,p_result jsonb) returns boolean
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare x jsonb;c jsonb;
begin
 perform 1 from paperlab.reliability_runtime where singleton and token=p_token and lease_until>now() for update;
 if not found then return false;end if;
 if octet_length(p_result::text)>200000 then raise exception 'Audit too large';end if;
 for x in select value from jsonb_array_elements(p_result->'models') loop
  if x->>'status'<>'final' or x->>'version'<>'reliability-v1' then raise exception 'Invalid final assessment';end if;
  c:=paperlab.model_audit_case(x->>'model_id');
  if c is null or jsonb_array_length(c->'window')<>60 or c->'window' is distinct from x->'window' or jsonb_array_length(x->'bounds')<>2 then raise exception 'Actual fixed audit window missing';end if;
  if (x->>'eligible')::boolean and ((c->'meta'->>'closes')::integer<120 or (c->'meta'->>'symbols')::integer<10 or (c->'meta'->>'sectors')::integer<5 or (c->'meta'->>'quality_days')::integer<60 or (c->'meta'->>'min_source_coverage')::double precision<.9 or (c->'meta'->>'calendar_coverage')::double precision<.8 or (c->'meta'->>'flagged_trades')::integer>0 or exists(select 1 from jsonb_array_elements(x->'bounds') b where (b->>'lower')::double precision<=0)) then raise exception 'Stored independent evidence insufficient';end if;
  insert into paperlab.model_assessments values(x->>'model_id',now(),x||jsonb_build_object('source_digest',encode(sha256(convert_to((c->'records')::text||(c->'meta')::text,'UTF8')),'hex'))) on conflict do nothing;
  if (x->>'eligible')::boolean is not true then update paperlab.learning_models set status='rejected' where id=x->>'model_id' and status<>'active';end if;
 end loop;
 for x in select value from jsonb_array_elements(p_result->'epochs') loop
  if x->>'status'<>'final' or x->>'version'<>'reliability-v1' then raise exception 'Invalid epoch assessment';end if;
  update paperlab.study_epochs set released_at=now(),report=x where id=(x->>'epoch_id')::bigint and test_end<(now() at time zone 'UTC')::date and released_at is null;
 end loop;
 update paperlab.reliability_runtime set token=null,lease_until=null,last_success=now(),status='ok' where singleton;
 return true;
end$$;

create or replace function paperlab.learning_promote(p_model text) returns boolean
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare r paperlab.learning_runtime;m paperlab.learning_models;p paperlab.portfolio;a paperlab.model_assessments;c jsonb;
begin
 select * into p from paperlab.portfolio where singleton for update;
 select * into r from paperlab.learning_runtime where singleton for update;
 select * into m from paperlab.learning_models where id=p_model;
 select * into a from paperlab.model_assessments where model_id=p_model;
 if a.model_id is null or (a.report->>'eligible')::boolean is not true or a.report->>'version'<>'reliability-v1' or not r.enabled or m.status<>'eligible'
  or not public.paper_learning_artifact_allowed(m.artifact) or (m.artifact->>'offline_pass')::boolean is not true or m.artifact->>'fingerprint'<>r.state->>'fingerprint'
  or not paperlab.run_open(p.state) or p.state->>'mode'<>'yahoo' or m.created_at<now()-interval '180 days' or m.reviewed_at<now()-interval '36 hours'
  or a.created_at<now()-interval '7 days' or paperlab.recent_model_failure(p_model) then return false;end if;
 c:=paperlab.model_audit_case(p_model);
 if c->'window' is distinct from a.report->'window' or a.report->>'source_digest' is distinct from encode(sha256(convert_to((c->'records')::text||(c->'meta')::text,'UTF8')),'hex') or (c->'meta'->>'closes')::integer<120 or not exists(select 1 from paperlab.learning_inputs where model_id=p_model)
  or (select max(day) from paperlab.learning_days where model_id=p_model and account='learned')<(now() at time zone 'UTC')::date-4 then return false;end if;
 if (select count(*) from jsonb_object_keys(p.state->'positions'))<>0 or jsonb_array_length(p.state->'pending')<>0 then return false;end if;
 update paperlab.learning_models set status='active',promoted_at=now() where id=p_model;
 update paperlab.learning_runtime set active_model_id=p_model,revision=revision+1,state=jsonb_set(state,'{live_drift}','{"total":0,"shifted":0}') where singleton;
 update paperlab.portfolio set revision=revision+1,lease=null,lease_until=null where singleton;
 insert into paperlab.learning_events(kind,message) values('paper_promoted','Koopfilter na strenge offline toets, zestig nieuwe dagen en eenmalige vaste beoordeling in PAPER gebruikt.');
 return true;
end$$;

create or replace function public.paper_learning_review(p_model text,p_verdict jsonb) returns boolean
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare m paperlab.learning_models;a paperlab.model_assessments;auto boolean;active text;v jsonb;
begin
 perform 1 from paperlab.portfolio where singleton for update;perform 1 from paperlab.learning_runtime where singleton for update;
 select * into m from paperlab.learning_models where id=p_model for update;
 if not found or m.status in('rolled_back','rejected') then return false;end if;
 if octet_length(p_verdict::text)>10000 then raise exception 'Verdict too large';end if;
 select * into a from paperlab.model_assessments where model_id=p_model;
 v:=p_verdict||jsonb_build_object('eligible',coalesce((a.report->>'eligible')::boolean,false),'independent_audit',a.report);
 if a.model_id is null then v:=jsonb_set(v,'{blocked}',coalesce(v->'blocked','[]')||'["Eenmalige onafhankelijke beoordeling na zestig nieuwe dagen ontbreekt."]');end if;
 update paperlab.learning_models set verdict=v,reviewed_at=now(),status=case when status='active' then 'active' when (v->>'eligible')::boolean then 'eligible' else 'shadow' end where id=p_model;
 select auto_paper,active_model_id into auto,active from paperlab.learning_runtime where singleton;
 if active=p_model and (paperlab.recent_model_failure(p_model) or (p_verdict->>'forward_days')::integer>=5 and (p_verdict->>'net_excess_eur')::double precision< -5) then
  update paperlab.learning_runtime set active_model_id=null,revision=revision+1 where singleton;
  update paperlab.learning_models set status='rolled_back' where id=p_model;
  update paperlab.portfolio set revision=revision+1,lease=null,lease_until=null,state=jsonb_set(state,'{pending}',coalesce((select jsonb_agg(x) from jsonb_array_elements(state->'pending')x where x->>'side'<>'koop'),'[]')) where singleton;
  insert into paperlab.learning_events(kind,message) values('performance_rollback','Automatische terugschakeling na recente onderprestatie; geen eigenaaropdracht of echte brokerorder.');
 elsif auto and active is distinct from p_model and (v->>'eligible')::boolean and p_model=(select state->>'candidate_id' from paperlab.learning_runtime where singleton) then perform paperlab.learning_promote(p_model);end if;
 return true;
end$$;

create or replace function paperlab.recent_model_failure(p_model text) returns boolean
language sql stable security definer set search_path=pg_catalog,pg_temp as $$
 with recent as(select a.day,(b.record->>'end_liquidation')::double precision-(b.record->>'start_liquidation')::double precision as mdl,
 (a.record->>'end_liquidation')::double precision-(a.record->>'start_liquidation')::double precision as ref,
 (a.record->>'exposure_sum')::double precision rexp,(b.record->>'exposure_sum')::double precision mexp,
 (b.record->>'stress_cost_eur')::double precision stress,row_number() over(order by a.day desc)rn
 from paperlab.learning_days a join paperlab.learning_days b on a.day=b.day and a.phase=b.phase
 where a.model_id=p_model and b.model_id=p_model and a.account='reference' and b.account='learned'
 and (a.record->>'complete')::boolean and (b.record->>'complete')::boolean and a.day<(now() at time zone 'UTC')::date order by a.day desc limit 10)
 select coalesce(count(*) filter(where rn<=5)>=5 and sum(mdl-ref) filter(where rn<=5)< -5,false)
 or coalesce(count(*)>=10 and avg(mdl-ref*case when rexp>0 then mexp/rexp else 0 end-stress)<=0,false) from recent;
$$;

create or replace function public.paper_opportunity_read(p_owner uuid) returns jsonb
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton) then raise exception 'Not owner';end if;
 return jsonb_build_object('enabled',(select enabled from paperlab.opportunity_runtime),'state',(select state-'active'-'seen' from paperlab.opportunity_runtime),
  'counts',(select jsonb_build_object('records',count(*),'symbols',count(distinct symbol),'days',count(distinct day),'clusters',count(distinct (symbol,day)),'active',count(*) filter(where record->>'status'='watching'),'expired',count(*) filter(where record->>'status'='expired')) from paperlab.opportunity_records),
  'days',(select coalesce(jsonb_agg(record order by day desc),'[]'::jsonb) from paperlab.opportunity_days d where day>=(now() at time zone 'UTC')::date-30 and not exists(select 1 from paperlab.study_epochs e where d.day between e.test_start and e.test_end and e.released_at is null)),
  'benchmark_days',(select coalesce(jsonb_agg(record order by day desc),'[]'::jsonb) from paperlab.opportunity_benchmark_days where day>=(now() at time zone 'UTC')::date-30),
  'coverage',(select coalesce(jsonb_agg(jsonb_build_object('day',day,'expected',expected,'fresh',fresh,'venues',venues) order by day desc),'[]'::jsonb) from paperlab.daily_quality where day>=(now() at time zone 'UTC')::date-7),
  'recent',(select coalesce(jsonb_agg(q order by q.time desc),'[]'::jsonb) from(select id,time,symbol,cohort,record->>'status' as status,record->>'statement' as statement,record->'main_reasons' as main_reasons,
   paperlab.visible_study_record(record)->'outcomes' as outcomes from paperlab.opportunity_records order by time desc,id desc limit 30)q),
  'is_portfolio',false,'used_for_training',false);
end$$;
create or replace function public.paper_opportunity_records(p_owner uuid,p_id text default null) returns jsonb
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton) then raise exception 'Not owner';end if;
 if p_id is not null then return(select paperlab.visible_study_record(record) from paperlab.opportunity_records where id=p_id);end if;
 return(select coalesce(jsonb_agg(paperlab.visible_study_record(record) order by time desc),'[]'::jsonb) from(select time,record from paperlab.opportunity_records order by time desc,id desc limit 500)q);
end$$;

create or replace function public.paper_reliability_read(p_owner uuid) returns jsonb
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton) then raise exception 'Not owner';end if;
 return jsonb_build_object('policy','reliability-v1','requirements',public.paper_learning_requirements(),
 'archive',(select jsonb_build_object('rows',count(*),'days',count(distinct day),'symbols',count(distinct symbol),'first_day',min(day),'last_day',max(day),'bytes',pg_total_relation_size('paperlab.opportunity_archive'),'mean_row_bytes',coalesce(avg(pg_column_size(a)),0),'row_limit',50000,'retention_days',730) from paperlab.opportunity_archive a),
 'datasets',(select jsonb_build_object('frozen_models',count(*) filter(where model_id is not null),'raw_bytes',coalesce(sum(octet_length(dataset::text)),0)) from paperlab.learning_inputs),
 'database_bytes',pg_database_size(current_database()),
 'epochs',(select coalesce(jsonb_agg(q order by q.id desc),'[]'::jsonb) from(select id,profile,development_start,test_start,test_end,released_at,report from paperlab.study_epochs order by id desc limit 10)q),
 'models',(select coalesce(jsonb_agg(q order by q.created_at desc),'[]'::jsonb) from(select model_id,created_at,report from paperlab.model_assessments order by created_at desc limit 5)q),
 'audit',(select jsonb_build_object('status',status,'last_success',last_success) from paperlab.reliability_runtime));
end$$;
create or replace function public.paper_archive_export(p_owner uuid,p_before text default null) returns jsonb
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton) then raise exception 'Not owner';end if;
 return(select coalesce(jsonb_agg(q order by q.id desc),'[]'::jsonb) from(select id,profile,day,time,symbol,venue,cohort,reason,features,observations,entry,
  case when paperlab.study_sealed(profile,day) then null else h30 end as h30,
  case when paperlab.study_sealed(profile,day) then null else h120 end as h120,
  case when paperlab.study_sealed(profile,day) then '{}'::text[] else flags end as flags,main_reasons,
  paperlab.study_sealed(profile,day) as sealed,1 as codec_version,decision_hash from paperlab.opportunity_archive where p_before is null or id<p_before order by id desc limit 500)q);
end$$;

create or replace function public.paper_reliability_maintenance() returns void
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
begin
 perform public.paper_opportunity_archive_sync(null);
 if (select count(*) from paperlab.opportunity_archive)>=49800 then
  delete from paperlab.opportunity_archive where id in(select id from paperlab.opportunity_archive where status<>'watching' and not paperlab.study_sealed(profile,day) order by time,id limit greatest(0,(select count(*)::integer-49000 from paperlab.opportunity_archive)));
 end if;
 delete from paperlab.opportunity_archive where status<>'watching' and not paperlab.study_sealed(profile,day) and
  (time<now()-interval '730 days' or id in(select id from paperlab.opportunity_archive order by time desc,id desc offset 50000));
 delete from paperlab.learning_inputs where model_id is null and created_at<now()-interval '2 days';
 delete from paperlab.learning_inputs where created_at<now()-interval '730 days' and model_id is not null and model_id not in(select active_model_id from paperlab.learning_runtime where active_model_id is not null);
 update paperlab.learning_models set status='expired' where status in('shadow','eligible') and (created_at<now()-interval '180 days' or id in(select model_id from paperlab.model_assessments where created_at<now()-interval '7 days'));
end$$;

create or replace function public.paper_tax_input(p_owner uuid) returns jsonb
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton) then raise exception 'Not owner';end if;
 return(select coalesce(jsonb_agg(q order by q.id),'[]'::jsonb) from(select id,time,symbol,side,qty,price,
  (snapshot->>'fx')::double precision as fx,(snapshot->'tax_detail'->>'capital_gains_reserve_eur')::double precision as capital_gains_reserve_eur from paperlab.trades)q);
end$$;

-- Recoverable backfill from existing recorded facts only. No synthetic outcomes.
select public.paper_opportunity_archive_sync(null);
do $$declare f record;begin
 for f in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'paper\_%' escape '\' loop
  execute format('revoke all on function %s from public,anon,authenticated',f.signature);
  execute format('grant execute on function %s to service_role',f.signature);
 end loop;
end$$;
commit;
