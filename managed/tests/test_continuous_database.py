"""Continuous scheduling, bounded research and retention in a disposable local DB."""
import json
from pathlib import Path
import secrets
import subprocess
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from scripts.deploy_managed import source_export,import_sql,literal,jsql
from managed.tests.test_database import query as admin_query,command,environment
ROOT=Path(__file__).resolve().parents[2]


def main():
    name='paperlab_continuous_'+secrets.token_hex(5)
    admin_query('create database '+name)
    checks=[]
    def q(text,denied=False):
        r=subprocess.run(command+['-d',name],input=text.encode(),capture_output=True,env=environment)
        if denied:
            assert r.returncode and 'permission denied' in r.stderr.decode(),r.stderr.decode()
        elif r.returncode:raise RuntimeError(r.stderr.decode()[-1800:])
        return r.stdout.decode().strip()
    def get(text):return json.loads(q(text))
    try:
        for file in ['001_paperlab.sql','002_learning.sql','003_continuous.sql']:q((ROOT/'managed/sql'/file).read_text())
        state,records,manifest=source_export();state['run_until']='2000-01-01T00:00:00Z';state['running']=True
        q(import_sql(state,records))
        assert q("select paperlab.run_open('{\"operation_mode\":\"continuous\",\"run_until\":\"2000-01-01\"}')")=='t'
        assert q("select paperlab.run_open('{\"run_until\":\"2000-01-01\"}')")=='f'
        assert q("select paperlab.run_open('{}')")=='f'
        assert q('select public.paper_claim_tick(false) is null')=='t'
        q("update paperlab.portfolio set state=jsonb_set(state,'{operation_mode}','\"continuous\"');select public.paper_action(null,'start');")
        lease=get('select public.paper_claim_tick(false)');assert lease['state']['operation_mode']=='continuous'
        out={'state':lease['state'],'trades':[],'events':[],'observations':[],'equity':None}
        assert q('select public.paper_commit_tick('+literal(lease['token'])+'::uuid,'+str(lease['revision'])+','+jsql(out)+')')=='t'
        checks.append('continuous_main_claim_and_commit_work_after_original_deadline')
        train=get('select public.paper_learning_train_input()');assert train and train['sample_count']==0
        q('select public.paper_learning_store('+literal(train['token'])+'::uuid,\'{"status":"waiting_data"}\')')
        checks.append('learning_continues_after_original_deadline_without_invented_samples')
        token=q('select public.paper_claim_research()');assert token and q('select public.paper_claim_research() is null')=='t'
        assert q('select public.paper_commit_research('+literal(token)+'::uuid,\'{"sources":[]}\')')=='t'
        assert q('select public.paper_commit_research('+literal(token)+'::uuid,\'{"sources":[]}\')')=='f'
        assert q('select public.paper_claim_research() is null')=='t'
        checks.append('research_is_leased_committed_once_and_rate_limited')
        q("update paperlab.research_runtime set last_claim=null;update paperlab.free_usage set estimated_worker_egress_bytes=2400000000;")
        assert q('select public.paper_claim_research() is null')=='t'
        assert q('select status from paperlab.research_runtime')=='budget_paused'
        assert q("select state->>'running' from paperlab.portfolio")=='true'
        checks.append('research_soft_budget_preserves_main_processing_budget')
        q("insert into paperlab.research(report) select '{}'::jsonb from generate_series(1,50);")
        q("insert into paperlab.equity(time,value,benchmark) select date_trunc('day',now()-interval '200 days')+i*interval '1 hour',case when i=2 then 300 when i=10 then 700 else 500+i end,500 from generate_series(0,15) i;")
        q("insert into paperlab.learning_trades(time,account,phase,trade) values(now()-interval '200 days','reference','test','{\"side\":\"koop\"}'),(now()-interval '200 days','reference','test','{\"side\":\"verkoop\"}');")
        before=q('select count(*) from paperlab.trades')
        result=get('select public.paper_maintenance()');assert result['purchase_audits_retained'] is True
        assert int(q('select count(*) from paperlab.research'))==40
        assert int(q("select count(*) from paperlab.equity where time::date=(now()-interval '200 days')::date"))==4
        assert get("select jsonb_agg(value order by value) from paperlab.equity where time::date=(now()-interval '200 days')::date")==[300,500,515,700]
        assert q('select count(*) from paperlab.trades')==before
        assert int(q("select count(*) from paperlab.learning_trades where trade->>'side'='koop'"))==1
        assert int(q("select count(*) from paperlab.learning_trades where trade->>'side'='verkoop'"))==0
        checks.append('maintenance_caps_reports_and_compacts_old_curves_without_deleting_purchase_audits')
        assert get('select public.paper_maintenance()')['status']=='maintained'
        for role in ['anon','authenticated']:
            for call in ['public.paper_claim_research()','public.paper_maintenance()',"public.paper_commit_research(null,'{}')"]:q('set role '+role+';select '+call,True)
        checks.append('browser_roles_cannot_trigger_maintenance_or_research')
        print(json.dumps({'result':'passed','database':'isolated local PostgreSQL','checks':checks,'production_modified':False},indent=2))
    finally:admin_query('drop database '+name)


if __name__=='__main__':main()
