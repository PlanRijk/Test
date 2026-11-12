import {recoveryKey} from './access-recovery-crypto.js';
export async function encryptRender(token,config,{crypto=globalThis.crypto,time=Date.now()}={}){
 if(typeof token!=='string'||!/^rnd_[A-Za-z0-9_-]{16,180}$/.test(token.trim()))throw Error('invalid_token');
 const key=await recoveryKey(config,{crypto,time});
 const msg=new TextEncoder().encode(JSON.stringify({v:1,k:config.kid,p:'render-management',iat:time,exp:time+1800000,t:token.trim()}));
 const encrypted=await crypto.subtle.encrypt({name:'RSA-OAEP',label:new TextEncoder().encode('PaperLab Render Recovery v1')},key,msg);
 return 'PAPERLAB-RENDER-RECOVERY-1.'+config.kid+'.'+btoa(String.fromCharCode(...new Uint8Array(encrypted))).replaceAll('+','-').replaceAll('/','_').replace(/=+$/,'');
}
