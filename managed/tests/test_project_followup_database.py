"""Isolated no-network SQL regression; no production credentials or restore writes."""
import copy,json,secrets,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];name='followup_'+secrets.token_hex(4)
base=['docker','--host=unix:///var/run/docker.sock','exec','-i','paperlab-research-sql','psql','-U','postgres','-v','ON_ERROR_STOP=1','-At']
subprocess.run(base,input=('create database '+name).encode(),capture_output=True,check=True)
def q(sql,error=None):
 r=subprocess.run(base+['-d',name],input=sql.encode(),capture_output=True)
 if error:assert r.returncode and error in r.stderr.decode(),r.stderr.decode()
 elif r.returncode:raise RuntimeError(r.stderr.decode())
 return r.stdout.decode().strip().splitlines()[-1]if r.stdout.strip()else''
def j(x):return "'"+json.dumps(x).replace("'","''")+"'::jsonb"
try:
 q("""create schema paperlab;create schema cron;create table cron.job(jobid bigint,jobname text);create table cron.job_run_details(jobid bigint,start_time timestamptz,status text);
 create table paperlab.settings(singleton boolean,owner_id uuid);insert into paperlab.settings values(true,'11111111-1111-4111-8111-111111111111');
 create table paperlab.free_usage(month date primary key,estimated_worker_egress_bytes bigint default 0,max_worker_egress_bytes bigint default 4000000000);
 create table paperlab.company_coverage_runtime(catalogue jsonb);create table paperlab.company_coverage(symbol text primary key,record jsonb);create table paperlab.company_reviews(symbol text,reviewed_at timestamptz,record jsonb);
 create table paperlab.company_dossiers(symbol text);create function public.paper_company_save(jsonb)returns text language sql as $$select 'fixture'::text$$;
 create table paperlab.capital_runtime(state jsonb,summary jsonb);insert into paperlab.capital_runtime values('{"positions":{"S0":{}}}','{"equity_eur":10000,"checked_at":"2026-11-12T00:00:00Z"}');create table paperlab.portfolio(state jsonb);insert into paperlab.portfolio values('{"data_info":{"fresh_symbols":12}}');
 create function paperlab.traffic_limit(text)returns bigint language sql as $$select least(3200000000,coalesce((select max_worker_egress_bytes from paperlab.free_usage limit 1),4000000000))$$;""")
 q((ROOT/'managed/sql/027_company_research.sql').read_text());symbols=['S'+str(i)for i in range(100)];q('insert into paperlab.company_coverage_runtime values('+j([{'symbol':s}for s in symbols])+')');now=q('select now()::text')
 rows=[{'version':'company-research-v1','symbol':s,'checked_at':now,'sources':[],'findings':[],'gaps':['missing'],'trade_approval':False,'complete_qualitative_review':False}for s in symbols]
 for i in range(0,100,10):q('select public.paper_company_research_save('+j(rows[i:i+10])+')')
 for p in['028_project_followup.sql','029_private_archives.sql','030_publication_watch.sql']:q((ROOT/'managed/sql'/p).read_text());q((ROOT/'managed/sql'/p).read_text())
 assert q('select count(*)from paperlab.research_history')=='100';q('select public.paper_project_refresh()');assert q('select count(*)from paperlab.research_queue')=='100';assert q("select reasons?'open_position'from paperlab.research_queue where symbol='S0'")=='t'
 for i in range(12):
  r=copy.deepcopy(rows[0]);r['checked_at']=q("select(now()+interval'"+str(i+1)+" milliseconds')::text");r['gaps']=[str(i)];q('select public.paper_company_research_save('+j([r])+')')
 assert q("select count(*)from paperlab.research_history where symbol='S0'")=='8'
 owner="'11111111-1111-4111-8111-111111111111'"
 for role in['anon','authenticated']:
  q('set role '+role+';select public.paper_project_read('+owner+')','permission denied');q('set role '+role+';select *from paperlab.research_history','permission denied');q('set role '+role+';select public.paper_project_claim()','permission denied')
 q('select public.paper_project_read(null)','Owner required')
 q("update paperlab.project_followup set started_at=now()-interval'3 days'");claim=json.loads(q('select public.paper_project_claim()'));today=q('select current_date::text');yesterday=q("select(current_date-1)::text")
 result={'symbol':'VWCE.DE','currency':'EUR','status':'observed','day':yesterday,'close':142,'known_at':now}
 q("select public.paper_project_commit('"+claim['token']+"',"+j(result)+')');assert q('select count(*)from paperlab.benchmark_observations')=='1'
 claim=json.loads(q('select public.paper_project_claim()'));result['close']=150;q("select public.paper_project_commit('"+claim['token']+"',"+j(result)+')');assert q("select record->>'close'from paperlab.benchmark_observations")=='142';assert q('select public.paper_project_claim()')==''
 backup=json.loads(q('select public.paper_project_backup_input()'));raw=''.join(json.loads(q("select to_jsonb(public.paper_project_backup_chunk('"+backup['token']+"',"+str(i)+"))"))for i in range(backup['parts']));snapshot=json.loads(raw);assert snapshot['tables']['capital_runtime'][0]['summary']['equity_eur']==10000;assert'backup_token'not in snapshot['tables']['project_followup'][0]
 record={'kind':'application_snapshot','object_path':backup['object_path'],'bytes':200,'sha256':'0'*64,'restore_tested':True};q("select public.paper_project_backup_commit('"+backup['token']+"',"+j(record)+')');assert q('select public.paper_project_backup_input()')==''
 q('select public.paper_project_archive_path(null,\'bad\')','Owner required');q('select public.paper_project_archive_prune('+j(['sources/never-delete.json.enc'])+')','Unexpected archive deletion')
 if int(q('select extract(isodow from current_date)::int'))<=5:
  watch=json.loads(q('select public.paper_project_watch_claim()'));target=watch['targets'][0]['symbol'];result={'symbol':target,'status':'observed','kind':'issuer_page','sha256':'1'*64,'refs':[]};assert q("select public.paper_project_watch_commit('"+watch['token']+"',"+j([result])+')')=='t';assert q('select count(*)from paperlab.publication_watch')=='1';assert q('select public.paper_project_watch_claim()')==''
  assert q("select public.paper_project_watch_commit('"+watch['token']+"',"+j([result])+')')=='f'
 q('update paperlab.free_usage set max_worker_egress_bytes=1');q("update paperlab.project_followup set attempt_day=null");assert q('select public.paper_project_claim()')==''
 print('SQL passed: 100-company queue, open-position priority, 8-version retention, owner/role checks, future-only reference, immutable daily evidence, daily limits, consistent bounded backup, lease stripping, private archive lookup and budget stops.')
finally:subprocess.run(base,input=('drop database '+name).encode(),capture_output=True,check=True)
