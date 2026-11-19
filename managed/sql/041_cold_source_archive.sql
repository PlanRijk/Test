-- Lossless cold storage of superseded source texts. Never archive active sources.
begin;
alter table paperlab.deep_documents add column if not exists archive_object_path text;
alter table paperlab.deep_documents add column if not exists archived_at timestamptz;
create table if not exists paperlab.cold_source_runtime(singleton boolean primary key default true check(singleton),token uuid,doc_id text,lease_until timestamptz,month date,estimated_bytes bigint not null default 0);
insert into paperlab.cold_source_runtime(singleton)values(true)on conflict do nothing;
alter table paperlab.cold_source_runtime enable row level security;
revoke all on paperlab.cold_source_runtime from public,anon,authenticated,service_role;
create or replace function public.paper_cold_source_claim()returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$declare r paperlab.cold_source_runtime;d paperlab.deep_documents;m date:=date_trunc('month',now()at time zone'UTC')::date;t uuid;charge bigint;begin
 select *into r from paperlab.cold_source_runtime where singleton for update;if r.lease_until>now()then return null;end if;
 select *into d from paperlab.deep_documents x where not active and body<>''and archived_at is null and not exists(select 1 from paperlab.deep_jobs j where j.doc_id=x.id and j.status='leased')order by pg_column_size(body)desc limit 1 for update;
 if not found then return null;end if;
 charge:=5*octet_length(d.body)+100000;if r.month is distinct from m then r.estimated_bytes:=0;end if;
 insert into paperlab.free_usage(month)values(m)on conflict do nothing;perform 1 from paperlab.free_usage where month=m for update;
 if r.estimated_bytes+charge>100000000 or(select estimated_worker_egress_bytes+charge from paperlab.free_usage where month=m)>paperlab.traffic_limit('soft')or(select coalesce(sum((metadata->>'size')::bigint),0)from storage.objects)+15000000>(select(policy->>'object_hard_bytes')::bigint from paperlab.storage_budget_runtime where singleton)then return null;end if;
 t:=gen_random_uuid();update paperlab.cold_source_runtime set token=t,doc_id=d.id,lease_until=now()+interval'180 seconds',month=m,estimated_bytes=r.estimated_bytes+charge where singleton;
 update paperlab.free_usage set estimated_worker_egress_bytes=estimated_worker_egress_bytes+charge where month=m;
 return jsonb_build_object('token',t,'id',d.id,'symbol',d.symbol,'url',d.url,'sha256',d.sha256,'body_sha256',d.body_sha256,'body',d.body,'scope',d.scope,'object_path','sources/cold-'||d.id||'.json.enc');
end$$;
create or replace function public.paper_cold_source_commit(p_token uuid,p_record jsonb)returns boolean language plpgsql security definer set search_path=pg_catalog,pg_temp as $$declare r paperlab.cold_source_runtime;d paperlab.deep_documents;begin
 select *into r from paperlab.cold_source_runtime where singleton and token=p_token and lease_until>now()for update;if not found then return false;end if;
 select *into d from paperlab.deep_documents where id=r.doc_id for update;
 if d.active or d.body=''or exists(select 1 from paperlab.deep_jobs where doc_id=d.id and status='leased')then return false;end if;
 if p_record->>'object_path'is distinct from 'sources/cold-'||d.id||'.json.enc'or p_record->>'body_sha256'is distinct from d.body_sha256 or p_record->>'verified'is distinct from'true'or coalesce(p_record->>'sha256','')!~'^[a-f0-9]{64}$'or coalesce((p_record->>'bytes')::bigint not between 1 and 15000000,true) or encode(sha256(convert_to(d.body,'UTF8')),'hex')<>d.body_sha256 then raise exception 'Verified exact source archive required';end if;
 insert into paperlab.archive_manifest(id,record)values('cold-'||d.id,jsonb_build_object('kind','cold_source_text','object_path',p_record->>'object_path','bytes',(p_record->>'bytes')::bigint,'sha256',p_record->>'sha256','body_sha256',d.body_sha256,'source_id',d.id,'symbol',d.symbol,'restore_tested',true,'restore_test_scope','Upload, download, AES-GCM/gzip decode, original text equality and original body SHA-256 verified before clearing inactive cache.'))on conflict do nothing;
 update paperlab.deep_documents set body='',archive_object_path=p_record->>'object_path',archived_at=now()where id=d.id;
 update paperlab.cold_source_runtime set token=null,doc_id=null,lease_until=null where singleton;return true;
end$$;
revoke all on function public.paper_cold_source_claim(),public.paper_cold_source_commit(uuid,jsonb)from public,anon,authenticated,service_role;
grant execute on function public.paper_cold_source_claim(),public.paper_cold_source_commit(uuid,jsonb)to service_role;
commit;
