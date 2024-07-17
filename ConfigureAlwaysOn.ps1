################################################################################################################################################
#Script to setup SQL Server 2016 AlwaysOn Availability Group
#Creates a SQL server 2016 DB. 
#Implement AlwaysOn Availability Groups

<#Variables input from VCAC properties
DomainAccountUsername - User Name of the Domain Administrator - String
DomainAccountPassword - Password Of the Domain Administrator
AlwaysonAgPrimaryReplicaHostName -Primary Node hostname
AlwaysonAgPrimaryReplicaInstanceName -Instance Name of SQL running on Primary Node
AlwaysonAgSecondaryReplicaHostname -Secondary Node Hostname
AlwaysonAgSecondaryReplicaInstanceName - Instance name of SQL running on Secondary Node
DomainFull - e.g. domain.com
DomainName - e.g. domain
AlwaysonAgHadrEndpointName2 - Name to call HadrEndpoint on Secondary Node
AlwaysonAgHadrEndpointName - Name to call HadrEndpoint on Primary Node
AlwaysonAgDatabaseName - Name to call AAG Database Name
AlwaysonAgBackupLocation - Location to backup the SQL instances 
AlwaysonAgName - Name to call the Always on Group
AlwaysonListenerOption - Whether to create Always On listener
AlwaysonAgListenerName - Always On Listener Name
AlwaysonAgListenerStaticIp - Listener Static IP Address
AlwaysonAgListenerNetMask - Listener NetMask
AlwaysonAgListenerPort - Listener Port. Default Port 1433
#>

<#Internal Variables
cmdUser - Domain User concatenated with Full Domain Name
dbuser - Database Admin user concatenated with Domain
passwordSecure - Password Converted for Credential Delegation
credentials - Credential Object to be used in invoke commands 
serverPrimary - Smo Object connection to Primary Node
serverSecondary - Smo Object connection to Secondary Node
query - SQL Query to create AlwaysOn DB
db - holder for DB Instance on Nodes
#>
################################################################################################################################################

[int] $AlwaysonAgHadrEndpointPort = 5022
	
Import-Module "sqlps" –DisableNameChecking

#Added by Winfred at 10/27/2016 to print input values
Write-Output "AlwaysonAgPrimaryReplicaHostName = $AlwaysonAgPrimaryReplicaHostName"
Write-Output "AlwaysonAgPrimaryReplicaInstanceName = $AlwaysonAgPrimaryReplicaInstanceName"
Write-Output "AlwaysonAgSecondaryReplicaHostname= $AlwaysonAgSecondaryReplicaHostname"
Write-Output "AlwaysonAgSecondaryReplicaInstanceName = $AlwaysonAgSecondaryReplicaInstanceName"
Write-Output "DomainFull= $DomainFull"
Write-Output "DomainName = $DomainName"
Write-Output "AlwaysonAgHadrEndpointName2 = $AlwaysonAgHadrEndpointName2"
Write-Output "AlwaysonAgHadrEndpointName = $AlwaysonAgHadrEndpointName"
Write-Output "AlwaysonAgDatabaseName = $AlwaysonAgDatabaseName"
Write-Output "AlwaysonAgName = $AlwaysonAgName"
Write-Output "AlwaysonListenerOption = $AlwaysonListenerOption"
Write-Output "AlwaysonAgListenerName = $AlwaysonAgListenerName"
Write-Output "AlwaysonAgListenerStaticIp = $AlwaysonAgListenerStaticIp"
Write-Output "AlwaysonAgListenerNetMask = $AlwaysonAgListenerNetMask"
Write-Output "AlwaysonAgListenerPort = $AlwaysonAgListenerPort"

# modified at 10/28/2016. Domain account for SQL Server will also be database "sysadmin" role.
# use domain netbios name instead, not domain full; and add cmduser as dbuser
[string]$cmdUser= $DomainName + "\" + $DomainAccountUserName
[string]$dbUser = $cmdUser

