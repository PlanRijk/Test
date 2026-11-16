-- Public-page provider consensus, separate from mechanical and owner forecasts.
begin;
create table if not exists paperlab.analyst_consensus(symbol text primary key,checked_at timestamptz,record jsonb,next_check timestamptz not null default now());
create table if not exists paperlab.analyst_consensus_history(symbol text not null,hash text not null,at timestamptz not null,record jsonb not null,primary key(symbol,hash));
create table if not exists paperlab.earnings_consensus_snapshots(cycle_id text not null references paperlab.earnings_cycles,source_hash text not null,recorded_at timestamptz not null default now(),record jsonb not null,primary key(cycle_id,source_hash));
create table if not exists paperlab.consensus_runtime(singleton boolean primary key default true check(singleton),enabled boolean not null default true,token uuid,lease_until timestamptz,targets jsonb,month date,estimated_bytes bigint not null default 0,day date,batches int not null default 0,last_success timestamptz,rounds bigint not null default 0);
insert into paperlab.consensus_runtime(singleton)values(true)on conflict do nothing;
do $$declare n text;begin foreach n in array array['analyst_consensus','analyst_consensus_history','earnings_consensus_snapshots','consensus_runtime']loop execute format('alter table paperlab.%I enable row level security',n);execute format('revoke all on paperlab.%I from public,anon,authenticated,service_role',n);end loop;end$$;
create or replace function public.paper_consensus_claim()returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$declare r paperlab.consensus_runtime;rows jsonb;charge bigint;m date:=date_trunc('month',now()at time zone'UTC')::date;d date:=(now()at time zone'UTC')::date;t uuid;begin
 select *into r from paperlab.consensus_runtime where singleton for update;if not r.enabled or r.lease_until>now()then return null;end if;
 if r.day is distinct from d then r.batches:=0;end if;if r.batches>=6 then return null;end if;if r.month is distinct from m then r.estimated_bytes:=0;end if;
 insert into paperlab.analyst_consensus(symbol)select symbol from paperlab.quarterly_expectations on conflict do nothing;
 select coalesce(jsonb_agg(jsonb_build_object('symbol',symbol)),'[]')into rows from(select a.symbol from paperlab.analyst_consensus a join paperlab.quarterly_expectations q on q.symbol=a.symbol where a.next_check<=now()and(q.record->>'eligible')::boolean is true and q.checked_at>=now()-interval'14 days'order by exists(select 1 from paperlab.earnings_cycles c where c.symbol=a.symbol and c.release_at between now()and now()+interval'21 days')desc,a.next_check,a.symbol limit 10)z;
 if jsonb_array_length(rows)=0 then return null;end if;charge:=1600000*jsonb_array_length(rows);
 insert into paperlab.free_usage(month)values(m)on conflict do nothing;perform 1 from paperlab.free_usage where month=m for update;
 if r.estimated_bytes+charge>500000000 or(select estimated_worker_egress_bytes+charge from paperlab.free_usage where month=m)>paperlab.traffic_limit('soft')or pg_database_size(current_database())>100000000 then return null;end if;
 t:=gen_random_uuid();update paperlab.consensus_runtime set month=m,estimated_bytes=r.estimated_bytes+charge,day=d,batches=r.batches+1,token=t,lease_until=now()+interval'150 seconds',targets=rows where singleton;update paperlab.free_usage set estimated_worker_egress_bytes=estimated_worker_egress_bytes+charge where month=m;
 return jsonb_build_object('token',t,'targets',rows);
