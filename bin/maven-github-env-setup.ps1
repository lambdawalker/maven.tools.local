#requires -Version 5.1
# Compatibility launcher; implementation lives in the module.
[CmdletBinding()]
param(
    [string]$Repository,
    [string]$Namespace,
    [string]$Fingerprint,
    [string]$Environment = 'maven-central',
    [string]$CredentialsPath = (Join-Path $HOME '.maven-key/github-maven.json'),
    [string]$SigningKeySecret = 'SIGNING_IN_MEMORY_KEY',
    [string]$SigningPasswordSecret = 'SIGNING_IN_MEMORY_KEY_PASSWORD',
    [string]$MavenUsernameSecret = 'MAVEN_CENTRAL_USERNAME',
    [string]$MavenPasswordSecret = 'MAVEN_CENTRAL_PASSWORD',
    [string]$SigningKeyIdSecret,
    [switch]$VerifyOnly,
    [switch]$CreateEnvironment # Retained for compatibility; creation is now automatic.
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../src/Apexfission.MavenTools/Apexfission.MavenTools.psd1') -ErrorAction Stop
& Set-MavenGitHubEnvironment @PSBoundParameters
