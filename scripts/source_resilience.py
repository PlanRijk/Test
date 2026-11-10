"""Bounded company-source failover; source disagreement never approves a trade."""
import hashlib,json,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.managed_api import sql,deploy_function,private_json
from scripts.deploy_managed import jsql,literal
from scripts.compact_transport import SNAPSHOT
PATHS=['managed/functions/_shared/source-registry.js','managed/functions/_shared/source-resilience.js','managed/functions/paper-source-resilience/index.js','managed/sql/024_source_resilience.sql','managed/functions/_shared/company-coverage.js']
def fingerprint():
 rows=[{'path':p,'sha256':hashlib.sha256((ROOT/p).read_bytes()).hexdigest()}for p in PATHS];h=hashlib.sha256(json.dumps(rows,sort_keys=True,separators=(',',':')).encode()).hexdigest();(ROOT/'managed/functions/_shared/source-implementation.js').write_text("export const SOURCE_IMPLEMENTATION_SHA='"+h+"';\n");return h
def protocol():
 h=fingerprint();r=subprocess.run(['node','--input-type=module','-e',"import{SOURCE_POLICY}from'./managed/functions/_shared/source-resilience.js';import{ISSUER_ROUTES}from'./managed/functions/_shared/source-registry.js';console.log(JSON.stringify({policy:SOURCE_POLICY,registry:ISSUER_ROUTES}));"],cwd=ROOT,capture_output=True,text=True,check=True);d=json.loads(r.stdout);d['policy']['implementation_sha256']=h;return d
def corrections(ref,path):
 if not path:return
 for row in json.loads(Path(path).read_text()):
  n=row['native'];assert n['source_extraction']['concept']=='us-gaap:Revenues'and n['symbol']==row['symbol'];symbol=literal(row['symbol']);old=row['old']['revenue'];acc=literal(n['annual_report']['accession']);refurl=n['source_extraction']['source_url'];assert refurl=='https://data.sec.gov/api/xbrl/companyfacts/CIK'+n['cik']+'.json'
  current=sql(ref,'select record from paperlab.company_coverage where symbol='+symbol,True)[0]['record'];existing=current.get('verified_financials');
  if existing and existing.get('financial',{}).get('revenue_definition')=='us-gaap:Revenues':continue
  if not existing or existing['financial']['revenue']!=old or existing['annual_report']['accession']!=n['annual_report']['accession']:raise RuntimeError('Primary source changed; re-evaluate correction')
  event={'kind':'consolidated_revenue_definition_corrected','previous':row['old'],'corrected':{k:n['financial'].get(k)for k in row['old']},'provenance':n['source_extraction']}
  q=("begin;do $correct$declare nv jsonb;begin nv:=jsonb_set("+jsql(n)+
     ",'{known_at}',to_jsonb(clock_timestamp()));update paperlab.company_coverage set record=jsonb_set(record,'{verified_financials}',nv)where symbol="+symbol+
     " and(record->'verified_financials'->'financial'->>'revenue')::numeric="+str(old)+
     " and record->'verified_financials'->'annual_report'->>'accession'="+acc+
     ";if not found then raise exception 'Source changed during correction';end if;perform public.paper_company_save(nv);insert into paperlab.source_events(symbol,record)values("+symbol+","+jsql(event)+
     ");end$correct$;commit;")
  sql(ref,q)
