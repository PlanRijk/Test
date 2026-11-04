# Gecontroleerd leren en aankoopdossiers

Geïnstalleerd op 4 november 2026. Uitsluitend paperhandel; geen brokerverbinding,
betaalde AI of zelfstandig herschrijven van code. De proef eindigt op 6 december
2026 om 21:00 UTC / 22:00 Brussel. Deze einddatum wordt niet automatisch verlengd.

## Wat er wordt geleerd

Elke marktmeting voedt dezelfde hoofdproef en afzonderlijke proefportefeuilles:
de vaste referentie en een variant met minder omzet. Na een geslaagde opleiding
komt daar een portefeuille met het geleerde koopfilter bij. Zij delen bronkoersen
maar hebben eigen kasboeken; hun geld of rendement telt niet mee in de hoofdproef.
De start kopieert de bestaande portefeuille, zonder verkopen of een kasreset.

Alleen afgesloten referentietransacties met bij aankoop vastgelegde kenmerken
worden opleidingsvoorbeelden. Overgenomen posities zonder deze gegevens tellen
niet mee. Er worden geen winstlabels verzonnen of achteraf kenmerken ingevuld.
De eerste versie gebruikt alleen posities die op dezelfde UTC-dag sluiten.
Het label is positieve of niet-positieve nettowinst volgens het kostenmodel.

Een vaste logistische regressie gebruikt zeven kenmerken: laatste en vijfpunts-
rendement, vijfpuntsvolatiliteit, signaal, geschatte kosten, bronleeftijd en
resterende sessietijd. Normalisatie wordt alleen op opleidingsdata aangepast.
Dit is een beperkte statistische schatter; nieuwstitels en macroreeksen worden
niet automatisch vertaald naar koopadviezen of fundamentele bedrijfswaarderingen.

## Toetsen voordat een filter mag meedoen

- Minstens 100 afgesloten voorbeelden, 20 datums, voldoende winnaars/verliezers
  en dekking per gebruikte beurs. Hele dagen worden chronologisch verdeeld in
  opleiding, validatie en test, met een dag tussenruimte aan beide grenzen.
- De kandidaat moet onafhankelijke kans- en resultaatcontroles doorstaan.
  Het koopfilter vereist vervolgens een geschatte winstkans van minimaal 60%.
  Maximaal drie modellen per negentig dagen; een volgende opleiding vereist
  twintig nieuwe datums. Mislukte modellen blijven zichtbaar.
- Daarna minstens twintig nieuwe volledige werkdagen in de afzonderlijke
  modelportefeuille en dertig gesloten posities. Dagen moeten voldoende verspreide
  vijfminutenmetingen en een afsluiting zonder posities hebben; dubbele handmatige
  aanroepen kunnen dit aantal niet verhogen.
- Vergelijking op dagelijkse nettoresultaten met de referentie, een benaderende
  blootstellingscorrectie, een positieve eenzijdige 99%-bootstrapondergrens en
  hoogstens EUR5 extra terugval. Dit zijn conservatieve proefcriteria, geen
  bewijs van causaliteit, een gelijkwaardige ETF-benchmark of gegarandeerde winst.

Pas na alle voorwaarden kan het model automatisch binnen de paperproef worden
geactiveerd. Dit staat standaard aan; de eigenaar kan het met 2FA uitschakelen
of terugschakelen. De hoofdportefeuille moet bij omschakeling vrij van posities
zijn. Model en uitvoeringscode worden met hashes gecontroleerd. Veroudering,
afwijkende invoer, bronwijziging of ongunstige vervolgresultaten kunnen het filter
weer uitschakelen. Bestaande beschermende verkoopregels blijven gelden.

Het model mag risicolimieten, kostenregels, bronleeftijd en beschermende exits
niet versoepelen. Een lagere voorspelkans verhindert aankopen; zij verhindert
geen noodzakelijke beschermende verkoop. Opleiding start niet zolang er te
weinig gegevens zijn. Risicopauzes kunnen die opbouw stoppen. De benodigde
opleidingsperiode plus twintig nieuwe toetsdagen kan langer duren dan deze proef.

## Iedere nieuwe aankoop krijgt een dossier

Bij het besluit worden de concrete motivatie, zes toen bekende koersmetingen,
signaal, kandidatenrangschikking, bedrijf/sector, kostenraming, risicocontroles en
eventuele modelversie en kans opgeslagen. Bij uitvoering komen de latere verse
bronkoers, werkelijke geboekte proefkosten en uitvoeringscontroles erbij.
Een verkoop verwijst naar dezelfde aankoop en maakt analyse van het nettoresultaat
mogelijk. Het oorspronkelijke aankoopargument wordt niet achteraf herschreven.

De website biedt **Leren & aankoopanalyse**, afzonderlijke aankoopbewijzen,
CSV-export en PNG-transactiebewijzen. Zowel hoofd- als afzonderlijke proefkaarten
zijn herkenbaar. Oude transacties behouden hun beperkte oorspronkelijke informatie;
de huidige verplichting reconstrueert geen ontbrekende historische motivering.

## Werking, toegang en budget

De koersroutine loopt op werkdagen elke vijf minuten tussen 07:00 en 20:55 UTC.
Leercontroles lopen om 06:45 en 22:45 UTC, tijdens deze proef 07:45 en 23:45 Brussel.
Dit staat los van een open browser of deze chatsessie. Alleen de eigenaar met
geverifieerde 2FA mag de gegevens en bediening via de beveiligde API bereiken.
Opleidingsgegevens en modellen zijn geen publieke databasetabellen.

De varianten hergebruiken dezelfde marktdata. Vroege leerpauzes bij 250 MB database
of 2,4 GB geraamd workerverkeer beschermen het resterende proefbudget; de bestaande
hoofdgrenzen blijven gelden. Zie [FREE-PLAN.md](FREE-PLAN.md) voor providerquota en
de nog handmatig te controleren Render-betaalinstellingen.

Er is pas een lerend model zodra echte voorbeelden een opleiding mogelijk maken.
Een geïnstalleerde routine met status `waiting_data` betekent dat de gegevensopbouw
werkt, niet dat al een winstgevend model beschikbaar is.
