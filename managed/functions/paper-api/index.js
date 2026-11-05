import {allowedOrigin,base,claims,context,digest,env,reply,requestBody,rpc,serviceKey,verifyOwner} from '../_shared/platform.js';
import {annualTaxReport} from '../_shared/tax-report.js';

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
      if(url.searchParams.has('optimizations'))return reply(await rpc('paper_optimization_read',{p_owner:user.id}),200,origin);
      if(url.searchParams.has('breadth-study'))return reply(await rpc('paper_breadth_read',{p_owner:user.id}),200,origin);
      if(url.searchParams.has('breadth-export')||url.searchParams.has('breadth-traces'))return reply(await rpc('paper_breadth_export',{p_owner:user.id,p_traces:url.searchParams.has('breadth-traces')}),200,origin);
      if(url.searchParams.has('history-learning'))return reply(await rpc('paper_history_read',{p_owner:user.id}),200,origin);
      if(url.searchParams.has('history-export'))return reply(await rpc('paper_history_export',{p_owner:user.id}),200,origin);
      if(url.searchParams.has('daily-study'))return reply(await rpc('paper_daily_read',{p_owner:user.id}),200,origin);
      if(url.searchParams.has('daily-export'))return reply(await rpc('paper_daily_export',{p_owner:user.id}),200,origin);
      if(url.searchParams.has('tax-report')){
        const year=Number(url.searchParams.get('year')||new Date().getUTCFullYear());if(!Number.isInteger(year)||year<2026||year>new Date().getUTCFullYear())return reply({error:'Ongeldig belastingjaar.'},400,origin);
        return reply(annualTaxReport(await rpc('paper_tax_input',{p_owner:user.id}),year),200,origin);
      }
      if(url.searchParams.has('reliability'))return reply(await rpc('paper_reliability_read',{p_owner:user.id}),200,origin);
      if(url.searchParams.has('archive-export')){
        const before=url.searchParams.get('before');if(before&&!/^op-[a-f0-9]{24}$/.test(before))return reply({error:'Ongeldige archiefcursor.'},400,origin);
        return reply(await rpc('paper_archive_export',{p_owner:user.id,p_before:before}),200,origin);
      }
      if(url.searchParams.has('opportunities'))return reply(await rpc('paper_opportunity_read',{p_owner:user.id}),200,origin);
      if(url.searchParams.has('opportunity-export'))return reply(await rpc('paper_opportunity_records',{p_owner:user.id}),200,origin);
      if(url.searchParams.has('opportunity')){
        const id=url.searchParams.get('opportunity');if(!/^op-[a-f0-9]{24}$/.test(id||''))return reply({error:'Ongeldig onderzoeks-ID.'},400,origin);
        const result=await rpc('paper_opportunity_records',{p_owner:user.id,p_id:id});return reply(result||{error:'Niet gevonden.'},result?200:404,origin);
      }
      if(url.searchParams.has('learning'))return reply(await rpc('paper_learning_read',{p_owner:user.id}),200,origin);
      if(url.searchParams.has('learning-trades'))return reply(await rpc('paper_learning_trades',{p_owner:user.id}),200,origin);
      if(url.searchParams.has('learning-export'))return reply(await rpc('paper_learning_export',{p_owner:user.id}),200,origin);
      if(url.searchParams.has('shadow-receipt')){
        const id=Number(url.searchParams.get('shadow-receipt'));if(!Number.isSafeInteger(id)||id<1)return reply({error:'Ongeldig bewijs-ID.'},400,origin);
        const result=await rpc('paper_learning_trades',{p_owner:user.id,p_id:id});return reply(result||{error:'Niet gevonden.'},result?200:404,origin);
      }
      if(url.searchParams.has('purchase-analysis'))return reply(await rpc('paper_purchase_analysis',{p_owner:user.id}),200,origin);
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
    if(body.action==='learning'){
      const actions=['promote','rollback','pause','resume','restart','auto-on','auto-off'];if(!actions.includes(body.command)||body.model&&!/^lr-[a-f0-9]{24}$/.test(body.model))return reply({error:'Ongeldige leerbediening.'},400,origin);
      const ok=await rpc('paper_learning_action',{p_owner:user.id,p_action:body.command,p_model:body.model||null});
      if(!ok)return reply({error:'Model voldoet niet aan de bewijsvoorwaarden of de hoofdportefeuille is niet leeg.'},409,origin);
      return reply(await rpc('paper_learning_read',{p_owner:user.id}),200,origin);
    }
    if(body.action==='breadth'){
      if(!['pause','resume'].includes(body.command))return reply({error:'Ongeldige registratiebediening.'},400,origin);
      await rpc('paper_breadth_action',{p_owner:user.id,p_action:body.command});return reply(await rpc('paper_breadth_read',{p_owner:user.id}),200,origin);
    }
    if(body.action==='opportunities'){
      if(!['pause','resume'].includes(body.command))return reply({error:'Ongeldige onderzoeksbediening.'},400,origin);
      await rpc('paper_opportunity_action',{p_owner:user.id,p_action:body.command});return reply(await rpc('paper_opportunity_read',{p_owner:user.id}),200,origin);
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
