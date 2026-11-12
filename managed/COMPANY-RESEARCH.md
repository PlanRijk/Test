# Financieel brononderzoek voor alle honderd bedrijven — 12 november 2026

De eerste ronde onderzocht alle honderd bestaande handelscatalogusbedrijven.
Voor 99 bedrijven is officiële tekst opgehaald: samen 314 pagina's/documenten,
waaronder jaarverslagen, kwartaalrapporten, materiële meldingen, resultaten en
IR-pagina's. Een IR-pagina is geen volledig jaarverslag. Inditex weigerde de
geteste officiële routes met HTTP403. Ook andere bronproblemen blijven zichtbaar.

Ieder bedrijf krijgt een aparte private onderzoekskaart met omzetontwikkeling,
winst tegenover kasstroom, schuld en cash uit dezelfde financiële jaarmomentopname,
verwatering waar vergelijkbare gegevens bestaan, recente kwartaalontwikkeling,
sector-/bedrijfsvragen, bronpassages, documenthashes en ontbrekend bewijs.
Financiële berekeningen gebruiken de bestaande aanvullende bronwaarneming met
oorspronkelijke kennisdatum; dit ververst de cijfers niet kunstmatig. Negentien
specifieke interpretaties zijn aan werkelijk opgehaalde passages gekoppeld, als
het bijbehorende bewijs nog in de collectoruitvoer aanwezig is.

Dit is geen afgeronde kwalitatieve koopbeoordeling van honderd ondernemingen.
De nieuwe kaarten schrijven niet naar company_reviews en geven geen moat-,
risico- of handelsgoedkeuring. Bestaande vijf pijlers, kasboeken, posities,
risicoregels, bevroren modellen en schedulers worden niet gewijzigd.

## Werking en bronlimieten

collect_company_research.py werkt tijdens een beheersessie, niet als een
zelfstandig dagelijks tekstmodel. Er worden geen betaalde APIs of modellen
aangesloten. De bestaande financiële bronmonitor blijft op haar schema actief.
Een nieuwe inhoudelijke ronde vereist een nieuwe werksessie en nieuwe bronnen.

De eigen initiële downloadgrens van 4 MB bleek 42 bronbestanden te blokkeren.
Alle 42 zijn daarna opgehaald met verhoogde, begrensde downloads: doorgaans
24 MB; twee grote PDFs gericht tot 80 MB. De grootste was circa 58 MB.
De standaard collector accepteert --max-document-mb (1–80) en --max-run-mb
(1–800), met defaults 24/400. Dat zijn onderzoeksgrenzen in de cloudwerkruimte,
geen Supabase-providerquota. HTTP403/429 wordt niet omzeild. Na 429 stopt die
host gedurende de ronde. Geen terugval naar andere host om een ratelimit te ontwijken.

PDF-extractie leest maximaal 300 pagina's en noemt het werkelijke bereik.
Air Liquide: 300 van 432 pagina's; dus geen claim van volledige lezing.
Tekstextractie interpreteert tabellen, grafieken en volledige context niet vanzelf.
Geselecteerde passages zijn beperkt, managementuitspraken blijven toegeschreven.

## Opslag, toegang en validatie

SQL027 bewaart alleen de actuele compacte onderzoekskaart per bedrijf (maximaal
24 kB), onder RLS en met beheer als enige schrijver. Owner-RPC via bestaande
eigenaar/MFA/sessiecontrole; overzicht geeft alleen tellingen en detail één bedrijf.
Opslaggrens 4 MB; databasegrens 100 MB; bestaande lagere handmatige transfergrens
blijft gelden. Toelating stopt uiterlijk op 3,2 GB geraamd maandverkeer en boekt
de import op de bestaande toepassingsteller. Grote bronbestanden blijven buiten
Supabase en Git. De teller is geen volledige providerfactuur.

Website: Aandelen → Bronnen & analyse → Uitgebreid financieel onderzoek.
Tests: bestaande Node-suite, gerichte onderzoek-UI/XSS-checks, geïsoleerde
netwerkloze PostgreSQL-test en Chromium-controle op 390/1400 pixels.
