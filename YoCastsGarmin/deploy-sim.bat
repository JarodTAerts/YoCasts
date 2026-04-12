@echo off
REM deploy-sim.bat — Build and deploy YoCasts to the CIQ simulator with settings
REM
REM Usage: deploy-sim.bat [device] [key_path]
REM   device   — Target device ID (default: venu441mm)
REM   key_path — Path to developer key (default: developer_key)
REM
REM Prerequisites: monkeyc and monkeydo must be on PATH (add SDK bin/ to PATH),
REM                and the CIQ simulator must be running.
setlocal

SET DEVICE=%~1
IF "%DEVICE%"=="" SET DEVICE=venu441mm

SET KEY=%~2
IF "%KEY%"=="" SET KEY=developer_key

SET PRG=bin\YoCasts.prg
SET SETTINGS=bin\YoCasts-settings.json

echo [1/2] Building for simulator (device: %DEVICE%)...
monkeyc -d %DEVICE% -f monkey.simulator.jungle -o %PRG% -y %KEY% -l 3
IF ERRORLEVEL 1 (
    echo BUILD FAILED
    exit /B 1
)
echo Build succeeded.

echo [2/2] Deploying to simulator...
IF NOT EXIST %SETTINGS% (
    echo WARNING: %SETTINGS% not found — settings will not be available in the simulator.
    monkeydo %PRG% %DEVICE%
) ELSE (
    monkeydo %PRG% %DEVICE% /a %SETTINGS% 0:/GARMIN/APPS/YoCasts-settings.json
)
IF ERRORLEVEL 1 (
    echo DEPLOY FAILED — is the simulator running?
    exit /B 1
)
echo Deployed successfully.
endlocal
