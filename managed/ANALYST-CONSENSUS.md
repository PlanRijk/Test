# Analistenconsensus volgens openbare provider

Versie `analyst-consensus-v1`. Aanvulling naast de mechanische kwartaalramingen en de
inhoudelijke tienbedrijvenpilot. Geen wijziging van de handelsmotor, koopgoedkeuring,
risicolimieten of bestaande eigenaarsvoorspellingen. Geen betaalde API geactiveerd.

## Bron en betekenis van controle

De openbare pagina `https://finance.yahoo.com/quote/SYMBOL/analysis/` toont kwartaal-
consensus volgens Yahoo Finance. De aparte quoteSummary-API antwoordde zonder toegang
HTTP401 en wordt niet gebruikt. Geen cookies, API-credentials, paywallomzeiling of
beschermde bronroute. Redirects, blokkades, ontbrekende tabellen en layoutwijzigingen
leveren `unavailable`, geen verzonnen schatting.

Ticker wordt gecontroleerd aan paginatitel en vaste bronroute. De collector leest alleen
zichtbare tabellen met expliciete kwartalen `0q`/`+1q`; jaarramingen worden genegeerd.
Gemiddelde, laagste en hoogste raming, valuta en een positief geheel aantal analisten
zijn per metriek vereist. EPS mag negatief zijn; omzetrange positief. Verwisselde
perioden of ongeldige bereiken worden geweigerd. Minder dan drie analisten krijgt een
zichtbare beperkte-steekproefmarkering. Getallen zijn de weergegeven, afgeronde waarden,
niet onderliggende ruwe feedprecisie.

EPS-basis volgt uitsluitend de expliciet geselecteerde GAAP- of Normalized-schakelaar.
Geen ondubbelzinnige selectie betekent `unknown`. Normalized wordt niet automatisch
identiek geacht aan de aangepaste EPS-definitie van het bedrijf. EPS-herzieningen over
7/30/60/90 dagen worden alleen overgenomen wanneer kwartaal en basis overeenkomen en
de actuele trendwaarde overeenstemt met de gemiddelde EPS-raming.

Dit is **brongecontroleerde providerconsensus**, niet onafhankelijk met een tweede
onderliggende dataset geverifieerde consensus. De bron vermeldt hier geen betrouwbare
onderliggende peildatum: `provider_updated_at=null`. `known_at` is onze echte
ophaaltijd. Ook een zojuist opgehaalde pagina kan vertraagde providergegevens tonen.
Providers kunnen verschillen door andere analisten, updatecycli en winstdefinities;
geen stilzwijgend middelen of kiezen van een gunstiger providerwaarde.

## Vergelijking met ons onderzoek

Onze omzetbasis wordt alleen numeriek vergeleken als beide metrieken beschikbaar zijn,
valuta en referentiemaand gelijk zijn en beide waarnemingen voldoende recent zijn.
Een maandmatch is nog geen geverifieerde volledige fiscale periodekoppeling. Afwijking
= `(onze basis / providergemiddelde − 1) × 100`. Dit is geen bewijs van een beter inzicht,
verwachte verrassing of toekomstig aandelenrendement.

EPS wordt **niet** automatisch vergeleken met onze rekenraming: daarvan is de GAAP/
Normalized-basis niet onafhankelijk bevestigd. Ook onze brede mechanische scenario-
banden zijn geen verdeling van analistenramingen. Bedrijfsprognose, providerconsensus,
eigen rekenraming en inhoudelijke eigenaarsvoorspelling blijven aparte gegevens.

Bestaande bevroren forecasts houden hun oorspronkelijke inhoud en consensusstatus.
Nieuwe providerwaarnemingen vóór een geregistreerde publicatie minus 24 uur kunnen
apart onwijzigbaar worden opgeslagen. Ze worden slechts aan een cyclus gekoppeld als
de providermaand overeenkomt met de numerieke referentieperiode, met expliciete
`cycle_match=baseline_reference_month_only`. Geen automatische fiscale of EPS-surprise-
beoordeling. Na de deadline worden geen nieuwe voorpublicatiekopieën toegevoegd.

## Doorlopende verwerking binnen bestaande gratis infrastructuur

Eén dagelijkse job `paperlab-analyst-consensus`, **07:35 UTC**, dus 08:35 Belgische
wintertijd en 09:35 zomertijd. Maximaal tien vervallen dossiers per normale ronde,
drie gelijktijdig. Alleen bedrijven met de bestaande ontvangen-koers-/officiële-bronbasis
komen in aanmerking. Normaal ongeveer wekelijks; bevestigde cijfers binnen 21 dagen
krijgen voorrang en dagelijkse opvolging. Bronfouten worden na twee dagen opnieuw
geprobeerd. Backlog en budget kunnen vertragen; geen SLA voor honderd tickers.

De eerste beheerde inleesronde mag maximaal zes begrensde batches op één UTC-dag
verwerken. De dagelijkse cron roept slechts één batch aan. Maximaal 750 kB gelezen
HTML per bedrijf; stoppen zodra de drie benodigde tabellen compleet zijn, zonder
hele pagina's of scripts uit te voeren. Alleen de gestructureerde cijfers en een hash
van het gedecodeerde HTML-prefix worden bewaard, geen permanente volledige pagina.
Een twaalfseconden-deadline per bron en leases beschermen de worker.

Conservatieve app-reservering 1,6 MB per bedrijf, maximaal 500 MB per UTC-maand.
Bestaande gedeelde soft/hard-grenzen en de databasegrens van 100 MB gelden daarnaast.
Quota zijn app-ramingen; andere organisatieconsumptie of providerbilling wordt hiermee
niet bewezen. Geen nieuwe betaalde dienst of abonnement. Toegang tot gratis openbare
pagina's is niet gegarandeerd en kan veranderen.

Maximaal acht private bronversies per bedrijf. Actuele bronfouten blijven zichtbaar;
een oude succesvolle versie wordt niet als actuele consensus voorgesteld. Versies en
voorpublicatiekopieën zijn gescheiden van de numerieke modelhistorie en eigenaarspilot.
Bronnen kunnen dezelfde upstream-feed delen; aantal websites is geen bewijs van
onafhankelijkheid.

## Installatie, beveiliging en herstel

`python scripts/analyst_consensus.py REF` installeert SQL035 en de aparte worker.
Bestaande jobs en bevroren handelsprofielen worden op gelijkheid gecontroleerd.
De eigenaars-/MFA-API toont de aanvulling via de bestaande onderzoekspagina; geen
wijziging in login, herstelcodes of brokerrechten. RLS en service-private tabellen;
claim/commit zijn token- en leasegebonden, bron/type/count/basis worden bij opslag
gecontroleerd. Configuratie en bronroutes komen niet uit anonieme gebruikersinput.

Herstelkopieën vanaf schema35 bevatten actuele consensus, historie en voorpublicatie-
kopieën. Eerst migraties t/m035 herstellen, dan workers hervatten. De followup-installer
herstelt035 als laatste leesadapter. Eerdere archieven hebben deze tabellen niet.

Tests: gecontroleerde synthetische HTML, identiteit, kwartaal/jaar, valuta, aantallen,
basis en missende velden, veilige streaming, bron401, vergelijking en niet-vergelijkbare
EPS; geïsoleerde PostgreSQL-tests voor eigenaar, opslagbewijzen en snapshots;
Chromium voor desktop/mobiel. Geen bewijs van handelsvoordeel of winstgevendheid.
