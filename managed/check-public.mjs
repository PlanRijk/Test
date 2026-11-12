// Free static build: reject accidental server/management credentials in assets.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
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
// Render's edge may retain a previous response for an unchanged asset URL.
// Content-address the changed research dependency chain and its stylesheet.
const versioned=(file,text)=>{const ext=path.extname(file),name=file.slice(0,-ext.length)+'.'+crypto.createHash('sha256').update(text).digest('hex').slice(0,12)+ext;fs.writeFileSync(path.join(root,name),text);return name;};
const built=new Map(),visiting=new Set();
function asset(file){
 if(built.has(file))return built.get(file);if(visiting.has(file))throw Error('Cyclic browser module');visiting.add(file);
 let text=fs.readFileSync(path.join(root,file),'utf8');
 text=text.replace(/(from\s*|import\s*)(['"])(\.\/[^'"]+\.js)\2/g,(_,prefix,quote,dependency)=>prefix+quote+'./'+asset(dependency.slice(2))+quote);
 const result=versioned(file,text);visiting.delete(file);built.set(file,result);return result;
}
const app=asset('app.js'),style=versioned('style.css',fs.readFileSync(path.join(root,'style.css'),'utf8'));
const index=path.join(root,'index.html'),html=fs.readFileSync(index,'utf8');
const updated=html.replace(/\/app(?:\.[a-f0-9]{12})?\.js/g,'/'+app).replace(/\/style(?:\.[a-f0-9]{12})?\.css/g,'/'+style);
if(!updated.includes('/'+app)||!updated.includes('/'+style))throw Error('Versioned entrypoints missing');
fs.writeFileSync(index,updated);
console.log('Research entrypoints and stylesheet use content-hashed URLs.');
