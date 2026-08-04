[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SentinelRepositoryPath,
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'Local1SqlSecret.psm1'
$secureStorePath = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'SAXIO\Local1\secrets\mssql-sa-password.dpapi'
$ignoredEnvFilePath = Join-Path $SentinelRepositoryPath '.env.sqlserver'

function Write-SecretResolutionStatus {
    param($Resolution)
    Write-Output ''
    Write-Output 'Local 1 SQL Secret:'
    Write-Output ("  Source: {0}" -f $Resolution.Source)
    Write-Output ("  Persisted Securely: {0}" -f $(if ($Resolution.Persisted) { 'YES' } else { 'NO' }))
    Write-Output ("  Existing Container: {0}" -f $(if ($Resolution.ExistingContainer) { 'YES' } else { 'NO' }))
    Write-Output ("  Existing Volume: {0}" -f $(if ($Resolution.ExistingVolume) { 'YES' } else { 'NO' }))
    Write-Output '  Secret Displayed: NO'
    Write-Output '  Result: PASS'
}

try {
    $stage = 'ImportModule'
    Import-Module $modulePath -Force -ErrorAction Stop
    $stage = 'ResolveSecret'
    $resolution = Resolve-Local1SqlSecret `
        -SecureStorePath $secureStorePath `
        -IgnoredEnvFilePath $ignoredEnvFilePath
    $stage = 'WriteStatus'
    Write-SecretResolutionStatus -Resolution $resolution

    if ($ValidateOnly) {
        Write-Output '  Validation Only: PASS'
        exit 0
    }

    $stage = 'DockerCompose'
    Start-Local1SqlDocker -RepositoryPath $SentinelRepositoryPath | Out-Null
    Write-Output 'Docker SQL Server:'
    Write-Output '  Credential Resolution: PASS'
    Write-Output '  Secret Displayed: NO'
    Write-Output '  Compose: PASS'
    exit 0
}
catch {
    $errorRecord = $_
    $safeMessage = [string]$errorRecord.Exception.Message
    $parts = $safeMessage.Split('|')
    $code = $parts[0]
    Write-Output ''
    Write-Output 'FAILED'
    switch ($code) {
        'DOCKER_UNAVAILABLE' {
            Write-Output 'Reason: Docker Desktop is not running or Docker Engine is unavailable.'
            Write-Output 'Suggested Fix:'
            Write-Output '  Start Docker Desktop and retry C:\Allprojects\Start-Local1.cmd.'
            exit 20
        }
        'UNRECOVERABLE_EXISTING_DATA' {
            $existingContainer = if ($parts.Count -gt 2 -and $parts[2] -eq 'True') { 'YES' } else { 'NO' }
            $existingVolume = if ($parts.Count -gt 3 -and $parts[3] -eq 'True') { 'YES' } else { 'NO' }
            Write-Output 'Reason: Local 1 SQL credential could not be recovered for the existing SQL environment.'
            Write-Output ("Existing Container: {0}" -f $existingContainer)
            Write-Output ("Existing Volume: {0}" -f $existingVolume)
            Write-Output 'Data Preservation: ENFORCED'
            Write-Output 'Automatic Recreation: DISABLED'
            Write-Output 'Suggested Fix:'
            Write-Output '  The existing database was preserved. Review the approved local secret authority or perform an authorized credential recovery. No container or volume was removed.'
            exit 21
        }
        'CREDENTIAL_CONFLICT' {
            Write-Output 'Reason: The approved local SQL credential conflicts with the existing SQL container credential.'
            Write-Output 'Data Preservation: ENFORCED'
            Write-Output 'Automatic Credential Replacement: DISABLED'
            Write-Output 'Suggested Fix:'
            Write-Output '  Review the approved local secret authority and existing container metadata. No credential, container, or volume was replaced.'
            exit 22
        }
        'COMPOSE_FAILED' {
            Write-Output 'Reason: Docker Compose failed after secure SQL credential resolution.'
            Write-Output 'Credential Resolution: PASS'
            Write-Output 'Secret Displayed: NO'
            Write-Output 'Suggested Fix:'
            Write-Output '  Review Docker Compose diagnostics. The SQL credential is configured and is not the source of this failure.'
            exit 30
        }
        default {
            Write-Output 'Reason: Secure Local 1 SQL credential resolution failed.'
            Write-Output ("Failure Stage: {0}" -f $stage)
            Write-Output ("Technical Code: {0}" -f $errorRecord.FullyQualifiedErrorId)
            Write-Output ("Exception Type: {0}" -f $errorRecord.Exception.GetType().FullName)
            Write-Output ("Resolver Stack: {0}" -f (($errorRecord.ScriptStackTrace -replace '[\r\n]+', ' <- ')))
            Write-Output 'Data Preservation: ENFORCED'
            Write-Output 'Secret Displayed: NO'
            Write-Output 'Suggested Fix:'
            Write-Output '  Review the approved local secret authority. No container or volume was removed.'
            exit 23
        }
    }
}