$passwordSecure = ConvertTo-SecureString -String $DomainAccountPassword -AsPlainText -Force
$credentials = New-Object System.Management.Automation.PSCredential $cmdUser,$passwordSecure

Write-Output "cmdUser= $cmdUser"
Write-Output "dbUser = $dbUser "
Write-Output "$credentials= $$credentials"

# If user enter "mssqlserver" as sql server instance name, rename the AlwaysonAgPrimaryReplicaInstanceName and AlwaysonAgSecondaryReplicaInstanceName parameter to "default" in powershell code
# The SQL server execution path use "\SQL\$hostname\default" if it is default instance
if($AlwaysonAgPrimaryReplicaInstanceName -eq "mssqlserver")
{
                $AlwaysonAgPrimaryReplicaInstanceName = "default"
}

if($AlwaysonAgSecondaryReplicaInstanceName -eq "mssqlserver")
{
                $AlwaysonAgSecondaryReplicaInstanceName= "default"
}

# Form the server-instance and service name.
#For default instance, use hostname as server-instance name, and MSSQLSERVER as service name.
#For named instances, follow 'hostname\instancename' as server-instance name and append MSSQL$ to instnace name as service name.
if($AlwaysonAgPrimaryReplicaInstanceName -ne "Default")
{
	$alwaysonAgPrimaryReplicaServerInstance = "$AlwaysonAgPrimaryReplicaHostName\$AlwaysonAgPrimaryReplicaInstanceName"
	$serviceNameOfPrimaryReplicaInstance = "MSSQL$" + $AlwaysonAgPrimaryReplicaInstanceName
}
else
{
	$alwaysonAgPrimaryReplicaServerInstance = $AlwaysonAgPrimaryReplicaHostName
	$serviceNameOfPrimaryReplicaInstance = "MSSQLSERVER"
}

if($AlwaysonAgSecondaryReplicaInstanceName -ne "Default")
{
	$alwaysonAgSecondaryReplicaServerInstance = "$AlwaysonAgSecondaryReplicaHostname\$AlwaysonAgSecondaryReplicaInstanceName"
	$serviceNameOfSecondaryReplicaInstance = "MSSQL$" + $AlwaysonAgSecondaryReplicaInstanceName
}
else
{
	$alwaysonAgSecondaryReplicaServerInstance = $AlwaysonAgSecondaryReplicaHostname
	$serviceNameOfSecondaryReplicaInstance = "MSSQLSERVER"
}

