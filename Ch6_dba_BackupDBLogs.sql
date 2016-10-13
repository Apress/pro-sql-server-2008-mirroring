CREATE PROCEDURE dbo.dba_BackupDBLogs 
  -- Database name or null for all databases
  @DBName sysname = NULL,
   -- Location where you want the backups 
  @LogBackupLocation NVARCHAR(255) = NULL, 
  -- log backup extension 
  @FileExtension NVARCHAR(3) = 'trn', 
  -- 0 = do not send alerts, 1 = send alerts
  @SendAlerts bit = 0, 
  @AlertRecipients VARCHAR(500) = NULL, 
  -- 0 = execute log backup, 1 = output the code without executing 
  @Debug bit = 0 
AS 

DECLARE @BakDir NVARCHAR(255), 
        @Exists INT, 
        @CurrID INT, 
        @MaxID INT, 
        @SQL NVARCHAR(1000), 
        @LogBackup NVARCHAR(500), 
        @DateSerial NVARCHAR(35), 
        @ErrNumber INT, 
        @ErrSeverity INT, 
        @ErrState INT, 
        @ErrProcedure sysname, 
        @ErrLine INT, 
        @ErrMsg NVARCHAR(2048), 
        @FailedDBs NVARCHAR(4000), 
        @Subject VARCHAR(255), 
        @Body VARCHAR(8000), 
        @ProfileName sysname 

DECLARE @DBs TABLE (DBID INT IDENTITY(1, 1) NOT NULL PRIMARY KEY, 
                    DBName sysname NOT NULL) 

DECLARE @FileExists TABLE (FileExists INT NOT NULL,  
                           FileIsDirectory INT NOT NULL,  
                           ParentDirectoryExists INT NOT NULL) 

DECLARE @Failures TABLE (FailId INT IDENTITY(1, 1) NOT NULL PRIMARY KEY, 
                         DBName sysname NOT NULL, 
                         ErrNumber INT NULL, 
                         ErrSeverity INT NULL, 
                         ErrState INT NULL, 
                         ErrProcedure sysname NULL, 
                         ErrLine INT NULL, 
                         ErrMsg NVARCHAR(2048) NULL) 

SET NOCOUNT ON 

SET @DateSerial = CONVERT(NVARCHAR, GETDATE(), 112) + 
          REPLACE(CONVERT(NVARCHAR, GETDATE(), 108), ':', '') 

