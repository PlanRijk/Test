"""Network-disabled SQL integration for persistent automatic quarterly baselines."""
import json,secrets,subprocess,datetime,copy
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];name='quarterly_'+secrets.token_hex(4)
cmd=['docker','--host=unix:///var/run/docker.sock','exec','-i','paperlab-research-sql','psql','-U','postgres','-v','ON_ERROR_STOP=1','-At']
def q(sql,error=None,db=name):
 r=subprocess.run(cmd+['-d',db],input=sql.encode(),capture_output=True)
 if error:assert r.returncode and error in r.stderr.decode(),r.stderr.decode()
 elif r.returncode:raise RuntimeError(r.stderr.decode())
 return r.stdout.decode().strip().splitlines()[-1]if r.stdout.strip()else''
def j(x):return "'"+json.dumps(x).replace("'","''")+"'::jsonb"
q('create database '+name,db='postgres')
try:
 now=datetime.datetime.now(datetime.timezone.utc).isoformat();owner='11111111-1111-4111-8111-111111111111'
 q("create schema paperlab;create table paperlab.settings(singleton boolean,owner_id uuid);insert into paperlab.settings values(true,'"+owner+"');create table paperlab.company_coverage_runtime(catalogue jsonb);create table paperlab.company_coverage(symbol text,record jsonb);create table paperlab.company_research(symbol text,record jsonb);create table paperlab.publication_watch(symbol text,status text,checked_at timestamptz,record jsonb);create table paperlab.portfolio(state jsonb);create table paperlab.earnings_cycles(id text primary key,symbol text,release_at timestamptz);create table paperlab.free_usage(month date primary key,estimated_worker_egress_bytes bigint default 0);create function paperlab.traffic_limit(text)returns bigint language sql as $$select 3200000000::bigint$$;create function public.paper_project_read(uuid,text default null)returns jsonb language sql as $$select '{\"existing\":true}'::jsonb$$;")
 catalogue=[{'symbol':'T'+str(i),'name':'Company '+str(i),'primary_url':'https://issuer.example/'+str(i)}for i in range(25)];q('insert into paperlab.company_coverage_runtime values('+j(catalogue)+')');q('insert into paperlab.portfolio values('+j({'last_observation':{x['symbol']:{'time':now}for x in catalogue}})+')')
 for x in catalogue:q('insert into paperlab.company_research values(\''+x['symbol']+'\','+j({'sources':[{'url':x['primary_url']}]})+');insert into paperlab.publication_watch values(\''+x['symbol']+'\',\'observed\',now(),null)')
 migration=(ROOT/'managed/sql/034_quarterly_expectations.sql').read_text();q(migration);q(migration)
 inputs=json.loads(q('select paperlab.quarterly_inputs()'));assert len(inputs)==25;assert all(x['official_source_available']for x in inputs)
 q("insert into paperlab.earnings_cycles values('event','T0',now()+interval'3 days')")
 claim=json.loads(q('select public.paper_quarterly_claim()'));assert len(claim['targets'])==20;assert claim['targets'][0]['symbol']=='T0';assert q('select public.paper_quarterly_claim()')==''
 rows=[{'version':'quarterly-baseline-v1','symbol':t['symbol'],'checked_at':now,'trade_approval':False,'stock_direction':'not_predicted','analyst_consensus':{'status':'not_connected'},'qualitative_review':{'status':'not_automated'},'official_source_available':t['official_source_available'],'quote_at':t['quote_at'],'eligible':True,'status':'baseline_available','input_known_at':now,'input_fingerprint':'a'*64,'financial_source_hash':'b'*64,'metrics':{'revenue':{'status':'baseline','currency':'EUR','low':80,'base':100,'high':120}}}for t in claim['targets']]
 commit=lambda obj:"select public.paper_quarterly_commit('"+claim['token']+"',"+j(obj)+')'
 bad=copy.deepcopy(rows);bad[0]['trade_approval']=True;q(commit(bad),'Untrusted baseline output')
 bad=copy.deepcopy(rows);bad[0]['official_source_available']=False;q(commit(bad),'Untrusted baseline output')
 bad=copy.deepcopy(rows);bad[0]['metrics']['revenue']['base']=1000;q(commit(bad),'Invalid numerical baseline range')
 bad=copy.deepcopy(rows);bad[0].pop('input_known_at');q(commit(bad),'Baseline requires')
 bad=copy.deepcopy(rows);bad[0]['input_fingerprint']='bad';q(commit(bad),'Baseline requires')
 assert q(commit(rows))=='t';assert q(commit(rows))=='f';assert q('select count(*)from paperlab.quarterly_event_baselines')=='1'
 for role in ['anon','authenticated','service_role']:q('set role '+role+';select *from paperlab.quarterly_expectations','permission denied')
 q('select public.paper_quarterly_read(null)','Owner required')
 report=json.loads(q("select public.paper_project_read('"+owner+"')"));assert report['existing'];assert report['quarterly_expectations']['counts']['with_baseline']==20
 # A refreshed mechanical estimate cannot overwrite a pre-event snapshot.
 original=q('select record from paperlab.quarterly_event_baselines');q("update paperlab.quarterly_runtime set last_attempt=null;update paperlab.quarterly_expectations set next_check=now()-interval'1 day'")
 c2=json.loads(q('select public.paper_quarterly_claim()'));assert c2;assert q('select record from paperlab.quarterly_event_baselines')==original
 print('Quarterly SQL passed: all-catalogue enrollment, quote/source gates, bounded recurring leases, private owner read, immutable pre-event snapshots, isolated research state and preserved existing API.')
finally:q('drop database '+name+' with(force)',db='postgres')
