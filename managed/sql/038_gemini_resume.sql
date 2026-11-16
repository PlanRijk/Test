-- Preserve model progress through provider outages and quota resets; no trading changes.
begin;
alter table paperlab.gemini_pending add column if not exists retry_after timestamptz not null default now();
alter table paperlab.gemini_pending add column if not exists slot_reserved boolean not null default true;
alter table paperlab.gemini_pending add column if not exists reserved_day date not null default((now()at time zone'America/Los_Angeles')::date);
alter table paperlab.gemini_pending add column if not exists reserved_month date not null default(date_trunc('month',now()at time zone'UTC')::date);
alter table paperlab.gemini_pending add column if not exists attempts integer not null default 0;
alter table paperlab.gemini_runtime add column if not exists retry_after timestamptz;
alter table paperlab.gemini_runtime add column if not exists quota_evidence jsonb;
alter table paperlab.gemini_runtime add column if not exists daily_request_limit integer not null default 4 check(daily_request_limit between 1 and 120);
alter table paperlab.gemini_runtime add column if not exists monthly_request_limit integer not null default 120 check(monthly_request_limit between 1 and 3600);
create table if not exists paperlab.gemini_progress_events(id bigserial primary key,at timestamptz not null default now(),symbol text not null,event text not null,record jsonb not null check(octet_length(record::text)<=4000));
alter table paperlab.gemini_progress_events enable row level security;
revoke all on paperlab.gemini_progress_events from public,anon,authenticated,service_role;
create or replace function paperlab.gemini_retry_time(p jsonb)returns timestamptz language plpgsql stable set search_path=pg_catalog,pg_temp as $$declare seconds int;begin
 if p->>'status'not in('rate_limited','provider_unavailable')then return null;end if;
 if p->>'status'='rate_limited'and p->>'quota_kind'='day'then return(((now()at time zone'America/Los_Angeles')::date+1)+time'00:01')at time zone'America/Los_Angeles';end if;
 if coalesce(p->>'retry_after_seconds','')~'^[0-9]{1,5}$'then seconds:=greatest(60,least(86400,(p->>'retry_after_seconds')::int));else seconds:=case when p->>'status'='rate_limited'then 3600 else 900 end;end if;
 return now()+make_interval(secs=>seconds);
end$$;
revoke all on function paperlab.gemini_retry_time(jsonb)from public,anon,authenticated,service_role;

