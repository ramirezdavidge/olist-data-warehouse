USE OlistDW;
SELECT 'customers' AS tabla, COUNT(*) AS filas FROM silver.customers
UNION ALL SELECT 'geolocation', COUNT(*) FROM silver.geolocation
UNION ALL SELECT 'orders', COUNT(*) FROM silver.orders
UNION ALL SELECT 'order_items', COUNT(*) FROM silver.order_items
UNION ALL SELECT 'order_payments', COUNT(*) FROM silver.order_payments
UNION ALL SELECT 'order_reviews', COUNT(*) FROM silver.order_reviews
UNION ALL SELECT 'products', COUNT(*) FROM silver.products
UNION ALL SELECT 'sellers', COUNT(*) FROM silver.sellers
UNION ALL SELECT 'category_translation', COUNT(*) FROM silver.product_category_translation;