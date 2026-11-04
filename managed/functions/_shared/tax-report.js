// Informational annual reconciliation. Never rewrites cash, reserves or orders.
export function annualTaxReport(trades,year=2026){
 const lots=new Map(),rows=[],issues=[];let gains=0,losses=0,reserved=0;
 const valid=x=>typeof x==='number'&&Number.isFinite(x)&&x>0;
 for(const t of [...trades].sort((a,b)=>Date.parse(a.time)-Date.parse(b.time)||a.id-b.id)){
  const date=new Date(t.time),y=date.getUTCFullYear();if(y>year)continue;
  const q=Number(t.qty),price=Number(t.price),rate=Number(t.fx),known=valid(q)&&valid(price)&&valid(rate),list=lots.get(t.symbol)||[];
  if(t.side==='koop'){list.push({qty:q,unit:known?price/rate:null,year:y});lots.set(t.symbol,list);continue;}
  if(t.side!=='verkoop')continue;
  let remaining=q,basis=0,complete=known;
  for(const lot of list){if(remaining<=1e-8)break;const used=Math.min(remaining,lot.qty);if(lot.unit==null||lot.year<2026)complete=false;else basis+=used*lot.unit;lot.qty-=used;remaining-=used;}
  lots.set(t.symbol,list.filter(x=>x.qty>1e-8));if(remaining>1e-8)complete=false;
  if(y!==year)continue;
  reserved+=Number(t.capital_gains_reserve_eur)||0;
  if(!complete){issues.push({id:t.id,symbol:t.symbol,reason:'Fiscale aankoopbasis, valuta of volledige FIFO-historiek ontbreekt; oude posities vereisen de referentiewaarde van 31-12-2025.'});continue;}
  const gross=q*price/rate,gain=gross-basis;gains+=Math.max(0,gain);losses+=Math.max(0,-gain);rows.push({id:t.id,time:t.time,symbol:t.symbol,gross_sale_eur:gross,gross_purchase_basis_eur:basis,gross_gain_eur:gain});
 }
 const net=gains-losses,complete=issues.length===0,allowance=year===2026?10000:null;
 return {year,scope:'Alleen vastgelegde virtuele hoofdtransacties; geen persoonlijke belastingaangifte.',complete,gross_gains_eur:gains,gross_losses_eur:losses,net_gains_eur:net,
  recorded_paper_reserve_eur:reserved,scenarios:{ordinary_rate:.1,base_allowance_eur:allowance,
   allowance_fully_available_tax_eur:complete&&allowance!=null?.1*Math.max(0,net-allowance):null,
   allowance_used_elsewhere_tax_eur:complete?.1*Math.max(0,net):null},rows,issues,
  sources:['https://www.bolero.be/nl/lp/meerwaardebelasting','https://www.bolero.be/nl/lp/meerwaardebelasting/bronheffing-en-opt-out'],
  limitations:['Vrijstelling is persoonlijk en gedeeld over rekeningen; andere beleggingen en overdracht zijn onbekend.','Proefreserve is geen werkelijke bronheffing. Bolero opt-in/opt-out mag niet automatisch op IBKR of andere brokers worden toegepast.','Geen aanname dat frequent automatisch handelen onder normaal privébeheer valt. Een bijzonder/speculatief regime kan anders belast worden.','Voor oudere posities ontbreken eventuele eind-2025-waardering en overgangsregeling; zulke verkopen worden niet als volledig berekend gepresenteerd.','TOB, commissies en overige proefkosten worden niet van de bruto fiscale meerwaarde afgetrokken; zij verlagen wel het economische rendement.','Geen automatische kasvrijgave of terugbetaling; oorspronkelijk geboekte proefreserves blijven ongewijzigd.']};
}
