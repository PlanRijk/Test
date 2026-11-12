import test from'node:test';import assert from'node:assert/strict';
import{generateKeyPairSync,createHash,privateDecrypt,constants,webcrypto}from'node:crypto';
import{encryptRecovery,recoveryKey,RECOVERY_LABEL}from'../web/access-recovery-crypto.js';
const{privateKey,publicKey}=generateKeyPairSync('rsa',{modulusLength:4096}),der=publicKey.export({type:'spki',format:'der'}),time=Date.now(),config={version:1,enabled:true,created_at:time,expires_at:time+86400000,kid:createHash('sha256').update(der).digest('hex'),spki:der.toString('base64')},token='sbp_'+'a'.repeat(40);
test('browser encryption roundtrips only with the matching private key and context label',async()=>{
 const out=await encryptRecovery(token,config,{crypto:webcrypto,time}),[prefix,kid,body]=out.split('.');assert.equal(prefix,'PAPERLAB-RECOVERY-1');assert.equal(kid,config.kid);assert(!out.includes(token));
 const options={key:privateKey,padding:constants.RSA_PKCS1_OAEP_PADDING,oaepHash:'sha256',oaepLabel:Buffer.from(RECOVERY_LABEL)},data=JSON.parse(privateDecrypt(options,Buffer.from(body,'base64url')));
 assert.equal(data.t,token);assert.equal(data.p,'supabase-management');assert.equal(data.exp-data.iat,1800000);
 assert.throws(()=>privateDecrypt({...options,oaepLabel:Buffer.from('wrong')},Buffer.from(body,'base64url')));
});
test('expired, disabled, future or mismatched public keys are rejected',async()=>{
 for(const bad of[{...config,expires_at:time},{...config,enabled:false},{...config,created_at:time+120000},{...config,kid:'0'.repeat(64)},{...config,expires_at:time+86400001}])await assert.rejects(recoveryKey(bad,{crypto:webcrypto,time}));
});
test('project keys and arbitrary input are rejected without reflecting their contents',async()=>{
 for(const value of['',123,'not-a-personal-token','sb_secret_'+'b'.repeat(40),'sbp_'+'x'.repeat(181)])await assert.rejects(encryptRecovery(value,config,{crypto:webcrypto,time}),{message:'personal_token_required'});
});
