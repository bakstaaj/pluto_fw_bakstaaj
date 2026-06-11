@echo off
setlocal

set "ROOT=%~dp0"
set "REPO=%ROOT%..\.."
set "DFU=%REPO%\tools\dfu-util\dfu-util-0.11-binaries\win64\dfu-util.exe"
set "FW=%ROOT%pluto.dfu"

echo Pluto Plus DFU Recovery
echo.
echo This flashes the last known-good SD-card firmware image to firmware.dfu.
echo It does not rewrite boot.dfu or uboot-env.dfu.
echo.

if not exist "%DFU%" (
  echo ERROR: dfu-util was not found:
  echo   "%DFU%"
  echo.
  pause
  exit /b 1
)

if not exist "%FW%" (
  echo ERROR: Recovery firmware was not found:
  echo   "%FW%"
  echo.
  pause
  exit /b 1
)

echo 1. Unplug Pluto USB.
echo 2. Hold the Pluto Plus DFU/BOOT button.
echo 3. Plug USB back in while holding the button.
echo 4. Keep holding for 5-10 seconds, then release.
echo.
pause

echo.
echo Looking for Pluto DFU device...
"%DFU%" -l
if errorlevel 1 (
  echo.
  echo ERROR: dfu-util failed while listing devices.
  pause
  exit /b 1
)

echo.
echo Flashing known-good firmware:
echo   "%FW%"
echo.
"%DFU%" -v -d 0456:b673,0456:b674 -a firmware.dfu -D "%FW%"
if errorlevel 1 (
  echo.
  echo ERROR: Firmware flash failed.
  echo Make sure the Pluto is in forced DFU mode and try again.
  pause
  exit /b 1
)

echo.
echo Detaching from DFU so Pluto can boot...
"%DFU%" -d 0456:b673,0456:b674 -a firmware.dfu -e

echo.
echo Recovery flash completed.
echo Wait 10-20 seconds for the PlutoSDR drive to return.
echo.
pause
exit /b 0
