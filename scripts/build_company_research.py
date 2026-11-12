"""Prepare transparent financial analysis and source passages for every company.

No extracted passage or rule-based number comparison constitutes a complete
qualitative review. No output can be written to company_reviews by this script.
"""
import datetime,json,math,re
from pathlib import Path

SECTOR={
 'IT':'Toets klantconcentratie, AI-investeringen, exportbeperkingen, productcycli, eigen R&D en de omzetting van vraag in kasstroom.',
 'Industrie':'Toets orderboek tegenover uitvoerbare leveringen, prijs/kostenontwikkeling, werkkapitaal, toeleveranciers en investeringscyclus.',
 'Gezondheidszorg':'Toets product- en patentconcentratie, klinische uitkomsten, vergoeding, toezicht, aansprakelijkheid en onderzoeksuitgaven.',
 'Financieel':'Toets rentegevoeligheid, kapitaal/liquiditeit, krediet- of verzekeringsrisico en waardering met passende sectormaatstaven.',
 'Financiële diensten':'Toets rentegevoeligheid, kapitaal/liquiditeit, krediet- of verzekeringsrisico en waardering met passende sectormaatstaven.',
 'Nutsbedrijven':'Toets gereguleerd rendement tegenover financieringskosten, investeringsverplichtingen, schuldafloop en mogelijke aandelenuitgiften.',
 'Materialen':'Toets grondstoffenprijzen, energie- en productiekosten, mijnbouw-/projectrisico, China en het cyclische karakter van kasstroom.',
 'Energie':'Toets olie-/gasprijzen, productiekosten, reserves, investeringen, afbouwverplichtingen en politieke blootstelling.',
 'Consumptie defensief':'Toets prijsverhogingen tegenover volume, marktaandeel, grondstofkosten, valuta en houdbaarheid van marges.',
 'Consumptie cyclisch':'Toets koopkracht, vraag/volume, prijsdruk, voorraden, financiering en gevoeligheid voor recessie.',
 'Communicatie':'Toets concurrentie, omzet per klant/adverteerder, content- of infrastructuuruitgaven en platform-/privacyregels.',
 'Vastgoed':'Toets AFFO/FFO, bezettingsgraad, huurders, LTV, taxaties en schuldafloop; nettowinst alleen is onvoldoende.'}
def valid(n):return isinstance(n,(int,float))and not isinstance(n,bool)and math.isfinite(n)
def amount(n,c):return f'{n:,.0f}'.replace(',','.')+' '+(c or 'valuta onbekend') if valid(n)else'onbekend'
def ratio(a,b):return a/b if valid(a)and valid(b)and b>0 else None
def clean_quote(s):
 return 100<=len(s)<=1800 and not re.search(r'forward.looking|could cause actual|cookie|privacy|table of contents|statements of cash flow|location belgium|stock information presented|^the risk.free rate',s,re.I)
