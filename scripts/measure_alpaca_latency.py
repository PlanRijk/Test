"""Bounded opening-session study; server secrets stay in Supabase, raw data local/private."""
import datetime,json,sys,time,urllib.request,urllib.error
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.managed_api import sql

def measure(ref,samples=12,interval=60):
 if not 1<=samples<=12 or interval<60:raise ValueError('At most twelve rounds, at least sixty seconds apart')
 token=sql(ref,"select decrypted_secret from vault.decrypted_secrets where name='paperlab_cron_token'")[0]['decrypted_secret']
 path=ROOT/'.data/managed/alpaca-opening-2026-11-09.jsonl';path.parent.mkdir(exist_ok=True,parents=True)
 path.touch(mode=0o600,exist_ok=True);path.chmod(0o600)
 for i in range(samples):
  started=time.monotonic();when=datetime.datetime.now(datetime.timezone.utc).isoformat()
  req=urllib.request.Request('https://'+ref+'.supabase.co/functions/v1/paper-alpaca-latency',method='POST',data=b'{}',headers={'Content-Type':'application/json','X-PaperLab-Cron':token})
  try:
   with urllib.request.urlopen(req,timeout=35)as r:out=json.load(r)
  except urllib.error.HTTPError as e:out={'status':'function_http_error','http_status':e.code}
  except Exception:out={'status':'caller_connection_error'}
  out.update(sample=i+1,client_started_at=when,client_roundtrip_ms=round((time.monotonic()-started)*1000,2))
  with path.open('a')as f:f.write(json.dumps(out,separators=(',',':'))+'\n')
  print(json.dumps({k:v for k,v in out.items()if k not in ['rows']},ensure_ascii=False),flush=True)
  if i+1<samples:
   deadline=started+interval
   while time.monotonic()<deadline:time.sleep(min(1,deadline-time.monotonic()))
 return path
if __name__=='__main__':
 if len(sys.argv)!=2:raise SystemExit('Use measure_alpaca_latency.py PROJECT_REF')
 measure(sys.argv[1])
