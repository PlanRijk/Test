import{base,serviceKey,env,rpc,digest}from'./platform.js';
import{encryptArchive,decryptArchive}from'./private-archive.js';
export async function archiveColdSource({fetcher=fetch,call=rpc,key=env('PAPERLAB_ARCHIVE_KEY')}={}){
 if(!/^[a-f0-9]{64}$/.test(key))return{status:'archive_key_missing'};
 const input=await call('paper_cold_source_claim');if(!input)return{status:'no_cold_source_or_budget'};
 if(!/^[a-f0-9]{64}$/.test(input.id)||input.object_path!=='sources/cold-'+input.id+'.json.enc'||await digest(input.body)!==input.body_sha256)throw Error('cold_source_hash');
 const raw=JSON.stringify({version:'paperlab-cold-source-v1',id:input.id,symbol:input.symbol,url:input.url,source_sha256:input.sha256,body_sha256:input.body_sha256,scope:input.scope,body:input.body});
 const encrypted=await encryptArchive(raw,key);if(new TextEncoder().encode(encrypted).length>15000000)throw Error('archive_size');
 const url=base()+'/storage/v1/object/paperlab-private-archives/'+input.object_path,headers={apikey:serviceKey(),Authorization:'Bearer '+serviceKey(),'Content-Type':'application/octet-stream','x-upsert':'false'};
 const upload=await fetcher(url,{method:'POST',headers,body:encrypted,redirect:'error',signal:AbortSignal.timeout(30000)});
 if(!upload.ok&&![400,409].includes(upload.status))throw Error('archive_upload');
 const check=await fetcher(url,{headers,redirect:'error',signal:AbortSignal.timeout(30000)});if(!check.ok)throw Error('archive_verify_read');
 const saved=await check.text();if(saved.length>15000000)throw Error('archive_size');const restored=JSON.parse(await decryptArchive(saved,key));
 if(restored.version!=='paperlab-cold-source-v1'||restored.id!==input.id||restored.url!==input.url||restored.source_sha256!==input.sha256||restored.body_sha256!==input.body_sha256||restored.body!==input.body||await digest(restored.body)!==input.body_sha256)throw Error('archive_integrity');
 const ok=await call('paper_cold_source_commit',{p_token:input.token,p_record:{object_path:input.object_path,bytes:new TextEncoder().encode(saved).length,sha256:await digest(saved),body_sha256:input.body_sha256,verified:true}});
 return{status:ok?'cold_source_verified_and_compressed':'source_changed_preserved',symbol:input.symbol,plaintext_bytes:new TextEncoder().encode(input.body).length,archive_bytes:new TextEncoder().encode(saved).length};
}
