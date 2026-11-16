# Gratis automatische tekstbeoordeling

De eigenaar bevestigde op 16 november 2026 dat het Google AI Studio-project Free tier gebruikt zonder betaalde facturatie. `GEMINI_API_KEY` staat als Supabase-projectsecret buiten chat en Git. Opslag is met de teruggelezen digest gecontroleerd; Google accepteerde de sleutel en een tekstaanvraag. De verbindingsprivésleutel is verwijderd en de verbindingspagina gesloten.

## Huidige keten zonder Codex-werksessie

`paper-gemini-research` verwerkt officiële HTML-bronnen, maximaal drie geselecteerde teksten van 7.000 tekens. De SEC-index wordt waar mogelijk vernieuwd. PDF's, spreadsheets en audio worden in deze ronde niet geïnterpreteerd. Alleen publieke bedrijfsinformatie gaat naar het vastgezette gratis model `gemini-3.5-flash-lite`; geen portefeuille, eigenaargegevens of sleutels in de prompt. Maximaal 2.000 uitvoer-/denktokens per aanvraag, minimaal denkniveau, geen betaalde zoektools.

1. Een eerste modelstap maakt brongebonden claims, onzekerheden en tegenargumenten.
2. Citaten worden letterlijk tegen de invoer gecontroleerd.
3. De eerste stap blijft privé bewaard. Een afzonderlijke serveraanroep controleert de claims inhoudelijk, inclusief periode, eenheden, winstdefinities en kasstroom.
4. Na minimaal drie ondersteunde claims wordt een gedateerd concept bewaard. De echte modelversie, tokengebruik, bronhashes en gebruikte passages blijven traceerbaar. Een mislukt nieuw resultaat wist de laatste geslaagde beoordeling niet.

NVIDIA voltooide de eerste echte tweestapsproef met vier claims. Bij Walmart slaagde de eerste stap maar gaf de tweede een providerfout; dit werd niet als voltooid geboekt. Deze resultaten zijn beperkte modelconcepten en geen volledige bedrijfsanalyses. Een tweede modelcontrole is geen onafhankelijk feitenbewijs. De vijf bedrijfspijlers, onwijzigbare verwachtingen, portefeuille en handelsregels worden niet door deze worker aangepast.

## Grenzen, bronhergebruik en hervatten

De eigenaar toonde 500 aanvragen/dag voor Flash-Lite en 20/dag voor Flash, met respectievelijk 15 en 5 aanvragen/minuut en beide 250.000 invoertokens/minuut. Op basis van dat screenshot is het operationele plafond voor Flash-Lite op 100 aanvragen/dag en 3.000/maand gezet, met een globale seriële worker. De quota-evidentie en plafonds staan privé in `gemini_runtime`. Een aparte Flash-eindbeoordeling is nog niet geactiveerd. Het eigen plafond blijft lager dan de getoonde providerquota; ook de maand-/overdrachtsgrens kan de uitvoering uitstellen. Een applicatielimiet is geen providerfactuurplafond: als later facturatie wordt gekoppeld, eerst pauzeren en opnieuw beoordelen.

- Iedere tien minuten een controle op vervallen of hervatbare taken; globale lease voorkomt parallelle modelstappen.
- Dagreserveringen volgen de Google-dag `America/Los_Angeles`. Google-dagquota vernieuwen om middernacht daar. RetryInfo en Retry-After worden gevolgd; minuutlimieten, daglimieten en tijdelijke providerfouten hebben verschillende wachttijden.
- Een eerste stap blijft bij een tijdelijke tweede-stapfout behouden. De herpoging reserveert alleen de nog benodigde aanvraag. Begonnen of onzekere aanvragen blijven meetellen; aantoonbaar ongebruikte slots worden vrijgegeven.
- Ongewijzigde reeds beoordeelde geselecteerde invoer vraagt geen nieuwe modelaanvraag. Dit label vernieuwt de broncontrole, niet de datum van de oorspronkelijke modelanalyse.
- Geen betaald reservemodel, sleutelroulatie of limietomzeiling. Bij onvoldoende quota blijft de taak wachten.
- Eén MB per HTML-bron, 400 kB SEC-index, 100 kB modelantwoord; overdracht wordt vooraf geboekt binnen het eigen maandplafond en de bestaande applicatiegrens. Databasegrens 100 MB, vier historische versies per bedrijf, maximaal 2.000 voortgangsgebeurtenissen.

De huidige bronselecties zijn geen volledige jaarverslaglezing. Het vernieuwde hervatten en bronhergebruik zijn operationeel voor modelstappen; een volledige hoofdstuk-/waarderingsketen is nog geen afgeronde functionaliteit. Het verdere ontwerp en een herhaalbare capaciteitsraming staan in [DEEP-RESEARCH-PLAN.md](DEEP-RESEARCH-PLAN.md).

## Beheer

Migraties 037 en 038; `python scripts/gemini_research.py kdyzlbknygeqinqduuic`. Alleen bij expliciete bevestiging van het onbetaalde Google-project dient `--confirm-free-tier` om activering toe te staan; bestaande activering blijft bij herstel behouden. Pauzeren: `update paperlab.gemini_runtime set enabled=false where singleton;` via management-SQL. Tabellen en modelinvoer zijn privé; de bestaande eigenaar/MFA-route toont resultaten. De cronroute vereist het bestaande crongeheim. De OpenAI-adapter blijft uitgeschakeld met budget nul.

Controles: Node-tests `gemini-research.test.mjs`, geïsoleerde SQL-tests `test_gemini_database.py` en `test_gemini_resume_database.py`, plus de bestaande frontend- en statische sitecontroles.
