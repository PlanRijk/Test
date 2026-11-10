begin;
create table if not exists paperlab.company_runtime(singleton boolean primary key default true check(singleton),enabled boolean not null default true,profile text,policy jsonb,started_at timestamptz,last_success timestamptz,status text not null default 'waiting',token uuid,lease_until timestamptz,last_claim timestamptz,claim_symbol text,catalogue jsonb not null default '[]');
insert into paperlab.company_runtime(singleton)values(true)on conflict do nothing;
create table if not exists paperlab.company_dossiers(id text primary key,symbol text not null,known_at timestamptz not null default now(),record jsonb not null check(octet_length(record::text)<=24000));
create index if not exists company_latest on paperlab.company_dossiers(symbol,known_at desc);
create table if not exists paperlab.company_reviews(id text primary key,symbol text not null,reviewed_at timestamptz not null,record jsonb not null check(octet_length(record::text)<=12000));
create index if not exists company_review_latest on paperlab.company_reviews(symbol,reviewed_at desc);
create table if not exists paperlab.company_usage(day date primary key,attempts integer not null default 0,source_bytes bigint not null default 0,transport_bytes bigint not null default 0);
create table if not exists paperlab.company_epochs(profile text primary key,started_at timestamptz not null,policy jsonb not null,baseline jsonb not null,cancelled_orders jsonb not null);
do $$declare n text;begin foreach n in array array['company_runtime','company_dossiers','company_reviews','company_usage','company_epochs']loop execute format('alter table paperlab.%I enable row level security',n);execute format('revoke all on paperlab.%I from public,anon,authenticated,service_role',n);end loop;end$$;
create or replace function public.paper_company_configure(p_policy jsonb,p_catalogue jsonb)returns text language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare r paperlab.company_runtime;c paperlab.capital_runtime;fp text;cancelled jsonb;
begin
 if not(p_policy @>'{"version":"company-entry-v1","pillars":["growth","profitability","valuation","moat","risks"],"real_orders":false,"automatic_risk_text_approval":false}'::jsonb)or coalesce(p_policy->>'implementation_sha256','')!~'^[a-f0-9]{64}$'or jsonb_array_length(p_catalogue)<>100 then raise exception'Invalid company protocol';end if;
 select *into r from paperlab.company_runtime where singleton for update;fp:=encode(sha256(convert_to(p_policy::text,'UTF8')),'hex');if r.profile is not null then if r.profile<>fp then raise exception'Existing company policy frozen';end if;return fp;end if;
 select *into c from paperlab.capital_runtime where singleton for update;if c.execution_profile is null then raise exception'Multiday account required';end if;
 select coalesce(jsonb_agg(o),'[]')into cancelled from jsonb_array_elements(c.state->'pending')o where o->>'side'='koop';
 insert into paperlab.company_epochs values(fp,now(),p_policy,jsonb_build_object('summary',c.summary,'positions',c.state->'positions','last_trade_id',(select coalesce(max(id),0)from paperlab.capital_trades),'carried_losses',true,'independent_restart',false),cancelled);
 update paperlab.company_runtime set profile=fp,policy=p_policy,catalogue=p_catalogue,started_at=now(),status='collecting_evidence'where singleton;
 update paperlab.capital_runtime set token=null,lease_until=null,revision=revision+1,state=jsonb_set(state,'{pending}',coalesce((select jsonb_agg(o)from jsonb_array_elements(state->'pending')o where o->>'side'<>'koop'),'[]')),allow_entries=false where singleton;
 return fp;
end$$;
create or replace function public.paper_company_save(p_record jsonb)returns text language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare id_value text;s text:=p_record->>'symbol';
begin
 if not exists(select 1 from paperlab.company_runtime r,jsonb_array_elements(r.catalogue)c where c->>'symbol'=s)or p_record->>'version' is distinct from'company-dossier-v1'or octet_length(p_record::text)>24000 or(p_record->>'known_at')::timestamptz>now()+interval'5 seconds' then raise exception'Invalid dossier';end if;
 id_value:='co-'||substr(encode(sha256(convert_to(p_record::text,'UTF8')),'hex'),1,24);
 insert into paperlab.company_dossiers values(id_value,s,(p_record->>'known_at')::timestamptz,p_record)on conflict do nothing;
 delete from paperlab.company_dossiers where id in(select id from paperlab.company_dossiers where symbol=s order by known_at desc,id desc offset 2);return id_value;
