# deploy-sim.ps1 - Build and deploy YoCasts to the CIQ simulator
# Usage: .\deploy-sim.ps1
# The simulator will be started automatically if not already running.

$ErrorActionPreference = 'Stop'

$Device = 'venu441mm'
$sdkConfig = Join-Path $env:APPDATA 'Garmin\ConnectIQ\current-sdk.cfg'
if (Test-Path $sdkConfig) {
    $sdkRoot = (Get-Content $sdkConfig -Raw).Trim()
} else {
    $sdkRoot = Get-ChildItem `
        (Join-Path $env:APPDATA 'Garmin\ConnectIQ\Sdks') `
        -Directory |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}
$SDK = Join-Path $sdkRoot 'bin'
$Key = Join-Path $env:APPDATA 'Garmin\ConnectIQ\developer_key.der'

$Jungle  = Join-Path $PSScriptRoot 'monkey.simulator.jungle'
$Prg     = Join-Path $PSScriptRoot 'bin\YoCastsGarmin.prg'

# --- Auto-start simulator if not running ---
$simProcess = Get-Process -Name 'simulator' -ErrorAction SilentlyContinue
if (-not $simProcess) {
    $simExe = Join-Path $SDK 'simulator.exe'
    if (-not (Test-Path $simExe)) {
        Write-Host "ERROR: simulator.exe not found at $simExe" -ForegroundColor Red
        exit 1
    }
    Write-Host "[0] Starting CIQ simulator..."
    Start-Process -FilePath $simExe
    Write-Host "    Waiting 5 seconds for simulator to initialize..."
    Start-Sleep -Seconds 5
} else {
    Write-Host "[0] Simulator already running (PID $($simProcess.Id))."
}

# --- Build ---
Write-Host "[1/2] Building for simulator (device: $Device)..."
& "$SDK\monkeyc.bat" -d $Device -f $Jungle -o $Prg -y $Key -l 3
if ($LASTEXITCODE -ne 0) {
    Write-Host "BUILD FAILED" -ForegroundColor Red
    exit 1
}
Write-Host "Build succeeded."

# --- Deploy ---
Write-Host "[2/2] Deploying to simulator..."
Write-Host (
    "NOTE: monkeydo cannot populate App Settings Editor. " +
    "Use VS Code F5 from the YoCastsGarmin folder to edit settings."
) -ForegroundColor Yellow
& "$SDK\monkeydo.bat" $Prg $Device
if ($LASTEXITCODE -ne 0) {
    Write-Host "DEPLOY FAILED" -ForegroundColor Red
    exit 1
}
Write-Host "Deployed successfully with settings." -ForegroundColor Green
