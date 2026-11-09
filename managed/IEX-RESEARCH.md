# IEX-minuutonderzoek en focuscontrole

Geactiveerd op 9 november 2026. Afzonderlijk onderzoek naar de 53 Amerikaanse
noteringen in de bestaande handelscatalogus. Geen orders, training, wijziging van
verlieslimieten of vervanging van de Yahoo-uitvoeringsbron.

## Vast protocol

`iex-study.js`, `paper-iex-research` en SQL014 vormen een bevroren implementatie:
`59afb4581a2db6765d692fb84788d7f26f34a53b0167225a723cd245b19ba27f`.
Profiel: `d8f80337e0be26bc00f3bdea9ed8b6fe660c28e01b8f43f65e6f7f1393d78a83`.

Eerste fase: 9 november 16:32:49 UTC tot 23 november 16:32:49 UTC
(17:32:49 Belgische wintertijd). Bestaande gratis Supabase-cron: eenmaal per minuut
binnen mogelijke reguliere NY-beursuren. Twee begrensde IEX-bronaanvragen, met
`BRK-B` expliciet naar providerinstrument `BRK.B`. Er is geen aparte feestdagen-
kalender; oude bronstempels worden niet als vers beschouwd.

We bewaren bied/laat, bronmoment en laatste transactieprijs/bronmoment compact.
Dagsamenvattingen volgen versheid, spreads en verschillen tegenover echt opgeslagen
vijfminutenreferenties. Die verschillen bewijzen geen betere instap of stopuitvoering.
Een IEX-quote is geen geconsolideerde NBBO en een verse quote kan ongunstig zijn.

Grenzen: 400 pogingen per dag, 200 MB eigen geraamd maandverkeer, 12 MB eigen
opslag; gedeelde pauze vanaf 105 MB database of 1,05 GB geraamd maandverkeer.
Reserve vóór downloaden: 50 kB, gevolgd door conservatieve verrekening. Maximaal
800 minuutbatches binnen een rollend venster van 48 uur tijdens collectie;
60 dagen dagsamenvattingen. Samenvattingen behouden statistiek, geen volledig
koerspad. Dit zijn app-begrotingen, geen providerfactuur of garantie van gratis
ononderbroken werking. Geen betaalde uitbreiding wordt gestart.

Leases, revisiecontrole en eenmalige commits voorkomen dubbele registratie.
RLS en alleen service-role RPC-uitvoering; de website vraagt eigenaar + AAL2 en
een geldige toepassingssessie. Pauzeren en hervatten resetten geen budget of fase.

## Begrensde focuscontrole

18 meetpunten tussen 17:40:48 en 17:43:38 Belgische tijd, ongeveer elke tien seconden:
TM, ICE, AMT, CME, AAPL en MSFT. Exploratief kwaliteitsfilter: maximaal 60 seconden
oud, positieve bied-/laatomvang, IEX-code V, voorwaarde R en maximaal 25 bp spread.
Geen optimale handelsregel of uitvoering bewezen.

TM, ICE en AMT hadden geen passend meetpunt. CME had er 11/18, AAPL en MSFT 18/18.
Een illustratieve €500-instap op het eerste passende punt vereist met de bestaande
proefkosten ongeveer 1,08% (AAPL) respectievelijk 1,16% (MSFT) stijging van de
**toekomstige biedprijs** om quitte te spelen. Dit is geen directe vergelijking met
het achteruitkijkende momentumkenmerk van +0,2%, geen daadwerkelijke rekeningwinst
of -verlies, en geen bewijs van voorspelkracht. Latere prijzen waren alleen
rekenwaarden; er is geen gunstigste uitstap achteraf gekozen.

SQL015 bewaart het volledige compacte bewijs en een vaste kostenconfiguratie
privé, maximaal tien rapporten van 24 kB. De eigenaarweergave verstuurt alleen de
samenvatting en de laatste zes minuutquotes. SQL016 biedt daarnaast een uitsluitend
lezend dashboard van de actieve €10.000-rekening; oorspronkelijke rekeningen,
kasboeken, profielen en afgeschermde onderzoeken blijven behouden.

## Controles

`npm test` in managed; `test_iex_database.py` en `test_dashboard_database.py` gebruiken
uitsluitend een lokale netwerkloze PostgreSQL-container. `browser_refresh.py`
gebruikt synthetische authenticatie. `browser_layout.py` kan privé opgeslagen
alleen-lezen snapshots tonen met alle API-verzoeken afgevangen; nooit live orders.
