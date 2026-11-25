-- Recurring quarterly research. Preserves human forecasts, accounts and trading policies.
begin;
create table if not exists paperlab.quarter_companies(symbol text primary key,calendar_url text,next_calendar timestamptz not null default now(),calendar_status text not null default 'unconfirmed');
insert into paperlab.quarter_companies(symbol,calendar_url)select x->>'symbol',e.record->>'calendar_url'from paperlab.company_coverage_runtime r cross join jsonb_array_elements(r.catalogue)x left join paperlab.earnings_companies e on e.symbol=x->>'symbol'on conflict do nothing;
create table if not exists paperlab.quarter_cycles(id text primary key,symbol text not null references paperlab.quarter_companies,release_at timestamptz not null,fiscal_label text,event jsonb not null,legacy_id text,created_at timestamptz not null default now(),unique(symbol,release_at));
insert into paperlab.quarter_cycles(id,symbol,release_at,fiscal_label,event,legacy_id)select 'auto:'||id,symbol,release_at,cycle_key,coalesce(event,'{}'),id from paperlab.earnings_cycles where release_at is not null and status<>'superseded_unconfirmed'on conflict do nothing;
create table if not exists paperlab.quarter_jobs(id text primary key,symbol text not null references paperlab.quarter_companies,cycle_id text references paperlab.quarter_cycles,phase text not null check(phase in('calendar','pre7','pre2','actual')),due_at timestamptz not null,available_at timestamptz not null default now(),status text not null default 'queued',attempts int not null default 0,result jsonb,completed_at timestamptz);
create table if not exists paperlab.quarter_forecasts(cycle_id text primary key references paperlab.quarter_cycles,recorded_at timestamptz not null,record jsonb not null,consensus jsonb,source_job text not null);
create table if not exists paperlab.quarter_actuals(cycle_id text primary key references paperlab.quarter_cycles,recorded_at timestamptz not null default now(),record jsonb not null);
create table if not exists paperlab.quarter_evaluations(cycle_id text primary key references paperlab.quarter_cycles,checked_at timestamptz not null default now(),record jsonb not null);
create table if not exists paperlab.quarter_calendar_cache(symbol text primary key,record jsonb not null,checked_at timestamptz not null default now());alter table paperlab.quarter_calendar_cache enable row level security;revoke all on paperlab.quarter_calendar_cache from public,anon,authenticated,service_role;
create table if not exists paperlab.quarter_usage(month date primary key,calendar_reserved_bytes bigint not null default 0);
alter table paperlab.quarter_usage enable row level security;revoke all on paperlab.quarter_usage from public,anon,authenticated,service_role;
create table if not exists paperlab.quarter_runtime(singleton boolean primary key default true check(singleton),enabled boolean not null default true,token uuid,lease_until timestamptz,job_id text,payload jsonb,last_attempt timestamptz,last_success timestamptz,status text not null default 'waiting',reserved boolean not null default false,model_day date,budget_month date);
insert into paperlab.quarter_runtime(singleton)values(true)on conflict do nothing;
alter table paperlab.quarter_runtime add column if not exists model_day date;alter table paperlab.quarter_runtime add column if not exists budget_month date;
do $$declare n text;begin foreach n in array array['quarter_companies','quarter_cycles','quarter_jobs','quarter_forecasts','quarter_actuals','quarter_evaluations','quarter_runtime']loop execute format('alter table paperlab.%I enable row level security',n);execute format('revoke all on paperlab.%I from public,anon,authenticated,service_role',n);end loop;end$$;
create or replace function paperlab.quarter_fiscal_key(p text)returns text language sql immutable as $$select coalesce(substring(upper(p)from 'FISCAL(?: YEAR)?[ -]*(20[0-9]{2})'),substring(upper(p)from 'FY[ -]*(20[0-9]{2})'),substring(upper(p)from '20[0-9]{2}'))||'Q'||coalesce(substring(upper(p)from 'Q[ -]*([1-4])'),case when upper(p)~'FIRST[ -]+QUARTER'then'1'when upper(p)~'SECOND[ -]+QUARTER'then'2'when upper(p)~'THIRD[ -]+QUARTER'then'3'when upper(p)~'FOURTH[ -]+QUARTER'then'4'end)$$;
revoke all on function paperlab.quarter_fiscal_key(text)from public,anon,authenticated,service_role;
create or replace function paperlab.quarter_price_context(p_id text)returns jsonb language plpgsql stable security definer set search_path=pg_catalog,pg_temp as $$declare c paperlab.quarter_cycles;tz text;ex text;close_time time;base record;last record;n int;out jsonb:='{}';begin
 select *into strict c from paperlab.quarter_cycles where id=p_id;
 select x->>'timezone',x->>'exchange'into tz,ex from paperlab.company_coverage_runtime r,jsonb_array_elements(r.catalogue)x where x->>'symbol'=c.symbol limit 1;
 if tz is null then return jsonb_build_object('status','timezone_unknown');end if;
 close_time:=case when ex in('XNYS','XNAS')then time'16:00'when ex in('XLON','XOSL')then time'16:30'when ex='XCSE'then time'17:00'when ex='XHEL'then time'18:30'else time'17:30'end;
 select day,close into base from paperlab.daily_study_bars where symbol=c.symbol and observed_at<=now()and close>0 and(day::date+close_time)at time zone tz<=c.release_at order by day desc limit 1;
 if not found then return jsonb_build_object('status','baseline_missing');end if;
 foreach n in array array[1,5,20]loop
  select day,close into last from paperlab.daily_study_bars where symbol=c.symbol and observed_at<=now()and close>0 and(day::date+close_time)at time zone tz>c.release_at and day::date<(now()at time zone tz)::date order by day offset(n-1)limit 1;
  if found then out:=out||jsonb_build_object(n::text,jsonb_build_object('return_percent',100*(last.close/base.close-1),'last_day',last.day));end if;
 end loop;
 return jsonb_build_object('status','indicative_cached_closes','baseline_day',base.day,'outcomes',out,'session_alignment_verified',false,'basis','Normale sessiesluiting aangenomen; afwijkende beursuren/bedrijfsacties niet onafhankelijk geverifieerd. Geen richting-score of handelswinst.','fees_dividends_excluded',true);
