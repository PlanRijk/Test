begin;
create table if not exists paperlab.capital_runtime(
 singleton boolean primary key default true check(singleton),enabled boolean not null default true,policy jsonb,profile text,state jsonb,summary jsonb not null default '{}',
 revision bigint not null default 1,token uuid,lease_until timestamptz,base_revision bigint,last_attempt timestamptz,last_success timestamptz,status text not null default 'waiting',started_at timestamptz,last_error text,allow_entries boolean not null default true,
 check(state is null or octet_length(state::text)<=200000)
);
insert into paperlab.capital_runtime(singleton) values(true) on conflict do nothing;
create table if not exists paperlab.capital_trades(
 id bigint generated always as identity primary key,time timestamptz not null,symbol text not null,side text not null check(side in('koop','verkoop')),qty double precision not null check(qty>0),price double precision not null check(price>0),fee double precision not null check(fee>=0),pnl double precision not null,reason text not null,snapshot jsonb not null check(octet_length(snapshot::text)<=20000),unique(symbol,side,time)
);
create index if not exists capital_trade_rationale on paperlab.capital_trades((snapshot->'purchase_rationale'->>'id'));
create table if not exists paperlab.capital_curve(hour timestamptz primary key,first_value double precision not null,last_value double precision not null,low_value double precision not null,high_value double precision not null,last_at timestamptz not null);
create table if not exists paperlab.capital_usage(month date primary key,estimated_bytes bigint not null default 0 check(estimated_bytes>=0));
do $$declare n text;begin foreach n in array array['capital_runtime','capital_trades','capital_curve','capital_usage']loop
 execute format('alter table paperlab.%I enable row level security',n);execute format('revoke all on paperlab.%I from public,anon,authenticated,service_role',n);end loop;end$$;

create or replace function public.paper_capital_configure(p_policy jsonb,p_state jsonb) returns text
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare r paperlab.capital_runtime;fp text;
begin
 if p_policy->>'version' is distinct from 'capital-10k-v1' or p_policy->>'initial_eur' is distinct from '10000' or p_policy->>'order_eur' is distinct from '500' or p_policy->>'unit_eur' is distinct from '5'
  or p_policy->>'max_positions' is distinct from '12' or p_policy->>'max_per_sector' is distinct from '2' or p_policy->>'max_buys_per_day' is distinct from '12' or p_policy->>'daily_loss_eur' is distinct from '200' or p_policy->>'max_drawdown_eur' is distinct from '500'
  or coalesce(p_policy->>'reference_fingerprint','') !~ '^[a-f0-9]{64}$' or coalesce(p_policy->>'implementation_sha256','') !~ '^[a-f0-9]{64}$' then raise exception 'Invalid capital policy';end if;
 fp:=encode(sha256(convert_to(p_policy::text,'UTF8')),'hex');select * into r from paperlab.capital_runtime where singleton for update;
 if r.profile is not null then if r.profile<>fp then raise exception 'Existing capital policy frozen';end if;return r.profile;end if;
 if p_state->>'cash' is distinct from '2000' or p_state->>'peak' is distinct from '2000' or p_state->'positions' is distinct from '{}'::jsonb or p_state->'pending' is distinct from '[]'::jsonb
  or (p_state->>'fees')::double precision<>0 or (p_state->>'realized')::double precision<>0 or p_state->'risk'->>'global_halted' is distinct from 'false' or p_state->'risk'->>'daily_halted' is distinct from 'false' then raise exception 'New capital account must start empty';end if;
 update paperlab.capital_runtime set policy=p_policy,profile=fp,state=p_state,started_at=now(),summary=jsonb_build_object('cash_eur',10000,'equity_eur',10000,'liquidation_eur',10000,'positions',0,'pending',0,'realized_eur',0,'fees_eur',0,'return_percent',0,'positions_detail','[]'::jsonb,'status','waiting_quotes'),status='waiting_quotes' where singleton;
 return fp;
end$$;

