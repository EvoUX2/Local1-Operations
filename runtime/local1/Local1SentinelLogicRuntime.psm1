Set-StrictMode -Version Latest

$script:DefaultRuntimeBranch = 'runtime/local1-sentinel-logic'
$script:DefaultUpstream = 'origin/main'
$script:RequiredJsExport = 'src\crime\schemas\crimeLevel2GovernedPopulation.schemas.js'
$script:RequiredTypeExport = 'src\crime\schemas\crimeLevel2GovernedPopulation.schemas.d.ts'

function Invoke-Local1Git {
    param(
        [Parameter(Mandatory)][string]$RepositoryPath,
        [Parameter(Mandatory)][string[]]$Arguments,
        [scriptblock]$GitAdapter
    )
    if ($GitAdapter) { return (& $GitAdapter $RepositoryPath $Arguments) }
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& git -C $RepositoryPath @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
        [pscustomobject]@{ ExitCode = $exitCode; Output = ($output -join [Environment]::NewLine) }
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
}

function Assert-Local1GitSuccess {
    param($Result, [string]$Code, [string]$Message)
    if ([int]$Result.ExitCode -ne 0) {
        $diagnosticMessage = if ($Result.Output) { "{0} Details: {1}" -f $Message, $Result.Output } else { $Message }
        throw ("{0}|{1}" -f $Code, $diagnosticMessage)
    }
    $Result.Output
}

function ConvertFrom-Local1AheadBehind {
    param([Parameter(Mandatory)][string]$Value)
    if ($Value.Trim() -notmatch '^(\d+)\s+(\d+)$') {
        throw 'RUNTIME_PARITY_UNREADABLE|Sentinel-Logic runtime ahead/behind state could not be calculated.'
    }
    [pscustomobject]@{ Behind = [int]$Matches[1]; Ahead = [int]$Matches[2] }
}

function Get-Local1SentinelLogicParityDecision {
    param([int]$Behind, [int]$Ahead)
    if ($Ahead -gt 0 -and $Behind -gt 0) { return 'Diverged' }
    if ($Ahead -gt 0) { return 'Ahead' }
    if ($Behind -gt 0) { return 'FastForward' }
    'Current'
}

