@echo off
setlocal DisableDelayedExpansion
title Local 1 Launcher
cd /d "%~dp0"

rem =============================================================================
rem  Local 1 startup ? Windows CMD only
rem  Governed config: Local1-Operations\runtime.manifest.json
rem  Secrets:        SAXIO-Sentinel\runtime\local1\.env.local
rem =============================================================================

set "SCRIPT_ROOT=%~dp0"
if "%SCRIPT_ROOT:~-1%"=="\" set "SCRIPT_ROOT=%SCRIPT_ROOT:~0,-1%"

if not "%LOCAL1_PORTFOLIO_ROOT%"=="" (
  set "ALLPROJECTS=%LOCAL1_PORTFOLIO_ROOT%"
) else (
  for %%I in ("%SCRIPT_ROOT%\..") do set "ALLPROJECTS=%%~fI"
)
if "%ALLPROJECTS:~-1%"=="\" set "ALLPROJECTS=%ALLPROJECTS:~0,-1%"

set "MANIFEST=%SCRIPT_ROOT%\runtime.manifest.json"
set "ENV_LOCAL=%ALLPROJECTS%\SAXIO-Sentinel\runtime\local1\.env.local"
set "REPO_SENTINEL=%ALLPROJECTS%\SAXIO-Sentinel"
set "REPO_EVO=%ALLPROJECTS%\Evo-Services\Evo-Service"
set "REPO_GATEWAY=%ALLPROJECTS%\local-gateway"
set "REPO_SENTINEL_WEB_DEV=%ALLPROJECTS%\Sentinel Web"
set "REPO_SENTINEL_WEB_RUNTIME=%ALLPROJECTS%\Local1\Sentinel-Web-Runtime"
set "SENTINEL_WEB_RUNTIME_BRANCH=runtime/local1-sentinel-web"
set "SENTINEL_WEB_UPSTREAM=origin/main"
set "REPO_SAXIO_WEB=%ALLPROJECTS%\Evo-Web\Evo-Web"
set "DB_AUTHORITY=%ALLPROJECTS%\runtime\local1\startup-db-authority.ps1"
set "SQL_BOOTSTRAP=%SCRIPT_ROOT%\runtime\local1\Start-Local1Sql.ps1"
set "SENTINEL_LOGIC_BOOTSTRAP=%SCRIPT_ROOT%\runtime\local1\Ensure-Local1SentinelLogic.ps1"

set "WAIT_SECONDS=240"
set "FAIL_REASON="
set "FAIL_FIX="
set "ALLOW_EXTERNAL_DB=0"
set "VALIDATE_ONLY=0"

:parse_args
if "%~1"=="" goto args_done
if /I "%~1"=="-AllowExternalDb" (
  set "ALLOW_EXTERNAL_DB=1"
  shift
  goto parse_args
)
if /I "%~1"=="-ValidateOnly" (
  set "VALIDATE_ONLY=1"
  shift
  goto parse_args
)
echo ERROR
echo Unsupported Start-Local1.cmd argument: %~1
echo Supported overrides: -AllowExternalDb, -ValidateOnly
endlocal
exit /b 2

:args_done

if not exist "%MANIFEST%" (
  call :fail "Governed runtime manifest is missing." "Create or restore %MANIFEST%"
  goto :eof
)

rem ===========================================================================
rem  Preflight: required tooling and Sentinel Web dependency state
rem ===========================================================================
node.exe --version >NUL 2>&1
if errorlevel 1 (
  call :fail "Node.js is unavailable on PATH." "Install the repository-supported Node.js version, open a new terminal, and retry Start-Local1.cmd."
  goto :eof
)

call npm.cmd --version >NUL 2>&1
if errorlevel 1 (
  call :fail "npm is unavailable on PATH." "Install npm with Node.js, open a new terminal, and retry Start-Local1.cmd."
  goto :eof
)

if not exist "%REPO_SENTINEL_WEB_DEV%\" (
  call :fail "Sentinel Web repository is missing." "Confirm Sentinel Web is cloned at %REPO_SENTINEL_WEB_DEV%"
  goto :eof
)

if not exist "%REPO_SENTINEL_WEB_DEV%\package.json" (
  call :fail "Sentinel Web package.json is missing." "Create or restore %REPO_SENTINEL_WEB_DEV%\package.json"
  goto :eof
)

if not exist "%REPO_SENTINEL_WEB_DEV%\package-lock.json" (
  call :fail "Sentinel Web package-lock.json is missing." "Restore the repository lockfile before starting Local 1."
  goto :eof
)

call :ensure_sentinel_web_runtime
if errorlevel 1 goto :eof

if not exist "%REPO_SENTINEL_WEB_RUNTIME%\package.json" (
  call :fail_sentinel_web_runtime "Runtime checkout is missing package.json." "Validate runtime worktree provisioning for %REPO_SENTINEL_WEB_RUNTIME%."
  goto :eof
)

