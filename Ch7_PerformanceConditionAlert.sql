USE msdb
GO

EXEC msdb.dbo.sp_add_alert 
      @name=N'Log Send Queue KB', 
      @enabled=1, 
      @delay_between_responses=1800, 
      @include_event_description_in=1, 
      @notification_message=
       N'Database Mirroring Threshold has been exceeded, 
         please contact the on-call DBA.',
      @performance_condition=
N'MSSQL$SQL2K8:Database Mirroring|Log Send Queue KB|_Total|>|1048576 '
GO

EXEC msdb.dbo.sp_add_notification 
      @alert_name=N'Log Send Queue KB', 
      @operator_name=N'DBASupport', 
      @notification_method = 1
