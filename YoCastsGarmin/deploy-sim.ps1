# deploy-sim.ps1 — Build and deploy YoCasts to the CIQ simulator with settings
# Usage: .\deploy-sim.ps1
# The simulator will be started automatically if not already running.

$ErrorActionPreference = 'Stop'

$Device   = 'venu441mm'
$SDK      = 'C:\Users\jaert\AppData\Roaming\Garmin\ConnectIQ\Sdks\connectiq-sdk-win-9.1.0-2026-03-09-6a872a80b\bin'
$Key      = 'C:\Users\jaert\AppData\Roaming\Garmin\ConnectIQ\developer_key.der'
$JavaHome = 'C:\Program Files\Microsoft\jdk-25.0.2.10-hotspot'

$env:JAVA_HOME = $JavaHome
$env:PATH      = "$JavaHome\bin;$SDK;$env:PATH"

$Prg      = 'bin\YoCasts.prg'
$Settings = 'bin\YoCasts-settings.json'

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
& "$SDK\monkeyc.bat" -d $Device -f monkey.simulator.jungle -o $Prg -y $Key -l 3
if ($LASTEXITCODE -ne 0) {
    Write-Host "BUILD FAILED" -ForegroundColor Red
    exit 1
}
Write-Host "Build succeeded."

# --- Deploy ---
Write-Host "[2/2] Deploying to simulator with settings..."
if (-not (Test-Path $Settings)) {
    Write-Host "WARNING: $Settings not found — settings will not be available in the simulator." -ForegroundColor Yellow
    & "$SDK\monkeydo.bat" $Prg $Device
} else {
    Write-Host "Found settings file: $Settings"
    & "$SDK\monkeydo.bat" $Prg $Device /a $Settings "0:/GARMIN/APPS/YoCasts-settings.json"
}
if ($LASTEXITCODE -ne 0) {
    Write-Host "DEPLOY FAILED" -ForegroundColor Red
    exit 1
}
Write-Host "Deployed successfully with settings." -ForegroundColor Green