if not exist "%REPO_SENTINEL_WEB_RUNTIME%\package-lock.json" (
  call :fail_sentinel_web_runtime "Runtime checkout is missing package-lock.json." "Restore package-lock.json under %REPO_SENTINEL_WEB_RUNTIME% from origin/main and retry."
  goto :eof
)

echo.
echo Sentinel Web Runtime:
echo   Development Path: %REPO_SENTINEL_WEB_DEV%
echo   Development Branch: %_SENTINEL_WEB_DEV_BRANCH%
echo   Runtime Path: %REPO_SENTINEL_WEB_RUNTIME%
echo   Runtime Branch: %_SENTINEL_WEB_RUNTIME_BRANCH%
echo   Upstream: %SENTINEL_WEB_UPSTREAM%
echo   Local SHA: %_SENTINEL_WEB_RUNTIME_HEAD%
echo   Remote SHA: %_SENTINEL_WEB_REMOTE_HEAD%
echo   Ahead/Behind: %_SENTINEL_WEB_BEHIND% %_SENTINEL_WEB_AHEAD%
echo   Working Tree Dirty: %_SENTINEL_WEB_RUNTIME_DIRTY%
echo   Result: PASS

if not exist "%SENTINEL_LOGIC_BOOTSTRAP%" (
  call :fail "Sentinel-Logic runtime bootstrap is missing." "Create or restore %SENTINEL_LOGIC_BOOTSTRAP%"
  goto :eof
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SENTINEL_LOGIC_BOOTSTRAP%" -PortfolioRoot "%ALLPROJECTS%" -Mode ProvisionRuntime
if errorlevel 1 (
  endlocal
  exit /b 1
)

if not exist "%SQL_BOOTSTRAP%" (
  call :fail "Local 1 SQL secure bootstrap is missing." "Create or restore %SQL_BOOTSTRAP%"
  goto :eof
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SQL_BOOTSTRAP%" -SentinelRepositoryPath "%REPO_SENTINEL%" -ValidateOnly
if errorlevel 1 (
  endlocal
  exit /b 1
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SENTINEL_LOGIC_BOOTSTRAP%" -PortfolioRoot "%ALLPROJECTS%" -Mode ValidateDependencies
if errorlevel 1 (
  endlocal
  exit /b 1
)

if not exist "%REPO_SENTINEL_WEB_RUNTIME%\node_modules\.bin\vite.cmd" (
  call :fail "Vite remains unavailable after governed Sentinel Web dependency validation." "Review package.json and package-lock.json in %REPO_SENTINEL_WEB_RUNTIME%, then retry Start-Local1.cmd."
  goto :eof
)

if "%VALIDATE_ONLY%"=="1" (
  echo.
  echo Validation-only mode complete.
  endlocal
  exit /b 0
)

echo.
echo ================================================================
echo  Local 1 Startup
echo  Manifest: %MANIFEST%
echo  External DB authorized: %ALLOW_EXTERNAL_DB%
echo ================================================================
echo.

if not exist "%ENV_LOCAL%" (
  call :fail "Local 1 env file is missing." "Create SAXIO-Sentinel\runtime\local1\.env.local from the approved Local 1 secret set. See Enterprise Playbook Evo\governance\runtime\Local1-Developer-Onboarding.md"
  goto :eof
)

if not exist "%DB_AUTHORITY%" (
  call :fail "Startup database authority is missing." "Create or restore %DB_AUTHORITY%"
  goto :eof
)

set "Sentinel__PiResourceKeyMapping__Enabled=true"
set "VITE_DEPLOYMENT_PORTFOLIO_ID=1"
set "VITE_PI_OPERATIONAL_TIMEZONE=America/New_York"
set "Crime__Analytics__OperationalTimezone=America/New_York"
set "VITE_SENTINEL_WEB_BASE_PATH=/sentinel/"
set "VITE_PI_API_PROXY_TARGET=http://127.0.0.1:5038"
set "VITE_CRIME_GOVERNED_DEVELOPMENT_PRINCIPAL_ID=ngower"
set "VITE_PI_ENABLE_SAXIO_AUTHORIZED_WORKFLOWS=true"
set "NODE_OPTIONS=--openssl-legacy-provider --max-old-space-size=8192"
if "%SAXIO_SENTINEL_DOCKER_PORT%"=="" set "SAXIO_SENTINEL_DOCKER_PORT=14333"

rem ===========================================================================
rem  1) Docker SQL
rem ===========================================================================
echo.
echo [1/6] Docker SQL Server
if not exist "%REPO_SENTINEL%\docker-compose.local.yml" (
  call :fail "docker-compose.local.yml not found under SAXIO-Sentinel." "Confirm SAXIO-Sentinel is cloned at %REPO_SENTINEL%"
  goto :eof
)

pushd "%REPO_SENTINEL%"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SQL_BOOTSTRAP%" -SentinelRepositoryPath "%REPO_SENTINEL%"
if errorlevel 1 (
  popd
  endlocal
  exit /b 1
)
popd

call :wait_port 14333 "Docker SQL Server"
if errorlevel 1 goto :eof

echo.
echo [db] Validating governed PI database authority...
if "%ALLOW_EXTERNAL_DB%"=="1" (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%DB_AUTHORITY%" -AllowExternalDb
) else (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%DB_AUTHORITY%"
)
if errorlevel 1 (
  call :fail "PI database authority validation failed." "Correct the reported Local 1 database configuration and retry."
  goto :eof
)

rem ===========================================================================
rem  2) EVO Auth/API
rem ===========================================================================
echo.
echo [2/6] EVO Auth/API
if not exist "%REPO_EVO%\Evo.Service.Host.API\Evo.Service.Host.API.csproj" (
  call :fail "EVO API project not found." "Confirm Evo-Service is cloned at %REPO_EVO%"
  goto :eof
)

call :is_http_ready "http://localhost:5000"
if not errorlevel 1 (
  echo REUSED: EVO Auth/API is already healthy on port 5000.
  goto evo_auth_api_ready
)

start "Local1 - EVO Auth/API" /D "%REPO_EVO%" cmd /k "set Sentinel__PiResourceKeyMapping__Enabled=true && echo Starting EVO Auth/API on :5000 && dotnet run --project Evo.Service.Host.API --urls http://localhost:5000"

call :wait_http "http://localhost:5000" "EVO Auth/API"
if errorlevel 1 goto :eof
:evo_auth_api_ready

rem ===========================================================================
rem  3) Portfolio Intelligence API
rem ===========================================================================
echo.
echo [3/6] Portfolio Intelligence API
if not exist "%REPO_SENTINEL%\services\portfolio-intelligence-api\Saxio.Sentinel.PortfolioIntelligence.Api.csproj" (
  call :fail "PI API project not found." "Confirm SAXIO-Sentinel services\\portfolio-intelligence-api exists."
  goto :eof
)

