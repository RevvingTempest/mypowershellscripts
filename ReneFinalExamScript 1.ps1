Stop-VM * -Force
Remove-VM * -Force
Remove-Item -Path 'C:\Users\Public\Documents\Hyper-V\Virtual hard disks\*.vhdx'
Remove-VMSwitch * -Force
Remove-NetNat * -Confirm:$false

$StationNumber = 'cs03'
$VHDDrive = Get-Volume | Out-GridView -PassThru -Title "Choose VHD drive"
$VHDPath = ($($VHDDrive).Driveletter)
$ParentDisk = Get-Item -Path "$($VHDPath):\VHDs\Parent\*.vhdx" | Out-GridView -PassThru -Title "Choose the parent disk"

$MyArray = 'NAT', 'DC1', 'DC2', 'DHCP1', 'DHCP2', 'IPAM', 'DFSR1', 'DFSR2', 'DFSS1', 'DFSS2'

#New-VMSwitch -Name Public -NetAdapterName Ethernet
#New-VMSwitch -Name Private -SwitchType Private

New-VMSwitch -Name vPrivate -SwitchType Private
$PublicInterface = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -ExpandProperty Name
New-VMSwitch -Name vPublic -NetAdapterName $PublicInterface

foreach ($Server in $MyArray) {
    New-VHD -Path "C:\Users\Public\Documents\Hyper-V\Virtual hard disks\$Server.vhdx" -ParentPath $ParentDisk
    New-VM -Name $Server -SwitchName vPrivate -VHDPath "C:\Users\Public\Documents\Hyper-V\Virtual hard disks\$Server.vhdx" -Generation 2 -Force
    Set-VMMemory -VMName $Server -DynamicMemoryEnabled $true
    Set-VM -VMName $Server -AutomaticCheckpointsEnabled $false
    Start-VM -VMName $Server
}

#--------------------------------------------------------------
Read-Host -Prompt "Press enter after all VM's are fully booted"
#--------------------------------------------------------------

$LocalUser = 'administrator'
$DomainUser = 'contoso\administrator'
$pwd = ConvertTo-SecureString 'Pa11word' -AsPlainText -Force
$LocalAuth = New-Object System.Management.Automation.PSCredential($LocalUser,$pwd)
$DomainAuth = New-Object System.Management.Automation.PSCredential($DomainUser,$pwd)

$MyArray = 'NAT', 'DC1', 'DC2', 'DHCP1', 'DHCP2', 'IPAM', 'DFSR1', 'DFSR2', 'DFSS1', 'DFSS2'

$count = 1

foreach ($Server in $MyArray) {
    Invoke-Command -VMName $Server -Credential $LocalAuth -ArgumentList $count -ScriptBlock {
        param($count)
        New-NetIPAddress -IPAddress "172.16.0.$count" -PrefixLength 16 -InterfaceAlias Ethernet -DefaultGateway 172.16.0.1
        Set-DnsClientServerAddress -ServerAddresses 172.16.0.2 -InterfaceAlias *
        #Start-Sleep 10
    }
    $count = $count + 1
}

Invoke-Command -VMName NAT -Credential $LocalAuth -ArgumentList $StationNumber -ScriptBlock {
    param($StationNumber)
    Install-WindowsFeature -Name routing -IncludeManagementTools -Restart
    Rename-Computer -NewName "$StationNumber-nat" -Restart
}

Invoke-Command -VMName DC1 -Credential $LocalAuth -ArgumentList $StationNumber -ScriptBlock {
    param($StationNumber)
    Set-DnsClientServerAddress -ServerAddresses 10.13.2.5,10.13.2.7 -InterfaceAlias *
    Install-WindowsFeature -Name ad-domain-services,npas -IncludeManagementTools -Restart
    Rename-Computer -NewName "$StationNumber-dc1" -Restart
}

Invoke-Command -VMName DC2 -Credential $LocalAuth -ArgumentList $StationNumber -ScriptBlock {
    param($StationNumber)    
    Install-WindowsFeature -Name ad-domain-services -IncludeManagementTools -Restart
    Rename-Computer -NewName "$StationNumber-dc2" -Restart
}

Invoke-Command -VMName DHCP1 -Credential $LocalAuth -ArgumentList $StationNumber -ScriptBlock {
    param($StationNumber)
    Install-WindowsFeature -Name dhcp -IncludeManagementTools -Restart
    Rename-Computer -NewName "$StationNumber-dhcp1" -Restart
}

Invoke-Command -VMName DHCP2 -Credential $LocalAuth -ArgumentList $StationNumber -ScriptBlock {
    param($StationNumber)
    Install-WindowsFeature -Name dhcp -IncludeManagementTools -Restart
    Rename-Computer -NewName "$StationNumber-dhcp2" -Restart
}

Invoke-Command -VMName IPAM -Credential $LocalAuth -ArgumentList $StationNumber -ScriptBlock {
    param($StationNumber)
    Rename-Computer -NewName "$StationNumber-ipam" -Restart
}

Invoke-Command -VMName NAT  -Credential $LocalAuth -ScriptBlock {
    Rename-NetAdapter -Name "Ethernet*" -NewName Private
}

Add-VMNetworkAdapter -VMName NAT -SwitchName vPublic

Invoke-Command -VMName NAT  -Credential $LocalAuth -ScriptBlock {
    Rename-NetAdapter -Name "Ethernet*" -NewName Public
}

#-----------------------------------------------------------
Read-Host -Prompt "Press enter after the DC is fully booted"
#-----------------------------------------------------------

Invoke-Command -VMName DC1 -Credential $LocalAuth -ArgumentList $pwd -ScriptBlock {
    param($pwd)
    Install-ADDSForest -DomainName contoso.com -SafeModeAdministratorPassword $pwd -Force
}

#-----------------------------------------------------------
Read-Host -Prompt "Press enter after the DC is fully booted"
#-----------------------------------------------------------

Invoke-Command -VMName DC1 -Credential $DomainAuth -ScriptBlock {
    Add-DnsServerPrimaryZone -NetworkID 172.16/16 -ReplicationScope Forest
    Register-DnsClient
}

$MyThirdArray = 'NAT', 'DC2', 'DHCP1', 'DHCP2', 'IPAM', 'DFSR1', 'DFSR2', 'DFSS1', 'DFSS2'

foreach ($Server in $MyThirdArray) {
    Invoke-Command -VMName $Server -Credential $LocalAuth -ArgumentList $DomainAuth,$Server -ScriptBlock {
        param($DomainAuth, $Server)        
        Add-Computer -DomainName contoso.com -Credential $DomainAuth -Restart
    }
}

Invoke-Command -VMName DC2 -Credential $DomainAuth -ScriptBlock {
    $pwd = ConvertTo-SecureString Pa11word -AsPlainText -Force
    Install-ADDSDomainController -DomainName contoso.com -SafeModeAdministratorPassword $pwd -Credential (Get-Credential contoso\administrator)    
}

Invoke-Command -VMName IPAM -Credential $DomainAuth -ScriptBlock {
    Install-WindowsFeature -Name ipam -IncludeManagementTools -Restart
}