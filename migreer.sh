#!/usr/bin/env bash
# Migreert een dump van de oude Foodsoft (fork v3.4.0+adam) naar de nieuwe Foodsoft.
# Per coop (scope) komt er een aparte database uit, zoals de nieuwe Foodsoft dat wil.
#
# Gebruik:   ./migreer.sh dump.sql [uitvoermap]
# Opties (omgevingsvariabelen):
#   FOODSOFT_IMAGE  standaard foodcoops/foodsoft:latest
#   DB_IMAGE        standaard mariadb:10.5
#   LEGE_SCOPE      naam voor rijen zonder scope (standaard f)
#   FORCEER=1       ga door, ook als er gedeelde bestellingen zijn
#
# Alles draait in tijdelijke Docker-containers. De echte server wordt niet aangeraakt.
set -euo pipefail

DUMP=${1:?Gebruik: ./migreer.sh dump.sql [uitvoermap]}
UIT=${2:-uitvoer}
KIT=$(cd "$(dirname "$0")" && pwd)
FOODSOFT_IMAGE=${FOODSOFT_IMAGE:-foodcoops/foodsoft:latest}
DB_IMAGE=${DB_IMAGE:-mariadb:10.5}
LEGE_SCOPE=${LEGE_SCOPE:-f}
NET=fskit-net; DB=fskit-db; PW=kitgeheim

mkdir -p "$UIT"; UIT=$(cd "$UIT" && pwd)
log() { echo "==> $*"; }
sql() { docker exec -i "$DB" mariadb -uroot -p"$PW" --default-character-set=utf8mb4 "$@"; }
opruimen() { docker rm -f "$DB" >/dev/null 2>&1 || true; docker network rm "$NET" >/dev/null 2>&1 || true; }
trap opruimen EXIT

log "Tijdelijke database starten ($DB_IMAGE)"
opruimen
docker network create "$NET" >/dev/null
docker run -d --name "$DB" --network "$NET" -e MARIADB_ROOT_PASSWORD="$PW" "$DB_IMAGE" \
  --character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci >/dev/null
until sql -e 'SELECT 1' >/dev/null 2>&1; do sleep 2; done

log "Dump inlezen in database 'bron'"
sql -e 'CREATE DATABASE bron'
sql bron < "$DUMP"

# Zonder multishared bestaat de kolom scope misschien niet: dan tijdelijk toevoegen (één coop).
for T in groups suppliers orders invites tasks messages article_categories; do
  if [ "$(sql -N bron -e "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema='bron' AND table_name='$T' AND column_name='scope'")" = 0 ]; then
    sql bron -e "ALTER TABLE \`$T\` ADD COLUMN scope varchar(255) NULL"
  fi
done

log "Analyse -> $UIT/analyse.txt"
sql -t bron < "$KIT/sql/analyse.sql" > "$UIT/analyse.txt"
cat "$UIT/analyse.txt"

GEDEELD=$(sql -N bron -e "SELECT COUNT(*) FROM group_orders go JOIN orders o ON o.id=go.order_id
                          JOIN groups g ON g.id=go.ordergroup_id WHERE NOT (o.scope <=> g.scope)")
if [ "$GEDEELD" != 0 ] && [ "${FORCEER:-0}" != 1 ]; then
  echo "STOP: $GEDEELD groepsbestellingen horen bij een bestelling van een andere coop (analyse stap 2)."
  echo "      De nieuwe Foodsoft kent geen gedeelde bestellingen tussen coops. Eerst samen besluiten"
  echo "      wat daarmee moet; daarna eventueel opnieuw met FORCEER=1 (die bestellingen vallen dan weg)."
  exit 1
fi

mapfile -t SCOPES < <(sql -N bron -e "SELECT DISTINCT IFNULL(scope,'') FROM groups")
for S in "${SCOPES[@]}"; do
  NAAM=${S:-$LEGE_SCOPE}; DBN="foodsoft_${NAAM//[^a-zA-Z0-9_-]/_}"   # zelfde naam als Foodsoft 5 verwacht
  if [ -z "$S" ]; then SCOPE_SQL="SET @scope = NULL;"; else SCOPE_SQL="SET @scope = '${S//\'/}';"; fi
  log "Coop '$NAAM' -> database $DBN"

  sql -e "DROP DATABASE IF EXISTS \`$DBN\`; CREATE DATABASE \`$DBN\`"
  docker exec "$DB" sh -c "mariadb-dump -uroot -p$PW --single-transaction bron | mariadb -uroot -p$PW $DBN"
  { echo "$SCOPE_SQL"; cat "$KIT/sql/splits.sql"; } | sql "$DBN"

  { echo "$SCOPE_SQL"; cat "$KIT/sql/saldi.sql"; } | sql -t bron > "$UIT/saldi-$NAAM-voor.txt"

  # Foodsoft 5 gebruikt geen scope-kolommen meer: weghalen.
  sql -N -e "SELECT CONCAT('ALTER TABLE \`',table_name,'\` DROP COLUMN scope;') FROM information_schema.columns
             WHERE table_schema='$DBN' AND column_name='scope'" | sql "$DBN"

  log "  tekenset naar utf8mb4"
  sql -N -e "SELECT CONCAT('ALTER TABLE \`',table_name,'\` CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;')
             FROM information_schema.tables WHERE table_schema='$DBN' AND table_type='BASE TABLE'" | sql "$DBN"
  sql -e "ALTER DATABASE \`$DBN\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"

  log "  botsingen met de fork oplossen"
  sql "$DBN" < "$KIT/sql/voor-migratie.sql" | tee "$UIT/voor-migratie-$NAAM.txt"

  log "  migreren met $FOODSOFT_IMAGE"
  docker run --rm --network "$NET" \
    -e RAILS_ENV=production -e SECRET_KEY_BASE=$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n') \
    -e DATABASE_URL="mysql2://root:$PW@$DB/$DBN?encoding=utf8mb4" \
    --entrypoint sh "$FOODSOFT_IMAGE" -c 'bin/rails db:migrate' \
    > "$UIT/migratie-$NAAM.log" 2>&1 || { grep -v '^\s*from ' "$UIT/migratie-$NAAM.log" | tail -15; echo "STOP: migratie mislukt, zie $UIT/migratie-$NAAM.log"; exit 1; }

  grep -v 'g.scope' "$KIT/sql/saldi.sql" | sql -t "$DBN" > "$UIT/saldi-$NAAM-na.txt"
  if diff -q "$UIT/saldi-$NAAM-voor.txt" "$UIT/saldi-$NAAM-na.txt" >/dev/null; then
    log "  saldi, leden en bestellingen per groep: gelijk"
  else
    echo "LET OP: verschil in saldi voor '$NAAM':"; diff "$UIT/saldi-$NAAM-voor.txt" "$UIT/saldi-$NAAM-na.txt" || true
  fi

  docker exec "$DB" mariadb-dump -uroot -p"$PW" --single-transaction "$DBN" > "$UIT/$DBN.sql"
  log "  klaar: $UIT/$DBN.sql"
done

log "Alles klaar. Uitvoer in $UIT"
