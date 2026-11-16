-- Autonomous free numerical baselines, separate from human forecasts and trading.
begin;
create table if not exists paperlab.quarterly_expectations(symbol text primary key,checked_at timestamptz,record jsonb,next_check timestamptz not null default now());
create table if not exists paperlab.quarterly_expectation_history(symbol text not null,hash text not null,at timestamptz not null,record jsonb not null,primary key(symbol,hash));
create table if not exists paperlab.quarterly_event_baselines(cycle_id text primary key references paperlab.earnings_cycles,recorded_at timestamptz not null default now(),record jsonb not null);
create table if not exists paperlab.quarterly_runtime(singleton boolean primary key default true check(singleton),enabled boolean not null default true,token uuid,lease_until timestamptz,targets jsonb,month date,estimated_bytes bigint not null default 0,last_attempt timestamptz,last_success timestamptz,rounds bigint not null default 0);
insert into paperlab.quarterly_runtime(singleton)values(true)on conflict do nothing;
do $$declare n text;begin foreach n in array array['quarterly_expectations','quarterly_expectation_history','quarterly_event_baselines','quarterly_runtime']loop execute format('alter table paperlab.%I enable row level security',n);execute format('revoke all on paperlab.%I from public,anon,authenticated,service_role',n);end loop;end$$;
create or replace function paperlab.quarterly_inputs(p_symbol text default null)returns jsonb language sql stable security definer set search_path=pg_catalog,pg_temp as $$
 select coalesce(jsonb_agg(jsonb_build_object('symbol',c->>'symbol','name',c->>'name','sector',c->>'sector','quote_at',p.state->'last_observation'->(c->>'symbol')->>'time','official_source_url',c->>'primary_url',
 'official_source_available',coalesce(jsonb_array_length(r.record->'sources')>0 and((w.status='observed'and w.checked_at>=now()-interval'14 days')or(v.record->'primary'->>'status'='200'and(v.record->'primary'->>'checked_at')::timestamptz>=now()-interval'14 days')),false),
 'known_at',v.record->'observation'->>'known_at','values',v.record->'observation'->'values','input_fingerprint',v.record->>'financial_fingerprint','source_url',v.record->>'source_url','source_hash',v.record->>'source_hash')),'[]')
 from paperlab.company_coverage_runtime rt cross join jsonb_array_elements(rt.catalogue)c cross join paperlab.portfolio p left join paperlab.company_coverage v on v.symbol=c->>'symbol'left join paperlab.company_research r on r.symbol=c->>'symbol'left join paperlab.publication_watch w on w.symbol=c->>'symbol'where p_symbol is null or c->>'symbol'=p_symbol
$$;
create or replace function public.paper_quarterly_seed(p_rows jsonb)returns int language plpgsql security definer set search_path=pg_catalog,pg_temp as $$declare x jsonb;h text;inserted int;begin
 if jsonb_typeof(p_rows)is distinct from'array'or jsonb_array_length(p_rows)>100 then raise exception'Bounded numerical seed';end if;
 for x in select value from jsonb_array_elements(p_rows)loop
  if x->>'version'is distinct from'quarterly-baseline-v1'or x->>'trade_approval'is distinct from'false'or octet_length(x::text)>16000 or not exists(select 1 from paperlab.company_coverage_runtime r,jsonb_array_elements(r.catalogue)c where c->>'symbol'=x->>'symbol')then raise exception'Invalid baseline seed';end if;
  insert into paperlab.quarterly_expectations(symbol,checked_at,record)values(x->>'symbol',now(),x)on conflict do nothing;get diagnostics inserted=row_count;
  if inserted=1 then h:=encode(sha256(convert_to((x-'checked_at')::text,'UTF8')),'hex');insert into paperlab.quarterly_expectation_history values(x->>'symbol',h,now(),x)on conflict do nothing;end if;
 end loop;return jsonb_array_length(p_rows);
