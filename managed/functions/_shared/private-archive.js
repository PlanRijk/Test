import{base,serviceKey,env,rpc,digest}from'./platform.js';
const LABEL='PaperLab private archive v1',encode=x=>new TextEncoder().encode(x),b64=x=>{let s='';for(let i=0;i<x.length;i+=8192)s+=String.fromCharCode(...x.subarray(i,i+8192));return btoa(s);},un64=x=>Uint8Array.from(atob(x),c=>c.charCodeAt(0));
async function key(hex,usage){if(!/^[a-f0-9]{64}$/.test(hex))throw Error('archive_key_missing');return crypto.subtle.importKey('raw',Uint8Array.from(hex.match(/../g),x=>parseInt(x,16)),{name:'AES-GCM'},false,[usage]);}
export async function encryptArchive(text,hex){
 const raw=encode(text);if(raw.length>30000000)throw Error('archive_plaintext_limit');
 const zipped=new Uint8Array(await new Response(new Blob([raw]).stream().pipeThrough(new CompressionStream('gzip'))).arrayBuffer()),nonce=crypto.getRandomValues(new Uint8Array(12));
 const encrypted=await crypto.subtle.encrypt({name:'AES-GCM',iv:nonce,additionalData:encode(LABEL)},await key(hex,'encrypt'),zipped);
 return JSON.stringify({v:1,algorithm:'AES-256-GCM',compression:'gzip',aad:LABEL,nonce:b64(nonce),ciphertext:b64(new Uint8Array(encrypted))});
}
export async function decryptArchive(text,hex){
 if(text.length>15000000)throw Error('archive_ciphertext_limit');const x=JSON.parse(text);if(x.v!==1||x.algorithm!=='AES-256-GCM'||x.compression!=='gzip'||x.aad!==LABEL)throw Error('archive_format');
 const raw=await crypto.subtle.decrypt({name:'AES-GCM',iv:un64(x.nonce),additionalData:encode(LABEL)},await key(hex,'decrypt'),un64(x.ciphertext));
 const reader=new Blob([raw]).stream().pipeThrough(new DecompressionStream('gzip')).getReader(),parts=[];let n=0;try{for(;;){const{done,value}=await reader.read();if(done)break;n+=value.length;if(n>30000000)throw Error('archive_decompressed_limit');parts.push(value);}}finally{await reader.cancel().catch(()=>{});}
 return await new Blob(parts).text();
}
export async function snapshotBackup({fetcher=fetch}={}){
 const hex=env('PAPERLAB_ARCHIVE_KEY');if(!/^[a-f0-9]{64}$/.test(hex))return{status:'archive_key_missing'};
 const input=await rpc('paper_project_backup_input');if(!input)return{status:'not_due_budget_or_busy'};
 if(!Number.isInteger(input.parts)||input.parts<1||input.parts>30)throw Error('archive_chunk_count');
 const parts=[];for(let i=0;i<input.parts;i++){const part=await rpc('paper_project_backup_chunk',{p_token:input.token,p_part:i});if(typeof part!=='string')throw Error('archive_chunk_missing');parts.push(part);}input.snapshot_text=parts.join('');if(await digest(input.snapshot_text)!==input.plaintext_sha256)throw Error('archive_source_hash');
 const encrypted=await encryptArchive(input.snapshot_text,hex);if(encrypted.length>15000000)throw Error('archive_size');
 const path='/storage/v1/object/paperlab-private-archives/'+input.object_path,headers={apikey:serviceKey(),Authorization:'Bearer '+serviceKey(),'Content-Type':'application/octet-stream','x-upsert':'false'};
 const response=await fetcher(base()+path,{method:'POST',headers,body:encrypted,redirect:'error',signal:AbortSignal.timeout(30000)});if(!response.ok)throw Error('archive_upload');
 const check=await fetcher(base()+path,{headers:{apikey:serviceKey(),Authorization:'Bearer '+serviceKey()},redirect:'error',signal:AbortSignal.timeout(30000)});if(!check.ok)throw Error('archive_verify_read');
 const saved=await check.text();if(saved.length>15000000||await decryptArchive(saved,hex)!==input.snapshot_text)throw Error('archive_integrity');
 const record={kind:'application_snapshot',object_path:input.object_path,bytes:encode(saved).length,sha256:await digest(saved),restore_tested:true,restore_test_scope:'AES-GCM decrypt, gzip decode and exact logical snapshot text equality; not a full provider/Auth restore',tables:Object.keys(JSON.parse(input.snapshot_text).tables).length};
 const committed=await rpc('paper_project_backup_commit',{p_token:input.token,p_record:record});let retention='not_checked';
 if(committed){const paths=await rpc('paper_project_archive_prune');if(paths.length&&paths.every(p=>/^backups\/[0-9-]+\.json\.enc$/.test(p))){const pruned=await fetcher(base()+'/storage/v1/object/paperlab-private-archives',{method:'DELETE',headers:{...headers,'Content-Type':'application/json'},body:JSON.stringify({prefixes:paths}),redirect:'error',signal:AbortSignal.timeout(30000)});if(pruned.ok){await rpc('paper_project_archive_prune',{p_confirmed:paths});retention='seven_snapshots';}else retention='deletion_failed';}else retention='seven_snapshots';}
 return{status:committed?'encrypted_verified':'manifest_not_saved',bytes:record.bytes,retention};
}