create or replace function public.paper_capital_claim(p_tick_token uuid,p_base_revision bigint) returns jsonb
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare r paperlab.capital_runtime;t uuid;m date;own_bytes bigint;total_bytes bigint;allocated bigint;trades_count integer;payload jsonb;charge bigint;entries boolean;
begin
 select * into r from paperlab.capital_runtime where singleton for update;
 if not r.enabled or r.profile is null or r.lease_until>now() or r.last_attempt>now()-interval '45 seconds' then return null;end if;
 if not exists(select 1 from paperlab.portfolio where singleton and revision=p_base_revision and lease=p_tick_token and lease_until>now() and paperlab.run_open(state)) then return null;end if;
 m:=date_trunc('month',now() at time zone 'UTC')::date;
 insert into paperlab.capital_usage(month) values(m) on conflict do nothing;insert into paperlab.free_usage(month) values(m) on conflict do nothing;
 select estimated_worker_egress_bytes into total_bytes from paperlab.free_usage where month=m for update;
 select estimated_bytes into own_bytes from paperlab.capital_usage where month=m for update;
 delete from paperlab.capital_curve where hour<now()-interval '90 days';delete from paperlab.capital_usage where month<m-interval '18 months';
 select sum(pg_total_relation_size(x::regclass)) into allocated from unnest(array['paperlab.capital_runtime','paperlab.capital_trades','paperlab.capital_curve','paperlab.capital_usage'])x;
 select count(*) into trades_count from paperlab.capital_trades;
 if pg_database_size(current_database())>=150000000 or allocated>=20000000 or own_bytes>=300000000 or total_bytes>=1500000000 or trades_count>=2000 then update paperlab.capital_runtime set status='budget_paused' where singleton;return null;end if;
 entries:=pg_database_size(current_database())<120000000 and allocated<12000000 and own_bytes<240000000 and total_bytes<1200000000 and trades_count<1800;
 payload:=jsonb_build_object('state',r.state,'revision',r.revision,'policy',r.policy,'allow_entries',entries);
 charge:=2*octet_length(payload::text)+2048;
 -- Leave room for a bounded output before admitting work. The commit charges
 -- actual serialized bytes, rather than a large fixed overhead on every tick.
 if own_bytes+charge+800000>=300000000 or total_bytes+charge+800000>=1500000000 then update paperlab.capital_runtime set status='budget_paused' where singleton;return null;end if;
 update paperlab.free_usage set estimated_worker_egress_bytes=estimated_worker_egress_bytes+charge where month=m;
 update paperlab.capital_usage set estimated_bytes=estimated_bytes+charge where month=m;
 t:=gen_random_uuid();update paperlab.capital_runtime set token=t,lease_until=now()+interval '120 seconds',base_revision=p_base_revision,last_attempt=now(),allow_entries=entries,status=case when entries then 'processing' else 'finishing_only' end where singleton;
 return payload||jsonb_build_object('token',t);
end$$;

