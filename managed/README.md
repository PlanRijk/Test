# PaperLab: gratis beheerde proef

Deze uitvoering gebruikt een gratis Render **Static Site** en een bestaand
Supabase Free-project in een EU-regio. Er wordt geen VPS, betaalde webservice,
database, disk, custom domain, SMS of AI-abonnement aangemaakt.

## Huidige website

https://paperlab-prive.onrender.com · standaard de actieve €10.000-proef.
Posities en motivaties bij Mijn portefeuille; brononderzoek bij Marktdata;
daguitkomsten bij Onderzoeksresultaten; koopkritiek en modellen apart. De oude
€500-referentie blijft bereikbaar via Instellingen. Zie [IEX-RESEARCH.md](IEX-RESEARCH.md)
en [FUND-COMPARISON.md](FUND-COMPARISON.md).

## Actieve strategische prioriteit

Vanaf 12 november: **beheer bestaande posities, onderzoek vóór nieuwe instap**.
Nieuwe aankopen in capital10k zijn afzonderlijk geblokkeerd totdat kosten,
uitvoering en een samenhangend meerdaags protocol voldoende zijn onderbouwd.
Posities en beschermende verkopen blijven behouden. De bestaande bevroren
context-kandidaat krijgt onderzoeksvoorrang, geen handelspromotie.
Zie [STRATEGY-PRIORITY.md](STRATEGY-PRIORITY.md) voor de keuze, voorwaarden en behoudscontroles.

## Actualisatie onderzoek en herstel — 12 november 2026

Alle honderd bedrijven hebben een uitgebreid financieel onderzoeksdossier.
Er zijn 314 officiële pagina's/documenten opgehaald voor 99 bedrijven; ontbrekend
bewijs blijft zichtbaar. De dagelijkse onderzoekswachtrij en publicatiemonitor,
begrensde versiegeschiedenis, prospectieve wereldwijde ETF-referentie en
versleutelde bron-/applicatiearchieven staan beschreven in
[PROJECT-FOLLOWUP.md](PROJECT-FOLLOWUP.md). De eerste herstelkopie is teruggelezen,
ontsleuteld en met geselecteerde financiële gegevens offline gerepeteerd; dit
is geen volledige Supabase Auth/MFA/providerbackup.

Volledige modelmatige tekstbeoordeling is **niet geactiveerd**. De geteste
pilotadapter, broncontroles en kostenraming staan in
[QUALITATIVE-AUTOMATION.md](QUALITATIVE-AUTOMATION.md). API-key, expliciet budget,
gedeeld kostenregister en pilotbeoordeling zijn nodig vóór betaalde verwerking.
Er is geen bewezen winstgevendheid of automatische goedkeuring toegevoegd.

## Vijf bedrijfspijlers

Vanaf 10 november krijgen nieuwe actieve €10.000-paperaankopen een verplichte
brongebonden bedrijfsbeoordeling en een aparte instaproute. Ontbrekende gegevens
blokkeren de koop. Zie [COMPANY-ENTRIES.md](COMPANY-ENTRIES.md); dit is nog geen
bewezen winstgevende strategie. De vaste referentieproeven blijven behouden.

## Bronkaarten voor alle honderd bedrijven

Onder Aandelen opent elk bedrijf zijn eigen brongebonden analyse. Primaire
verslagcijfers, aanvullende reeksen en nog ontbrekende kwalitatieve onderbouwing
worden zichtbaar onderscheiden. De gratis automatische financiële bronmonitor
blijft apart van de koopgoedkeuring. Zie [COMPANY-COVERAGE.md](COMPANY-COVERAGE.md).

## Onderdelen

- `web/`: Nederlandstalige website; alleen publieke projectconfiguratie.
- `functions/paper-api`: eigenaarcontrole, verplichte TOTP/AAL2, sessies en
  portefeuillebediening. Geen publieke registratie.
- `functions/paper-tick`: elke vijf minuten opvraagbare handelsronde; verse
  Yahoo-prijzen, ECB-dagkoersen en vaste handelsregels. Alleen paperorders.
- `functions/paper-research`: tweemaal per werkdag buiten US-uren een begrensde
  controle van 28 geselecteerde bronnen, korte primaire bronfragmenten, officiële nieuwstitels, vertraagde
  FRED-context en netto-/kostenevaluatie per fase. Geen AI-training, automatische
  artikelinterpretatie of parameterwijzigingen. Een operator kan de alleen-lezen
  controle ook handmatig aanvragen met het serversecret.
- `functions/paper-learn`: twee dagelijkse leercontroles; een klein statistisch
  model wordt pas na voldoende afgesloten referentietransacties getraind en
  vervolgens afzonderlijk met nieuwe gegevens getest. Zie [LEARNING.md](LEARNING.md).
- `sql/011_capital_study.sql` en [CAPITAL-STUDY.md](CAPITAL-STUDY.md):
  afzonderlijke EUR10.000-paperrekening met EUR500-orders, eigen kasboek en motivering, hergebruik van de bestaande marktbatch en gratis verbruiksgrenzen.
- `sql/010_candidate_comparison.sql` en [CANDIDATE-COMPARISON.md](CANDIDATE-COMPARISON.md):
  twee afzonderlijke bevroren kandidaatmodellen, dagelijks getoetst op gedeelde toekomstige daguitkomsten via de bestaande leercontrole.
