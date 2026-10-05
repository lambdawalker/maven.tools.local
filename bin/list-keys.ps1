#requires -Version 5.1
# Compatibility launcher; implementation lives in the module.
[CmdletBinding()]
param(
    [switch]$SecretOnly,
    [switch]$NoColor,
    [ValidateRange(0,36500)][int]$ExpiringWithinDays = 30
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../src/Apexfission.MavenTools/Apexfission.MavenTools.psd1') -ErrorAction Stop
& Get-MavenSigningKey @PSBoundParameters
