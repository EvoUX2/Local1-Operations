Set-StrictMode -Version Latest

if (-not ('System.Security.Cryptography.ProtectedData' -as [type])) {
    [void][Reflection.Assembly]::LoadWithPartialName('System.Security')
}

$script:SecretFileName = 'mssql-sa-password.dpapi'
$script:DefaultContainerName = 'sentinel-staging-sql'
$script:DefaultVolumeName = 'saxio-sentinel_sentinel_sql_data'

function Get-Local1SqlDefaultSecretPath {
    $localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    Join-Path $localAppData "SAXIO\Local1\secrets\$script:SecretFileName"
}

function Invoke-Local1Docker {
    param(
        [Parameter(Mandatory)][ValidateSet('Available', 'ContainerExists', 'VolumeExists', 'ContainerSecret')][string]$Operation,
        [string]$Name
    )

    switch ($Operation) {
        'Available' {
            & docker info --format '{{.ServerVersion}}' 2>$null | Out-Null
            return $LASTEXITCODE -eq 0
        }
        'ContainerExists' {
            $names = @(& docker ps -a --filter "name=^/$Name$" --format '{{.Names}}' 2>$null)
            if ($LASTEXITCODE -ne 0) { throw 'DOCKER_UNAVAILABLE|Docker Engine could not be queried.' }
            return $names -contains $Name
        }
        'VolumeExists' {
            $names = @(& docker volume ls --filter "name=^$Name$" --format '{{.Name}}' 2>$null)
            if ($LASTEXITCODE -ne 0) { throw 'DOCKER_UNAVAILABLE|Docker Engine could not be queried.' }
            return $names -contains $Name
        }
        'ContainerSecret' {
            $json = (& docker inspect $Name 2>$null) -join [Environment]::NewLine
            if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($json)) { return $null }
            try {
                $container = ($json | ConvertFrom-Json)[0]
                foreach ($entry in @($container.Config.Env)) {
                    if ($entry -match '^(?:MSSQL_SA_PASSWORD|SA_PASSWORD)=(.*)$') {
                        return $Matches[1]
                    }
                }
            }
            catch {
                throw 'CONTAINER_INSPECTION_FAILED|Existing SQL container metadata could not be inspected safely.'
            }
            return $null
        }
    }
}

function Test-Local1SqlContainerExists {
    param(
        [string]$ContainerName = $script:DefaultContainerName,
        [scriptblock]$DockerAdapter
    )
    if ($DockerAdapter) { return [bool](& $DockerAdapter 'ContainerExists' $ContainerName) }
    [bool](Invoke-Local1Docker -Operation ContainerExists -Name $ContainerName)
}

function Test-Local1SqlVolumeExists {
    param(
        [string]$VolumeName = $script:DefaultVolumeName,
        [scriptblock]$DockerAdapter
    )
    if ($DockerAdapter) { return [bool](& $DockerAdapter 'VolumeExists' $VolumeName) }
    [bool](Invoke-Local1Docker -Operation VolumeExists -Name $VolumeName)
}

function Get-Local1SqlSecretFromEnvironment {
    param(
        [ValidateSet('Process', 'User')][string]$Target,
        [scriptblock]$EnvironmentReader
    )
    $value = if ($EnvironmentReader) {
        & $EnvironmentReader 'MSSQL_SA_PASSWORD' $Target
    }
    else {
        [Environment]::GetEnvironmentVariable('MSSQL_SA_PASSWORD', $Target)
    }
    if ([string]::IsNullOrWhiteSpace($value)) { return $null }
    $value
}

function Get-Local1SqlSecretFromSecureStore {
    param([string]$Path = (Get-Local1SqlDefaultSecretPath))
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try {
        $encrypted = Get-Content -Raw -LiteralPath $Path -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($encrypted)) { return $null }
        if (-not $encrypted.StartsWith('L1DPAPI1:')) { throw 'Unsupported secure-store format.' }
        $protectedBytes = [Convert]::FromBase64String($encrypted.Substring(9))
        $plainBytes = [Security.Cryptography.ProtectedData]::Unprotect(
            $protectedBytes,
            $null,
            [Security.Cryptography.DataProtectionScope]::CurrentUser
        )
        try { [Text.Encoding]::UTF8.GetString($plainBytes) }
        finally { [Array]::Clear($plainBytes, 0, $plainBytes.Length) }
    }
    catch {
        throw 'SECURE_STORE_UNREADABLE|The user-scoped Local 1 SQL secret store could not be decrypted.'
    }
}

function Get-Local1SqlSecretFromIgnoredEnvFile {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^\s*(?:export\s+)?MSSQL_SA_PASSWORD\s*=\s*(.*?)\s*$') {
            $value = $Matches[1]
            if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
        }
    }
    $null
}

