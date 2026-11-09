begin;
create or replace function paperlab.iex_now()returns timestamptz language sql stable set search_path=pg_catalog,pg_temp as $$select now()$$;
revoke all on function paperlab.iex_now()from public,anon,authenticated,service_role;
create table if not exists paperlab.iex_runtime(
 singleton boolean primary key default true check(singleton),enabled boolean not null default false,policy jsonb,profile text,
 started_at timestamptz,run_until timestamptz,token uuid,lease_until timestamptz,last_attempt timestamptz,last_success timestamptz,
 status text not null default 'not_configured',latest jsonb not null default '{}'
);
insert into paperlab.iex_runtime(singleton)values(true)on conflict do nothing;
create table if not exists paperlab.iex_usage(month date primary key,attempts integer not null default 0,successes integer not null default 0,estimated_bytes bigint not null default 0 check(estimated_bytes>=0));
create table if not exists paperlab.iex_minutes(minute timestamptz primary key,sampled_at timestamptz not null,points jsonb not null check(octet_length(points::text)<=6000));
create table if not exists paperlab.iex_daily(day date not null,symbol text not null,bucket text not null check(bucket in('opening','middle','closing')),stats jsonb not null check(octet_length(stats::text)<=2500),primary key(day,symbol,bucket));
do $$declare n text;begin foreach n in array array['iex_runtime','iex_usage','iex_minutes','iex_daily']loop
 execute format('alter table paperlab.%I enable row level security',n);execute format('revoke all on paperlab.%I from public,anon,authenticated,service_role',n);end loop;end$$;
create or replace function paperlab.iex_merge(a jsonb,b jsonb) returns jsonb language sql immutable set search_path=pg_catalog,pg_temp as $$
 select jsonb_object_agg(k,case when right(k,4)='_max' then greatest(coalesce((a->>k)::float8,0),coalesce((b->>k)::float8,0)) else coalesce((a->>k)::float8,0)+coalesce((b->>k)::float8,0)end)from(select jsonb_object_keys(a||b)k)s;
$$;
revoke all on function paperlab.iex_merge(jsonb,jsonb)from public,anon,authenticated,service_role;
create or replace function public.paper_iex_configure(p_policy jsonb) returns text language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare r paperlab.iex_runtime;fp text;
begin
 select * into r from paperlab.iex_runtime where singleton for update;
 if not(p_policy @> '{"version":"iex-minute-research-v1","feed":"iex","cadence_seconds":60,"study_days":14,"raw_retention_hours":48,"max_raw_batches":800,"aggregate_retention_days":60,"max_storage_bytes":12000000,"max_database_bytes":105000000,"max_monthly_bytes":200000000,"shared_monthly_ceiling_bytes":1050000000,"reserved_bytes_per_attempt":50000,"max_attempts_per_day":400,"source_response_bytes":16000,"source_calls_per_round":2,"quote_age_seconds":60,"coarse_minutes":5,"move_thresholds_bps":[50,150],"orders":false,"automatic_training":false}'::jsonb)
 or coalesce(p_policy->>'implementation_sha256','')!~'^[a-f0-9]{64}$' or jsonb_array_length(p_policy->'symbols')<>53 or(select count(distinct s)from jsonb_array_elements_text(p_policy->'symbols')s)<>53 then raise exception 'Invalid IEX policy';end if;
 fp:=encode(sha256(convert_to(p_policy::text,'UTF8')),'hex');if r.profile is not null then if r.profile<>fp then raise exception 'IEX research policy frozen';end if;return fp;end if;
 update paperlab.iex_runtime set policy=p_policy,profile=fp,started_at=paperlab.iex_now(),run_until=paperlab.iex_now()+interval '14 days',enabled=true,status='waiting_session' where singleton;
 return fp;
