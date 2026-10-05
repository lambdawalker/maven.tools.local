function New-MavenSigningKey {
<#
.SYNOPSIS
Create a namespace-specific GPG signing key.
.DESCRIPTION
Generate a namespace-specific signing key in the normal GPG keyring.
  New-MavenSigningKey -Namespace 'com.example.library'
Reads $HOME/.maven-key/config.json; missing settings are prompted.
No key exports, output folders, or separate metadata files are created.
GPG itself manages its keyring and automatic revocation certificate.
Use Publish-MavenPublicKey to validate signing and publish the public key.

.PARAMETER Namespace
Exact namespace comment used to identify the GPG key. Prompted if required and omitted.

.PARAMETER Name
Public key identity name. Uses configuration or prompts when omitted.

.PARAMETER Email
Public publishing email. Uses configuration or prompts when omitted.

.PARAMETER KeyType
Key algorithm. Currently rsa; uses configuration or prompts when omitted.

.PARAMETER KeySize
RSA size: 2048, 3072 or 4096. Uses configuration or prompts when omitted.

.PARAMETER Expires
GPG expiration: duration, YYYY-MM-DD or 0. Uses configuration or prompts when omitted.

.PARAMETER ConfigPath
Key defaults JSON path. Defaults to $HOME/.maven-key/config.json.

.EXAMPLE
New-MavenSigningKey -Namespace com.example.library

.NOTES
Requires GnuPG. Supported on Windows PowerShell 5.1 and PowerShell 7 on Windows.
.LINK
https://github.com/lambdawalker/maven.tools.local/blob/main/docs/commands.md
#>
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
Set-StrictMode -Version Latest

# Priority: explicit command-line arguments > JSON settings > interactive prompts.
# No publishing defaults are embedded here. The config path is the only default.
$config = [pscustomobject]@{}
if (Test-Path -LiteralPath $ConfigPath) {
    try {
        $config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        throw "Cannot read JSON configuration '$ConfigPath': $($_.Exception.Message)"
    }
    if ($null -eq $config -or $config -isnot [System.Management.Automation.PSCustomObject]) {
        throw 'Configuration must be a JSON object.'
    }
} else {
    Write-Host "Configuration file not found: $ConfigPath"
    Write-Host 'Continuing with command-line arguments; any missing required settings will be requested interactively.'
}
$allowed = @('Name', 'Email', 'KeyType', 'KeySize', 'Expires')
foreach ($property in $config.PSObject.Properties) {
    if ($property.Name -eq 'OutputRoot') {
        Write-Host 'Ignoring legacy OutputRoot: keys now remain in the GPG keyring.'
        continue
    }
    if ($property.Name -notin $allowed) {
        throw "Unknown configuration setting: $($property.Name). Allowed: $($allowed -join ', ')."
    }
    if ($PSBoundParameters.ContainsKey($property.Name)) { continue }
    if ($null -eq $property.Value) { continue }
    if ($property.Value -isnot [string] -and
        -not ($property.Name -eq 'KeySize' -and
            ($property.Value -is [int] -or $property.Value -is [long]))) {
        throw "Setting '$($property.Name)' must be a string (KeySize can also be an integer)."
    }
    Set-Variable -Name $property.Name -Value ([string]$property.Value)
}
$prompts = @{
    Namespace = 'Software namespace (required, e.g. com.apexfission.android.permission)'
    Name = 'Name for the public key'
    Email = 'Publishing email'
    KeyType = 'Key type (supported: rsa)'
    KeySize = 'RSA key size (2048, 3072, or 4096)'
    Expires = 'Expiration (duration such as 2y, YYYY-MM-DD, or 0 for no expiration)'
}
# Namespace is mandatory and is not read from shared defaults.
$required = @('Namespace') + $allowed
foreach ($setting in $required) {
    $value = [string](Get-Variable -Name $setting -ValueOnly)
    while ([string]::IsNullOrWhiteSpace($value)) {
        $value = Read-Host $prompts[$setting]
        if ([string]::IsNullOrWhiteSpace($value)) {
            Write-Host 'A value is required. Enter a value or press Ctrl+C to cancel.'
        }
    }
    Set-Variable -Name $setting -Value $value.Trim()
}
# Keep namespace validation compatible with earlier keys and upload.ps1.
if ($Namespace.Length -gt 150 -or
    $Namespace -notmatch '^[A-Za-z0-9_][A-Za-z0-9_-]*(\.[A-Za-z0-9_][A-Za-z0-9_-]*)*$' -or
    $Namespace -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') {
    throw 'Invalid namespace. Use letters, digits, underscores, hyphens and dot-separated segments (maximum 150 characters); Windows device names are not allowed.'
}
if ($KeyType -ne 'rsa') { throw 'KeyType must be rsa; KeySize controls its size.' }
if ($KeySize -notin @('2048','3072','4096')) { throw 'KeySize must be 2048, 3072, or 4096.' }
if ($Expires -notmatch '^(0|[1-9][0-9]*[dwmy]?|[0-9]{4}-[0-9]{2}-[0-9]{2})$') {
    throw 'Expires must be 0, a duration such as 2y, or YYYY-MM-DD.'
}
if (-not (Get-Command gpg -ErrorAction SilentlyContinue)) {
    throw 'Install GnuPG/Gpg4win and reopen PowerShell so gpg is on PATH.'
}
function Invoke-Gpg {
    param([string[]]$Arguments)
    & gpg @Arguments
    if ($LASTEXITCODE -ne 0) { throw "GPG failed (exit $LASTEXITCODE)." }
}
if ($Email -eq 'CHANGE-ME@example.com' -or $Email -notmatch '^[^\s<>@]+@[^\s<>@]+\.[^\s<>@]+$') {
    throw 'Set Email to your real publishing email in config.json or pass -Email.'
}
if ([string]::IsNullOrWhiteSpace($Name) -or $Name -match '[\r\n<>]') {
    throw 'Provide a nonempty Name without newlines or angle brackets.'
}
Write-Host 'GPG will ask for a passphrase. Choose a strong, nonempty one.'
# Capture GPG's machine-readable creation result in memory, not in a file.
$status = @(Invoke-Gpg -Arguments @('--status-fd', '1', '--quick-generate-key',
    "$Name ($Namespace) <$Email>", "$KeyType$KeySize", 'sign', $Expires))
$created = @($status | Where-Object { $_ -match '^\[GNUPG:\] KEY_CREATED [BP] ([A-Fa-f0-9]{40})$' })
if ($created.Count -ne 1) {
    throw 'Cannot identify the generated key. Run gpg --list-secret-keys --with-fingerprint before trying again.'
}
$fingerprint = ($created[0] -split ' ')[-1]
Write-Host "Key created in GPG. Namespace: $Namespace"
Write-Host "Fingerprint: $fingerprint"
Write-Host 'No key files were exported.'
Write-Host "Next: Publish-MavenPublicKey -Namespace $Namespace -Fingerprint $fingerprint"
}
