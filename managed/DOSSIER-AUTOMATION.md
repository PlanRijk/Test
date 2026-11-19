# Automatische bedrijfsdossiers afronden

Migratie 042 en de bijgewerkte `paper-deep-research`-worker gebruiken de bestaande minuutcron en het bevestigde gratis Google-project. Een actieve Codex-werksessie is niet nodig om de verwerkingsketen uit te voeren.

## Voorrang aan afronden

De planner houdt twee dossiers met beschikbare jaar- en tussentijdse verslagen vooraan. Bij gelijke brondekking krijgen dossiers die bijna klaar zijn voorrang, gevolgd door de bestaande onderzoeksprioriteit. Afgeronde leesblokken blijven bewaard. Na bronlezing worden automatisch zes pijlers ingepland: financiële positie, winst/kasstroom, concurrentie, management/kapitaalallocatie, waardering en risico's. Daarna volgt een afzonderlijke controle door het zwaardere model.

De peergroepen voor onder meer Nvidia, Walmart, Linde en Novo Nordisk zijn expliciet gekozen met beperkingen voor segmentmix en valuta. Dit is een onderzoekshypothese, geen bewijs dat geconsolideerde cijfers economisch vergelijkbaar zijn. Waar geen gekozen groep bestaat, blijft de catalogussector slechts een suggestie. Ontbrekende peerdata wordt niet verzonnen.

## Bewijs en begrenzing

De code verdeelt ieder leesblok in exacte bronpassages. Het model selecteert passage-ID's; de code haalt het oorspronkelijke citaat op. Financiële tabellen, witruimte en leestekens worden dus niet door het model herschreven om aan de citaatcontrole te voldoen. Bevindingen blijven modelinterpretaties en kunnen ondanks een correct citaat onjuist zijn.

Iedere pijler mag alleen bestaande bewijs-ID's gebruiken. Secundaire cijfers en scenario's zijn afzonderlijk herkenbaar. De eindcontrole krijgt alle gebruikte primaire citaten (maximaal zes per pijler) en de volledige zes beoordelingen mee. De broncontext is begrensd; waar de benodigde onderbouwing ontbreekt, moet dit een datagat blijven. De originele volledige opgeslagen teksten blijven beschikbaar.

Een **afgerond dossier** kan ontbrekende informatie bevatten. `full_ai_dossier` wordt alleen waar bij volledige geladen jaar-/tussenverslagen, afgeronde bronlezing, zes onderbouwde pijlers zonder aangegeven kritieke datagaten en zes ondersteunde eindcontroles. `full_company_analysis`, `independently_verified` en `trade_approval` blijven onwaar: dit is geen onafhankelijke accountants-/beleggingsaudit en geen automatische handelsgoedkeuring. Normale toekomstige onzekerheid blijft daarnaast bestaan.

## Automatisch herstel

- Tijdelijke provideruitval telt niet mee als inhoudelijke validatiefout. Dat waren eerder ten onrechte dezelfde pogingen.
- Bij tijdelijke HTTP 5xx-uitval geldt oplopend 30 seconden, 1, 2, 4, 8 en maximaal 15 minuten wachttijd. Een langere Retry-After wordt gerespecteerd. Na herstel begint de reeks opnieuw. Google-dagquota en HTTP 429 volgen hun afzonderlijke quota/resetregels.
- Ongeldige antwoorden krijgen gerichte herpogingen na circa 1 en 2 minuten. Na drie echte validatiefouten wordt een leesblok in twee kleinere stukken gesplitst. Maximaal twee splitsingsniveaus bewaren de oorspronkelijke tekstvolgorde en exacte bronposities.
- Een vastgelopen pijler of eindcontrole krijgt maximaal twee compactere herstelrondes. Bewijsregels worden niet versoepeld om een dossier af te vinken.
- Daarna zijn maximaal twee dagelijkse herstelcycli mogelijk. Onoplosbare gevallen blijven zichtbaar als bewijsprobleem. De andere dossiers kunnen verdergaan.
- Verlopen leases worden opnieuw ingepland; verouderde taken uit een eerdere bronversie worden niet als actuele beoordeling opgeslagen.

Er blijven maximaal 500 lichte en 20 zware aanvragen per Pacific-dag beschikbaar. Twee zware aanvragen blijven gereserveerd voor eindcontroles wanneer vrije zware capaciteit bronlezing overneemt. Iedere werkelijke poging wordt vooraf gereserveerd. Er is geen betaald alternatief en geen reset van reeds gebruikt quotum.

## Bijwerken en zichtbare opvolging

Nieuwe bronversies en gewijzigde financiële/consensusinvoer starten automatisch een nieuwe beoordeling. Ongewijzigde gelezen teksten worden hergebruikt. Rond officieel bekende cijferpublicaties zoekt de planner vanaf twintig minuten na de publicatietijd maximaal eenmaal per uur naar een nieuw tussentijds verslag, gedurende twee dagen. De reguliere broncontrole blijft daarbuiten dagelijks rond kwartaalcijfers en wekelijks daarbuiten werken.

Dossiers met bewijsgebreken plannen een nieuwe broncontrole in. Alleen nieuwe invoer activeert opnieuw dezelfde beoordelingen; dezelfde onvoldoende gegevens worden niet eindeloos als nieuw onderzoek herhaald.

In Paperlab staan het huidige tweetal dossiers, gelezen blokken, afgeronde pijlers, verouderde rapportversies en blijvende aandachtspunten. Er zijn waarschuwingen voor ontbrekende verslagen, geblokkeerde verwerking, te grote context, opslag/verkeer en meer dan 24 uur stilstand bij een actief dossier. Dit zijn **meldingen in de app**, geen e-mail- of chatberichten. Ze maken een storing zichtbaar, maar garanderen niet dat ontbrekende externe bronnen automatisch beschikbaar worden.

Bij het bedrijfsdetail zijn de gebruikte primaire broncitaten, periodes, cijferbasis en links terug te lezen. Er blijven vier afgeronde dossierversies per bedrijf in de onderzoekshistoriek bewaard. De bestaande herstel- en opslaggrenzen blijven gelden. De planner vermijdt het voortdurend herschrijven van ongewijzigde taken en waarschuwingen.

## Installatie en controles

`python scripts/dossier_automation.py kdyzlbknygeqinqduuic` installeert 042 en publiceert de worker. De bestaande cron, financiële profielen, posities, bevroren kwartaalvoorspellingen en gebruikstellers worden niet gereset. De bekende herinstallatiescripts passen 042 na oudere bronmigraties opnieuw toe.

Regressies controleren het volledige pad van bron naar zes pijlers en audit, ontbrekende versus complete brondekking, afzonderlijke foutentellers, tekstbehoud bij splitsing, quote- en bewijs-ID-controle, quota, begrensde herstelpogingen, herinstallatie zonder gebruiksreset, geen onnodige rijupdates en eigenaarisolatie. Nieuwe modeluitkomsten worden niet als historische onafhankelijke handelsprestaties geteld.