create or replace function public.paper_gemini_claim()returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare r paperlab.gemini_runtime;chosen text;d date:=(now()at time zone'America/Los_Angeles')::date;m date:=date_trunc('month',now()at time zone'UTC')::date;t uuid;target jsonb;pending jsonb;pending_symbol text;reserved boolean;reservation_day date;reservation_month date;cost integer;begin
 select *into r from paperlab.gemini_runtime where singleton for update;
 if not r.enabled or r.free_tier_confirmed_at is null or r.lease_until>now()then return null;end if;
 if r.day is distinct from d then r.daily_reserved:=0;end if;if r.month is distinct from m then r.monthly_reserved:=0;r.estimated_bytes:=0;end if;
 if r.retry_after>now()then update paperlab.gemini_runtime set status='waiting_provider_retry'where singleton;return null;end if;
 select symbol,record,slot_reserved,reserved_day,reserved_month into pending_symbol,pending,reserved,reservation_day,reservation_month from paperlab.gemini_pending where retry_after<=now()order by created_at limit 1 for update;
 if pending is not null then
  cost:=case when reserved and reservation_day=d and reservation_month=m then 0 else 1 end;
  if r.daily_reserved+cost>(case when r.bootstrap_day=d then greatest(16,r.daily_request_limit) else r.daily_request_limit end)or r.monthly_reserved+cost>r.monthly_request_limit then update paperlab.gemini_runtime set status='request_budget_guard'where singleton;return null;end if;
  if cost=1 then
   insert into paperlab.free_usage(month)values(m)on conflict do nothing;perform 1 from paperlab.free_usage where month=m for update;
   if r.estimated_bytes+500000>600000000 or(select estimated_worker_egress_bytes+500000 from paperlab.free_usage where month=m)>paperlab.traffic_limit('soft')then update paperlab.gemini_runtime set status='storage_or_transfer_budget_guard'where singleton;return null;end if;
   update paperlab.free_usage set estimated_worker_egress_bytes=estimated_worker_egress_bytes+500000 where month=m;r.estimated_bytes:=r.estimated_bytes+500000;
  end if;
  update paperlab.gemini_pending set slot_reserved=false,attempts=attempts+1 where symbol=pending_symbol;
  t:=gen_random_uuid();update paperlab.gemini_runtime set day=d,daily_reserved=r.daily_reserved+cost,month=m,monthly_reserved=r.monthly_reserved+cost,estimated_bytes=r.estimated_bytes,token=t,lease_until=now()+interval'150 seconds',target=pending_symbol,phase='review',last_attempt=now(),status='processing_review'where singleton;
  return jsonb_build_object('token',t,'model',r.model,'phase','review','target',jsonb_build_object('symbol',pending_symbol),'pending',pending);
 end if;
 if r.daily_reserved+2>(case when r.bootstrap_day=d then greatest(16,r.daily_request_limit) else r.daily_request_limit end)or r.monthly_reserved+2>r.monthly_request_limit then update paperlab.gemini_runtime set status='request_budget_guard'where singleton;return null;end if;
 insert into paperlab.gemini_research(symbol)select symbol from paperlab.company_research on conflict do nothing;
 select g.symbol into chosen from paperlab.gemini_research g left join paperlab.research_queue q using(symbol)where g.next_check<=now()order by exists(select 1 from paperlab.earnings_cycles c where c.symbol=g.symbol and c.release_at between now()-interval'7 days'and now()+interval'3 days')desc,(g.checked_at is null)desc,coalesce(q.priority,0)desc,g.next_check,g.symbol limit 1;
 if chosen is null then return null;end if;
 insert into paperlab.free_usage(month)values(m)on conflict do nothing;perform 1 from paperlab.free_usage where month=m for update;
 if r.estimated_bytes+5000000>600000000 or(select estimated_worker_egress_bytes+5000000 from paperlab.free_usage where month=m)>paperlab.traffic_limit('soft')or pg_database_size(current_database())>100000000 or pg_total_relation_size('paperlab.gemini_research_history')>8000000 then update paperlab.gemini_runtime set status='storage_or_transfer_budget_guard'where singleton;return null;end if;
 select jsonb_build_object('symbol',chosen,'name',c.record->>'name','cik',c.record->>'cik','sources',coalesce((select record->'sources'from paperlab.scoped_research where symbol=chosen order by recorded_at desc limit 1),'[]'::jsonb)||coalesce(c.record->'sources','[]'::jsonb),'consensus',(select record from paperlab.analyst_consensus where symbol=chosen),'earnings',(select jsonb_build_object('release_at',release_at,'call_at',call_at)from paperlab.earnings_cycles where symbol=chosen and status<>'superseded_unconfirmed'order by created_at desc limit 1))into target from paperlab.company_research c where c.symbol=chosen;
 t:=gen_random_uuid();update paperlab.gemini_runtime set day=d,daily_reserved=r.daily_reserved+2,month=m,monthly_reserved=r.monthly_reserved+2,estimated_bytes=r.estimated_bytes+5000000,token=t,lease_until=now()+interval'240 seconds',target=chosen,phase='analysis',last_attempt=now(),status='processing'where singleton;
 update paperlab.free_usage set estimated_worker_egress_bytes=estimated_worker_egress_bytes+5000000 where month=m;
 return jsonb_build_object('token',t,'model',r.model,'phase','analysis','target',target,'max_calls',2);
