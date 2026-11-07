# Migratiekit: oude Foodsoft (v3.4.0+adam) naar Foodsoft 5

Voor het technische team van order.voedselcollectief.org.

Met deze kit kun je een dump van de huidige database omzetten naar de nieuwste Foodsoft (5.0), met één database per coop. Alles draait in tijdelijke Docker-containers op je eigen computer. De server wordt niet aangeraakt.

## Waarom een gewone update niet werkt

1. **De fork is geen oude versie maar een zijtak.** De fork is in 2014 afgetakt en heeft eigen kolommen toegevoegd. Twee daarvan voegt de nieuwe Foodsoft later ook toe (`orders.pickup` en de betaalkolommen in `financial_transactions`), en dan stopt `db:migrate` met *Duplicate column*.
2. **Alle coops zitten in één database.** De plugin `foodsoft_multishared` scheidt de coops met een kolom `scope`. De nieuwe Foodsoft kent die kolom niet: daar heeft elke coop een eigen database (`multi_coop_install`). Zonder te splitsen komen alle coops in één coop terecht.
3. **De tekenset is latin1.** De nieuwe versie gebruikt utf8mb4. Zet je dat niet goed om, dan worden letters als é en ë onleesbaar.
4. **Gedeelde bestellingen.** Met multishared kon coop B meedoen met een bestelling van coop A (`join_scope`). Dat bestaat niet in de nieuwe Foodsoft.

De kit lost 1 tot en met 3 op en stopt bij 4.

## Gebruik

Je hebt Docker nodig, en een dump van de huidige database:

```sh
mysqldump --single-transaction foodsoft > dump.sql   # op de server
./migreer.sh dump.sql uitvoer/                       # lokaal
```

Wat het script doet:

1. Leest de dump in een tijdelijke MariaDB in.
2. Schrijft een **analyse** naar `uitvoer/analyse.txt`. Het script verandert daarbij niets. Je ziet:
   - welke coops er zijn
   - of er gedeelde bestellingen zijn
   - of er leden in meerdere coops zitten
   - of er coops zonder beheerder zijn
   - of de saldi kloppen met de transacties
   - de tekenset
   - mogelijk dubbel gecodeerde tekst
3. **Stopt** als er gedeelde bestellingen zijn. Wil je toch door, gebruik dan `FORCEER=1`; die bestellingen vallen dan weg.
4. Per coop:
   - een kopie van de database maken en alles van andere coops eruit halen (`sql/splits.sql`)
   - omzetten naar utf8mb4
   - de botsingen met de fork oplossen (`sql/voor-migratie.sql`)
   - `rails db:migrate` draaien met de officiële image `foodcoops/foodsoft`
   - per bestelgroep saldo, aantal leden en aantal bestellingen voor en na vergelijken
   - een dump wegschrijven: `uitvoer/foodsoft_<coop>.sql`

Die dumps kun je inlezen op een nieuwe installatie van Foodsoft 5. Zet daar `multi_coop_install: true` en geef elke coop een eigen database in `config/app_config.yml` (zie `MULTI_COOP_INSTALL` in de Foodsoft-repo).

Opties: `FOODSOFT_IMAGE`, `DB_IMAGE` (standaard `mariadb:10.5`) en `LEGE_SCOPE` (naam voor rijen zonder scope, standaard `f`).

## Getest

Getest op testdata, niet op echte data. De testdata komt uit de fork, die daarvoor lokaal is opgebouwd: Ruby 2.2 en MySQL 5.6.

| Test | Uitkomst |
|---|---|
| Eén coop, geen scope | gemigreerd, saldi gelijk |
| Twee coops (`noord`, `zuid`) | gesplitst in twee databases, saldi gelijk, accenten (`Brontë`, `Café`) goed |
| Twee coops met een gedeelde bestelling | script stopt met uitleg |
| Gemigreerde database in Foodsoft 5 | app start in productie, dozen vullen geeft dezelfde uitkomst als in de fork |

## Nog niet getest, en wat je moet controleren

- **Echte data.** Na jaren gebruik kunnen er meer botsingen zijn, bijvoorbeeld van plugins die bij ons niet aanstonden. `db:migrate` noemt dan de kolom. Voeg die toe aan `sql/voor-migratie.sql` op dezelfde manier als de twee bestaande.
- **Leden in meerdere coops.** Die komen in elke coop als aparte gebruiker terecht, met hetzelfde wachtwoord.
- **Wachtwoorden.** Beide versies controleren met `SHA1(wachtwoord + password_salt)`, dus wachtwoorden gaan mee. Probeer het toch eerst met een echt account.
- **Wiki-pagina's** hebben geen scope en gaan naar elke coop mee. Verwijder per coop wat er niet bij hoort.
- **Afrekenen en een bestelling afsluiten** met echte data. Doe een proefbestelling op de gemigreerde kopie.
- **Plugins van de fork die niet in Foodsoft 5 zitten:**
  - adyen
  - multishared (gedeelde bestellingen, de inschrijfkaart)
  - payorder
  - orderdoc
  - signup
  - split_manufacturer
  - vokomokum
  - protect_shared
  - mailall
  - userinfo

  Mollie, messages, wiki, current_orders en uservoice bestaan wel. De tabel `adyen_notifications` blijft staan maar wordt niet gebruikt.

## Bestanden

- `migreer.sh`: het hele proces.
- `sql/analyse.sql`: alleen lezen. Kan ook los op de huidige database: `mysql -t foodsoft < sql/analyse.sql`.
- `sql/splits.sql`: houdt één coop over. Alleen op een kopie draaien.
- `sql/voor-migratie.sql`: lost de botsingen met de fork op.
- `sql/saldi.sql`: saldo per bestelgroep, voor de controle.
