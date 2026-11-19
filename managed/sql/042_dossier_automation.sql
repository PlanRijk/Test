-- Durable finish-first dossiers with bounded automatic recovery and explicit gaps.
begin;
set local lock_timeout='5s';
alter table paperlab.deep_models drop constraint if exists deep_models_model_check;
alter table paperlab.deep_models add constraint deep_models_model_check check(model in('gemini-3.5-flash-lite','gemini-3.8-flash','gemini-2.5-flash','gemini-3-flash-preview'));
insert into paperlab.deep_models(model,daily_limit,rpm,tpm)values('gemini-2.5-flash',20,5,250000),('gemini-3-flash-preview',20,5,250000)on conflict do nothing;
alter table paperlab.deep_models add column if not exists provider_failures int not null default 0;
alter table paperlab.deep_jobs add column if not exists validation_attempts int not null default 0;
alter table paperlab.deep_jobs add column if not exists parent_id text references paperlab.deep_jobs(id);
alter table paperlab.deep_jobs add column if not exists part_start int not null default 0;
alter table paperlab.deep_jobs add column if not exists part_length int not null default 7000;
alter table paperlab.deep_jobs add column if not exists repair_round int not null default 0;
alter table paperlab.deep_jobs add column if not exists recovery_cycles int not null default 0;
alter table paperlab.deep_companies add column if not exists last_progress timestamptz;
alter table paperlab.deep_companies add column if not exists queued_at timestamptz not null default now();
alter table paperlab.deep_companies add column if not exists dossier_gaps jsonb not null default '[]';
alter table paperlab.deep_companies add column if not exists input_hash text;
create table if not exists paperlab.dossier_automation(singleton boolean primary key default true check(singleton),version int not null,policy jsonb not null);
insert into paperlab.dossier_automation values(true,2,'{"mode":"finish_first","max_active_companies":2,"invalid_attempts_before_split":3,"max_split_depth":2,"max_daily_recovery_cycles":2,"heavy_audit_reserve":2,"stalled_after_hours":24,"paid_fallback":false}')on conflict do nothing;
alter table paperlab.dossier_automation add column if not exists focus_symbols text[]not null default '{}';
create table if not exists paperlab.dossier_alerts(id text primary key,symbol text,reason text not null,severity text not null,opened_at timestamptz not null default now(),last_seen timestamptz not null default now(),resolved_at timestamptz,record jsonb not null default '{}');
create table if not exists paperlab.dossier_peer_groups(symbol text,peer text,scope text not null,primary key(symbol,peer));
insert into paperlab.dossier_peer_groups values
('NVDA','AMD','Accelerators and semiconductors; product/customer mix differs'),('NVDA','AVGO','AI infrastructure and custom chips; segment comparability requires review'),
('WMT','COST','Large-scale retail; membership model differs'),('WMT','AMZN','Retail comparison only; consolidated AWS mix differs'),
('LIN','APD','Industrial gases; regional and project mix differs'),('LIN','AI.PA','Industrial gases; currency and regional mix differs'),
('NOVO-B.CO','LLY','Diabetes/obesity exposure; product pipeline and reporting differ'),
('UNH','CVS','US healthcare; insurance and service segments differ'),('UNH','CI','US healthcare; segment mix differs'),
('ATCO-A.ST','IR','Industrial equipment; compressor/vacuum segment mix differs'),
('MSFT','GOOGL','Cloud/software platforms; consolidated mix differs'),('MSFT','AMZN','Cloud comparison; retail mix differs'),
('GOOGL','META','Digital advertising; cloud and product mix differs'),('META','GOOGL','Digital advertising; product mix differs'),
('AMZN','WMT','Retail comparison only; AWS not comparable'),('AMZN','MSFT','Cloud comparison only; retail not comparable'),
('V','MA','Payment networks; geography and business mix differ'),('MA','V','Payment networks; geography and business mix differ'),
('COST','WMT','Retail; membership model differs')on conflict do nothing;
alter table paperlab.dossier_peer_groups enable row level security;
revoke all on paperlab.dossier_peer_groups from public,anon,authenticated,service_role;
create table if not exists paperlab.dossier_history(symbol text not null,completed_at timestamptz not null,record jsonb not null,primary key(symbol,completed_at));
alter table paperlab.dossier_automation enable row level security;
alter table paperlab.dossier_alerts enable row level security;
alter table paperlab.dossier_history enable row level security;
revoke all on paperlab.dossier_automation,paperlab.dossier_alerts,paperlab.dossier_history from public,anon,authenticated,service_role;
-- One-time upgrade recovery; never reset provider usage or previously completed work.
do $$begin if not exists(select 1 from paperlab.dossier_alerts where id='protocol-v2-installed-final')then
 update paperlab.deep_jobs j set status='retry',available_at=now(),model='gemini-3.5-flash-lite',validation_attempts=0 where j.stage='extract'and j.status in('blocked','retry')and j.result->>'status'='invalid_response'and j.result->>'protocol_version'is distinct from'2'and exists(select 1 from paperlab.deep_documents d where d.id=j.doc_id and d.active);
 insert into paperlab.dossier_alerts(id,reason,severity,resolved_at)values('protocol-v2-installed-final','protocol_upgrade','info',now());
end if;end$$;
update paperlab.dossier_automation set policy=policy||'{"heavy_fallback_model":"gemini-2.5-flash","heavy_shared_daily_limit":20,"fallback_quota_evidence":"Owner Google AI Studio Free screenshot: Gemini 2.5 Flash 5 RPM / 250K TPM / 20 RPD, 16 November 2026","fallback_only_for_capacity":true}'::jsonb where not(policy?'heavy_fallback_model');
update paperlab.dossier_automation set policy=policy||'{"capacity_backoff":"30 seconds, 1/2/4/8 minutes, maximum 15 minutes; Retry-After honored"}'::jsonb where not(policy?'capacity_backoff');
do $$begin if not exists(select 1 from paperlab.dossier_alerts where id='capacity-backoff-v2')then
 update paperlab.deep_models m set retry_after=least(retry_after,now()+interval'30 seconds')where last_status='provider_unavailable'and retry_after>now()and exists(select 1 from paperlab.deep_jobs j join paperlab.deep_events e on e.record->>'job'=j.id where e.record->>'model'=m.model and e.at>now()-interval'20 minutes'and j.result->>'provider_reason'='capacity'and j.result->>'retry_after_seconds'is null);
 insert into paperlab.dossier_alerts(id,reason,severity,resolved_at)values('capacity-backoff-v2','capacity_backoff_upgrade','info',now());end if;end$$;
