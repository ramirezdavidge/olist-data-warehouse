/*
===============================================================================
EJECUCIÓN DEL PIPELINE COMPLETO (Bronce -> Plata -> Oro)
===============================================================================

*/

USE OlistDW;
GO

EXEC bronze.usp_load_bronze @ruta_base =  N'C:\olist\raw\';
GO
EXEC silver.usp_load_silver;
GO
EXEC gold.usp_load_gold;
GO

-- Verificación: ver sql/99_validaciones.sql
