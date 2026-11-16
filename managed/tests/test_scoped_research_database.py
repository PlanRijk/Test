"""Isolated storage, owner isolation, source references, priority and non-approval checks."""
import json,secrets,subprocess,datetime,copy
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];name='scoped_'+secrets.token_hex(4)
cmd=['docker','--host=unix:///var/run/docker.sock','exec','-i','paperlab-research-sql','psql','-U','postgres','-v','ON_ERROR_STOP=1','-At']
def q(sql,error=None,db=name):
 r=subprocess.run(cmd+['-d',db],input=sql.encode(),capture_output=True)
 if error:assert r.returncode and error in r.stderr.decode(),r.stderr.decode()
 elif r.returncode:raise RuntimeError(r.stderr.decode())
 return r.stdout.decode().strip().splitlines()[-1]if r.stdout.strip()else''
def j(x):return "'"+json.dumps(x).replace("'","''")+"'::jsonb"
q('create database '+name,db='postgres')
try:
 owner='11111111-1111-4111-8111-111111111111';now=datetime.datetime.now(datetime.timezone.utc)
 q("create schema paperlab;create table paperlab.settings(owner_id uuid,singleton boolean);insert into paperlab.settings values('"+owner+"',true);create table paperlab.company_research(symbol text primary key);insert into paperlab.company_research values('TEST');create table paperlab.research_queue(symbol text,priority int,due_at timestamptz,reasons jsonb);insert into paperlab.research_queue values('TEST',40,now(),'[]');create table paperlab.publication_watch(symbol text,checked_at timestamptz,record jsonb);create table paperlab.earnings_cycles(symbol text,release_at timestamptz,status text);insert into paperlab.earnings_cycles values('TEST',now()+interval'2 days','confirmed');create function public.paper_project_read(uuid,text default null)returns jsonb language sql as $$select '{\"existing\":true}'::jsonb$$;create function public.paper_project_refresh()returns void language sql as $$update paperlab.research_queue set priority=40,reasons='[]'$$;")
 migration=(ROOT/'managed/sql/036_scoped_research.sql').read_text();q(migration);q(migration)
 src={'id':'s','url':'https://example.com/report','sha256':'a'*64,'known_at':now.isoformat()}
 sec={'title':'Risk','finding':'A sourced finding about this company and its operating results.','interpretation':'An interpretation with a clear distinction between facts and assumptions.','counterargument':'A relevant alternative explanation.','source_ids':['s']}
 record={'symbol':'TEST','scope':'earnings_preview','conclusion':'A completed scoped assessment is not a complete company analysis or a trading approval.','next_review_at':(now+datetime.timedelta(days=1)).isoformat(),'sources':[src],'sections':[sec]*5,'limitations':['Incomplete valuation'],'trade_approval':False,'full_company_analysis':False}
 save=lambda r:"select public.paper_scoped_research_save('"+owner+"',"+j(r)+')'
 first=q(save(record));assert first==q(save(record));assert q('select count(*)from paperlab.scoped_research')=='1'
 bad=copy.deepcopy(record);bad['trade_approval']=True;q(save(bad),'Complete bounded')
 bad=copy.deepcopy(record);bad['sections'][0]['source_ids']=['unknown'];q(save(bad),'Sourced findings')
 bad=copy.deepcopy(record);bad['sources'][0]['known_at']=(now+datetime.timedelta(days=2)).isoformat();q(save(bad),'Observed source')
 for role in ['anon','authenticated','service_role']:q('set role '+role+';select *from paperlab.scoped_research','permission denied')
 q('select public.paper_project_read(null)','Owner required');q("select public.paper_scoped_research_save(null,"+j(record)+')','Owner required')
 q('select public.paper_project_refresh()');assert q('select priority from paperlab.research_queue')=='340';q('select public.paper_project_refresh()');assert q('select priority from paperlab.research_queue')=='340'
 r=json.loads(q("select public.paper_project_read('"+owner+"')"));assert r['existing'];assert not r['scoped_research']['reviews'][0]['review_due'];assert not r['scoped_research']['reviews'][0]['record']['trade_approval']
 q("insert into paperlab.publication_watch values('TEST',now(),'{\"changed\":true}')");r=json.loads(q("select public.paper_project_read('"+owner+"','TEST')"));assert r['scoped_research']['reviews'][0]['source_changed'];q("update paperlab.scoped_research set next_review_at=now()-interval'1 day'");r=json.loads(q("select public.paper_project_read('"+owner+"','TEST')"));assert r['scoped_research']['reviews'][0]['review_due'];assert json.loads(q("select public.paper_project_read('"+owner+"','OTHER')"))['scoped_research']['reviews']==[]
 print('Scoped research SQL passed: idempotent migration, immutable record IDs, source integrity, owner isolation, stale reviews, symbol isolation and non-accumulating earnings priority.')
finally:q('drop database '+name+' with(force)',db='postgres')
