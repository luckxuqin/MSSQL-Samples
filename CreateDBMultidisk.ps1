$instanceName = "<0>"
$dbNamesAsString = "<1>"
$dataPath = "<2>"
$logPath = "<3>"

$dbNamesArr = $dbNamesAsString.split(',')

# get instance name
if ($InstanceName -eq "mssqlserver") {
    $Server = "$env:COMPUTERNAME"
}
else {
    $Server = "$env:COMPUTERNAME" + "\" + "$InstanceName"
}

# load smo
try{
    [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo") | Out-Null
}
catch{
	throw "Cannot load SMO Assembly"
}

# create directory
if (!(Test-Path $dataPath)) {
	New-Item $dataPath -type directory
}
else {
	write-host "DataPath $dataPath already exists!"
}

if (!(Test-Path $logPath)) {
	New-Item $logPath -type directory
}
else {
	write-host "logPath $logPath already exists!"
}

# return object
$returnStatus = New-Object PSObject -Property @{
    Success=$True;
    Message="Command completed successfully";
}

$server = New-Object Microsoft.SqlServer.Management.SMO.Server($Server)

foreach ($dbName in $dbNamesArr) {
	$db = $server.Databases[$dbName]
	if (!($db)) {
		try{
			$logicalDataFile = $dbName + "_Data"
			$logicalLogFile = $dbName + "_Log"
			$datapathfull = $dataPath + "\" + $dbName + "_Data.mdf"
			$logpathfull = $logPath  + "\" + $dbName +  "_Log.ldf"
			
			# Instantiate the database object and add the filegroups
			$db = New-Object ('Microsoft.SqlServer.Management.SMO.Database') ($server, $dbName)
			$fg = New-object ('Microsoft.SqlServer.Management.SMO.FileGroup') ($db, 'PRIMARY')
			$db.FileGroups.Add($fg)

			# Create the file for the data
			$dbDataFile = new-object ('Microsoft.SqlServer.Management.SMO.DataFile') ($fg, $logicalDataFile)
			$fg.Files.Add($dbDataFile) 
			$dbDataFile.FileName = $datapathfull
			
			# Create the file for the log 
			$dbLogFile = new-object ('Microsoft.SqlServer.Management.SMO.LogFile') ($db, $logicalLogFile)
			$db.LogFiles.Add($dbLogFile)
			$dbLogFile.FileName = $logpathfull
			
			# Create the database
			$db.Create()
		}
		catch{
			Write-Host $_.Exception.Message
		    	$returnStatus.Success = $False
			$returnStatus.Message = $_.Exception.Message
		}		
	}
	else {
		throw "ERROR: Database $dbName already exists."
	}
}