function Resolve-Local1GitCommonDirectory {
    param([Parameter(Mandatory)][string]$RepositoryPath, [Parameter(Mandatory)][string]$GitCommonDirectory)
    $GitCommonDirectory = $GitCommonDirectory.Trim()
    if ([IO.Path]::IsPathRooted($GitCommonDirectory)) { return [IO.Path]::GetFullPath($GitCommonDirectory).TrimEnd('\') }
    [IO.Path]::GetFullPath((Join-Path $RepositoryPath $GitCommonDirectory)).TrimEnd('\')
}

function Ensure-Local1SentinelLogicRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DevelopmentPath,
        [Parameter(Mandatory)][string]$RuntimePath,
        [string]$RuntimeBranch = $script:DefaultRuntimeBranch,
        [string]$Upstream = $script:DefaultUpstream,
        [scriptblock]$GitAdapter
    )

    if (-not (Test-Path -LiteralPath $DevelopmentPath -PathType Container)) {
        throw ("DEVELOPMENT_REPOSITORY_MISSING|Sentinel-Logic development repository was not found.|{0}" -f $DevelopmentPath)
    }
    $validRepo = Invoke-Local1Git -RepositoryPath $DevelopmentPath -Arguments @('rev-parse', '--is-inside-work-tree') -GitAdapter $GitAdapter
    Assert-Local1GitSuccess $validRepo 'DEVELOPMENT_REPOSITORY_INVALID' 'Sentinel-Logic development path is not a valid Git repository.' | Out-Null

    $developmentBranchResult = Invoke-Local1Git -RepositoryPath $DevelopmentPath -Arguments @('branch', '--show-current') -GitAdapter $GitAdapter
    $developmentBranch = (Assert-Local1GitSuccess $developmentBranchResult 'DEVELOPMENT_REPOSITORY_INVALID' 'Sentinel-Logic development branch could not be read.').Trim()

    $fetch = Invoke-Local1Git -RepositoryPath $DevelopmentPath -Arguments @('fetch', 'origin', '--prune') -GitAdapter $GitAdapter
    Assert-Local1GitSuccess $fetch 'GIT_FETCH_FAILED' 'Failed to fetch origin for Sentinel-Logic.' | Out-Null

    $upstreamRef = Invoke-Local1Git -RepositoryPath $DevelopmentPath -Arguments @('show-ref', '--verify', '--quiet', "refs/remotes/$Upstream") -GitAdapter $GitAdapter
    if ([int]$upstreamRef.ExitCode -ne 0) { throw ("UPSTREAM_MISSING|Required Sentinel-Logic upstream does not exist.|{0}" -f $Upstream) }

    $created = $false
    $runtimeExists = Test-Path -LiteralPath $RuntimePath
    if (-not $runtimeExists) {
        $worktreeList = Invoke-Local1Git -RepositoryPath $DevelopmentPath -Arguments @('worktree', 'list', '--porcelain') -GitAdapter $GitAdapter
        $listed = (Assert-Local1GitSuccess $worktreeList 'WORKTREE_LIST_FAILED' 'Sentinel-Logic worktree registrations could not be read.') -match [regex]::Escape($RuntimePath.Replace('\', '/'))
        if ($listed) {
            $prune = Invoke-Local1Git -RepositoryPath $DevelopmentPath -Arguments @('worktree', 'prune') -GitAdapter $GitAdapter
            Assert-Local1GitSuccess $prune 'STALE_WORKTREE_REGISTRATION' 'Stale Sentinel-Logic runtime worktree registration could not be pruned safely.' | Out-Null
        }

        $parent = Split-Path -Parent $RuntimePath
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
        $localBranch = Invoke-Local1Git -RepositoryPath $DevelopmentPath -Arguments @('show-ref', '--verify', '--quiet', "refs/heads/$RuntimeBranch") -GitAdapter $GitAdapter
        if ([int]$localBranch.ExitCode -eq 0) {
            $add = Invoke-Local1Git -RepositoryPath $DevelopmentPath -Arguments @('worktree', 'add', $RuntimePath, $RuntimeBranch) -GitAdapter $GitAdapter
        }
        else {
            $add = Invoke-Local1Git -RepositoryPath $DevelopmentPath -Arguments @('worktree', 'add', '-b', $RuntimeBranch, $RuntimePath, $Upstream) -GitAdapter $GitAdapter
        }
        Assert-Local1GitSuccess $add 'WORKTREE_CREATE_FAILED' 'Failed to create the governed Sentinel-Logic runtime worktree.' | Out-Null
        $created = $true
    }

    if (-not (Test-Path -LiteralPath $RuntimePath -PathType Container) -and -not $GitAdapter) {
        throw ("RUNTIME_PATH_INVALID|Sentinel-Logic runtime path is not a directory.|{0}" -f $RuntimePath)
    }
    $runtimeRepo = Invoke-Local1Git -RepositoryPath $RuntimePath -Arguments @('rev-parse', '--is-inside-work-tree') -GitAdapter $GitAdapter
    Assert-Local1GitSuccess $runtimeRepo 'RUNTIME_WORKTREE_INVALID' 'Sentinel-Logic runtime path is not a valid Git worktree.' | Out-Null

    $developmentCommonResult = Invoke-Local1Git -RepositoryPath $DevelopmentPath -Arguments @('rev-parse', '--git-common-dir') -GitAdapter $GitAdapter
    $runtimeCommonResult = Invoke-Local1Git -RepositoryPath $RuntimePath -Arguments @('rev-parse', '--git-common-dir') -GitAdapter $GitAdapter
    $developmentCommon = Resolve-Local1GitCommonDirectory -RepositoryPath $DevelopmentPath -GitCommonDirectory (Assert-Local1GitSuccess $developmentCommonResult 'DEVELOPMENT_REPOSITORY_INVALID' 'Sentinel-Logic common Git directory could not be read.')
    $runtimeCommon = Resolve-Local1GitCommonDirectory -RepositoryPath $RuntimePath -GitCommonDirectory (Assert-Local1GitSuccess $runtimeCommonResult 'RUNTIME_WORKTREE_INVALID' 'Sentinel-Logic runtime common Git directory could not be read.')
    if (-not $developmentCommon.Equals($runtimeCommon, [StringComparison]::OrdinalIgnoreCase)) {
        throw ("RUNTIME_FOREIGN_WORKTREE|Sentinel-Logic runtime path belongs to a different Git repository.|{0}" -f $RuntimePath)
    }

    $branchResult = Invoke-Local1Git -RepositoryPath $RuntimePath -Arguments @('branch', '--show-current') -GitAdapter $GitAdapter
    $observedBranch = (Assert-Local1GitSuccess $branchResult 'RUNTIME_BRANCH_UNREADABLE' 'Sentinel-Logic runtime branch could not be read.').Trim()
    if ($observedBranch -ne $RuntimeBranch) {
        throw ("RUNTIME_BRANCH_INVALID|Sentinel-Logic runtime worktree is on the wrong branch.|{0}|{1}" -f $observedBranch, $RuntimeBranch)
    }

    $status = Invoke-Local1Git -RepositoryPath $RuntimePath -Arguments @('status', '--porcelain') -GitAdapter $GitAdapter
    $dirty = -not [string]::IsNullOrWhiteSpace((Assert-Local1GitSuccess $status 'RUNTIME_STATUS_FAILED' 'Sentinel-Logic runtime status could not be read.'))
    if ($dirty) { throw ("RUNTIME_DIRTY|Sentinel-Logic runtime worktree is dirty.|{0}" -f $RuntimePath) }

    $setUpstream = Invoke-Local1Git -RepositoryPath $RuntimePath -Arguments @('branch', "--set-upstream-to=$Upstream", $RuntimeBranch) -GitAdapter $GitAdapter
    Assert-Local1GitSuccess $setUpstream 'UPSTREAM_CONFIGURATION_FAILED' 'Sentinel-Logic runtime upstream could not be configured.' | Out-Null

    $parityResult = Invoke-Local1Git -RepositoryPath $RuntimePath -Arguments @('rev-list', '--left-right', '--count', "$Upstream...HEAD") -GitAdapter $GitAdapter
    $parity = ConvertFrom-Local1AheadBehind (Assert-Local1GitSuccess $parityResult 'RUNTIME_PARITY_FAILED' 'Sentinel-Logic runtime parity could not be calculated.')
    $decision = Get-Local1SentinelLogicParityDecision -Behind $parity.Behind -Ahead $parity.Ahead
    switch ($decision) {
        'Diverged' { throw ("RUNTIME_DIVERGED|Sentinel-Logic runtime branch has diverged from origin/main.|{0}|{1}" -f $parity.Behind, $parity.Ahead) }
        'Ahead' { throw ("RUNTIME_AHEAD|Sentinel-Logic runtime branch is ahead of origin/main.|{0}|{1}" -f $parity.Behind, $parity.Ahead) }
        'FastForward' {
            $merge = Invoke-Local1Git -RepositoryPath $RuntimePath -Arguments @('merge', '--ff-only', $Upstream) -GitAdapter $GitAdapter
            Assert-Local1GitSuccess $merge 'RUNTIME_FAST_FORWARD_FAILED' 'Sentinel-Logic runtime fast-forward failed.' | Out-Null
        }
    }

    $finalStatus = Invoke-Local1Git -RepositoryPath $RuntimePath -Arguments @('status', '--porcelain') -GitAdapter $GitAdapter
    if (-not [string]::IsNullOrWhiteSpace((Assert-Local1GitSuccess $finalStatus 'RUNTIME_STATUS_FAILED' 'Sentinel-Logic runtime status could not be revalidated.'))) {
        throw ("RUNTIME_DIRTY|Sentinel-Logic runtime worktree became dirty during synchronization.|{0}" -f $RuntimePath)
    }
    $finalParityResult = Invoke-Local1Git -RepositoryPath $RuntimePath -Arguments @('rev-list', '--left-right', '--count', "$Upstream...HEAD") -GitAdapter $GitAdapter
    $finalParity = ConvertFrom-Local1AheadBehind (Assert-Local1GitSuccess $finalParityResult 'RUNTIME_PARITY_FAILED' 'Sentinel-Logic runtime parity could not be revalidated.')
    if ($finalParity.Behind -ne 0 -or $finalParity.Ahead -ne 0) {
        throw ("RUNTIME_PARITY_REQUIRED|Sentinel-Logic runtime must equal origin/main.|{0}|{1}" -f $finalParity.Behind, $finalParity.Ahead)
    }

    $localShaResult = Invoke-Local1Git -RepositoryPath $RuntimePath -Arguments @('rev-parse', 'HEAD') -GitAdapter $GitAdapter
    $remoteShaResult = Invoke-Local1Git -RepositoryPath $RuntimePath -Arguments @('rev-parse', $Upstream) -GitAdapter $GitAdapter
    [pscustomobject]@{
        DevelopmentPath = $DevelopmentPath
        DevelopmentBranch = $developmentBranch
        RuntimePath = $RuntimePath
        RuntimeBranch = $observedBranch
        Upstream = $Upstream
        LocalSha = (Assert-Local1GitSuccess $localShaResult 'RUNTIME_SHA_FAILED' 'Sentinel-Logic runtime SHA could not be read.').Trim()
        RemoteSha = (Assert-Local1GitSuccess $remoteShaResult 'RUNTIME_SHA_FAILED' 'Sentinel-Logic upstream SHA could not be read.').Trim()
        Behind = 0
        Ahead = 0
        Dirty = $false
        Created = $created
    }
}

function Get-Local1JunctionState {
    param([Parameter(Mandatory)][string]$Path, [scriptblock]$FileSystemAdapter)
    if ($FileSystemAdapter) { return (& $FileSystemAdapter 'GetState' $Path $null) }
    if (-not (Test-Path -LiteralPath $Path)) { return [pscustomobject]@{ Kind = 'Missing'; Target = $null } }
    $item = Get-Item -Force -LiteralPath $Path
    if ($item.LinkType -eq 'Junction') { return [pscustomobject]@{ Kind = 'Junction'; Target = [string]@($item.Target)[0] } }
    if ($item.PSIsContainer) { return [pscustomobject]@{ Kind = 'Directory'; Target = $null } }
    [pscustomobject]@{ Kind = 'File'; Target = $null }
}

function Test-Local1PathEqual {
    param([string]$Left, [string]$Right)
    if ([string]::IsNullOrWhiteSpace($Left) -or [string]::IsNullOrWhiteSpace($Right)) { return $false }
    $leftFull = [IO.Path]::GetFullPath($Left).TrimEnd('\')
    $rightFull = [IO.Path]::GetFullPath($Right).TrimEnd('\')
    $leftFull.Equals($rightFull, [StringComparison]::OrdinalIgnoreCase)
}

function Ensure-Local1SentinelLogicJunction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$JunctionPath,
        [Parameter(Mandatory)][string]$RuntimePath,
        [scriptblock]$FileSystemAdapter
    )
    $state = Get-Local1JunctionState -Path $JunctionPath -FileSystemAdapter $FileSystemAdapter
    $created = $false
    switch ($state.Kind) {
        'Missing' {
            if ($FileSystemAdapter) { & $FileSystemAdapter 'CreateJunction' $JunctionPath $RuntimePath | Out-Null }
            else {
                New-Item -ItemType Directory -Path (Split-Path -Parent $JunctionPath) -Force | Out-Null
                New-Item -ItemType Junction -Path $JunctionPath -Target $RuntimePath -ErrorAction Stop | Out-Null
            }
            $state = Get-Local1JunctionState -Path $JunctionPath -FileSystemAdapter $FileSystemAdapter
            $created = $true
        }
        'Directory' { throw ("JUNCTION_ORDINARY_DIRECTORY|Sentinel-Logic dependency path is an ordinary directory.|{0}|{1}" -f $JunctionPath, $RuntimePath) }
        'File' { throw ("JUNCTION_FILE|Sentinel-Logic dependency path is a file.|{0}|{1}" -f $JunctionPath, $RuntimePath) }
    }
    if ($state.Kind -ne 'Junction' -or -not (Test-Local1PathEqual -Left $state.Target -Right $RuntimePath)) {
        throw ("JUNCTION_INVALID|Sentinel-Logic dependency path exists but is not the governed junction.|{0}|{1}" -f $JunctionPath, $RuntimePath)
    }
    [pscustomobject]@{ JunctionPath = $JunctionPath; JunctionTarget = $RuntimePath; Created = $created }
}

function Test-Local1SentinelLogicExports {
    param([Parameter(Mandatory)][string]$RuntimePath, [scriptblock]$PathTester)
    $tester = if ($PathTester) { $PathTester } else { { param($Path) Test-Path -LiteralPath $Path -PathType Leaf } }
    $jsPath = Join-Path $RuntimePath $script:RequiredJsExport
    $typePath = Join-Path $RuntimePath $script:RequiredTypeExport
    if (-not (& $tester $jsPath)) { throw ("PACKAGE_EXPORT_JS_MISSING|Sentinel-Logic runtime package does not contain the exported Crime Level 2 module.|{0}" -f $script:RequiredJsExport) }
    if (-not (& $tester $typePath)) { throw ("PACKAGE_EXPORT_TYPES_MISSING|Sentinel-Logic runtime package does not contain the exported Crime Level 2 type module.|{0}" -f $script:RequiredTypeExport) }
    [pscustomobject]@{ JsPath = $jsPath; TypePath = $typePath; Valid = $true }
}

function Test-Local1OwnedViteCommandLine {
    param([Parameter(Mandatory)][string]$SentinelWebRuntimePath, [string]$CommandLine)
    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $false }
    $CommandLine.ToLowerInvariant().Contains($SentinelWebRuntimePath.ToLowerInvariant()) -and
        ($CommandLine -match '(?i)vite|--port\s+5173')
}

function Get-Local1OwnedViteProcesses {
    param([Parameter(Mandatory)][string]$SentinelWebRuntimePath, [scriptblock]$ProcessAdapter)
    if ($ProcessAdapter) { return @(& $ProcessAdapter 'List' $SentinelWebRuntimePath $null) }
    @(Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" -ErrorAction SilentlyContinue | Where-Object {
        Test-Local1OwnedViteCommandLine -SentinelWebRuntimePath $SentinelWebRuntimePath -CommandLine ([string]$_.CommandLine)
    })
}

function Stop-Local1SentinelWebViteProcess {
    param([Parameter(Mandatory)][string]$SentinelWebRuntimePath, [scriptblock]$ProcessAdapter)
    $owned = @(Get-Local1OwnedViteProcesses -SentinelWebRuntimePath $SentinelWebRuntimePath -ProcessAdapter $ProcessAdapter)
    foreach ($process in $owned) {
        if ($ProcessAdapter) { & $ProcessAdapter 'Stop' $SentinelWebRuntimePath $process | Out-Null }
        else {
            $processId = [int]$process.ProcessId
            Stop-Process -Id $processId -Force -ErrorAction Stop
            Wait-Process -Id $processId -Timeout 10 -ErrorAction SilentlyContinue
        }
    }
    $owned.Count
}

function Test-Local1SentinelLogicNodeModuleLink {
    param(
        [Parameter(Mandatory)][string]$ModulePath,
        [Parameter(Mandatory)][string]$JunctionPath,
        [scriptblock]$NodeModuleAdapter
    )
    if ($NodeModuleAdapter) { return [bool](& $NodeModuleAdapter $ModulePath $JunctionPath) }
    if (-not (Test-Path -LiteralPath $ModulePath -PathType Container)) { return $false }
    $item = Get-Item -Force -LiteralPath $ModulePath
    if ($item.LinkType -notin @('Junction', 'SymbolicLink')) { return $false }
    $target = [string]@($item.Target)[0]
    Test-Local1PathEqual -Left $target -Right $JunctionPath
}

function Get-Local1DependencyReadinessValues {
    param([string]$SentinelWebRuntimePath, [string]$SentinelLogicRuntimePath, [string]$JunctionPath)
    $headResult = Invoke-Local1Git -RepositoryPath $SentinelLogicRuntimePath -Arguments @('rev-parse', 'HEAD')
    if ($headResult.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($headResult.Output)) { return $null }
    $head = $headResult.Output
    $jsPath = Join-Path $SentinelLogicRuntimePath $script:RequiredJsExport
    $typePath = Join-Path $SentinelLogicRuntimePath $script:RequiredTypeExport
    $lockPath = Join-Path $SentinelWebRuntimePath 'package-lock.json'
    if (-not (Test-Path $jsPath) -or -not (Test-Path $typePath) -or -not (Test-Path $lockPath)) { return $null }
    [ordered]@{
        RuntimeHead = $head.Trim()
        JsExportHash = Get-Local1Sha256 -Path $jsPath
        TypeExportHash = Get-Local1Sha256 -Path $typePath
        PackageLockHash = Get-Local1Sha256 -Path $lockPath
        JunctionPath = [IO.Path]::GetFullPath($JunctionPath).TrimEnd('\')
    }
}

function Get-Local1Sha256 {
    param([Parameter(Mandatory)][string]$Path)
    $stream = [IO.File]::OpenRead($Path)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        ([BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace('-', '')
    }
    finally {
        $algorithm.Dispose()
        $stream.Dispose()
    }
}

function Test-Local1DependencyReadinessMarker {
    param([string]$SentinelWebRuntimePath, [string]$SentinelLogicRuntimePath, [string]$JunctionPath, [scriptblock]$ReadinessAdapter)
    if ($ReadinessAdapter) { return [bool](& $ReadinessAdapter 'MarkerValid' $null) }
    $markerPath = Join-Path $SentinelWebRuntimePath 'node_modules\.local1-sentinel-logic-ready.json'
    if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf)) { return $false }
    try {
        $expected = Get-Local1DependencyReadinessValues $SentinelWebRuntimePath $SentinelLogicRuntimePath $JunctionPath
        if ($null -eq $expected) { return $false }
        $actual = Get-Content -Raw -LiteralPath $markerPath | ConvertFrom-Json
        foreach ($name in @('RuntimeHead','JsExportHash','TypeExportHash','PackageLockHash','JunctionPath')) {
            if ([string]$actual.$name -ne [string]$expected[$name]) { return $false }
        }
        $true
    }
    catch { $false }
}

function Save-Local1DependencyReadinessMarker {
    param([string]$SentinelWebRuntimePath, [string]$SentinelLogicRuntimePath, [string]$JunctionPath, [scriptblock]$ReadinessAdapter)
    if ($ReadinessAdapter) { & $ReadinessAdapter 'SaveMarker' $null | Out-Null; return }
    $values = Get-Local1DependencyReadinessValues $SentinelWebRuntimePath $SentinelLogicRuntimePath $JunctionPath
    if ($null -eq $values) { throw 'READINESS_MARKER_FAILED|Sentinel-Logic dependency readiness values could not be calculated.' }
    $markerPath = Join-Path $SentinelWebRuntimePath 'node_modules\.local1-sentinel-logic-ready.json'
    $values | ConvertTo-Json | Set-Content -LiteralPath $markerPath -Encoding UTF8 -ErrorAction Stop
}

function Test-Local1ViteGovernedImport {
    param([scriptblock]$ReadinessAdapter)
    if ($ReadinessAdapter) { return [bool](& $ReadinessAdapter 'ProbeVite' $null) }
    try {
        $request = [Net.HttpWebRequest]::Create('http://127.0.0.1:5173/sentinel/src/domain/crime/crimeOperationalTime.ts')
        $request.Timeout = 5000
        $response = $request.GetResponse()
        try {
            if ([int]$response.StatusCode -ne 200) { return $false }
            $reader = New-Object IO.StreamReader($response.GetResponseStream())
            try { $body = $reader.ReadToEnd() }
            finally { $reader.Dispose() }
            $body -notmatch '(?i)failed to resolve import|could not resolve|does not exist'
        }
        finally { $response.Dispose() }
    }
    catch { $false }
}

function Invoke-Local1Npm {
    param([string]$SentinelWebRuntimePath, [ValidateSet('List', 'CleanInstall')][string]$Operation, [scriptblock]$NpmAdapter)
    if ($NpmAdapter) { return (& $NpmAdapter $Operation $SentinelWebRuntimePath) }
    Push-Location $SentinelWebRuntimePath
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        if ($Operation -eq 'List') { $output = @(& npm.cmd ls sentinel-logic --depth=0 2>&1) }
        else { $output = @(& npm.cmd ci 2>&1) }
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join [Environment]::NewLine) }
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
        Pop-Location
    }
}

