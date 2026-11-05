import {base,serviceKey} from './platform.js';
import {tick,equity,fx,day,validQuote} from './engine.js';
import {compactAccount,hydrateAccount,learningFingerprint,markedAccount} from './learning-runtime.js';
import {BY_SYMBOL} from './catalogue.js';
import {CAPITAL_IMPLEMENTATION_SHA} from './capital-implementation.js';
export const CAPITAL_POLICY={version:'capital-10k-v1',account:'capital10k',initial_eur:10000,order_eur:500,unit_eur:5,max_positions:12,max_per_sector:2,max_buys_per_day:12,min_cash_eur:1000,daily_loss_eur:200,max_drawdown_eur:500,max_exposure_fraction:.8,max_trades:2000,entry_trade_limit:1800,max_month_bytes:300000000,soft_month_bytes:240000000,soft_bytes:12000000,max_bytes:20000000,soft_database_bytes:120000000,max_database_bytes:150000000,soft_total_month_bytes:1200000000,max_total_month_bytes:1500000000};
const clone=structuredClone,RISK_MONEY=['min_cash_eur','daily_loss_eur','max_drawdown_eur'],COST_MONEY=['us_minimum_commission_usd','other_minimum_commission_eur','adr_buy_reserve_usd_per_share'],TAX_MONEY=['transaction_tax_cap_eur','minimum_net_profit_eur'];
function amounts(obj,keys,factor){const out=clone(obj);for(const k of keys)if(typeof out[k]==='number')out[k]*=factor;return out;}
function moneyObject(obj,factor){return Object.fromEntries(Object.entries(obj||{}).map(([k,v])=>[k,typeof v==='number'?v*factor:v]));}
function prices(rows,factor){return rows.map(x=>({...x,price:x.price*factor}));}
export function capitalBatch(batch){const b=clone(batch),u=CAPITAL_POLICY.unit_eur;for(const q of Object.values(b.quotes||{})){q.bid/=u;q.ask/=u;}return b;}
export function capitalMarket(account,market){
 const u=CAPITAL_POLICY.unit_eur,s=hydrateAccount(account,market);s.running=true;s.operation_mode='continuous';
 s.risk.config=amounts({...market.risk.config,min_cash_eur:1000,daily_loss_eur:200,max_drawdown_eur:500,max_positions:12,max_buys_per_day:12,max_exposure_fraction:.8},RISK_MONEY,1/u);s.risk.version='capital-risk-v1';
 for(const q of Object.values(s.risk.previous_quotes||{}))q.price/=u;
 s.catalogue={...market.catalogue,max_positions_per_sector:2};s.multi_market.cost_assumptions=amounts(market.multi_market.cost_assumptions,COST_MONEY,1/u);
 s.belgian_tax.config=amounts(market.belgian_tax.config,TAX_MONEY,1/u);
 s.prices=Object.fromEntries(Object.entries(market.prices).map(([k,v])=>[k,v/u]));s.history=Object.fromEntries(Object.entries(market.history).map(([k,v])=>[k,prices(v,1/u)]));return s;
}
export function initialCapital(market,time=Date.now()){
 const s=clone(market),u=CAPITAL_POLICY.unit_eur;s.cash=10000/u;s.peak=s.cash;s.fees=0;s.realized=0;s.max_drawdown=0;s.positions={};s.pending=[];s.tick=0;s.error=null;s.last_update=null;s.last_decision=null;s.running=true;s.operation_mode='continuous';
 s.risk={...s.risk,day:day(time),day_start_equity:s.cash,buys_today:0,daily_halted:false,global_halted:false,global_reason:null,data_complete:true,previous_quotes:{},cooldowns:{}};
 s.belgian_tax={...s.belgian_tax,transaction_tax_eur:0,capital_gains_reserve_eur:0};s.multi_market={...s.multi_market,foreign_tax_reserve_eur:0,adr_reserve_eur:0};
 return compactAccount(s);
}
function realRationale(r,u){if(!r)return r;const a=clone(r),d=a.decision||{},c=a.cost_estimate,risk=a.risk_at_decision,e=a.execution;
 for(const k of ['previous_five_average','latest_mid'])if(typeof d[k]==='number')d[k]*=u;if(d.observations)d.observations=prices(d.observations,u);
 if(c){for(const k of ['budget_eur','commission_eur','flat_round_trip_loss_eur','gross_target_price_eur','minimum_net_profit_eur'])if(typeof c[k]==='number')c[k]*=u;c.buy_taxes_and_reserves=moneyObject(c.buy_taxes_and_reserves,u);}
 if(risk){risk.cash_eur*=u;risk.equity_eur*=u;risk.config=amounts(risk.config,RISK_MONEY,u);}
 if(e){for(const k of ['price_local','commission_eur','cost_eur','cash_after_eur'])if(typeof e[k]==='number')e[k]*=u;e.taxes_and_reserves=moneyObject(e.taxes_and_reserves,u);}
 a.account=CAPITAL_POLICY.account;a.capital_protocol=CAPITAL_POLICY.version;return a;
}
export function realCapitalTrade(trade){
 const u=CAPITAL_POLICY.unit_eur,t=clone(trade),s=t.snapshot;t.price*=u;t.fee*=u;t.pnl*=u;t.reason=t.reason.replace('Budget EUR100','Budget EUR500');t.account=CAPITAL_POLICY.account;
 for(const k of ['cash','equity','price_local','price_usd'])if(typeof s[k]==='number')s[k]*=u;
 s.tax_detail=moneyObject(s.tax_detail,u);s.tax_config=amounts(s.tax_config,TAX_MONEY,u);s.risk_config=amounts(s.risk_config,RISK_MONEY,u);s.multi_market_config=amounts(s.multi_market_config,COST_MONEY,u);
 s.history=prices(s.history||[],u);if(s.quote){s.quote.bid*=u;s.quote.ask*=u;}s.reason=t.reason;s.account=CAPITAL_POLICY.account;s.purchase_rationale=realRationale(s.purchase_rationale,u);return t;
}
export async function stepCapital(input,market,batch,time=Date.now()){
 if(input.policy?.implementation_sha256!==CAPITAL_IMPLEMENTATION_SHA||input.policy.reference_fingerprint!==await learningFingerprint(market))throw Error('Capital profile differs');
 const account=capitalMarket(input.state,market),b=capitalBatch(batch),out=tick(account,b,time,{captureFeatures:true,contextTag:{policy:CAPITAL_POLICY.account,capital_protocol:CAPITAL_POLICY.version},entryGate:()=>input.allow_entries===true});
 const u=CAPITAL_POLICY.unit_eur,marked=markedAccount(out.state),summary={...marked};for(const k of ['equity_eur','liquidation_eur','cash_eur','realized_eur','fees_eur','max_drawdown_eur'])summary[k]*=u;
 summary.return_percent=(summary.liquidation_eur/10000-1)*100;summary.daily_halted=out.state.risk.daily_halted;summary.global_halted=out.state.risk.global_halted;summary.last_market_update=out.state.last_update;summary.checked_at=new Date(time).toISOString();summary.status=out.equity?input.allow_entries?'collecting':'finishing_only':'waiting_quotes';summary.error=out.state.error;
 summary.risk_config=amounts(out.state.risk.config,RISK_MONEY,u);summary.buys_today=out.state.risk.buys_today;
 summary.positions_detail=Object.entries(out.state.positions).map(([symbol,p])=>({symbol,company:BY_SYMBOL[symbol].name,sector:BY_SYMBOL[symbol].sector,qty:p.qty,cost_eur:p.cost*u,entry_eur:p.entry*u,mark_eur:p.qty*out.state.prices[symbol]/fx(out.state,symbol)*u,quote_time:out.state.last_observation[symbol]?.time||null,fresh:validQuote(symbol,b.quotes[symbol],time)}));
 return {protocol:CAPITAL_POLICY.version,revision:input.revision,state:compactAccount(out.state),summary,trades:out.trades.map(realCapitalTrade),new_orders:out.events.filter(e=>e.kind==='besluit'&&e.data?.side==='koop').length};
}

// Optional work gets a short deadline so a failed experimental RPC cannot
// consume the original market round's lease while quotes age.
export async function capitalRpc(name,args={}){
 if(!['paper_capital_claim','paper_capital_commit','paper_capital_fail'].includes(name))throw Error('Invalid capital RPC');
 const r=await fetch(base()+'/rest/v1/rpc/'+name,{method:'POST',headers:{apikey:serviceKey(),Authorization:'Bearer '+serviceKey(),'Content-Type':'application/json'},body:JSON.stringify(args),signal:AbortSignal.timeout(5000)});
 if(!r.ok)throw Error('Capital RPC unavailable');return r.json();
}
