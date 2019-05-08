@echo off

set noRestart=%1
IF NOT defined noRestart (
    set shouldRestart=1
) else (
    set shouldRestart=0
)

REM ***** Exit script if running in Emulator *****
if "%ComputeEmulatorRunning%"=="true" goto exit

REM ***** Setup .NET filenames and registry keys *****
set netfx="NDP472"

set "netfxinstallfile=NDP472-KB4054530-x86-x64-AllOS-ENU.exe"
set "regkeyPath=HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full"
set "regkey=Release"
set netfxregkey="0x70BF6"
goto install

:install
REM ***** Check if .NET is installed *****
echo Checking if .NET (%netfx%) is installed
set /A netfxregkeydecimal=%netfxregkey%
set foundkey=0
FOR /F "usebackq skip=2 tokens=1,2*" %%A in (`reg query "%regkeyPath%" /v %regkey% 2^>nul`) do @set /A foundkey=%%C
if %foundkey% GEQ %netfxregkeydecimal% goto installed


REM ***** Installing .NET *****
if shouldRestart==1 (
    echo Installing .NET with commandline: start /wait %netfxinstallfile% /q
    start /wait %netfxinstallfile% /q
) else (
    echo Installing .NET with commandline: start /wait %netfxinstallfile% /q /norestart
    start /wait %netfxinstallfile% /q /norestart
)
if %ERRORLEVEL%== 0 goto installed
    echo .NET installer exited with code %ERRORLEVEL%
    if %ERRORLEVEL%== 3010 goto restart
    if %ERRORLEVEL%== 1641 goto restart
    echo .NET (%netfx%) install failed with Error Code %ERRORLEVEL%

:restart
if shouldRestart==1 (
    echo Restarting to complete .NET (%netfx%) installation
    EXIT /B %ERRORLEVEL%
) else (
    EXIT /B 0
)

:installed
echo .NET (%netfx%) is installed

:end
echo .NET install completed

:exit
EXIT /B 0