function Publish-MavenPublicKey {
<#
.SYNOPSIS
Validate signing and publish only the public key to a keyserver.
.DESCRIPTION
Validate a namespace-specific key in GPG and publish ONLY its public key.
  Publish-MavenPublicKey -Namespace 'com.example.library'
  Publish-MavenPublicKey -Namespace 'com.example.library' -ValidateOnly
  Publish-MavenPublicKey -Namespace 'com.example.library' -Fingerprint 'FULL_FINGERPRINT'
Namespace is mandatory and prompted when absent. Multiple matches require selection.
No exported key files or OutputRoot/config file are needed. Temporary test data
and its signature are removed afterwards. Private key material stays in GPG.

.PARAMETER Namespace
Exact namespace comment used to identify the GPG key. Prompted if required and omitted.

.PARAMETER Fingerprint
Optional full 40-character fingerprint to select a specific namespace key.

.PARAMETER Keyserver
Public keyserver URL. Defaults to hkps://keyserver.ubuntu.com.

.PARAMETER ValidateOnly
Test signing and verification without uploading the public key.

.EXAMPLE
Publish-MavenPublicKey -Namespace com.example.library -ValidateOnly

.NOTES
Requires GnuPG. Supported on Windows PowerShell 5.1 and PowerShell 7 on Windows.
.LINK
https://github.com/lambdawalker/maven.tools.local/blob/main/docs/commands.md
#>
[CmdletBinding()]
param(
    [string]$Namespace,
    [string]$Fingerprint,
    [string]$Keyserver = 'hkps://keyserver.ubuntu.com',
    [switch]$ValidateOnly
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not (Get-Command gpg -ErrorAction SilentlyContinue)) { throw 'Install Gpg4win/GnuPG and ensure gpg is on PATH.' }
function Invoke-Gpg([string[]]$Arguments) {
    & gpg @Arguments
    if ($LASTEXITCODE -ne 0) { throw "GPG failed (exit $LASTEXITCODE). Upload stopped." }
}
while ([string]::IsNullOrWhiteSpace($Namespace)) {
    $Namespace = Read-Host 'Software namespace (required, e.g. com.example.library)'
}
$Namespace = $Namespace.Trim()
if ($Namespace.Length -gt 150 -or
    $Namespace -notmatch '^[A-Za-z0-9_][A-Za-z0-9_-]*(\.[A-Za-z0-9_][A-Za-z0-9_-]*)*$' -or
    $Namespace -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') {
    throw 'Invalid namespace. Use dot-separated letters, digits, underscores or hyphens; Windows device names are not allowed.'
}
if ($Fingerprint -and $Fingerprint -notmatch '^[A-Fa-f0-9]{40}$') { throw 'Provide the full 40-character fingerprint.' }
# Exact comment matching avoids confusing com.example with com.example.other.
# Namespace characters cannot contain GPG colon-format escapes.
$namespacePattern = '\(' + [regex]::Escape($Namespace) + '\)(?:\s*<[^<>]*>)?$'
$rows = @(Invoke-Gpg @('--batch','--with-colons','--fixed-list-mode','--with-fingerprint','--list-secret-keys'))
$keys = [Collections.Generic.List[object]]::new()
$current = $null
$awaitPrimaryFingerprint = $false
foreach ($row in $rows) {
    $fields = $row.Split(':')
    switch ($fields[0]) {
        'sec' {
            $current = [pscustomobject]@{ Fingerprint = ''; Fields = $fields; Matches = $false }
            $keys.Add($current)
            $awaitPrimaryFingerprint = $true
        }
        'ssb' { $awaitPrimaryFingerprint = $false }
        'fpr' {
            if ($awaitPrimaryFingerprint -and $null -ne $current) {
                $current.Fingerprint = $fields[9]
                $awaitPrimaryFingerprint = $false
            }
        }
        'uid' {
            if ($null -ne $current -and $fields[1] -notin @('r','e','i') -and $fields[9] -cmatch $namespacePattern) {
                $current.Matches = $true
            }
        }
    }
}
$candidates = @($keys | Where-Object { $_.Matches -and $_.Fingerprint })
if ($Fingerprint) { $candidates = @($candidates | Where-Object { $_.Fingerprint -eq $Fingerprint }) }
if ($candidates.Count -eq 0) {
    throw "No matching secret key with namespace comment ($Namespace) was found. Check gpg --list-secret-keys --with-fingerprint."
}
if ($candidates.Count -gt 1) {
    Write-Host "Multiple keys match namespace $Namespace. Select one explicitly:"
    for ($i = 0; $i -lt $candidates.Count; $i++) {
        $f = $candidates[$i].Fields
        $created = [DateTimeOffset]::FromUnixTimeSeconds([long]$f[5]).ToString('yyyy-MM-dd')
        $expiration = 'never'
        if ($f[6] -and $f[6] -ne '0') { $expiration = [DateTimeOffset]::FromUnixTimeSeconds([long]$f[6]).ToString('yyyy-MM-dd') }
        Write-Host ("{0}. {1}  created {2}  expires {3}  status [{4}]" -f ($i + 1), $candidates[$i].Fingerprint, $created, $expiration, $f[1])
    }
    $choice = 0
    do {
        $answer = Read-Host "Choose 1-$($candidates.Count) (Ctrl+C to cancel)"
        $valid = [int]::TryParse($answer, [ref]$choice) -and $choice -ge 1 -and $choice -le $candidates.Count
    } while (-not $valid)
    $selected = $candidates[$choice - 1]
} else { $selected = $candidates[0] }
$fingerprint = $selected.Fingerprint
$f = $selected.Fields
$now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
if ($f[1] -in @('r','e','d','i') -or $f[11] -cmatch 'D') { throw 'Selected key is revoked, expired, disabled, or invalid.' }
if ($f[6] -and $f[6] -ne '0' -and [long]$f[6] -le $now) { throw 'Selected key has expired.' }
if ([long]$f[5] -gt $now) { throw 'Key creation time is in the future. Check the system clock.' }
if ($f[11] -cnotmatch 's') { throw 'Selected primary key cannot sign. Use a primary signing key created by New-MavenSigningKey.' }
Write-Host "Namespace: $Namespace"
Write-Host "Fingerprint: $fingerprint"
Write-Host 'Testing signing through GPG. A passphrase or hardware-token prompt may appear.'
$work = Join-Path ([IO.Path]::GetTempPath()) ('maven-key-check-' + [Guid]::NewGuid().ToString('N'))
try {
    $null = New-Item -ItemType Directory -Path $work
    $sample = Join-Path $work 'test.txt'
    $signature = Join-Path $work 'test.asc'
    [IO.File]::WriteAllText($sample, [Guid]::NewGuid().ToString(), [Text.Encoding]::ASCII)
    Invoke-Gpg @('--armor','--local-user',"$fingerprint!",'--output',$signature,'--detach-sign',$sample)
    $verification = @(Invoke-Gpg @('--batch','--no-auto-key-retrieve','--status-fd','1','--verify',$signature,$sample))
    $validSignature = @($verification | Where-Object { $_ -match ('^\[GNUPG:\] VALIDSIG ' + [regex]::Escape($fingerprint) + ' ') })
    if ($validSignature.Count -ne 1) { throw 'Signature verification did not confirm the selected fingerprint.' }
    Write-Host 'Validation passed: signing and verification succeeded. No private key was exported.'
    if ($ValidateOnly) {
        Write-Host 'ValidateOnly selected: nothing uploaded.'
    } else {
        Write-Host "Publishing PUBLIC key $fingerprint to $Keyserver (including its name, namespace and email)."
        Invoke-Gpg @('--batch','--keyserver',$Keyserver,'--send-keys',$fingerprint)
        Write-Host 'Keyserver accepted the upload request. Propagation may take time.'
        if ($Keyserver -eq 'hkps://keyserver.ubuntu.com') {
            Write-Host "Check: https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x$fingerprint"
        }
    }
} finally {
    if (Test-Path -LiteralPath $work) {
        try { Remove-Item -LiteralPath $work -Recurse -Force }
        catch { Write-Warning "Could not remove temporary test data/signature: $work" }
    }
}
}
