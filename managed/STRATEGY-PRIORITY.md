# Nieuwe prioriteit: samenhang en netto bewijs vóór nieuwe instap

Besluit op 12 november 2026 na opdracht van de eigenaar om de beste benadering
te kiezen. Versie quality-swing-priority-v1. Alleen de actieve capital10k-rekening.

## Uitvoering nu

Nieuwe aankopen en nieuwe wachtende kooporders zijn op databaseniveau geblokkeerd.
Alle bestaande posities, hoeveelheden, cash, stops, winstdoelen, risicopauzes,
transacties en eerdere resultaten blijven behouden. Alleen wachtende kooporders
worden geannuleerd. Een oude in-flight worker kan na de overgang geen koop opslaan.
De bestaande koersroutine en verkoopmotor lopen door. Bestaande verkoopbesluiten
blijven aan hun oorspronkelijke bron-, kosten-, lease- en risicocontroles voldoen.

De eigenaar kan de proef nog pauzeren/hervatten, maar hervatten omzeilt deze
afzonderlijke instapblokkade niet. Er is geen browseractie die deze blokkade
opheft. Een expliciete volgende beheerstap is nodig nadat de voorwaarden zijn getoetst.

## Onderzoeksrichting

1. Verifieer broker, tariefplan en fiscale uitgangspunten. Houd werkelijke
   kosten en een afzonderlijk stressscenario naast elkaar; verlaag reserves
   niet om achteraf een gunstiger proefresultaat te creëren.
2. Beoordeel de bestaande open posities, materiële publicaties, financiering,
   koersdekking en uitvoerbaarheid. Dat krijgt voorrang op uitbreiding van de
   potentiële koopvoorraad.
3. Richt nieuw strategieonderzoek op dagen/weken, met beperkte omzet. Dag-/week-
   informatie moet de instap dragen; het oude 25-minutenmomentum is geen bewezen
   meerdaags voordeel. Positieomvang, kosten, volatiliteits-/theserisico en uitstap
   moeten gezamenlijk een vooraf vastgelegd protocol krijgen.
4. Geef de bestaande bevroren context-kandidaat onderzoeksvoorrang. Deze gebruikt
   marktcontext en volatiliteit en wordt reeds prospectief naast de referenties
   gevolgd. De 20-sessie-uitkomst is de bestaande primaire onderzoekshorizon,
   geen nieuw gedwongen verkoopmoment voor de overgenomen posities.
5. Beoordeel onafhankelijke toekomstige uitkomsten na kosten en stresskosten,
   met blootstelling, terugval, ontbrekende data en passende passieve referentie.
6. Een tekstmodelpilot komt na deze basis. Meer geanalyseerde tekst is geen bewijs
   van alpha. Er is geen betaalde verwerking geactiveerd.

De keuze voor context is een inhoudelijke onderzoeksprioriteit, geen selectie
van de recent best presterende kandidaat. Beide bestaande armen, hun modellen,
datasets, vaste toetsvakken en correcties blijven byte-identiek. Er komt geen
extra opleiding, lagere bewijsdrempel of automatische handelspromotie bij.
Onafhankelijke EUR100-onderzoekscases blijven geen eindige EUR10.000-portefeuille.
Een volgend coherent portefeuilleprotocol moet dat onderscheid zelf toetsen.

## Wat heropening moet onderbouwen

- Werkelijke kosten: ontbreekt totdat broker/tarief/fiscale woonplaats zijn
  aangeleverd en gecontroleerd.
- Uitvoeringskwaliteit: passende recente brongegevens en getoetste uitvoering,
  met marktsessies, spread, valuta, bedrijfsacties en eventuele gaps.
- Een vooraf vastgelegd samenhangend handelsprotocol, inclusief instap,
  positieomvang, verliesbeperking, winst-/tijd-/these-uitstap en gebeurtenisbeleid.
- Voldoende onafhankelijke nettoresultaten. De bestaande eisen voor de vaste
  kandidaattoets worden niet verlaagd. Een geslaagde installatie is geen bewijs.

Er is geen datum beloofd waarop de proef weer gaat kopen. Geen aankopen kan de
juiste uitkomst zijn wanneer kosten of bewijs geen verantwoorde instap toelaten.
De blootstelling van overgenomen posities blijft bestaan; de blokkade maakt
bestaande marktrisico's niet nul en garandeert geen winst of verliesplafond.

## Installatie en herstel

SQL031 voegt een afzonderlijke supervisor toe, rond de bestaande audited claim/
commit en de private projectuitlezing. De originele financiële helpers, audit-
policy, stopafstand en nettowinstformule veranderen niet. De oude baseroutines
zijn niet direct uitvoerbaar door browserrollen of service_role.

Na eventuele herinstallatie van oude schema's moet SQL031 als laatste opnieuw
worden toegepast, zodat het actieve instapbeleid niet door een oude wrapper wordt
vervangen. De project_followup-installer neemt SQL031 daarom mee. Configureren
is idempotent: een herhaling reset geen portefeuille en maakt geen nieuwe baseline.

Controles: geïsoleerde netwerkloze SQL-test voor statebehoud, kooporderannulering,
stale-commitweigering, behoud van verkoopdelegatie, rollen en ownercontrole;
Node-regressies en desktop-/gsm-weergave. Bij productieactivatie wordt binnen
één transactie gecontroleerd dat state buiten pending en bestaande trades gelijk blijven.

Bij herstel van een kopie van vóór deze prioriteitswijziging moeten SQL031 en
strategy_priority.py opnieuw worden uitgevoerd voordat de koersworkers worden
hervat. De oude kopie bevat deze nieuwe supervisorconfiguratie nog niet. Het
herstelproces blijft daarom eerst offline; er is geen automatische herstart.