end$$;
create or replace function public.paper_company_review_save(p_record jsonb)returns text language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare id_value text;s text:=p_record->>'symbol';
begin
 if not exists(select 1 from paperlab.company_dossiers where symbol=s)or octet_length(p_record::text)>12000 or jsonb_typeof(p_record->'sources')is distinct from'array'or jsonb_array_length(p_record->'sources')=0 or(p_record->>'reviewed_at')::timestamptz>now()+interval'5 seconds' then raise exception'Invalid qualitative review';end if;
 id_value:='cr-'||substr(encode(sha256(convert_to(p_record::text,'UTF8')),'hex'),1,24);insert into paperlab.company_reviews values(id_value,s,(p_record->>'reviewed_at')::timestamptz,p_record)on conflict do nothing;
 delete from paperlab.company_reviews where id in(select id from paperlab.company_reviews where symbol=s order by reviewed_at desc,id desc offset 2);return id_value;
end$$;
create or replace function paperlab.company_records()returns jsonb language sql security definer set search_path=pg_catalog,pg_temp as $$
 select coalesce(jsonb_object_agg(d.symbol,d.record||jsonb_build_object('id',d.id,'review',q.record||jsonb_build_object('id',q.id))),'{}')from(select distinct on(symbol)*from paperlab.company_dossiers where known_at<=now()order by symbol,known_at desc,id desc)d left join lateral(select *from paperlab.company_reviews where symbol=d.symbol and reviewed_at<=now()order by reviewed_at desc,id desc limit 1)q on true
$$;
revoke all on function paperlab.company_records()from public,anon,authenticated,service_role;
-- Previous worker can still manage protective sells, but cannot bypass the overlay.
create or replace function public.paper_capital_claim_multiday(p_tick_token uuid,p_base_revision bigint)returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$declare r paperlab.capital_runtime;x jsonb;begin
 select *into r from paperlab.capital_runtime where singleton for update;if r.execution_profile is null then return null;end if;
 x:=public.paper_capital_claim_base_v1(p_tick_token,p_base_revision);if x is null then return null;end if;
 return x||jsonb_build_object('execution_policy',r.execution_policy,'execution_profile',r.execution_profile,'execution_revision',r.execution_revision,'allow_entries',case when exists(select 1 from paperlab.company_runtime where profile is not null)then false else(x->>'allow_entries')::boolean end);end$$;
create or replace function public.paper_company_claim(p_tick_token uuid,p_base_revision bigint)returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare c paperlab.capital_runtime;r paperlab.company_runtime;x jsonb;ds jsonb;bars jsonb;payload jsonb;charge bigint;m date:=date_trunc('month',now()at time zone'UTC')::date;used bigint;
begin
 select *into r from paperlab.company_runtime where singleton;select *into c from paperlab.capital_runtime where singleton for update;
 if r.profile is null or c.execution_profile is null then return null;end if;x:=public.paper_capital_claim_base_v1(p_tick_token,p_base_revision);if x is null then return null;end if;
 -- Only explicitly reviewed dossiers are transported; all others fail closed.
 select coalesce(jsonb_object_agg(key,value),'{}')into ds from(select key,value from jsonb_each(paperlab.company_records())where(value->'review'->>'reviewed_at')::timestamptz>=now()-interval'7 days'and(not(c.state->'positions'?key)or exists(select 1 from jsonb_array_elements(c.state->'pending')o where o->>'symbol'=key and o->>'side'='koop'))order by exists(select 1 from jsonb_array_elements(c.state->'pending')o where o->>'symbol'=key)desc,coalesce((select(state->'history'->key->-1->>'price')::float8/nullif((state->'history'->key->-6->>'price')::float8,0)-1 from paperlab.portfolio where singleton),-1)desc,key limit 20)d;
 select coalesce(jsonb_object_agg(key,value->'market_closes'),'{}')into bars from jsonb_each(ds);
 -- Add newer already stored daily closes without changing the frozen day study.
 select coalesce(jsonb_object_agg(k.key,(select coalesce(jsonb_agg(to_jsonb(z)order by day),'[]')from(select distinct on(day)*from(select a->>'day'as day,(a->>'close')::float8 as close,a->>'observed_at'as observed_at from jsonb_array_elements(coalesce(bars->k.key,'[]'))a union all select b.day::text,b.close,b.observed_at::text from paperlab.daily_study_bars b where b.symbol=k.key and b.observed_at<=now())u order by day desc,observed_at desc limit 20)z)),'{}')into bars from jsonb_each(ds)k;
 payload:=jsonb_build_object('company_policy',r.policy,'company_profile',r.profile,'company_dossiers',ds,'company_daily',bars);
 charge:=2*octet_length(payload::text)+2048;
 select coalesce(sum(transport_bytes+source_bytes),0)into used from paperlab.company_usage where day>=m;
 insert into paperlab.company_usage(day)values((now()at time zone'UTC')::date)on conflict do nothing;
 if not r.enabled or octet_length(payload::text)>120000 or used+charge>(r.policy->>'max_monthly_bytes')::bigint or(select estimated_worker_egress_bytes from paperlab.free_usage where month=m)+charge>(r.policy->>'shared_monthly_ceiling_bytes')::bigint then
  payload:=jsonb_build_object('company_policy',r.policy,'company_profile',r.profile,'company_dossiers','{}'::jsonb,'company_daily','{}'::jsonb);x:=jsonb_set(x,'{allow_entries}','false');charge:=2*octet_length(payload::text)+2048;
 end if;
 update paperlab.company_usage set transport_bytes=transport_bytes+charge where day=(now()at time zone'UTC')::date;update paperlab.free_usage set estimated_worker_egress_bytes=estimated_worker_egress_bytes+charge where month=m;
 return x||payload||jsonb_build_object('execution_policy',c.execution_policy,'execution_profile',c.execution_profile,'execution_revision',c.execution_revision);
