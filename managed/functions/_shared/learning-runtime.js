import {tick,equity,fx,sale,FEATURE_SCHEMA} from './engine.js';
import {BY_SYMBOL} from './catalogue.js';
import {canonical,sha,predict,verifyArtifact} from './learner.js';
import {IMPLEMENTATION} from './implementation.js';
const MARKET=['history','prices','price_fx','last_observation','data_info','universe','catalogue','mode','run_until','operation_mode','usd_per_eur','fx_time','benchmark_units','benchmark_cash','benchmark_last_value','benchmark_started_at','benchmark_stale','managed_transport'];
const clone=structuredClone;
export async function learningFingerprint(s){return sha({version:'paper-learning-v1',implementation:IMPLEMENTATION,features:FEATURE_SCHEMA,signal:.002,stop:.015,profit:.025,quote_age:120,
 risk:s.risk.config,tax:s.belgian_tax.config,costs:s.multi_market.cost_assumptions,universe:s.universe});}
export function compactAccount(s){
 const a=clone(s);for(const k of MARKET)delete a[k];delete a.risk.previous_quotes;delete a.risk.config;delete a.belgian_tax.config;
 a.multi_market={foreign_tax_reserve_eur:s.multi_market.foreign_tax_reserve_eur,adr_reserve_eur:s.multi_market.adr_reserve_eur};return a;
}
export function hydrateAccount(a,market){
 const s=clone(market);Object.assign(s,clone(a));s.risk={...clone(a.risk),config:clone(market.risk.config),previous_quotes:clone(market.risk.previous_quotes)};
 s.belgian_tax={...clone(a.belgian_tax),config:clone(market.belgian_tax.config)};
 s.multi_market={...clone(market.multi_market),...clone(a.multi_market)};s.running=true;return s;
}
const flat=s=>Object.keys(s.positions).length===0&&s.pending.length===0;
export function markedAccount(s){
 const marked=equity(s);let exits=0;
 for(const[k,p]of Object.entries(s.positions)){const t=sale(s,k,p,s.prices[k]/fx(s,k));exits+=['commission_eur','transaction_tax_eur','capital_gains_reserve_eur','foreign_tax_reserve_eur','adr_reserve_eur'].reduce((v,x)=>v+(t[x]||0),0);}
 const liquidation=marked-exits;
 return {equity_eur:marked,liquidation_eur:liquidation,exposure:Math.max(0,(marked-s.cash)/(marked||1)),cash_eur:s.cash,positions:Object.keys(s.positions).length,
  pending:s.pending.length,realized_eur:s.realized,fees_eur:s.fees,max_drawdown_eur:Math.max(0,s.peak-marked),flat:flat(s)};
}
export function modelGate(artifact,time,stats={total:0,shifted:0}){
 return ({context,pending=false})=>{
  if(!context||context.schema!==FEATURE_SCHEMA||!artifact||time-Date.parse(artifact.created_at)>180*86400000||!artifact.venues.includes(context.venue))return false;
  if(stats.total>=50&&stats.shifted/stats.total>.25)return false;
  const result=predict(artifact,context.features);if(!result)return false;
  if(!pending)context.model_evaluation={id:artifact.id,probability_net_positive:result.probability,threshold:.6,outlier_features:result.outliers,trained_at:artifact.created_at,note:'Modelschatting voor referentie-uitkomsten; geen winstgarantie.'};
  if(!pending){stats.total++;if(result.outliers>=2)stats.shifted++;}
  return result.outliers<2&&result.probability>=.6;
 };
}
export async function livePolicy(payload,time,currentState=null){
 if(!payload?.active_model_id)return {options:{},stats:{total:0,shifted:0},rollback:null};
 const stats=clone(payload.state?.live_drift||{total:0,shifted:0}),model=payload.active_artifact;
 const currentFingerprint=currentState?await learningFingerprint(currentState):payload.state?.fingerprint;
 if(!await verifyArtifact(model)||model.fingerprint!==currentFingerprint)return {options:{entryGate:()=>false},stats,rollback:'Modelintegriteit of parameterprofiel ongeldig.'};
 if(time-Date.parse(model.created_at)>180*86400000||stats.total>=50&&stats.shifted/stats.total>.25)return {options:{entryGate:()=>false},stats,rollback:'Model verouderd of duidelijke invoerverschuiving; terug naar baseline.'};
 if(payload.state.latest_status==='error')return {options:{entryGate:()=>false},stats,rollback:'Leersysteemfout; terug naar baseline.'};
 return {options:{entryGate:modelGate(model,time,stats),captureFeatures:true,contextTag:{policy:'live_model',model_id:model.id,fingerprint:model.fingerprint}},stats,rollback:null};
}
export async function stepLearning(payload,marketBefore,batch,time,policyState={stats:{total:0,shifted:0},rollback:null}){
 if(!payload?.enabled)return null;
 const state=clone(payload.state||{}),fingerprint=await learningFingerprint(marketBefore),events=[],trades=[],samples=[],days=[];
 const originalRevision=payload.revision;
 if(!state.accounts){
  state.run_id='run-'+new Date(time).toISOString();state.fingerprint=fingerprint;state.started_at=new Date(time).toISOString();
  state.accounts={reference:compactAccount(marketBefore),low_turnover:compactAccount(marketBefore),learned:null};
  state.initial_liquidation=markedAccount(marketBefore).liquidation_eur;state.day_accumulators={};state.last_entry_at=null;
  events.push({kind:'initialized',message:'Gelijke beginstaat inclusief bestaande posities gekopieerd naar aparte referentie en kostenvariant; geen nieuwe aankoop door het kopiëren.'});
 }
 if(state.fingerprint!==fingerprint)return {revision:originalRevision,state:{...state,latest_status:'profile_changed',message:'Handels-/kostenprofiel gewijzigd; schaduwvergelijking gepauzeerd, geen ongeldige labels.'},events:[],trades:[],samples:[],days:[],rollback:payload.active_model_id?'Parameterprofiel gewijzigd.':null};
 const candidate=payload.candidate_artifact;
 if(candidate&&candidate.id!==state.candidate_id&&await verifyArtifact(candidate)&&candidate.fingerprint===fingerprint&&flat(hydrateAccount(state.accounts.reference,marketBefore))&&(!state.accounts.learned||flat(hydrateAccount(state.accounts.learned,marketBefore)))){
  state.accounts.learned=clone(state.accounts.reference);state.candidate_id=candidate.id;state.candidate_artifact=clone(candidate);state.candidate_started_at=new Date(time).toISOString();state.candidate_closes=0;state.candidate_drift={total:0,shifted:0};
  // Restart the paired day window for BOTH reference and challenger at the same instant.
  state.day_accumulators={};events.push({kind:'candidate_started',message:'Bevroren model gestart in aparte schaduwportefeuille; nog geen inzet in de hoofdproef.'});
 }
 const summary={};
 for(const name of ['reference','low_turnover','learned']){
  if(!state.accounts[name])continue;
  const account=hydrateAccount(state.accounts[name],marketBefore),tag={run_id:state.run_id,policy:name,fingerprint,schema:FEATURE_SCHEMA};
  let gate,accepted=false;
  if(name==='low_turnover')gate=({signal,time:now,pending})=>pending||(!accepted&&signal>=.004&&(!state.last_entry_at||now-Date.parse(state.last_entry_at)>=3600000)&&(accepted=true));
  if(name==='learned'){
   const frozen=state.candidate_artifact;
   if(!frozen||frozen.id!==state.candidate_id||!await verifyArtifact(frozen))gate=()=>false;
   else gate=modelGate(frozen,time,state.candidate_drift||={total:0,shifted:0});
  }
  const output=tick(account,batch,time,{captureFeatures:true,contextTag:tag,entryGate:gate});
  if(name==='low_turnover'&&output.events.some(e=>e.kind==='besluit'&&e.data?.side==='koop'))state.last_entry_at=new Date(time).toISOString();
  for(const t of output.trades){
   trades.push({account:name,phase:name==='low_turnover'?'fixed-low-v1':state.candidate_id||'baseline-warmup',...t});
   const context=t.snapshot.learning_context;
   if(name==='reference'&&t.side==='verkoop'&&context?.policy==='reference'&&context.fingerprint===fingerprint&&context.schema===FEATURE_SCHEMA){
    samples.push({id:state.run_id+'|'+t.symbol+'|'+context.decision_time,schema:FEATURE_SCHEMA,fingerprint,features:context.features,symbol:t.symbol,venue:BY_SYMBOL[t.symbol].exchange,
     decision_time:context.decision_time,entry_time:context.entry_time,available_at:t.time,net_eur:t.pnl});
   }
   if(name==='learned'&&t.side==='verkoop')state.candidate_closes=(state.candidate_closes||0)+1;
  }
  state.accounts[name]=compactAccount(output.state);summary[name]=markedAccount(output.state);
  const date=new Date(time).toISOString().slice(0,10),phase=name==='low_turnover'?'fixed-low-v1':state.candidate_id||'baseline-warmup',key=date+'|'+name+'|'+phase;
  const record=state.day_accumulators[key]||{date,account:name,model_id:state.candidate_id||null,phase,first_at:new Date(time).toISOString(),start_liquidation:summary[name].liquidation_eur,
   rounds:0,buckets:[],exposure_sum:0,closes:0,max_drawdown_eur:0,initial_flat:flat(account),initialized_midday:Date.parse(name==='learned'?state.candidate_started_at:state.started_at)>Date.parse(date+'T07:00:00Z')};
  record.last_at=new Date(time).toISOString();record.end_liquidation=summary[name].liquidation_eur;
  const bucket=Math.floor((time-Date.parse(date+'T07:00:00Z'))/300000);if(bucket>=0&&bucket<168&&!record.buckets.includes(bucket)){record.buckets.push(bucket);record.rounds++;record.exposure_sum+=summary[name].exposure;}record.unique_rounds=record.buckets.length;
  record.stress_cost_eur=(record.stress_cost_eur||0)+output.trades.reduce((v,t)=>v+t.fee+.001*t.qty*t.price/t.snapshot.fx,0);
  record.flat=summary[name].flat;record.closes+=output.trades.filter(t=>t.side==='verkoop').length;record.max_drawdown_eur=Math.max(record.max_drawdown_eur,summary[name].max_drawdown_eur);
  record.complete=!record.initialized_midday&&record.initial_flat&&record.flat&&record.first_at<=date+'T07:05:59.999Z'&&record.last_at>=date+'T20:50:00.000Z'&&record.unique_rounds>=160;
  state.day_accumulators[key]=record;days.push(record);
 }
 const today=new Date(time).toISOString().slice(0,10);state.day_accumulators=Object.fromEntries(Object.entries(state.day_accumulators).filter(([,v])=>v.date===today));
 state.summary=summary;state.last_tick=new Date(time).toISOString();state.latest_status='ok';state.message=state.candidate_id?'Schaduwvergelijking met bevroren model actief.':'Referentie en kostenbewuste variant verzamelen gegevens; wachten op trainingsvoorbeelden.';
 state.live_drift=policyState.stats;
 return {revision:originalRevision,state,events,trades,samples,days,rollback:policyState.rollback||null};
}
export function pairedDays(rows,modelId){
 const byDate=new Map();for(const r of rows){if(r.model_id!==modelId)continue;const group=byDate.get(r.date)||{};group[r.account]=r;byDate.set(r.date,group);}
 const result=[];for(const[date,g]of byDate){if(!g.reference||!g.learned)continue;
  const a=g.reference,b=g.learned,reference=a.end_liquidation-a.start_liquidation,model=b.end_liquidation-b.start_liquidation;
  const exposure=a.exposure_sum>0?b.exposure_sum/a.exposure_sum:0;
  result.push({date,model_id:modelId,complete:a.complete&&b.complete,excess_eur:model-reference,matched_excess_eur:model-reference*exposure,
   model_drawdown_eur:b.max_drawdown_eur,reference_drawdown_eur:a.max_drawdown_eur,reference_exposure:a.exposure_sum,model_exposure:b.exposure_sum,exposure_ratio:exposure,model_net_eur:model,stress_cost_eur:b.stress_cost_eur??null});}
 return result.sort((a,b)=>a.date.localeCompare(b.date));
}
