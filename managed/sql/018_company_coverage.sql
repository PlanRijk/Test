begin;
create table if not exists paperlab.company_coverage_runtime(singleton boolean primary key default true check(singleton),enabled boolean not null default true,policy jsonb,catalogue jsonb not null default '[]',token uuid,lease_until timestamptz,last_claim timestamptz,last_success timestamptz,status text not null default 'waiting');
insert into paperlab.company_coverage_runtime(singleton)values(true)on conflict do nothing;
create table if not exists paperlab.company_coverage(symbol text primary key,checked_at timestamptz not null,record jsonb not null check(octet_length(record::text)<=24000));
create table if not exists paperlab.company_coverage_events(id bigint generated always as identity primary key,at timestamptz not null default now(),symbol text not null,record jsonb not null check(octet_length(record::text)<=6000));
create table if not exists paperlab.company_coverage_usage(day date primary key,batches integer not null default 0,estimated_bytes bigint not null default 0);
do $$declare n text;begin foreach n in array array['company_coverage_runtime','company_coverage','company_coverage_events','company_coverage_usage']loop execute format('alter table paperlab.%I enable row level security',n);execute format('revoke all on paperlab.%I from public,anon,authenticated,service_role',n);end loop;end$$;
create or replace function public.paper_company_coverage_configure(p_policy jsonb,p_catalogue jsonb)returns void language plpgsql security definer set search_path=pg_catalog,pg_temp as $$declare old jsonb;begin
 if not(p_policy@>'{"version":"company-coverage-v1","companies":100,"automatic_trade_approval":false}'::jsonb)or jsonb_array_length(p_catalogue)<>100 then raise exception'Invalid coverage protocol';end if;
 select policy into old from paperlab.company_coverage_runtime where singleton for update;if old is not null and old<>p_policy then raise exception'Coverage policy frozen';end if;
 update paperlab.company_coverage_runtime set policy=p_policy,catalogue=p_catalogue,status=case when old is null then'configured'else status end where singleton;
end$$;
create or replace function public.paper_company_coverage_import(p_records jsonb)returns integer language plpgsql security definer set search_path=pg_catalog,pg_temp as $$declare x jsonb;n integer:=0;charge bigint:=0;d date:=(now()at time zone'UTC')::date;m date:=date_trunc('month',now()at time zone'UTC')::date;r paperlab.company_coverage_runtime;begin
 select *into r from paperlab.company_coverage_runtime where singleton;
 insert into paperlab.company_coverage_usage(day)values(d)on conflict do nothing;insert into paperlab.free_usage(month)values(m)on conflict do nothing;
 if jsonb_array_length(p_records)>20 then raise exception'Bounded import required';end if;
 for x in select value from jsonb_array_elements(p_records)loop
  if not exists(select 1 from paperlab.company_coverage_runtime rt,jsonb_array_elements(rt.catalogue)c where c->>'symbol'=x->>'symbol'and c->>'primary_url'=x->'primary'->>'url')or coalesce(x->>'financial_fingerprint','')!~'^[a-f0-9]{64}$'or jsonb_typeof(x->'observation'->'values')is distinct from'object'or(x->'observation'->>'known_at')::timestamptz>now()+interval'5 seconds' then raise exception'Invalid source record';end if;
  insert into paperlab.company_coverage values(x->>'symbol',(x->'observation'->>'known_at')::timestamptz,x)on conflict(symbol)do update set checked_at=excluded.checked_at,record=excluded.record where excluded.checked_at>=paperlab.company_coverage.checked_at;n:=n+1;charge:=charge+2*octet_length(x::text)+2048;
 end loop;
 if(select coalesce(sum(estimated_bytes),0)from paperlab.company_coverage_usage where day>=m)+charge>(r.policy->>'max_month_bytes')::bigint or(select estimated_worker_egress_bytes from paperlab.free_usage where month=m)+charge>(r.policy->>'shared_month_bytes')::bigint then raise exception'Coverage import budget';end if;
 update paperlab.company_coverage_usage set estimated_bytes=estimated_bytes+charge where day=d;update paperlab.free_usage set estimated_worker_egress_bytes=estimated_worker_egress_bytes+charge where month=m;return n;