[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO') | out-null
# Create an SMO connection to the primary replica server instance
$serverPrimary = New-Object ('Microsoft.SqlServer.Management.Smo.Server') $alwaysonAgPrimaryReplicaServerInstance
$serverSecondary = New-Object ('Microsoft.SqlServer.Management.Smo.Server') $alwaysonAgSecondaryReplicaServerInstance




#Check if Database already exists on Primary server and create if not
$db = $serverPrimary.Databases[$AlwaysonAgDatabaseName]

if ($db.name -ne $AlwaysonAgDatabaseName){
    Write-Output "database $databaseName does not exist creating now"
    $db = New-Object Microsoft.SqlServer.Management.Smo.Database($serverPrimary, $AlwaysonAgDatabaseName)
    $db.Create()
    Write-Host $db.CreateDate
}
else
{
    Write-Output "Database already exists, continuing" 
}

# Create an endpoint if one doesn't exist on primary replica.
function check_endpoints
{
    param(
    [string]$HadrEndpointname,
    $hadrEndpoint,
    [string]$hostName,
    [string]$instanceName
    )

    if($hadrEndpoint -eq $null)
	{
	 Write-Output "Creating endpoint '$HadrEndpointName' on server '$hostName'"
	New-SQLHADREndpoint -Name $HadrEndpointName -Port $AlwaysonAgHadrEndpointPort -Path "SQLSERVER:\SQL\$hostName\$instanceName" 
	Set-SqlHadrEndpoint -Path "SQLSERVER:\SQL\$hostName\$instanceName\Endpoints\$HadrEndpointName" -State Started
	}
	else
	{
	Write-Output "An endpoint for DatabaseMirroring already exists on '$hostName'. Skipping endpoint creation."
	}
}

# Check if endpoint already exists on primary replica.
$hadrEndpoint = $serverPrimary.Endpoints |
				Where-Object { $_.Name -eq $AlwaysonAgHadrEndpointName } |
				Select-Object -First 1

check_endpoints $AlwaysonAgHadrEndpointName $hadrEndpoint $AlwaysonAgPrimaryReplicaHostName $AlwaysonAgPrimaryReplicaInstanceName

# Check if endpoint already exists on secondary replica.
$hadrEndpoint = $serverSecondary.Endpoints |
				Where-Object { $_.Name -eq $AlwaysonAgHadrEndpointName2 } |
				Select-Object -First 1

check_endpoints $AlwaysonAgHadrEndpointName2 $hadrEndpoint $AlwaysonAgSecondaryReplicaHostname $AlwaysonAgSecondaryReplicaInstanceName

$query = "CREATE LOGIN [$dbUser] FROM WINDOWS WITH DEFAULT_DATABASE=[master], DEFAULT_LANGUAGE=[us_english]"
$queryrole = "EXEC master..sp_addsrvrolemember @loginame = N'$dbUser', @rolename = N'sysadmin'"

#Create DBA Users for AlwaysOn on both Nodes. 
$logins = $serverPrimary.Logins
$dba = $logins | where{$_.Name -eq $dbUser }

if ($dba -eq $null)
{
	Write-Output "DBA user '$dbUser' does not exist on ServerInstance '$alwaysonAgPrimaryReplicaServerInstance'. Adding DBA user..."
    Invoke-Sqlcmd -ServerInstance $alwaysonAgPrimaryReplicaServerInstance -Query $query
	Invoke-Sqlcmd  -ServerInstance $alwaysonAgPrimaryReplicaServerInstance -Query $queryrole
	$logins = $serverPrimary.Logins
	$dba = $logins | where{$_.Name -eq $dbUser}
	
	if ($dba -ne $null)
	{
		Write-Output "User '$dbUser' has been created on ServerInstance '$alwaysonAgPrimaryReplicaServerInstance'."
		$dba.name
	}
}
else
{
	Write-Output "User '$dbUser' already exists on ServerInstance '$alwaysonAgPrimaryReplicaServerInstance'. Skipping user creation."
	$dba.name
}

$logins = $serverSecondary.Logins
$dba = $logins | where{$_.Name -eq $dbUser}

if ($dba -eq $null)
{
	Write-Output "DBA User '$dbUser' does not exist on ServerInstance '$alwaysonAgSecondaryReplicaServerInstance' . Adding DBA user..."
  
    Invoke-Sqlcmd -ServerInstance $alwaysonAgSecondaryReplicaServerInstance -Query $query
	Invoke-Sqlcmd  -ServerInstance $alwaysonAgSecondaryReplicaServerInstance -Query $queryrole
	$logins = $serverSecondary.Logins
	$dba = $logins | where{$_.Name -eq $dbUser}
	
	if ($dba -ne $null)
	{
		Write-Output "User '$dbUser' has been created on ServerInstance '$alwaysonAgSecondaryReplicaServerInstance'"
		$dba.name
	}
}
else
{
	Write-Output "User '$dbUser' already exists on ServerInstance '$alwaysonAgSecondaryReplicaServerInstance'. Skipping user creation."
	$dba.name
}

$PrimaryHostname = [System.Net.Dns]::GetHostEntry([string]$AlwaysonAgPrimaryReplicaHostName).HostName
$SecondaryHostName = [System.Net.Dns]::GetHostEntry([string]$AlwaysonAgSecondaryReplicaHostName).HostName

# Enable AlwaysOn on Primary and restart service.
$timeout = New-Object System.TimeSpan -ArgumentList 0, 0, 30

if($serverPrimary.IsHadrEnabled -eq $false)
{
	Write-Output "Enabling AlwaysOn on server instance '$alwaysonAgPrimaryReplicaServerInstance'"

	Invoke-Command  -ComputerName $PrimaryHostname  -Authentication Credssp -Credential $credentials -ScriptBlock {
        param($alwaysonAgPrimaryReplicaServerInstance)
        Set-ExecutionPolicy Unrestricted
		Import-Module "sqlps" –DisableNameChecking
		Enable-SqlAlwaysOn -ServerInstance $alwaysonAgPrimaryReplicaServerInstance –Force
	} -ArgumentList $alwaysonAgPrimaryReplicaServerInstance
}
Invoke-Command -ComputerName $PrimaryHostname -Authentication Credssp -Credential $credentials -ScriptBlock {
    param($AlwaysonAgPrimaryReplicaHostName, $cmdUser, $DomainAccountPassword)
	[reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.SqlWmiManagement")
	$wmiPrimary = New-Object ("Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer") $AlwaysonAgPrimaryReplicaHostName
	$wmiPrimary.services | Where {$_.Type -eq 'SqlServer' -or $_.Type -eq 'SQLAgent'} | ForEach {$_.SetServiceAccount($cmdUser,$DomainAccountPassword)}
} -ArgumentList $AlwaysonAgPrimaryReplicaHostName, $cmdUser, $DomainAccountPassword

$svcPrimary = Get-Service -ComputerName $AlwaysonAgPrimaryReplicaHostName -Name $serviceNameOfPrimaryReplicaInstance
$svcPrimary.Stop()
$svcPrimary.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Stopped,$timeout)
$svcPrimary.Start(); 
$svcPrimary.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Running,$timeout)
# Enable AlwaysOn on Secondary and restart service.
if($serverSecondary.IsHadrEnabled -eq $false)
{
	Write-Output "Enabling AlwaysOn on server instance '$alwaysonAgSecondaryReplicaServerInstance'"
	Invoke-Command -ComputerName $SecondaryHostName  -Authentication Credssp -Credential $credentials -ScriptBlock {
        param($alwaysonAgSecondaryReplicaServerInstance)
        Set-ExecutionPolicy Unrestricted -Force
		Import-Module "sqlps" –DisableNameChecking
		Enable-SqlAlwaysOn -ServerInstance $alwaysonAgSecondaryReplicaServerInstance –Force
	} -ArgumentList $alwaysonAgSecondaryReplicaServerInstance
}
Invoke-Command -ComputerName $SecondaryHostName -Authentication Credssp -Credential $credentials -ScriptBlock {
	param($AlwaysonAgSecondaryReplicaHostName, $cmdUser, $DomainAccountPassword, $serviceNameOfSecondaryReplicaInstance, $timeout)
    [reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.SqlWmiManagement")
	$wmiSecondary = New-Object ("Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer") $AlwaysonAgSecondaryReplicaHostName
	$wmiSecondary.services | Where {$_.Type -eq 'SqlServer' -or $_.Type -eq 'SQLAgent'} | ForEach {$_.SetServiceAccount($cmdUser, $DomainAccountPassword)}
    $svcSecondary = Get-Service -ComputerName $AlwaysonAgSecondaryReplicaHostName -Name $serviceNameOfSecondaryReplicaInstance
    $svcSecondary.Stop()
    $svcSecondary.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Stopped,$timeout)
    $svcSecondary.Start(); 
    $svcSecondary.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Running,$timeout)
    Sleep 10
} -ArgumentList $AlwaysonAgSecondaryReplicaHostname, $cmdUser, $DomainAccountPassword, $serviceNameOfSecondaryReplicaInstance, $timeout





