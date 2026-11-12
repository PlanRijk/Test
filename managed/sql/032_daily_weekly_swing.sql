-- New prospective PAPER epoch. Existing capital, legacy stops and frozen studies remain.
begin;
create table if not exists paperlab.swing_runtime(singleton boolean primary key default true check(singleton),profile text,policy jsonb,started_at timestamptz,baseline jsonb,rounds bigint not null default 0,last_success timestamptz);
insert into paperlab.swing_runtime(singleton)values(true)on conflict do nothing;
alter table paperlab.swing_runtime enable row level security;
revoke all on paperlab.swing_runtime from public,anon,authenticated,service_role;
create or replace function public.paper_swing_configure(p_policy jsonb)returns text language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare r paperlab.swing_runtime;c paperlab.capital_runtime;fp text;begin
 select *into r from paperlab.swing_runtime where singleton for update;
 if r.profile is not null then if r.policy<>p_policy then raise exception'Swing epoch frozen';end if;return r.profile;end if;
 if not(p_policy@>'{"version":"quality-swing-paper-v1","account":"capital10k","real_orders":false,"paid_services":false,"unit_eur":5,"min_daily_closes":20,"volatility_returns":14,"volatility_multiple":2.5,"min_stop_fraction":0.03,"max_stop_fraction":0.08,"gap_reserve_fraction":0.01,"max_entry_gap_fraction":0.01,"max_round_trip_cost_fraction":0.015,"max_new_stop_loss_eur":20,"max_total_stop_loss_eur":150,"min_order_eur":100,"max_order_eur":500,"max_buys_per_day":2,"max_holding_sessions":20,"net_reward_risk":2,"reentry_hours":24,"quote_age_seconds":120,"additional_market_downloads":0,"legacy_positions_unchanged":true}'::jsonb)or coalesce(p_policy->>'implementation_sha256','')!~'^[a-f0-9]{64}$'then raise exception'Invalid swing policy';end if;
 select *into c from paperlab.capital_runtime where singleton for update;if c.profile is null then raise exception'Capital account required';end if;
 fp:=encode(sha256(convert_to(p_policy::text,'UTF8')),'hex');
 update paperlab.swing_runtime set profile=fp,policy=p_policy,started_at=now(),baseline=jsonb_build_object('state_hash',encode(sha256(convert_to(c.state::text,'UTF8')),'hex'),'summary',c.summary,'positions',c.state->'positions','cash',c.state->'cash','last_trade_id',(select coalesce(max(id),0)from paperlab.capital_trades),'independent_restart',false,'proven_edge',false)where singleton;
 -- No position rewrite, no cash reset and no forced sale at transition.
 update paperlab.capital_runtime set state=jsonb_set(state,'{pending}',coalesce((select jsonb_agg(o)from jsonb_array_elements(state->'pending')o where o->>'side'<>'koop'),'[]')),revision=revision+1,token=null,lease_until=null,last_attempt=null,summary=summary||jsonb_build_object('swing_policy',p_policy->>'version','swing_profile',fp,'new_entries_allowed',true,'priority_mode','daily_weekly_paper_active')where singleton;
 update paperlab.strategy_priority set new_entries_allowed=true,policy=policy||'{"mode":"daily_weekly_paper_active","live_trading_allowed":false}'::jsonb,
 readiness=jsonb_set(readiness,'{coherent_trade_protocol}',jsonb_build_object('status','paper_active','requires','Dag-/weekmotor actief als nieuwe, onbewezen paperhypothese. Persoonlijke kosten/data en voordeel blijven niet geverifieerd.'))where singleton;
 return fp;
end$$;
-- Old worker cannot submit stale or five-minute entries after activation.
create or replace function public.paper_audited_claim(p_tick_token uuid,p_base_revision bigint)returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$declare x jsonb;begin
 if exists(select 1 from paperlab.swing_runtime where profile is not null)then return null;end if;
 x:=public.paper_audited_claim_priority_base_v1(p_tick_token,p_base_revision);
 if exists(select 1 from paperlab.strategy_priority where singleton and policy is not null and not new_entries_allowed)then x:=x||jsonb_build_object('company_dossiers','{}'::jsonb,'priority_mode','manage_existing_research_first');end if;return x;
end$$;
create or replace function public.paper_audited_commit(p_token uuid,p_output jsonb)returns boolean language plpgsql security definer set search_path=pg_catalog,pg_temp as $$begin
 if exists(select 1 from paperlab.swing_runtime where profile is not null)then return false;end if;
 if exists(select 1 from paperlab.strategy_priority where singleton and policy is not null and not new_entries_allowed)and(exists(select 1 from jsonb_array_elements(p_output->'trades')t where t->>'side'='koop')or exists(select 1 from jsonb_array_elements(p_output->'state'->'pending')o where o->>'side'='koop'))then raise exception'New entries disabled';end if;
 return public.paper_audited_commit_priority_base_v1(p_token,p_output);
