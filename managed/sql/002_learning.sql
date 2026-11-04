-- Controlled, paper-only learning. Apply after 001; never resets the portfolio.
begin;
create table if not exists paperlab.learning_models (
 id text primary key check(id ~ '^lr-[a-f0-9]{24}$'),created_at timestamptz not null default now(),
 artifact jsonb not null check(octet_length(artifact::text)<=16000),dataset_hash text not null unique,
 status text not null default 'shadow',verdict jsonb not null default '{}',reviewed_at timestamptz,promoted_at timestamptz
);
create table if not exists paperlab.learning_runtime (
 singleton boolean primary key default true check(singleton),enabled boolean not null default true,
 auto_paper boolean not null default true,require_rationale boolean not null default false,revision bigint not null default 1,last_base_revision bigint not null default 0,
 active_model_id text references paperlab.learning_models(id),state jsonb not null default '{}',
 training_status jsonb not null default '{"status":"waiting_data"}',train_lease uuid,train_until timestamptz,last_train_check timestamptz
);
insert into paperlab.learning_runtime(singleton) values(true) on conflict do nothing;
alter table paperlab.learning_runtime add column if not exists require_rationale boolean not null default false;
create table if not exists paperlab.learning_samples (
 id text primary key check(length(id)<=180),schema text not null check(schema='decision-net-v1'),fingerprint text not null,
 features jsonb not null check(jsonb_typeof(features)='array' and jsonb_array_length(features)=7),symbol text not null,venue text not null,
 decision_time timestamptz not null,entry_time timestamptz not null,available_at timestamptz not null,
 net_eur double precision not null check(net_eur between -1000000 and 1000000),check(decision_time<entry_time and entry_time<available_at)
);
create index if not exists learning_samples_available on paperlab.learning_samples(available_at);
create or replace view paperlab.learning_eligible_samples with(security_barrier=true) as
 select * from paperlab.learning_samples where available_at>=now()-interval '180 days' and (decision_time at time zone 'UTC')::date=(available_at at time zone 'UTC')::date;
revoke all on paperlab.learning_eligible_samples from public,anon,authenticated,service_role;
create table if not exists paperlab.learning_trades (
 id bigint generated always as identity primary key,time timestamptz not null,account text not null,phase text not null,trade jsonb not null
);
create index if not exists learning_purchase_link on paperlab.learning_trades(account,phase,((trade->'snapshot'->'purchase_rationale'->>'id'))) where trade->>'side'='koop';
create table if not exists paperlab.learning_days (
 day date not null,account text not null,phase text not null,model_id text,record jsonb not null,
 primary key(day,account,phase)
);
create table if not exists paperlab.learning_events (
 id bigint generated always as identity primary key,time timestamptz not null default now(),kind text not null,message text not null
);
create index if not exists trades_purchase_link on paperlab.trades((snapshot->'purchase_rationale'->>'id')) where side='verkoop';
do $$declare n text;begin
 foreach n in array array['learning_models','learning_runtime','learning_samples','learning_trades','learning_days','learning_events'] loop
  execute format('alter table paperlab.%I enable row level security',n);
  execute format('revoke all on paperlab.%I from public,anon,authenticated,service_role',n);
 end loop;
end$$;

create or replace function public.paper_learning_payload() returns jsonb
language sql security definer set search_path=pg_catalog,pg_temp as $$
 select case when not r.enabled then jsonb_build_object('enabled',false,'revision',r.revision,'active_model_id',null) else
 jsonb_build_object('enabled',r.enabled,'revision',r.revision,'state',r.state,'active_model_id',r.active_model_id,
  'active_artifact',(select artifact from paperlab.learning_models where id=r.active_model_id),
  'candidate_artifact',(select artifact from paperlab.learning_models where artifact->>'fingerprint'=r.state->>'fingerprint' and status in('shadow','eligible','active') order by created_at desc limit 1)) end
 from paperlab.learning_runtime r where singleton;