do $$begin if not exists(select 1 from paperlab.dossier_alerts where id='validation-delay-v2')then
 update paperlab.deep_jobs set available_at=least(available_at,now()+interval'1 minute')where status='retry'and result->>'status'='invalid_response'and available_at>now()+interval'5 minutes';
 insert into paperlab.dossier_alerts(id,reason,severity,resolved_at)values('validation-delay-v2','validation_retry_upgrade','info',now());end if;end$$;
-- Generation can be unavailable even when a model remains listed in metadata.
update paperlab.dossier_automation set policy=policy||'{"heavy_fallback_model":"gemini-3-flash-preview","fallback_quota_evidence":"Owner Free screenshot Gemini 3 Flash: 5 RPM / 250K TPM / 20 RPD; generateContent model name checked via live catalogue on 19 November 2026","unavailable_legacy_fallback":"gemini-2.5-flash returned generation HTTP 404"}'::jsonb where policy->>'heavy_fallback_model'is distinct from'gemini-3-flash-preview';
update paperlab.deep_jobs set model='gemini-3.8-flash',available_at=now()where stage='audit'and model='gemini-2.5-flash'and status in('queued','retry');
create or replace function paperlab.dossier_alert(p_symbol text,p_reason text,p_record jsonb default '{}')returns void language sql security definer set search_path=pg_catalog,pg_temp as $$
 insert into paperlab.dossier_alerts(id,symbol,reason,severity,record)values(coalesce(p_symbol,'project')||':'||p_reason,p_symbol,p_reason,'warning',p_record)on conflict(id)do update set last_seen=now(),resolved_at=null,record=excluded.record where dossier_alerts.record is distinct from excluded.record or dossier_alerts.resolved_at is not null or dossier_alerts.last_seen<now()-interval'1 hour'
$$;
revoke all on function paperlab.dossier_alert(text,text,jsonb)from public,anon,authenticated,service_role;
create or replace function paperlab.dossier_context(p jsonb)returns jsonb language plpgsql immutable set search_path=pg_catalog,pg_temp as $$declare n int;begin
 p:=jsonb_strip_nulls(p);while p->>'stage'is distinct from'audit'and octet_length(p::text)>65000 and jsonb_array_length(coalesce(p->'facts','[]'))>12 loop
 n:=jsonb_array_length(p->'facts')-6;p:=jsonb_set(p,'{facts}',(select jsonb_agg(value order by ordinality)from jsonb_array_elements(p->'facts')with ordinality where ordinality<=n));p:=jsonb_set(p,'{fact_selection,context_truncated}','true');
 end loop;return p;
end$$;
revoke all on function paperlab.dossier_context(jsonb)from public,anon,authenticated,service_role;
create or replace function paperlab.dossier_peers(p_symbol text)returns jsonb language sql stable security definer set search_path=pg_catalog,pg_temp as $$
 select coalesce(jsonb_agg(v),'[]')from(select jsonb_build_object('symbol',pc.symbol,'source_url',pc.record->>'source_url','known_at',pc.record->>'secondary_checked_at','values',(select jsonb_object_agg(key,value)from jsonb_each(case when jsonb_typeof(pc.record->'observation'->'values')='object'then pc.record->'observation'->'values'else '{}'::jsonb end)where key in('annualTotalRevenue','annualNetIncome','annualOperatingCashFlow','annualFreeCashFlow','annualTotalDebt','annualCashAndCashEquivalents')),'comparison_scope',coalesce(dp.scope,'Same catalogue sector only; no proven economic comparability'),'independently_verified',false)v from paperlab.company_coverage pc left join paperlab.dossier_peer_groups dp on dp.symbol=p_symbol and dp.peer=pc.symbol where pc.symbol<>p_symbol and(dp.peer is not null or(not exists(select 1 from paperlab.dossier_peer_groups where symbol=p_symbol)and exists(select 1 from paperlab.company_coverage_runtime cr,jsonb_array_elements(cr.catalogue)a,paperlab.company_coverage_runtime cr2,jsonb_array_elements(cr2.catalogue)b where a->>'symbol'=p_symbol and b->>'symbol'=pc.symbol and a->>'sector'=b->>'sector')))order by pc.symbol limit 3)x
$$;
revoke all on function paperlab.dossier_peers(text)from public,anon,authenticated,service_role;
-- Target missing evidence inside already cached sources before downloading again.
alter table paperlab.deep_jobs add column if not exists research_question text;
create table if not exists paperlab.dossier_gap_runs(symbol text,source_hash text,round int,created_at timestamptz not null default now(),jobs int not null,primary key(symbol,source_hash,round));
alter table paperlab.dossier_gap_runs enable row level security;
revoke all on paperlab.dossier_gap_runs from public,anon,authenticated,service_role;
create or replace function paperlab.dossier_gap_work(p_symbol text,p_source_hash text,p_gaps jsonb)returns int language plpgsql security definer set search_path=pg_catalog,pg_temp as $$declare round_no int;spec record;hit record;start_at int;n int:=0;begin
 select coalesce(max(round),0)+1 into round_no from paperlab.dossier_gap_runs where symbol=p_symbol and source_hash=p_source_hash;if round_no>2 then return 0;end if;
 if exists(select 1 from paperlab.deep_jobs where symbol=p_symbol and id like'gap:%'and status in('queued','retry','leased'))then return 0;end if;
 for spec in select *from(values
 ('debt','schuld|looptijd|rente|maturit','maturities|principal payments|interest rates|weighted.average interest','Zoek concrete schuldlooptijden, aflossingen, rentetarieven en garanties; behoud de juiste verslagdatum en eenheden.'),
 ('acquisition','VIZIO|overname|acquisit|goodwill','VIZIO|purchase price allocation|acquisition.related|goodwill','Zoek de boekhoudkundige effecten van acquisities op activa, schuld, goodwill en eenmalige posten.'),
 ('cashquality','andere verliezen|other losses|reorg|restruct|eenmalig|kasstroom','other losses|reorganization|restructuring|non.recurring|net cash provided','Zoek onderbouwing voor eenmalige resultaten en winst tegenover kasstroom; meng geen kwartaal- en cumulatieve periodes.'),
 ('capex','CapEx|kapitaaluitgaven|capital expend','capital expenditures|capital investments|capital spending','Zoek historische investeringen en expliciete toekomstige CapEx-prognoses; label aannames en periode.'),
 ('competition','marktaandeel|market share|concurrent|peer','market share|competitive|competition|membership','Zoek primair bewijs voor concurrentiepositie, prijskracht, klantenbinding en marktaandeel; verzin geen ontbrekende peerdata.'),
 ('regulation','CAC|China|regelgev|regulat|goedkeuring','Cyberspace|CAC|China|export control|regulatory approval','Zoek concrete regelgeving, goedkeuringsvoorwaarden en geografische risico’s; onderscheid feit en mogelijke impact.')
 )v(topic,gap_pattern,source_pattern,question)loop
  if coalesce(p_gaps::text,'')!~*spec.gap_pattern then continue;end if;
  for hit in select d.id,d.body,occ.n,regexp_instr(d.body,spec.source_pattern,1,occ.n,0,'i')pos from paperlab.deep_documents d cross join(values(round_no*2),(round_no*2+1))occ(n)where d.symbol=p_symbol and d.active and d.body<>''and d.role<>'other'and regexp_instr(d.body,spec.source_pattern,1,occ.n,0,'i')>0 order by case when d.role='interim'then 0 when d.role='annual'then 1 else 2 end,d.known_at desc,d.id,occ.n limit 2 loop
   start_at:=greatest(0,hit.pos-901);
   insert into paperlab.deep_jobs(id,symbol,stage,model,doc_id,chunk_no,part_start,part_length,research_question,priority)values('gap:'||p_source_hash||':'||round_no||':'||spec.topic||':'||hit.id||':'||hit.n,p_symbol,'extract','gemini-3.5-flash-lite',hit.id,start_at/7000,start_at%7000,least(3500,length(hit.body)-start_at),spec.question,10000)on conflict do nothing;
   n:=n+1;
  end loop;
 end loop;
 insert into paperlab.dossier_gap_runs(symbol,source_hash,round,jobs)values(p_symbol,p_source_hash,round_no,n)on conflict do nothing;return n;
