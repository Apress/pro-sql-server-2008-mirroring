CREATE PROCEDURE dbo.dba_RestoreDBLog  
        @DBName sysname, 
        @BackupFile NVARCHAR(500), 
        @PrinServer sysname, 
        @Debug bit = 0 -- 0 = Execute, 1 = Return SQL for execution 
AS 

DECLARE @UNCBackupFile NVARCHAR(500), 
        @Exists INT, 
        @SQL NVARCHAR(MAX) 

SET NOCOUNT ON  

DECLARE @DBID INT ; 

SET @DBID = DB_ID(@DBName); 

-- Convert backup path to UNC 
IF SUBSTRING(@BackupFile, 2, 2) = ':\' 
  BEGIN 
        SET @UNCBackupFile = '\\' + @PrinServer + '\' + 
                REPLACE(LEFT(@BackupFile, 2), ':', '$') + 
                RIGHT(@BackupFile, LEN(@BackupFile) - 2); 
  END 
ELSE 
  BEGIN 
        SET @UNCBackupFile = @BackupFile 
  END 

-- Verify backup file is accessible 
EXEC xp_FileExist @UNCBackupFile, @Exists OUTPUT 

IF @Exists = 0 -- Does not exist or is not accessible 
  BEGIN 
        RAISERROR('Unable to open backup file: %s', 16, 1, @UNCBackupFile); 
        RETURN; 
  END 

SET @SQL = 'Restore Log ' + QUOTENAME(@DBName) + CHAR(10) + CHAR(9) + 
        'From Disk = ''' + @UNCBackupFile + '''' + CHAR(10) + CHAR(9) + 
        'With NoRecovery, Stats = 10' 

-- If not run in debug mode, execute, else print execute statement 
IF @Debug = 0 
  BEGIN 
        EXEC sp_executesql @SQL; 
  END 
ELSE 
  BEGIN 
        PRINT ''; 
        PRINT @SQL; 
  END
