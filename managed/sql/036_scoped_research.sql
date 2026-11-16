-- Scoped primary-source assessments. These never grant trading eligibility.
begin;
create table if not exists paperlab.scoped_research (
 id text primary key, symbol text not null, recorded_at timestamptz not null default now(),
 scope text not null check(scope in ('earnings_preview','position_risk_triage')),
 next_review_at timestamptz not null, record jsonb not null check(octet_length(record::text)<=30000));
alter table paperlab.scoped_research enable row level security;
revoke all on paperlab.scoped_research from public,anon,authenticated,service_role;
create or replace function public.paper_scoped_research_save(p_owner uuid,p_record jsonb)returns text language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare i text;s jsonb;begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton)then raise exception 'Owner required';end if;
 if p_record->>'scope'not in('earnings_preview','position_risk_triage')or coalesce(length(p_record->>'conclusion'),0)<80 or p_record->'trade_approval'is distinct from'false'::jsonb or p_record->'full_company_analysis'is distinct from'false'::jsonb or jsonb_typeof(p_record->'sections')is distinct from'array'or jsonb_array_length(p_record->'sections')<5 or jsonb_typeof(p_record->'sources')is distinct from'array'or jsonb_array_length(p_record->'sources')not between 1 and 12 or jsonb_typeof(p_record->'limitations')is distinct from'array'or octet_length(p_record::text)>30000 then raise exception 'Complete bounded scoped assessment required';end if;
 if not exists(select 1 from paperlab.company_research where symbol=p_record->>'symbol')or(p_record->>'next_review_at')::timestamptz<=now()then raise exception 'Known company and future review required';end if;
 for s in select value from jsonb_array_elements(p_record->'sources')loop
  if coalesce(s->>'url','')not like'https://%'or coalesce(s->>'sha256','')!~'^[a-f0-9]{64}$'or(s->>'known_at')is null or(s->>'known_at')::timestamptz>now()then raise exception 'Observed source proof required';end if;
 end loop;
 for s in select value from jsonb_array_elements(p_record->'sections')loop
  if coalesce(length(s->>'finding'),0)<40 or coalesce(length(s->>'interpretation'),0)<40 or coalesce(length(s->>'counterargument'),0)<20 or jsonb_typeof(s->'source_ids')is distinct from'array'or jsonb_array_length(s->'source_ids')<1 or exists(select 1 from jsonb_array_elements_text(s->'source_ids')r where not exists(select 1 from jsonb_array_elements(p_record->'sources')src where src->>'id'=r))then raise exception 'Sourced findings and counterarguments required';end if;
 end loop;
 i:=encode(sha256(convert_to(p_record::text,'UTF8')),'hex');
 if pg_database_size(current_database())>100000000 or pg_total_relation_size('paperlab.scoped_research')>5000000 then raise exception 'Research storage budget';end if;
 insert into paperlab.scoped_research values(i,p_record->>'symbol',now(),p_record->>'scope',(p_record->>'next_review_at')::timestamptz,p_record)on conflict do nothing;
 -- Immutable versions; retain eight per symbol. Frozen earnings forecasts are separate and never pruned here.
 delete from paperlab.scoped_research where symbol=p_record->>'symbol'and id in(select id from paperlab.scoped_research where symbol=p_record->>'symbol'order by recorded_at desc,id desc offset 8);
 return i;
end$$;
do $$begin if to_regprocedure('public.paper_project_refresh_scoped_base_v1()')is null then alter function public.paper_project_refresh()rename to paper_project_refresh_scoped_base_v1;end if;end$$;
create or replace function public.paper_project_refresh()returns void language plpgsql security definer set search_path=pg_catalog,pg_temp as $$begin
 perform public.paper_project_refresh_scoped_base_v1();
 -- Recomputed from the original priorities on every run: no accumulating boosts.
 update paperlab.research_queue q set priority=q.priority+case when exists(select 1 from paperlab.earnings_cycles c where c.symbol=q.symbol and c.release_at>now()-interval'7 days'and c.release_at<now()+interval'3 days'and c.status<>'superseded_unconfirmed')then 300 when exists(select 1 from paperlab.earnings_cycles c where c.symbol=q.symbol and c.release_at>now()-interval'7 days'and c.release_at<now()+interval'21 days'and c.status<>'superseded_unconfirmed')then 120 else 0 end,
 reasons=q.reasons||case when exists(select 1 from paperlab.earnings_cycles c where c.symbol=q.symbol and c.release_at>now()-interval'7 days'and c.release_at<now()+interval'21 days'and c.status<>'superseded_unconfirmed')then '["earnings_review_priority"]'::jsonb else '[]'::jsonb end;
end$$;
do $$begin if to_regprocedure('public.paper_project_read_scoped_base_v1(uuid,text)')is null then alter function public.paper_project_read(uuid,text)rename to paper_project_read_scoped_base_v1;end if;end$$;
create or replace function public.paper_project_read(p_owner uuid,p_symbol text default null)returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton)then raise exception 'Owner required';end if;
 return public.paper_project_read_scoped_base_v1(p_owner,p_symbol)||jsonb_build_object('scoped_research',jsonb_build_object(
 'note','Kwartaalvoorbereiding en positierisico zijn afgebakende beoordelingen, geen volledige bedrijfswaardering of koopgoedkeuring. Automatische controles verzamelen en signaleren; inhoudelijke herbeoordeling blijft apart werk.',
 'reviews',(select coalesce(jsonb_agg(to_jsonb(r)||jsonb_build_object('review_due',r.next_review_at<=now(),'source_changed',exists(select 1 from paperlab.publication_watch w where w.symbol=r.symbol and w.checked_at>r.recorded_at and(coalesce((w.record->>'changed')::boolean,false)or coalesce((w.record->>'unreviewed_official_disclosure')::boolean,false))))order by r.recorded_at desc),'[]')from(select distinct on(symbol,scope)*from paperlab.scoped_research where p_symbol is null or symbol=p_symbol order by symbol,scope,recorded_at desc,id desc)r),
 'priority_queue',(select coalesce(jsonb_agg(to_jsonb(q)order by priority desc,due_at,symbol),'[]')from(select symbol,priority,due_at,reasons from paperlab.research_queue where p_symbol is null or symbol=p_symbol order by priority desc,due_at,symbol limit 15)q)));
end$$;
revoke all on function public.paper_scoped_research_save(uuid,jsonb),public.paper_project_refresh(),public.paper_project_refresh_scoped_base_v1(),public.paper_project_read_scoped_base_v1(uuid,text),public.paper_project_read(uuid,text)from public,anon,authenticated,service_role;
grant execute on function public.paper_scoped_research_save(uuid,jsonb),public.paper_project_read(uuid,text)to service_role;
commit;
