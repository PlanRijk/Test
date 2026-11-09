# Amerikaanse openingsmeting, Euronext/BEL20 en vernieuwen — 9 november 2026

## Werkelijke Amerikaanse meting

De reguliere Amerikaanse sessie opende om 15:30 Belgische tijd. De meetfunctie
werd daarna twaalfmaal met een minuut tussenruimte aangeroepen, vanaf
**15:31:17 tot 15:42:17**. De eerste twee batches kregen HTTP 400 door het
verschil tussen Yahoo `BRK-B` en Alpaca `BRK.B`. De expliciete vertaling is
gecorrigeerd en getest. Deze twee mislukte rondes tellen niet als leeftijdsmetingen.
Er zijn geen verzonnen resultaten voor exact 15:30.

**Tien geslaagde rondes, telkens alle 53 Amerikaanse catalogusnoteringen:**

| Grootheid | Mediaan | 95e percentiel | Maximum |
|---|---:|---:|---:|
| Supabase–Alpaca HTTP-aanvraag inclusief antwoord | 131 ms | 225 ms | 313 ms |
| Volledige meetaanvraag vanuit Codex | 366,7 ms | 547,4 ms | 547,4 ms |
| Leeftijd van een bruikbare bied-laatquote | 0,953 s | 23,721 s | 238,812 s |
| Leeftijd laatste IEX-transactie | 5,341 s | 141,451 s | 236.544,408 s |

524 van 530 quote-momentopnamen waren jonger dan één minuut (**98,9%**).
Per ronde waren dat 51–53 van 53 aandelen. Uitschieters: SO éénmaal, AMT driemaal,
EQIX tweemaal boven één minuut. Alle geslaagde rondes bevatten 53 tweezijdige quotes.
Bij sommige aandelen was de laatste IEX-transactie nog van vrijdag, terwijl de
quotes wel werden bijgewerkt. Quoteleeftijd en transactieleeftijd zijn aparte maten.

Dit is een korte, onderling afhankelijke steekproef bij één opening, geen garantie
voor elk aandeel op elk moment. IEX is één handelsplaats. De vertraging van een
geconsolideerde feed, nieuws, fundamentele cijfers en een volledig orderboek zijn
hiermee niet gemeten. De leeftijd van de laatste gebeurtenis is ook niet gelijk
aan de zuivere netwerkvertraging. De meting vergelijkt bronstempels met de serverklok.

De onderzoeksfunctie `paper-alpaca-latency` gebruikt alleen twee vaste GET-endpoints
(quotes en trades), weigert anonieme toegang en retourneert geen sleutels of
providerfoutteksten. Ruwe feedantwoorden blijven lokaal onder `.data`, buiten Git;
de website bevat alleen afgeleide meetstatistieken. De 24 provider-aanvragen in
het begrensde onderzoek ontvingen samen ongeveer 120 kB bruikbare antwoordinhoud.
Geen permanente cronjob, betaalde dienst, order of rekeningreset toegevoegd.

De bestaande handelsroute gebruikt nog de compacte Yahoo-aanvraag met de oude
vijfminutencadans. Een praktische volgende fase is een **aparte compacte Amerikaanse
batch per minuut**, met echte bronstempels, bronidentificatie en een vooraf bepaald
verbruiksbudget. De volledige bestaande pipeline vijfmaal vaker uitvoeren is geen
verantwoorde shortcut. Een gewijzigde bron hoort herkenbaar in de uitvoeringen en
onderzoeksvergelijkingen, met behoud van bestaande verliezen en posities.

De maximumleeftijd kan niet universeel worden gegarandeerd als de bron geen nieuwe
gebeurtenis publiceert. Oude data blijven geweigerd; ontvangsttijd mag de oude
bronstempel niet vervangen. Een eventuele stream op het gratis plan kent een
30-symbolenlimiet; de geteste REST-batches bevatten wel alle 53 noteringen.

## Euronext en BEL20

Een aparte actuele steekproef van onze tien Brusselse noteringen gaf ongeveer
**15–25 minuten bronleeftijd**. De BEL20-indexstand liep ongeveer vijftien minuten
achter. Een grotere leeftijd kan tevens minder recente handel boven op de
bronvertraging weerspiegelen. Alleen de bronstempel is gemeten, geen afzonderlijke
licentievertraging per instrument. Meer verversen of een andere candle-resolutie
haalt deze vertraging niet weg.

De BEL20-indexstand is een andere gegevensreeks dan de twintig onderliggende
aandelen. Onze catalogus bevat tien Brusselse noteringen, geen volledige actuele
BEL20-samenstelling. Voor uitbreiding eerst actuele leden, ISIN, share class en
handelsplaats bevestigen. Een indexprijs is geen uitvoeringsprijs voor de aandelen.

| Route | Publiek gevonden prijs | Bruikbaarheid en open punten |
|---|---|---|
| IBKR Cboe EU Equities L1 | “Fee Waived” voor niet-professionele gebruikers | Realtime alternatieve Europese handelsplaats. Geen identieke Euronext-feed. Dekking, spreads en API-rechten per aandeel bevestigen. |
| IBKR Euronext Legacy Retail Cash & Indices L2 | €3/maand voor niet-professionele gebruikers | Brussels/Paris/Amsterdam/Lisbon in de tabel. “Legacy” maakt beschikbaarheid voor een nieuw account onzeker. Geen bevestigd persoonlijk aanbod. |
| Euronext Web Services | Offerte; geen gratis realtime aanbod bevestigd | Officiële realtime/delayed/historische API met quotes, laatste prijs, transacties en referentiedata. Passende gebruiksrechten nodig. |
| Twelve Data Cboe Europe | Vanaf USD 300/jaar, als add-on op een actief abonnement | Geen gratis route. De goedkope display-licentie kan automatische verwerking/opslag uitsluiten; juiste non-display-rechten bevestigen. Euronext zelf staat op de exchange-lijst als EOD. |
| Officiële vertraagde Euronext-data | Intern gebruik kosteloos volgens de publicatie | Bruikbaar voor langer onderzoek. Geen oplossing voor uitvoering op verse koersen. |

