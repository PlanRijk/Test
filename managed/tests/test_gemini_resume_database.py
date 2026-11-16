"""Isolated free-tier lease, budget, source proof and non-approval integration."""
import json,secrets,subprocess,datetime,copy
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];name='resume_'+secrets.token_hex(4)
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
 q("create schema paperlab;create table paperlab.settings(owner_id uuid,singleton boolean);insert into paperlab.settings values('"+owner+"',true);create table paperlab.company_research(symbol text primary key,record jsonb);insert into paperlab.company_research values('TEST','{\"sources\":[]}'),('OTHER','{\"sources\":[]}'),('THIRD','{\"sources\":[]}'),('FOURTH','{\"sources\":[]}');create table paperlab.research_queue(symbol text,priority int);insert into paperlab.research_queue values('TEST',340),('OTHER',40);create table paperlab.earnings_cycles(symbol text,release_at timestamptz,call_at timestamptz,status text,created_at timestamptz);create table paperlab.scoped_research(symbol text,recorded_at timestamptz,record jsonb);create table paperlab.analyst_consensus(symbol text,record jsonb);create table paperlab.free_usage(month date primary key,estimated_worker_egress_bytes bigint default 0);create function paperlab.traffic_limit(text)returns bigint language sql as $$select 3200000000::bigint$$;create function public.paper_project_read(uuid,text default null)returns jsonb language sql as $$select '{\"existing\":true}'::jsonb$$;")
 q((ROOT/'managed/sql/037_gemini_research.sql').read_text());sql=(ROOT/'managed/sql/038_gemini_resume.sql').read_text();q(sql);q(sql)
 q("select public.paper_gemini_enable('"+owner+"',true)");q('update paperlab.gemini_runtime set bootstrap_day=null')
 first=json.loads(q('select public.paper_gemini_claim()'));assert first['target']['symbol']=='TEST'
 src={'id':'s1','url':'https://example.com/report','sha256':'a'*64,'known_at':now.isoformat(),'text':'Reported revenue was 100 million USD and cash flow was 80 million USD. '+('More official reported financial context. '*4)}
 claims=[{'topic':'cash_earnings','finding':'A supported source finding about cash and earnings.','source_id':'s1','quote':'Reported revenue was 100 million USD'}]*3
 pending={'version':'gemini-pending-v1','symbol':'TEST','model':'gemini-3.5-flash-lite','draft':{'claims':claims},'sources':[src],'input_fingerprint':'a'*64}
 assert q("select public.paper_gemini_stage('"+first['token']+"',"+j(pending)+')')=='t'
 review=json.loads(q('select public.paper_gemini_claim()'));assert review['phase']=='review';assert q('select count(*)from paperlab.gemini_pending')=='1'
 failure={'version':'gemini-research-v1','symbol':'TEST','model':'gemini-3.5-flash-lite','checked_at':now.isoformat(),'status':'rate_limited','trade_approval':False,'qualitative_approval':False,'independently_verified':False,'attempted_calls':1,'quota_kind':'day','retry_after_seconds':5}
 assert q("select public.paper_gemini_commit('"+review['token']+"',"+j(failure)+')')=='t'
 assert json.loads(q("select record from paperlab.gemini_pending where symbol='TEST'"))==pending
 assert q("select retry_after=(((now()at time zone'America/Los_Angeles')::date+1)+time'00:01')at time zone'America/Los_Angeles'from paperlab.gemini_runtime")=='t'
 assert q('select public.paper_gemini_claim()')=='';assert q('select daily_reserved from paperlab.gemini_runtime')=='2'
 # Simulate the next provider day and a finished cooldown without sleeping.
 q("update paperlab.gemini_runtime set day=(now()at time zone'America/Los_Angeles')::date-1,retry_after=null;update paperlab.gemini_pending set retry_after=now()-interval'1 second'")
 resumed=json.loads(q('select public.paper_gemini_claim()'));assert resumed['phase']=='review';assert resumed['pending']==pending;assert q('select daily_reserved from paperlab.gemini_runtime')=='1';assert q('select monthly_reserved from paperlab.gemini_runtime')=='3'
 result={**failure,'status':'draft_checked','claims':claims,'sources':[src],'input_fingerprint':'a'*64,'exact_quotes_checked':True,'second_pass_completed':True}
 assert q("select public.paper_gemini_commit('"+resumed['token']+"',"+j(result)+')')=='t';assert q('select count(*)from paperlab.gemini_pending')=='0'
 # An unchanged known source refresh must not consume another model request.
 q("update paperlab.gemini_research set next_check=case when symbol='TEST'then now()else now()+interval'2 days'end")
 same=json.loads(q('select public.paper_gemini_claim()'));assert same['target']['symbol']=='TEST';assert q('select daily_reserved from paperlab.gemini_runtime')=='3'
 assert q("select public.paper_gemini_source_check('"+same['token']+"','"+'a'*64+"')")=='t';assert q('select daily_reserved from paperlab.gemini_runtime')=='1'
 assert q("select record->>'status'from paperlab.gemini_research where symbol='TEST'")=='source_unchanged'
 assert q("select last_success->>'status'from paperlab.gemini_research where symbol='TEST'")=='draft_checked'
 data=json.loads(q("select public.paper_project_read('"+owner+"')"));assert data['existing'];assert not next(x for x in data['gemini_research']['records']if x['symbol']=='TEST')['stale']
 seconds=float(q("select extract(epoch from(paperlab.gemini_retry_time('{\"status\":\"rate_limited\",\"quota_kind\":\"minute\",\"retry_after_seconds\":75}')-now()))"));assert seconds==75
 for role in ['anon','authenticated','service_role']:q('set role '+role+';select *from paperlab.gemini_pending','permission denied')
 q('select public.paper_gemini_read(null)','Owner required')
 print('Resume SQL passed: first draft survives quota failure, provider-midnight cooldown, review-only resume, reserved retry, preserved successful review, unchanged-source skip and owner isolation.')
finally:q('drop database '+name+' with(force)',db='postgres')