create or replace function public.paper_capital_commit(p_token uuid,p_output jsonb) returns boolean
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare r paperlab.capital_runtime;s jsonb;receipt_json jsonb;m date;charge bigint;cash_change double precision;fees_change double precision;pnl_change double precision;liquidation_value double precision;
begin
 select * into r from paperlab.capital_runtime where singleton and token=p_token and lease_until>now() for update;if not found then return false;end if;
 perform 1 from paperlab.portfolio where singleton and revision=r.base_revision+1 for share;if not found then return false;end if;
 if p_output->>'protocol' is distinct from 'capital-10k-v1' or (p_output->>'revision')::bigint is distinct from r.revision or octet_length(p_output::text)>400000 or jsonb_typeof(p_output->'trades') is distinct from 'array' or jsonb_array_length(p_output->'trades')>24 then raise exception 'Invalid capital batch';end if;
 s:=p_output->'state';if jsonb_typeof(s->'cash') is distinct from 'number' or jsonb_typeof(s->'fees') is distinct from 'number' or jsonb_typeof(s->'realized') is distinct from 'number' or (s->>'cash')::double precision<0 or (select count(*) from jsonb_object_keys(s->'positions'))>12 or jsonb_array_length(s->'pending')>24 then raise exception 'Invalid capital account';end if;
 if r.state->'risk'->>'global_halted'='true' and s->'risk'->>'global_halted' is distinct from 'true' then raise exception 'Capital risk stop cannot be reset';end if;
 if r.state->'risk'->>'daily_halted'='true' and r.state->'risk'->>'day'=s->'risk'->>'day' and s->'risk'->>'daily_halted' is distinct from 'true' then raise exception 'Capital daily stop cannot be reset';end if;
 if not r.allow_entries and((p_output->>'new_orders')::integer>0 or exists(select 1 from jsonb_array_elements(p_output->'trades')x where x->>'side'='koop')) then raise exception 'Capital entries paused';end if;
 for receipt_json in select value from jsonb_array_elements(p_output->'trades')loop
  if receipt_json->'snapshot'->>'account' is distinct from 'capital10k' or receipt_json->'snapshot'->'learning_context'->>'policy' is distinct from 'capital10k' or (receipt_json->>'time')::timestamptz>now()+interval '5 seconds' or (receipt_json->>'time')::timestamptz<now()-interval '120 seconds' then raise exception 'Invalid capital receipt';end if;
  if receipt_json->>'side'='koop' and(receipt_json->'snapshot'->'purchase_rationale'->>'schema' is distinct from 'purchase-rationale-v1' or receipt_json->'snapshot'->'purchase_rationale'->'decision'->>'statement' is null or jsonb_array_length(receipt_json->'snapshot'->'purchase_rationale'->'decision'->'observations') is distinct from 6
   or (receipt_json->'snapshot'->'purchase_rationale'->'cost_estimate'->>'budget_eur')::double precision is distinct from 500::double precision or receipt_json->'snapshot'->'purchase_rationale'->'execution'->>'quote_time' is null or jsonb_typeof(receipt_json->'snapshot'->'purchase_rationale'->'execution'->'quote_age_seconds') is distinct from 'number' or (receipt_json->'snapshot'->'purchase_rationale'->'execution'->>'quote_age_seconds')::double precision not between 0 and 120 or (receipt_json->'snapshot'->'purchase_rationale'->'execution'->>'cost_eur')::double precision>500.000001) then raise exception 'Capital purchase explanation required';end if;
 end loop;
 select coalesce(sum(case when x->>'side'='koop' then -(x->>'qty')::double precision*(x->>'price')::double precision/(x->'snapshot'->>'fx')::double precision else (x->>'qty')::double precision*(x->>'price')::double precision/(x->'snapshot'->>'fx')::double precision end
  -(x->>'fee')::double precision-coalesce((x->'snapshot'->'tax_detail'->>'transaction_tax_eur')::double precision,0)-coalesce((x->'snapshot'->'tax_detail'->>'capital_gains_reserve_eur')::double precision,0)-coalesce((x->'snapshot'->'tax_detail'->>'foreign_tax_reserve_eur')::double precision,0)-coalesce((x->'snapshot'->'tax_detail'->>'adr_reserve_eur')::double precision,0)),0),
  coalesce(sum((x->>'fee')::double precision),0),coalesce(sum((x->>'pnl')::double precision),0) into cash_change,fees_change,pnl_change from jsonb_array_elements(p_output->'trades')x;
 if abs(5*((s->>'cash')::double precision-(r.state->>'cash')::double precision)-cash_change)>0.000001 or abs(5*((s->>'fees')::double precision-(r.state->>'fees')::double precision)-fees_change)>0.000001 or abs(5*((s->>'realized')::double precision-(r.state->>'realized')::double precision)-pnl_change)>0.000001 then raise exception 'Capital ledger mismatch';end if;
 charge:=2*octet_length(p_output::text);m:=date_trunc('month',now() at time zone 'UTC')::date;
 perform 1 from paperlab.free_usage where month=m for update;perform 1 from paperlab.capital_usage where month=m for update;
 if exists(select 1 from paperlab.free_usage where month=m and estimated_worker_egress_bytes+charge>=1500000000) or exists(select 1 from paperlab.capital_usage where month=m and estimated_bytes+charge>=300000000) then
  update paperlab.capital_runtime set token=null,lease_until=null,status='budget_paused' where singleton;return false;end if;
 insert into paperlab.capital_trades(time,symbol,side,qty,price,fee,pnl,reason,snapshot)
  select (x->>'time')::timestamptz,x->>'symbol',x->>'side',(x->>'qty')::double precision,(x->>'price')::double precision,(x->>'fee')::double precision,(x->>'pnl')::double precision,x->>'reason',x->'snapshot' from jsonb_array_elements(p_output->'trades')x;
 if abs((p_output->'summary'->>'cash_eur')::double precision-5*(s->>'cash')::double precision)>0.000001 or abs((p_output->'summary'->>'realized_eur')::double precision-5*(s->>'realized')::double precision)>0.000001 then raise exception 'Capital summary mismatch';end if;
 liquidation_value:=(p_output->'summary'->>'liquidation_eur')::double precision;
 if liquidation_value is null or liquidation_value<0 or octet_length((p_output->'summary')::text)>20000 then raise exception 'Invalid capital valuation';end if;
 if p_output->'summary'->>'last_market_update' is not null and p_output->'summary'->>'status' in('collecting','finishing_only') then
  insert into paperlab.capital_curve values(date_trunc('hour',now()),liquidation_value,liquidation_value,liquidation_value,liquidation_value,now()) on conflict(hour) do update set last_value=excluded.last_value,low_value=least(paperlab.capital_curve.low_value,excluded.low_value),high_value=greatest(paperlab.capital_curve.high_value,excluded.high_value),last_at=excluded.last_at;
 end if;
 update paperlab.capital_runtime set state=s,summary=p_output->'summary',revision=revision+1,token=null,lease_until=null,last_success=now(),last_error=null,status=p_output->'summary'->>'status' where singleton;
 update paperlab.free_usage set estimated_worker_egress_bytes=estimated_worker_egress_bytes+charge where month=m;update paperlab.capital_usage set estimated_bytes=estimated_bytes+charge where month=m;return true;