end$$;
create or replace function public.paper_quarterly_claim()returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$declare r paperlab.quarterly_runtime;rows jsonb;t uuid;m date:=date_trunc('month',now()at time zone'UTC')::date;charge bigint;begin
 select *into r from paperlab.quarterly_runtime where singleton for update;if not r.enabled or r.lease_until>now()or (r.last_attempt at time zone'UTC')::date=(now()at time zone'UTC')::date then return null;end if;
 insert into paperlab.quarterly_expectations(symbol)select c->>'symbol'from paperlab.company_coverage_runtime rt,jsonb_array_elements(rt.catalogue)c on conflict do nothing;
 select coalesce(jsonb_agg(x-'values'),'[]')into rows from(select x from jsonb_array_elements(paperlab.quarterly_inputs())x join paperlab.quarterly_expectations e on e.symbol=x->>'symbol'where e.next_check<=now()or(e.record->>'status'='waiting_quote'and(x->>'quote_at')::timestamptz>e.checked_at)or exists(select 1 from paperlab.publication_watch w where w.symbol=e.symbol and w.checked_at>e.checked_at and coalesce((w.record->>'changed')::boolean,false))order by exists(select 1 from paperlab.earnings_cycles c where c.symbol=e.symbol and c.release_at between now()and now()+interval'21 days')desc,coalesce((x->>'quote_at')::timestamptz>=now()-interval'7 days',false)desc,e.next_check,e.symbol limit 20)z;
 if jsonb_array_length(rows)=0 then return null;end if;charge:=250000*jsonb_array_length(rows);if r.month is distinct from m then r.estimated_bytes:=0;end if;
 insert into paperlab.free_usage(month)values(m)on conflict do nothing;perform 1 from paperlab.free_usage where month=m for update;
 if r.estimated_bytes+charge>120000000 or(select estimated_worker_egress_bytes+charge from paperlab.free_usage where month=m)>paperlab.traffic_limit('soft')or pg_database_size(current_database())>100000000 then return null;end if;
 t:=gen_random_uuid();update paperlab.quarterly_runtime set token=t,lease_until=now()+interval'120 seconds',targets=rows,last_attempt=now(),month=m,estimated_bytes=r.estimated_bytes+charge where singleton;update paperlab.free_usage set estimated_worker_egress_bytes=estimated_worker_egress_bytes+charge where month=m;
 return jsonb_build_object('token',t,'targets',rows,'paid_calls',false);
end$$;
create or replace function public.paper_quarterly_commit(p_token uuid,p_rows jsonb)returns boolean language plpgsql security definer set search_path=pg_catalog,pg_temp as $$declare r paperlab.quarterly_runtime;x jsonb;target jsonb;h text;near_event boolean;m jsonb;begin
 select *into r from paperlab.quarterly_runtime where singleton and token=p_token and lease_until>now()for update;if not found then return false;end if;
 if jsonb_typeof(p_rows)is distinct from'array'or jsonb_array_length(p_rows)<>jsonb_array_length(r.targets)or(select count(distinct value->>'symbol')from jsonb_array_elements(p_rows))<>jsonb_array_length(p_rows)then raise exception'Expected exact baseline targets';end if;
 for x in select value from jsonb_array_elements(p_rows)loop
  select value into target from jsonb_array_elements(r.targets)where value->>'symbol'=x->>'symbol';
  if target is null or x->>'version'is distinct from'quarterly-baseline-v1'or x->>'trade_approval'is distinct from'false'or x->>'stock_direction'is distinct from'not_predicted'or x->'analyst_consensus'->>'status'is distinct from'not_connected'or x->'qualitative_review'->>'status'is distinct from'not_automated'or octet_length(x::text)>16000 or(x->>'checked_at')::timestamptz>now()+interval'5 seconds'or x->'official_source_available'is distinct from target->'official_source_available'or x->>'quote_at'is distinct from target->>'quote_at'then raise exception'Untrusted baseline output';end if;
  if coalesce(x->>'status','')not in('baseline_available','waiting_quote','waiting_official_source','insufficient_data','source_unavailable')then raise exception'Unknown baseline status';end if;
  for m in select value from jsonb_each(x->'metrics')loop
   if m->>'status'='baseline'and(exists(select 1 from unnest(array['low','base','high'])key where jsonb_typeof(m->key)is distinct from'number')or ((m->>'low')::float8>0 and(m->>'low')::float8<=(m->>'base')::float8 and(m->>'base')::float8<=(m->>'high')::float8 and(m->>'high')::float8<1e18)is not true)then raise exception'Invalid numerical baseline range';end if;
  end loop;
  if x->>'status'='baseline_available'and(x->'metrics'->'revenue'->>'status'is distinct from'baseline'or ((x->>'input_known_at')::timestamptz between now()-interval'14 days'and now()+interval'5 seconds')is not true or coalesce(x->>'input_fingerprint','')!~'^[a-f0-9]{64}$'or coalesce(x->>'financial_source_hash','')!~'^[a-f0-9]{64}$'or(x->>'eligible')::boolean is distinct from true or ((x->>'quote_at')::timestamptz between now()-interval'7 days'and now())is not true or(x->>'official_source_available')::boolean is distinct from true)then raise exception'Baseline requires received quote and official evidence';end if;
  h:=encode(sha256(convert_to((x-'checked_at')::text,'UTF8')),'hex');
  insert into paperlab.quarterly_expectation_history values(x->>'symbol',h,now(),x)on conflict do nothing;
  delete from paperlab.quarterly_expectation_history where symbol=x->>'symbol'and hash in(select hash from paperlab.quarterly_expectation_history where symbol=x->>'symbol'order by at desc offset 4);
  select exists(select 1 from paperlab.earnings_cycles c where c.symbol=x->>'symbol'and c.release_at between now()and now()+interval'21 days')into near_event;
  update paperlab.quarterly_expectations set checked_at=now(),record=x,next_check=(((now()at time zone'UTC')::date+case when near_event then 1 else 7 end)+time'07:19')at time zone'UTC'where symbol=x->>'symbol';
  if x->>'status'='baseline_available'then insert into paperlab.quarterly_event_baselines(cycle_id,record)select c.id,x||'{"cycle_match":"unverified_reference_period","human_forecast":false}'::jsonb from paperlab.earnings_cycles c where c.symbol=x->>'symbol'and now()<c.release_at-interval'24 hours'on conflict do nothing;end if;
 end loop;
 update paperlab.quarterly_runtime set token=null,lease_until=null,last_success=now(),rounds=rounds+1 where singleton;return true;
