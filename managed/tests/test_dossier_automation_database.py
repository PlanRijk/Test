"""Dossier-v2 complete graph, separate error counts, split recovery and finish-first scheduling."""
import json,secrets,subprocess,datetime,copy
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];name='dossier_'+secrets.token_hex(4)
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
 q("create function paperlab.storage_limit(text)returns bigint language sql as $$select 450000000::bigint$$")
 migration=(ROOT/'managed/sql/042_dossier_automation.sql').read_text();q(migration);q(migration)
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
 q("select paperlab.deep_plan();update paperlab.deep_jobs set generation=(select generation from paperlab.deep_companies where symbol='TEST'),status='queued'where id='test-heavy'")
 heavy=json.loads(q('select public.paper_deep_claim()'));assert heavy['job']['model']=='gemini-3.8-flash';assert heavy['job']['stage']=='pillar'
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
 # Release the source fixture before testing model-only recovery.
 q("select public.paper_deep_commit('"+dc['token']+"',"+js({'status':'completed','trade_approval':False,'independently_verified':False})+')')
 target=c['job']['id']
 q("update paperlab.deep_jobs set status='retry',available_at=now(),attempts=100,validation_attempts=0 where id='"+target+"'")
 transient={'status':'provider_unavailable','trade_approval':False,'independently_verified':False,'attempted_calls':1}
 for _ in range(3):
  q("update paperlab.deep_models set minute=null,retry_after=null;update paperlab.deep_jobs set available_at=now()where id='"+target+"'")
  attempt=json.loads(q('select public.paper_deep_claim()'));assert attempt['job']['id']==target
  q("select public.paper_deep_commit('"+attempt['token']+"',"+js(transient)+')')
  delay=float(q("select extract(epoch from available_at-now())from paperlab.deep_jobs where id='"+target+"'"));assert 30*(2**_)-5<=delay<=30*(2**_)+5
 assert q("select validation_attempts from paperlab.deep_jobs where id='"+target+"'")=='0'
 invalid={**transient,'status':'invalid_response','validation_reason':'claim_evidence'}
 for n in range(3):
  q("update paperlab.deep_models set minute=null,retry_after=null;update paperlab.deep_jobs set available_at=now()where id='"+target+"'")
  attempt=json.loads(q('select public.paper_deep_claim()'));q("select public.paper_deep_commit('"+attempt['token']+"',"+js(invalid)+')')
  if n<2:assert q("select status from paperlab.deep_jobs where id='"+target+"'")=='retry'
 assert q("select status from paperlab.deep_jobs where id='"+target+"'")=='superseded'
 assert q("select count(*)from paperlab.deep_jobs where parent_id='"+target+"'")=='2'
 pieces=[]
 for _ in range(2):
  q("update paperlab.deep_models set minute=null,retry_after=null")
  part=json.loads(q('select public.paper_deep_claim()'));assert part['job']['repair_round']==1;pieces.append((part['input']['source']['offset'],part['input']['source']['text']))
  q("select public.paper_deep_commit('"+part['token']+"',"+js(clean)+')')
 assert ''.join(t for _,t in sorted(pieces))==c['input']['source']['text']
 q('select paperlab.deep_plan()');assert q("select coverage->>'chunks_total'from paperlab.deep_companies where symbol='TEST'")=='3'
 assert q("select coverage->>'chunks_completed'from paperlab.deep_companies where symbol='TEST'")=='3'
 # A new interim report refreshes the generation and runs six assessments + audit.
 interim={**doc,'url':'https://issuer.example/interim.htm','sha256':'d'*64,'text':'Interim revenue was 150 million USD; cash flow was 90 million USD. '+('Complete interim financial statement context. '*10),'kind':'10-Q','role':'interim'}
 q("select public.paper_deep_seed('"+owner+"',"+js([interim])+')')
 q("update paperlab.deep_models set minute=null,retry_after=null")
 fresh=json.loads(q('select public.paper_deep_claim()'));assert fresh['job']['stage']=='extract'
 newfacts={**good,'claims':[{'topic':'cash_earnings','finding':'Interim cash flow and revenue are separately reported.','quote':'Interim revenue was 150 million USD'}]}
 q("select public.paper_deep_commit('"+fresh['token']+"',"+js(newfacts)+')')
 for _ in range(6):
  q("update paperlab.deep_models set minute=null,retry_after=null")
  step=json.loads(q('select public.paper_deep_claim()'));assert step['job']['stage']=='pillar';assert step['input']['pillars']==[]
  pr={**pillar,'pillar':step['job']['pillar'],'evidence_ids':[fresh['job']['id']+':0'],'requires_more_data':False}
  q("select public.paper_deep_commit('"+step['token']+"',"+js(pr)+')')
 q("update paperlab.deep_models set minute=null,retry_after=null")
 final=json.loads(q('select public.paper_deep_claim()'));assert final['job']['stage']=='audit';assert len(final['input']['pillars'])==6
 q("select public.paper_deep_commit('"+final['token']+"',"+js(audit)+')')
 complete=json.loads(q("select report from paperlab.deep_companies where symbol='TEST'"));assert complete['full_ai_dossier'];assert complete['full_company_analysis']is False;assert complete['trade_approval']is False
 assert q("select count(*)from paperlab.dossier_history where symbol='TEST'")=='2'
 # Reinstalling the protocol does not reset valid work or model counters.
 saved=q('select sum(used)from paperlab.deep_models');q(migration);assert q('select sum(used)from paperlab.deep_models')==saved
 q('select paperlab.deep_plan()');xmin=q("select xmin::text from paperlab.deep_companies where symbol='TEST'");q('select paperlab.deep_plan()');assert q("select xmin::text from paperlab.deep_companies where symbol='TEST'")==xmin
 q("insert into paperlab.company_coverage(symbol,record)values('AMD','{}'),('AVGO','{}'),('COST','{}'),('AMZN','{}')")
 peers=json.loads(q("select paperlab.dossier_peers('NVDA')"));assert {p['symbol']for p in peers}=={'AMD','AVGO'}
 peers=json.loads(q("select paperlab.dossier_peers('WMT')"));assert {p['symbol']for p in peers}=={'COST','AMZN'}
 evidence=json.loads(q("select public.paper_dossier_automation_read('"+owner+"','TEST')"))['evidence'];assert evidence and evidence[0]['quote']=='Interim revenue was 150 million USD'
 # Independent watchdog respects owner pauses, flags inactive cron and only queues a wakeup when useful.
 q("create schema cron;create table cron.job(jobname text,active boolean);create schema vault;create table vault.decrypted_secrets(name text,decrypted_secret text);insert into vault.decrypted_secrets values('paperlab_cron_token','synthetic-cron');create schema net;create table net.test_calls(id bigserial);create function net.http_post(url text,headers jsonb,body jsonb,timeout_milliseconds int)returns bigint language plpgsql as $$declare i bigint;begin insert into net.test_calls default values returning id into i;return i;end$$;")
 q("update paperlab.deep_runtime set enabled=false");assert json.loads(q('select public.paper_dossier_watchdog()'))['status']=='owner_paused'
 q("update paperlab.deep_runtime set enabled=true");assert json.loads(q('select public.paper_dossier_watchdog()'))['status']=='scheduler_inactive_owner_action_respected'
 q("insert into cron.job values('paperlab-deep-research',true);insert into paperlab.deep_jobs(id,symbol,stage,priority)values('watch-fixture','TEST','discover',1);update paperlab.deep_runtime set last_attempt=now()-interval'20 minutes',lease_until=null")
 assert json.loads(q('select public.paper_dossier_watchdog()'))['status']=='worker_wakeup_queued';assert q('select count(*)from net.test_calls')=='1'
 # Sustained primary-heavy capacity failures can use the verified free fallback.
 q("update paperlab.deep_jobs set status='completed'where id='watch-fixture';update paperlab.deep_models set minute=null,retry_after=null;update paperlab.deep_models set provider_failures=3,last_status='provider_unavailable',retry_after=now()+interval'15 minutes'where model='gemini-3.8-flash';insert into paperlab.deep_jobs(id,symbol,stage,model,generation)select 'fallback-audit','TEST','audit','gemini-3.8-flash',generation from paperlab.deep_companies where symbol='TEST'")
 q("update paperlab.deep_jobs set status='retry',available_at=now()+interval'15 minutes',result='\"PLACEHOLDER\"'::jsonb where id='fallback-audit'".replace("'\"PLACEHOLDER\"'::jsonb",js({**transient,'provider_http_status':None,'diagnostic':'TimeoutError'})))
 old_primary=q("select used from paperlab.deep_models where model='gemini-3.8-flash'")
 alt=json.loads(q('select public.paper_deep_claim()'));assert alt['job']['model']=='gemini-3-flash-preview';q("select public.paper_deep_commit('"+alt['token']+"',"+js({**transient,'provider_http_status':None,'diagnostic':'TimeoutError'})+')')
 assert q("select used from paperlab.deep_models where model='gemini-3.8-flash'")==old_primary
 assert q("select used from paperlab.deep_models where model='gemini-3-flash-preview'")=='1'
 q("update paperlab.deep_models set used=case when model='gemini-3.5-flash-lite'then 500 when model='gemini-2.5-flash'then 0 else 10 end;insert into paperlab.deep_jobs(id,symbol,stage,model,generation)select 'pool-exhausted','TEST','audit','gemini-3.8-flash',generation from paperlab.deep_companies where symbol='TEST'")
 assert q('select public.paper_deep_claim()')==''

 q("update cron.job set active=false");assert json.loads(q('select public.paper_dossier_watchdog()'))['status']=='scheduler_inactive_owner_action_respected';assert q('select active from cron.job')=='f'


 # Evidence-gap remediation reads bounded cached passages and stops after two rounds.
 q("begin;update paperlab.deep_documents set body=repeat('Debt maturities and weighted average interest rates. ',100) where symbol='TEST';do $$declare n int;begin n:=paperlab.dossier_gap_work('TEST','gap-fixture','[\"schuldlooptijden en rente\"]'::jsonb);assert n=2;assert(select count(*)=2 from paperlab.deep_jobs where id like 'gap:gap-fixture:%' and part_length<=3500 and research_question is not null);assert paperlab.dossier_gap_work('TEST','gap-fixture','[\"schuld\"]'::jsonb)=0;update paperlab.deep_jobs set status='completed'where id like 'gap:gap-fixture:%';assert paperlab.dossier_gap_work('TEST','gap-fixture','[\"schuld\"]'::jsonb)=2;update paperlab.deep_jobs set status='completed'where id like 'gap:gap-fixture:%';assert paperlab.dossier_gap_work('TEST','gap-fixture','[\"schuld\"]'::jsonb)=0;end$$;rollback;")

 for role in ['anon','authenticated','service_role']:q('set role '+role+';select *from paperlab.deep_documents','permission denied')
 q('select public.paper_deep_read(null)','Owner required');d=json.loads(q("select public.paper_project_read('"+owner+"')"));assert d['existing'];assert d['deep_research']['counts']['chunks_completed']==4
 print('Dossier-v2 SQL passed: complete-text chunking, idempotent cache, independent model quota, durable same-chunk retry, exact evidence and private owner read.')
finally:q('drop database '+name+' with(force)',db='postgres')
