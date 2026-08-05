$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $repositoryRoot 'runtime\local1\Local1SentinelLogicRuntime.psm1'
$launcherPath = Join-Path $repositoryRoot 'Start-Local1.cmd'
Import-Module $modulePath -Force -DisableNameChecking

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

function New-GitScenario {
    param(
        [string]$DevelopmentPath,
        [string]$RuntimePath,
        [string]$DevelopmentBranch = 'August-V1',
        [string]$RuntimeBranch = 'runtime/local1-sentinel-logic',
        [string]$StatusOutput = '',
        [string[]]$ParityOutputs = @('0 0', '0 0'),
        [bool]$UpstreamExists = $true,
        [bool]$LocalRuntimeBranchExists = $true,
        [bool]$WorktreeListed = $false
    )
    $state = [pscustomobject]@{
        Calls = New-Object 'System.Collections.Generic.List[string]'
        ParityIndex = 0
        DevelopmentPath = $DevelopmentPath
        RuntimePath = $RuntimePath
        DevelopmentBranch = $DevelopmentBranch
        RuntimeBranch = $RuntimeBranch
        CommonDirectory = (Join-Path $DevelopmentPath '.git')
        StatusOutput = $StatusOutput
        ParityOutputs = $ParityOutputs
        UpstreamExists = $UpstreamExists
        LocalRuntimeBranchExists = $LocalRuntimeBranchExists
        WorktreeListed = $WorktreeListed
    }
    $adapter = {
        param($RepositoryPath, $Arguments)
        $command = $Arguments -join ' '
        $state.Calls.Add("$RepositoryPath|$command")
        if ($command -eq 'rev-parse --is-inside-work-tree') { return [pscustomobject]@{ExitCode=0;Output='true'} }
        if ($command -eq 'rev-parse --git-common-dir') { return [pscustomobject]@{ExitCode=0;Output=$state.CommonDirectory} }
        if ($command -eq 'branch --show-current') {
            $branch = if ($RepositoryPath -eq $state.RuntimePath) { $state.RuntimeBranch } else { $state.DevelopmentBranch }
            return [pscustomobject]@{ExitCode=0;Output=$branch}
        }
        if ($command -eq 'fetch origin --prune') { return [pscustomobject]@{ExitCode=0;Output=''} }
        if ($command -eq 'show-ref --verify --quiet refs/remotes/origin/main') { return [pscustomobject]@{ExitCode=$(if($state.UpstreamExists){0}else{1});Output=''} }
        if ($command -eq 'show-ref --verify --quiet refs/heads/runtime/local1-sentinel-logic') { return [pscustomobject]@{ExitCode=$(if($state.LocalRuntimeBranchExists){0}else{1});Output=''} }
        if ($command -eq 'worktree list --porcelain') {
            $value = if ($state.WorktreeListed) { "worktree $($state.RuntimePath.Replace('\','/'))" } else { '' }
            return [pscustomobject]@{ExitCode=0;Output=$value}
        }
        if ($command -eq 'worktree prune') { return [pscustomobject]@{ExitCode=0;Output=''} }
        if ($command -like 'worktree add*') { return [pscustomobject]@{ExitCode=0;Output='created'} }
        if ($command -eq 'status --porcelain') { return [pscustomobject]@{ExitCode=0;Output=$state.StatusOutput} }
        if ($command -eq 'branch --set-upstream-to=origin/main runtime/local1-sentinel-logic') { return [pscustomobject]@{ExitCode=0;Output=''} }
        if ($command -eq 'rev-list --left-right --count origin/main...HEAD') {
            $index = [Math]::Min($state.ParityIndex, $state.ParityOutputs.Count - 1)
            $value = $state.ParityOutputs[$index]
            $state.ParityIndex++
            return [pscustomobject]@{ExitCode=0;Output=$value}
        }
        if ($command -eq 'merge --ff-only origin/main') { return [pscustomobject]@{ExitCode=0;Output='fast-forward'} }
        if ($command -eq 'rev-parse HEAD') { return [pscustomobject]@{ExitCode=0;Output='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'} }
        if ($command -eq 'rev-parse origin/main') { return [pscustomobject]@{ExitCode=0;Output='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'} }
        [pscustomobject]@{ExitCode=1;Output="Unexpected git command: $command"}
    }.GetNewClosure()
    [pscustomobject]@{ Adapter = $adapter; State = $state }
}

