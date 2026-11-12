-- Daily evidence triage, bounded research history and a prospective reference.
-- No trading/model rules, cost assumptions or portfolio balances are changed.
begin;
create table if not exists paperlab.research_history(
 symbol text not null,hash text not null,at timestamptz not null,record jsonb not null check(octet_length(record::text)<=24000),primary key(symbol,hash));
create table if not exists paperlab.research_queue(symbol text primary key,checked_at timestamptz not null,due_at timestamptz not null,priority integer not null,reasons jsonb not null,financial_fingerprint text);
create table if not exists paperlab.project_followup(singleton boolean primary key default true check(singleton),enabled boolean not null default true,started_at timestamptz not null default now(),last_refresh timestamptz,last_attempt timestamptz,last_success timestamptz,token uuid,lease_until timestamptz,status text not null default 'waiting',diagnostics jsonb not null default '{}',benchmark jsonb not null default '{}',budget_month date,budget_bytes bigint not null default 0,attempt_day date,attempts integer not null default 0,broker_tax jsonb not null default '{"broker_verified":false,"tax_verified":false,"provider_meter_verified":false}');
insert into paperlab.project_followup(singleton)values(true)on conflict do nothing;
create table if not exists paperlab.benchmark_observations(day date primary key,observed_at timestamptz not null,record jsonb not null check(octet_length(record::text)<=6000));
create table if not exists paperlab.archive_manifest(id text primary key,created_at timestamptz not null default now(),record jsonb not null check(octet_length(record::text)<=6000));
do $$declare t text;begin foreach t in array array['research_history','research_queue','project_followup','benchmark_observations','archive_manifest']loop execute format('alter table paperlab.%I enable row level security',t);execute format('revoke all on paperlab.%I from public,anon,authenticated,service_role',t);end loop;end$$;
create or replace function paperlab.retain_research_version()returns trigger language plpgsql security definer set search_path=pg_catalog,pg_temp as $$begin
 if exists(select 1 from paperlab.company_research where symbol=new.symbol and checked_at>=new.checked_at)then return new;end if;
 if pg_database_size(current_database())>=100000000 or pg_total_relation_size('paperlab.research_history')>=8000000 then raise exception'Research history budget';end if;
 insert into paperlab.research_history values(new.symbol,encode(sha256(convert_to(new.record::text,'UTF8')),'hex'),new.checked_at,new.record)on conflict do nothing;
 delete from paperlab.research_history where symbol=new.symbol and(hash in(select hash from paperlab.research_history where symbol=new.symbol order by at desc,hash desc offset 8)or at<now()-interval'365 days');
 return new;
