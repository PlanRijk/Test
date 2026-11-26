"""Deploy owner-only readiness diagnostics for the existing Paperlab website."""
import sys,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts import managed_api as api
from scripts.compact_transport import SNAPSHOT
REF='kdyzlbknygeqinqduuic'
def configure(ref=REF):
 if ref!=REF:raise ValueError('Existing Paperlab project required')
 api.ROOT=ROOT;before=api.sql(ref,SNAPSHOT,True)[0]['frozen']
 for filename in ['046_dashboard_readiness.sql','047_research_retry.sql']:
  sql=(ROOT/'managed/sql'/filename).read_text();api.sql(ref,sql.rsplit('commit;',1)[0]+'rollback;');api.sql(ref,sql)
 assert before==api.sql(ref,SNAPSHOT,True)[0]['frozen']
 print(json.dumps({'owner_diagnostics':True,'provider_limits_unchanged':True,'existing_provider_pauses_unchanged':True,'financial_profiles_unchanged':True,'trading_rules_changed':False,'paid_services':False}))
if __name__=='__main__':configure(sys.argv[1]if len(sys.argv)>1 else REF)
