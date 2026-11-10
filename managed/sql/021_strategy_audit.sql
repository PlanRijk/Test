begin;
create table if not exists paperlab.strategy_audit_runtime(singleton boolean primary key default true check(singleton),profile text,policy jsonb,started_at timestamptz,baseline jsonb,latest jsonb,rounds bigint not null default 0);
insert into paperlab.strategy_audit_runtime(singleton)values(true)on conflict do nothing;
alter table paperlab.strategy_audit_runtime enable row level security;
revoke all on paperlab.strategy_audit_runtime from public,anon,authenticated,service_role;
do $$begin
 if to_regprocedure('public.paper_net_exit_claim_audit_base_v1(uuid,bigint)')is null then
  alter function public.paper_net_exit_claim(uuid,bigint)rename to paper_net_exit_claim_audit_base_v1;
  alter function public.paper_net_exit_commit(uuid,jsonb)rename to paper_net_exit_commit_audit_base_v1;
 end if;
end$$;
create or replace function public.paper_strategy_audit_configure(p_policy jsonb)returns text language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare a paperlab.strategy_audit_runtime;c paperlab.capital_runtime;fp text;cancelled jsonb;
begin
 select *into a from paperlab.strategy_audit_runtime where singleton for update;select *into c from paperlab.capital_runtime where singleton for update;
 if not(p_policy@>'{"version":"entry-audit-v1","account":"capital10k","unit_eur":5,"max_round_trip_cost_fraction":0.015,"reentry_hours":24,"max_new_stop_loss_eur":20,"max_total_stop_loss_eur":150,"force_sell_existing":false,"change_stop_distance":false,"change_profit_targets":false,"automatic_model_approval":false,"additional_market_downloads":0,"real_orders":false}'::jsonb)
 or coalesce(p_policy->>'implementation_sha256','')!~'^[a-f0-9]{64}$'or not exists(select 1 from paperlab.net_exit_runtime where profile is not null and policy->>'implementation_sha256'=p_policy->>'net_exit_implementation_sha256')then raise exception'Invalid strategy audit policy';end if;
 fp:=encode(sha256(convert_to(p_policy::text,'UTF8')),'hex');if a.profile is not null then if a.policy<>p_policy then raise exception'Strategy audit epoch frozen';end if;return a.profile;end if;
 select coalesce(jsonb_agg(o),'[]')into cancelled from jsonb_array_elements(c.state->'pending')o where o->>'side'='koop';
 update paperlab.strategy_audit_runtime set profile=fp,policy=p_policy,started_at=now(),baseline=jsonb_build_object('summary',c.summary,'carried_positions',(select count(*)from jsonb_object_keys(c.state->'positions')),'last_trade_id',(select coalesce(max(id),0)from paperlab.capital_trades),'state_hash',encode(sha256(convert_to(c.state::text,'UTF8')),'hex'),'cancelled_buys',cancelled,'note','Bestaande posities, stops, winstdoelen en eerdere resultaten blijven bewaard; geen onafhankelijke voor/na-vergelijking.')where singleton;
 update paperlab.capital_runtime set state=jsonb_set(state,'{pending}',coalesce((select jsonb_agg(o)from jsonb_array_elements(state->'pending')o where o->>'side'<>'koop'),'[]')),token=null,lease_until=null,last_attempt=null,revision=revision+1,summary=summary||jsonb_build_object('entry_audit_policy','entry-audit-v1','entry_audit_profile',fp)where singleton;
 return fp;
end$$;
create or replace function public.paper_net_exit_claim(p_tick_token uuid,p_base_revision bigint)returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$begin
 if exists(select 1 from paperlab.strategy_audit_runtime where profile is not null)then return null;end if;return public.paper_net_exit_claim_audit_base_v1(p_tick_token,p_base_revision);end$$;
create or replace function public.paper_net_exit_commit(p_token uuid,p_output jsonb)returns boolean language plpgsql security definer set search_path=pg_catalog,pg_temp as $$begin
 if exists(select 1 from paperlab.strategy_audit_runtime where profile is not null)then return false;end if;return public.paper_net_exit_commit_audit_base_v1(p_token,p_output);end$$;
