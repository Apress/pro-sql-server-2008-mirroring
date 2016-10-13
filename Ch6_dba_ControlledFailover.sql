CREATE PROCEDURE dbo.dba_ControlledFailover 
    -- database to fail back; all applicable databases if null 
    @DBName sysname = NULL, 
    -- @MaxCounter = max # of loops, each loop = 5 seconds 
    -- 60 loops = 5 minutes 
    @MaxCounter INT = 60, 
    -- 0 = Execute it, 1 = Output SQL that would be executed 
    @Debug bit = 0 
AS 

DECLARE @SQL NVARCHAR(1000), 
        @MaxID INT, 
        @CurrID INT, 
        @DMState INT, 
        @SafeCounter INT, 
        @PartnerServer sysname, 
        @SafetyLevel INT, 
        @TrustWorthyOn bit, 
        @DBOwner sysname, 
        @Results INT, 
        @ErrMsg VARCHAR(500), 
        @Print NVARCHAR(1000) 
DECLARE @Databases TABLE 
       (DatabaseID INT IDENTITY(1, 1) NOT NULL PRIMARY KEY, 
        DatabaseName sysname NOT NULL, 
        PartnerServer sysname NOT NULL, 
        SafetyLevel INT NOT NULL, 
        TrustWorthyOn bit NOT NULL, 
        DBOwner sysname NULL) 

SET NOCOUNT ON 

INSERT INTO @Databases 
       (DatabaseName, 
        PartnerServer, 
        SafetyLevel, 
        TrustWorthyOn, 
        DBOwner) 
SELECT D.name, 
       DM.mirroring_partner_instance, 
       DM.mirroring_safety_level, 
       D.is_trustworthy_on, 
       SP.name 
FROM sys.database_mirroring DM INNER JOIN 
     sys.databases D 
       ON D.database_id = DM.database_id LEFT JOIN 
     sys.server_principals SP 
       ON SP.sid = D.owner_sid 
WHERE DM.mirroring_role = 1 AND -- Principal role 
      DM.mirroring_state IN (2, 4) AND -- Synchronizing, Synchronized 
     (D.name = @DBName OR
      @DBName IS NULL) 

IF NOT EXISTS (SELECT 1 
               FROM @Databases) AND
               @DBName IS NULL 
  BEGIN 
    RAISERROR ('There were no mirroring principals found on this server.',
                1, 1); 
  END 

