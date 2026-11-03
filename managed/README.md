# PaperLab: gratis beheerde proef

Deze uitvoering gebruikt een gratis Render **Static Site** en een bestaand
Supabase Free-project in een EU-regio. Er wordt geen VPS, betaalde webservice,
database, disk, custom domain, SMS of AI-abonnement aangemaakt.

## Onderdelen

- `web/`: Nederlandstalige website; alleen publieke projectconfiguratie.
- `functions/paper-api`: eigenaarcontrole, verplichte TOTP/AAL2, sessies en
  portefeuillebediening. Geen publieke registratie.
- `functions/paper-tick`: elke vijf minuten opvraagbare handelsronde; verse
  Yahoo-prijzen, ECB-dagkoersen en vaste handelsregels. Alleen paperorders.
- `functions/paper-research`: dagelijks buiten US-uren controle van negentien
  geselecteerde bron-URL's en deterministische evaluatie. Geen AI-training,
  nieuwe inhoudsanalyse of automatische parameterwijzigingen.
- `sql/001_paperlab.sql`: privétabellen, RLS, alleen voor de server toegankelijke
  RPC's, een lease en revisiecontrole tegen dubbele uitvoering en kasboekcontrole.

Het oude Python/SQLite-programma en zijn data blijven behouden. Import herschrijft
geen bestaande transacties en weigert een afwijkende bestaande doelportefeuille
te resetten. Oude profielen blijven herkenbaar. Nieuwe uitvoeringen noemen
`transport_version=supabase-v1`; de bestaande handelsparameters blijven gelden.

## Beveiliging

Frontendconfiguratie bevat alleen de project-URL en een publishable/anon-key.
Managementtokens, service-role keys, cronsecret, gebruikerwachtwoorden en TOTP-
seeds horen nooit in browserbestanden of Git. Sessietokens staan alleen in het
browsergeheugen; herladen vereist opnieuw aanmelden. Alleen een door Supabase
geverifieerde eigenaar met AAL2 kan de portefeuille lezen of bedienen.

RLS staat aan op alle tabellen in het niet-publieke schema `paperlab`. De RPC's
zijn niet uitvoerbaar door `anon` of `authenticated`; alleen de Edge-server mag
ze aanroepen. De gebruiker kiest zelf een wachtwoord en bevestigt de authenticator.
Herstelcodes worden als SHA256-hashes opgeslagen en werken eenmaal. De eerste
privéactivatielink wordt niet gemaild of publiek gepubliceerd.

## Bewuste beperkingen

- Geen garantie op ononderbroken werking: gratis hosting heeft quota en kan
  worden beperkt of gepauzeerd. Houd de providerlimieten in het oog.
- Maximaal twee minuten bronleeftijd; vertraagde of ontbrekende prijzen worden
  nooit vervangen door demo. Een andere host maakt Yahoo niet realtime.
- Vijfminutenmetingen en uitvoeringen op een latere verse quote; geschatte
  spread/slippage en voorlopige belasting-/kostenaannames.
- De nettowinstvloer is nog EUR0,01; dit is besproken, maar niet aangepast.
  Het bruto winstdoel wordt verhoogd om kosten en die vloer te dekken.
- Beschermende verkopen kunnen verlies maken; stops zijn geen verliesgarantie.
- Ruwe quotes blijven twee dagen in de beheerde database. Transacties, hun
  bewijzen, portefeuillecurve en belangrijke auditgebeurtenissen blijven behouden.
- De bronnenroutine controleert bereikbaarheid; zij vervangt het eerdere
  historische onderzoek of een volledige nieuws-/bedrijfsanalyse niet.
- Geen brokerverbinding, IBKR Gateway, zelflerend model of echte transacties.
- De bestaande proef stopt op 6 november 2026 om 21:00 UTC / 22:00 Brussel.
  De einddatum wordt niet stilzwijgend verlengd.

## Validatie

Vanuit de bestaande checkout:

```sh
node managed/tests/engine.test.mjs
node managed/tests/security.test.mjs
node managed/check-public.mjs
```

De eerste suite vergelijkt onder meer voor alle honderd instrumenten een
synthetische koop/verkoop met de bestaande Python-motor, inclusief eigen valuta,
minimale commissies, belastingscenario en internationale reserves. De tweede
controleert eigenaar, AAL2, CORS, sessies, onbekende opdrachten en cronbeveiliging.
`tests/test_database.py` gebruikt uitsluitend een geïsoleerde lokale PostgreSQL-
container zonder netwerk, nooit de echte Supabase-database.

Een geslaagde lokale test bewijst geen echte providerkoersen of live installatie.
Voor oplevering moeten schema, import, anonieme weigering, eigenaaractivatie,
functiegeheim, scheduler, bronverbinding en één actuele opgeslagen meting op het
echte project worden gecontroleerd.

## Uitrol

`scripts/deploy_managed.py` heeft expliciete fasen: `database`, `functions`,
`config`, `site` en `activate`. Bronbackup en overdrachtsrecords blijven in
`.data/managed`, buiten Git. Supabase-functies worden achtereenvolgens uitgerold.
De Render-aanvraag is uitsluitend `static_site`, zonder betaald computeplan.
De standaardworkspace-ID is nodig als Cloudflare de workspace-lijst blokkeert.

Beheerrechten zijn tijdelijk nodig voor de installatie. De website en Cron
gebruiken geen persoonlijke Management API-token; het verlopen van zo'n
beheertoken stopt de geïnstalleerde toepassing niet.
