# Alpaca: Supabase-verbinding gecontroleerd op 9 november 2026

De twee Alpaca-secrets zijn aanwezig in Supabase. De sleutelwaarden zijn niet
opgevraagd, gekopieerd naar Codex of getoond. Een afgeschermde serverfunctie
`paper-alpaca-check` gebruikt ze rechtstreeks voor één vaste GET-aanvraag naar
`data.alpaca.markets/v2/stocks/quotes/latest`, met `feed=iex` en drie symbolen.
Geen brokerage/order-endpoints, portefeuille-RPCs of periodieke jobs toegevoegd.

Werkelijke test om 14:01:32 UTC / **15:01:32 Belgische tijd**:

- Alpaca antwoordt met **HTTP 200**: toegang tot de IEX-endpoint werkt.
- AAPL, MSFT en NVDA bevatten records, maar met een laatprijs van nul.
- De koersstempels zijn van vrijdag 6 november rond 21:00 UTC, bij de vorige sluiting.
- Alle drie worden daarom als onbruikbare bied-laatquotes aangemerkt.
- De reguliere Amerikaanse beurs opent vandaag pas om **15:30 Belgische tijd**.
- Realtime-versheid tijdens de open sessie is hiermee nog niet aangetoond.

De diagnostiek is handmatig, vereist de bestaande geheime servertoken en weigert
anonieme toegang. Providerfouten worden als vaste statussen gerapporteerd;
providerfoutteksten en credentials komen niet in de uitvoer. Kruisende quotes,
ontbrekende zijden, ongeldige tijden en oude quotes kunnen geen verse data lijken.

De bestaande Yahoo-transportvariant en handelsregels zijn niet omgeschakeld.
Een nieuwe marktdatafase moet bij latere activering herkenbaar worden geregistreerd;
bestaande posities, verliezen en referentieresultaten blijven behouden.

Herhaalbaar via `python scripts/check_alpaca.py PROJECT_REF`.
`--deploy` installeert of actualiseert uitsluitend de afgeschermde testfunctie.
Het script controleert secretnamen en laat de waarden op Supabase staan.
Geen wijziging van de Codex-configuratie of Render nodig.

Validatie: vijf gerichte tests en de volledige bestaande Node-reeks geslaagd.
Live anonieme toegang geweigerd met HTTP 401; geautoriseerde aanvraag HTTP 200.
