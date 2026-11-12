# Automatische tekstbeoordeling: pilot en kostenraming

Status op 12 november 2026: koppeling voorbereid en met synthetische antwoorden
getest. Geen betaalde API-aanvragen uitgevoerd. Standaard disabled, maandbudget 0.
De gratis publicatiemonitor activeert deze adapter niet.

## Voorstel

1. De dagelijkse wachtrij prioriteert nieuwe publicaties, gewijzigde cijfers,
   verlopen beoordelingen en open posities. Een publicatie-index is geen gelezen rapport.
2. Haal de concrete officiële rapporttekst op; splits grote documenten met
   blijvende documenthash, sectie/paginanummer en oorspronkelijke publicatiedatum.
   Ontbrekende tabellen, OCR of hoofdstukken blijven als hiaten staan.
3. Een model maakt een gestructureerd concept over financiering, kasstroomkwaliteit,
   concurrentie, risico's, materiële gebeurtenissen en tegenargumenten. Alleen
   publieke bedrijfsinformatie gaat naar de API, geen eigenaar- of portefeuilledata.
4. Controleer exacte broncitaten en laat een tweede beoordelingsstap zoeken naar
   ongefundeerde conclusies, tegenstrijdigheden en ontbrekende actualiteit.
   Twee modelpassages zijn geen onafhankelijk feitenbewijs.
5. Bewaar een gedateerd concept met invoerhashes, modelversie en kosten. De
   huidige vijf-pijlergoedkeuring blijft afzonderlijk: het concept kan geen
   orders, risicolimieten, kasboeken of goedkeuringen schrijven.

De adapter in scripts/qualitative_api.py gebruikt de Responses API, store=false
en strikte JSON-uitvoer. Exacte citaten worden tegen de meegeleverde tekst
gecontroleerd. Dit bewijst niet dat de interpretatie juist of volledig is.
Een gedeeld, atomair reserverings-/kostenregister is verplicht vóór een echte
aanvraag. Fouten en onzekere aanvragen houden hun maximale reservering; geen
automatische herpoging die ongemerkt extra kosten maakt.

## Raming, geen factuurplafond

De op 12 november gecontroleerde standaardprijzen voor gpt-6.1-sol zijn
$2 per miljoen invoertokens en $10 per miljoen uitvoertokens. Bron:
https://developers.openai.com/api/docs/pricing

Voorbeeld: 20.000 invoertokens en 2.000 facturabele uitvoertokens per eerste
analyse, plus een controle met 22.000 invoer- en 2.000 uitvoertokens:

| Omvang | Geraamde modelkosten |
| --- | ---: |
| Eerste ronde van 100 bedrijven, één passage | $6,00 |
| Eerste ronde van 100 bedrijven, analyse + controle | $12,40 |
| Daarna 10 gewijzigde dossiers per week, 4 weken | $4,96 |
| Eerste ronde plus die 40 updates | $17,36 |
| Alle 100 wekelijks herhalen, 4 rondes | $49,60 |

Dit zijn expliciete tokenaannames, geen gemeten gebruik of kwaliteitsgarantie.
Eventuele geactiveerde API-credits van een daarvoor in aanmerking komend Pro- of
Business-abonnement zijn niet verrekend; Plus komt volgens de huidige documentatie
niet voor dat voordeel in aanmerking.
https://developers.openai.com/api/docs/guides/chatgpt-api-credits
Langere dossiers, meerdere tekstblokken, redeneringstokens, herpogingen, OCR,
zoektools, regiotoeslagen, btw en valutaomrekening kunnen de kosten verhogen.
De pilot heeft maximaal 4.000 uitvoertokens per aanvraag; de voorbeeldraming
veronderstelt er 2.000 inclusief eventuele facturabele redenering.

## Nog nodig vóór activering

- Een API-key voor een afzonderlijk OpenAI-project, via beveiligde secrets.
- Een expliciet maandbudget in USD en een gevalideerd reserveringsregister.
- Een pilot op circa tien gevarieerde bedrijven, inclusief banken/vastgoed,
  een verlieslatend bedrijf en tegenstrijdige/onvolledige bronnen.
- Controle van werkelijke tokens, citaten, financiële juistheid en uitvalgedrag.
- Een gekozen publicatie-/herbeoordelingsfrequentie en een veilige conceptworkflow.

Het budget staat nu bewust op nul. Alleen een API-key toevoegen zet de analyse
niet aan. De huidige server heeft geen OpenAI-key ontvangen.

Technische bronnen:
https://developers.openai.com/api/reference/resources/responses/methods/create
https://developers.openai.com/api/docs/guides/structured-outputs
