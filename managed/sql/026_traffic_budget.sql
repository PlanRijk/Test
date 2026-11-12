-- Traffic budget v2: explicit user authorization for 4 GB monthly app estimate.
-- Only global transfer guards change. Frozen financial profiles, storage,
-- per-study download limits, positions, receipts and existing counters remain.
begin;
set local lock_timeout='5s';
create table if not exists paperlab.traffic_budget_runtime(singleton boolean primary key default true check(singleton),policy jsonb not null,applied_at timestamptz not null default now());
create table if not exists paperlab.traffic_budget_patches(signature text primary key,before_hash text not null,after_hash text not null,applied_at timestamptz not null default now());
alter table paperlab.traffic_budget_runtime enable row level security;
alter table paperlab.traffic_budget_patches enable row level security;
revoke all on paperlab.traffic_budget_runtime,paperlab.traffic_budget_patches from public,anon,authenticated,service_role;
do $budget$declare p jsonb:='{"version":"traffic-budget-v2","hard_bytes":4000000000,"soft_bytes":3200000000,"warning_bytes":2800000000,"provider_uncached_quota_bytes":5000000000,"provider_database_quota_bytes":500000000,"provider_cached_quota_bytes":5000000000,"quota_scope":"organization","month_basis":"UTC calendar month","provider_meter_verified":false,"other_organization_usage_included":false,"storage_limits_changed":false,"financial_rules_changed":false}'::jsonb;begin
 if exists(select 1 from paperlab.traffic_budget_runtime where policy<>p)then raise exception'Traffic budget version frozen';end if;
 insert into paperlab.traffic_budget_runtime(singleton,policy)values(true,p)on conflict do nothing;
end$budget$;
create or replace function paperlab.traffic_limit(p_level text)returns bigint language plpgsql stable security definer set search_path=pg_catalog,pg_temp as $limit$
declare ceiling bigint;cap bigint;begin
 if p_level not in('warning','soft','hard')then raise exception'Unknown traffic limit';end if;
 select(policy->>(p_level||'_bytes'))::bigint into ceiling from paperlab.traffic_budget_runtime where singleton;
 if ceiling is null then raise exception'Traffic budget unavailable';end if;
 select max_worker_egress_bytes into cap from paperlab.free_usage where month=date_trunc('month',now()at time zone'UTC')::date;
 return least(ceiling,coalesce(cap,4000000000));
