CREATE PROCEDURE dbo.dba_CreateEndPoint  
        @EndPointName sysname, 
        @Port INT, 
        @Debug bit = 0 
AS 

DECLARE @SQL NVARCHAR(4000), 
        @ExPort INT, 
        @ExEndPoint sysname, 
        @ExRole INT, 
        @ExState INT, 
        @CurrEdition INT, 
        @State NVARCHAR(200), 
        @Role NVARCHAR(60) 

SET @CurrEdition = CAST(SERVERPROPERTY('EngineEdition') AS INT) 

SELECT @ExEndPoint = DME.name, 
        @ExPort = TE.port, 
        @ExRole = DME.role, 
        @ExState = DME.state 
FROM sys.database_mirroring_endpoints DME 
INNER JOIN sys.tcp_endpoints TE ON TE.endpoint_id = DME.endpoint_id 

IF @ExEndPoint IS NOT NULL 
  BEGIN 
        IF @ExRole <> 'All' 
                AND @CurrEdition <> 4 -- Express 
          BEGIN 
                SET @Role = 'All' 
          END 
        ELSE 
          BEGIN 
                SET @Role = @ExRole 
          END 

        IF @ExState <> 3 -- Started 
          BEGIN 
                SET @State = 'State = Started ' + CHAR(10) + CHAR(9) 
          END 
        ELSE 
          BEGIN 
                SET @State = '' 
          END 

        SET @SQL = 'Alter Endpoint ' + QUOTENAME(@ExEndPoint) + CHAR(10) + CHAR(9) +
                @State + 'For Database_Mirroring (Role = ' + @Role + ');'; 

        IF @Debug = 1 
          BEGIN 
                PRINT @SQL 
          END 
        ELSE 
          BEGIN 
                EXEC sp_executesql @SQL; 
          END 
  END 
ELSE 
  BEGIN 
        SET @SQL = 'Create Endpoint ' + QUOTENAME(@EndPointName) + 
                CHAR(10) + CHAR(9) + 
                'State = Started' + CHAR(10) + CHAR(9) + 
                'As TCP (Listener_Port = ' + CAST(@Port AS NVARCHAR) + ',' + 
                CHAR(10) + CHAR(9) + 
                'Listener_IP = ALL)' + CHAR(10) + CHAR(9) + 
                'For Database_Mirroring (Role = ALL)' 

        IF @Debug = 1 
          BEGIN 
                PRINT @SQL 
          END 
        ELSE 
          BEGIN 
                EXEC sp_executesql @SQL; 
          END 
  END   
