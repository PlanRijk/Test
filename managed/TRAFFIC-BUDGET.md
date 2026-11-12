# Dataverkeer en opslag — 12 november 2026

De eigenaar heeft een interne maandgrens van 4 GB gevraagd, binnen Supabase Free.
De officiële prijslijst en gebruiksdocumentatie zijn op 12 november gecontroleerd:
5 GB ongecachet egress, afzonderlijk 5 GB gecachet egress, 500 MB databasegrootte.
De cachequota wordt niet toegevoegd aan het budget voor dynamische database-/API-
gegevens. Quota gelden per organisatie; andere projecten en dashboardgebruik tellen
ook mee. De daadwerkelijke providergebruiks- en facturatiemeter is niet via onze
publieke Management-API bevestigd. Er wordt geen betaald plan of add-on aangezet.

De app-raamwaarde is conservatieve boekhouding van opgehaalde en uitgewisselde
payloads en overhead, geen één-op-één egressmeting. Zij mist onder andere volledig
browser-, Auth-, beheer- en ander organisatieverkeer en gebruikt UTC-kalendermaanden.
De provider kan een andere facturatieperiode hanteren. Daarom blijven buffer en
handmatige controle van het organisatiegebruik nodig. Er is geen providerbreed
factuurplafond of gegarandeerde ononderbroken werking beloofd.

Nieuwe gezamenlijke transfergrenzen (`traffic-budget-v2`):

- Waarschuwing en minder detail in breedteonderzoek vanaf 2,8 GB.
- Extra onderzoek en nieuwe paperinstappen stoppen vanaf 3,2 GB.
- De hoofdkoersroutine en bestaande posities houden ruimte tot maximaal 4 GB,
  onder voorbehoud van alle bestaande opslag-, risico-, bron- en overige grenzen.
- De resterende 1 GB tot de 5 GB-providerquota is buiten deze app-begroting gehouden.
- Elke maand krijgt dezelfde begroting; bestaande tellers worden niet gereset,
  teruggedraaid of als vermeend providergebruik gepresenteerd.

SQL026 wijzigt uitsluitend 30 bekende transfervergelijkingen in 20 bestaande
functies via exact getelde tekstsubstituties. Een onbekende bronversie breekt de
hele transactie af. OID, eigenaar, rechten en functie-instellingen blijven behouden.
De oude en nieuwe functiehash worden apart vastgelegd. Na herinstallatie van oudere
SQL moet SQL026 als laatste worden toegepast; exact de reeds bekende bronversie
mag opnieuw worden omgezet, onbekende bronwijzigingen worden geweigerd. De claim met volledige
float8-precisie blijft intact. Een lagere handmatig ingestelde globale limiet wordt
geresepecteerd. De huidige standaardkap van 3 GB wordt 4 GB, evenals de standaard
voor nieuwe verbruiksmaanden; historische maanden blijven behouden.

Bevroren financiële profielen, implementatievingerafdrukken, datasets, modeltoetsen,
commissies, belastingscenario's, koop-/verkooptriggers, risicobudgetten, posities en
transactiebewijzen worden niet herzien. Ook de eigen maandbudgetten van onderzoeken
(zoals 20 MB voor de bronmonitor), opslaggrenzen, rondegroottes en dagschema's blijven
staan. De oude profiel-JSON bevat dus historische verkeersdrempels; de effectieve
geautoriseerde verkeersgrenzen staan apart in `traffic_budget_runtime` en de private
owner-RPC. De boeken-/notitieroutine wordt niet opnieuw aangezet.

De eigenaar ziet beide meters bij **Instellingen → Gratis gebruik**. Dat paneel
noemt expliciet de app-raming, providerquota, ongetelde organisatiebelasting en de
aparte Render-meter. Alle API-uitlezingen vereisen de bestaande eigenaar-MFA en sessie.

Validatie: geïsoleerde PostgreSQL-test voor doorgang bij 1,13 GB, stop op nieuw
onderzoek bij 3,2 GB, resterende koersruimte boven 3,2 GB, hoofdstop bij 4 GB,
nieuwe-maanddefault, lagere custom kap, idempotentie, ACL/GUC-behoud en onaangeroerde
profielen/tellers. Node-tests toetsen MFA en de verschillende opslag-/verkeerslabels.
De uitrol controleert financiële profielen, eerdere transactiebewijzen en Cron.

Bronnen:
- https://supabase.com/pricing
- https://supabase.com/docs/guides/platform/manage-your-usage/egress
- https://supabase.com/docs/guides/platform/manage-your-usage/database-size
