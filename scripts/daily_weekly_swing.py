"""Version and activate only the new prospective PAPER execution epoch."""
import hashlib,json,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts import managed_api as api
from scripts.deploy_managed import jsql,literal
from scripts.compact_transport import SNAPSHOT
PATHS=['managed/functions/_shared/'+n for n in ['swing-rules.js','swing-fill.js','engine-swing.js','capital-swing.js','engine.js','capital-study.js','company-analysis.js','net-exit-policy.js','learning-runtime.js']]+['managed/functions/paper-tick-swing/index.js','managed/sql/032_daily_weekly_swing.sql']
def fingerprint():
 manifest=[{'path':p,'sha256':hashlib.sha256((ROOT/p).read_bytes()).hexdigest()}for p in PATHS];h=hashlib.sha256(json.dumps(manifest,sort_keys=True,separators=(',',':')).encode()).hexdigest();(ROOT/'managed/functions/_shared/swing-implementation.js').write_text("export const SWING_IMPLEMENTATION_SHA='"+h+"';\n");return h
def protocol():
 h=fingerprint();r=subprocess.run(['node','--input-type=module','-e',"import{SWING_POLICY}from'./managed/functions/_shared/swing-rules.js';console.log(JSON.stringify(SWING_POLICY));"],cwd=ROOT,capture_output=True,text=True,check=True);return{**json.loads(r.stdout),'implementation_sha256':h}
def configure(ref):
 p=protocol();api.ROOT=ROOT;before=api.sql(ref,SNAPSHOT,True)[0]['frozen'];jobs=api.sql(ref,'select jobid,jobname,schedule,command,active from cron.job order by jobid',True);tick=[j for j in jobs if j['jobname']=='paperlab-tick'];assert len(tick)==1 and tick[0]['schedule']=='*/5 7-20 * * 1-5'
 new=tick[0]['command'].replace('/paper-tick-audited','/paper-tick-swing');assert '/paper-tick-swing'in new
 prior=api.sql(ref,"select to_regclass('paperlab.swing_runtime')is not null as present",True)[0]['present']
 if prior:
  stored=api.sql(ref,'select policy from paperlab.swing_runtime',True)[0]['policy']
  if stored is not None and stored!=p:raise RuntimeError('Existing swing epoch frozen; create a new explicit epoch')
 api.sql(ref,(ROOT/'managed/sql/029_private_archives.sql').read_text());api.sql(ref,(ROOT/'managed/sql/032_daily_weekly_swing.sql').read_text());api.deploy_function(ref,'paper-tick-swing')
 # Same transaction: invalidate outstanding leases, preserve lots and enable route.
 api.sql(ref,"""begin;do $check$declare b jsonb;n bigint;begin
 select state into b from paperlab.capital_runtime where singleton for update;select count(*)into n from paperlab.capital_trades;
 perform public.paper_swing_configure("""+jsql(p)+""");
 if(b-'pending')is distinct from(select state-'pending'from paperlab.capital_runtime)or n<>(select count(*)from paperlab.capital_trades)then raise exception'Transition changed financial state';end if;
 end$check$;select cron.alter_job("""+str(tick[0]['jobid'])+',command:='+literal(new)+');commit;')
 api.deploy_function(ref,'paper-api')
 assert before==api.sql(ref,SNAPSHOT,True)[0]['frozen'];after=api.sql(ref,'select jobid,jobname,schedule,command,active from cron.job order by jobid',True);assert after==[{**j,'command':new}if j['jobid']==tick[0]['jobid']else j for j in jobs]
 print(json.dumps({'paper_epoch':p['version'],'profile':api.sql(ref,'select profile from paperlab.swing_runtime',True)[0]['profile'],'frozen_studies_unchanged':True,'same_job_schedule':True,'real_orders':False,'paid_services':False}))
if __name__=='__main__':
 if sys.argv[1:]==['fingerprint']:print(fingerprint())
 elif len(sys.argv)==3 and sys.argv[1]=='configure':configure(sys.argv[2])
 else:raise SystemExit('daily_weekly_swing.py fingerprint | configure REF')
