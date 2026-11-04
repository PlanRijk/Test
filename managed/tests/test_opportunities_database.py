"""No real markets/accounts: full opportunity pipeline in a disposable local DB."""
import json
from pathlib import Path
import secrets
import subprocess
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from scripts.deploy_managed import source_export,import_sql,literal,jsql
from managed.tests.test_database import query as admin_query,command,environment
ROOT=Path(__file__).resolve().parents[2]
T=1793718900000  # Synthetic 2026-11-03 15:15 UTC.
NODE="""
import fs from 'node:fs';import {tick} from './managed/functions/_shared/engine.js';
import {stepOpportunities} from './managed/functions/_shared/opportunities.js';
const i=JSON.parse(fs.readFileSync(0,'utf8')),o=tick(i.lease.state,i.batch,i.time);
o.opportunities=await stepOpportunities(i.lease.opportunities,o.state,i.batch,i.time);
process.stdout.write(JSON.stringify(o));
"""


def main():
    name='paperlab_opportunities_'+secrets.token_hex(5);admin_query('create database '+name);checks=[]
    def q(text,expected_error=None):
        r=subprocess.run(command+['-d',name],input=text.encode(),capture_output=True,env=environment)
        if expected_error:assert r.returncode and expected_error in r.stderr.decode(),r.stderr.decode()
        elif r.returncode:raise RuntimeError(r.stderr.decode()[-1800:])
        return r.stdout.decode().strip()
    def get(text):return json.loads(q(text))
    try:
        for file in ['001_paperlab.sql','002_learning.sql','003_continuous.sql','004_opportunities.sql']:q((ROOT/'managed/sql'/file).read_text())
        state,records,manifest=source_export();state.update(running=True,operation_mode='continuous',positions={},pending=[],last_decision=None)
        from datetime import datetime,timezone
        iso=lambda t:datetime.fromtimestamp(t/1000,timezone.utc).isoformat().replace('+00:00','Z')
        state['history']={k:[] for k in state['universe']};state['history']['AAPL']=[{'time':iso(T-(5-i)*300000),'quote_time':iso(T-(5-i)*300000),'price':p} for i,p in enumerate([100,100.1,100.2,100.3,100.4,100.7])]
        q(import_sql(state,records));q('update paperlab.learning_runtime set require_rationale=true')
        quote=json.loads((ROOT/'managed/tests/python-fixtures.json').read_text())['cases'][0]['buy_quote']
        outputs=[]
        for index,offset in enumerate([0,5,35,125]):
            time=T+offset*60000;price=100.7
            batch={'quotes':{'AAPL':{**quote,'time':iso(time),'bid':price*.9995,'ask':price*1.0005,'session_start':'2026-11-03T14:30:00Z','session_end':'2026-11-03T21:00:00Z'}},'expected_open':['AAPL'],'closed_symbols':[],'fx':{'usd_per_eur':1.1,'date':'2026-11-03'}}
            q('update paperlab.portfolio set last_attempt=null');lease=get('select public.paper_claim_tick(false)')
            r=subprocess.run(['node','--input-type=module','-e',NODE],input=json.dumps({'lease':lease,'batch':batch,'time':time}).encode(),capture_output=True,cwd=ROOT)
            assert r.returncode==0,r.stderr.decode();out=json.loads(r.stdout);outputs.append((lease,batch,time,out))
            assert q('select public.paper_commit_tick('+literal(lease['token'])+'::uuid,'+str(lease['revision'])+','+jsql(out)+')')=='t'
            runtime=get('select state from paperlab.opportunity_runtime');assert runtime['status']=='collecting',runtime
            if index==1:
                row=get('select record from paperlab.opportunity_records order by id limit 1')
                bad={'revision':int(q('select revision from paperlab.opportunity_runtime')),'state':runtime,'records':[],'updates':[{'id':row['id'],'outcomes':{'30':{'status':'observed','time':iso(time+600000),'quote_time':iso(time+600000),'net_eur':5}}}]}
                q('select public.paper_opportunity_apply('+jsql(bad)+')',expected_error='Invalid future study outcome')
                assert get('select record from paperlab.opportunity_records order by id limit 1')['outcomes']=={}
        checks.append('main_tick_atomically_persists_causal_opportunities_and_later_costed_outcomes')
        assert int(q('select count(*) from paperlab.opportunity_records'))==2
        assert q("select bool_and(record->>'status'='complete' and record->'outcomes'->'30'->>'status'='observed' and record->'outcomes'->'120'->>'status'='observed') from paperlab.opportunity_records")=='t'
        assert get("select record from paperlab.opportunity_days")['records']==2
        assert int(q('select count(*) from paperlab.learning_samples'))==0
        assert int(q('select count(*) from paperlab.trades'))==manifest['trades']+1
        checks.append('hypothetical_rows_never_become_executed_trades_or_training_labels')
        checks.append('future_outcomes_cannot_be_written_before_the_horizon')
        lease,_,_,out=outputs[-1]
        assert q('select public.paper_commit_tick('+literal(lease['token'])+'::uuid,'+str(lease['revision'])+','+jsql(out)+')')=='f'
        assert int(q('select count(*) from paperlab.opportunity_records'))==2;checks.append('lease_replay_does_not_duplicate_observations')
        owner_view=get('select public.paper_opportunity_read(null)');assert owner_view['used_for_training'] is False
        assert len(get('select public.paper_opportunity_records(null)'))==2
        assert 'active' not in owner_view['state'];checks.append('owner_reads_compact_summary_and_bounded_export')
        for role in ['anon','authenticated']:
            for call in ['public.paper_opportunity_read(null)','public.paper_opportunity_records(null)','public.paper_opportunity_payload()','public.paper_opportunity_maintenance()']:
                q('set role '+role+';select '+call,expected_error='permission denied')
        q("select public.paper_opportunity_action('11111111-1111-4111-8111-111111111111','pause')",expected_error='Not owner')
        checks.append('direct_browser_roles_and_non_owner_denied')
        q("update paperlab.free_usage set estimated_worker_egress_bytes=2000000000;select public.paper_opportunity_guard();")
        paused=get('select public.paper_opportunity_payload()');assert paused['enabled'] is False and 'state' not in paused
        assert q("select state->>'running' from paperlab.portfolio")=='true';checks.append('early_study_budget_pause_protects_main_trial')
        q("update paperlab.free_usage set estimated_worker_egress_bytes=0;select public.paper_opportunity_action(null,'resume');")
        before=q('select count(*) from paperlab.trades')
        q("insert into paperlab.opportunity_records select 'op-'||substr(md5(i::text),1,24),current_date-100,now()-interval '100 days','AAPL','control','old','{\"status\":\"complete\"}' from generate_series(1,5100)i;")
        q('select public.paper_maintenance()')
        assert int(q('select count(*) from paperlab.opportunity_records'))==2
        assert q('select count(*) from paperlab.trades')==before;checks.append('independent_maintenance_prunes_old_hypotheses_not_purchase_audits')
        # Invalid study output must roll back only its own subtransaction.
        q('update paperlab.portfolio set last_attempt=null');lease=get('select public.paper_claim_tick(false)')
        out={'state':lease['state'],'trades':[],'events':[],'observations':[],'equity':None,'opportunities':{'revision':lease['opportunities']['revision'],'state':{**lease['opportunities']['state'],'active':{'op-'+24*'a':{}}},'records':[],'updates':[]}}
        assert q('select public.paper_commit_tick('+literal(lease['token'])+'::uuid,'+str(lease['revision'])+','+jsql(out)+')')=='t'
        assert q("select state->>'status' from paperlab.opportunity_runtime")=='error'
        assert q('select count(*) from paperlab.trades')==before;checks.append('invalid_study_batch_cannot_roll_back_main_ledger')
        fixture={'summary':get('select public.paper_opportunity_read(null)'),'record':get('select record from paperlab.opportunity_records order by id limit 1')}
        p=Path('/tmp/paperlab-opportunities-ui-fixture.json');p.write_text(json.dumps(fixture));p.chmod(0o600)
        print(json.dumps({'result':'passed','checks':checks,'production_modified':False},indent=2))
    finally:admin_query('drop database '+name)


if __name__=='__main__':main()