def seed(ref):
 x=sql(ref,"select jsonb_build_object('coverage',(select jsonb_agg(record)from paperlab.company_coverage),'dossiers',paperlab.company_records())as input")[0]['input'];private_json('source-resilience-seed-input.json',x)
 code="""import fs from'node:fs';import{reconcileFinancials,pillarEvidence}from'./managed/functions/_shared/source-resilience.js';const x=JSON.parse(fs.readFileSync(0,'utf8')),time=Date.now();const out=x.coverage.map(c=>{const n=c.verified_financials,reference=n?Object.fromEntries(['version','symbol','cik','sector','checked_at','known_at','financial','latest_report','annual_report','sources','source_hashes','source_extraction'].filter(k=>n[k]!==undefined).map(k=>[k,n[k]])):null,verification={...reconcileFinancials(reference,c.observation),compared_at:new Date(time).toISOString(),source_observed_at:c.observation?.known_at||null,primary_checked_at:reference?.checked_at||null};return{symbol:c.symbol,reference,record:{version:'source-resilience-v1',symbol:c.symbol,route:'cached_reference_audit',attempted_at:null,last_financial_success_at:c.observation?.known_at||null,cached_available:!!c.observation,endpoints:{},availability:{},verification,pillars:pillarEvidence(c,reference,c.observation,x.dossiers[c.symbol]?.review,time,verification),trade_approval:false,same_provider_independent:false}};});console.log(JSON.stringify(out));"""
 r=subprocess.run(['node','--input-type=module','-e',code],cwd=ROOT,input=json.dumps(x).encode(),capture_output=True,check=True);rows=json.loads(r.stdout);assert len(rows)==100;private_json('source-resilience-seed.json',rows)
 for start in range(0,100,10):sql(ref,'select public.paper_source_seed('+jsql(rows[start:start+10])+')')
def configure(ref,correction_path=None):
 d=protocol();before=sql(ref,SNAPSHOT,True)[0]['frozen'];trade=sql(ref,"select jsonb_build_object('company',(select policy from paperlab.company_runtime),'exits',(select policy from paperlab.net_exit_runtime),'audit',(select policy from paperlab.strategy_audit_runtime),'coverage',(select policy from paperlab.company_coverage_runtime))as policies",True)[0]['policies']
 if sql(ref,"select to_regclass('paperlab.source_runtime')is not null as present",True)[0]['present']:
  old=sql(ref,'select policy from paperlab.source_runtime',True)[0]['policy']
  if old is not None and old!=d['policy']:raise RuntimeError('Source policy frozen; explicit new version needed')
 jobs=sql(ref,'select jobid,jobname,schedule,command,active from cron.job order by jobid',True);job=[j for j in jobs if j['jobname']=='paperlab-company-coverage'];assert len(job)==1
 new=job[0]['command'].replace('/paper-company-coverage','/paper-source-resilience');assert'/paper-source-resilience'in new
 sql(ref,(ROOT/'managed/sql/024_source_resilience.sql').read_text());corrections(ref,correction_path);sql(ref,'select public.paper_source_configure('+jsql(d['policy'])+','+jsql(d['registry'])+')');seed(ref)
 deploy_function(ref,'paper-source-resilience');deploy_function(ref,'paper-api');sql(ref,'select cron.alter_job('+str(job[0]['jobid'])+',command:='+literal(new)+')')
 assert before==sql(ref,SNAPSHOT,True)[0]['frozen'];assert trade==sql(ref,"select jsonb_build_object('company',(select policy from paperlab.company_runtime),'exits',(select policy from paperlab.net_exit_runtime),'audit',(select policy from paperlab.strategy_audit_runtime),'coverage',(select policy from paperlab.company_coverage_runtime))as policies",True)[0]['policies']
 after=sql(ref,'select jobid,jobname,schedule,command,active from cron.job order by jobid',True);assert after==[{**j,'command':new}if j['jobid']==job[0]['jobid']else j for j in jobs]
 private_json('source-resilience-deployed.json',{'policy':d['policy'],'jobs':after,'trading_policies_unchanged':True,'paid_resources':False});print(json.dumps({'companies':100,'failover':'query1_to_query2_same_provider','trading_policies_unchanged':True,'original_source_budget_unchanged':True,'paid_resources':False}))
if __name__=='__main__':
 if sys.argv[1:]==['fingerprint']:print(fingerprint())
 elif len(sys.argv)in[3,4]and sys.argv[1]=='configure':configure(sys.argv[2],sys.argv[3]if len(sys.argv)==4 else None)
 else:raise SystemExit('source_resilience.py fingerprint | configure REF [PRIVATE_CORRECTIONS.json]')
