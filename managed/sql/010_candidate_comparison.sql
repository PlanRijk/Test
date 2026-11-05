begin;
create table if not exists paperlab.candidate_runtime(
 singleton boolean primary key default true check(singleton),enabled boolean not null default true,policy jsonb,profile text,reference_id text references paperlab.history_models(id),reference_hash text,training_hash text,training_boundary date,
 token uuid,lease_until timestamptz,last_claim timestamptz,last_success timestamptz,status text not null default 'waiting',admission integer not null default 0,report jsonb not null default '{}',final_report jsonb
);
insert into paperlab.candidate_runtime(singleton) values(true) on conflict do nothing;
create table if not exists paperlab.candidate_models(
 slot smallint primary key check(slot in(0,1)),id text not null unique check(id~'^cm-[a-f0-9]{24}$'),artifact jsonb not null check(octet_length(artifact::text)<=16000)
);
create table if not exists paperlab.candidate_predictions(
 symbol text not null,day date not null,source text not null check(source in('core','extra')),recorded_at timestamptz not null default now(),feature_hash text not null check(feature_hash~'^[a-f0-9]{64}$'),
 probabilities double precision[] not null check(cardinality(probabilities)=2 and probabilities[1] between 0 and 1 and probabilities[2] between 0 and 1),reference_probability double precision not null check(reference_probability between 0 and 1),sector text not null,venue text not null,primary_sample boolean not null,
 status smallint not null default 0 check(status in(0,2,3)),net double precision,stress double precision,available_at timestamptz,reason text,primary key(symbol,day),
 check(status<>2 or(net is not null and stress is not null and available_at>recorded_at and stress<=net))
);
create index if not exists candidate_predictions_pending on paperlab.candidate_predictions(status) where status=0;
do $$declare n text;begin foreach n in array array['candidate_runtime','candidate_models','candidate_predictions']loop
 execute format('alter table paperlab.%I enable row level security',n);execute format('revoke all on paperlab.%I from public,anon,authenticated,service_role',n);end loop;end$$;
-- Only already recorded inputs and shared twenty-session outcomes. Never new prices.
create or replace view paperlab.candidate_sources with(security_barrier=true) as
 select h.model_id,'core'::text as source,h.symbol,h.day,h.record->>'known_day' as known_day,h.record->>'sector' as sector,h.record->>'venue' as venue,
  (h.record->>'decision_at')::timestamptz as decision_at,array(select jsonb_array_elements_text(h.record->'features')::double precision) as features,
  (h.record->>'probability')::double precision as reference_probability,case h.status when 'pending' then 0 when 'following' then 1 when 'complete' then 2 else 3 end as status,
  (h.record->'entry'->>'open_time')::timestamptz as entry_at,(h.record->'outcome'->>'known_at')::timestamptz as available_at,
  (h.record->'outcome'->>'net_eur')::double precision as net,(h.record->'outcome'->>'stressed_net_eur')::double precision as stress,h.record->>'reason' as reason
 from paperlab.history_forecasts h
 union all select b.model_id,'extra',b.symbol,b.day,b.known_day::text,b.sector,b.venue,b.decision_at,b.features,b.probability,b.status,
  to_timestamp(b.entry[1]/1000),to_timestamp(b.outcome[3]/1000),b.outcome[7],b.outcome[8],b.reason from paperlab.breadth_scores b;
revoke all on paperlab.candidate_sources from public,anon,authenticated,service_role;

create or replace function public.paper_candidates_configure(p_policy jsonb) returns text
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare m paperlab.history_models;r paperlab.candidate_runtime;fp text;
begin
 select * into m from paperlab.history_models order by created_at limit 1;if not found then raise exception 'Frozen reference required';end if;
 if p_policy->>'version' is distinct from 'candidate-comparison-v1' or p_policy->'variants' is distinct from '[{"id":"shrinkage","name":"Sterkere regularisatie","l2":0.1,"mask":[0,1,2,3,4,5,6,7]},{"id":"context","name":"Marktcontext en volatiliteit","l2":0.01,"mask":[3,5,6,7]}]'::jsonb
  or p_policy->>'primary_days' is distinct from '60' or p_policy->>'max_records' is distinct from '25000' or p_policy->>'automatic_trading_approval' is distinct from 'false' or coalesce(p_policy->>'implementation_sha256','') !~ '^[a-f0-9]{64}$' then raise exception 'Invalid candidate policy';end if;
 fp:=encode(sha256(convert_to(jsonb_build_object('policy',p_policy,'reference',m.id,'hash',m.artifact->>'integrity_hash')::text,'UTF8')),'hex');
 select * into r from paperlab.candidate_runtime where singleton for update;if r.profile is not null and r.profile<>fp then raise exception 'Candidate policy frozen';end if;
 update paperlab.candidate_runtime set policy=p_policy,profile=fp,reference_id=m.id,reference_hash=m.artifact->>'integrity_hash',training_boundary=(m.artifact->'windows'->>'validation_start')::date where singleton;return fp;
