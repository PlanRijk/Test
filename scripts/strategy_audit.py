"""Install prospective entry safety checks, retaining the frozen exit policy."""
import hashlib,json,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.managed_api import sql,deploy_function,private_json
from scripts.deploy_managed import jsql,literal
from scripts.compact_transport import SNAPSHOT
PATHS=['managed/functions/_shared/strategy-entry-audit.js','managed/functions/paper-tick-audited/index.js','managed/sql/021_strategy_audit.sql','managed/functions/_shared/capital-net-exits.js','managed/functions/_shared/net-exit-policy.js','managed/functions/_shared/net-exit-implementation.js','managed/functions/_shared/company-analysis.js','managed/functions/_shared/engine.js','managed/functions/_shared/capital-study.js']
def fingerprint():
 manifest=[{'path':p,'sha256':hashlib.sha256((ROOT/p).read_bytes()).hexdigest()}for p in PATHS];h=hashlib.sha256(json.dumps(manifest,sort_keys=True,separators=(',',':')).encode()).hexdigest();(ROOT/'managed/functions/_shared/strategy-audit-implementation.js').write_text("export const AUDIT_IMPLEMENTATION_SHA='"+h+"';\n");return h
def protocol():
 h=fingerprint();r=subprocess.run(['node','--input-type=module','-e',"import{AUDIT_POLICY}from'./managed/functions/_shared/strategy-entry-audit.js';import{NET_EXIT_IMPLEMENTATION_SHA}from'./managed/functions/_shared/net-exit-implementation.js';console.log(JSON.stringify({...AUDIT_POLICY,net_exit_implementation_sha256:NET_EXIT_IMPLEMENTATION_SHA}));"],cwd=ROOT,capture_output=True,text=True,check=True);return{**json.loads(r.stdout),'implementation_sha256':h}
def configure(ref):
 p=protocol();before=sql(ref,SNAPSHOT,True)[0]['frozen'];old=sql(ref,'select profile,policy from paperlab.net_exit_runtime',True)
 jobs=sql(ref,'select jobid,jobname,schedule,command,active from cron.job order by jobid',True);tick=[j for j in jobs if j['jobname']=='paperlab-tick'];assert len(tick)==1 and tick[0]['schedule']=='*/5 7-20 * * 1-5'
 if sql(ref,"select to_regclass('paperlab.strategy_audit_runtime')is not null as present",True)[0]['present']:
  prior=sql(ref,'select policy from paperlab.strategy_audit_runtime',True)[0]['policy']
  if prior is not None and prior!=p:raise RuntimeError('Audit policy frozen; use a new explicit epoch')
 new=tick[0]['command'].replace('/paper-tick-net-exits','/paper-tick-audited');assert'/paper-tick-audited'in new
 sql(ref,(ROOT/'managed/sql/022_history_transport_precision.sql').read_text());sql(ref,(ROOT/'managed/sql/021_strategy_audit.sql').read_text());sql(ref,(ROOT/'managed/sql/023_exit_audit.sql').read_text());deploy_function(ref,'paper-tick-audited');deploy_function(ref,'paper-api')
 sql(ref,'begin;select public.paper_strategy_audit_configure('+jsql(p)+');select cron.alter_job('+str(tick[0]['jobid'])+',command:='+literal(new)+');commit;')
 assert before==sql(ref,SNAPSHOT,True)[0]['frozen'];assert old==sql(ref,'select profile,policy from paperlab.net_exit_runtime',True)
 after=sql(ref,'select jobid,jobname,schedule,command,active from cron.job order by jobid',True);assert after==[{**j,'command':new}if j['jobid']==tick[0]['jobid']else j for j in jobs]
 live=sql(ref,'select profile,policy,started_at,baseline from paperlab.strategy_audit_runtime',True)[0];private_json('strategy-audit-deployed.json',{'runtime':live,'exit_policy_unchanged':True,'frozen_unchanged':True,'jobs':after,'paid_resources':False});print(json.dumps({'profile':live['profile'],'entry_cost_ceiling_percent':1.5,'reentry_hours':24,'max_new_estimated_stop_loss_eur':20,'max_total_estimated_stop_loss_eur':150,'carried_positions':live['baseline']['carried_positions'],'exit_policy_unchanged':True,'paid_resources':False}))
if __name__=='__main__':
 if sys.argv[1:]==['fingerprint']:print(fingerprint())
 elif len(sys.argv)==3 and sys.argv[1]=='configure':configure(sys.argv[2])
 else:raise SystemExit('strategy_audit.py fingerprint | configure REF')
