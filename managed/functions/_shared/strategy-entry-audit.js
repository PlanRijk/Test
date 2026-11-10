import{capitalMarket,capitalBatch}from'./capital-study.js';
import{stepCapitalNetExits}from'./capital-net-exits.js';
import{purchase,sale,validQuote,fx}from'./engine.js';
import{netExitPlan}from'./net-exit-policy.js';
import{assessCompany}from'./company-analysis.js';
import{AUDIT_IMPLEMENTATION_SHA}from'./strategy-audit-implementation.js';
import{base,serviceKey}from'./platform.js';
export const AUDIT_POLICY={version:'entry-audit-v1',account:'capital10k',unit_eur:5,max_round_trip_cost_fraction:.015,reentry_hours:24,max_new_stop_loss_eur:20,max_total_stop_loss_eur:150,force_sell_existing:false,change_stop_distance:false,change_profit_targets:false,automatic_model_approval:false,additional_market_downloads:0,real_orders:false};
const allowedCodes=['company_pillars','no_fresh_quote','reentry_cooldown','round_trip_cost','single_stop_risk','portfolio_stop_risk','unknown_risk'];
const stamp=t=>new Date(t).toISOString();
function extendCooldown(state,k,until){state.risk.cooldowns||={};const old=Date.parse(state.risk.cooldowns[k]);if(!Number.isFinite(old)||old<until)state.risk.cooldowns[k]=stamp(until);}
export function auditEntries(input,market,batch,time=Date.now()){
 const policy=AUDIT_POLICY,state=structuredClone(input.state),recent=input.recent_exits;
 if(!recent||typeof recent!=='object'||Array.isArray(recent))throw Error('Recent exit evidence missing');
 for(const[k,at]of Object.entries(recent)){const t=Date.parse(at);if(Number.isFinite(t))extendCooldown(state,k,t+policy.reentry_hours*3600000);}
 const account=capitalMarket(state,market),scaled=capitalBatch(batch),unit=policy.unit_eur;
 if(Number.isFinite(batch.fx?.usd_per_eur)&&batch.fx.usd_per_eur>0){account.usd_per_eur=batch.fx.usd_per_eur;account.fx_time=batch.fx.date;}
 for(const[k,q]of Object.entries(scaled.quotes||{}))if(validQuote(k,q,time)){account.prices[k]=(q.ask+q.bid)/2;account.price_fx[k]=q.fx_per_eur;}
 let heldRisk=0,riskKnown=true;
 for(const[k,p]of Object.entries(account.positions)){try{const plan=netExitPlan(account,k,p,time),q=scaled.quotes[k],mark=validQuote(k,q,time)?q.bid*.9995/q.fx_per_eur:account.prices[k]/fx(account,k)*.999,decline=(sale(account,k,p,mark).net_pnl_eur-sale(account,k,p,plan.proof.stop_execution_price_eur/unit).net_pnl_eur)*unit,risk=Math.max(plan.proof.estimated_stop_loss_eur,decline);if(!Number.isFinite(risk))throw Error('Unknown held risk');heldRisk+=risk;}catch{riskKnown=false;}}
 const checks=[];
 for(const[k,d]of Object.entries(input.company_dossiers||{})){
  if(account.positions[k])continue;
  const q=scaled.quotes[k],original=batch.quotes?.[k],codes=[],proof={symbol:k,checked_at:stamp(time)};
  const assessment=assessCompany(d,original?(original.bid+original.ask)/2:null,original?.currency,time,input.company_policy);
  if(!assessment.eligible)codes.push('company_pillars');
  const until=state.risk.cooldowns?.[k];if(until&&Date.parse(until)>time){codes.push('reentry_cooldown');proof.cooldown_until=until;}
  if(!validQuote(k,q,time))codes.push('no_fresh_quote');else try{
   const entry=q.ask*1.0005/q.fx_per_eur,buy=purchase(account,k,entry,100),cost=buy.qty*entry+buy.fee+Object.values(buy.tax).reduce((a,b)=>a+b,0),p={qty:buy.qty,cost,entry,entry_gross_eur:buy.qty*entry,stop:entry*.985},plan=netExitPlan(account,k,p,time),flat=sale(account,k,p,q.bid*.9995/q.fx_per_eur).net_pnl_eur*unit;
   proof.cost_eur=cost*unit;proof.flat_round_trip_loss_eur=Math.max(0,-flat);proof.round_trip_cost_fraction=proof.flat_round_trip_loss_eur/proof.cost_eur;proof.estimated_stop_loss_eur=plan.proof.estimated_stop_loss_eur;proof.required_net_profit_eur=plan.proof.required_net_profit_eur;proof.quote_time=q.time;
   if(proof.round_trip_cost_fraction>policy.max_round_trip_cost_fraction+1e-12)codes.push('round_trip_cost');
   if(proof.estimated_stop_loss_eur>policy.max_new_stop_loss_eur+1e-9)codes.push('single_stop_risk');
  }catch{codes.push('unknown_risk');}
  if(!riskKnown)codes.push('unknown_risk');
  const h=market.history?.[k]?.slice(-5)||[],avg=h.length===5?h.reduce((n,x)=>n+x.price,0)/5:0;
  checks.push({...proof,codes:[...new Set(codes)],pending:(state.pending||[]).some(o=>o.symbol===k&&o.side==='koop'),score:avg&&original?(original.bid+original.ask)/2/avg-1:-Infinity});
 }
 checks.sort((a,b)=>Number(b.pending)-Number(a.pending)||b.score-a.score||b.symbol.localeCompare(a.symbol));
 let reserved=0;const dossiers={};
 for(const c of checks){if(!c.codes.length){if(heldRisk+reserved+c.estimated_stop_loss_eur>policy.max_total_stop_loss_eur+1e-9)c.codes.push('portfolio_stop_risk');else{reserved+=c.estimated_stop_loss_eur;dossiers[c.symbol]=input.company_dossiers[c.symbol];}}c.passed=c.codes.length===0;delete c.score;}
 const counts=Object.fromEntries(allowedCodes.map(k=>[k,checks.filter(c=>c.codes.includes(k)).length]));
 return{state,dossiers,snapshot:{version:policy.version,checked_at:stamp(time),held_stop_risk_eur:heldRisk,held_risk_known:riskKnown,held_risk_basis:'max_entry_stop_loss_or_current_mark_to_stop',reserved_entry_stop_risk_eur:reserved,max_total_stop_loss_eur:policy.max_total_stop_loss_eur,considered:checks.length,passed:checks.filter(c=>c.passed).length,counts,checks,note:'Controles op aangeleverde beoordeelde dossiers; geen volledige analyse van alle 100 bedrijven en geen onafhankelijke leertrades.'}};
}
export async function stepCapitalAudited(input,market,batch,time=Date.now()){
 if(!input.audit_profile||input.audit_policy?.implementation_sha256!==AUDIT_IMPLEMENTATION_SHA)throw Error('Audit policy differs');
 const audit=auditEntries(input,market,batch,time),out=await stepCapitalNetExits({...input,state:audit.state,company_dossiers:audit.dossiers},market,batch,time);
 for(const[k,until]of Object.entries(audit.state.risk.cooldowns||{})){const t=Date.parse(until);if(Number.isFinite(t))extendCooldown(out.state,k,t);}
 for(const t of out.trades){t.snapshot.strategy_audit={version:AUDIT_POLICY.version,profile:input.audit_profile};if(t.side==='koop'){
   const check=audit.snapshot.checks.find(c=>c.symbol===t.symbol&&c.passed);if(!check)throw Error('Entry audit proof missing');t.snapshot.entry_audit={...check,version:AUDIT_POLICY.version,profile:input.audit_profile,held_stop_risk_eur:audit.snapshot.held_stop_risk_eur,reserved_entry_stop_risk_eur:audit.snapshot.reserved_entry_stop_risk_eur};
  }else{const until=Date.parse(t.time)+AUDIT_POLICY.reentry_hours*3600000;extendCooldown(out.state,t.symbol,until);t.snapshot.strategy_audit.reentry_not_before=stamp(until);}}
 out.summary.company_ready=audit.snapshot.checks.filter(c=>!c.codes.includes('company_pillars')).map(c=>c.symbol);
 out.summary.entry_audit_policy=AUDIT_POLICY.version;out.summary.entry_audit_profile=input.audit_profile;
 out.summary.entry_audit={version:AUDIT_POLICY.version,profile:input.audit_profile,checked_at:audit.snapshot.checked_at,considered:audit.snapshot.considered,passed:audit.snapshot.passed,held_stop_risk_eur:audit.snapshot.held_stop_risk_eur,held_risk_known:audit.snapshot.held_risk_known,counts:audit.snapshot.counts};
 return{...out,audit_profile:input.audit_profile,audit_policy:AUDIT_POLICY.version,entry_audit_snapshot:audit.snapshot};
}
export async function auditedRpc(name,args={}){
 if(!['paper_audited_claim','paper_audited_commit','paper_capital_fail'].includes(name))throw Error('Invalid audited RPC');
 const r=await fetch(base()+'/rest/v1/rpc/'+name,{method:'POST',headers:{apikey:serviceKey(),Authorization:'Bearer '+serviceKey(),'Content-Type':'application/json'},body:JSON.stringify(args),signal:AbortSignal.timeout(6000)});
 if(!r.ok)throw Error('Audited RPC unavailable');return r.json();
}
