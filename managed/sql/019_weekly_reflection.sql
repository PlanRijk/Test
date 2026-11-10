begin;
-- Read-only market/portfolio inspection. Only this feature's report tables change.
create table if not exists paperlab.weekly_runtime(singleton boolean primary key default true check(singleton),enabled boolean not null default true,last_success timestamptz,status text not null default 'waiting_friday');
insert into paperlab.weekly_runtime(singleton)values(true)on conflict do nothing;
create table if not exists paperlab.weekly_reports(week date not null,kind text not null check(kind in('preview','final')),created_at timestamptz not null,report jsonb not null check(octet_length(report::text)<=24000),primary key(week,kind));
alter table paperlab.weekly_runtime enable row level security;
alter table paperlab.weekly_reports enable row level security;
revoke all on paperlab.weekly_runtime,paperlab.weekly_reports from public,anon,authenticated,service_role;

create or replace function paperlab.weekly_due(p_at timestamptz)returns boolean language sql immutable set search_path=pg_catalog,pg_temp as $$
 select (p_at at time zone'Europe/Brussels')>=date_trunc('week',p_at at time zone'Europe/Brussels')+interval'4 days 23 hours 15 minutes'
 and(p_at at time zone'Europe/Brussels')<date_trunc('week',p_at at time zone'Europe/Brussels')+interval'6 days';
$$;
create or replace function paperlab.weekly_build(p_at timestamptz,p_preview boolean)returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare wk date:=date_trunc('week',p_at at time zone'Europe/Brussels')::date;k text:=case when p_preview then'preview'else'final'end;
 start_at timestamptz;finish_at timestamptz;s jsonb;previous jsonb;baseline_at timestamptz;delta jsonb;outdated jsonb;jobs jsonb;r jsonb;existing jsonb;market jsonb;
