$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$launcherPath = Join-Path $repositoryRoot 'Start-Local1.cmd'
$stopPath = Join-Path $repositoryRoot 'Stop-Local1.cmd'
$manifestPath = Join-Path $repositoryRoot 'runtime.manifest.json'
$readmePath = Join-Path $repositoryRoot 'README.md'
$chainPath = Join-Path $repositoryRoot 'runtime\local1\STARTUP-CHAIN.md'
$precedencePath = Join-Path $repositoryRoot 'runtime\local1\STARTUP-CONFIGURATION-PRECEDENCE.md'
$remediationPath = Join-Path $repositoryRoot 'runtime\local1\STARTUP-REMEDIATION.md'
$duplicateAuthorityPath = Join-Path $repositoryRoot 'runtime\local1\startup-db-authority.ps1'

$script:Passed = 0
$script:Failed = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Invoke-Test {
    param([string]$Name, [scriptblock]$Test)
    try { & $Test; $script:Passed++; Write-Output "PASS $Name" }
    catch { $script:Failed++; Write-Output "FAIL $Name - $($_.Exception.Message)" }
}

$launcher = Get-Content -Raw -LiteralPath $launcherPath
$stop = Get-Content -Raw -LiteralPath $stopPath
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
$readme = Get-Content -Raw -LiteralPath $readmePath
$chain = Get-Content -Raw -LiteralPath $chainPath
$precedence = Get-Content -Raw -LiteralPath $precedencePath
$remediation = Get-Content -Raw -LiteralPath $remediationPath
$saxioAuthority = 'C:\Allprojects\SAXIO-Sentinel\runtime\local1\startup-db-authority.ps1'
$saxioLauncher = 'C:\Allprojects\SAXIO-Sentinel\runtime\local1\launch-pi-api.cmd'