end$$;
revoke all on function paperlab.dossier_gap_work(text,text,jsonb)from public,anon,authenticated,service_role;

create or replace function paperlab.deep_plan()returns void language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare c paperlab.deep_companies;g text;p text;cov jsonb;annual boolean;interim boolean;ih text;progress int;focus text[];base_priority int;wanted_status text;source_set text;begin
 insert into paperlab.deep_companies(symbol,priority)select r.symbol,coalesce(q.priority,10)from paperlab.company_research r left join paperlab.research_queue q using(symbol)on conflict(symbol)do update set priority=excluded.priority where deep_companies.priority is distinct from excluded.priority;
 update paperlab.deep_jobs set model='gemini-3.5-flash-lite'where stage='extract'and status in('queued','retry')and model='gemini-3.8-flash';
 -- A daily, bounded second chance for exhausted validation leaves. Transient provider
 -- failures never consume this counter and continue under their provider cooldown.
 update paperlab.deep_jobs j set status='retry',available_at=now(),validation_attempts=0,recovery_cycles=recovery_cycles+1,model=case when stage='audit'then'gemini-3.8-flash'else'gemini-3.5-flash-lite'end where j.status='blocked'and j.stage in('extract','pillar','audit')and j.result->>'status'='invalid_response'and recovery_cycles<2 and available_at<=now()-interval'23 hours'and exists(select 1 from paperlab.deep_documents d where d.id=j.doc_id and d.active);
 for c in select *from paperlab.deep_companies loop
  if exists(select 1 from paperlab.earnings_cycles ec where ec.symbol=c.symbol and ec.release_at between now()-interval'2 days'and now()-interval'20 minutes'and not exists(select 1 from paperlab.deep_documents dd where dd.symbol=c.symbol and dd.active and dd.role='interim'and dd.known_at>=ec.release_at))and not exists(select 1 from paperlab.deep_jobs where symbol=c.symbol and stage='discover'and created_at>now()-interval'1 hour')then update paperlab.deep_companies set next_discovery=now()where symbol=c.symbol;c.next_discovery:=now();end if;
  if c.next_discovery<=now()and not exists(select 1 from paperlab.deep_jobs where symbol=c.symbol and stage='discover'and status in('queued','retry','leased'))then insert into paperlab.deep_jobs(id,symbol,stage,priority)values(c.symbol||':discover:'||to_char(now()at time zone'UTC','YYYYMMDDHH24MI'),c.symbol,'discover',c.priority-20)on conflict do nothing;end if;
  select encode(sha256(convert_to(coalesce(string_agg(id,'|'order by id),''),'UTF8')),'hex'),coalesce(bool_or(role='annual'and complete_extraction),false),coalesce(bool_or(role='interim'and complete_extraction and kind in('10-Q','6-K','official_report')),false)into g,annual,interim from paperlab.deep_documents where symbol=c.symbol and active and role<>'other';
  source_set:=g;
  -- Secondary-data revisions can refresh the six assessments without rereading
  -- unchanged full sources. Quote ticks and retrieval timestamps do not churn it.
  ih:=encode(sha256(convert_to(coalesce((select(record->'observation'->'values')::text from paperlab.company_coverage where symbol=c.symbol),'')||coalesce((select(record->'quarters')::text from paperlab.analyst_consensus where symbol=c.symbol),''),'UTF8')),'hex');
  g:=encode(sha256(convert_to(g||'|dossier-v2|'||ih||coalesce((select string_agg(z.id||':'||encode(sha256(convert_to(z.result::text,'UTF8')),'hex'),'|'order by z.id)from paperlab.deep_jobs z join paperlab.deep_documents d on d.id=z.doc_id where z.symbol=c.symbol and z.id like'gap:%'and z.status='completed'and jsonb_array_length(z.result->'claims')>0 and d.active),''),'UTF8')),'hex');
  if c.report is not null and c.report->>'generation'=g and c.status='dossier_completed_with_gaps'then perform paperlab.dossier_gap_work(c.symbol,source_set,c.dossier_gaps);end if;
  cov:=jsonb_build_object('annual_present',annual,'interim_present',interim,'active_documents',(select count(*)from paperlab.deep_documents where symbol=c.symbol and active and role<>'other'),
  'chunks_total',(select count(*)from paperlab.deep_jobs j join paperlab.deep_documents d on d.id=j.doc_id where j.symbol=c.symbol and j.stage='extract'and d.active and d.role<>'other'and j.status<>'superseded'),
  'chunks_completed',(select count(*)from paperlab.deep_jobs j join paperlab.deep_documents d on d.id=j.doc_id where j.symbol=c.symbol and j.stage='extract'and j.status='completed'and d.active and d.role<>'other'),
  'chunks_blocked',(select count(*)from paperlab.deep_jobs j join paperlab.deep_documents d on d.id=j.doc_id where j.symbol=c.symbol and j.stage='extract'and j.status='blocked'and d.active));
  progress:=(cov->>'chunks_completed')::int;
  update paperlab.deep_jobs set status='superseded'where symbol=c.symbol and generation is not null and generation<>g and status in('queued','retry','blocked');
  wanted_status:=case when(cov->>'active_documents')::int=0 then'waiting_documents'when(cov->>'chunks_blocked')::int>0 then'recovery_or_source_gap'when progress<(cov->>'chunks_total')::int then'reading_documents'when c.report is not null and c.report->>'generation'=g then case when c.report->>'full_ai_dossier'='true'then'full_ai_dossier_completed'else'dossier_completed_with_gaps'end else'assessing_pillars'end;
  update paperlab.deep_companies set generation=g,input_hash=ih,coverage=cov,status=wanted_status where symbol=c.symbol and(generation,input_hash,coverage,status)is distinct from(g,ih,cov,wanted_status);
  if not annual or not interim then perform paperlab.dossier_alert(c.symbol,'missing_official_reports',jsonb_build_object('annual_missing',not annual,'interim_missing',not interim));else update paperlab.dossier_alerts set resolved_at=now()where symbol=c.symbol and reason='missing_official_reports'and resolved_at is null;end if;
  if(cov->>'chunks_blocked')::int>0 then perform paperlab.dossier_alert(c.symbol,'validation_recovery',jsonb_build_object('blocked_leaves',cov->'chunks_blocked','next_automatic_retry','Daily for at most two recovery cycles; unresolved evidence remains a visible gap.'));else update paperlab.dossier_alerts set resolved_at=now()where symbol=c.symbol and reason='validation_recovery'and resolved_at is null;end if;
  if(cov->>'chunks_total')::int>0 and progress=(cov->>'chunks_total')::int then
   foreach p in array array['financial_position','cash_earnings','competitive_position','management','valuation','risks']loop insert into paperlab.deep_jobs(id,symbol,stage,model,pillar,generation,priority)values(c.symbol||':'||g||':'||p,c.symbol,'pillar','gemini-3.5-flash-lite',p,g,c.priority+20)on conflict do nothing;end loop;
   if(select count(*)from paperlab.deep_jobs where symbol=c.symbol and generation=g and stage='pillar'and status='completed')=6 then insert into paperlab.deep_jobs(id,symbol,stage,model,generation,priority)values(c.symbol||':'||g||':audit',c.symbol,'audit','gemini-3.8-flash',g,c.priority+30)on conflict do nothing;end if;
  end if;
  if coalesce(c.last_progress,c.queued_at)<now()-interval'24 hours'and exists(select 1 from paperlab.deep_jobs where symbol=c.symbol and priority>=10000 and status in('queued','retry','leased')and(stage in('extract','discover')or generation=g))then perform paperlab.dossier_alert(c.symbol,'progress_stalled',jsonb_build_object('last_progress',c.last_progress));else update paperlab.dossier_alerts set resolved_at=now()where symbol=c.symbol and reason='progress_stalled'and resolved_at is null;end if;
 end loop;
 -- Keep two complete-source dossiers in progress, with nearly finished ones first.
 select array_agg(symbol)into focus from(select dc.symbol from paperlab.deep_companies dc where exists(select 1 from paperlab.deep_jobs j where j.symbol=dc.symbol and j.status in('queued','retry','leased')and j.stage<>'discover'and(j.generation is null or j.generation=dc.generation))order by
 case when(dc.coverage->>'annual_present')::boolean and(dc.coverage->>'interim_present')::boolean then 1 else 0 end desc,
 case when dc.report is null then 1 else 0 end desc,
 (coalesce((dc.coverage->>'chunks_completed')::numeric,0)/greatest(1,coalesce((dc.coverage->>'chunks_total')::numeric,0)))desc,dc.priority desc,dc.symbol limit 2)x;
 update paperlab.dossier_automation set focus_symbols=coalesce(focus,array[]::text[])where singleton and focus_symbols is distinct from coalesce(focus,array[]::text[]);
 update paperlab.deep_jobs j set priority=least(900,coalesce((select priority from paperlab.deep_companies where symbol=j.symbol),10))+case when j.symbol=any(coalesce(focus,array[]::text[]))then 10000 else 0 end+case j.stage when'audit'then 30000 when'pillar'then 20000 when'extract'then 0 else case when exists(select 1 from paperlab.earnings_cycles ec where ec.symbol=j.symbol and ec.release_at between now()-interval'2 days'and now()-interval'20 minutes'and not exists(select 1 from paperlab.deep_documents dd where dd.symbol=j.symbol and dd.active and dd.role='interim'and dd.known_at>=ec.release_at))then 40000 else -100 end end where j.status in('queued','retry')and(j.generation is null or j.generation=(select generation from paperlab.deep_companies where symbol=j.symbol))and j.priority is distinct from(least(900,coalesce((select priority from paperlab.deep_companies where symbol=j.symbol),10))+case when j.symbol=any(coalesce(focus,array[]::text[]))then 10000 else 0 end+case j.stage when'audit'then 30000 when'pillar'then 20000 when'extract'then 0 else case when exists(select 1 from paperlab.earnings_cycles ec where ec.symbol=j.symbol and ec.release_at between now()-interval'2 days'and now()-interval'20 minutes'and not exists(select 1 from paperlab.deep_documents dd where dd.symbol=j.symbol and dd.active and dd.role='interim'and dd.known_at>=ec.release_at))then 40000 else -100 end end);
