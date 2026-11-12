"""Only an isolated PostgreSQL container with network disabled; no live credentials."""
import copy,json,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
CMD=['docker','--host=unix:///var/run/docker.sock','exec','-i','paperlab-research-sql','psql','-U','postgres','-v','ON_ERROR_STOP=1','-At']
def q(sql,error=None):
 r=subprocess.run(CMD,input=sql.encode(),capture_output=True)
 if error:assert r.returncode and error in r.stderr.decode(),r.stderr.decode()
 elif r.returncode:raise RuntimeError(r.stderr.decode())
 return r.stdout.decode().strip().splitlines()[-1]if r.stdout.strip()else''
def j(x):return "'"+json.dumps(x).replace("'","''")+"'::jsonb"
q("create schema paperlab;create role anon;create role authenticated;create role service_role;create table paperlab.settings(singleton boolean,owner_id uuid);insert into paperlab.settings values(true,'11111111-1111-4111-8111-111111111111');create table paperlab.free_usage(month date primary key,estimated_worker_egress_bytes bigint default 0,max_worker_egress_bytes bigint default 4000000000);create table paperlab.company_coverage_runtime(catalogue jsonb);")
q((ROOT/'managed/sql/027_company_research.sql').read_text());q((ROOT/'managed/sql/027_company_research.sql').read_text())
symbols=['S'+str(i)for i in range(100)];q('insert into paperlab.company_coverage_runtime values('+j([{'symbol':s}for s in symbols])+')');now=q('select now()::text')
rows=[{'version':'company-research-v1','symbol':s,'checked_at':now,'sources':[],'findings':[],'gaps':['missing primary text'],'trade_approval':False,'complete_qualitative_review':False}for s in symbols]
for i in range(0,100,10):assert q('select public.paper_company_research_save('+j(rows[i:i+10])+')')=='10'
assert q('select count(*)from paperlab.company_research')=='100'
owner="'11111111-1111-4111-8111-111111111111'"
assert json.loads(q('select public.paper_company_research_read('+owner+')'))['counts']['companies']==100
for role in ['anon','authenticated','service_role']:
 q('set role '+role+';select public.paper_company_research_save('+j(rows[:1])+')','permission denied')
 q('set role '+role+';select *from paperlab.company_research','permission denied')
for role in ['anon','authenticated']:q('set role '+role+';select public.paper_company_research_read('+owner+')','permission denied')
q('select public.paper_company_research_read(null)','Owner required')
bad=copy.deepcopy(rows[0]);bad['trade_approval']=True;q('select public.paper_company_research_save('+j([bad])+')','Invalid research evidence')
bad=copy.deepcopy(rows[0]);bad['sources']=[{'url':'javascript:bad','sha256':'0'*64}];q('select public.paper_company_research_save('+j([bad])+')','Invalid research evidence')
q('select public.paper_company_research_save('+j(rows[:11])+')','Bounded research batch')
q('update paperlab.free_usage set max_worker_egress_bytes=1');before=q('select estimated_worker_egress_bytes from paperlab.free_usage');q('select public.paper_company_research_save('+j(rows[:1])+')','Research budget limit');assert q('select estimated_worker_egress_bytes from paperlab.free_usage')==before
print('SQL passed: 100-company import, repeatable migration, owner check, RLS/roles, management-only writes, no approval, URL validation and atomic budget rollback.')
