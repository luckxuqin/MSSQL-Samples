<#
.Synopsis - Create a new database with data and file in specified directory
.PARAMATER InstanceName - the sql server instance on which to operate
.PARAMATER DatabaseName - the database name which to create
.PARAMATER DataPath - the data file location
.PARAMATER LogPath - the log file location
.Return - list databases in your instance
#>

# Paramaters with user input
$InstanceName =  "MSSQLSERVER"
$DatabaseName = "SMODB8"
$DataPath = "G:\Data"
$LogPath = "L:\Log"

# Paramaters without user input
$ServerName = $env:computername
$LogicalDataFile=$DatabaseName + "_Data"
$LogicalLogFile=$DatabaseName + "_Log"
$datapath1=$DataPath + "\" + $DatabaseName + "_Data.mdf"
$Logpath1=$LogPath  + "\" + $DatabaseName +  "_Log.ldf"

if ($InstanceName -eq "mssqlserver") {
    $Server = "$ServerName"
    }
else {
    $Server = "$ServerName" + "\" + "$InstanceName"
    }

#load assembly for SMO
try{
    [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo") | Out-Null
}
catch{
	throw "Cannot load SMO Assembly"
}

try{

$s= New-Object Microsoft.SqlServer.Management.Smo.Server($Server)

# Instantiate the database object and add the filegroups
$db = new-object ('Microsoft.SqlServer.Management.Smo.Database') ($s, $DatabaseName)
$fg = new-object ('Microsoft.SqlServer.Management.Smo.FileGroup') ($db, 'PRIMARY')
$db.FileGroups.Add($fg)

# Create the file for the data
$dbDataFile = new-object ('Microsoft.SqlServer.Management.Smo.DataFile') ($fg, $LogicalDataFile)
$fg.Files.Add($dbDataFile) 
$dbDataFile.FileName = $datapath1

# Create the file for the log 
$dbLogFile = new-object ('Microsoft.SqlServer.Management.Smo.LogFile') ($db, $LogicalLogFIle)
$db.LogFiles.Add($dbLogFile)
$dbLogFile.FileName = $Logpath1

# Create the database
$db.Create()

#To confirm, list databases in your instance
$s.Databases |
Select Name, Status, Owner, CreateDate
}

catch{
     throw "ERROR: Database $DatabaseName already exists"
}
