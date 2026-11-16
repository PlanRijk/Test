"""Isolated whole-document task graph, independent quotas and durable retries."""
import json,secrets,subprocess,datetime,copy
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];name='deep_'+secrets.token_hex(4)
cmd=['docker','--host=unix:///var/run/docker.sock','exec','-i','paperlab-research-sql','psql','-U','postgres','-v','ON_ERROR_STOP=1','-At']
def q(sql,error=None,db=name):
 r=subprocess.run(cmd+['-d',db],input=sql.encode(),capture_output=True)
 if error:assert r.returncode and error in r.stderr.decode(),r.stderr.decode()
 elif r.returncode:raise RuntimeError(r.stderr.decode())
 return r.stdout.decode().strip().splitlines()[-1]if r.stdout.strip()else''
def js(x):return "'"+json.dumps(x).replace("'","''")+"'::jsonb"
q('create database '+name,db='postgres')
try:
 owner='11111111-1111-4111-8111-111111111111';stamp=datetime.datetime.now(datetime.timezone.utc).isoformat()
 q("create schema paperlab;create table paperlab.settings(owner_id uuid,singleton boolean);insert into paperlab.settings values('"+owner+"',true);create table paperlab.company_research(symbol text primary key,record jsonb);insert into paperlab.company_research values('TEST','{\"sources\":[]}');create table paperlab.research_queue(symbol text,priority int);insert into paperlab.research_queue values('TEST',100);create table paperlab.earnings_cycles(symbol text,release_at timestamptz,status text);create table paperlab.scoped_research(symbol text,recorded_at timestamptz,record jsonb);create table paperlab.analyst_consensus(symbol text,record jsonb);create table paperlab.company_coverage(symbol text,record jsonb);create table paperlab.company_coverage_runtime(catalogue jsonb);insert into paperlab.company_coverage_runtime values('[{\"symbol\":\"TEST\",\"sector\":\"Tech\"}]');create table paperlab.portfolio(state jsonb);insert into paperlab.portfolio values('{}');create table paperlab.free_usage(month date primary key,estimated_worker_egress_bytes bigint default 0);create function paperlab.traffic_limit(text)returns bigint language sql as $$select 3200000000::bigint$$;create table paperlab.gemini_runtime(free_tier_confirmed_at timestamptz,quota_evidence jsonb);insert into paperlab.gemini_runtime values(now(),'{\"models\":{\"gemini-3.5-flash-lite\":{\"rpd\":500},\"gemini-3.8-flash\":{\"rpd\":20}}}');create function paperlab.gemini_retry_time(jsonb)returns timestamptz language sql as $$select now()+interval'15 minutes'$$;create function public.paper_project_read(uuid,text default null)returns jsonb language sql as $$select '{\"existing\":true}'::jsonb$$;")
 sql=(ROOT/'managed/sql/039_deep_research.sql').read_text();q(sql);q(sql)
 assert q('select public.paper_deep_claim()')=='';q('select public.paper_deep_enable(null)','Owner required');q("select public.paper_deep_enable('"+owner+"')")
 text='Reported revenue was 100 million USD and cash flow was 80 million USD. '+('Financial information in the annual report. '*190)
 doc={'symbol':'TEST','url':'https://issuer.example/report.htm','sha256':'a'*64,'text':text,'kind':'10-K','role':'annual','known_at':stamp,'filed_at':None,'scope':'Full HTML text','complete_extraction':True}
 seed="select public.paper_deep_seed('"+owner+"',"+js([doc])+')';assert q(seed)=='1';q(seed);assert q('select count(*)from paperlab.deep_documents')=='1';assert int(q("select count(*)from paperlab.deep_jobs where stage='extract'"))==2
 # Avoid source discovery in this deterministic fixture.
 q("update paperlab.deep_companies set next_discovery=now()+interval'7 days'")
 c=json.loads(q('select public.paper_deep_claim()'));assert c['job']['stage']=='extract';assert q('select public.paper_deep_claim()')==''
 failure={'status':'rate_limited','quota_kind':'day','trade_approval':False,'independently_verified':False,'attempted_calls':1}
 assert q("select public.paper_deep_commit('"+c['token']+"',"+js(failure)+')')=='t'
 assert q("select count(*)from paperlab.deep_jobs where status='retry'")=='1';assert q("select count(*)from paperlab.deep_models where retry_after>now()")=='1'
 # Heavy model remains available when the light quota is exhausted.
 q("update paperlab.deep_models set used=daily_limit where model='gemini-3.5-flash-lite';update paperlab.deep_companies set generation='g';insert into paperlab.deep_jobs(id,symbol,stage,model,pillar,generation,priority)values('test-heavy','TEST','pillar','gemini-3.8-flash','risks','g',999)")
 # The real planner computes the generation hash; align this fixture to it.
 q("select paperlab.deep_plan();update paperlab.deep_jobs set generation=(select generation from paperlab.deep_companies where symbol='TEST')where id='test-heavy'")
 heavy=json.loads(q('select public.paper_deep_claim()'));assert heavy['job']['model']=='gemini-3.8-flash'
 pillar={'status':'completed','trade_approval':False,'independently_verified':False,'pillar':'risks','assessment':'This is an evidence-limited risk assessment and identifies missing financial and source coverage.','evidence_ids':[],'limitations':['No complete interim report'],'requires_more_data':True}
 assert q("select public.paper_deep_commit('"+heavy['token']+"',"+js(pillar)+')')=='t'
 # When Lite is exhausted, free Flash can also read a real queued source block.
 overflow=json.loads(q('select public.paper_deep_claim()'));assert overflow['job']['stage']=='extract';assert overflow['job']['model']=='gemini-3.8-flash'
 q("select public.paper_deep_commit('"+overflow['token']+"',"+js(failure)+')')
 q("update paperlab.deep_models set used=daily_limit")
 assert q('select public.paper_deep_claim()')==''
 q("update paperlab.deep_models set used=0,retry_after=null;update paperlab.deep_jobs set available_at=now()where status='retry'")
 again=json.loads(q('select public.paper_deep_claim()'));assert again['job']['id']==c['job']['id'];assert again['input']['source']['text']==c['input']['source']['text']
 bad={'status':'completed','trade_approval':False,'independently_verified':False,'claims':[{'topic':'cash_earnings','finding':'A fabricated unsupported financial conclusion.','quote':'not in this source text'}],'no_material_information':False}
 q("select public.paper_deep_commit('"+again['token']+"',"+js(bad)+')','Exact passage')
 good={**bad,'claims':[{'topic':'cash_earnings','finding':'Reported revenue and cash flow use different metrics.','quote':'Reported revenue was 100 million USD'}]}
 assert q("select public.paper_deep_commit('"+again['token']+"',"+js(good)+')')=='t'
 assert q("select count(*)from paperlab.deep_jobs where stage='extract'and status='completed'")=='1'
 # Finish all chunks, then all six Lite pillars, then one Flash audit.
 while q("select count(*)from paperlab.deep_jobs where stage='extract'and status<>'completed'")!='0':
  c2=json.loads(q('select public.paper_deep_claim()'));assert c2['job']['stage']=='extract'
  clean={'status':'completed','trade_approval':False,'independently_verified':False,'claims':[],'no_material_information':True}
  q("select public.paper_deep_commit('"+c2['token']+"',"+js(clean)+')')
 # Remove the independent-model synthetic fixture, leaving the production planner only.
 q("delete from paperlab.deep_jobs where id='test-heavy'")
 for _ in range(6):
  q("update paperlab.deep_models set minute=null")
  c2=json.loads(q('select public.paper_deep_claim()'));assert c2['job']['stage']=='pillar';assert c2['job']['model']=='gemini-3.5-flash-lite'
  pr={**pillar,'pillar':c2['job']['pillar'],'evidence_ids':[again['job']['id']+':0'],'requires_more_data':False}
  q("select public.paper_deep_commit('"+c2['token']+"',"+js(pr)+')')
 q("update paperlab.deep_models set minute=null")
 c2=json.loads(q('select public.paper_deep_claim()'));assert c2['job']['stage']=='audit';assert c2['job']['model']=='gemini-3.8-flash'
 audit={'status':'completed','trade_approval':False,'independently_verified':False,'summary':'The six requested pillars have been reviewed, while the missing full interim report prevents a complete AI dossier.','checks':[{'pillar':p,'supported':True}for p in ['financial_position','cash_earnings','competitive_position','management','valuation','risks']]}
 q("select public.paper_deep_commit('"+c2['token']+"',"+js(audit)+')')
 report=json.loads(q("select report from paperlab.deep_companies where symbol='TEST'"));assert report['full_ai_dossier']is False;assert report['full_company_analysis']is False;assert report['trade_approval']is False
 assert q("select status from paperlab.deep_companies where symbol='TEST'")=='dossier_completed_with_gaps'
 # Provider day is Pacific, not UTC; a new day clears local exhausted counters automatically.
 q("update paperlab.deep_models set day=(now()at time zone'America/Los_Angeles')::date-1,used=daily_limit;select public.paper_deep_claim()")
 assert q("select sum(used)from paperlab.deep_models")=='0'
 # Source reservations are settled once against measured bytes, without weakening the shared guard.
 q("insert into paperlab.deep_jobs(id,symbol,stage,priority)values('source-fixture','TEST','discover',999)")
 dc=json.loads(q('select public.paper_deep_claim()'));assert dc['job']['stage']=='discover'
 old=int(q('select estimated_bytes from paperlab.deep_runtime'))
 q("select public.paper_deep_reserve_transfer('"+dc['token']+"',100000)")
 q("select public.paper_deep_settle_transfer('"+dc['token']+"',10000)")
 assert int(q('select estimated_bytes from paperlab.deep_runtime'))==old+10000
 q("select public.paper_deep_settle_transfer('"+dc['token']+"',10000)",'Active transfer')
 for role in ['anon','authenticated','service_role']:q('set role '+role+';select *from paperlab.deep_documents','permission denied')
 q('select public.paper_deep_read(null)','Owner required');d=json.loads(q("select public.paper_project_read('"+owner+"')"));assert d['existing'];assert d['deep_research']['counts']['chunks_completed']==2
 print('Deep SQL passed: complete-text chunking, idempotent cache, independent model quota, durable same-chunk retry, exact evidence and private owner read.')
finally:q('drop database '+name+' with(force)',db='postgres')