end$$;
revoke all on function paperlab.deep_plan()from public,anon,authenticated,service_role;
create or replace function public.paper_deep_claim()returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare r paperlab.deep_runtime;j paperlab.deep_jobs;b paperlab.deep_models;doc paperlab.deep_documents;d date:=(now()at time zone'America/Los_Angeles')::date;m date:=date_trunc('month',now()at time zone'UTC')::date;mi timestamptz:=date_trunc('minute',now());t uuid;payload jsonb;source text;charge bigint;token_bound int;begin
 select *into r from paperlab.deep_runtime where singleton for update;if not r.enabled or r.lease_until>now()then return null;end if;
 update paperlab.deep_jobs set status='retry',available_at=now()+interval'1 minute',token=null,lease_until=null where status='leased'and lease_until<=now();
 if r.month is distinct from m then r.estimated_bytes:=0;end if;
 update paperlab.deep_models set day=d,used=0 where day is distinct from d;
 update paperlab.deep_models set minute=mi,minute_used=0,minute_tokens=0 where minute is distinct from mi;
 perform paperlab.deep_plan();
 select x.*into j from paperlab.deep_jobs x left join paperlab.deep_models bm on bm.model=x.model left join paperlab.deep_models hm on hm.model='gemini-3.8-flash' left join paperlab.deep_models fm on fm.model='gemini-3-flash-preview' where x.status in('queued','retry')and(x.available_at<=now()or(x.stage='audit'and x.model='gemini-3.8-flash'and x.result->>'status'='provider_unavailable'and coalesce(x.result->>'provider_http_status','503')in('500','502','503','504')and hm.provider_failures>=3))and(x.model is null or(bm.used<bm.daily_limit and bm.minute_used<bm.rpm and bm.minute_tokens+100000<=bm.tpm and coalesce(bm.retry_after,'-infinity')<=now()and(x.model='gemini-3.5-flash-lite'or(select sum(used)from paperlab.deep_models where model in('gemini-3.8-flash','gemini-2.5-flash','gemini-3-flash-preview'))<20))or(x.stage='extract'and x.model='gemini-3.5-flash-lite'and(bm.used>=bm.daily_limit or bm.retry_after>now())and hm.used<hm.daily_limit-2 and(select sum(used)from paperlab.deep_models where model in('gemini-3.8-flash','gemini-2.5-flash','gemini-3-flash-preview'))<18 and hm.minute_used<hm.rpm and hm.minute_tokens+100000<=hm.tpm and coalesce(hm.retry_after,'-infinity')<=now())or(x.stage='audit'and x.model='gemini-3.8-flash'and hm.provider_failures>=3 and hm.last_status='provider_unavailable'and fm.used<fm.daily_limit and fm.minute_used<fm.rpm and fm.minute_tokens+100000<=fm.tpm and coalesce(fm.retry_after,'-infinity')<=now()and(select sum(used)from paperlab.deep_models where model in('gemini-3.8-flash','gemini-2.5-flash','gemini-3-flash-preview'))<20))and(x.generation is null or x.generation=(select generation from paperlab.deep_companies where symbol=x.symbol))order by x.priority desc,case x.stage when 'audit'then 0 when 'pillar'then 1 when 'extract'then 2 else 3 end,x.created_at,x.doc_id,x.chunk_no limit 1 for update of x;
 if not found then update paperlab.deep_runtime set status='waiting_work_or_quota'where singleton;return null;end if;
 if j.stage='audit'and j.model='gemini-3.8-flash'and exists(select 1 from paperlab.deep_models where model=j.model and provider_failures>=3 and(retry_after>now()or minute_used>=rpm or minute_tokens+100000>tpm)and last_status='provider_unavailable')then j.model:='gemini-3-flash-preview';update paperlab.deep_jobs set model=j.model where id=j.id;end if;
 if j.model='gemini-3.5-flash-lite'and j.stage='extract'and exists(select 1 from paperlab.deep_models where model=j.model and(used>=daily_limit or retry_after>now()))then j.model:='gemini-3.8-flash';update paperlab.deep_jobs set model=j.model where id=j.id;end if;
 if j.stage='extract'then
  select *into doc from paperlab.deep_documents where id=j.doc_id and active;
  if not found then update paperlab.deep_jobs set status='superseded'where id=j.id;return null;end if;
  if doc.body=''then update paperlab.deep_runtime set status='cache_restore_required'where singleton;return null;end if;
  source:=substring(doc.body from j.chunk_no*7000+j.part_start+1 for j.part_length);
  payload:=jsonb_build_object('symbol',j.symbol,'research_question',j.research_question,'source',jsonb_build_object('id',doc.id,'url',doc.url,'sha256',doc.sha256,'body_sha256',doc.body_sha256,'known_at',doc.known_at,'role',doc.role,'scope',doc.scope,'complete_extraction',doc.complete_extraction,'chunk',j.chunk_no,'chunks',doc.chunks,'offset',j.chunk_no*7000+j.part_start,'preceding_context',substring(doc.body from greatest(1,j.chunk_no*7000+j.part_start-350)for least(350,j.chunk_no*7000+j.part_start)),'header',left(doc.body,700),'text',source));
 elsif j.stage='discover'then
  select jsonb_build_object('symbol',j.symbol,'sources',coalesce((select record->'sources'from paperlab.scoped_research where symbol=j.symbol order by recorded_at desc limit 1),'[]'::jsonb)||coalesce(c.record->'sources','[]'::jsonb),'known_urls',(select coalesce(jsonb_agg(url),'[]')from paperlab.deep_documents where symbol=j.symbol),'cik',c.record->>'cik','offset',(select discovery_offset from paperlab.deep_companies where symbol=j.symbol))into payload from paperlab.company_research c where symbol=j.symbol;
 else
  payload:=jsonb_build_object('symbol',j.symbol,'pillar',j.pillar,'fact_selection',jsonb_build_object('context_limit',case when j.stage='audit'then 36 else case j.repair_round when 0 then 60 when 1 then 30 else 15 end end,'total_extracted_facts',(select coalesce(sum(jsonb_array_length(z.result->'claims')),0)from paperlab.deep_jobs z join paperlab.deep_documents sd on sd.id=z.doc_id where z.symbol=j.symbol and z.stage='extract'and z.status='completed'and sd.active),'scope','Topic-ranked selection of extracted facts; original full texts remain cached. Do not infer exhaustive audit.'),'coverage',(select coverage from paperlab.deep_companies where symbol=j.symbol),'facts',(select coalesce(jsonb_agg(v),'[]')from(select jsonb_build_object('id',z.id||':'||(f.ordinality-1),'finding',case when j.stage='audit'then null else f.value->>'finding'end,'topic',f.value->>'topic','quote',f.value->>'quote','period',f.value->>'period','basis',f.value->>'basis','source_id',z.doc_id,'url',case when j.stage='audit'then null else s.url end,'context',substring(s.body from greatest(1,z.chunk_no*7000+z.part_start+strpos(substring(s.body from z.chunk_no*7000+z.part_start+1 for z.part_length),f.value->>'quote')-case when j.stage='audit'then 150 else 350 end)for case when j.stage='audit'then 400 else 1000 end))v from paperlab.deep_jobs z join paperlab.deep_documents s on s.id=z.doc_id cross join lateral jsonb_array_elements(z.result->'claims')with ordinality f(value,ordinality)where z.symbol=j.symbol and z.stage='extract'and z.status='completed'and s.active and(j.stage<>'audit'or z.id||':'||(f.ordinality-1) in(select jsonb_array_elements_text(result->'evidence_ids')from paperlab.deep_jobs where symbol=j.symbol and generation=j.generation and stage='pillar'and status='completed')) order by case when f.value->>'topic'=j.pillar then 0 when j.pillar='valuation'and f.value->>'topic'='cash_earnings'then 1 else 2 end,case when z.id like'gap:%'then 0 else 1 end,s.known_at desc,z.chunk_no limit case when j.stage='audit'then 36 else case j.repair_round when 0 then 60 when 1 then 30 else 15 end end)a),'pillars',case when j.stage='audit'then(select coalesce(jsonb_agg(jsonb_build_object('pillar',pillar,'result',result)),'[]')from paperlab.deep_jobs where symbol=j.symbol and generation=j.generation and stage='pillar'and status='completed')else '[]'::jsonb end,'peer_context',paperlab.dossier_peers(j.symbol),'financial_context',(select jsonb_build_object('source_url',record->>'source_url','source_hash',record->>'source_hash','known_at',record->>'secondary_checked_at','quote',(select jsonb_build_object('price',case when(state->'last_observation'->j.symbol->>'time')::timestamptz between now()-interval'7 days'and now()then state->'prices'->j.symbol else null end,'bid',state->'last_observation'->j.symbol->'bid','ask',state->'last_observation'->j.symbol->'ask','currency',(select value->>'currency'from paperlab.company_coverage_runtime cr,jsonb_array_elements(cr.catalogue)where value->>'symbol'=j.symbol limit 1),'time',state->'last_observation'->j.symbol->>'time')from paperlab.portfolio limit 1),'values',record->'observation'->'values','independently_verified',false)from paperlab.company_coverage where symbol=j.symbol),'consensus',(select record from paperlab.analyst_consensus where symbol=j.symbol));
 end if;
 if j.stage in('pillar','audit')then payload:=payload||jsonb_build_object('source_manifest',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'url',url,'role',role,'kind',kind,'known_at',known_at,'scope',scope,'complete_extraction',complete_extraction,'header',left(body,400))),'[]')from paperlab.deep_documents where symbol=j.symbol and active));end if;payload:=paperlab.dossier_context(payload||jsonb_build_object('stage',j.stage));
 charge:=case when j.stage='discover'then 500000 else 2*octet_length(payload::text)+25000 end;
 insert into paperlab.free_usage(month)values(m)on conflict do nothing;perform 1 from paperlab.free_usage where month=m for update;
 if r.estimated_bytes+charge>1200000000 or(select estimated_worker_egress_bytes+charge from paperlab.free_usage where month=m)>paperlab.traffic_limit('soft')or pg_database_size(current_database())>paperlab.storage_limit('hard') then perform paperlab.dossier_alert(j.symbol,'storage_or_transfer_guard',jsonb_build_object('database_bytes',pg_database_size(current_database())));update paperlab.deep_runtime set status='storage_or_transfer_budget_guard'where singleton;return null;end if;
 if j.model is not null then
  token_bound:=octet_length(payload::text)+16000;
  if token_bound>96000 then perform paperlab.dossier_alert(j.symbol,'input_context_large');update paperlab.deep_jobs set status='blocked',result=jsonb_build_object('status','invalid_response','reason','bounded_input_exceeded')where id=j.id;return null;end if;
  select *into b from paperlab.deep_models where model=j.model for update;
  update paperlab.deep_models set used=used+1,minute_used=minute_used+1,minute_tokens=minute_tokens+token_bound,last_status='reserved'where model=j.model;
 end if;
 t:=gen_random_uuid();update paperlab.deep_jobs set status='leased',token=t,lease_until=now()+interval'240 seconds',attempts=attempts+1 where id=j.id;
 update paperlab.deep_runtime set token=t,lease_until=now()+interval'240 seconds',job_id=j.id,last_attempt=now(),status='processing_'||j.stage,transfer_reserved=0,month=m,estimated_bytes=r.estimated_bytes+charge where singleton;
 update paperlab.free_usage set estimated_worker_egress_bytes=estimated_worker_egress_bytes+charge where month=m;
 return jsonb_build_object('token',t,'job',jsonb_build_object('id',j.id,'symbol',j.symbol,'stage',j.stage,'model',j.model,'pillar',j.pillar,'repair_round',j.repair_round),'input',payload);