end$$;
revoke all on function paperlab.quarter_price_context(text)from public,anon,authenticated,service_role;
create or replace function paperlab.quarter_plan()returns void language plpgsql security definer set search_path=pg_catalog,pg_temp as $$declare c paperlab.quarter_cycles;j record;f record;a record;human jsonb;comparison jsonb;cons jsonb;pc jsonb;ce jsonb;cr jsonb;begin
 insert into paperlab.quarter_jobs(id,symbol,phase,due_at)select 'calendar:'||symbol||':'||to_char(now(),'YYYY-MM-DD'),symbol,'calendar',next_calendar from paperlab.quarter_companies where next_calendar<=now()and not exists(select 1 from paperlab.quarter_jobs qj where qj.symbol=quarter_companies.symbol and qj.phase='calendar'and qj.status in('queued','retry','source_missing','leased'))on conflict do nothing;
 update paperlab.quarter_jobs qj set status='missed_cutoff'where qj.phase in('pre7','pre2')and qj.status in('queued','retry','source_missing')and exists(select 1 from paperlab.quarter_cycles qc where qc.id=qj.cycle_id and qc.release_at<=now()+interval'24 hours');
 delete from paperlab.quarter_jobs where phase='calendar'and status='completed'and completed_at<now()-interval'90 days';
 for c in select *from paperlab.quarter_cycles where release_at>now()-interval'90 days'loop
  for j in select *from(values('pre7',c.release_at-interval'7 days'),('pre2',c.release_at-interval'2 days'),('actual',case when c.event->>'precision'='official_day_time_unknown'then(c.event->>'official_date')::timestamptz+interval'38 hours'else c.release_at+interval'2 hours'end))v(phase,due)loop
   insert into paperlab.quarter_jobs(id,symbol,cycle_id,phase,due_at,available_at,status)values(c.id||':'||j.phase,c.symbol,c.id,j.phase,j.due,j.due,case when j.phase in('pre7','pre2')and c.release_at-interval'24 hours'<now()then'missed_before_automation'else'queued'end)on conflict do nothing;
  end loop;
  if now()>=c.release_at-interval'24 hours'and not exists(select 1 from paperlab.quarter_forecasts where cycle_id=c.id)then
   select *into f from paperlab.quarter_jobs where cycle_id=c.id and phase in('pre7','pre2')and status='completed'and completed_at<=c.release_at-interval'24 hours'order by completed_at desc limit 1;
   if found then insert into paperlab.quarter_forecasts(cycle_id,recorded_at,record,consensus,source_job)values(c.id,f.completed_at,f.result->'assessment',f.result->'consensus_snapshot',f.id)on conflict do nothing;end if;
  end if;
  select *into a from paperlab.quarter_actuals where cycle_id=c.id;
  if found then
   select record into human from paperlab.quarter_forecasts where cycle_id=c.id;
   if human is null and c.legacy_id is not null then select forecast into human from paperlab.earnings_cycles where id=c.legacy_id and frozen_at<=release_at-interval'24 hours';end if;
   comparison:=jsonb_build_object('status',case when human is null then'actual_without_pre_release_forecast'else'compared'end,'actual',a.record,'forecast',human,'trade_approval',false,'profitability_proven',false,'eps_comparable',human->>'currency'=a.record->>'currency'and human->>'eps_basis'=a.record->>'eps_basis','consensus_surprise_status','requires_frozen_matching_period_and_basis','call_review_status',a.record->>'call_review_status','price_context',case when c.legacy_id is not null then paperlab.earnings_price_assessment(c.legacy_id)else paperlab.quarter_price_context(c.id)end);
   if human is not null and human->>'currency'=a.record->>'currency'then
    comparison:=comparison||jsonb_build_object('revenue_in_range',case when jsonb_typeof(human->'revenue')='object'then(a.record->>'revenue_million')::numeric between(human->'revenue'->>'low')::numeric and(human->'revenue'->>'high')::numeric else(a.record->>'revenue_value')::numeric between(human->>'revenue_low')::numeric and(human->>'revenue_high')::numeric end,'eps_in_range',case when human->>'eps_basis'=a.record->>'eps_basis'then case when jsonb_typeof(human->'eps')='object'then(a.record->>'eps')::numeric between(human->'eps'->>'low')::numeric and(human->'eps'->>'high')::numeric else(a.record->>'eps')::numeric between(human->>'eps_low')::numeric and(human->>'eps_high')::numeric end else null end);
   end if;
   select consensus into cons from paperlab.quarter_forecasts where cycle_id=c.id;
   if cons is null and c.legacy_id is not null and to_regclass('paperlab.earnings_consensus_snapshots')is not null then execute 'select record from paperlab.earnings_consensus_snapshots where cycle_id=$1 and recorded_at<=$2 order by recorded_at desc limit 1'into cons using c.legacy_id,c.release_at-interval'24 hours';end if;
   select value into pc from jsonb_array_elements(coalesce(cons->'quarters','[]'))where value->>'period'=left(a.record->>'period_end',7)limit 1;
   comparison:=comparison||jsonb_build_object('consensus_surprise_status',case when pc is null then'no_matching_frozen_period'else'basis_or_currency_unverified'end,'consensus_period_scope','Providermaand, geen onafhankelijk bevestigde fiscale periode');
   if pc is not null then
    ce:=pc->'eps';cr:=pc->'revenue';
    if ce->>'basis'=a.record->>'eps_basis'and ce->>'currency'=a.record->>'currency'and ce->>'status'='provider_reported'and(ce->>'average')::numeric<>0 then comparison:=comparison||jsonb_build_object('eps_surprise_percent',100*((a.record->>'eps')::numeric/(ce->>'average')::numeric-1),'consensus_surprise_status','compared_same_basis_month_reference');end if;
    if cr->>'basis'=a.record->>'eps_basis'and cr->>'currency'=a.record->>'currency'and cr->>'status'='provider_reported'and(cr->>'average')::numeric>0 then comparison:=comparison||jsonb_build_object('revenue_surprise_percent',100*((a.record->>'revenue_value')::numeric/(cr->>'average')::numeric-1),'consensus_surprise_status','compared_same_basis_month_reference');end if;
   end if;
   if c.legacy_id is not null and exists(select 1 from paperlab.earnings_cycles where id=c.legacy_id and actual is not null and(actual->>'currency'is distinct from a.record->>'currency'or actual->>'eps_basis'is distinct from a.record->>'eps_basis'or abs((actual->>'eps')::numeric-(a.record->>'eps')::numeric)>0.000001 or abs((actual->>'revenue_million')::numeric-(a.record->>'revenue_million')::numeric)>0.001))then comparison:=comparison||jsonb_build_object('status','conflicting_actual_sources','revenue_in_range',null,'eps_in_range',null,'consensus_surprise_status','actual_conflict_requires_review');end if;
   insert into paperlab.quarter_evaluations values(c.id,now(),comparison)on conflict(cycle_id)do update set checked_at=excluded.checked_at,record=excluded.record where paperlab.quarter_evaluations.record is distinct from excluded.record;
  end if;
 end loop;
