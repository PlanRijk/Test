"""Versioned net-profit policy for the active paper ledger; no capital reset."""
import hashlib,json,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.managed_api import sql,deploy_function,private_json
from scripts.deploy_managed import jsql,literal
from scripts.compact_transport import SNAPSHOT
PATHS=['managed/functions/_shared/net-exit-policy.js','managed/functions/_shared/engine-net-exits.js','managed/functions/_shared/capital-net-exits.js','managed/functions/paper-tick-net-exits/index.js','managed/sql/020_net_profit_exits.sql','managed/functions/_shared/engine.js','managed/functions/_shared/capital-study.js','managed/functions/_shared/learning-runtime.js','managed/functions/_shared/company-policy.js','managed/functions/_shared/company-analysis.js']
def fingerprint():
 manifest=[{'path':p,'sha256':hashlib.sha256((ROOT/p).read_bytes()).hexdigest()}for p in PATHS]
 h=hashlib.sha256(json.dumps(manifest,sort_keys=True,separators=(',',':')).encode()).hexdigest();(ROOT/'managed/functions/_shared/net-exit-implementation.js').write_text("export const NET_EXIT_IMPLEMENTATION_SHA='"+h+"';\n");return h
def protocol():
 h=fingerprint();r=subprocess.run(['node','--input-type=module','-e',"import{NET_EXIT_POLICY}from'./managed/functions/_shared/net-exit-policy.js';import{COMPANY_IMPLEMENTATION_SHA}from'./managed/functions/_shared/company-implementation.js';console.log(JSON.stringify({...NET_EXIT_POLICY,company_implementation_sha256:COMPANY_IMPLEMENTATION_SHA}));"],cwd=ROOT,capture_output=True,text=True,check=True)
 return{**json.loads(r.stdout),'implementation_sha256':h}
def configure(ref):
 p=protocol();before=sql(ref,SNAPSHOT,True)[0]['frozen'];company=sql(ref,'select profile,policy from paperlab.company_runtime',True)
 jobs=sql(ref,'select jobid,jobname,schedule,command,active from cron.job order by jobid',True);tick=[j for j in jobs if j['jobname']=='paperlab-tick'];assert len(tick)==1 and tick[0]['schedule']=='*/5 7-20 * * 1-5'
 existing=sql(ref,"select to_regclass('paperlab.net_exit_runtime')is not null as present",True)[0]['present']
 if existing:
  old=sql(ref,'select policy from paperlab.net_exit_runtime',True)[0]['policy']
  if old is not None and old!=p:raise RuntimeError('Net exit policy frozen; use a new explicit epoch')
 new=tick[0]['command'].replace('/paper-tick-company','/paper-tick-net-exits');assert'/paper-tick-net-exits'in new
 sql(ref,(ROOT/'managed/sql/020_net_profit_exits.sql').read_text())
 deploy_function(ref,'paper-tick-net-exits');deploy_function(ref,'paper-api')
 result=sql(ref,'begin;select public.paper_net_exit_configure('+jsql(p)+')as profile;select cron.alter_job('+str(tick[0]['jobid'])+',command:='+literal(new)+');commit;')
 assert before==sql(ref,SNAPSHOT,True)[0]['frozen'];assert company==sql(ref,'select profile,policy from paperlab.company_runtime',True)
 after=sql(ref,'select jobid,jobname,schedule,command,active from cron.job order by jobid',True);assert after==[{**j,'command':new}if j['jobid']==tick[0]['jobid']else j for j in jobs]
 live=sql(ref,'select profile,policy,started_at,baseline from paperlab.net_exit_runtime',True)[0];private_json('net-profit-exits-deployed.json',{'runtime':live,'frozen_unchanged':True,'paid_resources':False,'jobs':after})
 print(json.dumps({'profile':live['profile'],'minimum_net_eur':10,'minimum_net_fraction':.025,'minimum_net_reward_risk':1.5,'carried_positions':live['baseline']['carried_positions'],'balance_reset':False,'paid_resources':False}))
if __name__=='__main__':
 if sys.argv[1:]==['fingerprint']:print(fingerprint())
 elif len(sys.argv)==3 and sys.argv[1]=='configure':configure(sys.argv[2])
 else:raise SystemExit('net_profit_exits.py fingerprint | configure REF')
