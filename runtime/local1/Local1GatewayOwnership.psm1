Set-StrictMode -Version Latest

function Test-Local1SaxioAppDocument {
    param([string]$Html)
    if ([string]::IsNullOrWhiteSpace($Html)) { return $false }
    if ($Html -notmatch '(?i)<base\s+href="/app/"\s*/?>') { return $false }
    if ($Html -notmatch '(?i)<app-root\b') { return $false }
    if ($Html -match '(?i)@vite/client') { return $false }
    if ($Html -match '(?i)<title>[^<]*Portfolio Intelligence') { return $false }
    return $true
}

function Test-Local1SentinelEntryDocument {
    param([string]$Html)
    if ([string]::IsNullOrWhiteSpace($Html)) { return $false }
    if ($Html -match '(?i)<app-root\b') { return $false }
    if ($Html -match '(?i)<base\s+href="/app/"') { return $false }
    return ($Html -match '(?i)@vite/client' -or $Html -match '(?i)Portfolio Intelligence')
}

function Test-Local1SentinelViteDocument {
    param([string]$Html)
    if ([string]::IsNullOrWhiteSpace($Html)) { return $false }
    return ($Html -match '(?i)@vite/client' -or $Html -match '(?i)<title>\s*SAXIO Portfolio Intelligence Dashboard\s*</title>')
}

function Test-Local1GatewayRootResponse {
    param([int]$StatusCode, [string]$Body)
    return ($StatusCode -eq 404 -and $Body -match 'Cannot GET /')
}

function Test-Local1GatewayServerCommandLine {
    param([string]$CommandLine)
    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $false }
    if ($CommandLine -match '(?i)vite') { return $false }
    return ($CommandLine -match '(?i)(^|[^A-Za-z0-9_])server\.js([^A-Za-z0-9_]|$)')
}

function Test-Local1MisboundSentinelViteCommandLine {
    param([string]$CommandLine)
    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $false }
    return (
        $CommandLine -match '(?i)Sentinel-Web-Runtime' -and
        $CommandLine -match '(?i)vite(\.js)?([^A-Za-z0-9_]|$)' -and
        $CommandLine -match '(?i)--port(?:=|\s+)8080([^0-9]|$)'
    )
}

function Get-Local1PortListener {
    param([int]$Port)
    $connections = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
    if ($connections.Count -eq 0) { return $null }
    $processId = [int]$connections[0].OwningProcess
    $process = Get-CimInstance Win32_Process -Filter "ProcessId=$processId" -ErrorAction SilentlyContinue
    $commandLine = ''
    if ($null -ne $process) { $commandLine = [string]$process.CommandLine }
    [pscustomobject]@{
        ProcessId = $processId
        CommandLine = $commandLine
    }
}

function Invoke-Local1HttpProbe {
    param([string]$Url, [int]$TimeoutSec = 8)
    $bodyFile = [IO.Path]::GetTempFileName()
    try {
        $code = & curl.exe -sS -o $bodyFile -w "%{http_code}" --connect-timeout 2 --max-time $TimeoutSec -H "Accept: text/html" $Url 2>$null
        $body = ''
        if (Test-Path -LiteralPath $bodyFile) {
            $body = [IO.File]::ReadAllText($bodyFile)
        }
        $text = ([string]$code).Trim()
        if ([string]::IsNullOrWhiteSpace($text) -or $text -eq '000') {
            return [pscustomobject]@{ Reachable = $false; StatusCode = 0; Body = $body }
        }
        return [pscustomobject]@{ Reachable = $true; StatusCode = [int]$text; Body = $body }
    }
    catch {
        return [pscustomobject]@{ Reachable = $false; StatusCode = 0; Body = '' }
    }
    finally {
        if (Test-Path -LiteralPath $bodyFile) { Remove-Item -LiteralPath $bodyFile -Force -ErrorAction SilentlyContinue }
    }
}