end$$;
create or replace function public.paper_company_commit(p_token uuid,p_output jsonb)returns boolean language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare r paperlab.company_runtime;t jsonb;a jsonb;
begin
 select *into r from paperlab.company_runtime where singleton;if p_output->>'company_profile'is distinct from r.profile or p_output->>'company_policy'is distinct from'company-entry-v1'then raise exception'Company profile mismatch';end if;
 for t in select value from jsonb_array_elements(p_output->'trades')where value->>'side'='koop'loop
  a:=t->'snapshot'->'purchase_rationale'->'company_execution_check';
  if coalesce((a->>'eligible')::boolean,false)is not true or t->'snapshot'->'purchase_rationale'->'company_entry'->>'profile'is distinct from r.profile or (select count(*)from jsonb_object_keys(a->'assessment'->'pillars'))<>5 or not((a->'assessment'->'pillars')?&array['growth','profitability','valuation','moat','risks']) or exists(select 1 from jsonb_each(a->'assessment'->'pillars')p where p.value->>'status'is distinct from'pass')or not exists(select 1 from paperlab.company_dossiers where id=a->'assessment'->>'dossier_id'and symbol=t->>'symbol'and id=(select id from paperlab.company_dossiers d where d.symbol=t->>'symbol'order by known_at desc,id desc limit 1))or not exists(select 1 from paperlab.company_reviews where id=a->'assessment'->>'review_id'and symbol=t->>'symbol')then raise exception'Five-pillar entry evidence required';end if;
 end loop;
 return public.paper_capital_commit_multiday(p_token,p_output);
end$$;
create or replace function public.paper_company_collect_claim()returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare r paperlab.company_runtime;d date:=(now()at time zone'UTC')::date;m date:=date_trunc('month',now()at time zone'UTC')::date;u bigint;item jsonb;t uuid;reserve bigint;
begin
 select *into r from paperlab.company_runtime where singleton for update;if not r.enabled or r.profile is null or r.lease_until>now()then return null;end if;
 insert into paperlab.company_usage(day)values(d)on conflict do nothing;insert into paperlab.free_usage(month)values(m)on conflict do nothing;reserve:=(r.policy->>'reserved_bytes')::bigint;
 select sum(source_bytes+transport_bytes)into u from paperlab.company_usage where day>=m;
 delete from paperlab.company_usage where day<d-400;
 if(select sum(pg_total_relation_size(x::regclass))from unnest(array['paperlab.company_dossiers','paperlab.company_reviews','paperlab.company_usage','paperlab.company_runtime','paperlab.company_epochs'])x)>=(r.policy->>'max_storage_bytes')::bigint or(select attempts from paperlab.company_usage where day=d)>=(r.policy->>'max_collections_per_day')::int or u+reserve>(r.policy->>'max_monthly_bytes')::bigint or pg_database_size(current_database())>=(r.policy->>'max_database_bytes')::bigint or(select estimated_worker_egress_bytes from paperlab.free_usage where month=m)+reserve>(r.policy->>'shared_monthly_ceiling_bytes')::bigint then update paperlab.company_runtime set status='budget_or_daily_limit'where singleton;return null;end if;
 select c into item from jsonb_array_elements(r.catalogue)c left join lateral(select max(known_at)as at from paperlab.company_dossiers where symbol=c->>'symbol')q on true where c->>'cik'~'^\d{10}$'and(q.at is null or q.at<now()-interval'1 day')order by q.at nulls first,c->>'symbol'limit 1;if item is null then return null;end if;
 update paperlab.company_usage set attempts=attempts+1,source_bytes=source_bytes+reserve where day=d;update paperlab.free_usage set estimated_worker_egress_bytes=estimated_worker_egress_bytes+reserve where month=m;
 t:=gen_random_uuid();update paperlab.company_runtime set token=t,lease_until=now()+interval'90 seconds',claim_symbol=item->>'symbol',last_claim=now(),status='collecting'where singleton;
 return jsonb_build_object('token',t,'item',item,'policy',r.policy,'reserved_bytes',reserve);
