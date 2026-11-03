# Hoe PaperLab van de markt kan leren

Onderzoeksprotocol `paper-study-v1`, vastgesteld op 3 november 2026.
De lopende paperproef eindigt op 6 december 2026 om 22:00 Belgische tijd.
Het doel is vaststellen of een herhaalbaar voordeel **na kosten en risico**
aannemelijk wordt. Meer transacties of een mooie korte grafiek zijn geen succesmaat.

## Wat de gelezen primaire bronnen betekenen

| Bron | Wat is onderzocht | Gevolg voor deze proef |
| --- | --- | --- |
| Barber en Odean, 2000, origineel artikel via de auteurswebsite | 66.465 Amerikaanse huishoudens, 1991–1996; frequent handelen ging samen met slechtere nettoresultaten | Meet commissie, spread, slippage en reserves afzonderlijk. Minder handelen kan gunstiger zijn. Oude VS-resultaten zijn geen voorspelling voor ons of huidige IBKR-tarieven. |
| Moskowitz, Ooi en Pedersen, 2012, auteurs-/AQR-samenvatting | Tijdreeksmomentum met onder meer twaalfmaandsrendementen op 58 futures/forwards | Dit ondersteunt geen directe winstclaim voor ons 0,2%-signaal op vijfminutenmetingen. Frequentie en instrumenten verschillen. Alleen de beschikbare samenvatting is gelezen. |
| Bailey e.a., auteursversie 2015, *Probability of Backtest Overfitting* | Selectie uit vele strategieën kan schijnbaar goede backtests produceren; gewone holdout kan tekortschieten | Registreer alle geteste varianten, houd tijdvakken gescheiden, en rapporteer mislukkingen. Eén apart testvak bewijst geen blijvend voordeel. |
| Bailey en López de Prado, 2014, *Deflated Sharpe Ratio* | Selectiebias en niet-normale rendementen vertekenen prestatiematen | Bereken geen indrukwekkende jaarlijkse Sharpe op een paar transacties. Een gecorrigeerde significantietoets is nog niet uitgevoerd. |
| Harvey, Liu en Zhu, NBER 20592, publieke samenvatting | Veel gelijktijdig onderzochte rendementsfactoren verhogen de kans op valse ontdekkingen | Beperk de hypothesen; het beste resultaat uit honderd instellingen is geen onafhankelijk bewijs. Alleen de samenvatting is gelezen. |

Het bestaande historische rapport in `research/RAPPORT.md` blijft relevant voor
crisismechanismen. De jaarlijkse landenreeksen toetsen geen vijfminutenstrategie.
De huidige catalogus van honderd bestaande ondernemingen kent selectiebias;
een terugtest op alleen deze latere overlevenden mag niet als brede historische
wereldmarkttoets worden gepresenteerd.

## De onderzoeksvraag eerst kleiner maken

De lopende baseline blijft herkenbaar: honderd aandelen, eigen beurssessies,
EUR-boekhouding, dezelfde voorlopige kosten-/belastingregels en risicogrenzen.
Een parameterfingerprint in ieder nieuw rapport maakt wijzigingen zichtbaar.
Geen artikel, nieuwstitel, macrogetal of onderzoeksroutine verandert die regels.

De primaire maat is EUR-portefeuillewaarde na daadwerkelijk geboekte proefkosten,
met daarnaast een afzonderlijk gelabelde schatting van toekomstige verkoopkosten.
Belastingreserves zijn modelschattingen; actuele persoonlijke Belgische belasting
en werkelijke brokerkosten zijn niet volledig geverifieerd. De routine rapporteert:

1. Resultaten en aantallen per strategie- en uitvoeringsversie. De acht oude
   acties bewijzen niets over de latere beheerde uitvoering.
2. Netto gesloten resultaten, totale kosten en reserves, open blootstelling en
   waardering met geschatte uitstapkosten. Gesloten winnaars alleen zijn onvoldoende.
3. Verse bronmetingen ten opzichte van verwachte metingen per beurs, en mislukte
   rondes. Gesloten beurzen tellen niet als ontbrekende koersen. De aggregatie
   begint bij installatie; oudere dekking wordt niet verzonnen. Een nooit
   aangeroepen worker kan ontbreken in deze meting en vereist ook Cron-controle.
4. Besluit-tot-uitvoeringstijd en bronleeftijd bij uitvoeringen. Indicatieve
   Yahoo-quotes met een aangenomen spread bewijzen geen brokerliquiditeit.
5. Kostenhordes voor hypothetische EUR100-orders, inclusief spread/slippage.
   Alleen al EUR2,50 minimale commissie per zijde is ongeveer EUR5 op een
   EUR100-ronde, vóór andere kosten. De benodigde koersstijging volgt uit het
   kostenmodel, niet uit een voorspelling dat die stijging zal optreden.

