# Betrouwbaarheid en reproduceerbaarheid

Beleid `reliability-v1`, 4 november 2026. Dit stelt strengere voorwaarden aan
bewijs; het belooft geen betrouwbaarheidspercentage of winst. Hoofdhandel blijft
paperhandel met de bestaande saldo-, kosten-, sector- en verliesgrenzen.

## Drie bewaarniveaus

Uitgebreide onderzoeksdossiers: maximaal 5.000 afgeronde en 200 lopende dossiers,
met maximaal 90 dagen detail. Daaronder blijft een compact archief van maximaal
50.000 waarnemingen en maximaal 730 dagen beschikbaar. Bij bijna volle opslag
worden oudste vrijgegeven clusters op tijdsvolgorde opgeruimd; uitkomsten bepalen
de selectie niet. Afgeschermde toetsgegevens en lopende observaties worden beschermd.
Nieuwe observaties kunnen pauzeren terwijl bestaande observaties worden afgemaakt.

Het archief bewaart profiel, bedrijf, beurs, datum, motivatie, kenmerken, zes
oorspronkelijke koersmetingen, instap en vaste uitkomsten. Kosten-/belastingprofielen
worden één keer per fingerprint opgeslagen. Een checksum bewaakt het originele
besluit; een bestaande instap of uitkomst kan niet stilzwijgend wijzigen.
Codec 1 gebruikt getypeerde arrays:

- kenmerken: dezelfde zeven `decision-net-v1` kenmerken;
- koersmetingen: zes drietallen `[meetmoment_ms, prijs, bronmoment_ms]`;
- instap: `[tijd_ms, bron_ms, EURprijs, lokale_prijs, FX, aantal, budget, bruto_EUR, commissie, belastingen]`;
- uitkomst: `[1, tijd_ms, bron_ms, netto_EUR, bruto_beweging_pct, werkelijke_minuten, lokale_prijs, FX, bruto_EUR, commissie, belastingen]`; `[2]` betekent ontbrekend en `null` nog niet gemeten.

Een geïsoleerde test met 50.000 representatieve waarnemingen gebruikte ongeveer
71 MB inclusief indexen. Dit is een meetvoorbeeld, geen gegarandeerd maximum
voor ieder dossier. Archiefadmissie begrenst tevens de omvang; de bestaande
vroege studiegrenzen van 200 MB database en 2 GB geraamd verkeer blijven gelden.
De kernproef behoudt haar eigen 300 MB/3 GB-grenzen. Opruimen maakt pagina's
herbruikbaar; fysieke grootte hoeft niet direct te dalen.

## Afgeschermde kalenderperiodes

Per onderzoeksprofiel begint een vooraf vastgelegde periode na de installatiedag:
60 kalenderdagen ontwikkeling, daarna 60 kalenderdagen toetsing. De primaire
uitkomst is 120 minuten; 30 minuten blijft aanvullend. De toetsuitkomsten zijn
verborgen in normale dossiers, gemiddelden en compacte/volledige exports tot
de einddatum en een eenmalige beoordeling. Eerder bekeken pilotgegevens worden
geen nieuwe toetsdata. Openbare marktprijzen kunnen uiteraard buiten de app bekend zijn.

De beoordeling groepeert bedrijven per dag en gebruikt blokken van vijf en tien
dagen. Zij rapporteert ontbrekende paren, dekking, sectoren, beurzen, stijgende/
dalende dagen, hogere kosten en afhankelijkheid van een enkele dag of week.
Voor ontbrekende paren wordt ook een vooraf gekozen EUR100-nadeelscenario getoetst;
dit is geen wiskundig worstcasescenario. Timing/selection blijven observationeel,
dus een positief rapport geeft geen automatische handelsgoedkeuring.

## Strengere modeltoelating

Training: minimaal 300 echte afgesloten referentietrades, 60 datums, tien bedrijven
en vijf sectoren. Whole-date training/validatie/test en embargo blijven gelden.
Er zijn minimumaantallen per klasse, toetsvak en beurs. Exacte trainingsinvoer
wordt bij de lease bevroren en aan het model gekoppeld; het oorspronkelijke
optimisme-/overfitrisico wordt daardoor niet door gewijzigde latere input verborgen.
Maximaal twaalf datasets, samen maximaal 24 MB ongecomprimeerd, met bewaartermijn
van maximaal twee jaar; onvoldoende ruimte verhindert een nieuwe training.

Daarna volgt een vaste beoordeling van de eerste 60 nieuwe volledige gepaarde
handelsdagen, minimaal 120 afsluitingen, 40 werkelijk belegde gepaarde dagen,
tien bedrijven, vijf sectoren en voldoende bron-/kalenderdekking. Dubbele
handmatige rondes verhogen de blootstellingsweging niet. Modelblootstelling
boven 1,25 maal de referentie, ontbrekende stresskosten of uitschieters blokkeren toelating.

Dagblokken van vijf en tien dagen, 4.000 herhalingen en een correctie voor maximaal
drie modelproeven moeten positief blijven bij hogere kosten. Ook de recente helft
en het resultaat zonder de beste week moeten positief zijn. De beoordeling wordt
één keer vastgelegd; een mislukte toets krijgt geen dagelijks nieuwe kans.

De modellevensduur is maximaal 180 dagen zodat deze langere toets mogelijk is.
Promotie vereist een recente beoordeling, verse vervolgdata, een lege hoofdproef
en de bevroren dataset. Recente onderprestatie, gewijzigde invoer of ouderdom
kan terugschakeling veroorzaken. Geen bestaand risicobudget wordt verhoogd.

De nachtelijke `paper-audit`-taak draait op werkdagen om 23:00 UTC (in deze winter
00:00 Brussel op de volgende kalenderdag), met onafhankelijke lease, budget en
foutstatus. Alleen de eigenaar met AAL2 kan de rapporten en exports bekijken.

## Belgische fiscale context

De op 4 november aangeleverde tekst is vergeleken met Bolero's pagina's
[meerwaardebelasting](https://www.bolero.be/nl/lp/meerwaardebelasting) en
[bronheffing/opt-out](https://www.bolero.be/nl/lp/meerwaardebelasting/bronheffing-en-opt-out).
Bruto EUR-meerwaarden, FIFO en het verschil tussen bronheffing en jaarlijkse
afrekening zijn daarin bevestigd. De geprobeerde FOD-detail-URL gaf 404; die is
niet als geraadpleegde wettelijke bevestiging gebruikt. De aangeleverde specifieke
wetsdatum is niet zelfstandig bevestigd.

Het nieuwe jaaroverzicht houdt gewone 10%-scenario's met gedeelde vrijstelling
en verliezen apart van bestaande proefreserves. Voor 2026 worden zowel volledig
beschikbare basisvrijstelling als elders gebruikte vrijstelling getoond. Er wordt
geen persoonlijke beschikbaarheid, brokerinhouding, indexatie of overdracht verzonnen.
Bij ontbrekende valuta/FIFO/basis of posities vóór 2026 is de berekening onvolledig.
Kosten verlagen het economisch rendement maar niet de getoonde bruto fiscale basis.
Andere regimes, waaronder speculatief beheer, zijn niet automatisch vastgesteld.
De bestaande kasboekreserves worden niet achteraf gewijzigd of vrijgegeven.
