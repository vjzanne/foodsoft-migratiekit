-- Analyse van de oude Foodsoft-database (fork v3.4.0+adam).
-- Alleen lezen, verandert niets. Draait op MySQL 5.6 en nieuwer.
-- Gebruik: mysql -t <database> < analyse.sql

SELECT '1. Coops (scope) en aantallen' AS stap;
SELECT IFNULL(scope,'(leeg)') AS scope,
       SUM(type='Ordergroup') AS bestelgroepen,
       SUM(type='Workgroup')  AS werkgroepen,
       SUM(deleted_at IS NULL AND type='Ordergroup') AS actieve_bestelgroepen
FROM groups GROUP BY scope;

SELECT IFNULL(scope,'(leeg)') AS scope, COUNT(*) AS leveranciers FROM suppliers GROUP BY scope;
SELECT IFNULL(scope,'(leeg)') AS scope, COUNT(*) AS bestellingen, MAX(ends) AS laatste FROM orders GROUP BY scope;

SELECT '2. Gedeelde bestellingen (leden van coop A in een bestelling van coop B)' AS stap;
SELECT IFNULL(o.scope,'(leeg)') AS scope_bestelling, IFNULL(g.scope,'(leeg)') AS scope_lid,
       COUNT(DISTINCT o.id) AS bestellingen, COUNT(*) AS groepsbestellingen
FROM group_orders go
JOIN orders o ON o.id = go.order_id
JOIN groups g ON g.id = go.ordergroup_id
WHERE NOT (o.scope <=> g.scope)
GROUP BY o.scope, g.scope;

SELECT '3. Leden die in meer dan een coop zitten' AS stap;
SELECT COUNT(*) AS leden_in_meerdere_coops FROM (
  SELECT m.user_id FROM memberships m JOIN groups g ON g.id = m.group_id
  GROUP BY m.user_id HAVING COUNT(DISTINCT IFNULL(g.scope,'')) > 1
) x;

SELECT '4. Leden zonder groep (komen bij geen enkele coop terecht)' AS stap;
SELECT COUNT(*) AS leden_zonder_groep FROM users u
WHERE NOT EXISTS (SELECT 1 FROM memberships m WHERE m.user_id = u.id);

SELECT '4b. Coops zonder beheerder (geen werkgroep met beheerrechten en leden)' AS stap;
SELECT DISTINCT IFNULL(o.scope,'(leeg)') AS scope_zonder_beheerder FROM groups o
WHERE o.type='Ordergroup' AND NOT EXISTS (
  SELECT 1 FROM groups w JOIN memberships m ON m.group_id = w.id
  WHERE w.type='Workgroup' AND w.role_admin = 1 AND w.scope <=> o.scope);

SELECT '5. Saldo per coop (som van account_balance)' AS stap;
SELECT IFNULL(scope,'(leeg)') AS scope, SUM(account_balance) AS totaal_saldo
FROM groups WHERE type='Ordergroup' GROUP BY scope;

SELECT '6. Klopt account_balance met de transacties?' AS stap;
SELECT COUNT(*) AS bestelgroepen_met_verschil FROM groups g
LEFT JOIN (SELECT ordergroup_id, SUM(amount) s FROM financial_transactions GROUP BY ordergroup_id) t
  ON t.ordergroup_id = g.id
WHERE g.type='Ordergroup' AND ABS(g.account_balance - IFNULL(t.s,0)) > 0.005;

SELECT '7. Tekenset van de tabellen' AS stap;
SELECT table_collation, COUNT(*) AS tabellen FROM information_schema.tables
WHERE table_schema = DATABASE() GROUP BY table_collation;

SELECT '8. Mogelijk dubbel gecodeerde tekst (bijv. Ã© in plaats van é)' AS stap;
SELECT 'users' AS tabel, COUNT(*) AS verdacht FROM users
  WHERE CONCAT(first_name,last_name) REGEXP 'Ã|Â'
UNION ALL SELECT 'articles', COUNT(*) FROM articles WHERE name REGEXP 'Ã|Â'
UNION ALL SELECT 'groups', COUNT(*) FROM groups WHERE name REGEXP 'Ã|Â';

SELECT '9. Wiki-paginas (hebben geen scope, gaan naar elke coop mee)' AS stap;
SELECT COUNT(*) AS paginas FROM pages;

SELECT '10. Laatste migraties van de fork' AS stap;
SELECT COUNT(*) AS migraties FROM schema_migrations;
SELECT version FROM schema_migrations ORDER BY CAST(version AS UNSIGNED) DESC LIMIT 5;
