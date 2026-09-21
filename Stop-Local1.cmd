@echo off
setlocal DisableDelayedExpansion
title Local 1 Stop
cd /d "%~dp0"

rem =============================================================================
rem  Local 1 stop — Windows CMD only
rem  Source of truth: Local1-Operations\Stop-Local1.cmd
rem  Operator entrypoint: C:\Allprojects\Stop-Local1.cmd
rem  Terminates app processes listening on Local 1 ports.
rem  Does NOT stop Docker / SQL.
rem  Governed config: Local1-Operations\runtime.manifest.json
rem =============================================================================

echo.
echo ================================================================
echo  Local 1 Stop
echo  Stopping: EVO API, PI API, Gateway, Sentinel Web, SAXIO Web
echo  Leaving Docker SQL running
echo ================================================================
echo.

call :kill_port 5000 "EVO Auth/API"
call :kill_port 5038 "Portfolio Intelligence API"
call :kill_port 8080 "Local Gateway"
call :kill_port 5173 "Sentinel Web"
call :kill_port 4201 "SAXIO Web"
call :kill_port 24678 "Vite HMR"

echo.
echo ================================================================
echo  Local 1 app processes stopped
echo  Docker SQL left untouched ^(port 14333^)
echo ================================================================
echo.
endlocal
exit /b 0

:kill_port
set "_PORT=%~1"
set "_NAME=%~2"

netstat -ano | findstr ":%_PORT% " | findstr "LISTENING" >NUL 2>&1
if errorlevel 1 (
  echo Skip: %_NAME% not listening on :%_PORT%
  exit /b 0
)

for /f "tokens=5" %%P in ('netstat -ano ^| findstr ":%_PORT% " ^| findstr "LISTENING"') do (
  echo Stopping %_NAME% on :%_PORT% ^(PID %%P^)
  taskkill /PID %%P /T /F >NUL 2>&1
  if errorlevel 1 (
    echo   WARN: could not terminate PID %%P for %_NAME%
  ) else (
    echo   OK: terminated %_NAME%
  )
)
exit /b 0