end$$;

create or replace function public.paper_candidates_claim() returns jsonb
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare r paperlab.candidate_runtime;m paperlab.history_models;payload jsonb;training jsonb;usage_bytes bigint;charge bigint;t uuid;d date;new_limit integer;rows_count integer;active_count integer;primary_days integer;
begin
 select * into r from paperlab.candidate_runtime where singleton for update;d:=(now() at time zone 'UTC')::date;
 if not r.enabled or r.profile is null or r.lease_until>now() or r.last_claim>now()-interval '30 minutes' then return null;end if;
 if not exists(select 1 from paperlab.portfolio where singleton and paperlab.run_open(state)) then return null;end if;
 select * into m from paperlab.history_models where id=r.reference_id and artifact->>'integrity_hash'=r.reference_hash;
 if not found then update paperlab.candidate_runtime set status='reference_changed' where singleton;return null;end if;
 insert into paperlab.free_usage(month) values(date_trunc('month',now() at time zone 'UTC')::date) on conflict do nothing;
 select estimated_worker_egress_bytes into usage_bytes from paperlab.free_usage where month=date_trunc('month',now() at time zone 'UTC')::date for update;
 if pg_database_size(current_database())>=120000000 or usage_bytes>=1200000000 or (select sum(pg_total_relation_size(x::regclass)) from unnest(array['paperlab.candidate_runtime','paperlab.candidate_models','paperlab.candidate_predictions'])x)>=24000000 then
  update paperlab.candidate_runtime set status='budget_paused' where singleton;return null;end if;
 if not exists(select 1 from paperlab.candidate_models) then
  -- The original validation and test rows never leave the database for training.
  select jsonb_agg(e.value order by (e.value->>3)::double precision,e.value->>0) into training from jsonb_array_elements(m.dataset)e
   where (e.value->>3)::double precision<extract(epoch from r.training_boundary::timestamp at time zone 'UTC')*1000 and (e.value->>5)::double precision<extract(epoch from r.training_boundary::timestamp at time zone 'UTC')*1000;
  update paperlab.candidate_runtime set training_hash=encode(sha256(convert_to(training::text,'UTF8')),'hex') where singleton returning * into r;
  payload:=jsonb_build_object('stage','train','training',training,'training_boundary',r.training_boundary,'training_hash',r.training_hash,'reference_id',r.reference_id,'reference_hash',r.reference_hash);
 else
  -- Outcomes are copied only after the shared future entry and outcome were observed.
  update paperlab.candidate_predictions p set status=case when s.status=2 and encode(sha256(convert_to(to_jsonb(s.features)::text,'UTF8')),'hex')=p.feature_hash and s.reference_probability=p.reference_probability and s.entry_at>p.recorded_at and s.available_at>p.recorded_at and s.net is not null and s.stress<=s.net then 2 else 3 end,
   net=case when s.status=2 and encode(sha256(convert_to(to_jsonb(s.features)::text,'UTF8')),'hex')=p.feature_hash and s.reference_probability=p.reference_probability and s.entry_at>p.recorded_at and s.available_at>p.recorded_at and s.stress<=s.net then s.net end,
   stress=case when s.status=2 and encode(sha256(convert_to(to_jsonb(s.features)::text,'UTF8')),'hex')=p.feature_hash and s.reference_probability=p.reference_probability and s.entry_at>p.recorded_at and s.available_at>p.recorded_at and s.stress<=s.net then s.stress end,available_at=s.available_at,
   reason=case when s.status=3 then coalesce(s.reason,'Gedeelde bronuitkomst ontbreekt.') when s.entry_at<=p.recorded_at then 'Instap was niet toekomstig bij kandidaatvoorspelling.' else null end
   from paperlab.candidate_sources s where p.status=0 and s.model_id=r.reference_id and s.source=p.source and s.symbol=p.symbol and s.day=p.day and s.status in(2,3) and (s.available_at is null or s.available_at<=now());
  update paperlab.candidate_predictions set status=3,reason='Meettermijn verlopen zonder gedeelde uitkomst.' where status=0 and recorded_at<now()-interval '55 days';
  delete from paperlab.candidate_predictions where status in(2,3) and day<d-90 and(not primary_sample or r.final_report is not null);
  select count(*),count(*) filter(where status=0),count(distinct day) filter(where primary_sample) into rows_count,active_count,primary_days from paperlab.candidate_predictions;
  new_limit:=greatest(0,least(150,25000-rows_count,4000-active_count));
  if extract(hour from now() at time zone 'UTC')>=7 or extract(isodow from d)>=6 then new_limit:=0;end if;
  if not exists(select 1 from paperlab.breadth_runtime where last_day=d) or not exists(select 1 from paperlab.history_runtime where last_forward=d) then new_limit:=0;end if;
  payload:=jsonb_build_object('stage','observe','models',(select jsonb_agg(artifact order by slot) from paperlab.candidate_models),
   'cases',(select coalesce(jsonb_agg(jsonb_build_object('symbol',symbol,'day',day,'sector',sector,'primary',primary_sample,'status',status,'probabilities',probabilities,'reference_probability',reference_probability,'net',net,'stress',stress)),'[]') from paperlab.candidate_predictions where primary_sample and r.final_report is null),
   'sources',(select coalesce(jsonb_agg(to_jsonb(s)),'[]') from(select s.source,s.symbol,s.day,s.known_day,s.decision_at,s.status,s.features,encode(sha256(convert_to(to_jsonb(s.features)::text,'UTF8')),'hex') as feature_hash from paperlab.candidate_sources s
    where s.model_id=r.reference_id and s.day=d and s.status=0 and s.decision_at<=now() and not exists(select 1 from paperlab.candidate_predictions p where p.symbol=s.symbol and p.day=s.day) order by s.symbol limit new_limit)s),
   'max_new',new_limit);
 end if;
 charge:=4*octet_length(payload::text)+131072;if usage_bytes+charge>=1200000000 then update paperlab.candidate_runtime set status='budget_paused' where singleton;return null;end if;
 update paperlab.free_usage set estimated_worker_egress_bytes=estimated_worker_egress_bytes+charge where month=date_trunc('month',now() at time zone 'UTC')::date;
 t:=gen_random_uuid();update paperlab.candidate_runtime set token=t,lease_until=now()+interval '150 seconds',last_claim=now(),status='processing',admission=coalesce(new_limit,0) where singleton;
 return payload||jsonb_build_object('token',t,'policy',r.policy);
