"""Isolated capacity overlay: exact guards, roles, custom caps and unchanged usage."""
import json,secrets,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];name='storage_'+secrets.token_hex(4)
cmd=['docker','--host=unix:///var/run/docker.sock','exec','-i','paperlab-research-sql','psql','-U','postgres','-v','ON_ERROR_STOP=1','-At']
def q(sql,error=None,db=name):
 r=subprocess.run(cmd+['-d',db],input=sql.encode(),capture_output=True)
 if error:assert r.returncode and error in r.stderr.decode(),r.stderr.decode()
 elif r.returncode:raise RuntimeError(r.stderr.decode())
 return r.stdout.decode().strip().splitlines()[-1]if r.stdout.strip()else''
q('create database '+name,db='postgres')
try:
 owner='11111111-1111-4111-8111-111111111111'
 q("create schema paperlab;create schema storage;create table storage.objects(metadata jsonb);insert into storage.objects values('{\"size\":27000000}');create table paperlab.settings(owner_id uuid,singleton boolean);insert into paperlab.settings values('"+owner+"',true);create table paperlab.free_usage(month date primary key,estimated_worker_egress_bytes bigint default 0,max_database_bytes bigint default 300000000 check(max_database_bytes between 1 and 300000000));insert into paperlab.free_usage(month,estimated_worker_egress_bytes)values(date_trunc('month',now())::date,2500000000);insert into paperlab.free_usage(month,max_database_bytes)values(date_trunc('month',now())::date-1,80000000);create function public.paper_traffic_budget_read(uuid)returns jsonb language sql as $$select '{\"existing\":true}'::jsonb$$;create function public.paper_deep_claim()returns boolean language sql as $$select pg_database_size(current_database())>99000000$$;grant execute on function public.paper_deep_claim()to service_role;create function paperlab.deep_add_document(jsonb)returns boolean language sql as $$select pg_database_size(current_database())>97000000$$;")
 before=q("select jsonb_build_object('acl',proacl,'owner',proowner,'oid',oid)from pg_proc where oid='public.paper_deep_claim()'::regprocedure")
 sql=(ROOT/'managed/sql/040_storage_capacity.sql').read_text();q(sql);q(sql)
 assert before==q("select jsonb_build_object('acl',proacl,'owner',proowner,'oid',oid)from pg_proc where oid='public.paper_deep_claim()'::regprocedure")
 assert q("select estimated_worker_egress_bytes from paperlab.free_usage where month=date_trunc('month',now())::date")=='2500000000'
 assert q("select paperlab.storage_limit('hard')")=='450000000';assert q("select paperlab.storage_limit('soft')")=='400000000';assert q("select paperlab.storage_limit('warning')")=='350000000'
 assert q("select max_database_bytes from paperlab.free_usage where max_database_bytes=80000000")=='80000000'
 assert q('select public.paper_deep_claim()')=='f';assert q("select paperlab.deep_add_document('{}')")=='f'
 q("update paperlab.free_usage set max_database_bytes=1 where month=date_trunc('month',now())::date");q(sql);assert q('select public.paper_deep_claim()')=='t';assert q("select paperlab.deep_add_document('{}')")=='t'
 for role in ['anon','authenticated','service_role']:q('set role '+role+';select *from paperlab.storage_budget_runtime','permission denied')
 for role in ['anon','authenticated']:q("set role "+role+";select public.paper_storage_budget_read('"+owner+"')",'permission denied')
 q('select public.paper_storage_budget_read(null)','Owner required')
 read=json.loads(q("select public.paper_traffic_budget_read('"+owner+"')"));assert read['existing'];assert read['storage']['object_bytes']==27000000;assert read['storage']['database_status']=='hard_stop'
 q("update storage.objects set metadata='{\"size\":800000000}'");read=json.loads(q("select public.paper_storage_budget_read('"+owner+"')"));assert read['object_status']=='hard_stop'
 print('Storage capacity SQL passed: idempotent exact guard overlay, 350/400/450 MB limits, 1 GB separate Storage, private owner read, unchanged ACL/OID/counters, lower custom cap retained.')
finally:q('drop database '+name+' with(force)',db='postgres')
