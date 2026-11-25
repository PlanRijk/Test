# Doorlopend kwartaalonderzoek

Migratie 044 en `paper-quarter-cycle` voeren een eigen terugkerende wachtrij uit voor alle honderd gevolgde bedrijven. De bestaande menselijke pilotvoorspellingen blijven ongewijzigd. Deze route beheert onderzoek; hij schrijft geen orders en geeft geen automatische koopgoedkeuring.

## Voor iedere nieuwe kwartaalpublicatie

Officiële kalenderpagina's worden periodiek gecontroleerd, met conditionele HTTP-verzoeken en hergebruik van ongewijzigde inhoud. Datums worden alleen geregistreerd met een letterlijk citaat van de officiële pagina. Volgende kwartalen worden niet door drie maanden optellen verzonnen. Onbevestigde datums blijven zichtbaar. Zonder bereikbare officiële kalender kan voorbereiding op tijd niet worden gegarandeerd.

Een datum zonder tijd krijgt een expliciete onzekerheidsmarge: de voorbereiding en freeze gebruiken de vroegst mogelijke publicatie wereldwijd, de resultatencontrole wacht tot na de laatst mogelijke publicatietijd. De interface toont de officieel genoemde dag en vermeldt dat de tijd onbekend is.

Per geregistreerde cyclus ontstaan automatisch:

- T−7 dagen: brongebonden onderzoek naar verwachte cijfers, consensus, vooruitzichten, waardering, rente-/financieringsrisico en tegenargumenten. Mogelijke uitkomsten: onvoldoende bewijs, negatief, opvolgen of onder voorwaarden interessant.
- T−2 dagen: herbeoordeling met de eerdere beoordeling, nieuwe beschikbare bronnen en actuele indicatieve koerscontext.
- Uiterlijk T−24 uur: de laatste werkelijk tijdig opgeslagen beoordeling en consensus worden als onwijzigbare modelverwachting bewaard. Dit is afzonderlijk van de eigen verwachting uit de oorspronkelijke pilot.
- Na publicatie: extractie van omzet en diluted EPS uit opgeslagen primaire bronteksten. Numerieke waarden vereisen exacte citaten, bijbehorende fiscale kwartaalnaam en jaar, valuta, eenheid en GAAP/IFRS/non-GAAP-basis. Onvoldoende bewijs blijft een bronprobleem met herpogingen.
- Daarna: automatische vergelijking met de tijdig vastgelegde verwachting. Consensus wordt alleen vergeleken met een vóór publicatie opgeslagen, passende periode, valuta en winstdefinitie. Onbekende basis of een volgende kwartaalraming wordt niet als echte verrassing gebruikt.
- Koerscontext na 1/5/20 sessies wordt bijgewerkt waar bruikbare slotkoersen beschikbaar zijn. De bestaande pilot heeft zijn eigen koersfunctie. Andere bedrijven gebruiken indicatieve opgeslagen slotkoersen met expliciete beperkingen voor sessie-uren en bedrijfsacties; dit is geen uitvoeringsrendement of bewezen richting-score.

Een laat bekende kalender of quota-uitval kan betekenen dat T−7 wordt gemist. Het werkelijke verwerkingsmoment en de overschreden termijn blijven zichtbaar; er komen geen achterafvoorspellingen. Een ontbrekend of slechts gedeeltelijk gelezen calltranscript blijft een aparte beperking. Verwerking van cijfers geldt niet automatisch als een afgeronde callbeoordeling.

## Gratis capaciteit en hervatten

De bestaande Gemini Free-tier-bevestiging blijft vereist. Alle modelaanvragen gebruiken dezelfde Lite-tellers als het dossieronderzoek: gezamenlijk maximaal 500 per Pacific-dag, met dezelfde minuut-/tokenlimieten. Het aantal van 500 is geen extra quotum voor deze functie. Ongewijzigde kalenderinhoud wordt zonder nieuwe modelaanvraag hergebruikt. Dag-/minuutquota en provideruitval leiden tot hervatten op een later toegestaan moment.

Kalenderdownloads hebben een aanvullende conservatieve maandbegroting van 60 MB en maximaal 400 kB per verzoek. Werkelijke gemeten bytes verrekenen de reservering; fouten behouden hun conservatieve reservering. De totale bestaande appgrenzen blijven gelden: deze prioritaire kwartaalroute past binnen 3,5 GB en laat 500 MB tot de bestaande harde 4 GB-grens over voor kritieke werking. Er is geen betaald alternatief of nieuw project geactiveerd.

De vijfminutencron claimt maximaal één taak, met een lease, eenmalige commit en afzonderlijke fout-/bronstatus. Er is geen open chat nodig. De planning maakt nieuwe taken voor iedere nieuw bevestigde publicatie. Kalendercontrole is niet hetzelfde als datumbevestiging.

## Grenzen van het oordeel

`conditionally_interesting` is een onderzoeksoordeel in de paperproef. Het bestaande handelssysteem houdt eigen vereisten voor bedrijfspijlers, koerskwaliteit, kosten, risico en timing. De nieuwe functie verandert geen financieel profiel, saldo, positie, order, persoonlijke belastinginstelling of oorspronkelijke voorspelling.

Verwachtingen zijn modelhypothesen, niet automatisch analistenconsensus. Een correct voorspelde omzet of winst bewijst geen voorspelde koersstijging of winstgevende transactie. Er is geen onafhankelijk gevalideerd beleggingsvoordeel aangetoond.

Installatie: `python scripts/quarter_cycle.py kdyzlbknygeqinqduuic`. Deze voert een teruggedraaide migratieproef uit, bewaakt de bestaande financiële profielen en menselijke forecasts en installeert de worker en vijfminutenplanning. Nieuwe tabellen hebben RLS; browser-/anonrollen hebben geen directe toegang. De bestaande eigenaar/MFA-route toont de resultaten.

Tests controleren T−7-planning, quota delen, broncitaatcontrole, fiscale periode, negatieve EPS, eenmalige leases, onveranderlijk vastleggen, post-publicatiecijfers, financiële vergelijking, kalenderhergebruik en eigenaarisolatie. Een synthetische test is geen historische prestatie.
