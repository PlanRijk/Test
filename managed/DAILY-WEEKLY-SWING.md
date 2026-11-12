# Dag-/weekmotor: quality-swing-paper-v1

Nieuwe, prospectieve **paperhypothese**, op verzoek van de eigenaar geactiveerd.
Geen IBKR-koppeling, brokerorders, betaald taalmodel of bewezen winstvoordeel.
IBKR en Belgische woonplaats zijn door de eigenaar opgegeven; tariefplan,
marktdatarechten en persoonlijke fiscale behandeling blijven ongeverifieerd.
De bestaande conservatieve kosten- en belastingreserves blijven identiek.

## Instap en omvang

- Alle vijf bestaande actuele bedrijfspijlers slagen. Onbekende beoordelingen blijven blokkeren.
- Twintig beschikbare, afgesloten dagsloten, bekend vóór het besluit; geen huidige sessie.
  Laatste slot maximaal zeven kalenderdagen oud. Dubbele dagen worden ontdubbeld.
- Laatste slot boven het gemiddelde van twintig slotkoersen en boven elk van de vijf
  voorafgaande slotkoersen; gemiddelde laatste vijf hoger dan de vijf ervoor.
  Dit is een voortschrijdende vijf-sessiefilter, geen kalenderweekcandle.
- Geen aankoop bij een onopgeloste bedrijfsactie of een dagrendement boven 20% in absolute
  waarde. Dit is een blokkering voor controle, geen volledige split/dividendverwerking.
- Actuele aankoopprijs in lokale valuta maximaal 1% van het bevestigde dagslot, in beide
  richtingen. Eerste/laatste halfuur uitgesloten; quote maximaal 120 seconden oud.
- Aankoopbesluit en uitvoering op verschillende, later gedateerde quotes. Bij uitvoering
  opnieuw bedrijf, dagsignaal, kosten, portefeuille, saldo, sector en cooldown controleren.
- Stopafstand maximaal van 3%, 2,5 maal de standaardafwijking van veertien dagelijkse
  slotrendementen (steekproef), en afstand tot het laagste van vijf recente slotkoersen
  plus 0,5 procentpunt. Een benodigde afstand boven 8% blokkeert; geen ingekorte stop.
  Dit gebruikt slotkoersen en is **geen ATR op OHLC-data**.
- Zoek de grootste positie van €100–€500 die past binnen €20 geschat netto stopverlies
  en €150 gezamenlijk risico. Nieuwe stopraming bevat 1% extra ruimte onder de stop,
  transactiekosten en bestaande belastingreserves. Dit is geen gegarandeerd verliesplafond.
  Het gezamenlijke risico telt ook terugval van de huidige geschatte liquidatiewaarde mee.
- Hoogstens één open kooporder tegelijk en twee aankopen per Brusselse dag. Bestaande
  kasreserve €1.000, 80% blootstelling, twaalf posities, twee per sector, €200 dagverlies-
  en €500 terugvaltrigger blijven behouden. Budgetbewaking blijft actief.

## Uitstap van NIEUWE posities

Netto winstdoel = maximum van €10, 2,5% van de werkelijke inleg, tweemaal het oorspronkelijke
begrote netto stopverlies inclusief de 1%-reserve. Dit oorspronkelijke risico blijft vast;
een later opgetrokken stop verlaagt het winstdoel niet. Verkoop op biedprijs met slippage,
kosten en voorlopige belastingreserves. Doel opnieuw controleren op de latere uitvoeringsquote.

Een afgesloten dagslot boven instap plus één oorspronkelijke koersrisico activeert een
opwaartse stopaanpassing op basis van de oorspronkelijke volatiliteitsafstand (minimaal 3%).
Alleen omhoog. Expliciete actuele beoordeling met `thesis_broken` of `critical` leidt tot
beschermend verkopen. Ontbrekende beoordeling is geen verzonnen gebroken these. Na twintig
beschikbaar afgesloten sessies sinds instap volgt eveneens verkoop, ook onder winstdoel.
Koersstop en rekeningrisicostops mogen altijd verlies realiseren. Bij ontbrekende quote
geen verzonnen uitvoering. Zonder recente dagdata worden tijd- en dagreview niet gefingeerd;
koersbescherming blijft werken.

## Overgang en bewijs

Bestaande lots, cash, kosten, resultaten, stops en hun netto winstregels worden bij activatie
niet veranderd. Iedere nieuwe positie draagt zijn eigen `swing`-versie en profiel; oude lots
blijven `net-exits-v1`. De rekening start niet opnieuw. Aankoopbewijzen bevatten twintig
dagsloten; nieuwe resultaten krijgen hun eigen cohort, los van oude verliezen en verkopen.
De bestaande €500-referentie en bevroren dag-/leer-/contextkandidaten blijven ongewijzigd.
De VWCE-vergelijking heeft zijn eigen startdatum en kostenbeperkingen; dit is geen nieuwe
perfect gepaarde benchmark en bewijst geen alpha. Parameters zijn vooraf gekozen hypotheses,
geen optimalisatie op de bestaande 27 gesloten trades. Geen automatische modelpromotie.

## Beheer, controles en herstel

`python scripts/daily_weekly_swing.py configure REF` versieert de code, installeert SQL032,
publiceert `paper-tick-swing` en wisselt atomair de URL in dezelfde bestaande cronjob.
Geen extra markt-downloads, jobs of betaalde resources. Elke versie heeft een vast codeprofiel;
eerder bevroren code en persoonlijk kostenprofiel worden niet herschreven.

De nieuwe SQL-ledger is de financiële behoudscontrole uit SQL011 met uitsluitend de
koopbewijseisen aangepast naar twintig dagsloten en €100–€500. Hij is privé; de actieve
commit controleert daarnaast versie, vijf actuele bedrijfspijlers, kosten, risico, lots,
stopbehoud en 24 uur herinstaprust. De oude worker kan na omschakeling niet meer claimen of
committen. De routine blijft afhankelijk van vertrouwde servicecode; dit is geen cryptografisch
bewijs van een beursuitvoering. Brondata blijven indicatief, geen geconsolideerde IBKR-feed.

Tests: Node strategieproeven en bestaande suite; geïsoleerde PostgreSQL-proef met echte
leases, risicogestuurde aankoop, nettowinst, verliesstop en tijdsuitstap, plus weigering van
corrupt saldo, ontbrekend bedrijfsbewijs en te hoog risico. Tests bewijzen implementatie,
geen winstgevendheid.

Back-ups vermelden schema32 en nemen de nieuwe runtime mee. Bij herstel vóór hervatting van
workers migraties t/m032 installeren, dezelfde opgeslagen beleids-/codeversies gebruiken en
cronroute controleren. Een oud archief van vóór deze fase bevat het nieuwe profiel niet.
Niet blind de oudere priority-configurator of oudere worker activeren. De followup-installer
herinstalleert032 na031 zodat hij de oude route niet terug kan openzetten.
