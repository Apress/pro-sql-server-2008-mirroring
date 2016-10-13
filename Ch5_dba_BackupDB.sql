CREATE PROCEDURE dbo.dba_BackupDB  
        @DBName sysname, 
        @BackupType bit = 0, -- 0 = Full, 1 = Log 
        -- Location where you want the backups saved 
        @BackupLocation NVARCHAR(255) = NULL, 
        @Debug bit = 0, -- 0 = Execute, 1 = Return SQL for execution 
        @BackupFile NVARCHAR(500) = NULL OUTPUT 
AS 

DECLARE @BakDir NVARCHAR(255), 
        @Exists INT, 
        @DBID INT, 
        @SQL NVARCHAR(1000), 
        @Backup NVARCHAR(500), 
        @DateSerial NVARCHAR(35), 
        @ErrNumber INT, 
        @ErrSeverity INT, 
        @ErrState INT, 
        @ErrProcedure sysname, 
        @ErrLine INT, 
        @ErrMsg NVARCHAR(2048), 
        @BAKExtension NVARCHAR(10), 
        @BackupName sysname, 
        @BAKDesc sysname, 
        @BackupTypeStr NVARCHAR(20), 
        @BAKName sysname 

DECLARE @FileExists TABLE (FileExists INT NOT NULL,  
                        FileIsDirectory INT NOT NULL,  
                        ParentDirectoryExists INT NOT NULL) 

SET NOCOUNT ON 

SET @DateSerial = CONVERT(NVARCHAR, GETDATE(), 112) + 
                REPLACE(CONVERT(NVARCHAR, GETDATE(), 108), ':', ''); 
SET @DBID = DB_ID(@DBName) 

IF @DBID IS NULL 
  BEGIN 
        RAISERROR ('The specified database [%s] does not exist.', 16, 1, @DBName); 
        RETURN; 
  END 

IF EXISTS (SELECT 1 FROM sys.databases 
        WHERE name = @DBName 
        AND state > 0) 
  BEGIN 
        RAISERROR ('The specified database [%s] is not online.', 16, 1, @DBName); 
        RETURN; 
  END 

IF EXISTS (SELECT 1 FROM sys.databases 
        WHERE name = @DBName 
        AND source_database_id IS NOT NULL) 
  BEGIN 
        RAISERROR ('The specified database [%s] is a database snapshot.', 
                                16, 1, @DBName); 
        RETURN; 
  END 

IF @BackupLocation IS NULL 
  BEGIN 
        EXEC xp_instance_regread N'HKEY_LOCAL_MACHINE',  
                                N'Software\Microsoft\MSSQLServer\MSSQLServer',  
                                N'BackupDirectory',  
                                @BakDir output,  
                                'no_output'; 
        IF @BakDir IS NOT NULL 
          BEGIN 
                INSERT INTO @FileExists 
                EXEC sys.xp_fileexist @BakDir; 

                SELECT @Exists = ParentDirectoryExists 
                FROM @FileExists 
                 
                IF @Exists = 1 
                  BEGIN 
                        SET @BackupLocation = @BakDir; 
                  END 
          END 
  END 

IF @BackupLocation IS NULL 
  BEGIN 
    SELECT TOP 1 @BakDir = LEFT(MF.physical_device_name, 
               LEN(MF.physical_device_name) -
               CHARINDEX('\', REVERSE(MF.physical_device_name))) 
    FROM msdb.dbo.backupset BS  INNER JOIN
        msdb.dbo.backupmediafamily MF 
         ON MF.media_set_id = BS.media_set_id 
    ORDER BY BS.type ASC, -- full backups first, then differentials, then log backups 
        BS.backup_finish_date DESC; -- oldest first 

        IF @BakDir IS NOT NULL 
          BEGIN 
                DELETE FROM @FileExists 

                INSERT INTO @FileExists 
                EXEC sys.xp_fileexist @BakDir; 

                SELECT @Exists = ParentDirectoryExists 
                FROM @FileExists 
                 
                IF @Exists = 1 
                  BEGIN 
                        SET @BackupLocation = @BakDir; 
                  END 
          END 
  END 

IF @BackupLocation IS NOT NULL 
  BEGIN 
        IF RIGHT(@BackupLocation, 1) <> '\' 
                SET @BackupLocation = @BackupLocation + '\'; 
  END 
ELSE 
  BEGIN 
        RAISERROR ('Backup location not specified or not found.', 16, 1); 
        RETURN; 
  END 
         
/* Set backup extension and with option */ 
IF @BackupType = 0 
  BEGIN 
        SET @BAKExtension = '.bak' 
        SET @BackupTypeStr = 'Database' 
  END 
ELSE 
  BEGIN 
        SET @BAKExtension = '.trn' 
        SET @BackupTypeStr = 'Log' 
  END 

IF RIGHT(@BackupLocation, 1) <> '\' 
  BEGIN 
         SET @BackupLocation = @BackupLocation + '\' 
  END 
   
SET @BAKName = @DBName + '_backup_' + @DateSerial + @BAKExtension; 
SET @Backup = @BackupLocation + @DBName; 
SET @BackupName = @DBName + ' Backup'; 
SET @BAKDesc = 'Backup of ' + @DBName; 
SET @SQL = 'Backup ' + @BackupTypeStr + SPACE(1) + 
        QUOTENAME(@DBName) + CHAR(10) + CHAR(9) + 
        'To Disk = ''' + @Backup + '\' + @BAKName + '''' + CHAR(10) + CHAR(9) + 
        'With Init,' + CHAR(10) + CHAR(9) + CHAR(9) + 
        'Description = ''' + @BAKDesc + ''',' + CHAR(10) + CHAR(9) + CHAR(9) + 
        'Name = ''' + @BackupName + ''';'; 

-- Make sure backup location exists 
-- Will not overwrite existing files, if any 
IF @Debug = 0 
  BEGIN 
        EXEC xp_create_subdir @Backup; 
  END 
ELSE 
  BEGIN 
        PRINT 'Exec xp_create_subdir ' + @Backup + ';'; 
  END 

BEGIN TRY 
        IF @Debug = 0 
          BEGIN 
                PRINT 'Backing up ' + @DBName; 
                EXEC sp_executesql @SQL; 
          END 
        ELSE 
          BEGIN 
                PRINT 'Print ''Backing up ' + @DBName + ''';'; 
                PRINT @SQL; 
          END 
END TRY 
BEGIN CATCH 
        SET @ErrNumber = ERROR_NUMBER(); 
        SET @ErrSeverity = ERROR_SEVERITY(); 
        SET @ErrState = ERROR_STATE(); 
        SET @ErrProcedure = ERROR_PROCEDURE(); 
        SET @ErrLine = ERROR_LINE(); 
        SET @ErrMsg = ERROR_MESSAGE(); 
         
        PRINT ''; 
        PRINT 'Database Name = ' + @DBName; 
        PRINT 'Error Number = ' + CAST(@ErrNumber AS VARCHAR); 
        PRINT 'Error Severity = ' + CAST(@ErrSeverity AS VARCHAR); 
        PRINT 'Error State = ' + CAST(@ErrState AS VARCHAR); 
        PRINT 'Error Procedure = ' + ISNULL(@ErrProcedure, ''); 
        PRINT 'Error Line = ' + CAST(@ErrLine AS VARCHAR); 
        PRINT 'Error Message = ' + @ErrMsg; 
        PRINT ''; 

        RAISERROR('Failed to back up database [%s].', 16, 1, @DBName); 
        RETURN; 
END CATCH 

SET @BackupFile = @Backup + '\' + @BAKName
