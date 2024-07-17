Function Backup-Database {
	param ($dbName,$backupLocation, $instanceName)
	if ($instanceName -eq "MSSQLSERVER") { 
		$instance = "$env:COMPUTERNAME"
	}
	else {
		$instance = "$env:COMPUTERNAME\$instanceName"
	}
	Invoke-Command -ComputerName "$env:COMPUTERNAME.$env:USERDNSDOMAIN" -Authentication Credssp -Credential $credentials -ScriptBlock {
		param ($backupLocation)
		$exists = Test-Path $backupLocation 
		if(!$exists){
			Throw "Backup Location $backupLocation does not exist"
		}
	} -ArgumentList $backupLocation
	
    try{
		Write-Output "Backing Up database $dbName to $backupLocation"
		Backup-SqlDatabase -ServerInstance $instance -Database $dbName  "$backupLocation\$dbName.bak" -Initialize
		Backup-SqlDatabase -ServerInstance $instance -Database $dbName "$backupLocation\$dbName.trn" -BackupAction Log -Initialize
    }
	catch {
		Throw "Error while backing up database $dbName to location $backupLocation. Error: $_.Exception" 
    }
}

Function Restore-Database {
	param ($dbName,$backupLocation, $restoreDataPath, $restoreLogPath, $instanceName, $agName,$credentials)
	
	if ($instanceName -eq "MSSQLSERVER") { 
		$instance = "$env:COMPUTERNAME"
	}
	else {
		$instance = "$env:COMPUTERNAME\$instanceName"
	}
	
	$server = New-Object ('Microsoft.SqlServer.Management.SMO.Server') $instance
	
	if($instanceName -eq "MSSQLSERVER"){
		$instanceName = ""
	}
	
	$ag = $server.AvailabilityGroups[$agName]
	$replicas = $ag.AvailabilityReplicas
	$dbfile = $restoreDataPath + "\" + $dbName + ".mdf" 
	$logfile = $restoreLogPath + "\" + $dbName + "_Log.ldf" 
	$LogicalDataName = $dbName + "_Data"
	$LogicalLogName = $dbName + "_Log" 
	$RelocateData = New-Object ('Microsoft.SqlServer.Management.Smo.RelocateFile')($LogicalDataName, $dbfile) 
	$RelocateLog = New-Object ('Microsoft.SqlServer.Management.Smo.RelocateFile')($LogicalLogName, $logfile) 
	
	foreach ($replica in $replicas){
		if ($replica.Role -eq "Secondary"){
			$secondary = $replica.Name.toString()
			$hostname = $secondary.Split("\")[0] 
			Invoke-Command -ComputerName "$hostname.$env:USERDNSDOMAIN" -Authentication Credssp -Credential $credentials -ScriptBlock {
				param ($dbName, $backupLocation, $restoreDataPath, $restoreLogPath, $agName, $secondary, $RelocateData, $RelocateLog)
				
				if ($restoreDataPath.length -eq 0) {
					$restoreDataPath = $server.Information.MasterDBPath
				}
				elseif (!(Test-Path $restoreDataPath)) {
					New-Item $restoreDataPath -type directory
				}
				else {
					write-host "DataPath $restoreDataPath already exists!"
				}

				if ($restoreLogPath.length -eq 0) {
					$restoreLogPath = $server.Information.MasterDBLogPath
				}
				elseif (!(Test-Path $restoreLogPath)) {
					New-Item $restoreLogPath -type directory
				}
				else {
					write-host "LogPath $restoreLogPath already exists!"
				}
				
				try {
					Write-Host "Database $dbName only exists on Primary, restoring to Secondary replica instance $secondary"
					Restore-SqlDatabase -ServerInstance $secondary -Database $dbName "$backupLocation\$dbName.bak" -NoRecovery -RelocateFile @($RelocateData,$RelocateLog) 
					Restore-SqlDatabase -ServerInstance $secondary -Database $dbName "$backupLocation\$dbName.trn"  -RestoreAction Log -NoRecovery -RelocateFile @($RelocateData,$RelocateLog) 
				}

				catch {
					Throw "Error while restoring  database $dbName from location $backupLocation. Error: $_.Exception" | Format-List
				}
			} -Argumentlist $dbName, $backupLocation, $restoreDataPath, $restoreLogPath, $agName, $secondary, $RelocateData, $RelocateLog
		}
	}
}

Function Add-Database-AAG{
	param($dbName, $agName, $instanceName,$credentials)
	Write-Host "Adding database $dbName to Availability Group $agName"
	
	# Alwayson AG for default instance
	if ($instanceName -eq "MSSQLSERVER") { 
		$instance = "$env:COMPUTERNAME"
		Add-SqlAvailabilityDatabase -Path "SQLServer:\SQL\$env:computerName\default\AvailabilityGroups\$agName" -Database $dbName 
	}
	else {
		$instance = "$env:COMPUTERNAME\\$instanceName"
		Add-SqlAvailabilityDatabase -Path "SQLServer:\SQL\$env:computerName\$instanceName\AvailabilityGroups\$agName" -Database $dbName 
	}

	$server = New-Object ('Microsoft.SqlServer.Management.SMO.Server') $instance
	$ag = $server.AvailabilityGroups[$agName]
	$replicas = $ag.AvailabilityReplicas
	foreach ($replica in $replicas){
		if ($replica.Role -eq "Secondary"){
			$secondary = $replica.Name.toString()
			$hostname = $secondary.Split("\")[0] 
			Invoke-Command -ComputerName "$hostname.$env:USERDNSDOMAIN" -Authentication Credssp -Credential $credentials -ScriptBlock{
				param ($dbName, $agName, $instanceName, $secondary)
				try{
					Write-Output "Joining Secondary Replica database $dbName to Availability Group $agName on replica Instance $secondary"
					
					#AlwaysOn AG for default instance
					if ($instanceName -eq "MSSQLSERVER") { 
						Add-SqlAvailabilityDatabase -Path "SQLServer:\SQL\$secondary\default\AvailabilityGroups\$agName" -Database $dbName 
					}
					else {
						Add-SqlAvailabilityDatabase -Path "SQLServer:\SQL\$secondary\AvailabilityGroups\$agName" -Database $dbName 
					}
				}
				catch{
					Throw "Error occurred while joining secondary database $dbName to Availability Group $agName on $secondary. Error: $_.Exception"
				}
			} -ArgumentList $dbName, $agName, $instanceName, $secondary
		}
	}
}

$dbName = "mydb3"
$backupLocation = "\\10.110.96.77\aag"
$instanceName = "mssqlserver"
$agname = "AG1"
$username = "administrator@ehc40dev.local"
$password = "Password01!"
$restoreDataPath = "C:\test\data"
$restoreLogPath = "C:\test\log"

$PasswordSecure = ConvertTo-SecureString -String $password -AsPlainText -Force
$credentials= New-Object System.Management.Automation.PSCredential $username,$PasswordSecure

try{
    [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SMO") | Out-Null
}
catch{
	throw "Cannot load SMO Assembly"
}

Backup-Database -dbName $dbName -backupLocation $backupLocation -instanceName $instanceName
Restore-Database -dbName $dbName -backupLocation $backupLocation -restoreDataPath $restoreDataPath -restoreLogPath $restoreLogPath -instanceName $instanceName -agName $agName -credentials $credentials
Add-Database-AAG -dbName $dbName -agName $agName -instanceName $instanceName -credentials $credentials

