begin;
create table if not exists paperlab.source_runtime(singleton boolean primary key default true check(singleton),profile text,policy jsonb,registry jsonb,started_at timestamptz,last_success timestamptz,status text not null default 'waiting',token uuid);
insert into paperlab.source_runtime(singleton)values(true)on conflict do nothing;
create table if not exists paperlab.source_reliability(symbol text primary key,record jsonb not null check(octet_length(record::text)<=6000),reference jsonb check(octet_length(reference::text)<=12000));
create table if not exists paperlab.source_events(id bigint generated always as identity primary key,at timestamptz not null default now(),symbol text not null,record jsonb not null check(octet_length(record::text)<=4000));
do $$declare n text;begin foreach n in array array['source_runtime','source_reliability','source_events']loop execute format('alter table paperlab.%I enable row level security',n);execute format('revoke all on paperlab.%I from public,anon,authenticated,service_role',n);end loop;end$$;
do $$begin
 if to_regprocedure('public.paper_company_coverage_claim_source_base_v1(boolean)')is null then
  alter function public.paper_company_coverage_claim(boolean)rename to paper_company_coverage_claim_source_base_v1;
  alter function public.paper_company_coverage_commit(uuid,jsonb)rename to paper_company_coverage_commit_source_base_v1;
 end if;
end$$;
create or replace function public.paper_source_configure(p_policy jsonb,p_registry jsonb)returns text language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare r paperlab.source_runtime;fp text;begin
 select *into r from paperlab.source_runtime where singleton for update;
 if not(p_policy@>'{"version":"source-resilience-v1","companies":100,"research_horizon":"weeks_to_months","max_source_bytes":80000,"max_body_bytes":64000,"max_reliability_bytes":6000,"max_storage_bytes":3000000,"probe_after_days":7,"cache_fresh_days":8,"review_fresh_days":7,"automatic_trade_approval":false,"same_provider_counts_as_independent":false}'::jsonb)or coalesce(p_policy->>'implementation_sha256','')!~'^[a-f0-9]{64}$'or jsonb_array_length(p_registry)<>100 or(select count(distinct c->>'symbol')from jsonb_array_elements(p_registry)c)<>100 or exists(select 1 from jsonb_array_elements(p_registry)c where not exists(select 1 from paperlab.company_coverage_runtime rt,jsonb_array_elements(rt.catalogue)o where o->>'symbol'=c->>'symbol'))then raise exception'Invalid source registry';end if;
 fp:=encode(sha256(convert_to(p_policy::text,'UTF8')),'hex');if r.profile is not null then if r.policy<>p_policy or r.registry<>p_registry then raise exception'Source protocol frozen';end if;return r.profile;end if;
 if exists(select 1 from paperlab.company_coverage_runtime where token is not null and lease_until>now())then raise exception'Source collector busy';end if;
 update paperlab.source_runtime set profile=fp,policy=p_policy,registry=p_registry,started_at=now(),status='configured'where singleton;return fp;
end$$;
create or replace function public.paper_source_seed(p_rows jsonb)returns integer language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare x jsonb;n integer:=0;begin
 if jsonb_array_length(p_rows)>20 then raise exception'Bounded source seed required';end if;
 for x in select value from jsonb_array_elements(p_rows)loop
  if not exists(select 1 from paperlab.source_runtime r,jsonb_array_elements(r.registry)c where c->>'symbol'=x->>'symbol')or x->'record'->>'version'is distinct from'source-resilience-v1'or(x->'record'->>'trade_approval')::boolean is distinct from false then raise exception'Invalid source seed';end if;
  insert into paperlab.source_reliability values(x->>'symbol',x->'record',nullif(x->'reference','null'::jsonb))on conflict(symbol)do update set reference=coalesce(excluded.reference,paperlab.source_reliability.reference);n:=n+1;
 if(x->'record'->'verification'->>'critical_conflict')::boolean is true and exists(select 1 from paperlab.company_dossiers where symbol=x->>'symbol'and record->>'status'is distinct from'source_conflict_requires_review')then perform public.paper_company_save(jsonb_build_object('version','company-dossier-v1','symbol',x->>'symbol','known_at',clock_timestamp(),'checked_at',clock_timestamp(),'status','source_conflict_requires_review','financial','{}'::jsonb,'source_verification',x->'record'->'verification'));end if;
 end loop;return n;
end$$;
create or replace function public.paper_company_coverage_claim(p_manual boolean default false)returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$begin
 if exists(select 1 from paperlab.source_runtime where profile is not null)then return null;end if;return public.paper_company_coverage_claim_source_base_v1(p_manual);end$$;
create or replace function public.paper_company_coverage_commit(p_token uuid,p_rows jsonb)returns boolean language plpgsql security definer set search_path=pg_catalog,pg_temp as $$begin
 if exists(select 1 from paperlab.source_runtime where profile is not null)then return false;end if;return public.paper_company_coverage_commit_source_base_v1(p_token,p_rows);end$$;