end$$;
create or replace function public.paper_quarter_claim()returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$declare r paperlab.quarter_runtime;j paperlab.quarter_jobs;b paperlab.deep_models;t uuid;p jsonb;charge bigint;m date:=date_trunc('month',now()at time zone'UTC')::date;d date:=(now()at time zone'America/Los_Angeles')::date;begin
 select *into r from paperlab.quarter_runtime where singleton for update;if not r.enabled or r.lease_until>now()then return null;end if;
 if not exists(select 1 from paperlab.gemini_runtime where free_tier_confirmed_at is not null)then return null;end if;
 update paperlab.quarter_jobs set status='retry',available_at=now()+interval'2 minutes'where id=r.job_id and status='leased';perform paperlab.quarter_plan();
 insert into paperlab.free_usage(month)values(m)on conflict do nothing;perform 1 from paperlab.free_usage where month=m for update;insert into paperlab.quarter_usage(month)values(m)on conflict do nothing;
 select *into b from paperlab.deep_models where model='gemini-3.5-flash-lite'for update;
 if b.day is distinct from d then b.used:=0;end if;if b.minute is distinct from date_trunc('minute',now())then b.minute_used:=0;b.minute_tokens:=0;end if;
 if b.used>=b.daily_limit or b.minute_used>=b.rpm or b.minute_tokens+100000>b.tpm or b.retry_after>now()then update paperlab.quarter_runtime set status=case when b.used>=b.daily_limit then'waiting_daily_model_quota'when b.retry_after>now()then'waiting_model_cooldown'else'waiting_minute_capacity'end where singleton;return null;end if;
 select *into j from paperlab.quarter_jobs where status in('queued','retry','source_missing')and due_at<=now()and available_at<=now()and(phase<>'calendar'or((select calendar_reserved_bytes from paperlab.quarter_usage where month=m)+500000<=60000000 and(select estimated_worker_egress_bytes from paperlab.free_usage where month=m)+500000<paperlab.cached_research_limit()))and(phase not in('pre7','pre2')or(select release_at from paperlab.quarter_cycles where id=cycle_id)>now()+interval'24 hours')order by case phase when'pre7'then 0 when'pre2'then 1 when'actual'then 2 else 3 end,due_at limit 1 for update skip locked;
 if not found then update paperlab.quarter_runtime set status='waiting_work_quota_or_download_budget'where singleton;return null;end if;
 p:=jsonb_build_object('cycle',(select to_jsonb(c)from paperlab.quarter_cycles c where id=j.cycle_id),'sources',(select coalesce(jsonb_agg(v),'[]')from(select jsonb_build_object('id',s.id,'url',s.url,'sha256',s.sha256,'known_at',s.known_at,'role',s.role,'kind',s.kind,'total_chars',length(s.body),'text',substring(s.body from 1 for 16000))v from paperlab.deep_documents s where s.symbol=j.symbol and s.active and s.body<>''and(j.phase<>'actual'or s.known_at>=(select release_at from paperlab.quarter_cycles where id=j.cycle_id))order by case when s.kind='earnings_release'then 0 when s.role='interim'then 1 else 2 end,s.known_at desc limit 3)z),'consensus',(select record from paperlab.analyst_consensus where symbol=j.symbol),'market_quote',(select jsonb_build_object('price',pf.state->'prices'->j.symbol,'time',pf.state->'last_observation'->j.symbol->>'time','scope','Indicatieve laatst opgeslagen koers, geen uitvoeringsprijs')from paperlab.portfolio pf limit 1),'company_report',(select report-'source_manifest'from paperlab.deep_companies where symbol=j.symbol),'previous_research',(select result->'assessment'from paperlab.quarter_jobs where cycle_id=j.cycle_id and phase in('pre7','pre2')and status='completed'order by completed_at desc limit 1),'previous_calendar',(select result->'assessment'from paperlab.quarter_jobs where symbol=j.symbol and phase='calendar'and status='completed'order by completed_at desc limit 1),'macro_context',paperlab.macro_context(),'limitations','Geen automatische aankoopgoedkeuring. Primaire bronnen, periodes en eenheden blijven vereist.');
 if j.phase<>'calendar'and jsonb_array_length(p->'sources')=0 then update paperlab.quarter_jobs set status='source_missing',available_at=now()+interval'6 hours',result='{"gaps":["Primaire brontekst ontbreekt"]}'where id=j.id;update paperlab.deep_companies set next_discovery=least(next_discovery,now())where symbol=j.symbol;update paperlab.quarter_runtime set status='waiting_primary_sources'where singleton;return null;end if;
 charge:=2*octet_length(p::text)+32000+case when j.phase='calendar'then 500000 else 0 end;
 if octet_length(p::text)>95000 then p:=p-'company_report';end if;
 if octet_length(p::text)>95000 then p:=jsonb_set(p,'{sources}',(select jsonb_agg(jsonb_set(value,'{text}',to_jsonb(left(value->>'text',8000))))from jsonb_array_elements(p->'sources')));end if;
 if octet_length(p::text)>95000 or pg_database_size(current_database())>paperlab.storage_limit('hard')or(select estimated_worker_egress_bytes+charge from paperlab.free_usage where month=m)>paperlab.cached_research_limit()then update paperlab.quarter_runtime set status='waiting_context_or_storage_or_traffic_budget'where singleton;return null;end if;
 t:=gen_random_uuid();update paperlab.quarter_runtime set token=t,lease_until=now()+interval'150 seconds',job_id=j.id,payload=p,last_attempt=now(),status='processing',reserved=true,model_day=d,budget_month=m where singleton;
 update paperlab.quarter_jobs set status='leased',attempts=attempts+1 where id=j.id;
 if j.phase='calendar'then update paperlab.quarter_usage set calendar_reserved_bytes=calendar_reserved_bytes+500000 where month=m;end if;
 update paperlab.deep_models set day=d,used=b.used+1,minute=date_trunc('minute',now()),minute_used=b.minute_used+1,minute_tokens=b.minute_tokens+100000 where model=b.model;
 update paperlab.free_usage set estimated_worker_egress_bytes=estimated_worker_egress_bytes+charge where month=m;
 return jsonb_build_object('token',t,'job',to_jsonb(j)||jsonb_build_object('calendar_cache',(select record from paperlab.quarter_calendar_cache where symbol=j.symbol),'calendar_url',(select calendar_url from paperlab.quarter_companies where symbol=j.symbol)),'input',p);
