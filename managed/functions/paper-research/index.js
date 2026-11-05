import {constantEqual,context,digest,env,reply,requestBody,rpc} from '../_shared/platform.js';
import {possibleSession} from '../_shared/engine.js';
import {BY_SYMBOL} from '../_shared/catalogue.js';
import {SOURCES} from '../_shared/sources.js';
import {optimizationReview} from '../_shared/optimization-review.js';
import {diagnose,inspectSources} from '../_shared/review.js';

export async function handler(request){
 const secret=env('PAPERLAB_CRON_TOKEN');if(!secret||!constantEqual(request.headers.get('X-PaperLab-Cron')||'',secret))return reply({error:'Niet toegestaan.'},401);
 if(request.method!=='POST')return reply({error:'POST vereist.'},405);
 let manual=false;try{manual=(await requestBody(request)).manual===true;}catch{return reply({error:'Ongeldig onderzoeksverzoek.'},400);}
 if(!manual&&possibleSession(BY_SYMBOL.AAPL,Date.now()))return reply({status:'deferred_market_open'});
 let lease;
 try{
  lease=await rpc('paper_claim_research');if(!lease)return reply({status:'paused_budget_busy_or_ended'});
  const settings=await context(),portfolio=await rpc('paper_read',{p_owner:settings.owner_id,p_revision:-1});
  const input=await rpc('paper_research_input');
  const reports=await inspectSources(SOURCES,{previous:portfolio.research?.sources||[]});
  let optimization;
  try{optimization=optimizationReview(await rpc('paper_optimization_input'));}
  catch{optimization={status:'unavailable',checked_at:new Date().toISOString(),note:'Optimalisatiecontrole niet voltooid; geen resultaat bevestigd.',trading_changes:false,model_changes:false};}
  try{optimization.maintenance=await rpc('paper_optimization_maintenance');}
  catch{optimization.maintenance={status:'unavailable'};}
  const diagnostics=diagnose(portfolio,input),s=portfolio.state;
  const fingerprint=await digest(JSON.stringify({engine:'global-paper-v1',signal:.002,lookback:5,source_age_seconds:120,
    universe:s.universe,risk:s.risk.config,tax:s.belgian_tax.config,costs:s.multi_market.cost_assumptions}));
  const report={checked_at:new Date().toISOString(),protocol:'paper-study-v1',trigger:manual?'manual_operator':'scheduled',parameter_fingerprint:fingerprint,
   ok_sources:reports.filter(x=>x.status==='reachable').length,sources:reports,diagnostics,
   closed_positions:diagnostics.managed_closes,trade_count:portfolio.trade_count,equity_eur:portfolio.equity,
   note:'Begrensde bronfragmenten, vastgelegde kennisnotities, officiële nieuwstitels, vertraagde macroreeksen en portefeuille-evaluatie. Modeltraining gebruikt afzonderlijk afgesloten proeftransacties; broninhoud wijzigt geen handelsregels.',
   optimization,automatic_learning:false,trading_changes:false,proposals:diagnostics.proposals};
  const stored=await rpc('paper_commit_research',{p_token:lease,p_report:report});return reply({status:stored?'reviewed':'superseded',ok_sources:report.ok_sources,trading_changes:false});
 }catch{return reply({error:'Onderzoeksrapport niet voltooid. Handelsregels blijven behouden.'},503);}
}
if(globalThis.Deno?.serve)Deno.serve(handler);
