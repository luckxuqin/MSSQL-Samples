#################################################################################################################################################################
#Script to enable remote commands to work in Powershell when running from within VCAC. Required to overcome Microsoft double hop mechanism within Powershell
#See http://blogs.msdn.com/b/clustering/archive/2009/06/25/9803001.aspx for an explanation of why this is a requirement
#caveat - changes registry keys to allow invoke commands to work from VCAC - this is because some commands need to delegate credentials to the domain Admin

#Adds communication between primary and secondary nodes as commands for Always on Clustering are required to be run on primary and
#executed on Secodary node. 

#External Variable 
#PrimaryHostName - NodeName of the PrimaryNode
#SecondaryHostName - NodeName of the SecondaryNode
#Internal Variables

#Hostname - The FQDN of the local host. Used to add to the allowed WSMAN systems. 
#Version - A string to hold the version of the operating system currently running
#allowed - WSMAN/* allows all machines to remote send winrm commands to this machine 
#trusted - a variable name to name the registry key properties we need to create
#rootRegister - the root registry we need to create to enable NTLM delegation 
#freshCredentials - container variable
#NTLMOnly - container variable
#################################################################################################################################################################

#Function to check if a regiistry key exists - takes a path to the key as a paramater
function testRegistryKey{
    param(
        [Parameter(Mandatory=$true)]
        [string]
        # The path to the registry key where the value should be set.  Will be created if it doesn't exist.
        $Path)
		if( !(Test-Path -Path $Path -PathType Container) )
    	{
        	New-Item -Path $Path -ItemType Key -Force
    	}
		else {
            Write-Output "Key $Path already Exists"
        }
}

function testRegistryProperty{
    param(
    $Property,
    $Name,
    $Value,
    $Type
    )



        Set-ItemProperty -Path $Property -Name $Name -Value $Value -Type $Type  -Force
        Write-Output "Added property $Name $Value to $Property"       
}



 [string]$PrimaryHost =[System.Net.DNS]::GetHostByName($PrimaryHostName).HostName
 [string]$SecondaryHost =  [System.Net.DNS]::GetHostByName($SecondaryHostName).HostName

 [string[]]$hosts = $PrimaryHost, $SecondaryHost

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


#Edit Registry keys and values to enable Remote Powershell commands




#Set Max MB per shell to 2048 to overcome intermittent memory usage errors 

 
Enable-WSManCredSSP -role server -force
Enable-WSManCredSSP -Role client -DelegateComputer $PrimaryHost,$SecondaryHost -force
 
#$allowed = "WSMAN/$Hostname"           
#$trusted = "1"

#Create registry Keys

$rootRegister = 'hklm:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation'
testRegistryKey -Path $rootRegister
$freshCredentials = Join-Path -Path $rootRegister -childPath 'AllowFreshCredentials' 
testRegistryKey -path $freshCredentials
$NTLMOnly = Join-Path -Path $rootRegister -childPath 'AllowFreshCredentialsWhenNTLMOnly'  
testRegistryKey -Path $NTLMOnly

#Create Properties for keys

testRegistryProperty -Property $rootRegister -Name AllowFreshCredentials -Value 1 -Type Dword  
testRegistryProperty -Property $rootRegister -Name AllowFreshCredentialsWhenNTLMOnly -Value 1 -Type Dword  

$i = 1
foreach ($computer in $hosts){  
Write-Output $Computer  
set-item wsman:\localhost\Client\TrustedHosts -value $Computer -force
testRegistryProperty -Property $freshCredentials -Name $i -Value "WSMAN/$computer" -Type String       
testRegistryProperty -Property $NTLMOnly -Name $i -Value "WSMAN/$computer" -Type String 
$i++
}


#Allow WinRM connections over http protocol   ---added by Winfred at EHC 4.0 verification 5/23/2016
winrm set winrm/config/client '@{AllowUnencrypted="true"}'
winrm set winrm/config/service '@{AllowUnencrypted="true"}'