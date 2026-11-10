# Honderd brongebonden bedrijfsanalyses

Toegevoegd op 10 november 2026. Alle honderd bestaande handelscatalogusbedrijven
hebben een eigen bronkaart. Dat is een onderbouwde eerste analyse en datakwaliteitstoets,
geen claim dat honderd volledige kwalitatieve investeringsanalyses afgerond zijn.
De bestaande vijf-pijlerfilter, instapregels, kasboeken, koers- en risicogrenzen
blijven ongewijzigd. Geen nieuw account, betaalde bron of AI-abonnement.

## Werkelijk bereikt bij de eerste collectie

- 100/100 primaire bronpagina’s bereikbaar en vastgelegd met tijdstip en hash:
  onderneming, SEC of officiële beurs/toezichthouder. Verouderde routes zijn via
  officiële ingangen hersteld; een algemene beursstartpagina is niet als bewijs
  van een specifieke onderneming aanvaard.
- 100/100 aanvullende financiële reeksen opgehaald via de openbare Yahoo
  fundamentals-timeseriesroute, zonder API-sleutel: jaar- en kwartaalgegevens.
- Bij 46 bedrijven konden financiële concepten uit officiële SEC-filings worden
  geëxtraheerd en aan ticker, CIK en de gepubliceerde filing worden gekoppeld.
  Dat is een cijferextractie, geen volledig gelezen jaarverslag of sectorspecifieke
  waarderingsgoedkeuring. Financiële ondernemingen kunnen aparte concepten hebben.
- De 44 extra officiële dossiers zijn als financiële invoer gekoppeld aan de
  actieve analyse. De bestaande Apple-/Microsoft-dossiers, prijsvensters en
  kwalitatieve beoordelingen zijn behouden.
- Twee actuele, expliciete kwalitatieve beoordelingen waren reeds beschikbaar.
  Voor andere bedrijven wordt ontbrekende onderbouwing niet als ‘moat aanwezig’
  of ‘risico akkoord’ ingevuld.
- Een echte bronronde in Supabase werkte: zes nieuwe bevestigde aanvullende
  bronopvragingen, nul bronfouten. De directe SEC-collector blijft afzonderlijk
  gepauzeerd wegens SEC HTTP403; die beperking wordt niet als opgelost voorgesteld.

De ruwe primaire factbestanden besloegen circa 215 MB in de tijdelijke
cloudwerkruimte. Supabase krijgt compacte cijferreeksen, berekeningen, links,
verslagidentiteiten en hashes; niet dit volledige ruwe rapportarchief. De eerste
honderd genormaliseerde bronkaarten zijn samen circa 0,94 MB JSON, met normale
PostgreSQL-compressie en indexen afzonderlijk begrensd.

## Keten en betekenis

1. Vast bronregister per juridische onderneming en notering.
2. Genormaliseerde financiële observaties met periode, valuta, bronhash en het
   werkelijke tijdstip waarop de toepassing ze leerde kennen. De verslagperiode
   is geen publicatiedatum; onbekende publicatiedata blijven onbekend.
3. Bedrijfsspecifieke voorlopige bevindingen voor omzet, winst/kasstroom,
   waardering, concurrentievoordeel en risico. Ontbrekende waarden zijn geen nul.
4. Passend onderzoeksprofiel: operationeel bedrijf, bank, verzekeraar, holding
   of vastgoed. CET1/liquiditeit, solvabiliteit, NAV of FFO/AFFO/LTV worden niet
   vervangen door een blind algemeen kasstroomcriterium. Aandelenklassen, ADR’s,
   valuta, investeringscycli en broninterpretatie kunnen extra bewijs vereisen.
5. Een gemotiveerd oordeel over welk bewijs ontbreekt. De bronkaart verleent
   geen kooptoestemming. De actieve vijf-pijlertoets, betrouwbare uitvoeringskoers,
   instaproute en bestaande financiële veiligheidscontroles blijven doorslaggevend.
6. Bij een veranderde financiële gegevensset wordt een korte revisiegebeurtenis
   bewaard. Een gekoppeld oud koopdossier wordt onbekend gemaakt totdat de gewijzigde
   informatie opnieuw gecontroleerd is. Er volgt geen automatische kwalitatieve
   goedkeuring of modelpromotie.

De API gebruikt de laatste echt waargenomen koers alleen voor indicatieve
verhoudingen; een ontbrekende of meer dan zeven dagen oude koers levert geen
berekende waardering. De uitvoeringscode blijft haar strengere koersgrens gebruiken.
Een publieke filingindex of investorpagina bewijst niet dat iedere volledige
rapporttekst is gelezen. De bronkaarten tonen hun leesscope expliciet.

## Doorlopende gratis monitor

SQL018 en paper-company-coverage vormen een aparte, begrensde bronmonitor.
Vier werkdagmomenten: 06:40, 06:50, 07:40 en 07:50 UTC; in de Belgische wintertijd
07:40, 07:50, 08:40 en 08:50. Elke claim maximaal zes bedrijven, dus maximaal
24 per dag. Oudste observaties krijgen voorrang na drie kalenderdagen. Dit
betekent geen realtime financiële of volledige nieuwsmonitoring.

Maximaal 100 kB bronantwoord per bedrijf; vooraf 1 MB per batch reserveren.
Werkelijke bron- en conservatieve transportbytes worden na commit verrekend.
Ook de eerste import telt mee. Eigen maandbegroting 20 MB; eigen opslag 8 MB;
gedeelde pauze vanaf 100 MB database of 1,0 GB geraamd maandverkeer. Geen betaalde
uitbreiding. Een bewuste pauze blijft behouden bij herhaalde installatie.

Er is één actuele uitgebreide bronkaart per bedrijf en maximaal duizend compacte
revisiegebeurtenissen. De kaarten bewaren meerdere jaar-/kwartaalpunten. Dit is
geen onbeperkt point-in-time archief en geen nieuwe verzameling onafhankelijke
leertrades. De bestaande afgeschermde onderzoeken blijven intact.

## Toegang en interface

Alle tabellen hebben RLS en zijn onbereikbaar voor anon/authenticated. De Edge-API
controleert eigenaar, AAL2 en toepassingssessie. Importeren of voorbereiden van
gecontroleerde financiële invoer is alleen een beheerhandeling; de bronworker
kan geen kwalitatieve beoordeling of trading approval maken.

Onder Aandelen staat bij ieder van de honderd bedrijven **Bronnen & analyse**.
De hoofdtelling is klein; alleen het aangeklikte dossier wordt volledig naar de
browser gestuurd. Dat dossier toont cijfers, berekeningswijze, bronlinks,
brongebonden bevindingen, ontbrekende pijlers en sectorvragen. Een oude import mag
nieuwe observaties niet overschrijven.

Lokale controles: company-coverage.test.mjs, coverage-ui.test.mjs,
test_company_coverage_database.py en de bestaande beveiligings-/browsertests.
Ze toetsen identiteit, datums, ontbrekende kasstroom, verliescijfers, canonieke
revisiehashes, bronnenlimieten, RLS, owner/MFA, budgetreservering/refund, nieuwe
cijfers die oud bewijs blokkeren, nul trades en bronkaarten op laptop/gsm.
