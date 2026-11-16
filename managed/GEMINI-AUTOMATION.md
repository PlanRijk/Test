# Gemini-automatisering

De operationele worker is sinds migratie 039 **paper-deep-research**, iedere minuut aangeroepen via Supabase-cron. Het bevestigde gratis project gebruikt maximaal **500 Gemini 3.5 Flash-Lite- en 20 Gemini 3.8 Flash-aanvragen per Pacific-dag**, met onafhankelijke limieten, duurzame taakvoortgang en automatische hervatting na limieten of tijdelijke uitval. Geen betaald alternatief.

Volledige beschikbare bronteksten worden gehasht, in blokken gelezen, tot zes bedrijfspijlers verwerkt en door het zwaardere model gecontroleerd. Ontbrekende bronnen of onvoldoende bewijs blijven als gaten zichtbaar. Modelonderzoek verleent geen handelsgoedkeuring.

Zie [de volledige werking, quota, PDF-verwerking en herstelgrenzen](DEEP-RESEARCH-PLAN.md).

De eerdere `paper-gemini-research`-worker (migraties 037/038) las geselecteerde HTML-passages. De cron en runtime daarvan staan uit om dubbele quotaconsumptie te voorkomen. Eerdere concepten en gedeeltelijke resultaten blijven opgeslagen; de pagina toont deze als historische fragmentbeoordelingen. De oude installer alleen gebruiken voor een expliciete terugrol, anders activeert die opnieuw de oude verwerking.
