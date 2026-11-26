-- Owner-only diagnostics. No trading, research or financial policy changes.
begin;
do $$begin if to_regprocedure('public.paper_dashboard_read_status_base(uuid)')is null then alter function public.paper_dashboard_read(uuid)rename to paper_dashboard_read_status_base;end if;end$$;
create or replace function public.paper_dashboard_read(p_owner uuid)returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare d jsonb;used bigint;own bigint;allocated bigint;db bigint;trades bigint;source_counts jsonb;source_age int;begin
 d:=public.paper_dashboard_read_status_base(p_owner);if coalesce((d->>'available')::boolean,false)is not true then return d;end if;
 select estimated_worker_egress_bytes into used from paperlab.free_usage where month=date_trunc('month',now()at time zone'UTC')::date;
 select estimated_bytes into own from paperlab.capital_usage where month=date_trunc('month',now()at time zone'UTC')::date;
 select sum(pg_total_relation_size(x::regclass))into allocated from unnest(array['paperlab.capital_runtime','paperlab.capital_trades','paperlab.capital_curve','paperlab.capital_usage'])x;
 db:=pg_database_size(current_database());select count(*)into trades from paperlab.capital_trades;
 select coalesce((policy->>'max_check_age_days')::int,8)into source_age from paperlab.company_runtime where singleton;
 select jsonb_build_object('dossiers',count(*),'fresh',count(*)filter(where(record->>'checked_at')::timestamptz between now()-make_interval(days=>source_age)and now()),'max_age_days',source_age,'collector_status',(select status from paperlab.company_runtime where singleton),'fresh_does_not_imply_approval',true)into source_counts from(select distinct on(symbol)symbol,record from paperlab.company_dossiers where known_at<=now()order by symbol,known_at desc,id desc)x;

 return d||jsonb_build_object('entry_status',jsonb_build_object('checked_at',now(),'configured_entry_enabled',(select new_entries_allowed from paperlab.strategy_priority where singleton),
 'traffic',jsonb_build_object('used_bytes',used,'entry_limit_bytes',paperlab.traffic_limit('soft'),'hard_limit_bytes',paperlab.traffic_limit('hard'),'blocked',used>=paperlab.traffic_limit('soft'),'next_window_at',(date_trunc('month',now()at time zone'UTC')+interval'1 month')at time zone'UTC','provider_verified',false),
 'storage',jsonb_build_object('database_bytes',db,'entry_limit_bytes',paperlab.storage_limit('soft'),'hard_limit_bytes',paperlab.storage_limit('hard'),'blocked',db>=paperlab.storage_limit('soft')),
 'account_budget',jsonb_build_object('used_bytes',own,'entry_limit_bytes',240000000,'blocked',own>=240000000,'allocated_bytes',allocated,'allocation_entry_limit_bytes',12000000,'allocation_blocked',allocated>=12000000,'trades',trades,'trade_entry_limit',1800,'trade_limit_blocked',trades>=1800),
 'sources',source_counts,'reviews',jsonb_build_object('total',(select count(*)from paperlab.company_reviews),'current',(select count(distinct symbol)from paperlab.company_reviews where reviewed_at between now()-interval'7 days'and now()),'last_review_at',(select max(reviewed_at)from paperlab.company_reviews),'max_age_days',7,'current_does_not_imply_approval',true),
 'note','Actuele toelatingsvoorwaarden en laatste uitvoeringsronde zijn afzonderlijke metingen. Een recente review geeft niet automatisch vijf-pijlergoedkeuring. App-verkeer is een conservatieve raming, geen providerfactuur.'));
end$$;
revoke all on function public.paper_dashboard_read_status_base(uuid),public.paper_dashboard_read(uuid)from public,anon,authenticated,service_role;
grant execute on function public.paper_dashboard_read(uuid)to service_role;
commit;
