# Periodieke optimalisatiecontrole

De bestaande `paper-research`-routine voert een regelgestuurde diagnose uit met reeds opgeslagen gegevens: kostendrempels per beurs, afgeronde versus ontbrekende leeruitkomsten, bevestigde verwerkingstijden, ontbrekende bronverbindingen en de gratis gebruiksmarge. Geen extra koersdownloads, worker of cron nodig. Geen modelhertraining, gewijzigde handelsregels of automatische promotie.

Planning: werkdagen 06:30/22:30 UTC. België: in de winter 07:30/23:30; in de zomer 08:30/00:30 (tweede controle op de volgende kalenderdag). Dit is geen doorlopend autonoom programmeerproces. Resultaten staan onder **Onderzoek & regels → Optimalisaties & voortgang**, achter eigenaar/MFA/sessiecontrole (`GET ?optimizations`).

Kostenscan: per beurs de mediaan over bedrijven met recente gedateerde prijs- en FX-invoer. Hypothetische tickets van €100, €250, €500 en €1.000; dezelfde vaste dagelijkse kostenformules, indicatieve spread, commissie, TOB, buitenlandse aankoopreserve, ADR-reserve en voorlopige meerwaardereserve. FX blijft gelijk tussen instap en uitstap. De normalisatie herschaalt alleen vaste minima en geldcaps en is onafhankelijk getest tegen directe kasstromen op de werkelijke ordergrootte. Het is geen geverifieerd brokertarief of zelfstandig advies om grotere orders te nemen. Grotere tickets kunnen buiten het bestaande rekening- en risicobudget vallen.

Nul afgeronde nieuwe twintig-sessiewaarnemingen betekent **niet meetbaar**, niet nul modelnauwkeurigheid. De oorspronkelijke bevestigingsproef en brede verkenning blijven afzonderlijk. Afhankelijke korte waarnemingen worden als waarnemingen beschreven, niet als onafhankelijke trades of portefeuillewinst.

`009_optimization_review.sql` voegt private service-RPC's toe. Invoer lezen wijzigt geen proefgegevens. Onderhoud verwijdert per uitvoering maximaal 5.000 **afgeronde** cronlogs ouder dan zeven dagen, alleen voor de negen bekende PaperLab-taken. Recente, lopende en andere taken blijven behouden. Zodra een historisch model bestaat, wordt alleen de lege `paperlab-history-bootstrap`-taak uitgeschakeld; `paperlab-history` blijft nieuwe voorspellingen en uitkomsten volgen. Aankoopbewijzen en onderzoeksuitkomsten vallen buiten deze opruiming.

Het rapport gebruikt de bestaande onderzoeksopslag: maximaal 128 kB per rapport, veertien dagen/maximaal veertig rapporten. De bestaande onderzoekslease reserveert al een begrensd gegevensbudget. Databasegrootte en app-verkeersraming zijn geen factuurcontrole en bevatten geen Render-verkeer. Bestaande budgetstops blijven van kracht. Een mislukte diagnose of onderhoudsactie wordt expliciet als niet beschikbaar opgeslagen, zonder fictief resultaat.

Validatie: `npm test --prefix managed`, `python managed/tests/test_optimization_database.py` (alleen lokale tijdelijke database), browsercontrole met synthetische MFA-sessie en echte openbare sitebestanden. De bevroren historische modelcode en brede beleidsfingerprint worden niet gewijzigd.
