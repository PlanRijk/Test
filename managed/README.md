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
- `functions/paper-research`: tweemaal per werkdag buiten US-uren een begrensde
  controle van 24 geselecteerde bronnen, officiële nieuwstitels, vertraagde
  FRED-context en netto-/kostenevaluatie per fase. Geen AI-training, automatische
  artikelinterpretatie of parameterwijzigingen. Een operator kan de alleen-lezen
  controle ook handmatig aanvragen met het serversecret.
- `functions/paper-learn`: twee dagelijkse leercontroles; een klein statistisch
  model wordt pas na voldoende afgesloten referentietransacties getraind en
  vervolgens afzonderlijk met nieuwe gegevens getest. Zie [LEARNING.md](LEARNING.md).
- `sql/001_paperlab.sql`: privétabellen, RLS, alleen voor de server toegankelijke
  RPC's, een lease en revisiecontrole tegen dubbele uitvoering en kasboekcontrole.
- `sql/002_learning.sql`: afzonderlijke proefportefeuilles, opleidingsgegevens,
  modelversies, controles, aankoopdossiers en terugschakeling.

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
- De bronnenroutine leest beperkte officiële feeds en macroreeksen en controleert
  statische bronmetadata. Zij vervangt het eerdere historische onderzoek of een
  volledige nieuws-/bedrijfsanalyse niet. Zie [RESEARCH-PLAN.md](RESEARCH-PLAN.md)
  voor de gelezen primaire bronnen, toetsbare hypothesen en ontbrekende bewijzen.
- Geen brokerverbinding, IBKR Gateway of echte transacties. De leerpijplijn
  wacht op voldoende echte proefgegevens; installatie betekent niet dat er al
  een getraind of winstgevend model is. Risicogrenzen blijven vast.
- Iedere nieuwe aankoop bewaart de oorspronkelijke motivatie, bekende
  koersmetingen, verwachte kosten en uitvoeringscontrole. De website toont
  dossiers en exporteert ze; oudere transacties krijgen geen verzonnen analyse.
- Op verzoek is de bestaande einddatum met dertig dagen verlengd tot 6 december
  2026 om 21:00 UTC / 22:00 Brussel. Verdere verlenging gebeurt alleen op verzoek.
- Zie [FREE-PLAN.md](FREE-PLAN.md) voor de gecontroleerde quota, verbruiksraming,
  automatische pauzes en beperkingen van de Render-kostenbewaking.

## Validatie

Vanuit de bestaande checkout:

```sh
node managed/tests/engine.test.mjs
node managed/tests/security.test.mjs
node managed/tests/usage.test.mjs
node managed/tests/review.test.mjs
node managed/tests/learning.test.mjs
node managed/check-public.mjs
```

De eerste suite vergelijkt onder meer voor alle honderd instrumenten een
synthetische koop/verkoop met de bestaande Python-motor, inclusief eigen valuta,
minimale commissies, belastingscenario en internationale reserves. De tweede
controleert eigenaar, AAL2, CORS, sessies, onbekende opdrachten en cronbeveiliging.
`tests/test_database.py` gebruikt uitsluitend een geïsoleerde lokale PostgreSQL-
container zonder netwerk, nooit de echte Supabase-database.
`tests/test_learning_database.py` controleert de gezamenlijke verwerking,
gescheiden kasboeken, aankoopdossiers, trainingslabels en promotie/terugschakeling
in een tijdelijke lokale testdatabase.

Een geslaagde lokale test bewijst geen echte providerkoersen of live installatie.
Voor oplevering moeten schema, import, anonieme weigering, eigenaaractivatie,
functiegeheim, scheduler, bronverbinding en één actuele opgeslagen meting op het
echte project worden gecontroleerd.

## Uitrol

De website staat op https://paperlab-prive.onrender.com. De productieprocessen
draaien op Supabase en vereisen geen open browser of actief ontwikkelproces.
`python scripts/managed_status.py` leest de actuele remote status, bronmetingen,
opslagomvang en de geplande taken zonder de portefeuille te wijzigen.

De initiële eigenaar kiest zelf een wachtwoord en koppelt TOTP via het persoonlijke
activatiebestand buiten Git. Bij latere aanmeldingen zijn wachtwoord en
authenticatorcode nodig. Een echt eigenaarsaccount wordt nooit gebruikt voor
automatische tests. Tijdelijke Auth-testaccounts worden na controles verwijderd.

`scripts/deploy_managed.py` heeft expliciete fasen: `database`, `functions`,
`config`, `site`, `activate`, `learning-schema` en `learning-enable`. Gebruik bij
een bestaande gevorderde portefeuille de laatste twee leerfasen; herhaal geen
import of eigenaaractivatie. Bronbackup en overdrachtsrecords blijven in
`.data/managed`, buiten Git. Supabase-functies worden achtereenvolgens uitgerold.
De Render-aanvraag is uitsluitend `static_site`, zonder betaald computeplan.
De standaardworkspace-ID is nodig als Cloudflare de workspace-lijst blokkeert.

De eenmalige `database`-import vereist ook de oorspronkelijke lokale SQLite-
backuphelpers en bronportefeuille. Latere beheerfasen en `managed_status.py`
werken vanuit de gepubliceerde managed checkout zonder het oude Python-programma.
Voer de import niet opnieuw uit om een intussen gevorderde productieportefeuille
te herstellen; daarvoor is een afzonderlijke gecontroleerde herstelprocedure nodig.

Beheerrechten zijn tijdelijk nodig voor de installatie. De website en Cron
gebruiken geen persoonlijke Management API-token; het verlopen van zo'n
beheertoken stopt de geïnstalleerde toepassing niet.