$$;
create or replace function public.paper_learning_budget_guard() returns boolean
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
begin
 if not exists(select 1 from paperlab.learning_runtime where singleton and enabled) then return false;end if;
 if pg_database_size(current_database())<250000000 and coalesce((select estimated_worker_egress_bytes from paperlab.free_usage where month=date_trunc('month',now() at time zone 'UTC')::date),0)<2400000000 then return false;end if;
 perform 1 from paperlab.portfolio where singleton for update;
 update paperlab.learning_runtime set enabled=false,active_model_id=null,revision=revision+1,
  state=jsonb_set(jsonb_set(state,'{latest_status}','"budget_paused"'),'{message}','"Leerverwerking gepauzeerd om het gratis budget voor de hoofdproef te beschermen."') where singleton;
 update paperlab.portfolio set revision=revision+1,lease=null,lease_until=null,
  state=jsonb_set(state,'{pending}',coalesce((select jsonb_agg(x) from jsonb_array_elements(state->'pending') x where x->>'side'<>'koop'),'[]'::jsonb)) where singleton;
 insert into paperlab.learning_events(kind,message) values('budget_pause','Leerwerk automatisch gepauzeerd vanaf EUR0-budgetmarge: 250MB opslag of 2,4GB werkerraming. Geen betaald plan geactiveerd.');
 return true;
end$$;
create or replace function public.paper_learning_rationale_required() returns boolean
language sql security definer set search_path=pg_catalog,pg_temp as $$select require_rationale from paperlab.learning_runtime where singleton;$$;

create or replace function public.paper_purchase_analysis(p_owner uuid) returns jsonb
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton) then raise exception 'Not owner';end if;
 return(select coalesce(jsonb_agg(q order by q.id desc),'[]'::jsonb) from
  (select b.id,b.time,b.symbol,b.reason,b.snapshot->'purchase_rationale'->'decision'->>'signal_fraction' as signal_fraction,
    b.snapshot->'purchase_rationale'->'decision'->'model'->>'id' as model_id,
    b.snapshot->'purchase_rationale'->>'id' as rationale_id,c.time as closed_at,c.pnl as net_result_eur
   from paperlab.trades b left join lateral(select time,pnl from paperlab.trades s where s.side='verkoop' and s.snapshot->'purchase_rationale'->>'id'=b.snapshot->'purchase_rationale'->>'id' order by s.id limit 1) c on true
   where b.side='koop' order by b.id desc limit 200) q);
end$$;

create or replace function public.paper_learning_trades(p_owner uuid,p_id bigint default null) returns jsonb
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton) then raise exception 'Not owner';end if;
 if p_id is not null then return(select trade||jsonb_build_object('id',id) from paperlab.learning_trades where id=p_id);end if;
 return(select coalesce(jsonb_agg(q order by q.id desc),'[]'::jsonb) from
  (select id,time,account,trade->>'symbol' as symbol,trade->'snapshot'->'purchase_rationale'->'decision'->>'statement' as reason,
   trade->'snapshot'->'purchase_rationale'->>'id' as rationale_id,trade->'outcome'->>'time' as closed_at,
   (trade->'outcome'->>'net_eur')::double precision as net_result_eur from paperlab.learning_trades where trade->>'side'='koop' order by id desc limit 100) q);
end$$;

create or replace function public.paper_learning_export(p_owner uuid) returns jsonb
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton) then raise exception 'Not owner';end if;
 return(select coalesce(jsonb_agg(q order by q.available_at),'[]'::jsonb) from(select * from paperlab.learning_samples order by available_at desc limit 2000) q);
end$$;