end$$;
create or replace function public.paper_swing_claim(p_tick_token uuid,p_base_revision bigint)returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare r paperlab.swing_runtime;c paperlab.capital_runtime;x jsonb;ds jsonb;bars jsonb;payload jsonb;charge bigint;m date:=date_trunc('month',now()at time zone'UTC')::date;begin
 select *into r from paperlab.swing_runtime where singleton for share;if r.profile is null then return null;end if;
 x:=public.paper_audited_claim_priority_base_v1(p_tick_token,p_base_revision);if x is null then return null;end if;
 if not exists(select 1 from paperlab.strategy_priority where singleton and new_entries_allowed)then x:=jsonb_set(x,'{allow_entries}','false');end if;
 select *into c from paperlab.capital_runtime where singleton;
 -- Reviewed candidates plus ALL held dossiers for explicit thesis invalidation.
 select coalesce(jsonb_object_agg(key,value),'{}')into ds from(select key,value from jsonb_each(paperlab.company_records())where c.state->'positions'?key or x->'company_dossiers'?key order by (c.state->'positions'?key)desc,key limit 20)z;
 select coalesce(jsonb_object_agg(k.key,(select coalesce(jsonb_agg(to_jsonb(z)order by day),'[]')from(select distinct on(day)*from(select a->>'day'as day,(a->>'close')::float8 as close,a->>'observed_at'as observed_at from jsonb_array_elements(coalesce(k.value->'market_closes','[]'))a union all select b.day::text,b.close,b.observed_at::text from paperlab.daily_study_bars b where b.symbol=k.key and b.observed_at<=now())u where day<(now()at time zone'UTC')::date::text order by day desc,observed_at desc limit 20)z)),'{}')into bars from jsonb_each(ds)k;
 payload:=jsonb_build_object('company_dossiers',ds,'company_daily',bars,'swing_profile',r.profile,'swing_policy',r.policy,'swing_implementation_sha256',r.policy->>'implementation_sha256');charge:=2*octet_length(payload::text)+1024;
 if octet_length(payload::text)>120000 or(select estimated_worker_egress_bytes+charge from paperlab.free_usage where month=m)>paperlab.traffic_limit('soft')then
  payload:=jsonb_build_object('company_dossiers','{}'::jsonb,'company_daily','{}'::jsonb,'swing_profile',r.profile,'swing_policy',r.policy,'swing_implementation_sha256',r.policy->>'implementation_sha256');x:=jsonb_set(x,'{allow_entries}','false');charge:=2*octet_length(payload::text)+1024;
 end if;
 update paperlab.free_usage set estimated_worker_egress_bytes=estimated_worker_egress_bytes+charge where month=m;
 update paperlab.capital_usage set estimated_bytes=estimated_bytes+charge where month=m;
 return x||payload;
