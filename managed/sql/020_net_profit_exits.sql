begin;
create table if not exists paperlab.net_exit_runtime(singleton boolean primary key default true check(singleton),profile text,policy jsonb,started_at timestamptz,baseline jsonb,cancelled_orders jsonb);
insert into paperlab.net_exit_runtime(singleton)values(true)on conflict do nothing;
alter table paperlab.net_exit_runtime enable row level security;
revoke all on paperlab.net_exit_runtime from public,anon,authenticated,service_role;
-- Preserve the old implementation as an explicit reference and block its active
-- route once the new exit epoch starts. An in-flight old fill cannot commit.
do $$begin
 if to_regprocedure('public.paper_company_claim_entry_v1(uuid,bigint)')is null then
  alter function public.paper_company_claim(uuid,bigint)rename to paper_company_claim_entry_v1;
  alter function public.paper_company_commit(uuid,jsonb)rename to paper_company_commit_entry_v1;
 end if;
end$$;
create or replace function public.paper_net_exit_configure(p_policy jsonb)returns text language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare n paperlab.net_exit_runtime;c paperlab.capital_runtime;fp text;cancelled jsonb;kept jsonb;
begin
 select *into n from paperlab.net_exit_runtime where singleton for update;select *into c from paperlab.capital_runtime where singleton for update;
 if not(p_policy@>'{"version":"net-exits-v1","account":"capital10k","unit_eur":5,"min_profit_eur":10,"min_net_return_fraction":0.025,"min_reward_risk":1.5,"stop_execution_buffer_fraction":0.001,"quote_age_seconds":120,"close_at_session_end":false,"protective_exceptions":true,"additional_market_downloads":0,"real_orders":false}'::jsonb)
 or coalesce(p_policy->>'implementation_sha256','')!~'^[a-f0-9]{64}$'or c.execution_policy->>'version'is distinct from'capital-multiday-v2'or not exists(select 1 from paperlab.company_runtime where profile is not null and policy->>'implementation_sha256'=p_policy->>'company_implementation_sha256')then raise exception'Invalid net exit policy';end if;
 fp:=encode(sha256(convert_to(p_policy::text,'UTF8')),'hex');
 if n.profile is not null then if n.policy<>p_policy then raise exception'Net exit epoch frozen';end if;return n.profile;end if;
 select coalesce(jsonb_agg(o),'[]')into cancelled from jsonb_array_elements(c.state->'pending')o where o->>'side'='koop'or(o->>'side'='verkoop'and coalesce((o->>'risk_exit')::boolean,false)is false);
 select coalesce(jsonb_agg(o),'[]')into kept from jsonb_array_elements(c.state->'pending')o where o->>'side'='verkoop'and(o->>'risk_exit')::boolean is true;
 update paperlab.net_exit_runtime set profile=fp,policy=p_policy,started_at=now(),cancelled_orders=cancelled,baseline=jsonb_build_object('summary',c.summary,'capital_revision',c.revision,'last_trade_id',(select coalesce(max(id),0)from paperlab.capital_trades),'carried_positions',(select count(*)from jsonb_object_keys(c.state->'positions')),'state_hash',encode(sha256(convert_to(c.state::text,'UTF8')),'hex'),'note','Bestaande posities en eerdere resultaten blijven behouden; geen onafhankelijke vergelijking met een lege rekening.')where singleton;
 update paperlab.capital_runtime set state=jsonb_set(state,'{pending}',kept),token=null,lease_until=null,last_attempt=null,revision=revision+1,
 summary=summary||jsonb_build_object('profit_exit_policy','net-exits-v1','profit_exit_profile',fp)where singleton;
 return fp;
end$$;
create or replace function public.paper_company_claim(p_tick_token uuid,p_base_revision bigint)returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$begin
 if exists(select 1 from paperlab.net_exit_runtime where profile is not null)then return null;end if;return public.paper_company_claim_entry_v1(p_tick_token,p_base_revision);end$$;
create or replace function public.paper_company_commit(p_token uuid,p_output jsonb)returns boolean language plpgsql security definer set search_path=pg_catalog,pg_temp as $$begin
 if exists(select 1 from paperlab.net_exit_runtime where profile is not null)then return false;end if;return public.paper_company_commit_entry_v1(p_token,p_output);end$$;
