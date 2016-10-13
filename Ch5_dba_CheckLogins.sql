CREATE PROCEDURE dbo.dba_CheckLogins  
        @Server1 sysname, 
        @Server2 sysname = NULL, 
        @EPName sysname, 
        @Debug bit = 0 
AS 

DECLARE @SQLServAcct sysname, 
        @Domain sysname, 
        @SQL NVARCHAR(500) 
DECLARE @LoginConfig TABLE (Name sysname, 
                        ConfigValue sysname) 

SET NOCOUNT ON 

INSERT INTO @LoginConfig 
EXEC xp_loginconfig 'default domain' 

SELECT @Domain = ConfigValue 
FROM @LoginConfig 

EXEC xp_instance_regread N'HKEY_LOCAL_MACHINE',  
                N'System\CurrentControlSet\Services\MSSQLSERVER',  
                N'ObjectName', 
                @SQLServAcct OUTPUT, 
                N'no_output' 

IF @SQLServAcct = 'NT AUTHORITY\NetworkService' 
        SET @SQLServAcct = @Domain + '\' + 
       CAST(SERVERPROPERTY('MachineName') AS sysname) + '$' 

-- Server 1 
SET @SQL = 'If Not Exists (Select 1' + CHAR(10) + 
        'From ' + QUOTENAME(@Server1) + '.master.sys.server_principals' + 
        CHAR(10) + 'Where name = ''' + @SQLServAcct + ''')' + CHAR(10) + CHAR(9) + 
        'Create Login ' + QUOTENAME(@SQLServAcct) + ' From Windows;' 

IF @Debug = 1 
  BEGIN 
        PRINT @SQL; 
  END 
ELSE 
  BEGIN 
        EXEC sp_executesql @SQL; 
  END 

SET @SQL = 'If Not Exists (Select 1' + CHAR(10) + 'From ' + 
        QUOTENAME(@Server1) + '.master.sys.server_principals P' + CHAR(10) + 
        'Inner Join ' + QUOTENAME(@Server1) + '.master.sys.server_permissions SP ' +
        CHAR(9) + 'On SP.grantee_principal_id = P.principal_id' + CHAR(10) + 
        'Inner Join ' + QUOTENAME(@Server1) + 
        '.master.sys.database_mirroring_endpoints E' + 
        CHAR(10) + CHAR(9) + 'On E.name = Object_Name(SP.major_id)' + CHAR(10) + 
        'Where SP.permission_type = ''CO''' + CHAR(10) + 
        'And SP.state = ''G'')' + CHAR(10) + CHAR(9) + 
        'Grant Connect On EndPoint::' + QUOTENAME(@EPName) + 
        ' To ' + QUOTENAME(@SQLServAcct) + ';'; 

IF @Debug = 1 
  BEGIN 
        PRINT @SQL; 
  END 
ELSE 
  BEGIN 
        EXEC sp_executesql @SQL; 
  END 

-- Server 2 
IF @Server2 IS NOT NULL 
  BEGIN 
        SET @SQL = 'If Not Exists (Select 1' + CHAR(10) + 
                'From ' + QUOTENAME(@Server2) + 
                '.master.sys.server_principals' + 
                CHAR(10) + 'Where name = ''' + @SQLServAcct + ''')' + 
                CHAR(10) + CHAR(9) + 
                'Create Login ' + QUOTENAME(@SQLServAcct) + ' From Windows;' 

        IF @Debug = 1 
          BEGIN 
                PRINT @SQL; 
          END 
        ELSE 
          BEGIN 
                EXEC sp_executesql @SQL; 
          END 

        SET @SQL = 'If Not Exists (Select 1' + CHAR(10) + 
                'From ' + QUOTENAME(@Server2) + '.master.sys.server_principals P' + 
                CHAR(10) + 'Inner Join ' + QUOTENAME(@Server2) + 
                '.master.sys.server_permissions SP ' + CHAR(10) + CHAR(9) + 
                'On SP.grantee_principal_id = P.principal_id' + CHAR (10) + 
                'Inner Join ' + QUOTENAME(@Server2) + 
                '.master.sys.database_mirroring_endpoints E' + CHAR(10) + 
                CHAR(9) + 'On E.name = Object_Name(SP.major_id)' + CHAR(10) + 
                'Where SP.permission_type = ''CO''' + CHAR(10) + 
                'And SP.state = ''G'')' + CHAR(10) + CHAR(9) + 
                'Grant Connect On EndPoint::' + QUOTENAME(@EPName) + 
                ' To ' + QUOTENAME(@SQLServAcct) + ';'; 

        IF @Debug = 1 
          BEGIN 
                PRINT @SQL; 
          END 
        ELSE 
          BEGIN 
                EXEC sp_executesql @SQL; 
          END 
  END
