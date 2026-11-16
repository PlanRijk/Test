# Onderzoek op kwaliteit en urgentie

De dagelijkse onderzoeksvolgorde geeft bevestigde kwartaalpublicaties binnen drie dagen en de eerste zeven dagen erna de hoogste extra prioriteit, daarna publicaties binnen 21 dagen. Bestaande posities en gewijzigde officiële publicaties behouden hun eerdere risicoprioriteit. Onbekende publicatiedata worden niet ingevuld met schattingen.

Inhoudelijke beoordelingen staan los van bronkaarten, mechanische ramingen en providerconsensus. Een kwartaalvoorbereiding behandelt vraag, marges en winstdefinities, kasstroom/balans, materiële gebeurtenissen, tegenbewijs en de volgende controle. Een positierisicotriage heeft een beperktere dekking. Beide worden expliciet als **geen volledige bedrijfsanalyse en geen koopgoedkeuring** opgeslagen. Zij vervangen de vijf bedrijfspijlers niet.

Feiten en interpretaties hebben bronverwijzingen, documenthashes en werkelijk waargenomen leestijden. Aangepaste, genormaliseerde en GAAP-winst zijn niet zonder reconciliatie vergelijkbaar. Netto-omzet bij constante valuta is niet hetzelfde als totale omzet in gerapporteerde valuta. Jaar-op-jaar, kwartaal-op-kwartaal en cumulatieve kasstroom houden elk hun eigen periode. Een XLSX-bestand is geen HTML-verslag.

Eigen kwartaalstressscenario's worden prospectief via de bestaande onwijzigbare forecastprocedure opgeslagen. Onthouden (`abstain`) is een geldige conclusie als geen aantoonbaar koersvoordeel bestaat. Scenariobanden zijn geen gekalibreerde kansen. Consensus heeft een afzonderlijke providerwaarneming en krijgt geen label onafhankelijk geverifieerd.

Private beoordelingen worden via de bestaande eigenaar/MFA-route gelezen. De servicetoegang kan met eigenaarcontrole inhoud toevoegen; anonieme en gewone ingelogde rollen hebben geen tabel- of functietoegang. Opslag bewaart maximaal acht inhoudsversies per bedrijf. De applicatieherstelkopie neemt de nieuwe tabel mee; gelezen bronteksten hebben afzonderlijke versleutelde archieven.

Nieuwe controles krijgen een concrete datum, en worden als verlopen getoond zodra die verstreken is. Een bronwijzigingssignaal na de beoordeling maakt een nieuwe controle zichtbaar. De bestaande publicatiemonitor blijft wijzigingen signaleren; een broncontrole voert zelf geen nieuwe tekstbeoordeling uit. Dit voegt geen betaalde modelservice toe. Volledige automatische herinterpretatie van nieuwe teksten is hiermee dus niet gerealiseerd. Handelsregels, bestaande stops, posities en oorspronkelijke experimenten blijven ongewijzigd.

Migratie: `036_scoped_research.sql`. Controle: `python managed/tests/test_scoped_research_database.py` met de bestaande geïsoleerde PostgreSQL-testcontainer, plus frontendtests en de statische sitecontrole.
