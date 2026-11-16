# Eenmalig beheerherstel

De gewone Codex-beheertoken wordt geweigerd. De huidige Render API-sleutel kan
de bestaande gratis PaperLab-site en `paperlab-beheer` bereiken. De andere
Render-groep uit de browsersessie van de eigenaar is niet toegankelijk voor
deze sleutel. Kopieer geen leesbare tokens naar chat, Git, assets of lokale logs.

`access-recovery.html` versleutelt uitsluitend in de browser, met Web Crypto
RSA-OAEP 4096/SHA-256 en een vaste contextlabel. De sleutelconfiguratie bevat
alleen de openbare sleutel, SHA-256-id en een geldigheid van maximaal 24 uur.
Een herstelbericht is 30 minuten geldig. Het formulier verstuurt geen token,
gebruikt geen browseropslag en wist het invoerveld na iedere poging. Alleen
het versleutelde bericht wordt op uitdrukkelijke actie gekopieerd. Deze pagina
geeft geen portefeuille- of brokerrechten en vervangt geen gebruikers-MFA.

`python scripts/access_recovery.py generate` maakt de privésleutel met beperkte
bestandsrechten buiten de checkout onder `/tmp/paperlab-supabase-recovery`.
Alleen de publieke `managed/web/access-recovery-key.json` mag worden gepubliceerd.
Na verlies/herstart van deze cloudomgeving is een nieuwe sleutel nodig.

De eigenaar voert zijn persoonlijke Supabase-token op de HTTPS-herstelpagina in
en deelt uitsluitend het versleutelde bericht. Sla dat bericht op als tijdelijke
ciphertext-invoer en gebruik `python scripts/access_recovery.py accept FILE`.
Dit ontsleutelt uitsluitend in het geheugen, verifieert databaseleesrechten op
het bestaande project en slaat de token op in de reeds bestaande **ongekoppelde**
Render-groep. De token wordt nooit in een bestand of procesomgeving gezet.
Na bevestigde opslag wordt de privésleutel verwijderd en de publieke configuratie
uitgeschakeld. Publiceer die uitgeschakelde configuratie daarna ook op Render.
De reguliere HTTP-secret in Codex wordt hierdoor niet automatisch aangepast.

Voor beheer via deze expliciete herstelroute:

`python scripts/access_recovery.py run scripts/managed_status.py`

De wrapper leest de opgeslagen waarde vers uit Render, houdt haar in het geheugen
en gebruikt uitsluitend `https://api.supabase.com/v1/`. Andere beheerclients en de
geërfde proxy/CA-configuratie blijven intact. Scripts moeten onder `scripts/` staan.
Geen extra hosting, betaald plan of echte brokerorders worden aangemaakt.

## Gemini API-sleutel via versleuteld bericht

`/gemini-connect.html` is een afzonderlijk browserformulier voor `GEMINI_API_KEY`.
Genereer de publieke verbindingsconfiguratie met `python scripts/gemini_recovery.py generate`.
De RSA-4096 privésleutel blijft buiten Git onder `/tmp/paperlab-gemini-connect/`.
De publieke configuratie is maximaal 24 uur geldig; een bericht 30 minuten.
Het formulier verstuurt de ingevulde sleutel niet en gebruikt geen browseropslag.

Na ontvangst wordt uitsluitend het versleutelde bericht in een afgeschermd lokaal
bestand gezet. `scripts/gemini_recovery.py accept ENCRYPTED_FILE` controleert de
berichtcontext en vervaltijden, slaat de sleutel als Supabase Edge Function secret
op en vergelijkt de teruggelezen SHA-256 digest. Het commando gebruikt de bestaande
beheerclient. De provider-sleutel is daarmee nog niet getest: er worden geen
modelaanvragen uitgevoerd en geen betaalde facturatie of handelsregels geactiveerd.
Na succesvolle opslag worden de lokale verbinding gesloten en privésleutel verwijderd.
Publiceer daarna ook de gesloten publieke configuratie om het formulier af te sluiten.
Bij verlies van de tijdelijke privésleutel is een nieuwe verbindingsronde nodig.

Controle met synthetische sleutel: `python managed/tests/browser_gemini_connect.py`.
Voor de live pagina: `PAPERLAB_BROWSER_URL=https://paperlab-prive.onrender.com python managed/tests/browser_gemini_connect.py`.