end$$;
create or replace function public.paper_quarter_calendar_cache(p_token uuid,p_source jsonb)returns boolean language plpgsql security definer set search_path=pg_catalog,pg_temp as $$declare s text;begin
 select j.symbol into s from paperlab.quarter_runtime r join paperlab.quarter_jobs j on j.id=r.job_id where r.token=p_token and r.lease_until>now()and j.phase='calendar';if not found then return false;end if;
 if p_source->>'url'is distinct from(select calendar_url from paperlab.quarter_companies where symbol=s)or length(p_source->>'text')>20000 or p_source->>'sha256'!~'^[a-f0-9]{64}$'then raise exception'Invalid calendar cache';end if;
 insert into paperlab.quarter_calendar_cache(symbol,record)values(s,p_source-'unchanged')on conflict(symbol)do update set record=excluded.record,checked_at=now();
 if p_source->>'follow_url'like'https://%'and length(p_source->>'follow_url')<=1200 and split_part(p_source->>'follow_url','/',3)=split_part(p_source->>'url','/',3)then update paperlab.quarter_companies set calendar_url=p_source->>'follow_url'where symbol=s;end if;return true;
end$$;
revoke all on function public.paper_quarter_calendar_cache(uuid,jsonb)from public,anon,authenticated,service_role;grant execute on function public.paper_quarter_calendar_cache(uuid,jsonb)to service_role;
create or replace function public.paper_quarter_commit(p_token uuid,p_result jsonb)returns boolean language plpgsql security definer set search_path=pg_catalog,pg_temp as $$declare r paperlab.quarter_runtime;j paperlab.quarter_jobs;c paperlab.quarter_cycles;e jsonb;s jsonb;a jsonb;eid text;delay timestamptz;owner uuid;begin
 select *into r from paperlab.quarter_runtime where singleton and token=p_token and lease_until>now()for update;if not found then return false;end if;select *into strict j from paperlab.quarter_jobs where id=r.job_id for update;
 if octet_length(p_result::text)>40000 or p_result->>'trade_approval'is distinct from'false'or(p_result->>'attempted_calls')::int not between 0 and 1 then raise exception'Bounded research-only result required';end if;
 if(p_result->>'attempted_calls')::int=0 and r.reserved then update paperlab.deep_models set used=greatest(0,used-1)where model='gemini-3.5-flash-lite'and day=r.model_day;end if;
 if j.phase='calendar'then
   if p_result->'calendar_source'->>'download_bytes'is not null and(p_result->'calendar_source'->>'download_bytes')::int between 0 and 400000 then update paperlab.free_usage set estimated_worker_egress_bytes=greatest(0,estimated_worker_egress_bytes-(500000-((p_result->'calendar_source'->>'download_bytes')::int+10000)))where month=r.budget_month;update paperlab.quarter_usage set calendar_reserved_bytes=greatest(0,calendar_reserved_bytes-(500000-((p_result->'calendar_source'->>'download_bytes')::int+10000)))where month=r.budget_month;end if;
 end if;
 if p_result->>'status'='completed'then
  if j.phase<>'calendar'then
   for e in select value from jsonb_array_elements(p_result->'evidence')loop select value into s from jsonb_array_elements(r.payload->'sources')where value->>'id'=e->>'source_id';if s is null or length(e->>'quote')<10 or strpos(s->>'text',e->>'quote')=0 then raise exception'Quarter source evidence mismatch';end if;end loop;
  end if;
  if j.phase='calendar'then
   e:=p_result->'calendar_event';if e is not null and e<>'null'::jsonb then
    if e->>'source_url'is distinct from(select calendar_url from paperlab.quarter_companies where symbol=j.symbol)or(e->>'release_at')::timestamptz<now()-interval'3 days'or(e->>'release_at')::timestamptz>now()+interval'370 days'or length(e->>'evidence')<10 or e->>'source_url'not like'https://%'or not exists(select 1 from paperlab.quarter_calendar_cache cc where cc.symbol=j.symbol and strpos(cc.record->>'text',e->>'evidence')>0)then raise exception'Invalid official calendar event';end if;
    select id into eid from paperlab.quarter_cycles where symbol=j.symbol and(coalesce(event->>'official_date',release_at::date::text)=coalesce(e->>'official_date',left(e->>'release_at',10)))limit 1;
    if eid is null then eid:='auto:'||j.symbol||':'||encode(sha256(convert_to(e->>'release_at','UTF8')),'hex');insert into paperlab.quarter_cycles(id,symbol,release_at,fiscal_label,event)values(eid,j.symbol,(e->>'release_at')::timestamptz,e->>'fiscal_label',e)on conflict do nothing;end if;
   end if;
   update paperlab.quarter_companies set next_calendar=now()+interval'1 day',calendar_status=case when e is null or e='null'::jsonb then'unconfirmed'else'official_day_confirmed'end where symbol=j.symbol;
  end if;
  a:=p_result;
  if j.cycle_id is not null and paperlab.quarter_fiscal_key(p_result->>'fiscal_label')is not null and exists(select 1 from jsonb_array_elements(p_result->'evidence')where value->>'metric'='period'and paperlab.quarter_fiscal_key(value->>'quote')=paperlab.quarter_fiscal_key(p_result->>'fiscal_label'))then update paperlab.quarter_cycles set fiscal_label=p_result->>'fiscal_label'where id=j.cycle_id and fiscal_label is null;end if;
  if j.phase='actual'and p_result->>'actual_valid'='true'then
   select *into strict c from paperlab.quarter_cycles where id=j.cycle_id;
   if paperlab.quarter_fiscal_key(p_result->>'fiscal_label')is distinct from paperlab.quarter_fiscal_key(c.fiscal_label)or paperlab.quarter_fiscal_key(c.fiscal_label)is null or not exists(select 1 from jsonb_array_elements(p_result->'evidence')where value->>'metric'='revenue')or not exists(select 1 from jsonb_array_elements(p_result->'evidence')where value->>'metric'='eps')or not exists(select 1 from jsonb_array_elements(p_result->'evidence')where value->>'metric'='period')or(p_result->>'period_end')::date<c.release_at::date-180 or(p_result->>'period_end')::date>=c.release_at::date or(p_result->>'revenue_value')::numeric<=0 or p_result->>'currency'!~'^[A-Z]{3}$'then raise exception'Invalid actual period or currency';end if;
   a:=p_result||jsonb_build_object('revenue_million',(p_result->>'revenue_value')::numeric/1000000,'no_consensus_surprise_computed',true);
   insert into paperlab.quarter_actuals(cycle_id,record)values(c.id,a)on conflict do nothing;
   if c.legacy_id is not null and a->>'currency'='USD'and a->>'eps_basis'in('GAAP','non-GAAP')and not exists(select 1 from paperlab.earnings_cycles where id=c.legacy_id and actual is not null)then
    select value into s from jsonb_array_elements(r.payload->'sources')where value->>'id'=(select value->>'source_id'from jsonb_array_elements(a->'evidence')where value->>'metric'='revenue'limit 1);
    select owner_id into owner from paperlab.settings where singleton;
    a:=a||jsonb_build_object('source_url',s->>'url','source_sha256',s->>'sha256','guidance_review',case when length(a->>'guidance_review')>=80 then a->>'guidance_review'else 'De beschikbare bron is automatisch op de gerapporteerde cijfers gecontroleerd. De vooruitzichten zijn nog niet volledig kwalitatief geverifieerd; dit blijft een expliciet onderzoeksgat.'end,'call_review',case when length(a->>'call_review')>=80 then a->>'call_review'else 'Er is geen volledig gelezen en onafhankelijk geverifieerd aandeelhouderscalltranscript in deze verwerking. Deze cijfervergelijking geldt niet als afgeronde beoordeling van de call.'end);
    perform public.paper_earnings_actual(owner,c.legacy_id,a);
    update paperlab.earnings_tasks set status='completed',completed_at=now(),note='Automatische brongebonden cijferverwerking; callbeoordeling blijft afzonderlijk.'where cycle_id=c.legacy_id and phase='results_1'and status='pending';
   end if;
  end if;
  if j.phase='actual'and coalesce(p_result->>'actual_valid','false')<>'true'then update paperlab.quarter_jobs set status='source_missing',available_at=now()+interval'12 hours',result=p_result where id=j.id;
  else update paperlab.quarter_jobs set status='completed',completed_at=now(),result=jsonb_build_object('assessment',a,'consensus_snapshot',r.payload->'consensus')where id=j.id;end if;
  update paperlab.deep_models set last_status='completed',provider_failures=0,retry_after=null where model='gemini-3.5-flash-lite';
  update paperlab.quarter_runtime set last_success=now(),status='processed'where singleton;
 else
  delay:=case when p_result->>'status'='rate_limited'then paperlab.gemini_retry_time(p_result)else now()+case when j.attempts>=3 then interval'12 hours'else interval'15 minutes'end end;
  update paperlab.quarter_jobs set status=case when p_result->>'status'='source_missing'then'source_missing'else'retry'end,available_at=delay,result=p_result where id=j.id;
  if p_result->>'status'='rate_limited'or(p_result->>'status'='provider_unavailable'and coalesce(p_result->>'provider_http_status','503')in('500','502','503','504'))then update paperlab.deep_models set retry_after=delay,last_status=p_result->>'status'where model='gemini-3.5-flash-lite';end if;
  update paperlab.quarter_runtime set status=p_result->>'status'where singleton;
 end if;
 update paperlab.quarter_runtime set token=null,lease_until=null,payload=null,reserved=false where singleton;perform paperlab.quarter_plan();return true;