end$$;
create or replace function paperlab.swing_ledger_commit(p_token uuid,p_output jsonb) returns boolean
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
  if receipt_json->>'side'='koop' and(receipt_json->'snapshot'->'purchase_rationale'->>'schema' is distinct from 'purchase-rationale-v1' or receipt_json->'snapshot'->'purchase_rationale'->'decision'->>'statement' is null or jsonb_array_length(receipt_json->'snapshot'->'purchase_rationale'->'decision'->'observations') is distinct from 20
   or ((receipt_json->'snapshot'->'purchase_rationale'->'cost_estimate'->>'budget_eur')::double precision between 99.999999 and 500.000001) is not true or receipt_json->'snapshot'->'purchase_rationale'->'execution'->>'quote_time' is null or jsonb_typeof(receipt_json->'snapshot'->'purchase_rationale'->'execution'->'quote_age_seconds') is distinct from 'number' or (receipt_json->'snapshot'->'purchase_rationale'->'execution'->>'quote_age_seconds')::double precision not between 0 and 120 or (receipt_json->'snapshot'->'purchase_rationale'->'execution'->>'cost_eur')::double precision>500.000001) then raise exception 'Capital purchase explanation required';end if;
 end loop;
 select coalesce(sum(case when x->>'side'='koop' then -(x->>'qty')::double precision*(x->>'price')::double precision/(x->'snapshot'->>'fx')::double precision else (x->>'qty')::double precision*(x->>'price')::double precision/(x->'snapshot'->>'fx')::double precision end
  -(x->>'fee')::double precision-coalesce((x->'snapshot'->'tax_detail'->>'transaction_tax_eur')::double precision,0)-coalesce((x->'snapshot'->'tax_detail'->>'capital_gains_reserve_eur')::double precision,0)-coalesce((x->'snapshot'->'tax_detail'->>'foreign_tax_reserve_eur')::double precision,0)-coalesce((x->'snapshot'->'tax_detail'->>'adr_reserve_eur')::double precision,0)),0),
  coalesce(sum((x->>'fee')::double precision),0),coalesce(sum((x->>'pnl')::double precision),0) into cash_change,fees_change,pnl_change from jsonb_array_elements(p_output->'trades')x;
 if abs(5*((s->>'cash')::double precision-(r.state->>'cash')::double precision)-cash_change)>0.000001 or abs(5*((s->>'fees')::double precision-(r.state->>'fees')::double precision)-fees_change)>0.000001 or abs(5*((s->>'realized')::double precision-(r.state->>'realized')::double precision)-pnl_change)>0.000001 then raise exception 'Capital ledger mismatch';end if;
 charge:=2*octet_length(p_output::text);m:=date_trunc('month',now() at time zone 'UTC')::date;
 perform 1 from paperlab.free_usage where month=m for update;perform 1 from paperlab.capital_usage where month=m for update;
 if exists(select 1 from paperlab.free_usage where month=m and estimated_worker_egress_bytes+charge>=paperlab.traffic_limit('hard')) or exists(select 1 from paperlab.capital_usage where month=m and estimated_bytes+charge>=300000000) then
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
create or replace function public.paper_swing_commit(p_token uuid,p_output jsonb)returns boolean language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare r paperlab.swing_runtime;c paperlab.capital_runtime;t jsonb;p jsonb;old jsonb;proof jsonb;a jsonb;required float8;protective boolean;saved boolean;k text;begin
 select *into r from paperlab.swing_runtime where singleton for share;
 select *into c from paperlab.capital_runtime where singleton and token=p_token and lease_until>now()for update;if not found then return false;end if;
 if r.profile is null or p_output->>'protocol'is distinct from'quality-swing-paper-v1'or p_output->>'swing_profile'is distinct from r.profile or p_output->'summary'->>'swing_profile'is distinct from r.profile then raise exception'Swing profile mismatch';end if;
 if not exists(select 1 from paperlab.strategy_priority where singleton and new_entries_allowed)and(exists(select 1 from jsonb_array_elements(p_output->'trades')z where z->>'side'='koop')or exists(select 1 from jsonb_array_elements(p_output->'state'->'pending')z where z->>'side'='koop'))then raise exception'Swing entries disabled';end if;
 if exists(select 1 from jsonb_array_elements(p_output->'state'->'pending')o where o->>'side'='koop'and(o->'swing_plan'->>'profile'is distinct from r.profile or ((o->'swing_plan'->>'budget_eur')::float8 between 100 and 500.000001)is not true))then raise exception'Unversioned pending buy';end if;
 -- Existing lots cannot be silently resized, rewritten or deleted without receipt.
 for k,old in select key,value from jsonb_each(c.state->'positions')loop
  p:=p_output->'state'->'positions'->k;
  if p is null then if not exists(select 1 from jsonb_array_elements(p_output->'trades')tr where tr->>'symbol'=k and tr->>'side'='verkoop'and abs((tr->>'qty')::float8-(old->>'qty')::float8)<1e-9)then raise exception'Position disappeared without sale';end if;
  elsif p->'qty'is distinct from old->'qty'or p->'cost'is distinct from old->'cost'or p->'entry'is distinct from old->'entry'or p->'time'is distinct from old->'time'or(p->>'stop')::float8<(old->>'stop')::float8 or(not(old?'swing')and p->'stop'is distinct from old->'stop')or(p->'swing'->>'initial_stop_loss_eur'is distinct from old->'swing'->>'initial_stop_loss_eur')then raise exception'Existing position changed';end if;
 end loop;
 for k,p in select key,value from jsonb_each(p_output->'state'->'positions')loop
  if not(c.state->'positions'?k)and not exists(select 1 from jsonb_array_elements(p_output->'trades')tr where tr->>'symbol'=k and tr->>'side'='koop')then raise exception'Position without purchase';end if;
 end loop;
 for t in select value from jsonb_array_elements(p_output->'trades')loop
  k:=t->>'symbol';proof:=t->'snapshot'->'profit_exit';
  if t->'snapshot'->'execution_policy'->>'profile'is distinct from r.profile then raise exception'Execution epoch required';end if;
  if t->>'side'='koop'then
   p:=p_output->'state'->'positions'->k;a:=t->'snapshot'->'purchase_rationale'->'company_execution_check';
   if c.state->'positions'?k or p->'swing'->>'profile'is distinct from r.profile or coalesce((a->>'eligible')::boolean,false)is not true
    or(select count(*)from jsonb_object_keys(a->'assessment'->'pillars'))<>5 or not((a->'assessment'->'pillars')?&array['growth','profitability','valuation','moat','risks'])or exists(select 1 from jsonb_each(a->'assessment'->'pillars')x where x.value->>'status'is distinct from'pass')
    or not exists(select 1 from paperlab.company_dossiers d where id=a->'assessment'->>'dossier_id'and symbol=k and id=(select id from paperlab.company_dossiers where symbol=k order by known_at desc,id desc limit 1))
    or not exists(select 1 from paperlab.company_reviews q where id=a->'assessment'->>'review_id'and symbol=k and reviewed_at<=now()and reviewed_at>=now()-interval'7 days'and id=(select id from paperlab.company_reviews where symbol=k order by reviewed_at desc,id desc limit 1))then raise exception'Current five-pillar evidence required';end if;
   a:=t->'snapshot'->'swing_entry';
   if exists(select 1 from unnest(array['round_trip_cost_fraction','estimated_stop_loss_eur','held_stop_risk_eur','stop_fraction','cost_eur'])key where jsonb_typeof(a->key)is distinct from'number')or a->>'signal_day'is null then raise exception'Numeric entry evidence required';end if;
   if abs((p->>'qty')::float8-(t->>'qty')::float8)>1e-9 or abs((p->>'cost')::float8*5-(t->'snapshot'->'purchase_rationale'->'execution'->>'cost_eur')::float8)>1e-6 then raise exception'Purchase lot mismatch';end if;
   if exists(select 1 from jsonb_array_elements(t->'snapshot'->'purchase_rationale'->'decision'->'observations')b where (b->>'day')::date>=(t->'snapshot'->>'decision_time')::timestamptz::date or (b->>'observed_at')::timestamptz>(t->'snapshot'->>'decision_time')::timestamptz)then raise exception'Future daily evidence rejected';end if;
   if a->>'profile'is distinct from r.profile or ((a->>'round_trip_cost_fraction')::float8 between 0 and .015000000001)is not true
    or((a->>'estimated_stop_loss_eur')::float8 between 0 and 20.000000001)is not true
    or((a->>'held_stop_risk_eur')::float8>=0 and(a->>'held_stop_risk_eur')::float8+(a->>'estimated_stop_loss_eur')::float8<=150.000001)is not true
    or((a->>'stop_fraction')::float8 between .03 and .080000000001)is not true
    or abs((p->>'stop')::float8-(p->>'entry')::float8*(1-(a->>'stop_fraction')::float8))>1e-6
    or abs((a->>'cost_eur')::float8-5*(p->>'cost')::float8)>1e-6
    or abs((a->>'estimated_stop_loss_eur')::float8-(p->'swing'->>'initial_stop_loss_eur')::float8)>1e-6
    or (a->>'signal_day')::date>=(t->>'time')::timestamptz::date
    or exists(select 1 from paperlab.capital_trades where symbol=k and side='verkoop'and time>(t->>'time')::timestamptz-interval'24 hours')then raise exception'Swing entry risk/cost proof rejected';end if;
   if (p_output->'state'->'risk'->>'buys_today')::int>2 then raise exception'Two buys per day maximum';end if;
  else
   old:=c.state->'positions'->k;if old is null then raise exception'Exit lot missing';end if;
   if coalesce((p_output->'state'->'risk'->'cooldowns'->>k)::timestamptz,'-infinity')<(t->>'time')::timestamptz+interval'24 hours'then raise exception'Exit cooldown required';end if;
   if jsonb_typeof(proof->'required_net_profit_eur')is distinct from'number'or jsonb_typeof(proof->'estimated_stop_loss_eur')is distinct from'number'then raise exception'Net target proof required';end if;
   required:=greatest(10,5*(old->>'cost')::float8*.025,case when old?'swing'then 2*(old->'swing'->>'initial_stop_loss_eur')::float8 else 1.5*(proof->>'estimated_stop_loss_eur')::float8 end);
   if proof->>'version'is distinct from(case when old?'swing'then'quality-swing-paper-v1'else'net-exits-v1'end)or abs((proof->>'required_net_profit_eur')::float8-required)>1e-6 then raise exception'Position net target mismatch';end if;
   protective:=coalesce((proof->>'protective_exception')::boolean,false);
   if not protective and(t->>'pnl')::float8+1e-6<required then raise exception'Profit exit below net target';end if;
   if protective and not((t->>'price')::float8/(t->'snapshot'->>'fx')::float8<=5*(old->>'stop')::float8 or coalesce((p_output->'state'->'risk'->>'daily_halted')::boolean,false)or coalesce((p_output->'state'->'risk'->>'global_halted')::boolean,false)
    or exists(select 1 from jsonb_array_elements(c.state->'pending')o where o->>'symbol'=k and o->>'side'='verkoop'and(o->>'risk_exit')::boolean is true))then raise exception'Protective evidence missing';end if;
  end if;
 end loop;
 saved:=paperlab.swing_ledger_commit(p_token,jsonb_set(p_output,'{protocol}','"capital-10k-v1"'));
 if saved then update paperlab.swing_runtime set rounds=rounds+1,last_success=now()where singleton;end if;return saved;