end$$;
create or replace function public.paper_deep_commit(p_token uuid,p_result jsonb)returns boolean language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare j paperlab.deep_jobs;b paperlab.deep_models;doc paperlab.deep_documents;source text;x jsonb;h text;retry timestamptz;success boolean;full_report boolean;source_id text;fact_index int;half int;child int;failures int;delay int;begin
 select *into j from paperlab.deep_jobs where token=p_token and status='leased'and lease_until>now()for update;if not found then return false;end if;
 if j.generation is not null and j.generation is distinct from(select generation from paperlab.deep_companies where symbol=j.symbol)then update paperlab.deep_jobs set status='superseded',token=null,lease_until=null where id=j.id;update paperlab.deep_runtime set token=null,lease_until=null,job_id=null where singleton;return false;end if;
 if octet_length(p_result::text)>40000 or p_result->>'trade_approval'is distinct from'false'or p_result->>'independently_verified'is distinct from'false'or p_result->>'status'not in('completed','rate_limited','provider_unavailable','invalid_response','source_unavailable','blocked_source')then raise exception 'Bounded research-only result required';end if;
 success:=p_result->>'status'='completed';
 if success and j.stage='extract'then
  select *into doc from paperlab.deep_documents where id=j.doc_id;source:=substring(doc.body from j.chunk_no*7000+j.part_start+1 for j.part_length);
  if jsonb_typeof(p_result->'claims')is distinct from'array'or jsonb_array_length(p_result->'claims')>8 or(jsonb_array_length(p_result->'claims')=0 and p_result->>'no_material_information'is distinct from'true')then raise exception 'Facts or explicit empty passage required';end if;
  for x in select value from jsonb_array_elements(p_result->'claims')loop if coalesce(x->>'topic','')not in('financial_position','cash_earnings','competitive_position','management','valuation','risks','material_events','expectations')or length(coalesce(x->>'finding',''))not between 20 and 1000 or length(coalesce(x->>'quote',''))not between 10 and 220 or strpos(source,x->>'quote')=0 then raise exception 'Exact passage evidence required';end if;end loop;
 elsif success and j.stage='pillar'then
  if p_result->>'pillar'is distinct from j.pillar or length(coalesce(p_result->>'assessment',''))not between 60 and 8000 or jsonb_typeof(p_result->'evidence_ids')is distinct from'array'or jsonb_array_length(p_result->'evidence_ids')>30 or jsonb_typeof(p_result->'limitations')is distinct from'array'or p_result->>'requires_more_data'not in('true','false')or(p_result->>'requires_more_data'='false'and jsonb_array_length(p_result->'evidence_ids')=0)then raise exception 'Sourced pillar required';end if;
  for h in select jsonb_array_elements_text(p_result->'evidence_ids')loop
   if h in('secondary_financials','valuation_scenarios','peer_context')then continue;end if;
   source_id:=regexp_replace(h,':[0-9]+$','');fact_index:=substring(h from':([0-9]+)$')::int;
   if fact_index is null or not exists(select 1 from paperlab.deep_jobs where id=source_id and symbol=j.symbol and stage='extract'and status='completed'and result->'claims'->fact_index is not null)then raise exception 'Unknown fact citation';end if;
  end loop;
 elsif success and j.stage='audit'then
  if jsonb_typeof(p_result->'checks')is distinct from'array'or jsonb_array_length(p_result->'checks')<>6 or(select count(distinct av.value->>'pillar')from jsonb_array_elements(p_result->'checks')av(value))<>6 or length(coalesce(p_result->>'summary',''))not between 80 and 8000 then raise exception 'Six-pillar final audit required';end if;
  for x in select value from jsonb_array_elements(p_result->'checks')loop if x->>'pillar'not in('financial_position','cash_earnings','competitive_position','management','valuation','risks')or x->>'supported'not in('true','false')then raise exception 'Invalid audit check';end if;end loop;
 end if;
 if success then
  update paperlab.deep_companies set last_progress=now()where symbol=j.symbol;
  update paperlab.deep_jobs set status='completed',result=p_result,completed_at=now(),token=null,lease_until=null where id=j.id;
  if j.stage='discover'then update paperlab.deep_companies set discovery_offset=discovery_offset+3 where symbol=j.symbol;end if;
  if j.stage='audit'then
   full_report:=coalesce(((select coverage->>'annual_present'from paperlab.deep_companies where symbol=j.symbol)::boolean),false)and coalesce(((select coverage->>'interim_present'from paperlab.deep_companies where symbol=j.symbol)::boolean),false)and not exists(select 1 from jsonb_array_elements(p_result->'checks')av(value)where av.value->>'supported'is distinct from'true')and not exists(select 1 from paperlab.deep_jobs where symbol=j.symbol and generation=j.generation and stage='pillar'and result->>'requires_more_data'is distinct from'false');
   update paperlab.deep_companies set audit=p_result,report=jsonb_build_object('generation',j.generation,'completed_at',now(),'coverage',coverage,'full_company_analysis',false,'full_ai_dossier',full_report,'protocol_version',2,'market_context',p_result->'market_context','source_manifest',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'url',url,'role',role,'sha256',sha256,'known_at',known_at,'scope',scope,'complete_extraction',complete_extraction)),'[]')from paperlab.deep_documents where symbol=j.symbol and active),'independently_verified',false,'trade_approval',false,'pillars',(select jsonb_agg(jsonb_build_object('pillar',pillar,'result',result))from paperlab.deep_jobs where symbol=j.symbol and generation=j.generation and stage='pillar'and status='completed'),'audit',p_result),last_completed=now(),status=case when full_report then 'full_ai_dossier_completed'else 'dossier_completed_with_gaps'end where symbol=j.symbol;
   insert into paperlab.dossier_history(symbol,completed_at,record)select symbol,last_completed,report from paperlab.deep_companies where symbol=j.symbol on conflict do nothing;
   delete from paperlab.dossier_history where symbol=j.symbol and completed_at in(select completed_at from paperlab.dossier_history where symbol=j.symbol order by completed_at desc offset 4);
   update paperlab.deep_companies set dossier_gaps=coalesce(p_result->'missing_information','[]'),next_discovery=case when full_report then next_discovery else least(next_discovery,now()+interval'6 hours')end where symbol=j.symbol;
   if not full_report then perform paperlab.dossier_alert(j.symbol,'dossier_evidence_gaps',jsonb_build_object('missing_information',p_result->'missing_information'));else update paperlab.dossier_alerts set resolved_at=now()where symbol=j.symbol and reason='dossier_evidence_gaps'and resolved_at is null;end if;
  end if;
 else
  update paperlab.deep_jobs set validation_attempts=validation_attempts+case when p_result->>'status'='invalid_response'then 1 else 0 end where id=j.id returning *into j;
  retry:=case when p_result->>'status'in('rate_limited','provider_unavailable')then paperlab.gemini_retry_time(p_result)when p_result->>'status'='invalid_response'then now()+make_interval(secs=>least(300,60*greatest(1,j.validation_attempts)))else now()+interval'1 hour'end;
  if p_result->>'status'='provider_unavailable'and j.model is not null and(coalesce((p_result->>'provider_http_status')::int,503)in(500,502,503,504))then select provider_failures+1 into failures from paperlab.deep_models where model=j.model;delay:=greatest(least(900,(30*power(2,least(5,failures-1)))::int),coalesce((p_result->>'retry_after_seconds')::int,0));retry:=now()+make_interval(secs=>delay);update paperlab.deep_models set provider_failures=failures where model=j.model;end if;
  update paperlab.deep_jobs set status=case when p_result->>'status'='blocked_source'or(p_result->>'status'='invalid_response'and j.validation_attempts>=3)then'blocked'else'retry'end,available_at=retry,result=p_result,token=null,lease_until=null where id=j.id;
  if p_result->>'status'='invalid_response'and j.validation_attempts>=3 and j.stage='extract'and j.repair_round<2 and j.part_length>1000 then
   half:=ceil(j.part_length/2.0)::int;
   for child in 0..1 loop insert into paperlab.deep_jobs(id,symbol,stage,model,doc_id,chunk_no,parent_id,part_start,part_length,repair_round,priority)values(j.id||':part:'||child,j.symbol,'extract','gemini-3.5-flash-lite',j.doc_id,j.chunk_no,j.id,j.part_start+child*half,case when child=0 then half else j.part_length-half end,j.repair_round+1,j.priority)on conflict do nothing;end loop;
   update paperlab.deep_jobs set status='superseded'where id=j.id;
  elsif p_result->>'status'='invalid_response'and j.validation_attempts>=3 and j.stage in('pillar','audit')and j.repair_round<2 then
   update paperlab.deep_jobs set status='retry',available_at=now()+interval'5 minutes',validation_attempts=0,repair_round=repair_round+1 where id=j.id;
  elsif p_result->>'status'='invalid_response'and j.validation_attempts>=3 then perform paperlab.dossier_alert(j.symbol,'validation_recovery',jsonb_build_object('job',j.id,'validation_reason',p_result->>'validation_reason'));
  end if;
  if j.stage='extract'then update paperlab.deep_jobs set model='gemini-3.5-flash-lite'where id=j.id and status='retry';end if;
 end if;
 if j.model is not null then
  update paperlab.deep_models set retry_after=case when p_result->>'status'in('rate_limited','provider_unavailable')then retry when success then null else retry_after end,provider_failures=case when p_result->>'status'in('completed','invalid_response')then 0 else provider_failures end,last_status=p_result->>'status',used=greatest(0,used-case when p_result->>'attempted_calls'='0'then 1 else 0 end)where model=j.model;
 end if;
 insert into paperlab.deep_events(symbol,event,record)values(j.symbol,case when success then j.stage||'_completed'else j.stage||'_saved_for_retry'end,jsonb_build_object('job',j.id,'model',j.model,'status',p_result->>'status','retry_after',retry,'attempts',j.attempts,'validation_attempts',j.validation_attempts,'validation_reason',p_result->>'validation_reason'));
 delete from paperlab.deep_events where id in(select id from paperlab.deep_events order by id desc offset 3000);
 update paperlab.deep_runtime set token=null,lease_until=null,job_id=null,status=p_result->>'status',last_success=case when success then now()else last_success end where singleton;
 return true;