end$$;
create or replace function public.paper_iex_claim()returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare r paperlab.iex_runtime;m date:=date_trunc('month',paperlab.iex_now()at time zone'UTC')::date;local_now timestamp:=paperlab.iex_now()at time zone'America/New_York';u paperlab.iex_usage;g paperlab.free_usage;own bigint;t uuid;
begin
 select * into r from paperlab.iex_runtime where singleton for update;
 if not r.enabled or r.profile is null or r.lease_until>paperlab.iex_now() or r.last_attempt>=date_trunc('minute',paperlab.iex_now())then return null;end if;
 if paperlab.iex_now()>=r.run_until then update paperlab.iex_runtime set status='study_ended'where singleton;return null;end if;
 if extract(isodow from local_now)>5 or local_now::time<time'09:30' or local_now::time>=time'16:00'then return null;end if;
 delete from paperlab.iex_minutes where minute<paperlab.iex_now()-interval'48 hours';
 delete from paperlab.iex_daily where day<local_now::date-60;
 delete from paperlab.iex_minutes where minute in(select minute from paperlab.iex_minutes order by minute desc offset 799);
 select sum(pg_total_relation_size(x::regclass))into own from unnest(array['paperlab.iex_minutes','paperlab.iex_daily','paperlab.iex_runtime','paperlab.iex_usage'])x;
 insert into paperlab.iex_usage(month)values(m)on conflict do nothing;select * into u from paperlab.iex_usage where month=m for update;
 select * into g from paperlab.free_usage where month=m for update;
 if own>=12000000 or pg_database_size(current_database())>=105000000 or u.estimated_bytes+50000>=200000000 or not found or g.estimated_worker_egress_bytes+50000>=least(g.max_worker_egress_bytes,1050000000)
 or(select count(*)from paperlab.iex_minutes where minute::date=(paperlab.iex_now()at time zone'UTC')::date)>=400 then update paperlab.iex_runtime set status='budget_paused'where singleton;return null;end if;
 -- Reserve before fetching, including failed attempts. Duplicate cron/manual calls cannot collect the same minute.
 update paperlab.iex_usage set attempts=attempts+1,estimated_bytes=estimated_bytes+50000 where month=m;
 update paperlab.free_usage set estimated_worker_egress_bytes=estimated_worker_egress_bytes+50000 where month=m;
 t:=gen_random_uuid();update paperlab.iex_runtime set token=t,lease_until=paperlab.iex_now()+interval'60 seconds',last_attempt=paperlab.iex_now(),status='collecting'where singleton;
 return jsonb_build_object('token',t,'implementation_sha256',r.policy->>'implementation_sha256');
end$$;
create or replace function public.paper_iex_commit(p_token uuid,p_output jsonb)returns boolean language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare r paperlab.iex_runtime;t timestamptz;minute_at timestamptz;local_now timestamp;d date;buck text;points jsonb;q jsonb;oldq jsonb;coarse paperlab.iex_minutes;idx integer:=0;sym text;
 qt float8;bid float8;ask float8;tt float8;tp float8;age float8;ta float8;mid float8;spread float8;oldtime float8;oldbid float8;oldask float8;gap float8;good boolean;fresh boolean;tf boolean;paired boolean;
 stats jsonb;fresh_count integer:=0;valid_count integer:=0;trade_count integer:=0;spread_sum float8:=0;spread_count integer:=0;comparison_count integer:=0;m date;charge bigint;refund bigint;