create or replace function public.paper_audited_claim(p_tick_token uuid,p_base_revision bigint)returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare a paperlab.strategy_audit_runtime;x jsonb;payload jsonb;charge bigint;begin
 select *into a from paperlab.strategy_audit_runtime where singleton for update;if a.profile is null then return null;end if;
 x:=public.paper_net_exit_claim_audit_base_v1(p_tick_token,p_base_revision);if x is null then return null;end if;
 payload:=jsonb_build_object('audit_profile',a.profile,'audit_policy',a.policy,'recent_exits',(select coalesce(jsonb_object_agg(symbol,last_exit),'{}')from(select symbol,max(time)last_exit from paperlab.capital_trades where side='verkoop'and time>=now()-interval'24 hours'and time<=now()group by symbol)z));
 charge:=2*octet_length(payload::text)+512;update paperlab.free_usage set estimated_worker_egress_bytes=estimated_worker_egress_bytes+charge where month=date_trunc('month',now()at time zone'UTC')::date;
 return x||payload;
end$$;
create or replace function public.paper_audited_commit(p_token uuid,p_output jsonb)returns boolean language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare a paperlab.strategy_audit_runtime;t jsonb;p jsonb;saved boolean;
begin
 select *into a from paperlab.strategy_audit_runtime where singleton for update;
 if not exists(select 1 from paperlab.capital_runtime where singleton and token=p_token and lease_until>now())then return false;end if;
 if a.profile is null or p_output->>'audit_profile'is distinct from a.profile or p_output->>'audit_policy'is distinct from'entry-audit-v1'or p_output->'entry_audit_snapshot'->>'version'is distinct from'entry-audit-v1'or octet_length((p_output->'entry_audit_snapshot')::text)>12000 then raise exception'Audit profile or snapshot mismatch';end if;
 for t in select value from jsonb_array_elements(p_output->'trades')loop
  if t->'snapshot'->'strategy_audit'->>'profile'is distinct from a.profile then raise exception'Audit receipt required';end if;
  if t->>'side'='koop'then
   p:=t->'snapshot'->'entry_audit';
   if p->>'version'is distinct from'entry-audit-v1'or p->>'symbol'is distinct from t->>'symbol'or p->>'checked_at'is distinct from t->>'time'or p->>'profile'is distinct from a.profile or(p->>'passed')::boolean is distinct from true or jsonb_array_length(p->'codes')is distinct from 0
    or jsonb_typeof(p->'round_trip_cost_fraction')is distinct from'number'or((p->>'round_trip_cost_fraction')::float8 between 0 and .015000000001)is not true
    or jsonb_typeof(p->'estimated_stop_loss_eur')is distinct from'number'or((p->>'estimated_stop_loss_eur')::float8 between 0 and 20.000000001)is not true
    or jsonb_typeof(p->'held_stop_risk_eur')is distinct from'number'or jsonb_typeof(p->'reserved_entry_stop_risk_eur')is distinct from'number'or jsonb_typeof(p->'cost_eur')is distinct from'number'
    or coalesce((p->>'held_stop_risk_eur')::float8,-1)<0 or coalesce((p->>'reserved_entry_stop_risk_eur')::float8,-1)<0
    or((p->>'held_stop_risk_eur')::float8+(p->>'reserved_entry_stop_risk_eur')::float8<=150.000000001)is not true
    or abs((p->>'estimated_stop_loss_eur')::float8-(t->'snapshot'->'profit_exit'->>'estimated_stop_loss_eur')::float8)>.000001
    or abs((p->>'cost_eur')::float8-(t->'snapshot'->'purchase_rationale'->'execution'->>'cost_eur')::float8)>.000001
    or p->>'quote_time'is distinct from t->'snapshot'->'quote'->>'time'
    or exists(select 1 from paperlab.capital_trades s where s.symbol=t->>'symbol'and s.side='verkoop'and s.time>(t->>'time')::timestamptz-interval'24 hours'and s.time<=(t->>'time')::timestamptz)then raise exception'Entry cost, risk or cooldown proof rejected';end if;
  elsif coalesce((p_output->'state'->'risk'->'cooldowns'->>(t->>'symbol'))::timestamptz,'-infinity')<(t->>'time')::timestamptz+interval'24 hours'then raise exception'Post-sale cooldown required';end if;
 end loop;
 saved:=public.paper_net_exit_commit_audit_base_v1(p_token,p_output);
 if saved then update paperlab.strategy_audit_runtime set latest=p_output->'entry_audit_snapshot',rounds=rounds+1 where singleton;end if;return saved;