end$$;
create or replace function public.paper_quarter_read(p_owner uuid,p_symbol text default null)returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton)then raise exception'Owner required';end if;
 return jsonb_build_object('runtime',(select to_jsonb(r)-'token'-'lease_until'-'payload'from paperlab.quarter_runtime r),'companies',(select count(*)from paperlab.quarter_companies),'calendar_unconfirmed',(select count(*)from paperlab.quarter_companies where calendar_status='unconfirmed'),'schedule','Vijfminutenwachtrij; onderzoek T−7/T−2, verwachting uiterlijk T−24 uur, daarna cijfers en evaluatie. Gratis quota gedeeld met dossieronderzoek.','cycles',(select coalesce(jsonb_agg(v),'[]')from(select to_jsonb(c)||jsonb_build_object('jobs',(select jsonb_agg(case when p_symbol is null then jsonb_build_object('id',j.id,'phase',j.phase,'due_at',j.due_at,'status',j.status,'completed_at',j.completed_at,'assessment',j.result->'assessment','gaps',j.result->'gaps')else to_jsonb(j)end)from paperlab.quarter_jobs j where cycle_id=c.id),'frozen_forecast',(select record from paperlab.quarter_forecasts where cycle_id=c.id),'evaluation',(select record from paperlab.quarter_evaluations where cycle_id=c.id))v from paperlab.quarter_cycles c where p_symbol is null or symbol=p_symbol order by case when release_at>=now()then 0 else 1 end,case when release_at>=now()then release_at end,release_at desc limit 20)z),'trade_approval',false);
