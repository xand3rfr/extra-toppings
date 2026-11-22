$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$dir = Join-Path $env:LOCALAPPDATA "ExtraToppings\loader"
$zip = Join-Path $env:TEMP "extra-toppings.zip"
$tmp = Join-Path $env:TEMP "extra-toppings-unzip"

Write-Host "Downloading Extra Toppings..." -ForegroundColor Cyan
Invoke-WebRequest "https://github.com/xand3rfr/extra-toppings/archive/refs/heads/main.zip" -OutFile $zip -UseBasicParsing
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
Expand-Archive $zip $tmp -Force
if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
New-Item -ItemType Directory -Force (Split-Path $dir) | Out-Null
Move-Item (Get-ChildItem $tmp -Directory | Select-Object -First 1).FullName $dir
Remove-Item $zip, $tmp -Recurse -Force -ErrorAction SilentlyContinue

$run = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $dir "install.ps1"))
if ($env:EXTRA_TOPPINGS_UNINSTALL) { $run += "-Uninstall" }
Remove-Item Env:\EXTRA_TOPPINGS_UNINSTALL -ErrorAction SilentlyContinue
& powershell.exe @run
