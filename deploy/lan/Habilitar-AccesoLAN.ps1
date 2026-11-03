#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'
$taskRule = 'IngeArt-Caddy-LAN'
if (Get-NetFirewallRule -Name $taskRule -ErrorAction SilentlyContinue) {
    throw 'Ya existe una regla con este nombre. Revisarla antes de reemplazarla.'
}
New-NetFirewallRule -Name $taskRule -DisplayName 'IngeArt Caddy LAN' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 80,443 -RemoteAddress LocalSubnet -Profile Private -Program (Join-Path $PSScriptRoot 'bin\caddy.exe') | Select-Object DisplayName,Enabled,Profile