call :is_http_status_ready "http://127.0.0.1:5038/api/health/db" "200"
if not errorlevel 1 (
  echo REUSED: Portfolio Intelligence API is already healthy on port 5038.
  goto pi_api_ready
)

rem Launch PI via the same validated database authority used by preflight.
if "%ALLOW_EXTERNAL_DB%"=="1" (
  start "Local1 - PI API" cmd /c call "%ALLPROJECTS%\runtime\local1\launch-pi-api.cmd" -AllowExternalDb
) else (
  start "Local1 - PI API" cmd /c call "%ALLPROJECTS%\runtime\local1\launch-pi-api.cmd"
)


call :wait_http_status "http://127.0.0.1:5038/api/health/db" "200" "Portfolio Intelligence API /api/health/db"
if errorlevel 1 goto :eof
:pi_api_ready

rem ===========================================================================
rem  4) Local Gateway
rem ===========================================================================
echo.
echo [4/6] Local Gateway
if not exist "%REPO_GATEWAY%\package.json" (
  call :fail "local-gateway not found." "Confirm local-gateway is cloned at %REPO_GATEWAY%"
  goto :eof
)

call :is_http_ready "http://localhost:8080"
if not errorlevel 1 (
  echo REUSED: Local Gateway is already healthy on port 8080.
  goto local_gateway_ready
)

start "Local1 - Gateway" /D "%REPO_GATEWAY%" cmd /k "echo Starting Local Gateway on :8080 && call npm.cmd start"

call :wait_http "http://localhost:8080" "Local Gateway"
if errorlevel 1 goto :eof
:local_gateway_ready

rem ===========================================================================
rem  5) Sentinel Web
rem ===========================================================================
echo.
echo [5/6] Sentinel Web
if not exist "%REPO_SENTINEL_WEB_RUNTIME%\package.json" (
  call :fail "Sentinel Web runtime checkout is missing." "Confirm Sentinel Web runtime worktree exists at %REPO_SENTINEL_WEB_RUNTIME%"
  goto :eof
)

call :is_http_ready "http://localhost:5173"
if not errorlevel 1 (
  echo REUSED: Sentinel Web is already healthy on port 5173.
  goto sentinel_web_ready
)

call :require_free_port 5173 "Sentinel Web"
if errorlevel 1 goto :eof

start "Local1 - Sentinel Web" /D "%REPO_SENTINEL_WEB_RUNTIME%" cmd /k "set VITE_SENTINEL_WEB_BASE_PATH=/sentinel/ && set VITE_PI_API_PROXY_TARGET=http://127.0.0.1:5038 && echo Starting Sentinel Web on :5173 from %REPO_SENTINEL_WEB_RUNTIME% && call npm.cmd run dev -- --port 5173 --strictPort"

