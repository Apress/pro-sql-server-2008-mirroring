CREATE PROCEDURE dbo.dba_MirroringStateChanged 
AS 

DECLARE @Message XML, 
        @DBName sysname, 
        @MirrorStateChange INT, 
        @ServerName sysname, 
        @PostTime datetime, 
        @SPID INT, 
        @TextData NVARCHAR(500), 
        @DatabaseID INT, 
        @TransactionsID INT, 
        @StartTime datetime; 

SET NOCOUNT ON; 

-- Receive first unread message in service broker queue 
RECEIVE TOP (1) 
    @Message = CAST(message_body AS XML) 
FROM DBMirrorQueue; 

BEGIN TRY 
  -- Parse state change and database affected 
  -- 7 or 8 = database failing over, 
  --11 = synchronizing, 
  --1 or 2 = synchronized 
  SET @MirrorStateChange = 
        @Message.value('(/EVENT_INSTANCE/State)[1]', 'int'); 

  SET @DBName = 
        @Message.value('(/EVENT_INSTANCE/DatabaseName)[1]', 'sysname'); 

  SET @ServerName = 
        @Message.value('(/EVENT_INSTANCE/ServerName)[1]', 'sysname'); 

  SET @PostTime = 
        @Message.value('(/EVENT_INSTANCE/PostTime)[1]', 'datetime'); 

  SET @SPID = @Message.value('(/EVENT_INSTANCE/SPID)[1]', 'int'); 

  SET @TextData = 
        @Message.value('(/EVENT_INSTANCE/TextData)[1]', 'nvarchar(500)');
 
  SET @DatabaseID = 
        @Message.value('(/EVENT_INSTANCE/DatabaseID)[1]', 'int'); 

  SET @TransactionsID =
        @Message.value('(/EVENT_INSTANCE/TransactionsID)[1]', 'int');
 
  SET @StartTime = 
        @Message.value('(/EVENT_INSTANCE/StartTime)[1]', 'datetime'); 
END TRY 
BEGIN CATCH 
  PRINT 'Parse of mirroring state change message failed.'; 
END CATCH 

IF (@MirrorStateChange IN (7, 8)) -- database failing over 
  BEGIN 
    -- Fail over all databases still in the principal role 
    IF EXISTS (SELECT 1 
               FROM sys.database_mirroring 
               WHERE mirroring_role = 1 AND -- Principal 
                     mirroring_state <> 3)  -- Pending Failover 
      BEGIN 
        EXEC master.dbo.dba_ControlledFailover 
      END 
  END
