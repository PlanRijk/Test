"""Inspect/decrypt a downloaded archive offline. Never restores production.

Keep the 64-character PAPERLAB_ARCHIVE_KEY in a private key file outside Git.
--extract-to writes the original JSON text, not a reserialized numeric payload.
"""
import argparse,base64,gzip,io,json,os,secrets,subprocess
from pathlib import Path
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
LABEL=b'PaperLab private archive v1'
def decrypt(data,key):
 if len(data)>15000000:raise ValueError('Encrypted archive bound')
 x=json.loads(data)
 if x.get('v')!=1 or x.get('algorithm')!='AES-256-GCM'or x.get('compression')!='gzip'or x.get('aad')!=LABEL.decode():raise ValueError('Unsupported archive')
 zipped=AESGCM(bytes.fromhex(key.strip())).decrypt(base64.b64decode(x['nonce'],validate=True),base64.b64decode(x['ciphertext'],validate=True),LABEL)
 with gzip.GzipFile(fileobj=io.BytesIO(zipped))as r:raw=r.read(30000001)
 if len(raw)>30000000:raise ValueError('Decrypted archive bound')
 return raw
def rehearse(snapshot,container):
 env={k:v for k,v in os.environ.items()if k not in ['DOCKER_HOST','DOCKER_CONTEXT','DOCKER_TLS','DOCKER_TLS_VERIFY','DOCKER_CERT_PATH']}
 docker=['docker','--host=unix:///var/run/docker.sock'];metadata=json.loads(subprocess.check_output(docker+['inspect',container],env=env))[0]
 if metadata['HostConfig']['NetworkMode']!='none':raise RuntimeError('Rehearsal requires a network-disabled local container')
 cmd=docker+['exec','-i',container,'psql','-U','postgres','-v','ON_ERROR_STOP=1','-At'];name='archive_'+secrets.token_hex(4)
 def q(sql,db=None):
  result=subprocess.run(cmd+(['-d',db]if db else[]),input=sql.encode(),capture_output=True,env=env,check=True);return result.stdout.decode().strip()
 q('create database '+name)
 try:
  q('create table restored(name text primary key,records jsonb not null)',name)
  for table,rows in snapshot['tables'].items():q("insert into restored values('"+table.replace("'","''")+"','"+json.dumps(rows).replace("'","''")+"'::jsonb)",name)
  counts=json.loads(q('select jsonb_object_agg(name,jsonb_array_length(records))from restored',name));assert counts=={k:len(v)for k,v in snapshot['tables'].items()}
  for table in ['capital_runtime','capital_trades','portfolio','trades','history_models']:
   if table in snapshot['tables']:assert json.loads(q("select records from restored where name='"+table+"'",name))==snapshot['tables'][table]
  return{'tables':len(counts),'records':sum(counts.values()),'selected_financial_payloads_equal':True,'full_schema_or_auth_restore':False}
 finally:q('drop database '+name)
def main():
 p=argparse.ArgumentParser();p.add_argument('archive');p.add_argument('--key-file',required=True);p.add_argument('--extract-to');p.add_argument('--rehearse-local');a=p.parse_args();raw=decrypt(Path(a.archive).read_bytes(),Path(a.key_file).read_text());d=json.loads(raw)
 result={'version':d.get('version'),'decrypted_integrity_verified':True,'tables':len(d.get('tables',{})),'companies':len(d.get('companies',[]))}
 if a.rehearse_local:result['offline_rehearsal']=rehearse(d,a.rehearse_local)
 if a.extract_to:
  fd=os.open(a.extract_to,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
  with os.fdopen(fd,'wb')as f:f.write(raw)
 print(json.dumps(result))
if __name__=='__main__':main()
