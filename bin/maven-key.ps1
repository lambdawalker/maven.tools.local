#requires -Version 5.1
# Compatibility launcher; implementation lives in the module.
[CmdletBinding()]
param(
    [string]$Namespace,
    [string]$Name,
    [string]$Email,
    [string]$KeyType,
    [string]$KeySize,
    [string]$Expires,
    [string]$ConfigPath = (Join-Path $HOME '.maven-key/config.json')
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../src/Apexfission.MavenTools/Apexfission.MavenTools.psd1') -ErrorAction Stop
& New-MavenSigningKey @PSBoundParameters
