--MAKE SURE TO STOP SQL SERVER AGENT BEFORE RUNNING THIS SCRIPT!
USE msdb
GO

--Enable Database Mail
sp_configure 'show advanced options', 1;
GO
RECONFIGURE;
GO
sp_configure 'Database Mail XPs', 1;
GO
RECONFIGURE
GO

--Enable Service Broker
ALTER DATABASE msdb SET ENABLE_BROKER

--Add the profile
EXEC msdb.dbo.sysmail_add_profile_sp
      @profile_name = 'DBA Mail Profile',
      @description = 'Profile used by the database administrator to send email.'

--Add the account
EXEC msdb.dbo.sysmail_add_account_sp
      @account_name = 'DBA Mail Account',
      @description = 'Profile used by the database administrator to send email.',
      @email_address = 'DBA@somecompany.com',
      @display_name =  (Select @@ServerName),
      @mailserver_name =  'KEN-PC'

--Associate the account with the profile
EXEC msdb.dbo.sysmail_add_profileaccount_sp
      @profile_name = 'DBA Mail Profile',
      @account_name = 'DBA Mail Account',
      @sequence_number = 1 

Print 'Don’t Forget To Restart SQL Server Agent!'
