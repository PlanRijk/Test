# Doorlopend onderzoek met de bestaande gratis middelen

Sinds migratie 039 gebruikt Paperlab een duurzame taakgrafiek in Supabase. De database en sleutels blijven bij de providers; de chat hoeft niet open te staan.

## Verwerking

1. Officiële SEC-publicaties en geregistreerde investor-relationsbronnen worden periodiek gecontroleerd. Rond een bekende cijferpublicatie (21 dagen ervoor tot 7 dagen erna) dagelijks, anders wekelijks. Onbevestigde publicatiedata blijven onbevestigd.
2. Volledige beschikbare HTML-teksten en tekst-PDF's worden gehasht en eenmaal opgeslagen. Elk blok van 7.000 tekens krijgt een afzonderlijke leestaak. Spreadsheetbestanden, gescande pagina's zonder OCR, onbereikbare bronnen en overschrijdingen van bronlimieten blijven expliciete gaten.
3. Gemini 3.5 Flash-Lite leest de blokken en extraheert feiten met letterlijk terugvindbare citaten, periode en cijferbasis. Ook een passage zonder relevante feiten krijgt een expliciet resultaat.
4. Na de documenten volgen zes Lite-beoordelingen: financiële positie, winst/kasstroom, concurrentie, management, waardering en risico's. De context bevat een begrensde, op onderwerp gerangschikte selectie van opgeslagen feiten, secundaire cijfers/consensus en eventuele peers. De selectie is geen uitputtende audit. Sectorsuggesties zijn geen bewezen economische concurrenten.
5. Gemini 3.8 Flash controleert alle zes pijlers. Een dossier kan worden afgerond **met gaten**. Zelfs een AI-dossier zonder vastgestelde gaten is geen onafhankelijk geverifieerde volledige bedrijfsanalyse, koopgoedkeuring of garantie op rendement. Rapporten wijzigen geen portefeuille, stopregels of vastgelegde voorspellingen.

De algemene FCF-DCF gebruikt drie expliciete vaste scenario's en alleen positieve, gelijktijdige FCF/aandelen/cash/schuld in dezelfde rapporteringsmunt. Ontbrekende of oude invoer maakt die berekening onbeschikbaar. De methode is niet zonder meer geschikt voor banken en verzekeraars. Geen analistenkoersdoelen verzinnen.

## Gratis quota en hervatten

Het door de eigenaar bevestigde Free-tier-project heeft volgens zijn AI Studio-scherm 500 Lite- en 20 Flash-aanvragen per dag. Paperlab reserveert iedere aanvraag vóór de netwerkoproep. Mislukte of onzeker afgebroken oproepen blijven conservatief meetellen; alleen aantoonbaar niet gestarte oproepen worden vrijgegeven.

Een Supabase-cron loopt iedere minuut. Eén globale lease voorkomt dubbel werk. De limieten per model zijn onafhankelijk (15/5 aanvragen per minuut, 250.000 inputtokens per minuut); de invoerreservering gebruikt een ruime bovengrens in bytes. Quota en status zijn zichtbaar onder onderzoeksopvolging. De oude fragmentworker is uitgeschakeld, zijn resultaten blijven bewaard.

Bij een daglimiet wacht de taak tot na middernacht **America/Los_Angeles**. Bij een korte limiet gebruikt Paperlab RetryInfo/Retry-After; zonder bruikbare aanwijzing geldt een veilige afkoelperiode. Bij tijdelijke provideruitval blijft hetzelfde blok bewaard voor een latere poging. Een verlopen lease wordt opnieuw ingepland. Het andere model blijft beschikbaar zolang zijn eigen quota dit toelaten. Wanneer Lite zijn daglimiet of afkoelperiode bereikt, kan vrije Flash-capaciteit ook nog ongelezen tekstblokken verwerken; eindcontroles hebben binnen hetzelfde bedrijfsprioriteitsniveau voorrang. Er is geen betaald alternatief, limietomzeiling of nieuw Google-project.

De volledige **bruikbare** capaciteit is beschikbaar; er worden geen nutteloze verzoeken verstuurd om een teller op te vullen. De 20 eindcontroles vragen eerst voldoende afgeronde Lite-beoordelingen. Google kan capaciteit beperken of quota wijzigen: 500+20 is een plafond, geen leveringsgarantie. De bestaande gedeelde gratis opslag- en verkeersbewaking blijft gelden en kan eerder pauzeren.

## PDF-verwerking

De Render-webservice `paperlab-pdf-reader` draait expliciet op het gratis plan. Deze leest alle pagina's van toegestane openbare PDF-bronnen, met bronhash en paginatelling. De service heeft uitsluitend een cron-authenticatiesleutel en geregistreerde bronhosts; geen Gemini-, broker- of beheersleutels. Maximum 20 MB, 600 pagina's en 2 miljoen teksttekens. Geen automatische OCR. Een slapende gratis service kan de eerste poging vertragen; de taak blijft in de wachtrij. Opnieuw opstarten en downloaden blijven onder providerlimieten vallen.

## Installatie en herstel

- `python scripts/deep_research.py kdyzlbknygeqinqduuic` past 039 toe, publiceert de Edge Function, behoudt bestaande dagreserveringen, schakelt de oude modelcron uit en installeert de minuutcron. Het script controleert dat bevroren handelsprofielen en andere cronjobs gelijk blijven.
- `python scripts/seed_deep_sources.py REF /pad/naar/brontekstarchief` importeert de volledige opgeslagen publieke verslagen hervatbaar op bronhash. Geen tekst of sleutels in Git.
- Vereiste providersecrets: bestaande `GEMINI_API_KEY`, `PAPERLAB_CRON_TOKEN` en niet-geheime `PAPERLAB_PDF_URL`. De PDF-service gebruikt `PAPERLAB_PDF_HOSTS` en dezelfde cron-authenticatie. Beheersleutels blijven in de bestaande afzonderlijke beheeropslag.
- De gewone versleutelde applicatiesnapshot bewaart documentmetadata/hashes, taken, claims en rapporten; grote reconstructeerbare bronlichamen, afleidbare nog niet gestarte taken en tijdelijke eventlogs worden eruit gelaten om de bestaande backupgrens te respecteren. De eerder versleutelde brontekstarchieven blijven apart beschikbaar. Bij volledig providerherstel eerst offline oefenen, de worker uit laten, de cache uit die archieven of op hash gecontroleerde openbare bronnen opnieuw vullen, en pas daarna activeren. Een gewone app-snapshot alleen herstelt die tekstcache niet.

## Grenzen van de kwaliteit

Niet voor elk van de honderd bedrijven bestaat al een compleet beschikbaar jaar-/tussenverslag, bruikbaar transcript, vergelijkbare peerdata of geverifieerde consensus. Tabellen, beelden, boekhoudkundige definities en toekomstige verwachtingen vragen inhoudelijke controle. Automatisch verwerken maakt ontbrekende gegevens niet bekend. Modeluitkomsten, broncitaten en een tweede modelcontrole sluiten fouten niet uit. Nieuwe bronversies starten nieuwe taken; ongewijzigde teksten worden hergebruikt.
