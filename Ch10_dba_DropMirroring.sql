CREATE PROCEDURE dbo.dba_DropMirroring  
        @DBName sysname = NULL -- NULL returns help text 
AS 
DECLARE @SQL NVARCHAR(1000), 
        @MaxID INT, 
        @CurrID INT, 
        @PartnerServer sysname 

DECLARE @Databases TABLE (DatabaseID INT IDENTITY(1, 1) NOT NULL PRIMARY KEY, 
                                                       DBName sysname NOT NULL) 

SET NOCOUNT ON 

-- Returns help info if no value entered 
IF @DBName IS NULL 
  GOTO PrintHelp 

IF @DBName <> 'drop all' 
  BEGIN 
    -- Check to see if database is mirrored 
    IF EXISTS (SELECT 1 
                        FROM sys.database_mirroring WITH(nolock) 
                        WHERE database_id = DB_ID(@DBName) AND 
                                       mirroring_role IS NULL)-- NULL = not mirrored 
      BEGIN 
        RAISERROR('%s is either not mirrored or is not currently in the principal role.', 
                               1, 1, @DBName) 
          GOTO Failed 
      END 

      IF EXISTS (SELECT 1 
                          FROM sys.database_mirroring WITH(nolock) 
                          WHERE database_id = DB_ID(@DBName) AND
                                          mirroring_role IS NOT NULL) 
        BEGIN 
          SET @SQL = 'Alter Database ' + QUOTENAME(@DBName) + 
                                 ' Set Partner Off;' 

          EXEC sp_executesql @SQL 
        END 
  END 
ELSE 
  BEGIN 
    INSERT INTO @Databases (DBName) 
    SELECT DB_NAME(D.database_id) 
    FROM sys.databases D INNER JOIN
                sys.database_mirroring DM 
                 ON DM.database_id = D.database_id 
    WHERE D.state = 0 -- online AND 
                   DM.mirroring_state IN (2, 4) AND-- Synchronizing, Synchronized 
                   DM.mirroring_role IS NOT NULL 

    SELECT @MaxID = MAX(DatabaseID), 
                    @CurrID = 1 
    FROM @Databases 

    /* Turn of Partner Instance */ 
    WHILE @CurrID <= @MaxID 
      BEGIN 
        SELECT @DBName = DBName 
        FROM @Databases 
        WHERE DatabaseID = @CurrID 

        SET @SQL = 'Alter Database ' + QUOTENAME(@DBName) + 
                               ' Set Partner Off;' 

        EXEC sp_executesql @SQL 

        SET @CurrID = @CurrID + 1 
      END 
  END 
  
GOTO Completed 
Failed: 
PrintHelp: 
  PRINT 'Procedure: dbo.dba_DropMirroring' 
  PRINT 'Parameters: @DBName sysname, default = Null' 
  PRINT CHAR(9) + CHAR(9) + 'When Null, procedure returns help information about the procedure.' 
  PRINT CHAR(9) + CHAR(9) + 'When set to name of a mirrored database, '  + 
                                                      ' drops mirroring for that database only.' 
  PRINT CHAR(9) + CHAR(9) + 'When set to "drop all", drops mirroring for all mirrored databases.' 
  PRINT CHAR(9) + CHAR(9) + 'When set to name of a non-mirrored database, returns a warning.' 
  PRINT 'Purpose: Drops mirroring for the selected database or for all databases.' 
  PRINT 'Examples: Exec dbo.dba_DropMirroring @DBName = ''MirrorTest''' 
  PRINT CHAR(9) + CHAR(9) + 'Exec OpsDB.dbo.ops_DropMirroring @DBName = ''drop all''' 
  PRINT CHAR(9) + CHAR(9) + 'Exec OpsDB.dbo.ops_DropMirroring' 
  PRINT 'Tasks performed:' 
  PRINT CHAR(9) + '1. If a single database name is supplied:' 
  PRINT CHAR(9) + CHAR(9) + 'a. Verifies that the database is mirrored.' 
  PRINT CHAR(9) + CHAR(9) + 'b. Drops database mirroring for the specified database.' 
  PRINT CHAR(9) + CHAR(9) + 'c. Leaves the mirrored database in a restoring mode.' 
  PRINT CHAR(9) + '2. If "drop all" is supplied:' 
  PRINT CHAR(9) + CHAR(9) + 'a. Drops all database mirroring sessions on the server.' 
  PRINT CHAR(9) + CHAR(9) + 'b. Leaves all mirrored databases in a restoring mode.' 
  PRINT CHAR(9) + '3. Else:' 
  PRINT CHAR(9) + CHAR(9) + 'a. Returns a warning and/or help information' 
Completed: 
  PRINT ''