call :wait_http "http://localhost:5173" "Sentinel Web"
if errorlevel 1 goto :eof
:sentinel_web_ready

rem ===========================================================================
rem  6) SAXIO Web
rem ===========================================================================
echo.
echo [6/6] SAXIO Web
if not exist "%REPO_SAXIO_WEB%\package.json" (
  call :fail "SAXIO Web / Evo-Web not found." "Confirm Evo-Web is cloned at %REPO_SAXIO_WEB%"
  goto :eof
)

call :is_http_ready "http://localhost:4201"
if not errorlevel 1 (
  echo REUSED: SAXIO Web is already healthy on port 4201.
  goto saxio_web_ready
)

start "Local1 - SAXIO Web" /D "%REPO_SAXIO_WEB%" cmd /k "set NODE_OPTIONS=--openssl-legacy-provider --max-old-space-size=8192 && echo Starting SAXIO Web on :4201 && call npm.cmd run start:local"

call :wait_http "http://localhost:4201" "SAXIO Web"
if errorlevel 1 goto :eof
:saxio_web_ready

rem ===========================================================================
rem  Final verification
rem ===========================================================================
echo.
echo ================================================================
echo  Final health verification
echo ================================================================
call :verify_all
if errorlevel 1 goto :eof

echo.
echo ================================================================
echo  Local 1 is READY
echo ================================================================
echo   EVO Auth/API     http://localhost:5000
echo   PI API           http://127.0.0.1:5038
echo   Local Gateway    http://localhost:8080
echo   Sentinel Web     http://localhost:5173  ^(via gateway: /sentinel^)
echo   SAXIO Web        http://localhost:4201  ^(via gateway: /app^)
echo.
echo   Open: http://localhost:8080/app
echo   Stop: %ALLPROJECTS%\Stop-Local1.cmd
echo ================================================================
echo.
endlocal
exit /b 0

rem =============================================================================
rem  Helpers
rem =============================================================================

:fail
echo.
echo FAILED
echo Reason: %~1
echo Suggested Fix: %~2
echo.
endlocal
exit /b 1

:fail_sentinel_web_runtime
echo.
echo FAILED
echo Reason: %~1
echo Sentinel Web Runtime Path: %REPO_SENTINEL_WEB_RUNTIME%
echo Sentinel Web Development Path: %REPO_SENTINEL_WEB_DEV%
echo Expected Runtime Branch: %SENTINEL_WEB_RUNTIME_BRANCH%
echo Observed Runtime Branch: %_SENTINEL_WEB_RUNTIME_BRANCH%
echo Upstream Authority: %SENTINEL_WEB_UPSTREAM%
echo Local SHA: %_SENTINEL_WEB_RUNTIME_HEAD%
echo Remote SHA: %_SENTINEL_WEB_REMOTE_HEAD%
echo Ahead/Behind: %_SENTINEL_WEB_BEHIND% %_SENTINEL_WEB_AHEAD%
echo Working Tree Dirty: %_SENTINEL_WEB_RUNTIME_DIRTY%
echo Development Branch: %_SENTINEL_WEB_DEV_BRANCH%
echo Exact Remediation:
echo   1. Run: git -C "%REPO_SENTINEL_WEB_DEV%" worktree list --porcelain
echo   2. Run: git -C "%REPO_SENTINEL_WEB_RUNTIME%" status --short --branch
echo   3. Preserve runtime-only commits before any reconciliation; do not reset or force-update automatically.
echo   4. Reconcile runtime branch under an authorized work unit using fast-forward-only policy.
echo   5. Re-run C:\Allprojects\Start-Local1.cmd. Do not modify the WU-001B evidence worktree.
echo Suggested Fix: %~2
echo.
endlocal
exit /b 1

:ensure_sentinel_web_runtime
set "_SENTINEL_WEB_RUNTIME_HEAD="
set "_SENTINEL_WEB_RUNTIME_BRANCH="
set "_SENTINEL_WEB_REMOTE_HEAD="
set "_SENTINEL_WEB_BEHIND=0"
set "_SENTINEL_WEB_AHEAD=0"
set "_SENTINEL_WEB_RUNTIME_DIRTY=NO"
set "_SENTINEL_WEB_DEV_BRANCH="
set "_SENTINEL_WEB_DEV_HEAD="
set "_SENTINEL_WEB_RUNTIME_CREATED=NO"
set "_SENTINEL_WEB_RUNTIME_REUSED=NO"
set "_RUNTIME_PATH_EXISTS=NO"
if exist "%REPO_SENTINEL_WEB_RUNTIME%\" set "_RUNTIME_PATH_EXISTS=YES"

