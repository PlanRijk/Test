// Original, dependency-free implementations of the free research workbench methods.
// Project references and exact scope: managed/OPEN-SOURCE-INTEGRATION.md.
export const RESEARCH_PROTOCOL='free-research-workbench-v1';
export const RESEARCH_AREAS=[
 {id:'equity',label:'Bedrijf en verwachtingen',checks:['Kwartaalperiode, valuta en winstdefinitie','Verwachting versus passende vooraf opgeslagen consensus','Groei, kasconversie en waardering']},
 {id:'macro',label:'Macro en financiering',checks:['Rente en schuldherfinanciering','Vraaggevoeligheid en valuta','Ontbrekende actuele macrodata benoemen']},
 {id:'quant',label:'Koers en toetsing',checks:['Alleen afgesloten, tijdig bekende koerswaarnemingen','Bandbreedtes vooraf bewaren','Koersreactie afzonderlijk van cijferverrassing toetsen']},
 {id:'risk',label:'Risico en tegenbewijs',checks:['Sterkste tegenargument en verliesmechanisme','Ontbrekend bronbewijs expliciet','Geen modeloordeel als handelsgoedkeuring']}
];
export function fiscalKey(label){const s=String(label||'').toUpperCase(),year=s.match(/(?:FISCAL(?: YEAR)?|FY)[ -]*(20\d{2})/)?.[1]||s.match(/20\d{2}/)?.[0]||(s.match(/\bFY[ -]*(\d{2})\b/)?.[1]?'20'+s.match(/\bFY[ -]*(\d{2})\b/)[1]:null),q=s.match(/Q\s*([1-4])|([1-4])(?:ST|ND|RD|TH)?\s*(?:QUARTER|KWARTAAL)/),w=s.match(/\b(FIRST|SECOND|THIRD|FOURTH)[ -]+QUARTER\b/);const n=q?(q[1]||q[2]):w?({FIRST:1,SECOND:2,THIRD:3,FOURTH:4}[w[1]]):null;return year&&n?year+'Q'+n:null;}
const number=s=>{const v=Number(String(s).replace(/[$,()\s]/g,'').replace('−','-'));return /\(.*\)/.test(s)?-Math.abs(v):v;};
const NUM='(\\(?\\s*\\$?\\s*[-−]?\\d[\\d,]*(?:\\.\\d+)?\\s*\\)?)';
export function epsFromQuote(quote,basis){
 const paired=quote.match(new RegExp('GAAP and non[- ]GAAP earnings per diluted share were\\s*'+NUM+'\\s+and\\s*'+NUM+'[, ]+respectively','i'));
 if(paired)return basis==='GAAP'?number(paired[1]):basis==='non-GAAP'?number(paired[2]):null;
 const name=basis==='non-GAAP'?'(?:Adjusted|non[- ]GAAP)':basis==='GAAP'?'(?<!non[- ])GAAP':basis==='IFRS'?'IFRS':null;
 if(!name)return null;
 const m=quote.match(new RegExp('\\b'+name+'\\s+(?:diluted\\s+)?(?:EPS|earnings per (?:diluted )?share)(?:\\s+[1-9])?\\s*(?:of|was|were|is|:)?\\s*'+NUM,'i'));
 return m?number(m[1]):null;
}
export function researchContext(input){return {protocol:RESEARCH_PROTOCOL,areas:RESEARCH_AREAS,method:'Eén brongebonden beoordeling met vier onderzoeksperspectieven; geen vier onafhankelijke analisten.',source_count:(input.sources||[]).length,consensus_scope:'Alleen opgeslagen providergegevens; periode en winstdefinitie moeten overeenkomen.',countercase_required:true,paid_services:false,trade_approval:false};}
function dateValue(s){const t=Date.parse(s+' UTC');return Number.isFinite(t)?new Date(t).toISOString().slice(0,10):null;}
// Deliberately narrow: explicit USD earnings headlines, not guessed table columns.
// Unsupported layouts/bases stay unknown and may use the existing quota-bounded model.
export function extractCachedActuals(input,time=Date.now()){
 const target=fiscalKey(input.cycle?.fiscal_label),release=Date.parse(input.cycle?.release_at),preferred=input.reference_forecast?.eps_basis||'GAAP';
 if(!target||!['GAAP','non-GAAP','IFRS'].includes(preferred))return null;
 const currency=input.reporting_currency||input.reference_forecast?.currency;
 if(currency!=='USD')return null;
 const candidates=[];
 for(const source of input.sources||[]){
  if(source.kind!=='earnings_release'||!/^https:\/\/www\.sec\.gov\/Archives\/edgar\/data\/\d+\//.test(source.url||'')||!/^\w{64}$/.test(source.sha256||'')||Date.parse(source.known_at)<release||Date.parse(source.known_at)>time)continue;
  const text=source.text||'',head=text.slice(0,6500),title=[...head.matchAll(/(?:First|Second|Third|Fourth)[ -]+Quarter(?:\s+(?:of\s+)?(?:Fiscal(?: Year)?\s+)?20\d{2})|Q[1-4]\s+FY(?:20)?\d{2}/gi)].find(m=>fiscalKey(m[0])===target);
  if(!title||/\b(?:CAD|AUD|HKD|NT\$|Canadian dollars|Australian dollars)\b/i.test(head))continue;
  const revenue=[...head.matchAll(new RegExp('\\brevenue\\s+(?:of|was|were|totaled|totalled|reached)\\s*'+NUM+'\\s*(million|billion)\\b','gi'))].filter(m=>!/(?:expect|outlook|guidance|data center|hyperscale|edge computing|international|segment|platform)/i.test(head.slice(Math.max(0,m.index-60),m.index)));
  if(!revenue.length||new Set(revenue.map(m=>number(m[1])*({million:1e6,billion:1e9}[m[2].toLowerCase()]))).size!==1)continue;
  const value=revenue[0],pair=head.match(new RegExp('GAAP and non[- ]GAAP earnings per diluted share were\\s*'+NUM+'\\s+and\\s*'+NUM+'[, ]+respectively\\.?','i'));
  let epsQuote=pair?.[0];
  if(!epsQuote){const name=preferred==='non-GAAP'?'(?:Adjusted|non[- ]GAAP)':preferred==='GAAP'?'(?<!non[- ])GAAP':'IFRS';epsQuote=head.match(new RegExp('\\b'+name+'\\s+(?:diluted\\s+)?(?:EPS|earnings per (?:diluted )?share)(?:\\s+[1-9])?\\s*(?:of|was|were|is|:)?\\s*'+NUM,'i'))?.[0];}
  const eps=epsFromQuote(epsQuote||'',preferred);if(!Number.isFinite(eps))continue;
  const dates=[];for(const m of text.matchAll(/(?:January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{1,2},?\s+20\d{2}/gi)){const d=dateValue(m[0]),t=Date.parse(d);if(/ended/i.test(text.slice(Math.max(0,m.index-160),m.index))&&t<release&&release-t<120*86400000)dates.push({date:d,quote:m[0]});}
  dates.sort((a,b)=>b.date.localeCompare(a.date));if(!dates.length)continue;
  const periodQuote=head.slice(Math.max(0,title.index-30),title.index+title[0].length);
  const evidence=[{source_id:source.id,metric:'period',quote:periodQuote},{source_id:source.id,metric:'period',quote:dates[0].quote},{source_id:source.id,metric:'revenue',quote:value[0]},{source_id:source.id,metric:'eps',quote:epsQuote}];
  candidates.push({summary:'De gerapporteerde kwartaalomzet en winst per aandeel zijn met vaste extractieregels uit de opgeslagen SEC-publicatie gelezen. Dit is cijferverwerking, geen nieuwe kwalitatieve koopbeoordeling.',counterarguments:['Er is geen volledige callbeoordeling of onafhankelijke accountantscontrole uitgevoerd.'],gaps:['Rapporteringsvaluta is gekoppeld aan de opgeslagen financiële context; niet afzonderlijk geaudit.'],stance:'insufficient_evidence',direction:'abstain',fiscal_label:input.cycle.fiscal_label,period_end:dates[0].date,currency,eps_basis:preferred,revenue:number(value[1]),revenue_unit:value[2].toLowerCase(),eps,evidence,guidance_review:'De vooruitzichten zijn niet door deze vaste cijferextractie kwalitatief beoordeeld. De vermelding van gerealiseerde cijfers geldt niet als een controle van de toekomstprognose.',call_review:'Er is geen gelezen calltranscript in deze cijferextractie. Dit blijft een afzonderlijk onderzoeksgat.',revenue_low:null,revenue_base:null,revenue_high:null,eps_low:null,eps_base:null,eps_high:null,calendar_date:null,calendar_quote:null,extraction_method:'cached-primary-rules-v1',currency_scope:'stored_financial_reporting_context',research_protocol:RESEARCH_PROTOCOL,model_generated:false,model:null,attempted_calls:0});
 }
 if(!candidates.length)return null;
 const first=candidates[0];if(candidates.some(c=>c.period_end!==first.period_end||c.eps!==first.eps||c.revenue*({million:1e6,billion:1e9}[c.revenue_unit])!==first.revenue*({million:1e6,billion:1e9}[first.revenue_unit])))return null;
 return first;
}
