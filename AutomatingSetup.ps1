param (
        [string] $SSPrincipal,
        [string] $SSMirror,
        [string] $Database,
        [string] $PrincipalPath,
        [string] $MirrorPath,
        [string] $SSWitness
)

## Path and name used to invoke script
$CUR_SCRIPT = $myinvocation.InvocationName

## Load SMO assemblies
[Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.ConnectionInfo")|out-null
[Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SmoEnum")|out-null
[Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo")|out-null
$SMO = [Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo")
## Parse out the internal version number
$SMOVer = $SMO.FullName.Split(",")[1].Split("=")[1].Split(".")[0]
## Load SMOExtended if not SQL Server 2005 (9)
if ($SMOVer -ne 9) {
        [Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SMOExtended")|out-null
}

## Declare empty array to hold ports already selected
$PortsUsed = @()

## Function to find an unused port
Function FindAPort ([string]$ServerToCheck) {
        $PortArray = ((5022..5025), (7022..7025), (5026..6000), (7026..8000))
        $socket = new-object System.Net.Sockets.TcpClient
        $PortAvailable = 0
        foreach ($Ports in $PortArray) {
                foreach ($Port in $Ports) {
                        if ($PortsUsed -notcontains $Port) {
                                $erroractionpreference = "SilentlyContinue"
                                $socket.Connect($ServerToCheck, $Port)
                                if (!$socket.Connected) {
                                        $PortAvailable = $Port
                                        $erroractionpreference = "Continue"
                                        $error.clear()
                                        $socket.Close()
                                        break
                                } else {
                                        $socket.Disconnect()
                                }
                        }
                }
                if ($PortAvailable -ne 0) { break }
        }
        write-host "`t Port $PortAvailable appears to be available" -f green
        return $PortAvailable
}

## Function to create endpoints
Function CreateEndPoint ([string]$EPName, [string]$EPServer, [int]$EPPort) {
        $MyEPServer = New-Object "Microsoft.SqlServer.Management.Smo.Server" $EPServer
        if ($MyEPServer.Edition -eq "Express Edition") {
                $EPRole = "Witness"
        } else {
                $EPRole = "All"
        }
        $EndPoint = New-Object "Microsoft.SqlServer.Management.Smo.EndPoint" $MyEPServer, $EPName
        $EndPoint.ProtocolType = "TCP"
        $EndPoint.EndPointType = "DatabaseMirroring"
        $EndPoint.Protocol.Tcp.ListenerPort = $EPPort
        $EndPoint.Payload.DatabaseMirroring.ServerMirroringRole = $EPRole
        $EndPoint.Create()
        $EndPoint.Start()
        if (!$error){
                write-host "`t Created Endpoint $EPName on $EPServer" -f green
        } else {
                RaisError "`t EndPoint Creation returned an error"
                Exit
        }
}

## Function to raise error
Function RaisError ([string]$ErrMsg){
        write-host $ErrMsg -f red
        $error.clear()
}

## Check user input, prompt for each value not provided as parameters
if(!$SSPrincipal) {
        $SSPrincipal = read-host "Enter Principal Server Name"
}
if(!$SSMirror) {
        $SSMirror = read-host "Enter Mirror Server Name"
}
if(!$Database) {
        $Database = read-host "Enter Database Name"
}
if(!$PrincipalPath) {
        $PrincipalPath = read-host "Enter Backup Directory for Principal"
}
if(!$MirrorPath) {
        $MirrorPath = read-host "Enter UNC Path to Backup Directory for Mirror"
}
if(!$SSWitness) {
        $SSWitness = read-host "Enter Witness Server Name (optional)"
}

## Make sure unique instance names were provided
if($SSPrincipal -eq $SSMirror -or $SSPrincipal -eq $SSWitness -or $SSMirror -eq $SSWitness) {
        RaisError "`t All mirroring partners must be on unique SQL instances."
        exit
}

## Return Help and exit if any required input is missing
if(!$SSPrincipal -or !$SSMirror -or !$Database -or !$PrincipalPath -or !$MirrorPath) {
        write-host "Usage: $CUR_SCRIPT options:
        string Principal SQL Server Instance
        string Mirror SQL Server Instance
        string Database Name
        string Backup Path for Principal Server
        string Backup Path for Mirror Server
        string Witness SQL Server Instance (optional)"
        exit
}

## Ensure backup directory exists
[System.IO.Directory]::CreateDirectory($PrincipalPath) | out-null

## Create server objects
$PrinSrv = New-Object "Microsoft.SqlServer.Management.Smo.Server" $SSPrincipal
$MirrSrv = New-Object "Microsoft.SqlServer.Management.Smo.Server" $SSMirror

## Check to see if SQL Edition meets requirements
$PrinEdition = $PrinSrv.Edition
$MirrEdition = $MirrSrv.Edition
$ValidEditions = "Developer Edition", "Standard Edition", "Enterprise Edition"

## Alert and exit if principal or mirror partner is not a valid edition
if (($ValidEditions -notcontains $PrinEdition) -or ($ValidEditions -notcontains $MirrEdition)) {
        Write-host "`t Database Mirroring is only available in Developer, Standard,” -f red
        Write-host "`t and Enterprise Editions." -f red
        Write-host "`t Principal Server: `t $PrinEdition" -f red
        Write-host "`t Mirror Server: `t`t $MirrEdition" -f red
        Exit
}

## Alert if principal and mirror are different editions and continue
if ($PrinEdition -ne $MirrEdition) {
        Write-host "`t Database Mirroring is not officially supported" -f yellow
        Write-host "`t with different Editions. You should use the same " -f yellow
        Write-host "`t Edition for both Principal and Mirror." -f yellow
        Write-host "`t Principal Server: `t $PrinEdition" -f yellow
        Write-host "`t Mirror Server: `t`t $MirrEdition" -f yellow
        Write-host ""
        Write-host "`t Proceeding with mirroring setup." -f yellow
}

## Get machine name of server -> get FQDN of server
$PrinMachine = $PrinSrv.NetName
$MirrMachine = $MirrSrv.NetName
$PrinFQDN = [system.net.dns]::GetHostEntry($PrinMachine).HostName
$MirrFQDN = [system.net.dns]::GetHostEntry($MirrMachine).HostName

## Create principal database object
$PrinDB = $PrinSrv.Databases[$Database]

## Return error and exit if database is already mirrored
if ($PrinDB.IsMirroringEnabled) {
        Write-host "Database $Database is already configured as a mirroring partner on $SSPrincipal." -f red
        exit
}

## Create Endpoint on Principal if not exists
$EPExist = $PrinSrv.Endpoints | where {$_.EndpointType -eq "DatabaseMirroring"}
if ($EPExist) {
        ## If existing Endpoint is for the witness role only, change role to all
        if ($EPExist.Payload.DatabaseMirroring.ServerMirroringRole -eq "Witness") {
                $EPExist.Payload.DatabaseMirroring.ServerMirroringRole = "All"
                $EPExist.Alter()
        }
        ## If existing Endpoint is not started, start it
        if ($EPExist.EndpointState -ne "started") {
                $EPExist.Start()
        }
        ## Get endpoint port
        $PrinPort = $EPExist.Protocol.Tcp.ListenerPort
} else {
        ## Find an unused port
        $PrinPort = FindAPort($SSPrincipal)
        ## Add port returned to array of ports used
        $PortsUsed = $PortsUsed + $PrinPort
        ## Create endpoint
        CreateEndPoint "MirroringEndPoint" $SSPrincipal $PrinPort
}

## Create Endpoint on Mirror if not exists
$EPExist = $MirrSrv.Endpoints | where {$_.EndpointType -eq "DatabaseMirroring"}
if ($EPExist) {
        ## If existing Endpoint is for the witness role only, change role to all
        if ($EPExist.Payload.DatabaseMirroring.ServerMirroringRole -eq "Witness") {
                $EPExist.Payload.DatabaseMirroring.ServerMirroringRole = "All"
                $EPExist.Alter()
        }
        ## If existing Endpoint is not started, start it
        if ($EPExist.EndpointState -ne "started") {
                $EPExist.Start()
        }
        ## Get endpoint port
        $MirrPort = $EPExist.Protocol.Tcp.ListenerPort
} else {
        ## Find an unused port
        $MirrPort = FindAPort($SSMirror)
        ## Add port returned to array of ports used
        $PortsUsed = $PortsUsed + $MirrPort
        ## Create endpoint
        CreateEndPoint "MirroringEndPoint" $SSMirror $MirrPort
}

## Check that principal database is ready for mirroring
## Checking compatibility level and recovery model
$dbCompatLevel = $PrinDB.Properties | where {$_.Name -eq "CompatibilityLevel"} | %{$_.value}
if ($dbCompatLevel -eq "Version80") {
        write-host "Compatilibility level is set to SQL 2000 (80)." -f red
        write-host " Please change compatibility level to SQL 2005 (90) " -f red
        write-host "or SQL 2008 (10)." -f red
        exit
}
$dbRecoveryModel = $PrinDB.Properties | where {$_.Name -eq "RecoveryModel"} | %{$_.value}
if ($dbRecoveryModel -ne 1) {
        $PrinDB.RecoveryModel = 1
        $PrinDB.Alter()
        if (!$error){
                write-host "`t Changed recovery model to Full " -f green
                write-host "`t from $dbRecoveryModel" -f green
        } else {
                RaisError "`t Recovery model change returned an error."
                Exit
        }
}

## Create backup name
$BkDate = Get-Date -Format yyyyMMddHHmmss
$BkName = $Database + "_backup_$BkDate.bak"

## Backup the Principal database
$Backup = new-object "Microsoft.SqlServer.Management.Smo.Backup"
$BkFile = new-object "Microsoft.SqlServer.Management.Smo.BackupDeviceItem"
$BkFile.DeviceType = 'File'
$BkFile.Name = [System.IO.Path]::Combine($PrincipalPath, $BkName)
$Backup.Devices.Add($BkFile)
$Backup.Database = $Database
$Backup.Action = 'Database'
$Backup.Initialize = 1
$Backup.BackupSetDescription = "Backup of database $Database"
$Backup.BackupSetName = "$Database Backup"
$Backup.PercentCompleteNotification = 5
$Backup.SqlBackup($PrinSrv)
if (!$error){
        write-host "`t Database $Database backed up to $PrincipalPath" -f green
} else {
        RaisError "`t Database $Database backup returned an error."
        Exit
}

## If database exists on Mirror, delete it
$DBExists = $MirrSrv.Databases[$Database]
if ($DBExists) {
        if ($dbExists.IsMirroringEnabled) {
                RaisError "`t Database $DBExists is already configured as a Mirroring partner on $SSMirror."
                Exit
        }
        if ($DBExists.status -eq "online") {
                $MirrSrv.KillDatabase($Database)
        } else {
                $DBExists.drop()
        }
        if (!$error){
                write-host "`t Dropping existing database on Mirror server" -f green
        } else {
                RaisError "`t Drop of existing database on Mirror server returned an error."
                Exit
        }
}

## Restore the Mirror database
$Restore = new-object "Microsoft.SqlServer.Management.Smo.Restore"
$Restore.Database = $Database
$Restore.Action = 'Database'
$BkFile.Name = [System.IO.Path]::Combine($MirrorPath, $BkName)
$Restore.Devices.Add($BkFile)
$Restore.ReplaceDatabase = $false
## Check file list and generate new file names if files already exists
$DataFiles = $Restore.ReadFileList($SSMirror)
ForEach ($DataRow in $DataFiles) {
        $LogicalName = $DataRow.LogicalName
        $PhysicalName = $DataRow.PhysicalName
        $FileExists = Test-Path $PhysicalName
        if ($FileExists) {
                $PhysicalName = $PhysicalName -replace(".mdf", "_mirr.mdf")
                $PhysicalName = $PhysicalName -replace(".ldf", "_mirr.ldf")
                $PhysicalName = $PhysicalName -replace(".ndf", "_mirr.ndf")
                $Restore.RelocateFiles.Add((new-object microsoft.sqlserver.management.smo.relocatefile -ArgumentList $LogicalName, $PhysicalName))|out-null;
        }
}
$Restore.NoRecovery = $true
$Restore.PercentCompleteNotification = 5
$Restore.SqlRestore($SSMirror)
if (!$error){
        write-host "`t Database $Database restored from $MirrorPath" -f green
} else {
        RaisError "`t Restore of database $Database on Mirror server returned an error."
        Exit
}

## Create backup name
$BkDate = Get-Date -Format yyyyMMddHHmmss
$BkName = $Database + "_backup_$BkDate.trn"

## Backup the log on Principal database
$LogBackup = new-object "Microsoft.SqlServer.Management.Smo.Backup"
$BkFile.DeviceType = 'File'
$BkFile.Name = [System.IO.Path]::Combine($PrincipalPath, $BkName)
$LogBackup.Devices.Add($BkFile)
$LogBackup.Database = $Database
$LogBackup.Action = 'Log'
$LogBackup.Initialize = 1
$LogBackup.BackupSetDescription = "Log backup of database $Database"
$LogBackup.BackupSetName = "$Database Log Backup"
$LogBackup.PercentCompleteNotification = 5
$LogBackup.SqlBackup($PrinSrv)
if (!$error){
        write-host "`t Database $Database log backed up to $PrincipalPath" -f green
} else {
        RaisError "`t Database $Database log backup returned an error."
        Exit
}

## Restore the log on Mirror Database
$LogRestore = new-object "Microsoft.SqlServer.Management.Smo.Restore"
$LogRestore.Database = $Database
$LogRestore.Action = 'log'
$BkFile.Name = [System.IO.Path]::Combine($MirrorPath, $BkName)
$LogRestore.Devices.Add($BkFile)
$LogRestore.NoRecovery = $true
$LogRestore.PercentCompleteNotification = 5
$LogRestore.SqlRestore($SSMirror)
if (!$error){
        write-host "`t Database $Database log restored from $MirrorPath" -f green
} else {
        RaisError "`t Database $Database log restore returned an error."
        Exit
}

## Set the Principal Partner on Mirror Partner
$MirrDB = $MirrSrv.Databases[$Database]
$MirrDB.MirroringPartner = "TCP://" + $PrinFQDN.ToString() + ":$PrinPort"
$MirrDB.Alter()
if (!$error){
        write-host "`t Set Principal Partner on Mirror " -f green
} else {
        RaisError "`t Setting Principal Partner on Mirror returned an error."
        Exit
}

## Set the Mirror Partner on Principal Partner
$PrinDB.MirroringPartner = "TCP://" + $MirrFQDN.ToString() + ":$MirrPort"
$PrinDB.Alter()
if (!$error){
        write-host "`t Set Mirror Partner on Principal" -f green
} else {
        RaisError "`t Setting Mirror Partner on Principal returned an error."
        Exit
}

## Verify that mirroring is started
$PrinDB.Refresh()
if ($PrinDB.MirroringStatus) {
        write-host ""
        write-host "`t Database Mirroring started" -f green
}

## Process Mirror database if provided
if (!$SSWitness) {
        ## Set Safety off if no witness and if
        ## running Enterprise or Developer Edition on both partners
        if ($PrinEdition -ne "Standard Edition" -and $MirrEdition -ne "Standard Edition") {
                $PrinDB.MirroringSafetyLevel = "Off"
                $PrinDB.Alter()
                if (!$error){
                        Write-host "`t Turning transaction safety off." -f green
                } else {
                        RaisError "`t Turning transaction safety off returned an error."
                        Exit
                }
        }
} else {
        ## Connect to Witness server
        $WitSrv = New-Object "Microsoft.SqlServer.Management.Smo.Server" $SSWitness
        ## Get machine name of server -> get FQDN of server
        $WitMachine = $WitSrv.NetName
        $WitFQDN = [system.net.dns]::GetHostEntry($WitMachine).HostName

        ## Create Endpoint on Witness if not exists
        $EPExist = $WitSrv.Endpoints | where {$_.EndpointType -eq "DatabaseMirroring"}
        if ($EPExist) {
                ## If existing Endpoint is for the Partner role only, change role to all
                ## No need to check for Express Edition due to existing Partner role
                if ($EPExist.Payload.DatabaseMirroring.ServerMirroringRole -eq "Partner") {
                        $EPExist.Payload.DatabaseMirroring.ServerMirroringRole = "All"
                        $EPExist.Alter()
                }
                ## If existing Endpoint is not started, start it
                if ($EPExist.EndpointState -ne "started") {
                        $EPExist.Start()
                }
                ## Get endpoint port
                $WitPort = $EPExist.Protocol.Tcp.ListenerPort
        } else {
                ## Find an unused port
                $WitPort = FindAPort($SSWitness)
                ## Create endpoint
                CreateEndPoint "MirroringEndPoint" $SSWitness $WitPort
        }

        ## Set Witness server on Principal
        $PrinDB.MirroringWitness = "TCP://" + $WitFQDN.ToString() + ":$WitPort"
        $PrinDB.Alter()
        if (!$error){
                Write-host "`t Set Witness Partner on Principal" -f green
        } else {
                RaisError "`t Setting Witness Partner on Principal returned an error."
                Exit
        }
}

## Refresh connections to reload stale properties
$MirrDB.Refresh()
$PrinDB.Refresh()
## Get and display mirroring status
$PrinPart = $MirrDB.MirroringPartner
$PrinStatus = $PrinDB.MirroringStatus
$MirrPart = $PrinDB.MirroringPartner
$MirrStatus = $MirrDB.MirroringStatus
$Safety = $PrinDB.MirroringSafetyLevel
write-host "`t Principal: `t $PrinPart"  -f green
write-host "`t Status: `t $PrinStatus"  -f green
write-host "`t Mirror: `t $MirrPart"  -f green
write-host "`t Status: `t $MirrStatus"  -f green
if ($SSWitness) {
        $WitPart = $PrinDB.MirroringWitness
        $WitStatus = $PrinDB.MirroringWitnessStatus
        write-host "`t Witness: `t $WitPart"  -f green
        write-host "`t Status: `t $WitStatus"  -f green
}
write-host "`t Safety Level: `t $Safety" -f green