for /f "delims=" %%B in ('git -C "%REPO_SENTINEL_WEB_DEV%" branch --show-current 2^>NUL') do set "_SENTINEL_WEB_DEV_BRANCH=%%B"
for /f "delims=" %%H in ('git -C "%REPO_SENTINEL_WEB_DEV%" rev-parse HEAD 2^>NUL') do set "_SENTINEL_WEB_DEV_HEAD=%%H"
if "%_SENTINEL_WEB_DEV_BRANCH%"=="" (
  call :fail_sentinel_web_runtime "Sentinel Web development checkout is not a valid Git repository." "Repair or re-clone %REPO_SENTINEL_WEB_DEV% and retry."
  exit /b 1
)

git -C "%REPO_SENTINEL_WEB_DEV%" fetch origin --prune >NUL 2>&1
if errorlevel 1 (
  call :fail_sentinel_web_runtime "Failed to fetch origin for Sentinel Web development checkout." "Verify remote 'origin' and network access, then retry."
  exit /b 1
)

if "%_RUNTIME_PATH_EXISTS%"=="NO" (
  set "_RUNTIME_LISTED=NO"
  for /f "tokens=1,* delims= " %%A in ('git -C "%REPO_SENTINEL_WEB_DEV%" worktree list --porcelain 2^>NUL') do (
    if /I "%%A"=="worktree" if /I "%%B"=="%REPO_SENTINEL_WEB_RUNTIME%" set "_RUNTIME_LISTED=YES"
  )
)

if "%_RUNTIME_PATH_EXISTS%"=="NO" if "%_RUNTIME_LISTED%"=="YES" (
  git -C "%REPO_SENTINEL_WEB_DEV%" worktree prune >NUL 2>&1
  set "_RUNTIME_LISTED=NO"
  for /f "tokens=1,* delims= " %%A in ('git -C "%REPO_SENTINEL_WEB_DEV%" worktree list --porcelain 2^>NUL') do (
    if /I "%%A"=="worktree" if /I "%%B"=="%REPO_SENTINEL_WEB_RUNTIME%" set "_RUNTIME_LISTED=YES"
  )
  if "%_RUNTIME_LISTED%"=="YES" (
    call :fail_sentinel_web_runtime "Runtime worktree metadata is stale and still points to a missing path after prune." "Inspect linked worktree metadata in %REPO_SENTINEL_WEB_DEV% and resolve manually without force deletion."
    exit /b 1
  )
)

if "%_RUNTIME_PATH_EXISTS%"=="NO" (
  if not exist "%ALLPROJECTS%\Local1\" md "%ALLPROJECTS%\Local1" >NUL 2>&1

  set "_RUNTIME_BRANCH_LOCAL=NO"
  set "_RUNTIME_BRANCH_REMOTE=NO"
  git -C "%REPO_SENTINEL_WEB_DEV%" show-ref --verify --quiet "refs/heads/%SENTINEL_WEB_RUNTIME_BRANCH%"
  if not errorlevel 1 set "_RUNTIME_BRANCH_LOCAL=YES"
  git -C "%REPO_SENTINEL_WEB_DEV%" show-ref --verify --quiet "refs/remotes/origin/%SENTINEL_WEB_RUNTIME_BRANCH%"
  if not errorlevel 1 set "_RUNTIME_BRANCH_REMOTE=YES"

  if "%_RUNTIME_BRANCH_LOCAL%"=="YES" (
    git -C "%REPO_SENTINEL_WEB_DEV%" worktree add "%REPO_SENTINEL_WEB_RUNTIME%" "%SENTINEL_WEB_RUNTIME_BRANCH%" >NUL 2>&1
  ) else if "%_RUNTIME_BRANCH_REMOTE%"=="YES" (
    git -C "%REPO_SENTINEL_WEB_DEV%" worktree add -b "%SENTINEL_WEB_RUNTIME_BRANCH%" "%REPO_SENTINEL_WEB_RUNTIME%" "origin/%SENTINEL_WEB_RUNTIME_BRANCH%" >NUL 2>&1
  ) else (
    git -C "%REPO_SENTINEL_WEB_DEV%" worktree add -b "%SENTINEL_WEB_RUNTIME_BRANCH%" "%REPO_SENTINEL_WEB_RUNTIME%" "%SENTINEL_WEB_UPSTREAM%" >NUL 2>&1
  )
  if errorlevel 1 (
    call :fail_sentinel_web_runtime "Failed to create Sentinel Web runtime worktree." "Ensure the runtime branch is not checked out elsewhere and that %REPO_SENTINEL_WEB_RUNTIME% is empty, then retry."
    exit /b 1
  )
  set "_SENTINEL_WEB_RUNTIME_CREATED=YES"
) else (
  set "_SENTINEL_WEB_RUNTIME_REUSED=YES"
)