function Invoke-Local1GatewayEnsure {
    param(
        [int]$Port = 8080,
        [scriptblock]$ProbeHttp,
        [scriptblock]$GetListener,
        [scriptblock]$StopProcess
    )
    if (-not $ProbeHttp) { $ProbeHttp = { param($Url) Invoke-Local1HttpProbe -Url $Url } }
    if (-not $GetListener) { $GetListener = { param($ListenPort) Get-Local1PortListener -Port $ListenPort } }
    if (-not $StopProcess) { $StopProcess = { param($ProcessId) Stop-Process -Id $ProcessId -Force } }

    $listener = & $GetListener $Port
    if ($null -eq $listener) { return 2 }

    $root = & $ProbeHttp ("http://127.0.0.1:{0}/" -f $Port)
    if ($root.Reachable -and (Test-Local1GatewayRootResponse -StatusCode $root.StatusCode -Body $root.Body)) {
        if (Test-Local1GatewayServerCommandLine -CommandLine $listener.CommandLine) { return 0 }
        Write-Host ("Port {0} returned the gateway root response, but the listener is not local-gateway server.js." -f $Port)
        Write-Host ("Listener PID {0}: {1}" -f $listener.ProcessId, $listener.CommandLine)
        return 1
    }

    $app = & $ProbeHttp ("http://127.0.0.1:{0}/app" -f $Port)
    $viteDocument = $app.Reachable -and (Test-Local1SentinelViteDocument -Html $app.Body)
    if ($viteDocument -and (Test-Local1MisboundSentinelViteCommandLine -CommandLine $listener.CommandLine)) {
        Write-Host ("DISPLACED: Sentinel Web Vite PID {0} was bound to port {1}. Local Gateway will own the SAXIO entry point." -f $listener.ProcessId, $Port)
        & $StopProcess ([int]$listener.ProcessId)
        for ($attempt = 0; $attempt -lt 15; $attempt++) {
            $still = & $GetListener $Port
            if ($null -eq $still) { return 2 }
            Start-Sleep -Seconds 1
        }
        Write-Host "Sentinel Web Vite did not release port $Port."
        return 1
    }

    Write-Host "Port $Port is occupied by a process that is not the Local Gateway."
    Write-Host ("Listener PID {0}: {1}" -f $listener.ProcessId, $listener.CommandLine)
    return 1
}

function Invoke-Local1GatewayVerifyRoutes {
    param(
        [int]$Port = 8080,
        [scriptblock]$ProbeHttp
    )
    if (-not $ProbeHttp) { $ProbeHttp = { param($Url) Invoke-Local1HttpProbe -Url $Url } }
    $app = & $ProbeHttp ("http://127.0.0.1:{0}/app" -f $Port)
    $sentinel = & $ProbeHttp ("http://127.0.0.1:{0}/sentinel/" -f $Port)
    $ok = $true
    if ((-not $app.Reachable) -or $app.StatusCode -ne 200 -or -not (Test-Local1SaxioAppDocument -Html $app.Body)) {
        Write-Host ("FAILED SAXIO entry http://127.0.0.1:{0}/app status={1}" -f $Port, $app.StatusCode)
        $ok = $false
    }
    else {
        Write-Host ("OK SAXIO entry http://127.0.0.1:{0}/app HTTP {1}" -f $Port, $app.StatusCode)
    }
    if ((-not $sentinel.Reachable) -or $sentinel.StatusCode -ne 200 -or -not (Test-Local1SentinelEntryDocument -Html $sentinel.Body)) {
        Write-Host ("FAILED Sentinel entry http://127.0.0.1:{0}/sentinel/ status={1}" -f $Port, $sentinel.StatusCode)
        $ok = $false
    }
    else {
        Write-Host ("OK Sentinel entry http://127.0.0.1:{0}/sentinel/ HTTP {1}" -f $Port, $sentinel.StatusCode)
    }
    if ($ok) { return 0 }
    return 1
}

Export-ModuleMember -Function @(
    'Test-Local1SaxioAppDocument',
    'Test-Local1SentinelEntryDocument',
    'Test-Local1SentinelViteDocument',
    'Test-Local1GatewayRootResponse',
    'Test-Local1GatewayServerCommandLine',
    'Test-Local1MisboundSentinelViteCommandLine',
    'Get-Local1PortListener',
    'Invoke-Local1HttpProbe',
    'Invoke-Local1GatewayEnsure',
    'Invoke-Local1GatewayVerifyRoutes'
)
