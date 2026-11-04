"""Combined history/forward pipeline in a disposable local DB; no live mutations."""
import json
from pathlib import Path
import secrets
import subprocess
import sys
from datetime import datetime,timedelta,timezone
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from scripts.deploy_managed import source_export,import_sql,literal,jsql
from managed.tests.test_database import query as admin_query,command,environment
ROOT=Path(__file__).resolve().parents[2]

def main():
    name='paperlab_history_'+secrets.token_hex(5);admin_query('create database '+name);checks=[]
    def q(text,error=None):
        p=subprocess.run(command+['-d',name],input=text.encode(),capture_output=True,env=environment)
        if error:assert p.returncode and error in p.stderr.decode(),p.stderr.decode()
        elif p.returncode:raise RuntimeError(p.stderr.decode()[-3500:])
        return p.stdout.decode().strip()
    def get(text):return json.loads(q(text) or 'null')
    def node(code,obj=None):
        p=subprocess.run(['node','--input-type=module','-e',code],input=json.dumps(obj).encode(),capture_output=True,cwd=ROOT)
        assert not p.returncode,p.stderr.decode();return json.loads(p.stdout)
    def commit(lease,output,error=None):return q('select public.paper_history_commit('+literal(lease['token'])+'::uuid,'+jsql({'stage':lease['stage'],**output})+')',error)
    try:
        for path in sorted((ROOT/'managed/sql').glob('*.sql')):q(path.read_text())
        state,trades,_=source_export();state.update(operation_mode='continuous',running=True);q(import_sql(state,trades))
        original=q("select md5(state::text),revision,(select count(*) from paperlab.trades) from paperlab.portfolio")
        daily=node("import {DAILY_COMPANIES,DAILY_PROTOCOL} from './managed/functions/_shared/daily-catalogue.js';console.log(JSON.stringify({catalogue:DAILY_COMPANIES,protocol:DAILY_PROTOCOL}));")
        q('select public.paper_daily_configure('+jsql(daily['catalogue'])+','+jsql(daily['protocol'])+')')
        conf=node("import {HISTORY_ITEMS,HISTORY_PROTOCOL} from './managed/functions/_shared/history-data.js';console.log(JSON.stringify({symbols:HISTORY_ITEMS.map(x=>x.symbol),protocol:HISTORY_PROTOCOL}));")
        configure='select public.paper_history_configure('+jsql(conf['protocol'])+','+jsql(conf['symbols'])+')';profile=q(configure);assert q(configure)==profile
        for role in ['anon','authenticated']:
            q('set role '+role+';select public.paper_history_read(null);','permission denied')
            q('set role '+role+';select public.paper_history_export(null);','permission denied')
        q('set role service_role;select * from paperlab.history_models;','permission denied')
        q("select public.paper_history_read('11111111-1111-4111-8111-111111111111')",'Owner required')
        checks.append('private_sources_models_exports_and_repeatable_configuration')
        lease=get('select public.paper_history_claim()');assert lease['stage']=='base';assert get('select public.paper_history_claim()') is None
        base={'symbol':'__base__','status':'available','data':{'fx':{'rows':[],'columns':[]},'mapping':{}},'hash':'a'*64,'source_bytes':1}
        assert commit(lease,{'snapshots':[base]})=='t';assert commit(lease,{'snapshots':[base]})=='f'
        rounds=0
        while True:
            lease=get('select public.paper_history_claim()')
            if lease['stage']=='train':break
            assert lease['stage']=='collect';rounds+=1
            assert len(lease['symbols'])<=15 and lease['derivation_snapshots'][0]['symbol']=='__base__'
            commit(lease,{'snapshots':[{'symbol':s,'status':'unavailable','data':{'reason':'local fixture only'},'hash':None,'source_bytes':0} for s in lease['symbols']]})
        assert rounds==11
        checks.append('single_use_leases_and_bounded_bootstrap_progress_to_training')
        # Local algorithm-generated fixture. No synthetic observations ever enter production.
        code="""import {trainHistory} from './managed/functions/_shared/history-model.js';import {DAILY_COMPANIES} from './managed/functions/_shared/daily-catalogue.js';import fs from 'node:fs';const input=JSON.parse(fs.readFileSync(0,'utf8')),rows=[];let t=Date.parse('2016-01-04T06:20:00Z');for(let i=0;i<600;i++){for(let j=0;j<6;j++){const item=DAILY_COMPANIES[(i*6+j)%150],y=(i+j)%2;rows.push({id:i+'-'+j,symbol:item.symbol,venue:item.exchange,sector:item.sector,date:new Date(t).toISOString().slice(0,10),decision:t,entry:t+86400000,available:t+30*86400000,features:[y?.02:-.02,.01,.02,.01,.1,.01,-.01,.02],net:y?4:-3,stress:y?3:-4,y,origin:'historically_simulated'});}t+=86400000;}console.log(JSON.stringify(await trainHistory({...input,prepared:{rows,source_candidates:rows.length,sampled_candidates:rows.length,excluded:{},source_count:153}})));"""
        result=node(code,{'profile':profile,'cutoff':lease['cutoff'],'snapshots':lease['snapshots']})
        assert result['status']=='historical_model_frozen';assert commit(lease,result)=='t'
        assert q('select count(*) from paperlab.history_models')=='1'
        forward=get('select public.paper_history_claim()');assert forward['stage']=='forward'
        assert forward['artifact']['id']==result['artifact']['id']
        checks.append('actual_fixed_optimizer_artifact_and_frozen_dataset_are_stored_once')
        now=datetime.now(timezone.utc);today=now.date();rid='hf-'+'b'*24
        record={'id':rid,'model_id':result['artifact']['id'],'symbol':'AAPL','venue':'XNAS','sector':'IT','decision_at':now.isoformat(),'decision_day':str(today),'known_day':str(today-timedelta(days=1)),'probability':.6,'selected':True,'features':[0]*8,'status':'pending','entry':None,'outcome':None,'reason':None,'origin':'prospective_hypothetical'}
        out={'records':[record],'updates':[],'report':{'status':'collecting_forward','days':0,'automatic_trading_approval':False},'context':[],'checks':[],'connections':[]}
        assert commit(forward,out)=='t';assert get('select public.paper_history_claim()') is None
        assert q('select calls from paperlab.history_runtime')=='14'
        visible=get('select public.paper_history_read(null)');assert 'dataset' not in visible['model'] and 'token' not in visible['runtime'];assert visible['counts']['predictions']==1
        assert get('select public.paper_history_export(null)')[0]['origin']=='prospective_hypothetical'
        checks.append('daily_forward_limit_private_bounded_export_and_explicit_origin')
        # Invalid old-close execution is rejected atomically even for the server role.
        q('update paperlab.history_runtime set calls=0,last_forward=null')
        again=get('select public.paper_history_claim()')
        bad={**out,'records':[],'updates':[{'id':rid,'status':'following','entry':{'open_time':(now-timedelta(days=1)).isoformat(),'day':str(today-timedelta(days=1)),'close':100},'outcome':None,'reason':None}]}
        commit(again,bad,'Unbacked or retrospective forward entry')
        q('select public.paper_history_fail('+literal(again['token'])+'::uuid)')
        q("update paperlab.free_usage set estimated_worker_egress_bytes=2000000000;update paperlab.history_runtime set calls=0,last_forward=null")
        assert get('select public.paper_history_claim()') is None
        assert q('select status from paperlab.history_runtime')=='budget_paused'
        assert q("select md5(state::text),revision,(select count(*) from paperlab.trades) from paperlab.portfolio")==original
        assert q('select count(*) from paperlab.learning_models')=='0'
        checks.append('causal_entry_guard_budget_stop_and_original_portfolio_and_models_unchanged')
        print(json.dumps({'checks':checks,'count':len(checks)},indent=2))
    finally:admin_query('drop database '+name+' with(force)')

if __name__=='__main__':main()
