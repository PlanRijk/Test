"""Isolated free-tier lease, budget, source proof and non-approval integration."""
import json,secrets,subprocess,datetime,copy
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];name='gemini_'+secrets.token_hex(4)
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
 sql=(ROOT/'managed/sql/037_gemini_research.sql').read_text();q(sql);q(sql);assert q('select public.paper_gemini_claim()')==''
 q('select public.paper_gemini_enable(null,true)','Owner required');q("select public.paper_gemini_enable('"+owner+"',false)",'Unbilled free tier')
 q("select public.paper_gemini_enable('"+owner+"',true)");q('update paperlab.gemini_runtime set bootstrap_day=null');c=json.loads(q('select public.paper_gemini_claim()'));assert c['target']['symbol']=='TEST';assert q('select public.paper_gemini_claim()')==''
 source={'id':'s1','url':'https://example.com/report','sha256':'a'*64,'known_at':now.isoformat(),'text':'Reported revenue was 100 million USD and cash flow was 80 million USD. '+('More official reported financial context. '*4)}
 record={'version':'gemini-research-v1','symbol':'TEST','checked_at':now.isoformat(),'model':'gemini-3.5-flash-lite','status':'draft_checked','trade_approval':False,'qualitative_approval':False,'independently_verified':False,'exact_quotes_checked':True,'second_pass_completed':True,'claims':[{'topic':'cash_earnings','finding':'A supported source finding about cash and earnings.','source_id':'s1','quote':'Reported revenue was 100 million USD'}]*3,'sources':[source]}
 pending={'version':'gemini-pending-v1','symbol':'TEST','model':'gemini-3.5-flash-lite','draft':{'claims':record['claims']},'sources':[source]}
 stage_sql="select public.paper_gemini_stage('"+c['token']+"',"+j(pending)+')';assert q(stage_sql)=='t';assert q(stage_sql)=='f'
 assert q('select count(*)from paperlab.gemini_pending')=='1'
 c=json.loads(q('select public.paper_gemini_claim()'));assert c['phase']=='review';assert c['pending']['symbol']=='TEST';assert q('select daily_reserved from paperlab.gemini_runtime')=='2';assert q('select count(*)from paperlab.gemini_pending')=='0'
 commit=lambda x:"select public.paper_gemini_commit('"+c['token']+"',"+j(x)+')'
 bad=copy.deepcopy(record);bad['trade_approval']=True;q(commit(bad),'Invalid bounded')
 bad=copy.deepcopy(record);bad['sources'][0]['known_at']=(now+datetime.timedelta(days=1)).isoformat();q(commit(bad),'Observed excerpt')
 bad=copy.deepcopy(record);bad['claims'][0]['quote']='invented numbers and unsupported statement';q(commit(bad),'Exact source')
 assert q(commit(record))=='t';assert q(commit(record))=='f'
 second=json.loads(q('select public.paper_gemini_claim()'));assert second['target']['symbol']=='OTHER';failure={**record,'symbol':'OTHER','status':'rate_limited'};q("select public.paper_gemini_commit('"+second['token']+"',"+j(failure)+')')
 assert q('select public.paper_gemini_claim()')==''
 assert q('select daily_reserved from paperlab.gemini_runtime')=='4';assert q('select monthly_reserved from paperlab.gemini_runtime')=='4'
 for role in ['anon','authenticated','service_role']:q('set role '+role+';select *from paperlab.gemini_research','permission denied')
 q('select public.paper_gemini_read(null)','Owner required');data=json.loads(q("select public.paper_project_read('"+owner+"')"));assert data['existing'];assert data['gemini_research']['counts']['drafts']==1;assert 'text'not in data['gemini_research']['records'][1].get('draft',{}).get('sources',[{}])[0]if data['gemini_research']['records'][1]['draft']else True
 print('Gemini SQL passed: disabled until owner free-tier confirmation, atomic two-call reservation, daily cap, exact quotes, source times, no approvals, owner gates and preserved read API.')
finally:q('drop database '+name+' with(force)',db='postgres')
