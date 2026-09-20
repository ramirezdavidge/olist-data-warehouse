/*
===============================================================================
99 - VALIDACIONES DE CALIDAD Y CONCILIACIÓN ENTRE CAPAS
===============================================================================

===============================================================================
*/

USE OlistDW;
GO

/* ----------------------------------------------------------------------------
   1. CONTEO DE FILAS POR CAPA
   ---------------------------------------------------------------------------- */
SELECT 'bronze' AS capa, 'customers'    AS tabla, COUNT(*) AS filas, 99441   AS esperado FROM bronze.customers
UNION ALL SELECT 'bronze', 'geolocation',    COUNT(*), 1000163 FROM bronze.geolocation
UNION ALL SELECT 'bronze', 'order_items',    COUNT(*), 112650  FROM bronze.order_items
UNION ALL SELECT 'bronze', 'order_payments', COUNT(*), 103886  FROM bronze.order_payments
UNION ALL SELECT 'bronze', 'order_reviews',  COUNT(*), 99224   FROM bronze.order_reviews
UNION ALL SELECT 'bronze', 'orders',         COUNT(*), 99441   FROM bronze.orders
UNION ALL SELECT 'bronze', 'products',       COUNT(*), 32951   FROM bronze.products
UNION ALL SELECT 'bronze', 'sellers',        COUNT(*), 3095    FROM bronze.sellers
UNION ALL SELECT 'bronze', 'product_category_translation', COUNT(*), 71 FROM bronze.product_category_translation
UNION ALL SELECT 'silver', 'customers',      COUNT(*), 99441   FROM silver.customers
UNION ALL SELECT 'silver', 'geolocation',    COUNT(*), 720463  FROM silver.geolocation   -- sin duplicados ni coordenadas fuera de Brasil
UNION ALL SELECT 'silver', 'order_items',    COUNT(*), 112650  FROM silver.order_items
UNION ALL SELECT 'silver', 'order_payments', COUNT(*), 103886  FROM silver.order_payments
UNION ALL SELECT 'silver', 'order_reviews',  COUNT(*), 99224   FROM silver.order_reviews
UNION ALL SELECT 'silver', 'orders',         COUNT(*), 99441   FROM silver.orders
UNION ALL SELECT 'silver', 'products',       COUNT(*), 32951   FROM silver.products
UNION ALL SELECT 'silver', 'sellers',        COUNT(*), 3095    FROM silver.sellers
UNION ALL SELECT 'silver', 'product_category_translation', COUNT(*), 74 FROM silver.product_category_translation  -- 71 + 3 agregadas
UNION ALL SELECT 'gold',   'dim_fecha',      COUNT(*), 1096    FROM gold.dim_fecha
UNION ALL SELECT 'gold',   'dim_cliente',    COUNT(*), 96096   FROM gold.dim_cliente     -- clientes únicos
UNION ALL SELECT 'gold',   'dim_producto',   COUNT(*), 32951   FROM gold.dim_producto
UNION ALL SELECT 'gold',   'dim_vendedor',   COUNT(*), 3095    FROM gold.dim_vendedor
UNION ALL SELECT 'gold',   'dim_tipo_pago',  COUNT(*), 5       FROM gold.dim_tipo_pago
UNION ALL SELECT 'gold',   'fact_ventas',    COUNT(*), 112650  FROM gold.fact_ventas
UNION ALL SELECT 'gold',   'fact_pagos',     COUNT(*), 103886  FROM gold.fact_pagos
UNION ALL SELECT 'gold',   'fact_resenas',   COUNT(*), 98673   FROM gold.fact_resenas;   -- 1 reseña por pedido
GO

/* ----------------------------------------------------------------------------
   2. BRONCE: toda fila trae fecha/hora de carga (esperado: 0 filas sin fecha)
   ---------------------------------------------------------------------------- */
SELECT 'orders' AS tabla,
       SUM(CASE WHEN fecha_carga IS NULL THEN 1 ELSE 0 END) AS filas_sin_fecha_carga,
       MIN(fecha_carga) AS primera_carga,
       MAX(fecha_carga) AS ultima_carga
FROM bronze.orders;
GO

/* ----------------------------------------------------------------------------
   3. PLATA: sin duplicados en las llaves (esperado: 0 filas en cada consulta)
   ---------------------------------------------------------------------------- */
