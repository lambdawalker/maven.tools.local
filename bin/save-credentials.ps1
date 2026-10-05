#requires -Version 5.1
# Compatibility launcher; implementation lives in the module.
[CmdletBinding()]
param(
    [ValidateSet('All','GitHub','MavenCentral')][string]$Only = 'All',
    [string]$Path = (Join-Path $HOME '.maven-key/github-maven.json')
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../src/Apexfission.MavenTools/Apexfission.MavenTools.psd1') -ErrorAction Stop
& Save-MavenCredentials @PSBoundParameters
