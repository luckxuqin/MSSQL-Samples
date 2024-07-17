add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

$KB1 = "KB2919442"
$KB2 = "KB2919355"
$KB3 = "KB3151864"
$FilePath = "C:\SQLKB"
New-Item $FilePath -type directory
$ExePath1 = $FilePath + "\" + $KB1 + ".msu"
$CabName1 = "Windows8.1-KB2919442-x64.cab"
$ExePath2 = $FilePath + "\" + $KB2 + ".msu"
$CabName2 = "Windows8.1-KB2919355-x64.cab"
$ExePath3 = $FilePath + "\" + $KB3 + ".exe"

$HotFixQuery1 = Get-HotFix | Where-Object {$_.HotFixId -eq $KB1} | Select-Object -First 1;
if($HotFixQuery1 -eq $null) {
	try {
		Write-Host "`nDownloading Hotfix $KB1...`n"
		Invoke-webrequest -URI "https://download.microsoft.com/download/D/6/0/D60ED3E0-93A5-4505-8F6A-8D0A5DA16C8A/Windows8.1-KB2919442-x64.msu" -OutFile $ExePath1
		
		Write-Host "Installing...`n"
		winrs.exe -r:$env:computername wusa.exe $ExePath1 /extract:$FilePath
		winrs.exe -r:$env:computername dism.exe /online /add-package /PackagePath:$FilePath\$CabName1 /NoRestart
		Write-Host "Install Hotfix $KB1 successfully...`n"
	}
	catch {
		throw "$KB1 installation failed!`n"
		Remove-Item $FilePath -force -recurse
	}
}
else
{
	Write-Host "Hotfix $KB1 already installed`n"
}

$HotFixQuery2 = Get-HotFix | Where-Object {$_.HotFixId -eq $KB2} | Select-Object -First 1;
if($HotFixQuery2 -eq $null) {
	try {
		Write-Host "`nDownloading Hotfix $KB2...`n"
		Invoke-webrequest -URI "https://download.microsoft.com/download/2/5/6/256CCCFB-5341-4A8D-A277-8A81B21A1E35/Windows8.1-KB2919355-x64.msu" -OutFile $ExePath2
		
		Write-Host "Installing...`n"
		winrs.exe -r:$env:computername wusa.exe $ExePath2 /extract:$FilePath
		winrs.exe -r:$env:computername dism.exe /online /add-package /PackagePath:$FilePath\$CabName2 /NoRestart
		Write-Host "Install Hotfix $KB2 successfully...`n"
	}
	catch {
		throw "$KB2 installation failed!`n"
		Remove-Item $FilePath -force -recurse
	}
}
else
{
	Write-Host "Hotfix $KB2 already installed`n"
}

$HotFixQuery3 = Get-HotFix | Where-Object {$_.HotFixId -eq $KB3} | Select-Object -First 1;
if($HotFixQuery3 -eq $null) {
	try {
		Write-Host "`nDownloading Hotfix $KB3...`n"
		Invoke-webrequest -URI "https://download.microsoft.com/download/F/9/4/F942F07D-F26F-4F30-B4E3-EBD54FABA377/NDP462-KB3151800-x86-x64-AllOS-ENU.exe" -OutFile $ExePath3
		
		Write-Host "Installing...`n"
		Start-Process -FilePath $ExePath3 -ArgumentList "/q /norestart" -Wait
		Write-Host "Install Hotfix $KB3 successfully...`n"
	}
	catch {
		throw "$KB3 installation failed!`n"
		Remove-Item $FilePath -force -recurse
	}
}
else
{
	Write-Host "Hotfix $KB3 already installed`n"
}

Remove-Item $FilePath -force -recurse

Install-WindowsFeature -Name Failover-Clustering –IncludeManagementTools
Install-WindowsFeature Net-Framework-Core,NET-Framework-45-Features

Write-Host "`nPlease restart the machine to complete customization for SQL Server VM template...`n"

