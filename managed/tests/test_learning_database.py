"""Full paper/learner integration in a disposable network-disabled PostgreSQL DB."""
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from scripts.deploy_managed import source_export,import_sql,jsql,literal
from managed.tests.test_database import query as admin_query,command,environment

ROOT=Path(__file__).resolve().parents[2]
NOW=1793718000000  # 2026-11-03 15:00 UTC, synthetic fixture only.
NODE="""
import fs from 'node:fs';
import {tick} from './managed/functions/_shared/engine.js';
import {livePolicy,stepLearning} from './managed/functions/_shared/learning-runtime.js';
const i=JSON.parse(fs.readFileSync(0,'utf8')),l=i.lease,p=await livePolicy(l.learning,i.time,l.state),o=tick(l.state,i.batch,i.time,p.options);
o.learning=await stepLearning(l.learning,l.state,i.batch,i.time,p);o.state.running=Boolean(l.persist_running)&&o.state.running;
process.stdout.write(JSON.stringify(o));
"""

def main():
    name='paperlab_learning_'+secrets.token_hex(5)
    admin_query('create database '+name)
    checks=[]
    def q(text,fail=False,contains=''):
        result=subprocess.run(command+['-d',name],input=text.encode(),capture_output=True,env=environment)
        if fail:
            assert result.returncode and contains in result.stderr.decode(),result.stderr.decode()
        elif result.returncode:raise RuntimeError(result.stderr.decode()[-2000:])
        return result.stdout.decode().strip()
    def get(text):return json.loads(q(text))
    try:
        q((ROOT/'managed/sql/001_paperlab.sql').read_text());q((ROOT/'managed/sql/002_learning.sql').read_text())
        state,records,manifest=source_export();state['running']=True;state['run_until']='2030-12-06T21:00:00Z';state['pending']=[];state['positions']={};state['last_decision']=None
        state['history']={k:[] for k in state['universe']}
        from datetime import datetime,timezone
        iso=lambda ms:datetime.fromtimestamp(ms/1000,timezone.utc).isoformat().replace('+00:00','Z')
        state['history']['AAPL']=[{'time':iso(NOW-(5-i)*300000),'quote_time':iso(NOW-(5-i)*300000),'price':p} for i,p in enumerate([100,100.1,100.2,100.3,100.4,100.7])]
        q(import_sql(state,records));q('update paperlab.learning_runtime set require_rationale=true')
        fixtures=json.loads((ROOT/'managed/tests/python-fixtures.json').read_text())
        quote=next(c['buy_quote'] for c in fixtures['cases'] if c['symbol']=='AAPL')
        outputs=[]
        for i,price in enumerate([100.7,100.8,110,110]):
            stamp=NOW+i*300000
            batch={'quotes':{'AAPL':{**quote,'bid':price*.9995,'ask':price*1.0005,'time':iso(stamp),'session_start':'2026-11-03T14:30:00Z','session_end':'2026-11-03T21:00:00Z'}},'expected_open':['AAPL'],'closed_symbols':[],'fx':{'usd_per_eur':1.1,'date':'2026-11-03'}}
            q('update paperlab.portfolio set last_attempt=null')
            lease=get('select public.paper_claim_tick(false)')
            result=subprocess.run(['node','--input-type=module','-e',NODE],input=json.dumps({'lease':lease,'batch':batch,'time':stamp}).encode(),capture_output=True,cwd=ROOT)
            assert result.returncode==0,result.stderr.decode();out=json.loads(result.stdout);outputs.append((lease,batch,stamp,out))
            q('begin;update paperlab.portfolio set revision='+str(lease['revision']+1)+',state='+jsql(out['state'])+' where singleton;select public.paper_learning_apply('+jsql(out['learning'])+','+str(lease['revision'])+','+jsql(lease['state'])+');rollback;')
            assert q('select public.paper_commit_tick('+literal(lease['token'])+'::uuid,'+str(lease['revision'])+','+jsql(out)+')')=='t'
            runtime=get('select state from paperlab.learning_runtime');assert runtime['latest_status']=='ok',runtime.get('message')
        checks.append('same_quote_pipeline_commits_main_and_independent_shadow_ledgers')
        ui={'buy':next(t for _,_,_,o in outputs for t in o['trades'] if t['side']=='koop'),'learning':get('select public.paper_learning_read(null)')}
        ui_file=Path('/tmp/paperlab-learning-ui-fixture.json');ui_file.write_text(json.dumps(ui));ui_file.chmod(0o600)
        assert q('select count(*) from paperlab.learning_samples')=='1';checks.append('only_completed_reference_trade_becomes_a_label')
        assert int(q('select count(*) from paperlab.trades'))==manifest['trades']+2
        assert q("select bool_and(snapshot->'purchase_rationale'->>'schema'='purchase-rationale-v1') from paperlab.trades where id>8 and side='koop'")=='t'
        checks.append('new_purchase_has_saved_decision_and_execution_reasoning')
        lease,_,_,out=outputs[-1]
        before=q('select count(*) from paperlab.learning_samples')
        assert q('select public.paper_commit_tick('+literal(lease['token'])+'::uuid,'+str(lease['revision'])+','+jsql(out)+')')=='f'
        assert q('select count(*) from paperlab.learning_samples')==before;checks.append('duplicate_main_commit_cannot_duplicate_training_data')
        training=get('select public.paper_learning_train_input()')
        assert training['sample_count']==1 and training['samples']==[] and training['closes']=={}
        assert q('select public.paper_learning_store('+literal(training['token'])+'::uuid,'+jsql({'status':'waiting_data','samples':1,'days':1})+')')=='t'
        assert get('select training_status from paperlab.learning_runtime')['status']=='waiting_data'
        assert q('select public.paper_learning_train_input() is null')=='t'
        checks.append('live_training_input_waits_with_sparse_data_and_enforces_cooldown')
        for role in ['anon','authenticated']:
            q('set role '+role+';select public.paper_learning_read(null);',True,'permission denied')
            q('set role '+role+';select public.paper_learning_train_input();',True,'permission denied')
            q('set role '+role+';select public.paper_purchase_analysis(null);',True,'permission denied')
        checks.append('all_browser_roles_denied_direct_learning_and_reasoning_rpc')
        q("begin;update paperlab.settings set owner_id='11111111-1111-4111-8111-111111111111';select public.paper_learning_action('22222222-2222-4222-8222-222222222222','pause');rollback;",True,'Not owner')
        checks.append('non_owner_cannot_change_learning')
        # A forged eligible flag cannot bypass actual forward-evidence requirements.
        model='lr-'+'1'*24
        artifact={'id':model,'algorithm':'net-logit-v1','feature_schema':'decision-net-v1','fingerprint':runtime['fingerprint'],'offline_pass':True,'training_cutoff':'2026-01-01'}
        q('insert into paperlab.learning_models(id,artifact,dataset_hash,status,verdict,reviewed_at) values('+literal(model)+','+jsql(artifact)+",'synthetic-only','eligible','{\"eligible\":true,\"lower99_mean_eur\":1,\"net_excess_eur\":100}',now())")
        assert q('select public.paper_learning_action(null,\'promote\','+literal(model)+')')=='f';checks.append('fabricated_eligible_flag_without_20_real_forward_days_cannot_promote')
        # Positive gate fixture: signed model and twenty genuinely later weekday records.
        program="""
        import fs from 'node:fs';import {trainCandidate} from './managed/functions/_shared/learner.js';
        const fp=fs.readFileSync(0,'utf8'),rows=[];let t=Date.parse('2026-08-03T15:00:00Z'),d=0;
        while(d<40){if(![0,6].includes(new Date(t).getUTCDay())){for(let j=0;j<8;j++){const p=j%2===0;
        rows.push({id:d+'-'+j,schema:'decision-net-v1',fingerprint:fp,features:[p?.01:-.01,p?.04:-.03,.002,p?.01:.003,.015,.2,.7],symbol:'AAPL',venue:'XNAS',decision_time:new Date(t+j*1000).toISOString(),entry_time:new Date(t+j*1000+300000).toISOString(),available_at:new Date(t+j*1000+3600000).toISOString(),net_eur:p?3:-1});}d++;}t+=86400000;}
        const result=await trainCandidate(rows,{fingerprint:fp,time:Date.parse('2026-10-01T22:00:00Z')});process.stdout.write(JSON.stringify(result.artifact));
        """
        produced=subprocess.run(['node','--input-type=module','-e',program],input=runtime['fingerprint'].encode(),capture_output=True,cwd=ROOT)
        assert produced.returncode==0,produced.stderr.decode();artifact=json.loads(produced.stdout);assert artifact['offline_pass']
        from datetime import timedelta
        today=datetime.now(timezone.utc).date();dates=[];day=today-timedelta(days=1)
        while len(dates)<20:
            if day.weekday()<5:dates.append(day.isoformat())
            day-=timedelta(days=1)
        dates.sort();created=(datetime.fromisoformat(dates[0])-timedelta(days=3)).replace(tzinfo=timezone.utc).isoformat()
        # Use a synthetic artifact creation time preceding its synthetic forward period.
        statements=['begin;',"update paperlab.portfolio set state=jsonb_set(jsonb_set(state,'{positions}','{}'),'{pending}','[]');"]
        verdict={'eligible':True,'lower99_mean_eur':2,'net_excess_eur':40,'last_date':dates[-1]}
        statements.append('insert into paperlab.learning_models(id,created_at,artifact,dataset_hash,status,verdict,reviewed_at) values('+literal(artifact['id'])+','+literal(created)+'::timestamptz,'+jsql(artifact)+','+literal(artifact['dataset_hash'])+",'eligible',"+jsql(verdict)+',now());')
        for date in dates:
            for account,value in [('reference',501),('learned',503)]:
                record={'date':date,'account':account,'phase':artifact['id'],'model_id':artifact['id'],'complete':True,'unique_rounds':168,'max_drawdown_eur':1,'start_liquidation':500,'end_liquidation':value}
                statements.append('insert into paperlab.learning_days values('+literal(date)+'::date,'+literal(account)+','+literal(artifact['id'])+','+literal(artifact['id'])+','+jsql(record)+');')
        statements.append('insert into paperlab.learning_trades(time,account,phase,trade) select now(),\'learned\','+literal(artifact['id'])+",'{\"side\":\"verkoop\"}'::jsonb from generate_series(1,30);")
        statements.append("do $$begin if not public.paper_learning_action(null,'promote',"+literal(artifact['id'])+") then raise exception 'Qualified paper model not promoted';end if;end$$;")
        statements.append("select public.paper_learning_action(null,'rollback');do $$begin if (select active_model_id from paperlab.learning_runtime) is not null then raise exception 'Rollback failed';end if;end$$;rollback;")
        q('\n'.join(statements));checks.append('qualified_paper_promotion_and_owner_rollback_work_without_real_orders')
        q("begin;update paperlab.learning_runtime set require_rationale=true;update paperlab.portfolio set last_attempt=null;do $$declare l jsonb;o jsonb;blocked boolean:=false;begin l:=public.paper_claim_tick(false);o:=jsonb_build_object('state',l->'state','trades','[{\"side\":\"koop\",\"snapshot\":{}}]'::jsonb);begin perform public.paper_commit_tick((l->>'token')::uuid,(l->>'revision')::bigint,o);exception when others then if sqlerrm like '%Purchase explanation required%' then blocked:=true;else raise;end if;end;if not blocked then raise exception 'Unmotivated purchase accepted';end if;end$$;rollback;")
        checks.append('database_rejects_every_new_buy_without_a_recorded_reason')
        q('select public.paper_learning_action(null,\'pause\')');assert get('select public.paper_learning_payload()')['enabled'] is False
        q('select public.paper_learning_action(null,\'resume\')');checks.append('owner_can_pause_and_resume_learning_without_portfolio_reset')
        # Failure isolation: a broken shadow cash ledger must not roll back a valid main tick.
        q('update paperlab.portfolio set last_attempt=null')
        lease=get('select public.paper_claim_tick(false)');last=outputs[-1]
        result=subprocess.run(['node','--input-type=module','-e',NODE],input=json.dumps({'lease':lease,'batch':last[1],'time':last[2]+300000}).encode(),capture_output=True,cwd=ROOT)
        assert result.returncode==0,result.stderr.decode();out=json.loads(result.stdout);out['learning']['state']['accounts']['reference']['cash']+=1
        assert q('select public.paper_commit_tick('+literal(lease['token'])+'::uuid,'+str(lease['revision'])+','+jsql(out)+')')=='t'
        assert get('select state from paperlab.learning_runtime')['latest_status']=='error'
        assert abs(float(q("select state->>'cash' from paperlab.portfolio"))-out['state']['cash'])<1e-6
        checks.append('bad_shadow_ledger_isolated_and_model_rolled_back_while_main_tick_preserved')
        print(json.dumps({'result':'passed','database':'isolated disposable PostgreSQL, no network','checks':checks,'real_supabase_modified':False},indent=2))
    finally:
        admin_query('drop database '+name)

if __name__=='__main__':main()
