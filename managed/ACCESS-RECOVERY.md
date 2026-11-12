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
