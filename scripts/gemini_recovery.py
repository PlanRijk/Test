"""One-time browser-encrypted Gemini connection; no model requests or billing changes.

The private key lives outside Git. Only a matching, unexpired envelope can set
GEMINI_API_KEY in the existing Supabase project's function secrets.
"""
import base64,hashlib,json,re,secrets,sys,time
from pathlib import Path
from cryptography.hazmat.primitives import hashes,serialization
from cryptography.hazmat.primitives.asymmetric import padding,rsa
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts import managed_api as api
PRIVATE=Path('/tmp/paperlab-gemini-connect/private-key.pem')
PUBLIC=ROOT/'managed/web/gemini-connect-key.json'
REF='kdyzlbknygeqinqduuic';LABEL=b'PaperLab Gemini Connection v1'
def generate():
 now=int(time.time()*1000)
 if PRIVATE.exists()and PUBLIC.exists():
  old=json.loads(PUBLIC.read_text())
  if old.get('enabled')is True and old.get('expires_at',0)>now:return old
 PRIVATE.parent.mkdir(mode=0o700,parents=True,exist_ok=True);PRIVATE.parent.chmod(0o700)
 key=rsa.generate_private_key(public_exponent=65537,key_size=4096)
 PRIVATE.touch(mode=0o600,exist_ok=True);PRIVATE.chmod(0o600)
 PRIVATE.write_bytes(key.private_bytes(serialization.Encoding.PEM,serialization.PrivateFormat.PKCS8,serialization.NoEncryption()))
 der=key.public_key().public_bytes(serialization.Encoding.DER,serialization.PublicFormat.SubjectPublicKeyInfo)
 config={'version':1,'enabled':True,'created_at':now,'expires_at':now+86400000,'kid':hashlib.sha256(der).hexdigest(),'spki':base64.b64encode(der).decode()}
 PUBLIC.write_text(json.dumps(config,separators=(',',':'))+'\n');return config
def decode(envelope,now=None):
 now=int(time.time()*1000)if now is None else now
 try:
  config=json.loads(PUBLIC.read_text());parts=envelope.strip().split('.')
  if len(parts)!=3 or parts[0]!='PAPERLAB-GEMINI-CONNECT-1'or parts[1]!=config['kid']or not re.fullmatch(r'[A-Za-z0-9_-]{683}',parts[2])or config.get('enabled')is not True or config['expires_at']<=now:raise ValueError()
  ciphertext=base64.b64decode(parts[2]+'=',altchars=b'-_',validate=True)
  if len(ciphertext)!=512 or base64.urlsafe_b64encode(ciphertext).decode().rstrip('=')!=parts[2]:raise ValueError()
  key=serialization.load_pem_private_key(PRIVATE.read_bytes(),password=None)
  d=json.loads(key.decrypt(ciphertext,padding.OAEP(mgf=padding.MGF1(hashes.SHA256()),algorithm=hashes.SHA256(),label=LABEL)))
  if d.get('v')!=1 or d.get('k')!=config['kid']or d.get('p')!='gemini-api'or not isinstance(d.get('iat'),int)or not isinstance(d.get('exp'),int)or d['iat']>now+60000 or d['iat']<config['created_at']-60000 or d['exp']-d['iat']!=1800000 or d['exp']<=now or not re.fullmatch(r'(?!rnd_|sbp_|sb_secret_)[A-Za-z0-9._~-]{20,200}',d.get('t','')):raise ValueError()
  return d
 except Exception:raise RuntimeError('Invalid, expired or mismatched encrypted Gemini message')from None
def accept(path):
 d=decode(Path(path).read_text());token=d['t']
 api.request('supabase','/v1/projects/'+REF+'/secrets','POST',[{'name':'GEMINI_API_KEY','value':token}])
 stored=api.request('supabase','/v1/projects/'+REF+'/secrets')
 row=next((x for x in stored if x.get('name')=='GEMINI_API_KEY'),{})
 if not secrets.compare_digest(row.get('digest',''),hashlib.sha256(token.encode()).hexdigest()):raise RuntimeError('Secret persistence could not be verified')
 config=json.loads(PUBLIC.read_text());config['enabled']=False;PUBLIC.write_text(json.dumps(config,separators=(',',':'))+'\n');PRIVATE.unlink()
 return {'stored':True,'location':'Supabase Edge Function secret GEMINI_API_KEY','project':REF,'persistence_digest_verified':True,'provider_key_validated':False,'model_execution_enabled':False,'billing_changed':False,'connection_closed_locally':True,'private_key_removed':True}
if __name__=='__main__':
 try:
  if sys.argv[1:]==['generate']:
   c=generate();print(json.dumps({'public_key_id':c['kid'],'expires_at_ms':c['expires_at'],'private_key_outside_repository':True}))
  elif len(sys.argv)==3 and sys.argv[1]=='accept':print(json.dumps(accept(sys.argv[2])))
  else:raise RuntimeError('Use generate | accept ENCRYPTED_FILE')
 except Exception:print(json.dumps({'status':'connection_failed','detail':'Message expired, unavailable or persistence not verified; no key values logged.'}));raise SystemExit(1)
