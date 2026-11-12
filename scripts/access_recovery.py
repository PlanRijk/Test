"""Explicit credential recovery: private key and decrypted token never enter Git.

Only an encrypted envelope is accepted as input. Successful credentials go to
the owner's existing unlinked Render group, not browser assets or local files.
"""
import base64,hashlib,json,re,runpy,secrets,subprocess,sys,time,urllib.request,urllib.error
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts import managed_api as api
PRIVATE=Path('/tmp/paperlab-supabase-recovery/private-key.pem')
PUBLIC=ROOT/'managed/web/access-recovery-key.json'
GROUP='evg-dbqnsnbtqb8s739tmpvg';OWNER='tea-dbkv4j15efls73fp2uhg';REF='kdyzlbknygeqinqduuic'
LABEL=b'PaperLab Supabase Recovery v1'
class NoCredentialRedirect(urllib.request.HTTPRedirectHandler):
 def redirect_request(self,req,fp,code,msg,headers,newurl):return None

def generate():
 now=int(time.time()*1000)
 if PRIVATE.exists()and PUBLIC.exists():
  old=json.loads(PUBLIC.read_text())
  if old.get('enabled')is True and old.get('expires_at',0)>now:return old
 PRIVATE.parent.mkdir(mode=0o700,parents=True,exist_ok=True);PRIVATE.parent.chmod(0o700)
 PRIVATE.touch(mode=0o600,exist_ok=True);PRIVATE.chmod(0o600)
 subprocess.run(['openssl','genpkey','-algorithm','RSA','-pkeyopt','rsa_keygen_bits:4096','-out',str(PRIVATE)],capture_output=True,check=True)
 der=subprocess.run(['openssl','pkey','-in',str(PRIVATE),'-pubout','-outform','DER'],capture_output=True,check=True).stdout
 config={'version':1,'enabled':True,'created_at':now,'expires_at':now+86400000,'kid':hashlib.sha256(der).hexdigest(),'spki':base64.b64encode(der).decode()}
 PUBLIC.write_text(json.dumps(config,separators=(',',':'))+'\n');return config

def decode(envelope,now=None):
 now=int(time.time()*1000)if now is None else now
 try:
  config=json.loads(PUBLIC.read_text());parts=envelope.strip().split('.')
  if len(parts)!=3 or parts[0]!='PAPERLAB-RECOVERY-1'or parts[1]!=config['kid']or not re.fullmatch(r'[A-Za-z0-9_-]{683}',parts[2])or config.get('enabled')is not True or config['expires_at']<=now:raise ValueError()
  ciphertext=base64.b64decode(parts[2]+'=',altchars=b'-_',validate=True)
  if len(ciphertext)!=512 or base64.urlsafe_b64encode(ciphertext).decode().rstrip('=')!=parts[2]:raise ValueError()
  r=subprocess.run(['openssl','pkeyutl','-decrypt','-inkey',str(PRIVATE),'-pkeyopt','rsa_padding_mode:oaep','-pkeyopt','rsa_oaep_md:sha256','-pkeyopt','rsa_mgf1_md:sha256','-pkeyopt','rsa_oaep_label:'+LABEL.hex()],input=ciphertext,capture_output=True)
  if r.returncode:raise ValueError()
  d=json.loads(r.stdout)
  if d.get('v')!=1 or d.get('k')!=config['kid']or d.get('p')!='supabase-management'or not isinstance(d.get('iat'),int)or not isinstance(d.get('exp'),int)or d['iat']>now+60000 or d['iat']<config['created_at']-60000 or d['exp']-d['iat']!=1800000 or d['exp']<=now or not re.fullmatch(r'sbp_[A-Za-z0-9_-]{20,180}',d.get('t','')):raise ValueError()
  return d
 except Exception:raise RuntimeError('Encrypted recovery message is invalid, expired, or has no matching private key')from None

