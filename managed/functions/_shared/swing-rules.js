// Prospective PAPER hypothesis. No broker transport and no model approval.
import {BY_SYMBOL} from './catalogue.js';
import {day,sale,fx,purchase,validQuote} from './engine.js';
import {netExitPlan,exitQuoteCheck,NET_EXIT_POLICY} from './net-exit-policy.js';
import {assessCompany} from './company-analysis.js';
export const SWING_POLICY={version:'quality-swing-paper-v1',account:'capital10k',real_orders:false,paid_services:false,unit_eur:5,min_daily_closes:20,volatility_returns:14,volatility_multiple:2.5,min_stop_fraction:.03,max_stop_fraction:.08,gap_reserve_fraction:.01,max_entry_gap_fraction:.01,max_round_trip_cost_fraction:.015,max_new_stop_loss_eur:20,max_total_stop_loss_eur:150,min_order_eur:100,max_order_eur:500,max_buys_per_day:2,max_holding_sessions:20,net_reward_risk:2,reentry_hours:24,quote_age_seconds:120,additional_market_downloads:0,legacy_positions_unchanged:true};
const P=SWING_POLICY,DAY=86400000,mean=a=>a.reduce((s,x)=>s+x,0)/a.length;
export function completedBars(rows,k,time){
 const localDay=day(time,BY_SYMBOL[k].timezone),byDay=new Map();
 for(const b of rows||[])if(/^\d{4}-\d{2}-\d{2}$/.test(b.day||'')&&b.day<localDay&&Date.parse(b.observed_at)<=time&&Number.isFinite(b.close)&&b.close>0){const old=byDay.get(b.day);if(!old||Date.parse(old.observed_at)<Date.parse(b.observed_at))byDay.set(b.day,b);}
 return [...byDay.values()].sort((a,b)=>a.day.localeCompare(b.day)).slice(-20);
}
export function dailySignal(rows,k,time){
 const bars=completedBars(rows,k,time),no=reason=>({eligible:false,reason,bars});
 if(bars.length!==20)return no('Twintig afgesloten dagsloten ontbreken.');
 const last=bars.at(-1),age=time-Date.parse(last.day+'T00:00:00Z');
 if(age>7*DAY)return no('Laatste afgesloten dagslot is ouder dan zeven kalenderdagen.');
 const prices=bars.map(b=>b.close),returns=prices.slice(1).map((x,i)=>x/prices[i]-1);
 if(returns.some(x=>Math.abs(x)>.20))return no('Grote dagsprong: bedrijfsactie of koersreeks moet inhoudelijk worden gecontroleerd.');
 const r=returns.slice(-14),avg=mean(r),sigma=Math.sqrt(r.reduce((a,x)=>a+(x-avg)**2,0)/(r.length-1));
 const weekly=mean(prices.slice(-5))>mean(prices.slice(-10,-5)),trend=last.close>mean(prices),breakout=last.close>Math.max(...prices.slice(-6,-1));
 return{eligible:weekly&&trend&&breakout,reason:!weekly?'Vijfdaagse trend bevestigt niet.':!trend?'Slot onder het twintigdaagse gemiddelde.':!breakout?'Geen uitbraak boven de vijf voorafgaande dagsloten.':'Kwaliteit, stijgende vijfdaagse trend en bevestigde slotuitbraak.',bars,signal_day:last.day,last_close:last.close,sigma,stop_fraction:Math.max(P.min_stop_fraction,P.volatility_multiple*sigma),recent_support:Math.min(...prices.slice(-5)),score:last.close/mean(prices)-1};
}
export function swingExitPlan(s,k,p,time){
 if(!p.swing)return netExitPlan(s,k,p,time);
 const policy={...NET_EXIT_POLICY,version:P.version,min_reward_risk:0},plan=netExitPlan(s,k,p,time,policy),required=Math.max(10/5,p.cost*.025,P.net_reward_risk*p.swing.initial_stop_loss_eur/5);
 let lo=p.entry,hi=p.entry*1.1;for(let i=0;i<30&&sale(s,k,p,hi).net_pnl_eur<required;i++)hi*=1.25;
 if(sale(s,k,p,hi).net_pnl_eur<required)throw Error('No finite swing target');
 for(let i=0;i<60;i++){const m=(lo+hi)/2;if(sale(s,k,p,m).net_pnl_eur>=required)hi=m;else lo=m;}
 return{required,target:hi,proof:{...plan.proof,minimum_reward_risk:P.net_reward_risk,estimated_stop_loss_eur:p.swing.initial_stop_loss_eur,required_net_profit_eur:required*5,target_execution_price_eur:hi*5,initial_risk_fixed:true}};
}
export function swingExitCheck(s,k,p,q,time){
 if(!p.swing)return exitQuoteCheck(s,k,p,q,time);
 const plan=swingExitPlan(s,k,p,time),price=q.bid*.9995/q.fx_per_eur,net=sale(s,k,p,price).net_pnl_eur;
 return{...plan,price,net,eligible:net>=plan.required,proof:{...plan.proof,expected_net_profit_eur:net*5,quote_time:q.time}};
}
export function heldStopRisk(s){let total=0;
 for(const[k,p]of Object.entries(s.positions)){const stop=sale(s,k,p,p.stop*(1-(p.swing?P.gap_reserve_fraction:.001))).net_pnl_eur,mark=sale(s,k,p,s.prices[k]/fx(s,k)*.9995).net_pnl_eur;const risk=Math.max(0,-stop,mark-stop)*5;if(!Number.isFinite(risk))throw Error('Unknown portfolio risk');total+=risk;}return total;
}
export function swingCandidate(input,s,k,q,time){
 const d=input.company_dossiers?.[k],signal=dailySignal(input.company_daily?.[k],k,time),assessment=assessCompany(d,q?(q.bid+q.ask)/2*5:null,q?.currency,time,input.company_policy),no=reason=>({eligible:false,reason,assessment,signal});
 if(!assessment.eligible)return no('Niet alle vijf actuele bedrijfspijlers zijn goedgekeurd.');
 if(d.price_window_status==='corporate_action_requires_review')return no('Onopgeloste bedrijfsactie.');
 if(!signal.eligible)return no(signal.reason);
 if(!validQuote(k,q,time))return no('Geen verse uitvoeringskoers.');
 // First/last thirty minutes excluded, and no chasing large overnight gaps.
 if(time<Date.parse(q.session_start)+1800000||time>=Date.parse(q.session_end)-1800000)return no('Buiten het instapvenster van de sessie.');
 const localEntry=q.ask*1.0005*5,entry=localEntry/5/q.fx_per_eur,gap=localEntry/signal.last_close-1;
 if(gap<-.01||gap>P.max_entry_gap_fraction)return no('Actuele instap ligt meer dan 1% van het bevestigde dagslot.');
 const stopFraction=Math.max(signal.stop_fraction,1-signal.recent_support/localEntry+.005);
 if(stopFraction>P.max_stop_fraction)return no('Benodigde stop is breder dan 8%; geen verkleinde kunstmatige stop.');
 let held;try{held=heldStopRisk(s);}catch{return no('Portefeuillerisico onbekend.');}
 const available=Math.min(P.max_order_eur/5,s.cash-s.risk.config.min_cash_eur),preview=budget=>{
  const buy=purchase(s,k,entry,budget),cost=buy.qty*entry+buy.fee+Object.values(buy.tax).reduce((a,b)=>a+b,0),p={qty:buy.qty,cost,entry,entry_gross_eur:buy.qty*entry,stop:entry*(1-stopFraction)};
  const risk=Math.max(0,-sale(s,k,p,p.stop*(1-P.gap_reserve_fraction)).net_pnl_eur)*5,flat=Math.max(0,-sale(s,k,p,q.bid*.9995/q.fx_per_eur).net_pnl_eur)*5;
  return{budget_eur:budget*5,cost_eur:cost*5,estimated_stop_loss_eur:risk,round_trip_cost_fraction:flat/(cost*5),stop_fraction:stopFraction,held_stop_risk_eur:held};
 };
 if(available<P.min_order_eur/5)return no('Onvoldoende kas voor de minimale positie.');
 let lo=P.min_order_eur/5,hi=available;
 const fits=x=>x.estimated_stop_loss_eur<=P.max_new_stop_loss_eur+1e-9&&held+x.estimated_stop_loss_eur<=P.max_total_stop_loss_eur+1e-9;
 if(!fits(preview(lo)))return no('Stoprisico past niet binnen €20 per positie en €150 gezamenlijk.');
 for(let i=0;i<45;i++){const m=(lo+hi)/2;if(fits(preview(m)))lo=m;else hi=m;}
 const proof=preview(lo);
 if(proof.round_trip_cost_fraction>P.max_round_trip_cost_fraction)return no('Koop-/verkoopfrictie is hoger dan 1,5%.');
 return{eligible:true,reason:signal.reason,assessment,signal,score:signal.score,proof};
}
export function reviewSwingPosition(s,k,p,rows,d,time){
 if(!p.swing)return null;
 const bars=completedBars(rows,k,time),last=bars.at(-1),entryDay=day(p.time,BY_SYMBOL[k].timezone),sessions=bars.filter(b=>b.day>=entryDay).length;
 const flags=d?.review?.risks?.flags||[],reviewed=Date.parse(d?.review?.reviewed_at);
 if(reviewed<=time&&reviewed>=Date.parse(p.time)&&flags.some(x=>['thesis_broken','critical'].includes(x)))return{exit:true,kind:'thesis',review_id:d.review.id,reviewed_at:d.review.reviewed_at};
 if(last&&time-Date.parse(last.day+'T00:00:00Z')<=7*DAY){
  if(sessions>=P.max_holding_sessions)return{exit:true,kind:'time',sessions,last_day:last.day};
  // Trailing starts only after a completed close exceeds one initial price-risk.
  if(last.day>=(p.swing.last_review_day||'')){
   const eur=last.close/5/fx(s,k),initialDistance=p.swing.initial_stop_fraction*p.entry;
   if(eur>=p.entry+initialDistance){const fraction=Math.max(P.min_stop_fraction,p.swing.volatility_fraction),raised=eur*(1-fraction);p.stop=Math.max(p.stop,raised);}
   p.swing.last_review_day=last.day;
  }
 }
 return null;
}
