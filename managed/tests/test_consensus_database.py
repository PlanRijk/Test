"""Isolated private SQL integration for provider consensus; no production writes."""
import json,secrets,subprocess,copy,datetime
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];name='consensus_'+secrets.token_hex(4)
cmd=['docker','--host=unix:///var/run/docker.sock','exec','-i','paperlab-research-sql','psql','-U','postgres','-v','ON_ERROR_STOP=1','-At']
def q(sql,error=None,db=name):
 r=subprocess.run(cmd+['-d',db],input=sql.encode(),capture_output=True)
 if error:assert r.returncode and error in r.stderr.decode(),r.stderr.decode()
 elif r.returncode:raise RuntimeError(r.stderr.decode())
 return r.stdout.decode().strip().splitlines()[-1]if r.stdout.strip()else''
def j(x):return "'"+json.dumps(x).replace("'","''")+"'::jsonb"
q('create database '+name,db='postgres')
try:
 owner='11111111-1111-4111-8111-111111111111';now=datetime.datetime.now(datetime.timezone.utc);stamp=now.isoformat();period=stamp[:7]
 q("create schema paperlab;create table paperlab.settings(singleton boolean,owner_id uuid);insert into paperlab.settings values(true,'"+owner+"');create table paperlab.quarterly_expectations(symbol text primary key,checked_at timestamptz,record jsonb);create table paperlab.earnings_cycles(id text primary key,symbol text,release_at timestamptz);create table paperlab.free_usage(month date primary key,estimated_worker_egress_bytes bigint default 0);create function paperlab.traffic_limit(text)returns bigint language sql as $$select 3200000000::bigint$$;create function public.paper_project_read(uuid,text default null)returns jsonb language sql as $$select '{\"existing\":true}'::jsonb$$;")
 for i in range(15):q("insert into paperlab.quarterly_expectations values('T"+str(i)+"',now(),"+j({'eligible':i<12,'input_known_at':stamp,'metrics':{'revenue':{'target_period_reference':period+'-30'}}})+')')
 q("insert into paperlab.earnings_cycles values('e','T0',now()+interval'3 days')")
 sql=(ROOT/'managed/sql/035_analyst_consensus.sql').read_text();q(sql);q(sql)
 c=json.loads(q('select public.paper_consensus_claim()'));assert len(c['targets'])==10;assert c['targets'][0]['symbol']=='T0';assert q('select public.paper_consensus_claim()')==''
 metric={'status':'provider_reported','analysts':20,'average':100,'low':90,'high':110,'currency':'USD','basis':'normalized'}
 rows=[{'version':'analyst-consensus-v1','symbol':x['symbol'],'status':'provider_reported','known_at':stamp,'trade_approval':False,'qualitative_approval':False,'independently_verified':False,'source_url':'https://finance.yahoo.com/quote/'+x['symbol']+'/analysis/','source_sha256':'a'*64,'quarters':[{'period':period,'revenue':metric,'eps':metric}]}for x in c['targets']]
 commit=lambda rows:"select public.paper_consensus_commit('"+c['token']+"',"+j(rows)+')'
 bad=copy.deepcopy(rows);bad[0]['quarters'][0]['eps']['analysts']=0;q(commit(bad),'Consensus count/range')
 bad=copy.deepcopy(rows);bad[0]['quarters'][0]['eps']['analysts']=2.5;q(commit(bad),'Consensus count/range')
 bad=copy.deepcopy(rows);bad[0]['independently_verified']=True;q(commit(bad),'Provider source proof')
 assert q(commit(rows))=='t';assert q(commit(rows))=='f';assert q('select count(*)from paperlab.earnings_consensus_snapshots')=='1'
 for role in ['anon','authenticated','service_role']:q('set role '+role+';select *from paperlab.analyst_consensus','permission denied')
 q('select public.paper_consensus_read(null)','Owner required')
 r=json.loads(q("select public.paper_project_read('"+owner+"')"));assert r['existing'];assert r['analyst_consensus']['counts']['reported']==10
 c2=json.loads(q('select public.paper_consensus_claim()'));assert len(c2['targets'])==2;assert {x['symbol']for x in c2['targets']}=={'T8','T9'}
 print('Consensus SQL passed: eligible roster, bounded batches, count/basis proof, owner gates, no independent-verification inflation, immutable pre-event copy and unchanged existing API.')
finally:q('drop database '+name+' with(force)',db='postgres')