end$$;
create or replace function public.paper_priority_read(p_owner uuid)returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton)then raise exception'Owner required';end if;
 return jsonb_build_object('policy',(select policy from paperlab.strategy_priority),'started_at',(select started_at from paperlab.strategy_priority),'new_entries_allowed',(select new_entries_allowed from paperlab.strategy_priority),'readiness',(select readiness from paperlab.strategy_priority),'swing',(select to_jsonb(s)-'baseline'from paperlab.swing_runtime s),'note','Nieuwe dag-/weekregels zijn alleen voor nieuwe paperposities actief. Bestaande posities behouden hun oorspronkelijke stops en winstdoelen. IBKR is niet gekoppeld; werkelijke kosten, belastingen en winstgevendheid zijn nog niet geverifieerd.');
end$$;
revoke all on function public.paper_swing_configure(jsonb),paperlab.swing_ledger_commit(uuid,jsonb),public.paper_swing_claim(uuid,bigint),public.paper_swing_commit(uuid,jsonb)from public,anon,authenticated,service_role;
grant execute on function public.paper_swing_claim(uuid,bigint),public.paper_swing_commit(uuid,jsonb)to service_role;
create or replace function public.paper_strategy_audit_read(p_owner uuid)returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare stats jsonb;cohorts jsonb;begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton)then raise exception'Owner required';end if;
 with closed as(select s.*,b.id buy_id,
  s.qty*s.price/(s.snapshot->>'fx')::float8-b.qty*b.price/(b.snapshot->>'fx')::float8 gross_gain,
  case when b.snapshot?'swing_entry'then'quality-swing-paper-v1'when b.snapshot?'entry_audit'then'entry-audit-v1'when b.snapshot->'purchase_rationale'?'company_entry'then'company-entry-v1'else'legacy-entry'end entry_cohort,
  coalesce(s.snapshot->'profit_exit'->>'version',s.snapshot->'execution_policy'->>'version','legacy-exit')exit_cohort
  from paperlab.capital_trades s left join lateral(select *from paperlab.capital_trades b where b.symbol=s.symbol and b.side='koop'and b.time<s.time order by b.time desc,b.id desc limit 1)b on true where s.side='verkoop'),
 grouped as(select entry_cohort,exit_cohort,count(*)closed,count(*)filter(where pnl>0)wins,sum(pnl)net_eur from closed group by entry_cohort,exit_cohort)
 select(select jsonb_build_object('closed',count(*),'wins',count(*)filter(where pnl>0),'losses',count(*)filter(where pnl<0),'net_eur',sum(pnl),'matched',count(buy_id),'gross_before_costs_eur',sum(gross_gain),'costs_and_reserves_eur',sum(gross_gain-pnl),'mean_win_eur',avg(pnl)filter(where pnl>0),'mean_loss_eur',avg(pnl)filter(where pnl<0),'profit_factor',sum(pnl)filter(where pnl>0)/nullif(-sum(pnl)filter(where pnl<0),0),'net_exit_closed',count(*)filter(where exit_cohort='net-exits-v1'),'audited_entry_closed',count(*)filter(where entry_cohort='entry-audit-v1'))from closed),
 (select coalesce(jsonb_agg(to_jsonb(g)),'[]')from grouped g)into stats,cohorts;
 return jsonb_build_object('checked_at',now(),'runtime',(select to_jsonb(a)from paperlab.strategy_audit_runtime a),'statistics',stats,'cohorts',cohorts,
 'health',(select jsonb_build_object('history_status',h.status,'history_last_success',h.last_success,'reference_examples',(select count(*)from paperlab.learning_samples),'learning_status',l.training_status->>'status','database_bytes',pg_database_size(current_database()))from paperlab.history_runtime h cross join paperlab.learning_runtime l));
end$$;
commit;
