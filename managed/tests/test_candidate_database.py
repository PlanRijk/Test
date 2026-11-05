"""Candidate isolation, shared labels and quotas; disposable local database only."""
import json,math,secrets,subprocess,sys
from pathlib import Path
from datetime import datetime,timezone
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from scripts.deploy_managed import source_export,import_sql,literal,jsql
from scripts.candidate_study import fingerprint
from managed.tests.test_database import query as admin_query,command,environment
ROOT=Path(__file__).resolve().parents[2]
def main():
 name='paperlab_candidate_'+secrets.token_hex(5);admin_query('create database '+name);checks=[]
 def q(text,error=None):
  r=subprocess.run(command+['-d',name],input=text.encode(),capture_output=True,env=environment)
  if error:assert r.returncode and error in r.stderr.decode(),r.stderr.decode()
  elif r.returncode:raise RuntimeError(r.stderr.decode()[-4500:])
  return r.stdout.decode().strip()
 def get(text):return json.loads((q(text) or 'null').splitlines()[-1])
 def node(code,obj=None):
  r=subprocess.run(['node','--input-type=module','-e',code],input=json.dumps(obj).encode(),capture_output=True,cwd=ROOT)
  assert not r.returncode,r.stderr.decode();return json.loads(r.stdout)
 def clock(stamp):
  # Only this isolated test replaces database time; production uses real now().
  q((ROOT/'managed/sql/010_candidate_comparison.sql').read_text().replace('now()',literal(stamp)+'::timestamptz'))
  q('alter table paperlab.candidate_predictions alter recorded_at set default '+literal(stamp)+'::timestamptz')
 def claim():
  q('update paperlab.candidate_runtime set last_claim=null,token=null,lease_until=null');return get('select public.paper_candidates_claim()')
 def commit(lease,out,error=None):return q('select public.paper_candidates_commit('+literal(lease['token'])+'::uuid,'+jsql(out)+')',error)
 frozen="select md5(state::text),revision,(select count(*) from paperlab.trades),(select md5(jsonb_agg(artifact::text||dataset::text order by id)::text) from paperlab.history_models) from paperlab.portfolio"
 try:
  for path in sorted((ROOT/'managed/sql').glob('*.sql')):q(path.read_text())
  clock('2026-11-06T06:45:00Z')
  state,trades,_=source_export();state['operation_mode']='continuous';q(import_sql(state,trades))
  fixture=node("import {breadthFixture} from './managed/tests/breadth-fixture.mjs';const f=await breadthFixture();f.artifact.windows={validation_start:'2018-12-25'};console.log(JSON.stringify(f));")
  artifact=fixture['artifact'];model_id=artifact['id'];rows=[];base=datetime(2010,1,1,tzinfo=timezone.utc).timestamp()*1000
  for i in range(1000):
   t=base+i*86400000;rows.append(['A'+str(i),'XNYS','S'+str(i%5),t,t+1000,t+2000]+[math.sin(i*.2+j)*.03 for j in range(8)]+([2,1] if i%3 else [-3,-4]))
  excluded=['TEST','XNYS','S',datetime(2022,1,1,tzinfo=timezone.utc).timestamp()*1000]*1
  dataset=rows+[['HIDDEN','XNYS','S',1700000000000,1700000001000,1700000002000]+[0]*8+[100,99]]
  q('insert into paperlab.history_models(id,artifact,dataset) values('+literal(model_id)+','+jsql(artifact)+','+jsql(dataset)+')')
  policy=node("import {CANDIDATE_POLICY} from './managed/functions/_shared/candidate-study.js';console.log(JSON.stringify(CANDIDATE_POLICY));");policy['implementation_sha256']=fingerprint()
  configure='select public.paper_candidates_configure('+jsql(policy)+')';assert q(configure)==q(configure)
  bad={**policy,'primary_days':1};q('select public.paper_candidates_configure('+jsql(bad)+')','Invalid candidate policy')
  for role in ['anon','authenticated']:
   for rpc in ['paper_candidates_claim()','paper_candidates_read(null)',"paper_candidates_action(null,'pause')"]:q('set role '+role+';select public.'+rpc,'permission denied')
  q('set role service_role;select * from paperlab.candidate_models','permission denied')
  q("select public.paper_candidates_read('11111111-1111-4111-8111-111111111111')",'Owner required')
  before=q(frozen);lease=get('select public.paper_candidates_claim()');assert len(lease['training'])==1000 and all(r[0]!='HIDDEN' for r in lease['training']);assert get('select public.paper_candidates_claim()') is None
  models=node("import fs from 'node:fs';import {trainCandidates} from './managed/functions/_shared/candidate-study.js';console.log(JSON.stringify(await trainCandidates(JSON.parse(fs.readFileSync(0,'utf8')),{time:Date.parse('2026-11-05T06:45:00Z')})));",lease)
  assert commit(lease,{'models':models})=='t';assert commit(lease,{'models':models})=='f';assert q(frozen)==before
  checks.append('purged_training_only_two_frozen_models_private_access_and_single_lease')
  for i in range(3):
   rec={'symbol':'C'+str(i),'model_id':model_id,'known_day':'2026-11-05','decision_at':'2026-11-06T06:20:00Z','sector':'IT','venue':'XNAS','features':rows[i][6:14],'probability':.4,'entry':None,'outcome':None,'status':'pending'}
   q('insert into paperlab.history_forecasts values('+literal('hf-'+str(i)*24)+','+literal(model_id)+','+literal(rec['symbol'])+",'2026-11-06','pending',"+jsql(rec)+')')
  q("update paperlab.breadth_runtime set last_day='2026-11-06';update paperlab.history_runtime set last_forward='2026-11-06'")
  lease=claim();out=node("import fs from 'node:fs';import {candidateBatch} from './managed/functions/_shared/candidate-study.js';console.log(JSON.stringify(await candidateBatch(JSON.parse(fs.readFileSync(0,'utf8')),{time:Date.parse('2026-11-06T06:45:00Z')})));",lease)
  assert len(out['records'])==3
  bad=json.loads(json.dumps(out));bad['records'][0]['feature_hash']='0'*64;commit(lease,bad,'Unbacked candidate input')
  bad=json.loads(json.dumps(out));bad['records'][0]['probabilities']=[2,.5];commit(lease,bad,'violates check constraint')
  assert commit(lease,out)=='t';assert q('select count(*) from paperlab.candidate_predictions')=='3';assert q(frozen)==before
  lease=claim();assert len(lease['sources'])==0;assert commit(lease,{'models':models},'Candidate models frozen') is not None
  q('select public.paper_candidates_fail('+literal(lease['token'])+'::uuid)')
  checks.append('future_predictions_bound_to_original_inputs_two_probabilities_per_single_case_no_duplicates')
  # Future labels cannot be adopted early, even if a source record is malformed.
  q("update paperlab.history_forecasts set status='complete',record=record||'{\"entry\":{\"open_time\":\"2026-11-06T14:30:00Z\"},\"outcome\":{\"known_at\":\"2026-12-07T06:10:00Z\",\"net_eur\":2,\"stressed_net_eur\":1}}'::jsonb")
  lease=claim();assert q('select count(*) from paperlab.candidate_predictions where status=2')=='0'
  q('select public.paper_candidates_fail('+literal(lease['token'])+'::uuid)')
  clock('2026-12-08T06:45:00Z');q("update paperlab.history_forecasts set record=jsonb_set(record,'{entry,open_time}','\"2026-11-05T14:30:00Z\"') where symbol='C1'")
  q("update paperlab.history_forecasts set record=jsonb_set(record,'{features}','[9,9,9,9,9,9,9,9]') where symbol='C2'")
  lease=claim();assert q('select count(*) from paperlab.candidate_predictions where status=2')=='1';assert q('select count(*) from paperlab.candidate_predictions where status=3')=='2'
  bad={'protocol':policy['version'],'records':[],'report':{'status':'final','automatic_trading_approval':False}};commit(lease,bad,'Premature candidate verdict');q('select public.paper_candidates_fail('+literal(lease['token'])+'::uuid)')
  assert q(frozen)==before;checks.append('known_future_labels_only_late_entries_or_revised_features_censored_no_early_final_verdict')
  assert q("select public.paper_candidates_action(null,'pause')")=='t';assert claim() is None
  assert q("select public.paper_candidates_action(null,'resume')")=='t';assert q("select public.paper_candidates_action(null,'promote')")=='f'
  q('update paperlab.free_usage set estimated_worker_egress_bytes=1200000000');assert claim() is None;assert q('select status from paperlab.candidate_runtime')=='budget_paused'
  assert q(frozen)==before;checks.append('owner_pause_cancels_processing_budget_pauses_no_promotion_or_portfolio_changes')
  q('update paperlab.free_usage set estimated_worker_egress_bytes=0')
  q("insert into paperlab.candidate_predictions(symbol,day,source,feature_hash,probabilities,reference_probability,sector,venue,primary_sample,status) select 'B'||i,'2026-12-01','core',repeat('a',64),array[.5,.5],.4,'IT','XNAS',false,3 from generate_series(1,24997)i")
  lease=claim();assert lease['max_new']==0;assert q('select count(*) from paperlab.candidate_predictions')=='25000'
  q('select public.paper_candidates_fail('+literal(lease['token'])+'::uuid)')
  checks.append('twenty_five_thousand_cases_stop_new_admission_within_bounded_storage')
  q("delete from paperlab.candidate_predictions where symbol like 'B%'")
  clock('2027-02-08T06:45:00Z')
  q("insert into paperlab.candidate_predictions(symbol,day,source,feature_hash,probabilities,reference_probability,sector,venue,primary_sample,status) values('OLD','2026-10-01','core',repeat('a',64),array[.5,.5],.4,'IT','XNAS',false,3)")
  lease=claim();assert q("select count(*) from paperlab.candidate_predictions where symbol='OLD'")=='0';assert q('select count(*) from paperlab.candidate_predictions where primary_sample')=='3'
  q('select public.paper_candidates_fail('+literal(lease['token'])+'::uuid)')
  q("update paperlab.candidate_runtime set final_report='{\"audit\":\"fixed\"}'")
  lease=claim();assert q('select count(*) from paperlab.candidate_predictions')=='0'
  assert commit(lease,{'protocol':policy['version'],'records':[],'report':{'status':'collecting','automatic_trading_approval':False}})=='t'
  assert get('select final_report from paperlab.candidate_runtime')=={'audit':'fixed'};assert q(frozen)==before
  checks.append('retention_protects_unfinished_primary_trial_and_later_preserves_frozen_final_report')

  print(json.dumps({'checks':checks,'count':len(checks)},indent=2))
 finally:admin_query('drop database '+name+' with(force)')
if __name__=='__main__':main()
