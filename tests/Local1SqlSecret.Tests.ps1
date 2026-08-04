$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $repositoryRoot 'runtime\local1\Local1SqlSecret.psm1'
$wrapperPath = Join-Path $repositoryRoot 'runtime\local1\Start-Local1Sql.ps1'
$launcherPath = Join-Path $repositoryRoot 'Start-Local1.cmd'
Import-Module $modulePath -Force

$script:Passed = 0
$script:Failed = 0
$script:OriginalProcessSecret = [Environment]::GetEnvironmentVariable('MSSQL_SA_PASSWORD', 'Process')

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function New-TestSecret {
    New-Local1SqlSecret
}

function New-DockerAdapter {
    param([bool]$Available = $true, [bool]$Container, [bool]$Volume, [string]$ContainerSecret)
    $availableValue = $Available
    $containerValue = $Container
    $volumeValue = $Volume
    $secretValue = $ContainerSecret
    {
        param($Operation, $Name)
        switch ($Operation) {
            'Available' { $availableValue }
            'ContainerExists' { $containerValue }
            'VolumeExists' { $volumeValue }
            'ContainerSecret' { $secretValue }
            default { throw "Unexpected Docker operation: $Operation" }
        }
    }.GetNewClosure()
}

function New-EnvironmentReader {
    param([string]$ProcessSecret, [string]$UserSecret)
    $processValue = $ProcessSecret
    $userValue = $UserSecret
    {
        param($Name, $Target)
        if ($Target -eq 'Process') { return $processValue }
        if ($Target -eq 'User') { return $userValue }
        $null
    }.GetNewClosure()
}

