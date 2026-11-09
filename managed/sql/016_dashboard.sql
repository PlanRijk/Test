begin;
create or replace function public.paper_dashboard_read(p_owner uuid)returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare c paperlab.capital_runtime;m paperlab.portfolio;signals jsonb;
begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton)then raise exception'Owner required';end if;
 select *into c from paperlab.capital_runtime where singleton;select *into m from paperlab.portfolio where singleton;
 if c.profile is null then return jsonb_build_object('available',false);end if;
 select coalesce(jsonb_agg(to_jsonb(z)order by signal_fraction desc,symbol),'[]')into signals from(
  select h.key as symbol,(h.value->-1->>'price')::float8/nullif(a.avg_price,0)-1 as signal_fraction,
   c.state->'positions'?h.key as already_held,c.state->'risk'->'cooldowns'->>h.key as cooldown_until,
   m.state->'last_observation'->h.key->>'time'as quote_time
  from jsonb_each(m.state->'history')h
  cross join lateral(select avg((v->>'price')::float8)as avg_price from jsonb_array_elements(h.value)with ordinality x(v,i)where i between jsonb_array_length(h.value)-5 and jsonb_array_length(h.value)-1)a
  where jsonb_array_length(h.value)>=6 and jsonb_array_length(h.value)<=12 and a.avg_price>0
   and extract(epoch from((c.summary->>'last_market_update')::timestamptz-(h.value->-6->>'time')::timestamptz))between 0 and 1800
   and extract(epoch from((c.summary->>'last_market_update')::timestamptz-(m.state->'last_observation'->h.key->>'time')::timestamptz))between 0 and 120
   and(h.value->-1->>'price')::float8/a.avg_price-1>.002
  order by signal_fraction desc,symbol limit 8)z;
 return jsonb_build_object('available',true,'as_of',now(),'account',jsonb_build_object('enabled',c.enabled,'status',c.status,'last_success',c.last_success,'started_at',c.started_at,'execution_profile',c.execution_profile,'policy',c.execution_policy,'summary',c.summary,'allow_entries',c.allow_entries,
  'data_complete',c.state->'risk'->'data_complete','pending_buys',(select count(*)from jsonb_array_elements(c.state->'pending')p where p->>'side'='koop')),
  'main_running',(m.state->>'running')::boolean,'main_last_update',m.state->>'last_update','collector_status',m.last_tick_status,
  'data_info',jsonb_build_object('checked_at',m.state->'data_info'->>'checked_at','fresh_symbols',m.state->'data_info'->'fresh_symbols','source',m.state->'data_info'->>'source','closed_symbols',m.state->'data_info'->'closed_symbols'),
  'signal_snapshot',signals,'signals_are_orders',false,
  'counts',(select jsonb_build_object('trades',count(*),'buys',count(*)filter(where side='koop'),'closes',count(*)filter(where side='verkoop'),'commissions_eur',coalesce(sum(fee),0))from paperlab.capital_trades),
  'trades',(select coalesce(jsonb_agg(to_jsonb(t)order by id desc),'[]')from(select id,time,symbol,side,qty,price,fee,pnl,reason from paperlab.capital_trades order by id desc limit 20)t),
  'curve',(select coalesce(jsonb_agg(to_jsonb(t)order by hour),'[]')from(select hour,last_at,last_value from paperlab.capital_curve order by hour desc limit 90)t),
  'research',jsonb_build_object('iex',(select jsonb_build_object('enabled',enabled,'status',status,'latest',latest,'run_until',run_until)from paperlab.iex_runtime),'daily',(select jsonb_build_object('last_success',last_success,'summary',summary)from paperlab.daily_study_runtime),'learning',(select training_status from paperlab.learning_runtime)));
end$$;
revoke all on function public.paper_dashboard_read(uuid)from public,anon,authenticated;
grant execute on function public.paper_dashboard_read(uuid)to service_role;
commit;