end$$;
drop trigger if exists retain_research_version on paperlab.company_research;
create trigger retain_research_version before insert or update on paperlab.company_research for each row execute function paperlab.retain_research_version();
insert into paperlab.research_history select symbol,encode(sha256(convert_to(record::text,'UTF8')),'hex'),checked_at,record from paperlab.company_research on conflict do nothing;
create or replace function public.paper_project_refresh()returns void language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare c jsonb;s text;r jsonb;rv timestamptz;why jsonb;p integer;due timestamptz;stats jsonb;publication_alert boolean;begin
 for c in select value from paperlab.company_coverage_runtime rt,jsonb_array_elements(rt.catalogue)loop
  s:=c->>'symbol';select record into r from paperlab.company_research where symbol=s;
  select max(reviewed_at)into rv from paperlab.company_reviews where symbol=s;
  why:='[]';p:=10;due:=coalesce(rv,(r->>'checked_at')::timestamptz,now())+interval'7 days';
  if rv is null then why:=why||'"qualitative_review_missing"'::jsonb;p:=p+30;due:=now();elsif rv<now()-interval'7 days' then why:=why||'"qualitative_review_expired"'::jsonb;p:=p+25;end if;
  if r is null or(r->>'checked_at')::timestamptz<now()-interval'7 days'then why:=why||'"research_missing_or_expired"'::jsonb;p:=p+20;end if;
  if exists(select 1 from paperlab.company_coverage v where v.symbol=s and v.record->>'source_hash'is distinct from r->>'financial_source_hash')then why:=why||'"financial_source_changed"'::jsonb;p:=p+30;due:=now();end if;
  if exists(select 1 from paperlab.company_coverage v where v.symbol=s and v.record->>'secondary_status'='source_unavailable')then why:=why||'"financial_source_unavailable"'::jsonb;p:=p+15;end if;
  if exists(select 1 from paperlab.capital_runtime where state->'positions'?s)then why:=why||'"open_position"'::jsonb;p:=p+50;end if;
  if r is not null and exists(select 1 from jsonb_array_elements(r->'sources')x where x->>'read_scope'like'PDF text, first %'and substring(x->>'read_scope'from'first ([0-9]+)') is distinct from substring(x->>'read_scope'from'of ([0-9]+)'))then why:=why||'"partial_pdf_scope"'::jsonb;end if;
  if to_regclass('paperlab.publication_watch')is not null then
   execute 'select exists(select 1 from paperlab.publication_watch where symbol=$1 and(coalesce((record->>''changed'')::boolean,false)or coalesce((record->>''unreviewed_official_disclosure'')::boolean,false)))'into publication_alert using s;
   if publication_alert then why:=why||'"official_publication_changed"'::jsonb;p:=p+40;due:=now();end if;
  end if;
  insert into paperlab.research_queue values(s,now(),due,p,why,(select record->>'financial_fingerprint'from paperlab.company_coverage where symbol=s))on conflict(symbol)do update set checked_at=excluded.checked_at,due_at=excluded.due_at,priority=excluded.priority,reasons=excluded.reasons,financial_fingerprint=excluded.financial_fingerprint;
 end loop;
 stats:=jsonb_build_object('at',now(),'queue_total',(select count(*)from paperlab.research_queue),'due',(select count(*)from paperlab.research_queue where due_at<=now()),'missing_qualitative',(select count(*)from paperlab.research_queue where reasons?'qualitative_review_missing'),'source_failures',(select count(*)from paperlab.company_coverage where record->>'secondary_status'='source_unavailable'),
 'last_market_update',(select state->>'last_update'from paperlab.portfolio),'fresh_quotes_at_last_check',(select state->'data_info'->'fresh_symbols'from paperlab.portfolio),'market_attention',(select state->>'error'from paperlab.portfolio),'database_bytes',pg_database_size(current_database()),'app_estimated_month_bytes',(select estimated_worker_egress_bytes from paperlab.free_usage where month=date_trunc('month',now()at time zone'UTC')::date),
 'recent_scheduler_failures',(select count(*)from cron.job_run_details d join cron.job j on d.jobid=j.jobid where j.jobname like'paperlab-%'and d.start_time>now()-interval'1 day'and d.status='failed'),
 'feed_note','Indicatieve vijfminutenuitvoering; geen realtime brokerstop of volledige marktfeed. Een geslaagde cronaanroep bewijst geen geslaagde bronverwerking.');
 update paperlab.project_followup set last_refresh=now(),diagnostics=stats where singleton;
end$$;
create or replace function public.paper_project_claim()returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare r paperlab.project_followup;d date:=(now()at time zone'UTC')::date;m date:=(date_trunc('month',now()at time zone'UTC'))::date;t uuid;begin
 select *into r from paperlab.project_followup where singleton for update;
 if not r.enabled or r.lease_until>now()or(r.attempt_day=d and r.attempts>=2)then return null;end if;
 perform public.paper_project_refresh();
 if r.budget_month is distinct from m then r.budget_bytes:=0;end if;
 insert into paperlab.free_usage(month)values(m)on conflict do nothing;
 perform 1 from paperlab.free_usage where month=m for update;
 if r.budget_bytes+200000>10000000 or(select estimated_worker_egress_bytes+200000 from paperlab.free_usage where month=m)>paperlab.traffic_limit('soft')or pg_database_size(current_database())>100000000 then update paperlab.project_followup set status='budget_guard'where singleton;return null;end if;
 update paperlab.free_usage set estimated_worker_egress_bytes=estimated_worker_egress_bytes+200000 where month=m;
 t:=gen_random_uuid();update paperlab.project_followup set token=t,lease_until=now()+interval'90 seconds',last_attempt=now(),budget_month=m,budget_bytes=r.budget_bytes+200000,attempt_day=d,attempts=case when r.attempt_day=d then r.attempts+1 else 1 end,status='checking'where singleton;
 return jsonb_build_object('token',t,'started_at',r.started_at,'benchmark',r.benchmark,'symbol','VWCE.DE','currency','EUR','max_bytes',120000);