create or replace function public.paper_learning_error(p_message text) returns boolean
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
begin
 perform 1 from paperlab.portfolio where singleton for update;
 update paperlab.learning_runtime set state=jsonb_set(jsonb_set(state,'{latest_status}','"error"'),'{message}',to_jsonb(left(p_message,220))),
  active_model_id=null,revision=revision+1 where singleton;
 -- An unsafe learner may not leave queued learned buys behind. Exits are preserved.
 update paperlab.portfolio set state=jsonb_set(state,'{pending}',coalesce((select jsonb_agg(x) from jsonb_array_elements(state->'pending') x where x->>'side'<>'koop'),'[]'::jsonb)),
  revision=revision+1,lease=null,lease_until=null where singleton;
 insert into paperlab.learning_events(kind,message) values('error',left(p_message,220));
 insert into paperlab.events(time,kind,reason) values(now(),'leren',left(p_message,220));
 return true;
end$$;

drop function if exists public.paper_learning_apply(jsonb,bigint);
create or replace function public.paper_learning_apply(p_output jsonb,p_base_revision bigint,p_before jsonb default null) returns boolean
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare r paperlab.learning_runtime;s jsonb;a text;old jsonb;new jsonb;t jsonb;x jsonb;flow double precision;fees double precision;pnl double precision;reset_candidate boolean;
begin
 select * into r from paperlab.learning_runtime where singleton for update;
 if not r.enabled then return false;end if;
 if not found or p_base_revision is null or p_output->>'revision' is null or (p_output->>'revision')::bigint<>r.revision or r.last_base_revision>=p_base_revision+1 or
   (select revision from paperlab.portfolio where singleton)<>p_base_revision+1 then raise exception 'Stale learning revision';end if;
 if octet_length(p_output::text)>400000 or jsonb_array_length(coalesce(p_output->'trades','[]'))>60 or jsonb_array_length(coalesce(p_output->'samples','[]'))>20 then raise exception 'Learning payload too large';end if;
 s:=p_output->'state';if jsonb_typeof(s)<>'object' then raise exception 'Invalid learning state';end if;
 if s->>'latest_status'='error' then perform public.paper_learning_error('Leerstap mislukt; baseline behouden.');return false;end if;
 reset_candidate:=s->>'candidate_id' is distinct from r.state->>'candidate_id';
 if reset_candidate and s->>'candidate_id' is not null and not exists(select 1 from paperlab.learning_models where id=s->>'candidate_id' and artifact->>'fingerprint'=s->>'fingerprint' and status in('shadow','eligible','active')) then raise exception 'Unknown candidate';end if;
 foreach a in array array['reference','low_turnover','learned'] loop
  new:=s->'accounts'->a;if new is null or new='null'::jsonb then continue;end if;
  old:=r.state->'accounts'->a;
  if a='learned' and reset_candidate then
   old:=r.state->'accounts'->'reference';
   if (select count(*) from jsonb_object_keys(coalesce(old->'positions','{}')))<>0 or coalesce(jsonb_array_length(old->'pending'),0)<>0 or
     (select count(*) from jsonb_object_keys(coalesce(r.state->'accounts'->'learned'->'positions','{}')))<>0 or coalesce(jsonb_array_length(r.state->'accounts'->'learned'->'pending'),0)<>0 then raise exception 'Candidate switch requires flat shadow accounts';end if;
  end if;
  if old is null or old='null'::jsonb then old:=coalesce(p_before,(select state from paperlab.portfolio where singleton));end if;
  if new->>'cash' is null or new->>'fees' is null or new->>'realized' is null or jsonb_typeof(new->'positions') is distinct from 'object' or jsonb_typeof(new->'pending') is distinct from 'array' then raise exception 'Invalid shadow state';end if;
  select coalesce(sum((case when e.value->>'side'='koop' then -1 else 1 end)*(e.value->>'qty')::double precision*(e.value->>'price')::double precision/(e.value->'snapshot'->>'fx')::double precision
    -(e.value->>'fee')::double precision-coalesce((e.value->'snapshot'->'tax_detail'->>'transaction_tax_eur')::double precision,0)
    -coalesce((e.value->'snapshot'->'tax_detail'->>'capital_gains_reserve_eur')::double precision,0)-coalesce((e.value->'snapshot'->'tax_detail'->>'foreign_tax_reserve_eur')::double precision,0)
    -coalesce((e.value->'snapshot'->'tax_detail'->>'adr_reserve_eur')::double precision,0)),0),coalesce(sum((e.value->>'fee')::double precision),0),coalesce(sum((e.value->>'pnl')::double precision),0)
    into flow,fees,pnl from jsonb_array_elements(coalesce(p_output->'trades','[]')) as e(value) where e.value->>'account'=a;
  if abs((new->>'cash')::double precision-((old->>'cash')::double precision+flow))>0.000001 or
     abs((new->>'fees')::double precision-((old->>'fees')::double precision+fees))>0.000001 or
     abs((new->>'realized')::double precision-((old->>'realized')::double precision+pnl))>0.000001 or
     not ((new->>'cash')::double precision between 0 and 1000000) then raise exception 'Shadow ledger mismatch';end if;
 end loop;
 for t in select value from jsonb_array_elements(coalesce(p_output->'trades','[]')) loop
  if t->>'account' not in('reference','low_turnover','learned') then raise exception 'Invalid shadow account';end if;
  if t->>'side'='koop' and (t->'snapshot'->'purchase_rationale'->>'schema' is distinct from 'purchase-rationale-v1' or t->'snapshot'->'purchase_rationale'->'execution'->>'quote_time' is null) then raise exception 'Shadow purchase explanation required';end if;
  insert into paperlab.learning_trades(time,account,phase,trade) values((t->>'time')::timestamptz,t->>'account',t->>'phase',t);
  if t->>'side'='verkoop' and t->'snapshot'->'purchase_rationale'->>'id' is not null then
   update paperlab.learning_trades set trade=jsonb_set(trade,'{outcome}',jsonb_build_object('time',t->>'time','net_eur',t->'pnl','exit_price',t->'price'))
    where account=t->>'account' and phase=t->>'phase' and trade->>'side'='koop' and trade->'snapshot'->'purchase_rationale'->>'id'=t->'snapshot'->'purchase_rationale'->>'id';
  end if;
 end loop;
 for x in select value from jsonb_array_elements(coalesce(p_output->'samples','[]')) loop
  if x->>'fingerprint'<>s->>'fingerprint' or (x->>'available_at')::timestamptz>now()+interval '1 minute' or exists(select 1 from jsonb_array_elements(x->'features') f where jsonb_typeof(f)<>'number') then raise exception 'Invalid sample';end if;
  if not exists(select 1 from jsonb_array_elements(coalesce(p_output->'trades','[]')) as tr(value) where tr.value->>'account'='reference' and tr.value->>'side'='verkoop'
    and tr.value->>'symbol'=x->>'symbol' and (tr.value->>'time')::timestamptz=(x->>'available_at')::timestamptz and (tr.value->>'pnl')::double precision=(x->>'net_eur')::double precision
    and tr.value->'snapshot'->'learning_context'->'features'=x->'features') then raise exception 'Label without corresponding closed reference trade';end if;
  if exists(select 1 from paperlab.learning_samples where id=x->>'id' and (features is distinct from x->'features' or net_eur<>(x->>'net_eur')::double precision)) then raise exception 'Conflicting training label';end if;
  insert into paperlab.learning_samples(id,schema,fingerprint,features,symbol,venue,decision_time,entry_time,available_at,net_eur)
   values(x->>'id',x->>'schema',x->>'fingerprint',x->'features',x->>'symbol',x->>'venue',(x->>'decision_time')::timestamptz,(x->>'entry_time')::timestamptz,(x->>'available_at')::timestamptz,(x->>'net_eur')::double precision) on conflict do nothing;
 end loop;
 for x in select value from jsonb_array_elements(coalesce(p_output->'days','[]')) loop
  insert into paperlab.learning_days(day,account,phase,model_id,record) values((x->>'date')::date,x->>'account',x->>'phase',x->>'model_id',x)
   on conflict(day,account,phase) do update set model_id=excluded.model_id,record=excluded.record;
 end loop;
 for x in select value from jsonb_array_elements(coalesce(p_output->'events','[]')) loop
  insert into paperlab.learning_events(kind,message) values(left(x->>'kind',40),left(x->>'message',240));
 end loop;
 update paperlab.learning_runtime set state=s,revision=revision+1,last_base_revision=p_base_revision+1 where singleton;
 if p_output->>'rollback' is not null then
  update paperlab.learning_models set status='rolled_back' where id=r.active_model_id;
  update paperlab.learning_runtime set active_model_id=null where singleton;
  update paperlab.portfolio set state=jsonb_set(state,'{pending}',coalesce((select jsonb_agg(e.value) from jsonb_array_elements(state->'pending') as e(value) where e.value->>'side'<>'koop'),'[]'::jsonb)) where singleton;
  insert into paperlab.learning_events(kind,message) values('automatic_rollback',left(p_output->>'rollback',240));
 end if;
 delete from paperlab.learning_samples where available_at<now()-interval '180 days' or id in(select id from paperlab.learning_samples order by available_at desc offset 2000);
 -- Every purchase explanation and its linked outcome remain available for audit.
 delete from paperlab.learning_trades where trade->>'side'='verkoop' and (time<now()-interval '180 days' or id in(select id from paperlab.learning_trades where trade->>'side'='verkoop' order by id desc offset 5000));
 delete from paperlab.learning_days where day<(now() at time zone 'UTC')::date-120;
 delete from paperlab.learning_events where id in(select id from paperlab.learning_events order by id desc offset 500);
 return true;
