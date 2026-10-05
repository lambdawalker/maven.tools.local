#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Tag)
$ErrorActionPreference = 'Stop'
if ($Tag -cnotmatch '^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') {
    throw 'Release tag must have the form vX.Y.Z (three numeric components).'
}
$repoRoot = Split-Path $PSScriptRoot -Parent
$manifest = Import-PowerShellDataFile (Join-Path $repoRoot 'src/Apexfission.MavenTools/Apexfission.MavenTools.psd1')
if ($Tag.Substring(1) -cne $manifest.ModuleVersion) { throw 'Release tag must match ModuleVersion.' }
$tagCommit = & git -C $repoRoot rev-parse --verify "refs/tags/$Tag^{commit}"
if ($LASTEXITCODE -ne 0) { throw 'Release tag does not exist.' }
$headCommit = & git -C $repoRoot rev-parse HEAD
if ($LASTEXITCODE -ne 0 -or $tagCommit -ne $headCommit) { throw 'Checkout must match the release tag commit.' }
& git -C $repoRoot merge-base --is-ancestor $headCommit origin/main
if ($LASTEXITCODE -ne 0) { throw 'Release commit must be part of origin/main.' }
Write-Host "Release verified: $Tag ($headCommit)"