create or replace function public.paper_source_claim(p_manual boolean default false)returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare r paperlab.source_runtime;c paperlab.company_coverage_runtime;x jsonb;targets jsonb;extra bigint;d date:=(now()at time zone'UTC')::date;m date:=date_trunc('month',now()at time zone'UTC')::date;
begin
 select *into r from paperlab.source_runtime where singleton for update;if r.profile is null then return null;end if;
 if(select sum(pg_total_relation_size(t::regclass))from unnest(array['paperlab.source_runtime','paperlab.source_reliability','paperlab.source_events'])t)>=(r.policy->>'max_storage_bytes')::bigint then update paperlab.source_runtime set status='storage_guard'where singleton;return null;end if;
 x:=public.paper_company_coverage_claim_source_base_v1(p_manual);if x is null then update paperlab.source_runtime set status=coalesce((select status from paperlab.company_coverage_runtime),'idle')where singleton;return null;end if;
 select *into c from paperlab.company_coverage_runtime where singleton;
 select jsonb_agg(item||jsonb_build_object('primary_reference',coalesce(v.record->'verified_financials',s.reference),'last_financial_success_at',v.record->'observation'->'known_at','reliability',jsonb_build_object('endpoints',s.record->'endpoints','availability',s.record->'availability','last_financial_success_at',s.record->'last_financial_success_at','verification',s.record->'verification'),'review',(select jsonb_build_object('reviewed_at',reviewed_at,'total_debt',record->'total_debt','balance_end',record->'balance_end')from paperlab.company_reviews where symbol=item->>'symbol'order by reviewed_at desc,id desc limit 1)))into targets from jsonb_array_elements(x->'targets')item left join paperlab.company_coverage v on v.symbol=item->>'symbol'left join paperlab.source_reliability s on s.symbol=item->>'symbol';
 extra:=2*octet_length(targets::text)+1024;
 if(select sum(estimated_bytes)from paperlab.company_coverage_usage where day>=m)+extra>(c.policy->>'max_month_bytes')::bigint or(select estimated_worker_egress_bytes from paperlab.free_usage where month=m)+extra>(c.policy->>'shared_month_bytes')::bigint then
  update paperlab.company_coverage_usage set estimated_bytes=estimated_bytes-(c.policy->>'reserved_batch_bytes')::bigint where day=d;update paperlab.free_usage set estimated_worker_egress_bytes=estimated_worker_egress_bytes-(c.policy->>'reserved_batch_bytes')::bigint where month=m;update paperlab.company_coverage_runtime set token=null,lease_until=null,status='budget_or_daily_limit'where singleton;update paperlab.source_runtime set status='budget_guard'where singleton;return null;
 end if;
 update paperlab.company_coverage_usage set estimated_bytes=estimated_bytes+extra where day=d;update paperlab.free_usage set estimated_worker_egress_bytes=estimated_worker_egress_bytes+extra where month=m;
 update paperlab.source_runtime set token=(x->>'token')::uuid,status='checking'where singleton;
 return x||jsonb_build_object('targets',targets,'source_policy',r.policy,'source_profile',r.profile);
