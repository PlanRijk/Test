begin;
alter table paperlab.capital_runtime add column if not exists execution_policy jsonb;
alter table paperlab.capital_runtime add column if not exists execution_profile text;
alter table paperlab.capital_runtime add column if not exists execution_revision bigint not null default 0;
alter table paperlab.capital_runtime add column if not exists execution_started_at timestamptz;
alter table paperlab.capital_runtime add column if not exists execution_baseline jsonb;
create table if not exists paperlab.capital_policy_epochs(profile text primary key,started_at timestamptz not null,policy jsonb not null,baseline jsonb not null,carry_positions jsonb not null,cancelled_orders jsonb not null,last_legacy_trade_id bigint not null,state_hash text not null);
alter table paperlab.capital_policy_epochs enable row level security;
revoke all on paperlab.capital_policy_epochs from public,anon,authenticated,service_role;
-- Preserve the original financial conservation/risk checks behind private adapters.
do $$begin
 if to_regprocedure('public.paper_capital_claim_base_v1(uuid,bigint)') is null then alter function public.paper_capital_claim(uuid,bigint) rename to paper_capital_claim_base_v1;end if;
 if to_regprocedure('public.paper_capital_commit_base_v1(uuid,jsonb)') is null then alter function public.paper_capital_commit(uuid,jsonb) rename to paper_capital_commit_base_v1;end if;
end$$;
revoke all on function public.paper_capital_claim_base_v1(uuid,bigint),public.paper_capital_commit_base_v1(uuid,jsonb) from public,anon,authenticated,service_role;
create or replace function public.paper_capital_set_horizon(p_policy jsonb) returns text
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare r paperlab.capital_runtime;fp text;baseline jsonb;cancelled jsonb;positions jsonb;old_id bigint;
begin
 select * into r from paperlab.capital_runtime where singleton for update;
 if not(p_policy @> '{"version":"capital-multiday-v2","account":"capital10k","close_at_session_end":false,"holding_horizon":"multiple_sessions","force_exit_at_review":false,"carry_protective_sells":true,"stop_fraction":0.015,"base_profit_fraction":0.025,"order_eur":500,"minimum_cash_eur":1000,"max_positions":12,"max_per_sector":2,"max_buys_per_day":12,"max_exposure_fraction":0.8,"daily_loss_eur":200,"max_drawdown_eur":500,"maximum_quote_age_seconds":120,"review_horizon_sessions":20,"additional_market_downloads":0}'::jsonb)
 or coalesce(p_policy->>'implementation_sha256','') !~ '^[a-f0-9]{64}$' or p_policy->>'base_implementation_sha256' is distinct from r.policy->>'implementation_sha256' then raise exception 'Invalid multiday policy';end if;
 fp:=encode(sha256(convert_to(p_policy::text,'UTF8')),'hex');
 if r.execution_profile is not null then if r.execution_profile<>fp then raise exception 'Existing multiday policy frozen';end if;return fp;end if;
 if r.enabled then raise exception 'Pause capital before horizon migration';end if;
 select coalesce(jsonb_agg(o),'[]') into cancelled from jsonb_array_elements(r.state->'pending')o where o->>'side'='koop' or(o->>'side'='verkoop' and o->>'reason'='Dagsluiting van de eigen beurs.');
 positions:=r.state->'positions';select coalesce(max(id),0) into old_id from paperlab.capital_trades;
 baseline:=r.summary||jsonb_build_object('carried_positions',(select count(*) from jsonb_object_keys(positions)),'last_legacy_trade_id',old_id,'valuation_at',r.summary->>'checked_at','note','Fase begint met bestaande posities en verliezen; geen herstart of schone onafhankelijke vergelijking.');
 insert into paperlab.capital_policy_epochs values(fp,now(),p_policy,baseline,positions,cancelled,old_id,encode(sha256(convert_to(r.state::text,'UTF8')),'hex'));
 update paperlab.capital_runtime set execution_policy=p_policy,execution_profile=fp,execution_revision=execution_revision+1,execution_started_at=now(),execution_baseline=baseline,
 state=jsonb_set(state,'{pending}',coalesce((select jsonb_agg(o) from jsonb_array_elements(r.state->'pending')o where not(o->>'side'='koop' or(o->>'side'='verkoop' and o->>'reason'='Dagsluiting van de eigen beurs.'))),'[]'::jsonb)),
 token=null,lease_until=null,last_attempt=null,revision=revision+1,status='owner_paused' where singleton;
 return fp;
