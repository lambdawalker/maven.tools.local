#requires -Version 5.1
[CmdletBinding()]
param([string]$OutputDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'dist'))
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repoRoot = Split-Path $PSScriptRoot -Parent
$moduleName = 'Apexfission.MavenTools'
$source = Join-Path $repoRoot "src/$moduleName"
$target = Join-Path $OutputDirectory $moduleName
if (Test-Path -LiteralPath $target) { throw "Staging directory already exists: $target. Choose a new OutputDirectory or remove the old build explicitly." }
$null = New-Item -ItemType Directory -Path $target -Force
# Explicit file list: never copy the repo/user configuration into a package.
$moduleFiles = @(
    'Apexfission.MavenTools.psd1', 'Apexfission.MavenTools.psm1',
    'Public/New-MavenSigningKey.ps1', 'Public/Get-MavenSigningKey.ps1',
    'Public/Publish-MavenPublicKey.ps1', 'Public/Save-MavenCredentials.ps1',
    'Public/Set-MavenGitHubEnvironment.ps1', 'Public/Test-MavenToolsDependency.ps1'
)
$repoFiles = @('LICENSE', 'NOTICE', 'README.md', 'CHANGELOG.md',
    'docs/commands.md', 'docs/security.md', 'docs/troubleshooting.md', 'docs/publishing.md',
    'examples/config.example.json')
foreach ($pair in @(@{Root=$source; Files=$moduleFiles}, @{Root=$repoRoot; Files=$repoFiles})) {
    foreach ($file in $pair.Files) {
        $destination = Join-Path $target $file
        $null = New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force
        Copy-Item -LiteralPath (Join-Path $pair.Root $file) -Destination $destination
    }
}
$null = Test-ModuleManifest (Join-Path $target "$moduleName.psd1")
# Only the resulting path goes to the success stream for callers.
(Resolve-Path -LiteralPath $target).Path