end$$;
create or replace function public.paper_quarterly_read(p_owner uuid,p_symbol text default null)returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton)then raise exception'Owner required';end if;
 return jsonb_build_object('version','quarterly-baseline-v1','counts',(select jsonb_build_object('registered',count(*),'eligible',count(*)filter(where(record->>'eligible')::boolean),'with_baseline',count(*)filter(where record->>'status'='baseline_available'),'awaiting_quote',count(*)filter(where record->>'status'='waiting_quote'),'awaiting_official_source',count(*)filter(where record->>'status'='waiting_official_source'),'source_gaps',count(*)filter(where record->>'status'in('insufficient_data','source_unavailable')),'latest',max(checked_at))from paperlab.quarterly_expectations),
 'records',(select coalesce(jsonb_agg(jsonb_build_object('symbol',symbol,'checked_at',checked_at,'next_check',next_check,'record',record,'stale',checked_at<now()-interval'14 days')order by symbol),'[]')from paperlab.quarterly_expectations where p_symbol is null or symbol=p_symbol),
 'event_snapshots',(select coalesce(jsonb_agg(jsonb_build_object('cycle_id',b.cycle_id,'recorded_at',b.recorded_at,'record',b.record)),'[]')from paperlab.quarterly_event_baselines b join paperlab.earnings_cycles c on c.id=b.cycle_id where p_symbol is null or c.symbol=p_symbol),
 'runtime',(select to_jsonb(r)-'token'-'lease_until'-'targets'from paperlab.quarterly_runtime r),
 'schedule','Dagelijks 07:20 UTC: maximaal twintig vervallen dossiers. Normaal ongeveer wekelijks; bevestigde naderende cijfers eerst. Bronfouten of budget kunnen vertragen.',
 'limitations','Ontvangen indicatieve koersen zijn geen broker-livefeed. Rekenramingen zijn geen bedrijfsprognoses of analistenconsensus. Geen automatische kwalitatieve goedkeuring, koersvoorspelling of aankoop. Ontbrekende data blijven onbekend.');
end$$;
do $$begin if to_regprocedure('public.paper_project_read_quarterly_base_v1(uuid,text)')is null then alter function public.paper_project_read(uuid,text)rename to paper_project_read_quarterly_base_v1;end if;end$$;
create or replace function public.paper_project_read(p_owner uuid,p_symbol text default null)returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$begin return public.paper_project_read_quarterly_base_v1(p_owner,p_symbol)||jsonb_build_object('quarterly_expectations',public.paper_quarterly_read(p_owner,p_symbol));end$$;
revoke all on function paperlab.quarterly_inputs(text),public.paper_quarterly_seed(jsonb),public.paper_quarterly_claim(),public.paper_quarterly_commit(uuid,jsonb),public.paper_quarterly_read(uuid,text),public.paper_project_read_quarterly_base_v1(uuid,text),public.paper_project_read(uuid,text)from public,anon,authenticated,service_role;
grant execute on function public.paper_quarterly_claim(),public.paper_quarterly_commit(uuid,jsonb),public.paper_quarterly_read(uuid,text),public.paper_project_read(uuid,text)to service_role;
commit;