end$$;
create or replace function public.paper_source_commit(p_token uuid,p_rows jsonb)returns boolean language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare r paperlab.source_runtime;c paperlab.company_coverage_runtime;x jsonb;core jsonb;refs jsonb;old jsonb;extra bigint;d date;m date;
begin
 select *into r from paperlab.source_runtime where singleton and token=p_token for update;if not found then return false;end if;
 select *into c from paperlab.company_coverage_runtime where singleton and token=p_token and lease_until>now()for update;if not found then return false;end if;
 if jsonb_array_length(p_rows)>6 then raise exception'Bounded source results required';end if;
 for x in select value from jsonb_array_elements(p_rows)loop
  if x->'reliability'->>'version'is distinct from'source-resilience-v1'or(x->'reliability'->>'trade_approval')::boolean is distinct from false or(x->'reliability'->>'same_provider_independent')::boolean is distinct from false then raise exception'Source evidence cannot approve trades';end if;
 end loop;
 select jsonb_agg(z.value-'reliability'),2*sum(octet_length((z.value->'reliability')::text))into core,extra from jsonb_array_elements(p_rows)z(value);
 d:=(c.last_claim at time zone'UTC')::date;m:=date_trunc('month',c.last_claim at time zone'UTC')::date;
 if(select sum(estimated_bytes)from paperlab.company_coverage_usage where day>=m)+extra>(c.policy->>'max_month_bytes')::bigint or(select estimated_worker_egress_bytes from paperlab.free_usage where month=m)+extra>(c.policy->>'shared_month_bytes')::bigint then raise exception'Source evidence budget';end if;
 select jsonb_object_agg(v.symbol,coalesce(v.record->'verified_financials',s.reference))into refs from paperlab.company_coverage v left join paperlab.source_reliability s using(symbol)where exists(select 1 from jsonb_array_elements(p_rows)z(value)where z.value->>'symbol'=v.symbol);
 if not public.paper_company_coverage_commit_source_base_v1(p_token,core)then return false;end if;
 for x in select value from jsonb_array_elements(p_rows)loop
  select record into old from paperlab.source_reliability where symbol=x->>'symbol';
  if old->'verification'->>'status'is distinct from x->'reliability'->'verification'->>'status'or old->>'route'is distinct from x->'reliability'->>'route'then insert into paperlab.source_events(symbol,record)values(x->>'symbol',jsonb_build_object('kind','source_status_changed','previous_route',old->>'route','route',x->'reliability'->>'route','verification',x->'reliability'->'verification','attempts',x->'reliability'->'attempts'));end if;
  if x?'observation'and(x->'reliability'->'verification'->>'critical_conflict')::boolean is true and coalesce((old->'verification'->>'critical_conflict')::boolean,false)is false and exists(select 1 from paperlab.company_dossiers where symbol=x->>'symbol')then
   perform public.paper_company_save(jsonb_build_object('version','company-dossier-v1','symbol',x->>'symbol','known_at',clock_timestamp(),'checked_at',clock_timestamp(),'status','source_conflict_requires_review','financial','{}'::jsonb,'source_verification',x->'reliability'->'verification'));
  end if;
  insert into paperlab.source_reliability values(x->>'symbol',x->'reliability',refs->(x->>'symbol'))on conflict(symbol)do update set record=excluded.record,reference=coalesce(excluded.reference,paperlab.source_reliability.reference);
 end loop;
 delete from paperlab.source_events where id in(select id from paperlab.source_events order by id desc offset 300);
 update paperlab.company_coverage_usage set estimated_bytes=estimated_bytes+extra where day=d;update paperlab.free_usage set estimated_worker_egress_bytes=estimated_worker_egress_bytes+extra where month=m;
 update paperlab.source_runtime set token=null,last_success=now(),status='observing'where singleton;return true;
end$$;
create or replace function public.paper_source_fail(p_token uuid)returns void language plpgsql security definer set search_path=pg_catalog,pg_temp as $$begin
 perform public.paper_company_coverage_fail(p_token);update paperlab.source_runtime set token=null,status='source_or_commit_error'where singleton and token=p_token;
end$$;
create or replace function public.paper_source_read(p_owner uuid,p_symbol text default null)returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton)then raise exception'Owner required';end if;
 return jsonb_build_object('runtime',(select to_jsonb(r)-'registry'-'token'from paperlab.source_runtime r),'counts',(select jsonb_build_object('companies',count(*),'checked',count(*)filter(where record->>'attempted_at'is not null),'last_run_failover',count(*)filter(where record->>'route'='same_provider_failover'),'cached_only',count(*)filter(where record->>'route'='cached_only'),'matched_figures',count(*)filter(where record->'verification'->>'status'='matched_reported_figures'),'conflicts',count(*)filter(where(record->'verification'->>'critical_conflict')::boolean is true),'primary_references',count(reference))from paperlab.source_reliability),
 'current_reviews',(select count(distinct symbol)from paperlab.company_reviews where reviewed_at>=now()-interval'7 days'),
 'records',(select coalesce(jsonb_agg(jsonb_build_object('symbol',s.symbol,'record',s.record,'primary_reference',s.reference,'observation',v.record->'observation','review',(select jsonb_build_object('reviewed_at',reviewed_at,'total_debt',record->'total_debt','balance_end',record->'balance_end')from paperlab.company_reviews where symbol=s.symbol order by reviewed_at desc,id desc limit 1))),'[]')from paperlab.source_reliability s left join paperlab.company_coverage v using(symbol)where s.symbol=p_symbol),
 'events',(select coalesce(jsonb_agg(to_jsonb(e)order by id desc),'[]')from(select *from paperlab.source_events where p_symbol is not null and symbol=p_symbol order by id desc limit 5)e));
end$$;
revoke all on function public.paper_source_configure(jsonb,jsonb),public.paper_source_seed(jsonb),public.paper_company_coverage_claim_source_base_v1(boolean),public.paper_company_coverage_commit_source_base_v1(uuid,jsonb),public.paper_company_coverage_claim(boolean),public.paper_company_coverage_commit(uuid,jsonb),public.paper_source_claim(boolean),public.paper_source_commit(uuid,jsonb),public.paper_source_fail(uuid),public.paper_source_read(uuid,text)from public,anon,authenticated,service_role;
grant execute on function public.paper_company_coverage_claim(boolean),public.paper_company_coverage_commit(uuid,jsonb),public.paper_source_claim(boolean),public.paper_source_commit(uuid,jsonb),public.paper_source_fail(uuid),public.paper_source_read(uuid,text)to service_role;
commit;
