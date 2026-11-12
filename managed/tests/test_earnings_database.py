"""Isolated no-network quarterly pilot tests; no production credentials."""
import json,secrets,subprocess,copy,datetime
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];name='earnings_'+secrets.token_hex(4)
cmd=['docker','--host=unix:///var/run/docker.sock','exec','-i','paperlab-research-sql','psql','-U','postgres','-v','ON_ERROR_STOP=1','-At']
def q(sql,error=None,db=name):
 r=subprocess.run(cmd+['-d',db],input=sql.encode(),capture_output=True)
 if error:assert r.returncode and error in r.stderr.decode(),r.stderr.decode()
 elif r.returncode:raise RuntimeError(r.stderr.decode())
 return r.stdout.decode().strip().splitlines()[-1]if r.stdout.strip()else''
def j(x):return "'"+json.dumps(x).replace("'","''")+"'::jsonb"
q('create database '+name,db='postgres')
try:
 owner='11111111-1111-4111-8111-111111111111';now=datetime.datetime.now(datetime.timezone.utc);rows=json.loads((ROOT/'managed/knowledge/earnings-pilot.json').read_text())['companies']
 for r in rows:
  if r['event']:r['event']['release_at']=(now+datetime.timedelta(days=14)).isoformat();r['event']['call_at']=(now+datetime.timedelta(days=14,hours=1)).isoformat()
 q("create schema paperlab;create table paperlab.settings(singleton boolean,owner_id uuid);insert into paperlab.settings values(true,'"+owner+"');create table paperlab.company_coverage_runtime(catalogue jsonb);insert into paperlab.company_coverage_runtime values("+j([{'symbol':r['symbol']}for r in rows])+");create table paperlab.free_usage(month date primary key,estimated_worker_egress_bytes bigint default 0);create function paperlab.traffic_limit(text)returns bigint language sql as $$select 3200000000::bigint$$;create function public.paper_project_read(uuid,text default null)returns jsonb language sql as $$select '{\"old\":true}'::jsonb$$;")
 migration=(ROOT/'managed/sql/033_earnings_pilot.sql').read_text();q(migration);q(migration)
 assert q('select public.paper_earnings_configure('+j(rows)+')')=='10';q('select public.paper_earnings_configure('+j(rows)+')');assert q('select count(*)from paperlab.earnings_cycles')=='10';assert q('select count(*)from paperlab.earnings_tasks')=='80'
 for role in ['anon','authenticated','service_role']:
  q('set role '+role+';select public.paper_earnings_configure('+j(rows)+')','permission denied');q('set role '+role+';select *from paperlab.earnings_companies','permission denied')
 q('select public.paper_earnings_read(null)','Owner required')
 report=json.loads(q("select public.paper_project_read('"+owner+"')"));assert report['old'];assert len(report['earnings_pilot']['companies'])==10
 claim=json.loads(q('select public.paper_earnings_claim()'));assert len(claim['targets'])==10;assert q('select public.paper_earnings_claim()')==''
 result=[{'symbol':r['symbol'],'status':'partial','sources':[],'qualitative_review_completed':False}for r in rows];assert q("select public.paper_earnings_commit('"+claim['token']+"',"+j(result)+')')=='t';assert q("select public.paper_earnings_commit('"+claim['token']+"',"+j(result)+')')=='f'
 assert q('select count(*)from paperlab.earnings_companies where next_check>now()')=='10';assert q('select public.paper_earnings_claim()')==''
 cycle=q("select id from paperlab.earnings_cycles where symbol='NVDA'");company=next(r for r in rows if r['symbol']=='NVDA')
 f={'currency':'USD','revenue_unit':'million','revenue':{'low':90,'base':100,'high':110},'eps':{'low':1,'base':2,'high':3},'eps_basis':'GAAP','direction':'up','rationale':'Synthetic expected growth based on operating evidence and reported financial statements. '+('x'*30),'counterarguments':'Synthetic contrary case: costs, demand and margins can disappoint.','sources':[company['source_refs'][0]]}
 freeze=lambda obj:"select public.paper_earnings_freeze('"+owner+"','"+cycle+"',"+j(obj)+')'
 bad=copy.deepcopy(f);bad.pop('direction');q(freeze(bad),'Complete sourced forecast')
 bad=copy.deepcopy(f);bad['revenue']['low']=200;q(freeze(bad),'Ordered finite scenario')
 bad=copy.deepcopy(f);bad['sources'][0]['sha256']='0'*64;q(freeze(bad),'Known archived source')
 q("update paperlab.earnings_cycles set release_at=now()+interval'12 hours'where id='"+cycle+"'");q(freeze(f),'before cutoff');q("update paperlab.earnings_cycles set release_at=now()+interval'14 days'where id='"+cycle+"'")
 assert q(freeze(f))=='t';q(freeze(f),'immutable')
 actual={'currency':'USD','revenue_million':105,'eps':2.5,'eps_basis':'GAAP','source_url':company['source_refs'][0]['url'],'source_sha256':'a'*64,'guidance_review':'Synthetic reviewed forward guidance and context, not automatic approval. '+('x'*30),'call_review':'Synthetic review of the management call, questions and contrary evidence. '+('x'*30)}
 save=lambda obj:"select public.paper_earnings_actual('"+owner+"','"+cycle+"',"+j(obj)+')'
 q(save(actual),'must follow release');q("update paperlab.earnings_cycles set release_at=now()-interval'2 days'where id='"+cycle+"'");assert q(save(actual))=='t';q(save(actual),'cannot be overwritten')
 d=json.loads(q("select public.paper_earnings_read('"+owner+"','NVDA')"));assert d['cycles'][0]['assessment']['revenue_in_range'];assert d['cycles'][0]['assessment']['eps_in_range'];assert not d['cycles'][0]['assessment']['consensus_surprise_available']
 # Incompatible EPS accounting bases do not produce a false hit/miss.
 q("update paperlab.earnings_cycles set actual=jsonb_set(actual,'{eps_basis}','\"non-GAAP\"')where id='"+cycle+"'")
 d=json.loads(q("select public.paper_earnings_read('"+owner+"','NVDA')"));assert d['cycles'][0]['assessment']['eps_in_range']is None
 prices={'status':'observed','rows':[{'day':'2026-11-04','close':100},{'day':'2026-11-05','close':101},{'day':'2026-11-06','close':102},{'day':'2026-11-09','close':101},{'day':'2026-11-10','close':100},{'day':'2026-11-11','close':98}]}
 q("update paperlab.earnings_cycles set release_at='2026-11-04T21:20:00Z',frozen_at='2026-11-03T20:00:00Z',prices="+j(prices)+" where id='"+cycle+"'")
 score=json.loads(q("select paperlab.earnings_price_assessment('"+cycle+"')"));assert score['outcomes']['1']['correct'];assert not score['outcomes']['5']['correct'];assert '20'not in score['outcomes']
 task=q("select id from paperlab.earnings_tasks where cycle_id='"+cycle+"'and phase='initial'")
 note='Synthetic substantive review with a real registered official source and explicit remaining uncertainties.'
 review="select public.paper_earnings_review('"+owner+"','"+task+"','"+note+"','"+company['source_refs'][0]['url']+"')";assert q(review)=='t';q(review,'already recorded')
 # Future earnings control tasks and old missed phases are distinct.
 q("update paperlab.earnings_cycles set release_at=now()+interval'2 days'where symbol='WMT';select paperlab.earnings_plan(id)from paperlab.earnings_cycles where symbol='WMT'")
 assert int(q("select count(*)from paperlab.earnings_tasks t join paperlab.earnings_cycles c on c.id=t.cycle_id where c.symbol='WMT'and t.status='missed_before_pilot'"))>=2
 print('Earnings SQL passed: ten sourced dossiers, repeatable planning, private owner gates, bounded once-only leases, preserved unknowns, immutable pre-release forecasts, actuals after release and comparable GAAP scoring.')
finally:q('drop database '+name+' with(force)',db='postgres')
