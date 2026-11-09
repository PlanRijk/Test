import json,sys,secrets,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from managed.tests.test_database import query,command,environment
name='paperlab_dashboard_'+secrets.token_hex(4);query('create database '+name)
def q(s,fail=False):
 r=subprocess.run(command+['-d',name],input=s.encode(),capture_output=True,env=environment)
 if fail:assert r.returncode
 elif r.returncode:raise RuntimeError(r.stderr.decode()[-3000:])
 return r.stdout.decode().strip().splitlines()[-1]if r.stdout.strip()else''
try:
 for p in sorted((ROOT/'managed/sql').glob('*.sql')):q(p.read_text())
 q('set role anon;select public.paper_dashboard_read(null)',True)
 q("update paperlab.settings set owner_id='11111111-1111-4111-8111-111111111111'")
 q('select public.paper_dashboard_read(null)',True)
 assert json.loads(q("select public.paper_dashboard_read('11111111-1111-4111-8111-111111111111')"))['available']==False
 q("insert into paperlab.portfolio(singleton,state)values(true,'{\"running\":true,\"history\":{},\"last_observation\":{}}')on conflict do nothing;update paperlab.capital_runtime set profile='test',state='{\"pending\":[],\"positions\":{},\"risk\":{\"data_complete\":true}}',summary='{}'")
 r=json.loads(q("select public.paper_dashboard_read('11111111-1111-4111-8111-111111111111')"));assert r['available']and r['account']['pending_buys']==0;assert r['signals_are_orders']==False;before=q("select md5(row_to_json(p)::text)from paperlab.portfolio p")
 for _ in range(2):q("select public.paper_dashboard_read('11111111-1111-4111-8111-111111111111')")
 assert before==q("select md5(row_to_json(p)::text)from paperlab.portfolio p")
 print('Dashboard SQL: private owner read, unconfigured state and compact configured payload passed')
finally:query('drop database '+name+' with(force)')