end$$;
create or replace function public.paper_company_coverage_claim(p_manual boolean default false)returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare r paperlab.company_coverage_runtime;d date:=(now()at time zone'UTC')::date;m date:=date_trunc('month',now()at time zone'UTC')::date;targets jsonb;t uuid;used bigint;reserve bigint;
begin
 select *into r from paperlab.company_coverage_runtime where singleton for update;if not r.enabled or r.policy is null or r.lease_until>now()then return null;end if;
 insert into paperlab.company_coverage_usage(day)values(d)on conflict do nothing;insert into paperlab.free_usage(month)values(m)on conflict do nothing;
 delete from paperlab.company_coverage_usage where day<d-400;delete from paperlab.company_coverage_events where id in(select id from paperlab.company_coverage_events order by id desc offset 1000);
 select coalesce(sum(estimated_bytes),0)into used from paperlab.company_coverage_usage where day>=m;reserve:=(r.policy->>'reserved_batch_bytes')::bigint;
 if(select batches from paperlab.company_coverage_usage where day=d)>=(r.policy->>'max_batches_day')::int or used+reserve>(r.policy->>'max_month_bytes')::bigint or pg_database_size(current_database())>=(r.policy->>'max_database_bytes')::bigint or(select estimated_worker_egress_bytes from paperlab.free_usage where month=m)+reserve>(r.policy->>'shared_month_bytes')::bigint or(select sum(pg_total_relation_size(x::regclass))from unnest(array['paperlab.company_coverage','paperlab.company_coverage_events','paperlab.company_coverage_usage','paperlab.company_coverage_runtime'])x)>=(r.policy->>'max_storage_bytes')::bigint then update paperlab.company_coverage_runtime set status='budget_or_daily_limit'where singleton;return null;end if;
 select coalesce(jsonb_agg(c),'[]')into targets from(select c from jsonb_array_elements(r.catalogue)c left join paperlab.company_coverage v on v.symbol=c->>'symbol'where p_manual or v.checked_at is null or v.checked_at<now()-make_interval(days=>(r.policy->>'refresh_after_days')::int)order by v.checked_at nulls first,c->>'symbol'limit(r.policy->>'per_batch')::int)x;
 if jsonb_array_length(targets)=0 then return null;end if;
 update paperlab.company_coverage_usage set batches=batches+1,estimated_bytes=estimated_bytes+reserve where day=d;update paperlab.free_usage set estimated_worker_egress_bytes=estimated_worker_egress_bytes+reserve where month=m;
 t:=gen_random_uuid();update paperlab.company_coverage_runtime set token=t,lease_until=now()+interval'90 seconds',last_claim=now(),status='collecting'where singleton;
 return jsonb_build_object('token',t,'targets',targets,'policy',r.policy);
end$$;
create or replace function public.paper_company_coverage_commit(p_token uuid,p_rows jsonb)returns boolean language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare r paperlab.company_coverage_runtime;x jsonb;old paperlab.company_coverage;updated jsonb;bytes bigint:=0;d date;m date;changed boolean;
begin
 select *into r from paperlab.company_coverage_runtime where singleton and token=p_token and lease_until>now()for update;if not found then return false;end if;
 if jsonb_array_length(p_rows)>(r.policy->>'per_batch')::int then raise exception'Coverage batch size';end if;
 for x in select value from jsonb_array_elements(p_rows)loop
  if not exists(select 1 from jsonb_array_elements(r.catalogue)c where c->>'symbol'=x->>'symbol')or(x->>'source_bytes')::int not between 0 and(r.policy->>'max_source_bytes')::int or octet_length(x::text)>24000 then raise exception'Coverage source rejected';end if;
  select *into old from paperlab.company_coverage where symbol=x->>'symbol'for update;updated:=coalesce(old.record,'{}'::jsonb);bytes:=bytes+coalesce((x->>'source_bytes')::bigint,(r.policy->>'max_source_bytes')::bigint)+2*octet_length(x::text)+2048;
  if x->'observation'is not null and(coalesce(x->>'financial_fingerprint','')!~'^[a-f0-9]{64}$'or jsonb_typeof(x->'observation'->'values')is distinct from'object'or(x->'observation'->>'known_at')::timestamptz>now()+interval'5 seconds')then raise exception'Invalid financial observation';end if;
  if x->'observation'is not null then
   changed:=old.record->>'financial_fingerprint'is not null and old.record->>'financial_fingerprint'is distinct from x->>'financial_fingerprint';
   updated:=(updated-'secondary_error')||x||jsonb_build_object('secondary_status','observed','secondary_checked_at',now());
   if changed then
    insert into paperlab.company_coverage_events(symbol,record)values(x->>'symbol',jsonb_build_object('kind','financial_source_changed','previous_fingerprint',old.record->>'financial_fingerprint','new_fingerprint',x->>'financial_fingerprint','previous_period',old.record->'observation'->'financial'->>'period_end','new_period',x->'observation'->'financial'->>'period_end','approval',false));
    if exists(select 1 from paperlab.company_dossiers where symbol=x->>'symbol')then perform public.paper_company_save(jsonb_build_object('version','company-dossier-v1','symbol',x->>'symbol','known_at',now(),'checked_at',now(),'status','financial_source_change_requires_review','financial','{}'::jsonb));end if;
    updated:=updated-'verified_financials';
   end if;
  else updated:=updated||jsonb_build_object('secondary_status','source_unavailable','secondary_checked_at',now(),'secondary_error',x->>'source_status');end if;
  if octet_length(updated::text)>24000 then raise exception'Coverage record size';end if;
  insert into paperlab.company_coverage values(x->>'symbol',now(),updated)on conflict(symbol)do update set checked_at=excluded.checked_at,record=excluded.record;
 end loop;
 if bytes>(r.policy->>'reserved_batch_bytes')::bigint then raise exception'Coverage reserve exceeded';end if;
 d:=(r.last_claim at time zone'UTC')::date;m:=date_trunc('month',r.last_claim at time zone'UTC')::date;
 update paperlab.company_coverage_usage set estimated_bytes=estimated_bytes-(r.policy->>'reserved_batch_bytes')::bigint+bytes where day=d;update paperlab.free_usage set estimated_worker_egress_bytes=estimated_worker_egress_bytes-(r.policy->>'reserved_batch_bytes')::bigint+bytes where month=m;
 update paperlab.company_coverage_runtime set token=null,lease_until=null,last_success=now(),status=case when exists(select 1 from jsonb_array_elements(p_rows)batch_row where batch_row->'observation'is null)then'observing_with_source_gaps'else'observing'end where singleton;return true;
