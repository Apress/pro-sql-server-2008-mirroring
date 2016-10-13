CREATE  PROCEDURE dbo.dba_ConfigureDBForMirroring 
        @DBName sysname 
AS 

DECLARE @RecoveryModel INT, 
        @Compatibility INT, 
        @DBID INT, 
        @MaxCompat INT, 
        @SQL NVARCHAR(500), 
        @MirrState INT, 
        @Server sysname  

SET NOCOUNT ON 

SET @DBID = DB_ID(@DBName) 
SET @MaxCompat = PARSENAME(CAST(SERVERPROPERTY('ProductVersion') AS sysname), 4)*10 
SET @Server = @@SERVERNAME 

IF @DBID IS NULL 
  BEGIN 
        RAISERROR('Database [%s] not found on server [%s].', 
                               16, 1, @DBName,  @Server); 
        RETURN; 
  END 

SELECT @Compatibility = D.compatibility_level, 
               @RecoveryModel = D.recovery_model, 
               @MirrState = DM.mirroring_state 
FROM   sys.databases D 
INNER JOIN sys.database_mirroring DM ON DM.database_id = D.database_id 
WHERE D.database_id = @DBID  

IF @MirrState IS NOT NULL 
  BEGIN 
    RAISERROR('Database [%s] is already configured for mirroring on server [%s].', 
                   16, 1, @DBName, @Server); 
    RETURN; 
  END 

IF @Compatibility < 90 
  BEGIN 
        PRINT 'Changing compatibility level to ' + CAST(@MaxCompat AS NVARCHAR); 
        IF @MaxCompat = 90 -- SQL Server 2005 
          BEGIN 
                EXEC sp_dbcmptlevel @dbname = @DBName, 
                                @new_cmptlevel = @MaxCompat; 
          END 
        ELSE IF @MaxCompat >= 100 -- SQL Server 2008+ 
          BEGIN 
                SET @SQL = 'Alter Database ' + QUOTENAME(@DBName) + 
                        ' Set Compatibility_Level = ' + 
                        CAST(@MaxCompat AS NVARCHAR) + ';'; 
                EXEC sp_executesql @SQL; 
          END 
  END 

IF @RecoveryModel <> 1 -- Full Recovery Model 
  BEGIN 
        PRINT 'Changing Recovery Model to Full'; 
        SET @SQL = 'Alter Database ' + QUOTENAME(@DBName) + 
                ' Set Recovery Full;'; 
        EXEC sp_executesql @SQL; 
  END


