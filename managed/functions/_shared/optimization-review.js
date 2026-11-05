import {DAILY_COMPANIES} from './daily-catalogue.js';
import {dailyEntry,dailyOutcome} from './daily-study.js';
import {possibleSession} from './engine.js';
const median=a=>{const x=[...a].sort((a,b)=>a-b),n=x.length;return n?(n%2?x[n>>1]:(x[n/2-1]+x[n/2])/2):null;};
const valid=x=>typeof x==='number'&&Number.isFinite(x),stamp=t=>new Date(t).toISOString();
export function costScenario(config,item,bar,budget){
 if(![100,250,500,1000].includes(budget)||!valid(bar.close)||bar.close<=0||!valid(bar.fx)||bar.fx<=0)throw Error('Invalid cost scenario');
 // Normalize to EUR100 to reuse the frozen engine exactly. Percentage costs
 // and per-share ADR costs scale with quantity; only fixed money minima/caps
 // change in normalized units. This never changes the original configuration.
 const normalized=structuredClone(config),factor=100/budget;
 normalized.costs.us_minimum_commission_usd*=factor;normalized.costs.other_minimum_commission_eur*=factor;normalized.tax.transaction_tax_cap_eur*=factor;
 const entry=dailyEntry(normalized,item,bar),flat=dailyOutcome(normalized,item,entry,bar),result=price=>dailyOutcome(normalized,item,entry,{...bar,close:bar.close*(1+price)});
 let lo=0,hi=.05;while(hi<4&&result(hi).net_eur<0)hi*=2;
 if(result(hi).net_eur<0)return {budget_eur:budget,break_even_percent:null,flat_loss_eur:-flat.net_eur/factor,flat_loss_percent:-flat.net_eur};
 for(let n=0;n<45;n++){const mid=(lo+hi)/2;if(result(mid).net_eur>=0)hi=mid;else lo=mid;}
 return {budget_eur:budget,break_even_percent:hi*100,flat_loss_eur:-flat.net_eur/factor,flat_loss_percent:-flat.net_eur,
  note:'Netto break-even bij gelijke FX; indicatieve spread, commissies, TOB en voorlopige belastingreserves. Geen geverifieerd brokertarief.'};
}
function lastRequiredDay(time,hour,minute,weekdays=false){
 const now=new Date(time),today=now.toISOString().slice(0,10);let due=Date.parse(today+'T00:00:00Z')+(hour*60+minute+30)*60000;
 if(time<due)due-=86400000;
 while(weekdays&&[0,6].includes(new Date(due).getUTCDay()))due-=86400000;
 return new Date(due).toISOString().slice(0,10);
}
export function optimizationReview(input,{time=Date.now()}={}){
 const findings=[],costs=[],groups=new Map(),available=[];
 const add=(level,id,title,message)=>findings.push({level,id,title,message});
 const prices=new Map((input.prices||[]).map(x=>[x.symbol,x]));
 if(input.config)for(const item of DAILY_COMPANIES){const bar=prices.get(item.symbol);
  if(!bar||!valid(bar.close)||bar.close<=0||!valid(bar.fx)||bar.fx<=0||!Number.isFinite(Date.parse(bar.day))||!Number.isFinite(Date.parse(bar.observed_at))||!Number.isFinite(Date.parse(bar.fx_date))||bar.fx_date>bar.day||Date.parse(bar.day)-Date.parse(bar.fx_date)>4*86400000||bar.day>=stamp(time).slice(0,10)||Date.parse(stamp(time).slice(0,10))-Date.parse(bar.day)>4*86400000||Date.parse(bar.observed_at)>time)continue;
  available.push(item.symbol);
  for(const budget of [100,250,500,1000]){const scenario=costScenario(input.config,item,bar,budget),key=item.exchange+'|'+budget,g=groups.get(key)||{venue:item.exchange,currency:item.currency,budget_eur:budget,flat:[],break_even:[],symbols:[]};
   g.flat.push(scenario.flat_loss_percent);if(scenario.break_even_percent!=null)g.break_even.push(scenario.break_even_percent);g.symbols.push(item.symbol);groups.set(key,g);}
 }
 for(const g of groups.values())costs.push({venue:g.venue,currency:g.currency,budget_eur:g.budget_eur,companies:g.symbols.length,
  median_flat_loss_percent:median(g.flat),median_break_even_percent:median(g.break_even),example:g.symbols[0],larger_order_scenario:g.budget_eur>100});
 if(costs.length){const hundred=costs.filter(x=>x.budget_eur===100),largest=Math.max(...hundred.map(x=>x.median_break_even_percent||0));
  add('priority','costs','Eerst de kostendrempel begrijpen',`Bij EUR100 vraagt het huidige scenario op minstens één beurs ongeveer ${largest.toFixed(2)}% prijsstijging voor netto break-even. Werkelijke brokerkosten valideren en omzet vergelijken voordat we handelsregels wijzigen.`);
 }
 const p=input.progress||{},mature=(p.reference_complete||0)+(p.extra_complete||0);
 if(!mature)add('waiting','future_labels','Dagmodel: nieuwe uitkomsten nog niet meetbaar','De twintig-sessiewaarnemingen zijn nog niet afgerond. Modelnauwkeurigheid en netto voordeel op deze nieuwe gegevens zijn nog niet meetbaar; een nulscore zou misleidend zijn.');
 else add('info','future_labels','Nieuwe uitkomsten beschikbaar',`${mature} afgeronde waarnemingen. Afhankelijkheid, ontbrekende gevallen en de vaste toetsperiode blijven gelden.`);
 if(input.model?.historical_pass===false)add('waiting','historical_gate','Historische bewijseis nog niet gehaald',`${input.model.test_selected||0} geselecteerde historische testgevallen; minstens honderd nodig. Bestaande gewichten en toetsregels blijven vast.`);
 const training=input.learning?.training;
 if(training?.status==='waiting_data')add('waiting','intraday_data','Intradayroute wacht op echte voorbeelden',`${training.samples||p.reference_samples||0} / 300 gesloten referentievoorbeelden over ${training.days||0} / 60 dagen. Wachten op meer gegevens is hier de correcte toestand.`);
 for(const [key,hour,minute]of [['daily',6,10],['history',6,20],['breadth',6,25],['audit',23,0]]){
  const job=input[key];if(key==='breadth'&&job?.enabled===false){add('info','paused_'+key,'Brede registratie door eigenaar gepauzeerd','Geplande controles veranderen deze keuze niet.');continue;}
  const date=job?.last_success?.slice(0,10),due=lastRequiredDay(time,hour,minute,key==='audit');
  if(!date||date<due||['error','hard_budget_paused','budget_paused','reference_changed'].includes(job?.status))add('attention','job_'+key,'Controle nodig: '+key,`Laatste bevestigde verwerking ${job?.last_success||'ontbreekt'}; status ${job?.status||'onbekend'}. Een geslaagde cron-aanroep alleen bewijst geen voltooid werk.`);
 }
 const expectedOpen=DAILY_COMPANIES.some(c=>possibleSession(c,time));
 if(input.account?.running&&expectedOpen&&(!input.account.last_update||time-Date.parse(input.account.last_update)>15*60000))add('attention','quote_progress','Koersverwerking loopt achter','Tijdens mogelijke beursuren is meer dan vijftien minuten geen nieuwe hoofdmeting bevestigd. Buiten beursuren telt dit niet als storing.');
 if(input.account?.global_halted||input.account?.daily_halted)add('info','risk_pause','Risicopauze actief','De risicopauze blijft behouden. Meer onderzoek is geen reden om verliesgrenzen te resetten.');
 for(const source of input.history?.context||[])if(source.status==='unavailable')add('attention','source_'+source.symbol,'Externe bron ontbreekt: '+source.symbol,source.note||'Geen actuele broninhoud beschikbaar; gegevens worden niet ingevuld.');
 const keys=(input.history?.connections||[]).filter(x=>x.status==='credentials_required').map(x=>x.id);
 if(keys.length)add('dependency','credentials','Aanvullende bronnen wachten op sleutels',keys.join(', ')+'. De publieke prijs- en FX-route blijft bruikbaar; er worden geen accounts of betaalde abonnementen aangemaakt.');
 if(available.length<150)add('info','coverage','Dagdekking is niet volledig',`${available.length} van 150 bedrijven hebben bruikbare gedateerde prijs-/FX-invoer voor deze kostenscan.`);
 const b=input.budget||{};
 if((b.database_bytes||0)>=105000000||(b.monthly_estimated_bytes||0)>=1050000000)add('attention','budget','Gratis marge bewaken','De waarschuwingsmarge voor de brede onderzoeksroute is bereikt. Bestaande toelatings- en stopgrenzen blijven van kracht.');
 if((input.short_outcomes?.observed||0)>0&&input.short_outcomes.mean_net_eur<0)add('priority','short_costs','Korte waarnemingen halen hun kosten gemiddeld nog niet terug',`${input.short_outcomes.observed} gemeten 120-minutenuitkomsten: gemiddeld EUR${input.short_outcomes.mean_net_eur.toFixed(2)} per hypothetische EUR100. Overlappende observaties zijn geen onafhankelijke portefeuilleresultaten.`);
 return {version:'optimization-review-v1',status:'reviewed',checked_at:stamp(time),findings,costs,covered_companies:available.length,progress:p,budget:b,
  trading_changes:false,model_changes:false,extra_market_downloads:0,
  note:'Regelgestuurde optimalisatiecontrole; geen nieuwe voorspeller. Bedragen boven EUR100 zijn rekenscenario’s en kunnen buiten het rekening- en risicobudget vallen. Kosten en bronkwaliteit kunnen nu onderzocht worden; modelvoordeel vraagt nieuwe toetsgegevens.'};
}
