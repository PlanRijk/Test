import{capitalMarket,capitalBatch}from'./capital-study.js';import{BY_SYMBOL}from'./catalogue.js';import{possibleSession,validQuote,fx,sale}from'./engine.js';import{netExitPlan,exitQuoteCheck}from'./net-exit-policy.js';
export function exitAudit(input,time=Date.now()){
 if(!input.state)return{checked_at:new Date(time).toISOString(),positions:[],status:'no_account'};
 const s=capitalMarket(input.state,input.market),quotes=capitalBatch({quotes:input.quotes||{}}).quotes,positions=[];
 for(const[k,p]of Object.entries(s.positions))try{
  const q=quotes[k],fresh=validQuote(k,q,time),open=possibleSession(BY_SYMBOL[k],time),pending=s.pending.find(o=>o.symbol===k&&o.side==='verkoop'),plan=fresh?exitQuoteCheck(s,k,p,q,time):netExitPlan(s,k,p,time),protective=!!(pending?.risk_exit||s.risk.daily_halted||s.risk.global_halted||fresh&&(pending?q.bid*.9995/q.fx_per_eur<=p.stop:(q.bid+q.ask)/2/q.fx_per_eur<=p.stop)),newer=fresh&&(!pending||Date.parse(q.time)>Date.parse(pending.time));
  let status=input.enabled===false||input.main_running===false?'collector_paused':!open?'market_closed':!fresh?'no_fresh_quote':!newer?'waiting_later_quote':protective?'protective_ready':plan.eligible?'profit_target_ready':plan.net*5>=plan.proof.base_minimum_net_eur?'waiting_risk_reward_target':'waiting_minimum_net';
  positions.push({symbol:k,status,protective,order_pending:!!pending,quote_time:q?.time||null,quote_age_seconds:q?(time-Date.parse(q.time))/1000:null,fresh,base_minimum_net_eur:plan.proof.base_minimum_net_eur,required_net_profit_eur:plan.proof.required_net_profit_eur,net_eur:fresh?plan.net*5:null,indicative_net_eur:fresh?plan.net*5:sale(s,k,p,s.prices[k]/fx(s,k)*.999).net_pnl_eur*5,cost_eur:p.cost*5});
 }catch{positions.push({symbol:k,status:'unknown_calculation',fresh:false});}
 return{checked_at:new Date(time).toISOString(),last_success:input.last_success,status:'read_only_snapshot',positions,cost_breakdown:input.cost_breakdown||null,note:'Momentopname uit opgeslagen quotes, geen orderuitvoering. De handel controleert om de vijf minuten en voert op een latere verse quote uit; broncontrole blijft verplicht.'};
}