CD "SQLSERVER:\SQL\$AlwaysonAgPrimaryReplicaHostName\$AlwaysonAgPrimaryReplicaInstanceName\AvailabilityGroups"

#sqlcmd -S $alwaysonAgPrimaryReplicaServerInstance -i C:\Temp\table.sql

try
{
	Write-Output "Backing up database '$AlwaysonAgDatabaseName' to location $alwaysonAgBackupLocation"

        # Add -Initialize argument to ensure a fresh backup /Mark 2016-5-23

	Backup-SqlDatabase $AlwaysonAgDatabaseName "$alwaysonAgBackupLocation\$AlwaysonAgDatabaseName.bak" -Initialize
	Backup-SqlDatabase $AlwaysonAgDatabaseName "$alwaysonAgBackupLocation\$AlwaysonAgDatabaseName.trn" -BackupAction Log -Initialize
}
catch
{
	Write-Error "Error while backing up database '$AlwaysonAgDatabaseName' to location $alwaysonAgBackupLocation. Error: $_.Exception"
	exit 1
}

# Create an in-memory representation of the primary replica.
$primaryReplica = New-SqlAvailabilityReplica `
    -Name $alwaysonAgPrimaryReplicaServerInstance `
    -EndpointURL "TCP://$AlwaysonAgPrimaryReplicaHostName.${DomainFull}:$AlwaysonAgHadrEndpointPort" `
    -AvailabilityMode "SynchronousCommit" `
    -FailoverMode "Automatic" `
    -Version $serverPrimary.VersionMajor `
    -ConnectionModeInPrimaryRole "AllowAllConnections" `
    -ConnectionModeInSecondaryRole "AllowAllConnections" `
    -AsTemplate

