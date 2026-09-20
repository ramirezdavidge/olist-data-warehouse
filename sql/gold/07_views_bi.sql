/*
===============================================================================
07 - CAPA ORO: vistas de negocio (KPIs listos para el dashboard)
===============================================================================

===============================================================================
*/

USE OlistDW;
GO

CREATE OR ALTER VIEW gold.vw_ventas_mensuales AS
SELECT
    d.anio,
    d.mes,
    d.anio_mes,
    COUNT(DISTINCT v.order_id)                                   AS pedidos,
    COUNT(*)                                                     AS items_vendidos,
    ROUND(SUM(v.precio), 2)                                      AS ingresos,
    ROUND(SUM(v.flete), 2)                                       AS flete_total,
    ROUND(SUM(v.precio) / COUNT(DISTINCT v.order_id), 2)         AS ticket_promedio
FROM gold.fact_ventas AS v
JOIN gold.dim_fecha   AS d ON d.fecha_key = v.fecha_compra_key
WHERE v.es_venta_valida = 1
GROUP BY d.anio, d.mes, d.anio_mes;
GO

CREATE OR ALTER VIEW gold.vw_top_categorias AS
SELECT
    p.categoria_en                                   AS categoria,
    COUNT(*)                                         AS unidades,
    COUNT(DISTINCT v.order_id)                       AS pedidos,
    ROUND(SUM(v.precio), 2)                          AS ingresos,
    ROUND(AVG(v.precio), 2)                          AS precio_promedio,
    RANK() OVER (ORDER BY SUM(v.precio) DESC)        AS ranking
FROM gold.fact_ventas  AS v
JOIN gold.dim_producto AS p ON p.producto_key = v.producto_key
WHERE v.es_venta_valida = 1
GROUP BY p.categoria_en;
GO

CREATE OR ALTER VIEW gold.vw_top_vendedores AS
SELECT
    s.seller_id,
    s.ciudad,
    s.estado,
    s.region,
    COUNT(DISTINCT v.order_id)                                AS pedidos,
    COUNT(*)                                                  AS items_vendidos,
    ROUND(SUM(v.precio), 2)                                   AS ingresos,
    ROUND(100.0 * AVG(CAST(v.entregado_a_tiempo AS FLOAT)), 1) AS pct_entregas_a_tiempo,
    RANK() OVER (ORDER BY SUM(v.precio) DESC)                 AS ranking
FROM gold.fact_ventas  AS v
JOIN gold.dim_vendedor AS s ON s.vendedor_key = v.vendedor_key
WHERE v.es_venta_valida = 1
GROUP BY s.seller_id, s.ciudad, s.estado, s.region;
GO

CREATE OR ALTER VIEW gold.vw_entregas_por_estado AS
WITH pedidos_entregados AS (
    -- una fila por pedido (los ítems de un mismo pedido comparten fechas)
    SELECT DISTINCT v.order_id, v.cliente_key, v.dias_entrega_real, v.dias_retraso, v.entregado_a_tiempo
    FROM gold.fact_ventas AS v
    WHERE v.estado_pedido = 'delivered'
      AND v.entregado_a_tiempo IS NOT NULL
)
SELECT
    c.region,
    c.estado,
    COUNT(*)                                                      AS pedidos_entregados,
    ROUND(AVG(CAST(p.dias_entrega_real AS FLOAT)), 1)             AS dias_entrega_promedio,
    ROUND(AVG(CAST(p.dias_retraso AS FLOAT)), 1)                  AS dias_retraso_promedio,
    ROUND(100.0 * AVG(CAST(p.entregado_a_tiempo AS FLOAT)), 1)    AS pct_entregas_a_tiempo
FROM pedidos_entregados AS p
JOIN gold.dim_cliente   AS c ON c.cliente_key = p.cliente_key
GROUP BY c.region, c.estado;
GO

CREATE OR ALTER VIEW gold.vw_metodos_pago AS
SELECT
    t.descripcion                                           AS tipo_pago,
    COUNT(*)                                                AS num_pagos,
    ROUND(SUM(p.valor_pago), 2)                             AS valor_total,
    ROUND(100.0 * SUM(p.valor_pago) / SUM(SUM(p.valor_pago)) OVER (), 1) AS pct_del_total,
    ROUND(AVG(CAST(p.cuotas AS FLOAT)), 1)                  AS cuotas_promedio
FROM gold.fact_pagos    AS p
JOIN gold.dim_tipo_pago AS t ON t.tipo_pago_key = p.tipo_pago_key
GROUP BY t.descripcion;
GO

CREATE OR ALTER VIEW gold.vw_satisfaccion_mensual AS
SELECT
    d.anio_mes,
    COUNT(*)                                                              AS resenas,
    ROUND(AVG(CAST(r.review_score AS FLOAT)), 2)                          AS score_promedio,
    ROUND(100.0 * AVG(CASE WHEN r.review_score = 5  THEN 1.0 ELSE 0 END), 1) AS pct_5_estrellas,
    ROUND(100.0 * AVG(CASE WHEN r.review_score <= 2 THEN 1.0 ELSE 0 END), 1) AS pct_negativas
FROM gold.fact_resenas AS r
JOIN gold.dim_fecha    AS d ON d.fecha_key = r.fecha_resena_key
GROUP BY d.anio_mes;
GO