end$$;

create or replace function public.paper_learning_read(p_owner uuid) returns jsonb
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare r paperlab.learning_runtime;
begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton) then raise exception 'Not owner';end if;
 select * into r from paperlab.learning_runtime where singleton;
 return jsonb_build_object('enabled',r.enabled,'automatic_paper_promotion',r.auto_paper,'active_model_id',r.active_model_id,
  'state',r.state-'accounts'-'candidate_artifact'-'day_accumulators','training',r.training_status,
  'samples',(select count(*) from paperlab.learning_eligible_samples where fingerprint=r.state->>'fingerprint'),
  'sample_days',(select count(distinct (available_at at time zone 'UTC')::date) from paperlab.learning_eligible_samples where fingerprint=r.state->>'fingerprint'),
  'models',(select coalesce(jsonb_agg(q order by q.created_at desc),'[]'::jsonb) from
    (select id,created_at,status,artifact->'metrics' as metrics,artifact->'windows' as windows,artifact->'offline_blockers' as offline_blockers,artifact->>'training_cutoff' as training_cutoff,verdict,reviewed_at from paperlab.learning_models order by created_at desc limit 5) q),
  'events',(select coalesce(jsonb_agg(q order by q.id desc),'[]'::jsonb) from(select * from paperlab.learning_events order by id desc limit 25) q),
  'requirements',jsonb_build_object('samples',100,'days',20,'forward_days',20,'forward_closes',30),'real_trading',false);
