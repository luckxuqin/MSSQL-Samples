$installMedia = "<0>"
$instanceName = "<1>"
$shareUserName = "<2>"
$sharePassword = "<3>"

function regKeyExist {
    Param ($regKeyPath, $regKeyName) 
    try {
        $key = Get-ItemProperty $regKeyPath -Name $regKeyName -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

if($installMedia.Contains(":\")) {
    $networkShare = $false
    $localInstallPath = $installMedia
}
else {
    $networkShare = $true  
    $leafFolder = split-path -path $installMedia -Leaf
    $localInstallPath = Join-Path -Path $env:TEMP -ChildPath $leafFolder

	if ($shareUserName -eq "") {
		Net use Z: "$installMedia"
	}
	else {
		Net use Z: "$installMedia" $sharePassword /user:$shareUserName
	}
	
	$localInstallPath = "Z:\"
}

$setupPath = Join-Path -Path $localInstallPath -ChildPath "setup.exe"

try {
	start-process -FilePath $setupPath -ArgumentList @("/QUIET", "/ACTION=INSTALL", "/FEATURES=SQLENGINE","/INSTANCENAME=$instanceName", "/IACCEPTSQLSERVERLICENSETERMS" ,"/SQLSYSADMINACCOUNTS=$($env:USERDOMAIN)\$($env:USERNAME)", "/UPDATEENABLED=FALSE") -Wait -NoNewWindow -PassThru
}
catch {
	if ($networkShare){
		net use Z: /delete
	}
	Throw "Error while installing $instanceName" | Format-List
}

if($networkShare) {
	start-sleep -Seconds 10
	net use Z: /delete
}

#Validate instance was deleted
$regKeyX86 = "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Microsoft SQL Server\Instance Names\SQL\"
$regKeyX64 = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL\"

if((regKeyExist $regKeyX86 $instanceName) -or (regKeyExist $regKeyX64 $instanceName)) {
	write-host "Instance $instanceName created successfully"
}
else {
    throw "ERROR: SQL Instance failed to be created. Check sql logs in $env:temp folder on machine"
}