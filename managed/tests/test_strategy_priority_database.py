"""Priority overlay tested in a local PostgreSQL container with no network."""
import json,secrets,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];name='priority_'+secrets.token_hex(4)
cmd=['docker','--host=unix:///var/run/docker.sock','exec','-i','paperlab-research-sql','psql','-U','postgres','-v','ON_ERROR_STOP=1','-At']
def q(sql,error=None,db=name):
 r=subprocess.run(cmd+['-d',db],input=sql.encode(),capture_output=True)
 if error:assert r.returncode and error in r.stderr.decode(),r.stderr.decode()
 elif r.returncode:raise RuntimeError(r.stderr.decode())
 return r.stdout.decode().strip().splitlines()[-1]if r.stdout.strip()else''
q('create database '+name,db='postgres')
try:
 q("""create schema paperlab;create table paperlab.settings(singleton boolean,owner_id uuid);insert into paperlab.settings values(true,'11111111-1111-4111-8111-111111111111');
 create table paperlab.capital_runtime(singleton boolean,profile text,state jsonb,summary jsonb,revision bigint,token uuid,lease_until timestamptz,last_attempt timestamptz);
 insert into paperlab.capital_runtime values(true,'existing-profile','{"cash":900,"positions":{"AAPL":{"qty":2,"stop":99,"target":105}},"risk":{"global_halted":true},"pending":[{"side":"koop","symbol":"MSFT"},{"side":"verkoop","symbol":"AAPL"}]}','{"equity_eur":9999}',9,null,null,null);
 create table paperlab.capital_trades(id bigint);insert into paperlab.capital_trades values(7);create table paperlab.research_queue(symbol text,priority integer,reasons jsonb);create table paperlab.candidate_runtime(status text,report jsonb,final_report jsonb);
 create table paperlab.fixture_commits(body jsonb);
 create function public.paper_audited_claim(uuid,bigint)returns jsonb language sql as $$select '{"company_dossiers":{"AAPL":{"ready":true}},"state":{"cash":900}}'::jsonb$$;
 create function public.paper_audited_commit(uuid,jsonb)returns boolean language plpgsql as $$begin insert into paperlab.fixture_commits values($2);return true;end$$;
 create function public.paper_project_read(uuid,text default null)returns jsonb language sql as $$select '{"existing":true}'::jsonb$$;""")
 migration=(ROOT/'managed/sql/031_strategy_priority.sql').read_text();q(migration);q(migration)
 before=json.loads(q('select state from paperlab.capital_runtime'));policy=q('select public.paper_priority_configure()');assert q('select public.paper_priority_configure()')==policy
 after=json.loads(q('select state from paperlab.capital_runtime'));assert before['cash']==after['cash'];assert before['positions']==after['positions'];assert before['risk']==after['risk'];assert after['pending']==[{'side':'verkoop','symbol':'AAPL'}];assert q('select revision from paperlab.capital_runtime')=='10'
 claim=json.loads(q('select public.paper_audited_claim(null,1)'));assert claim['company_dossiers']=={};assert claim['state']['cash']==900
 q("select public.paper_audited_commit(null,'{\"trades\":[{\"side\":\"koop\"}],\"state\":{\"pending\":[]}}')",'New entries disabled')
 q("select public.paper_audited_commit(null,'{\"trades\":[],\"state\":{\"pending\":[{\"side\":\"koop\"}]}}')",'New entries disabled')
 assert q("select public.paper_audited_commit(null,'{\"trades\":[{\"side\":\"verkoop\"}],\"state\":{\"pending\":[]}}')")=='t';assert q('select count(*)from paperlab.fixture_commits')=='1'
 for role in ['anon','authenticated','service_role']:
  q('set role '+role+';select public.paper_priority_configure()','permission denied');q('set role '+role+';select public.paper_audited_claim_priority_base_v1(null,1)','permission denied')
 q('select public.paper_priority_read(null)','Owner required')
 assert json.loads(q("select public.paper_project_read('11111111-1111-4111-8111-111111111111')"))['existing']is True
 print('SQL passed: repeatable activation, balances/positions/stops/targets/risk preserved, pending buys only cancelled, stale buy commits blocked, sells delegated to unchanged engine, private bases and owner checks.')
finally:q('drop database '+name,db='postgres')