end$$;
create or replace function public.paper_gemini_stage(p_token uuid,p_pending jsonb)returns boolean language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare r paperlab.gemini_runtime;v_claim jsonb;begin
 select *into r from paperlab.gemini_runtime where singleton and token=p_token and lease_until>now()and phase='analysis'for update;if not found then return false;end if;
 if p_pending->>'version'is distinct from'gemini-pending-v1'or p_pending->>'symbol'is distinct from r.target or p_pending->>'model'is distinct from r.model or octet_length(p_pending::text)>90000 or jsonb_typeof(p_pending->'draft'->'claims')is distinct from'array'or jsonb_array_length(p_pending->'draft'->'claims')not between 3 and 12 or jsonb_typeof(p_pending->'sources')is distinct from'array'or jsonb_array_length(p_pending->'sources')not between 1 and 3 then raise exception 'Bounded first model step required';end if;
 for v_claim in select value from jsonb_array_elements(p_pending->'draft'->'claims')loop
  if length(coalesce(v_claim->>'quote',''))not between 10 and 220 or not exists(select 1 from jsonb_array_elements(p_pending->'sources')s where s->>'id'=v_claim->>'source_id'and strpos(s->>'text',v_claim->>'quote')>0)then raise exception 'Exact first-step quotation required';end if;
 end loop;
 insert into paperlab.gemini_pending(symbol,record,reserved_day,reserved_month)values(r.target,p_pending,r.day,r.month)on conflict(symbol)do update set record=excluded.record,created_at=now(),retry_after=now(),slot_reserved=true,reserved_day=r.day,reserved_month=r.month,attempts=0;
 update paperlab.gemini_research set checked_at=now(),next_check=now()+interval'15 minutes',record=jsonb_build_object('version','gemini-research-v1','symbol',r.target,'status','awaiting_second_pass','trade_approval',false,'qualitative_approval',false,'independently_verified',false)where symbol=r.target;
 insert into paperlab.gemini_progress_events(symbol,event,record)values(r.target,'first_step_saved',jsonb_build_object('model',r.model,'claims',jsonb_array_length(p_pending->'draft'->'claims')));
 update paperlab.gemini_runtime set token=null,lease_until=null,target=null,status='awaiting_second_pass'where singleton;return true;