try {
    Invoke-Test '1 Default launcher does not start or require Docker SQL' {
        Assert-True ($launcher -match 'Docker SQL: not used') 'Default banner must state Docker SQL is not used.'
        Assert-True ($launcher -notmatch '\[1/6\] Docker SQL Server') 'Default numbered steps must not include Docker SQL.'
        Assert-True ($launcher -notmatch 'SKIPPED: Docker SQL is secondary') 'Default path must not print a Docker SKIPPED step.'
        Assert-True ($launcher -match 'if "%USE_DOCKER_SQL%"=="1"') 'UseDockerSql guard is missing.'
        $composeCall = '"%SQL_BOOTSTRAP%" -SentinelRepositoryPath "%REPO_SENTINEL%"'
        $composeIndex = $launcher.LastIndexOf($composeCall)
        Assert-True ($composeIndex -gt 0) 'Docker SQL bootstrap invocation is missing.'
        $guardBeforeCompose = $launcher.LastIndexOf('if "%USE_DOCKER_SQL%"=="1"', $composeIndex)
        Assert-True ($guardBeforeCompose -ge 0) 'Docker SQL bootstrap is not inside a UseDockerSql guard.'
        Assert-True ($launcher -notmatch '(?i)docker info|docker version|Docker Desktop') 'Default launcher must not check Docker daemon/install status.'
    }

    Invoke-Test '2 SQL secret validation is UseDockerSql-only' {
        $validateOnlyCall = '"%SQL_BOOTSTRAP%" -SentinelRepositoryPath "%REPO_SENTINEL%" -ValidateOnly'
        $validateIndex = $launcher.IndexOf($validateOnlyCall)
        Assert-True ($validateIndex -gt 0) 'SQL ValidateOnly invocation is missing.'
        $guardBeforeValidate = $launcher.LastIndexOf('if "%USE_DOCKER_SQL%"=="1"', $validateIndex)
        Assert-True ($guardBeforeValidate -ge 0) 'SQL ValidateOnly is not inside a UseDockerSql guard.'
    }

    Invoke-Test '3 PI/database authority is delegated to SAXIO-Sentinel' {
        Assert-True ($launcher -match 'call :resolve_saxio_repo') 'Launcher does not resolve a hostname-capable SAXIO checkout.'
        Assert-True ($launcher -match 'PW9FEZ\.cus\.win\.liquidweb\.com') 'Launcher does not require approved TLS hostname PW9FEZ.'
        Assert-True ($launcher.Contains('set "DB_AUTHORITY=%REPO_SENTINEL%\runtime\local1\startup-db-authority.ps1"')) 'Launcher does not delegate DB authority to SAXIO-Sentinel.'
        Assert-True ($launcher.Contains('set "PI_LAUNCHER=%REPO_SENTINEL%\runtime\local1\launch-pi-api.cmd"')) 'Launcher does not retain PI launcher path from resolved SAXIO checkout.'
        Assert-True ($launcher -match '-Repository "%REPO_SENTINEL%" -EnvironmentFile "%ENV_LOCAL%"') 'Launcher does not pass resolved repository and canonical secrets to authority.'
        Assert-True ($launcher -match '-LaunchPiApi') 'Launcher does not launch PI through SAXIO authority.'
        Assert-True (-not (Test-Path -LiteralPath $duplicateAuthorityPath -PathType Leaf)) 'Local1-Operations still duplicates SAXIO startup-db-authority.ps1.'
        Assert-True (Test-Path -LiteralPath $saxioAuthority -PathType Leaf) 'SAXIO startup-db-authority.ps1 is missing.'
        Assert-True (Test-Path -LiteralPath $saxioLauncher -PathType Leaf) 'SAXIO launch-pi-api.cmd is missing.'
    }

    Invoke-Test '4 AllowExternalDb is obsolete and not an authority' {
        Assert-True ($launcher -match 'NOTE: -AllowExternalDb is obsolete') 'Launcher does not mark AllowExternalDb obsolete.'
        Assert-True ($launcher -notmatch '(?i)set "ALLOW_EXTERNAL_DB=1"') 'Launcher still promotes AllowExternalDb as an active switch.'
        Assert-True ($manifest.crimePiDatabase.obsoleteFlags -contains '-AllowExternalDb') 'Manifest does not list AllowExternalDb as obsolete.'
        Assert-True ($launcher -notmatch '(?i)AllowExternalDb is the') 'Launcher still describes AllowExternalDb as current authority.'
    }

    Invoke-Test '5 Manifest default startup does not require Docker SQL' {
        Assert-True ($manifest.startupOrder -notcontains 'docker-sql') 'Default startupOrder still includes docker-sql.'
        $docker = $manifest.services | Where-Object { $_.id -eq 'docker-sql' }
        Assert-True ($null -ne $docker) 'docker-sql override service is missing from the manifest.'
        Assert-True ($docker.requiredByDefault -eq $false) 'docker-sql is still required by default.'
        Assert-True ($docker.overrideFlag -eq '-UseDockerSql') 'docker-sql override flag is missing.'
        $defaultDependents = @($manifest.services | Where-Object { $_.id -ne 'docker-sql' -and $_.dependencies -contains 'docker-sql' })
        Assert-True ($defaultDependents.Count -eq 0) ("Unconditional docker-sql dependency remains on: " + (($defaultDependents | ForEach-Object { $_.id }) -join ', '))
        Assert-True ($manifest.crimePiDatabase.default.server -eq '67.225.176.136') 'Manifest default Crime PI server is wrong.'
        Assert-True ($manifest.crimePiDatabase.default.database -eq 'SentinelStaging') 'Manifest default Crime PI database is wrong.'
        Assert-True ($manifest.crimePiDatabase.authorityScript -eq $saxioAuthority) 'Manifest does not point Crime PI authority at SAXIO-Sentinel.'
        Assert-True ($manifest.services.Where({ $_.id -eq 'pi-api' }).command -eq $saxioLauncher) 'Manifest PI command is not SAXIO launch-pi-api.cmd.'
    }

    Invoke-Test '6 Canonical start/stop sources are owned here' {
        Assert-True (Test-Path -LiteralPath $stopPath -PathType Leaf) 'Stop-Local1.cmd is not tracked in Local1-Operations.'
        Assert-True ($stop -match 'Does NOT stop Docker / SQL' -or $stop -match 'Leaving Docker SQL running') 'Stop script no longer leaves Docker SQL running.'
        Assert-True ($stop -notmatch 'docker compose|compose down|sentinel-staging-sql') 'Stop script contains Docker lifecycle commands.'
        Assert-True ($manifest.launcher.stopSource -like '*Local1-Operations\Stop-Local1.cmd') 'Manifest stopSource is not this repository.'
        Assert-True ($manifest.launcher.startSource -like '*Local1-Operations\Start-Local1.cmd') 'Manifest startSource is not this repository.'
    }

    Invoke-Test '7 README and chain describe the same topology' {
        Assert-True ($readme -match 'cross-repository orchestration authority') 'README does not state orchestration authority.'
        Assert-True ($readme -match 'does not own' -or $readme -match 'What this repository does not own') 'README does not state the non-ownership boundary.'
        Assert-True ($readme -match '67\.225\.176\.136') 'README does not name the default Crime PI server.'
        Assert-True ($readme -match '-UseDockerSql') 'README does not name the Docker override.'
        Assert-True ($chain -match 'Local1-Operations\\runtime.manifest.json') 'STARTUP-CHAIN still points at the stale AllProjects runtime manifest.'
        Assert-True ($chain -match 'optional, -UseDockerSql only') 'STARTUP-CHAIN still treats Docker SQL as unconditional.'
        Assert-True ($precedence -match 'Local1-Operations does not select the Crime PI database') 'Precedence doc still claims Local1-Operations selects the database.'
        Assert-True ($precedence -notmatch 'SQL_CONNECTION_STRING` in `\.env\.local` is the sole default') 'Precedence doc still treats Docker SQL_CONNECTION_STRING as the default authority.'
        Assert-True ($remediation -match '67\.225\.176\.136') 'Remediation doc does not name the default Crime PI server.'
        Assert-True ($remediation -notmatch 'Start-Local1\.cmd -AllowExternalDb') 'Remediation doc still presents AllowExternalDb as the external startup command.'
    }

    Invoke-Test '8 Default orchestration surfaces remain intact' {
        $requiredIds = @('evo-auth-api', 'pi-api', 'local-gateway', 'sentinel-web', 'saxio-web')
        foreach ($id in $requiredIds) {
            Assert-True ($manifest.startupOrder -contains $id) "Default startupOrder is missing $id."
            $service = $manifest.services | Where-Object { $_.id -eq $id }
            Assert-True ($null -ne $service) "Manifest is missing service $id."
            Assert-True ($service.requiredByDefault -eq $true) "$id is not required by default."
        }
        Assert-True ($launcher -match '\[1/5\] EVO Auth/API') 'Launcher lost EVO Auth/API startup.'
        Assert-True ($launcher -match '\[2/5\] Portfolio Intelligence API') 'Launcher lost PI API startup.'
        Assert-True ($launcher -match '\[3/5\] Local Gateway') 'Launcher lost Local Gateway startup.'
        Assert-True ($launcher -match '\[4/5\] Sentinel Web') 'Launcher lost Sentinel Web startup.'
        Assert-True ($launcher -match '\[5/5\] SAXIO Web') 'Launcher lost SAXIO Web startup.'
        Assert-True ($launcher -match 'Ensure-Local1SentinelLogic.ps1') 'Launcher lost Sentinel-Logic runtime provisioning.'
    }
}
finally { }

Write-Output ("RESULT Passed={0} Failed={1}" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
exit 0