begin
 perform 1 from paperlab.weekly_runtime where singleton and enabled for update;
 if not found then return jsonb_build_object('status','paused');end if;
 if not p_preview and not paperlab.weekly_due(p_at)then return jsonb_build_object('status','not_due');end if;
 select report into existing from paperlab.weekly_reports where week=wk and kind=k;
 if existing is not null then return existing;end if;
 if pg_database_size(current_database())>=100000000 or(select coalesce(sum(pg_total_relation_size(x::regclass)),0)from unnest(array['paperlab.weekly_reports','paperlab.weekly_runtime'])x)>=5000000 then
  update paperlab.weekly_runtime set status='storage_guard'where singleton;return jsonb_build_object('status','storage_guard');end if;
 start_at:=wk::timestamp at time zone'Europe/Brussels';
 finish_at:=least(p_at,(wk::timestamp+interval'4 days 23 hours 15 minutes')at time zone'Europe/Brussels');
 -- Snapshots are measured when actually run, never backdated to the intended close.
 select jsonb_build_object('companies',(select count(*)from paperlab.company_coverage),
 'official_extracts',(select count(*)from paperlab.company_coverage where jsonb_typeof(record->'verified_financials')='object'),
 'dated_qualitative_reviews',(select count(distinct symbol)from paperlab.company_reviews where reviewed_at>=p_at-interval'7 days'and reviewed_at<=p_at),
 'reference_examples',(select count(*)from paperlab.learning_samples),
 'history_complete',(select count(*)from paperlab.history_forecasts where status='complete'),
 'candidate_complete',(select count(*)from paperlab.candidate_predictions where status=2),
 'daily_complete',(select count(*)from paperlab.daily_study_records where status='complete'),
 'database_bytes',pg_database_size(current_database()),
 'estimated_month_bytes',coalesce((select estimated_worker_egress_bytes from paperlab.free_usage where month=date_trunc('month',p_at at time zone'UTC')::date),0))into s;
 select report->'snapshot',created_at into previous,baseline_at from paperlab.weekly_reports where created_at<p_at and(kind='final'or kind='preview')order by(kind='final')desc,created_at desc limit 1;
 if previous is not null then select jsonb_object_agg(key,(value::text)::numeric-(previous->>key)::numeric)into delta from jsonb_each(s)where key not in('database_bytes','estimated_month_bytes');end if;
 select coalesce(jsonb_agg(x),'[]')into outdated from(
  select c->>'symbol'as symbol,v.checked_at as financial_checked_at,rev.reviewed_at as qualitative_reviewed_at,v.record->'primary'->>'url'as primary_url,
   case when v.symbol is null then'no_source_card'when v.record->>'secondary_status'='source_unavailable'then'source_unavailable'when v.checked_at<p_at-interval'8 days'then'financial_check_expired'when dossier.record->>'status'='financial_source_change_requires_review'then'financial_revision_requires_review'when rev.reviewed_at is null then'qualitative_review_missing'else'qualitative_review_expired'end as issue
  from paperlab.company_coverage_runtime rt cross join lateral jsonb_array_elements(rt.catalogue)c left join paperlab.company_coverage v on v.symbol=c->>'symbol'
  left join lateral(select max(reviewed_at)reviewed_at from paperlab.company_reviews where symbol=c->>'symbol'and reviewed_at<=p_at)rev on true
  left join lateral(select record from paperlab.company_dossiers where symbol=c->>'symbol'and known_at<=p_at order by known_at desc limit 1)dossier on true
  where v.symbol is null or v.record->>'secondary_status'='source_unavailable'or v.checked_at<p_at-interval'8 days'or dossier.record->>'status'='financial_source_change_requires_review'or rev.reviewed_at is null or rev.reviewed_at<p_at-interval'7 days'
  order by case when v.symbol is null or v.checked_at<p_at-interval'8 days'then 0 else 1 end,c->>'symbol'limit 12)x;
 select jsonb_agg(x)into jobs from(
  select'financial_sources'name,status,last_success,enabled from paperlab.company_coverage_runtime union all
  select'primary_financial_sources',status,last_success,enabled from paperlab.company_runtime union all
  select'historical_forward',status,last_success,enabled from paperlab.history_runtime union all
  select'candidate_models',status,last_success,enabled from paperlab.candidate_runtime union all
  select'daily_research',status,last_success,enabled from paperlab.daily_study_runtime union all
  select'iex_research',status,last_success,enabled from paperlab.iex_runtime
 )x;
 with ranked as(select symbol,day,close,row_number()over(partition by symbol order by day)rn,count(*)over(partition by symbol)n from paperlab.daily_study_bars where day>=wk and day<=(finish_at at time zone'Europe/Brussels')::date and observed_at<=p_at),
 moves as(select symbol,min(day)first_day,max(day)last_day,100*(max(close)filter(where rn=n)/max(close)filter(where rn=1)-1)change_percent from ranked where n>=2 group by symbol),
 extremes as((select *, 'rise'::text direction from moves order by change_percent desc,symbol limit 3)union all(select *, 'fall'::text direction from moves order by change_percent,symbol limit 3))
 select jsonb_build_object('source','daily_study_bars','scope','Gevolgde bedrijven met minstens twee opgeslagen bron-dagsluitingen deze week; lokale valuta, geen indexrendement of oorzakelijk bewijs.',
 'companies',(select count(*)from moves),'rising',(select count(*)from moves where change_percent>0),'falling',(select count(*)from moves where change_percent<0),
 'mean_local_change_percent',(select avg(change_percent)from moves),'extremes',(select coalesce(jsonb_agg(to_jsonb(e)),'[]')from extremes e))into market;
 r:=jsonb_build_object('version','weekly-reflection-v1','kind',k,'week',wk,'generated_at',p_at,'period_start',start_at,'period_end',finish_at,'market_observations',market,
 'snapshot_at',p_at,'baseline_at',baseline_at,'baseline_only',previous is null,'snapshot',s,'net_count_changes',delta,
 'activity',jsonb_build_object('source_revisions',(select count(*)from paperlab.company_coverage_events where at>=start_at and at<=finish_at),
 'closed_reference_examples',(select count(*)from paperlab.learning_samples where available_at>=start_at and available_at<=finish_at),
 'buys',(select count(*)from paperlab.capital_trades where time>=start_at and time<=finish_at and side='koop'),
 'sells',(select count(*)from paperlab.capital_trades where time>=start_at and time<=finish_at and side='verkoop'),
 'closed_trade_pnl_eur',(select sum(pnl)from paperlab.capital_trades where time>=start_at and time<=finish_at and side='verkoop'),
 'fees_eur',(select sum(fee)from paperlab.capital_trades where time>=start_at and time<=finish_at)),
 'account_snapshot',(select jsonb_build_object('last_success',last_success,'status',status,'liquidation_eur',summary->'liquidation_eur','cash_eur',summary->'cash_eur','positions',summary->'positions')from paperlab.capital_runtime),
 'learning',(select jsonb_build_object('status',training_status->>'status','last_check',last_train_check,'active_model',active_model_id)from paperlab.learning_runtime),
 'jobs',jobs,'review_queue_sample',outdated,'queue_is_sample',true,
 'evidence',jsonb_build_object('company_cards','company_coverage','qualitative_reviews','company_reviews','source_changes','company_coverage_events','closed_examples','learning_samples','paper_trades','capital_trades','models','learning_runtime/history_forecasts/candidate_predictions'),
 'assessment',jsonb_build_object('method','Deterministische controle van opgeslagen bronnen, nettoresultaten, tegenbewijs en ontbrekende validatie; geen nieuw gelezen boek of onafhankelijke marktvoorspelling.',
 'known','Bronkaart, officiële cijferextractie, kwalitatieve beoordeling en gevalideerd handelsmodel zijn verschillende bewijsniveaus.',
 'new_evidence','Alleen geregistreerde bronwijzigingen en afgesloten voorbeelden gelden hier als nieuwe waarnemingen; meerdere koersen zijn geen onafhankelijke leertrades.',
 'counterevidence','Transactiekosten, verliestrades, ontbrekende uitkomsten, bronfouten en verouderde reviews blijven zichtbaar. Winst uit enkele trades bewijst geen voorspellende waarde.',
 'irrelevance','Verlopen of gewijzigde bronnen moeten opnieuw worden beoordeeld. Oude bewijsstukken worden door deze controle niet aangepast; een ouder inzicht wordt niet automatisch vervangen door een nieuw feit.',
 'next_steps','Eerst bronfouten en verlopen reviews oplossen; daarna voldoende gespreide, afgesloten uitkomsten verzamelen en kandidaten op aparte tijdvakken toetsen.',
 'automatic_strategy_change',false,'consciousness',false,'paid_model_calls',0),
 'retention',jsonb_build_object('final_reports',104,'preview_reports',1,'max_report_bytes',24000,'storage_guard_bytes',100000000));
 insert into paperlab.weekly_reports values(wk,k,p_at,r);
 delete from paperlab.weekly_reports where(week,kind)in(select week,kind from paperlab.weekly_reports where kind='final'order by week desc offset 104);
 delete from paperlab.weekly_reports where(week,kind)in(select week,kind from paperlab.weekly_reports where kind='preview'order by week desc offset 1);
 update paperlab.weekly_runtime set last_success=p_at,status=case when p_preview then'preview_ready'else'reflected'end where singleton;
 return r;
end$$;
create or replace function public.paper_weekly_run(p_preview boolean default false)returns jsonb language sql security definer set search_path=pg_catalog,pg_temp as $$select paperlab.weekly_build(now(),p_preview)$$;
create or replace function public.paper_weekly_read(p_owner uuid)returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton)then raise exception'Owner required';end if;
 return jsonb_build_object('schedule','Vrijdag 23:15 Europe/Brussels; zaterdag hercontrole bij gemiste uitvoering.','runtime',(select to_jsonb(r)from paperlab.weekly_runtime r),
 'latest',(select report from paperlab.weekly_reports order by created_at desc limit 1),
 'history',(select coalesce(jsonb_agg(jsonb_build_object('week',week,'kind',kind,'created_at',created_at,'report',report)order by created_at desc),'[]')from(select *from paperlab.weekly_reports order by created_at desc limit 8)x));
end$$;
revoke all on function paperlab.weekly_due(timestamptz),paperlab.weekly_build(timestamptz,boolean),public.paper_weekly_run(boolean),public.paper_weekly_read(uuid)from public,anon,authenticated,service_role;
grant execute on function public.paper_weekly_read(uuid)to service_role;
-- Scheduled SQL and management only: no browser-triggered generation.
commit;
