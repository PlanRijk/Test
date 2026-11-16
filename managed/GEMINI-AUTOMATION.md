# Automatische kwalitatieve concepten op de gratis laag

Model en gratis tarieven gecontroleerd via https://ai.google.dev/gemini-api/docs/pricing#gemini-3.5-flash-lite en https://ai.google.dev/gemini-api/docs/models/gemini-3.5-flash-lite. Vastgezet model met minimaal denkniveau, maximaal 2.000 uitvoer-/denktokens per aanvraag; geen betaalde zoektools. De eerste oudere-modelproeven gaven HTTP 404 en zijn als mislukt bewaard.

De eigenaar bevestigde op 16 november 2026 dat het Google AI Studio-project Free tier gebruikt zonder betaalde facturatie. De API-sleutel staat als projectsecret `GEMINI_API_KEY` in Supabase; de managementcontrole accepteerde de sleutel zonder generatieaanvraag. De eenmalige verbindingsprivésleutel is verwijderd. Er wordt geen facturatie geactiveerd. Deze projectstatus is een eigenaarsverklaring en niet door de API-sleutel onafhankelijk aantoonbaar. Als de eigenaar later facturatie koppelt, moet de verwerking eerst worden uitgezet en opnieuw beoordeeld: een applicatielimiet is geen providerfactuurplafond.

## Keten zonder Codex-werksessie

De geplande Supabase Edge Function `paper-gemini-research` claimt atomair één vervallen dossier. Eerst naderende bevestigde kwartaalcijfers en de eerste zeven dagen erna, daarna nog niet gestarte dossiers met de bestaande risicoprioriteit. Eén ronde is maximaal drie officiële HTML-bronnen, geselecteerde passages tot 7.000 tekens per bron en twee aanvragen aan het vastgezette model `gemini-3.5-flash-lite`. Alleen openbare broninhoud, publieke consensuscontext en publicatiedata gaan naar Google; geen portefeuille, eigenaargegevens of toegangssleutels in de prompt.

1. Vernieuw waar mogelijk de officiële SEC-index en haal de concrete publicaties op; voor andere bedrijven gebruik geregistreerde officiële HTML-bronnen.
2. Maak een Nederlandstalig concept met letterlijke broncitaten, onzekerheden en tegenargumenten.
3. Controleer elk citaat exact tegen de aangeleverde tekst. Niet passende citaten stoppen de beoordeling.
4. Laat een tweede modelaanvraag alle claims kritisch controleren op feiten, periode, eenheden en vergelijkbare winst-/omzetdefinities. Bewaar alleen ondersteunde claims, minimaal drie.
5. Bewaar resultaat, echte modelversie, tokengebruik, bronhashes, geselecteerde brontekst en volgende controledatum. De eigenaar ziet het concept onder Aandelen. Een mislukt nieuw resultaat wist het vorige concept niet, maar toont het als niet actueel.

Deze modelcontrole is geen onafhankelijke feitencontrole en bewijst geen volledige lezing, financiële juistheid of winstgevendheid. Het model kan fouten missen. De oorspronkelijke vijf-pijlergoedkeuring en onwijzigbare voorspellingen blijven afzonderlijk. Geen aankoop/verkoop, wijziging van stops of brokeractie via deze worker.

## Grenzen en opvolging

- Cron dagelijks 07:45/07:50 en 15:45/15:50 UTC; in Belgische wintertijd 08:45/08:50 en 16:45/16:50. Analyse en controle zijn afzonderlijke serverstappen met private tussenopslag en maximaal 90 seconden modelwachttijd per stap. De tweede stap gebruikt de vooraf gereserveerde aanvraag.
- Reguliere planning twee dossiers/vier gereserveerde modelaanvragen per dag, 120 per maand. Alleen de eenmalige installatiedag heeft een apart plafond van zestien aanvragen voor de beheerde ingebruikname; daarna automatisch vier. Dit is geen dynamisch plafond of automatische verhoging bij uitval. Elke begonnen of onzekere modelaanvraag blijft meetellen. Alleen aantoonbaar niet begonnen vervolgslots worden vrijgegeven; geen automatische herpoging van dezelfde aanvraag. Het grotere Flash-model overschreed de servertijd bij ingebruikname; het vastgezette gratis Flash-Lite-model wordt daarom gebruikt.
- Geen betaald reservemodel of andere API bij een 429; uitstel tot een latere ronde. De gratis Google-quota kunnen lager zijn en veranderen.
- Normaal elke veertien dagen inhoudelijke herbeoordeling; tussen 21 dagen vóór en zeven dagen na bevestigde cijfers dagelijks. Daglimieten kunnen achterstand geven. Onbekende publicatiedata worden niet verzonnen. Honderd geregistreerde dossiers betekenen niet honderd afgeronde analyses.
- Hoogstens 1 MB per bron, 400 kB SEC-index, 100 kB per modelantwoord; vijf MB overdrachtsreserve per dossier, 200 MB per maand binnen de bestaande applicatiegrens. Databasegrens 100 MB, vier geschiedenisversies per bedrijf.
- PDF's en spreadsheets worden in deze HTML-ronde niet automatisch geïnterpreteerd. Ontbrekende financiële tekst, onbereikbare bronnen en ontbrekende hoofdstukken blijven expliciet zichtbaar; dit is geen downloadlimietomzeiling.

Migratie `037_gemini_research.sql` start uitgeschakeld. Activering vereist managementtoegang, eigenaar-ID en expliciete bevestiging van het onbetaalde Google-project. De cronroute is afgeschermd met het bestaande project-crongeheim; alle tabellen zijn privé en alle leesroutes vereisen eigenaarcontrole via de bestaande website/MFA-route.

Controles: `node --test managed/tests/gemini-research.test.mjs`, `python managed/tests/test_gemini_database.py` en de bestaande frontend-/websitecontroles. De aparte OpenAI-adapter blijft uitgeschakeld met budget nul.

Installatie/herstel: `python scripts/gemini_research.py kdyzlbknygeqinqduuic`. Alleen bij expliciete bevestiging van het gratis project kan `--confirm-free-tier` worden gebruikt; bestaande activering wordt bij herstel behouden. Direct pauzeren via management-SQL: `update paperlab.gemini_runtime set enabled=false where singleton;`.
