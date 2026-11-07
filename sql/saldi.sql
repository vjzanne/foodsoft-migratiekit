-- Saldo per bestelgroep, voor vergelijking voor en na de migratie.
-- Zet vooraf: SET @scope = 'naam';  (NULL = geen filter)
SELECT g.id, g.name, g.account_balance,
       IFNULL((SELECT SUM(ft.amount) FROM financial_transactions ft WHERE ft.ordergroup_id = g.id), 0) AS som_transacties,
       (SELECT COUNT(*) FROM memberships m WHERE m.group_id = g.id) AS leden,
       (SELECT COUNT(*) FROM group_orders go WHERE go.ordergroup_id = g.id) AS bestellingen
FROM groups g
WHERE g.type = 'Ordergroup'
  AND (@scope IS NULL OR g.scope <=> @scope)   -- regel wordt weggelaten na de migratie
ORDER BY g.id;