end$$;
create or replace function public.paper_strategy_audit_read(p_owner uuid)returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare stats jsonb;cohorts jsonb;begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton)then raise exception'Owner required';end if;
 with closed as(select s.*,b.id buy_id,
  s.qty*s.price/(s.snapshot->>'fx')::float8-b.qty*b.price/(b.snapshot->>'fx')::float8 gross_gain,
  case when b.snapshot?'entry_audit'then'entry-audit-v1'when b.snapshot->'purchase_rationale'?'company_entry'then'company-entry-v1'else'legacy-entry'end entry_cohort,
  coalesce(s.snapshot->'profit_exit'->>'version',s.snapshot->'execution_policy'->>'version','legacy-exit')exit_cohort
  from paperlab.capital_trades s left join lateral(select *from paperlab.capital_trades b where b.symbol=s.symbol and b.side='koop'and b.time<s.time order by b.time desc,b.id desc limit 1)b on true where s.side='verkoop'),
 grouped as(select entry_cohort,exit_cohort,count(*)closed,count(*)filter(where pnl>0)wins,sum(pnl)net_eur from closed group by entry_cohort,exit_cohort)
 select(select jsonb_build_object('closed',count(*),'wins',count(*)filter(where pnl>0),'losses',count(*)filter(where pnl<0),'net_eur',sum(pnl),'matched',count(buy_id),'gross_before_costs_eur',sum(gross_gain),'costs_and_reserves_eur',sum(gross_gain-pnl),'mean_win_eur',avg(pnl)filter(where pnl>0),'mean_loss_eur',avg(pnl)filter(where pnl<0),'profit_factor',sum(pnl)filter(where pnl>0)/nullif(-sum(pnl)filter(where pnl<0),0),'net_exit_closed',count(*)filter(where exit_cohort='net-exits-v1'),'audited_entry_closed',count(*)filter(where entry_cohort='entry-audit-v1'))from closed),
 (select coalesce(jsonb_agg(to_jsonb(g)),'[]')from grouped g)into stats,cohorts;
 return jsonb_build_object('checked_at',now(),'runtime',(select to_jsonb(a)from paperlab.strategy_audit_runtime a),'statistics',stats,'cohorts',cohorts,
 'health',(select jsonb_build_object('history_status',h.status,'history_last_success',h.last_success,'reference_examples',(select count(*)from paperlab.learning_samples),'learning_status',l.training_status->>'status','database_bytes',pg_database_size(current_database()))from paperlab.history_runtime h cross join paperlab.learning_runtime l));
end$$;
revoke all on function public.paper_strategy_audit_configure(jsonb),public.paper_net_exit_claim_audit_base_v1(uuid,bigint),public.paper_net_exit_commit_audit_base_v1(uuid,jsonb),public.paper_net_exit_claim(uuid,bigint),public.paper_net_exit_commit(uuid,jsonb),public.paper_audited_claim(uuid,bigint),public.paper_audited_commit(uuid,jsonb),public.paper_strategy_audit_read(uuid)from public,anon,authenticated,service_role;
grant execute on function public.paper_net_exit_claim(uuid,bigint),public.paper_net_exit_commit(uuid,jsonb),public.paper_audited_claim(uuid,bigint),public.paper_audited_commit(uuid,jsonb),public.paper_strategy_audit_read(uuid)to service_role;
commit;
