@echo off
REM deploy-sim.bat — Build and deploy YoCasts to the CIQ simulator with settings
REM Usage: deploy-sim.bat
REM Prerequisites: The CIQ simulator must be running.
setlocal

SET DEVICE=venu441mm
SET SDK=C:\Users\jaert\AppData\Roaming\Garmin\ConnectIQ\Sdks\connectiq-sdk-win-9.1.0-2026-03-09-6a872a80b\bin
SET KEY=C:\Users\jaert\AppData\Roaming\Garmin\ConnectIQ\developer_key.der
SET JAVA_HOME=C:\Program Files\Microsoft\jdk-25.0.2.10-hotspot
SET PATH=%JAVA_HOME%\bin;%SDK%;%PATH%

SET PRG=bin\YoCasts.prg
SET SETTINGS=bin\YoCasts-settings.json

echo [1/2] Building for simulator (device: %DEVICE%)...
call "%SDK%\monkeyc.bat" -d %DEVICE% -f monkey.simulator.jungle -o %PRG% -y "%KEY%" -l 3
IF ERRORLEVEL 1 (
    echo BUILD FAILED
    exit /B 1
)
echo Build succeeded.

echo [2/2] Deploying to simulator with settings...
IF NOT EXIST %SETTINGS% (
    echo WARNING: %SETTINGS% not found — settings will not be available in the simulator.
    call "%SDK%\monkeydo.bat" %PRG% %DEVICE%
) ELSE (
    echo Found settings file: %SETTINGS%
    call "%SDK%\monkeydo.bat" %PRG% %DEVICE% /a %SETTINGS% 0:/GARMIN/APPS/YoCasts-settings.json
)
IF ERRORLEVEL 1 (
    echo DEPLOY FAILED — is the simulator running?
    exit /B 1
)
echo Deployed successfully with settings.
endlocal
