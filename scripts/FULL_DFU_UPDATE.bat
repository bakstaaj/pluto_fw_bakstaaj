@echo off
setlocal EnableExtensions

set "ROOT=%~dp0"
set "DRYRUN=0"
if /I "%~1"=="/dry-run" set "DRYRUN=1"

set "FW=%ROOT%pluto.dfu"
set "BOOT=%ROOT%boot.dfu"
set "UBOOT_ENV=%ROOT%uboot-env.dfu"
set "DFU="

call :find_dfu
if not defined DFU (
  echo ERROR: dfu-util.exe was not found.
  echo.
  echo Expected one of:
  echo   %ROOT%dfu-util.exe
  echo   %ROOT%tools\dfu-util\dfu-util-0.11-binaries\win64\dfu-util.exe
  echo   %ROOT%..\tools\dfu-util\dfu-util-0.11-binaries\win64\dfu-util.exe
  echo   %ROOT%..\..\tools\dfu-util\dfu-util-0.11-binaries\win64\dfu-util.exe
  echo or dfu-util.exe on PATH.
  echo.
  pause
  exit /b 1
)

call :require_file "main firmware image" "%FW%" || exit /b 1
call :require_file "bootloader image" "%BOOT%" || exit /b 1
call :require_file "U-Boot environment image" "%UBOOT_ENV%" || exit /b 1

echo Pluto Plus Full DFU Firmware Loader
echo.
echo dfu-util:
echo   "%DFU%"
echo.
echo Images:
echo   firmware.dfu   "%FW%"
echo   boot.dfu       "%BOOT%"
echo   uboot-env.dfu  "%UBOOT_ENV%"
echo.

if "%DRYRUN%"=="1" (
  echo Dry run OK. Required files were found.
  exit /b 0
)

echo WARNING:
echo This rewrites the main firmware, bootloader, and U-Boot environment.
echo It will reset U-Boot environment settings such as custom network/RF envs.
echo Use this only when you intend to deploy the complete firmware package.
echo.
echo 1. Set the Pluto Plus USB reset jumper to USRT-MIO52.
echo 2. Hold the Pluto Plus DFU/BOOT button while plugging in or resetting.
echo 3. Keep holding for 5-10 seconds, until Windows sees the DFU device.
echo 4. Move the USB reset jumper to USRT-MIO46 before continuing.
echo 5. Leave the USB cable connected while this script flashes the package.
echo.
set /p CONFIRM=Type FULLDFU to continue: 
if /I not "%CONFIRM%"=="FULLDFU" (
  echo Cancelled.
  exit /b 2
)

echo.
echo Looking for Pluto DFU device...
"%DFU%" -l
if errorlevel 1 (
  echo.
  echo ERROR: dfu-util failed while listing devices.
  echo Make sure the Pluto is in forced DFU mode and try again.
  pause
  exit /b 1
)

call :flash "firmware.dfu" "%FW%" "main firmware" || exit /b 1
call :flash "boot.dfu" "%BOOT%" "bootloader" || exit /b 1
call :flash "uboot-env.dfu" "%UBOOT_ENV%" "U-Boot environment" || exit /b 1

echo.
echo Detaching from DFU so Pluto can boot...
"%DFU%" -d 0456:b673,0456:b674 -a firmware.dfu -e
if errorlevel 1 (
  echo.
  echo WARNING: Detach failed. Unplug and reconnect the Pluto after Windows settles.
) else (
  echo Detach command sent.
)

echo.
echo Full DFU update completed.
echo Wait 10-20 seconds for the PlutoSDR USB drive or network device to return.
echo.
pause
exit /b 0

:find_dfu
for %%P in ("%ROOT%dfu-util.exe" "%ROOT%tools\dfu-util\dfu-util-0.11-binaries\win64\dfu-util.exe" "%ROOT%..\tools\dfu-util\dfu-util-0.11-binaries\win64\dfu-util.exe" "%ROOT%..\..\tools\dfu-util\dfu-util-0.11-binaries\win64\dfu-util.exe") do (
  if not defined DFU if exist "%%~fP" set "DFU=%%~fP"
)
if not defined DFU (
  for %%P in (dfu-util.exe) do (
    if not "%%~$PATH:P"=="" set "DFU=%%~$PATH:P"
  )
)
exit /b 0

:require_file
if not exist "%~2" (
  echo ERROR: Missing %~1:
  echo   "%~2"
  echo.
  pause
  exit /b 1
)
exit /b 0

:flash
echo.
echo Flashing %~3 to %~1:
echo   "%~2"
"%DFU%" -v -d 0456:b673,0456:b674 -a %~1 -D "%~2"
if errorlevel 1 (
  echo.
  echo ERROR: Failed while flashing %~3.
  echo Make sure the Pluto is still in DFU mode and try again.
  pause
  exit /b 1
)
exit /b 0
