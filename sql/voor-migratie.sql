-- Lost de botsingen op tussen de fork en de nieuwe Foodsoft, vóór `rails db:migrate`.
-- De fork had sommige kolommen al zelf toegevoegd. De nieuwe migraties willen ze
-- opnieuw toevoegen en stoppen dan met "Duplicate column". Hier passen we de kolom
-- aan naar wat de nieuwe versie verwacht en markeren we die migratie als gedaan.
-- (Puur SQL: `rails runner` start niet op het oude schema. MariaDB-syntax.)

-- 1. orders.pickup: de fork heeft datetime, de nieuwe versie date (migratie 20160217152621).
SET @h := (SELECT COUNT(*) FROM information_schema.columns
           WHERE table_schema = DATABASE() AND table_name = 'orders' AND column_name = 'pickup');
SET @s := IF(@h = 1, 'ALTER TABLE orders MODIFY pickup date', 'DO 0');
PREPARE p FROM @s; EXECUTE p; DEALLOCATE PREPARE p;
SET @s := IF(@h = 1, "INSERT IGNORE INTO schema_migrations (version) VALUES ('20160217152621')", 'DO 0');
PREPARE p FROM @s; EXECUTE p; DEALLOCATE PREPARE p;
SELECT IF(@h = 1, 'orders.pickup: omgezet en gemarkeerd', 'orders.pickup: niet aanwezig, niets gedaan') AS stap1;

-- 2. Betaalkolommen in financial_transactions (migratie 20230915093041).
--    Alleen als alle 8 kolommen er al zijn; anders laat de migratie de fout zien.
SET @h := (SELECT COUNT(*) FROM information_schema.columns
           WHERE table_schema = DATABASE() AND table_name = 'financial_transactions'
             AND column_name IN ('updated_on','payment_method','payment_plugin','payment_id',
                                 'payment_amount','payment_currency','payment_state','payment_fee'));
SET @s := IF(@h = 8, 'ALTER TABLE financial_transactions MODIFY amount decimal(8,2) NULL DEFAULT NULL', 'DO 0');
PREPARE p FROM @s; EXECUTE p; DEALLOCATE PREPARE p;
SET @s := IF(@h = 8, 'CREATE INDEX IF NOT EXISTS index_financial_transactions_on_payment_plugin_and_payment_id
                      ON financial_transactions (payment_plugin, payment_id)', 'DO 0');
PREPARE p FROM @s; EXECUTE p; DEALLOCATE PREPARE p;
SET @s := IF(@h = 8, "INSERT IGNORE INTO schema_migrations (version) VALUES ('20230915093041')", 'DO 0');
PREPARE p FROM @s; EXECUTE p; DEALLOCATE PREPARE p;
SELECT CASE @h WHEN 8 THEN 'betaalkolommen: gemarkeerd'
               WHEN 0 THEN 'betaalkolommen: niet aanwezig, niets gedaan'
               ELSE CONCAT('LET OP: maar ', @h, ' van 8 betaalkolommen aanwezig, migratie zal botsen') END AS stap2;
