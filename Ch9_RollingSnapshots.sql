--***Run this script every hour 5 minutes before the hour***

--Set the @NextHour variable to the number of the next hour
DECLARE @NextHour VARCHAR(2) = DATEPART(HOUR,DATEADD(HOUR,1,GETDATE()))

DECLARE @SQL VARCHAR(MAX)

--***Remove any snapshots older than 130 minutes*** 
--     ***for the AdventureWorks database***

--Create a string of DROP DATABASE statements 
--using the sys.databases table
SELECT @SQL = ISNULL(@SQL,'') + 'DROP DATABASE ' + name + ';'
FROM sys.databases
WHERE source_database_id = DB_ID('AdventureWorks') AND
      create_date < DATEADD(MINUTE,-130,GETDATE())

--Print the DROP DATABASE statements
PRINT @SQL
--Execute the DROP DATABASE statements
EXEC (@SQL)


--***Create a snapshot for the next hour***
SET @SQL = 
    'CREATE DATABASE AW_SS_' + @NextHour +
    ' ON
    (NAME = AdventureWorks_Data,
     FILENAME = ''C:\AW_data_' + @NextHour + '.ss'')
     AS SNAPSHOT OF AdventureWorks;'
     
--Print the CREATE DATABASE statement
PRINT @SQL
--Execute the CREATE DATABASE statement
EXEC (@SQL)
