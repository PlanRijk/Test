-- Free event-driven research pilot; never writes trading accounts or approvals.
begin;
create table if not exists paperlab.earnings_companies(symbol text primary key,record jsonb not null check(octet_length(record::text)<22000),next_check timestamptz not null default now(),last_check timestamptz,watch jsonb);
create table if not exists paperlab.earnings_cycles(id text primary key,symbol text not null references paperlab.earnings_companies,cycle_key text not null,created_at timestamptz not null default now(),release_at timestamptz,call_at timestamptz,event jsonb,status text not null default 'awaiting_date',forecast jsonb,frozen_at timestamptz,actual jsonb,prices jsonb,unique(symbol,cycle_key));
create table if not exists paperlab.earnings_tasks(id text primary key,cycle_id text not null references paperlab.earnings_cycles,phase text not null,due_at timestamptz,status text not null,note text,completed_at timestamptz);
create table if not exists paperlab.earnings_runtime(singleton boolean primary key default true check(singleton),enabled boolean not null default true,token uuid,lease_until timestamptz,targets jsonb,month date,estimated_bytes bigint not null default 0,last_attempt timestamptz,last_success timestamptz,rounds bigint not null default 0);
insert into paperlab.earnings_runtime(singleton)values(true)on conflict do nothing;
do $$declare n text;begin foreach n in array array['earnings_companies','earnings_cycles','earnings_tasks','earnings_runtime']loop execute format('alter table paperlab.%I enable row level security',n);execute format('revoke all on paperlab.%I from public,anon,authenticated,service_role',n);end loop;end$$;
create or replace function paperlab.earnings_plan(p_id text)returns void language plpgsql security definer set search_path=pg_catalog,pg_temp as $$declare c paperlab.earnings_cycles;phase text;offset_days int;due timestamptz;begin
 select *into strict c from paperlab.earnings_cycles where id=p_id;
 for phase,offset_days in select *from(values('prepare_21',-21),('review_7',-7),('review_2',-2),('freeze',-1),('results_1',1),('call_review_7',7),('price_review_28',28))v(phase,offset_days)loop
  due:=case when phase='freeze'then c.release_at-interval'24 hours'else(((c.release_at at time zone'Europe/Brussels')::date+offset_days)+time'08:05')at time zone'Europe/Brussels'end;
  insert into paperlab.earnings_tasks values(c.id||':'||phase,c.id,phase,due,case when due is null then'awaiting_date'when due<c.created_at then'missed_before_pilot'else'pending'end,null,null)
  on conflict(id)do update set due_at=excluded.due_at,status=case when paperlab.earnings_tasks.completed_at is not null then paperlab.earnings_tasks.status else excluded.status end;
 end loop;
 insert into paperlab.earnings_tasks values(c.id||':initial',c.id,'initial',c.created_at,'pending','Initiële dossiercontrole; geen historische voorbereiding achteraf verzinnen.',null)on conflict do nothing;
end$$;
create or replace function public.paper_earnings_event_save(p_symbol text,p_event jsonb)returns text language plpgsql security definer set search_path=pg_catalog,pg_temp as $$declare i text;c paperlab.earnings_cycles;host text;begin
 if not exists(select 1 from paperlab.earnings_companies where symbol=p_symbol)or length(p_event->>'cycle_key')not between 3 and 60 or coalesce(p_event->>'source_url','')not like'https://%'or length(coalesce(p_event->>'evidence',''))<40 or(p_event->>'release_at')::timestamptz is null then raise exception'Official dated event evidence required';end if;
 i:='ep-'||p_symbol||'-'||encode(sha256(convert_to(p_event->>'cycle_key','UTF8')),'hex');
 select *into c from paperlab.earnings_cycles where symbol=p_symbol and cycle_key=p_event->>'cycle_key'for update;
 if found then
  if c.frozen_at is not null and c.release_at is distinct from(p_event->>'release_at')::timestamptz then raise exception'Frozen calendar: create explicit revised cycle';end if;
  if c.event=p_event then return c.id;end if;
  update paperlab.earnings_cycles set release_at=(p_event->>'release_at')::timestamptz,call_at=(p_event->>'call_at')::timestamptz,event=p_event,status='scheduled'where id=c.id;i:=c.id;
 else
  insert into paperlab.earnings_cycles(id,symbol,cycle_key,release_at,call_at,event,status)values(i,p_symbol,p_event->>'cycle_key',(p_event->>'release_at')::timestamptz,(p_event->>'call_at')::timestamptz,p_event,'scheduled');
  update paperlab.earnings_cycles set status='superseded_unconfirmed'where symbol=p_symbol and release_at is null;
 end if;
 perform paperlab.earnings_plan(i);update paperlab.earnings_companies set next_check=least(next_check,now())where symbol=p_symbol;return i;
