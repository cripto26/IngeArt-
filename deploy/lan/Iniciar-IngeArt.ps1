[CmdletBinding()]
param([switch]$SoloVerificar)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$taskRoot = [IO.Path]::GetFullPath($PSScriptRoot)
$taskPython = Join-Path $taskRoot 'backend\.tools\python-3.14.8\tools\python.exe'
$taskVenvPython = Join-Path $taskRoot 'backend\.venv\Scripts\python.exe'
$taskCaddy = Join-Path $taskRoot 'bin\caddy.exe'
$env:INGEAR_RELEASE_ROOT = $taskRoot.Replace('\','/')
$env:XDG_DATA_HOME = Join-Path $taskRoot 'caddy-data'
$env:XDG_CONFIG_HOME = Join-Path $taskRoot 'caddy-config'
New-Item -ItemType Directory -Path (Join-Path $taskRoot 'logs') -Force | Out-Null
& $taskPython (Join-Path $taskRoot 'verify_release.py')
if ($LASTEXITCODE -ne 0) { throw 'La entrega no conserva sus huellas de integridad.' }
Push-Location (Join-Path $taskRoot 'backend')
try {
    & $taskVenvPython scripts/verify_environment.py --runtime
    if ($LASTEXITCODE -ne 0) { throw 'El entorno no coincide con el lock.' }
    & $taskVenvPython -m app.db.migrations status
    if ($LASTEXITCODE -ne 0) { throw 'La base requiere preparacion. Este arranque no ejecuta migraciones.' }
    & $taskCaddy validate --config (Join-Path $taskRoot 'Caddyfile') --adapter caddyfile
    if ($LASTEXITCODE -ne 0) { throw 'Configuracion Caddy invalida.' }
} finally { Pop-Location }
if ($SoloVerificar) { return }
$taskPortCheck = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,8010)
try { $taskPortCheck.Start() } finally { $taskPortCheck.Stop() }
if (Test-Path -LiteralPath (Join-Path $taskRoot 'logs\processes.json')) {
    throw 'Hay un registro de ejecucion. Ejecuta Detener-IngeArt.ps1 antes de iniciar nuevamente.'
}
$taskStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$taskApi = $null
$taskProxy = $null
try {
    $taskApi = Start-Process -FilePath $taskPython -ArgumentList @(('"' + (Join-Path $taskRoot 'launch_api.py') + '"')) -WorkingDirectory $taskRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $taskRoot "logs\api-$taskStamp.out.log") -RedirectStandardError (Join-Path $taskRoot "logs\api-$taskStamp.err.log")
    $taskHealthy = $false
    for ($taskAttempt=0; $taskAttempt -lt 40; $taskAttempt++) {
        Start-Sleep -Milliseconds 500
        $taskApi.Refresh()
        if ($taskApi.HasExited) { throw 'La API se detuvo; revisa su log privado.' }
        try {
            $taskHealth = Invoke-RestMethod -Uri 'http://127.0.0.1:8010/health/ready' -TimeoutSec 2
            if ($taskHealth) { $taskHealthy=$true; break }
        } catch { }
    }
    if (-not $taskHealthy) { throw 'La API no alcanzo disponibilidad.' }
    $taskProxy = Start-Process -FilePath $taskCaddy -ArgumentList @('run','--config',('"' + (Join-Path $taskRoot 'Caddyfile') + '"'),'--adapter','caddyfile') -WorkingDirectory $taskRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $taskRoot "logs\caddy-$taskStamp.out.log") -RedirectStandardError (Join-Path $taskRoot "logs\caddy-$taskStamp.err.log")
    Start-Sleep -Seconds 2
    $taskProxy.Refresh()
    if ($taskProxy.HasExited) { throw 'Caddy se detuvo; verifica puertos 80/443 y el log.' }
    @($taskApi,$taskProxy) | ForEach-Object { @{ id=$_.Id; started=$_.StartTime.ToUniversalTime().ToString('O'); executable=$_.Path } } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $taskRoot 'logs\processes.json') -Encoding utf8
    Write-Output 'IngeArt disponible en https://192.168.1.152 y https://localhost. Instala el certificado local en cada equipo cliente.'
} catch {
    foreach ($taskProcess in @($taskProxy,$taskApi)) {
        if ($null -ne $taskProcess -and -not $taskProcess.HasExited) { $taskProcess | Stop-Process }
    }
    throw
}
