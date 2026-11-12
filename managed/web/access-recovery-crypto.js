export const RECOVERY_LABEL='PaperLab Supabase Recovery v1';
const encode=x=>new TextEncoder().encode(x);
const b64=bytes=>btoa(String.fromCharCode(...bytes));
const fromB64=s=>Uint8Array.from(atob(s),c=>c.charCodeAt(0));
const hex=bytes=>Array.from(bytes,b=>b.toString(16).padStart(2,'0')).join('');
export async function recoveryKey(config,{crypto=globalThis.crypto,time=Date.now()}={}){
 if(config?.version!==1||config.enabled!==true||!Number.isFinite(config.created_at)||!Number.isFinite(config.expires_at)||config.created_at>time+60000||config.expires_at<=time||config.expires_at-config.created_at>86400000||!/^([a-f0-9]{64})$/.test(config.kid||'')||typeof config.spki!=='string'||config.spki.length>1500)throw Error('recovery_unavailable');
 const der=fromB64(config.spki),digest=hex(new Uint8Array(await crypto.subtle.digest('SHA-256',der)));
 if(digest!==config.kid)throw Error('recovery_unavailable');
 const key=await crypto.subtle.importKey('spki',der,{name:'RSA-OAEP',hash:'SHA-256'},false,['encrypt']);
 if(key.algorithm.modulusLength!==4096)throw Error('recovery_unavailable');
 return key;
}
export async function encryptRecovery(token,config,{crypto=globalThis.crypto,time=Date.now()}={}){
 if(typeof token!=='string'||!/^sbp_[A-Za-z0-9_-]{20,180}$/.test(token.trim()))throw Error('personal_token_required');
 const key=await recoveryKey(config,{crypto,time}),message=encode(JSON.stringify({v:1,k:config.kid,p:'supabase-management',iat:time,exp:time+1800000,t:token.trim()}));
 if(message.length>446)throw Error('personal_token_required');
 const ciphertext=await crypto.subtle.encrypt({name:'RSA-OAEP',label:encode(RECOVERY_LABEL)},key,message);
 return'PAPERLAB-RECOVERY-1.'+config.kid+'.'+b64(new Uint8Array(ciphertext)).replaceAll('+','-').replaceAll('/','_').replace(/=+$/,'');
}
