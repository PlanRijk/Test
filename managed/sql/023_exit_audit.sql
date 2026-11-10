begin;
-- Private read-only diagnostic input; no financial state, orders or targets change.
create or replace function public.paper_exit_audit_input(p_owner uuid)returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare c paperlab.capital_runtime;m paperlab.portfolio;begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton)then raise exception'Owner required';end if;
 select *into c from paperlab.capital_runtime;select *into m from paperlab.portfolio;
 return jsonb_build_object('enabled',c.enabled,'main_running',(m.state->>'running')::boolean,'last_success',c.last_success,'state',c.state,'market',jsonb_build_object('prices',m.state->'prices','price_fx',m.state->'price_fx','usd_per_eur',m.state->'usd_per_eur','fx_time',m.state->'fx_time','history','{}'::jsonb,'catalogue',m.state->'catalogue','risk',jsonb_build_object('config',m.state->'risk'->'config','previous_quotes','{}'::jsonb),'belgian_tax',m.state->'belgian_tax','multi_market',m.state->'multi_market'),
 'cost_breakdown',(select jsonb_build_object('matched_closed',count(*),'commissions_eur',sum(b.fee+s.fee),'transaction_tax_eur',sum(coalesce((b.snapshot->'tax_detail'->>'transaction_tax_eur')::float8,0)+coalesce((s.snapshot->'tax_detail'->>'transaction_tax_eur')::float8,0)),'capital_gains_reserve_eur',sum(coalesce((s.snapshot->'tax_detail'->>'capital_gains_reserve_eur')::float8,0)),'foreign_and_adr_reserve_eur',sum(coalesce((b.snapshot->'tax_detail'->>'foreign_tax_reserve_eur')::float8,0)+coalesce((b.snapshot->'tax_detail'->>'adr_reserve_eur')::float8,0)+coalesce((s.snapshot->'tax_detail'->>'foreign_tax_reserve_eur')::float8,0)+coalesce((s.snapshot->'tax_detail'->>'adr_reserve_eur')::float8,0)))from paperlab.capital_trades s join lateral(select *from paperlab.capital_trades b where b.symbol=s.symbol and b.side='koop'and b.time<s.time order by b.time desc,b.id desc limit 1)b on true where s.side='verkoop'),
 'quotes',(select coalesce(jsonb_object_agg(symbol,payload),'{}')from(select distinct on(o.symbol)o.symbol,o.payload from paperlab.observations o where c.state->'positions'?o.symbol and o.received>now()-interval'4 days'order by o.symbol,o.received desc,o.id desc)x));
end$$;
revoke all on function public.paper_exit_audit_input(uuid)from public,anon,authenticated;
grant execute on function public.paper_exit_audit_input(uuid)to service_role;
commit;