end$limit$;
revoke all on function paperlab.traffic_limit(text)from public,anon,authenticated,service_role;
alter table paperlab.free_usage drop constraint if exists free_usage_max_worker_egress_bytes_check;
alter table paperlab.free_usage add constraint free_usage_max_worker_egress_bytes_check check(max_worker_egress_bytes between 1 and 4000000000);
alter table paperlab.free_usage alter column max_worker_egress_bytes set default 4000000000;
-- Respect a deliberately lower custom cap. Do not reset or refund estimated use.
update paperlab.free_usage set max_worker_egress_bytes=4000000000 where month=date_trunc('month',now()at time zone'UTC')::date and max_worker_egress_bytes=3000000000;
-- Exact, bounded substitutions in known budget contexts. CREATE OR REPLACE
-- preserves the original function OID, ACL, owner and function-local settings.
do $patch$declare item jsonb;rule jsonb;proc oid;definition text;original text;oldcount integer;newcount integer;begin
 for item in select value from jsonb_array_elements($rules$[{"name":"paper_audit_input","rules":[{"old":"least(max_worker_egress_bytes,2400000000)","new":"paperlab.traffic_limit('soft')","count":1}]},{"name":"paper_claim_research","rules":[{"old":"least(max_worker_egress_bytes,2400000000)","new":"paperlab.traffic_limit('soft')","count":1}]},{"name":"paper_breadth_claim","rules":[{"old":"usage_bytes>=1800000000","new":"usage_bytes>=paperlab.traffic_limit('soft')","count":1},{"old":"usage_bytes>=1500000000","new":"usage_bytes>=paperlab.traffic_limit('soft')","count":1},{"old":"usage_bytes>=1200000000","new":"usage_bytes>=paperlab.traffic_limit('warning')","count":2},{"old":"usage_bytes+charge>=1800000000","new":"usage_bytes+charge>=paperlab.traffic_limit('soft')","count":1}]},{"name":"paper_breadth_commit","rules":[{"old":"estimated_worker_egress_bytes+charge>=1800000000","new":"estimated_worker_egress_bytes+charge>=paperlab.traffic_limit('soft')","count":1}]},{"name":"paper_candidates_claim","rules":[{"old":"usage_bytes>=1200000000","new":"usage_bytes>=paperlab.traffic_limit('soft')","count":1},{"old":"usage_bytes+charge>=1200000000","new":"usage_bytes+charge>=paperlab.traffic_limit('soft')","count":1}]},{"name":"paper_capital_claim_base_v1","rules":[{"old":"total_bytes>=1500000000","new":"total_bytes>=paperlab.traffic_limit('hard')","count":1},{"old":"total_bytes<1200000000","new":"total_bytes<paperlab.traffic_limit('soft')","count":1},{"old":"total_bytes+charge+800000>=1500000000","new":"total_bytes+charge+800000>=paperlab.traffic_limit('hard')","count":1}]},{"name":"paper_capital_commit_base_v1","rules":[{"old":"estimated_worker_egress_bytes+charge>=1500000000","new":"estimated_worker_egress_bytes+charge>=paperlab.traffic_limit('hard')","count":1}]},{"name":"paper_company_claim_entry_v1","rules":[{"old":"(r.policy->>'shared_monthly_ceiling_bytes')::bigint","new":"paperlab.traffic_limit('soft')","count":1}]},{"name":"paper_company_collect_claim","rules":[{"old":"(r.policy->>'shared_monthly_ceiling_bytes')::bigint","new":"paperlab.traffic_limit('soft')","count":1}]},{"name":"paper_company_coverage_claim_source_base_v1","rules":[{"old":"(r.policy->>'shared_month_bytes')::bigint","new":"paperlab.traffic_limit('soft')","count":1}]},{"name":"paper_company_coverage_import","rules":[{"old":"(r.policy->>'shared_month_bytes')::bigint","new":"paperlab.traffic_limit('soft')","count":1}]},{"name":"paper_daily_claim","rules":[{"old":"least(max_worker_egress_bytes,2000000000)","new":"paperlab.traffic_limit('soft')","count":2}]},{"name":"paper_history_claim_transport_v1","rules":[{"old":"least(max_worker_egress_bytes,2000000000)","new":"paperlab.traffic_limit('soft')","count":2}]},{"name":"paper_iex_claim","rules":[{"old":"least(g.max_worker_egress_bytes,1050000000)","new":"paperlab.traffic_limit('soft')","count":1}]},{"name":"paper_learning_budget_guard","rules":[{"old":"<2400000000 then return false","new":"<paperlab.traffic_limit('soft') then return false","count":1},{"old":"2,4GB werkerraming","new":"de actuele gedeelde verkeersgrens","count":1}]},{"name":"paper_opportunity_apply","rules":[{"old":"least(max_worker_egress_bytes,2000000000)","new":"paperlab.traffic_limit('soft')","count":1}]},{"name":"paper_opportunity_guard","rules":[{"old":"estimated_worker_egress_bytes>=2000000000","new":"estimated_worker_egress_bytes>=paperlab.traffic_limit('soft')","count":1}]},{"name":"paper_reading_claim","rules":[{"old":"total_bytes+300000>=1200000000","new":"total_bytes+300000>=paperlab.traffic_limit('soft')","count":1}]},{"name":"paper_source_claim","rules":[{"old":"(c.policy->>'shared_month_bytes')::bigint","new":"paperlab.traffic_limit('soft')","count":1}]},{"name":"paper_source_commit","rules":[{"old":"(c.policy->>'shared_month_bytes')::bigint","new":"paperlab.traffic_limit('soft')","count":1}]}]$rules$::jsonb)loop
  select p.oid into strict proc from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'and p.proname=item->>'name';
  definition:=pg_get_functiondef(proc);original:=definition;
  if exists(select 1 from paperlab.traffic_budget_patches where signature=proc::regprocedure::text)then
   if encode(sha256(convert_to(definition,'UTF8')),'hex')=(select after_hash from paperlab.traffic_budget_patches where signature=proc::regprocedure::text)then continue;end if;
   if encode(sha256(convert_to(definition,'UTF8')),'hex')<>(select before_hash from paperlab.traffic_budget_patches where signature=proc::regprocedure::text)then raise exception'Budget-patched function changed: %',item->>'name';end if;
  end if;
  for rule in select value from jsonb_array_elements(item->'rules')loop
   oldcount:=(length(definition)-length(replace(definition,rule->>'old','')))/length(rule->>'old');
   if oldcount<>(rule->>'count')::int then raise exception'Unexpected budget source: % / %',item->>'name',rule->>'old';end if;
   definition:=replace(definition,rule->>'old',rule->>'new');
  end loop;
  execute definition;
  insert into paperlab.traffic_budget_patches(signature,before_hash,after_hash)values(proc::regprocedure::text,encode(sha256(convert_to(original,'UTF8')),'hex'),encode(sha256(convert_to(pg_get_functiondef(proc),'UTF8')),'hex'))on conflict(signature)do update set after_hash=excluded.after_hash;
 end loop;
end$patch$;
create or replace function public.paper_traffic_budget_read(p_owner uuid)returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $read$
begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton)then raise exception'Owner required';end if;
 return jsonb_build_object('checked_at',now(),'policy',(select policy from paperlab.traffic_budget_runtime),'estimated_month_bytes',coalesce((select estimated_worker_egress_bytes from paperlab.free_usage where month=date_trunc('month',now()at time zone'UTC')::date),0),'month',date_trunc('month',now()at time zone'UTC')::date,'effective_hard_bytes',paperlab.traffic_limit('hard'),'effective_soft_bytes',paperlab.traffic_limit('soft'),'effective_warning_bytes',paperlab.traffic_limit('warning'),'database_bytes',pg_database_size(current_database()),'reading_enabled',(select enabled from paperlab.reading_runtime),'provider_usage_url','https://supabase.com/dashboard/org/mbeljbybwiosetomvmwq/usage','render_usage_separate',true);
end$read$;
revoke all on function public.paper_traffic_budget_read(uuid)from public,anon,authenticated;
grant execute on function public.paper_traffic_budget_read(uuid)to service_role;
commit;