end$$;

create or replace function public.paper_candidates_commit(p_token uuid,p_output jsonb) returns boolean
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare r paperlab.candidate_runtime;x jsonb;slot_no integer;primary_days integer;is_primary boolean;d date;probs double precision[];s record;
begin
 select * into r from paperlab.candidate_runtime where singleton and token=p_token and lease_until>now() for update;if not found then return false;end if;
 if octet_length(p_output::text)>100000 then raise exception 'Candidate batch too large';end if;d:=(now() at time zone 'UTC')::date;
 if p_output ? 'models' then
  if exists(select 1 from paperlab.candidate_models) or jsonb_array_length(p_output->'models')<>2 then raise exception 'Candidate models frozen';end if;
  slot_no:=0;for x in select value from jsonb_array_elements(p_output->'models') loop
   if x->>'source_model' is distinct from r.reference_id or x->>'source_hash' is distinct from r.reference_hash or x->>'training_hash' is distinct from r.training_hash or x->>'training_boundary' is distinct from r.training_boundary::text
    or x->>'variant' is distinct from r.policy->'variants'->slot_no->>'id' or x->'mask' is distinct from r.policy->'variants'->slot_no->'mask' or x->'l2' is distinct from r.policy->'variants'->slot_no->'l2'
    or x->>'automatic_trading_approval' is distinct from 'false' or x->>'protocol' is distinct from 'candidate-comparison-v1' or x->>'threshold' is distinct from '0.6'
    or jsonb_array_length(x->'weights')<>8 or jsonb_array_length(x->'scale')<>8 or jsonb_array_length(x->'mean')<>8 or x->>'integrity_hash' !~ '^[a-f0-9]{64}$' then raise exception 'Invalid candidate artifact';end if;
   insert into paperlab.candidate_models values(slot_no,x->>'id',x);slot_no:=slot_no+1;
  end loop;
  if p_output ? 'report' then
   if octet_length((p_output->'report')::text)>32000 or p_output->'report'->>'automatic_trading_approval' is distinct from 'false' then raise exception 'Invalid initial candidate report';end if;
   update paperlab.candidate_runtime set report=p_output->'report' where singleton;
  end if;
 else
  if p_output->>'protocol' is distinct from 'candidate-comparison-v1' or jsonb_typeof(p_output->'records') is distinct from 'array' or jsonb_array_length(p_output->'records')>r.admission or p_output->'report'->>'automatic_trading_approval' is distinct from 'false' then raise exception 'Invalid candidate batch';end if;
  select count(distinct day) into primary_days from paperlab.candidate_predictions where primary_sample;
  is_primary:=r.final_report is null and(primary_days<60 or exists(select 1 from paperlab.candidate_predictions where primary_sample and day=d));
  for x in select value from jsonb_array_elements(p_output->'records')loop
   if (x->>'day')::date<>d or extract(hour from now() at time zone 'UTC')>=7 or extract(isodow from d)>=6 or exists(select 1 from paperlab.candidate_models where (artifact->>'created_at')::timestamptz>=d::timestamp at time zone 'UTC') then raise exception 'Retrospective candidate prediction';end if;
   select * into s from paperlab.candidate_sources where model_id=r.reference_id and symbol=x->>'symbol' and day=d and source=x->>'source' and status=0 and decision_at<=now();
   if not found or s.known_day::date>=d or encode(sha256(convert_to(to_jsonb(s.features)::text,'UTF8')),'hex') is distinct from x->>'feature_hash' then raise exception 'Unbacked candidate input';end if;
   probs:=array(select jsonb_array_elements_text(x->'probabilities')::double precision);
   insert into paperlab.candidate_predictions(symbol,day,source,feature_hash,probabilities,reference_probability,sector,venue,primary_sample) values(s.symbol,d,s.source,x->>'feature_hash',probs,s.reference_probability,s.sector,s.venue,is_primary);
  end loop;
  if octet_length((p_output->'report')::text)>32000 then raise exception 'Candidate report too large';end if;
  if p_output->'report'->>'status'='final' and((select count(distinct day) from paperlab.candidate_predictions where primary_sample)<>60 or exists(select 1 from paperlab.candidate_predictions where primary_sample and status=0)) then raise exception 'Premature candidate verdict';end if;
  update paperlab.candidate_runtime set report=p_output->'report',final_report=case when final_report is null and p_output->'report'->>'status'='final' then p_output->'report' else final_report end where singleton;
 end if;
 update paperlab.candidate_runtime set token=null,lease_until=null,last_success=now(),status='observing' where singleton;return true;
