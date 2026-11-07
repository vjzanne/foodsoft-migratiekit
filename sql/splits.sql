-- Houdt in deze database-kopie alleen de gegevens van één coop over.
-- Zet vooraf: SET @scope = 'naam';
-- Draai dit ALLEEN op een kopie. Gedeelde bestellingen (zie analyse stap 2)
-- worden hier niet opgelost: migreer.sh stopt als die er zijn.

SET FOREIGN_KEY_CHECKS = 0;

-- 1. Rijen met een andere scope
DELETE FROM groups             WHERE NOT (scope <=> @scope);
DELETE FROM suppliers          WHERE NOT (scope <=> @scope);
DELETE FROM orders             WHERE NOT (scope <=> @scope);
DELETE FROM invites            WHERE NOT (scope <=> @scope);
DELETE FROM tasks              WHERE NOT (scope <=> @scope);
DELETE FROM messages           WHERE NOT (scope <=> @scope);

-- 2. Wat daaraan hing
DELETE m  FROM memberships m  LEFT JOIN groups g ON g.id = m.group_id WHERE g.id IS NULL;
DELETE ft FROM financial_transactions ft LEFT JOIN groups g ON g.id = ft.ordergroup_id WHERE g.id IS NULL;
DELETE go FROM group_orders go LEFT JOIN groups g ON g.id = go.ordergroup_id WHERE g.id IS NULL;
DELETE go FROM group_orders go LEFT JOIN orders o ON o.id = go.order_id WHERE o.id IS NULL;
DELETE goa FROM group_order_articles goa LEFT JOIN group_orders go ON go.id = goa.group_order_id WHERE go.id IS NULL;
DELETE q  FROM group_order_article_quantities q LEFT JOIN group_order_articles goa ON goa.id = q.group_order_article_id WHERE goa.id IS NULL;
DELETE oa FROM order_articles oa LEFT JOIN orders o ON o.id = oa.order_id WHERE o.id IS NULL;
DELETE oc FROM order_comments oc LEFT JOIN orders o ON o.id = oc.order_id WHERE o.id IS NULL;
DELETE a  FROM articles a LEFT JOIN suppliers s ON s.id = a.supplier_id WHERE s.id IS NULL;
DELETE p  FROM article_prices p LEFT JOIN articles a ON a.id = p.article_id WHERE a.id IS NULL;
DELETE d  FROM deliveries d LEFT JOIN suppliers s ON s.id = d.supplier_id WHERE s.id IS NULL;
DELETE i  FROM invoices i LEFT JOIN suppliers s ON s.id = i.supplier_id WHERE s.id IS NULL;
DELETE sc FROM stock_changes sc LEFT JOIN articles a ON a.id = sc.stock_article_id WHERE a.id IS NULL;
DELETE asg FROM assignments asg LEFT JOIN tasks t ON t.id = asg.task_id WHERE t.id IS NULL;

-- 3. Categorieën: eigen scope, of nog gebruikt door een artikel van deze coop
DELETE c FROM article_categories c
WHERE NOT (c.scope <=> @scope)
  AND NOT EXISTS (SELECT 1 FROM articles a WHERE a.article_category_id = c.id);

-- 4. Leden zonder groep in deze coop
DELETE u FROM users u
WHERE NOT EXISTS (SELECT 1 FROM memberships m WHERE m.user_id = u.id);

-- 5. Instellingen van andere coops (rails-settings: foodcoop.<scope>.<sleutel>)
DELETE FROM settings
WHERE var LIKE 'foodcoop.%' AND var NOT LIKE CONCAT('foodcoop.', IFNULL(@scope,''), '.%');

SET FOREIGN_KEY_CHECKS = 1;
