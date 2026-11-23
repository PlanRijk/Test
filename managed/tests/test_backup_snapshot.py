"""Local, network-isolated regression for a logical backup larger than the old 30 MB ceiling."""
import subprocess,secrets,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
base=['docker','--host=unix:///var/run/docker.sock','exec','-i','paperlab-research-sql','psql','-U','postgres','-v','ON_ERROR_STOP=1','-At'];name='backup_'+secrets.token_hex(3)
def q(s,db='postgres'):
 r=subprocess.run(base+['-d',db],input=s.encode(),capture_output=True);assert r.returncode==0,r.stderr.decode();return r.stdout.decode().strip()
q('create database '+name)
try:
 q("create schema paperlab;create table paperlab.synthetic(id int,data text,token text);insert into paperlab.synthetic select i,repeat('Evidence Ω and quote',1700),'PRIVATE-SYNTHETIC-TOKEN'from generate_series(1,1000)i;create table paperlab.deep_documents(id text,body text,active boolean);insert into paperlab.deep_documents values('test','ORIGINAL-SOURCE-BODY',true);create table paperlab.deep_jobs(status text,doc_id text);",name)
 sql=(ROOT/'managed/sql/043_audit_repairs.sql').read_text();fn=re.search(r'create or replace function paperlab.project_snapshot_text\(\).*?end\$\$;',sql,re.S).group(0);q(fn,name)
 d=q("select json_array_length((paperlab.project_snapshot_text()::json)->'synthetic')",name);assert d=='1000'
 assert int(q('select octet_length(paperlab.project_snapshot_text())',name))>30000000
 assert q("select ((paperlab.project_snapshot_text()::json)->'deep_documents'->0->>'body')=''",name)=='t'
 assert q("select strpos(paperlab.project_snapshot_text(),'PRIVATE-SYNTHETIC-TOKEN')=0",name)=='t'
 print('Large JSON snapshot passed: >30MB, exact Unicode rows, omitted source-body cache and secret tokens.')
finally:q('drop database '+name+' with(force)')