end$$;

create or replace function public.paper_learning_train_input() returns jsonb
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare r paperlab.learning_runtime;t uuid;n integer;d integer;data jsonb;recent integer;charge bigint;m date;
begin
 select * into r from paperlab.learning_runtime where singleton for update;
 if not r.enabled or r.train_until>now() or r.last_train_check>now()-interval '30 minutes' or
    (select (state->>'run_until')::timestamptz<=now() from paperlab.portfolio where singleton) then return null;end if;
 select count(*),count(distinct (available_at at time zone 'UTC')::date) into n,d from paperlab.learning_eligible_samples
  where fingerprint=r.state->>'fingerprint' and available_at<date_trunc('day',now() at time zone 'UTC') at time zone 'UTC';
 select count(*) into recent from paperlab.learning_models where created_at>now()-interval '90 days';
 data:='[]';
 if n>=100 and d>=20 and recent<3 then
  select coalesce(jsonb_agg(q order by q.available_at),'[]'::jsonb) into data from
   (select * from paperlab.learning_eligible_samples where fingerprint=r.state->>'fingerprint' and available_at<date_trunc('day',now() at time zone 'UTC') at time zone 'UTC' order by available_at desc limit 2000) q;
 end if;
 m:=date_trunc('month',now() at time zone 'UTC')::date;charge:=4*(octet_length(data::text)+16384);
 insert into paperlab.free_usage(month) values(m) on conflict do nothing;
 if pg_database_size(current_database())>=300000000 or (select estimated_worker_egress_bytes+charge>max_worker_egress_bytes from paperlab.free_usage where month=m) then return null;end if;
 update paperlab.free_usage set estimated_worker_egress_bytes=estimated_worker_egress_bytes+charge where month=m;
 t:=gen_random_uuid();update paperlab.learning_runtime set train_lease=t,train_until=now()+interval '120 seconds',last_train_check=now() where singleton;
 return jsonb_build_object('token',t,'fingerprint',r.state->>'fingerprint','samples',data,'sample_count',n,'days',d,'model_limit_reached',recent>=3,
  'previous_cutoff',(select max(artifact->>'training_cutoff') from paperlab.learning_models where artifact->>'fingerprint'=r.state->>'fingerprint'),
  'models',(select coalesce(jsonb_agg(jsonb_build_object('artifact',artifact,'status',status)),'[]'::jsonb) from paperlab.learning_models where status in('shadow','eligible','active')),
  'days_data',(select coalesce(jsonb_agg(record),'[]'::jsonb) from paperlab.learning_days where day<(now() at time zone 'UTC')::date),
  'closes',(select coalesce(jsonb_object_agg(q.phase,q.closed_count),'{}'::jsonb) from(select phase,count(*) as closed_count from paperlab.learning_trades where account='learned' and trade->>'side'='verkoop' group by phase) q));