IF NOT EXISTS (SELECT 1 
               FROM @Databases) AND 
               @DBName IS NOT NULL 
  BEGIN 
    RAISERROR ('Database [%s] was not found or is not a mirroring principal 
                on this server.', 1, 1, @DBName); 
  END 

SELECT @MaxID = MAX(DatabaseID), 
       @CurrID = 1 
FROM @Databases 

-- Set Safety to Full on all databases first, if needed 
WHILE @CurrID <= @MaxID 
  BEGIN 
    SELECT @DBName = DatabaseName, 
           @PartnerServer = PartnerServer, 
           @SafetyLevel = SafetyLevel 
    FROM @Databases 
    WHERE DatabaseID = @CurrID 
         
    -- Make sure linked server to mirror exists 
    EXEC @Results = dbo.dba_ManageLinkedServer 
         @ServerName = @PartnerServer, 
         @Action = 'create' 

    IF @Results <> 0 
      BEGIN 
        RAISERROR ('Failed to create linked server to mirror instance
                   [%s].', 1, 1, @PartnerServer); 
      END 

    IF @SafetyLevel = 1 
      BEGIN 
        SET @SQL = 'Alter Database ' + QUOTENAME(@DBName) + 
                   ' Set Partner Safety Full;' 
                 
        SET @Print = 'Setting Safety on for database ' + 
                      QUOTENAME(@DBName) + '.'; 
                 
        IF @Debug = 0 
          BEGIN 
            PRINT @Print 
            EXEC sp_executesql @SQL 
          END 
        ELSE 
          BEGIN 
            PRINT '-- ' + @Print 
            PRINT @SQL; 
          END 
        END 

    SET @CurrID = @CurrID + 1 
  END 

-- Reset @CurrID to 1 
SET @CurrID = 1 

-- Pause momentarily 
WAITFOR Delay '0:00:03'; 

-- Failover all databases 
WHILE @CurrID <= @MaxID 
  BEGIN 
    SELECT @DBName = DatabaseName, 
           @DMState = DM.mirroring_state, 
           @SafeCounter = 0, 
           @SafetyLevel = SafetyLevel 
    FROM @Databases D INNER JOIN 
         sys.database_mirroring DM 
           ON DM.database_id = DB_ID(D.DatabaseName) 
    WHERE DatabaseID = @CurrID         
         
    WHILE @DMState = 2 AND -- Synchronizing 
          @SafeCounter < @MaxCounter 
      BEGIN 
        WAITFOR Delay '0:00:05'; 

        SELECT @DMState = mirroring_state, 
               @SafeCounter = @SafeCounter + 1 
        FROM sys.database_mirroring  
        WHERE database_id = DB_ID(@DBName) 
      END 

      IF @DMState = 2 AND @SafeCounter = @MaxCounter 
        BEGIN 
          RAISERROR('Synchronization timed out for database [%s].
                     Please check and fail over manually.', 1, 1, @DBName); 
                 
      IF @SafetyLevel = 1 
        BEGIN 
          SET @SQL = 'Alter Database ' + QUOTENAME(@DBName) + 
                     ' Set Partner Safety Full;' 
                         
          SET @Print = 'Setting Safety Full for database ' + 
                        QUOTENAME(@DBName) + '.'; 
                         
          IF @Debug = 0 
            BEGIN 
              PRINT @Print 
              EXEC sp_executesql @SQL 
            END 
          ELSE 
            BEGIN 
              PRINT '-- ' + @Print 
              PRINT @SQL; 
            END 
          END 
        END 
      ELSE 
        BEGIN 
          SET @SQL = 'Alter Database ' + QUOTENAME(@DBName) + 
                     ' Set Partner Failover;' 

          SET @Print = 'Failing over database ' + QUOTENAME(@DBName) + '.'; 
                 
          IF @Debug = 0 
            BEGIN 
              PRINT @Print 
              EXEC sp_executesql @SQL 
            END 
          ELSE 
            BEGIN 
              PRINT '-- ' + @Print 
              PRINT @SQL; 
            END 
        END 

    SET @CurrID = @CurrID + 1 
  END 

-- Reset @CurrID to 1 
SET @CurrID = 1 

-- Pause momentarily 
WAITFOR Delay '0:00:03'; 

-- Set safety level and db owner on failed over databases 
WHILE @CurrID <= @MaxID 
  BEGIN 
    SELECT @DBName = DatabaseName, 
           @PartnerServer = PartnerServer, 
           @SafetyLevel = SafetyLevel, 
           @TrustWorthyOn = TrustWorthyOn, 
           @DBOwner = DBOwner, 
           @DMState = DM.mirroring_state, 
           @SafeCounter = 0 
    FROM @Databases D INNER JOIN
         sys.database_mirroring DM 
           ON DM.database_id = DB_ID(D.DatabaseName) 
    WHERE DatabaseID = @CurrID 
         
    -- Make sure linked server to mirror exists 
    EXEC @Results = dbo.dba_ManageLinkedServer 
         @ServerName = @PartnerServer, 
         @Action = 'create' 
         
    WHILE @DMState = 2 AND -- Synchronizing 
          @SafeCounter < @MaxCounter 
      BEGIN 
        WAITFOR Delay '0:00:05'; 

        SELECT @DMState = mirroring_state, 
               @SafeCounter = @SafeCounter + 1 
        FROM sys.database_mirroring  
        WHERE database_id = DB_ID(@DBName) 
      END 
         
    IF @DMState = 2 AND 
       @SafeCounter = @MaxCounter 
      BEGIN 
        RAISERROR('Synchronization timed out for database [%s]
                   after failover. Please check and set 
                   database options manually.', 1, 1, @DBName); 
      END 
    ELSE 
      BEGIN 
        -- Turn safety off if it was originally off 
        IF @SafetyLevel = 1 
          BEGIN 
            SET @SQL = 'Alter Database ' + QUOTENAME(@DBName) + 
                       'Set Partner Safety Off;' 

            SET @SQL = 'Exec ' + QUOTENAME(@PartnerServer) + 
                       '.master.sys.sp_executesql N''' + @SQL + ''';'; 
                         
            SET @Print = 'Setting Safety off for database ' + 
                          QUOTENAME(@DBName) + 
                         ' on server ' + QUOTENAME(@PartnerServer) + '.'; 
                         
            IF @Debug = 0 
              BEGIN 
                PRINT @Print 
                EXEC sp_executesql @SQL 
              END 
            ELSE 
              BEGIN 
                PRINT '-- ' + @Print 
                PRINT @SQL; 
              END 
        END 
                 
    -- Set TrustWorthy property on if it was originally on 
    IF @TrustWorthyOn = 1 
      BEGIN 
        SET @SQL = 'Alter Database ' + QUOTENAME(@DBName) + 
                   ' Set TrustWorthy On;' 

        SET @SQL = 'EXEC ' + QUOTENAME(@PartnerServer) + 
                   '.master.sys.sp_executesql N''' + @SQL + ''';'; 
                         
        SET @Print = 'Setting TrustWorthy On for database ' + 
                      QUOTENAME(@DBName) + 
                     ' on server ' + QUOTENAME(@PartnerServer) + '.'; 
                         
        IF @Debug = 0 
          BEGIN 
            PRINT @Print 
            EXEC sp_executesql @SQL 
          END 
        ELSE 
          BEGIN 
            PRINT '-- ' + @Print 
            PRINT @SQL; 
          END 
      END 
                 
      -- Change database owner if different than original 
      SET @SQL = 'If Exists (Select 1 From sys.databases D' + 
                  CHAR(10) + CHAR(9) + 
                 'Left Join sys.server_principals P' + 
                 ' On P.sid = D.owner_sid' + CHAR(10) + CHAR(9) + 
                 'Where P.name Is Null' + CHAR(10) + CHAR(9) + 
                 'Or P.name <> ''' + @DBOwner + ''')' + CHAR(10) + 
                  CHAR(9) + 
                 'Exec ' + QUOTENAME(@DBName) + 
                 '..sp_changedbowner ''' + @DBOwner + ''';' 

      SET @SQL = REPLACE(@SQL, '''', '''''') 
      SET @SQL = 'Exec ' + QUOTENAME(@PartnerServer) + 
                 '.master.sys.sp_executesql N''' + @SQL + ''';'; 
                 
      SET @Print = 'Changing Database owner to ' + QUOTENAME(@DBOwner) + 
                   ' for database ' + QUOTENAME(@DBName) + 
                   ' on server ' + QUOTENAME(@PartnerServer) + '.'; 
                 
      IF @Debug = 0 
        BEGIN 
          PRINT @Print 
          EXEC sp_executesql @SQL 
        END 
      ELSE 
        BEGIN 
          PRINT '-- ' + @Print 
          PRINT @SQL; 
        END 
    END 

    SET @CurrID = @CurrID + 1 
  END
