CREATE PROCEDURE dbo.dba_SetOperatingMode    
        @DBName sysname, 
        @Debug bit = 0 
AS 

DECLARE @SQL NVARCHAR(100) 

SET NOCOUNT ON 

SET @SQL = 'Alter Database ' + QUOTENAME(@DBName) + 
        ' Set Safety Off;'; 

IF @Debug = 1 
  BEGIN 
        PRINT @SQL; 
  END 
ELSE 
  BEGIN 
        EXEC sp_executesql @SQL; 
  END   
