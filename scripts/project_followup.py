"""Install bounded daily triage/reference and private encrypted recovery storage.

Credentials are provided by the existing management clients. Never logs values.
"""
import base64,datetime,gzip,hashlib,json,secrets,sys,urllib.error
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts import managed_api as api
from scripts.deploy_managed import jsql,literal
from scripts.compact_transport import SNAPSHOT
GROUP='evg-dbqnsnbtqb8s739tmpvg';BUCKET='paperlab-private-archives';LABEL=b'PaperLab private archive v1'
def archive_key():
 g=api.request('render','/v1/env-groups/'+GROUP)
 if g.get('name')!='paperlab-beheer'or g.get('ownerId')!='tea-dbkv4j15efls73fp2uhg'or g.get('serviceLinks')!=[]:raise RuntimeError('Expected unlinked management group')
 found=[x for x in g.get('envVars',[])if x.get('key')=='PAPERLAB_ARCHIVE_KEY']
 if found:return api.request('render','/v1/env-groups/'+GROUP+'/env-vars/PAPERLAB_ARCHIVE_KEY')['value']
 value=secrets.token_hex(32);api.request('render','/v1/env-groups/'+GROUP+'/env-vars/PAPERLAB_ARCHIVE_KEY','PUT',{'value':value})
 if not secrets.compare_digest(api.request('render','/v1/env-groups/'+GROUP+'/env-vars/PAPERLAB_ARCHIVE_KEY')['value'],value):raise RuntimeError('Archive key persistence failed')
 return value
def configure(ref):
 before=api.sql(ref,SNAPSHOT,True)[0]['frozen'];jobs=api.sql(ref,"select jobid,jobname,schedule,active from cron.job where jobname<>'paperlab-project-followup'order by jobid",True)
 for name in ['028_project_followup.sql','029_private_archives.sql','030_publication_watch.sql','031_strategy_priority.sql','032_daily_weekly_swing.sql']:api.sql(ref,(ROOT/'managed/sql'/name).read_text())
 value=archive_key();api.request('supabase','/v1/projects/'+ref+'/secrets','POST',[{'name':'PAPERLAB_ARCHIVE_KEY','value':value}])
 service=api.keys(ref)['service_role']
 try:b=api.project_request(ref,service,'/storage/v1/bucket/'+BUCKET)
 except api.ApiError as e:
  if e.status not in(400,404):raise
  api.project_request(ref,service,'/storage/v1/bucket','POST',{'id':BUCKET,'name':BUCKET,'public':False,'file_size_limit':15000000,'allowed_mime_types':['application/octet-stream']});b=api.project_request(ref,service,'/storage/v1/bucket/'+BUCKET)
 if b.get('public')is not False:raise RuntimeError('Archive bucket must be private')
 api.deploy_function(ref,'paper-project-followup');api.deploy_function(ref,'paper-api')
 command="select public.paper_project_prepare_weekly_backup();select net.http_post(url:="+literal('https://'+ref+'.supabase.co/functions/v1/paper-project-followup')+",headers:=jsonb_build_object('Content-Type','application/json','X-PaperLab-Cron',(select decrypted_secret from vault.decrypted_secrets where name='paperlab_cron_token')),body:='{}'::jsonb,timeout_milliseconds:=120000);"
 existing=api.sql(ref,"select jobid,schedule,command from cron.job where jobname='paperlab-project-followup'",True)
 if not existing:api.sql(ref,"select cron.schedule('paperlab-project-followup','55 6 * * *',"+literal(command)+')')
 elif len(existing)!=1 or existing[0]['schedule']!='55 6 * * *':raise RuntimeError('Unexpected followup schedule')
 elif existing[0]['command']!=command:api.sql(ref,'select cron.alter_job('+str(existing[0]['jobid'])+',command:='+literal(command)+')')
 api.sql(ref,'select public.paper_project_refresh()')
 assert before==api.sql(ref,SNAPSHOT,True)[0]['frozen']
 current=api.sql(ref,"select jobid,jobname,schedule,active from cron.job where jobname<>'paperlab-project-followup'order by jobid",True);assert jobs==current
 print(json.dumps({'daily_followup_utc':'06:55','weekly_backup':'Sunday, inside daily followup','private_bucket':BUCKET,'archive_key_location':'unlinked Render paperlab-beheer and Supabase function secret','existing_policies_and_jobs_unchanged':True,'paid_resources':False}))
