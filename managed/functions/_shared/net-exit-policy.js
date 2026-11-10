import{sale,fx}from'./engine.js';
export const NET_EXIT_POLICY={version:'net-exits-v1',account:'capital10k',unit_eur:5,min_profit_eur:10,min_net_return_fraction:.025,min_reward_risk:1.5,stop_execution_buffer_fraction:.001,quote_age_seconds:120,close_at_session_end:false,protective_exceptions:true,additional_market_downloads:0,real_orders:false};
// All calculations use the existing account's five-euro internal unit. Public
// proofs explicitly contain real EUR; price/fill/tax helpers remain unchanged.
export function netExitPlan(s,k,p,time=Date.now(),policy=NET_EXIT_POLICY){
 if(![p.qty,p.cost,p.entry,p.stop].every(x=>Number.isFinite(x)&&x>0))throw Error('Invalid exit position');
 const unit=policy.unit_eur,stop=sale(s,k,p,p.stop*(1-policy.stop_execution_buffer_fraction)),stopLoss=Math.max(0,-stop.net_pnl_eur),floor=Math.max(policy.min_profit_eur/unit,p.cost*policy.min_net_return_fraction),required=Math.max(floor,stopLoss*policy.min_reward_risk);
 let lo=p.entry,hi=p.entry*1.025;
 for(let i=0;i<30&&sale(s,k,p,hi).net_pnl_eur<required;i++)hi*=1.25;
 if(!Number.isFinite(required)||sale(s,k,p,hi).net_pnl_eur<required)throw Error('No finite net exit target');
 for(let i=0;i<60;i++){const mid=(lo+hi)/2;if(sale(s,k,p,mid).net_pnl_eur>=required)hi=mid;else lo=mid;}
 return{required,target:hi,proof:{version:policy.version,checked_at:new Date(time).toISOString(),cost_eur:p.cost*unit,base_minimum_net_eur:floor*unit,estimated_stop_loss_eur:stopLoss*unit,minimum_reward_risk:policy.min_reward_risk,required_net_profit_eur:required*unit,target_execution_price_eur:hi*unit,stop_execution_price_eur:p.stop*(1-policy.stop_execution_buffer_fraction)*unit}};
}
export function exitQuoteCheck(s,k,p,q,time=Date.now(),policy=NET_EXIT_POLICY){
 const plan=netExitPlan(s,k,p,time,policy),price=q.bid*.9995/q.fx_per_eur,net=sale(s,k,p,price).net_pnl_eur;
 return{...plan,net,price,eligible:net>=plan.required,proof:{...plan.proof,expected_net_profit_eur:net*policy.unit_eur,quote_time:q.time}};
}
export function exitMark(s,k,p,time=Date.now(),policy=NET_EXIT_POLICY){const plan=netExitPlan(s,k,p,time,policy);return{...plan.proof,indicative_net_eur:sale(s,k,p,s.prices[k]/fx(s,k)*.999).net_pnl_eur*policy.unit_eur};}