end$$;
create or replace function public.paper_candidates_fail(p_token uuid) returns void
language sql security definer set search_path=pg_catalog,pg_temp as $$update paperlab.candidate_runtime set token=null,lease_until=null,status='error' where singleton and token=p_token$$;
create or replace function public.paper_candidates_read(p_owner uuid) returns jsonb
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton) then raise exception 'Owner required';end if;
 return jsonb_build_object('runtime',(select to_jsonb(r)-'token'-'lease_until' from paperlab.candidate_runtime r),'models',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'artifact',artifact) order by slot),'[]') from paperlab.candidate_models),
 'counts',(select jsonb_build_object('predictions',count(*),'pending',count(*) filter(where status=0),'complete',count(*) filter(where status=2),'missing',count(*) filter(where status=3),'days',count(distinct day)) from paperlab.candidate_predictions),
 'storage_bytes',(select sum(pg_total_relation_size(x::regclass)) from unnest(array['paperlab.candidate_runtime','paperlab.candidate_models','paperlab.candidate_predictions'])x));end$$;
create or replace function public.paper_candidates_action(p_owner uuid,p_action text) returns boolean
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton) then raise exception 'Owner required';end if;
 if p_action not in('pause','resume') then return false;end if;update paperlab.candidate_runtime set enabled=p_action='resume',token=null,lease_until=null,status=case when p_action='pause' then 'owner_paused' else 'waiting' end where singleton;return true;end$$;
revoke all on function public.paper_candidates_configure(jsonb),public.paper_candidates_claim(),public.paper_candidates_commit(uuid,jsonb),public.paper_candidates_fail(uuid),public.paper_candidates_read(uuid),public.paper_candidates_action(uuid,text) from public,anon,authenticated;
grant execute on function public.paper_candidates_configure(jsonb),public.paper_candidates_claim(),public.paper_candidates_commit(uuid,jsonb),public.paper_candidates_fail(uuid),public.paper_candidates_read(uuid),public.paper_candidates_action(uuid,text) to service_role;
commit;
