"""Offline persistence verification and one-time connection closure, synthetic key only."""
import base64,hashlib,json,sys,tempfile,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from scripts import gemini_recovery as g
from cryptography.hazmat.primitives import serialization,hashes
from cryptography.hazmat.primitives.asymmetric import padding
with tempfile.TemporaryDirectory()as folder:
 p=Path(folder);g.PRIVATE=p/'private.pem';g.PUBLIC=p/'public.json';cfg=g.generate();stamp=int(time.time()*1000);dummy='AIza'+'a'*35
 payload={'v':1,'k':cfg['kid'],'p':'gemini-api','iat':stamp,'exp':stamp+1800000,'t':dummy}
 key=serialization.load_pem_private_key(g.PRIVATE.read_bytes(),password=None)
 encrypted=key.public_key().encrypt(json.dumps(payload).encode(),padding.OAEP(mgf=padding.MGF1(hashes.SHA256()),algorithm=hashes.SHA256(),label=g.LABEL))
 envelope='PAPERLAB-GEMINI-CONNECT-1.'+cfg['kid']+'.'+base64.urlsafe_b64encode(encrypted).decode().rstrip('=');f=p/'message.txt';f.write_text(envelope)
 assert g.decode(envelope)['t']==dummy;events=[];good=False
 def request(provider,path,method='GET',body=None):
  assert provider=='supabase'and path=='/v1/projects/'+g.REF+'/secrets';events.append(method)
  if method=='POST':assert body==[{'name':'GEMINI_API_KEY','value':dummy}];return None
  return [{'name':'GEMINI_API_KEY','digest':hashlib.sha256(dummy.encode()).hexdigest()if good else'0'*64}]
 g.api.request=request
 try:g.accept(f);raise AssertionError('Unverified persistence accepted')
 except RuntimeError:pass
 assert g.PRIVATE.exists()and json.loads(g.PUBLIC.read_text())['enabled']is True
 good=True;result=g.accept(f);assert result['persistence_digest_verified']and not result['model_execution_enabled'];assert not g.PRIVATE.exists();assert json.loads(g.PUBLIC.read_text())['enabled']is False
 calls=len(events)
 try:g.accept(f);raise AssertionError('Closed connection reused')
 except RuntimeError:pass
 assert len(events)==calls
print('Gemini connection passed: digest verification required, failed save retains recovery, successful save closes connection, replay rejected, no model or billing calls.')
