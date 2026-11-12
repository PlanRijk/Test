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
const research=versioned('company-research.js',fs.readFileSync(path.join(root,'company-research.js'),'utf8'));
const coverageText=fs.readFileSync(path.join(root,'company-coverage.js'),'utf8').replace("'./company-research.js'","'./"+research+"'");
if(!coverageText.includes(research))throw Error('Research dependency missing');
const coverage=versioned('company-coverage.js',coverageText);
const appText=fs.readFileSync(path.join(root,'app.js'),'utf8').replace("'./company-coverage.js'","'./"+coverage+"'");
if(!appText.includes(coverage))throw Error('Coverage dependency missing');
const app=versioned('app.js',appText),style=versioned('style.css',fs.readFileSync(path.join(root,'style.css'),'utf8'));
const index=path.join(root,'index.html'),html=fs.readFileSync(index,'utf8');
const updated=html.replace(/\/app(?:\.[a-f0-9]{12})?\.js/g,'/'+app).replace(/\/style(?:\.[a-f0-9]{12})?\.css/g,'/'+style);
if(!updated.includes('/'+app)||!updated.includes('/'+style))throw Error('Versioned entrypoints missing');
fs.writeFileSync(index,updated);
console.log('Research entrypoints and stylesheet use content-hashed URLs.');
