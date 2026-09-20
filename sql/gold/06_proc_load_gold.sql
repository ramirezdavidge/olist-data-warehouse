/*
===============================================================================
06 - CAPA ORO: procedimiento de carga (Plata -> Modelo estrella)
===============================================================================

===============================================================================
*/

USE OlistDW;
GO

CREATE OR ALTER PROCEDURE gold.usp_load_gold
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @inicio DATETIME2 = SYSDATETIME();

    BEGIN TRY
        PRINT '================================================';
        PRINT ' CARGA CAPA ORO (MODELO ESTRELLA)';
        PRINT '================================================';

        -- Limpieza: hechos primero (TRUNCATE), dimensiones después (DELETE por las FK)
        TRUNCATE TABLE gold.fact_resenas;
        TRUNCATE TABLE gold.fact_pagos;
        TRUNCATE TABLE gold.fact_ventas;
        DELETE FROM gold.dim_tipo_pago;
        DELETE FROM gold.dim_vendedor;
        DELETE FROM gold.dim_producto;
        DELETE FROM gold.dim_cliente;
        DELETE FROM gold.dim_fecha;

        ------------------------------------------------------------------
        -- Tablas temporales de apoyo
        ------------------------------------------------------------------
        IF OBJECT_ID('tempdb..#estado_region') IS NOT NULL DROP TABLE #estado_region;
        SELECT v.estado, v.region
        INTO #estado_region
        FROM (VALUES
            ('AC','Norte'),('AM','Norte'),('AP','Norte'),('PA','Norte'),('RO','Norte'),('RR','Norte'),('TO','Norte'),
            ('AL','Nordeste'),('BA','Nordeste'),('CE','Nordeste'),('MA','Nordeste'),('PB','Nordeste'),
            ('PE','Nordeste'),('PI','Nordeste'),('RN','Nordeste'),('SE','Nordeste'),
            ('DF','Centro-Oeste'),('GO','Centro-Oeste'),('MS','Centro-Oeste'),('MT','Centro-Oeste'),
            ('ES','Sudeste'),('MG','Sudeste'),('RJ','Sudeste'),('SP','Sudeste'),
            ('PR','Sur'),('RS','Sur'),('SC','Sur')
        ) AS v(estado, region);

        IF OBJECT_ID('tempdb..#geo_zip') IS NOT NULL DROP TABLE #geo_zip;
        SELECT zip_code_prefix, AVG(lat) AS lat, AVG(lng) AS lng
        INTO #geo_zip
        FROM silver.geolocation
        GROUP BY zip_code_prefix;

        ------------------------------------------------------------------
        -- dim_fecha  (2016-01-01 a 2018-12-31 cubre compras, entregas y reseñas)
        ------------------------------------------------------------------
        ;WITH fechas AS (
            SELECT CAST('2016-01-01' AS DATE) AS f
            UNION ALL
            SELECT DATEADD(DAY, 1, f) FROM fechas WHERE f < '2018-12-31'
        )
        INSERT INTO gold.dim_fecha (
            fecha_key, fecha, anio, trimestre, mes, nombre_mes, anio_mes,
            dia, dia_semana, nombre_dia, es_fin_de_semana)
        SELECT
            YEAR(f) * 10000 + MONTH(f) * 100 + DAY(f),
            f,
            YEAR(f),
            DATEPART(QUARTER, f),
            MONTH(f),
            CHOOSE(MONTH(f), 'Enero','Febrero','Marzo','Abril','Mayo','Junio',
                             'Julio','Agosto','Septiembre','Octubre','Noviembre','Diciembre'),
            CONCAT(YEAR(f), '-', RIGHT('0' + CAST(MONTH(f) AS VARCHAR(2)), 2)),
            DAY(f),
            (DATEDIFF(DAY, '19000101', f) % 7) + 1,          -- 1900-01-01 fue lunes
            CHOOSE((DATEDIFF(DAY, '19000101', f) % 7) + 1,
                   'Lunes','Martes','Miércoles','Jueves','Viernes','Sábado','Domingo'),
            CASE WHEN (DATEDIFF(DAY, '19000101', f) % 7) + 1 IN (6, 7) THEN 1 ELSE 0 END
        FROM fechas
        OPTION (MAXRECURSION 2000);
        PRINT '   gold.dim_fecha     : ' + CAST(@@ROWCOUNT AS NVARCHAR(20)) + ' filas';

        ------------------------------------------------------------------
        -- dim_cliente  (1 fila por customer_unique_id)
        ------------------------------------------------------------------
        ;WITH pedidos AS (
            SELECT
                c.customer_unique_id, c.zip_code_prefix, c.city, c.state,
                o.order_id, o.order_purchase_timestamp,
                ROW_NUMBER() OVER (PARTITION BY c.customer_unique_id
                                   ORDER BY o.order_purchase_timestamp DESC, o.order_id) AS rn
            FROM silver.customers AS c
            JOIN silver.orders    AS o ON o.customer_id = c.customer_id
        ),
        resumen AS (
            SELECT customer_unique_id,
                   MIN(CAST(order_purchase_timestamp AS DATE)) AS primera_compra,
                   MAX(CAST(order_purchase_timestamp AS DATE)) AS ultima_compra,
                   COUNT(DISTINCT order_id)                    AS total_pedidos
            FROM pedidos
            GROUP BY customer_unique_id
        )
        INSERT INTO gold.dim_cliente (
            cliente_key, customer_unique_id, ciudad, estado, region, zip_code_prefix,
            latitud, longitud, primera_compra, ultima_compra, total_pedidos, tipo_cliente)
        SELECT
            ROW_NUMBER() OVER (ORDER BY p.customer_unique_id),
            p.customer_unique_id,
            COALESCE(p.city, N'desconocida'),
            COALESCE(p.state, 'NA'),
            COALESCE(er.region, 'Desconocida'),
            p.zip_code_prefix,
            g.lat, g.lng,
            r.primera_compra, r.ultima_compra, r.total_pedidos,
            CASE WHEN r.total_pedidos >= 2 THEN 'Recurrente' ELSE 'Nuevo' END
        FROM pedidos AS p
        JOIN resumen AS r            ON r.customer_unique_id = p.customer_unique_id
        LEFT JOIN #estado_region er  ON er.estado = p.state
        LEFT JOIN #geo_zip g         ON g.zip_code_prefix = p.zip_code_prefix
        WHERE p.rn = 1;
        PRINT '   gold.dim_cliente   : ' + CAST(@@ROWCOUNT AS NVARCHAR(20)) + ' filas';

        ------------------------------------------------------------------
        -- dim_producto
        ------------------------------------------------------------------
        INSERT INTO gold.dim_producto (
            producto_key, product_id, categoria_pt, categoria_en, fotos_qty,
            peso_g, largo_cm, alto_cm, ancho_cm, volumen_cm3, rango_peso)
        SELECT
            ROW_NUMBER() OVER (ORDER BY p.product_id),
            p.product_id,
            p.product_category_name,
            COALESCE(t.product_category_name_english, p.product_category_name),
            p.product_photos_qty,
            p.product_weight_g, p.product_length_cm, p.product_height_cm, p.product_width_cm,
            p.product_length_cm * p.product_height_cm * p.product_width_cm,
            CASE
                WHEN p.product_weight_g IS NULL OR p.product_weight_g = 0 THEN N'Sin dato'
                WHEN p.product_weight_g <  500                             THEN N'Ligero (<500 g)'
                WHEN p.product_weight_g <= 2000                            THEN N'Medio (500 g - 2 kg)'
                ELSE                                                            N'Pesado (>2 kg)'
            END
        FROM silver.products AS p
        LEFT JOIN silver.product_category_translation AS t
               ON t.product_category_name = p.product_category_name;
        PRINT '   gold.dim_producto  : ' + CAST(@@ROWCOUNT AS NVARCHAR(20)) + ' filas';

        ------------------------------------------------------------------
        -- dim_vendedor
        ------------------------------------------------------------------
        INSERT INTO gold.dim_vendedor (
            vendedor_key, seller_id, ciudad, estado, region, zip_code_prefix, latitud, longitud)
        SELECT
            ROW_NUMBER() OVER (ORDER BY s.seller_id),
            s.seller_id,
            COALESCE(s.city, N'desconocida'),
            COALESCE(s.state, 'NA'),
            COALESCE(er.region, 'Desconocida'),
            s.zip_code_prefix,
            g.lat, g.lng
        FROM silver.sellers AS s
        LEFT JOIN #estado_region er ON er.estado = s.state
        LEFT JOIN #geo_zip g        ON g.zip_code_prefix = s.zip_code_prefix;
        PRINT '   gold.dim_vendedor  : ' + CAST(@@ROWCOUNT AS NVARCHAR(20)) + ' filas';

        ------------------------------------------------------------------
        -- dim_tipo_pago
        ------------------------------------------------------------------
        INSERT INTO gold.dim_tipo_pago (tipo_pago_key, payment_type, descripcion)
        SELECT
            ROW_NUMBER() OVER (ORDER BY t.payment_type),
            t.payment_type,
            CASE t.payment_type
                WHEN 'credit_card' THEN N'Tarjeta de crédito'
                WHEN 'debit_card'  THEN N'Tarjeta de débito'
                WHEN 'boleto'      THEN N'Boleto bancario'
                WHEN 'voucher'     THEN N'Voucher'
                WHEN 'not_defined' THEN N'No definido'
                ELSE N'Otro'
            END
        FROM (SELECT DISTINCT payment_type FROM silver.order_payments) AS t;
        PRINT '   gold.dim_tipo_pago : ' + CAST(@@ROWCOUNT AS NVARCHAR(20)) + ' filas';

        ------------------------------------------------------------------
        -- fact_ventas  (1 fila por ítem de pedido)
        ------------------------------------------------------------------
        INSERT INTO gold.fact_ventas (
            venta_key, order_id, order_item_id, estado_pedido,
            fecha_compra_key, fecha_entrega_estimada_key, fecha_entrega_real_key,
            cliente_key, producto_key, vendedor_key,
            precio, flete, total_item,
            dias_entrega_real, dias_entrega_estimada, dias_retraso,
            entregado_a_tiempo, es_venta_valida)
        SELECT
            ROW_NUMBER() OVER (ORDER BY i.order_id, i.order_item_id),
            i.order_id, i.order_item_id, o.order_status,
            CONVERT(INT, CONVERT(CHAR(8), o.order_purchase_timestamp,      112)),
            CONVERT(INT, CONVERT(CHAR(8), o.order_estimated_delivery_date, 112)),
            CONVERT(INT, CONVERT(CHAR(8), o.order_delivered_customer_date, 112)),
            dc.cliente_key, dp.producto_key, dv.vendedor_key,
            i.price,
            i.freight_value,
            ROUND(i.price + i.freight_value, 2),
            DATEDIFF(DAY, CAST(o.order_purchase_timestamp AS DATE), CAST(o.order_delivered_customer_date AS DATE)),
            DATEDIFF(DAY, CAST(o.order_purchase_timestamp AS DATE), o.order_estimated_delivery_date),
            CASE
                WHEN o.order_delivered_customer_date IS NULL THEN NULL
                WHEN CAST(o.order_delivered_customer_date AS DATE) > o.order_estimated_delivery_date
                     THEN DATEDIFF(DAY, o.order_estimated_delivery_date, CAST(o.order_delivered_customer_date AS DATE))
                ELSE 0
            END,
            CASE
                WHEN o.order_delivered_customer_date IS NULL THEN NULL
                WHEN CAST(o.order_delivered_customer_date AS DATE) <= o.order_estimated_delivery_date THEN 1
                ELSE 0
            END,
            CASE WHEN o.order_status IN ('canceled', 'unavailable') THEN 0 ELSE 1 END
        FROM silver.order_items AS i
        JOIN silver.orders      AS o  ON o.order_id    = i.order_id
        JOIN silver.customers   AS c  ON c.customer_id = o.customer_id
        JOIN gold.dim_cliente   AS dc ON dc.customer_unique_id = c.customer_unique_id
        JOIN gold.dim_producto  AS dp ON dp.product_id = i.product_id
        JOIN gold.dim_vendedor  AS dv ON dv.seller_id  = i.seller_id;
        PRINT '   gold.fact_ventas   : ' + CAST(@@ROWCOUNT AS NVARCHAR(20)) + ' filas';

        ------------------------------------------------------------------
        -- fact_pagos  (1 fila por pago)
        ------------------------------------------------------------------
        INSERT INTO gold.fact_pagos (
            pago_key, order_id, payment_sequential, fecha_compra_key,
            cliente_key, tipo_pago_key, cuotas, valor_pago)
        SELECT
            ROW_NUMBER() OVER (ORDER BY p.order_id, p.payment_sequential),
            p.order_id, p.payment_sequential,
            CONVERT(INT, CONVERT(CHAR(8), o.order_purchase_timestamp, 112)),
            dc.cliente_key, tp.tipo_pago_key,
            p.payment_installments, p.payment_value
        FROM silver.order_payments AS p
        JOIN silver.orders         AS o  ON o.order_id    = p.order_id
        JOIN silver.customers      AS c  ON c.customer_id = o.customer_id
        JOIN gold.dim_cliente      AS dc ON dc.customer_unique_id = c.customer_unique_id
        JOIN gold.dim_tipo_pago    AS tp ON tp.payment_type = p.payment_type;
        PRINT '   gold.fact_pagos    : ' + CAST(@@ROWCOUNT AS NVARCHAR(20)) + ' filas';

        ------------------------------------------------------------------
        -- fact_resenas  (1 reseña por pedido: la más reciente)
        ------------------------------------------------------------------
        ;WITH ultima AS (
            SELECT r.*,
                   ROW_NUMBER() OVER (PARTITION BY r.order_id
                                      ORDER BY r.review_answer_timestamp DESC, r.review_id) AS rn
            FROM silver.order_reviews AS r
        )
        INSERT INTO gold.fact_resenas (
            resena_key, review_id, order_id, fecha_resena_key, cliente_key,
            review_score, tiene_comentario, dias_respuesta)
        SELECT
            ROW_NUMBER() OVER (ORDER BY u.order_id),
            u.review_id, u.order_id,
            CONVERT(INT, CONVERT(CHAR(8), u.review_creation_date, 112)),
            dc.cliente_key,
            u.review_score, u.tiene_comentario,
            DATEDIFF(DAY, u.review_creation_date, CAST(u.review_answer_timestamp AS DATE))
        FROM ultima AS u
        JOIN silver.orders    AS o  ON o.order_id    = u.order_id
        JOIN silver.customers AS c  ON c.customer_id = o.customer_id
        JOIN gold.dim_cliente AS dc ON dc.customer_unique_id = c.customer_unique_id
        WHERE u.rn = 1 AND u.review_creation_date IS NOT NULL;
        PRINT '   gold.fact_resenas  : ' + CAST(@@ROWCOUNT AS NVARCHAR(20)) + ' filas';

        PRINT '------------------------------------------------';
        PRINT ' Oro cargada en ' + CAST(DATEDIFF(SECOND, @inicio, SYSDATETIME()) AS NVARCHAR(20)) + ' segundos';
        PRINT '================================================';
    END TRY
    BEGIN CATCH
        PRINT '*** ERROR CARGANDO ORO ***';
        PRINT 'Mensaje : ' + ERROR_MESSAGE();
        PRINT 'Número  : ' + CAST(ERROR_NUMBER() AS NVARCHAR(20));
        THROW;
    END CATCH;
END;
GO
