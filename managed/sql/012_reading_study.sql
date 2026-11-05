begin;
create table if not exists paperlab.reading_runtime(singleton boolean primary key default true check(singleton),enabled boolean not null default true,policy jsonb,cursor integer not null default 0 check(cursor>=0),token uuid,lease_until timestamptz,last_day date,last_attempt timestamptz,attempt_day date,attempts integer not null default 0,status text not null default 'waiting',last_success timestamptz);
insert into paperlab.reading_runtime(singleton) values(true) on conflict do nothing;
create table if not exists paperlab.reading_notes(day date primary key,report jsonb not null check(octet_length(report::text)<=8000));
create table if not exists paperlab.reading_usage(month date primary key,estimated_bytes bigint not null default 0 check(estimated_bytes>=0));
do $$declare n text;begin foreach n in array array['reading_runtime','reading_notes','reading_usage']loop execute format('alter table paperlab.%I enable row level security',n);execute format('revoke all on paperlab.%I from public,anon,authenticated,service_role',n);end loop;end$$;
create or replace function public.paper_reading_configure(p_policy jsonb) returns boolean language plpgsql security definer set search_path=pg_catalog,pg_temp as $$declare old jsonb;begin
 if p_policy->>'version' is distinct from 'buffett-reading-v1' or coalesce(p_policy->>'implementation_sha256','') !~ '^[a-f0-9]{64}$' or jsonb_array_length(p_policy->'library') is distinct from 8 or octet_length(p_policy::text)>20000 then raise exception 'Invalid reading policy';end if;
 select policy into old from paperlab.reading_runtime where singleton for update;if old is not null and old<>p_policy then raise exception 'Existing reading policy frozen';end if;
 update paperlab.reading_runtime set policy=p_policy where singleton;return true;end$$;
create or replace function public.paper_reading_claim() returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare r paperlab.reading_runtime;d date:=(now() at time zone 'UTC')::date;m date:=date_trunc('month',now() at time zone 'UTC')::date;t uuid;own_bytes bigint;total_bytes bigint;allocated bigint;
begin
 select * into r from paperlab.reading_runtime where singleton for update;
 if not r.enabled or r.policy is null or r.last_day=d or r.lease_until>now() or r.last_attempt>now()-interval '30 minutes' or (r.attempt_day=d and r.attempts>=3) then return null;end if;
 delete from paperlab.reading_notes where day<d-120 or day in(select day from paperlab.reading_notes order by day desc offset 119);
 delete from paperlab.reading_usage where month<m-interval '18 months';
 if to_regclass('cron.job_run_details') is not null then execute 'delete from cron.job_run_details where runid in(select d.runid from cron.job_run_details d join cron.job j using(jobid) where j.jobname=''paperlab-reading'' and d.end_time<now()-interval ''7 days'' limit 100)';end if;
 insert into paperlab.reading_usage(month)values(m) on conflict do nothing;insert into paperlab.free_usage(month)values(m) on conflict do nothing;
 select estimated_worker_egress_bytes into total_bytes from paperlab.free_usage where month=m for update;select estimated_bytes into own_bytes from paperlab.reading_usage where month=m for update;
 select sum(pg_total_relation_size(x::regclass)) into allocated from unnest(array['paperlab.reading_runtime','paperlab.reading_notes','paperlab.reading_usage'])x;
 if pg_database_size(current_database())>=100000000 or allocated>=2000000 or own_bytes+300000>=20000000 or total_bytes+300000>=1200000000 then update paperlab.reading_runtime set status='budget_paused' where singleton;return null;end if;
 -- Reserve a bounded attempt up front, including failed/terminated downloads.
 update paperlab.reading_usage set estimated_bytes=estimated_bytes+300000 where month=m;update paperlab.free_usage set estimated_worker_egress_bytes=estimated_worker_egress_bytes+300000 where month=m;
 t:=gen_random_uuid();update paperlab.reading_runtime set token=t,lease_until=now()+interval '90 seconds',last_attempt=now(),attempt_day=d,attempts=case when r.attempt_day=d then r.attempts+1 else 1 end,status='processing' where singleton;
 return jsonb_build_object('token',t,'day',d,'cursor',r.cursor,'policy',r.policy);