function Invoke-Test {
    param([string]$Name, [scriptblock]$Test)
    try {
        [Environment]::SetEnvironmentVariable('MSSQL_SA_PASSWORD', $null, 'Process')
        & $Test
        $script:Passed++
        Write-Output "PASS $Name"
    }
    catch {
        $script:Failed++
        Write-Output "FAIL $Name - $($_.Exception.Message)"
    }
    finally {
        [Environment]::SetEnvironmentVariable('MSSQL_SA_PASSWORD', $null, 'Process')
    }
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('local1-sql-tests-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null

try {
    Invoke-Test '1 Process environment exists' {
        $secret = New-TestSecret
        $result = Resolve-Local1SqlSecret -SecureStorePath (Join-Path $testRoot '1.dpapi') -DockerAdapter (New-DockerAdapter) -EnvironmentReader (New-EnvironmentReader -ProcessSecret $secret)
        Assert-True ($result.Source -eq 'ProcessEnvironment') 'Process environment was not selected.'
    }

    Invoke-Test '2 User environment exists' {
        $secret = New-TestSecret
        $result = Resolve-Local1SqlSecret -SecureStorePath (Join-Path $testRoot '2.dpapi') -DockerAdapter (New-DockerAdapter) -EnvironmentReader (New-EnvironmentReader -UserSecret $secret)
        Assert-True ($result.Source -eq 'UserEnvironment') 'User environment was not selected.'
    }

    Invoke-Test '3 Secure-store secret exists' {
        $secret = New-TestSecret
        $path = Join-Path $testRoot '3.dpapi'
        Save-Local1SqlSecretSecurely -Secret $secret -Path $path | Out-Null
        $result = Resolve-Local1SqlSecret -SecureStorePath $path -DockerAdapter (New-DockerAdapter) -EnvironmentReader (New-EnvironmentReader)
        Assert-True ($result.Source -eq 'SecureStore') 'Secure store was not selected.'
    }

    Invoke-Test '4 Ignored env file exists' {
        $secret = New-TestSecret
        $envPath = Join-Path $testRoot 'ignored.env'
        Set-Content -LiteralPath $envPath -Value ("MSSQL_SA_PASSWORD={0}" -f $secret) -NoNewline
        $result = Resolve-Local1SqlSecret -SecureStorePath (Join-Path $testRoot '4.dpapi') -IgnoredEnvFilePath $envPath -DockerAdapter (New-DockerAdapter) -EnvironmentReader (New-EnvironmentReader)
        Assert-True ($result.Source -eq 'IgnoredEnvFile') 'Ignored env file was not selected.'
    }

    Invoke-Test '5 Existing container credential migrates' {
        $secret = New-TestSecret
        $result = Resolve-Local1SqlSecret -SecureStorePath (Join-Path $testRoot '5.dpapi') -DockerAdapter (New-DockerAdapter -Container $true -Volume $true -ContainerSecret $secret) -EnvironmentReader (New-EnvironmentReader)
        Assert-True ($result.Source -eq 'ExistingContainerMigration' -and $result.Persisted) 'Container credential was not migrated.'
    }

    Invoke-Test '6 Existing container credential is never printed' {
        $secret = New-TestSecret
        $output = Resolve-Local1SqlSecret -SecureStorePath (Join-Path $testRoot '6.dpapi') -DockerAdapter (New-DockerAdapter -Container $true -Volume $true -ContainerSecret $secret) -EnvironmentReader (New-EnvironmentReader) | Out-String
        Assert-True (-not $output.Contains($secret)) 'Credential appeared in resolver output.'
    }

    Invoke-Test '7 Existing volume without credential fails closed' {
        $failedClosed = $false
        try { Resolve-Local1SqlSecret -SecureStorePath (Join-Path $testRoot '7.dpapi') -DockerAdapter (New-DockerAdapter -Volume $true) -EnvironmentReader (New-EnvironmentReader) | Out-Null }
        catch { $failedClosed = $_.Exception.Message.StartsWith('UNRECOVERABLE_EXISTING_DATA|') }
        Assert-True $failedClosed 'Existing-volume state did not fail closed.'
    }

    Invoke-Test '8 New environment generates a credential' {
        $result = Resolve-Local1SqlSecret -SecureStorePath (Join-Path $testRoot '8.dpapi') -DockerAdapter (New-DockerAdapter) -EnvironmentReader (New-EnvironmentReader)
        Assert-True ($result.Source -eq 'GeneratedNewEnvironment') 'New environment did not generate a credential.'
    }

    Invoke-Test '9 Generated credential satisfies SQL complexity' {
        1..25 | ForEach-Object { Assert-True (Test-Local1SqlPasswordComplexity -Secret (New-Local1SqlSecret)) 'Generated credential failed complexity.' }
    }

    Invoke-Test '10 Generated credential is securely persisted' {
        $path = Join-Path $testRoot '10.dpapi'
        $result = Resolve-Local1SqlSecret -SecureStorePath $path -DockerAdapter (New-DockerAdapter) -EnvironmentReader (New-EnvironmentReader)
        $stored = Get-Content -Raw -LiteralPath $path
        Assert-True ($result.Persisted -and $stored -notmatch '^L1!') 'Credential was not persisted as DPAPI ciphertext.'
    }

    Invoke-Test '11 Second run reuses secure credential' {
        $path = Join-Path $testRoot '11.dpapi'
        $first = Resolve-Local1SqlSecret -SecureStorePath $path -DockerAdapter (New-DockerAdapter) -EnvironmentReader (New-EnvironmentReader)
        $firstValue = $env:MSSQL_SA_PASSWORD
        [Environment]::SetEnvironmentVariable('MSSQL_SA_PASSWORD', $null, 'Process')
        $second = Resolve-Local1SqlSecret -SecureStorePath $path -DockerAdapter (New-DockerAdapter) -EnvironmentReader (New-EnvironmentReader)
        Assert-True ($second.Source -eq 'SecureStore' -and $env:MSSQL_SA_PASSWORD -eq $firstValue) 'Second run did not reuse the secure credential.'
    }

    Invoke-Test '12 Missing secret does not blame Docker Desktop' {
        $text = Get-Content -Raw -LiteralPath $launcherPath
        Assert-True ($text -notmatch 'Docker SQL failed to start') 'Legacy misleading Docker failure remains.'
    }

    Invoke-Test '13 Docker unavailable is classified' {
        $classified = $false
        try { Resolve-Local1SqlSecret -SecureStorePath (Join-Path $testRoot '13.dpapi') -DockerAdapter (New-DockerAdapter -Available $false) -EnvironmentReader (New-EnvironmentReader) | Out-Null }
        catch { $classified = $_.Exception.Message.StartsWith('DOCKER_UNAVAILABLE|') }
        Assert-True $classified 'Docker-unavailable state was not classified.'
    }

    Invoke-Test '14 Compose failure follows credential resolution' {
        $env:MSSQL_SA_PASSWORD = New-TestSecret
        $classified = $false
        try { Start-Local1SqlDocker -RepositoryPath $testRoot -ComposeInvoker { param($Path) 9 } | Out-Null }
        catch { $classified = $_.Exception.Message.StartsWith('COMPOSE_FAILED|') }
        Assert-True $classified 'Compose failure was not classified.'
    }

    Invoke-Test '15 No plaintext secret file is created' {
        $path = Join-Path $testRoot '15.dpapi'
        $result = Resolve-Local1SqlSecret -SecureStorePath $path -DockerAdapter (New-DockerAdapter) -EnvironmentReader (New-EnvironmentReader)
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $testRoot '.env.sqlserver'))) 'A plaintext .env.sqlserver file was created.'
    }

    Invoke-Test '16 Secret does not appear in status or errors' {
        $secret = New-TestSecret
        $output = Resolve-Local1SqlSecret -SecureStorePath (Join-Path $testRoot '16.dpapi') -DockerAdapter (New-DockerAdapter) -EnvironmentReader (New-EnvironmentReader -ProcessSecret $secret) | Format-List * | Out-String
        Assert-True (-not $output.Contains($secret)) 'Secret appeared in structured status.'
    }

    Invoke-Test '17 Credential conflict fails closed' {
        $classified = $false
        try { Resolve-Local1SqlSecret -SecureStorePath (Join-Path $testRoot '17.dpapi') -DockerAdapter (New-DockerAdapter -Container $true -Volume $true -ContainerSecret (New-TestSecret)) -EnvironmentReader (New-EnvironmentReader -ProcessSecret (New-TestSecret)) | Out-Null }
        catch { $classified = $_.Exception.Message.StartsWith('CREDENTIAL_CONFLICT|') }
        Assert-True $classified 'Credential conflict did not fail closed.'
    }

    Invoke-Test '18 Container and volume deletion operations are absent' {
        $source = Get-Content -Raw -LiteralPath $modulePath
        Assert-True ($source -notmatch 'compose\s+down|volume\s+(?:rm|remove)|container\s+(?:rm|remove)') 'Destructive Docker operation found.'
    }

    Invoke-Test '19 Startup resolution is idempotent' {
        $path = Join-Path $testRoot '19.dpapi'
        $script:generationCount = 0
        $generator = { $script:generationCount++; New-Local1SqlSecret }
        Resolve-Local1SqlSecret -SecureStorePath $path -DockerAdapter (New-DockerAdapter) -EnvironmentReader (New-EnvironmentReader) -SecretGenerator $generator | Out-Null
        [Environment]::SetEnvironmentVariable('MSSQL_SA_PASSWORD', $null, 'Process')
        Resolve-Local1SqlSecret -SecureStorePath $path -DockerAdapter (New-DockerAdapter) -EnvironmentReader (New-EnvironmentReader) -SecretGenerator $generator | Out-Null
        $launcher = Get-Content -Raw -LiteralPath $launcherPath
        Assert-True ($script:generationCount -eq 1) 'A second credential was generated.'
        Assert-True (($launcher | Select-String -Pattern 'REUSED:' -AllMatches).Matches.Count -ge 5) 'Healthy service reuse guards are missing.'
    }

    Invoke-Test '20 Validation-only mode resolves without Compose' {
        $text = Get-Content -Raw -LiteralPath $wrapperPath
        Assert-True ($text -match 'if \(\$ValidateOnly\)' -and $text -match 'exit 0') 'Validation-only path is missing.'
        Assert-True ($text.IndexOf('if ($ValidateOnly)') -lt $text.IndexOf('Start-Local1SqlDocker')) 'Validation-only path does not exit before Compose.'
    }

    Invoke-Test '21 Unreadable store is replaced only from established container' {
        $path = Join-Path $testRoot '21.dpapi'
        Set-Content -LiteralPath $path -Value 'not-dpapi-ciphertext' -NoNewline
        $secret = New-TestSecret
        $result = Resolve-Local1SqlSecret -SecureStorePath $path -DockerAdapter (New-DockerAdapter -Container $true -Volume $true -ContainerSecret $secret) -EnvironmentReader (New-EnvironmentReader)
        $stored = Get-Content -Raw -LiteralPath $path
        Assert-True ($result.Source -eq 'ExistingContainerMigration' -and -not $stored.Contains($secret)) 'Unreadable store recovery was not container-authoritative and encrypted.'
    }
}
finally {
    [Environment]::SetEnvironmentVariable('MSSQL_SA_PASSWORD', $script:OriginalProcessSecret, 'Process')
    $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
    $resolvedSystemTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($resolvedTestRoot.StartsWith($resolvedSystemTemp, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedTestRoot).StartsWith('local1-sql-tests-') -and
        (Test-Path -LiteralPath $resolvedTestRoot)) {
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}

Write-Output ("RESULT Passed={0} Failed={1}" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
exit 0