# Create an in-memory representation of the secondary replica.
$secondaryReplica = New-SqlAvailabilityReplica `
    -Name $alwaysonAgSecondaryReplicaServerInstance `
    -EndpointURL "TCP://$AlwaysonAgSecondaryReplicaHostname.${DomainFull}:$AlwaysonAgHadrEndpointPort" `
    -AvailabilityMode "SynchronousCommit" `
    -FailoverMode "Automatic" `
    -Version $serverSecondary.VersionMajor `
    -ConnectionModeInSecondaryRole "AllowAllConnections" `
    -ConnectionModeInPrimaryRole "AllowAllConnections" `
    -AsTemplate

# Create the availability group
try
{
	Write-Output "Creating AvailabilityGroup '$AlwaysonAgName'..."
	New-SqlAvailabilityGroup `
	    -Name $AlwaysonAgName `
	    -Path "SQLSERVER:\SQL\$AlwaysonAgPrimaryReplicaHostName\$AlwaysonAgPrimaryReplicaInstanceName" `
	    -AvailabilityReplica @($primaryReplica,$secondaryReplica) `
	    -Database $AlwaysonAgDatabaseName 
}
catch
{
	Write-Error "Failed to create Availability Group. Error: $_.Exception"
	exit 1
}

# Create the SQL Connection Object  
$SQLConn=New-Object System.Data.SQLClient.SQLConnection  

# Create the SQL Command Ojbect  
$SQLCmd=New-Object System.Data.SQLClient.SQLCommand  

# Set our connection string property on the SQL Connection Object 
$SQLConn.ConnectionString="Server=$alwaysonAgSecondaryReplicaServerInstance;Integrated Security=SSPI" 
 
# Open the connection 
try
{
	Write-Output "Connecting to Server Instance '$alwaysonAgSecondaryReplicaServerInstance'..."
	$SQLConn.Open() 
}
catch
{
	Write-Error "Error occurred while connecting to Server Instance '$alwaysonAgSecondaryReplicaServerInstance'. Error: $_.Exception"
	exit 1
}

# Join the secondary replica to the availability group.
try
{
	Write-Output "Joining Server Instance '$alwaysonAgSecondaryReplicaServerInstance' to Availability Group '$AlwaysonAgName'"
	Join-SqlAvailabilityGroup -Path "SQLSERVER:\SQL\$AlwaysonAgSecondaryReplicaHostname\$AlwaysonAgSecondaryReplicaInstanceName" -Name $AlwaysonAgName
}
catch
{
	Write-Error "Error occurred while joining Server Instance '$alwaysonAgSecondaryReplicaServerInstance' to Availability Group '$AlwaysonAgName'. Error: $_.Exception"
	exit 1
}

