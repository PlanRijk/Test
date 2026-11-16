import {recoveryKey} from './access-recovery-crypto.js';
export const GEMINI_LABEL='PaperLab Gemini Connection v1';
export async function encryptGemini(token,config,{crypto=globalThis.crypto,time=Date.now()}={}){
 if(typeof token!=='string'||! /^(?!rnd_|sbp_|sb_secret_)[A-Za-z0-9._~-]{20,200}$/.test(token.trim()))throw Error('invalid_gemini_key');
 const key=await recoveryKey(config,{crypto,time});
 const message=new TextEncoder().encode(JSON.stringify({v:1,k:config.kid,p:'gemini-api',iat:time,exp:time+1800000,t:token.trim()}));
 if(message.length>446)throw Error('invalid_gemini_key');
 const encrypted=await crypto.subtle.encrypt({name:'RSA-OAEP',label:new TextEncoder().encode(GEMINI_LABEL)},key,message);
 return 'PAPERLAB-GEMINI-CONNECT-1.'+config.kid+'.'+btoa(String.fromCharCode(...new Uint8Array(encrypted))).replaceAll('+','-').replaceAll('/','_').replace(/=+$/,'');
}
