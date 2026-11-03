import {constantEqual,context,env,reply,rpc} from '../_shared/platform.js';
import {possibleSession} from '../_shared/engine.js';
import {BY_SYMBOL} from '../_shared/catalogue.js';
import {SOURCES} from '../_shared/sources.js';

export async function handler(request){
 const secret=env('PAPERLAB_CRON_TOKEN');if(!secret||!constantEqual(request.headers.get('X-PaperLab-Cron')||'',secret))return reply({error:'Niet toegestaan.'},401);
 if(request.method!=='POST')return reply({error:'POST vereist.'},405);
 if(possibleSession(BY_SYMBOL.AAPL,Date.now()))return reply({status:'deferred_market_open'});
 const reports=[];let i=0;
 async function worker(){while(i<SOURCES.length){const source=SOURCES[i++];
  try{
   const response=await fetch(source.url,{headers:{'User-Agent':'PaperLab/1.0 (personal source review)'},signal:AbortSignal.timeout(5000),redirect:'manual'});
   // Websites are untrusted data: no execution, redirects or parameter changes.
   if(response.body)await response.body.cancel();reports.push({id:source.id,url:source.url,status:response.ok?'reachable':'unavailable',http:response.status});
  }catch{reports.push({id:source.id,url:source.url,status:'unavailable'});}
 }}
 await Promise.all(Array.from({length:4},worker));
 const settings=await context(),portfolio=await rpc('paper_read',{p_owner:settings.owner_id,p_revision:-1});
 const report={checked_at:new Date().toISOString(),ok_sources:reports.filter(x=>x.status==='reachable').length,sources:reports,
  closed_positions:portfolio.trades.filter(x=>x.side==='verkoop').length,trade_count:portfolio.trade_count,
  equity_eur:portfolio.equity,note:'Bronbereikbaarheid en deterministische evaluatie. Geen nieuwe inhoudsanalyse, voorspelling of automatische regelwijziging.',
  automatic_learning:false,trading_changes:false,proposals:['Evalueer handelskosten en waarnemingsgaten vóór vergelijking van strategieën.','De kleine steekproef toont geen blijvend handelsvoordeel aan.']};
 await rpc('paper_research',{p_report:report});return reply({status:'reviewed',ok_sources:report.ok_sources,trading_changes:false});
}
if(globalThis.Deno?.serve)Deno.serve(handler);