end$$;

create or replace function public.paper_learning_store(p_token uuid,p_result jsonb) returns boolean
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare r paperlab.learning_runtime;a jsonb;
begin
 select * into r from paperlab.learning_runtime where singleton for update;
 if p_token is null or r.train_lease is distinct from p_token or r.train_until<=now() then return false;end if;
 a:=p_result->'artifact';
 if a is not null and a<>'null'::jsonb then
  if (select count(*)<100 or count(distinct (available_at at time zone 'UTC')::date)<20 from paperlab.learning_eligible_samples where fingerprint=r.state->>'fingerprint' and available_at<date_trunc('day',now() at time zone 'UTC') at time zone 'UTC') then raise exception 'Insufficient reference data';end if;
  if a->>'algorithm'<>'net-logit-v1' or a->>'feature_schema'<>'decision-net-v1' or a->>'fingerprint'<>r.state->>'fingerprint' or octet_length(a::text)>16000
   or jsonb_array_length(a->'weights')<>7 or jsonb_array_length(a->'mean')<>7 or jsonb_array_length(a->'scale')<>7 or (a->>'threshold')::numeric<>.6 then raise exception 'Invalid model';end if;
  if (select count(*) from paperlab.learning_models where created_at>now()-interval '90 days')>=3 then raise exception 'Training trial budget exceeded';end if;
  insert into paperlab.learning_models(id,artifact,dataset_hash) values(a->>'id',a,a->>'dataset_hash') on conflict(dataset_hash) do nothing;
  insert into paperlab.learning_events(kind,message) values('trained','Nieuw beperkt model getraind; alleen schaduwgebruik, afzonderlijke toetsing blijft vereist.');
 end if;
 update paperlab.learning_runtime set training_status=p_result-'artifact',train_lease=null,train_until=null where singleton;
 return true;
end$$;