**Kosten en voorwaarden bij IBKR:** de officiële API-documentatie verlangt een
geopend PRO-account, USD 500 accountwaarde (of equivalent) naast abonnementskosten,
een passend data-abonnement en de Market Data API Acknowledgement. Die accountwaarde
is geen maandelijkse abonnementskost, maar wel geld dat op de rekening moet staan.
Een demoaccount kan geen data-abonnement nemen. Het PRO-platformtype is niet hetzelfde
als de classificatie “professional” voor beursdata. De professionele Euronext-prijs
van €91,50/maand is daarom niet als particulier tarief gebruikt.

Voor automatische orderinzending moet bij IBKR ook de API User Activity Certification
correct ingevuld worden. De Euronext-policies onderscheiden display van non-display
(waaronder algoritmische beslissingen); een schermabonnement is niet vanzelf bewijs
dat iedere vorm van analyse, opslag of verwerking is toegestaan. De effectieve
marktdataregels zijn per 1 oktober 2026 gewijzigd. Daarom rechten en beschikbaarheid
bevestigen vóór een abonnement of een ingebouwde handelsbron.

Voor continu gebruik moeten daarnaast de API-sessie en eventueel Gateway-hosting
worden opgelost. Onze Render Static Site kan geen blijvend Gateway-proces draaien.
Een kosteloze dataregel betekent dus niet automatisch een volledig kosteloos,
onderhoudsvrij IBKR-systeem.

**Voorkeursroute:** eerst kosteloze Cboe EU-data onderzoeken zodra een geschikt IBKR-
account beschikbaar is. Voor exacte Euronext-koersen het retailpakket en de API-
rechten laten bevestigen. Een offerte bij Euronext Web Services is het alternatief
voor directe HTTP-toegang zonder zelf een broker-Gateway te beheren. Geen account
of betaald abonnement geopend; geen aanbieder namens de gebruiker benaderd.

Primaire bronnen, gecontroleerd op 9 november 2026:

- [IBKR-prijstabel](https://www.interactivebrokers.com/en/pricing/market-data-pricing.php), met onderscheid per rij tussen `non-pro` en `pro`.
- [IBKR API-marktdatavereisten](https://www.interactivebrokers.com/docs/general/market-data-subscriptions/market-data-requirements).
- [IBKR minimale accountwaarde](https://www.interactivebrokers.com/docs/general/market-data-subscriptions/market-data-subscription-minimum-equity-balance-requirements).
- [IBKR API Acknowledgement](https://www.interactivebrokers.com/docs/general/market-data-subscriptions/compliance-requirements-for-api-market-data/market-data-api-acknowledgement).
- [IBKR automatiseringsverklaring](https://www.interactivebrokers.com/docs/general/market-data-subscriptions/compliance-requirements-for-api-market-data/api-user-activity-certification/automation-and-software-disclosure).
- [Euronext Web Services](https://www.euronext.com/en/data/how-access-market-data/web-services).
- [Euronext toegangswegen en vertraagde data](https://www.euronext.com/en/data/real-time-data/how-access-market-data).
- [Euronext prijzen en gebruik](https://www.euronext.com/en/data/real-time-data/pricing-specs-agreements/market-data-pricing-policies).
- [Euronext regels vanaf oktober 2026](https://www.euronext.com/en/data/real-time/reasonable-commercial-basis).
- [Twelve Data-prijzen](https://twelvedata.com/pricing) en [beursdekking](https://twelvedata.com/exchanges).

## Vernieuwen zonder opnieuw aanmelden

De website krijgt een knop **Gegevens vernieuwen**. Deze haalt de laatste opgeslagen
gegevens en de zichtbare onderzoekspagina opnieuw op. Ze plaatst geen orders en
start geen extra marktmeting.

Een geverifieerde aanmelding wordt alleen in `sessionStorage` van het tabblad
bewaard: toegangstoken, vernieuwingstoken, vervaltijd, oorspronkelijke starttijd,
laatste activiteit en paginanaam. Geen wachtwoord, authenticatorsecret of herstelcodes.
De browser kan tabbladsessies herstellen; de tijdslimieten en servercontrole blijven
daarom leidend. Er wordt geen `localStorage` of onbeperkte “onthoud mij”-login gebruikt.

Bij reload blijft de app verborgen totdat de server de bestaande sessie opnieuw
heeft geaccepteerd. Verlopen toegangstokens kunnen eenmalig worden vernieuwd met
het vernieuwingstoken. Parallelle aanvragen delen dezelfde tokenvernieuwing.

Dertig minuten zonder activiteit, acht uur totale looptijd, intrekking, uitloggen
of een door de server geweigerde MFA-sessie leiden opnieuw naar aanmelden. Reload
begint de acht uur niet opnieuw en zet oude inactiviteit niet op nul. Uitloggen
wist de tabbladopslag; ook op gsm is nu een zichtbare uitlogknop beschikbaar.

Browservalidatie met synthetische accounts controleerde MFA vóór opslag, GET-only
vernieuwen, reload en paginabehoud, tokenrotatie, afzonderlijke tabs, inactiviteit,
AAL1-weigering, uitloggen en desktop/gsm-layout. Geen echte inloggegevens of
productiemutaties gebruikt. De volledige Node-reeks is tevens uitgevoerd.
