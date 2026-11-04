"""Extra observation storage, causal codecs and budgets in a disposable local DB."""
import copy
import json
from pathlib import Path
import secrets
import subprocess
import sys
from datetime import datetime,timezone,timedelta
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from scripts.deploy_managed import source_export,import_sql,literal,jsql
from managed.tests.test_database import query as admin_query,command,environment
ROOT=Path(__file__).resolve().parents[2]

def main():
    name='paperlab_breadth_'+secrets.token_hex(5);admin_query('create database '+name);checks=[]
    def q(text,error=None):
        r=subprocess.run(command+['-d',name],input=text.encode(),capture_output=True,env=environment)
        if error:assert r.returncode and error in r.stderr.decode(),r.stderr.decode()
        elif r.returncode:raise RuntimeError(r.stderr.decode()[-4000:])
        return r.stdout.decode().strip()
    def get(text):return json.loads(q(text) or 'null')
    def node(code,obj=None):
        r=subprocess.run(['node','--input-type=module','-e',code],input=json.dumps(obj).encode(),capture_output=True,cwd=ROOT)
        assert not r.returncode,r.stderr.decode();return json.loads(r.stdout)
    def commit(lease,out,error=None):return q('select public.paper_breadth_commit('+literal(lease['token'])+'::uuid,'+jsql(out)+')',error)
    def next_claim():
        q('update paperlab.breadth_runtime set last_day=null,token=null,lease_until=null;delete from paperlab.breadth_days where day=current_date')
        return get('select public.paper_breadth_claim()')
    try:
        for path in sorted((ROOT/'managed/sql').glob('*.sql')):q(path.read_text())
        state,trades,_=source_export();state.update(operation_mode='continuous',running=True);q(import_sql(state,trades))
        daily=node("import {DAILY_COMPANIES,DAILY_PROTOCOL} from './managed/functions/_shared/daily-catalogue.js';console.log(JSON.stringify({catalogue:DAILY_COMPANIES,protocol:DAILY_PROTOCOL}));")
        q('select public.paper_daily_configure('+jsql(daily['catalogue'])+','+jsql(daily['protocol'])+')')
        fixture=node("import {breadthFixture} from './managed/tests/breadth-fixture.mjs';console.log(JSON.stringify(await breadthFixture(Date.now())));")
        policy=node("import {BREADTH_POLICY} from './managed/functions/_shared/breadth-study.js';console.log(JSON.stringify(BREADTH_POLICY));")
        model=fixture['artifact'];model_id=model['id'];today=datetime.now(timezone.utc).date()
        q('insert into paperlab.history_models(id,created_at,artifact,dataset) values('+literal(model_id)+','+literal(model['created_at'])+'::timestamptz,'+jsql(model)+",'[]')")
        q('update paperlab.history_runtime set profile='+literal(model['fingerprint'])+',protocol='+jsql({'implementation_sha256':fixture['reference_implementation']})+',config='+jsql(fixture['config'])+',last_forward=current_date')
        for symbol in fixture['reference_symbols']:
            record={'symbol':symbol,'model_id':model_id,'decision_at':datetime.now(timezone.utc).isoformat(),'status':'pending','entry':None,'outcome':None}
            q('insert into paperlab.history_forecasts values('+literal('hf-'+secrets.token_hex(12))+','+literal(model_id)+','+literal(symbol)+",current_date,'pending',"+jsql(record)+')')
        packed=[]
        for b in fixture['bars']:
            record={'day':b[1],'open_time':datetime.fromtimestamp(b[2]/1000,timezone.utc).isoformat(),'close':b[3],'volume':b[4],'fx':b[5],'fx_date':b[6],'session_starts':b[8],'actions':[]}
            packed.append({'symbol':b[0],'day':b[1],'observed_at':datetime.fromtimestamp(b[7]/1000,timezone.utc).isoformat(),'close':b[3],'record':record})
        q('insert into paperlab.daily_study_bars select * from jsonb_to_recordset('+jsql(packed)+')x(symbol text,day date,observed_at timestamptz,close double precision,record jsonb)')
        original=q("select md5(state::text),revision,(select md5(jsonb_agg(record order by id)::text) from paperlab.history_forecasts),(select md5(artifact::text||dataset::text) from paperlab.history_models),(select count(*) from paperlab.trades) from paperlab.portfolio")
        configure='select public.paper_breadth_configure('+jsql(policy)+')';assert q(configure)==q(configure)
        for role in ['anon','authenticated']:
            q('set role '+role+';select public.paper_breadth_read(null);','permission denied')
            q('set role '+role+';select public.paper_breadth_export(null,false);','permission denied')
        q('set role service_role;select * from paperlab.breadth_scores;','permission denied')
        q("select public.paper_breadth_read('11111111-1111-4111-8111-111111111111')",'Owner required')
        checks.append('repeatable_configuration_private_tables_and_owner_only_exports')
        q('update paperlab.history_runtime set last_forward=null');assert get('select public.paper_breadth_claim()') is None
        q('update paperlab.history_runtime set last_forward=current_date')
        lease=get('select public.paper_breadth_claim()');assert lease['max_new']==150 and lease['max_details']==40
        assert get('select public.paper_breadth_claim()') is None
        out=node("import fs from 'node:fs';import {stepBreadth} from './managed/functions/_shared/breadth-study.js';const input=JSON.parse(fs.readFileSync(0,'utf8'));console.log(JSON.stringify(await stepBreadth(input)));",lease)
        assert len(out['records'])==127 and len(out['traces'])==40
        bad=copy.deepcopy(out);bad['records'][0][0]=fixture['reference_symbols'][0];bad['traces']=[]
        commit(lease,bad,'Invalid or duplicate reference prediction');assert q('select count(*) from paperlab.breadth_scores')=='0'
        bad=copy.deepcopy(out);bad['traces'][0]['record']['prices'][0][3]=datetime.now(timezone.utc).timestamp()*1000+86400000
        commit(lease,bad,'Invalid or frozen breadth trace');assert q('select count(*) from paperlab.breadth_scores')=='0'
        assert commit(lease,out)=='t';assert commit(lease,out)=='f';assert get('select public.paper_breadth_claim()') is None
        visible=get('select public.paper_breadth_read(null)');assert visible['counts']['compact']==127 and visible['counts']['traces']==40 and visible['counts']['reference']==20
        assert len(get('select public.paper_breadth_export(null,true)'))==40
        checks.append('real_worker_output_single_daily_commit_no_duplicate_reference_or_future_trace')
        lease=next_claim();assert q("select public.paper_breadth_action(null,'pause')")=='t'
        assert commit(lease,out)=='f';assert get('select public.paper_breadth_claim()') is None
        assert q("select public.paper_breadth_action(null,'resume')")=='t'
        assert q("select public.paper_breadth_action(null,'replace-model')")=='f'
        checks.append('owner_pause_invalidates_inflight_work_without_touching_reference')
        # Synthetic clock replay for SQL codec/horizon checks, local DB only.
        record=get('select row_to_json(s) from paperlab.breadth_scores s where not exists(select 1 from paperlab.breadth_traces t where t.model_id=s.model_id and t.symbol=s.symbol and t.day=s.day) order by symbol limit 1')
        symbol=record['symbol'];source=[b for b in fixture['bars'] if b[0]==symbol];entry_bar=source[20];exit_bar=source[40]
        decision=entry_bar[2]-3600000;decision_day=datetime.fromtimestamp(decision/1000,timezone.utc).date()
        q('update paperlab.breadth_scores set day='+literal(str(decision_day))+'::date,decision_at=to_timestamp('+str(decision/1000)+'),known_day='+literal(source[19][1])+'::date where model_id='+literal(model_id)+' and symbol='+literal(symbol))
        for position in [20,40]:
            b=source[position];q('update paperlab.daily_study_bars set record=jsonb_set(record,\'{session_starts}\','+jsql([a[2]/1000 for a in source[:position+1]])+') where symbol='+literal(symbol)+' and day='+literal(b[1])+'::date')
        codec=node("import fs from 'node:fs';import {dailyEntry,dailyOutcome} from './managed/functions/_shared/daily-study.js';import {encodeEntry,encodeOutcome} from './managed/functions/_shared/breadth-study.js';import {DAILY_COMPANIES} from './managed/functions/_shared/daily-catalogue.js';const x=JSON.parse(fs.readFileSync(0,'utf8')),item=DAILY_COMPANIES.find(i=>i.symbol===x.symbol),bar=b=>({day:b[1],open_time:new Date(b[2]).toISOString(),close:b[3],fx:b[5],fx_date:b[6]}),entry={...dailyEntry(x.config,item,bar(x.entry)),known_at:new Date(x.entry[7]).toISOString()},outcome={...dailyOutcome(x.config,item,entry,bar(x.exit)),known_at:new Date(x.exit[7]).toISOString()};console.log(JSON.stringify({entry:encodeEntry(entry),outcome:encodeOutcome(outcome)}));",{'config':fixture['config'],'symbol':symbol,'entry':entry_bar,'exit':exit_bar})
        lease=next_claim();follow={'protocol':policy['version'],'model_id':model_id,'records':[],'traces':[],'updates':[[symbol,str(decision_day),1,codec['entry'],None,None]],'summary':{}}
        assert commit(lease,follow)=='t'
        lease=next_claim();bad=copy.deepcopy(follow);bad['updates'][0][3][7]+=1;commit(lease,bad,'Frozen breadth entry or outcome changed')
        complete=copy.deepcopy(follow);complete['updates'][0][2]=2;complete['updates'][0][4]=codec['outcome'];assert commit(lease,complete)=='t'
        checks.append('lossless_entry_and_exact_twenty_session_outcome_with_immutable_fills')
        q('update paperlab.free_usage set estimated_worker_egress_bytes=1200000000');lease=next_claim();assert lease['max_new']==75 and lease['max_details']==0
        q('select public.paper_breadth_fail('+literal(lease['token'])+'::uuid)')
        q('update paperlab.free_usage set estimated_worker_egress_bytes=1500000000');lease=next_claim();assert lease['max_new']==0
        q('select public.paper_breadth_fail('+literal(lease['token'])+'::uuid)')
        q('update paperlab.free_usage set estimated_worker_egress_bytes=1800000000');assert next_claim() is None
        assert q('select status from paperlab.breadth_runtime')=='hard_budget_paused'
        checks.append('adaptive_limits_reduce_then_finish_only_then_stop_at_hard_free_budget')
        # Fifty thousand representative closed cases, including final costs.
        q('insert into paperlab.breadth_scores select model_id,\'S\'||(i%150),current_date-1-(i/150),decision_at,known_day,probability,features,sector,venue,2,entry,outcome,null from paperlab.breadth_scores cross join generate_series(1,49873)i where status=2')
        size=get("select jsonb_build_object('rows',count(*),'bytes',pg_total_relation_size('paperlab.breadth_scores')) from paperlab.breadth_scores")
        assert size['rows']==50000 and size['bytes']<32000000,size
        q('update paperlab.free_usage set estimated_worker_egress_bytes=0');lease=next_claim();assert lease['max_new']==0
        assert len(get('select public.paper_breadth_export(null,false)'))==500
        q("select public.paper_breadth_fail("+literal(lease['token'])+"::uuid)")
        q("insert into paperlab.breadth_scores select model_id,'OLD',current_date-400,decision_at,known_day,probability,features,sector,venue,2,entry,outcome,null from paperlab.breadth_scores where status=2 limit 1")
        q("insert into paperlab.breadth_traces select model_id,symbol,day,'{}'::jsonb from paperlab.breadth_scores where symbol='OLD'")
        lease=next_claim();assert q("select count(*) from paperlab.breadth_scores where symbol='OLD'")=='0'
        assert q("select count(*) from paperlab.breadth_traces where symbol='OLD'")=='0'
        checks.append('retention_removes_only_expired_extra_cases_and_their_traces')
        assert q("select md5(state::text),revision,(select md5(jsonb_agg(record order by id)::text) from paperlab.history_forecasts),(select md5(artifact::text||dataset::text) from paperlab.history_models),(select count(*) from paperlab.trades) from paperlab.portfolio")==original
        checks.append('fifty_thousand_closed_cases_fit_storage_budget_exports_bound_and_frozen_study_is_unchanged')
        print(json.dumps({'checks':checks,'sizing':size,'count':len(checks)},indent=2))
    finally:admin_query('drop database '+name+' with(force)')

if __name__=='__main__':main()
