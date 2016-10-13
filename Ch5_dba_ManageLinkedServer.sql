CREATE PROCEDURE dbo.dba_ManageLinkedServer  
        @ServerName sysname, 
        @Action VARCHAR(10) = 'create' 
AS 
IF @ServerName = @@ServerName 
        RETURN 

IF @Action = 'create' 
 BEGIN 
        IF NOT EXISTS (SELECT 1 FROM sys.servers  
                        WHERE name = @ServerName 
                        AND is_linked = 1) 
          BEGIN 
                EXEC master.dbo.sp_addlinkedserver @server = @ServerName, 
                                            @srvproduct = N'SQL Server'; 
                EXEC master.dbo.sp_serveroption @server = @ServerName, 
                                            @optname = N'collation compatible', 
                                            @optvalue = N'false'; 
                EXEC master.dbo.sp_serveroption @server = @ServerName, 
                                            @optname = N'data access', 
                                            @optvalue = N'true'; 
                EXEC master.dbo.sp_serveroption @server = @ServerName, 
                                            @optname = N'dist', 
                                            @optvalue = N'false'; 
                EXEC master.dbo.sp_serveroption @server = @ServerName, 
                                            @optname = N'pub', 
                                            @optvalue = N'false'; 
                EXEC master.dbo.sp_serveroption @server = @ServerName, 
                                            @optname = N'rpc', 
                                            @optvalue = N'true'; 
                EXEC master.dbo.sp_serveroption @server = @ServerName, 
                                            @optname = N'rpc out', 
                                            @optvalue = N'true'; 
                EXEC master.dbo.sp_serveroption @server = @ServerName, 
                                            @optname = N'sub', 
                                            @optvalue = N'false'; 
                EXEC master.dbo.sp_serveroption @server = @ServerName, 
                                            @optname = N'connect timeout', 
                                            @optvalue = N'0'; 
                EXEC master.dbo.sp_serveroption @server = @ServerName, 
                                            @optname = N'collation name', 
                                            @optvalue = NULL; 
                EXEC master.dbo.sp_serveroption @server = @ServerName, 
                                            @optname = N'lazy schema validation', 
                                            @optvalue = N'false'; 
                EXEC master.dbo.sp_serveroption @server = @ServerName, 
                                            @optname = N'query timeout', 
                                            @optvalue = N'0'; 
                EXEC master.dbo.sp_serveroption @server = @ServerName, 
                                            @optname = N'use remote collation', 
                                            @optvalue = N'true'; 
                EXEC master.dbo.sp_addlinkedsrvlogin @rmtsrvname = @ServerName, 
                                            @locallogin = NULL , 
                                            @useself = N'True'; 
          END 
  END 
ELSE IF @Action = 'drop' 
 BEGIN 
        IF EXISTS (SELECT 1 FROM sys.servers  
                WHERE name = @ServerName 
                AND is_linked = 1) 
          BEGIN 
                EXEC master.dbo.sp_dropserver @server = @ServerName, 
                                            @droplogins = NULL 
          END 
  END