SELECT 'orders' AS tabla, order_id AS llave, COUNT(*) AS veces
FROM silver.orders GROUP BY order_id HAVING COUNT(*) > 1
UNION ALL
SELECT 'order_items', order_id + '|' + CAST(order_item_id AS VARCHAR(10)), COUNT(*)
FROM silver.order_items GROUP BY order_id, order_item_id HAVING COUNT(*) > 1
UNION ALL
SELECT 'order_reviews', review_id + '|' + order_id, COUNT(*)
FROM silver.order_reviews GROUP BY review_id, order_id HAVING COUNT(*) > 1
UNION ALL
SELECT 'products', product_id, COUNT(*)
FROM silver.products GROUP BY product_id HAVING COUNT(*) > 1;
GO

/* PLATA: nulos que deben haber sido tratados (esperado: todo en 0) */
SELECT
    (SELECT COUNT(*) FROM silver.products      WHERE product_category_name IS NULL)                 AS productos_sin_categoria_null,
    (SELECT COUNT(*) FROM silver.order_reviews WHERE review_comment_message IS NULL)                AS resenas_mensaje_null,
    (SELECT COUNT(*) FROM silver.customers     WHERE city IS NULL OR state IS NULL)                 AS clientes_sin_ciudad_estado,
    (SELECT COUNT(*) FROM silver.geolocation   WHERE lat NOT BETWEEN -34 AND 6)                     AS geo_fuera_de_brasil;
GO

/* PLATA: nulos que se dejan a propósito (informativo) */
SELECT
    SUM(CASE WHEN order_approved_at IS NULL            THEN 1 ELSE 0 END) AS sin_aprobacion,          -- 160
    SUM(CASE WHEN order_delivered_carrier_date IS NULL THEN 1 ELSE 0 END) AS sin_entrega_transportista, -- 1783
    SUM(CASE WHEN order_delivered_customer_date IS NULL THEN 1 ELSE 0 END) AS sin_entrega_cliente       -- 2965
FROM silver.orders;
GO

/* ----------------------------------------------------------------------------
   4. CONCILIACIÓN DE MONTOS ENTRE CAPAS
      Los tres valores de cada bloque deben ser IGUALES.
   ---------------------------------------------------------------------------- */
SELECT 'bronze.order_items' AS origen, ROUND(SUM(TRY_CAST(price AS FLOAT)), 2) AS total_precio FROM bronze.order_items     -- 13,591,643.70
UNION ALL SELECT 'silver.order_items', ROUND(SUM(price), 2)  FROM silver.order_items
UNION ALL SELECT 'gold.fact_ventas',   ROUND(SUM(precio), 2) FROM gold.fact_ventas;

SELECT 'bronze.order_payments' AS origen, ROUND(SUM(TRY_CAST(payment_value AS FLOAT)), 2) AS total_pagado FROM bronze.order_payments  -- 16,008,872.12
UNION ALL SELECT 'silver.order_payments', ROUND(SUM(payment_value), 2) FROM silver.order_payments
UNION ALL SELECT 'gold.fact_pagos',       ROUND(SUM(valor_pago), 2)    FROM gold.fact_pagos;
GO

/* ----------------------------------------------------------------------------
   5. KPI DE NEGOCIO (esperado con Olist: ingresos válidos = 13,494,400.74)
   ---------------------------------------------------------------------------- */
SELECT
    COUNT(DISTINCT order_id)  AS pedidos_validos,      -- 98,199
    COUNT(*)                  AS items_validos,        -- 112,101
    ROUND(SUM(precio), 2)     AS ingresos_validos,     -- 13,494,400.74
    ROUND(SUM(flete), 2)      AS flete_valido
FROM gold.fact_ventas
WHERE es_venta_valida = 1;
GO

/* ----------------------------------------------------------------------------
   6. PRUEBAS RÁPIDAS DE LAS VISTAS DE NEGOCIO
   ---------------------------------------------------------------------------- */
SELECT TOP 10 * FROM gold.vw_top_categorias    ORDER BY ranking;
SELECT        * FROM gold.vw_ventas_mensuales  ORDER BY anio, mes;
SELECT        * FROM gold.vw_metodos_pago      ORDER BY valor_total DESC;
SELECT TOP 10 * FROM gold.vw_entregas_por_estado ORDER BY pedidos_entregados DESC;
SELECT TOP 10 * FROM gold.vw_top_vendedores    ORDER BY ranking;
SELECT        * FROM gold.vw_satisfaccion_mensual ORDER BY anio_mes;
GO
