CREATE PROCEDURE dbo.dba_RestoreDB  
        @DBName sysname, 
        @BackupFile NVARCHAR(500), 
        @PrinServer sysname, 
        @Debug bit = 0 -- 0 = Execute, 1 = Return SQL for execution 
AS 

DECLARE @DBID INT, 
        @UNCBackupFile NVARCHAR(500), 
        @Exists INT, 
        @SQL NVARCHAR(MAX), 
        @SQLVersion INT, 
        @MaxID INT, 
        @CurrID INT, 
        @PhysicalName NVARCHAR(260), 
        @Movelist NVARCHAR(MAX) 
DECLARE @Files TABLE (FileID INT NOT NULL PRIMARY KEY, 
                LogicalName NVARCHAR(128) NULL, 
                PhysicalName NVARCHAR(260) NULL, 
                [Type] CHAR(1) NULL, 
                FileGroupName NVARCHAR(128) NULL, 
                [Size] numeric(20,0) NULL, 
                [MaxSize] numeric(20,0) NULL, 
                CreateLSN numeric(25,0), 
                DropLSN numeric(25,0) NULL, 
                UniqueID uniqueidentifier, 
                ReadOnlyLSN numeric(25,0) NULL, 
                ReadWriteLSN numeric(25,0) NULL, 
                BackupSizeInBytes bigint, 
                SourceBlockSize INT, 
                FileGroupID INT, 
                LogGroupGUID uniqueidentifier NULL, 
                DifferentialBaseLSN numeric(25,0) NULL, 
                DifferentialBaseGUID uniqueidentifier, 
                IsReadOnly bit, 
                IsPresent bit, 
                TDEThumbprint varbinary(32) NULL, 
                NewPhysicalName NVARCHAR(260) NULL) 

SET NOCOUNT ON 

SET @DBID = DB_ID(@DBName); 
SET @SQLVersion = PARSENAME(CAST(SERVERPROPERTY('ProductVersion') AS sysname), 4) 

IF @DBID IS NOT NULL 
  BEGIN 
        IF EXISTS (SELECT 1 FROM sys.databases 
                WHERE database_id = @DBID 
                AND state = 0) -- online 
          BEGIN 
                SET @SQL = 'Alter Database ' + QUOTENAME(@DBName) + 
                        ' Set Offline With Rollback Immediate;'; 

                IF @Debug = 1 
                  BEGIN 
                        PRINT @SQL; 
                  END 
                ELSE 
                  BEGIN 
                        EXEC sp_executesql @SQL; 
                  END 
          END 
         
        PRINT 'Dropping existing database'; 
        SET @SQL = 'Drop Database ' + QUOTENAME(@DBName) + ';'; 
        IF @Debug = 1 
          BEGIN 
                PRINT @SQL; 
          END 
        ELSE 
          BEGIN 
                EXEC sp_executesql @SQL; 
          END 
  END 

-- Convert bakup path to UNC 
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

SET @SQL  = 'Restore FileListonly From Disk = ''' + @UNCBackupFile + ''';'; 

-- Check file paths specified in backup 
IF @SQLVersion = 9 
  BEGIN 
      INSERT INTO @Files (LogicalName, PhysicalName, [Type], FileGroupName, [Size], 
                  [MaxSize], FileID, CreateLSN, DropLSN, UniqueId, ReadOnlyLSN, 
                  ReadWriteLSN, BackupSizeInBytes, SourceBlockSize, FileGroupId, 
                  LogGroupGUID, DifferentialBaseLSN, DifferentialBaseGUID, 
                  IsReadOnly, IsPresent) 
      EXEC sp_executesql @SQL 
  END 
ELSE 
  BEGIN 
      INSERT INTO @Files (LogicalName, PhysicalName, [Type], FileGroupName, [Size], 
                  [MaxSize], FileID, CreateLSN, DropLSN, UniqueId, ReadOnlyLSN, 
                  ReadWriteLSN, BackupSizeInBytes, SourceBlockSize, FileGroupId, 
                  LogGroupGUID, DifferentialBaseLSN, DifferentialBaseGUID, 
                  IsReadOnly, IsPresent , TDEThumbprint) 
      EXEC sp_executesql @SQL; 
  END 

SELECT @MaxID = MAX(FileId), @CurrID = 1 
FROM @Files 

WHILE @CurrID <= @MaxID 
  BEGIN 
        SELECT @PhysicalName = PhysicalName 
        FROM @Files 
        WHERE FileID = @CurrID 
         
        -- Check if file already exists 
        EXEC xp_FileExist @PhysicalName, @Exists OUTPUT 

        -- Change physical name if the file already exists 
        IF @Exists = 1 
          BEGIN 
                SET @PhysicalName = LEFT(@PhysicalName, LEN(@PhysicalName) - 4) + 
                                '_mirr' + RIGHT(@PhysicalName, 4) 
          END 

        UPDATE @Files 
        SET NewPhysicalName = @PhysicalName 
        WHERE FileID = @CurrID 

        SET @CurrID = @CurrID + 1 
  END 

-- Build the "With Move" portion of the Restore command 
SELECT @Movelist = ISNULL(@MoveList + ',' + CHAR(10) + CHAR(9), '') + 
                'Move ''' + LogicalName + ''' To ''' +  
                NewPhysicalName + '''' 
FROM @Files 
ORDER BY [Type] 

SET @SQL = 'Restore Database ' + QUOTENAME(@DBName) + CHAR(10) + CHAR(9) + 
        'From Disk = ''' + @UNCBackupFile + '''' + CHAR(10) + CHAR(9) + 
        'With NoRecovery, Stats = 10, NoUnload,' + CHAR(10) + CHAR(9) + 
        @Movelist 

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