end$$;
-- The old endpoint can still update the untouched EUR500 reference, but cannot
-- claim or commit the capital account after its explicitly recorded transition.
create or replace function public.paper_capital_claim(p_tick_token uuid,p_base_revision bigint) returns jsonb
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$begin
 perform 1 from paperlab.capital_runtime where singleton and execution_profile is null for update;if not found then return null;end if;
 return public.paper_capital_claim_base_v1(p_tick_token,p_base_revision);end$$;
create or replace function public.paper_capital_commit(p_token uuid,p_output jsonb) returns boolean
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$begin
 perform 1 from paperlab.capital_runtime where singleton and execution_profile is null for update;if not found then return false;end if;
 return public.paper_capital_commit_base_v1(p_token,p_output);end$$;
create or replace function public.paper_capital_claim_multiday(p_tick_token uuid,p_base_revision bigint) returns jsonb
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$declare r paperlab.capital_runtime;x jsonb;begin
 select * into r from paperlab.capital_runtime where singleton for update;if r.execution_profile is null then return null;end if;
 x:=public.paper_capital_claim_base_v1(p_tick_token,p_base_revision);if x is null then return null;end if;
 return x||jsonb_build_object('execution_policy',r.execution_policy,'execution_profile',r.execution_profile,'execution_revision',r.execution_revision);end$$;
create or replace function public.paper_capital_commit_multiday(p_token uuid,p_output jsonb) returns boolean
language plpgsql security definer set search_path=pg_catalog,pg_temp as $$declare r paperlab.capital_runtime;receipt jsonb;begin
 select * into r from paperlab.capital_runtime where singleton and token=p_token and lease_until>now() for update;if not found then return false;end if;
 if r.execution_profile is null or p_output->>'protocol' is distinct from 'capital-multiday-v2' or p_output->>'execution_profile' is distinct from r.execution_profile or (p_output->>'execution_revision')::bigint is distinct from r.execution_revision
 or p_output->'summary'->>'execution_policy' is distinct from 'capital-multiday-v2' or p_output->'summary'->>'close_at_session_end' is distinct from 'false' then raise exception 'Invalid multiday epoch';end if;
 for receipt in select value from jsonb_array_elements(p_output->'trades')loop
  if receipt->'snapshot'->'execution_policy'->>'profile' is distinct from r.execution_profile or receipt->'snapshot'->'execution_policy'->>'version' is distinct from 'capital-multiday-v2'
   or receipt->'snapshot'->'execution_policy'->>'close_at_session_end' is distinct from 'false' or receipt->>'reason'='Dagsluiting van de eigen beurs.' then raise exception 'Legacy or unexplained multiday receipt';end if;
 end loop;
 if exists(select 1 from jsonb_array_elements(p_output->'state'->'pending')o where o->>'side'='verkoop' and o->>'reason'='Dagsluiting van de eigen beurs.') then raise exception 'No forced session exit in multiday phase';end if;
 return public.paper_capital_commit_base_v1(p_token,jsonb_set(p_output,'{protocol}','"capital-10k-v1"'));
end$$;
revoke all on function public.paper_capital_set_horizon(jsonb) from public,anon,authenticated,service_role;
revoke all on function public.paper_capital_claim(uuid,bigint),public.paper_capital_commit(uuid,jsonb),public.paper_capital_claim_multiday(uuid,bigint),public.paper_capital_commit_multiday(uuid,jsonb) from public,anon,authenticated;
grant execute on function public.paper_capital_claim(uuid,bigint),public.paper_capital_commit(uuid,jsonb),public.paper_capital_claim_multiday(uuid,bigint),public.paper_capital_commit_multiday(uuid,jsonb) to service_role;
commit;
