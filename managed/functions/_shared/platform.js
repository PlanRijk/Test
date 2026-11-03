export function env(name){return globalThis.Deno?.env.get(name)||'';}
export function base(){const value=env('SUPABASE_URL');if(!/^https:\/\/[a-z]+\.supabase\.co$/.test(value))throw Error('Projectomgeving ontbreekt.');return value;}
export function serviceKey(){const key=env('SUPABASE_SERVICE_ROLE_KEY');if(!key)throw Error('Servercredential ontbreekt.');return key;}
export async function rpc(name,args={}){
  const r=await fetch(base()+'/rest/v1/rpc/'+name,{method:'POST',headers:{apikey:serviceKey(),Authorization:'Bearer '+serviceKey(),'Content-Type':'application/json'},body:JSON.stringify(args),signal:AbortSignal.timeout(30000)});
  if(!r.ok)throw Error('Database-opdracht geweigerd ('+r.status+').');return r.json();
}
export async function context(){return await rpc('paper_context');}
export function allowedOrigin(request,expected){const actual=request.headers.get('Origin');return !actual||actual===expected;}
export function reply(body,status=200,origin=''){
  const headers={'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Vary':'Origin'};
  if(origin)Object.assign(headers,{'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'GET, POST, OPTIONS'});
  return new Response(body===null?null:JSON.stringify(body),{status,headers});
}
export async function requestBody(request){const text=await request.text();if(text.length>8192)throw Error('Verzoek te groot.');return text?JSON.parse(text):{};}
export function claims(token){try{return JSON.parse(atob(token.split('.')[1].replaceAll('-','+').replaceAll('_','/')));}catch{return {};}}
export async function verifyOwner(request,settings,{allowAal1=false}={}){
  const bearer=request.headers.get('Authorization')||'';if(!bearer.startsWith('Bearer ')||bearer.length>8192)throw Error('AUTH_REQUIRED');
  const token=bearer.slice(7),r=await fetch(base()+'/auth/v1/user',{headers:{apikey:serviceKey(),Authorization:'Bearer '+token},signal:AbortSignal.timeout(10000)});
  if(!r.ok)throw Error('AUTH_REQUIRED');const user=await r.json(),jwt=claims(token);
  if(!settings.owner_id||user.id!==settings.owner_id||jwt.sub!==user.id)throw Error('OWNER_REQUIRED');
  if(!allowAal1&&jwt.aal!=='aal2')throw Error('MFA_REQUIRED');
  if(!/^[0-9a-f-]{36}$/.test(jwt.session_id||''))throw Error('AUTH_REQUIRED');
  return {user,jwt,token};
}
export async function digest(value){return [...new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(value)))].map(x=>x.toString(16).padStart(2,'0')).join('');}
export function constantEqual(a,b){if(a.length!==b.length)return false;let diff=0;for(let i=0;i<a.length;i++)diff|=a.charCodeAt(i)^b.charCodeAt(i);return diff===0;}