end$$;
create or replace function public.paper_earnings_configure(p_rows jsonb)returns int language plpgsql security definer set search_path=pg_catalog,pg_temp as $$declare x jsonb;i text;n int:=0;begin
 if jsonb_typeof(p_rows)is distinct from'array'or jsonb_array_length(p_rows)<>10 or(select count(distinct value->>'symbol')from jsonb_array_elements(p_rows))<>10 then raise exception'Exactly ten companies required';end if;
 for x in select value from jsonb_array_elements(p_rows)loop
  if not exists(select 1 from paperlab.company_coverage_runtime rt,jsonb_array_elements(rt.catalogue)c where c->>'symbol'=x->>'symbol')or jsonb_array_length(x->'source_refs')<3 or coalesce(x->>'calendar_url','')not like'https://%'or exists(select 1 from jsonb_array_elements(x->'source_refs')s where coalesce(s->>'sha256','')!~'^[a-f0-9]{64}$'or coalesce(s->>'url','')not like'https://%'or(s->>'known_at')::timestamptz>now())then raise exception'Existing official source evidence required';end if;
  insert into paperlab.earnings_companies(symbol,record)values(x->>'symbol',x-'event')on conflict do nothing;
  if x->'event'is not null and x->'event'<>'null'::jsonb then perform public.paper_earnings_event_save(x->>'symbol',x->'event');
  elsif not exists(select 1 from paperlab.earnings_cycles where symbol=x->>'symbol')then i:='ep-'||(x->>'symbol')||'-next-unconfirmed';insert into paperlab.earnings_cycles(id,symbol,cycle_key)values(i,x->>'symbol','next-unconfirmed');perform paperlab.earnings_plan(i);end if;n:=n+1;
 end loop;
 if(select count(*)from paperlab.earnings_companies)<>10 then raise exception'Pilot roster already differs';end if;return n;
end$$;
create or replace function public.paper_earnings_claim()returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$declare r paperlab.earnings_runtime;t uuid;rows jsonb;charge bigint;m date:=date_trunc('month',now()at time zone'UTC')::date;begin
 select *into r from paperlab.earnings_runtime where singleton for update;
 if not r.enabled or r.lease_until>now()or r.last_attempt>now()-interval'1 hour'then return null;end if;
 select coalesce(jsonb_agg(jsonb_build_object('symbol',symbol,'calendar_url',record->>'calendar_url','cycle_id',(select id from paperlab.earnings_cycles cy where cy.symbol=z.symbol and cy.release_at between now()-interval'60 days'and now()order by cy.release_at desc limit 1),'release_at',(select release_at from paperlab.earnings_cycles cy where cy.symbol=z.symbol and cy.release_at between now()-interval'60 days'and now()order by cy.release_at desc limit 1))),'[]')into rows from(select *from paperlab.earnings_companies where next_check<=now()order by next_check,symbol limit 10)z;
 if jsonb_array_length(rows)=0 then return null;end if;charge:=1800000*jsonb_array_length(rows);
 insert into paperlab.free_usage(month)values(m)on conflict do nothing;perform 1 from paperlab.free_usage where month=m for update;
 if r.month is distinct from m then r.estimated_bytes:=0;end if;
 if r.estimated_bytes+charge>160000000 or(select estimated_worker_egress_bytes+charge from paperlab.free_usage where month=m)>paperlab.traffic_limit('soft')or pg_database_size(current_database())>100000000 then return null;end if;
 t:=gen_random_uuid();update paperlab.earnings_runtime set month=m,estimated_bytes=r.estimated_bytes+charge,token=t,targets=rows,lease_until=now()+interval'120 seconds',last_attempt=now()where singleton;
 update paperlab.free_usage set estimated_worker_egress_bytes=estimated_worker_egress_bytes+charge where month=m;
 return jsonb_build_object('token',t,'targets',rows,'max_page_bytes',400000,'paid_calls',false);
