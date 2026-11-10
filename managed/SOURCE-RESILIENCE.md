# Bronnen, uitval en betrouwbaarheid

Uitgangspunt: weken tot maanden. Deze uitbreiding verandert geen handelsparameters,
leersplitsingen, kapitaal of kostenlimieten. Ontbrekende of tegenstrijdige financiële
onderbouwing mag geen goedkeuring worden. Alleen paperhandel blijft actief.

Voor alle 100 bedrijven zijn vijf bronplannen beschikbaar bij **Aandelen → Bronnen &
analyse**. Een jaarverslag, kwartaalverslag, IR-pagina, officieel publicatieregister,
aanvullende financiële reeks, sectorvergelijking en valutareferentie hebben een
expliciete rol. Een zoekpagina is geen gelezen rapport. Bereikbaarheid via HEAD
betekent uitsluitend dat de route bereikbaar was vanuit de genoemde omgeving.
Sectorgenoten zijn onderzoeksaanknopingspunten, niet automatisch directe concurrenten.

De nieuwe serverroutine vervangt alleen de bestaande bronmonitor op hetzelfde
cron-schema. Yahoo query1 krijgt query2 als technische terugval na een mislukte
transport-/validatiecontrole. Beide zijn één leverancier. HTTP 429 en Retry-After
leggen beide hosts stil; terugval mag geen rate-limit omzeilen. Exponentiële backoff
wordt opgeslagen. Bestaande cijfers behouden hun oorspronkelijke waarnemingsdatum.
De cache geldt na acht dagen niet als actuele financiële bronbevestiging; een
kwalitatieve review veroudert apart na zeven dagen. Een verse aanvullende reeks
maakt een oud officieel verslag of een oude review niet vers.

Vier jaarlijkse maatstaven worden vergeleken met opgeslagen officiële extracties,
alleen bij gelijke periode en valuta. Tolerantie: omzet, nettowinst en operationele
kasstroom 0,1%; vrije kasstroom 1% vanwege definitieverschillen. Dit is een detectiegrens,
geen bewijs van juistheid. Materiële verschillen in de eerste drie maken het actieve
financiële dossier ongeldig tot onderzoek. De bronreferentie en redenen blijven
opgeslagen. De originele rapportage plus verwerking is geen bewijs uit twee
onafhankelijke bedrijfsverklaringen. De secundaire cijfers krijgen geen voorrang.

De optionele reproduceerbare correctie gebruikt uitsluitend de unieke officiële
`us-gaap:Revenues`-context in de reeds vastgelegde jaaraccessie, met een vergelijkbaar
vorig jaar uit dezelfde accessie. Het CIK, concept, periode, oude waarden en ruwe
bronhash worden vastgelegd. Totale opbrengsten kunnen andere inkomsten omvatten;
dit bewijst geen organische groei. De oorspronkelijke broncontroledatum blijft
staan; alleen de nieuwe interpretatie krijgt een actuele kennisdatum. Overige
cijfers en kwalitatieve reviews worden niet herzien of automatisch goedgekeurd.

Budgetten blijven: bestaande bronmonitor maximaal zes bedrijven per ronde, vier
rondes per dag, 20 MB geschat bronverkeer per maand, gedeelde zachte grens 1 GB,
100 MB databasebewaking. Nieuwe gegevens hebben een eigen 3 MB opslagbewaking,
maximaal 6 KB status per bedrijf en 300 wijzigingsevents. Rapportteksten worden
niet massaal gekopieerd. Extra RPC-transport wordt op dezelfde budgetten geboekt.
Een zachte eigen raming is geen garantie over de volledige providerfactuur.

## Wat nog ontbreekt

Bij de start waren er 46 officiële cijferextracties en twee kwalitatieve reviews.
Bronplannen voor 100 bedrijven vullen die inhoudelijke hiaten niet automatisch.
SEC gaf vanuit Supabase HTTP 403; een IR-route is beschikbaar als onderzoekslocatie,
maar er is nog geen algemene automatische PDF-/XBRL-interpretatie voor alle Europese
verslagen. Voor concurrentievoordeel, risico's, sectorwaardering, winstkwaliteit,
financiering, recente materiële berichten en een volledige winstkalender blijft
inhoudelijke verificatie nodig. Er is geen betaalde externe tekstmodel-API toegevoegd.

De eigenaar hoeft geen honderd rapporten aan te leveren. Later zijn vooral broker
(en tariefprofiel), gewenste marktdatarechten en geverifieerde fiscale uitgangspunten
nodig voor werkelijke uitvoeringskosten en livehandel. Geen wachtwoorden, persoonlijke
belastingdocumenten of API-sleutels in de chat delen. Voor deze publieke bronuitbreiding
is geen nieuwe sleutel vereist.

Controle: Node-regressies voor terugval, cache, ratelimits, vergelijkbaarheid, XSS,
MFA en commitfouten; geïsoleerde PostgreSQL-regressie voor rechten, budgetten,
lease-eenmaligheid, materiële conflicten en behoud van brondata. Bron- en handels-
beleidsvingerafdrukken worden bij deployment gecontroleerd.

SQL025 normaliseert JSON-null naar SQL-NULL bij ontbrekende bronreferenties.
Dit verandert uitsluitend het opslagformaat en de correcte referentieteller,
niet de bronpolicy of beslisregels. Niet-objectreferenties worden geweigerd.
