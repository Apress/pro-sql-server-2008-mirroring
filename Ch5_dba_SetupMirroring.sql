CREATE PROCEDURE dbo.dba_SetupMirroring 
        @DBName sysname, 
        @MirrorServer sysname, 
        @PrincipalPort INT = 5022, 
        @MirrorPort INT = 5023, 
        @WitnessServer sysname = NULL, 
        @WitnessPort INT = 5024, 
        @Debug bit = 0 
AS 

DECLARE @PrincipalServer sysname, 
        @CurrDBName sysname, 
        @BackupFile NVARCHAR(500), 
        @Results INT, 
        @Exists INT, 
        @SQL NVARCHAR(MAX), 
        @EPName sysname 

SET NOCOUNT ON 

SET @PrincipalServer = @@ServerName 
SET @CurrDBName = DB_NAME() 
SET @EPName = 'MirroringEndPoint' 

-- Make sure linked server to mirror exists 
EXEC @Results = dbo.dba_ManageLinkedServer  
                @ServerName = @ MirrorServer, 
                @Action = 'create' 

IF @Results <> 0 
  BEGIN 
        RETURN @Results; 
  END 

-- Make sure linked server to witness exists, if provided 
IF @WitnessServer IS NOT NULL 
  BEGIN 
        EXEC @Results = dbo.dba_ManageLinkedServer 
                        @ServerName = @WitnessServer, 
                        @Action = 'create' 

        IF @Results <> 0 
          BEGIN 
                RETURN @Results; 
          END 
  END 

-- Configure database for mirroring 
EXEC @Results = dbo.dba_ConfigureDBForMirroring @DBName = @DBName 

IF @Results <> 0 
  BEGIN 
        RETURN @Results; 
  END 

-- Back up the principal database 
EXEC @Results = dbo.dba_BackupDB @DBName = @DBName, 
        @BackupType = 0, -- 0 = Full, 1 = Log 
        -- Location where you want the backups saved 
        -- Allow procedure to choose the best location 
        -- @BackupLocation nvarchar(255) = null, 
        @Debug = @Debug, -- 0 = Execute, 1 = Return SQL for execution 
        @BackupFile = @BackupFile OUTPUT 

IF @Results <> 0 
  BEGIN 
        RETURN @Results; 
  END 

IF @BackupFile IS NULL 
  BEGIN 
        RAISERROR('Full backup failed for unknown reason.', 16, 1); 
        RETURN; 
  END 

-- Verify new backup exists 
EXEC @Results = xp_FileExist @BackupFile, @Exists OUTPUT 

IF @Results <> 0 
  BEGIN 
        RETURN @Results; 
  END 

IF @Exists = 0 
  BEGIN 
        RAISERROR('Full backup file not found after backup.', 16, 1); 
        RETURN; 
  END 

