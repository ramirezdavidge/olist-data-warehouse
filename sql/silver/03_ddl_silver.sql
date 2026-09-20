/*
===============================================================================
03 - CAPA PLATA: definición de tablas
===============================================================================

===============================================================================
*/

USE OlistDW;
GO

-- Función de apoyo: minúsculas, sin espacios sobrantes y sin acentos/ñ/ç.
-- Devuelve NULL si el texto queda vacío.
CREATE OR ALTER FUNCTION silver.fn_limpiar_texto (@texto NVARCHAR(500))
RETURNS NVARCHAR(500)
WITH SCHEMABINDING
AS
BEGIN
    RETURN NULLIF(
        TRANSLATE(LOWER(LTRIM(RTRIM(@texto))),
                  N'áàâãäéèêëíìîïóòôõöúùûüçñ',
                  N'aaaaaeeeeiiiiooooouuuucn'),
        N'');
END;
GO

IF OBJECT_ID('silver.customers', 'U') IS NOT NULL DROP TABLE silver.customers;
GO
CREATE TABLE silver.customers (
    customer_id             VARCHAR(50)   NOT NULL PRIMARY KEY,
    customer_unique_id      VARCHAR(50)   NOT NULL,
    zip_code_prefix         CHAR(5)       NULL,
    city                    NVARCHAR(100) NULL,
    state                   CHAR(2)       NULL,
    dwh_fecha_carga_bronze  DATETIME2(0)  NULL,
    dwh_fecha_proceso       DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME()
);
GO

IF OBJECT_ID('silver.geolocation', 'U') IS NOT NULL DROP TABLE silver.geolocation;
GO
CREATE TABLE silver.geolocation (
    zip_code_prefix         CHAR(5)       NOT NULL,
    lat                     FLOAT         NOT NULL,
    lng                     FLOAT         NOT NULL,
    city                    NVARCHAR(100) NULL,
    state                   CHAR(2)       NULL,
    dwh_fecha_carga_bronze  DATETIME2(0)  NULL,
    dwh_fecha_proceso       DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME()
);
GO

IF OBJECT_ID('silver.orders', 'U') IS NOT NULL DROP TABLE silver.orders;
GO
CREATE TABLE silver.orders (
    order_id                       VARCHAR(50)  NOT NULL PRIMARY KEY,
    customer_id                    VARCHAR(50)  NOT NULL,
    order_status                   VARCHAR(20)  NOT NULL,
    order_purchase_timestamp       DATETIME2(0) NOT NULL,
    order_approved_at              DATETIME2(0) NULL,
    order_delivered_carrier_date   DATETIME2(0) NULL,
    order_delivered_customer_date  DATETIME2(0) NULL,
    order_estimated_delivery_date  DATE         NULL,
    dwh_fecha_carga_bronze         DATETIME2(0) NULL,
    dwh_fecha_proceso              DATETIME2(0) NOT NULL DEFAULT SYSDATETIME()
);
GO

IF OBJECT_ID('silver.order_items', 'U') IS NOT NULL DROP TABLE silver.order_items;
GO
CREATE TABLE silver.order_items (
    order_id                VARCHAR(50)  NOT NULL,
    order_item_id           INT          NOT NULL,
    product_id              VARCHAR(50)  NOT NULL,
    seller_id               VARCHAR(50)  NOT NULL,
    shipping_limit_date     DATETIME2(0) NULL,
    price                   FLOAT        NOT NULL,
    freight_value           FLOAT        NOT NULL,
    dwh_fecha_carga_bronze  DATETIME2(0) NULL,
    dwh_fecha_proceso       DATETIME2(0) NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT pk_silver_order_items PRIMARY KEY (order_id, order_item_id)
);
GO

IF OBJECT_ID('silver.order_payments', 'U') IS NOT NULL DROP TABLE silver.order_payments;
GO
CREATE TABLE silver.order_payments (
    order_id                VARCHAR(50)  NOT NULL,
    payment_sequential      INT          NOT NULL,
    payment_type            VARCHAR(30)  NOT NULL,
    payment_installments    INT          NOT NULL,
    payment_value           FLOAT        NOT NULL,
    dwh_fecha_carga_bronze  DATETIME2(0) NULL,
    dwh_fecha_proceso       DATETIME2(0) NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT pk_silver_order_payments PRIMARY KEY (order_id, payment_sequential)
);
GO

IF OBJECT_ID('silver.order_reviews', 'U') IS NOT NULL DROP TABLE silver.order_reviews;
GO
CREATE TABLE silver.order_reviews (
    review_id                VARCHAR(50)    NOT NULL,
    order_id                 VARCHAR(50)    NOT NULL,
    review_score             INT            NOT NULL,
    review_comment_title     NVARCHAR(500)  NOT NULL,
    review_comment_message   NVARCHAR(2000) NOT NULL,
    tiene_comentario         BIT            NOT NULL,
    review_creation_date     DATE           NULL,
    review_answer_timestamp  DATETIME2(0)   NULL,
    dwh_fecha_carga_bronze   DATETIME2(0)   NULL,
    dwh_fecha_proceso        DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT pk_silver_order_reviews PRIMARY KEY (review_id, order_id)
);
GO

IF OBJECT_ID('silver.products', 'U') IS NOT NULL DROP TABLE silver.products;
GO
CREATE TABLE silver.products (
    product_id                  VARCHAR(50)  NOT NULL PRIMARY KEY,
    product_category_name       VARCHAR(100) NOT NULL,
    product_name_length         INT          NOT NULL,
    product_description_length  INT          NOT NULL,
    product_photos_qty          INT          NOT NULL,
    product_weight_g            FLOAT        NULL,
    product_length_cm           FLOAT        NULL,
    product_height_cm           FLOAT        NULL,
    product_width_cm            FLOAT        NULL,
    dwh_fecha_carga_bronze      DATETIME2(0) NULL,
    dwh_fecha_proceso           DATETIME2(0) NOT NULL DEFAULT SYSDATETIME()
);
GO

IF OBJECT_ID('silver.sellers', 'U') IS NOT NULL DROP TABLE silver.sellers;
GO
CREATE TABLE silver.sellers (
    seller_id               VARCHAR(50)   NOT NULL PRIMARY KEY,
    zip_code_prefix         CHAR(5)       NULL,
    city                    NVARCHAR(100) NULL,
    state                   CHAR(2)       NULL,
    dwh_fecha_carga_bronze  DATETIME2(0)  NULL,
    dwh_fecha_proceso       DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME()
);
GO

IF OBJECT_ID('silver.product_category_translation', 'U') IS NOT NULL DROP TABLE silver.product_category_translation;
GO
CREATE TABLE silver.product_category_translation (
    product_category_name          VARCHAR(100) NOT NULL PRIMARY KEY,
    product_category_name_english  VARCHAR(100) NOT NULL,
    dwh_fecha_carga_bronze         DATETIME2(0) NULL,
    dwh_fecha_proceso              DATETIME2(0) NOT NULL DEFAULT SYSDATETIME()
);
GO
