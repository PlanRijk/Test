import {allowedOrigin,base,claims,context,digest,env,reply,requestBody,rpc,serviceKey,verifyOwner} from '../_shared/platform.js';

export async function handler(request){
  let settings,origin='';
  try{
    if(request.method!=='OPTIONS'&&!(request.headers.get('Authorization')||'').startsWith('Bearer '))return reply({error:'Aanmelden vereist.'},401);
    settings=await context();origin=settings?.origin||'';
    if(!origin)return reply({error:'De installatie wordt voorbereid.'},503);
    if(!allowedOrigin(request,origin))return reply({error:'Oorsprong geweigerd.'},403);
    if(request.method==='OPTIONS')return reply(null,204,origin);
    if(!['GET','POST'].includes(request.method))return reply({error:'Methode niet toegestaan.'},405,origin);
    const body=request.method==='POST'?await requestBody(request):{},url=new URL(request.url);
    const recovery=body.action==='recover';const {user,jwt}=await verifyOwner(request,settings,{allowAal1:recovery});
    if(recovery){
      if(!/^[a-f0-9]{24}$/.test(body.code||''))return reply({error:'Herstelcode ongeldig.'},400,origin);
      const accepted=await rpc('paper_recovery',{p_owner:user.id,p_action:'consume',p_hash:await digest(body.code)});
      if(!accepted)return reply({error:'Herstelcode ongeldig of gebruikt.'},400,origin);
      for(const factor of user.factors||[])if(factor.factor_type==='totp'){
        const r=await fetch(base()+`/auth/v1/admin/users/${user.id}/factors/${factor.id}`,{method:'DELETE',headers:{apikey:serviceKey(),Authorization:'Bearer '+serviceKey()}});
        if(!r.ok)throw Error('MFA-herstel niet voltooid.');
      }
      return reply({ok:true,re_enroll_required:true},200,origin);
    }
    if(!await rpc('paper_session',{p_owner:user.id,p_session:jwt.session_id,p_revoke:body.action==='logout'})){
      if(body.action==='logout')return reply({ok:true},200,origin);
      return reply({error:'Sessie verlopen. Meld opnieuw aan.'},401,origin);
    }
    if(request.method==='GET'){
      if(url.searchParams.has('receipt')){
        const id=Number(url.searchParams.get('receipt'));if(!Number.isSafeInteger(id)||id<1)return reply({error:'Ongeldig transactie-ID.'},400,origin);
        const result=await rpc('paper_receipt',{p_owner:user.id,p_id:id});return reply(result||{error:'Niet gevonden.'},result?200:404,origin);
      }
      if(url.searchParams.has('export'))return reply(await rpc('paper_export',{p_owner:user.id}),200,origin);
      const revision=Number(url.searchParams.get('revision')??-1);return reply(await rpc('paper_read',{p_owner:user.id,p_revision:Number.isSafeInteger(revision)?revision:-1}),200,origin);
    }
    if(['start','pause'].includes(body.action)){
      await rpc('paper_action',{p_owner:user.id,p_action:body.action});
      return reply(await rpc('paper_read',{p_owner:user.id,p_revision:-1}),200,origin);
    }
    if(body.action==='step'){
      const response=await fetch(base()+'/functions/v1/paper-tick',{method:'POST',headers:{'Content-Type':'application/json','X-PaperLab-Cron':env('PAPERLAB_CRON_TOKEN')},body:JSON.stringify({manual:true}),signal:AbortSignal.timeout(80000)});
      if(!response.ok)throw Error('Koersmeting mislukt.');return reply(await rpc('paper_read',{p_owner:user.id,p_revision:-1}),200,origin);
    }
    if(body.action==='recovery-codes'){
      if(!Array.isArray(body.hashes)||body.hashes.length!==10||new Set(body.hashes).size!==10||!body.hashes.every(x=>/^[0-9a-f]{64}$/.test(x)))return reply({error:'Ongeldige herstelcodes.'},400,origin);
      await rpc('paper_recovery',{p_owner:user.id,p_action:'create',p_hashes:body.hashes});return reply({ok:true},200,origin);
    }
    return reply({error:'Onbekende actie.'},400,origin);
  }catch(error){
    const message=String(error.message||'');
    if(['AUTH_REQUIRED','OWNER_REQUIRED','MFA_REQUIRED'].includes(message))return reply({error:message==='MFA_REQUIRED'?'Tweefactorauthenticatie vereist.':'Aanmelden als eigenaar vereist.'},message==='AUTH_REQUIRED'?401:403,origin);
    return reply({error:'Opdracht niet voltooid. Geen nieuwe uitvoering bevestigd.'},503,origin);
  }
}
if(globalThis.Deno?.serve)Deno.serve(handler);
