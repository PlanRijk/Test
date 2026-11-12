begin;
create table if not exists paperlab.publication_watch(symbol text primary key,checked_at timestamptz not null,status text not null,record jsonb not null check(octet_length(record::text)<=16000));
alter table paperlab.publication_watch enable row level security;revoke all on paperlab.publication_watch from public,anon,authenticated,service_role;
alter table paperlab.project_followup add column if not exists watch_day date;
alter table paperlab.project_followup add column if not exists watch_month date;
alter table paperlab.project_followup add column if not exists watch_bytes bigint not null default 0;
alter table paperlab.project_followup add column if not exists watch_token uuid;
alter table paperlab.project_followup add column if not exists watch_until timestamptz;
alter table paperlab.project_followup add column if not exists watch_targets jsonb not null default '[]';
create or replace function public.paper_project_watch_claim()returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare r paperlab.project_followup;d date:=(now()at time zone'UTC')::date;m date:=(date_trunc('month',now()at time zone'UTC'))::date;targets jsonb;t uuid;begin
 select *into r from paperlab.project_followup where singleton for update;if not r.enabled or r.watch_day=d or r.watch_until>now()or extract(isodow from d)>5 then return null;end if;
 if r.watch_month is distinct from m then r.watch_bytes:=0;end if;
 insert into paperlab.free_usage(month)values(m)on conflict do nothing;perform 1 from paperlab.free_usage where month=m for update;
 if r.watch_bytes+5000000>120000000 or(select estimated_worker_egress_bytes+5000000 from paperlab.free_usage where month=m)>paperlab.traffic_limit('soft')or pg_database_size(current_database())>100000000 then return null;end if;
 select jsonb_agg(jsonb_build_object('symbol',c->>'symbol'))into targets from(select c from paperlab.company_coverage_runtime rt,jsonb_array_elements(rt.catalogue)c left join paperlab.publication_watch w on w.symbol=c->>'symbol'left join paperlab.research_queue q on q.symbol=c->>'symbol'order by w.checked_at nulls first,q.priority desc,c->>'symbol'limit 20)tgt;
 t:=gen_random_uuid();update paperlab.project_followup set watch_day=d,watch_month=m,watch_bytes=r.watch_bytes+5000000,watch_token=t,watch_targets=targets,watch_until=now()+interval'100 seconds'where singleton;
 update paperlab.free_usage set estimated_worker_egress_bytes=estimated_worker_egress_bytes+5000000 where month=m;
 return jsonb_build_object('token',t,'targets',targets);
end$$;
create or replace function public.paper_project_watch_commit(p_token uuid,p_rows jsonb)returns boolean language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare x jsonb;old jsonb;changed boolean;new_material boolean;s text;review jsonb;begin
 if not exists(select 1 from paperlab.project_followup where singleton and watch_token=p_token and watch_until>now()for update)then return false;end if;
 if jsonb_typeof(p_rows)is distinct from'array'or jsonb_array_length(p_rows)>20 or(select count(distinct value->>'symbol')from jsonb_array_elements(p_rows))<>jsonb_array_length(p_rows)then raise exception'Bounded publication batch';end if;
 for x in select value from jsonb_array_elements(p_rows)loop
  s:=x->>'symbol';if not exists(select 1 from paperlab.company_coverage_runtime rt,jsonb_array_elements(rt.catalogue)c where c->>'symbol'=s)or not exists(select 1 from paperlab.project_followup f,jsonb_array_elements(f.watch_targets)t where t->>'symbol'=s)or octet_length(x::text)>16000 or coalesce(x->>'status','')not in('observed','not_available','too_large','rate_limited')then raise exception'Invalid publication result';end if;
  select record into old from paperlab.publication_watch where symbol=s;changed:=old->>'sha256'is not null and x->>'status'='observed'and old->>'sha256'is distinct from x->>'sha256';
  if x->>'status'='observed'and(coalesce(x->>'sha256','')!~'^[a-f0-9]{64}$'or jsonb_typeof(x->'refs')is distinct from'array')then raise exception'Invalid publication evidence';end if;
  select record into review from paperlab.company_reviews where symbol=s order by reviewed_at desc limit 1;
  new_material:=false;
  if review is not null and x->>'kind'='SEC_index'and x->>'status'='observed'then
   select exists(select 1 from jsonb_array_elements(x->'refs')f where f->>'form'in('10-K','10-Q','8-K','20-F','6-K')and(f->>'day')::date>=(review->>'reviewed_at')::timestamptz::date and not coalesce(review->'reviewed_accessions','[]')?(f->>'accession'))into new_material;
  end if;
  insert into paperlab.publication_watch values(s,now(),x->>'status',x||jsonb_build_object('changed',changed,'unreviewed_official_disclosure',new_material))on conflict(symbol)do update set checked_at=excluded.checked_at,status=excluded.status,record=case when excluded.status='observed'then excluded.record else excluded.record||jsonb_build_object('last_confirmed',case when paperlab.publication_watch.status='observed'then paperlab.publication_watch.record-'last_confirmed'else paperlab.publication_watch.record->'last_confirmed'end)end;
  if changed or new_material then update paperlab.research_queue set reasons=case when reasons?'official_publication_changed'then reasons else reasons||'"official_publication_changed"'::jsonb end,priority=greatest(priority,90),due_at=now()where symbol=s;end if;
  if new_material and exists(select 1 from paperlab.company_dossiers where symbol=s)then perform public.paper_company_save(jsonb_build_object('version','company-dossier-v1','symbol',s,'known_at',clock_timestamp(),'checked_at',clock_timestamp(),'status','unreviewed_official_disclosure','financial','{}'::jsonb));end if;
 end loop;
 update paperlab.project_followup set watch_token=null,watch_until=null where singleton;return true;
end$$;
create or replace function public.paper_project_publications(p_owner uuid,p_symbol text default null)returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton)then raise exception'Owner required';end if;
 return jsonb_build_object('checked',(select count(*)from paperlab.publication_watch),'confirmed',(select count(*)from paperlab.publication_watch where status='observed'),'record',(select jsonb_build_object('checked_at',checked_at,'status',status,'evidence',record)from paperlab.publication_watch where symbol=p_symbol),'schedule','Maximaal twintig bedrijven per werkdag, oudste controle eerst. Een volledige ronde duurt normaal vijf werkdagen, onder voorbehoud van bronbeschikbaarheid en budget. Alleen publicatie-/paginawijziging, geen volledige automatische interpretatie.');
end$$;
revoke all on function public.paper_project_watch_claim(),public.paper_project_watch_commit(uuid,jsonb),public.paper_project_publications(uuid,text)from public,anon,authenticated,service_role;
grant execute on function public.paper_project_watch_claim(),public.paper_project_watch_commit(uuid,jsonb),public.paper_project_publications(uuid,text)to service_role;
commit;
