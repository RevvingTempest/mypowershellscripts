$LocalUser = 'administrator'
$DomainUser = 'contoso\administrator'
$pwd = ConvertTo-SecureString 'Pa11word' -AsPlainText -Force
$LocalAuth = New-Object System.Management.Automation.PSCredential($LocalUser,$pwd)
$DomainAuth = New-Object System.Management.Automation.PSCredential($DomainUser,$pwd)

Invoke-Command -VMName DFSR1 -Credential $DomainAuth -ScriptBlock {
    param($DomainAuth,$StationNumber)    
    Install-WindowsFeature -Name FS-DFS-Namespace,FS-DFS-Replication -IncludeManagementTools -Restart
    Rename-Computer -NewName "cs03-dfsr1" -Restart
}

Invoke-Command -VMName DFSR2 -Credential $DomainAuth -ScriptBlock {
    param($DomainAuth,$StationNumber)
    Install-WindowsFeature -Name FS-DFS-Namespace,FS-DFS-Replication -IncludeManagementTools -Restart
    Rename-Computer -NewName "cs03-dfsr2" -Restart
}

Invoke-Command -VMName DFSS1 -Credential $DomainAuth -ScriptBlock {
    param($DomainAuth,$StationNumber)
    Install-WindowsFeature -Name FS-DFS-Replication -IncludeManagementTools -Restart
    Rename-Computer -NewName "cs03-dfss1" -Restart
}

Invoke-Command -VMName DFSS2 -Credential $DomainAuth -ScriptBlock {
    param($DomainAuth,$StationNumber)
    Install-WindowsFeature -Name FS-DFS-Replication -IncludeManagementTools -Restart
    Rename-Computer -NewName "cs03-dfss2" -Restart
}