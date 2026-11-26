"""Align the existing project with the owner's 26 Nov Free-plan observation."""
import json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts import managed_api as api
from scripts.compact_transport import SNAPSHOT
from scripts.deploy_managed import literal
REF='kdyzlbknygeqinqduuic'
METRICS={'egress_bytes':250000000,'database_bytes':152000000,'monthly_active_users':4,'file_storage_bytes':20000000,'log_ingestion_bytes':110000000,'log_query_bytes':1970000000,
 'included':{'egress_bytes':5000000000,'database_bytes':500000000,'monthly_active_users':50000,'file_storage_bytes':1000000000,'log_ingestion_bytes':1000000000,'log_query_bytes':100000000000}}
QUOTAS="select jsonb_agg(jsonb_build_object('model',model,'daily_limit',daily_limit,'rpm',rpm,'tpm',tpm)order by model)as limits from paperlab.deep_models"
LEDGER="select jsonb_build_object('count',count(*),'digest',md5(coalesce(string_agg(to_jsonb(t)::text,''order by id),'')))as ledger from paperlab.capital_trades t"
def configure(ref=REF):
 if ref!=REF:raise ValueError('Existing Paperlab project required')
 api.ROOT=ROOT
 before=api.sql(ref,SNAPSHOT,True)[0]['frozen'];quotas=api.sql(ref,QUOTAS,True)[0];ledger=api.sql(ref,LEDGER,True)[0]
 raw=api.sql(ref,"select estimated_worker_egress_bytes from paperlab.free_usage where month=date_trunc('month',now()at time zone'UTC')::date",True)[0]['estimated_worker_egress_bytes']
 sql=(ROOT/'managed/sql/048_free_plan_reconciliation.sql').read_text().rsplit('commit;',1)[0]
 sql+='select paperlab.record_provider_usage('+literal('owner-free-plan-2026-11-26')+','+literal(json.dumps(METRICS))+"::jsonb,'Owner-provided Supabase Free dashboard screenshot, 26 November 2026; billing cycle dates unknown');"
 api.sql(ref,sql+'rollback;');api.sql(ref,sql+'commit;')
 assert before==api.sql(ref,SNAPSHOT,True)[0]['frozen'],'Financial profiles changed'
 assert quotas==api.sql(ref,QUOTAS,True)[0],'Model quotas changed'
 assert ledger==api.sql(ref,LEDGER,True)[0],'Trade ledger changed'
 result=api.sql(ref,'select paperlab.traffic_meter()as meter')[0]['meter']
 assert result['raw_work_bytes']>=raw,'Historical work meter reset'
 assert result['hard_limit_bytes']<=4500000000 and result['provider_verified']is False
 print(json.dumps({'free_plan_aligned':True,'provider_meter_live':False,'traffic':result,'financial_profiles_and_trades_unchanged':True,'model_limits_unchanged':True,'paid_resources':False}))
if __name__=='__main__':configure(sys.argv[1]if len(sys.argv)>1 else REF)
