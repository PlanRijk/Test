import {BY_SYMBOL} from './catalogue.js';
import {prepareSamples,chronologicalSplit,trainCandidate,predict,sha} from './learner.js';
export const RELIABILITY={version:'reliability-v1',samples:300,days:60,forward_days:60,forward_closes:120,draws:4000,alpha:.01/3};
const finite=x=>typeof x==='number'&&Number.isFinite(x),mean=x=>x.length?x.reduce((a,b)=>a+b,0)/x.length:null;
export function blockBounds(values,block=5,alpha=RELIABILITY.alpha){
 if(values.length<30||values.some(x=>!finite(x)))return null;
 let seed=1729;const random=()=>{seed=(1664525*seed+1013904223)>>>0;return seed/4294967296;},draws=[];
 for(let b=0;b<4000;b++){let sum=0,n=0;while(n<values.length){const start=Math.floor(random()*values.length);for(let j=0;j<block&&n<values.length;j++,n++)sum+=values[(start+j)%values.length];}draws.push(sum/values.length);}
 draws.sort((a,b)=>a-b);return {lower:draws[Math.floor(draws.length*alpha)],upper:draws[Math.min(draws.length-1,Math.floor(draws.length*(1-alpha)))],block_days:block,draws:4000,alpha};
}
function concentration(values){const positive=values.filter(v=>v>0).reduce((a,b)=>a+b,0);return positive?Math.max(0,...values)/positive:1;}
function dropBestBlock(values,size=5){let best=-Infinity,at=0;for(let i=0;i<=values.length-size;i++){const n=values.slice(i,i+size).reduce((a,b)=>a+b,0);if(n>best){best=n;at=i;}}return mean(values.filter((_,i)=>i<at||i>=at+size));}
export async function reliableTrain(rows,options={}){
 const time=options.time??Date.now(),cutoff=Date.parse(new Date(time).toISOString().slice(0,10)+'T00:00:00Z');
 let samples=prepareSamples(rows,cutoff,options.fingerprint),split=chronologicalSplit(samples),blocked=[];
 const venues=[...new Set(split.train.map(r=>r.venue))].filter(v=>split.train.filter(r=>r.venue===v).length>=30&&split.validation.filter(r=>r.venue===v).length>=10&&split.test.filter(r=>r.venue===v).length>=10);
 samples=samples.filter(r=>venues.includes(r.venue));split=chronologicalSplit(samples);
 if(samples.length<300||split.dates.length<60)blocked.push('Minstens 300 gesloten referentietrades verspreid over 60 handelsdagen nodig.');
 if(new Set(samples.map(r=>r.symbol)).size<10||new Set(samples.map(r=>BY_SYMBOL[r.symbol]?.sector)).size<5)blocked.push('Minstens tien bedrijven en vijf sectoren nodig binnen de getoetste beursdekking.');
 if(split.train.length<150||split.validation.length<30||split.test.length<30)blocked.push('Minstens 150 trainings-, 30 validatie- en 30 aparte testvoorbeelden nodig.');
 for(const[name,part,min]of [['training',split.train,50],['validatie',split.validation,10],['test',split.test,10]])if(part.filter(r=>r.y).length<min||part.filter(r=>!r.y).length<min)blocked.push('Te weinig positieve en negatieve voorbeelden in '+name+'.');
 if(options.previousCutoff&&split.dates.filter(d=>d>options.previousCutoff).length<60)blocked.push('Zestig nieuwe datums nodig; geen herhaald toetsen op hetzelfde bewijs.');
 if(blocked.length)return {status:'waiting_data',blocked,samples:samples.length,days:split.dates.length};
 const result=await trainCandidate(samples,{...options,time});if(result.status!=='trained')return result;
 const a=result.artifact,selected=split.test.filter(r=>predict(a,r.features)?.probability>=.6),stress=mean(selected.map(r=>r.net_eur-Math.max(0,r.features[4])*100));
 a.protocol='paper-learning-v2';a.reliability={version:RELIABILITY.version,samples:samples.length,days:split.dates.length,symbols:new Set(samples.map(r=>r.symbol)).size,sectors:new Set(samples.map(r=>BY_SYMBOL[r.symbol]?.sector)).size,
  train_rows:split.train.length,validation_rows:split.validation.length,test_rows:split.test.length,selected_test:selected.length,selected_test_stress_mean_eur:stress,venues};
 if(selected.length<30||stress==null||stress<=0)a.offline_blockers.push('Apart testvak vereist dertig geselecteerde voorbeelden met positieve gemiddelde uitkomst na verdubbelde geraamde rondekosten.');
 a.offline_pass=a.offline_blockers.length===0;const{integrity_hash,...body}=a;a.integrity_hash=await sha(body);return result;
}
export async function modelAudit(artifact,days,meta={},time=Date.now()){
 const today=new Date(time).toISOString().slice(0,10),seen=new Set(),duplicates=days.some(d=>seen.has(d.date)||!seen.add(d.date));
 const selected=days.filter(d=>d.complete&&d.model_id===artifact.id&&d.date>artifact.training_cutoff&&d.date>artifact.created_at.slice(0,10)&&d.date<today&&/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/.test(d.date)&&Number.isFinite(Date.parse(d.date))&&new Date(d.date+'T12:00:00Z').toISOString().slice(0,10)===d.date&&![0,6].includes(new Date(d.date+'T12:00:00Z').getUTCDay())).sort((a,b)=>a.date.localeCompare(b.date)).slice(0,60);
 if(selected.length<60)return {status:'waiting',model_id:artifact.id,days:selected.length,required_days:60};
 const blocked=[],stressed=selected.map(d=>d.matched_excess_eur-d.stress_cost_eur),bounds=[blockBounds(stressed,5),blockBounds(stressed,10)],window=selected.map(d=>d.date);
 if(duplicates)blocked.push('Dubbele dagrecords.');
 if(!artifact.offline_pass||artifact.reliability?.version!==RELIABILITY.version)blocked.push('Strenge offline bewijsvoorwaarden ontbreken.');
 if(!finite(meta.closes)||meta.closes<120||!finite(meta.symbols)||meta.symbols<10||!finite(meta.sectors)||meta.sectors<5)blocked.push('Minstens 120 afsluitingen, tien bedrijven en vijf sectoren nodig in het vaste venster.');
 if(!finite(meta.quality_days)||meta.quality_days<60||!finite(meta.min_source_coverage)||meta.min_source_coverage<.9||!finite(meta.calendar_coverage)||meta.calendar_coverage<.8)blocked.push('Onvoldoende aantoonbare bron- of dagdekking binnen de getoetste beurzen.');
 if(!finite(meta.flagged_trades)||meta.flagged_trades>0)blocked.push('Uitschieters/corporate actions vereisen beoordeling.');
 if(selected.filter(d=>d.model_exposure>0&&d.reference_exposure>0).length<40)blocked.push('Minstens veertig werkelijk belegde gepaarde dagen nodig.');
 if(selected.some(d=>!finite(d.stress_cost_eur)||d.stress_cost_eur<0||!finite(d.excess_eur)||!finite(d.matched_excess_eur)||!finite(d.model_net_eur)||d.model_exposure>0&&d.reference_exposure<=0||d.exposure_ratio>1.25))blocked.push('Ontbrekende kosten of onvoldoende vergelijkbare blootstelling.');
 if(selected.some(d=>d.model_drawdown_eur>d.reference_drawdown_eur+5))blocked.push('Extra drawdown groter dan EUR5.');
 if(!bounds.every(b=>b&&b.lower>0)||mean(selected.map(d=>d.excess_eur))<=0||mean(selected.map(d=>d.model_net_eur-d.stress_cost_eur))<=0)blocked.push('Geen robuust positief netto voordeel bij beide bloklengtes en hogere kosten.');
 if(concentration(stressed)>.2||dropBestBlock(stressed)<=0||mean(stressed.slice(30))<=0)blocked.push('Resultaat te afhankelijk van één dag/week of niet positief in de recente helft.');
 return {status:'final',version:RELIABILITY.version,model_id:artifact.id,eligible:blocked.length===0,blocked,window,window_hash:await sha(selected),first_date:window[0],last_date:window.at(-1),forward_days:60,closed_positions:meta.closes,
  mean_stressed_excess_eur:mean(stressed),bounds,source_quality:meta,net_excess_eur:selected.reduce((a,d)=>a+d.excess_eur,0),note:'Eenmalig vast venster, dagblokken van vijf en tien dagen en correctie voor maximaal drie modelproeven; geen winstgarantie.'};
}
export async function epochAudit(epoch,time=Date.now()){
 const rows=epoch.days||[],total=rows.reduce((n,d)=>n+d.expected,0),observed=rows.reduce((n,d)=>n+d.observed,0),values=rows.map(d=>d.mean_difference_eur),stress=rows.map(d=>d.mean_stressed_difference_eur),blocked=[];
 if(new Date(time).toISOString().slice(0,10)<=epoch.test_end)return {status:'sealed',epoch_id:epoch.id};
 if(rows.length<30||observed<100)blocked.push('Minstens dertig aparte toetsdagen en honderd gepaarde bedrijf-dagen nodig.');
 if(!total||observed/total<.9)blocked.push('Meer dan tien procent ontbrekende of ongepaarde primaire uitkomsten.');
 if(rows.filter(d=>d.control_gross_mean>=0).length<10||rows.filter(d=>d.control_gross_mean<0).length<10)blocked.push('Te weinig positieve en negatieve marktdagen in dit toetsvak.');
 if(epoch.sectors<5||epoch.venues<2)blocked.push('Beperkte sector- of beursdekking.');
 if(epoch.flagged>0)blocked.push('Uitschieters moeten worden beoordeeld.');
 const bounds=[blockBounds(stress,5,.01),blockBounds(stress,10,.01)];
 if(!bounds.every(b=>b&&b.lower>0)||mean(values)==null||mean(values)<=0||mean(rows.map(d=>d.adverse_mean_eur))<=0)blocked.push('Geen robuust voordeel na kosten en het vooraf vastgelegde ontbrekende-data-scenario.');
 if(concentration(stress)>.2||dropBestBlock(stress)<=0)blocked.push('Te veel afhankelijkheid van een enkele dag of week.');
 return {status:'final',version:RELIABILITY.version,epoch_id:epoch.id,conclusion:blocked.length?'not_supported':'supported_within_scope',blocked,days:rows.length,paired:observed,expected:total,coverage:total?observed/total:0,
  primary_horizon_minutes:120,mean_difference_eur:mean(values),mean_stressed_difference_eur:mean(stress),bounds,window_hash:await sha(rows),automatic_trading_approval:false,
  note:'Observationele vergelijking op een vooraf afgesloten toetsvak; timing en selectie kunnen verschillen. Een scenario van EUR100 nadeel per ontbrekend paar is geen wiskundig worstcasescenario.'};
}
