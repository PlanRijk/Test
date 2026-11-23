"""Offline authenticated multipart assembly, including tamper/reorder rejection."""
import json,hashlib,gzip,base64,secrets,importlib.util
from pathlib import Path
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
root=Path(__file__).resolve().parents[2];spec=importlib.util.spec_from_file_location('archive',root/'scripts/inspect_archive.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
key='12'*32;raw=json.dumps({'tables':{'capital_trades':[{'pnl':-1.23456789012345}],'unicode':'Ω bewijs'}},ensure_ascii=False).encode();text=raw.decode();cut=len(text)//2;pieces=[text[:cut],text[cut:]];hash=hashlib.sha256(raw).hexdigest()
def part(i,total,text,token='synthetic'):
 payload=json.dumps({'token':token,'part':i,'total':total,'source_sha256':hash,'text':text}).encode();nonce=secrets.token_bytes(12);body=AESGCM(bytes.fromhex(key)).encrypt(nonce,gzip.compress(payload),m.LABEL)
 return {'v':1,'algorithm':'AES-256-GCM','compression':'gzip','aad':m.LABEL.decode(),'nonce':base64.b64encode(nonce).decode(),'ciphertext':base64.b64encode(body).decode()}
parts=[part(i,2,t)for i,t in enumerate(pieces)];bundle={'v':2,'format':'paperlab-multipart-archive-v1','parts':parts};assert m.decrypt(json.dumps(bundle).encode(),key)==raw
for bad in [[parts[1],parts[0]],parts[:1],[parts[0],part(1,2,pieces[1],token='other')]]:
 try:m.decrypt(json.dumps({**bundle,'parts':bad}).encode(),key)
 except ValueError:pass
 else:raise AssertionError('Invalid multipart archive accepted')
print('Multipart archive passed: exact financial/Unicode payload, reordered/missing/mixed parts rejected.')
