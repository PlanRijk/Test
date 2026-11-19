"""Verify (default) or rehydrate one private lossless cold-source archive.
Usage: restore_cold_source.py REF DOCUMENT_SHA [--restore]
No plaintext, keys or service tokens are logged.
"""
import base64,gzip,hashlib,io,json,re,sys,urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts import managed_api as api
from scripts.project_followup import archive_key,LABEL,BUCKET
from scripts.deploy_managed import literal

def restore(ref,doc_id,write=False):
 from cryptography.hazmat.primitives.ciphers.aead import AESGCM
 if ref!='kdyzlbknygeqinqduuic'or not re.fullmatch('[a-f0-9]{64}',doc_id):raise RuntimeError('Existing project and exact document ID required')
 rows=api.sql(ref,'select id,url,sha256,body_sha256,archive_object_path from paperlab.deep_documents where id='+literal(doc_id),True)
 if len(rows)!=1:raise RuntimeError('Document not found')
 d=rows[0];path='sources/cold-'+doc_id+'.json.enc'
 if d['archive_object_path']!=path:raise RuntimeError('No matching cold archive')
 key=bytes.fromhex(archive_key());service=api.keys(ref)['service_role']
 class NoRedirect(urllib.request.HTTPRedirectHandler):
  def redirect_request(self,*args):return None
 request=urllib.request.Request('https://'+ref+'.supabase.co/storage/v1/object/'+BUCKET+'/'+path,headers={'apikey':service,'Authorization':'Bearer '+service})
 with urllib.request.build_opener(NoRedirect()).open(request,timeout=30)as response:raw=response.read(15000001)
 if len(raw)>15000000:raise RuntimeError('Archive bound')
 envelope=json.loads(raw)
 if envelope.get('v')!=1 or envelope.get('algorithm')!='AES-256-GCM'or envelope.get('compression')!='gzip'or envelope.get('aad')!=LABEL.decode():raise RuntimeError('Archive format')
 packed=AESGCM(key).decrypt(base64.b64decode(envelope['nonce']),base64.b64decode(envelope['ciphertext']),LABEL)
 with gzip.GzipFile(fileobj=io.BytesIO(packed))as zipped:plain=zipped.read(30000001)
 if len(plain)>30000000:raise RuntimeError('Decoded bound')
 source=json.loads(plain);body=source.get('body','')
 if source.get('version')!='paperlab-cold-source-v1'or source.get('id')!=doc_id or source.get('url')!=d['url']or source.get('source_sha256')!=d['sha256']or source.get('body_sha256')!=d['body_sha256']or hashlib.sha256(body.encode()).hexdigest()!=d['body_sha256']:raise RuntimeError('Source identity or hash mismatch')
 if write:
  result=api.sql(ref,'update paperlab.deep_documents set body='+literal(body)+" where not active and body=''and id="+literal(doc_id)+'and body_sha256='+literal(d['body_sha256'])+' returning id')
  if len(result)!=1:raise RuntimeError('Inactive empty cache required; nothing restored')
 print(json.dumps({'document':doc_id,'verified':True,'restored_to_database':write,'plaintext_bytes':len(body.encode()),'archive_bytes':len(raw)}))
if __name__=='__main__':restore(sys.argv[1],sys.argv[2],len(sys.argv)==4 and sys.argv[3]=='--restore')
