"""Install an isolated bounded IEX research phase; never initialize or mutate portfolios."""
import hashlib,json,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.managed_api import sql,request,deploy_function,private_json
from scripts.deploy_managed import jsql,literal
from scripts.compact_transport import SNAPSHOT

def fingerprint():
 paths=['managed/functions/_shared/iex-study.js','managed/functions/_shared/catalogue.js','managed/functions/paper-iex-research/index.js','managed/sql/014_iex_research.sql']
 manifest=[{'path':p,'sha256':hashlib.sha256((ROOT/p).read_bytes()).hexdigest()}for p in paths]
 value=hashlib.sha256(json.dumps(manifest,sort_keys=True,separators=(',',':')).encode()).hexdigest()
 (ROOT/'managed/functions/_shared/iex-implementation.js').write_text("export const IEX_IMPLEMENTATION_SHA = '"+value+"';\n")
 return value

def policy():
 r=subprocess.run(['node','--input-type=module','-e',"import{IEX_POLICY}from'./managed/functions/_shared/iex-study.js';console.log(JSON.stringify(IEX_POLICY));"],cwd=ROOT,capture_output=True,text=True,check=True)
 return {**json.loads(r.stdout),'implementation_sha256':fingerprint()}

def configure(ref):
 names={s.get('name')for s in request('supabase','/v1/projects/'+ref+'/secrets')}
 if not{'ALPACA_API_KEY_ID','ALPACA_API_SECRET_KEY'}<=names:raise RuntimeError('Missing Alpaca server secrets')
 before=sql(ref,SNAPSHOT,True)[0]['frozen'];private_json('iex-study-frozen-before.json',before)
 p=policy()
 exists=sql(ref,"select to_regclass('paperlab.iex_runtime')is not null as present",True)[0]['present']
 if exists:
  old=sql(ref,'select policy from paperlab.iex_runtime',True)[0]['policy']
  if old and old!=p:raise RuntimeError('IEX research phase is frozen; no silent protocol update')
 sql(ref,(ROOT/'managed/sql/014_iex_research.sql').read_text())
 fp=sql(ref,'select public.paper_iex_configure('+jsql(p)+')as profile')[0]['profile']
 deploy_function(ref,'paper-iex-research');deploy_function(ref,'paper-api')
 command="select net.http_post(url:="+literal('https://'+ref+'.supabase.co/functions/v1/paper-iex-research')+",headers:=jsonb_build_object('Content-Type','application/json','X-PaperLab-Cron',(select decrypted_secret from vault.decrypted_secrets where name='paperlab_cron_token')),body:='{}'::jsonb,timeout_milliseconds:=20000) where exists(select 1 from paperlab.iex_runtime where singleton and enabled and now()<run_until and extract(isodow from now()at time zone'America/New_York')<=5 and(now()at time zone'America/New_York')::time>=time'09:30'and(now()at time zone'America/New_York')::time<time'16:00');"
 sql(ref,"select cron.schedule('paperlab-iex-research','* 13-21 * * 1-5',"+literal(command)+')')
 after=sql(ref,SNAPSHOT,True)[0]['frozen'];assert before==after,'Existing policy changed'
 private_json('iex-study-deployed.json',{'profile':fp,'policy':p,'frozen_unchanged':True,'orders':False,'automatic_training':False,'new_jobs':1})
 print(json.dumps({'profile':fp,'frozen_unchanged':True,'research_minutes':1,'companies':53,'study_days':14,'new_jobs':1,'paid_resources':False}))
if __name__=='__main__':
 if sys.argv[1:]==['fingerprint']:print(fingerprint())
 elif len(sys.argv)==3 and sys.argv[1]=='configure':configure(sys.argv[2])
 else:raise SystemExit('Use iex_study.py fingerprint | configure REF')