begin
 select * into r from paperlab.iex_runtime where singleton and enabled and token=p_token and lease_until>paperlab.iex_now() for update;if not found then return false;end if;
 if p_output->>'version'<>'iex-minute-research-v1' or jsonb_typeof(p_output->'points')<>'array' or jsonb_array_length(p_output->'points')<>53 or octet_length(p_output::text)>6000
 or coalesce((p_output->>'source_bytes')::bigint,-1)not between 0 and 32000 or(p_output->>'source_calls')::integer is distinct from 2 then raise exception 'Invalid IEX batch';end if;
 t:=(p_output->>'checked_at')::timestamptz;if t is null or t<r.last_attempt or t>paperlab.iex_now()+interval'5 seconds' or t>r.last_attempt+interval'45 seconds'then raise exception 'Invalid IEX observation time';end if;
 minute_at:=date_trunc('minute',r.last_attempt);local_now:=r.last_attempt at time zone'America/New_York';d:=local_now::date;
 buck:=case when local_now::time<time'10:00'then'opening'when local_now::time>=time'15:30'then'closing'else'middle'end;
 if extract(minute from minute_at)::integer%5<>0 then select * into coarse from paperlab.iex_minutes where minute=date_trunc('hour',minute_at)+make_interval(mins=>(extract(minute from minute_at)::integer/5)*5);end if;
 points:=p_output->'points';
 for q in select value from jsonb_array_elements(points)loop
  if jsonb_typeof(q)<>'array'or jsonb_array_length(q)<>5 or exists(select 1 from jsonb_array_elements(q)v where jsonb_typeof(v)not in('number','null'))then raise exception 'Invalid IEX point';end if;
  sym:=r.policy->'symbols'->>idx;qt:=(q->>0)::float8;bid:=(q->>1)::float8;ask:=(q->>2)::float8;tt:=(q->>3)::float8;tp:=(q->>4)::float8;
  if(qt is not null and(qt<946684800000 or qt>=4102444800000))or(tt is not null and(tt<946684800000 or tt>=4102444800000))or exists(select 1 from jsonb_array_elements(q)v where jsonb_typeof(v)='number'and abs(v::text::float8)>=1e15)then raise exception 'IEX number outside limits';end if;
  if(bid is not null and(bid<0 or bid>=1e9))or(ask is not null and(ask<0 or ask>=1e9))or(tp is not null and(tp<0 or tp>=1e9))then raise exception 'IEX price outside limits';end if;
  age:=extract(epoch from t)-qt/1000;ta:=extract(epoch from t)-tt/1000;
  good:=coalesce(qt is not null and bid>=.000001 and ask>=bid,false);fresh:=good and age between 0 and 60;tf:=coalesce(tp>0 and ta between 0 and 60,false);
  mid:=case when good then(bid+ask)/2 end;spread:=case when fresh then(ask-bid)/mid*10000 end;gap:=null;paired:=false;
  oldq:=coarse.points->idx;oldtime:=(oldq->>0)::float8;oldbid:=(oldq->>1)::float8;oldask:=(oldq->>2)::float8;
  if fresh and oldtime is not null and oldbid>=.000001 and oldask>=oldbid and extract(epoch from coarse.sampled_at)-oldtime/1000 between 0 and 60 and qt>=oldtime
   and(qt<>oldtime or(bid=oldbid and ask=oldask))then gap:=(mid/((oldbid+oldask)/2)-1)*10000;paired:=true;end if;
  stats:=jsonb_build_object('samples',1,'valid',good::int,'fresh60',fresh::int,'fresh120',(good and age between 0 and 120)::int,'trade_fresh60',tf::int,
   'spread_n',fresh::int,'spread_sum',coalesce(spread,0),'spread_max',coalesce(spread,0),'age_n',case when age>=0 then 1 else 0 end,'age_sum',case when age>=0 then age else 0 end,'age_max',case when age>=0 then age else 0 end,
   'coarse_n',paired::int,'coarse_abs_sum',coalesce(abs(gap),0),'coarse_abs_max',coalesce(abs(gap),0),'move50',coalesce(abs(gap)>=50,false)::int,'move150',coalesce(abs(gap)>=150,false)::int);
  insert into paperlab.iex_daily values(d,sym,buck,stats)on conflict(day,symbol,bucket)do update set stats=paperlab.iex_merge(paperlab.iex_daily.stats,excluded.stats);
  valid_count:=valid_count+good::int;fresh_count:=fresh_count+fresh::int;trade_count:=trade_count+tf::int;spread_sum:=spread_sum+coalesce(spread,0);spread_count:=spread_count+fresh::int;comparison_count:=comparison_count+paired::int;idx:=idx+1;
 end loop;
 insert into paperlab.iex_minutes values(minute_at,t,points);
 m:=date_trunc('month',r.last_attempt at time zone'UTC')::date;charge:=least(50000,(p_output->>'source_bytes')::bigint+2*octet_length(p_output::text)+4096);refund:=50000-charge;
 update paperlab.iex_usage set successes=successes+1,estimated_bytes=greatest(0,estimated_bytes-refund)where month=m;
 update paperlab.free_usage set estimated_worker_egress_bytes=greatest(0,estimated_worker_egress_bytes-refund)where month=m;
 update paperlab.iex_runtime set token=null,lease_until=null,last_success=paperlab.iex_now(),status='observing',latest=jsonb_build_object('checked_at',t,'expected',53,'valid_quotes',valid_count,'fresh60',fresh_count,'trade_fresh60',trade_count,'mean_spread_bps',spread_sum/nullif(spread_count,0),'coarse_comparisons',comparison_count,'duration_ms',p_output->'duration_ms','estimated_bytes',charge)where singleton;
 return true;
