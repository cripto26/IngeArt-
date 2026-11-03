$ErrorActionPreference = 'Stop'
$taskCertificate = Join-Path $PSScriptRoot 'caddy-data\caddy\pki\authorities\local\root.crt'
if (-not (Test-Path -LiteralPath $taskCertificate)) { throw 'Inicia Caddy una vez para generar la autoridad local.' }
Import-Certificate -FilePath $taskCertificate -CertStoreLocation Cert:\CurrentUser\Root | Select-Object Subject,Thumbprint
Write-Output 'Certificado instalado para el usuario actual. En otros equipos importa solamente root.crt; nunca copies root.key.'
