CREATE PROCEDURE dbo.dba_FailoverMirrorToOriginalPrincipal 
    -- database to fail back; all applicable databases if null 
    @DBName sysname = NULL, 
    -- 0 = Execute it, 1 = Output SQL that would be executed 
    @Debug bit = 0 
AS 

DECLARE @SQL NVARCHAR(200), 
        @MaxID INT, 
        @CurrID INT 

DECLARE @MirrDBs TABLE 
                (MirrDBID INT IDENTITY(1, 1) NOT NULL PRIMARY KEY, 
                 DBName sysname NOT NULL) 

SET NOCOUNT ON 

-- If database is in the principal role 
-- and is in a synchronized state, 
-- fail database back to original principal 

INSERT INTO @MirrDBs (DBName) 
SELECT DB_NAME(database_id) 
FROM sys.database_mirroring 
WHERE mirroring_role = 1 AND  -- Principal partner 
      mirroring_state = 4 AND -- Synchronized 
     (database_id = DB_ID(@DBName) OR
      @DBName IS NULL)  

SELECT @MaxID = MAX(MirrDBID) 
FROM @MirrDBs 

WHILE @CurrID <= @MaxID 
  BEGIN 
    SELECT @DBName = DBName 
    FROM @MirrDBs 
    WHERE MirrDBID = @CurrID 
         
    SET @SQL = 'Alter Database ' + QUOTENAME(@DBName) + 
               ' Set Partner Failover;' 

    IF @Debug = 1 
      BEGIN 
        EXEC sp_executesql @SQL; 
      END 
    ELSE 
      BEGIN 
        PRINT @SQL; 
      END 
         
    SET @CurrID = @CurrID + 1 
  END
