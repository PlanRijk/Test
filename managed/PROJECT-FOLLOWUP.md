# Doorlopende projectopvolging en herstel

Toegevoegd op 12 november 2026. Deze aanvulling verandert geen bevroren strategie,
portfolio, brokerkosten, belastingscenario, marktbron voor fills of modeltoetsen.

## Dagelijks en wekelijks

paperlab-project-followup draait dagelijks om 06:55 UTC: 07:55 in Belgische
wintertijd, 08:55 in zomertijd. Eén bevestigde planning; geen permanent Codex-proces.

- Alle 100 bedrijven krijgen dagelijks een onderzoeksprioriteit: ontbrekende of
  verlopen kwalitatieve review, verouderd onderzoek, gewijzigde financiële bron,
  bronproblemen en open posities. Signalering is geen inhoudelijke beoordeling.
- Op werkdagen maximaal twintig officiële publicatie-indexen of financiële
  publicatielijsten, oudste controle eerst. Een normale volledige cyclus duurt vijf
  werkdagen; bereikbaarheid en budget kunnen die verlengen. SEC HTTP403, te grote
  antwoorden en ontbrekende publicatiedata blijven zichtbaar. Na HTTP429 stopt die
  host in de batch. Er is geen zoek-/tekstmodel of volledige live nieuwsfeed.
- Nieuwe niet-beoordeelde relevante SEC-meldingen kunnen een bestaand dossier
  onbekend maken. Dit blokkeert nieuwe instap, geen beschermende verkoop.
- Op zondag een versleutelde logische applicatiekopie naar een private Storage-bucket.

De eerste uitgebreide inhoudelijke ronde blijft een gedateerde analyse. Een
dagelijkse groene monitoringstatus maakt die niet opnieuw inhoudelijk actueel.
Zie QUALITATIVE-AUTOMATION.md voor de afzonderlijke, nog niet geactiveerde modelpilot.

## Versiegeschiedenis en bronnen

Nieuwe inhoudsversies worden met hash bewaard: maximaal acht per bedrijf binnen
365 dagen en maximaal 8 MB voor deze historiek. Oudere details verdwijnen volgens
die grenzen; dit is geen onbeperkt point-in-time archief. De eerste 100 bestaande
kaarten zijn als beginversie overgenomen, zonder teruggedateerde analyses.

De verzamelde uitgepakte bronteksten en hun herkomst krijgen aparte versleutelde
archiefbundels. Het zijn de werkelijk geëxtraheerde teksten, niet de oorspronkelijke
PDF/HTML-bestanden. Een oorspronkelijk bestand is opnieuw via de bronlink op te
vragen; de bewaarde oorspronkelijke bronhash maakt wijzigingen detecteerbaar.
Beperkte PDF-leesscope blijft staan: een archief maakt ongelezen pagina's niet gelezen.

## Passieve referentie en uitvoeringskwaliteit

VWCE.DE: een accumulerend wereldwijd aandelenfonds in EUR, als prospectieve
indicatieve referentie. Start pas bij een na installatie waargenomen afgeronde
toekomstige bronsessie, zonder historische instap te verzinnen. Dagbewijzen worden
niet herschreven. Splitsingen stoppen de vergelijking voor beoordeling.

De referentie is vóór persoonlijke brokerkosten/belastingen. Prijstijdstip en
rekeningwaardering zijn niet exact uitgelijnd; het verschil bewijst geen alpha.
De bestaande bevroren onderzoeken blijven de plaats voor strategievalidatie.
Meer bewijs vraagt toekomstige waarnemingen en kan niet worden geïnstalleerd.

De handelsmotor gebruikt nog Yahoo/vijfminutenmetingen en latere verse paperfills.
Geen nieuwe realtime licentie, Alpaca-tradingendpoint of echte stoporder is toegevoegd.
Broker-/belastingverificatie en providerbrede factuurmeting blijven apart gemarkeerd.
App-tellers vervangen niet het Supabase-organisatiedashboard of de Render-meter.

## Herstelkopieën en toegang

Private bucket: paperlab-private-archives, geen publieke bucket of leespolicy.
AES-256-GCM met willekeurige nonce, gzip en authentieke contextbinding.
PAPERLAB_ARCHIVE_KEY staat als serversecret bij Supabase en in de **ongekoppelde**
Render-groep paperlab-beheer. Geen sleutelwaarden in Git, frontend of rapporten.

Wekelijkse snapshot: één consistente STABLE/MVCC-uitlezing met exacte
float-uitvoer; maximaal 30 MB ongecomprimeerde JSON. De cron bereidt de kopie voor buiten de korte
PostgREST-time-out; de server leest haar daarna in delen met hashes. Tijdelijke
voorbereidingsdelen hebben een lease en worden na bevestiging verwijderd. Zij bevat de geselecteerde
duurzame paperlab-tabellen. Niet inbegrepen: Supabase Auth/MFA, vaultgeheimen,
Storage-objecten, ruwe tijdelijke quotes, historische invoersnapshots en bepaalde
wachtrijen/tellers. Expirerende leases worden uit de kopie verwijderd.
Schema en migraties staan afzonderlijk in GitHub. Dit is geen volledige providerbackup.

Bewaring: maximaal zeven bevestigde wekelijkse applicatiekopieën. Verouderde
bestanden worden pas na bevestigde nieuwe kopie verwijderd, uitsluitend via
gevalideerde backup-paden; de bronarchieven worden hierdoor niet verwijderd.
Elke kopie wordt teruggelezen, ontsleuteld en exact met de oorspronkelijke tekst
vergeleken. Dat test cryptografie en integriteit, geen volledige Auth/providerrestore.
Herstel gebeurt eerst offline en nooit door een automatische portfolioreset.

Downloaden kan via de privéwebsite na eigenaar-MFA, met een link van tien minuten.
De gebruiker bewaart ook een eigen kopie en de archiefkey in een wachtwoordmanager:
opslag binnen hetzelfde Supabase-account is geen onafhankelijke uitwijkprovider.
Een toekomstige Codex-chat krijgt geen automatische toegang tot de Render-key.
Beveiligde heroverdracht of platformsecretkoppeling blijft nodig.

## Begrotingen en verificatie

Publicatiemonitor: 5 MB conservatieve reservering per werkdag, 120 MB/maand.
Referentie/opvolging: 200 kB per poging, maximaal twee per dag, 10 MB/maand.
Applicatiekopie: 50 MB reservering per poging, 300 MB/maand; geen teruggaaf bij
onzekerheid. Zowel bestaande lagere handmatige cap als gedeelde zachte grens
en 100 MB databasegrens blijven gelden. Bronarchieven boeken conservatieve
overdrachtskosten op de bestaande teller. Geen betaald plan wordt geactiveerd.

Controles: volledige Node-suite, netwerkloze PostgreSQL-regressie, gesimuleerde
modeladapter zonder echte API-aanvraag, Chromium op laptop/gsm en live controle
van private toegang, nieuwe planning, echte bronantwoorden en archiefintegriteit.