create or replace function paperlab.learning_promote(p_model text) returns boolean
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare r paperlab.learning_runtime;m paperlab.learning_models;p paperlab.portfolio;count_days integer;count_closes integer;last_day date;bad_risk boolean;
begin
 select * into p from paperlab.portfolio where singleton for update;
 select * into r from paperlab.learning_runtime where singleton for update;
 select * into m from paperlab.learning_models where id=p_model;
 if not found or not r.enabled or m.status<>'eligible' or (m.artifact->>'offline_pass')::boolean is not true or (m.verdict->>'eligible')::boolean is not true
  or m.reviewed_at<now()-interval '36 hours' or m.artifact->>'fingerprint'<>r.state->>'fingerprint'
  or (p.state->>'run_until')::timestamptz<=now() or p.state->>'mode'<>'yahoo' then return false;end if;
 if (select count(*) from jsonb_object_keys(p.state->'positions'))<>0 or jsonb_array_length(p.state->'pending')<>0 then return false;end if;
 select count(*),max(a.day),coalesce(bool_or((b.record->>'max_drawdown_eur')::double precision>(a.record->>'max_drawdown_eur')::double precision+5),false) into count_days,last_day,bad_risk from paperlab.learning_days a join paperlab.learning_days b on a.day=b.day and a.phase=b.phase
  where a.account='reference' and b.account='learned' and a.model_id=p_model and b.model_id=p_model and a.day<(now() at time zone 'UTC')::date
  and a.day>greatest((m.artifact->>'training_cutoff')::date,(m.created_at at time zone 'UTC')::date) and extract(isodow from a.day) between 1 and 5
  and (a.record->>'complete')::boolean and (b.record->>'complete')::boolean
  and coalesce((a.record->>'unique_rounds')::integer,0)>=160 and coalesce((b.record->>'unique_rounds')::integer,0)>=160;
 select count(*) into count_closes from paperlab.learning_trades where account='learned' and phase=p_model and trade->>'side'='verkoop';
 if count_days<20 or count_closes<30 or bad_risk or last_day<(now() at time zone 'UTC')::date-4 or m.created_at<now()-interval '60 days'
  or last_day is distinct from (m.verdict->>'last_date')::date or coalesce((m.verdict->>'lower99_mean_eur')::double precision,0)<=0 or coalesce((m.verdict->>'net_excess_eur')::double precision,0)<=0 then return false;end if;
 update paperlab.learning_models set status='shadow' where id=r.active_model_id and id<>p_model;
 update paperlab.learning_models set status='active',promoted_at=now() where id=p_model;
 update paperlab.learning_runtime set active_model_id=p_model,revision=revision+1,state=jsonb_set(state,'{live_drift}','{"total":0,"shifted":0}') where singleton;
 update paperlab.portfolio set revision=revision+1,lease=null,lease_until=null where singleton;
 insert into paperlab.learning_events(kind,message) values('paper_promoted','Modelkoopfilter na offline en voorwaartse toetsen in de hoofd-PAPERproef geactiveerd; risicoregels behouden.');
 return true;
end$$;

