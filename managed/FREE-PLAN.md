# Gratis proef: verbruik en grenzen

Bijgewerkt op 4 november 2026. Op aanvullend verzoek loopt de paperproef
**door zonder vaste einddatum**, zolang risico- en gratis verbruiksbudgetten dit toelaten.
Er is geen betaald plan, betaalde server, disk, domein, SMS of AI-model geactiveerd.

## Actuele inbegrepen quota

| Dienst | Inbegrepen in het gebruikte gratis plan |
| --- | --- |
| Render Hobby Static Site | 5 GB uitgaand verkeer per maand; 500 standaard buildminuten |
| Supabase Free | 500 MB database; 5 GB ongecachet en 5 GB gecachet dataverkeer; 500.000 Edge-aanroepen per maand |
| Supabase Auth | Basis-TOTP inbegrepen; geen SMS-authenticatie gebruikt |

Dit zijn providerquota. Ze kunnen gedeeld worden met andere projecten/diensten
in hetzelfde account. De dashboardmeters van de providers blijven leidend.

## Ingebouwde beperking

- Koersronde elke vijf minuten, maandag-vrijdag tussen 07:00 en 20:55 UTC.
  Bronbevestiging van de eigen beurssessie blijft vereist; gesloten markten worden
  niet gebruikt. Dit tijdvak omvat de geselecteerde markten bij zomer- en wintertijd.
- Maximaal 3.864 geplande koersrondes in een maand met 23 werkdagen, plus hoogstens
  46 bronnencontroles en 46 leercontroles. Eén continu open dashboard voegt circa
  44.640 basisstatusaanroepen per 31 dagen toe, afgezien van handmatige bediening.
  Een geopende leerpagina vraagt bovendien enkele compacte deeloverzichten op;
  deze schatting is geen totaal voor alle dashboardroutes.
- Twaalf koerspunten per bedrijf in de actieve status. De strategie gebruikt
  zes punten; de signaalregels blijven gelijk. Bestaande transactiebewijzen blijven
  behouden. Ruwe geaccepteerde quotes blijven twee dagen beschikbaar.
- Routinefout- en wachtmeldingen worden na zeven dagen verwijderd; bronrapporten
  na veertien dagen. Transacties, hun bewijzen en portefeuillecurve blijven behouden.
- Compacte dagaggregaten van koerskwaliteit blijven negentig dagen bewaard.
  Statische bronmetadata worden wekelijks gecontroleerd; officiële feedtitels en
  hoogstens 120 dagen vertraagde FRED-context worden begrensd opgehaald. Volledige
  wetenschappelijke PDFs worden niet dagelijks gedownload of opgeslagen.
- Automatische pauze bij 300 MB totale databasegrootte, 10.000 gemeten koerspogingen
  in een UTC-kalendermaand, of een app-raming van 3 GB automatisch dataverkeer.
  De raming telt per koerspoging viermaal de hoofd- en leerstatus plus vaste overhead.
  Deze grenzen zijn lokaal ook met geforceerd lage budgetten getest.
- De afzonderlijke referentie en varianten delen dezelfde opgehaalde koersen;
  zij doen geen extra marktdata- of AI-aanroepen. Leerverwerking pauzeert eerder,
  bij 250 MB database of 2,4 GB geraamd workerverkeer. Modellen worden maximaal
  driemaal per negentig dagen getraind. De laatste 2.000 opleidingsvoorbeelden
  blijven maximaal 180 dagen; dagelijkse leeraggregaten 120 dagen. Aankoopdossiers
  blijven behouden, ook als hun opleidingsvoorbeeld later wordt opgeruimd.
- Ook de bronnenroutine reserveert vooraf een conservatief budget voor begrensde
  downloads en statusoverdracht, met een lease en maximaal één claim per dertig
  minuten. Zij stopt bij 250 MB database of 2,4 GB geraamd workerverkeer.
- Een dagelijkse SQL-onderhoudstaak ruimt tijdelijke gegevens op zonder Edge-
  downloads, ook bij gepauzeerde handel. Bronrapporten: maximaal veertien dagen
  en veertig rapporten. Technische Cron-uitvoeringen van onze eigen vier taken:
  zeven dagen; app-verbruiksmaanden: vierentwintig maanden. Na negentig dagen
  blijven van de portefeuillecurve vier echte punten per UTC-dag over
  (eerste/laatste/laagste/hoogste). Aankoopdossiers en hoofdtransacties blijven behouden.
- In de website verschijnt een waarschuwing vanaf 70% van een app-budget.
  Een pauze doet geen abonnementupgrade en plaatst geen echte brokerorders.
- Automatische Render-deployments staan uit. Builds zijn kort en starten alleen
  bij expliciete uitrol. De statische site serveert alleen de frontend; de
  periodieke koersen en portefeuille-API lopen rechtstreeks via Supabase.

De database was bij de controle ongeveer 13 MB. Dat is geen bewijs voor toekomstig
verbruik. De ramingen en buffers maken deze private paperproef aannemelijk binnen
de gratis quota; ze zijn geen providerbreed factuurplafond. De app-raming telt
geen volledige Auth-/dashboard-/ander-projectbelasting en is niet gekoppeld aan
de precieze facturatieperiode van de provider. Er draait geen permanente agent
die vooraf toestemming kan vragen in deze chat. Waarschuwingen staan in de website.

## Specifiek voor Render

Render vermeldt dat extra bandbreedte wordt gefactureerd wanneer een betaalmethode
is gekoppeld; zonder betaalmethode worden diensten bij overschrijding tijdelijk
beperkt. Het Hobby-planoverzicht op zichzelf zegt niets over een betaalmethode.
De beschikbare API kon de werkelijke bandbreedtemeter niet uitlezen (HTTP 403).
Daarom is automatische waarschuwing of uitschakeling op basis van die meter
**niet bevestigd**. Een stop van de Supabase-worker stopt bovendien het publieke
verkeer naar de Render-frontend niet.

Voor strikt nul euro: controleer in Render Billing of er geen betaalmethode
gekoppeld is. Stel daarnaast in Workspace Settings → Build Pipeline → Set spend
limit het aanvullende buildbudget op $0 in. Een buildlimiet is geen
bandbreedtelimiet. Laat het account op Hobby, gebruik het inbegrepen onrender.com-
adres en controleer Monthly Included Usage. Er is geen betaalde wijziging toegestaan
zonder expliciete toestemming van de eigenaar.

Supabase documenteert dat Free-gebruik niet wordt gefactureerd. Bij quota-
overschrijding of structureel overmatig gebruik kan de dienst worden beperkt;
gratis hosting levert geen gegarandeerde ononderbroken werking.

Opschonen maakt databasepagina's herbruikbaar maar laat de gemelde fysieke
databasegrootte niet noodzakelijk meteen dalen. Omdat aankoopbewijzen blijven
groeien, is een toekomstige opslagpauze mogelijk, ook bij doorlopende planning.

## Bronnen

- [Render Free](https://render.com/docs/free)
- [Render-prijzen](https://render.com/pricing)
- [Render-bandbreedte en overschrijding](https://render.com/docs/outbound-bandwidth)
- [Render-buildbudget instellen](https://render.com/docs/build-pipeline#setting-a-spend-limit)
- [Supabase-prijzen](https://supabase.com/pricing)
- [Supabase Spend Cap en Free](https://supabase.com/docs/guides/platform/manage-your-usage/spend-cap)
- [Supabase-dataverkeer](https://supabase.com/docs/guides/platform/manage-your-usage/egress)
- [Supabase Edge-aanroepen](https://supabase.com/docs/guides/platform/manage-your-usage/edge-function-invocations)