end$$;
create or replace function public.paper_company_collect_commit(p_token uuid,p_record jsonb,p_source_bytes bigint)returns boolean language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare r paperlab.company_runtime;charge bigint;m date:=date_trunc('month',now()at time zone'UTC')::date;
begin
 select *into r from paperlab.company_runtime where singleton and token=p_token and lease_until>now()for update;if not found then return false;end if;
 if p_record->>'symbol'is distinct from r.claim_symbol or p_source_bytes<0 or p_source_bytes>(r.policy->>'reserved_bytes')::bigint then raise exception'Invalid collection';end if;
 perform public.paper_company_save(p_record);charge:=p_source_bytes+2*octet_length(p_record::text)+2048;
 if charge>(r.policy->>'reserved_bytes')::bigint then raise exception'Collection budget exceeded';end if;
 update paperlab.company_usage set source_bytes=source_bytes-(r.policy->>'reserved_bytes')::bigint+charge where day=(r.last_claim at time zone'UTC')::date;update paperlab.free_usage set estimated_worker_egress_bytes=estimated_worker_egress_bytes-(r.policy->>'reserved_bytes')::bigint+charge where month=date_trunc('month',r.last_claim at time zone'UTC')::date;
 update paperlab.company_runtime set token=null,lease_until=null,last_success=now(),status='evidence_collected'where singleton;return true;
end$$;
create or replace function public.paper_company_collect_fail(p_token uuid)returns void language plpgsql security definer set search_path=pg_catalog,pg_temp as $$declare r paperlab.company_runtime;begin
 select *into r from paperlab.company_runtime where singleton and token=p_token for update;if not found then return;end if;
 perform public.paper_company_save(jsonb_build_object('version','company-dossier-v1','symbol',r.claim_symbol,'known_at',now(),'checked_at',now(),'status','source_unavailable','financial','{}'::jsonb));
 update paperlab.company_runtime set token=null,lease_until=null,status='source_unavailable'where singleton and token=p_token;end$$;
create or replace function public.paper_company_read(p_owner uuid)returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton)then raise exception'Owner required';end if;
 return jsonb_build_object('runtime',(select to_jsonb(r)-'token'-'lease_until'from paperlab.company_runtime r),'dossiers',paperlab.company_records(),'prices',(select state->'prices'from paperlab.portfolio),'usage',(select jsonb_build_object('source_bytes',sum(source_bytes),'transport_bytes',sum(transport_bytes),'attempts',sum(attempts))from paperlab.company_usage where day>=date_trunc('month',now()at time zone'UTC')::date),'storage_bytes',(select sum(pg_total_relation_size(x::regclass))from unnest(array['paperlab.company_dossiers','paperlab.company_reviews','paperlab.company_usage','paperlab.company_runtime','paperlab.company_epochs'])x));end$$;
create or replace function public.paper_company_summary(p_owner uuid)returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton)then raise exception'Owner required';end if;
 return jsonb_build_object('profile',(select profile from paperlab.company_runtime),'enabled',(select enabled from paperlab.company_runtime),'policy',(select policy from paperlab.company_runtime),'status',(select status from paperlab.company_runtime),'dossiers',(select count(distinct symbol)from paperlab.company_dossiers),'reviewed',(select count(distinct symbol)from paperlab.company_reviews where reviewed_at>=now()-interval'7 days'),'started_at',(select started_at from paperlab.company_runtime));end$$;
do $$declare n text;begin for n in select p.oid::regprocedure::text from pg_proc p join pg_namespace s on s.oid=p.pronamespace where s.nspname='public'and p.proname like'paper_company_%'loop execute'revoke all on function '||n||' from public,anon,authenticated';execute'grant execute on function '||n||' to service_role';end loop;end$$;
-- Bootstrap and qualitative review are management-only operations, never browser actions.
revoke all on function public.paper_company_configure(jsonb,jsonb),public.paper_company_review_save(jsonb)from service_role;
commit;
