-- Prioritize coherent low-turnover research; preserve existing positions/exits.
begin;
create table if not exists paperlab.strategy_priority(singleton boolean primary key default true check(singleton),policy jsonb,started_at timestamptz,new_entries_allowed boolean not null default false,baseline jsonb,readiness jsonb not null default '{}');
insert into paperlab.strategy_priority(singleton)values(true)on conflict do nothing;
alter table paperlab.strategy_priority enable row level security;
revoke all on paperlab.strategy_priority from public,anon,authenticated,service_role;
create or replace function public.paper_priority_configure()returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare r paperlab.strategy_priority;c paperlab.capital_runtime;cancelled jsonb;p jsonb:='{"version":"quality-swing-priority-v1","account":"capital10k","mode":"manage_existing_research_first","research_horizon":"days_to_weeks","primary_existing_candidate":"context","candidate_protocol_unchanged":true,"primary_outcome_sessions":20,"new_model_training":false,"force_sales":false,"change_existing_stops":false,"change_existing_profit_targets":false,"reset_account":false,"real_orders":false,"paid_services":false,"priorities":["verified_costs_and_execution","review_existing_positions","coherent_daily_weekly_candidate","prospective_net_validation","text_model_pilot_after_budget"]}'::jsonb;begin
 select *into r from paperlab.strategy_priority where singleton for update;
 if r.policy is not null then if r.policy<>p then raise exception'Priority policy already configured';end if;return r.policy;end if;
 select *into c from paperlab.capital_runtime where singleton for update;
 if c.profile is null or c.state is null then raise exception'Existing capital account required';end if;
 select coalesce(jsonb_agg(o),'[]')into cancelled from jsonb_array_elements(c.state->'pending')o where o->>'side'='koop';
 update paperlab.strategy_priority set policy=p,started_at=now(),new_entries_allowed=false,
 baseline=jsonb_build_object('last_trade_id',(select coalesce(max(id),0)from paperlab.capital_trades),'summary',c.summary,'positions_hash',encode(sha256(convert_to((c.state->'positions')::text,'UTF8')),'hex'),'cash',c.state->'cash','cancelled_pending_buys',cancelled,'note','Alle bestaande posities en eerdere resultaten behouden; geen historische herstart.'),
 readiness='{"verified_personal_costs":{"status":"missing","requires":"Broker, tariefplan en fiscale woonplaats, met gecontroleerde bronnen"},"executable_market_data":{"status":"unproven","requires":"Verse verhandelbare bron, passende marktdekking en uitvoeringstest"},"coherent_trade_protocol":{"status":"research","requires":"Vooraf vastgelegde dag-/weekinstap, risicogestuurde positieomvang, uitstap en bedrijfsactieverwerking"},"prospective_net_edge":{"status":"unproven","requires":"Nieuwe onafhankelijke uitkomsten na kosten, risico en passende referentie"}}'where singleton;
 update paperlab.capital_runtime set state=jsonb_set(state,'{pending}',coalesce((select jsonb_agg(o)from jsonb_array_elements(state->'pending')o where o->>'side'<>'koop'),'[]')),revision=revision+1,token=null,lease_until=null,last_attempt=null,summary=summary||jsonb_build_object('priority_mode','manage_existing_research_first','new_entries_allowed',false)where singleton;
 return p;
end$$;
do $$begin
 if to_regprocedure('public.paper_audited_claim_priority_base_v1(uuid,bigint)')is null then
  alter function public.paper_audited_claim(uuid,bigint)rename to paper_audited_claim_priority_base_v1;
  alter function public.paper_audited_commit(uuid,jsonb)rename to paper_audited_commit_priority_base_v1;
 end if;
 if to_regprocedure('public.paper_project_read_priority_base_v1(uuid,text)')is null then alter function public.paper_project_read(uuid,text)rename to paper_project_read_priority_base_v1;end if;
end$$;
create or replace function public.paper_audited_claim(p_tick_token uuid,p_base_revision bigint)returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$declare x jsonb;begin
 x:=public.paper_audited_claim_priority_base_v1(p_tick_token,p_base_revision);if x is null then return null;end if;
 if exists(select 1 from paperlab.strategy_priority where singleton and policy is not null and not new_entries_allowed)then
  x:=x||jsonb_build_object('company_dossiers','{}'::jsonb,'priority_mode','manage_existing_research_first');
 end if;return x;
end$$;
create or replace function public.paper_audited_commit(p_token uuid,p_output jsonb)returns boolean language plpgsql security definer set search_path=pg_catalog,pg_temp as $$declare saved boolean;begin
 perform 1 from paperlab.strategy_priority where singleton for share;
 if exists(select 1 from paperlab.strategy_priority where singleton and policy is not null and not new_entries_allowed)and(
  exists(select 1 from jsonb_array_elements(p_output->'trades')t where t->>'side'='koop')or exists(select 1 from jsonb_array_elements(p_output->'state'->'pending')o where o->>'side'='koop'))then raise exception'New entries disabled: research-first priority';end if;
 saved:=public.paper_audited_commit_priority_base_v1(p_token,p_output);
 if saved and exists(select 1 from paperlab.strategy_priority where singleton and policy is not null)then update paperlab.capital_runtime set summary=summary||jsonb_build_object('priority_mode','manage_existing_research_first','new_entries_allowed',(select new_entries_allowed from paperlab.strategy_priority where singleton))where singleton;end if;
 return saved;
end$$;
create or replace function public.paper_priority_read(p_owner uuid)returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton)then raise exception'Owner required';end if;
 return jsonb_build_object('policy',(select policy from paperlab.strategy_priority),'started_at',(select started_at from paperlab.strategy_priority),'new_entries_allowed',(select new_entries_allowed from paperlab.strategy_priority),'readiness',(select readiness from paperlab.strategy_priority),
 'next_reviews',(select coalesce(jsonb_agg(jsonb_build_object('symbol',s.symbol,'priority',s.priority,'reasons',s.reasons)order by s.priority desc,s.symbol),'[]')from(select *from paperlab.research_queue order by priority desc,symbol limit 12)s),
 'candidate_status',(select jsonb_build_object('status',status,'final_report_present',final_report is not null)from paperlab.candidate_runtime),
 'note','Bestaande posities en beschermende verkopen blijven actief. De context-kandidaat krijgt onderzoeksvoorrang; hij is niet tot handel toegelaten. Hervatten vereist geverifieerde kosten/data, een getoetst samenhangend protocol en een expliciete nieuwe beheerstap.');
end$$;
create or replace function public.paper_project_read(p_owner uuid,p_symbol text default null)returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$begin
 return public.paper_project_read_priority_base_v1(p_owner,p_symbol)||jsonb_build_object('strategy_priority',public.paper_priority_read(p_owner));
end$$;
revoke all on function public.paper_priority_configure(),public.paper_priority_read(uuid),public.paper_audited_claim_priority_base_v1(uuid,bigint),public.paper_audited_commit_priority_base_v1(uuid,jsonb),public.paper_project_read_priority_base_v1(uuid,text)from public,anon,authenticated,service_role;
revoke all on function public.paper_audited_claim(uuid,bigint),public.paper_audited_commit(uuid,jsonb),public.paper_project_read(uuid,text)from public,anon,authenticated;
grant execute on function public.paper_audited_claim(uuid,bigint),public.paper_audited_commit(uuid,jsonb),public.paper_project_read(uuid,text),public.paper_priority_read(uuid)to service_role;
commit;