function Get-Local1SqlSecretFromExistingContainer {
    param(
        [string]$ContainerName = $script:DefaultContainerName,
        [scriptblock]$DockerAdapter
    )
    if ($DockerAdapter) { return (& $DockerAdapter 'ContainerSecret' $ContainerName) }
    Invoke-Local1Docker -Operation ContainerSecret -Name $ContainerName
}

function Set-Local1SecretFileAcl {
    param([Parameter(Mandatory)][string]$Path)
    $identityName = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    & icacls.exe $Path '/inheritance:r' '/grant:r' "${identityName}:(F)" 1>$null 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw 'SECURE_STORE_ACL_FAILED|The user-only ACL could not be applied to the Local 1 SQL secret store.'
    }
}

function Save-Local1SqlSecretSecurely {
    param(
        [Parameter(Mandatory)][string]$Secret,
        [string]$Path = (Get-Local1SqlDefaultSecretPath)
    )
    if ([string]::IsNullOrWhiteSpace($Secret)) { throw 'INVALID_SECRET|A blank SQL credential cannot be persisted.' }
    $directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop | Out-Null
    $plainBytes = [Text.Encoding]::UTF8.GetBytes($Secret)
    try {
        $protectedBytes = [Security.Cryptography.ProtectedData]::Protect(
            $plainBytes,
            $null,
            [Security.Cryptography.DataProtectionScope]::CurrentUser
        )
        $encrypted = 'L1DPAPI1:' + [Convert]::ToBase64String($protectedBytes)
    }
    finally { [Array]::Clear($plainBytes, 0, $plainBytes.Length) }
    $temporaryPath = Join-Path $directory ('.' + [IO.Path]::GetRandomFileName())
    try {
        Set-Content -LiteralPath $temporaryPath -Value $encrypted -Encoding ASCII -NoNewline -ErrorAction Stop
        Set-Local1SecretFileAcl -Path $temporaryPath
        Move-Item -LiteralPath $temporaryPath -Destination $Path -Force -ErrorAction Stop
        Set-Local1SecretFileAcl -Path $Path
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue }
    }
    $true
}

