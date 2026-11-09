// Per-tab session only. The server still checks owner, MFA, revocation and expiry.
export const TAB_SESSION_KEY='paperlab.tab-session.v1';
export const IDLE_MS=30*60*1000,MAX_SESSION_MS=8*60*60*1000;
const pages=new Set(['overview','catalogue','trades','research','learning','opportunities','settings','reference']);
export function clearTabSession(storage){try{storage?.removeItem(TAB_SESSION_KEY);}catch{}}
export function readTabSession(storage,now=Date.now()){
 try{
  const r=JSON.parse(storage?.getItem(TAB_SESSION_KEY)||'null'),s=r?.session;
  if(!r)return null;
  if(r.version!==1||!s||!['access_token','refresh_token'].every(k=>typeof s[k]==='string'&&s[k].length>0&&s[k].length<=8192)||!Number.isFinite(s.expires_at)||!Number.isFinite(r.started_at)||!Number.isFinite(r.last_activity)||r.last_activity<r.started_at||now<r.last_activity||now-r.last_activity>=IDLE_MS||now-r.started_at>=MAX_SESSION_MS)throw Error('Invalid or expired tab session');
  return {session:{access_token:s.access_token,refresh_token:s.refresh_token,expires_at:s.expires_at},started_at:r.started_at,last_activity:r.last_activity,page:pages.has(r.page)?r.page:'overview'};
 }catch{clearTabSession(storage);return null;}
}
export function writeTabSession(storage,session,{started_at,last_activity,page='overview'}){
 try{
  if(!storage)return false;
  storage.setItem(TAB_SESSION_KEY,JSON.stringify({version:1,session:{access_token:session.access_token,refresh_token:session.refresh_token,expires_at:session.expires_at},started_at,last_activity,page:pages.has(page)?page:'overview'}));return true;
 }catch{return false;}
}
