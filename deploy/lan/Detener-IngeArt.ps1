$ErrorActionPreference = 'Stop'
$taskStateFile = Join-Path $PSScriptRoot 'logs\processes.json'
if (-not (Test-Path -LiteralPath $taskStateFile)) { Write-Output 'No hay procesos registrados.'; return }
$taskRoot = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\') + '\'
foreach ($taskRecord in (Get-Content -LiteralPath $taskStateFile -Raw | ConvertFrom-Json)) {
    $taskProcess = Get-Process -Id $taskRecord.id -ErrorAction SilentlyContinue
    if (-not $taskProcess) { continue }
    $taskExpectedStart = if ($taskRecord.started -is [DateTime]) { $taskRecord.started.ToUniversalTime() } else {
        [DateTimeOffset]::Parse([string]$taskRecord.started, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime
    }
    if (-not $taskProcess.Path.StartsWith($taskRoot,[StringComparison]::OrdinalIgnoreCase) -or
        $taskProcess.Path -ne $taskRecord.executable -or
        $taskProcess.StartTime.ToUniversalTime().Ticks -ne $taskExpectedStart.Ticks) {
        throw 'El PID ya no corresponde a esta entrega. No se detiene el proceso.'
    }
    $taskProcess | Stop-Process
}
Remove-Item -LiteralPath $taskStateFile
Write-Output 'Procesos de esta entrega detenidos.'
