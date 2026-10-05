#requires -Version 5.1
# Compatibility launcher; implementation lives in the module.
[CmdletBinding()]
param(
    [string]$Namespace,
    [string]$Fingerprint,
    [string]$Keyserver = 'hkps://keyserver.ubuntu.com',
    [switch]$ValidateOnly
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../src/Apexfission.MavenTools/Apexfission.MavenTools.psd1') -ErrorAction Stop
& Publish-MavenPublicKey @PSBoundParameters
