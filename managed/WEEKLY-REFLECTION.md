# Wekelijkse reflectie

De privépagina **Leerproces → Wekelijkse marktreflectie** toont een controleerbaar,
deterministisch verslag. Geen bewustzijn, LLM-aanroepen, nieuw gelezen boeken of
automatische handels-/modelwijzigingen. De routine draait in Supabase zonder een
geopende website en zonder Render-worker.

Vrijdag **23:15 Europe/Brussels**, na reguliere Europese en Amerikaanse sessies.
Dit betekent niet dat alle wereldbeurzen of 24/7-markten dicht zijn. Cron probeert
vrijdag en zaterdag om 06:15, 21:15 en 22:15 UTC; een lokale tijdcontrole slaat
vroege pogingen over. Zomertijd en Amerikaanse overgangsweken zijn afgedekt.
Een unieke weeksleutel en vergrendeling voorkomen dubbele verslagen. Zaterdag
haalt een gemiste vrijdag in. Na zaterdag wordt geen ontbrekende week gefingeerd.
Een latere uitvoering meet de actuele snapshot, zonder die naar vrijdag terug te
dateren. Activiteit stopt wel op het geplande vrijdagtijdstip.

Het verslag bevat brondekking, actuele gedateerde reviews (geen koopgoedkeuring),
afgesloten voorbeelden, modelstatus, bronwijzigingen, werkelijke papertrades,
kosten, verliesresultaten en mislukte routines. Marktbewegingen komen uit minstens
twee opgeslagen dagsluitingen in dezelfde week, in lokale valuta: geen brede
index, compleet weekrendement of bewijs van een economische oorzaak. De wachtrij
toont maximaal twaalf bedrijven met ontbrekende/verlopen broncontroles of reviews.
Geen bron, goedkeuring of financiële rekening wordt door de reflectie gewijzigd.

Een eerste voorlopige nulmeting levert geen fictieve historische vooruitgang op.
Latere verschillen zijn netto aantallen bewaarde records; retentie, overlap en
correlatie beperken de interpretatie. De eerste vrijdag vergelijkt zo mogelijk
met die voorlopige meting; daarna met de vorige eindreflectie.

Bewaring: 104 eindverslagen + één voorlopige meting, elk maximaal 24 kB.
De privé-API levert de acht nieuwste verslagen. Oudere verslagen blijven binnen
deze bewaartermijn in de database; details daarbuiten worden verwijderd, niet
verliesloos samengevat. Eigen opslaggrens 5 MB, databasegrens 100 MB. Geen externe
bronfetches of betaalde modeloproepen. Installatie bewaart bestaande pauzes.

Een brede cijfercontrole kan maximaal 24 bedrijven per dag verwerken. Voor 100
bedrijven is ongeveer een werkweek nodig, onder voorbehoud van bronnen en quota.
Een volledige vijfpijlerbeoordeling vraagt daarnaast een actuele, brongebonden
interpretatie van concurrentievoordeel, risico's en materiële nieuwe berichten.
Dat kwalitatieve werk wordt nog niet volledig automatisch voltooid; er is dus
geen gegarandeerde doorlooptijd per bedrijf. Vers geladen koersen vervangen die
inhoudelijke beoordeling niet.
