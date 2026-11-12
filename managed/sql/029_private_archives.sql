begin;
alter table paperlab.project_followup add column if not exists backup_token uuid;
alter table paperlab.project_followup add column if not exists backup_until timestamptz;
alter table paperlab.project_followup add column if not exists archive_month date;
alter table paperlab.project_followup add column if not exists archive_bytes bigint not null default 0;
alter table paperlab.project_followup add column if not exists backup_info jsonb;
create table if not exists paperlab.backup_chunks(token uuid not null,part integer not null,expires_at timestamptz not null,body text not null check(octet_length(body)<=4000000),primary key(token,part));
alter table paperlab.backup_chunks enable row level security;
revoke all on paperlab.backup_chunks from public,anon,authenticated,service_role;
create or replace function paperlab.project_snapshot()returns jsonb language plpgsql stable security definer set search_path=pg_catalog,pg_temp set extra_float_digits=3 as $$
declare name text;rows jsonb;data jsonb:='{}';total_bytes bigint:=0;begin
 for name in select tablename from pg_tables where schemaname='paperlab'and tablename not in('backup_chunks','observations','history_snapshots','research_queue','benchmark_observations','archive_manifest','free_usage','company_usage','company_coverage_usage','capital_usage','iex_usage','daily_usage')order by tablename loop
  execute format('select coalesce(jsonb_agg(to_jsonb(t)-''token''-''lease''-''lease_until''-''backup_token''-''backup_until''-''backup_info''-''watch_token''-''watch_until''),''[]''::jsonb)from paperlab.%I t',name)into rows;
  data:=data||jsonb_build_object(name,rows);
  total_bytes:=total_bytes+octet_length(rows::text);
  if total_bytes>30000000 then raise exception'Logical backup exceeds 30MB bound';end if;
 end loop;
 return data;
end$$;
revoke all on function paperlab.project_snapshot()from public,anon,authenticated,service_role;
create or replace function public.paper_project_backup_input()returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare r paperlab.project_followup;m date:=(date_trunc('month',now()at time zone'UTC'))::date;name text;rows jsonb;data jsonb:='{}';archive_token uuid;snapshot_text text;i integer;parts integer;begin
 select *into r from paperlab.project_followup where singleton for update;
 if r.backup_until>now()and r.backup_info is not null then return r.backup_info;end if;
 if not r.enabled or r.backup_until>now()or exists(select 1 from paperlab.archive_manifest where record->>'kind'='application_snapshot'and (created_at at time zone'UTC')::date=(now()at time zone'UTC')::date)then return null;end if;
 if r.archive_month is distinct from m then r.archive_bytes:=0;end if;
 insert into paperlab.free_usage(month)values(m)on conflict do nothing;perform 1 from paperlab.free_usage where month=m for update;
 if r.archive_bytes+50000000>300000000 or(select estimated_worker_egress_bytes+50000000 from paperlab.free_usage where month=m)>paperlab.traffic_limit('soft')or pg_database_size(current_database())>100000000 then return null;end if;
 -- STABLE helper reads one MVCC snapshot, with lossless float output.
 data:=paperlab.project_snapshot();
 archive_token:=gen_random_uuid();update paperlab.project_followup set backup_token=archive_token,backup_until=now()+interval'120 seconds',archive_month=m,archive_bytes=r.archive_bytes+50000000 where singleton;
 update paperlab.free_usage set estimated_worker_egress_bytes=estimated_worker_egress_bytes+50000000 where month=m;
 snapshot_text:=jsonb_build_object('version','paperlab-logical-snapshot-v1','at',now(),'schema_version',case when to_regclass('paperlab.earnings_cycles')is not null then 33 when to_regclass('paperlab.swing_runtime')is not null then 32 when to_regclass('paperlab.strategy_priority')is not null then 31 else 30 end,'tables',data,'excluded','Auth users/MFA, vault secrets, Storage objects and selected transient quotes, historical input snapshots, queues, meters and reference observations. Source text has a separate archive.','restore_mode','offline rehearsal first; never automatic portfolio reset')::text;
 parts:=ceil(length(snapshot_text)/1000000.0)::integer;
 delete from paperlab.backup_chunks where expires_at<now();
 for i in 0..parts-1 loop insert into paperlab.backup_chunks values(archive_token,i,now()+interval'120 seconds',substring(snapshot_text from i*1000000+1 for 1000000));end loop;
 update paperlab.project_followup set backup_info=jsonb_build_object('token',archive_token,'parts',parts,'plaintext_sha256',encode(sha256(convert_to(snapshot_text,'UTF8')),'hex'),'object_path','backups/'||to_char(now()at time zone'UTC','YYYY-MM-DD')||'.json.enc')where singleton;
 return(select backup_info from paperlab.project_followup where singleton);
