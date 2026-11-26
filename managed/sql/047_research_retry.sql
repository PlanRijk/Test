-- Bounded application backoff for temporary HTTP 5xx errors. Provider waits,
-- daily/minute counters, financial profiles and research evidence are unchanged.
begin;
create or replace function paperlab.quarter_retry_time(p_result jsonb,p_attempts int,p_now timestamptz default now())returns timestamptz language plpgsql stable security definer set search_path=pg_catalog,pg_temp as $$declare seconds int;begin
 if p_result->>'status'='rate_limited'or p_result->>'quota_kind'in('day','minute')then return paperlab.gemini_retry_time(p_result);end if;
 if p_result->>'status'='provider_unavailable'and coalesce(p_result->>'provider_http_status','')in('500','502','503','504')then
  seconds:=greatest(least(900,(30*power(2,least(5,greatest(0,coalesce(p_attempts,1)-1))))::int),coalesce((p_result->>'retry_after_seconds')::int,0));
  return p_now+make_interval(secs=>seconds);
 end if;
 return p_now+case when p_attempts>=3 then interval'12 hours'else interval'15 minutes'end;
end$$;
revoke all on function paperlab.quarter_retry_time(jsonb,int,timestamptz)from public,anon,authenticated,service_role;
do $$declare s text;old text:=$old$delay:=case when p_result->>'status'='rate_limited'then paperlab.gemini_retry_time(p_result)else now()+case when j.attempts>=3 then interval'12 hours'else interval'15 minutes'end end;$old$;begin
 s:=pg_get_functiondef('public.paper_quarter_commit_workbench_base(uuid,jsonb)'::regprocedure);
 if strpos(s,'delay:=paperlab.quarter_retry_time(p_result,j.attempts);')=0 then
  if strpos(s,old)=0 then raise exception'Quarter retry definition differs; inspect before patching';end if;
  execute replace(s,old,'delay:=paperlab.quarter_retry_time(p_result,j.attempts);');
 end if;
end$$;
commit;