function Test-Local1NpmSentinelLogicListValid {
    param(
        $List,
        [bool]$ModuleExists,
        [bool]$ModuleLinkValid
    )
    if (-not $ModuleExists -or -not $ModuleLinkValid) { return $false }
    if ([int]$List.ExitCode -eq 0 -and $List.Output -notmatch '(?i)\binvalid\b') { return $true }
    # npm ls realpaths file:../Sentinel-Logic through the governed junction and
    # reports that as invalid even when the install points at the Local1 junction.
    return [bool]($List.Output -match '(?i)invalid:\s+"file:\.\./Sentinel-Logic".*Sentinel-Logic-Runtime')
}

function Ensure-Local1SentinelWebDependency {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SentinelWebRuntimePath,
        [Parameter(Mandatory)][string]$SentinelLogicRuntimePath,
        [Parameter(Mandatory)][string]$JunctionPath,
        [scriptblock]$NpmAdapter,
        [scriptblock]$ProcessAdapter,
        [scriptblock]$PathTester,
        [scriptblock]$NodeModuleAdapter,
        [scriptblock]$ReadinessAdapter
    )
    $packageJsonPath = Join-Path $SentinelWebRuntimePath 'package.json'
    if (-not (Test-Path -LiteralPath $packageJsonPath -PathType Leaf) -and -not $PathTester) { throw 'SENTINEL_WEB_PACKAGE_MISSING|Sentinel Web runtime package.json is missing.' }
    if (-not $PathTester) {
        $package = Get-Content -Raw -LiteralPath $packageJsonPath | ConvertFrom-Json
        if ([string]$package.dependencies.'sentinel-logic' -ne 'file:../Sentinel-Logic') {
            throw 'DEPENDENCY_DECLARATION_INVALID|Sentinel Web must declare sentinel-logic as file:../Sentinel-Logic.'
        }
    }
    Test-Local1SentinelLogicExports -RuntimePath $SentinelLogicRuntimePath -PathTester $PathTester | Out-Null
    $junction = Get-Local1JunctionState -Path $JunctionPath
    if ($PathTester) { $junction = [pscustomobject]@{ Kind = 'Junction'; Target = $SentinelLogicRuntimePath } }
    if ($junction.Kind -ne 'Junction' -or -not (Test-Local1PathEqual $junction.Target $SentinelLogicRuntimePath)) {
        throw ("JUNCTION_INVALID|Sentinel-Logic dependency junction is invalid.|{0}|{1}" -f $JunctionPath, $SentinelLogicRuntimePath)
    }

    $modulePath = Join-Path $SentinelWebRuntimePath 'node_modules\sentinel-logic'
    $moduleExists = if ($PathTester) { [bool](& $PathTester $modulePath) } else { Test-Path -LiteralPath $modulePath -PathType Container }
    $moduleLinkValid = if ($PathTester -and -not $NodeModuleAdapter) { $true } else { Test-Local1SentinelLogicNodeModuleLink -ModulePath $modulePath -JunctionPath $JunctionPath -NodeModuleAdapter $NodeModuleAdapter }
    $ownedAtStart = @(Get-Local1OwnedViteProcesses -SentinelWebRuntimePath $SentinelWebRuntimePath -ProcessAdapter $ProcessAdapter)
    $markerValid = if ($PathTester -and -not $ReadinessAdapter) { $false } else { Test-Local1DependencyReadinessMarker $SentinelWebRuntimePath $SentinelLogicRuntimePath $JunctionPath $ReadinessAdapter }
    if ($moduleExists -and $moduleLinkValid -and $ownedAtStart.Count -gt 0 -and $markerValid -and (Test-Local1ViteGovernedImport $ReadinessAdapter)) {
        return [pscustomobject]@{ Valid=$true;Reinstalled=$false;OwnedViteProcessesStopped=0;ModulePath=$modulePath;NpmValidation='PreviouslyPassed';ActiveViteReused=$true }
    }
    $list = Invoke-Local1Npm -SentinelWebRuntimePath $SentinelWebRuntimePath -Operation List -NpmAdapter $NpmAdapter
    $listValid = Test-Local1NpmSentinelLogicListValid -List $list -ModuleExists $moduleExists -ModuleLinkValid $moduleLinkValid
    $reinstalled = $false
    $stopped = 0
    if (-not $listValid) {
        $stopped = Stop-Local1SentinelWebViteProcess -SentinelWebRuntimePath $SentinelWebRuntimePath -ProcessAdapter $ProcessAdapter
        $install = Invoke-Local1Npm -SentinelWebRuntimePath $SentinelWebRuntimePath -Operation CleanInstall -NpmAdapter $NpmAdapter
        if ([int]$install.ExitCode -ne 0) { throw 'NPM_INSTALL_FAILED|Sentinel Web dependency installation failed.' }
        $reinstalled = $true
        $moduleExists = if ($PathTester) { [bool](& $PathTester $modulePath) } else { Test-Path -LiteralPath $modulePath -PathType Container }
        $moduleLinkValid = if ($PathTester -and -not $NodeModuleAdapter) { $true } else { Test-Local1SentinelLogicNodeModuleLink -ModulePath $modulePath -JunctionPath $JunctionPath -NodeModuleAdapter $NodeModuleAdapter }
        $list = Invoke-Local1Npm -SentinelWebRuntimePath $SentinelWebRuntimePath -Operation List -NpmAdapter $NpmAdapter
        $listValid = Test-Local1NpmSentinelLogicListValid -List $list -ModuleExists $moduleExists -ModuleLinkValid $moduleLinkValid
    }
    if (-not $listValid) { throw 'DEPENDENCY_INVALID|Sentinel Web local dependency sentinel-logic is invalid after npm installation.' }
    if (-not $PathTester -or $ReadinessAdapter) { Save-Local1DependencyReadinessMarker $SentinelWebRuntimePath $SentinelLogicRuntimePath $JunctionPath $ReadinessAdapter }
    [pscustomobject]@{ Valid = $true; Reinstalled = $reinstalled; OwnedViteProcessesStopped = $stopped; ModulePath = $modulePath; NpmValidation='PASS';ActiveViteReused=$false }
}

Export-ModuleMember -Function @(
    'ConvertFrom-Local1AheadBehind',
    'Get-Local1SentinelLogicParityDecision',
    'Resolve-Local1GitCommonDirectory',
    'Ensure-Local1SentinelLogicRuntime',
    'Get-Local1JunctionState',
    'Ensure-Local1SentinelLogicJunction',
    'Test-Local1SentinelLogicExports',
    'Test-Local1OwnedViteCommandLine',
    'Get-Local1OwnedViteProcesses',
    'Stop-Local1SentinelWebViteProcess',
    'Test-Local1SentinelLogicNodeModuleLink',
    'Test-Local1DependencyReadinessMarker',
    'Save-Local1DependencyReadinessMarker',
    'Test-Local1ViteGovernedImport',
    'Test-Local1NpmSentinelLogicListValid',
    'Ensure-Local1SentinelWebDependency'
)