end$$;
create or replace function public.paper_project_prepare_weekly_backup()returns void language plpgsql security definer set search_path=pg_catalog,pg_temp as $$begin
 if extract(isodow from(now()at time zone'UTC'))=7 then
  begin perform public.paper_project_backup_input();exception when others then update paperlab.project_followup set diagnostics=diagnostics||jsonb_build_object('backup_prepare_failed',true)where singleton;end;
 end if;
end$$;
revoke all on function public.paper_project_prepare_weekly_backup()from public,anon,authenticated,service_role;
create or replace function public.paper_project_backup_chunk(p_token uuid,p_part integer)returns text language plpgsql security definer set search_path=pg_catalog,pg_temp as $$begin
 if not exists(select 1 from paperlab.project_followup where singleton and backup_token=p_token and backup_until>now())then raise exception'Archive lease expired';end if;
 return(select body from paperlab.backup_chunks where token=p_token and part=p_part and expires_at>now());
end$$;
revoke all on function public.paper_project_backup_chunk(uuid,integer)from public,anon,authenticated,service_role;
grant execute on function public.paper_project_backup_chunk(uuid,integer)to service_role;
create or replace function public.paper_project_backup_commit(p_token uuid,p_record jsonb)returns boolean language plpgsql security definer set search_path=pg_catalog,pg_temp as $$begin
 if not exists(select 1 from paperlab.project_followup where singleton and backup_token=p_token and backup_until>now()for update)then return false;end if;
 if p_record->>'kind'is distinct from'application_snapshot'or p_record->'restore_tested'is distinct from'true'::jsonb or p_record->>'object_path'!~'^backups/[0-9-]+\.json\.enc$'or coalesce(p_record->>'sha256','')!~'^[a-f0-9]{64}$'or(p_record->>'bytes')::bigint not between 1 and 15000000 or octet_length(p_record::text)>6000 then raise exception'Invalid archive proof';end if;
 insert into paperlab.archive_manifest(id,record)values('backup-'||(p_record->>'object_path'),p_record)on conflict do nothing;
 delete from paperlab.backup_chunks where token=p_token;
 update paperlab.project_followup set backup_token=null,backup_until=null,backup_info=null where singleton;return true;
end$$;
create or replace function public.paper_project_archive_path(p_owner uuid,p_id text)returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton)then raise exception'Owner required';end if;
 return(select jsonb_build_object('object_path',record->>'object_path')from paperlab.archive_manifest where id=p_id and(record->>'object_path'~'^backups/[0-9-]+\.json\.enc$'or record->>'object_path'~'^sources/[a-z0-9-]+\.json\.enc$'));
end$$;
create or replace function public.paper_project_archive_prune(p_confirmed jsonb default null)returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare paths jsonb;begin
 select coalesce(jsonb_agg(record->>'object_path'),'[]')into paths from(select record from paperlab.archive_manifest where record->>'kind'='application_snapshot'order by created_at desc offset 7)a;
 if p_confirmed is not null then
  if jsonb_typeof(p_confirmed)is distinct from'array'or exists(select 1 from jsonb_array_elements_text(p_confirmed)p where not paths?p)then raise exception'Unexpected archive deletion';end if;
  delete from paperlab.archive_manifest where record->>'kind'='application_snapshot'and p_confirmed?(record->>'object_path');
 end if;return paths;
end$$;
revoke all on function public.paper_project_backup_input(),public.paper_project_backup_commit(uuid,jsonb),public.paper_project_archive_path(uuid,text)from public,anon,authenticated,service_role;
grant execute on function public.paper_project_backup_input(),public.paper_project_backup_commit(uuid,jsonb),public.paper_project_archive_path(uuid,text)to service_role;
revoke all on function public.paper_project_archive_prune(jsonb)from public,anon,authenticated,service_role;
grant execute on function public.paper_project_archive_prune(jsonb)to service_role;
-- Expiring leases and secrets are never included in a logical restore payload.
commit;