end$$;
create or replace function public.paper_earnings_commit(p_token uuid,p_rows jsonb)returns boolean language plpgsql security definer set search_path=pg_catalog,pg_temp as $$declare r paperlab.earnings_runtime;x jsonb;near_event boolean;begin
 select *into r from paperlab.earnings_runtime where singleton and token=p_token and lease_until>now()for update;if not found then return false;end if;
 if jsonb_typeof(p_rows)is distinct from'array'or jsonb_array_length(p_rows)<>jsonb_array_length(r.targets)or(select count(distinct value->>'symbol')from jsonb_array_elements(p_rows))<>jsonb_array_length(p_rows)then raise exception'Expected bounded target results';end if;
 for x in select value from jsonb_array_elements(p_rows)loop
  if octet_length(x::text)>14000 or not exists(select 1 from jsonb_array_elements(r.targets)t where t->>'symbol'=x->>'symbol')or coalesce(x->>'status','')not in('observed','partial','unavailable')then raise exception'Invalid earnings source result';end if;
  if x->'prices'->>'status'in('observed','corporate_action_review')then
   if x->'prices'->>'currency'is distinct from'USD'or jsonb_typeof(x->'prices'->'rows')is distinct from'array'or jsonb_array_length(x->'prices'->'rows')>95 or coalesce(x->'prices'->>'sha256','')!~'^[a-f0-9]{64}$'or exists(select 1 from jsonb_array_elements(x->'prices'->'rows')b where(b->>'day')::date>=(now()at time zone'America/New_York')::date or jsonb_typeof(b->'close')is distinct from'number'or((b->>'close')::float8 between .0000001 and 1e12)is not true)or(x->'prices'->>'known_at')::timestamptz>now()+interval'5 seconds'then raise exception'Invalid completed price series';end if;
   update paperlab.earnings_cycles set prices=x->'prices'where id=(select t->>'cycle_id'from jsonb_array_elements(r.targets)t where t->>'symbol'=x->>'symbol');
  end if;
  select exists(select 1 from paperlab.earnings_cycles where symbol=x->>'symbol'and release_at between now()-interval'7 days'and now()+interval'21 days')into near_event;
  update paperlab.earnings_companies set last_check=now(),next_check=(((now()at time zone'UTC')::date+case when near_event then 1 else 7 end)+time'07:04')at time zone'UTC',watch=x||jsonb_build_object('calendar_needs_confirmation',not exists(select 1 from paperlab.earnings_cycles where symbol=x->>'symbol'and release_at>now()),'source_fingerprints_changed',coalesce(watch->'sources','[]')is distinct from x->'sources')where symbol=x->>'symbol';
 end loop;
 update paperlab.earnings_runtime set token=null,lease_until=null,last_success=now(),rounds=rounds+1 where singleton;return true;
end$$;
create or replace function public.paper_earnings_freeze(p_owner uuid,p_cycle text,p_forecast jsonb)returns boolean language plpgsql security definer set search_path=pg_catalog,pg_temp as $$declare c paperlab.earnings_cycles;company jsonb;x jsonb;k text;lo float8;v float8;hi float8;begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton)then raise exception'Owner required';end if;
 select *into c from paperlab.earnings_cycles where id=p_cycle for update;
 if not found or c.release_at is null or now()>=c.release_at-interval'24 hours'or c.frozen_at is not null then raise exception'Forecast requires confirmed date, before cutoff, and is immutable';end if;
 if octet_length(p_forecast::text)>7000 or coalesce(p_forecast->>'direction','')not in('up','down','flat','abstain')or length(coalesce(p_forecast->>'rationale',''))<80 or length(coalesce(p_forecast->>'counterarguments',''))<40 or coalesce(p_forecast->>'eps_basis','')not in('GAAP','non-GAAP')or coalesce(p_forecast->>'currency','')<>'USD'or coalesce(p_forecast->>'revenue_unit','')<>'million'or jsonb_typeof(p_forecast->'sources')is distinct from'array'or coalesce(jsonb_array_length(p_forecast->'sources'),0)not between 1 and 5 then raise exception'Complete sourced forecast required';end if;
 select record into company from paperlab.earnings_companies where symbol=c.symbol;
 for x in select value from jsonb_array_elements(p_forecast->'sources')loop
  if not exists(select 1 from jsonb_array_elements(company->'source_refs')s where s->>'url'=x->>'url'and s->>'sha256'=x->>'sha256'and(s->>'known_at')::timestamptz<=now())then raise exception'Known archived source required';end if;
 end loop;
 foreach k in array array['revenue','eps']loop
  x:=p_forecast->k;
  if exists(select 1 from unnest(array['low','base','high'])key where jsonb_typeof(x->key)is distinct from'number')then raise exception'Numeric scenario ranges required';end if;
  lo:=(x->>'low')::float8;v:=(x->>'base')::float8;hi:=(x->>'high')::float8;
  if not(lo<=v and v<=hi and abs(lo)<1e12 and abs(hi)<1e12)or(k='revenue'and lo<=0)then raise exception'Ordered finite scenario ranges required';end if;
 end loop;
 -- No free consensus feed is connected. Unknown stays unknown, never own forecast relabelled consensus.
 update paperlab.earnings_cycles set forecast=(p_forecast-'consensus')||'{"consensus":{"status":"unknown"},"version":"earnings-forecast-v1","trade_approval":false}'::jsonb,frozen_at=now(),status='forecast_frozen'where id=p_cycle;
 update paperlab.earnings_tasks set status='completed',completed_at=now(),note='Verwachting prospectief en onwijzigbaar vastgelegd.'where id=p_cycle||':freeze';return true;
