CREATE PROCEDURE dbo.dba_DeleteLogBackups 
    -- Name of database, all databases if null 
    @DBName sysname = NULL, 
    -- Location of log backups 
    @LogBackupLocation NVARCHAR(255) = NULL, 
    -- log backup extension 
    @FileExtension NVARCHAR(3) = 'trn', 
    @Retention INT = 4, -- days 
    -- 0 = execute deletion of log backup,
    -- 1 = output the code without executing 
    @Debug bit = 0 
AS 

DECLARE @DeleteDate NVARCHAR(19), 
        @BakDir NVARCHAR(255), 
        @Exists INT 

DECLARE @FileExists TABLE (FileExists INT NOT NULL,  
                           FileIsDirectory INT NOT NULL,  
                           ParentDirectoryExists INT NOT NULL) 

SET NOCOUNT ON 

SET @DeleteDate = CONVERT(NVARCHAR(19), 
                  DATEADD(DAY, -@Retention, GETDATE()), 126) 

IF @DBName IS NOT NULL 
  BEGIN 
    IF NOT EXISTS (SELECT 1 
                   FROM sys.databases 
                   WHERE name = @DBName) 
      BEGIN 
        RAISERROR ('The specified database [%s] does not exist. 
                    Please  check the name entered or do not supply
                    a database name if you want to delete  the 
                    log backups for all databases.', 16, 1, @DBName); 
        RETURN; 
      END 
  END 

IF @LogBackupLocation IS NULL 
  BEGIN 
    EXEC xp_instance_regread 
            N'HKEY_LOCAL_MACHINE',  
            N'Software\Microsoft\MSSQLServer\MSSQLServer',  
            N'BackupDirectory',  
            @BakDir output,  
            'no_output'; 

    IF @BakDir IS NOT NULL 
      BEGIN 
        INSERT INTO @FileExists 
        EXEC sys.xp_fileexist @BakDir; 

        SELECT @Exists = ParentDirectoryExists 
        FROM @FileExists; 
                 
        IF @Exists = 1 
          BEGIN 
            SET @LogBackupLocation = @BakDir + ISNULL('\' + @DBName, ''); 
          END 
      END 
  END 

IF @LogBackupLocation IS NULL 
  BEGIN 
    SELECT TOP 1 @BakDir = LEFT(MF.physical_device_name, 
           LEN(MF.physical_device_name) - 
           CHARINDEX('\', REVERSE(MF.physical_device_name))) 
    FROM msdb.dbo.backupset BS INNER JOIN 
         msdb.dbo.backupmediafamily MF 
           ON MF.media_set_id = BS.media_set_id 
    -- log backups first, then differentials, then full backups 
    ORDER BY BS.type DESC, 
          BS.backup_finish_date DESC; -- newest first 

    IF @BakDir IS NOT NULL 
      BEGIN 
        DELETE FROM @FileExists 

        INSERT INTO @FileExists 
        EXEC sys.xp_fileexist @BakDir; 

        SELECT @Exists = ParentDirectoryExists 
        FROM @FileExists 
                 
        IF @Exists = 1 
          BEGIN 
            SET @LogBackupLocation = @BakDir; 
          END 
      END 
  END 

IF @LogBackupLocation IS NOT NULL 
  BEGIN 
    IF RIGHT(@LogBackupLocation, 1) <> '\' 
      SET @LogBackupLocation = @LogBackupLocation + '\'; 
  END 
ELSE 
  BEGIN 
    RAISERROR ('Backup location not specified or not found.', 16, 1); 
    RETURN; 
  END 

IF @Debug = 0 
  BEGIN 
    EXEC sys.xp_delete_file 
           0, 
           @LogBackupLocation,  
           @FileExtension,  
           @DeleteDate,  
           1; 
  END 
ELSE 
  BEGIN 
    PRINT 'Exec sys.xp_delete_file 0, ''' + @LogBackupLocation + 
          ''', ''' + @FileExtension + ''', ''' + 
          @DeleteDate + ''', 1;'; 
  END
