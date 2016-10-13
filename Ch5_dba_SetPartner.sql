CREATE PROCEDURE dbo.dba_SetPartner   
        @Partner sysname, 
        @DBName sysname, 
        @Port INT, 
        @IsWitness bit = 0,  
        @Debug bit = 0 
AS 

DECLARE @PartnerFQDN NVARCHAR(300), 
        @PartnerRole NVARCHAR(7), 
        @SQL NVARCHAR(100), 
        @OrigShowAdvanced INT, 
        @OrigXPCmdShell INT, 
        @CmdShell NVARCHAR(200) 
DECLARE @Ping TABLE (PingID INT IDENTITY(1, 1) NOT NULL PRIMARY KEY, 
                PingText VARCHAR(1000) NULL) 

SET NOCOUNT ON 

-- If SQL Instance, parse out machine name 
IF CHARINDEX('\', @Partner) > 0 
        SET @Partner = LEFT(@Partner, CHARINDEX('\', @Partner) - 1) 

IF @IsWitness = 0 
  BEGIN 
        SET @PartnerRole = 'Partner' 
  END 
ELSE 
  BEGIN 
        SET @PartnerRole = 'Witness' 
  END 

                                                                 
-- Check if xp_cmdshell and show advanced options is enabled 
SELECT @OrigShowAdvanced = CAST(value_in_use AS INT) 
FROM sys.configurations 
WHERE name = 'show advanced options' 

SELECT @OrigXPCmdShell = CAST(value_in_use AS INT) 
FROM sys.configurations 
WHERE name = 'xp_cmdshell' 

-- If disabled, enable xp_cmdshell 
IF @OrigXPCmdShell = 0 
  BEGIN 
        IF @OrigShowAdvanced = 0 
          BEGIN 
                EXEC sp_configure 'show advanced options', 1; 
                RECONFIGURE; 
          END 
        EXEC sp_configure 'xp_cmdshell', 1; 
        RECONFIGURE; 
  END 

SET @CmdShell = 'ping ' + @Partner 

INSERT INTO @Ping (PingText) 
EXEC xp_cmdshell @CmdShell 

-- If originally disabled, disable xp_cmdshell again 
IF @OrigXPCmdShell = 0 
  BEGIN 
        EXEC sp_configure 'xp_cmdshell', 0; 
        RECONFIGURE; 

        IF @OrigShowAdvanced = 0 
          BEGIN 
                EXEC sp_configure 'show advanced options', 0; 
                RECONFIGURE; 
          END 
  END 

DELETE FROM @Ping 
WHERE PingText NOT LIKE 'Pinging%' 
OR PingText IS NULL 

SELECT @PartnerFQDN = SUBSTRING(PingText, 9, CHARINDEX(SPACE(1), PingText, 9) - 9) 
FROM @Ping 

SET @PartnerFQDN = 'TCP://' + @PartnerFQDN + ':' + CAST(@Port AS NVARCHAR) 

SET @SQL = 'Alter Database ' + QUOTENAME(@DBName) + 
        ' Set ' + @PartnerRole + ' = ''' + @PartnerFQDN + ''';' 

IF @Debug = 1 
  BEGIN 
        PRINT @SQL; 
  END 
ELSE 
  BEGIN 
        EXEC sp_executesql @SQL; 
  END