IF @DBName IS NOT NULL 
  BEGIN 
    IF NOT EXISTS (SELECT 1 
                   FROM sys.databases 
                   WHERE name = @DBName) 
      BEGIN 
        RAISERROR ('The specified database [%s] does not exist. 
                   Please check the name entered or do not supply
                   a database name if you want to back up the log 
                   for all online databases using the full or 
                   bulk-logged recovery model.', 16, 1, @DBName); 
        RETURN; 
      END 
         
    IF EXISTS (SELECT 1 
               FROM sys.databases 
               WHERE name = @DBName AND 
                     state > 0) 
      BEGIN 
        RAISERROR ('The specified database [%s] is not online.
                    Please check the name entered or do not supply
                    a database name if you want to back up the log 
                    for all online databases using the full or 
                    bulk-logged recovery model.', 16, 1, @DBName); 
        RETURN; 
      END 
         
    IF EXISTS (SELECT 1 
               FROM sys.databases 
               WHERE name = @DBName AND 
                     recovery_model = 3) 
      BEGIN 
        RAISERROR ('The specified database [%s] is using the simple 
                    recovery model. Please check the name entered or
                    do not supply a database name if you want to back up
                    the log for all online databases using the full or 
                    bulk-logged recovery model.', 16, 1, @DBName); 
        RETURN; 
      END 
         
    IF EXISTS (SELECT 1 
               FROM sys.databases 
               WHERE name = @DBName AND 
                     source_database_id IS NOT NULL) 
      BEGIN 
        RAISERROR ('The specified database [%s] is a database snapshot.
                    Please check the name entered or do not supply 
                    a database name if you want to back up the log 
                    for all online databases using the full or 
                    bulk-logged recovery model.', 16, 1, @DBName); 
        RETURN; 
      END 
         
    IF EXISTS (SELECT 1 
               FROM msdb.dbo.log_shipping_primary_databases 
               WHERE primary_database = @DBName) 
      BEGIN 
        RAISERROR ('The specified database [%s] is a log shipping 
                    primary and cannot have its log file backed up.
                    Please check the name entered or do not supply 
                    a database name if you want to back up the log 
                    for all online databases using the full or 
                    bulk-logged recovery model.', 16, 1, @DBName); 
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
        FROM @FileExists 
                 
        IF @Exists = 1 
          BEGIN 
            SET @LogBackupLocation = @BakDir; 
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
    WHERE NOT EXISTS (SELECT 1 
                      FROM msdb.dbo.log_shipping_primary_databases 
                      WHERE primary_database = BS.database_name) 
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

INSERT INTO @DBs (DBName) 
SELECT name 
FROM sys.databases D 
WHERE state = 0 AND --online 
      -- 1 = Full, 2 = Bulk-logged, 3 = Simple 
      -- (log backups not needed for simple recovery model) 
      recovery_model IN (1, 2) AND
      -- No log backups for core system databases 
      name NOT IN ('master', 'tempdb', 'msdb', 'model') AND
      -- If is not null, database is a database snapshot 
      -- and can not be backed up 
      source_database_id IS NULL AND
      -- Backing up the log of a log-shipped database will 
      -- break the log shipping log chain 
      NOT EXISTS (SELECT 1 
                  FROM msdb.dbo.log_shipping_primary_databases 
                  WHERE primary_database = D.name) AND
      (name = @DBName OR 
       @DBName IS NULL); 

SELECT @MaxID = MAX(DBID), @CurrID = 1 
FROM @DBs; 

WHILE @CurrID <= @MaxID 
  BEGIN 
    SELECT @DBName = DBName 
    FROM @DBs 
    WHERE DBID = @CurrID; 

    SET @LogBackup = @LogBackupLocation + @DBName + '\'; 

    -- Make sure backup location exists 
    -- Will not overwrite existing files, if any 
    IF @Debug = 0 
      BEGIN 
        EXEC xp_create_subdir @LogBackup; 
      END 
    ELSE 
      BEGIN 
        PRINT 'Exec xp_create_subdir ' + @LogBackup + ';'; 
      END 

    SET @LogBackup = 
        @LogBackup + @DBName + @DateSerial + '.' + @FileExtension 

    SET @SQL = 'Backup Log ' + QUOTENAME(@DBName) + 
               ' To Disk = ''' + @LogBackup + ''';'; 

    BEGIN TRY 
      IF @Debug = 0 
        BEGIN 
          PRINT 'Backing up the log for ' + @DBName; 
          EXEC sp_executesql @SQL; 
        END 
      ELSE 
        BEGIN 
          PRINT 'Print ''Backing up the log for ' + @DBName + ''';'; 
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
                 
      INSERT INTO @Failures 
         (DBName, ErrNumber, ErrSeverity, ErrState, 
          ErrProcedure, ErrLine, ErrMsg) 
      SELECT @DBName, @ErrNumber, @ErrSeverity, @ErrState, 
             @ErrProcedure, @ErrLine, @ErrMsg 
    END CATCH 

    SET @CurrID = @CurrID + 1; 
  END 

IF EXISTS (SELECT 1 
           FROM @Failures) 
  BEGIN 
    SELECT @MaxID = MAX(FailId), @CurrID = 1 
    FROM @Failures 
         
    WHILE @CurrID <= @MaxID 
      BEGIN 
        SELECT @DBName = DBName, 
               @ErrNumber = ErrNumber, 
               @ErrSeverity = ErrSeverity, 
               @ErrState = ErrState, 
               @ErrProcedure = ErrProcedure, 
               @ErrLine = ErrLine, 
               @ErrMsg = ErrMsg 
        FROM @Failures 
        WHERE FailId = @CurrID 
                 
        PRINT ''; 
        PRINT 'Database Name = ' + @DBName; 
        PRINT 'Error Number = ' + CAST(@ErrNumber AS VARCHAR); 
        PRINT 'Error Severity = ' + CAST(@ErrSeverity AS VARCHAR); 
        PRINT 'Error State = ' + CAST(@ErrState AS VARCHAR); 
        PRINT 'Error Procedure = ' + ISNULL(@ErrProcedure, ''); 
        PRINT 'Error Line = ' + CAST(@ErrLine AS VARCHAR); 
        PRINT 'Error Message= ' + @ErrMsg; 
        PRINT ''; 
                 
        SET @CurrID = @CurrID + 1 
      END 

      SELECT @FailedDBs = 
             ISNULL(@FailedDBs + ', ', '') + QUOTENAME(DBName) 
      FROM @Failures 
         
      IF @SendAlerts = 1 AND 
         @AlertRecipients IS NOT NULL 
        BEGIN 
          IF EXISTS (SELECT 1 
                     FROM sys.configurations 
                     WHERE name = 'Database Mail XPs') 
            BEGIN 
              SELECT TOP (1) @ProfileName = name 
              FROM msdb.dbo.sysmail_profile P WITH(nolock) LEFT JOIN 
                   msdb.dbo.sysmail_principalprofile PP 
                     ON PP.profile_id = P.profile_id 
              ORDER BY PP.is_default DESC 
                 
              SET @Subject = 'Backup failures on ' + 
                              CAST(@@SERVERNAME AS VARCHAR(255)) 
              SET @Body = 'Unable to back up the following databases: ' + 
                          @FailedDBs 
                         
              EXEC msdb..sp_send_dbmail 
                           @profile_name = @ProfileName, 
                           @recipients = @AlertRecipients, 
                           @Subject = @Subject, 
                           @body = @Body 
            END 
        END 
         
    RAISERROR ('Unable to back up the following databases: %s',
                1, 1, @FailedDBs); 
  END
