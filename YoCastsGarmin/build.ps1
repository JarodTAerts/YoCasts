param(
    [ValidateSet('Device', 'Simulator', 'All')]
    [string]$Target = 'All',
    [string]$Device = 'venu441mm',
    [string]$DeveloperKey = "$env:APPDATA\Garmin\ConnectIQ\developer_key.der"
)

$ErrorActionPreference = 'Stop'

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

if (-not $sdkRoot) {
    throw 'No Garmin Connect IQ SDK installation was found.'
}

$compiler = Join-Path $sdkRoot 'bin\monkeyc.bat'
if (-not (Test-Path $compiler)) {
    throw "Monkey C compiler not found at $compiler"
}
if (-not (Test-Path $DeveloperKey)) {
    throw "Developer key not found at $DeveloperKey"
}

$buildDir = Join-Path $PSScriptRoot 'build'
New-Item -ItemType Directory -Path $buildDir -Force | Out-Null

function Invoke-CiqBuild {
    param(
        [string]$Jungle,
        [string]$Output
    )

    & $compiler `
        -d $Device `
        -f $Jungle `
        -o (Join-Path $buildDir $Output) `
        -y $DeveloperKey `
        -l 3

    if ($LASTEXITCODE -ne 0) {
        throw "Connect IQ build failed for $Jungle"
    }
}

Push-Location $PSScriptRoot
try {
    if ($Target -in @('Device', 'All')) {
        Invoke-CiqBuild -Jungle 'monkey.jungle' -Output 'YoCastsDevice.prg'
    }
    if ($Target -in @('Simulator', 'All')) {
        Invoke-CiqBuild `
            -Jungle 'monkey.simulator.jungle' `
            -Output 'YoCastsSimulator.prg'
    }
} finally {
    Pop-Location
}

Write-Host "YoCasts $Target build completed in $buildDir" -ForegroundColor Green
