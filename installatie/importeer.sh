#!/usr/bin/env bash
# Leest de uitvoer van migreer.sh in de database van docker-compose.yml.
# Gebruik: ./importeer.sh ../uitvoer      (map met foodsoft_<coop>.sql)
set -euo pipefail
MAP=${1:?Gebruik: ./importeer.sh <map met foodsoft_*.sql>}
cd "$(dirname "$0")"
set -a; . ./.env; set +a

docker compose up -d db
until docker compose exec -T db mariadb -uroot -p"$DB_ROOT_PASSWORD" -e 'SELECT 1' >/dev/null 2>&1; do sleep 2; done

for f in "$MAP"/foodsoft_*.sql; do
  DBN=$(basename "$f" .sql)
  echo "==> $DBN"
  docker compose exec -T db mariadb -uroot -p"$DB_ROOT_PASSWORD" -e "
    CREATE DATABASE IF NOT EXISTS \`$DBN\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    GRANT ALL ON \`$DBN\`.* TO 'foodsoft'@'%';"
  docker compose exec -T db mariadb -uroot -p"$DB_ROOT_PASSWORD" "$DBN" < "$f"
done

# Voor de zekerheid: eventuele nieuwere migraties van de gekozen Foodsoft-versie
docker compose run --rm web bin/rails multicoops:run TASK=db:migrate
docker compose up -d
echo "==> Klaar. Foodsoft draait op http://127.0.0.1:3000/<coop>/login"