end$$;
create or replace function public.paper_project_commit(p_token uuid,p_result jsonb)returns boolean language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare r paperlab.project_followup;b jsonb;x jsonb;price double precision;v double precision;baseline double precision;firstday date;begin
 select *into r from paperlab.project_followup where singleton and token=p_token and lease_until>now()for update;if not found then return false;end if;
 if octet_length(p_result::text)>6000 or p_result->>'symbol'is distinct from'VWCE.DE'or p_result->>'currency'is distinct from'EUR'or p_result->>'status'not in('observed','source_unavailable','waiting_future_session','corporate_action_review')then raise exception'Invalid reference evidence';end if;
 b:=r.benchmark;
 if p_result->>'status'='observed'then
  if(p_result->>'day')::date<= (r.started_at at time zone'Europe/Brussels')::date or(p_result->>'day')::date>=(now()at time zone'Europe/Berlin')::date or(p_result->>'day')::date<(now()at time zone'Europe/Berlin')::date-4 or(p_result->>'close')::double precision<=0 or(p_result->>'known_at')::timestamptz>now()+interval'5 seconds'then raise exception'Prospective completed reference session required';end if;
  price:=(p_result->>'close')::double precision;if price='NaN'::double precision or price='Infinity'::double precision then raise exception'Invalid price';end if;
  if not(b?'entry_price')then b:=jsonb_build_object('symbol','VWCE.DE','currency','EUR','entry_price',price,'entry_day',p_result->>'day','entry_known_at',p_result->>'known_at','account_baseline',(select summary->'equity_eur'from paperlab.capital_runtime),'account_baseline_at',(select summary->'checked_at'from paperlab.capital_runtime),'initial_eur',10000,'peak_eur',10000);end if;
  v:=10000*price/(b->>'entry_price')::double precision;baseline:=(b->>'account_baseline')::double precision;
  x:=p_result||jsonb_build_object('reference_value_eur',v,'reference_return_percent',100*(v/10000-1),'account_equity_eur',(select summary->'equity_eur'from paperlab.capital_runtime),'account_observed_at',(select summary->'checked_at'from paperlab.capital_runtime),'account_return_since_baseline_percent',case when baseline>0 then 100*((select(summary->>'equity_eur')::double precision from paperlab.capital_runtime)/baseline-1)else null end,'reference_before_broker_costs',true,'timestamps_aligned',false,'not_strategy_validation',true);
  insert into paperlab.benchmark_observations values((p_result->>'day')::date,now(),x)on conflict(day)do nothing;
  if b->>'last_day'is null or(p_result->>'day')::date>(b->>'last_day')::date then b:=b||jsonb_build_object('last_day',p_result->>'day','latest',x,'peak_eur',greatest(coalesce((b->>'peak_eur')::double precision,10000),v));end if;
 end if;
 update paperlab.project_followup set token=null,lease_until=null,last_success=case when p_result->>'status'in('observed','waiting_future_session')then now()else last_success end,status=p_result->>'status',benchmark=b||jsonb_build_object('source_status',p_result->>'status','last_checked_at',now())where singleton;
 delete from paperlab.benchmark_observations where day in(select day from paperlab.benchmark_observations order by day desc offset 400);
 return true;
end$$;
create or replace function public.paper_project_read(p_owner uuid,p_symbol text default null)returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton)then raise exception'Owner required';end if;
 return jsonb_build_object('runtime',(select to_jsonb(r)-'token'-'lease_until'-'backup_token'-'backup_until'-'backup_info'-'watch_token'-'watch_until'from paperlab.project_followup r),
 'queue',(select coalesce(jsonb_agg(to_jsonb(q)order by priority desc,symbol),'[]')from(select *from paperlab.research_queue where p_symbol is null or symbol=p_symbol order by priority desc,symbol limit case when p_symbol is null then 12 else 1 end)q),
 'history',(select coalesce(jsonb_agg(jsonb_build_object('hash',hash,'at',at,'sources',jsonb_array_length(record->'sources'),'findings',jsonb_array_length(record->'findings'))order by at desc),'[]')from paperlab.research_history where symbol=p_symbol),
 'archives',(select coalesce(jsonb_agg(to_jsonb(a)order by created_at desc),'[]')from(select *from paperlab.archive_manifest order by created_at desc limit 12)a),
 'benchmark_note','Prospectieve EUR-referentie VWCE.DE (accumulerend wereldwijd aandelenfonds). Start pas op een toekomstige afgeronde sessie. Indicatieve koers vóór persoonlijke brokerkosten en belastingen; rekening- en referentietijdstippen zijn niet exact gelijk. Geen bewijs van strategievoordeel.',
 'history_note','Maximaal acht inhoudsversies per bedrijf binnen 365 dagen; bronarchief en herstelkopie hebben eigen bewaartermijnen.');
end$$;
do $$declare n text;begin for n in select p.oid::regprocedure::text from pg_proc p join pg_namespace s on s.oid=p.pronamespace where s.nspname='public'and p.proname in('paper_project_refresh','paper_project_claim','paper_project_commit','paper_project_read')loop execute'revoke all on function '||n||' from public,anon,authenticated,service_role';end loop;end$$;
revoke all on function paperlab.retain_research_version()from public,anon,authenticated,service_role;
grant execute on function public.paper_project_claim(),public.paper_project_commit(uuid,jsonb),public.paper_project_read(uuid,text)to service_role;
commit;
