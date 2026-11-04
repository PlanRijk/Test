"""Storage sizing, sealed evidence and promotion guards in an isolated local DB."""
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
    name='paperlab_reliability_'+secrets.token_hex(5);admin_query('create database '+name);checks=[]
    def q(text,error=None):
        r=subprocess.run(command+['-d',name],input=text.encode(),capture_output=True,env=environment)
        if error:assert r.returncode and error in r.stderr.decode(),r.stderr.decode()
        elif r.returncode:raise RuntimeError(r.stderr.decode()[-2500:])
        return r.stdout.decode().strip()
    def get(text):return json.loads(q(text))
    def node(code,obj):
        r=subprocess.run(['node','--input-type=module','-e',code],input=json.dumps(obj).encode(),capture_output=True,cwd=ROOT)
        assert r.returncode==0,r.stderr.decode();return json.loads(r.stdout)
    try:
        for f in ['001_paperlab.sql','002_learning.sql','003_continuous.sql','004_opportunities.sql','005_reliability.sql']:q((ROOT/'managed/sql'/f).read_text())
        state,records,_=source_export();state.update(operation_mode='continuous',running=True,positions={},pending=[]);q(import_sql(state,records))
        cat=node("import fs from 'node:fs';import {COMPANIES} from './managed/functions/_shared/catalogue.js';process.stdout.write(JSON.stringify(COMPANIES.map(x=>({symbol:x.symbol,sector:x.sector,venue:x.exchange}))));",{})
        q('insert into paperlab.reliability_catalogue select * from jsonb_to_recordset('+jsql(cat)+')x(symbol text,sector text,venue text)')
        fixture=json.loads(Path('/tmp/paperlab-opportunities-ui-fixture.json').read_text())['record']
        q('insert into paperlab.opportunity_records values('+','.join([literal(fixture['id']),literal(fixture['day'])+'::date',literal(fixture['decision_at'])+'::timestamptz',literal(fixture['symbol']),literal(fixture['cohort']),literal(fixture['fingerprint']),jsql(fixture)])+')')
        q('select public.paper_opportunity_archive_sync(null)')
        a=get('select row_to_json(a) from paperlab.opportunity_archive a');assert a['features']==fixture['context']['features'];assert abs(a['h30'][3]-fixture['outcomes']['30']['net_eur'])<1e-9
        assert len(a['observations'])==18 and len(a['entry'])==10 and len(a['h120'])==11
        q("begin;update paperlab.opportunity_records set record=jsonb_set(record,'{statement}','\"changed\"');select public.paper_opportunity_archive_sync(null);",'Immutable opportunity decision changed')
        q("begin;update paperlab.opportunity_records set record=jsonb_set(record,'{outcomes,30,net_eur}','99');select public.paper_opportunity_archive_sync(null);",'Frozen opportunity entry or outcome changed')
        checks.append('compact_codec_preserves_original_facts_and_freezes_decisions_and_outcomes')
        # Same typed payload sizes; unique keys and varied dates, never production rows.
        q("insert into paperlab.opportunity_archive select 'op-'||substr(md5('s'||i::text),1,24),profile,current_date-1-(i/100),time,'S'||(i%100),venue,cohort,reason,features,observations,entry,h30,h120,status,flags,main_reasons,decision_hash from paperlab.opportunity_archive a cross join generate_series(1,49999)i;")
        sizing=get("select jsonb_build_object('rows',count(*),'allocated_bytes',pg_total_relation_size('paperlab.opportunity_archive'),'live_bytes',sum(pg_column_size(a))) from paperlab.opportunity_archive a")
        assert sizing['rows']==50000 and sizing['allocated_bytes']<88000000,sizing
        q('select public.paper_reliability_maintenance()');assert int(q('select count(*) from paperlab.opportunity_archive'))<=49000
        q("delete from paperlab.opportunity_archive where symbol like 'S%'")
        checks.append('fifty_thousand_representative_records_fit_archive_budget_and_ring_retention_works')
        fp=fixture['fingerprint'];day=fixture['day']
        q("update paperlab.study_epochs set development_start="+literal(day)+"::date-61,test_start="+literal(day)+"::date-1,test_end=current_date+7 where profile="+literal(fp))
        detail=get('select public.paper_opportunity_records(null,'+literal(fixture['id'])+')');assert detail['outcomes']['30']['status']=='sealed'
        exported=get('select public.paper_archive_export(null)');assert exported[0]['h30'] is None and exported[0]['h120'] is None
        token=get('select public.paper_audit_input()')['token']
        eid=int(q('select id from paperlab.study_epochs limit 1'))
        q('select public.paper_audit_store('+literal(token)+'::uuid,'+jsql({'models':[],'epochs':[{'status':'final','version':'reliability-v1','epoch_id':eid,'conclusion':'forged'}]})+')')
        assert q('select released_at is null from paperlab.study_epochs limit 1')=='t'
        checks.append('sealed_labels_hidden_in_details_and_archive_and_cannot_release_early')
        q("update paperlab.study_epochs set test_end=current_date-1;update paperlab.reliability_runtime set last_claim=null;")
        input=get('select public.paper_audit_input()');report=node("import fs from 'node:fs';import {epochAudit} from './managed/functions/_shared/reliability.js';process.stdout.write(JSON.stringify(await epochAudit(JSON.parse(fs.readFileSync(0,'utf8')))));",input['epochs'][0])
        assert report['conclusion']=='not_supported'
        q('select public.paper_audit_store('+literal(input['token'])+'::uuid,'+jsql({'models':[],'epochs':[report]})+')')
        assert get('select public.paper_opportunity_records(null,'+literal(fixture['id'])+')')['outcomes']['30']['status']=='observed'
        checks.append('due_epoch_releases_once_with_insufficient_evidence_recorded_honestly')
        for role in ['anon','authenticated']:
            for call in ['public.paper_reliability_read(null)','public.paper_archive_export(null)','public.paper_audit_input()']:
                q('set role '+role+';select '+call,'permission denied')
        q("select public.paper_reliability_read('11111111-1111-4111-8111-111111111111')",'Not owner')
        checks.append('browser_roles_and_non_owner_denied_reliability_data_and_audit_execution')
        mid='lr-'+24*'a';today=datetime.now(timezone.utc).date();dates=[];d=today-timedelta(days=1)
        while len(dates)<60:
            if d.weekday()<5:dates.append(d.isoformat())
            d-=timedelta(days=1)
        dates.sort();created=(datetime.fromisoformat(dates[0])-timedelta(days=3)).replace(tzinfo=timezone.utc).isoformat()
        artifact={'id':mid,'created_at':created,'training_cutoff':created[:10],'protocol':'paper-learning-v2','fingerprint':fp,'offline_pass':True,'venues':['XNAS','XNYS'],
          'reliability':{'version':'reliability-v1','samples':300,'days':60,'symbols':12,'sectors':11,'validation_rows':30,'test_rows':30}}
        q('insert into paperlab.learning_models(id,created_at,artifact,dataset_hash) values('+literal(mid)+','+literal(created)+'::timestamptz,'+jsql(artifact)+',\''+64*'c'+'\')')
        q('update paperlab.learning_runtime set state='+jsql({'fingerprint':fp,'candidate_id':mid}))
        assert q("select public.paper_learning_action(null,'promote',"+literal(mid)+')')=='f'
        checks.append('forged_model_or_old_eligibility_without_independent_assessment_cannot_promote')
        statements=[];names=['AAPL','CAT','JNJ','JPM','NEE','LIN','XOM','KO','AMZN','GOOGL','PLD','MSFT']
        for i,date in enumerate(dates):
            for account,end,exposure in [('reference',501,100),('learned',503,80)]:
                r={'date':date,'model_id':mid,'phase':mid,'account':account,'complete':True,'unique_rounds':168,'start_liquidation':500,'end_liquidation':end,'exposure_sum':exposure,'stress_cost_eur':.2,'max_drawdown_eur':1}
                statements.append('insert into paperlab.learning_days values('+literal(date)+'::date,'+literal(account)+','+literal(mid)+','+literal(mid)+','+jsql(r)+');')
            for j in range(2):
                statements.append('insert into paperlab.learning_trades(time,account,phase,trade) values('+literal(date+'T16:00:00Z')+"::timestamptz,'learned',"+literal(mid)+','+jsql({'symbol':names[(i*2+j)%12],'side':'verkoop','pnl':3})+');')
            statements.append('insert into paperlab.daily_quality(day,venues) values('+literal(date)+"::date,'{\"XNAS\":{\"fresh\":100,\"expected\":100},\"XNYS\":{\"fresh\":100,\"expected\":100}}');")
        q('\n'.join(statements))
        q('update paperlab.reliability_runtime set last_claim=null');input=get('select public.paper_audit_input()');case=input['models'][0]
        report=node("import fs from 'node:fs';import {modelAudit} from './managed/functions/_shared/reliability.js';import {pairedDays} from './managed/functions/_shared/learning-runtime.js';const c=JSON.parse(fs.readFileSync(0,'utf8'));process.stdout.write(JSON.stringify(await modelAudit(c.artifact,pairedDays(c.records,c.artifact.id),c.meta)));",case)
        assert report['eligible'] is True,report
        q('select public.paper_audit_store('+literal(input['token'])+'::uuid,'+jsql({'models':[report],'epochs':[]})+')')
        # Snapshot ownership is mandatory even after the independent assessment.
        q('select public.paper_learning_review('+literal(mid)+','+jsql({'eligible':True,'forward_days':60,'net_excess_eur':120})+')')
        assert q("select active_model_id is null from paperlab.learning_runtime")=='t'
        tok=str(__import__('uuid').uuid4());data=[{'id':str(i),'features':[.1]*7} for i in range(300)]
        q('select public.paper_learning_capture_input('+literal(tok)+'::uuid,'+literal(fp)+','+jsql(data)+')')
        q('select public.paper_learning_record_dataset('+literal(tok)+'::uuid,'+jsql(artifact)+')')
        assert get('select dataset from paperlab.learning_inputs where token='+literal(tok)+'::uuid')==data
        assert q("select public.paper_learning_action(null,'promote',"+literal(mid)+')')=='t'
        assert q("select public.paper_learning_action(null,'rollback')")=='t'
        checks.append('qualified_sixty_day_case_requires_frozen_dataset_and_can_promote_and_roll_back_only_in_paper')
        fixture_ui={'summary':get('select public.paper_reliability_read(null)'),'archive':get('select public.paper_archive_export(null)')}
        p=Path('/tmp/paperlab-reliability-ui-fixture.json');p.write_text(json.dumps(fixture_ui));p.chmod(0o600)
        print(json.dumps({'result':'passed','checks':checks,'local_archive_sizing':sizing,'production_modified':False},indent=2))
    finally:admin_query('drop database '+name)

if __name__=='__main__':main()
