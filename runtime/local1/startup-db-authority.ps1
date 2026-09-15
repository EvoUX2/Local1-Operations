[CmdletBinding()]
param(
    [switch]$UseDockerSql,
    [switch]$AllowExternalDb,
    [switch]$LaunchPiApi,
    [string]$Repository = 'C:\Allprojects\SAXIO-Sentinel',
    [string]$EnvironmentFile = 'C:\Allprojects\SAXIO-Sentinel\runtime\local1\.env.local'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-LocalEnvironment {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Local 1 environment file is missing: $Path"
    }

    $values = [System.Collections.Generic.Dictionary[string,string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) { continue }
        $separator = $line.IndexOf('=')
        if ($separator -le 0) { continue }
        $name = $line.Substring(0, $separator).Trim()
        $value = $line.Substring($separator + 1)
        if (-not [string]::IsNullOrWhiteSpace($name)) { $values[$name] = $value }
    }
    return $values
}

function Set-DefaultEnvironmentValue {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Value)
    if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($Name, 'Process'))) {
        [Environment]::SetEnvironmentVariable($Name, $Value, 'Process')
    }
}

function Resolve-SentinelLogicRoot {
    $candidates = [System.Collections.Generic.List[string]]::new()
    $existing = [Environment]::GetEnvironmentVariable('SENTINEL_LOGIC_ROOT', 'Process')
    if (-not [string]::IsNullOrWhiteSpace($existing)) {
        [void]$candidates.Add($existing.Trim())
    }
    [void]$candidates.Add('C:\Allprojects\Local1\Sentinel-Logic')
    [void]$candidates.Add('C:\Allprojects\Sentinel-Logic')

    $contractRel = Join-Path 'src' (Join-Path 'portfolio-intelligence' (Join-Path 'contracts' 'crime.l10.early-indicator.v1.schema.json'))
    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        if (-not (Test-Path -LiteralPath $candidate -PathType Container)) { continue }
        $contractPath = Join-Path $candidate $contractRel
        if (Test-Path -LiteralPath $contractPath -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw 'SENTINEL_LOGIC_ROOT is unavailable. Governed Local1 Crime PI requires C:\Allprojects\Local1\Sentinel-Logic or C:\Allprojects\Sentinel-Logic with Crime L10 contract files. No manual fallback is authorized.'
}

try {
    $resolvedRepo = (Resolve-Path -LiteralPath $Repository).Path
    if ($resolvedRepo -match '(?i)pi-runtime-5038-restoration') {
        throw "Restoration checkout is not a governed Local1 PI source: $resolvedRepo"
    }

    $configured = Read-LocalEnvironment -Path $EnvironmentFile
    $useDocker = $UseDockerSql.IsPresent
    if ($AllowExternalDb.IsPresent -and -not $useDocker) {
        Write-Host 'NOTE: -AllowExternalDb is obsolete. 67-server SentinelStaging is the default Local1 Crime PI database.'
    }

    $connectionSource = if ($useDocker) {
        'SQL_CONNECTION_STRING'
    } else {
        'ConnectionStrings__SentinelStagingDb'
    }

    if (-not $configured.ContainsKey($connectionSource) -or [string]::IsNullOrWhiteSpace($configured[$connectionSource])) {
        throw "$connectionSource is required in $EnvironmentFile"
    }

    $connectionString = $configured[$connectionSource]
    $builder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new($connectionString)
    $dataSource = $builder.DataSource
    $database = $builder.InitialCatalog
    if ([string]::IsNullOrWhiteSpace($dataSource)) { throw 'The selected connection string has no Server/Data Source.' }
    if ([string]::IsNullOrWhiteSpace($database)) { throw 'The selected connection string has no Database/Initial Catalog.' }

    $serverToken = $dataSource.Trim()
    if ($serverToken.StartsWith('tcp:', [System.StringComparison]::OrdinalIgnoreCase)) {
        $serverToken = $serverToken.Substring(4)
    }
    $serverParts = $serverToken.Split(@(','), 2, [System.StringSplitOptions]::None)
    $serverHost = $serverParts[0].Trim()
    $serverPortToken = if ($serverParts.Count -eq 2) { $serverParts[1].Trim() } else { $null }
    $serverPort = if ($serverPortToken -match '^\d+$') { [int]$serverPortToken } else { 1433 }

    if (-not $database.Equals('SentinelStaging', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Database must be SentinelStaging. Selected database: $database"
    }

    if ($useDocker) {
        $localHosts = @('localhost', '127.0.0.1', '::1', '(local)')
        $isLocal = $localHosts -contains $serverHost.ToLowerInvariant()
        if (-not $isLocal -or $serverPort -ne 14333) {
            throw "Docker SQL override selected. Expected localhost,14333 / SentinelStaging. Selected server: $dataSource"
        }
    } else {
        if (-not $serverHost.Equals('67.225.176.136', [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Canonical Local1 Crime PI database is 67.225.176.136 / SentinelStaging. Selected server: $dataSource. Use -UseDockerSql for the secondary Docker substrate."
        }
    }

    $tcp = [System.Net.Sockets.TcpClient]::new()
    try {
        $connect = $tcp.ConnectAsync($serverHost, $serverPort)
        if (-not $connect.Wait([TimeSpan]::FromSeconds(8)) -or -not $tcp.Connected) {
            throw "SQL endpoint is not reachable: ${serverHost}:$serverPort"
        }
    } finally {
        $tcp.Dispose()
    }

    $requiredObjects = @(
        'pi.fact_incident',
        'pi.dim_property',
        'pi.dim_reporting_set',
        'pi.bridge_incident_reporting_set',
        'pi.bridge_incident_case_file',
        'pi.isci_taxonomy_node',
        'pi.isci_taxonomy_version'
    )
    $sqlConnection = [System.Data.SqlClient.SqlConnection]::new($connectionString)
    try {
        $sqlConnection.Open()
        $command = $sqlConnection.CreateCommand()
        $command.CommandTimeout = 10
        $command.CommandText = @'
SET NOCOUNT ON;
SELECT required.object_name
FROM (VALUES
    (N'pi.fact_incident'),
    (N'pi.dim_property'),
    (N'pi.dim_reporting_set'),
    (N'pi.bridge_incident_reporting_set'),
    (N'pi.bridge_incident_case_file'),
    (N'pi.isci_taxonomy_node'),
    (N'pi.isci_taxonomy_version')
) required(object_name)
WHERE OBJECT_ID(required.object_name, N'U') IS NULL;
'@
        $missing = [System.Collections.Generic.List[string]]::new()
        $reader = $command.ExecuteReader()
        try {
            while ($reader.Read()) { [void]$missing.Add($reader.GetString(0)) }
        } finally {
            $reader.Dispose()
            $command.Dispose()
        }
        if ($missing.Count -gt 0) {
            throw "Governed Crime/ISCI substrate is incomplete. Missing: $($missing -join ', ')."
        }
    } finally {
        $sqlConnection.Dispose()
    }

    $logicRoot = Resolve-SentinelLogicRoot
    $headSha = (git -C $resolvedRepo rev-parse HEAD).Trim()
    if ([string]::IsNullOrWhiteSpace($headSha)) {
        throw "SAXIO-Sentinel HEAD SHA is unavailable at $resolvedRepo"
    }

    Write-Host ''
    Write-Host 'PI Database Authority'
    Write-Host "  Server               : ${serverHost}:$serverPort"
    Write-Host "  Database             : $database"
    Write-Host "  Connection source    : $connectionSource"
    Write-Host "  Canonical target     : 67.225.176.136 / SentinelStaging"
    Write-Host "  Docker SQL override  : $($useDocker)"
    Write-Host "  Configuration source : $EnvironmentFile"
    Write-Host "  Repository           : $resolvedRepo"
    Write-Host "  HEAD SHA             : $headSha"
    Write-Host "  SENTINEL_LOGIC_ROOT  : $logicRoot"
    Write-Host '  Crime+ISCI substrate : VALID'
    foreach ($requiredObject in $requiredObjects) { Write-Host "    [OK] $requiredObject" }
    Write-Host ''

    if (-not $LaunchPiApi) { exit 0 }

    if (-not (Test-Path -LiteralPath $resolvedRepo -PathType Container)) {
        throw "SAXIO-Sentinel repository is missing: $resolvedRepo"
    }

    foreach ($entry in $configured.GetEnumerator()) {
        [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process')
    }

    [Environment]::SetEnvironmentVariable('ConnectionStrings__SaxioDb', $connectionString, 'Process')
    [Environment]::SetEnvironmentVariable('ConnectionStrings__SentinelStaging', $connectionString, 'Process')
    [Environment]::SetEnvironmentVariable('ConnectionStrings__SentinelStagingDb', $connectionString, 'Process')
    [Environment]::SetEnvironmentVariable('SENTINEL_LOGIC_ROOT', $logicRoot, 'Process')

    Set-DefaultEnvironmentValue -Name 'ASPNETCORE_ENVIRONMENT' -Value 'Development'
    Set-DefaultEnvironmentValue -Name 'DOTNET_ENVIRONMENT' -Value 'Development'
    Set-DefaultEnvironmentValue -Name 'PortfolioIntelligence__ComputeMode' -Value 'Database'
    Set-DefaultEnvironmentValue -Name 'SAXIO_DB_ENABLED' -Value 'true'
    Set-DefaultEnvironmentValue -Name 'SAXIO_DB_ANALYTICS_ENABLED' -Value 'true'
    Set-DefaultEnvironmentValue -Name 'SaxioAuth__Enabled' -Value 'true'

    $mappingDefaults = [ordered]@{
        'SaxioCrimeDbMapping__IncidentSource__Schema' = 'pi'
        'SaxioCrimeDbMapping__IncidentSource__Name' = 'fact_incident'
        'SaxioCrimeDbMapping__IncidentColumns__OccurredAt' = 'occurred_at_utc'
        'SaxioCrimeDbMapping__IncidentColumns__PropertyId' = 'property_id'
        'SaxioCrimeDbMapping__IncidentColumns__IncidentId' = 'incident_id'
        'SaxioCrimeDbMapping__IncidentColumns__ReportingSetId' = 'reporting_set_id'
        'SaxioCrimeDbMapping__IncidentColumns__PortfolioId' = 'portfolio_id'
        'SaxioCrimeDbMapping__IncidentColumns__WorkgroupId' = 'workgroup_id'
        'SaxioCrimeDbMapping__PropertySource__Schema' = 'pi'
        'SaxioCrimeDbMapping__PropertySource__Name' = 'dim_property'
        'SaxioCrimeDbMapping__PropertyColumns__PropertyId' = 'property_id'
        'SaxioCrimeDbMapping__PropertyColumns__PropertyName' = 'property_name'
        'SaxioCrimeDbMapping__PropertyColumns__PortfolioId' = 'portfolio_id'
        'SaxioCrimeDbMapping__PropertyColumns__WorkgroupId' = 'workgroup_id'
    }
    foreach ($mapping in $mappingDefaults.GetEnumerator()) {
        Set-DefaultEnvironmentValue -Name $mapping.Key -Value $mapping.Value
    }

    if ([string]::IsNullOrWhiteSpace($env:SaxioAuth__EvoTokenValidationUrl)) {
        throw 'SaxioAuth__EvoTokenValidationUrl is required in the Local 1 environment file.'
    }
    if ([string]::IsNullOrWhiteSpace($env:SaxioAuth__EvoCurrentUserScopeUrl)) {
        throw 'SaxioAuth__EvoCurrentUserScopeUrl is required in the Local 1 environment file.'
    }

    $logPath = Join-Path $PSScriptRoot 'last-pi-launch.log'
    @(
        '[OK] Governed PI database authority validated.',
        "[OK] Server=${serverHost}:$serverPort;Database=$database",
        "[OK] ConnectionSource=$connectionSource",
        "[OK] CanonicalTarget=67.225.176.136/SentinelStaging",
        "[OK] UseDockerSql=$useDocker",
        "[OK] ConfigurationSource=$EnvironmentFile",
        "[OK] Repository=$resolvedRepo",
        "[OK] HeadSha=$headSha",
        "[OK] SentinelLogicRoot=$logicRoot"
    ) | Set-Content -LiteralPath $logPath

    Write-Host 'Starting PI API on http://127.0.0.1:5038'
    Push-Location $resolvedRepo
    try {
        & dotnet run --no-launch-profile --project 'services\portfolio-intelligence-api\Saxio.Sentinel.PortfolioIntelligence.Api.csproj' --urls 'http://127.0.0.1:5038'
        exit $LASTEXITCODE
    } finally {
        Pop-Location
    }
} catch {
    Write-Host ''
    Write-Host 'ERROR' -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ''
    exit 1
}