end$$;
do $$begin if to_regprocedure('public.paper_project_read_quarter_base(uuid,text)')is null then alter function public.paper_project_read(uuid,text)rename to paper_project_read_quarter_base;end if;end$$;
create or replace function public.paper_project_read(p_owner uuid,p_symbol text default null)returns jsonb language sql security definer set search_path=pg_catalog,pg_temp as $$select public.paper_project_read_quarter_base(p_owner,p_symbol)||jsonb_build_object('quarter_automation',public.paper_quarter_read(p_owner,p_symbol))$$;
revoke all on function paperlab.quarter_plan(),public.paper_quarter_claim(),public.paper_quarter_commit(uuid,jsonb),public.paper_quarter_read(uuid,text),public.paper_project_read_quarter_base(uuid,text),public.paper_project_read(uuid,text)from public,anon,authenticated,service_role;
grant execute on function public.paper_quarter_claim(),public.paper_quarter_commit(uuid,jsonb),public.paper_quarter_read(uuid,text),public.paper_project_read(uuid,text)to service_role;
create index if not exists quarter_job_due on paperlab.quarter_jobs(status,available_at,due_at);
select paperlab.quarter_plan();
do $$declare s text;begin if to_regprocedure('public.paper_project_backup_prepare()')is not null then s:=pg_get_functiondef('public.paper_project_backup_prepare()'::regprocedure);s:=replace(s,$old$'schema_version',43$old$,$new$'schema_version',44$new$);execute s;end if;end$$;
commit;
