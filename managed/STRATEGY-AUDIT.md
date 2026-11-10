# Audit van aankoop- en verkoopstrategie — 10 november 2026

De live privéaudit staat onder **Koopaanpak & modellen → Audit aankoop- en
verkoopstrategie**. Persoonlijke proefresultaten blijven in de afgeschermde
database. De audit koppelt verkopen aan hun aankoop en scheidt de instap- en
verkoopcohorten; een nieuwe exit op een oude positie is geen nieuwe instaptest.

## Conclusies

Een bewezen positief netto instapvoordeel ontbreekt. De oude kleine steekproef
bevat verlieslatende korte trades, hoge kosten en snelle herinstappen na winst.
De brongebonden vijfpijlerfilter is een kwaliteitscontrole, geen voorspelling van
een rendabele transactie. Een momentumsignaal over circa 25 minuten is niet
gevalideerd voor een meerdaagse horizon. Een hoger winstdoel bewijst geen hogere
winstkans of beter totaalrendement.

De kosten in deze proef zijn conservatieve aannames, inclusief belasting- en
buitenlandreserves. We verlagen die niet om een gunstiger resultaat te tonen.
Werkelijke brokerkosten en persoonlijke belastingen moeten later afzonderlijk
worden geverifieerd. Een passende passieve benchmark ontbreekt nog; de oude
Apple-vergelijking is daarvoor onvoldoende.

## Aangepast, als vooraf vastgelegde instapcontroles

`entry-audit-v1` beoordeelt iedere nieuwe aankoop en opnieuw de uitvoeringsquote:

- Maximaal 1,5% verwachte volledige koop-verkoopfrictie bij onveranderde markt,
  inclusief kosten, proefreserves, quote-spread en veronderstelde slippage.
- Minstens 24 verstreken uren herinstaprust na iedere verkoop van hetzelfde
  aandeel, ook na winst; langere bestaande pauzes worden niet verkort.
- Maximaal €20 geschat nettoverlies bij de bestaande stop voor een nieuwe positie.
- Maximaal €150 gezamenlijk geschat stopverlies voor bestaande posities en
  gereserveerde kandidaten. Dit is 75% van de bestaande €200-dagverliestrigger;
  de resterende ruimte is een buffer, geen garantie tegen gaps of correlatie.

De 1,5%-kostengrens is een vooraf gekozen kostenbudget (€7,50 op €500). De
€20/€150-risicobudgetten zijn behoudende proefgrenzen voor deze vaste rekening.
Deze waarden zijn niet op historische winst gemaximaliseerd of bewezen optimaal.
Kandidaten krijgen eerst capaciteit voor bestaande kooporders, daarna volgens
het oorspronkelijke momentumsignaal. Risico wordt voor de hele geselecteerde
groep gereserveerd; niet afzonderlijk opnieuw vanaf een leeg budget. Bij bestaande
posities telt het hoogste van het verlies tegenover de inleg bij de stop en de
daling van de huidige geschatte verkoopwaarde tot die stop. Zo verdwijnt de
terugvalruimte van opgelopen winsten niet uit het risicobudget.

De stopafstand wordt niet achteraf opgerekt. Het bestaande `net-exits-v1`-doel
blijft bevroren: maximaal gekozen uit €10, 2,5% van inleg en 1,5× geschat
stopverlies. De financiële invulling, vijf pijlers en beschermende verkopen blijven
de oorspronkelijke gecontroleerde modules gebruiken. Open posities worden niet
wegens de nieuwe instapgrenzen geforceerd geliquideerd. Eerdere verliezen blijven
zichtbaar; de overgang annuleert uitsluitend nog wachtende kooporders.

Het doel is eerst vermijdbare frictie en budgetoverschrijding te beperken.
Een lager handelsvolume kan weinig zinvolle herhaling voorkomen. Onderzoeken,
kandidaatmodellen en observaties blijven onafhankelijk van echt paperkapitaal
gegevens verzamelen. Herhaalde controles tellen niet als onafhankelijke leertrades.

De audit bevat ook een alleen-lezen uitlezing per open positie: geen verkooptrigger,
wachten op het extra netto risico-doel, latere bronkoers, ontbrekende verse quote,
gesloten markt of een beschermende trigger. Dat zijn verschillende oorzaken; een
wachtende positie is niet automatisch een door de winstgrens geblokkeerde order.
Een te hoog doel kan winst laten terugvallen; de huidige steekproef bewijst nog
niet welk doel optimaal is. De uitlezing schrijft geen orders en reconstrueert
geen gemiste historische winsten.

## Uitvoering en bronkwaliteit

De uitvoering gebruikt nog indicatieve Yahoo-koersen en een vijfminutenroutine
met een latere verse paperfill. Dat is geen brokerfeed of continu beschermende
stoporder. Het afzonderlijke IEX-onderzoek geeft één handelsplaats, geen bewezen
NBBO of compleet marktbeeld. Dit rechtvaardigt geen scalpstrategie. De vereiste
actualiteit, open sessie en broncontroles blijven gelden.

Onbekende kwalitatieve reviews worden niet automatisch goedgekeurd. Er is geen
zelfstandig tekstmodel dat alle rapporten begrijpt en geen automatische promotie
van een model zonder afzonderlijke toekomstige validatie. De bestaande minima
voor trainings-/validatie-/testgegevens blijven gehandhaafd.

Een historische onderzoeksronde bleek te blokkeren door verlies van float8-
precisie in SQL-naar-JSON-transport. Migratie 022 plaatst alleen de claim in een
functiecontext met `extra_float_digits=3`. Zo blijft de exacte bestaande bronprijs
behouden. De bevroren modelcode, bronrijen, oude voorspellingen en strenge
commitvalidatie worden niet gewijzigd. Een teruggedraaide productievalidatie
reproduceerde de fout bij beperkte precisie en slaagde met volledige precisie.

## Bronnen en verdere toetsing

- [FINRA Regulatory Notice 16-19](https://www.finra.org/rules-guidance/notices/16-19):
  waarschuwingen over stopprijzen, ongunstige uitvoering en tijdelijke schokken.
- [Bailey, Borwein, López de Prado en Zhu (2015), The Probability of Backtest
  Overfitting](https://www.davidhbailey.com/dhbpapers/backtest-prob.pdf):
  probleemstelling over herhaald optimaliseren en zwakke prestaties buiten de
  ontwikkeldata; titelpagina en relevante probleemsecties geraadpleegd.

Geraadpleegd op 10 november 2026. Deze bronnen onderbouwen de beperkingen en
werkwijze, niet onze percentages of een winstverwachting. De geteste nieuwe regels
moeten eerst nieuwe, gescheiden uitkomsten opleveren. Geen gegarandeerde winst,
geen schone voor/na-vergelijking met overgedragen posities en geen reden om nu
steeds nieuwe verkoopparameters te proberen.

Alle wijzigingen gebruiken de bestaande gratis infrastructuur en marktdata.
De audit bewaart één begrensde actuele controle, een fasebaseline en gewone
transactiebewijzen; geen nieuwe ruwe koersarchieven of betaalde AI-aanroepen.
