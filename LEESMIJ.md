# Migratiekit: oude Foodsoft (v3.4.0+adam) naar Foodsoft 5

Voor het technische team van order.voedselcollectief.org.

Met deze kit kun je een dump van de huidige database omzetten naar de nieuwste Foodsoft (5.0), met één database per coop. Alles draait in tijdelijke Docker-containers op je eigen computer. De server wordt niet aangeraakt.

## Waarom een gewone update niet werkt

Wat zeker is:

1. **De fork is geen oude versie maar een zijtak.** De fork is in 2014 afgetakt en heeft eigen kolommen toegevoegd. Twee daarvan voegt de nieuwe Foodsoft later ook toe (`orders.pickup` en de betaalkolommen in `financial_transactions`), en dan stopt `db:migrate` met *Duplicate column*.
2. **Meerdere coops op één installatie.** De voorpagina toont zes coops onder `/foodsoft/<coop>/`. Foodsoft 5 kan dat ook (`multi_coop_install`), maar met een eigen database per coop.
3. **De fork draait op Ruby 2.2 en Rails 3.2.** Foodsoft 5 draait op Ruby 3.4 en Rails 7.2. Je kunt dus niet "gewoon updaten": je installeert de nieuwe versie apart en zet de gegevens over.

Wat waarschijnlijk is, maar alleen met de echte database te bevestigen:

4. **Alle coops in één database.** De fork heeft een plugin, `foodsoft_multishared`, die alle coops in één database zet, gescheiden door een kolom `scope`. Gebruikt de server die, dan komen bij een gewone migratie alle coops in één coop terecht. Stap 1 van `sql/analyse.sql` laat dit zien. Je kunt die analyse los draaien op de huidige database, en dan verandert er niets.
5. **De tekenset is latin1.** Foodsoft 5 gebruikt utf8mb4. Zet je dat niet goed om, dan worden letters als é en ë onleesbaar.
6. **Gedeelde bestellingen.** Met multishared kon coop B meedoen met een bestelling van coop A (`join_scope`). Dat bestaat niet in Foodsoft 5.

De kit lost 1, 2, 4 en 5 op en stopt bij 6. Heeft elke coop al een eigen database, dan werkt de kit ook: draai hem dan per dump, met `LEGE_SCOPE=<coopnaam>`.

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

Opties: `FOODSOFT_IMAGE`, `DB_IMAGE` (standaard `mariadb:10.5`) en `LEGE_SCOPE` (naam van de coop als er geen scope is, standaard `f`; gebruik de naam uit de URL, bijvoorbeeld `fcadam`).

## Importeren in Foodsoft 5

In de map `installatie/` staat een voorbeeld van een nieuwe server: Foodsoft 5 met MariaDB, Redis, een worker en cron, via Docker Compose. Foodsoft zoekt de coops zelf: elke database die met `foodsoft_` begint, wordt een coop met dezelfde naam in de URL. De uitvoer van `migreer.sh` heeft al die namen.

Op de nieuwe server:

```sh
cd installatie
cp .env.voorbeeld .env        # wachtwoorden en SECRET_KEY_BASE invullen (openssl rand -hex 64)
nano app_config.defaults.yml  # default_scope, naam, contact
./importeer.sh ../uitvoer     # maakt per coop een database, leest de dump in, migreert, start alles
```

Wat `importeer.sh` doet:

1. Start de database.
2. Maakt voor elke `foodsoft_<coop>.sql` een database met dezelfde naam aan, en leest de dump in.
3. Draait `rails multicoops:run TASK=db:migrate`. Dat doet niets als de versie gelijk is aan die van `migreer.sh`, en werkt de database bij als je een nieuwere versie kiest.
4. Start `web`, `worker` en `cron`.

Daarna:

- **Https:** zet een reverse proxy voor poort 3000. Met Caddy krijg je automatisch een certificaat:

  ```
  order.voedselcollectief.org {
      @oud path_regexp oud ^/foodsoft/(.*)$
      redir @oud /{re.oud.1} permanent
      reverse_proxy 127.0.0.1:3000
  }
  ```

- **URLs veranderen** van `/foodsoft/<coop>/` naar `/<coop>/`. De `redir` hierboven stuurt oude links en bladwijzers door.
- **De voorpagina met de coops** zit niet in Foodsoft. Zet die als statische pagina in de proxy, of laat `default_scope` naar één coop wijzen.
- **Mail:** vul `SMTP_*` in `.env` in, anders gaan er geen mails uit, zoals wachtwoordherstel en berichten.
- **Instellingen per coop** (naam, adres, btw, opslag) zet je daarna in Foodsoft zelf, via Beheer > Instellingen.
- **Back-ups:** maak elke nacht een dump per database, en bewaar die buiten de server.
- **Een coop erbij** is gewoon een nieuwe lege database `foodsoft_<naam>`, met daarna `docker compose run --rm web bin/rails multicoops:run_single TASK=db:setup FOODCOOP=<naam>` en een herstart (niet getest).




## Getest

Getest op testdata, niet op echte data. De testdata komt uit de fork, die daarvoor lokaal is opgebouwd: Ruby 2.2 en MySQL 5.6.

| Test | Uitkomst |
|---|---|
| Eén coop, geen scope | gemigreerd, saldi gelijk |
| Twee coops (`noord`, `zuid`) | gesplitst in twee databases, saldi gelijk, accenten (`Brontë`, `Café`) goed |
| Twee coops met een gedeelde bestelling | script stopt met uitleg |
| Database zonder `scope`-kolommen (geen multishared) | gemigreerd als één coop, saldi gelijk |
| Coopnaam met streepje (`open-noord`) | database `foodsoft_open-noord`, werkt in Foodsoft 5 |
| Gemigreerde database in Foodsoft 5 | app start in productie, dozen vullen geeft dezelfde uitkomst als in de fork |
| Importeren met meerdere coops | beide coops bereikbaar onder `/<coop>/`, inloggen werkt (ook een wachtwoord uit de oude versie), elke coop ziet alleen zijn eigen leden |

## Nog niet getest, en wat je moet controleren

- **`docker-compose.yml` zelf.** De containers en instellingen zijn getest met losse `docker run`-commando's, niet met Compose zelf. `worker`, `cron` en mail zijn niet getest. De tests gebruikten MariaDB 10.5, het voorbeeld 10.11.
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
- `installatie/docker-compose.yml`: voorbeeld van de nieuwe server.
- `installatie/app_config.defaults.yml`: instellingen voor alle coops.
- `installatie/importeer.sh`: leest de uitvoer in en start Foodsoft.
- `installatie/.env.voorbeeld`: kopiëren naar `.env` en invullen.
