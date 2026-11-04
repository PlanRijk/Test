# Dagonderzoek: protocol daily-observations-v1

150 bedrijven (79 Europese, 71 Amerikaanse noteringen) en drie prijsindices.
De oorspronkelijke 100 bedrijven, intradaykansen, trainingslabels, leermodellen,
risicostops en verzegelde toetsvakken veranderen niet. Nieuwe noteringen hebben
geen bevestigde brokerbeschikbaarheid. Er worden geen brokerorders aangemaakt.

Een begrensde bronronde om 06:10 UTC, ook zaterdag om vrijdag te verzamelen.
Yahoo-chartdagbars zijn indicatief. Vandaag in de beurstijdzone wordt volledig
uitgesloten; voor kenmerken zijn minstens 21 afgeronde sessies nodig. Instrument,
valuta (inclusief Britse pence), chronologie en laatste datum worden gevalideerd.
ECB-90-dagenreferenties worden uitsluitend van de prijsdatum of eerder gebruikt,
maximaal vier kalenderdagen oud. Geen hedendaagse FX terugrekenen naar het verleden.
Geen betaalde API, bronabonnement, AI-aanroep of extra Render-service.

Eerste bruikbare bedrijf-weekwaarneming, onafhankelijk van later rendement.
Bekende een-, vijf- en twintigdaagse prijsbewegingen, twintigdaagse volatiliteit,
gedateerde vijfdaagse beweging van S&P 500, EURO STOXX 50 en BEL 20, expliciet
ontbrekende winstkalender. Context is beschrijvend, geen causale crashvoorspelling.
Indices zijn prijsreeksen en geen belegbare nettovergelijking of totaalrendement.

Instap is de eerste latere bronsessie waarvan de bron-opening na het opgeslagen
besluit ligt. Alleen de laatst afgeronde dag mag als geobserveerde instap dienen.
Geen achteraf ingevulde instap na een onderbreking. De 1/5/20 volgende gedateerde
bronsessies leveren de meetmomenten; 20 is primair. Gemiste meetdagen worden als
ontbrekend geregistreerd. Geen interpolatie, fictieve nul of selectie van beste
verkoopdag. Het is een slotkoersonderzoek; uitvoering op een historische slotprijs
is niet bewezen en deze gegevens worden nooit labels van uitgevoerde orders.

EUR100 met bevroren hoofdkosten en voorlopige Belgische 10%-meerwaardereserve,
TOB, buitenlandse koopreserve, eventuele ADR-reserve en 10 bp prijsnadeel per
zijde. ECB-valuta is geen uitvoerbaar brokertarief. Extra stress verdubbelt beide
commissies en voegt nog 10 bp nadeel per zijde toe. Persoonlijke vrijstelling en
afwijkend fiscaal regime zijn niet vastgesteld. Geen werkelijke belastingaangifte.

Splitsingen, dividenden, herziene opgeslagen bronprijzen en sprongen boven 30%
censureren resterende uitkomsten. We corrigeren niet automatisch voor onbekende
corporate actions. Dagbars zijn geen geverifieerde beurskalender: een ontbrekende
bronbar kan ook dataverlies betekenen. Geen gegarandeerde datadekking.

60 kalenderdagen ontwikkeling en 60 kalenderdagen toetsing; toetsbesluiten worden
verborgen in gemiddelden en alle exportpaden tot na een extra 45 kalenderdagen
voor lange uitkomsten. Alleen volledig beëindigde toetsvakken worden descriptief
vrijgegeven. Geen impliciete statistische goedkeuring of modelpromotie. Wekelijkse
bedrijfsobservaties en dezelfde marktschokken zijn afhankelijk; aantallen zijn
geen onafhankelijk bewijs. Kwantitatieve bevestiging vereist een apart vooraf
vastgelegd model en nieuwe validatie.

Maximaal 154 bronaanvragen, 8 MB ontvangen brongegevens, zes parallelle verzoeken,
vier seconden timeout en 48 seconden toelatingstijd per ronde. Eén claim per
UTC-datum, ook na fout; handmatige verzoeken omzeilen dat niet. Herstel probeert
de volgende dag. Bronverkeer en Supabase-egress worden apart beschreven: inkomende
bronbytes zijn geen gemeten facturatie van de provider.

Maximaal 900 actieve en 10.000 bewaarde dossiers, 730 dagen. Bronbars 45 dagen,
kwaliteitsmetingen 365 dagen. Nog verzegelde observaties worden nooit gewist om
ruimte vrij te maken; toelating stopt. Eigen tabellen pauzeren vanaf 48 MB, globale
grenzen 200 MB database / 2 GB geraamd maandelijks workerverkeer. Bestaande globale
veiligheidsmarges en gratis-planwaarschuwingen blijven van kracht. Providergebruik
door andere projecten en Render-facturatie zijn niet volledig meetbaar.

Installatie zonder portefeuille-import: migratie 006, uitsluitend `paper-api` en
`paper-daily` publiceren, `python scripts/deploy_managed.py daily-enable`, daarna
één echte bronronde en anonieme weigering controleren. `daily-enable` is herhaalbaar
bij hetzelfde profiel en maakt geen nieuw toetsvak of nieuw saldo bij herhaling.
Bij verschil in kosten/cataloog vereist het bewust een nieuw onderzoeksprotocol.

Verificatie: `node managed/tests/daily-study.test.mjs`,
`python managed/tests/test_daily_database.py`, de bestaande beveiligingstests en
de browserweergave met synthetische aanmelding. Databasetests gebruiken alleen de
geïsoleerde lokale PostgreSQL-container.
