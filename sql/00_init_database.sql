/*
===============================================================================
00 - Inicialización de la base de datos y esquemas (arquitectura medallón)
===============================================================================

===============================================================================
*/

USE master;
GO

IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'OlistDW')
BEGIN
    ALTER DATABASE OlistDW SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE OlistDW;
END;
GO

CREATE DATABASE OlistDW;
GO

USE OlistDW;
GO

CREATE SCHEMA bronze;
GO
CREATE SCHEMA silver;
GO
CREATE SCHEMA gold;
GO