end$$;
create or replace function public.paper_company_coverage_fail(p_token uuid)returns void language plpgsql security definer set search_path=pg_catalog,pg_temp as $$begin update paperlab.company_coverage_runtime set token=null,lease_until=null,status='source_or_processing_error'where singleton and token=p_token;end$$;
create or replace function public.paper_company_coverage_read(p_owner uuid,p_symbol text default null)returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton)then raise exception'Owner required';end if;
 return jsonb_build_object('runtime',(select to_jsonb(r)-'token'-'lease_until'-'catalogue'from paperlab.company_coverage_runtime r),
 'counts',(select jsonb_build_object('companies',count(*),'primary_reachable',count(*)filter(where record->'primary'->>'status'='200'),'primary_financial_extracts',count(*)filter(where jsonb_typeof(record->'verified_financials')='object'),'secondary_financials',count(*)filter(where record->'observation'->'financial'->>'revenue'is not null),'source_updates',count(*)filter(where record->>'secondary_status'='observed'),'source_failed',count(*)filter(where record->>'secondary_status'='source_unavailable'))from paperlab.company_coverage),
 'qualitative_reviews',(select count(distinct symbol)from paperlab.company_reviews where reviewed_at>=now()-interval'7 days'),
 'records',(select coalesce(jsonb_agg(record order by symbol),'[]')from paperlab.company_coverage where symbol=p_symbol),
 'company_dossier',paperlab.company_records()->p_symbol,'price',(select(state->'prices'->>p_symbol)::float8 from paperlab.portfolio),
 'price_time',(select state->'last_observation'->p_symbol->>'time'from paperlab.portfolio),
 'events',(select coalesce(jsonb_agg(to_jsonb(e)order by id desc),'[]')from(select id,at,symbol,record from paperlab.company_coverage_events where p_symbol is not null and symbol=p_symbol order by id desc limit 5)e),
 'storage_bytes',(select sum(pg_total_relation_size(x::regclass))from unnest(array['paperlab.company_coverage','paperlab.company_coverage_events','paperlab.company_coverage_runtime','paperlab.company_coverage_usage'])x));end$$;
create or replace function public.paper_company_coverage_stage(p_symbol text)returns text language plpgsql security definer set search_path=pg_catalog,pg_temp as $$declare v jsonb;begin
 select record->'verified_financials'into v from paperlab.company_coverage where symbol=p_symbol;
 if v is null or v='null'::jsonb or v->>'symbol'is distinct from p_symbol or v->>'version'is distinct from'company-dossier-v1'or coalesce(v->'latest_report'->>'form','')not in('10-K','10-Q')then raise exception'Official financial evidence required';end if;
 -- This prepares financial input only; an absent qualitative review remains absent.
 return public.paper_company_save(v);
end$$;
do $$declare n text;begin for n in select p.oid::regprocedure::text from pg_proc p join pg_namespace s on s.oid=p.pronamespace where s.nspname='public'and p.proname like'paper_company_coverage_%'loop execute'revoke all on function '||n||' from public,anon,authenticated';execute'grant execute on function '||n||' to service_role';end loop;end$$;
revoke all on function public.paper_company_coverage_configure(jsonb,jsonb),public.paper_company_coverage_import(jsonb),public.paper_company_coverage_stage(text)from service_role;
commit;