end$$;
create or replace function public.paper_earnings_actual(p_owner uuid,p_cycle text,p_result jsonb)returns boolean language plpgsql security definer set search_path=pg_catalog,pg_temp as $$declare c paperlab.earnings_cycles;begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton)then raise exception'Owner required';end if;
 select *into c from paperlab.earnings_cycles where id=p_cycle for update;
 if not found or c.release_at is null or now()<c.release_at or c.actual is not null then raise exception'Actual result must follow release and cannot be overwritten';end if;
 if jsonb_typeof(p_result->'revenue_million')is distinct from'number'or jsonb_typeof(p_result->'eps')is distinct from'number'or coalesce(p_result->>'eps_basis','')not in('GAAP','non-GAAP')or p_result->>'currency'is distinct from'USD'or coalesce(p_result->>'source_url','')not like'https://%'or length(coalesce(p_result->>'guidance_review',''))<80 or length(coalesce(p_result->>'call_review',''))<80 or coalesce(p_result->>'source_sha256','')!~'^[a-f0-9]{64}$'then raise exception'Sourced actuals, guidance and call review required';end if;
 update paperlab.earnings_cycles set actual=p_result||jsonb_build_object('recorded_at',now(),'no_consensus_surprise_computed',true),status=case when c.frozen_at is null then'actual_without_prediction'else'actual_recorded'end where id=p_cycle;return true;
end$$;
create or replace function paperlab.earnings_price_assessment(p_id text)returns jsonb language plpgsql stable security definer set search_path=pg_catalog,pg_temp as $$declare c paperlab.earnings_cycles;b jsonb;last jsonb;n int;r float8;out jsonb:='{}';direction text;begin
 select *into c from paperlab.earnings_cycles where id=p_id;
 if c.frozen_at is null or c.frozen_at>c.release_at-interval'24 hours'or c.prices->>'status'is distinct from'observed'then return jsonb_build_object('status','waiting_frozen_forecast_and_valid_prices');end if;
 select value into b from jsonb_array_elements(c.prices->'rows')where((value->>'day')::date+time'16:00')at time zone'America/New_York'<=c.release_at order by value->>'day'desc limit 1;
 if b is null then return jsonb_build_object('status','baseline_missing');end if;
 foreach n in array array[1,5,20]loop
  select value into last from jsonb_array_elements(c.prices->'rows')where((value->>'day')::date+time'16:00')at time zone'America/New_York'>c.release_at order by value->>'day'offset(n-1)limit 1;
  if last is not null then r:=(last->>'close')::float8/(b->>'close')::float8-1;direction:=case when r>.005 then'up'when r<-.005 then'down'else'flat'end;
   out:=out||jsonb_build_object(n::text,jsonb_build_object('return_percent',100*r,'last_day',last->>'day','realized_direction',direction,'predicted_direction',c.forecast->>'direction','correct',case when c.forecast->>'direction'='abstain'then null else direction=c.forecast->>'direction'end));end if;
 end loop;
 return jsonb_build_object('status','observed','baseline_day',b->>'day','outcomes',out,'primary_sessions',1,'flat_threshold_fraction',.005,'fees_dividends_excluded',true,'not_trading_profit',true);
end$$;
revoke all on function paperlab.earnings_price_assessment(text)from public,anon,authenticated,service_role;
create or replace function public.paper_earnings_review(p_owner uuid,p_task text,p_note text,p_source_url text)returns boolean language plpgsql security definer set search_path=pg_catalog,pg_temp as $$declare t paperlab.earnings_tasks;c paperlab.earnings_cycles;r paperlab.earnings_companies;begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton)then raise exception'Owner required';end if;
 select *into t from paperlab.earnings_tasks where id=p_task for update;if not found or t.status<>'pending'or t.phase='freeze'or t.due_at is null or t.due_at>now()then raise exception'Control not due or already recorded';end if;
 select *into c from paperlab.earnings_cycles where id=t.cycle_id;
 if t.phase in('prepare_21','review_7','review_2')and now()>=c.release_at then raise exception'No retrospective pre-release review';end if;
 select *into r from paperlab.earnings_companies where symbol=c.symbol;
 if length(coalesce(p_note,''))not between 80 and 5000 or not(exists(select 1 from jsonb_array_elements(r.record->'source_refs')s where s->>'url'=p_source_url)or exists(select 1 from jsonb_array_elements(r.watch->'sources')s,jsonb_array_elements(s->'refs')ref where ref->>'url'=p_source_url))then raise exception'Substantive note and known official source required';end if;
 update paperlab.earnings_tasks set note=p_note||E'\nBron: '||p_source_url,status='completed',completed_at=now()where id=p_task;return true;