def build(item,source,coverage,now):
 obs=coverage.get('observation',{});f=obs.get('financial',{});values=obs.get('values',{});currency=f.get('currency');period=f.get('period_end');findings=[]
 def add(topic,text,basis='stored_financial_observation'):findings.append({'topic':topic,'text':text,'basis':basis})
 add('Omzet en groei',f'Jaarperiode {period or "onbekend"}: omzet {amount(f.get("revenue"),currency)}. '+(f'Verandering tegenover de vergelijkbare opgeslagen jaarperiode: {f["revenue_growth"]:.1%}. Groei kan mede door overnames of valuta komen.'if valid(f.get('revenue_growth'))else'Een vergelijkbare groeivoet ontbreekt.'))
 income,ocf,fcf=f.get('net_income'),f.get('operating_cash_flow'),f.get('free_cash_flow');margin=ratio(income,f.get('revenue'));conversion=ratio(ocf,income)
 add('Winstkwaliteit',f'Jaarwinst {amount(income,currency)}; operationele kasstroom {amount(ocf,currency)}; vrije kasstroom {amount(fcf,currency)}. '+(f'Indicatieve nettomarge {margin:.1%}. 'if margin is not None else'')+(f'Operationele kasstroom/positieve jaarwinst {conversion:.2f}×; eenmalige posten, werkkapitaal en aandelenbeloning moeten apart worden beoordeeld.'if conversion is not None else'Een betrouwbare winst-kasstroomvergelijking ontbreekt of de jaarwinst is niet positief.'))
 if valid(fcf)and fcf<0:add('Kasstroomrisico','De opgeslagen vrije jaarkasstroom is negatief. Onderzoek of investeringen tijdelijk zijn en hoe het tekort wordt gefinancierd; omzetgroei alleen neemt dit risico niet weg.')
 debt,cash=f.get('total_debt'),f.get('cash');net=debt-cash if valid(debt)and valid(cash)else None;debtfcf=ratio(net,fcf)
 add('Financiering',f'Binnen dezelfde jaarmomentopname: schuld {amount(debt,currency)}, liquide middelen {amount(cash,currency)}. '+(f'Indicatieve netto-schuld {amount(net,currency)}. 'if net is not None else'Ontbrekende schuld/cash wordt niet als nul gerekend. ')+(f'Netto-schuld/vrije kasstroom {debtfcf:.2f}×. 'if debtfcf is not None else'')+'Dit is geen volledige liquiditeitstoets: recente emissies, aflossingskalender, leaseverplichtingen en convenanten kunnen ontbreken.')
 shares=values.get('annualDilutedAverageShares',[])
 if len(shares)>=2:
  a,b=shares[-2:];growth=ratio(b['value'],a['value'])
  if growth is not None and 300*86400000<(datetime.date.fromisoformat(b['end'])-datetime.date.fromisoformat(a['end'])).days*86400000<400*86400000:add('Verwatering',f'Gewogen verwaterd jaaraandelenaantal verandert met {growth-1:.1%}. Dit is niet hetzelfde als het actuele uitstaande aantal; aandelenbeloning en terugkoop vragen verdere controle.')
 quarters=values.get('quarterlyTotalRevenue',[])
 if len(quarters)>=5:
  a,b=quarters[-5],quarters[-1];days=(datetime.date.fromisoformat(b['end'])-datetime.date.fromisoformat(a['end'])).days;growth=ratio(b['value'],a['value'])
  if a['currency']==b['currency']and 300<days<400 and growth is not None:add('Recente kwartaalontwikkeling',f'Kwartaalomzet {b["end"]}: {amount(b["value"],b["currency"])}; {growth-1:.1%} tegenover {a["end"]}. Geen consensusvergelijking of verrassing vastgesteld.')
 annual=values.get('annualNetIncome',[])
 if len(annual)>=2 and valid(annual[-1]['value'])and valid(annual[-2]['value']):add('Resultaattrend',f'Opgeslagen jaarresultaat: {amount(annual[-2]["value"],annual[-2]["currency"])} ({annual[-2]["end"]}) naar {amount(annual[-1]["value"],annual[-1]["currency"])} ({annual[-1]["end"]}). Vergelijk consolidatiekring en eenmalige posten voordat dit als structurele trend geldt.')
 add('Mogelijke koersinvloeden',SECTOR.get(item['sector'],'Toets sectorcyclus, marges, financiering, regelgeving en vraagontwikkeling.')+' Bedrijfsspecifiek onderzoekspunt: '+item['company_risk']+'. Dit zijn te toetsen kanalen, geen vastgestelde oorzaak van een koersbeweging.','research_hypotheses')
 sources=[]
 for d in source['documents']:
  quotes=[]
  for topic,ss in d['excerpts'].items():
   selected=next((s for s in ss if clean_quote(s)),None)
   if selected:quotes.append({'topic':topic,'text':selected[:220],'truncated':len(selected)>220})
  sources.append({k:d[k]for k in ['url','sha256','retrieved_at','read_scope','kind','bytes','characters']}|{'passages':quotes})
 gaps=['Dit dossier is een eerste financiële analyse met bronpassages, geen afgeronde kwalitatieve koopbeoordeling.','Concurrentievoordeel, managementkwaliteit, materiële actualiteit en sectorspecifieke waardering vereisen expliciete inhoudelijke verificatie.','Geen volledige realtime nieuwsfeed, geverifieerde winstkalender, analistenconsensus of intrinsiekewaardemodel aangesloten.']
 if not coverage.get('verified_financials'):gaps.append('De gebruikte financiële reeksen zijn aanvullend; passende primaire cijferverificatie ontbreekt.')
 if not sources:gaps.append('In deze ronde kon geen officiële documenttekst worden opgehaald.')
 if not any(d['kind']in['10-K','10-Q','20-F','linked_financial_publication']for d in source['documents']):gaps.append('Er is geen volledige jaar-/kwartaalpublicatie in deze bronronde opgehaald; een IR-startpagina vervangt die niet.')
 if not any(s['passages'] for s in sources):gaps.append('De tekstextractie leverde geen geschikte contextpassages; bereikbaarheid bewijst geen inhoudelijke dekking.')
 return {'version':'company-research-v1','symbol':item['symbol'],'checked_at':now,'financial_known_at':obs.get('known_at'),'financial_basis':'secondary_stored_observation','financial_source_url':coverage.get('source_url'),'financial_source_hash':coverage.get('source_hash'),'financial_period':period,'findings':findings,'sources':sources,'filings':source.get('filings',[])[:6],'source_failures':source['failures'],'gaps':gaps,'trade_approval':False,'complete_qualitative_review':False,'refresh_method':'Onderzoek tijdens werksessies; bestaande financiële monitor blijft actief. Geen dagelijks autonome AI-beoordeling.'}
def main():
 import sys
 items=json.loads(Path(sys.argv[1]).read_text());sources={x['symbol']:x for x in json.loads(Path(sys.argv[2]).read_text())};current=json.loads(Path(sys.argv[3]).read_text());coverage={x['symbol']:x['record']for x in current['coverage']};now=datetime.datetime.now(datetime.timezone.utc).isoformat();rows=[build(c,sources[c['symbol']],coverage[c['symbol']],now)for c in items]
 assert len(rows)==100 and len({x['symbol']for x in rows})==100
 notes=json.loads((Path(__file__).resolve().parents[1]/'managed/knowledge/research-interpretations-2026-11-12.json').read_text())
 for r in rows:
  if r['symbol']not in notes:continue
  term,note=notes[r['symbol']]
  for source in r['sources']:
   path=Path(sys.argv[2]).parent/r['symbol']/(source['sha256']+'.txt')
   if not path.exists():continue
   text=path.read_text();at=text.lower().find(term.lower())
   if at<0:continue
   r['findings'].append({'topic':'Inhoudelijke broninterpretatie','text':note,'basis':'operator_reviewed_source_passage','source_url':source['url'],'source_sha256':source['sha256'],'source_excerpt':text[max(0,at-50):at+300]})
   break
 for r in rows:assert len(json.dumps(r,ensure_ascii=False).encode())<22000,r['symbol']
 Path(sys.argv[4]).write_text(json.dumps(rows,ensure_ascii=False,indent=2));print(json.dumps({'companies':len(rows),'documents':sum(len(x['sources'])for x in rows),'bytes':sum(len(json.dumps(x).encode())for x in rows),'trade_approvals':0}))
if __name__=='__main__':main()