function New-FileSystemScenario {
    param([string]$Kind, [string]$Target)
    $state = [pscustomobject]@{ Kind=$Kind; Target=$Target; CreateCount=0 }
    $adapter = {
        param($Operation, $Path, $ExpectedTarget)
        if ($Operation -eq 'GetState') { return [pscustomobject]@{Kind=$state.Kind;Target=$state.Target} }
        if ($Operation -eq 'CreateJunction') { $state.Kind='Junction';$state.Target=$ExpectedTarget;$state.CreateCount++;return }
        throw "Unexpected filesystem operation: $Operation"
    }.GetNewClosure()
    [pscustomobject]@{Adapter=$adapter;State=$state}
}

function New-DependencyScenario {
    param(
        [string]$WebPath,
        [string]$LogicPath,
        [bool]$ModuleExists = $true,
        [bool]$JsExportExists = $true,
        [bool]$TypeExportExists = $true,
        [string[]]$ListOutputs = @('sentinel-logic@0.1.0'),
        [int[]]$ListExitCodes = @(0),
        [int]$InstallExitCode = 0,
        [object[]]$OwnedProcesses = @()
    )
    $state = [pscustomobject]@{ModuleExists=$ModuleExists;Js=$JsExportExists;Types=$TypeExportExists;ListIndex=0;InstallCount=0;StopCount=0;ListOutputs=$ListOutputs;ListExitCodes=$ListExitCodes;InstallExitCode=$InstallExitCode;Owned=$OwnedProcesses}
    $pathTester = {
        param($Path)
        if ($Path -like '*crimeLevel2GovernedPopulation.schemas.js') { return $state.Js }
        if ($Path -like '*crimeLevel2GovernedPopulation.schemas.d.ts') { return $state.Types }
        if ($Path -like '*node_modules\sentinel-logic') { return $state.ModuleExists }
        $true
    }.GetNewClosure()
    $npmAdapter = {
        param($Operation, $Path)
        if ($Operation -eq 'CleanInstall') { $state.InstallCount++;$state.ModuleExists=$true;return [pscustomobject]@{ExitCode=$state.InstallExitCode;Output='install'} }
        $index=[Math]::Min($state.ListIndex,$state.ListOutputs.Count-1)
        $exitIndex=[Math]::Min($state.ListIndex,$state.ListExitCodes.Count-1)
        $result=[pscustomobject]@{ExitCode=$state.ListExitCodes[$exitIndex];Output=$state.ListOutputs[$index]}
        $state.ListIndex++
        $result
    }.GetNewClosure()
    $processAdapter = {
        param($Operation, $Path, $Process)
        if($Operation -eq 'List'){return $state.Owned}
        if($Operation -eq 'Stop'){$state.StopCount++;return}
        throw "Unexpected process operation: $Operation"
    }.GetNewClosure()
    [pscustomobject]@{State=$state;PathTester=$pathTester;NpmAdapter=$npmAdapter;ProcessAdapter=$processAdapter}
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('local1-logic-tests-' + [Guid]::NewGuid().ToString('N'))
$devPath = Join-Path $testRoot 'Sentinel-Logic'
$runtimePath = Join-Path $testRoot 'Local1\Sentinel-Logic-Runtime'
$junctionPath = Join-Path $testRoot 'Local1\Sentinel-Logic'
$webPath = Join-Path $testRoot 'Local1\Sentinel-Web-Runtime'
New-Item -ItemType Directory -Path $devPath,$runtimePath,$webPath -Force | Out-Null

try {
    Invoke-Test '1 Development checkout may remain on non-main branch' {
        $scenario=New-GitScenario $devPath $runtimePath -DevelopmentBranch 'August-V1'
        $result=Ensure-Local1SentinelLogicRuntime -DevelopmentPath $devPath -RuntimePath $runtimePath -GitAdapter $scenario.Adapter
        Assert-True ($result.DevelopmentBranch -eq 'August-V1') 'Development branch was not informational.'
    }
    Invoke-Test '2 Missing runtime worktree is accepted for provisioning' {
        $missing=Join-Path $testRoot 'Local1\Missing-Runtime'
        $scenario=New-GitScenario $devPath $missing
        $result=Ensure-Local1SentinelLogicRuntime -DevelopmentPath $devPath -RuntimePath $missing -GitAdapter $scenario.Adapter
        Assert-True $result.Created 'Missing runtime was not provisioned.'
    }
    Invoke-Test '3 First run creates runtime branch and worktree' {
        $missing=Join-Path $testRoot 'Local1\First-Run'
        $scenario=New-GitScenario $devPath $missing -LocalRuntimeBranchExists $false
        Ensure-Local1SentinelLogicRuntime -DevelopmentPath $devPath -RuntimePath $missing -GitAdapter $scenario.Adapter | Out-Null
        Assert-True ([bool]($scenario.State.Calls | Where-Object {$_ -match 'worktree add -b runtime/local1-sentinel-logic'})) 'Expected worktree creation command was not issued.'
    }
    Invoke-Test '4 Existing valid runtime worktree is reused' {
        $scenario=New-GitScenario $devPath $runtimePath
        $result=Ensure-Local1SentinelLogicRuntime -DevelopmentPath $devPath -RuntimePath $runtimePath -GitAdapter $scenario.Adapter
        Assert-True (-not $result.Created) 'Existing runtime was recreated.'
    }
    Invoke-Test '5 Behind-only runtime fast-forwards' {
        $scenario=New-GitScenario $devPath $runtimePath -ParityOutputs @('1 0','0 0')
        Ensure-Local1SentinelLogicRuntime -DevelopmentPath $devPath -RuntimePath $runtimePath -GitAdapter $scenario.Adapter | Out-Null
        Assert-True ([bool]($scenario.State.Calls | Where-Object {$_ -like '*merge --ff-only origin/main'})) 'Behind runtime did not fast-forward.'
    }
    Invoke-Test '6 Dirty runtime fails closed' {
        $scenario=New-GitScenario $devPath $runtimePath -StatusOutput ' M package.json'
        $failed=$false;try{Ensure-Local1SentinelLogicRuntime -DevelopmentPath $devPath -RuntimePath $runtimePath -GitAdapter $scenario.Adapter|Out-Null}catch{$failed=$_.Exception.Message.StartsWith('RUNTIME_DIRTY|')}
        Assert-True $failed 'Dirty runtime did not fail closed.'
    }
    Invoke-Test '7 Ahead runtime fails closed' {
        $scenario=New-GitScenario $devPath $runtimePath -ParityOutputs @('0 1')
        $failed=$false;try{Ensure-Local1SentinelLogicRuntime -DevelopmentPath $devPath -RuntimePath $runtimePath -GitAdapter $scenario.Adapter|Out-Null}catch{$failed=$_.Exception.Message.StartsWith('RUNTIME_AHEAD|')}
        Assert-True $failed 'Ahead runtime did not fail closed.'
    }
    Invoke-Test '8 Diverged runtime fails closed' {
        $scenario=New-GitScenario $devPath $runtimePath -ParityOutputs @('2 3')
        $failed=$false;try{Ensure-Local1SentinelLogicRuntime -DevelopmentPath $devPath -RuntimePath $runtimePath -GitAdapter $scenario.Adapter|Out-Null}catch{$failed=$_.Exception.Message.StartsWith('RUNTIME_DIVERGED|')}
        Assert-True $failed 'Diverged runtime did not fail closed.'
    }
    Invoke-Test '9 Missing origin main fails closed' {
        $scenario=New-GitScenario $devPath $runtimePath -UpstreamExists $false
        $failed=$false;try{Ensure-Local1SentinelLogicRuntime -DevelopmentPath $devPath -RuntimePath $runtimePath -GitAdapter $scenario.Adapter|Out-Null}catch{$failed=$_.Exception.Message.StartsWith('UPSTREAM_MISSING|')}
        Assert-True $failed 'Missing origin/main did not fail closed.'
    }
    Invoke-Test '10 Missing junction is created' {
        $fs=New-FileSystemScenario 'Missing' $null
        $result=Ensure-Local1SentinelLogicJunction -JunctionPath $junctionPath -RuntimePath $runtimePath -FileSystemAdapter $fs.Adapter
        Assert-True ($result.Created -and $fs.State.CreateCount -eq 1) 'Missing junction was not created once.'
    }
    Invoke-Test '11 Correct junction is reused' {
        $fs=New-FileSystemScenario 'Junction' $runtimePath
        $result=Ensure-Local1SentinelLogicJunction -JunctionPath $junctionPath -RuntimePath $runtimePath -FileSystemAdapter $fs.Adapter
        Assert-True (-not $result.Created -and $fs.State.CreateCount -eq 0) 'Correct junction was not reused.'
    }
    Invoke-Test '12 Wrong junction target fails closed' {
        $fs=New-FileSystemScenario 'Junction' (Join-Path $testRoot 'Wrong')
        $failed=$false;try{Ensure-Local1SentinelLogicJunction -JunctionPath $junctionPath -RuntimePath $runtimePath -FileSystemAdapter $fs.Adapter|Out-Null}catch{$failed=$_.Exception.Message.StartsWith('JUNCTION_INVALID|')}
        Assert-True $failed 'Wrong junction target did not fail closed.'
    }
    Invoke-Test '13 Ordinary directory at junction path fails closed' {
        $fs=New-FileSystemScenario 'Directory' $null
        $failed=$false;try{Ensure-Local1SentinelLogicJunction -JunctionPath $junctionPath -RuntimePath $runtimePath -FileSystemAdapter $fs.Adapter|Out-Null}catch{$failed=$_.Exception.Message.StartsWith('JUNCTION_ORDINARY_DIRECTORY|')}
        Assert-True $failed 'Ordinary directory did not fail closed.'
    }
    Invoke-Test '14 Missing exported JS file fails' {
        $dep=New-DependencyScenario $webPath $runtimePath -JsExportExists $false
        $failed=$false;try{Ensure-Local1SentinelWebDependency -SentinelWebRuntimePath $webPath -SentinelLogicRuntimePath $runtimePath -JunctionPath $junctionPath -PathTester $dep.PathTester -NpmAdapter $dep.NpmAdapter -ProcessAdapter $dep.ProcessAdapter|Out-Null}catch{$failed=$_.Exception.Message.StartsWith('PACKAGE_EXPORT_JS_MISSING|')}
        Assert-True $failed 'Missing JS export did not fail.'
    }
    Invoke-Test '15 Missing exported type file fails' {
        $dep=New-DependencyScenario $webPath $runtimePath -TypeExportExists $false
        $failed=$false;try{Ensure-Local1SentinelWebDependency -SentinelWebRuntimePath $webPath -SentinelLogicRuntimePath $runtimePath -JunctionPath $junctionPath -PathTester $dep.PathTester -NpmAdapter $dep.NpmAdapter -ProcessAdapter $dep.ProcessAdapter|Out-Null}catch{$failed=$_.Exception.Message.StartsWith('PACKAGE_EXPORT_TYPES_MISSING|')}
        Assert-True $failed 'Missing type export did not fail.'
    }
    Invoke-Test '16 Npm list invalid after install fails' {
        $dep=New-DependencyScenario $webPath $runtimePath -ListOutputs @('invalid','invalid') -ListExitCodes @(1,1)
        $failed=$false;try{Ensure-Local1SentinelWebDependency -SentinelWebRuntimePath $webPath -SentinelLogicRuntimePath $runtimePath -JunctionPath $junctionPath -PathTester $dep.PathTester -NpmAdapter $dep.NpmAdapter -ProcessAdapter $dep.ProcessAdapter|Out-Null}catch{$failed=$_.Exception.Message.StartsWith('DEPENDENCY_INVALID|')}
        Assert-True $failed 'Invalid npm dependency did not fail after reinstall.'
    }
    Invoke-Test '17 Stale node modules triggers governed reinstall' {
        $dep=New-DependencyScenario $webPath $runtimePath -ModuleExists $false -ListOutputs @('invalid','sentinel-logic@0.1.0') -ListExitCodes @(1,0)
        $result=Ensure-Local1SentinelWebDependency -SentinelWebRuntimePath $webPath -SentinelLogicRuntimePath $runtimePath -JunctionPath $junctionPath -PathTester $dep.PathTester -NpmAdapter $dep.NpmAdapter -ProcessAdapter $dep.ProcessAdapter
        Assert-True ($result.Reinstalled -and $dep.State.InstallCount -eq 1) 'Stale dependency did not reinstall once.'
    }
    Invoke-Test '18 Local 1 owned Vite process can be stopped safely' {
        $owned=[pscustomobject]@{ProcessId=1234;CommandLine="node $webPath\node_modules\vite --port 5173"}
        $dep=New-DependencyScenario $webPath $runtimePath -ListOutputs @('invalid','sentinel-logic@0.1.0') -ListExitCodes @(1,0) -OwnedProcesses @($owned)
        $result=Ensure-Local1SentinelWebDependency -SentinelWebRuntimePath $webPath -SentinelLogicRuntimePath $runtimePath -JunctionPath $junctionPath -PathTester $dep.PathTester -NpmAdapter $dep.NpmAdapter -ProcessAdapter $dep.ProcessAdapter
        Assert-True ($result.OwnedViteProcessesStopped -eq 1 -and $dep.State.StopCount -eq 1) 'Owned Vite process was not stopped.'
    }
    Invoke-Test '19 Unrelated Node process is not owned' {
        Assert-True (-not (Test-Local1OwnedViteCommandLine -SentinelWebRuntimePath $webPath -CommandLine 'node C:\Other\app.js --port 5173')) 'Unrelated Node process was classified as Local 1-owned.'
    }
    Invoke-Test '20 Repeated startup is idempotent' {
        $dep=New-DependencyScenario $webPath $runtimePath
        1..2|ForEach-Object{Ensure-Local1SentinelWebDependency -SentinelWebRuntimePath $webPath -SentinelLogicRuntimePath $runtimePath -JunctionPath $junctionPath -PathTester $dep.PathTester -NpmAdapter $dep.NpmAdapter -ProcessAdapter $dep.ProcessAdapter|Out-Null}
        Assert-True ($dep.State.InstallCount -eq 0 -and $dep.State.StopCount -eq 0) 'Repeated dependency validation was not idempotent.'
    }
    Invoke-Test '21 Development checkout remains unchanged by command policy' {
        $scenario=New-GitScenario $devPath $runtimePath
        Ensure-Local1SentinelLogicRuntime -DevelopmentPath $devPath -RuntimePath $runtimePath -GitAdapter $scenario.Adapter|Out-Null
        $unsafe=@($scenario.State.Calls|Where-Object{$_ -like "$devPath|*" -and $_ -match '\|(switch|checkout|reset|rebase|stash|clean|merge)\b'})
        Assert-True ($unsafe.Count -eq 0) 'Development checkout mutation command was issued.'
    }
    Invoke-Test '22 Sentinel Web import remains unchanged' {
        $source=Get-Content -Raw -LiteralPath 'C:\Allprojects\Sentinel Web\src\domain\crime\crimeOperationalTime.ts'
        Assert-True ($source.Contains("from 'sentinel-logic/crime/level2-governed-population'")) 'Sentinel Web governed import changed.'
    }
    Invoke-Test '23 WU-001B worktrees remain untouched' {
        $source=Get-Content -Raw -LiteralPath $modulePath
        Assert-True ($source -notmatch '(?i)wu-001b|wu001b|crime-l2-wu') 'Governance module references an evidence worktree.'
        Assert-True ($source -notmatch "'reset'|'rebase'|'stash'|'clean'") 'Prohibited Git mutation exists.'
    }
    Invoke-Test '24 Node module link must target governed junction' {
        $wrong={param($Module,$Junction) $false}
        $valid=Test-Local1SentinelLogicNodeModuleLink -ModulePath (Join-Path $webPath 'node_modules\sentinel-logic') -JunctionPath $junctionPath -NodeModuleAdapter $wrong
        Assert-True (-not $valid) 'Wrong node_modules link target was accepted.'
    }
    Invoke-Test '25 Active owned Vite reuses prior npm readiness' {
        $owned=[pscustomobject]@{ProcessId=1234;CommandLine="node $webPath\node_modules\vite --port 5173"}
        $dep=New-DependencyScenario $webPath $runtimePath -ListOutputs @('invalid') -ListExitCodes @(1) -OwnedProcesses @($owned)
        $readiness={param($Operation,$Value) $Operation -in @('MarkerValid','ProbeVite')}
        $result=Ensure-Local1SentinelWebDependency -SentinelWebRuntimePath $webPath -SentinelLogicRuntimePath $runtimePath -JunctionPath $junctionPath -PathTester $dep.PathTester -NpmAdapter $dep.NpmAdapter -ProcessAdapter $dep.ProcessAdapter -ReadinessAdapter $readiness
        Assert-True ($result.ActiveViteReused -and $result.NpmValidation -eq 'PreviouslyPassed' -and $dep.State.InstallCount -eq 0) 'Active Vite did not reuse prior validated readiness.'
    }
}
finally {
    $resolved=[IO.Path]::GetFullPath($testRoot)
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if($resolved.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved).StartsWith('local1-logic-tests-') -and (Test-Path -LiteralPath $resolved)){
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}

Write-Output ("RESULT Passed={0} Failed={1}" -f $script:Passed,$script:Failed)
if($script:Failed -gt 0){exit 1}
exit 0