end$$;
create or replace function public.paper_reading_commit(p_token uuid,p_report jsonb) returns boolean language plpgsql security definer set search_path=pg_catalog,pg_temp as $$declare r paperlab.reading_runtime;card jsonb;d date:=(now() at time zone 'UTC')::date;begin
 select * into r from paperlab.reading_runtime where singleton and token=p_token and lease_until>now() for update;if not found then return false;end if;
 card:=r.policy->'library'->(r.cursor%8);
 if p_report->>'day' is distinct from d::text or p_report->>'card_id' is distinct from card->>'id' or p_report->>'url' is distinct from card->>'url' or p_report->>'version' is distinct from 'buffett-reading-v1' or coalesce(p_report->>'status','') not in('verified','source_invalid','source_unavailable') or octet_length(p_report::text)>8000
 or p_report->>'read_scope' is distinct from 'selected_passage_verification' or p_report->>'analysis_origin' is distinct from 'editor_reviewed_at_setup' or p_report->>'automatic_model_training' is distinct from 'false' or p_report->>'trading_changes' is distinct from 'false' then raise exception 'Invalid reading note';end if;
 if p_report->>'status'='verified' and(coalesce(p_report->>'content_sha256','') !~ '^[a-f0-9]{64}$' or p_report->>'lesson' is null or (p_report->>'source_bytes')::integer>262144) then raise exception 'Unverified reading source';end if;
 if p_report->>'status'<>'verified' and(p_report ? 'lesson' or p_report ? 'question') then raise exception 'Failed source has no confirmed lesson';end if;
 insert into paperlab.reading_notes values(d,p_report);
 update paperlab.reading_runtime set cursor=cursor+case when p_report->>'status'='verified' then 1 else 0 end,last_day=d,token=null,lease_until=null,status=p_report->>'status',last_success=case when p_report->>'status'='verified' then now() else last_success end where singleton;return true;
end$$;
create or replace function public.paper_reading_fail(p_token uuid) returns void language sql security definer set search_path=pg_catalog,pg_temp as $$update paperlab.reading_runtime set token=null,lease_until=null,status='error' where singleton and token=p_token$$;
create or replace function public.paper_reading_read(p_owner uuid) returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton) then raise exception 'Owner required';end if;
 return jsonb_build_object('runtime',(select to_jsonb(r)-'token'-'lease_until' from paperlab.reading_runtime r),'notes',(select coalesce(jsonb_agg(report order by day desc),'[]') from(select day,report from paperlab.reading_notes order by day desc limit 30)n),'usage',(select to_jsonb(u) from paperlab.reading_usage u where month=date_trunc('month',now() at time zone 'UTC')::date));end$$;
create or replace function public.paper_reading_action(p_owner uuid,p_action text) returns boolean language plpgsql security definer set search_path=pg_catalog,pg_temp as $$begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton) then raise exception 'Owner required';end if;
 if p_action not in('pause','resume') then return false;end if;
 update paperlab.reading_runtime set enabled=p_action='resume',token=null,lease_until=null,status=case when p_action='pause' then 'owner_paused' else 'waiting' end where singleton;return true;end$$;
revoke all on function public.paper_reading_configure(jsonb),public.paper_reading_claim(),public.paper_reading_commit(uuid,jsonb),public.paper_reading_fail(uuid),public.paper_reading_read(uuid),public.paper_reading_action(uuid,text) from public,anon,authenticated;
grant execute on function public.paper_reading_configure(jsonb),public.paper_reading_claim(),public.paper_reading_commit(uuid,jsonb),public.paper_reading_fail(uuid),public.paper_reading_read(uuid),public.paper_reading_action(uuid,text) to service_role;
commit;
