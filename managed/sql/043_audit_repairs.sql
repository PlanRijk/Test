-- Reliability repairs; no change to financial selection thresholds or historical forecasts.
begin;
do $$declare s text;begin
 s:=pg_get_functiondef('paperlab.project_snapshot()'::regprocedure);s:=replace(s,'30000000','80000000');execute s;
 s:=pg_get_functiondef('public.paper_project_backup_commit(uuid,jsonb)'::regprocedure);s:=replace(s,'15000000','30000000');execute s;
 s:=pg_get_functiondef('public.paper_project_backup_input()'::regprocedure);s:=replace(s,'interval''120 seconds''','interval''600 seconds''');s:=replace(s,'then 42 when','then 43 when');execute s;
 s:=pg_get_functiondef('public.paper_deep_commit(uuid,jsonb)'::regprocedure);
 if position('full_report:=jsonb_array_length' in s)=0 then s:=replace(s,'full_report:=coalesce(',$patch$full_report:=jsonb_array_length(coalesce(p_result->'missing_information','[]'::jsonb))=0 and coalesce($patch$);execute s;end if;
end$$;
-- PostgREST safeupdate forbids an unqualified UPDATE, including inside this definer function.
do $$declare s text;begin s:=pg_get_functiondef('public.paper_project_refresh()'::regprocedure);s:=replace(s,$old$else '[]'::jsonb end;$old$,$new$else '[]'::jsonb end where q.symbol is not null;$new$);execute s;end$$;
-- Assemble the outer JSON object once instead of copying it for each table.
create or replace function paperlab.project_snapshot()returns jsonb language plpgsql stable security definer set search_path=pg_catalog,pg_temp set extra_float_digits=3 set jit=off as $$declare n text;q text:='';part text;d jsonb;projection text;begin
 for n in select tablename from pg_tables where schemaname='paperlab'and tablename not in('backup_chunks','observations','history_snapshots','research_queue','benchmark_observations','archive_manifest','free_usage','company_usage','company_coverage_usage','capital_usage','iex_usage','daily_usage','deep_events')order by tablename loop
 select string_agg(format('%I',attname),',')into projection from pg_attribute where attrelid=('paperlab.'||quote_ident(n))::regclass and attnum>0 and not attisdropped and not(n='deep_documents'and attname='body');
 part:=format('select %L as name,coalesce(jsonb_agg((to_jsonb(t)%s)-''token''-''lease''-''lease_until''-''backup_token''-''backup_until''-''backup_info''-''watch_token''-''watch_until''),''[]''::jsonb)as rows from (select %s from paperlab.%I)t%s',n,case when n='deep_documents'then ' || jsonb_build_object(''body'','''')'else ''end,projection,n,case when n='deep_jobs'then ' where t.status in(''completed'',''retry'',''blocked'')and(t.doc_id is null or exists(select 1 from paperlab.deep_documents d where d.id=t.doc_id and d.active))'else ''end);
 q:=q||case when q=''then ''else ' union all 'end||part;
 end loop;
 execute 'select jsonb_object_agg(name,rows)from('||q||')z'into d;
 if octet_length(d::text)>80000000 then raise exception'Logical backup exceeds 80MB bound';end if;return d;
end$$;
revoke all on function paperlab.project_snapshot()from public,anon,authenticated,service_role;
update paperlab.deep_companies set report=jsonb_set(report,'{full_ai_dossier}','false'),status=case when status='full_ai_dossier_completed'then'dossier_completed_with_gaps'else status end where report->>'full_ai_dossier'='true'and jsonb_array_length(coalesce(report->'audit'->'missing_information','[]'))>0;
create or replace function paperlab.macro_context()returns jsonb language sql stable security definer set search_path=pg_catalog,pg_temp as $$select jsonb_build_object('checked_at',r.report->>'checked_at','indicators',(select coalesce(jsonb_agg(jsonb_build_object('id',s->>'id','url',s->>'url','indicator',s->'indicator')),'[]')from jsonb_array_elements(coalesce(r.report->'sources','[]'))s where s->'indicator'is not null),'rate_expectations_status','not_connected','scope','Vertraagde broncontext, geen voorspellend marktregime. Ontbrekende beleidsrentes, rentefutures en inflatieverwachtingen zijn onbekend; verzin geen rentepad.')from(select report from paperlab.research order by id desc limit 1)r$$;
revoke all on function paperlab.macro_context()from public,anon,authenticated,service_role;

create table if not exists paperlab.operations_measurements(day date primary key,checked_at timestamptz not null,record jsonb not null);
alter table paperlab.operations_measurements enable row level security;
revoke all on paperlab.operations_measurements from public,anon,authenticated,service_role;
create or replace function public.paper_operations_check()returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$declare d jsonb;b timestamptz;begin
 select max(created_at)into b from paperlab.archive_manifest where record->>'kind'='application_snapshot';
 d:=jsonb_build_object('checked_at',now(),'database_bytes',pg_database_size(current_database()),'object_bytes',(select coalesce(sum((metadata->>'size')::bigint),0)from storage.objects),'last_backup',b,'backup_stale',b is null or b<now()-interval'7 days','fresh_trade_reviews',(select count(*)from paperlab.company_reviews where reviewed_at>now()-interval'7 days'),'quarterly_actuals_missing',(select count(*)from paperlab.earnings_cycles where release_at<now()-interval'1 day'and actual is null),'overdue_earnings_tasks',(select count(*)from paperlab.earnings_tasks where status='pending'and due_at<now()),'research_reports',(select count(*)from paperlab.deep_companies where report is not null),'remaining_research_transfer_bytes',(select greatest(0,paperlab.traffic_limit('soft')-estimated_worker_egress_bytes)from paperlab.free_usage where month=date_trunc('month',now())::date),'followup_stale',(select last_success is null or last_success<now()-interval'3 days'from paperlab.project_followup));
 insert into paperlab.operations_measurements values(current_date,now(),d)on conflict(day)do update set checked_at=excluded.checked_at,record=excluded.record;
 delete from paperlab.operations_measurements where day<current_date-365;
 -- Retain scheduler diagnostics for all project jobs, including recently added workers.
 delete from cron.job_run_details where runid in(select r.runid from cron.job_run_details r join cron.job j using(jobid)where j.jobname like'paperlab-%'and r.end_time<now()-interval'7 days'order by r.end_time limit 10000);
 return d;
end$$;
revoke all on function public.paper_operations_check()from public,anon,authenticated,service_role;
-- Expose the health snapshot only through the existing owner-gated read.
do $$begin if to_regprocedure('public.paper_project_read_ops_base(uuid,text)')is null then alter function public.paper_project_read(uuid,text)rename to paper_project_read_ops_base;end if;end$$;
create or replace function public.paper_project_read(p_owner uuid,p_symbol text default null)returns jsonb language sql security definer set search_path=pg_catalog,pg_temp as $$select public.paper_project_read_ops_base(p_owner,p_symbol)||jsonb_build_object('operations',(select record from paperlab.operations_measurements order by day desc limit 1))$$;
revoke all on function public.paper_project_read_ops_base(uuid,text),public.paper_project_read(uuid,text)from public,anon,authenticated,service_role;
grant execute on function public.paper_project_read(uuid,text)to service_role;
do $$declare s text;begin s:=pg_get_functiondef('public.paper_deep_claim()'::regprocedure);if position('macro_context'in s)=0 then s:=replace(s,$old$'peer_context',paperlab.dossier_peers(j.symbol)$old$,$new$'macro_context',paperlab.macro_context(),'peer_context',paperlab.dossier_peers(j.symbol)$new$);execute s;end if;end$$;
do $$declare s text;begin s:=pg_get_functiondef('public.paper_deep_claim()'::regprocedure);s:=replace(s,$old$jsonb_build_object('source_url',record->>'source_url'$old$,$new$jsonb_build_object('sector',(select value->>'sector'from paperlab.company_coverage_runtime rt,jsonb_array_elements(rt.catalogue)where value->>'symbol'=j.symbol limit 1),'source_url',record->>'source_url'$new$);execute s;end$$;
alter function public.paper_project_backup_input()set jit=off;
-- JSON text aggregation avoids repeatedly reparsing large immutable row arrays.
create or replace function paperlab.project_snapshot_text()returns text language plpgsql stable security definer set search_path=pg_catalog,pg_temp set extra_float_digits=3 set jit=off as $$declare n text;q text:='';p text;cols text;d text;begin
 for n in select tablename from pg_tables where schemaname='paperlab'and tablename not in('backup_chunks','observations','history_snapshots','research_queue','benchmark_observations','archive_manifest','free_usage','company_usage','company_coverage_usage','capital_usage','iex_usage','daily_usage','deep_events')order by tablename loop
 select string_agg(format('%I',attname),','order by attnum)into cols from pg_attribute where attrelid=('paperlab.'||quote_ident(n))::regclass and attnum>0 and not attisdropped and attname not in('token','lease','lease_until','backup_token','backup_until','backup_info','watch_token','watch_until')and not(n='deep_documents'and attname='body');
 if n='deep_documents'then cols:=cols||',''''::text as body';end if;
 p:=format('select %L as name,coalesce(json_agg(row_to_json(t)),''[]''::json)::text as rows from(select %s from paperlab.%I%s)t',n,cols,n,case when n='deep_jobs'then ' where status in(''completed'',''retry'',''blocked'')and(doc_id is null or exists(select 1 from paperlab.deep_documents d where d.id=deep_jobs.doc_id and d.active))'else ''end);
 q:=q||case when q=''then ''else ' union all 'end||p;
 end loop;
 execute 'select ''{''||string_agg(to_json(name)::text||'':''||rows,'','')||''}''from('||q||')z'into d;
 if octet_length(d)>80000000 then raise exception'Logical backup exceeds 80MB bound';end if;return d;
end$$;
revoke all on function paperlab.project_snapshot_text()from public,anon,authenticated,service_role;
do $$declare s text;begin
 s:=pg_get_functiondef('public.paper_project_backup_input()'::regprocedure);
 s:=replace(s,'data jsonb','data text');s:=replace(s,'data:=paperlab.project_snapshot();','data:=paperlab.project_snapshot_text();');
 s:=replace(s,$old$'tables',data,$old$,'');
 if position($tag$||data||$tag$in s)=0 then s:=replace(s,'parts:=ceil(', $patch$snapshot_text:=left(snapshot_text,length(snapshot_text)-1)||',"tables":'||data||'}'; parts:=ceil($patch$);end if;
 execute s;
end$$;

do $$declare s text;begin s:=pg_get_functiondef('public.paper_project_backup_input()'::regprocedure);s:=regexp_replace(s,$old$'schema_version',case.*?end,'excluded'$old$,$new$'schema_version',43,'excluded'$new$);execute s;end$$;
create table if not exists paperlab.backup_part_proofs(token uuid,part int,record jsonb not null,primary key(token,part));
alter table paperlab.backup_part_proofs enable row level security;
revoke all on paperlab.backup_part_proofs from public,anon,authenticated,service_role;
do $$begin if to_regprocedure('public.paper_project_backup_prepare()')is null then alter function public.paper_project_backup_input()rename to paper_project_backup_prepare;end if;end$$;
create or replace function public.paper_project_backup_input()returns jsonb language sql security definer set search_path=pg_catalog,pg_temp as $$select r.backup_info||jsonb_build_object('next_part',coalesce((select min(i)from generate_series(0,(r.backup_info->>'parts')::int-1)i where not exists(select 1 from paperlab.backup_part_proofs p where p.token=r.backup_token and p.part=i)),(r.backup_info->>'parts')::int),'part_records',(select coalesce(jsonb_agg(record order by part),'[]')from paperlab.backup_part_proofs where token=r.backup_token))from paperlab.project_followup r where singleton and enabled and backup_until>now()and backup_info is not null$$;
create or replace function public.paper_backup_part_commit(p_token uuid,p_part int,p_record jsonb)returns boolean language plpgsql security definer set search_path=pg_catalog,pg_temp as $$declare r paperlab.project_followup;begin
 select *into r from paperlab.project_followup where singleton and backup_token=p_token and backup_until>now()for update;if not found then return false;end if;
 if p_part<0 or p_part>=(r.backup_info->>'parts')::int or p_record->>'path'is distinct from replace(r.backup_info->>'object_path','.json.enc','-part-'||p_part||'.json.enc')or p_record->>'sha256'!~'^[a-f0-9]{64}$'or(p_record->>'bytes')::int not between 1 and 15000000 then raise exception'Invalid backup part';end if;
 insert into paperlab.backup_part_proofs values(p_token,p_part,p_record)on conflict do nothing;return true;
end$$;
revoke all on function public.paper_project_backup_prepare(),public.paper_project_backup_input(),public.paper_backup_part_commit(uuid,int,jsonb)from public,anon,authenticated,service_role;
grant execute on function public.paper_project_backup_input(),public.paper_backup_part_commit(uuid,int,jsonb)to service_role;
-- A preparation runs in SQL outside the short API timeout. Each Edge invocation processes one bounded chunk.
alter function public.paper_project_backup_prepare()set jit=off;
do $$declare s text;begin s:=pg_get_functiondef('public.paper_project_backup_prepare()'::regprocedure);s:=replace(s,'600 seconds','7200 seconds');execute s;end$$;
update paperlab.project_followup set backup_until=now()+interval'2 hours'where singleton and backup_info is not null;
update paperlab.backup_chunks set expires_at=now()+interval'2 hours'where token=(select backup_token from paperlab.project_followup where singleton);

do $$declare s text;begin s:=pg_get_functiondef('public.paper_project_backup_prepare()'::regprocedure);s:=regexp_replace(s,$old$'schema_version',case.*?end,'excluded'$old$,$new$'schema_version',43,'excluded'$new$);execute s;end$$;
do $$declare s text;begin s:=pg_get_functiondef('public.paper_project_backup_commit(uuid,jsonb)'::regprocedure);s:=replace(s,'backup_info=null where singleton;', $new$backup_info=null,diagnostics=diagnostics-'backup_prepare_failed'where singleton;$new$);execute s;end$$;
do $$declare s text;begin s:=pg_get_functiondef('public.paper_project_backup_prepare()'::regprocedure);s:=replace(s,'r.archive_bytes+50000000>300000000','r.archive_bytes+80000000>400000000');s:=replace(s,'50000000','80000000');s:=replace(s,$old$paperlab.traffic_limit('soft')$old$,$new$paperlab.traffic_limit('hard')$new$);execute s;end$$;
-- Account conservatively for the extra multipart verification traffic, once only.
do $$declare i text;begin
 select id into i from paperlab.archive_manifest where record->>'kind'='application_snapshot'and record->>'format'='paperlab-multipart-archive-v1'and created_at::date=current_date and not record?'reservation_settled'order by created_at desc limit 1 for update;
 if i is not null then
 update paperlab.free_usage set estimated_worker_egress_bytes=estimated_worker_egress_bytes+30000000 where month=date_trunc('month',now())::date;
 update paperlab.project_followup set archive_bytes=archive_bytes+30000000 where singleton;
 update paperlab.archive_manifest set record=record||'{"reservation_settled":true,"app_reservation_bytes":80000000}'::jsonb where id=i;
 end if;
end$$;

-- Prioritize completing already cached dossiers inside the existing 4 GB hard ceiling.
-- Fresh downloads and auxiliary studies keep the original 3.2 GB soft ceiling.
create or replace function paperlab.cached_research_limit()returns bigint language sql stable security definer set search_path=pg_catalog,pg_temp as $$select greatest(0,paperlab.traffic_limit('hard')-500000000)$$;
revoke all on function paperlab.cached_research_limit()from public,anon,authenticated,service_role;
do $$declare s text;begin
 s:=pg_get_functiondef('public.paper_deep_claim()'::regprocedure);
 s:=replace(s,$old$paperlab.traffic_limit('soft')$old$,'paperlab.cached_research_limit()');
 if position('x.stage<>''discover''or'in s)=0 then s:=replace(s,$old$where x.status in('queued','retry')$old$,$new$where(x.stage<>'discover'or coalesce((select estimated_worker_egress_bytes from paperlab.free_usage where month=m),0)<paperlab.traffic_limit('soft'))and x.status in('queued','retry')$new$);end if;execute s;
 s:=pg_get_functiondef('public.paper_dossier_watchdog()'::regprocedure);s:=replace(s,$old$paperlab.traffic_limit('soft')$old$,'paperlab.cached_research_limit()');execute s;
 s:=pg_get_functiondef('public.paper_operations_check()'::regprocedure);if position('remaining_cached_research_transfer_bytes'in s)=0 then s:=replace(s,$old$'remaining_research_transfer_bytes',$old$,$new$'remaining_cached_research_transfer_bytes',(select greatest(0,paperlab.cached_research_limit()-estimated_worker_egress_bytes)from paperlab.free_usage where month=date_trunc('month',now())::date),'remaining_research_transfer_bytes',$new$);execute s;end if;
end$$;

commit;