"""Test Supabase's Alpaca secrets in place; never retrieve or copy their values."""
import json,sys,urllib.request,urllib.error
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts.managed_api import request,sql,deploy_function,private_json

def check(ref,deploy=False):
 names={s.get('name') for s in request('supabase','/v1/projects/'+ref+'/secrets')}
 present={n:n in names for n in ['ALPACA_API_KEY_ID','ALPACA_API_SECRET_KEY']}
 if not all(present.values()):return {'status':'missing_supabase_secrets','present':present}
 if deploy:deploy_function(ref,'paper-alpaca-check')
 token=sql(ref,"select decrypted_secret from vault.decrypted_secrets where name='paperlab_cron_token'")[0]['decrypted_secret']
 url='https://'+ref+'.supabase.co/functions/v1/paper-alpaca-check'
 try:
  urllib.request.urlopen(urllib.request.Request(url,method='POST',data=b'{}',headers={'Content-Type':'application/json'}),timeout=20)
  raise RuntimeError('Anonymous diagnostic request unexpectedly accepted')
 except urllib.error.HTTPError as e:
  if e.code!=401:raise RuntimeError('Unexpected anonymous diagnostic status '+str(e.code)) from None
 req=urllib.request.Request(url,method='POST',data=b'{}',headers={'Content-Type':'application/json','X-PaperLab-Cron':token})
 try:
  with urllib.request.urlopen(req,timeout=30)as r:out=json.load(r)
 except urllib.error.HTTPError as e:out=json.loads(e.read(64000))
 private_json('alpaca-connection-check.json',out)
 return out

if __name__=='__main__':
 if len(sys.argv)not in[2,3] or(len(sys.argv)==3 and sys.argv[2]!='--deploy'):raise SystemExit('Use check_alpaca.py PROJECT_REF [--deploy]')
 print(json.dumps(check(sys.argv[1],deploy='--deploy'in sys.argv),ensure_ascii=False))
