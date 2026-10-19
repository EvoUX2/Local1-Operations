$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $repositoryRoot 'runtime\local1\Local1GatewayOwnership.psm1'
$entryPath = Join-Path $repositoryRoot 'runtime\local1\Invoke-Local1GatewayOwnership.ps1'
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

$saxioHtml = @'
<title>EvoUX</title>
<base href="/app/">
<app-root></app-root>
'@
$viteHtml = @'
<script type="module" src="/@vite/client"></script>
<title>SAXIO Portfolio Intelligence Dashboard</title>
<div class="loading-indicator">Loading Portfolio Intelligence...</div>
'@
$gatewayRoot = '<pre>Cannot GET /</pre>'
$sentinelHtml = @'
<script type="module" src="/sentinel/@vite/client"></script>
<title>SAXIO Portfolio Intelligence Dashboard</title>
'@
$misboundCommand = '"node" "C:\Allprojects\Local1\Sentinel-Web-Runtime\node_modules\vite\bin\vite.js" --host 127.0.0.1 --port 8080'
$governedSentinelCommand = '"node" "C:\Allprojects\Local1\Sentinel-Web-Runtime\node_modules\vite\bin\vite.js" --port 5173 --strictPort'
$launcher = Get-Content -Raw -LiteralPath $launcherPath