end$$;
create or replace function public.paper_consensus_commit(p_token uuid,p_rows jsonb)returns boolean language plpgsql security definer set search_path=pg_catalog,pg_temp as $$declare r paperlab.consensus_runtime;x jsonb;quarter jsonb;metric jsonb;h text;near_event boolean;begin
 select *into r from paperlab.consensus_runtime where singleton and token=p_token and lease_until>now()for update;if not found then return false;end if;
 if jsonb_typeof(p_rows)is distinct from'array'or jsonb_array_length(p_rows)<>jsonb_array_length(r.targets)or(select count(distinct value->>'symbol')from jsonb_array_elements(p_rows))<>jsonb_array_length(p_rows)then raise exception'Expected exact consensus targets';end if;
 for x in select value from jsonb_array_elements(p_rows)loop
  if x->>'version'is distinct from'analyst-consensus-v1'or x->>'trade_approval'is distinct from'false'or x->>'qualitative_approval'is distinct from'false'or coalesce(x->>'status','')not in('provider_reported','unavailable')or octet_length(x::text)>16000 or not exists(select 1 from jsonb_array_elements(r.targets)t where t->>'symbol'=x->>'symbol')or((x->>'known_at')::timestamptz between now()-interval'10 minutes'and now()+interval'5 seconds')is not true then raise exception'Invalid consensus output';end if;
  if x->>'status'='provider_reported'then
   if coalesce(x->>'source_sha256','')!~'^[a-f0-9]{64}$'or x->>'source_url'is distinct from('https://finance.yahoo.com/quote/'||(x->>'symbol')||'/analysis/')or x->>'independently_verified'is distinct from'false'or jsonb_typeof(x->'quarters')is distinct from'array'or jsonb_array_length(x->'quarters')not between 1 and 2 then raise exception'Provider source proof required';end if;
   for quarter in select value from jsonb_array_elements(x->'quarters')loop
    if coalesce(quarter->>'period','')!~'^20[0-9]{2}-(0[1-9]|1[0-2])$'then raise exception'Quarter scope required';end if;
    for metric in select value from jsonb_each(quarter)where key in('revenue','eps')loop
     if metric->>'status'='provider_reported'and(jsonb_typeof(metric->'analysts')is distinct from'number'or((metric->>'analysts')::numeric=trunc((metric->>'analysts')::numeric)and(metric->>'analysts')::int between 1 and 2000)is not true or exists(select 1 from unnest(array['average','low','high'])k where jsonb_typeof(metric->k)is distinct from'number')or((metric->>'low')::float8<=(metric->>'average')::float8 and(metric->>'average')::float8<=(metric->>'high')::float8)is not true or coalesce(metric->>'currency','')!~'^[A-Z]{3}$'or coalesce(metric->>'basis','')not in('GAAP','normalized','unknown'))then raise exception'Consensus count/range/currency required';end if;
    end loop;
   end loop;
  end if;
  h:=coalesce(x->>'source_sha256',encode(sha256(convert_to(x::text,'UTF8')),'hex'));
  insert into paperlab.analyst_consensus_history values(x->>'symbol',h,now(),x)on conflict do nothing;
  delete from paperlab.analyst_consensus_history where symbol=x->>'symbol'and hash in(select hash from paperlab.analyst_consensus_history where symbol=x->>'symbol'order by at desc offset 8);
  select exists(select 1 from paperlab.earnings_cycles c where c.symbol=x->>'symbol'and c.release_at between now()and now()+interval'21 days')into near_event;
  update paperlab.analyst_consensus set checked_at=now(),record=x,next_check=(((now()at time zone'UTC')::date+case when near_event then 1 when x->>'status'='unavailable'then 2 else 7 end)+time'07:34')at time zone'UTC'where symbol=x->>'symbol';
  if x->>'status'='provider_reported'then insert into paperlab.earnings_consensus_snapshots(cycle_id,source_hash,record)select c.id,h,x||'{"human_forecast":false,"cycle_match":"baseline_reference_month_only"}'::jsonb from paperlab.earnings_cycles c join paperlab.quarterly_expectations q on q.symbol=c.symbol where c.symbol=x->>'symbol'and now()<c.release_at-interval'24 hours'and exists(select 1 from jsonb_array_elements(x->'quarters')p where p->>'period'=left(q.record->'metrics'->'revenue'->>'target_period_reference',7))on conflict do nothing;end if;
 end loop;
 update paperlab.consensus_runtime set token=null,lease_until=null,last_success=now(),rounds=rounds+1 where singleton;return true;
end$$;
create or replace function public.paper_consensus_read(p_owner uuid,p_symbol text default null)returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton)then raise exception'Owner required';end if;
 return jsonb_build_object('counts',(select jsonb_build_object('registered',count(*),'reported',count(*)filter(where record->>'status'='provider_reported'),'unavailable',count(*)filter(where record->>'status'='unavailable'),'pending',count(*)filter(where record is null))from paperlab.analyst_consensus),
 'records',(select coalesce(jsonb_agg(jsonb_build_object('symbol',a.symbol,'checked_at',a.checked_at,'next_check',a.next_check,'record',a.record,'eligible',q.record->'eligible','stale',a.checked_at<now()-interval'7 days','baseline_stale',coalesce(q.checked_at<now()-interval'14 days'or(q.record->>'input_known_at')::timestamptz<now()-interval'14 days',true),'baseline_revenue',q.record->'metrics'->'revenue','eps_comparison','not_comparable_unverified_baseline_basis')order by a.symbol),'[]')from paperlab.analyst_consensus a join paperlab.quarterly_expectations q on q.symbol=a.symbol where p_symbol is null or a.symbol=p_symbol),
 'runtime',(select to_jsonb(r)-'token'-'lease_until'-'targets'from paperlab.consensus_runtime r),
 'pre_event_snapshots',(select count(*)from paperlab.earnings_consensus_snapshots),
 'schedule','Dagelijks 07:35 UTC maximaal tien vervallen dossiers. Normaal wekelijks, naderende bevestigde cijfers eerst en dagelijks. Initiële beheerde inleesronde maximaal zes batches per dag.',
 'limitations','Consensus volgens één openbare provider, niet onafhankelijk geverifieerd. Onderliggende peildatum en upstream-licentiefeed niet bevestigd. Ophalen, periode, munt, aantallen en EPS-basis worden gecontroleerd. Geen koopgoedkeuring.');
end$$;
do $$begin if to_regprocedure('public.paper_project_read_consensus_base_v1(uuid,text)')is null then alter function public.paper_project_read(uuid,text)rename to paper_project_read_consensus_base_v1;end if;end$$;
create or replace function public.paper_project_read(p_owner uuid,p_symbol text default null)returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$begin return public.paper_project_read_consensus_base_v1(p_owner,p_symbol)||jsonb_build_object('analyst_consensus',public.paper_consensus_read(p_owner,p_symbol));end$$;
revoke all on function public.paper_consensus_claim(),public.paper_consensus_commit(uuid,jsonb),public.paper_consensus_read(uuid,text),public.paper_project_read_consensus_base_v1(uuid,text),public.paper_project_read(uuid,text)from public,anon,authenticated,service_role;
grant execute on function public.paper_consensus_claim(),public.paper_consensus_commit(uuid,jsonb),public.paper_consensus_read(uuid,text),public.paper_project_read(uuid,text)to service_role;
commit;
