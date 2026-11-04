"""Daily study checks in a disposable, network-disabled local database only."""
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
    name='paperlab_daily_'+secrets.token_hex(5);admin_query('create database '+name);checks=[]
    def q(text,error=None):
        r=subprocess.run(command+['-d',name],input=text.encode(),capture_output=True,env=environment)
        if error:assert r.returncode and error in r.stderr.decode(),r.stderr.decode()
        elif r.returncode:raise RuntimeError(r.stderr.decode()[-2500:])
        return r.stdout.decode().strip()
    def get(text):return json.loads(q(text) or 'null')
    def node(code,obj=None):
        r=subprocess.run(['node','--input-type=module','-e',code],input=json.dumps(obj).encode(),capture_output=True,cwd=ROOT)
        assert not r.returncode,r.stderr.decode();return json.loads(r.stdout)
    try:
        for p in sorted((ROOT/'managed/sql').glob('*.sql')):q(p.read_text())
        state,records,_=source_export();state.update(operation_mode='continuous',running=True);q(import_sql(state,records))
        original=q("select md5(state::text),(select count(*) from paperlab.trades),revision from paperlab.portfolio")
        conf=node("import {DAILY_COMPANIES,DAILY_PROTOCOL} from './managed/functions/_shared/daily-catalogue.js';console.log(JSON.stringify({catalogue:DAILY_COMPANIES,protocol:DAILY_PROTOCOL}));")
        configure='select public.paper_daily_configure('+jsql(conf['catalogue'])+','+jsql(conf['protocol'])+')'
        profile=q(configure);assert len(profile)==64;assert q(configure)==profile
        assert q('select count(*) from paperlab.daily_study_epochs')=='1'
        checks.append('configure_repeatable_without_creating_new_epoch_or_touching_main')
        for role in ['anon','authenticated']:
            q('set role '+role+';select public.paper_daily_read(null);','permission denied')
            q('set role '+role+';select public.paper_daily_export(null);','permission denied')
        q('set role service_role;select * from paperlab.daily_study_records;','permission denied')
        q("select public.paper_daily_read('11111111-1111-4111-8111-111111111111');",'Owner required')
        checks.append('tables_and_owner_read_export_remain_private')
        claim=get('select public.paper_daily_claim()');assert claim and claim['max_new_records']==150
        assert get('select public.paper_daily_claim()') is None
        today=datetime.now(timezone.utc).date();prior=today-timedelta(days=1)
        while prior.weekday()>4:prior-=timedelta(days=1)
        chartbars=[];d=prior
        while len(chartbars)<45:
            if d.weekday()<5:chartbars.insert(0,{'day':str(d),'open_time':str(d)+'T14:30:00Z','close':100+len(chartbars)*.01,'fx':1.1,'fx_date':str(d)})
            d-=timedelta(days=1)
        now=datetime.now(timezone.utc).isoformat();chart={'symbol':'AAPL','bars':chartbars,'latest':chartbars[-1],'actions':[],'observed_at':now,'earnings':{'status':'unknown'}}
        output=node("import fs from 'node:fs';import {stepDaily} from './managed/functions/_shared/daily-study.js';const x=JSON.parse(fs.readFileSync(0,'utf8'));console.log(JSON.stringify(await stepDaily(x.input,x.batch)));",{'input':claim,'batch':{'charts':{'AAPL':chart},'errors':{},'requests':1,'bytes':1000,'checked_at':now}})
        call='select public.paper_daily_commit('+literal(claim['token'])+'::uuid,'+jsql(output)+')'
        assert q(call)=='t';assert q(call)=='f';assert q('select count(*) from paperlab.daily_study_records')=='1'
        q('select public.paper_daily_fail('+literal(claim['token'])+'::uuid)');assert get('select public.paper_daily_claim()') is None
        checks.append('real_prospective_output_single_use_daily_lease_and_no_manual_limit_bypass')
        r=output['records'][0];rid=r['id']
        old_decision=str(prior-timedelta(days=1))+'T06:10:00Z'
        q('update paperlab.daily_study_records set decision_at='+literal(old_decision)+'::timestamptz,record=jsonb_set(record,\'{decision_at}\','+jsql(old_decision)+')')
        q('update paperlab.daily_study_runtime set last_claim=null;delete from paperlab.daily_study_quality')
        lease=get('select public.paper_daily_claim()')
        actual_entry={**chartbars[-1],'known_at':now,'price_eur':chartbars[-1]['close']/1.1*1.001,'qty':.98,'gross_eur':98,'commission_eur':1,'budget_eur':100}
        valid={**output,'records':[],'bars':[],'updates':[{'id':rid,'entry':actual_entry,'outcomes':{},'status':'following','reason':None}]}
        assert q('select public.paper_daily_commit('+literal(lease['token'])+'::uuid,'+jsql(valid)+')')=='t'
        assert q('select status from paperlab.daily_study_records')=='following'
        checks.append('a_causal_future_entry_backed_by_the_frozen_source_bar_can_commit')
        # Controlled old-date fixtures in this local DB only; never forge a live quote.
        entry={'day':str(prior),'open_time':str(prior)+'T14:30:00Z','known_at':now,'price_eur':100,'close':110,'fx':1.1,'qty':.98,'gross_eur':98,'commission_eur':1,'budget_eur':100}
        outcome={'status':'observed','day':str(today),'known_at':now,'net_eur':2,'stressed_net_eur':1,'sessions':20}
        fixture={**r,'entry':entry,'status':'complete','outcomes':{'1':outcome,'5':outcome,'20':outcome}}
        q('update paperlab.daily_study_records set record='+jsql(fixture)+",status='complete' where id="+literal(rid))
        q("update paperlab.daily_study_epochs set development_start=current_date-61,test_start=current_date-1,test_end=current_date+1,release_after=current_date+46")
        read=get('select public.paper_daily_read(null)');export=get('select public.paper_daily_export(null)')
        assert not read['groups'];assert read['recent'][0]['outcomes']=={'status':'sealed'};assert export[0]['sealed']
        q('select public.paper_daily_maintenance()');assert q('select released_at is null from paperlab.daily_study_epochs limit 1')=='t'
        q("update paperlab.daily_study_epochs set development_start=current_date-120,test_start=current_date-60,test_end=current_date,release_after=current_date+45")
        # Labels stay sealed through the additional maturity window.
        assert get('select public.paper_daily_export(null)')[0]['outcomes']=={'status':'sealed'}
        q("update paperlab.daily_study_epochs set development_start=current_date-200,test_start=current_date-140,test_end=current_date-81,release_after=current_date-36")
        q('select public.paper_daily_maintenance()')
        assert q('select released_at is not null from paperlab.daily_study_epochs order by id limit 1')=='t'
        checks.append('sealed_labels_hidden_in_summary_and_every_export_until_maturity_window')
        # Reject immutable entry/output changes and malformed batches atomically.
        q("update paperlab.daily_study_runtime set last_claim=null;update paperlab.daily_study_records set status='following',record=jsonb_set(record,'{status}','\"following\"')")
        lease=get('select public.paper_daily_claim()');patch={'id':rid,'entry':{**entry,'qty':1000},'outcomes':fixture['outcomes'],'status':'complete','reason':None}
        bad={**output,'records':[],'bars':[],'updates':[patch]}
        q('select public.paper_daily_commit('+literal(lease['token'])+'::uuid,'+jsql(bad)+')','Frozen daily entry changed')
        q('select public.paper_daily_commit('+literal(lease['token'])+"::uuid,'{}')",'Daily output outside budget')
        assert q('select token is not null from paperlab.daily_study_runtime')=='t'
        checks.append('frozen_entry_and_invalid_batches_reject_without_partial_writes')
        q("update paperlab.daily_study_runtime set token=null,lease_until=null,last_claim=null;update paperlab.free_usage set estimated_worker_egress_bytes=2000000000")
        assert get('select public.paper_daily_claim()') is None;assert q('select status from paperlab.daily_study_runtime')=='budget_paused'
        assert q("select md5(state::text),(select count(*) from paperlab.trades),revision from paperlab.portfolio")==original
        checks.append('budget_pause_preserves_main_funds_positions_trades_and_revision')
        # Same decision payload size at the admission cap, without touching real data.
        q('insert into paperlab.daily_study_records select \'dy-\'||substr(md5(i::text),1,24),profile,\'S\'||i,week,decision_day,decision_at,\'complete\',record from paperlab.daily_study_records cross join generate_series(1,9999)i')
        size=get("select jsonb_build_object('rows',count(*),'bytes',pg_total_relation_size('paperlab.daily_study_records')) from paperlab.daily_study_records")
        assert size['rows']==10000 and size['bytes']<48000000,size
        q('update paperlab.free_usage set estimated_worker_egress_bytes=0;update paperlab.daily_study_runtime set last_claim=null')
        assert get('select public.paper_daily_claim()')['max_new_records']==0
        checks.append('ten_thousand_representative_dossiers_fit_storage_budget_and_stop_admission')
        print(json.dumps({'checks':checks,'sizing':size,'count':len(checks)},indent=2))
    finally:admin_query('drop database '+name+' with(force)')

if __name__=='__main__':main()
