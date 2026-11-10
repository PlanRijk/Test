-- Canonical storage only: JSON null is not an official source reference.
-- Source policy, transport and financial decisions remain unchanged.
begin;
create or replace function paperlab.source_reference_canonical()returns trigger language plpgsql set search_path=pg_catalog,pg_temp as $$begin
 new.reference:=nullif(new.reference,'null'::jsonb);
 if new.reference is not null and jsonb_typeof(new.reference)<>'object'then raise exception'Official source reference must be an object';end if;
 return new;
end$$;
revoke all on function paperlab.source_reference_canonical()from public,anon,authenticated,service_role;
drop trigger if exists source_reference_canonical on paperlab.source_reliability;
create trigger source_reference_canonical before insert or update on paperlab.source_reliability for each row execute function paperlab.source_reference_canonical();
update paperlab.source_reliability set reference=null where reference='null'::jsonb;
commit;