for /f "delims=" %%G in ('git -C "%REPO_SENTINEL_WEB_RUNTIME%" rev-parse --git-common-dir 2^>NUL') do set "_RUNTIME_COMMON_DIR=%%G"
if "%_RUNTIME_COMMON_DIR%"=="" (
  call :fail_sentinel_web_runtime "Runtime path is not a valid Git worktree." "Repair runtime worktree registration from %REPO_SENTINEL_WEB_DEV% and retry."
  exit /b 1
)

echo %_RUNTIME_COMMON_DIR% | findstr /I /C:"Sentinel Web/.git" /C:"Sentinel Web\.git" >NUL
if errorlevel 1 (
  call :fail_sentinel_web_runtime "Runtime path belongs to a different Git repository." "Recreate %REPO_SENTINEL_WEB_RUNTIME% as a linked worktree from %REPO_SENTINEL_WEB_DEV%."
  exit /b 1
)

for /f "delims=" %%B in ('git -C "%REPO_SENTINEL_WEB_RUNTIME%" branch --show-current 2^>NUL') do set "_SENTINEL_WEB_RUNTIME_BRANCH=%%B"
set "_SENTINEL_WEB_RUNTIME_DIRTY=NO"
for /f "delims=" %%S in ('git -C "%REPO_SENTINEL_WEB_RUNTIME%" status --porcelain 2^>NUL') do set "_SENTINEL_WEB_RUNTIME_DIRTY=YES"

if not "%_SENTINEL_WEB_RUNTIME_BRANCH%"=="%SENTINEL_WEB_RUNTIME_BRANCH%" (
  if "%_SENTINEL_WEB_RUNTIME_DIRTY%"=="YES" (
    call :fail_sentinel_web_runtime "Runtime worktree is on the wrong branch and has local changes." "Preserve changes, clean runtime worktree, then switch to %SENTINEL_WEB_RUNTIME_BRANCH%."
    exit /b 1
  )
  git -C "%REPO_SENTINEL_WEB_RUNTIME%" switch "%SENTINEL_WEB_RUNTIME_BRANCH%" >NUL 2>&1
  if errorlevel 1 (
    call :fail_sentinel_web_runtime "Runtime worktree is on the wrong branch and automatic non-destructive switch failed." "Switch %REPO_SENTINEL_WEB_RUNTIME% to %SENTINEL_WEB_RUNTIME_BRANCH% manually, then retry."
    exit /b 1
  )
)

git -C "%REPO_SENTINEL_WEB_RUNTIME%" branch --set-upstream-to=%SENTINEL_WEB_UPSTREAM% "%SENTINEL_WEB_RUNTIME_BRANCH%" >NUL 2>&1

set "_SENTINEL_WEB_RUNTIME_DIRTY=NO"
for /f "delims=" %%S in ('git -C "%REPO_SENTINEL_WEB_RUNTIME%" status --porcelain 2^>NUL') do set "_SENTINEL_WEB_RUNTIME_DIRTY=YES"
if "%_SENTINEL_WEB_RUNTIME_DIRTY%"=="YES" (
  call :fail_sentinel_web_runtime "Runtime worktree is dirty." "Preserve or disposition runtime changes under an authorized work unit before startup."
  exit /b 1
)

git -C "%REPO_SENTINEL_WEB_RUNTIME%" fetch origin --prune >NUL 2>&1
if errorlevel 1 (
  call :fail_sentinel_web_runtime "Runtime fetch from origin failed." "Verify remote 'origin' and network access for %REPO_SENTINEL_WEB_RUNTIME%, then retry."
  exit /b 1
)

for /f "delims=" %%R in ('git -C "%REPO_SENTINEL_WEB_RUNTIME%" rev-parse "%SENTINEL_WEB_UPSTREAM%" 2^>NUL') do set "_SENTINEL_WEB_REMOTE_HEAD=%%R"
if "%_SENTINEL_WEB_REMOTE_HEAD%"=="" (
  call :fail_sentinel_web_runtime "Upstream authority origin/main is missing." "Restore remote branch origin/main and retry startup."
  exit /b 1
)

for /f "tokens=1,2" %%L in ('git -C "%REPO_SENTINEL_WEB_RUNTIME%" rev-list --left-right --count "%SENTINEL_WEB_UPSTREAM%...HEAD" 2^>NUL') do (set "_SENTINEL_WEB_BEHIND=%%L" & set "_SENTINEL_WEB_AHEAD=%%M")

if not "%_SENTINEL_WEB_AHEAD%"=="0" if not "%_SENTINEL_WEB_BEHIND%"=="0" (
  call :fail_sentinel_web_runtime "Sentinel Web runtime worktree has diverged from origin/main." "Inspect commits unique to the runtime branch and reconcile under an authorized work unit."
  exit /b 1
)

if not "%_SENTINEL_WEB_AHEAD%"=="0" if "%_SENTINEL_WEB_BEHIND%"=="0" (
  call :fail_sentinel_web_runtime "Sentinel Web runtime worktree is ahead of origin/main." "Preserve runtime commits and reconcile manually; startup does not auto-reset or force-update."
  exit /b 1
)

