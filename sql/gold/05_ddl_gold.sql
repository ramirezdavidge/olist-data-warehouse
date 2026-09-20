/*
===============================================================================
05 - CAPA ORO: definición del MODELO ESTRELLA
===============================================================================

===============================================================================
*/

USE OlistDW;
GO

-- Se eliminan primero los hechos (tienen las FK) y luego las dimensiones
IF OBJECT_ID('gold.fact_resenas', 'U') IS NOT NULL DROP TABLE gold.fact_resenas;
IF OBJECT_ID('gold.fact_pagos',   'U') IS NOT NULL DROP TABLE gold.fact_pagos;
IF OBJECT_ID('gold.fact_ventas',  'U') IS NOT NULL DROP TABLE gold.fact_ventas;
IF OBJECT_ID('gold.dim_tipo_pago','U') IS NOT NULL DROP TABLE gold.dim_tipo_pago;
IF OBJECT_ID('gold.dim_vendedor', 'U') IS NOT NULL DROP TABLE gold.dim_vendedor;
IF OBJECT_ID('gold.dim_producto', 'U') IS NOT NULL DROP TABLE gold.dim_producto;
IF OBJECT_ID('gold.dim_cliente',  'U') IS NOT NULL DROP TABLE gold.dim_cliente;
IF OBJECT_ID('gold.dim_fecha',    'U') IS NOT NULL DROP TABLE gold.dim_fecha;
GO

/* ============================ DIMENSIONES ============================ */

CREATE TABLE gold.dim_fecha (
    fecha_key         INT          NOT NULL PRIMARY KEY,   -- yyyymmdd
    fecha             DATE         NOT NULL,
    anio              SMALLINT     NOT NULL,
    trimestre         TINYINT      NOT NULL,
    mes               TINYINT      NOT NULL,
    nombre_mes        VARCHAR(12)  NOT NULL,
    anio_mes          CHAR(7)      NOT NULL,               -- 2017-11
    dia               TINYINT      NOT NULL,
    dia_semana        TINYINT      NOT NULL,               -- 1 = lunes ... 7 = domingo
    nombre_dia        VARCHAR(12)  NOT NULL,
    es_fin_de_semana  BIT          NOT NULL,
    CONSTRAINT uq_dim_fecha_fecha UNIQUE (fecha)
);
GO

CREATE TABLE gold.dim_cliente (
    cliente_key         INT           NOT NULL PRIMARY KEY,
    customer_unique_id  VARCHAR(50)   NOT NULL,
    ciudad              NVARCHAR(100) NOT NULL,
    estado              CHAR(2)       NOT NULL,
    region              VARCHAR(20)   NOT NULL,
    zip_code_prefix     CHAR(5)       NULL,
    latitud             FLOAT         NULL,
    longitud            FLOAT         NULL,
    primera_compra      DATE          NOT NULL,
    ultima_compra       DATE          NOT NULL,
    total_pedidos       INT           NOT NULL,
    tipo_cliente        VARCHAR(15)   NOT NULL,            -- Nuevo / Recurrente
    CONSTRAINT uq_dim_cliente_unique_id UNIQUE (customer_unique_id)
);
GO

CREATE TABLE gold.dim_producto (
    producto_key   INT           NOT NULL PRIMARY KEY,
    product_id     VARCHAR(50)   NOT NULL,
    categoria_pt   VARCHAR(100)  NOT NULL,
    categoria_en   VARCHAR(100)  NOT NULL,
    fotos_qty      INT           NOT NULL,
    peso_g         FLOAT         NULL,
    largo_cm       FLOAT         NULL,
    alto_cm        FLOAT         NULL,
    ancho_cm       FLOAT         NULL,
    volumen_cm3    FLOAT         NULL,
    rango_peso     NVARCHAR(30)  NOT NULL,
    CONSTRAINT uq_dim_producto_product_id UNIQUE (product_id)
);
GO

CREATE TABLE gold.dim_vendedor (
    vendedor_key     INT           NOT NULL PRIMARY KEY,
    seller_id        VARCHAR(50)   NOT NULL,
    ciudad           NVARCHAR(100) NOT NULL,
    estado           CHAR(2)       NOT NULL,
    region           VARCHAR(20)   NOT NULL,
    zip_code_prefix  CHAR(5)       NULL,
    latitud          FLOAT         NULL,
    longitud         FLOAT         NULL,
    CONSTRAINT uq_dim_vendedor_seller_id UNIQUE (seller_id)
);
GO

CREATE TABLE gold.dim_tipo_pago (
    tipo_pago_key  INT           NOT NULL PRIMARY KEY,
    payment_type   VARCHAR(30)   NOT NULL,
    descripcion    NVARCHAR(40)  NOT NULL,
    CONSTRAINT uq_dim_tipo_pago_tipo UNIQUE (payment_type)
);
GO

/* ============================== HECHOS =============================== */