end$$;
create or replace function public.paper_earnings_read(p_owner uuid,p_symbol text default null)returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton)then raise exception'Owner required';end if;
 return jsonb_build_object('version','earnings-pilot-v1','paid_calls',false,'automatic_qualitative',false,'trade_approval',false,'schedule','Kalender/bronnen wekelijks; vanaf 21 dagen vóór tot 7 dagen na bevestigde cijfers dagelijks een beperkte broncontrole. Uitvoering 07:05 UTC (08:05 Belgische wintertijd, 09:05 zomertijd). Inhoudelijke controle in werksessies.',
 'runtime',(select to_jsonb(r)-'token'-'lease_until'-'targets'from paperlab.earnings_runtime r),
 'companies',(select coalesce(jsonb_agg(to_jsonb(c)order by c.symbol),'[]')from paperlab.earnings_companies c where p_symbol is null or c.symbol=p_symbol),
 'cycles',(select coalesce(jsonb_agg(to_jsonb(c)||jsonb_build_object('cutoff_at',release_at-interval'24 hours','price_assessment',paperlab.earnings_price_assessment(c.id),'assessment',case when actual is null or forecast is null then null else jsonb_build_object('revenue_in_range',(actual->>'revenue_million')::float8 between(forecast->'revenue'->>'low')::float8 and(forecast->'revenue'->>'high')::float8,'eps_comparable',actual->>'eps_basis'=forecast->>'eps_basis','eps_in_range',case when actual->>'eps_basis'=forecast->>'eps_basis'then(actual->>'eps')::float8 between(forecast->'eps'->>'low')::float8 and(forecast->'eps'->>'high')::float8 else null end,'stock_direction_evaluated',false,'consensus_surprise_available',false)end)order by created_at desc),'[]')from paperlab.earnings_cycles c where(p_symbol is null or symbol=p_symbol)and status<>'superseded_unconfirmed'),
 'tasks',(select coalesce(jsonb_agg(to_jsonb(t)||jsonb_build_object('symbol',c.symbol,'overdue',t.status='pending'and t.due_at<now())order by t.due_at nulls last,t.id),'[]')from paperlab.earnings_tasks t join paperlab.earnings_cycles c on c.id=t.cycle_id where(p_symbol is null or c.symbol=p_symbol)and c.status<>'superseded_unconfirmed'),
 'limitations','Geen analistenconsensusfeed, automatische tekstinterpretatie of calltranscriptgarantie. Broncontrole is geen inhoudelijke goedkeuring. Koersrichting vereist aparte waarnemingen; juiste cijfers voorspellen bewijst geen juist koerssignaal.');
end$$;
-- Owner-gated existing research API gains the pilot without altering trading endpoints.
do $$begin if to_regprocedure('public.paper_project_read_earnings_base_v1(uuid,text)')is null then alter function public.paper_project_read(uuid,text)rename to paper_project_read_earnings_base_v1;end if;end$$;
create or replace function public.paper_project_read(p_owner uuid,p_symbol text default null)returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$begin return public.paper_project_read_earnings_base_v1(p_owner,p_symbol)||jsonb_build_object('earnings_pilot',public.paper_earnings_read(p_owner,p_symbol));end$$;
revoke all on function paperlab.earnings_plan(text),public.paper_earnings_event_save(text,jsonb),public.paper_earnings_configure(jsonb),public.paper_earnings_claim(),public.paper_earnings_commit(uuid,jsonb),public.paper_earnings_freeze(uuid,text,jsonb),public.paper_earnings_actual(uuid,text,jsonb),public.paper_earnings_read(uuid,text),public.paper_earnings_review(uuid,text,text,text),public.paper_project_read_earnings_base_v1(uuid,text),public.paper_project_read(uuid,text)from public,anon,authenticated,service_role;
grant execute on function public.paper_earnings_claim(),public.paper_earnings_commit(uuid,jsonb),public.paper_earnings_freeze(uuid,text,jsonb),public.paper_earnings_actual(uuid,text,jsonb),public.paper_earnings_read(uuid,text),public.paper_earnings_review(uuid,text,text,text),public.paper_project_read(uuid,text)to service_role;
commit;
