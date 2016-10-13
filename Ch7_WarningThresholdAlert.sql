USE msdb
GO

EXEC msdb.dbo.sp_add_alert 
      @name=N'Oldest Unsent Transaction', 
      @message_id=32040, 
      @severity=0, 
      @enabled=1, 
      @delay_between_responses=1800, 
      @include_event_description_in=1, 
      @notification_message=
        N'Database Mirroring Threshold has been exceeded, 
          please contact the on-call DBA.'
GO

EXEC msdb.dbo.sp_add_notification 
      @alert_name=N'Oldest Unsent Transaction', 
      @operator_name=N'DBASupport', 
      @notification_method = 1
GO
