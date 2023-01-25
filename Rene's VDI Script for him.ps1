Stop-VM * -Force
Remove-VM * -Force
Remove-Item -Path 'F:\VDI\*' -Force
Remove-VMSwitch Private -Force

$LocalUser = 'administrator'
$DomainUser = 'contoso\administrator'
$pwd = ConvertTo-SecureString 'Pa11word' -AsPlainText -Force
$LocalAuth = New-Object System.Management.Automation.PSCredential($LocalUser,$pwd)
$DomainAuth = New-Object System.Management.Automation.PSCredential($DomainUser,$pwd)
$domainName = 'contoso.com'
$vhd_path = "D"
$parent_disk = Get-Item -Path "$($vhd_path):VHDs\Parent\*.vhdx" | Out-GridView -Title "Choose the parent disk" -PassThru

Start-Sleep 10

New-VMSwitch -Name Public  -NetAdapterName "Ethernet 2" -AllowManagementOS $true 
New-VMSwitch -Name Private -SwitchType Private

$PublicInterface = Get-NetAdapter | where { $_.Status -eq "Up" } | Select-Object -ExpandProperty Name

New-VHD -Path 'F:\VDI\NAT.vhdx' -ParentPath $parent_disk
New-VHD -Path 'F:\VDI\DC.vhdx' -ParentPath $parent_disk
New-VHD -Path 'F:\VDI\RDS.vhdx' -ParentPath $parent_disk

New-VM -Name "NAT" -VHDPath "F:\VDI\NAT.vhdx" -SwitchName Private -Generation 2 -Force
New-VM -Name "DC" -VHDPath "F:\VDI\DC.vhdx" -SwitchName Private -Generation 2 -Force
New-VM -Name "RDS" -VHDPath "F:\VDI\RDS.vhdx" -SwitchName Private -MemoryStartupBytes 6144MB -Generation 2 -Force


Set-VM -Name * -AutomaticCheckpointsEnabled $false

Add-VMNetworkAdapter -VMName NAT -SwitchName Public

Set-VMMemory * -DynamicMemoryEnabled $true

Start-VM *

Read-Host -Prompt "Hit enter once all virtual machines are completely booted"

$s = Get-VMNetworkAdapter -VMName NAT | Where-Object { $_.SwitchName -eq "Private" } | Select-Object -ExpandProperty MacAddress
$PrivateMACNAT = $s -replace '..(?!$)', '$&-'
$s = Get-VMNetworkAdapter -VMName NAT | Where-Object { $_.SwitchName -eq "Public" } | Select-Object -ExpandProperty MacAddress
$PublicMACNAT = $s -replace '..(?!$)', '$&-'

$ran = Get-Random -Minimum 10 -Maximum 254

Invoke-Command -VMName NAT -Credential $LocalAuth -ArgumentList $PrivateMACNAT,$PublicMACNAT -ScriptBlock {
param($PrivateMACNAT,$PublicMACNAT)
    Get-NetAdapter | Where-Object { $_.MacAddress -eq $PublicMACNAT } | Rename-NetAdapter -NewName Public
    Get-NetAdapter | Where-Object { $_.MacAddress -eq $PrivateMACNAT } | Rename-NetAdapter -NewName Private
    Start-Sleep 5
    New-NetIPAddress -IPAddress 172.16.0.1 -PrefixLength 16 -InterfaceAlias Private    
    New-NetIPAddress -IPAddress 10.3.13.$ran -PrefixLength 22 -DefaultGateway 10.3.12.1 -InterfaceAlias Public
    Set-DnsClientServerAddress -ServerAddresses 172.16.0.2 -InterfaceAlias *
}

Invoke-Command -VMName NAT -Credential $LocalAuth -ScriptBlock {
    Install-WindowsFeature -Name routing -IncludeManagementTools
    Rename-Computer -NewName nat -Restart
}

Invoke-Command -VMName DC -Credential $LocalAuth -ScriptBlock {
    New-NetIPAddress -IPAddress 172.16.0.2 -PrefixLength 16 -DefaultGateway 172.16.0.1 -InterfaceAlias "Ethernet"
    Set-DnsClientServerAddress -ServerAddresses 10.13.2.5,10.13.2.7 -InterfaceAlias *
    Install-WindowsFeature -Name ad-domain-services -IncludeManagementTools -Restart
    Rename-Computer -NewName dc -Restart
}

