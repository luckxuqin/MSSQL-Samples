# Name install.ps1

# SYNOPSIS
# This script adds the virtual machine to AD Domain
                
write-output "Changing password of the local administrator..."
net user Administrator $prop_local_admin_password

write-output  "Updating DNS server in network settings..."
$wmi = Get-WmiObject win32_networkadapterconfiguration -filter "ipenabled = 'true'"
$wmi.SetDNSServerSearchOrder("$prop_dns_ip")
$outputMessage = "DNS has been successfully set to: " + $prop_dns_ip
write-output $outputMessage

$outputMessage= "Adding virtual machine to domain: " + $prop_domain_name
write-output $outputMessage
Add-Computer -DomainName $prop_domain_name -credential (`
                New-Object System.Management.Automation.PSCredential (`
                                "$prop_domain_name\$prop_domain_user", `
                                (ConvertTo-SecureString $prop_domain_password -AsPlainText -Force)`
                )`
)
if($?){ 
    write-output "Host added to domain successfully" 
    $HostnameDebug = [System.Net.DNS]::GetHostByName('').HostName 
    write-output "Host FQDN is $HostnameDebug" 
} 
else {
    write-output "Host is not added to domain"
                $outputMessage= "Domain name is: " + $prop_domain_name
                write-output $outputMessage
                $outputMessage= "Domain user name is: " + $prop_domain_user
                write-output $outputMessage
                $HostnameDebug = [System.Net.DNS]::GetHostByName('').HostName 
    write-output "Host FQDN is $HostnameDebug" 
    exit
}

###########################################################################################################
#Script to enable remote commands to work in PowerShell when running from within VCAC. Required to overcome Microsoft double hop mechanism within PowerShell
#See http://blogs.msdn.com/b/clustering/archive/2009/06/25/9803001.aspx for an explanation of why this is a requirement
#Caveat - changes registry keys to allow invoke commands to work from VCAC - this is because some commands need to delegate credentials to the domain Admin

#No external variables required as input from VCAC 
#Internal Variables

#Hostname - The FQDN of the local host. Used to add to the allowed WSMAN systems. 
#Version - A string to hold the version of the operating system currently running
#allowed - WSMAN/* allows all machines to remote send winrm commands to this machine 
#trusted - a variable name to name the registry key properties we need to create
#rootRegister - the root registry we need to create to enable NTLM delegation 
#freshCredentials - container variable
#NTLMOnly - container variable


#Function to check if a registry key exists - takes a path to the key as a parameter
function testRegistryKey{
    param(
        [Parameter(Mandatory=$true)]
        [string]
        # The path to the registry key where the value should be set.  Will be created if it doesn't exist.
        $Path)
                                if( !(Test-Path -Path $Path -PathType Container) )
                {
                New-Item -Path $Path -ItemType Key -Verbose -Force
                }
                                else {
            Write-Output "Key $Path already Exists"
        }
}

#Function to set value of a registry key
function setRegistryProperty{
    param(
    $Property,
    $Name,
    $Value,
    $Type
    )
        Set-ItemProperty -Path $Property -Name $Name -Value $Value -Type $Type  -Verbose
        Write-Output "Added property $Name $Value to $Property"       
}

$Hostname = [System.Net.DNS]::GetHostByName('').HostName 

Write-Output "Host name FQDN is: $Hostname"

$HostSystem= Get-WmiObject Win32_ComputerSystem
$ComputerName = $HostSystem.Name
$DomainName = $HostSystem.Domain
$FQDN = $ComputerName + "." + $DomainName

if($Hostname.ToLower() -ne $FQDN.ToLower())
{
                $Hostname = $FQDN
                Write-Output "The FQDN of this VM is not correctly get. Replaced with calculated FQDN $Hostname."
}


#Check OS versions
try 
{
                $version = (Get-WmiObject Win32_OperatingSystem).Caption
                Write-Output $version
}
catch
{
                Write-Output ("Could not retrieve Windows Operating System Version " + $_)
}

# block to enable winrm on 2008 R2 (enabled by default on 2012)
if ($version -Match "Microsoft Windows Server 2008 R2*") 
{
                winrm quickconfig -quiet
}

#Edit Registry keys and values to enable Remote PowerShell commands
set-item wsman:\localhost\Client\TrustedHosts -value $Hostname -force

#Set Maximum MB per shell to 2048 to overcome intermittent memory usage errors 

Set-Item WSMan:\localhost\Shell\MaxMemoryPerShellMB 2048

Enable-WSManCredSSP -role server -force
Enable-WSManCredSSP -Role client -DelegateComputer $Hostname -force

$allowed = "WSMAN/$Hostname"           
$trusted = "1"

#Create registry Keys

$rootRegister = 'hklm:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation'
testRegistryKey -Path $rootRegister
$freshCredentials = Join-Path -Path $rootRegister -childPath 'AllowFreshCredentials' 
testRegistryKey -path $freshCredentials
$NTLMOnly = Join-Path -Path $rootRegister -childPath 'AllowFreshCredentialsWhenNTLMOnly'  
testRegistryKey -Path $NTLMOnly

#Create Properties for keys

setRegistryProperty -Property $rootRegister -Name AllowFreshCredentials -Value 1 -Type Dword  
setRegistryProperty -Property $rootRegister -Name AllowFreshCredentialsWhenNTLMOnly -Value 1 -Type Dword        
setRegistryProperty -Property $rootRegister -Name ConcatenateDefaults_AllowFreshNTLMOnly -Value 1 -Type Dword  
setRegistryProperty -Property $freshCredentials -Name $trusted -Value $allowed -Type String       
setRegistryProperty -Property $NTLMOnly -Name $trusted -Value $allowed -Type String 

winrm set winrm/config/service '@{AllowUnencrypted="true"}'
winrm set winrm/config/client '@{AllowUnencrypted="true"}'


#Add the domain account to local administrator group, because SharePoint set up account requires this permission.
$HostnameFQDN = [System.Net.Dns]::GetHostByName(($env:computerName)).hostname
$HostName = $env:computerName
$CommandDir = $null; 

Write-Output "Adding the domain account to local administrator group..."
$DomainWords = $prop_domain_name.Split(".")
$prop_domain_name = $DomainWords[0]

#Debug
$outputMessage= "Domain name is: " + $prop_domain_name
write-output $outputMessage
$outputMessage= "Domain user name is: " + $prop_domain_user
write-output $outputMessage
#Debug

$ObjUser = [ADSI]("WinNT://$prop_domain_name/$prop_domain_user") 
$ObjLocalAdminsGroup = [ADSI]("WinNT://$HostName/administrators") 
$ObjLocalAdminsGroup.PSBase.Invoke("Add",$ObjUser.PSBase.Path) 
Write-Output "Successfully added the domain account to local administrator group."

$FileOldPath = "C:\opt\vmware-appdirector\agent\custom.properties"
$FileNewPath = "C:\opt\vmware-appdirector\agent\custom1.properties"
$NewName = "custom.properties"

write-output  "Changing custom properties"


Get-content –Path $FileOldPath | Select-String -Pattern 'providerid' -NotMatch | Select-String -Pattern 'subtenantid' -NotMatch | Select-String -Pattern 'providerbindingid' -NotMatch| set-content $FileNewPath

Remove-Item -Path $FileOldPath -Force

Rename-Item -Path $FileNewPath -NewName $NewName