def token_client(token):
 opener=urllib.request.build_opener(NoCredentialRedirect())
 def call(path,method='GET',body=None,content_type='application/json',timeout=90):
  if not isinstance(path,str)or not path.startswith('/v1/')or'://'in path or'\r'in path or'\n'in path:raise RuntimeError('Invalid management API path')
  data=json.dumps(body).encode()if body is not None and not isinstance(body,bytes)else body
  req=urllib.request.Request('https://api.supabase.com'+path,data=data,method=method,headers={'Authorization':'Bearer '+token,'Content-Type':content_type,'Accept':'application/json'})
  try:
   with opener.open(req,timeout=timeout)as r:raw=r.read(16*1024*1024)
   return json.loads(raw)if raw else None
  except urllib.error.HTTPError as e:raise api.ApiError('supabase',e.code,'Response details withheld to protect credentials.')from None
 return call

def recovery_group():
 d=api.request('render','/v1/env-groups/'+GROUP)
 if d.get('ownerId')!=OWNER or d.get('name')!='paperlab-beheer'or d.get('serviceLinks')!=[]:raise RuntimeError('Expected unlinked private recovery group')
 return d

def accept(path):
 d=decode(Path(path).read_text());token=d['t'];call=token_client(token)
 proof=call('/v1/projects/'+REF+'/database/query/read-only','POST',{'query':'select now()as checked_at'})
 recovery_group();api.request('render','/v1/env-groups/'+GROUP+'/env-vars/SUPABASE_ACCESS_TOKEN','PUT',{'value':token})
 stored=api.request('render','/v1/env-groups/'+GROUP+'/env-vars/SUPABASE_ACCESS_TOKEN')
 if not secrets.compare_digest(stored.get('value',''),token):raise RuntimeError('Credential storage could not be verified')
 config=json.loads(PUBLIC.read_text());config['enabled']=False;PUBLIC.write_text(json.dumps(config,separators=(',',':'))+'\n');PRIVATE.unlink()
 result={'restored':True,'checked_at':proof[0]['checked_at'],'credential_location':'unlinked Render recovery group','group_id':GROUP,'private_key_removed':True}
 api.private_json('access-recovery-result.json',result);return result

def run(target,args):
 d=recovery_group();rows=[v for v in d.get('envVars',[])if v.get('key')=='SUPABASE_ACCESS_TOKEN']
 if len(rows)!=1 or not rows[0].get('value'):raise RuntimeError('Recovery group has no token value')
 call=token_client(rows[0]['value'].strip());original=api.request
 def explicit(provider,path,method='GET',body=None,content_type='application/json',timeout=90):
  return call(path,method,body,content_type,timeout)if provider=='supabase'else original(provider,path,method,body,content_type,timeout)
 file=(ROOT/target).resolve()
 if file.parent!=ROOT/'scripts'or file.suffix!='.py'or not file.is_file():raise RuntimeError('Expected an existing project management script')
 previous_args=sys.argv;api.request=explicit;sys.argv=[str(file),*args]
 try:runpy.run_path(str(file),run_name='__main__')
 finally:api.request=original;sys.argv=previous_args

if __name__=='__main__':
 try:
  if sys.argv[1:]==['generate']:
   c=generate();print(json.dumps({'public_key_id':c['kid'],'expires_at_ms':c['expires_at'],'private_key_saved_outside_repository':True}))
  elif len(sys.argv)==3 and sys.argv[1]=='accept':print(json.dumps(accept(sys.argv[2])))
  elif len(sys.argv)>=3 and sys.argv[1]=='run':run(sys.argv[2],sys.argv[3:])
  else:raise RuntimeError('Use generate | accept ENCRYPTED_FILE | run scripts/NAME.py [ARGS]')
 except api.ApiError as e:print(json.dumps({'status':'access_failed','provider_status':e.status}));raise SystemExit(1)
 except Exception:print(json.dumps({'status':'recovery_failed','detail':'Input, key, or recovery configuration unavailable; no credential values logged.'}));raise SystemExit(1)
