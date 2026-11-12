import {constantEqual,env,reply,rpc} from '../_shared/platform.js';
import {earningsBatch} from '../_shared/earnings-pilot.js';
export async function handler(request){
 const secret=env('PAPERLAB_CRON_TOKEN');if(!secret||!constantEqual(request.headers.get('X-PaperLab-Cron')||'',secret))return reply({error:'Niet toegestaan.'},401);
 if(request.method!=='POST')return reply({error:'POST vereist.'},405);
 try{const input=await rpc('paper_earnings_claim');if(!input)return reply({status:'not_due_busy_or_budget'});const rows=await earningsBatch(input.targets),saved=await rpc('paper_earnings_commit',{p_token:input.token,p_rows:rows});return reply({status:saved?'checked':'superseded',companies:rows.length,confirmed_sources:rows.reduce((n,x)=>n+x.sources.filter(s=>s.status==='observed').length,0),qualitative_review_completed:false,trade_changes:false,paid_calls:false});}
 catch{return reply({error:'Kwartaalcontrole niet bevestigd; taken blijven zichtbaar.'},503);}
}
if(globalThis.Deno?.serve)Deno.serve(handler);
