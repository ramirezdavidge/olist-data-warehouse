/*
===============================================================================
04 - CAPA PLATA: procedimiento de carga (Bronce -> Plata)
===============================================================================
silver.usp_load_silver lee SOLO de Bronce y aplica estas reglas:

DUPLICADOS
  * Se define la llave natural de cada tabla y se conserva 1 registro por llave
    (ROW_NUMBER() ... ORDER BY fecha_carga DESC).
  * geolocation: tiene ~26% de filas idénticas -> se agrupan.
  * order_reviews: llave (review_id, order_id); si se repite, gana la respuesta
    más reciente.

NULOS
  * Texto vacío ('') se convierte en NULL y luego se aplica la regla:
      products.product_category_name nulo      -> 'sin_categoria'
      products.name/description/photos nulos   -> 0   (no hay dato registrado)
      products.peso/dimensiones nulas          -> se dejan NULL (no se inventan)
      order_reviews título/mensaje nulos       -> 'Sin título' / 'Sin comentario'
                                                  + columna tiene_comentario (BIT)
      orders.order_approved_at / *_delivered_* -> se dejan NULL: son nulos
        LEGÍTIMOS (pedido cancelado, en camino, no aprobado, etc.)

TIPOS
  * Fechas     : DATE (fecha estimada, fecha de reseña) o DATETIME2 (con hora)
  * Montos     : FLOAT     * Cantidades / secuenciales : INT
  * TRY_CAST / TRY_CONVERT: si un valor no se puede convertir queda NULL y el
    registro se descarta cuando el campo es obligatorio.

TEXTO
  * Ciudades en minúsculas, sin acentos y sin espacios sobrantes.
  * Estados en MAYÚSCULAS (2 letras). CP con 5 dígitos (relleno con ceros).

FILTROS DE CALIDAD
  * geolocation: se descartan coordenadas fuera de Brasil (42 filas).
  * order_items: se descartan precios nulos o negativos.
  * order_reviews: se descartan puntajes fuera de 1-5.
===============================================================================
*/

USE OlistDW;
GO

