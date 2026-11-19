"""Cold-archive transaction requires inactive, unleased, hash-verified source."""
import json,secrets,subprocess,hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];name='cold_'+secrets.token_hex(4);cmd=['docker','--host=unix:///var/run/docker.sock','exec','-i','paperlab-research-sql','psql','-U','postgres','-v','ON_ERROR_STOP=1','-At']
def q(sql,error=None,db=name):
 r=subprocess.run(cmd+['-d',db],input=sql.encode(),capture_output=True)
 if error:assert r.returncode and error in r.stderr.decode(),r.stderr.decode()
 elif r.returncode:raise RuntimeError(r.stderr.decode())
 return r.stdout.decode().strip().splitlines()[-1]if r.stdout.strip()else''
def js(x):return "'"+json.dumps(x).replace("'","''")+"'::jsonb"
q('create database '+name,db='postgres')
try:
 q("create schema paperlab;create schema storage;create table storage.objects(metadata jsonb);create table paperlab.deep_documents(id text primary key,symbol text,url text,sha256 text,body_sha256 text,body text,scope text,active boolean);create table paperlab.deep_jobs(doc_id text,status text);create table paperlab.archive_manifest(id text primary key,record jsonb);create table paperlab.free_usage(month date primary key,estimated_worker_egress_bytes bigint default 0);create table paperlab.storage_budget_runtime(singleton boolean,policy jsonb);insert into paperlab.storage_budget_runtime values(true,'{\"object_hard_bytes\":800000000}');create function paperlab.traffic_limit(text)returns bigint language sql as $$select 3200000000::bigint$$;")
 sql=(ROOT/'managed/sql/041_cold_source_archive.sql').read_text();q(sql);q(sql)
 text='Full original report — €123\n';sha=hashlib.sha256(text.encode()).hexdigest();doc='a'*64
 q("insert into paperlab.deep_documents values('"+doc+"','TEST','https://issuer.example/report.pdf','"+'b'*64+"','"+sha+"',"+js(text).replace('::jsonb','::jsonb #>> \'{}\'')+",'Complete',true,null,null)")
 assert q('select public.paper_cold_source_claim()')==''
 q("update paperlab.deep_documents set active=false;insert into paperlab.deep_jobs values('"+doc+"','leased')");assert q('select public.paper_cold_source_claim()')==''
 q('delete from paperlab.deep_jobs');claim=json.loads(q('select public.paper_cold_source_claim()'));assert claim['body']==text;assert q('select public.paper_cold_source_claim()')==''
 proof={'object_path':claim['object_path'],'bytes':1000,'sha256':'c'*64,'body_sha256':sha,'verified':False}
 q("select public.paper_cold_source_commit('"+claim['token']+"',"+js(proof)+')','Verified exact')
 assert q("select length(body)>0 from paperlab.deep_documents")=='t'
 proof['verified']=True;assert q("select public.paper_cold_source_commit('"+claim['token']+"',"+js(proof)+')')=='t'
 assert q("select body=''and archived_at is not null from paperlab.deep_documents")=='t';assert q('select count(*)from paperlab.archive_manifest')=='1';assert q('select count(*)from paperlab.deep_documents')=='1'
 for role in ['anon','authenticated']:q('set role '+role+';select public.paper_cold_source_claim()','permission denied')
 print('Cold archive SQL passed: active/leased source exclusion, private claims, exact hash proof before cache clearing, retained document identity and archive manifest.')
finally:q('drop database '+name+' with(force)',db='postgres')