try {
    Invoke-Test '1 SAXIO /app document is recognized' {
        Assert-True (Test-Local1SaxioAppDocument -Html $saxioHtml) 'SAXIO document was rejected.'
    }
    Invoke-Test '2 Sentinel Vite document is not the SAXIO entry' {
        Assert-True (-not (Test-Local1SaxioAppDocument -Html $viteHtml)) 'Portfolio Intelligence HTML was accepted as SAXIO.'
    }
    Invoke-Test '3 Gateway root 404 identifies local-gateway' {
        Assert-True (Test-Local1GatewayRootResponse -StatusCode 404 -Body $gatewayRoot) 'Express gateway root was rejected.'
        Assert-True (-not (Test-Local1GatewayRootResponse -StatusCode 200 -Body $viteHtml)) 'Vite HTTP 200 was accepted as the gateway root.'
    }
    Invoke-Test '4 Sentinel entry is distinct from SAXIO /app' {
        Assert-True (Test-Local1SentinelEntryDocument -Html $sentinelHtml) 'Sentinel document was rejected.'
        Assert-True (-not (Test-Local1SentinelEntryDocument -Html $saxioHtml)) 'SAXIO document was accepted as Sentinel.'
    }
    Invoke-Test '5 Misbound Sentinel Vite on 8080 is recognized' {
        Assert-True (Test-Local1MisboundSentinelViteCommandLine -CommandLine $misboundCommand) 'Known misbound Vite command was not recognized.'
        Assert-True (-not (Test-Local1MisboundSentinelViteCommandLine -CommandLine $governedSentinelCommand)) 'Governed Vite on 5173 was classified as the 8080 misbinding.'
        Assert-True (-not (Test-Local1GatewayServerCommandLine -CommandLine $misboundCommand)) 'Vite command was classified as local-gateway.'
    }
    Invoke-Test '6 local-gateway server.js command is the gateway owner' {
        Assert-True (Test-Local1GatewayServerCommandLine -CommandLine 'node server.js') 'node server.js was not accepted as the gateway.'
        Assert-True (Test-Local1GatewayServerCommandLine -CommandLine '"node" "C:\Allprojects\local-gateway\server.js"') 'Full gateway path was not accepted.'
        Assert-True (-not (Test-Local1GatewayServerCommandLine -CommandLine 'node C:\Other\app.js')) 'Unrelated Node process was accepted as the gateway.'
    }
    Invoke-Test '7 Ensure reuses a live gateway' {
        $probe = { param($Url) [pscustomobject]@{ Reachable = $true; StatusCode = 404; Body = '<pre>Cannot GET /</pre>' } }
        $listener = { param($ListenPort) [pscustomobject]@{ ProcessId = 11; CommandLine = 'node server.js' } }
        $code = Invoke-Local1GatewayEnsure -Port 8080 -ProbeHttp $probe -GetListener $listener -StopProcess { param($ProcessId) throw 'reuse path stopped a process' }
        Assert-True ($code -eq 0) "Expected reuse exit 0, got $code."
    }
    Invoke-Test '8 Ensure displaces misbound Sentinel Vite and asks for gateway start' {
        $state = [pscustomobject]@{ Stopped = $false }
        $probe = {
            param($Url)
            if ($Url -like '*/app') {
                return [pscustomobject]@{ Reachable = $true; StatusCode = 200; Body = $viteHtml }
            }
            return [pscustomobject]@{ Reachable = $true; StatusCode = 200; Body = $viteHtml }
        }
        $listener = {
            param($ListenPort)
            if ($state.Stopped) { return $null }
            [pscustomobject]@{ ProcessId = 70620; CommandLine = $misboundCommand }
        }
        $stop = { param($ProcessId) if ($ProcessId -ne 70620) { throw "stopped unexpected pid $ProcessId" }; $state.Stopped = $true }
        $code = Invoke-Local1GatewayEnsure -Port 8080 -ProbeHttp $probe -GetListener $listener -StopProcess $stop
        Assert-True ($code -eq 2 -and $state.Stopped) "Expected displace exit 2, got $code stopped=$($state.Stopped)."
    }
    Invoke-Test '9 Ensure fails closed for an unrelated 8080 listener' {
        $probe = { param($Url) [pscustomobject]@{ Reachable = $true; StatusCode = 200; Body = '<html>other</html>' } }
        $listener = { param($ListenPort) [pscustomobject]@{ ProcessId = 9; CommandLine = 'node C:\Other\app.js --port 8080' } }
        $code = Invoke-Local1GatewayEnsure -Port 8080 -ProbeHttp $probe -GetListener $listener -StopProcess { param($ProcessId) throw 'unrelated listener was stopped' }
        Assert-True ($code -eq 1) "Expected fail-closed exit 1, got $code."
    }
    Invoke-Test '10 Ensure starts the gateway when 8080 is free' {
        $listener = { param($ListenPort) $null }
        $code = Invoke-Local1GatewayEnsure -Port 8080 -ProbeHttp { param($Url) throw 'probed a free port' } -GetListener $listener -StopProcess { param($ProcessId) throw 'stopped a free port' }
        Assert-True ($code -eq 2) "Expected start exit 2, got $code."
    }
    Invoke-Test '11 VerifyRoutes accepts SAXIO /app and Sentinel /sentinel' {
        $probe = {
            param($Url)
            if ($Url -like '*/app') { return [pscustomobject]@{ Reachable = $true; StatusCode = 200; Body = $saxioHtml } }
            return [pscustomobject]@{ Reachable = $true; StatusCode = 200; Body = $sentinelHtml }
        }
        $code = Invoke-Local1GatewayVerifyRoutes -Port 8080 -ProbeHttp $probe
        Assert-True ($code -eq 0) "Expected route verification exit 0, got $code."
    }
    Invoke-Test '12 VerifyRoutes rejects Sentinel HTML on /app' {
        $probe = {
            param($Url)
            if ($Url -like '*/app') { return [pscustomobject]@{ Reachable = $true; StatusCode = 200; Body = $viteHtml } }
            return [pscustomobject]@{ Reachable = $true; StatusCode = 200; Body = $sentinelHtml }
        }
        $code = Invoke-Local1GatewayVerifyRoutes -Port 8080 -ProbeHttp $probe
        Assert-True ($code -eq 1) "Expected route verification exit 1, got $code."
    }
    Invoke-Test '13 Launcher identifies gateway ownership before using port 8080' {
        Assert-True (Test-Path -LiteralPath $entryPath) 'Ownership entry script is missing.'
        Assert-True ($launcher.Contains('Invoke-Local1GatewayOwnership.ps1')) 'Launcher does not call the ownership guard.'
        Assert-True ($launcher.Contains('-Mode Ensure -Port 8080')) 'Launcher does not ensure gateway ownership of port 8080.'
        Assert-True ($launcher.Contains('-Mode VerifyRoutes -Port 8080')) 'Launcher does not verify SAXIO and Sentinel routes.'
        Assert-True ($launcher.Contains('REUSED: Local Gateway owns port 8080.')) 'Launcher lost the gateway-owner reuse message.'
        Assert-True ($launcher -notmatch 'REUSED: Local Gateway is already healthy') 'Launcher still reuses any HTTP listener on port 8080.'
        Assert-True ($launcher -notmatch 'is_http_ready "http://localhost:8080"') 'Launcher still treats any HTTP response on 8080 as the gateway.'
        Assert-True ($launcher.Contains('--port 5173 --strictPort')) 'Sentinel Web is no longer pinned to port 5173.'
        Assert-True ($launcher -notmatch 'vite --host 127\.0\.0\.1 --port 8080') 'Launcher starts Sentinel Vite on port 8080.'
    }
}
finally { }

Write-Output ("RESULT Passed={0} Failed={1}" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
exit 0
