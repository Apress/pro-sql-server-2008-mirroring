CREATE PROCEDURE dbo.dba_ShrinkMirroredDatabases 
    -- database to shrink; all mirrored databases if null 
    @DBName sysname = NULL, 
    -- target size for shrink operation. Defaults to 5 GB (5120 MB) 
    @TargetSize INT = 5120, 
    -- 0 = Execute it, 1 = Output SQL that would be executed 
    @Debug bit = 0 
AS 

DECLARE @CurrID INT, 
        @MaxID INT, 
        @DefaultTargetSize INT, 
        @FileName sysname, 
        @FileSize INT, 
        @NewFileSize INT, 
        @SQL NVARCHAR(MAX), 
        @ErrMsg NVARCHAR(500) 

DECLARE @MirroredDBs TABLE 
       (MirroredDBID INT IDENTITY(1, 1) NOT NULL PRIMARY KEY, 
        DBName sysname NOT NULL, 
        LogFileName sysname NOT NULL, 
        FileSize INT NOT NULL) 

SET NOCOUNT ON 
  
-- Assume entered as GB and convert to MB 
IF @TargetSize < 20 
  BEGIN 
    SET @TargetSize = @TargetSize * 1024 
  END
 
-- Assume entered as MB and use 512 
ELSE IF @TargetSize <= 512 
  BEGIN 
    SET @TargetSize = 512 
  END
 
-- Assume entered as KB and return warning 
ELSE IF @TargetSize > 19922944 
  BEGIN 
    SET @ErrMsg = 'Please enter a valid target size less than 20 GB. ' + 
                  'Amount entered can be in GB (max size = 19), ' +
                  'MB (max size = 19456), or ' + 
                  'KB (max size = 19922944).'; 
    GOTO ErrComplete; 
  END
 
-- Assume entered as KB and convert to MB 
ELSE IF @TargetSize > 525311 
  BEGIN 
    SET @TargetSize = 525311 / 1024 
  END
 
-- Assume entered as KB and use 512 as converted MB 
ELSE IF @TargetSize > 19456 
  BEGIN 
    SET @TargetSize = 512 
  END
 
-- Else assume entered as MB and use as entered 
INSERT INTO @MirroredDBs 
           (DBName, LogFileName, FileSize) 
SELECT DB_NAME(MF.database_id), 
       MF.[name], 
       -- Size = number of 8K pages 
       CEILING(MF.[size] * 8 / 1024.0) 
FROM sys.master_files MF INNER JOIN 
     sys.database_mirroring DM 
       ON DM.database_id = MF.database_id 
WHERE MF.[type] = 1 AND -- log file 
      DM.Mirroring_Role = 1 AND -- Principal partner 
      -- Specified database or all databases if null 
     (MF.database_id = @DBName OR
      @DBName IS NULL) 

IF NOT EXISTS (SELECT 1 
               FROM @MirroredDBs) 
  BEGIN 
    SET @ErrMsg = CASE WHEN @DBName IS NOT NULL 
                    THEN 
                      'Database ' + QUOTENAME(@DBName) +  
                      ' was either not found or is not' +
                      ' a mirroring principal.' 
                    ELSE 
                      'No databases were found in the ' +
                      'mirroring principal role.' 
                  END; 
    GOTO ErrComplete; 
  END 
ELSE 
  BEGIN 
    SELECT @MaxID = MAX(MirroredDBID), 
           @CurrID = 1 
    FROM @MirroredDBs 

    WHILE @CurrID <= @MaxID 
      BEGIN 
        SELECT @DBName = DBName, 
               @FileName = LogFileName, 
               @FileSize = FileSize 
        FROM @MirroredDBs 
        WHERE MirroredDBID = @CurrID 

        IF @FileSize > @TargetSize 
          BEGIN 
            SET @SQL = 'Use ' + QUOTENAME(@DBName) + ';' + 
                       'DBCC ShrinkFile(''' + @FileName + ''', ' + 
                        CAST(@TargetSize AS NVARCHAR) + ');' 

            IF @Debug = 0 
              BEGIN 
                EXEC sp_executesql @SQL 
              END 
            ELSE 
              BEGIN 
                PRINT @SQL 
              END 

            SELECT -- Size = number of 8K pages 
                   @NewFileSize = CEILING(([size] + 1) * 8) 
            FROM sys.master_files 
            WHERE [type] = 1 AND -- log file 
                  [name] = @FileName AND
                  database_id = DB_ID(@DBName) 

            IF @NewFileSize < @FileSize 
              BEGIN 
                SET @SQL = 'Alter Database ' + QUOTENAME(@DBName) + 
                           ' Modify File (name = ' + @FileName + 
                           ', size = ' + 
                           CAST(@NewFileSize AS NVARCHAR) + 'KB);' 

                IF @Debug = 0 
                  BEGIN 
                    EXEC sp_executesql @SQL 
                  END 
                ELSE 
                  BEGIN 
                    PRINT @SQL 
                  END 
                END 
              END 

      SET @CurrID = @CurrID + 1 
    END 
  END 

Success: 
  GOTO Complete; 
ErrComplete: 
  RAISERROR (@ErrMsg, 1, 1) 
  RETURN 
Complete:
