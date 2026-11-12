-- Operator research is separate from trade-eligible qualitative approvals.
begin;
create table if not exists paperlab.company_research(
 symbol text primary key,checked_at timestamptz not null,
 record jsonb not null check(octet_length(record::text)<=24000)
);
alter table paperlab.company_research enable row level security;
revoke all on paperlab.company_research from public,anon,authenticated,service_role;
create or replace function public.paper_company_research_save(p_records jsonb)
returns integer language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare x jsonb;n integer:=0;charge bigint:=0;m date:=(date_trunc('month',now()at time zone'UTC'))::date;used bigint;begin
 if jsonb_typeof(p_records)is distinct from'array'or jsonb_array_length(p_records)>10 then raise exception'Bounded research batch required';end if;
 -- Serialize admission and charge against the existing application transfer meter.
 insert into paperlab.free_usage(month)values(m)on conflict do nothing;
 select estimated_worker_egress_bytes into used from paperlab.free_usage where month=m for update;
 for x in select value from jsonb_array_elements(p_records)loop
  if x->>'version'is distinct from'company-research-v1'or x->'trade_approval'is distinct from'false'::jsonb
   or x->'complete_qualitative_review'is distinct from'false'::jsonb
   or not exists(select 1 from paperlab.company_coverage_runtime r,jsonb_array_elements(r.catalogue)c where c->>'symbol'=x->>'symbol')
   or jsonb_typeof(x->'sources')is distinct from'array'or jsonb_typeof(x->'findings')is distinct from'array'
   or jsonb_typeof(x->'gaps')is distinct from'array'or octet_length(x::text)>24000
   or coalesce(x->>'checked_at','')=''or(x->>'checked_at')::timestamptz>now()+interval'5 seconds'
   or exists(select 1 from jsonb_array_elements(x->'sources')s where coalesce(s->>'url','')!~'^https://'or coalesce(s->>'sha256','')!~'^[a-f0-9]{64}$')
  then raise exception'Invalid research evidence';end if;
  charge:=charge+2*octet_length(x::text)+2048;
  insert into paperlab.company_research values(x->>'symbol',(x->>'checked_at')::timestamptz,x)
   on conflict(symbol)do update set checked_at=excluded.checked_at,record=excluded.record where excluded.checked_at>paperlab.company_research.checked_at;
  n:=n+1;
 end loop;
 if used+charge>3200000000 or exists(select 1 from paperlab.free_usage where month=m and used+charge>max_worker_egress_bytes)
  or pg_database_size(current_database())>100000000 or pg_total_relation_size('paperlab.company_research')>4000000 then raise exception'Research budget limit';end if;
 update paperlab.free_usage set estimated_worker_egress_bytes=estimated_worker_egress_bytes+charge where month=m;
 return n;
end$$;
create or replace function public.paper_company_research_read(p_owner uuid,p_symbol text default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton)then raise exception'Owner required';end if;
 return jsonb_build_object('counts',(select jsonb_build_object('companies',count(*),'with_documents',count(*)filter(where jsonb_array_length(record->'sources')>0),'with_gaps',count(*)filter(where jsonb_array_length(record->'gaps')>0),'latest_checked_at',max(checked_at))from paperlab.company_research),
  'record',(select record from paperlab.company_research where symbol=p_symbol),
  'method','Brononderzoek tijdens werksessies; geen autonome tekstanalist of koopgoedkeuring. Bronmonitor en risicocontroles blijven afzonderlijk actief.');
end$$;
revoke all on function public.paper_company_research_save(jsonb),public.paper_company_research_read(uuid,text)from public,anon,authenticated,service_role;
grant execute on function public.paper_company_research_read(uuid,text)to service_role;
commit;
