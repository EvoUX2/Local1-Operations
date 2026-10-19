[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Ensure', 'VerifyRoutes')]
    [string]$Mode,
    [int]$Port = 8080
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Local1GatewayOwnership.psm1') -Force -DisableNameChecking

switch ($Mode) {
    'Ensure' { $code = Invoke-Local1GatewayEnsure -Port $Port }
    'VerifyRoutes' { $code = Invoke-Local1GatewayVerifyRoutes -Port $Port }
}

exit $code
