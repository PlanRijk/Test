"""Three-minute diagnostic focus. No orders; keys remain on Supabase."""
import datetime,json,sys,time,urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.managed_api import sql,private_json
FOCUS=['TM','ICE','AMT','CME','AAPL','MSFT']
POLICY={'version':'iex-focus-v1','symbols':FOCUS,'samples':18,'interval_seconds':10,'maximum_quote_age_seconds':60,'maximum_entry_spread_bps':25,'hypothetical_budget_eur':500,'orders':False,'automatic_training':False,'interpretation':'Exploratory three-minute quote study; no predictive signal, no optimized exit, no broker execution.'}
def run(ref):
 # An additional conservative allowance for this bounded manual investigation.
 rows=sql(ref,"update paperlab.free_usage set estimated_worker_egress_bytes=estimated_worker_egress_bytes+2000000 where month=date_trunc('month',now())::date and estimated_worker_egress_bytes+2000000<least(max_worker_egress_bytes,1050000000) returning month")
 if not rows:raise RuntimeError('No free research allowance remains; focus study not started')
 config=sql(ref,"select jsonb_build_object('usd_per_eur',state->'usd_per_eur','multi_market',jsonb_build_object('cost_assumptions',state->'multi_market'->'cost_assumptions'),'belgian_tax',jsonb_build_object('enabled',state->'belgian_tax'->'enabled','config',state->'belgian_tax'->'config'))as config from paperlab.portfolio",True)[0]['config']
 private_json('iex-focus-config.json',config);private_json('iex-focus-policy.json',POLICY)
 token=sql(ref,"select decrypted_secret from vault.decrypted_secrets where name='paperlab_cron_token'")[0]['decrypted_secret'];samples=[]
 for i in range(18):
  begin=time.monotonic();req=urllib.request.Request('https://'+ref+'.supabase.co/functions/v1/paper-alpaca-latency',method='POST',data=b'{}',headers={'Content-Type':'application/json','X-PaperLab-Cron':token})
  try:
   with urllib.request.urlopen(req,timeout=20)as response:r=json.load(response)
   rows=[q for q in r.get('rows',[])if q['symbol']in FOCUS];snapshot={'checked_at':r.get('checked_at'),'status':r.get('status'),'rows':rows}
  except Exception:snapshot={'checked_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'status':'unavailable','rows':[]}
  samples.append(snapshot);private_json('iex-focus-samples.json',{'policy':POLICY,'samples':samples})
  print(json.dumps({'sample':i+1,'at':snapshot['checked_at'],'focus_rows':len(snapshot['rows']),'status':snapshot['status']}),flush=True)
  if i<17:
   deadline=begin+10
   while time.monotonic()<deadline:time.sleep(min(1,deadline-time.monotonic()))
if __name__=='__main__':
 if len(sys.argv)!=2:raise SystemExit('Use focus_iex.py PROJECT_REF')
 run(sys.argv[1])
