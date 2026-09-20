/*
===============================================================================
02 - CAPA BRONCE: procedimientos de carga (extracción desde CSV)
===============================================================================

===============================================================================
*/

USE OlistDW;
GO

CREATE OR ALTER PROCEDURE bronze.usp_cargar_csv
    @tabla        SYSNAME,        -- tabla destino dentro del esquema bronze
    @archivo      NVARCHAR(260),  -- nombre del CSV
    @ruta_base    NVARCHAR(400),  -- carpeta donde están los CSV
    @fin_de_fila  NVARCHAR(10)    -- '0x0a' (LF) o '0x0d0a' (CRLF)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @cols NVARCHAR(MAX),
            @sql  NVARCHAR(MAX),
            @ts   DATETIME2(0) = SYSDATETIME(),
            @n    INT;

    -- Columnas del archivo = columnas de la tabla menos las de auditoría
    SELECT @cols = STRING_AGG(CAST(QUOTENAME(c.name) AS NVARCHAR(MAX)), N', ')
                   WITHIN GROUP (ORDER BY c.column_id)
    FROM sys.columns AS c
    WHERE c.object_id = OBJECT_ID(N'bronze.' + QUOTENAME(@tabla))
      AND c.name NOT IN (N'fecha_carga', N'archivo_origen');

    IF @cols IS NULL
    BEGIN
        RAISERROR('La tabla bronze.%s no existe. Ejecuta primero 01_ddl_bronze.sql', 16, 1, @tabla);
        RETURN;
    END;

    IF RIGHT(@ruta_base, 1) NOT IN (N'\', N'/')
        SET @ruta_base += CASE WHEN CHARINDEX(N'\', @ruta_base) > 0 THEN N'\' ELSE N'/' END;

    SET @sql = N'
        TRUNCATE TABLE bronze.' + QUOTENAME(@tabla) + N';

        SELECT TOP (0) ' + @cols + N'
        INTO #stg
        FROM bronze.' + QUOTENAME(@tabla) + N';

        BULK INSERT #stg
        FROM ''' + REPLACE(@ruta_base + @archivo, N'''', N'''''') + N'''
        WITH (
            FORMAT          = ''CSV'',
            FIRSTROW        = 2,
            FIELDQUOTE      = ''"'',
            FIELDTERMINATOR = '','',
            ROWTERMINATOR   = ''' + @fin_de_fila + N''',
            CODEPAGE        = ''65001'',
            TABLOCK
        );

        INSERT INTO bronze.' + QUOTENAME(@tabla) + N' (' + @cols + N', fecha_carga, archivo_origen)
        SELECT ' + @cols + N', @ts, @archivo
        FROM #stg;';

    EXEC sys.sp_executesql @sql,
         N'@ts DATETIME2(0), @archivo NVARCHAR(260)',
         @ts = @ts, @archivo = @archivo;

    SET @sql = N'SELECT @n = COUNT(*) FROM bronze.' + QUOTENAME(@tabla);
    EXEC sys.sp_executesql @sql, N'@n INT OUTPUT', @n = @n OUTPUT;

    PRINT '   bronze.' + @tabla + ' <- ' + @archivo + ' : ' + CAST(@n AS NVARCHAR(20)) + ' filas';
END;
GO


CREATE OR ALTER PROCEDURE bronze.usp_load_bronze
    @ruta_base NVARCHAR(400)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @inicio DATETIME2 = SYSDATETIME();

    BEGIN TRY
        PRINT '================================================';
        PRINT ' CARGA CAPA BRONCE';
        PRINT '================================================';

        -- Los archivos de Olist usan salto de línea LF, salvo reviews y
        -- product_category_name_translation que usan CRLF.
        EXEC bronze.usp_cargar_csv 'customers',                    'olist_customers_dataset.csv',         @ruta_base, '0x0a';
        EXEC bronze.usp_cargar_csv 'geolocation',                  'olist_geolocation_dataset.csv',       @ruta_base, '0x0a';
        EXEC bronze.usp_cargar_csv 'order_items',                  'olist_order_items_dataset.csv',       @ruta_base, '0x0a';
        EXEC bronze.usp_cargar_csv 'order_payments',               'olist_order_payments_dataset.csv',    @ruta_base, '0x0a';
        EXEC bronze.usp_cargar_csv 'order_reviews',                'olist_order_reviews_dataset.csv',     @ruta_base, '0x0d0a';
        EXEC bronze.usp_cargar_csv 'orders',                       'olist_orders_dataset.csv',            @ruta_base, '0x0a';
        EXEC bronze.usp_cargar_csv 'products',                     'olist_products_dataset.csv',          @ruta_base, '0x0a';
        EXEC bronze.usp_cargar_csv 'sellers',                      'olist_sellers_dataset.csv',           @ruta_base, '0x0a';
        EXEC bronze.usp_cargar_csv 'product_category_translation', 'product_category_name_translation.csv', @ruta_base, '0x0d0a';

        PRINT '------------------------------------------------';
        PRINT ' Bronce cargada en ' + CAST(DATEDIFF(SECOND, @inicio, SYSDATETIME()) AS NVARCHAR(20)) + ' segundos';
        PRINT '================================================';
    END TRY
    BEGIN CATCH
        PRINT '*** ERROR CARGANDO BRONCE ***';
        PRINT 'Mensaje : ' + ERROR_MESSAGE();
        PRINT 'Número  : ' + CAST(ERROR_NUMBER() AS NVARCHAR(20));
        THROW;
    END CATCH;
END;
GO