Read-Host -Prompt "Configure NAT routing and remote access. Press Enter"

Invoke-Command -VMName DC -Credential $LocalAuth -ArgumentList $domainName,$pwd -ScriptBlock {
    param($domainName,$pwd)
    Install-ADDSForest -DomainName $domainName -SafeModeAdministratorPassword $pwd -SkipPreChecks -Force
}

Read-Host -Prompt "Wait for DC to finish rebooting then continue"

Invoke-Command -VMName DC -Credential $DomainAuth  -ArgumentList $domainName,$DomainAuth,$pwd -ScriptBlock {
    param($domainName,$DomainAuth,$pwd)
    Add-DnsServerPrimaryZone -NetworkID 172.16/16 -ReplicationScope Forest
    Register-DnsClient
    Install-ADDSDomainController -DomainName $domainName -InstallDns -NoGlobalCatalog -Credential $DomainAuth -SafeModeAdministratorPassword $pwd -Force
    Add-WindowsFeature Adcs-Cert-Authority -IncludeManagementTools
    Install-AdcsCertificationAuthority -CAType StandaloneRootCa
    Add-WindowsFeature RSAT-ADCS,RSAT-ADCS-mgmt,ADCS-Enroll-Web-Pol,ADCS-Enroll-Web-Svc,ADCS-Online-Cert,ADCS-Web-Enrollment
}

Invoke-Command -VMName RDS -Credential $LocalAuth -ArgumentList $domainName,$DomainAuth -ScriptBlock {
    param($domainName,$DomainAuth)
    New-NetIPAddress -IPAddress 172.16.0.3 -PrefixLength 16 -DefaultGateway 172.16.0.1 -InterfaceAlias "Ethernet"
    Set-DnsClientServerAddress -ServerAddresses 172.16.0.2 -InterfaceAlias *
    Add-Computer -NewName rds -DomainName $domainName -Credential $DomainAuth -Restart
}

Read-Host -Prompt "Press Enter after RDS has fully booted"

Stop-VM RDS -Force

Set-VMProcessor -VMName RDS -ExposeVirtualizationExtensions $true
Get-VMNetworkAdapter -VMName RDS | Set-VMNetworkAdapter -MacAddressSpoofing On
$tss = Get-WmiObject -Namespace root\CIMv2\TerminalServices -Class win32_terminalservicesetting
$tss.setallowtsconnections(1,0)

Start-VM RDS

Invoke-Command -VMName "DC" -Credential $DomainAuth -ScriptBlock {

    $userone = @{
    Enable = $true
    ChangePasswordAtLogon = $false
    UserPrincipalName = "uone@contoso.com"
    Name = "User One"
    GivenName = "User"
    Surname= "One"
    SamAccountName = "uone"
    DisplayName = "User One"
    AccountPassword = ConvertTo-SecureString Pa11word -AsPlainText -Force
    } 
    New-ADUser @userone

    $usertwo = @{
    Enable = $true
    ChangePasswordAtLogon = $false
    UserPrincipalName = "utwo@contoso.com"
    Name = "User Two"
    GivenName = "User"
    Surname= "Two"
    SamAccountName = "utwo"
    DisplayName = "User Two"
    AccountPassword = ConvertTo-SecureString Pa11word -AsPlainText -Force
    } 
    New-ADUser @usertwo

    $userthree = @{
    Enable = $true
    ChangePasswordAtLogon = $false
    UserPrincipalName = "uthree@contoso.com"
    Name = "User Three"
    GivenName = "User"
    Surname= "One"
    SamAccountName = "uthree"
    DisplayName = "User Three"
    AccountPassword = ConvertTo-SecureString Pa11word -AsPlainText -Force
    } 
    New-ADUser @userthree

    $userfour = @{
    Enable = $true
    ChangePasswordAtLogon = $false
    UserPrincipalName = "ufour@contoso.com"
    Name = "User Four"
    GivenName = "User"
    Surname= "Four"
    SamAccountName = "ufour"
    DisplayName = "User Four"
    AccountPassword = ConvertTo-SecureString Pa11word -AsPlainText -Force
    } 
    New-ADUser @userfour
}