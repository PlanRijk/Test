begin;
create table if not exists paperlab.iex_focus_reviews(id text primary key,created_at timestamptz not null default now(),report jsonb not null check(octet_length(report::text)<=24000));
alter table paperlab.iex_focus_reviews enable row level security;
revoke all on paperlab.iex_focus_reviews from public,anon,authenticated,service_role;
create or replace function public.paper_iex_focus_save(p_report jsonb)returns text language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare id_value text;
begin
 if not(p_report @>'{"version":"iex-focus-v1","orders":false,"training":false,"causal_or_profitability_evidence":false}'::jsonb)or jsonb_array_length(p_report->'companies')<>6 or(p_report->>'samples')::int not between 1 and 18 or octet_length(p_report::text)>24000 then raise exception'Invalid IEX focus review';end if;
 id_value:='if-'||substr(encode(sha256(convert_to(p_report::text,'UTF8')),'hex'),1,24);
 insert into paperlab.iex_focus_reviews values(id_value,now(),p_report)on conflict do nothing;
 delete from paperlab.iex_focus_reviews where id in(select id from paperlab.iex_focus_reviews order by created_at desc,id desc offset 10);
 return id_value;
end$$;
create or replace function public.paper_iex_focus_read(p_owner uuid)returns jsonb language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare result jsonb;watch jsonb;
begin
 if p_owner is distinct from(select owner_id from paperlab.settings where singleton)then raise exception'Owner required';end if;
 select report into result from paperlab.iex_focus_reviews order by created_at desc,id desc limit 1;
 select coalesce(jsonb_agg(jsonb_build_object('symbol',s.symbol,'sampled_at',s.sampled_at,'quote_time',to_timestamp((s.point->>0)::float8/1000),'bid',s.point->1,'ask',s.point->2,
  'quote_age_seconds',extract(epoch from paperlab.iex_now())-(s.point->>0)::float8/1000,
  'spread_bps',case when(s.point->>1)::float8>0 and(s.point->>2)::float8>=(s.point->>1)::float8 then((s.point->>2)::float8-(s.point->>1)::float8)/(((s.point->>1)::float8+(s.point->>2)::float8)/2)*10000 end,
  'fresh60',coalesce(extract(epoch from paperlab.iex_now())-(s.point->>0)::float8/1000 between 0 and 60 and(s.point->>1)::float8>0 and(s.point->>2)::float8>=(s.point->>1)::float8,false))order by array_position(array['TM','ICE','AMT','CME','AAPL','MSFT'],s.symbol)),'[]')into watch
 from(select r.policy->'symbols'->>(p.i::int-1)as symbol,m.sampled_at,p.point from(select *from paperlab.iex_minutes order by minute desc limit 1)m cross join paperlab.iex_runtime r cross join lateral jsonb_array_elements(m.points)with ordinality p(point,i)where r.singleton)s where s.symbol in('TM','ICE','AMT','CME','AAPL','MSFT');
 return(coalesce(result,'{}'::jsonb)-'evidence'-'cost_config_snapshot')||jsonb_build_object('live_watch',watch,'watch_as_of',paperlab.iex_now());
end$$;
revoke all on function public.paper_iex_focus_save(jsonb),public.paper_iex_focus_read(uuid)from public,anon,authenticated;
grant execute on function public.paper_iex_focus_save(jsonb),public.paper_iex_focus_read(uuid)to service_role;
commit;
