import {SWING_IMPLEMENTATION_SHA} from './swing-implementation.js';
import {base,serviceKey} from './platform.js';
import {fx,validQuote} from './engine.js';
import {capitalMarket,capitalBatch,realCapitalTrade} from './capital-study.js';
import {compactAccount,markedAccount,learningFingerprint} from './learning-runtime.js';
import {BY_SYMBOL} from './catalogue.js';
import {tickSwing} from './engine-swing.js';
import {SWING_POLICY,swingCandidate,swingExitPlan,heldStopRisk} from './swing-rules.js';
import {CAPITAL_IMPLEMENTATION_SHA} from './capital-implementation.js';
export async function stepCapitalSwing(input,market,batch,time=Date.now()){
 if(!input.swing_profile||input.swing_policy?.version!==SWING_POLICY.version||input.swing_policy.implementation_sha256!==SWING_IMPLEMENTATION_SHA||!input.swing_implementation_sha256)throw Error('Swing profile absent');
 if(input.policy?.implementation_sha256!==CAPITAL_IMPLEMENTATION_SHA||input.policy.reference_fingerprint!==await learningFingerprint(market))throw Error('Financial reference changed');
 if(!input.recent_exits||typeof input.recent_exits!=='object'||Array.isArray(input.recent_exits))throw Error('Recent exit evidence missing');
 const s=capitalMarket(input.state,market),b=capitalBatch(batch);
 s.risk.config.max_buys_per_day=SWING_POLICY.max_buys_per_day;
 for(const[k,at]of Object.entries(input.recent_exits||{})){const until=Date.parse(at)+86400000;if(Number.isFinite(until)&&until>(Date.parse(s.risk.cooldowns[k])||0))s.risk.cooldowns[k]=new Date(until).toISOString();}
 const checks=new Map(),check=(k,state,q,t)=>{const c=swingCandidate(input,state,k,q,t);checks.set(k,{symbol:k,eligible:c.eligible,pillars_eligible:c.assessment.eligible,reason:c.reason,signal_day:c.signal?.signal_day||null,proof:c.proof||null});return c;};
 const out=tickSwing(s,b,time,{companyProfile:input.company_profile,swingProfile:input.swing_profile,companyDaily:input.company_daily,companyDossiers:input.company_dossiers,companyCheck:check,entryGate:({symbol,state,time:at})=>input.allow_entries===true&&check(symbol,state,b.quotes[symbol],at).eligible});
 for(const[k,p]of Object.entries(out.state.positions)){p.net_exit=swingExitPlan(out.state,k,p,time).proof;p.target=p.net_exit.target_execution_price_eur/5;}
 const summary=markedAccount(out.state);for(const k of ['equity_eur','liquidation_eur','cash_eur','realized_eur','fees_eur','max_drawdown_eur'])summary[k]*=5;
 Object.assign(summary,{return_percent:(summary.liquidation_eur/10000-1)*100,daily_halted:out.state.risk.daily_halted,global_halted:out.state.risk.global_halted,last_market_update:out.state.last_update,checked_at:new Date(time).toISOString(),status:out.equity?input.allow_entries?'collecting':'finishing_only':'waiting_quotes',error:out.state.error,risk_config:{...out.state.risk.config},buys_today:out.state.risk.buys_today,company_policy:'company-entry-v1',company_profile:input.company_profile,company_ready:[...checks.values()].filter(c=>c.pillars_eligible).map(c=>c.symbol),execution_policy:SWING_POLICY.version,execution_profile:input.swing_profile,profit_exit_policy:'mixed-legacy-and-swing',close_at_session_end:false,priority_mode:'daily_weekly_paper_active',new_entries_allowed:input.allow_entries===true,swing_policy:SWING_POLICY.version,swing_profile:input.swing_profile,entry_audit_policy:SWING_POLICY.version,entry_audit:{held_stop_risk_eur:heldStopRisk(out.state),held_risk_known:true,counts:{}},swing_checks:[...checks.values()].slice(0,20),costs_verified:false,live_trading_allowed:false});
 for(const k of ['min_cash_eur','daily_loss_eur','max_drawdown_eur'])summary.risk_config[k]*=5;
 summary.positions_detail=Object.entries(out.state.positions).map(([symbol,p])=>({symbol,company:BY_SYMBOL[symbol].name,sector:BY_SYMBOL[symbol].sector,qty:p.qty,cost_eur:p.cost*5,entry_eur:p.entry*5,entry_at:p.time,mark_eur:p.qty*out.state.prices[symbol]/fx(out.state,symbol)*5,quote_time:out.state.last_observation[symbol]?.time||null,profit_exit:p.net_exit,holding_policy:p.swing?.version||'legacy-net-exits-v1',stop_eur:p.stop*5,fresh:validQuote(symbol,batch.quotes[symbol],time)}));
 const trades=out.trades.map(raw=>{const t=realCapitalTrade(raw),snap=t.snapshot;
  snap.execution_policy={version:SWING_POLICY.version,profile:input.swing_profile,close_at_session_end:false};
  snap.profit_exit={...snap.profit_exit,profile:raw.side==='koop'||raw.snapshot.profit_exit.version===SWING_POLICY.version?input.swing_profile:input.exit_profile};
  snap.strategy_version+='+'+SWING_POLICY.version;
  if(t.side==='koop'){
   const p=out.state.positions[t.symbol];
   // Actual executed quantities are authoritative, not a previous queue estimate.
   const r=snap.purchase_rationale;r.cost_estimate.budget_eur=r.execution.cost_eur;r.decision.observations=raw.snapshot.purchase_rationale.decision.observations;
   snap.swing_entry={version:SWING_POLICY.version,profile:input.swing_profile,signal_day:p.swing.signal_day,stop_fraction:p.swing.initial_stop_fraction,estimated_stop_loss_eur:p.swing.initial_stop_loss_eur,cost_eur:p.cost*5,held_stop_risk_eur:r.swing_entry.held_stop_risk_eur,round_trip_cost_fraction:r.swing_entry.round_trip_cost_fraction};
   r.company_execution_check.assessment.dossier_id=input.company_dossiers[t.symbol].id;
  }else{const until=time+86400000,old=Date.parse(out.state.risk.cooldowns[t.symbol]||0);out.state.risk.cooldowns[t.symbol]=new Date(Math.max(until,Number.isFinite(old)?old:0)).toISOString();}
  return t;
 });
 return{protocol:SWING_POLICY.version,swing_profile:input.swing_profile,revision:input.revision,state:compactAccount(out.state),summary,trades,new_orders:out.events.filter(e=>e.kind==='besluit'&&e.data?.side==='koop').length};
}
export async function swingRpc(name,args={}){
 if(!['paper_swing_claim','paper_swing_commit','paper_capital_fail'].includes(name))throw Error('Invalid swing RPC');
 const r=await fetch(base()+'/rest/v1/rpc/'+name,{method:'POST',headers:{apikey:serviceKey(),Authorization:'Bearer '+serviceKey(),'Content-Type':'application/json'},body:JSON.stringify(args),signal:AbortSignal.timeout(6000)});
 if(!r.ok)throw Error('Swing RPC unavailable');return r.json();
}