end$$;
create or replace function public.paper_gemini_commit(p_token uuid,p_record jsonb)returns boolean language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare r paperlab.gemini_runtime;v_source jsonb;v_claim jsonb;near_event boolean;h text;unused integer:=0;retry timestamptz;begin
 select *into r from paperlab.gemini_runtime where singleton and token=p_token and lease_until>now()for update;if not found then return false;end if;
 if p_record->>'version'is distinct from'gemini-research-v1'or p_record->>'symbol'is distinct from r.target or p_record->>'trade_approval'is distinct from'false'or p_record->>'qualitative_approval'is distinct from'false'or p_record->>'independently_verified'is distinct from'false'or p_record->>'status'not in('draft_checked','source_unavailable','rate_limited','provider_unavailable','invalid_response','verification_failed')or octet_length(p_record::text)>90000 or((p_record->>'checked_at')::timestamptz between now()-interval'10 minutes'and now()+interval'5 seconds')is not true then raise exception 'Invalid bounded model draft';end if;
 if p_record->>'status'='draft_checked'then
  if r.phase<>'review'or p_record->>'model'is distinct from r.model or p_record->>'exact_quotes_checked'is distinct from'true'or p_record->>'second_pass_completed'is distinct from'true'or jsonb_typeof(p_record->'claims')is distinct from'array'or jsonb_array_length(p_record->'claims')not between 3 and 12 or jsonb_typeof(p_record->'sources')is distinct from'array'or jsonb_array_length(p_record->'sources')not between 1 and 3 then raise exception 'Two-pass sourced draft required';end if;
  for v_source in select value from jsonb_array_elements(p_record->'sources')loop
   if coalesce(v_source->>'url','')not like'https://%'or coalesce(v_source->>'sha256','')!~'^[a-f0-9]{64}$'or((v_source->>'known_at')::timestamptz<=now())is not true or length(coalesce(v_source->>'text',''))not between 100 and 7000 then raise exception 'Observed excerpt proof required';end if;
  end loop;
  for v_claim in select value from jsonb_array_elements(p_record->'claims')loop
   if length(coalesce(v_claim->>'quote',''))not between 10 and 220 or not exists(select 1 from jsonb_array_elements(p_record->'sources')s where s->>'id'=v_claim->>'source_id'and strpos(s->>'text',v_claim->>'quote')>0)then raise exception 'Exact source quotation required';end if;
  end loop;
 end if;
 select exists(select 1 from paperlab.earnings_cycles c where c.symbol=r.target and c.release_at between now()-interval'7 days'and now()+interval'21 days'and c.status<>'superseded_unconfirmed')into near_event;
 retry:=paperlab.gemini_retry_time(p_record);
 if p_record->>'status'in('rate_limited','provider_unavailable')and r.phase='review'then
  update paperlab.gemini_pending set retry_after=retry,slot_reserved=false where symbol=r.target;
 else delete from paperlab.gemini_pending where symbol=r.target;end if;
 insert into paperlab.gemini_progress_events(symbol,event,record)values(r.target,case when p_record->>'status'='draft_checked'then 'review_completed'when r.phase='review'and p_record->>'status'in('rate_limited','provider_unavailable')then 'review_saved_for_retry'else 'attempt_not_completed'end,jsonb_build_object('status',p_record->>'status','phase',r.phase,'retry_after',retry,'provider_http_status',p_record->'provider_http_status','quota_kind',p_record->'quota_kind'));
 delete from paperlab.gemini_progress_events where id in(select id from paperlab.gemini_progress_events order by id desc offset 2000);
 update paperlab.gemini_research set checked_at=now(),record=p_record,next_check=case when retry is not null then retry else(((now()at time zone'UTC')::date+case when p_record->>'status'in('rate_limited','provider_unavailable')then 1 when p_record->>'status'<>'draft_checked'then 2 when near_event then 1 else 14 end)+time'07:44')at time zone'UTC'end,last_success=case when p_record->>'status'='draft_checked'then p_record else last_success end,last_success_at=case when p_record->>'status'='draft_checked'then now()else last_success_at end where symbol=r.target;
 h:=encode(sha256(convert_to(p_record::text,'UTF8')),'hex');insert into paperlab.gemini_research_history values(r.target,h,now(),p_record)on conflict do nothing;
 delete from paperlab.gemini_research_history where symbol=r.target and hash in(select hash from paperlab.gemini_research_history where symbol=r.target order by at desc offset 4);
 if p_record->>'status'<>'draft_checked'and(p_record->>'attempted_calls')in('0','1')then unused:=(case when r.phase='analysis'then 2 else 1 end)-(p_record->>'attempted_calls')::int;end if;
 update paperlab.gemini_runtime set token=null,lease_until=null,target=null,retry_after=retry,daily_reserved=greatest(0,daily_reserved-unused),monthly_reserved=greatest(0,monthly_reserved-unused),status=p_record->>'status',last_success=case when p_record->>'status'='draft_checked'then now()else last_success end where singleton;return true;
