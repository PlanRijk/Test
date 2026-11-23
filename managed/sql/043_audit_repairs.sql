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
create or replace function paperlab.project_snapshot()returns jsonb language plpgsql stable security definer set search_path=pg_catalog,pg_temp set extra_float_digits=3 as $$declare n text;q text:='';part text;d jsonb;begin
 for n in select tablename from pg_tables where schemaname='paperlab'and tablename not in('backup_chunks','observations','history_snapshots','research_queue','benchmark_observations','archive_manifest','free_usage','company_usage','company_coverage_usage','capital_usage','iex_usage','daily_usage','deep_events')order by tablename loop
 part:=format('select %L as name,coalesce(jsonb_agg((to_jsonb(t)%s)-''token''-''lease''-''lease_until''-''backup_token''-''backup_until''-''backup_info''-''watch_token''-''watch_until''),''[]''::jsonb)as rows from paperlab.%I t%s',n,case when n='deep_documents'then ' - ''body'' || jsonb_build_object(''body'','''')'else ''end,n,case when n='deep_jobs'then ' where t.status in(''completed'',''retry'',''blocked'')and(t.doc_id is null or exists(select 1 from paperlab.deep_documents d where d.id=t.doc_id and d.active))'else ''end);
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
commit;