end$$;
-- Independent SQL watchdog; respects owner pauses and never changes trade rules.
create or replace function public.paper_dossier_watchdog()returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$declare r paperlab.deep_runtime;active_job boolean;ready boolean;secret text;request_id bigint;begin
 select *into r from paperlab.deep_runtime where singleton;if not r.enabled then return jsonb_build_object('status','owner_paused');end if;
 perform paperlab.deep_plan();
 select coalesce(bool_or(active),false)into active_job from cron.job where jobname='paperlab-deep-research';
 if not active_job then perform paperlab.dossier_alert(null,'engine_scheduler_inactive');return jsonb_build_object('status','scheduler_inactive_owner_action_respected');end if;
 update paperlab.dossier_alerts set resolved_at=now()where id='project:engine_scheduler_inactive'and resolved_at is null;
 select exists(select 1 from paperlab.deep_jobs j left join paperlab.deep_models m on m.model=j.model where j.status in('queued','retry')and j.available_at<=now()and(j.generation is null or j.generation=(select generation from paperlab.deep_companies where symbol=j.symbol))and(j.model is null or((m.day is distinct from(now()at time zone'America/Los_Angeles')::date or m.used<m.daily_limit)and coalesce(m.retry_after,'-infinity')<=now())))into ready;
 if ready and coalesce(r.last_attempt,'-infinity')<now()-interval'15 minutes'and coalesce(r.lease_until,'-infinity')<=now()and pg_database_size(current_database())<paperlab.storage_limit('hard')and coalesce((select estimated_worker_egress_bytes from paperlab.free_usage where month=date_trunc('month',now()at time zone'UTC')::date),0)<paperlab.traffic_limit('soft')and(r.month is distinct from date_trunc('month',now()at time zone'UTC')::date or r.estimated_bytes<1200000000)then
  select decrypted_secret into secret from vault.decrypted_secrets where name='paperlab_cron_token';
  if coalesce(secret,'')=''then perform paperlab.dossier_alert(null,'engine_auth_missing');return jsonb_build_object('status','cron_auth_missing');end if;
  perform paperlab.dossier_alert(null,'engine_watchdog_wakeup',jsonb_build_object('last_attempt',r.last_attempt));
  select net.http_post(url:='https://kdyzlbknygeqinqduuic.supabase.co/functions/v1/paper-deep-research',headers:=jsonb_build_object('Content-Type','application/json','X-PaperLab-Cron',secret),body:='{}'::jsonb,timeout_milliseconds:=120000)into request_id;
  return jsonb_build_object('status','worker_wakeup_queued');
 end if;
 if r.last_success>now()-interval'1 hour'then update paperlab.dossier_alerts set resolved_at=now()where id='project:engine_watchdog_wakeup'and resolved_at is null;end if;
 return jsonb_build_object('status','monitored','ready_work',ready);