CREATE TABLE gold.fact_ventas (
    venta_key                   INT          NOT NULL PRIMARY KEY,
    -- atributos degenerados
    order_id                    VARCHAR(50)  NOT NULL,
    order_item_id               INT          NOT NULL,
    estado_pedido               VARCHAR(20)  NOT NULL,
    -- llaves a dimensiones
    fecha_compra_key            INT          NOT NULL,
    fecha_entrega_estimada_key  INT          NULL,
    fecha_entrega_real_key      INT          NULL,      -- NULL si aún no se entrega
    cliente_key                 INT          NOT NULL,
    producto_key                INT          NOT NULL,
    vendedor_key                INT          NOT NULL,
    -- métricas
    precio                      FLOAT        NOT NULL,
    flete                       FLOAT        NOT NULL,
    total_item                  FLOAT        NOT NULL,  -- precio + flete
    dias_entrega_real           INT          NULL,      -- compra -> entrega
    dias_entrega_estimada       INT          NULL,      -- compra -> fecha prometida
    dias_retraso                INT          NULL,      -- 0 si llegó a tiempo
    entregado_a_tiempo          BIT          NULL,      -- NULL si no entregado
    es_venta_valida             BIT          NOT NULL,  -- 0 = cancelado / no disponible
    CONSTRAINT uq_fact_ventas_item UNIQUE (order_id, order_item_id),
    CONSTRAINT fk_ventas_fecha_compra   FOREIGN KEY (fecha_compra_key)           REFERENCES gold.dim_fecha (fecha_key),
    CONSTRAINT fk_ventas_fecha_estim    FOREIGN KEY (fecha_entrega_estimada_key) REFERENCES gold.dim_fecha (fecha_key),
    CONSTRAINT fk_ventas_fecha_real     FOREIGN KEY (fecha_entrega_real_key)     REFERENCES gold.dim_fecha (fecha_key),
    CONSTRAINT fk_ventas_cliente        FOREIGN KEY (cliente_key)                REFERENCES gold.dim_cliente (cliente_key),
    CONSTRAINT fk_ventas_producto       FOREIGN KEY (producto_key)               REFERENCES gold.dim_producto (producto_key),
    CONSTRAINT fk_ventas_vendedor       FOREIGN KEY (vendedor_key)               REFERENCES gold.dim_vendedor (vendedor_key)
);
GO
CREATE INDEX ix_fact_ventas_fecha    ON gold.fact_ventas (fecha_compra_key);
CREATE INDEX ix_fact_ventas_cliente  ON gold.fact_ventas (cliente_key);
CREATE INDEX ix_fact_ventas_producto ON gold.fact_ventas (producto_key);
CREATE INDEX ix_fact_ventas_vendedor ON gold.fact_ventas (vendedor_key);
GO

CREATE TABLE gold.fact_pagos (
    pago_key            INT          NOT NULL PRIMARY KEY,
    order_id            VARCHAR(50)  NOT NULL,
    payment_sequential  INT          NOT NULL,
    fecha_compra_key    INT          NOT NULL,
    cliente_key         INT          NOT NULL,
    tipo_pago_key       INT          NOT NULL,
    cuotas              INT          NOT NULL,
    valor_pago          FLOAT        NOT NULL,
    CONSTRAINT uq_fact_pagos UNIQUE (order_id, payment_sequential),
    CONSTRAINT fk_pagos_fecha     FOREIGN KEY (fecha_compra_key) REFERENCES gold.dim_fecha (fecha_key),
    CONSTRAINT fk_pagos_cliente   FOREIGN KEY (cliente_key)      REFERENCES gold.dim_cliente (cliente_key),
    CONSTRAINT fk_pagos_tipo_pago FOREIGN KEY (tipo_pago_key)    REFERENCES gold.dim_tipo_pago (tipo_pago_key)
);
GO
CREATE INDEX ix_fact_pagos_fecha ON gold.fact_pagos (fecha_compra_key);
GO

CREATE TABLE gold.fact_resenas (
    resena_key        INT          NOT NULL PRIMARY KEY,
    review_id         VARCHAR(50)  NOT NULL,
    order_id          VARCHAR(50)  NOT NULL,
    fecha_resena_key  INT          NOT NULL,
    cliente_key       INT          NOT NULL,
    review_score      TINYINT      NOT NULL,             -- 1 a 5
    tiene_comentario  BIT          NOT NULL,
    dias_respuesta    INT          NULL,                 -- creación -> respuesta
    CONSTRAINT uq_fact_resenas_order UNIQUE (order_id),
    CONSTRAINT fk_resenas_fecha   FOREIGN KEY (fecha_resena_key) REFERENCES gold.dim_fecha (fecha_key),
    CONSTRAINT fk_resenas_cliente FOREIGN KEY (cliente_key)      REFERENCES gold.dim_cliente (cliente_key)
);
GO
CREATE INDEX ix_fact_resenas_fecha ON gold.fact_resenas (fecha_resena_key);
GO