if "%_SENTINEL_WEB_AHEAD%"=="0" if not "%_SENTINEL_WEB_BEHIND%"=="0" (
  git -C "%REPO_SENTINEL_WEB_RUNTIME%" merge --ff-only "%SENTINEL_WEB_UPSTREAM%" >NUL 2>&1
  if errorlevel 1 (
    call :fail_sentinel_web_runtime "Runtime worktree is behind and fast-forward synchronization failed." "Resolve blocking runtime state manually without rebase/reset, then retry."
    exit /b 1
  )
)

for /f "delims=" %%H in ('git -C "%REPO_SENTINEL_WEB_RUNTIME%" rev-parse HEAD 2^>NUL') do set "_SENTINEL_WEB_RUNTIME_HEAD=%%H"
for /f "delims=" %%R in ('git -C "%REPO_SENTINEL_WEB_RUNTIME%" rev-parse "%SENTINEL_WEB_UPSTREAM%" 2^>NUL') do set "_SENTINEL_WEB_REMOTE_HEAD=%%R"
for /f "tokens=1,2" %%L in ('git -C "%REPO_SENTINEL_WEB_RUNTIME%" rev-list --left-right --count "%SENTINEL_WEB_UPSTREAM%...HEAD" 2^>NUL') do (set "_SENTINEL_WEB_BEHIND=%%L" & set "_SENTINEL_WEB_AHEAD=%%M")
set "_SENTINEL_WEB_RUNTIME_DIRTY=NO"
for /f "delims=" %%S in ('git -C "%REPO_SENTINEL_WEB_RUNTIME%" status --porcelain 2^>NUL') do set "_SENTINEL_WEB_RUNTIME_DIRTY=YES"
for /f "delims=" %%B in ('git -C "%REPO_SENTINEL_WEB_RUNTIME%" branch --show-current 2^>NUL') do set "_SENTINEL_WEB_RUNTIME_BRANCH=%%B"

if not "%_SENTINEL_WEB_RUNTIME_BRANCH%"=="%SENTINEL_WEB_RUNTIME_BRANCH%" (
  call :fail_sentinel_web_runtime "Runtime worktree is on the wrong branch." "Switch runtime worktree to %SENTINEL_WEB_RUNTIME_BRANCH% and retry."
  exit /b 1
)

if "%_SENTINEL_WEB_RUNTIME_DIRTY%"=="YES" (
  call :fail_sentinel_web_runtime "Runtime worktree became dirty during synchronization." "Clean runtime worktree state and retry."
  exit /b 1
)

if not "%_SENTINEL_WEB_RUNTIME_HEAD%"=="%_SENTINEL_WEB_REMOTE_HEAD%" (
  call :fail_sentinel_web_runtime "Runtime HEAD does not equal origin/main after synchronization." "Inspect runtime divergence and reconcile under an authorized work unit."
  exit /b 1
)

if not "%_SENTINEL_WEB_AHEAD%:%_SENTINEL_WEB_BEHIND%"=="0:0" (
  call :fail_sentinel_web_runtime "Runtime parity check failed after synchronization." "Ensure runtime branch matches origin/main with ahead/behind 0 0, then retry."
  exit /b 1
)

exit /b 0

:require_free_port
set "_PORT=%~1"
set "_LABEL=%~2"
set "_LISTEN_PID="
for /f "tokens=5" %%P in ('netstat -ano ^| findstr /R /C:":%_PORT% .*LISTENING"') do if not defined _LISTEN_PID set "_LISTEN_PID=%%P"
if not defined _LISTEN_PID exit /b 0
call :fail "%_LABEL% cannot start because port %_PORT% is already occupied by pre-existing process PID %_LISTEN_PID%." "Stop the unrelated process or run %ALLPROJECTS%\Stop-Local1.cmd, then retry Start-Local1.cmd."
exit /b 1

:wait_port
set "_PORT=%~1"
set "_LABEL=%~2"
set /a "_I=0"
echo Waiting for %_LABEL% ^(port %_PORT%^)...
:wait_port_loop
netstat -ano | findstr ":%_PORT% " | findstr "LISTENING" >NUL 2>&1
if not errorlevel 1 (
  echo READY: %_LABEL%
  exit /b 0
)
set /a "_I+=2"
if %_I% GEQ %WAIT_SECONDS% (
  call :fail "%_LABEL% did not open port %_PORT% within %WAIT_SECONDS%s." "Inspect Docker Desktop / container logs for sentinel-staging-sql."
  exit /b 1
)
ping -n 3 127.0.0.1 >NUL
goto wait_port_loop

