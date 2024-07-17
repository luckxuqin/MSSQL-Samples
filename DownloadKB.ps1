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
$URL1 = "https://download.microsoft.com/download/D/6/0/D60ED3E0-93A5-4505-8F6A-8D0A5DA16C8A/Windows8.1-KB2919442-x64.msu"
$KB2 = "KB2919355"
$URL2 = "https://download.microsoft.com/download/2/5/6/256CCCFB-5341-4A8D-A277-8A81B21A1E35/Windows8.1-KB2919355-x64.msu"
$KB3 = "KB3151864"
$URL3 = "https://download.microsoft.com/download/F/9/4/F942F07D-F26F-4F30-B4E3-EBD54FABA377/NDP462-KB3151800-x86-x64-AllOS-ENU.exe"

$FilePath = Get-Location
$DownLoadPath = "$FilePath\SQLKB"

if(!(Test-Path $DownLoadPath)) {
	New-Item $DownLoadPath -type directory
}

$ExePath1 = $DownLoadPath + "\" + $KB1 + ".msu"
$ExePath2 = $DownLoadPath + "\" + $KB2 + ".msu"
$ExePath3 = $DownLoadPath + "\" + $KB3 + ".exe"

Write-Host "`nDownloading Hotfix $KB1...`n"
Invoke-webrequest -URI $URL1 -OutFile $ExePath1
Write-Host "Download completed"

Write-Host "`nDownloading Hotfix $KB2...`n"
Invoke-webrequest -URI $URL2 -OutFile $ExePath2
Write-Host "Download completed"

Write-Host "`nDownloading Hotfix $KB3...`n"
Invoke-webrequest -URI $URL3 -OutFile $ExePath3
Write-Host "Download completed"

