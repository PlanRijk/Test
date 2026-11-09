# Boeken en koersvertraging — 9 november 2026

Op verzoek is de dagelijkse routine met vooraf geschreven notities gestopt:
`paperlab-reading` is inactief, de runtime staat op `owner_paused`. Het archief
blijft bewaard. De installatiehelper weigert heractivering. Er draait geen
zelfstandige AI-lezer; nieuwe inhoudelijke lectuur gebeurt tijdens werksessies.

## Rechtmatige volledige boeken en werkelijke leesvoortgang

**Poor Charlie’s Almanack**, Charles T. Munger, redactie Peter D. Kaufman,
Stripe Press 2023: [volledige digitale editie bij de uitgever](https://www.stripe.press/poor-charlies-almanack).
Dit is een verkorte editie van het oorspronkelijke boek; de digitale editie zelf
is volledig beschikbaar. Ook de [oorspronkelijke uitgever](https://www.poorcharliesalmanack.com/)
verwijst naar deze gratis ebookuitgave. Buffett schreef het voorwoord zelf.

Gelezen op 9 november:

- [Buffett’s voorwoord](https://www.stripe.press/poor-charlies-almanack/forewords#warren-e-buffett).
- [Hoofdstuk 3](https://www.stripe.press/poor-charlies-almanack/chapter-three), redactionele uitleg van Kaufman over Munger’s aanpak, hoofdtekst.
- [Lezing 9](https://www.stripe.press/poor-charlies-almanack/talk-nine), *Academic Economics: Strengths and Faults After Considering Interdisciplinary Needs*, hoofdtekst inclusief vragenronde en terugblik.

**Het hele boek is nog niet uit.** Geen percentage of datum van voltooiing verzonnen.

Eigen conclusies om later te toetsen:

1. Innovatie kan door concurrentie vooral klanten bevoordelen; omzetgroei is geen bewijs van aandeelhoudersrendement. Marges en benodigd kapitaal horen bij de analyse.
2. Handel, specialisatie, prikkels, financiële structuren en geopolitiek beïnvloeden elkaar. Volg het mechanisme en de gevolgen op meerdere termijnen.
3. Een economisch aantrekkelijk bedrijf kan een slechte investering zijn tegen een te hoge prijs. Kasstroom, kwaliteit en waardering moeten samen worden bekeken.
4. Beoordeel besluiten met de informatie die toen beschikbaar was. Een gunstige uitkomst achteraf kan geluk zijn; meer omzet/handelingen betekenen niet automatisch meer kennis.

Dit zijn interpretaties van auteursargumenten, geen onafhankelijk bewezen signalen.
Anekdotes en de geopolitieke uitspraken uit 2003 vragen onafhankelijke toetsing.
Munger’s voorkeur voor sterke concentratie is niet overgenomen. Geen regels,
modelgewichten of financiële grenzen zijn vanwege deze lectuur aangepast.

Vervolgselectie met primaire onderbouwing:

| Boek | Buffett-verbinding en toegang | Werkelijke status |
|---|---|---|
| The Intelligent Investor — Benjamin Graham | [Brief 2013, p. 20](https://www.berkshirehathaway.com/letters/2013ltr.pdf): zelf gelezen, belang van hoofdstukken 8 en 20 | Niet volledig gelezen; rechtmatig volledig exemplaar nodig |
| The Outsiders — William N. Thorndike Jr. | [Brief 2012, p. 22](https://www.berkshirehathaway.com/letters/2012ltr.pdf): expliciet aanbevolen | Niet volledig gelezen; rechtmatig volledig exemplaar nodig |
| The Clash of the Cultures — John C. Bogle | Zelfde brief 2012, p. 22 | Niet volledig gelezen; rechtmatig volledig exemplaar nodig |
| Lombard Street — Walter Bagehot (1873) | [Volledig publiek domein bij Gutenberg](https://www.gutenberg.org/ebooks/4359); geen bevestigde Buffett-aanbeveling | Volledige tekst gevonden; nog niet inhoudelijk uitgelezen |

Alleen eigen analyses, bronverwijzingen en controleerbare voortgang worden
gepubliceerd. Beschermde boekteksten staan niet in repository, browserassets of
de productiedatabase. De oude brievenroutine wordt geen vervanging voor lectuur.

## Meting van de koersvertraging

Beperkte steekproef tijdens de Europese sessie, geen garantie voor andere dagen:

- DSV, Novo Nordisk, Neste en Atlas Copco: enkele tot tientallen seconden bronleeftijd; in de herhaalde test was Neste ook 71 seconden oud. Dus geen universele grens van één minuut.
- KBC, ASML, SAP en AstraZeneca: ongeveer 15–16 minuten oud.
- `query1` versus `query2`, of `interval=1m` versus `5m`: dezelfde actuele bronstempels; geen oplossing voor de Europese vertraging.
- Een minuutgrafiek was ongeveer 3,5–4 keer groter zonder versere actuele metadata.
- VS was tijdens de meting gesloten; vrijdagstempels zijn dan geen bewijs van een lopende storing.

Gepaarde vergelijking van `5m` en `1d`: bij alle acht instrumenten dezelfde
actuele metadata-prijs én tijdstempel. Antwoorden met `1d` waren 1.232–1.307 bytes,
tegen 3.941–6.590 bytes voor `5m`: gemiddeld ongeveer 75% minder ongecomprimeerde
inhoud. Dit is een inhoudsmeting, geen providerfactuur of gegarandeerde snelheidswinst.

## Compact transport

`market-compact.js` gebruikt de bestaande, bevroren marktparser met uitsluitend
een andere candle-resolutie in de aanvraag. Orders blijven uitsluitend gebaseerd
op `meta.regularMarketPrice` en `meta.regularMarketTime`, nooit op candle-close.

- Bronouderdom >120 seconden en expliciete bronvertraging blijven geweigerd.
- Valuta, FX, sessies en alle financiële regels blijven identiek.
- `transport_variant` en `data_info.transport` maken de wijziging zichtbaar.
- De bestaande cronroute gaat naar `paper-tick-compact`, nog steeds elke vijf minuten, met dezelfde gedeelde download voor beide paperaccounts.
- Geen extra cronjob, betaald product, modelpromotie of portefeuilleherstart.
- De conservatieve bestaande verbruiksraming wordt niet verlaagd op basis van deze kleine proef.

De vijfminutencontrole kan ook bij een verse bron meerdere minuten detectiewachttijd
veroorzaken. Het dashboard toont daarom geen universele realtime-dekking. Om de
controlefrequentie te verhogen is eerst een geschikte feed en een compactere,
begrote dataverwerking nodig; de volledige bestaande pipeline vijfmaal zo vaak
laten lopen is niet zonder meer passend bij gratis quota.

## Beste vervolgroutes

**Gratis VS:** [Alpaca Basic](https://docs.alpaca.markets/us/docs/about-market-data-api)
biedt realtime IEX-data, 30 streamsymbolen en 200 historische API-verzoeken/minuut.
IEX is één handelsplaats, geen volledige geconsolideerde Amerikaanse marktfeed;
recente historische toegang heeft een beperking van vijftien minuten. Actuele
quotes en historische bars moeten niet worden verward. [Paper Only](https://docs.alpaca.markets/us/docs/paper-trading)
is wereldwijd met e-mail beschikbaar. Een eigen API-key én secret zijn nodig.
Er is nog geen Alpaca-account of koppeling gemaakt. Een stream vereist een
werkend serverproces; de gratis Render-site is een statische site.

**Europa:** nog geen rechtmatige gratis bron gevonden die onze volledige Europese
catalogus voortdurend binnen één minuut levert. Gelicentieerde brokerdata, zoals
IBKR, is de logische route zodra de entitlements en kosten per beurs zijn vastgesteld.
De IBKR-pagina bevat zowel professionele als particuliere prijzen; daarom geen
professioneel Euronext-tarief als persoonlijk aanbod gepresenteerd. Geen abonnement
of betaalde dienst geactiveerd. Geen automatisering van bronnen die dit verbieden.

Bronnen gecontroleerd op 9 november 2026; abonnementsvoorwaarden kunnen wijzigen.

## Uitvoering gecontroleerd

De compacte route is live in Supabase. De geplande ronde van 9 november 2026,
13:00 UTC / 14:00 Belgische tijd, verwerkte 47 Europese aanvragen en accepteerde
vier verse koersen; 43 te oude quotes bleven geweigerd. De VS was gesloten.
Financiële en onderzoeksprofielen bleven gelijk, het aantal cronjobs bleef tien
waarvan acht actief. De notitieroutine en historische bootstrap zijn inactief.

De volledige Node-testreeks en de deploymentcontroles zijn geslaagd. De nieuwe
transporttests vergelijken de oorspronkelijke parseruitvoer, weigeren oude quotes
en bewaken eenmalig ophalen, leaseafhandeling en de gescheiden grootboeken.