end$$;

create or replace function public.paper_capital_fail(p_token uuid) returns void
language sql security definer set search_path=pg_catalog,pg_temp as $$update paperlab.capital_runtime set token=null,lease_until=null,status='error',last_error='Afzonderlijke kapitaalronde niet opgeslagen; rekening en hoofdproef behouden.' where singleton and token=p_token$$;
create or replace function public.paper_capital_read(p_owner uuid) returns jsonb
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton) then raise exception 'Owner required';end if;
 return jsonb_build_object('runtime',(select to_jsonb(r)-'state'-'token'-'lease_until'-'base_revision' from paperlab.capital_runtime r),
 'counts',(select jsonb_build_object('trades',count(*),'buys',count(*) filter(where side='koop'),'closes',count(*) filter(where side='verkoop'),'winning_closes',count(*) filter(where side='verkoop' and pnl>0),'gross_turnover_eur',sum(qty*price/(snapshot->>'fx')::double precision),'commissions_eur',sum(fee),'taxes_reserves_eur',sum(coalesce((snapshot->'tax_detail'->>'transaction_tax_eur')::double precision,0)+coalesce((snapshot->'tax_detail'->>'capital_gains_reserve_eur')::double precision,0)+coalesce((snapshot->'tax_detail'->>'foreign_tax_reserve_eur')::double precision,0)+coalesce((snapshot->'tax_detail'->>'adr_reserve_eur')::double precision,0))) from paperlab.capital_trades),
 'recent',(select coalesce(jsonb_agg(to_jsonb(t) order by t.id desc),'[]') from(select id,time,symbol,side,qty,price,fee,pnl,reason from paperlab.capital_trades order by id desc limit 30)t),
 'curve',(select coalesce(jsonb_agg(to_jsonb(c) order by c.hour),'[]') from(select * from paperlab.capital_curve order by hour desc limit 240)c),
 'usage',(select to_jsonb(u) from paperlab.capital_usage u where month=date_trunc('month',now() at time zone 'UTC')::date),
 'storage_bytes',(select sum(pg_total_relation_size(x::regclass)) from unnest(array['paperlab.capital_runtime','paperlab.capital_trades','paperlab.capital_curve','paperlab.capital_usage'])x));end$$;
create or replace function public.paper_capital_receipt(p_owner uuid,p_id bigint default null) returns jsonb
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton) then raise exception 'Owner required';end if;
 if p_id is not null then return(select to_jsonb(t)||jsonb_build_object('account','capital10k') from paperlab.capital_trades t where id=p_id);end if;
 return(select coalesce(jsonb_agg(to_jsonb(t)||jsonb_build_object('account','capital10k') order by id desc),'[]') from(select * from paperlab.capital_trades order by id desc limit 500)t);end$$;
create or replace function public.paper_capital_action(p_owner uuid,p_action text) returns boolean
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton) then raise exception 'Owner required';end if;
 if p_action not in('pause','resume') then return false;end if;
 update paperlab.capital_runtime set enabled=p_action='resume',token=null,lease_until=null,status=case when p_action='pause' then 'owner_paused' else 'waiting_quotes' end where singleton;return true;end$$;
revoke all on function public.paper_capital_configure(jsonb,jsonb),public.paper_capital_claim(uuid,bigint),public.paper_capital_commit(uuid,jsonb),public.paper_capital_fail(uuid),public.paper_capital_read(uuid),public.paper_capital_receipt(uuid,bigint),public.paper_capital_action(uuid,text) from public,anon,authenticated;
grant execute on function public.paper_capital_configure(jsonb,jsonb),public.paper_capital_claim(uuid,bigint),public.paper_capital_commit(uuid,jsonb),public.paper_capital_fail(uuid),public.paper_capital_read(uuid),public.paper_capital_receipt(uuid,bigint),public.paper_capital_action(uuid,text) to service_role;
commit;
