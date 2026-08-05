[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PortfolioRoot,
    [Parameter(Mandatory)][ValidateSet('ProvisionRuntime', 'ValidateDependencies')][string]$Mode
)

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'Local1SentinelLogicRuntime.psm1'
$developmentPath = Join-Path $PortfolioRoot 'Sentinel-Logic'
$runtimePath = Join-Path $PortfolioRoot 'Local1\Sentinel-Logic-Runtime'
$junctionPath = Join-Path $PortfolioRoot 'Local1\Sentinel-Logic'
$sentinelWebRuntimePath = Join-Path $PortfolioRoot 'Local1\Sentinel-Web-Runtime'

function Write-Local1SentinelLogicFailure {
    param($ErrorRecord)
    $parts = ([string]$ErrorRecord.Exception.Message).Split('|')
    $code = $parts[0]
    Write-Output ''
    Write-Output 'FAILED'
    switch ($code) {
        'DEVELOPMENT_REPOSITORY_MISSING' {
            Write-Output 'Reason: Sentinel-Logic development repository was not found.'
            Write-Output ("Expected Path: {0}" -f $developmentPath)
            Write-Output 'Runtime provisioning was not attempted.'
        }
        'RUNTIME_DIRTY' {
            Write-Output 'Reason: Sentinel-Logic runtime worktree is dirty.'
            Write-Output ("Runtime Path: {0}" -f $runtimePath)
            Write-Output 'Automatic cleanup: DISABLED'
        }
        'RUNTIME_DIVERGED' {
            Write-Output 'Reason: Sentinel-Logic runtime branch has diverged from origin/main.'
            Write-Output ("Ahead/Behind: {0} {1}" -f $parts[2], $parts[1])
            Write-Output 'Automatic reset: DISABLED'
        }
        'RUNTIME_AHEAD' {
            Write-Output 'Reason: Sentinel-Logic runtime branch is ahead of origin/main.'
            Write-Output ("Ahead/Behind: {0} {1}" -f $parts[2], $parts[1])
            Write-Output 'Automatic reset: DISABLED'
        }
        { $_ -in @('JUNCTION_INVALID', 'JUNCTION_ORDINARY_DIRECTORY', 'JUNCTION_FILE') } {
            Write-Output 'Reason: Sentinel-Logic dependency path exists but is not the governed junction.'
            Write-Output ("Path: {0}" -f $junctionPath)
            Write-Output ("Expected Target: {0}" -f $runtimePath)
            Write-Output 'Automatic deletion: DISABLED'
        }
        'PACKAGE_EXPORT_JS_MISSING' {
            Write-Output 'Reason: Sentinel-Logic runtime package does not contain the exported Crime Level 2 module.'
            Write-Output 'Expected File:'
            Write-Output '  src\crime\schemas\crimeLevel2GovernedPopulation.schemas.js'
        }
        'PACKAGE_EXPORT_TYPES_MISSING' {
            Write-Output 'Reason: Sentinel-Logic runtime package does not contain the exported Crime Level 2 type module.'
            Write-Output 'Expected File:'
            Write-Output '  src\crime\schemas\crimeLevel2GovernedPopulation.schemas.d.ts'
        }
        'DEPENDENCY_INVALID' {
            Write-Output 'Reason: Sentinel Web local dependency `sentinel-logic` is invalid after npm installation.'
            Write-Output 'Suggested Fix:'
            Write-Output '  Inspect the governed Sentinel-Logic runtime worktree and package export contract.'
        }
        default {
            Write-Output 'Reason: Sentinel-Logic Local 1 runtime governance failed.'
            Write-Output ("Failure Code: {0}" -f $code)
            Write-Output 'Automatic cleanup/reset/deletion: DISABLED'
        }
    }
}

try {
    Import-Module $modulePath -Force -DisableNameChecking
    if ($Mode -eq 'ProvisionRuntime') {
        $runtime = Ensure-Local1SentinelLogicRuntime -DevelopmentPath $developmentPath -RuntimePath $runtimePath
        $junction = Ensure-Local1SentinelLogicJunction -JunctionPath $junctionPath -RuntimePath $runtimePath
        Test-Local1SentinelLogicExports -RuntimePath $runtimePath | Out-Null
        Write-Output ''
        Write-Output 'Sentinel-Logic Runtime Provisioning:'
        Write-Output ("  Development Branch: {0}" -f $runtime.DevelopmentBranch)
        Write-Output ("  Runtime Branch: {0}" -f $runtime.RuntimeBranch)
        Write-Output '  Ahead/Behind: 0 0'
        Write-Output ("  Junction Target: {0}" -f $junction.JunctionTarget)
        Write-Output '  Result: PASS'
        exit 0
    }

    $runtime = Ensure-Local1SentinelLogicRuntime -DevelopmentPath $developmentPath -RuntimePath $runtimePath
    $junction = Ensure-Local1SentinelLogicJunction -JunctionPath $junctionPath -RuntimePath $runtimePath
    $dependency = Ensure-Local1SentinelWebDependency -SentinelWebRuntimePath $sentinelWebRuntimePath -SentinelLogicRuntimePath $runtimePath -JunctionPath $junctionPath
    Write-Output ''
    Write-Output 'Sentinel-Logic Runtime:'
    Write-Output ("  Development Path: {0}" -f $runtime.DevelopmentPath)
    Write-Output ("  Development Branch: {0}" -f $runtime.DevelopmentBranch)
    Write-Output ("  Runtime Path: {0}" -f $runtime.RuntimePath)
    Write-Output ("  Runtime Branch: {0}" -f $runtime.RuntimeBranch)
    Write-Output ("  Upstream: {0}" -f $runtime.Upstream)
    Write-Output ("  Local SHA: {0}" -f $runtime.LocalSha)
    Write-Output ("  Remote SHA: {0}" -f $runtime.RemoteSha)
    Write-Output '  Ahead/Behind: 0 0'
    Write-Output '  Working Tree Dirty: NO'
    Write-Output ("  Junction Path: {0}" -f $junction.JunctionPath)
    Write-Output ("  Junction Target: {0}" -f $junction.JunctionTarget)
    Write-Output '  Dependency Valid: YES'
    Write-Output ("  npm Validation: {0}" -f $dependency.NpmValidation)
    Write-Output ("  Active Vite Reused: {0}" -f $(if ($dependency.ActiveViteReused) { 'YES' } else { 'NO' }))
    Write-Output ("  Dependencies Reinstalled: {0}" -f $(if ($dependency.Reinstalled) { 'YES' } else { 'NO' }))
    Write-Output ("  Local 1 Vite Processes Stopped: {0}" -f $dependency.OwnedViteProcessesStopped)
    Write-Output '  Result: PASS'
    exit 0
}
catch {
    Write-Local1SentinelLogicFailure -ErrorRecord $_
    exit 1
}