end$$;
create or replace function public.paper_gemini_source_check(p_token uuid,p_fingerprint text)returns boolean language plpgsql security definer set search_path=pg_catalog,pg_temp as $$declare r paperlab.gemini_runtime;near_event boolean;begin
 select *into r from paperlab.gemini_runtime where singleton and token=p_token and lease_until>now()and phase='analysis'for update;if not found then raise exception 'Active analysis required';end if;
 if coalesce(p_fingerprint,'')!~'^[a-f0-9]{64}$'then raise exception 'Source fingerprint required';end if;
 if not exists(select 1 from paperlab.gemini_research where symbol=r.target and last_success->>'input_fingerprint'=p_fingerprint)then return false;end if;
 select exists(select 1 from paperlab.earnings_cycles c where c.symbol=r.target and c.release_at between now()-interval'7 days'and now()+interval'21 days'and c.status<>'superseded_unconfirmed')into near_event;
 update paperlab.gemini_research set checked_at=now(),next_check=(((now()at time zone'UTC')::date+case when near_event then 1 else 14 end)+time'07:44')at time zone'UTC',record=jsonb_build_object('version','gemini-research-v1','symbol',r.target,'status','source_unchanged','input_fingerprint',p_fingerprint,'model',r.model,'trade_approval',false,'qualitative_approval',false,'independently_verified',false)where symbol=r.target;
 update paperlab.gemini_runtime set token=null,lease_until=null,target=null,daily_reserved=greatest(0,daily_reserved-2),monthly_reserved=greatest(0,monthly_reserved-2),status='source_unchanged'where singleton;
 insert into paperlab.gemini_progress_events(symbol,event,record)values(r.target,'unchanged_input_no_model_call',jsonb_build_object('input_fingerprint',p_fingerprint));delete from paperlab.gemini_progress_events where id in(select id from paperlab.gemini_progress_events order by id desc offset 2000);return true;
end$$;
revoke all on function public.paper_gemini_source_check(uuid,text)from public,anon,authenticated,service_role;
grant execute on function public.paper_gemini_source_check(uuid,text)to service_role;

create or replace function public.paper_gemini_read(p_owner uuid,p_symbol text default null)returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton)then raise exception 'Owner required';end if;
 return jsonb_build_object('runtime',(select(to_jsonb(r)-'token'-'lease_until'-'target')||jsonb_build_object('daily_reserved',case when r.day=(now()at time zone'America/Los_Angeles')::date then r.daily_reserved else 0 end,'daily_limit',case when r.bootstrap_day=(now()at time zone'America/Los_Angeles')::date then greatest(16,r.daily_request_limit) else r.daily_request_limit end)from paperlab.gemini_runtime r),
 'counts',(select jsonb_build_object('registered',count(*),'drafts',count(*)filter(where last_success_at is not null),'pending',count(*)filter(where checked_at is null),'waiting_review',count(*)filter(where exists(select 1 from paperlab.gemini_pending p where p.symbol=gemini_research.symbol)),'failed',count(*)filter(where record->>'status'not in('draft_checked','awaiting_second_pass','source_unchanged')))from paperlab.gemini_research),
 'records',(select coalesce(jsonb_agg(jsonb_build_object('symbol',g.symbol,'checked_at',g.checked_at,'next_check',g.next_check,'last_success_at',g.last_success_at,'status',g.record->>'status','provider_http_status',g.record->'provider_http_status','diagnostic',g.record->'diagnostic','draft',case when g.last_success is null then null else(g.last_success-'sources')||jsonb_build_object('sources',(select jsonb_agg(s-'text')from jsonb_array_elements(g.last_success->'sources')s))end,'stale',g.next_check<=now()or coalesce(g.record->>'status','')not in('draft_checked','source_unchanged'))order by g.checked_at desc nulls last),'[]')from(select *from paperlab.gemini_research where p_symbol is null or symbol=p_symbol order by checked_at desc nulls last,symbol limit 12)g),
 'pending_steps',(select count(*)from paperlab.gemini_pending),'schedule','Iedere tien minuten controle op hervatbare taken. Daglimieten volgen America/Los_Angeles. Dag- en maandgrenzen volgen de opgeslagen projectinstellingen; werk wordt over de dagen gespreid.',
 'limitations','Gratis Google-project door eigenaar bevestigd; wijzig facturatie niet zonder de taak opnieuw te beoordelen. Bij limieten uitstel, geen betaald alternatief. Geselecteerde HTML-passages en modelcontrole, geen volledig gelezen jaarverslag of onafhankelijke feitencontrole. Geen automatische koopgoedkeuring.');
end$$;
commit;