end$$;
revoke all on function public.paper_dossier_watchdog()from public,anon,authenticated,service_role;

create or replace function public.paper_dossier_automation_read(p_owner uuid,p_symbol text default null)returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton)then raise exception 'Owner required';end if;
 return jsonb_build_object('policy',(select policy from paperlab.dossier_automation where singleton),'heavy_pool',jsonb_build_object('daily_limit',20,'used',(select coalesce(sum(case when day=(now()at time zone'America/Los_Angeles')::date then used else 0 end),0)from paperlab.deep_models where model in('gemini-3.8-flash','gemini-2.5-flash','gemini-3-flash-preview'))),'alerts',(select coalesce(jsonb_agg(to_jsonb(a)order by last_seen desc),'[]')from(select symbol,reason,severity,opened_at,last_seen,record from paperlab.dossier_alerts where resolved_at is null and(p_symbol is null or symbol=p_symbol)order by last_seen desc limit 100)a),
 'progress',(select coalesce(jsonb_agg(to_jsonb(c)order by priority desc,symbol),'[]')from(select symbol,priority,coverage,status,last_progress,last_completed,dossier_gaps,case when report is not null then report->>'generation'is distinct from generation else false end report_stale,(select count(*)from paperlab.deep_jobs j where j.symbol=dc.symbol and j.generation=dc.generation and j.stage='pillar'and j.status='completed')pillars_completed,(select coalesce(jsonb_agg(jsonb_build_object('pillar',pillar,'assessment',result->>'assessment','requires_more_data',result->'requires_more_data')),'[]')from paperlab.deep_jobs j where j.symbol=dc.symbol and j.generation=dc.generation and j.stage='pillar'and j.status='completed')pillar_previews from paperlab.deep_companies dc where p_symbol is null or symbol=p_symbol order by priority desc,symbol limit 100)c),
 'evidence',case when p_symbol is null then '[]'::jsonb else(select coalesce(jsonb_agg(v),'[]')from(select distinct on(e.value)jsonb_build_object('id',e.value,'symbol',dc.symbol,'finding',f.value->>'finding','quote',f.value->>'quote','period',f.value->>'period','basis',f.value->>'basis','url',d.url,'source_sha256',d.sha256,'known_at',d.known_at)v from paperlab.deep_companies dc cross join lateral jsonb_array_elements(dc.report->'pillars')p cross join lateral jsonb_array_elements_text(p->'result'->'evidence_ids')e(value)join paperlab.deep_jobs z on z.symbol=dc.symbol and z.status='completed'and z.stage='extract'cross join lateral jsonb_array_elements(z.result->'claims')with ordinality f(value,ordinality)join paperlab.deep_documents d on d.id=z.doc_id where dc.symbol=p_symbol and e.value=z.id||':'||(f.ordinality-1)order by e.value limit 36)x)end,
 'focus',(select to_jsonb(focus_symbols)from paperlab.dossier_automation where singleton),
 'note','Dossiers afronden heeft voorrang. Tijdelijke provideruitval bewaart voortgang. Ongeldige antwoorden krijgen gerichte herpogingen en kleinere bronblokken; blijvende bewijsproblemen blijven zichtbaar. Ontbrekende bronnen worden opnieuw gezocht. Een compleet AI-dossier is geen onafhankelijke audit of handelsgoedkeuring.');
end$$;
do $$begin if to_regprocedure('public.paper_deep_read_automation_base_v1(uuid,text)')is null then alter function public.paper_deep_read(uuid,text)rename to paper_deep_read_automation_base_v1;end if;end$$;
create or replace function public.paper_deep_read(p_owner uuid,p_symbol text default null)returns jsonb language sql security definer set search_path=pg_catalog,pg_temp as $$select public.paper_deep_read_automation_base_v1(p_owner,p_symbol)||jsonb_build_object('automation',public.paper_dossier_automation_read(p_owner,p_symbol))$$;
revoke all on function public.paper_dossier_automation_read(uuid,text),public.paper_deep_read_automation_base_v1(uuid,text),public.paper_deep_read(uuid,text)from public,anon,authenticated,service_role;
grant execute on function public.paper_dossier_automation_read(uuid,text),public.paper_deep_read(uuid,text)to service_role;
commit;