def archive_sources(ref,root):
 from cryptography.hazmat.primitives.ciphers.aead import AESGCM
 value=archive_key();key=bytes.fromhex(value);service=api.keys(ref)['service_role'];sources=json.loads((root/'all-sources.json').read_text());batch=[];size=0;groups=[]
 for source in sources:
  texts={}
  for d in source['documents']:
   p=root/source['symbol']/(d['sha256']+'.txt')
   if p.exists():
    text=p.read_text();texts[d['sha256']]={'text':text,'text_sha256':hashlib.sha256(text.encode()).hexdigest()}
  item={'company':source,'extracted_texts':texts};n=len(json.dumps(item).encode())
  if size+n>24000000 and batch:groups.append(batch);batch=[];size=0
  batch.append(item);size+=n
 if batch:groups.append(batch)
 day=datetime.datetime.now(datetime.timezone.utc).date().isoformat();total=0
 for i,group in enumerate(groups):
  raw=json.dumps({'version':'paperlab-source-text-archive-v1','scope':'Extracted text and source metadata; not original PDF/HTML bytes','companies':group},ensure_ascii=False,separators=(',',':')).encode()
  if len(raw)>30000000:raise RuntimeError('Source text bundle exceeds bounded extraction archive')
  nonce=secrets.token_bytes(12);cipher=AESGCM(key).encrypt(nonce,gzip.compress(raw),LABEL)
  envelope=json.dumps({'v':1,'algorithm':'AES-256-GCM','compression':'gzip','aad':LABEL.decode(),'nonce':base64.b64encode(nonce).decode(),'ciphertext':base64.b64encode(cipher).decode()},separators=(',',':')).encode()
  if len(envelope)>15000000:raise RuntimeError('Encrypted source archive too large')
  path='sources/'+day+'-batch-'+str(i+1).zfill(2)+'.json.enc'
  stored_bytes=api.sql(ref,"select coalesce(sum((record->>'bytes')::bigint),0)as bytes from paperlab.archive_manifest where record->>'kind'='extracted_source_texts'",True)[0]['bytes']
  if stored_bytes+len(envelope)>100000000:raise RuntimeError('Source archive storage budget; select retention explicitly')
  charge=4*len(envelope)+8192
  # Reserve before transfer. Never reset the existing month meter.
  api.sql(ref,"do $$begin perform 1 from paperlab.free_usage where month=date_trunc('month',now()at time zone'UTC')::date for update;if(select estimated_worker_egress_bytes+"+str(charge)+" from paperlab.free_usage where month=date_trunc('month',now()at time zone'UTC')::date)>paperlab.traffic_limit('soft')then raise exception'Archive transfer budget';end if;update paperlab.free_usage set estimated_worker_egress_bytes=estimated_worker_egress_bytes+"+str(charge)+" where month=date_trunc('month',now()at time zone'UTC')::date;end$$;")
  import urllib.request
  class NoRedirect(urllib.request.HTTPRedirectHandler):
   def redirect_request(self,*a,**k):return None
  opener=urllib.request.build_opener(NoRedirect());url='https://'+ref+'.supabase.co/storage/v1/object/'+BUCKET+'/'+path;headers={'apikey':service,'Authorization':'Bearer '+service,'Content-Type':'application/octet-stream','x-upsert':'false'}
  with opener.open(urllib.request.Request(url,data=envelope,method='POST',headers=headers),timeout=60)as response:response.read()
  with opener.open(urllib.request.Request(url,headers={'apikey':service,'Authorization':'Bearer '+service}),timeout=60)as response:saved=response.read(15000001)
  x=json.loads(saved);restored=gzip.decompress(AESGCM(key).decrypt(base64.b64decode(x['nonce']),base64.b64decode(x['ciphertext']),LABEL));assert restored==raw
  record={'kind':'extracted_source_texts','object_path':path,'bytes':len(saved),'sha256':hashlib.sha256(saved).hexdigest(),'restore_tested':True,'restore_test_scope':'Downloaded ciphertext decrypted and exact source-text package compared','companies':len(group),'original_documents_included':False}
  api.sql(ref,'insert into paperlab.archive_manifest(id,record)values('+literal('sources-'+day+'-'+str(i+1))+','+jsql(record)+')on conflict do nothing')
  total+=len(saved);print(json.dumps({'source_archive_batch':i+1,'companies':len(group),'encrypted_bytes':len(saved),'verified':True}),flush=True)
 print(json.dumps({'source_archives':len(groups),'companies':len(sources),'total_encrypted_bytes':total}))
if __name__=='__main__':
 if len(sys.argv)==3 and sys.argv[1]=='configure':configure(sys.argv[2])
 elif len(sys.argv)==4 and sys.argv[1]=='archive-sources':archive_sources(sys.argv[2],Path(sys.argv[3]))
 else:raise SystemExit('project_followup.py configure REF | archive-sources REF DIRECTORY')
