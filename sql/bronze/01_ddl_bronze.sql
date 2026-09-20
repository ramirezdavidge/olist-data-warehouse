/*
===============================================================================
01 - CAPA BRONCE: definición de tablas
===============================================================================

===============================================================================
*/

USE OlistDW;
GO

IF OBJECT_ID('bronze.customers', 'U') IS NOT NULL DROP TABLE bronze.customers;
GO
CREATE TABLE bronze.customers (
    customer_id               NVARCHAR(100),
    customer_unique_id        NVARCHAR(100),
    customer_zip_code_prefix  NVARCHAR(20),
    customer_city             NVARCHAR(200),
    customer_state            NVARCHAR(20),
    fecha_carga               DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    archivo_origen            NVARCHAR(260) NOT NULL DEFAULT 'olist_customers_dataset.csv'
);
GO

IF OBJECT_ID('bronze.geolocation', 'U') IS NOT NULL DROP TABLE bronze.geolocation;
GO
CREATE TABLE bronze.geolocation (
    geolocation_zip_code_prefix  NVARCHAR(20),
    geolocation_lat              NVARCHAR(50),
    geolocation_lng              NVARCHAR(50),
    geolocation_city             NVARCHAR(200),
    geolocation_state            NVARCHAR(20),
    fecha_carga                  DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    archivo_origen               NVARCHAR(260) NOT NULL DEFAULT 'olist_geolocation_dataset.csv'
);
GO

IF OBJECT_ID('bronze.order_items', 'U') IS NOT NULL DROP TABLE bronze.order_items;
GO
CREATE TABLE bronze.order_items (
    order_id             NVARCHAR(100),
    order_item_id        NVARCHAR(20),
    product_id           NVARCHAR(100),
    seller_id            NVARCHAR(100),
    shipping_limit_date  NVARCHAR(50),
    price                NVARCHAR(50),
    freight_value        NVARCHAR(50),
    fecha_carga          DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    archivo_origen       NVARCHAR(260) NOT NULL DEFAULT 'olist_order_items_dataset.csv'
);
GO

IF OBJECT_ID('bronze.order_payments', 'U') IS NOT NULL DROP TABLE bronze.order_payments;
GO
CREATE TABLE bronze.order_payments (
    order_id              NVARCHAR(100),
    payment_sequential    NVARCHAR(20),
    payment_type          NVARCHAR(50),
    payment_installments  NVARCHAR(20),
    payment_value         NVARCHAR(50),
    fecha_carga           DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    archivo_origen        NVARCHAR(260) NOT NULL DEFAULT 'olist_order_payments_dataset.csv'
);
GO

IF OBJECT_ID('bronze.order_reviews', 'U') IS NOT NULL DROP TABLE bronze.order_reviews;
GO
CREATE TABLE bronze.order_reviews (
    review_id                NVARCHAR(100),
    order_id                 NVARCHAR(100),
    review_score             NVARCHAR(20),
    review_comment_title     NVARCHAR(1000),
    review_comment_message   NVARCHAR(4000),
    review_creation_date     NVARCHAR(50),
    review_answer_timestamp  NVARCHAR(50),
    fecha_carga              DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    archivo_origen           NVARCHAR(260) NOT NULL DEFAULT 'olist_order_reviews_dataset.csv'
);
GO

IF OBJECT_ID('bronze.orders', 'U') IS NOT NULL DROP TABLE bronze.orders;
GO
CREATE TABLE bronze.orders (
    order_id                       NVARCHAR(100),
    customer_id                    NVARCHAR(100),
    order_status                   NVARCHAR(50),
    order_purchase_timestamp       NVARCHAR(50),
    order_approved_at              NVARCHAR(50),
    order_delivered_carrier_date   NVARCHAR(50),
    order_delivered_customer_date  NVARCHAR(50),
    order_estimated_delivery_date  NVARCHAR(50),
    fecha_carga                    DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    archivo_origen                 NVARCHAR(260) NOT NULL DEFAULT 'olist_orders_dataset.csv'
);
GO

IF OBJECT_ID('bronze.products', 'U') IS NOT NULL DROP TABLE bronze.products;
GO
CREATE TABLE bronze.products (
    product_id                   NVARCHAR(100),
    product_category_name        NVARCHAR(200),
    product_name_lenght          NVARCHAR(20),   -- (sic) el nombre viene mal escrito en la fuente
    product_description_lenght   NVARCHAR(20),   -- (sic)
    product_photos_qty           NVARCHAR(20),
    product_weight_g             NVARCHAR(50),
    product_length_cm            NVARCHAR(50),
    product_height_cm            NVARCHAR(50),
    product_width_cm             NVARCHAR(50),
    fecha_carga                  DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    archivo_origen               NVARCHAR(260) NOT NULL DEFAULT 'olist_products_dataset.csv'
);
GO

IF OBJECT_ID('bronze.sellers', 'U') IS NOT NULL DROP TABLE bronze.sellers;
GO
CREATE TABLE bronze.sellers (
    seller_id               NVARCHAR(100),
    seller_zip_code_prefix  NVARCHAR(20),
    seller_city             NVARCHAR(200),
    seller_state            NVARCHAR(20),
    fecha_carga             DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    archivo_origen          NVARCHAR(260) NOT NULL DEFAULT 'olist_sellers_dataset.csv'
);
GO

IF OBJECT_ID('bronze.product_category_translation', 'U') IS NOT NULL DROP TABLE bronze.product_category_translation;
GO
CREATE TABLE bronze.product_category_translation (
    product_category_name          NVARCHAR(200),
    product_category_name_english  NVARCHAR(200),
    fecha_carga                    DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    archivo_origen                 NVARCHAR(260) NOT NULL DEFAULT 'product_category_name_translation.csv'
);
GO
