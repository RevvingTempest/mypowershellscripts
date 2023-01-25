Start-Sleep -Seconds 3600
New-NetFirewallRule -DisplayName "Roblox Port Disable" -Direction Outbound -LocalPort 49152-65535 -Protocol UDP -Action Block