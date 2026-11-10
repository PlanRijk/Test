begin;
-- The frozen historical engine checks exact stored source prices. float8 -> JSON
-- must round-trip even when the caller's extra_float_digits is zero. This changes
-- neither models, records, labels, source data nor the strict commit validation.
do $$begin
 if to_regprocedure('public.paper_history_claim_transport_v1()')is null then
  alter function public.paper_history_claim()rename to paper_history_claim_transport_v1;
 end if;
end$$;
create or replace function public.paper_history_claim()returns jsonb
language sql security definer set search_path=pg_catalog,pg_temp set extra_float_digits=3
as $$select public.paper_history_claim_transport_v1()$$;
revoke all on function public.paper_history_claim_transport_v1(),public.paper_history_claim()from public,anon,authenticated,service_role;
grant execute on function public.paper_history_claim()to service_role;
commit;