## Vergelijking en volgende hypothesen

Een cashreferentie van 0% zonder rente is duidelijk maar zwak. Voor een uitspraak
over beleggingsvoordeel is ook een breed gespreide, eenvoudige marktbenchmark
nodig, met dezelfde EUR-valuta, periode, beschikbare data en toepasbare kosten.
De bestaande AAPL-lijn is onvoldoende gelijkwaardig: één aandeel en afwijkende
belasting-/kostenaannames. Een echte vergelijkbare ETF-benchmark is nog niet
geïmplementeerd; gegevens en toepasselijke Belgische heffingen moeten eerst kloppen.

Twee volgende onderzoekshypothesen zijn vooraf vastgelegd, nog niet geactiveerd:

- **Minder omzet:** toets of een dagelijkse/langzamere trendvariant na alle kosten
  beter presteert dan de intradaybaseline en een eenvoudige marktbenchmark.
  Maandmomentumonderzoek wordt niet klakkeloos vertaald naar een 200-dagenregel.
- **Risico gericht op marktomstandigheden:** toets één vooraf bepaalde
  volatiliteits-/trendfilter op dezelfde signalen en gelijke blootstelling, naast
  een controle met alleen minder belegd geld. Zo wordt niet elk lager verlies
  automatisch aan een slimmere voorspeller toegeschreven.

Voor die toetsen ontbreken nog een betrouwbaar historisch intradaybestand of
correct aangepaste dagprijzen, dividend/splits, voldoende onafhankelijke
testperioden en een vergelijkbare benchmark. Dagprijzen of vertraagde koersen
mogen voor historisch onderzoek bruikbaar zijn, maar worden daardoor geen
toegestane actuele uitvoeringskoersen. De dertig dagen dienen eerst voor
operationele validatie en hypothesevorming, niet als bewijs van blijvende winst.

## Automatische, begrensde bron- en portefeuille-evaluatie

De Supabase-routine draait op werkdagen om **06:30 en 22:30 UTC**: tijdens deze
proef om **07:30 en 23:30 Belgische tijd**. Zij blijft buiten reguliere VS-uren.
De portefeuillecollector blijft afzonderlijk draaien.

- Vaste inventaris van 24 beoordeelde bronnen. Statische bronnen krijgen maximaal
  wekelijks een bereikbaarheids-/metadatacontrole; fouten worden eerder herprobeerd.
- Officiële Fed-/ECB-feedtitels en vier FRED-contextreeksen worden in begrensde
  omvang ingelezen. Geen berichteninstructies worden uitgevoerd en er is geen
  automatische analyse van volledige nieuwsartikelen of zelfstandige AI-training.
- Datums, ouderdom en ontbrekende/verouderde macrogegevens blijven zichtbaar.
  Een FRED-observatiedatum bewijst niet het oorspronkelijke publicatiemoment.
  VIX is geen crashkans in procenten; context is geen koop- of verkoopsignaal.
- Dagaggregaten bewaren koersdekking langer dan de tweedaagse ruwe quotedata.
  Rapporten krijgen kleine omvangslimieten; oude rapporten worden opgeruimd.
- Geen betaalde data, AI-aanroepen, managementtokens in de functies of echte orders.
  De grenzen in [FREE-PLAN.md](FREE-PLAN.md) blijven gelden.

Een automatisch rapport formuleert onderzoeksvragen. Het traint geen model en
gaat niet zelfstandig nieuwe websites ontdekken of bewezen winstgevende regels
promoveren. In deze chat interpreteer ik de opgeslagen resultaten verder wanneer
we eraan werken; er draait geen permanente denkende chatsessie.

## Bronnen

- [Barber & Odean: origineel artikel](https://faculty.haas.berkeley.edu/odean/Papers%20current%20versions/Individual_Investor_Performance_Final.pdf)
- [Auteurswebsite Odean](https://faculty.haas.berkeley.edu/odean/)
- [Time Series Momentum: AQR/auteurs-samenvatting](https://www.aqr.com/Insights/Research/Journal-Article/Time-Series-Momentum)
- [Probability of Backtest Overfitting: auteursversie](https://www.davidhbailey.com/dhbpapers/backtest-prob.pdf)
- [Deflated Sharpe Ratio: auteursversie](https://www.davidhbailey.com/dhbpapers/deflated-sharpe.pdf)
- [Harvey, Liu & Zhu: NBER-samenvatting](https://www.nber.org/papers/w20592)

Downloadchecksums, leesomvang en mislukte aanvullende downloads staan in
`knowledge/provenance-2026-11-03.json`. De volledige auteurs-PDFs worden niet
opnieuw gepubliceerd. De MIT-download gaf 403; de geprobeerde Investor.gov-
fees-URL gaf 404. Die zijn niet als gelezen bewijs gebruikt.