function New-Local1SqlSecret {
    $bytes = New-Object byte[] 24
    $rng = New-Object Security.Cryptography.RNGCryptoServiceProvider
    try { $rng.GetBytes($bytes) }
    finally { $rng.Dispose() }
    $body = [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('/', 'x').Replace('+', 'Z')
    "L1!aA9_$body"
}

function Test-Local1SqlPasswordComplexity {
    param([Parameter(Mandatory)][string]$Secret)
    $Secret.Length -ge 12 -and
        $Secret -cmatch '[A-Z]' -and
        $Secret -cmatch '[a-z]' -and
        $Secret -match '[0-9]' -and
        $Secret -match '[^A-Za-z0-9]'
}

function Test-Local1SecretEqual {
    param([string]$Left, [string]$Right)
    if ($null -eq $Left -or $null -eq $Right) { return $false }
    $leftBytes = [Text.Encoding]::UTF8.GetBytes($Left)
    $rightBytes = [Text.Encoding]::UTF8.GetBytes($Right)
    if ($leftBytes.Length -ne $rightBytes.Length) { return $false }
    $difference = 0
    for ($index = 0; $index -lt $leftBytes.Length; $index++) {
        $difference = $difference -bor ($leftBytes[$index] -bxor $rightBytes[$index])
    }
    $difference -eq 0
}

function Get-Local1SqlDockerState {
    param(
        [string]$ContainerName = $script:DefaultContainerName,
        [string]$VolumeName = $script:DefaultVolumeName,
        [scriptblock]$DockerAdapter
    )
    $available = if ($DockerAdapter) { [bool](& $DockerAdapter 'Available' $null) } else { [bool](Invoke-Local1Docker -Operation Available) }
    if (-not $available) { throw 'DOCKER_UNAVAILABLE|Docker Desktop is not running or Docker Engine is unavailable.' }
    [pscustomobject]@{
        DockerAvailable = $true
        ExistingContainer = Test-Local1SqlContainerExists -ContainerName $ContainerName -DockerAdapter $DockerAdapter
        ExistingVolume = Test-Local1SqlVolumeExists -VolumeName $VolumeName -DockerAdapter $DockerAdapter
    }
}

function Resolve-Local1SqlSecret {
    [CmdletBinding()]
    param(
        [string]$SecureStorePath = (Get-Local1SqlDefaultSecretPath),
        [string]$IgnoredEnvFilePath,
        [string]$ContainerName = $script:DefaultContainerName,
        [string]$VolumeName = $script:DefaultVolumeName,
        [scriptblock]$DockerAdapter,
        [scriptblock]$EnvironmentReader,
        [scriptblock]$SecretGenerator
    )

    $state = Get-Local1SqlDockerState -ContainerName $ContainerName -VolumeName $VolumeName -DockerAdapter $DockerAdapter
    $source = $null
    $secret = Get-Local1SqlSecretFromEnvironment -Target Process -EnvironmentReader $EnvironmentReader
    if ($secret) { $source = 'ProcessEnvironment' }
    if (-not $secret) {
        $secret = Get-Local1SqlSecretFromEnvironment -Target User -EnvironmentReader $EnvironmentReader
        if ($secret) { $source = 'UserEnvironment' }
    }
    $secureStoreUnreadable = $false
    if (-not $secret) {
        try {
            $secret = Get-Local1SqlSecretFromSecureStore -Path $SecureStorePath
            if ($secret) { $source = 'SecureStore' }
        }
        catch {
            if ($_.Exception.Message -like 'SECURE_STORE_UNREADABLE|*') {
                $secureStoreUnreadable = $true
                $secret = $null
            }
            else { throw }
        }
    }
    if (-not $secret) {
        $secret = Get-Local1SqlSecretFromIgnoredEnvFile -Path $IgnoredEnvFilePath
        if ($secret) { $source = 'IgnoredEnvFile' }
    }

    $containerSecret = $null
    if ($state.ExistingContainer) {
        $containerSecret = Get-Local1SqlSecretFromExistingContainer -ContainerName $ContainerName -DockerAdapter $DockerAdapter
        if ($secret -and $containerSecret -and -not (Test-Local1SecretEqual -Left $secret -Right $containerSecret)) {
            throw 'CREDENTIAL_CONFLICT|An approved credential source does not match the existing SQL container. Existing data was preserved and no credential was replaced.'
        }
        if (-not $secret -and $containerSecret) {
            $secret = $containerSecret
            $source = 'ExistingContainerMigration'
        }
    }

    if (-not $secret) {
        if ($state.ExistingContainer -or $state.ExistingVolume) {
            throw ("UNRECOVERABLE_EXISTING_DATA|Local 1 SQL credential could not be recovered for the existing SQL environment.|{0}|{1}" -f $state.ExistingContainer, $state.ExistingVolume)
        }
        if ($secureStoreUnreadable) {
            throw 'SECURE_STORE_UNREADABLE|The user-scoped Local 1 SQL secret store could not be decrypted and no existing container credential proved a safe replacement.'
        }
        $secret = if ($SecretGenerator) { & $SecretGenerator } else { New-Local1SqlSecret }
        if (-not (Test-Local1SqlPasswordComplexity -Secret $secret)) {
            throw 'GENERATED_SECRET_INVALID|The generated SQL credential did not meet SQL Server complexity requirements.'
        }
        $source = 'GeneratedNewEnvironment'
    }

    $persisted = $source -eq 'SecureStore' -and -not $secureStoreUnreadable
    if (-not $persisted) {
        $persisted = Save-Local1SqlSecretSecurely -Secret $secret -Path $SecureStorePath
    }
    $env:MSSQL_SA_PASSWORD = $secret

    [pscustomobject]@{
        Result = 'PASS'
        Source = $source
        Persisted = [bool]$persisted
        ExistingContainer = [bool]$state.ExistingContainer
        ExistingVolume = [bool]$state.ExistingVolume
        SecretValueDisplayed = $false
    }
}

function Start-Local1SqlDocker {
    param(
        [Parameter(Mandatory)][string]$RepositoryPath,
        [scriptblock]$ComposeInvoker
    )
    if ([string]::IsNullOrWhiteSpace($env:MSSQL_SA_PASSWORD)) {
        throw 'SECRET_NOT_RESOLVED|Docker Compose was not invoked because secure SQL credential resolution did not pass.'
    }
    if ($ComposeInvoker) { $exitCode = & $ComposeInvoker $RepositoryPath }
    else {
        Push-Location $RepositoryPath
        try {
            & docker compose -f docker-compose.local.yml up -d
            $exitCode = $LASTEXITCODE
        }
        finally { Pop-Location }
    }
    if ([int]$exitCode -ne 0) {
        throw 'COMPOSE_FAILED|Docker Compose failed after secure SQL credential resolution.'
    }
    [pscustomobject]@{ Result = 'PASS'; CredentialResolution = 'PASS'; SecretDisplayed = $false }
}

Export-ModuleMember -Function @(
    'Get-Local1SqlDefaultSecretPath',
    'Test-Local1SqlContainerExists',
    'Test-Local1SqlVolumeExists',
    'Get-Local1SqlSecretFromEnvironment',
    'Get-Local1SqlSecretFromSecureStore',
    'Get-Local1SqlSecretFromIgnoredEnvFile',
    'Get-Local1SqlSecretFromExistingContainer',
    'Save-Local1SqlSecretSecurely',
    'New-Local1SqlSecret',
    'Test-Local1SqlPasswordComplexity',
    'Resolve-Local1SqlSecret',
    'Start-Local1SqlDocker'
)
