// Free static build: reject accidental server/management credentials in assets.
import fs from 'node:fs';
import path from 'node:path';
const root=path.resolve('managed/web');
for(const file of fs.readdirSync(root)){
 const text=fs.readFileSync(path.join(root,file),'utf8');
 if(/(?:sbp_|rnd_|sb_secret_)[A-Za-z0-9_-]{12,}/.test(text))throw Error('Private credential detected in browser assets.');
 for(const token of text.match(/eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g)||[]){
  const claims=JSON.parse(Buffer.from(token.split('.')[1],'base64url').toString());if(claims.role!=='anon')throw Error('Privileged JWT detected.');
 }
}
const {CONFIG}=await import('./web/config.js');
if(!CONFIG.url.startsWith('https://')||!CONFIG.key)throw Error('Public Supabase configuration missing.');
console.log('Static browser assets verified; no private management/server credentials.');