create or replace function public.paper_learning_review(p_model text,p_verdict jsonb) returns boolean
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare m paperlab.learning_models;auto boolean;active text;
begin
 perform 1 from paperlab.portfolio where singleton for update;
 perform 1 from paperlab.learning_runtime where singleton for update;
 select * into m from paperlab.learning_models where id=p_model for update;
 if not found or m.status='rolled_back' then return false;end if;
 if octet_length(p_verdict::text)>10000 then raise exception 'Verdict too large';end if;
 update paperlab.learning_models set verdict=p_verdict,reviewed_at=now(),status=case when status='active' then 'active' when (p_verdict->>'eligible')::boolean then 'eligible' else 'shadow' end where id=p_model;
 select auto_paper,active_model_id into auto,active from paperlab.learning_runtime where singleton;
 if active=p_model and (p_verdict->>'forward_days')::integer>=5 and (p_verdict->>'net_excess_eur')::double precision< -5 then
  update paperlab.learning_runtime set active_model_id=null,revision=revision+1 where singleton;
  update paperlab.learning_models set status='rolled_back' where id=p_model;
  update paperlab.portfolio set revision=revision+1,lease=null,lease_until=null,
   state=jsonb_set(state,'{pending}',coalesce((select jsonb_agg(x) from jsonb_array_elements(state->'pending') x where x->>'side'<>'koop'),'[]'::jsonb)) where singleton;
  insert into paperlab.learning_events(kind,message) values('performance_rollback','Gepaarde schaduwprestatie verslechterd; modelkoopfilter automatisch teruggezet naar baseline.');
 elsif auto and active is distinct from p_model and (p_verdict->>'eligible')::boolean and p_model=(select state->>'candidate_id' from paperlab.learning_runtime where singleton) then perform paperlab.learning_promote(p_model);
 end if;
 return true;
end$$;

create or replace function public.paper_learning_action(p_owner uuid,p_action text,p_model text default null) returns boolean
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare active text;
begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton) then raise exception 'Not owner';end if;
 perform 1 from paperlab.portfolio where singleton for update;
 perform 1 from paperlab.learning_runtime where singleton for update;
 if p_action='promote' then return paperlab.learning_promote(p_model);end if;
 if p_action not in('rollback','pause','resume','restart','auto-on','auto-off') then raise exception 'Unsupported learning action';end if;
 if p_action='restart' then
  if (select count(*) from paperlab.portfolio,jsonb_object_keys(state->'positions'))<>0 or (select jsonb_array_length(state->'pending') from paperlab.portfolio where singleton)<>0 then return false;end if;
  if exists(select 1 from paperlab.learning_runtime,jsonb_each(state->'accounts') a where (select count(*) from jsonb_object_keys(coalesce(a.value->'positions','{}')))>0 or coalesce(jsonb_array_length(a.value->'pending'),0)>0) then return false;end if;
  update paperlab.learning_runtime set state='{}',active_model_id=null,enabled=true,revision=revision+1 where singleton;
  update paperlab.learning_models set status='rolled_back' where status in('shadow','eligible','active');
  update paperlab.portfolio set revision=revision+1,lease=null,lease_until=null where singleton;
  insert into paperlab.learning_events(kind,message) values('new_epoch','Nieuwe leercyclus bij lege portefeuilles; oude gegevens, modellen en resultaten behouden.');return true;
 end if;
 if p_action in('rollback','pause') then
  select active_model_id into active from paperlab.learning_runtime where singleton;
  update paperlab.learning_runtime set active_model_id=null,enabled=case when p_action='pause' then false else enabled end,revision=revision+1 where singleton;
  if active is not null then update paperlab.learning_models set status='rolled_back' where id=active;end if;
  update paperlab.portfolio set revision=revision+1,lease=null,lease_until=null,
   state=jsonb_set(state,'{pending}',coalesce((select jsonb_agg(x) from jsonb_array_elements(state->'pending') x where x->>'side'<>'koop'),'[]'::jsonb)) where singleton;
 elsif p_action='resume' then update paperlab.learning_runtime set enabled=true,revision=revision+1 where singleton;
 else update paperlab.learning_runtime set auto_paper=p_action='auto-on' where singleton;end if;
 insert into paperlab.learning_events(kind,message) values('owner_action','Eigenaar wijzigt leerbediening: '||p_action||'. Geen echte brokerorders.');
 return true;
end$$;

do $$declare f record;begin
 for f in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'paper_learning_%' loop
  execute format('revoke all on function %s from public,anon,authenticated',f.signature);
  execute format('grant execute on function %s to service_role',f.signature);
 end loop;
end$$;
revoke all on function public.paper_purchase_analysis(uuid) from public,anon,authenticated;
grant execute on function public.paper_purchase_analysis(uuid) to service_role;
commit;