CREATE OR ALTER PROCEDURE silver.usp_load_silver
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @inicio DATETIME2 = SYSDATETIME(),
            @n_traduccion INT;

    BEGIN TRY
        PRINT '================================================';
        PRINT ' CARGA CAPA PLATA';
        PRINT '================================================';

        ------------------------------------------------------------------
        -- customers
        ------------------------------------------------------------------
        TRUNCATE TABLE silver.customers;

        ;WITH limpio AS (
            SELECT
                NULLIF(LTRIM(RTRIM(customer_id)), '')         AS customer_id,
                NULLIF(LTRIM(RTRIM(customer_unique_id)), '')  AS customer_unique_id,
                RIGHT('00000' + NULLIF(LTRIM(RTRIM(customer_zip_code_prefix)), ''), 5) AS zip_code_prefix,
                silver.fn_limpiar_texto(customer_city)        AS city,
                UPPER(NULLIF(LTRIM(RTRIM(customer_state)), '')) AS state,
                fecha_carga
            FROM bronze.customers
        ),
        dedup AS (
            SELECT *, ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY fecha_carga DESC) AS rn
            FROM limpio
        )
        INSERT INTO silver.customers (customer_id, customer_unique_id, zip_code_prefix, city, state, dwh_fecha_carga_bronze)
        SELECT customer_id, customer_unique_id, zip_code_prefix, city, state, fecha_carga
        FROM dedup
        WHERE rn = 1 AND customer_id IS NOT NULL AND customer_unique_id IS NOT NULL;
        PRINT '   silver.customers                    : ' + CAST(@@ROWCOUNT AS NVARCHAR(20)) + ' filas';

        ------------------------------------------------------------------
        -- geolocation  (duplicados exactos + coordenadas fuera de Brasil)
        ------------------------------------------------------------------
        TRUNCATE TABLE silver.geolocation;

        INSERT INTO silver.geolocation (zip_code_prefix, lat, lng, city, state, dwh_fecha_carga_bronze)
        SELECT zip_code_prefix, lat, lng, city, state, MAX(fecha_carga)
        FROM (
            SELECT
                RIGHT('00000' + NULLIF(LTRIM(RTRIM(geolocation_zip_code_prefix)), ''), 5) AS zip_code_prefix,
                TRY_CAST(geolocation_lat AS FLOAT)                AS lat,
                TRY_CAST(geolocation_lng AS FLOAT)                AS lng,
                silver.fn_limpiar_texto(geolocation_city)         AS city,
                UPPER(NULLIF(LTRIM(RTRIM(geolocation_state)), '')) AS state,
                fecha_carga
            FROM bronze.geolocation
        ) AS g
        WHERE zip_code_prefix IS NOT NULL
          AND lat BETWEEN -34 AND 6          -- caja aproximada de Brasil
          AND lng BETWEEN -74 AND -34
        GROUP BY zip_code_prefix, lat, lng, city, state;
        PRINT '   silver.geolocation                  : ' + CAST(@@ROWCOUNT AS NVARCHAR(20)) + ' filas';

        ------------------------------------------------------------------
        -- orders
        ------------------------------------------------------------------
        TRUNCATE TABLE silver.orders;

        ;WITH limpio AS (
            SELECT
                NULLIF(LTRIM(RTRIM(order_id)), '')     AS order_id,
                NULLIF(LTRIM(RTRIM(customer_id)), '')  AS customer_id,
                LOWER(NULLIF(LTRIM(RTRIM(order_status)), '')) AS order_status,
                TRY_CONVERT(DATETIME2(0), NULLIF(LTRIM(RTRIM(order_purchase_timestamp)), ''))      AS order_purchase_timestamp,
                TRY_CONVERT(DATETIME2(0), NULLIF(LTRIM(RTRIM(order_approved_at)), ''))             AS order_approved_at,
                TRY_CONVERT(DATETIME2(0), NULLIF(LTRIM(RTRIM(order_delivered_carrier_date)), ''))  AS order_delivered_carrier_date,
                TRY_CONVERT(DATETIME2(0), NULLIF(LTRIM(RTRIM(order_delivered_customer_date)), '')) AS order_delivered_customer_date,
                TRY_CONVERT(DATE,         NULLIF(LTRIM(RTRIM(order_estimated_delivery_date)), ''))  AS order_estimated_delivery_date,
                fecha_carga
            FROM bronze.orders
        ),
        dedup AS (
            SELECT *, ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY fecha_carga DESC) AS rn
            FROM limpio
        )
        INSERT INTO silver.orders (
            order_id, customer_id, order_status, order_purchase_timestamp, order_approved_at,
            order_delivered_carrier_date, order_delivered_customer_date, order_estimated_delivery_date,
            dwh_fecha_carga_bronze)
        SELECT
            order_id, customer_id, order_status, order_purchase_timestamp, order_approved_at,
            order_delivered_carrier_date, order_delivered_customer_date, order_estimated_delivery_date,
            fecha_carga
        FROM dedup
        WHERE rn = 1
          AND order_id IS NOT NULL AND customer_id IS NOT NULL
          AND order_status IS NOT NULL AND order_purchase_timestamp IS NOT NULL;
        PRINT '   silver.orders                       : ' + CAST(@@ROWCOUNT AS NVARCHAR(20)) + ' filas';

        ------------------------------------------------------------------
        -- order_items
        ------------------------------------------------------------------
        TRUNCATE TABLE silver.order_items;

        ;WITH limpio AS (
            SELECT
                NULLIF(LTRIM(RTRIM(order_id)), '')    AS order_id,
                TRY_CAST(NULLIF(LTRIM(RTRIM(order_item_id)), '') AS INT) AS order_item_id,
                NULLIF(LTRIM(RTRIM(product_id)), '')  AS product_id,
                NULLIF(LTRIM(RTRIM(seller_id)), '')   AS seller_id,
                TRY_CONVERT(DATETIME2(0), NULLIF(LTRIM(RTRIM(shipping_limit_date)), '')) AS shipping_limit_date,
                TRY_CAST(NULLIF(LTRIM(RTRIM(price)), '')         AS FLOAT) AS price,
                TRY_CAST(NULLIF(LTRIM(RTRIM(freight_value)), '') AS FLOAT) AS freight_value,
                fecha_carga
            FROM bronze.order_items
        ),
        dedup AS (
            SELECT *, ROW_NUMBER() OVER (PARTITION BY order_id, order_item_id ORDER BY fecha_carga DESC) AS rn
            FROM limpio
        )
        INSERT INTO silver.order_items (
            order_id, order_item_id, product_id, seller_id, shipping_limit_date,
            price, freight_value, dwh_fecha_carga_bronze)
        SELECT
            order_id, order_item_id, product_id, seller_id, shipping_limit_date,
            price, COALESCE(freight_value, 0), fecha_carga     -- flete nulo = 0
        FROM dedup
        WHERE rn = 1
          AND order_id IS NOT NULL AND order_item_id IS NOT NULL
          AND product_id IS NOT NULL AND seller_id IS NOT NULL
          AND price IS NOT NULL AND price >= 0;
        PRINT '   silver.order_items                  : ' + CAST(@@ROWCOUNT AS NVARCHAR(20)) + ' filas';

        ------------------------------------------------------------------
        -- order_payments
        ------------------------------------------------------------------
        TRUNCATE TABLE silver.order_payments;

        ;WITH limpio AS (
            SELECT
                NULLIF(LTRIM(RTRIM(order_id)), '') AS order_id,
                TRY_CAST(NULLIF(LTRIM(RTRIM(payment_sequential)), '')   AS INT)   AS payment_sequential,
                LOWER(COALESCE(NULLIF(LTRIM(RTRIM(payment_type)), ''), 'not_defined')) AS payment_type,
                TRY_CAST(NULLIF(LTRIM(RTRIM(payment_installments)), '') AS INT)   AS payment_installments,
                TRY_CAST(NULLIF(LTRIM(RTRIM(payment_value)), '')        AS FLOAT) AS payment_value,
                fecha_carga
            FROM bronze.order_payments
        ),
        dedup AS (
            SELECT *, ROW_NUMBER() OVER (PARTITION BY order_id, payment_sequential ORDER BY fecha_carga DESC) AS rn
            FROM limpio
        )
        INSERT INTO silver.order_payments (
            order_id, payment_sequential, payment_type, payment_installments, payment_value, dwh_fecha_carga_bronze)
        SELECT order_id, payment_sequential, payment_type, COALESCE(payment_installments, 1), payment_value, fecha_carga
        FROM dedup
        WHERE rn = 1
          AND order_id IS NOT NULL AND payment_sequential IS NOT NULL
          AND payment_value IS NOT NULL AND payment_value >= 0;
        PRINT '   silver.order_payments               : ' + CAST(@@ROWCOUNT AS NVARCHAR(20)) + ' filas';

        ------------------------------------------------------------------
        -- order_reviews
        ------------------------------------------------------------------
        TRUNCATE TABLE silver.order_reviews;

        ;WITH limpio AS (
            SELECT
                NULLIF(LTRIM(RTRIM(review_id)), '')  AS review_id,
                NULLIF(LTRIM(RTRIM(order_id)), '')   AS order_id,
                TRY_CAST(NULLIF(LTRIM(RTRIM(review_score)), '') AS INT) AS review_score,
                NULLIF(LTRIM(RTRIM(review_comment_title)), '')   AS titulo,
                NULLIF(LTRIM(RTRIM(review_comment_message)), '') AS mensaje,
                TRY_CONVERT(DATE,         NULLIF(LTRIM(RTRIM(review_creation_date)), ''))    AS review_creation_date,
                TRY_CONVERT(DATETIME2(0), NULLIF(LTRIM(RTRIM(review_answer_timestamp)), '')) AS review_answer_timestamp,
                fecha_carga
            FROM bronze.order_reviews
        ),
        dedup AS (
            SELECT *,
                   ROW_NUMBER() OVER (PARTITION BY review_id, order_id
                                      ORDER BY review_answer_timestamp DESC, fecha_carga DESC) AS rn
            FROM limpio
        )
        INSERT INTO silver.order_reviews (
            review_id, order_id, review_score, review_comment_title, review_comment_message,
            tiene_comentario, review_creation_date, review_answer_timestamp, dwh_fecha_carga_bronze)
        SELECT
            review_id, order_id, review_score,
            COALESCE(titulo,  N'Sin título'),
            COALESCE(mensaje, N'Sin comentario'),
            CASE WHEN mensaje IS NULL THEN 0 ELSE 1 END,
            review_creation_date, review_answer_timestamp, fecha_carga
        FROM dedup
        WHERE rn = 1
          AND review_id IS NOT NULL AND order_id IS NOT NULL
          AND review_score BETWEEN 1 AND 5;
        PRINT '   silver.order_reviews                : ' + CAST(@@ROWCOUNT AS NVARCHAR(20)) + ' filas';

        ------------------------------------------------------------------
        -- products
        ------------------------------------------------------------------
        TRUNCATE TABLE silver.products;

        ;WITH limpio AS (
            SELECT
                NULLIF(LTRIM(RTRIM(product_id)), '') AS product_id,
                LOWER(NULLIF(LTRIM(RTRIM(product_category_name)), ''))  AS product_category_name,
                TRY_CAST(TRY_CAST(NULLIF(LTRIM(RTRIM(product_name_lenght)), '')        AS DECIMAL(18,2)) AS INT) AS product_name_length,
                TRY_CAST(TRY_CAST(NULLIF(LTRIM(RTRIM(product_description_lenght)), '') AS DECIMAL(18,2)) AS INT) AS product_description_length,
                TRY_CAST(TRY_CAST(NULLIF(LTRIM(RTRIM(product_photos_qty)), '')         AS DECIMAL(18,2)) AS INT) AS product_photos_qty,
                TRY_CAST(NULLIF(LTRIM(RTRIM(product_weight_g)), '')  AS FLOAT) AS product_weight_g,
                TRY_CAST(NULLIF(LTRIM(RTRIM(product_length_cm)), '') AS FLOAT) AS product_length_cm,
                TRY_CAST(NULLIF(LTRIM(RTRIM(product_height_cm)), '') AS FLOAT) AS product_height_cm,
                TRY_CAST(NULLIF(LTRIM(RTRIM(product_width_cm)), '')  AS FLOAT) AS product_width_cm,
                fecha_carga
            FROM bronze.products
        ),
        dedup AS (
            SELECT *, ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY fecha_carga DESC) AS rn
            FROM limpio
        )
        INSERT INTO silver.products (
            product_id, product_category_name, product_name_length, product_description_length,
            product_photos_qty, product_weight_g, product_length_cm, product_height_cm,
            product_width_cm, dwh_fecha_carga_bronze)
        SELECT
            product_id,
            COALESCE(product_category_name, 'sin_categoria'),
            COALESCE(product_name_length, 0),
            COALESCE(product_description_length, 0),
            COALESCE(product_photos_qty, 0),
            product_weight_g, product_length_cm, product_height_cm, product_width_cm,
            fecha_carga
        FROM dedup
        WHERE rn = 1 AND product_id IS NOT NULL;
        PRINT '   silver.products                     : ' + CAST(@@ROWCOUNT AS NVARCHAR(20)) + ' filas';

        ------------------------------------------------------------------
        -- sellers
        ------------------------------------------------------------------
        TRUNCATE TABLE silver.sellers;

        ;WITH limpio AS (
            SELECT
                NULLIF(LTRIM(RTRIM(seller_id)), '') AS seller_id,
                RIGHT('00000' + NULLIF(LTRIM(RTRIM(seller_zip_code_prefix)), ''), 5) AS zip_code_prefix,
                silver.fn_limpiar_texto(seller_city)               AS city,
                UPPER(NULLIF(LTRIM(RTRIM(seller_state)), ''))      AS state,
                fecha_carga
            FROM bronze.sellers
        ),
        dedup AS (
            SELECT *, ROW_NUMBER() OVER (PARTITION BY seller_id ORDER BY fecha_carga DESC) AS rn
            FROM limpio
        )
        INSERT INTO silver.sellers (seller_id, zip_code_prefix, city, state, dwh_fecha_carga_bronze)
        SELECT seller_id, zip_code_prefix, city, state, fecha_carga
        FROM dedup
        WHERE rn = 1 AND seller_id IS NOT NULL;
        PRINT '   silver.sellers                      : ' + CAST(@@ROWCOUNT AS NVARCHAR(20)) + ' filas';

        ------------------------------------------------------------------
        -- product_category_translation
        ------------------------------------------------------------------
        TRUNCATE TABLE silver.product_category_translation;

        ;WITH limpio AS (
            SELECT
                LOWER(NULLIF(LTRIM(RTRIM(REPLACE(product_category_name, NCHAR(65279), N''))), '')) AS product_category_name,
                LOWER(NULLIF(LTRIM(RTRIM(product_category_name_english)), ''))                     AS product_category_name_english,
                fecha_carga
            FROM bronze.product_category_translation
        ),
        dedup AS (
            SELECT *, ROW_NUMBER() OVER (PARTITION BY product_category_name ORDER BY fecha_carga DESC) AS rn
            FROM limpio
        )
        INSERT INTO silver.product_category_translation (product_category_name, product_category_name_english, dwh_fecha_carga_bronze)
        SELECT product_category_name, product_category_name_english, fecha_carga
        FROM dedup
        WHERE rn = 1 AND product_category_name IS NOT NULL AND product_category_name_english IS NOT NULL;

        -- Categorías presentes en products pero ausentes en el archivo de traducción
        INSERT INTO silver.product_category_translation (product_category_name, product_category_name_english)
        SELECT v.pt, v.en
        FROM (VALUES
                ('pc_gamer', 'pc_gamer'),
                ('portateis_cozinha_e_preparadores_de_alimentos', 'portable_kitchen_food_preparers'),
                ('sin_categoria', 'uncategorized')
             ) AS v(pt, en)
        WHERE NOT EXISTS (SELECT 1 FROM silver.product_category_translation t WHERE t.product_category_name = v.pt);
        SELECT @n_traduccion = COUNT(*) FROM silver.product_category_translation;
        PRINT '   silver.product_category_translation : ' + CAST(@n_traduccion AS NVARCHAR(20)) + ' filas';

        PRINT '------------------------------------------------';
        PRINT ' Plata cargada en ' + CAST(DATEDIFF(SECOND, @inicio, SYSDATETIME()) AS NVARCHAR(20)) + ' segundos';
        PRINT '================================================';
    END TRY
    BEGIN CATCH
        PRINT '*** ERROR CARGANDO PLATA ***';
        PRINT 'Mensaje : ' + ERROR_MESSAGE();
        PRINT 'Número  : ' + CAST(ERROR_NUMBER() AS NVARCHAR(20));
        THROW;
    END CATCH;
END;
GO