end$$;
create or replace function public.paper_iex_fail(p_token uuid)returns void language sql security definer set search_path=pg_catalog,pg_temp as $$
 update paperlab.iex_runtime set token=null,lease_until=null,status='source_or_processing_error'where singleton and token=p_token;
$$;
create or replace function public.paper_iex_read(p_owner uuid)returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton)then raise exception 'Owner required';end if;
 return jsonb_build_object('runtime',(select to_jsonb(r)-'token'-'lease_until'from paperlab.iex_runtime r),'usage',(select to_jsonb(u)from paperlab.iex_usage u where month=date_trunc('month',paperlab.iex_now()at time zone'UTC')::date),
 'storage_bytes',(select sum(pg_total_relation_size(x::regclass))from unnest(array['paperlab.iex_minutes','paperlab.iex_daily','paperlab.iex_runtime','paperlab.iex_usage'])x),
 'raw_batches',(select count(*)from paperlab.iex_minutes),'retained_days',(select count(distinct day)from paperlab.iex_daily),
 'companies',(select coalesce(jsonb_agg(to_jsonb(x)order by symbol),'[]'::jsonb)from(select symbol,sum((stats->>'samples')::int)as samples,sum((stats->>'fresh60')::int)as fresh60,sum((stats->>'trade_fresh60')::int)as trade_fresh60,
  sum((stats->>'spread_sum')::float8)/nullif(sum((stats->>'spread_n')::int),0)as mean_spread_bps,max((stats->>'spread_max')::float8)as max_spread_bps,max((stats->>'age_max')::float8)as max_quote_age_seconds,
  sum((stats->>'coarse_n')::int)as coarse_comparisons,sum((stats->>'coarse_abs_sum')::float8)/nullif(sum((stats->>'coarse_n')::int),0)as mean_abs_coarse_gap_bps,max((stats->>'coarse_abs_max')::float8)as max_abs_coarse_gap_bps,sum((stats->>'move50')::int)as moves_50bps,sum((stats->>'move150')::int)as moves_150bps
  from paperlab.iex_daily where day=(paperlab.iex_now()at time zone'America/New_York')::date group by symbol)x),
 'buckets',(select coalesce(jsonb_agg(to_jsonb(x)order by bucket),'[]'::jsonb)from(select bucket,sum((stats->>'samples')::int)as samples,sum((stats->>'fresh60')::int)as fresh60,sum((stats->>'spread_sum')::float8)/nullif(sum((stats->>'spread_n')::int),0)as mean_spread_bps from paperlab.iex_daily where day=(paperlab.iex_now()at time zone'America/New_York')::date group by bucket)x));
end$$;
create or replace function public.paper_iex_action(p_owner uuid,p_action text)returns boolean language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton)then raise exception 'Owner required';end if;
 if p_action not in('pause','resume')then raise exception 'Invalid IEX action';end if;
 update paperlab.iex_runtime set enabled=p_action='resume',token=null,lease_until=null,status=case when p_action='pause'then'owner_paused'else'waiting_session'end where singleton;return true;
end$$;
do $$declare n text;begin for n in select p.oid::regprocedure::text from pg_proc p join pg_namespace s on s.oid=p.pronamespace where s.nspname='public'and p.proname like'paper_iex_%'loop
 execute'revoke all on function '||n||' from public,anon,authenticated';execute'grant execute on function '||n||' to service_role';end loop;end$$;
commit;
