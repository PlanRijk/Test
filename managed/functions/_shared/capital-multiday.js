import {base,serviceKey} from './platform.js';
import {fx,validQuote} from './engine.js';
import {tickMultiday} from './engine-multiday.js';
import {capitalMarket,capitalBatch,realCapitalTrade} from './capital-study.js';
import {compactAccount,learningFingerprint,markedAccount} from './learning-runtime.js';
import {BY_SYMBOL} from './catalogue.js';
import {CAPITAL_IMPLEMENTATION_SHA} from './capital-implementation.js';
import {MULTIDAY_IMPLEMENTATION_SHA} from './multiday-implementation.js';
export const MULTIDAY_POLICY={version:'capital-multiday-v2',account:'capital10k',close_at_session_end:false,holding_horizon:'multiple_sessions',review_horizon_sessions:20,force_exit_at_review:false,carry_protective_sells:true,stop_fraction:.015,base_profit_fraction:.025,minimum_quote_age_seconds:0,maximum_quote_age_seconds:120,order_eur:500,minimum_cash_eur:1000,max_positions:12,max_per_sector:2,max_buys_per_day:12,max_exposure_fraction:.8,daily_loss_eur:200,max_drawdown_eur:500,additional_market_downloads:0};
const money=['min_cash_eur','daily_loss_eur','max_drawdown_eur'];
export async function stepCapitalMultiday(input,market,batch,time=Date.now()){
 const p=input.execution_policy;
 if(!p||p.version!==MULTIDAY_POLICY.version||p.implementation_sha256!==MULTIDAY_IMPLEMENTATION_SHA||p.base_implementation_sha256!==CAPITAL_IMPLEMENTATION_SHA||input.policy.implementation_sha256!==CAPITAL_IMPLEMENTATION_SHA||input.policy.reference_fingerprint!==await learningFingerprint(market))throw Error('Multiday profile differs');
 const account=capitalMarket(input.state,market),out=tickMultiday(account,capitalBatch(batch),time,{captureFeatures:true,contextTag:{policy:'capital10k',capital_protocol:p.version,execution_profile:input.execution_profile},entryGate:()=>input.allow_entries===true});
 for(const o of out.state.pending)if(o.side==='koop'&&o.purchase_rationale)o.purchase_rationale.holding_policy={version:p.version,profile:input.execution_profile,close_at_session_end:false,review_horizon_sessions:20,note:'Meerdere handelsdagen mogelijk; koers-/risicostop en kostenbewust winstdoel blijven actief. Geen voorspelling van een grote dagsprong.'};
 const summary=markedAccount(out.state);for(const k of ['equity_eur','liquidation_eur','cash_eur','realized_eur','fees_eur','max_drawdown_eur'])summary[k]*=5;
 summary.return_percent=(summary.liquidation_eur/10000-1)*100;summary.daily_halted=out.state.risk.daily_halted;summary.global_halted=out.state.risk.global_halted;summary.last_market_update=out.state.last_update;summary.checked_at=new Date(time).toISOString();summary.status=out.equity?input.allow_entries?'collecting':'finishing_only':'waiting_quotes';summary.error=out.state.error;
 summary.risk_config={...out.state.risk.config};for(const k of money)summary.risk_config[k]*=5;summary.buys_today=out.state.risk.buys_today;
 summary.execution_policy=p.version;summary.execution_profile=input.execution_profile;summary.close_at_session_end=false;
 summary.positions_detail=Object.entries(out.state.positions).map(([symbol,pos])=>({symbol,company:BY_SYMBOL[symbol].name,sector:BY_SYMBOL[symbol].sector,qty:pos.qty,cost_eur:pos.cost*5,entry_eur:pos.entry*5,entry_at:pos.time,mark_eur:pos.qty*out.state.prices[symbol]/fx(out.state,symbol)*5,quote_time:out.state.last_observation[symbol]?.time||null,fresh:validQuote(symbol,batch.quotes[symbol],time)}));
 const trades=out.trades.map(raw=>{
  const entryProtocol=raw.snapshot.learning_context?.capital_protocol||'capital-10k-v1',t=realCapitalTrade(raw),s=t.snapshot;
  s.execution_policy={version:p.version,profile:input.execution_profile,revision:input.execution_revision,close_at_session_end:false};s.entry_capital_protocol=entryProtocol;
  s.strategy_version+='+'+p.version;
  if(s.purchase_rationale){s.purchase_rationale.capital_protocol=t.side==='koop'?p.version:entryProtocol;if(t.side==='koop')s.purchase_rationale.holding_policy={version:p.version,profile:input.execution_profile,close_at_session_end:false,review_horizon_sessions:20};}
  return t;
 });
 return {protocol:p.version,execution_profile:input.execution_profile,execution_revision:input.execution_revision,revision:input.revision,state:compactAccount(out.state),summary,trades,new_orders:out.events.filter(e=>e.kind==='besluit'&&e.data?.side==='koop').length};
}
export async function capitalMultidayRpc(name,args={}){
 if(!['paper_capital_claim_multiday','paper_capital_commit_multiday','paper_capital_fail'].includes(name))throw Error('Invalid multiday RPC');
 const r=await fetch(base()+'/rest/v1/rpc/'+name,{method:'POST',headers:{apikey:serviceKey(),Authorization:'Bearer '+serviceKey(),'Content-Type':'application/json'},body:JSON.stringify(args),signal:AbortSignal.timeout(5000)});
 if(!r.ok)throw Error('Multiday RPC unavailable');return r.json();
}
