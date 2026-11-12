import {iso,entryBudget,purchase,validQuote,profile,currency,profitTarget,equity,sale} from './engine.js';
import {SWING_POLICY,swingExitPlan} from './swing-rules.js';
function event(out,kind,reason,time,symbol='',data={}){out.events.push({time:iso(time),kind,symbol,reason,data});}
function affordable(s,k,price,budget) {
  const buy=purchase(s,k,price,budget),gross=buy.qty*price,cost=gross+buy.fee+Object.values(buy.tax).reduce((a,b)=>a+b,0);
  const p={qty:buy.qty,entry:price,entry_gross_eur:gross,cost},loss=Math.max(0,-sale(s,k,p,price*.998).net_pnl_eur);
  let exits=0;for(const [x,pos]of Object.entries(s.positions)){const d=sale(s,x,pos,s.prices[x]/fx(s,x)*.999);exits+=Math.max(0,d.gross_eur-(pos.cost+d.net_pnl_eur));}
  const value=equity(s),c=s.risk.config;
  return loss<=Math.min(c.daily_loss_eur-Math.max(0,(s.risk.day_start_equity??value)-value)-exits,c.max_drawdown_eur-Math.max(0,s.peak-value)-exits)+1e-9;
}
export function fillSwing(s,order,q,time,out) {
  const k=order.symbol;if(!validQuote(k,q,time)||Date.parse(q.time)<=Date.parse(order.time))return false;
  const buy=order.side==='koop',price=(buy?q.ask*1.0005:q.bid*.9995),eur=price/q.fx_per_eur;
  s.price_fx[k]=q.fx_per_eur;s.prices[k]=(q.bid+q.ask)/2;s.last_observation[k]={time:q.time,indicative:true};
  let qty,fee,tax,pnl=0,learningContext=order.learning_context||null,rationale=order.purchase_rationale||null;
  if(buy){
    if(s.positions[k])return true;const budget=Math.min(entryBudget(s,k,time),order.swing_plan?.budget_eur/5??100);
    if(budget<10||!affordable(s,k,eur,budget)){event(out,'kostenrem','Aankoop past niet binnen het risico-/kostenbudget.',time,k);return true;}
    ({qty,fee,tax}=purchase(s,k,eur,budget));const cost=qty*eur+fee+Object.values(tax).reduce((a,b)=>a+b,0);s.cash-=cost;if(s.cash<0&&s.cash>-1e-8)s.cash=0;
    if(learningContext)learningContext={...learningContext,entry_time:iso(time)};
    if(!rationale)rationale={schema:'purchase-rationale-v1',id:k+'|'+order.time,recorded_at:iso(time),profile:profile(s),
      decision:{time:order.time,symbol:k,statement:order.reason,detail_unavailable:true,note:'Deze order bestond al voor de uitgebreide motivatie; ontbrekende beslisgegevens zijn niet achteraf verzonnen.'}};
    rationale=structuredClone(rationale);rationale.execution={time:iso(time),decision_time:order.time,quote_time:q.time,quote_age_seconds:(time-Date.parse(q.time))/1000,
     statement:'Virtuele aankoop op een latere verse bronkoers; saldo-, sector-, kosten- en risicocontroles bij uitvoering geslaagd.',
     price_local:price,currency:q.currency,fx_per_eur:q.fx_per_eur,quantity:qty,commission_eur:fee,taxes_and_reserves:tax,cost_eur:cost,cash_after_eur:s.cash};
    const p={qty,cost,entry_gross_eur:qty*eur,entry:eur,time:iso(time),stop:eur*(1-(order.swing_plan?.stop_fraction??.015)),target:eur*1.025,currency:currency(k)};
    if(order.swing_plan){const sp=order.swing_plan;p.swing={version:SWING_POLICY.version,profile:sp.profile,signal_day:sp.signal_day,initial_stop_fraction:sp.stop_fraction,volatility_fraction:sp.volatility_fraction,initial_stop_loss_eur:Math.max(0,-sale(s,k,p,p.stop*(1-SWING_POLICY.gap_reserve_fraction)).net_pnl_eur)*5};}
    if(learningContext)p.learning_context=learningContext;
    // The immutable full explanation lives in the buy receipt; carry its ID to exit.
    p.purchase_rationale={schema:rationale.schema,id:rationale.id,decision:{time:rationale.decision.time,symbol:k,statement:rationale.decision.statement}};
    p.target=p.swing?swingExitPlan(s,k,p,time).target:profitTarget(s,k,p);s.positions[k]=p;s.risk.buys_today++;
  }else{
    const p=s.positions[k];if(!p)return true;
    learningContext=p.learning_context||null;
    rationale=p.purchase_rationale||null;
    tax=sale(s,k,p,eur);
    const protective=order.risk_exit||eur<=p.stop||s.risk.daily_halted||s.risk.global_halted;
    if(!protective&&tax.net_pnl_eur<s.belgian_tax.config.minimum_net_profit_eur){event(out,'belastingfilter','Gewone verkoop onvoldoende netto positief.',time,k);return true;}
    qty=p.qty;fee=tax.commission_eur;pnl=tax.net_pnl_eur;s.cash+=tax.gross_eur-fee-tax.transaction_tax_eur-tax.capital_gains_reserve_eur-tax.foreign_tax_reserve_eur-tax.adr_reserve_eur;s.realized+=pnl;delete s.positions[k];
    if(pnl<0)s.risk.cooldowns[k]=iso(time+s.risk.config.loss_cooldown_minutes*60000);
  }
  s.fees+=fee;s.belgian_tax.transaction_tax_eur+=tax.transaction_tax_eur;s.belgian_tax.capital_gains_reserve_eur+=tax.capital_gains_reserve_eur;
  for(const key of ['foreign_tax_reserve_eur','adr_reserve_eur'])s.multi_market[key]+=tax[key]||0;
  const snapshot={swing_exit_evidence:order.swing_exit_evidence||null,strategy_version:profile(s),transport_version:'supabase-v1',tax_scenario:true,tax_config:s.belgian_tax.config,tax_detail:tax,risk_config:s.risk.config,multi_market_config:s.multi_market.cost_assumptions,
    cash:s.cash,equity:equity(s),fx:q.fx_per_eur,currency:currency(k),price_local:price,price_usd:currency(k)==='USD'?price:null,history:s.history[k].slice(-40),quote:q,mode:'yahoo',reason:order.reason,decision_time:order.time,qty,side:order.side,symbol:k,time:iso(time),learning_context:learningContext,purchase_rationale:rationale};
  out.trades.push({time:iso(time),symbol:k,side:order.side,qty,price,fee,pnl,reason:order.reason,snapshot});event(out,'uitvoering','Virtuele uitvoering op latere verse koers.',time,k);return true;
}
