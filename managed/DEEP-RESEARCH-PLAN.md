# Diepgaand onderzoek: benodigde verwerking en haalbaarheid

Dit is het vervolgontwerp. Het beschrijft geen reeds voltooide volledige bedrijfsanalyses. De huidige productie verwerkt geselecteerde HTML-passages en bewaart gecontroleerde concepten. Honderd bronkaarten zijn geen honderd volledige analyses.

Een volledig dossier moet bedrijfsmodel en concurrentievoordeel, winst- en kasstroomkwaliteit, balans en financiering, management en kapitaalallocatie, waardering met expliciete scenarioaannames, en risico's/katalysatoren samen behandelen. Jaarverslag, actuele kwartaalpublicaties, relevante voetnoten en toegankelijk callmateriaal hebben een dekkingsregister nodig. Onbereikbare documenten, niet verwerkte PDF/spreadsheet/audio en ontbrekende consensus blijven zichtbare hiaten. Een model kan ontbrekende bronnen niet vervangen.

## Spreiden

De door de eigenaar getoonde Google Free-tierquota op 16 november 2026 zijn voor Gemini 3.5 Flash-Lite 500 aanvragen/dag, 15/minuut en 250.000 invoertokens/minuut, en voor Gemini 3.8 Flash 20/dag, 5/minuut en 250.000 invoertokens/minuut. Dit zijn projectlimieten, geen gegarandeerde beschikbare capaciteit. De eerdere HTTP 503-fouten waren geen bewijs van uitgeputte dagquota.

Gebruik kleine documenttaken met een inhoudshash en opgeslagen cursor. Bouw eenmalig de jaarverslagbasis op; hergebruik reeds verwerkte ongewijzigde documenten. Verwerk daarna nieuwe kwartalen, gewijzigde vooruitzichten en materiële meldingen. Flash-Lite past bij bronextractie; het zwaardere model is een mogelijke afzonderlijke eindcontrole. Die afzonderlijke diepgaande modelrouting en volledige hoofdstukverwerking zijn nog niet geactiveerd.

Het operationele plafond is na dit screenshot op 100 lichte aanvragen per dag en 3.000 per maand gezet, binnen de gedeelde applicatiegrenzen. Dit plafond maakt de volledige-documentworkflow op zichzelf nog niet actief.

De herhaalbare raming in `knowledge/research-capacity.json` gebruikt de werkelijk opgeslagen tekstlengte en blokken van 7.000 tekens, elk met een modelanalyse en een controle. Alleen de twee opgeslagen NVIDIA-jaar/kwartaalteksten vragen in dat ontwerp circa 154 aanvragen: minimaal 39 dagen bij vier aanvragen/dag, acht bij twintig en twee bij honderd. Dat omvat nog geen waardering, concurrenten, overige bronnen en uitval. Efficiëntere controle per onderwerp kan minder aanvragen vragen, maar moet inhoudelijk worden gevalideerd. Deze raming is geen beloofde doorlooptijd.

## Bestaand hervatten

Migratie 038 bewaart de eerste modelstap wanneer de tweede door een Google-limiet of tijdelijke fout mislukt. De taak wacht op Retry-After/RetryInfo of een voorzichtige pauze en reserveert voor de herpoging alleen de ontbrekende modelaanvraag. Aanvraag- en opslaggrenzen blijven gelden. Dagquota volgen `America/Los_Angeles`, zoals Google voorschrijft; op 16 november is middernacht daar 09:00 in België. De croncontrole loopt elke tien minuten en hervat zodra zowel providerpauze als eigen quota dit toelaten. Ongewijzigde reeds beoordeelde geselecteerde invoer wordt opnieuw bevestigd zonder nieuw modelverbruik. Dit is hervatten van modelstappen; volledige hoofdstukvoortgang hoort nog bij het vervolgontwerp.