create or replace function public.paper_net_exit_claim(p_tick_token uuid,p_base_revision bigint)returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare n paperlab.net_exit_runtime;x jsonb;begin
 select *into n from paperlab.net_exit_runtime where singleton for update;if n.profile is null then return null;end if;
 x:=public.paper_company_claim_entry_v1(p_tick_token,p_base_revision);if x is null then return null;end if;
 return x||jsonb_build_object('exit_profile',n.profile,'exit_policy',n.policy);
end$$;
create or replace function public.paper_net_exit_commit(p_token uuid,p_output jsonb)returns boolean language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare n paperlab.net_exit_runtime;c paperlab.capital_runtime;t jsonb;proof jsonb;pos jsonb;floor float8;required float8;protective boolean;
begin
 select *into n from paperlab.net_exit_runtime where singleton for update;select *into c from paperlab.capital_runtime where singleton and token=p_token and lease_until>now()for update;if not found then return false;end if;
 if n.profile is null or p_output->>'exit_profile'is distinct from n.profile or p_output->>'exit_policy'is distinct from'net-exits-v1'then raise exception'Net exit profile mismatch';end if;
 for t in select value from jsonb_array_elements(p_output->'trades')loop
  proof:=t->'snapshot'->'profit_exit';
  if proof->>'version'is distinct from'net-exits-v1'or proof->>'profile'is distinct from n.profile then raise exception'Net exit proof required';end if;
  if t->>'side'='verkoop'then
   pos:=c.state->'positions'->(t->>'symbol');if pos is null then raise exception'Exit position missing';end if;
   floor:=greatest(10,5*(pos->>'cost')::float8*.025);required:=(proof->>'required_net_profit_eur')::float8;
   if jsonb_typeof(proof->'required_net_profit_eur')is distinct from'number'or jsonb_typeof(proof->'estimated_stop_loss_eur')is distinct from'number'or jsonb_typeof(proof->'cost_eur')is distinct from'number'
    or required is null or required<floor or required>1000000 or coalesce((proof->>'estimated_stop_loss_eur')::float8,-1)<0 or abs((proof->>'cost_eur')::float8-5*(pos->>'cost')::float8)>.000001
    or abs(required-greatest(floor,1.5*(proof->>'estimated_stop_loss_eur')::float8))>.000001 then raise exception'Invalid position-linked net target';end if;
   protective:=(t->>'price')::float8/(t->'snapshot'->>'fx')::float8<=5*(pos->>'stop')::float8
    or coalesce((p_output->'state'->'risk'->>'daily_halted')::boolean,false)or coalesce((p_output->'state'->'risk'->>'global_halted')::boolean,false)
    or exists(select 1 from jsonb_array_elements(c.state->'pending')o where o->>'symbol'=t->>'symbol'and o->>'side'='verkoop'and(o->>'risk_exit')::boolean is true);
   if (proof->>'protective_exception')::boolean is distinct from protective or proof->>'exit_type'is distinct from(case when protective then'protective'else'profit_target'end)then raise exception'Protective exit evidence mismatch';end if;
   if not protective and(t->>'pnl')::float8+.000001<required then raise exception'Ordinary sale below net target';end if;
  end if;
 end loop;
 return public.paper_company_commit_entry_v1(p_token,p_output);
end$$;
create or replace function public.paper_net_exit_read(p_owner uuid)returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton)then raise exception'Owner required';end if;
 return jsonb_build_object('runtime',(select jsonb_build_object('profile',profile,'policy',policy,'started_at',started_at,'baseline',baseline)from paperlab.net_exit_runtime),
 'positions',(select coalesce(jsonb_object_agg(key,value->'net_exit'),'{}')from paperlab.capital_runtime,jsonb_each(state->'positions')));
end$$;
revoke all on function public.paper_net_exit_configure(jsonb),public.paper_company_claim_entry_v1(uuid,bigint),public.paper_company_commit_entry_v1(uuid,jsonb),public.paper_company_claim(uuid,bigint),public.paper_company_commit(uuid,jsonb),public.paper_net_exit_claim(uuid,bigint),public.paper_net_exit_commit(uuid,jsonb),public.paper_net_exit_read(uuid)from public,anon,authenticated,service_role;
grant execute on function public.paper_company_claim(uuid,bigint),public.paper_company_commit(uuid,jsonb),public.paper_net_exit_claim(uuid,bigint),public.paper_net_exit_commit(uuid,jsonb),public.paper_net_exit_read(uuid)to service_role;
commit;