:wait_http
set "_URL=%~1"
set "_LABEL=%~2"
set /a "_I=0"
echo Waiting for %_LABEL% ^(%_URL%^)...
:wait_http_loop
set "_CODE="
for /f "delims=" %%C in ('curl.exe -s -o NUL -w "%%{http_code}" --connect-timeout 2 --max-time 5 "%_URL%" 2^>NUL') do set "_CODE=%%C"
if not "%_CODE%"=="" if not "%_CODE%"=="000" (
  echo READY: %_LABEL% ^(HTTP %_CODE%^)
  exit /b 0
)
set /a "_I+=2"
if %_I% GEQ %WAIT_SECONDS% (
  call :fail "%_LABEL% did not respond at %_URL% within %WAIT_SECONDS%s." "Check the Local1 console window for that service, then re-run Start-Local1.cmd."
  exit /b 1
)
ping -n 3 127.0.0.1 >NUL
goto wait_http_loop

:is_http_ready
set "_CODE="
for /f "delims=" %%C in ('curl.exe -s -o NUL -w "%%{http_code}" --connect-timeout 2 --max-time 5 "%~1" 2^>NUL') do set "_CODE=%%C"
if "%_CODE%"=="" exit /b 1
if "%_CODE%"=="000" exit /b 1
exit /b 0

:is_http_status_ready
set "_CODE="
for /f "delims=" %%C in ('curl.exe -s -o NUL -w "%%{http_code}" --connect-timeout 2 --max-time 5 "%~1" 2^>NUL') do set "_CODE=%%C"
if "%_CODE%"=="%~2" exit /b 0
exit /b 1

:wait_http_status
set "_URL=%~1"
set "_EXPECT=%~2"
set "_LABEL=%~3"
set /a "_I=0"
echo Waiting for %_LABEL% ^(expect HTTP %_EXPECT%^)...
:wait_http_status_loop
set "_CODE="
for /f "delims=" %%C in ('curl.exe -s -o NUL -w "%%{http_code}" --connect-timeout 2 --max-time 5 "%_URL%" 2^>NUL') do set "_CODE=%%C"
if "%_CODE%"=="%_EXPECT%" (
  echo READY: %_LABEL% ^(HTTP %_CODE%^)
  exit /b 0
)
set /a "_I+=2"
if %_I% GEQ %WAIT_SECONDS% (
  call :fail "%_LABEL% did not return HTTP %_EXPECT% within %WAIT_SECONDS%s. Last status: %_CODE%." "Confirm DB connection in .env.local and review the Local1 - PI API console."
  exit /b 1
)
ping -n 3 127.0.0.1 >NUL
goto wait_http_status_loop

:verify_all
set "_OK=1"
call :check_one 5000 "http://localhost:5000" "EVO Auth/API"
if errorlevel 1 set "_OK=0"
call :check_status 5038 "http://127.0.0.1:5038/api/health/db" "200" "PI API health/db"
if errorlevel 1 set "_OK=0"
call :check_one 5173 "http://localhost:5173" "Sentinel Web"
if errorlevel 1 set "_OK=0"
call :check_one 4201 "http://localhost:4201" "SAXIO Web"
if errorlevel 1 set "_OK=0"
call :check_one 8080 "http://localhost:8080" "Local Gateway"
if errorlevel 1 set "_OK=0"
if "%_OK%"=="0" (
  call :fail "One or more Local 1 services failed final verification." "Review FAILED lines above, fix the listed console, then re-run Start-Local1.cmd or use Stop-Local1.cmd first."
  exit /b 1
)
exit /b 0

:check_one
set "_P=%~1"
set "_U=%~2"
set "_N=%~3"
set "_CODE="
for /f "delims=" %%C in ('curl.exe -s -o NUL -w "%%{http_code}" --connect-timeout 2 --max-time 5 "%_U%" 2^>NUL') do set "_CODE=%%C"
if "%_CODE%"=="" set "_CODE=000"
if "%_CODE%"=="000" (
  echo   FAILED  :%_P%  %_N%
  echo   Reason: endpoint not reachable: %_U%
  echo   Suggested Fix: Check the Local1 console for %_N%, then restart that service.
  exit /b 1
)
echo   OK      :%_P%  %_N% ^(HTTP %_CODE%^)
exit /b 0

:check_status
set "_P=%~1"
set "_U=%~2"
set "_EXPECT=%~3"
set "_N=%~4"
set "_CODE="
for /f "delims=" %%C in ('curl.exe -s -o NUL -w "%%{http_code}" --connect-timeout 2 --max-time 5 "%_U%" 2^>NUL') do set "_CODE=%%C"
if "%_CODE%"=="%_EXPECT%" (
  echo   OK      :%_P%  %_N% ^(HTTP %_CODE%^)
  exit /b 0
)
echo   FAILED  :%_P%  %_N%
echo   Reason: expected HTTP %_EXPECT% from %_U%, got %_CODE%
echo   Suggested Fix: Check the Local1 console for %_N%, then restart that service.
exit /b 1