- `sql/009_optimization_review.sql` en [OPTIMIZATION-REVIEW.md](OPTIMIZATION-REVIEW.md):
  periodieke kosten-, bron-, voortgangs- en budgetcontrole via de bestaande bronnenroutine, met begrensde logopruiming.
- `sql/008_breadth_study.sql`, `functions/paper-breadth` en [BREADTH-STUDY.md](BREADTH-STUDY.md):
  alle extra geschikte modelvoorspellingen en uitkomsten compact bewaren,
  maximaal veertig uitgebreide invoerdossiers per werkdag, automatische budgetrem.
- `sql/007_history_learning.sql`, `functions/paper-history` en [HISTORY-LEARNING.md](HISTORY-LEARNING.md):
  afzonderlijk historisch dagmodel vanaf 2007, bevroren dataset en dagelijkse
  prospectieve controle; SEC-context en optionele aanvullende databronnen.
- `sql/006_daily_study.sql`, `functions/paper-daily` en [DAILY-STUDY.md](DAILY-STUDY.md):
  prospectief dagonderzoek naar 150 bedrijven, 1/5/20 beursdagen, gedateerde
  marktcontext en afzonderlijke opslag- en toetsgrenzen; geen orders of labels.
- `sql/001_paperlab.sql`: privétabellen, RLS, alleen voor de server toegankelijke
  RPC's, een lease en revisiecontrole tegen dubbele uitvoering en kasboekcontrole.
- `sql/002_learning.sql`: afzonderlijke proefportefeuilles, opleidingsgegevens,
  modelversies, controles, aankoopdossiers en terugschakeling.
- `sql/003_continuous.sql`: begrensde onderzoeksclaims en dagelijks onderhoud,
  ook wanneer paperhandel of leerverwerking gepauzeerd is.
- `sql/004_opportunities.sql`: afzonderlijk kansenregister, vaste meetperioden,
  gespreide indicatieve sectormand en begrensde onderzoeksopslag.
  Zie [OPPORTUNITY-STUDY.md](OPPORTUNITY-STUDY.md).
- `sql/005_reliability.sql` en `functions/paper-audit`: compact archief,
  afgeschermde toetsperiodes, bevroren trainingsinvoer, eenmalige onafhankelijke
  modelbeoordeling en een afzonderlijk fiscaal proefjaaroverzicht.
  Zie [RELIABILITY.md](RELIABILITY.md) voor voorwaarden en beperkingen.

Het oude Python/SQLite-programma en zijn data blijven behouden. Import herschrijft
geen bestaande transacties en weigert een afwijkende bestaande doelportefeuille
te resetten. Oude profielen blijven herkenbaar. Nieuwe uitvoeringen noemen
`transport_version=supabase-v1`; de bestaande handelsparameters blijven gelden.

## Beveiliging

Frontendconfiguratie bevat alleen de project-URL en een publishable/anon-key.
Managementtokens, service-role keys, cronsecret, gebruikerwachtwoorden en TOTP-
seeds horen nooit in browserbestanden of Git. Sessietokens blijven alleen in het tabbladgeheugen en sessionStorage; herladen
herstelt pas na servercontrole. Dertig minuten inactiviteit of maximaal acht uur
vereist opnieuw aanmelden. Wachtwoorden en TOTP-codes worden niet bewaard. Alleen een door Supabase
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
- Sinds het aanvullende verzoek van 4 november werkt de proef doorlopend zonder
  vaste einddatum (`operation_mode=continuous`). De oorspronkelijke `run_until`
  blijft auditinformatie. Risico-, opslag- en gratis verbruiksgrenzen blijven gelden.
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
node managed/tests/opportunities.test.mjs
node managed/tests/reliability.test.mjs
node managed/tests/tax-report.test.mjs
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
`tests/test_continuous_database.py` toetst de oude einddatum, onderzoeksleases,
budgetpauze en onderhoud zonder aankoopdossiers te verwijderen.
`tests/test_opportunities_database.py` controleert tijdsvolgorde, afzondering
van transacties/trainingslabels, beveiliging, budget en foutisolatie.
`tests/test_reliability_database.py` toetst 50.000 compacte records, opslagrotatie,
afgeschermde uitkomsten, beoordeling en toelating met verplichte datasetsnapshot.

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
`config`, `site`, `activate`, `learning-schema`, `learning-enable` en `continuous-enable`. Gebruik bij
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

De eenmalige fase `continuous-enable` is specifiek voor de goedgekeurde overgang
zonder bestaande modellen/opleidingslabels. Zij behoudt de rekeningen en vernieuwt
uitsluitend de vergelijkingsfingerprint voor de gewijzigde looptijdcode. Herhaal
haar niet wanneer later echte opleidingsgegevens of modellen bestaan.

## Beheertoegang herstellen

Bij geweigerde Codex-beheertokens en niet-overeenkomende Render-workspaces is er
[een expliciete versleutelde herstelroute](ACCESS-RECOVERY.md). Alleen de publieke
herstelsleutel staat in de website; de privésleutel en leesbare token horen nooit
in chat of Git. Het beheercommando na herstel is
`python scripts/access_recovery.py run scripts/managed_status.py`.
