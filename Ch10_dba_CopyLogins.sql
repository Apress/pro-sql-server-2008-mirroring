CREATE PROCEDURE dbo.dba_CopyLogins  
        @PartnerServer sysname 
AS 

DECLARE @MaxID INT, 
        @CurrID INT, 
        @SQL NVARCHAR(MAX), 
        @LoginName sysname, 
        @RoleName sysname, 
        @Machine sysname 

DECLARE @Logins TABLE (LoginID INT IDENTITY(1, 1) NOT NULL PRIMARY KEY, 
                                                  [Name] sysname NOT NULL, 
                                                  [SID] varbinary(85) NOT NULL, 
                                                  IsDisabled INT NOT NULL) 

DECLARE @Roles TABLE (RoleID INT IDENTITY(1, 1) NOT NULL PRIMARY KEY, 
                                                RoleName sysname NOT NULL, 
                                                LoginName sysname NOT NULL) 

SET NOCOUNT ON 

IF CHARINDEX('\', @PartnerServer) > 0 
  BEGIN 
    SET @Machine = LEFT(@PartnerServer, CHARINDEX('\', @PartnerServer) - 1) 
  END 
ELSE 
  BEGIN 
    SET @Machine = @PartnerServer 
  END 

-- Get all Windows logins from principal server 
SET @SQL = 'Select name, sid, is_disabled' + CHAR(10) + 
        'From ' + QUOTENAME(@PartnerServer) + '.master.sys.server_principals' + 
        CHAR(10) + 'Where type In (''U'', ''G'')' + CHAR(10) + 
        'And CharIndex(''' + @Machine + ''', name) = 0'; 

INSERT INTO @Logins (Name, SID, IsDisabled) 
EXEC sp_executesql @SQL; 

-- Get all roles from principal server 
SET @SQL = 'Select RoleP.name, LoginP.name' + CHAR(10) + 'From ' + 
        QUOTENAME(@PartnerServer) + '.master.sys.server_role_members RM' + 
        CHAR(10) + 'Inner Join ' + 
        QUOTENAME(@PartnerServer) + '.master.sys.server_principals RoleP' + 
        CHAR(10) + CHAR(9) + 'On RoleP.principal_id = RM.role_principal_id' + 
        CHAR(10) + 'Inner Join ' + 
        QUOTENAME(@PartnerServer) + '.master.sys.server_principals LoginP' + 
        CHAR(10) + CHAR(9) + 'On LoginP.principal_id = RM.member_principal_id' + 
        CHAR(10) + 'Where LoginP.type In (''U'', ''G'')' + CHAR(10) + 
        'And RoleP.type = ''R''' + CHAR(10) + 
        'And CharIndex(''' + @Machine + ''', LoginP.name) = 0'; 

INSERT INTO @Roles (RoleName, LoginName) 
EXEC sp_executesql @SQL; 

SELECT @MaxID = MAX(LoginID), @CurrID = 1 
FROM @Logins 

WHILE @CurrID <= @MaxID 
  BEGIN 
    SELECT @SQL = 'If Not Exists (Select 1' + CHAR(10) + CHAR(9) + 
                'From sys.server_principals' + CHAR(10) + CHAR(9) + 
                'Where name = ''' + Name + ''')' + CHAR(10) + CHAR(9) + 
                'Create Login ' + QUOTENAME(Name) + ' From Windows;' +  
                CASE IsDisabled WHEN 1 THEN CHAR(10) + CHAR(9) + 
                ' Alter Login ' + QUOTENAME(Name) + ' Disable;' 
                ELSE '' END 
    FROM @Logins 
    WHERE LoginID = @CurrID 

    EXEC sp_executesql @SQL 

    SET @CurrID = @CurrID + 1 
  END 

SELECT @MaxID = MAX(RoleID), @CurrID = 1 
FROM @Roles 

WHILE @CurrID <= @MaxID 
  BEGIN 
    SELECT @LoginName = LoginName, 
                    @RoleName = RoleName 
    FROM @Roles 
    WHERE RoleID = @CurrID 

    IF NOT EXISTS (SELECT 1 
                                 FROM sys.server_role_members RM INNER JOIN 
                                             sys.server_principals RoleP 
                                               ON RoleP.principal_id = RM.role_principal_id INNER JOIN 
                                             sys.server_principals LoginP 
                                               ON LoginP.principal_id = RM.member_principal_id 
                                  WHERE LoginP.type IN ('U', 'G') AND 
                                                 RoleP.type = 'R' AND 
                                                 RoleP.name = @RoleName AND
                                                 LoginP.name = @LoginName) 
      BEGIN 
        EXEC sp_addsrvrolemember @rolename = @RoleName, 
                                                        @loginame = @LoginName; 
      END 

      SET @CurrID = @CurrID + 1 
  END  
