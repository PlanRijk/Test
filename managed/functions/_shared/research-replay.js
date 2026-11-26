import{dailySignal,SWING_POLICY}from'./swing-rules.js';
import{BY_SYMBOL}from'./catalogue.js';
export const REPLAY_PROTOCOL='cached-close-replay-v1';
export const REPLAY_POLICY=Object.freeze({starting_units:10000,position_fraction:.05,cost_per_side:.005,stress_cost_per_side:.01,lookback:20,max_holding_sessions:20,stop_multiple:2.5,min_stop_fraction:.03,max_stop_fraction:.08,reward_risk:2,parameter_search:false,live_orders:false});
function fold(rows,symbol,start,end,cost){
 const p=REPLAY_POLICY,capital=p.starting_units,initial=capital;let cash=capital,position=null,pending=null,peak=initial,maxDD=0;const trades=[];let signals=0,rejectedGap=0;
 const sell=(b,reason)=>{const net=position.qty*b.close*(1-cost),pnl=net-position.cost;cash+=net;trades.push({entry_day:position.entry_day,exit_day:b.day,signal_day:position.signal_day,reason,pnl_units:pnl,entry_price:position.entry,exit_price:b.close});position=null;};
 for(let i=start;i<end;i++){
  const b=rows[i];
  // Only orders decided on a prior completed bar can execute on this close.
  if(pending?.side==='sell'&&position)sell(b,pending.reason);
  else if(pending?.side==='buy'&&!position){const gap=b.close/pending.signal.last_close-1;if(Math.abs(gap)<=SWING_POLICY.max_entry_gap_fraction){const spend=Math.min(initial*p.position_fraction,cash),qty=spend/(b.close*(1+cost));cash-=spend;position={qty,cost:spend,entry:b.close,entry_day:b.day,entry_index:i,signal_day:pending.signal.signal_day,stop:b.close*(1-pending.signal.stop_fraction),target:b.close*(1+p.reward_risk*pending.signal.stop_fraction),distance:b.close*pending.signal.stop_fraction};}else rejectedGap++;}
  pending=null;
  if(position){if(b.close<=position.stop)pending={side:'sell',reason:'close_stop_next_close'};else if(b.close>=position.target)pending={side:'sell',reason:'close_target_next_close'};else if(i-position.entry_index+1>=p.max_holding_sessions)pending={side:'sell',reason:'time_next_close'};else if(b.close>=position.entry+position.distance)position.stop=Math.max(position.stop,b.close*(1-p.min_stop_fraction));}
  else if(i+1<end){const past=rows.slice(Math.max(0,i-19),i+1).map(r=>({...r,observed_at:r.day+'T23:59:59Z'})),s=dailySignal(past,symbol,Date.parse(b.day+'T00:00:00Z')+36*3600000);if(s.eligible&&s.stop_fraction<=p.max_stop_fraction){signals++;pending={side:'buy',signal:s};}}
  const eq=cash+(position?position.qty*b.close*(1-cost):0);peak=Math.max(peak,eq);maxDD=Math.max(maxDD,(peak-eq)/peak*100);
 }
 if(position)sell(rows[end-1],'diagnostic_window_end');
 const first=rows[start].close,last=rows[end-1].close,holdMultiple=last/first*(1-cost)/(1+cost),hold=initial*(1-p.position_fraction)+initial*p.position_fraction*holdMultiple;
 return {start:rows[start].day,end:rows[end-1].day,sessions:end-start,return_percent:(cash/initial-1)*100,max_drawdown_percent:maxDD,trades:trades.length,winning_trades:trades.filter(x=>x.pnl_units>0).length,signals,rejected_entry_gap:rejectedGap,buy_hold_same_initial_allocation_percent:(hold/initial-1)*100,excess_vs_same_initial_allocation_percent:(cash-hold)/initial*100,execution_examples:trades.slice(0,3)};
}
export function replayCached(input,time=Date.now()){
 const rows=(input.bars||[]).filter(b=>b.day<new Date(time).toISOString().slice(0,10));
 const base={protocol:REPLAY_PROTOCOL,policy:REPLAY_POLICY,symbol:input.symbol,source_hash:input.source_hash,source_acquired_at:input.source_acquired_at,retrospective:true,paid_services:false,trade_approval:false,profitability_proven:false,implementation:'Paperlab native close-only diagnostic; LEAN is a method reference, not the runtime.',limitations:['Geen historische kwalitatieve goedkeuringen: alleen de technische hypothese wordt onderzocht.','Alleen slotkoersen: stop-/doelorders worden op een volgend slot gesimuleerd; geen intradaguitvoering.','Kosten zijn vaste scenario’s van 0,5% en 1% per zijde, geen geverifieerde IBKR- of Belgische belastingberekening.','Rendement in rapporterings-/koersmunt; geen EUR-omrekening, dividendherbelegging of rente op cash.','Huidig bedrijvenuniversum en achteraf verworven historie: overlevingsbias en geen volledige point-in-time-dataset.','Koop-en-aanhouden gebruikt dezelfde initiële allocatie van 5%; risico en looptijd zijn niet volledig gelijk.','Twee chronologische vensters met vaste parameters; geen parameterselectie op de uitkomsten.']};
 if(!BY_SYMBOL[input.symbol]||rows.length<100||rows.length>180||rows.some((b,i)=>!/^20\d{2}-\d{2}-\d{2}$/.test(b.day)||!Number.isFinite(b.close)||b.close<=0||i&&b.day<=rows[i-1].day))return {...base,status:'insufficient_or_invalid_history'};
 if(rows.some((b,i)=>i&&Math.abs(b.close/rows[i-1].close-1)>.2)||(input.actions||[]).some(a=>a.type==='splits'&&a.day>=rows[0].day&&a.day<=rows.at(-1).day))return {...base,status:'corporate_action_review'};
 const midpoint=Math.floor((rows.length+20)/2),windows=[[20,midpoint],[midpoint,rows.length]];
 return {...base,status:'completed',first_source_day:rows[0].day,last_source_day:rows.at(-1).day,source_is_stale:time-Date.parse(rows.at(-1).day+'T00:00:00Z')>7*86400000,folds:windows.map(([s,e])=>({base:fold(rows,input.symbol,s,e,REPLAY_POLICY.cost_per_side),stress:fold(rows,input.symbol,s,e,REPLAY_POLICY.stress_cost_per_side)}))};
}
