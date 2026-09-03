$ErrorActionPreference = 'Stop'
$windowsRoot = Split-Path $PSScriptRoot -Parent
$output = Join-Path $windowsRoot 'dist/PhoneDock-Windows-x64'
dotnet publish (Join-Path $windowsRoot 'PhoneDock') -c Release -r win-x64 --self-contained true -o $output
if ($LASTEXITCODE -ne 0) { throw 'No se pudo compilar Phone Dock.' }
Copy-Item (Join-Path $windowsRoot 'README.md') $output -Force
Copy-Item (Join-Path $windowsRoot 'THIRD-PARTY-NOTICES.md') $output -Force
Copy-Item (Join-Path $windowsRoot 'licenses') $output -Recurse -Force
Copy-Item (Join-Path $windowsRoot 'PhoneDock/packages.lock.json') $output -Force
$zip = Join-Path $windowsRoot 'dist/PhoneDock-Windows-x64.zip'
Compress-Archive -Path $output -DestinationPath $zip -Force
Get-FileHash $zip -Algorithm SHA256
Write-Output "Listo: $zip"
