// Pure counterfactual marking with the existing frozen cost engine. No orders.
import fs from 'node:fs';import crypto from 'node:crypto';
import {purchase,sale}from'../managed/functions/_shared/engine.js';
const root=new URL('../',import.meta.url),read=name=>JSON.parse(fs.readFileSync(new URL('.data/managed/'+name,root),'utf8'));
const input=read('iex-focus-samples.json'),config=read('iex-focus-config.json'),p=input.policy;
const percentile=(xs,f)=>xs.length?[...xs].sort((a,b)=>a-b)[Math.ceil(xs.length*f)-1]:null;
function quality(q){const mid=q&&(q.bid+q.ask)/2,spread=q&&q.bid>0&&q.ask>=q.bid?(q.ask-q.bid)/mid*10000:null;return {spread,usable:!!q&&q.quote_within_60s&&q.bid_size>0&&q.ask_size>0&&q.bid_exchange==='V'&&q.ask_exchange==='V'&&q.quote_conditions?.includes('R')&&spread!==null&&spread<=p.maximum_entry_spread_bps};}
const companies=p.symbols.map(symbol=>{
 let position,entrySnapshot,entryBid,breakEven,valid=0,eligible=0,spreads=[],marks=[];
 for(const snapshot of input.samples){const q=snapshot.rows.find(x=>x.symbol===symbol),checked=quality(q);if(q?.quote_within_60s&&checked.spread!==null){valid++;spreads.push(checked.spread);}if(!checked.usable)continue;eligible++;
  if(!position){const price=q.ask/config.usd_per_eur,buy=purchase(config,symbol,price,p.hypothetical_budget_eur);position={qty:buy.qty,entry:price,entry_gross_eur:buy.qty*price,cost:p.hypothetical_budget_eur};entrySnapshot=snapshot.checked_at;entryBid=q.bid;
   let lo=price,hi=price*1.1;while(sale(config,symbol,position,hi).net_pnl_eur<0&&hi<price*4)hi*=1.5;
   for(let i=0;i<50;i++){const mid=(lo+hi)/2;if(sale(config,symbol,position,mid).net_pnl_eur>=0)hi=mid;else lo=mid;}breakEven=100*(hi*config.usd_per_eur/entryBid-1);
  }
  marks.push({at:snapshot.checked_at,net_eur:sale(config,symbol,position,q.bid/config.usd_per_eur).net_pnl_eur});
 }
 const lastSnapshot=input.samples.at(-1),lastIsUsable=quality(lastSnapshot.rows.find(x=>x.symbol===symbol)).usable;
 return {symbol,samples:input.samples.length,available:input.samples.filter(s=>s.rows.some(r=>r.symbol===symbol)).length,fresh_quotes:valid,quality_passes:eligible,median_spread_bps:percentile(spreads,.5),max_spread_bps:spreads.length?Math.max(...spreads):null,hypothetical_entry_at:entrySnapshot||null,break_even_bid_rise_percent:breakEven??null,final_mark_net_eur:lastIsUsable?marks.at(-1)?.net_eur??null:null,final_mark_at:lastIsUsable?marks.at(-1)?.at??null:null,unusable_last_quote:!lastIsUsable,orders:0};
});
const sorted=x=>Array.isArray(x)?x.map(sorted):x&&typeof x==='object'?Object.fromEntries(Object.keys(x).sort().map(k=>[k,sorted(x[k])])):x;
const evidence=input.samples.map(s=>[s.checked_at,p.symbols.map(symbol=>{const q=s.rows.find(r=>r.symbol===symbol);return q?[q.quote_time,q.bid,q.ask,q.bid_size,q.ask_size,q.bid_exchange,q.ask_exchange,q.quote_conditions]:null;})]);
const report={cost_config_snapshot:config,evidence,version:p.version,policy:p,started_at:input.samples[0].checked_at,finished_at:input.samples.at(-1).checked_at,samples:input.samples.length,successful_samples:input.samples.filter(s=>s.status==='measured').length,companies,cost_config_sha256:crypto.createHash('sha256').update(JSON.stringify(sorted(config))).digest('hex'),fx_usd_per_eur:config.usd_per_eur,orders:false,training:false,causal_or_profitability_evidence:false,note:'Exploratory fixed-budget illustration using first quality-passing quote, later eligible bids, static ECB FX and existing paper cost/reserve assumptions. No buy signal, forced exit, account profit, NBBO or actual fill.'};
fs.writeFileSync(new URL('.data/managed/iex-focus-report.json',root),JSON.stringify(report,null,2),{mode:0o600});console.log(JSON.stringify({started_at:report.started_at,finished_at:report.finished_at,companies:report.companies,bytes:JSON.stringify(report).length},null,2));
