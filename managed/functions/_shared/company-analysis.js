import {COMPANY_POLICY as P}from'./company-policy.js';
const DAY=86400000,iso=t=>new Date(t).toISOString(),num=x=>typeof x==='number'&&Number.isFinite(x),stamp=x=>Date.parse(x),fraction=(a,b)=>num(a)&&num(b)&&b>0?a/b-1:null;
const tags={revenue:['RevenueFromContractWithCustomerExcludingAssessedTax','Revenues','SalesRevenueNet'],income:['NetIncomeLoss'],ocf:['NetCashProvidedByUsedInOperatingActivities'],capex:['PaymentsToAcquirePropertyPlantAndEquipment'],shares:['CommonStockSharesOutstanding'],diluted:['WeightedAverageNumberOfDilutedSharesOutstanding'],cash:['CashAndCashEquivalentsAtCarryingValue'],debt:['LongTermDebt'],current_debt:['LongTermDebtCurrent'],noncurrent_debt:['LongTermDebtNoncurrent'],commercial_paper:['CommercialPaper']};
function points(facts,key,unit,time){return(tags[key]||[]).flatMap(tag=>(facts?.facts?.['us-gaap']?.[tag]?.units?.[unit]||[]).filter(x=>['10-K','10-Q'].includes(x.form)&&num(x.val)&&/^\d{4}-\d{2}-\d{2}$/.test(x.end||'')&&stamp(x.end)<=time&&stamp(x.filed+'T23:59:59Z')<=time).map(x=>({...x,tag})));}
function select(xs,{end,start,accession,annual=false}={}){return xs.filter(x=>(!end||x.end===end)&&(!start||x.start===start)&&(!accession||x.accn===accession)&&(!annual||stamp(x.end)-stamp(x.start)>=330*DAY&&stamp(x.end)-stamp(x.start)<=380*DAY)).sort((a,b)=>b.end.localeCompare(a.end)||b.filed.localeCompare(a.filed)||a.tag.localeCompare(b.tag))[0]||null;}
function pick(facts,key,unit,end,time,start,accession){return select(points(facts,key,unit,time),{end,start,accession});}
export function parseCompanyFacts(facts,submissions,item,{time=Date.now(),source_bytes=0}={}){
 if(!/^\d{10}$/.test(item.cik||'')||Number(facts.cik)!==Number(item.cik)||Number(submissions.cik)!==Number(item.cik)||!(submissions.tickers||[]).includes(item.provider_symbol||item.symbol))throw Error('Issuer identity not confirmed');
 const rf=submissions.filings?.recent||{},filings=[];
 for(let i=0;i<(rf.form||[]).length;i++){const at=stamp(rf.acceptanceDateTime?.[i]);if(!['10-K','10-Q','8-K'].includes(rf.form[i])||!num(at)||at>time)continue;const accession=rf.accessionNumber[i],doc=rf.primaryDocument[i];if(!/^\d{10}-\d{2}-\d{6}$/.test(accession||'')||!doc||doc.includes('..'))continue;filings.push({form:rf.form[i],published_at:iso(at),accession,items:rf.items?.[i]||'',url:'https://www.sec.gov/Archives/edgar/data/'+Number(item.cik)+'/'+accession.replaceAll('-','')+'/'+encodeURIComponent(doc)});}
 filings.sort((a,b)=>b.published_at.localeCompare(a.published_at));
 const latestReport=filings.find(x=>['10-K','10-Q'].includes(x.form)),annualReport=filings.find(x=>x.form==='10-K');
 if(!latestReport||!annualReport)throw Error('Dated financial reports missing');
 const revs=points(facts,'revenue','USD',time),a=select(revs,{annual:true,accession:annualReport.accession});if(!a)throw Error('Comparable annual revenue missing');
 const previous=select(revs.filter(x=>stamp(a.end)-stamp(x.end)>330*DAY&&stamp(a.end)-stamp(x.end)<400*DAY),{annual:true,accession:annualReport.accession});
 const y=key=>pick(facts,key,key==='diluted'?'shares':'USD',a.end,time,a.start,annualReport.accession),last=key=>pick(facts,key,key==='shares'?'shares':'USD',undefined,time,undefined,latestReport.accession);
 const ni=y('income'),ocf=y('ocf'),capex=y('capex'),diluted=y('diluted'),priorShares=previous?pick(facts,'diluted','shares',previous.end,time,previous.start,annualReport.accession):null;
 const currentRevenue=select(revs.filter(x=>x.accn===latestReport.accession&&x.start&&stamp(x.end)-stamp(x.start)>=60*DAY&&stamp(x.end)-stamp(x.start)<=380*DAY));
 const comp=currentRevenue?select(revs.filter(x=>x.accn===latestReport.accession&&x.start&&Math.abs((stamp(currentRevenue.end)-stamp(currentRevenue.start))-(stamp(x.end)-stamp(x.start)))<12*DAY&&stamp(currentRevenue.end)-stamp(x.end)>330*DAY&&stamp(currentRevenue.end)-stamp(x.end)<400*DAY)):null;
 const shares=last('shares'),cash=last('cash'),debt=last('debt'),cur=last('current_debt'),noncur=last('noncurrent_debt'),cp=last('commercial_paper');
 // Missing commercial paper is not silently interpreted as zero. A reviewed
 // balance-sheet total may supply debt separately through the risk review.
 const financial={currency:'USD',annual_start:a.start,annual_end:a.end,revenue:a.val,previous_revenue:previous?.val??null,revenue_growth:fraction(a.val,previous?.val),latest_revenue_growth:fraction(currentRevenue?.val,comp?.val),net_income:ni?.val??null,operating_cash_flow:ocf?.val??null,capex:capex?.val??null,free_cash_flow:ocf&&capex?ocf.val-capex.val:null,diluted_shares:diluted?.val??null,share_growth:fraction(diluted?.val,priorShares?.val),shares_outstanding:shares?.val??null,balance_end:shares?.end||cash?.end||null,cash:cash?.val??null,reported_long_debt:debt?.val??(cur&&noncur&&cur.end===noncur.end?cur.val+noncur.val:null),commercial_paper:cp?.val??null,debt_complete:!!cp&&cp.end===cash?.end&&(!!debt&&debt.end===cash?.end||!!cur&&!!noncur&&cur.end===cash?.end&&noncur.end===cash?.end)};
 const factsUrl='https://data.sec.gov/api/xbrl/companyfacts/CIK'+item.cik+'.json';
 return{version:'company-dossier-v1',symbol:item.symbol,issuer:facts.entityName,cik:item.cik,known_at:iso(time),checked_at:iso(time),latest_report:latestReport,annual_report:annualReport,latest_disclosure:filings[0],filings:filings.slice(0,8),financial,sources:[{url:factsUrl,kind:'SEC companyfacts',checked_at:iso(time)},latestReport,annualReport],source_bytes,limitations:['Annual GAAP screen, not an intrinsic value or consensus forecast.','Qualitative moat and current risk require an explicit sourced review.','No complete real-time news, analyst consensus or earnings calendar.']};
}
function recent(t,time,days){const age=time-stamp(t);return num(age)&&age>=0&&age<=days*DAY;}
export function assessCompany(d,price,currency,time=Date.now(),policy=P){
 const unknown=reason=>({status:'unknown',reason}),check=(ok,reason)=>({status:ok?'pass':'fail',reason});
 const p=Object.fromEntries(policy.pillars.map(k=>[k,unknown('Geen volledig, actueel bronbewijs.')]));
 if(!d||d.version!=='company-dossier-v1')return{eligible:false,pillars:p,blockers:['Bedrijfsdossier ontbreekt.']};
 const f=d.financial||{},r=d.review||{},fresh=recent(d.checked_at,time,policy.max_check_age_days)&&recent(d.latest_report?.published_at,time,policy.max_report_age_days)&&recent(d.annual_report?.published_at,time,policy.max_annual_age_days)&&recent(f.annual_end,time,policy.max_annual_age_days);
 if(!fresh)return{eligible:false,pillars:p,blockers:['Bedrijfsrapport of broncontrole is verouderd of ligt in de toekomst.']};
 if(['Financieel','Vastgoed'].includes(d.sector))return{eligible:false,pillars:p,blockers:['Voor deze sector ontbreekt nog een passend fundamenteel waarderings- en risicoprofiel.']};
 if(num(f.revenue_growth)&&num(f.latest_revenue_growth))p.growth=check(f.revenue_growth>=policy.min_annual_revenue_growth&&f.latest_revenue_growth>=policy.min_latest_revenue_growth,`Omzetgroei jaar ${Math.round(f.revenue_growth*1000)/10}%; laatste vergelijkbare periode ${Math.round(f.latest_revenue_growth*1000)/10}%.`);
 if([f.net_income,f.operating_cash_flow,f.free_cash_flow].every(num))p.profitability=check(f.net_income>0&&f.operating_cash_flow>0&&f.free_cash_flow>0,'Positieve jaarwinst, operationele kasstroom en kasstroom na materiële investeringen vereist.');
 let pe=null,pfcf=null;
 if(currency===f.currency&&num(price)&&price>0&&num(f.shares_outstanding)&&f.shares_outstanding>0&&f.net_income>0&&f.free_cash_flow>0){pe=price*f.shares_outstanding/f.net_income;pfcf=price*f.shares_outstanding/f.free_cash_flow;p.valuation=check(pe<=policy.max_pe&&pfcf<=policy.max_price_fcf,`Jaar-K/W ${pe.toFixed(1)}; koers/vrije kasstroom ${pfcf.toFixed(1)}. Voorlopige plafonds ${policy.max_pe}/${policy.max_price_fcf}, geen intrinsieke waarde.`);}
 const reviewFresh=stamp(r.reviewed_at)>=stamp(d.latest_disclosure?.published_at)&&(r.sources||[]).some(s=>s.url===d.latest_disclosure?.url)&&recent(r.reviewed_at,time,policy.max_review_age_days)&&Array.isArray(r.sources)&&r.sources.length>0&&r.sources.every(s=>/^https:\/\//.test(s.url||'')&&recent(s.published_at,time,policy.max_annual_age_days)&&stamp(s.published_at)<=stamp(r.reviewed_at));
 if(reviewFresh&&r.moat?.status==='supported'&&r.moat.evidence?.length>=40)p.moat=check(true,r.moat.evidence);else if(reviewFresh&&r.moat?.status==='unsupported')p.moat=check(false,r.moat.evidence||'Concurrentievoordeel onvoldoende onderbouwd.');
 const disclosureCovered=(r.reviewed_accessions||[]).includes(d.latest_disclosure?.accession),debtTotal=f.debt_complete&&num(f.reported_long_debt)&&num(f.commercial_paper)?f.reported_long_debt+f.commercial_paper:null;
 const debt=num(r.total_debt)&&r.balance_end===f.balance_end?r.total_debt:debtTotal;
 const netDebtFcf=num(debt)&&num(f.cash)&&f.free_cash_flow>0?Math.max(0,debt-f.cash)/f.free_cash_flow:null;
 if(reviewFresh&&disclosureCovered&&num(netDebtFcf)&&num(f.share_growth)&&r.risks?.summary?.length>=40&&Array.isArray(r.risks?.flags))p.risks=check(!r.risks.flags.some(x=>['thesis_broken','critical','uncertain'].includes(x))&&netDebtFcf<=policy.max_net_debt_fcf&&f.share_growth<=policy.max_share_growth,`${r.risks.summary} Netto-schuld/jaarkasstroom ${netDebtFcf.toFixed(2)}; verwatering ${(f.share_growth*100).toFixed(1)}%.`);
 const blockers=Object.entries(p).filter(([,v])=>v.status!=='pass').map(([k,v])=>k+': '+v.reason);
 return{eligible:blockers.length===0,pillars:p,blockers,metrics:{pe,price_fcf:pfcf,net_debt_fcf:netDebtFcf},dossier_id:d.id,review_id:r.id||null,known_at:d.known_at,reviewed_at:r.reviewed_at||null,financial_snapshot:f,source_urls:[...new Set([...(d.sources||[]),...(r.sources||[])].map(s=>s.url))],latest_disclosure:d.latest_disclosure?.accession||null};
}
export function companySignal({dossier,history=[],quote,daily=[],time=Date.now(),policy=P,price_scale=1}){
 const assessment=assessCompany(dossier,quote?(quote.bid+quote.ask)/2*price_scale:null,quote?.currency,time,policy),no=why=>({eligible:false,assessment,reason:why});
 if(!assessment.eligible)return no('Niet alle vijf bedrijfspijlers zijn goedgekeurd.');
 const h=history.slice(-6);if(h.length<6||h.some(x=>!num(x.price)||x.price<=0)||time-stamp(h[0].time)>1800000||time-stamp(h[0].time)<0)return no('Zes recente koersmetingen ontbreken.');
 const avg=h.slice(0,5).reduce((s,x)=>s+x.price,0)/5,momentum=h[5].price/avg-1;
 const ds=daily.filter(x=>stamp(x.day+'T00:00:00Z')<time&&stamp(x.observed_at)<=time&&num(x.close)&&x.close>0).sort((a,b)=>a.day.localeCompare(b.day)).slice(-20),last=ds.at(-1);
 const current=quote?(quote.bid+quote.ask)/2*price_scale:null;
 const dayMove=last&&time-stamp(last.day+'T00:00:00Z')<=4*DAY?current/last.close-1:null;
 const events=(dossier.review?.events||[]).filter(e=>recent(e.published_at,time,policy.event_window_days)&&stamp(e.reviewed_at)<=time&&recent(e.reviewed_at,time,policy.max_review_age_days)&&e.url&&e.accession&&typeof e.rationale==='string'&&e.rationale.length>=40&&(dossier.review?.sources||[]).some(s=>s.url===e.url)&&(dossier.review?.reviewed_accessions||[]).includes(e.accession));
 if(ds.length!==policy.min_daily_closes||!last||time-stamp(last.day+'T00:00:00Z')>4*DAY||dossier.price_window_status==='corporate_action_requires_review')return no('Twintig recente, bruikbare referentiesloten ontbreken of een bedrijfsactie vraagt beoordeling.');
 const adverse=events.find(e=>e.kind==='adverse_news'),earnings=events.find(e=>e.kind==='earnings');
 const drawdown=ds.length===policy.min_daily_closes?current/Math.max(...ds.map(x=>x.close))-1:null;
 const recovery=h[5].price/h[0].price-1,stabilized=recovery>=policy.recovery_fraction&&h[5].price>h[4].price&&h[4].price>=h[3].price;
 let route=null;
 if(adverse&&adverse.verdict!=='temporary')return no('Slecht nieuws is nog onzeker of tast de beleggingsthese aan.');
 if(num(drawdown)&&drawdown<=-policy.dip_fraction){if(adverse?.verdict==='temporary'&&stabilized)route='reviewed_news_recovery';else return no('Sterke daling: beoordeelde tijdelijke oorzaak en bevestigd herstel vereist.');}
 else if(earnings&&earnings.verdict==='constructive'&&momentum>policy.momentum_fraction&&num(dayMove)&&dayMove>0)route='earnings_momentum';
 else if(momentum>policy.momentum_fraction)route='quality_momentum';
 if(!route)return no('Bedrijf doorstaat de pijlers, maar er is nog geen bevestigd instapsignaal.');
 return{eligible:true,route,score:momentum,assessment,momentum_fraction:momentum,day_move_fraction:dayMove,drawdown_fraction:drawdown,recovery_fraction:recovery,event:route==='reviewed_news_recovery'?adverse:route==='earnings_momentum'?earnings:null,reason:{quality_momentum:'Vijf bedrijfspijlers akkoord en positief kortetermijnmomentum.',earnings_momentum:'Beoordeelde cijferpublicatie, vijf pijlers akkoord en positief koersmomentum; geen bewezen consensusverrassing.',reviewed_news_recovery:'Minstens 5% onder twintig bekende slotkoersen, beoordeeld tijdelijk slecht nieuws en bevestigd koersherstel.'}[route]};
}
