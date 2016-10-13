--MAKE SURE TO **START** SQL SERVER AGENT 
--BEFORE RUNNING THIS SCRIPT!!!!!!!

--Enable SQL Server Agent to use Database Mail
-- and set fail-safe operator


EXEC master.dbo.sp_MSsetalertinfo 
           @failsafeoperator=N'DBASupport', --Failsafe Operator
		   @notificationmethod=1,
		   @failsafeemailaddress = N'DBA@Somecompany.com'


EXEC msdb.dbo.sp_set_sqlagent_properties 
              @email_save_in_sent_folder=1


EXEC master.dbo.xp_instance_regwrite 
           N'HKEY_LOCAL_MACHINE', 
           N'SOFTWARE\Microsoft\MSSQLServer\SQLServerAgent', 
           N'UseDatabaseMail', 
           N'REG_DWORD', 1


EXEC master.dbo.xp_instance_regwrite 
           N'HKEY_LOCAL_MACHINE', 
           N'SOFTWARE\Microsoft\MSSQLServer\SQLServerAgent', 
           N'DatabaseMailProfile', 
           N'REG_SZ', 
           N'DBMailProfile'
           
           
 PRINT '***********Please Restart SQL Server Agent!************'