#modified by Mark line 329~363 in EHC 4.0 verification to ensure a correct restore path if Node 2 has a different instance name to Node 1. 5/23/2016 

CD "SQLSERVER:\SQL\$AlwaysonAgSecondaryReplicaHostname\$AlwaysonAgSecondaryReplicaInstanceName\AvailabilityGroups"

# change restore location if use different instance name
$fileloc = $serverSecondary.Settings.DefaultFile
$logloc = $serverSecondary.Settings.DefaultLog
if ($fileloc.Length -eq 0) {
    $fileloc = $serverSecondary.Information.MasterDBPath
    }
if ($logloc.Length -eq 0) {
    $logloc = $serverSecondary.Information.MasterDBLogPath
    }

$dbfile = $fileloc + '\'+ $AlwaysonAgDatabaseName + '.mdf'
$logfile = $logloc + '\'+ $AlwaysonAgDatabaseName + '_Log.ldf'

$LogicalDataName = $AlwaysonAgDatabaseName
$LogicalLogName = $AlwaysonAgDatabaseName + '_Log'

$RelocateData = New-Object Microsoft.SqlServer.Management.Smo.RelocateFile( $LogicalDataName , $dbfile)
$RelocateLog = New-Object Microsoft.SqlServer.Management.Smo.RelocateFile( $LogicalLogName, $logfile)

try
{
	Write-Output "Restoring database '$AlwaysonAgDatabaseName' from location '$alwaysonAgBackupLocation'"
	#Restore-SqlDatabase $AlwaysonAgDatabaseName "$alwaysonAgBackupLocation\$AlwaysonAgDatabaseName.bak" -NoRecovery
    Restore-SqlDatabase $AlwaysonAgDatabaseName "$alwaysonAgBackupLocation\$AlwaysonAgDatabaseName.bak" -NoRecovery -RelocateFile @($RelocateData,$RelocateLog)
	#Restore-SqlDatabase $AlwaysonAgDatabaseName "$alwaysonAgBackupLocation\$AlwaysonAgDatabaseName.trn" -RestoreAction "Log" -NoRecovery
	Restore-SqlDatabase $AlwaysonAgDatabaseName "$alwaysonAgBackupLocation\$AlwaysonAgDatabaseName.trn" -RestoreAction "Log" -NoRecovery -RelocateFile @($RelocateData,$RelocateLog)
}
catch
{
	Write-Error "Error occurred while restoring database '$AlwaysonAgDatabaseName' from location '$alwaysonAgBackupLocation'. Error: $_.Exception"
	exit 1
}

# Join database in secondary replica to the availability group.
try
{
	Write-Output "Joining database '$AlwaysonAgDatabaseName' to Availability Group '$AlwaysonAgName'"
	Add-SqlAvailabilityDatabase -Path "SQLSERVER:\SQL\$AlwaysonAgSecondaryReplicaHostname\$AlwaysonAgSecondaryReplicaInstanceName\AvailabilityGroups\$AlwaysonAgName" -Database $AlwaysonAgDatabaseName
}
catch
{
	Write-Error "Error occurred while joining database '$AlwaysonAgDatabaseName' to Availability Group '$AlwaysonAgName'. Error: $_.Exception"
	exit 1
}

# Create Always On Listener
If ($AlwaysonListenerOption) {
	$StaticIpNetMask = $AlwaysonAgListenerStaticIp + "/" + $AlwaysonAgListenerNetMask
	New-SqlAvailabilityGroupListener -Name $AlwaysonAgListenerName -StaticIp $StaticIpNetMask -Path "SQLSERVER:\Sql\$AlwaysonAgPrimaryReplicaHostName\$AlwaysonAgPrimaryReplicaInstanceName\AvailabilityGroups\$AlwaysonAgName" -Port $AlwaysonAgListenerPort
}