-- Restore full backup 
SET @SQL = 'Exec ' + QUOTENAME(@MirrorServer) + '.' + 
        QUOTENAME(@CurrDBName) + '.dbo.dba_RestoreDB' + CHAR(10) + CHAR(9) + 
        '@DBName = ''' + @DBName + ''',' + CHAR(10) + CHAR(9) + 
        '@BackupFile = ''' + @BackupFile + ''',' + CHAR(10) + CHAR(9) + 
        '@PrinServer = ''' + @PrincipalServer + ''',' + CHAR(10) + CHAR(9) + 
        '@Debug = ' + CAST(@Debug AS NVARCHAR) + ';' 
EXEC @Results = sp_executesql @SQL 

IF @Results <> 0 
  BEGIN 
        RETURN @Results; 
  END 

-- Backup log of principal database 
SET @BackupFile = NULL 

EXEC @Results = dbo.dba_BackupDB @DBName = @DBName, 
        @BackupType = 1, -- 0 = Full, 1 = Log 
        -- Location where you want the backups saved 
        -- Allow procedure to choose the best location 
        -- @BackupLocation nvarchar(255) = null, 
        @Debug = @Debug, -- 0 = Execute, 1 = Return SQL for execution 
        @BackupFile = @BackupFile OUTPUT 

IF @Results <> 0 
  BEGIN 
        RETURN @Results; 
  END 

IF @BackupFile IS NULL 
  BEGIN 
        RAISERROR('Log backup failed for unknown reason.', 16, 1); 
        RETURN; 
  END 

-- Verify new log backup exists 
EXEC @Results = xp_FileExist @BackupFile, @Exists OUTPUT 

IF @Results <> 0 
  BEGIN 
        RETURN @Results; 
  END 

IF @Exists = 0 
  BEGIN 
        RAISERROR('Log backup file not found after backup.', 16, 1); 
        RETURN; 
  END 

-- Restore log backup 
SET @SQL = 'Exec ' + QUOTENAME(@MirrorServer) + '.' + 
        QUOTENAME(@CurrDBName) + '.dbo.dba_RestoreDBLog' + CHAR(10) + CHAR(9) + 
        '@DBName = ''' + @DBName + ''',' + CHAR(10) + CHAR(9) + 
        '@BackupFile = ''' + @BackupFile + ''',' + CHAR(10) + CHAR(9) + 
        '@PrinServer = ''' + @PrincipalServer  + ''',' + CHAR(10) + CHAR(9) + 
        '@Debug = ' + CAST(@Debug AS NVARCHAR) + ';' 
EXEC @Results = sp_executesql @SQL 

IF @Results <> 0 
  BEGIN 
        RETURN @Results; 
  END 

-- Create EndPoint on Principal 
EXEC @Results = dbo.dba_CreateEndPoint 
                @EndPointName = @EPName, 
                @Port = @PrincipalPort, 
                @Debug = @Debug 

IF @Results <> 0 
  BEGIN 
        RETURN @Results; 
  END 

-- Create EndPoint on Mirror 
SET @SQL = 'Exec ' + QUOTENAME(@MirrorServer) + '.' + 
        QUOTENAME(@CurrDBName) + '.dbo.dba_CreateEndPoint' + CHAR(10) + CHAR(9) + 
        '@EndPointName = ''' + @EPName + ''',' + CHAR(10) + CHAR(9) + 
        '@Port = ' + CAST(@MirrorPort AS NVARCHAR) + ',' + CHAR(10) + CHAR(9) + 
        '@Debug = ' + CAST(@Debug AS NVARCHAR) + ';' 
EXEC @Results = sp_executesql @SQL 

IF @Results <> 0 
  BEGIN 
        RETURN @Results; 
  END 

-- Create EndPoint on Witness, if provided 
IF @WitnessServer IS NOT NULL 
  BEGIN 
        SET @SQL = 'Exec ' + QUOTENAME(@WitnessServer) + '.' + 
                QUOTENAME(@CurrDBName) + 
                '.dbo.dba_CreateEndPoint' + CHAR(10) + CHAR(9) + 
                '@EndPointName = ''' + @EPName + ''',' + CHAR(10) + CHAR(9) + 
                '@Port = ' + CAST(@WitnessPort AS NVARCHAR) + ',' + 
                CHAR(10) + CHAR(9) + 
                '@Debug = ' + CAST(@Debug AS NVARCHAR) + ';' 
        EXEC @Results = sp_executesql @SQL 

        IF @Results <> 0 
          BEGIN 
                RETURN @Results; 
          END 
  END 

-- Create service account logins and grant Connect 
-- On Principal 
EXEC @Results = dbo.dba_CheckLogins 
                @Server1 = @MirrorServer, 
                @Server2 = @WitnessServer, 
                @EPName = @EPName, 
                @Debug = @Debug -- 0 = Execute, 1 = Return SQL for execution 

IF @Results <> 0 
  BEGIN 
        RETURN @Results; 
  END 

-- Create service account logins and grant Connect 
-- On Mirror 
SET @SQL = 'Exec ' + QUOTENAME(@MirrorServer) + '.' + 
        QUOTENAME(@CurrDBName) + '.dbo.dba_CheckLogins' + CHAR(10) + CHAR(9) + 
        '@Server1 = ''' + @PrincipalServer + ''',' + CHAR(10) + CHAR(9) + 
        CASE WHEN @WitnessServer IS NOT NULL THEN 
        '@Server2 = ''' + @WitnessServer + ''',' + CHAR(10) + CHAR(9) 
        ELSE '' END + 
        '@EPName = ''' + @EPName + ''',' + CHAR(10) + CHAR(9) + 
        '@Debug = ' + CAST(@Debug AS NVARCHAR) + ';' 
EXEC @Results = sp_executesql @SQL; 

IF @Results <> 0 
  BEGIN 
        RETURN @Results; 
  END 

-- Create service account logins and grant Connect 
-- On Mirror 
IF @WitnessServer IS NOT NULL 
  BEGIN 
        SET @SQL = 'Exec ' + QUOTENAME(@MirrorServer) + '.' + 
                QUOTENAME(@CurrDBName) + '.dbo.dba_CheckLogins' +
                CHAR(10) + CHAR(9) + 
                '@Server1 = ''' + @PrincipalServer + ''',' + CHAR(10) + CHAR(9) + 
                '@Server2 = ''' + @MirrorServer + ''',' + CHAR(10) + CHAR(9) + 
                '@EPName = ''' + @EPName + ''',' + CHAR(10) + CHAR(9) + 
                '@Debug = ' + CAST(@Debug AS NVARCHAR) + ';' 
        EXEC @Results = sp_executesql @SQL; 

        IF @Results <> 0 
          BEGIN 
                RETURN @Results; 
          END 
  END 

-- Configure Partner on Mirror 
SET @SQL = 'Exec ' + QUOTENAME(@MirrorServer) + '.' + 
        QUOTENAME(@CurrDBName) + '.dbo.dba_SetPartner' + CHAR(10) + CHAR(9) + 
        '@Partner = ''' + @PrincipalServer + ''',' + CHAR(10) + CHAR(9) + 
        '@DBName = ''' + @DBName + ''',' + CHAR(10) + CHAR(9) + 
        '@Port = ' + CAST(@PrincipalPort AS NVARCHAR) + ',' + CHAR(10) + CHAR(9) + 
        '@IsWitness = 0,' + CHAR(10) + CHAR(9) + 
        '@Debug = ' + CAST(@Debug AS NVARCHAR) + ';' 
EXEC @Results = sp_executesql @SQL; 

IF @Results <> 0 
  BEGIN 
        RETURN @Results; 
  END 

-- Configure Partner on Principal 
EXEC @Results = dbo.dba_SetPartner 
                @Partner = @MirrorServer, 
                @DBName = @DBName, 
                @Port = @MirrorPort, 
                @IsWitness = 0, 
                @Debug = @Debug; 

IF @Results <> 0 
  BEGIN 
        RETURN @Results; 
  END 

-- Configure Witness on Principal, if provided 
IF @WitnessServer IS NOT NULL 
  BEGIN 
        EXEC @Results = dbo.dba_SetPartner 
                        @Partner = @WitnessServer, 
                        @DBName = @DBName, 
                        @Port = @WitnessPort, 
                        @IsWitness = 1, 
                        @Debug = @Debug; 

        IF @Results <> 0 
          BEGIN 
                RETURN @Results; 
          END 
  END 

-- Change operating mode if no witness 
IF @WitnessServer IS NULL 
  BEGIN 
        EXEC @Results = dbo.dba_SetOperatingMode 
                        @DBName = @DBName, 
                        @Debug = @Debug; 

        IF @Results <> 0 
          BEGIN 
                RETURN @Results; 
          END 
  END 

-- Display Mirroring status 
SELECT DBName = DB_NAME(database_id), 
        MirroringRole = mirroring_role_desc, 
        MirroringState = mirroring_state_desc, 
        SafetyLevel = mirroring_safety_level_desc, 
        MirrorName = mirroring_partner_instance, 
        MirrorFQDN = mirroring_partner_name, 
        WitnessName = mirroring_witness_name 
FROM sys.database_mirroring 
WHERE database_id = DB_ID(@DBName)
