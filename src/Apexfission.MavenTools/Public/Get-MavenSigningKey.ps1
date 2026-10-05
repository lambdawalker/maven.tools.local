function Get-MavenSigningKey {
<#
.SYNOPSIS
Display local GPG keys, fingerprints and expiration status.
.DESCRIPTION
Colorful, read-only view of your local GPG keyring.
  Get-MavenSigningKey                    All public keys (including your own keys)
  Get-MavenSigningKey -SecretOnly        Only keys listed in the secret keyring
  Get-MavenSigningKey -NoColor           Plain text
  Get-MavenSigningKey -ExpiringWithinDays 60
Colors: name=white, email=cyan, description=magenta, ID/fingerprint=yellow,
expired/revoked/disabled/invalid=red, upcoming expiration=yellow, valid date=green.
Status labels remain visible even without colors. Dates are shown in local time.
No keys are generated, modified, exported, or uploaded.

.PARAMETER SecretOnly
List only keys in the secret keyring, including unavailable stubs.

.PARAMETER NoColor
Display plain text without console colors.

.PARAMETER ExpiringWithinDays
Highlight keys expiring within this many days; defaults to 30.

.EXAMPLE
Get-MavenSigningKey -SecretOnly

.NOTES
Requires GnuPG. Supported on Windows PowerShell 5.1 and PowerShell 7 on Windows.
.LINK
https://github.com/lambdawalker/maven.tools.local/blob/main/docs/commands.md
#>
[CmdletBinding()]
param(
    [switch]$SecretOnly,
    [switch]$NoColor,
    [ValidateRange(0,36500)][int]$ExpiringWithinDays = 30
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not (Get-Command gpg -ErrorAction SilentlyContinue)) {
    throw 'Install Gpg4win/GnuPG and ensure gpg is on PATH.'
}
function Write-Color {
    param([string]$Text, [string]$Color = 'Gray', [switch]$Inline)
    if ($NoColor) { Write-Host $Text -NoNewline:$Inline }
    else { Write-Host $Text -ForegroundColor $Color -NoNewline:$Inline }
}
function Get-Field([string[]]$Fields, [int]$Index) {
    if ($Index -lt $Fields.Length) { return $Fields[$Index] }
    return ''
}
function Decode-Uid([string]$Text) {
    # GPG --with-colons uses byte-level \xHH escaping, not shell quoting.
    $bytes = [Collections.Generic.List[byte]]::new()
    for ($i = 0; $i -lt $Text.Length; $i++) {
        if ($Text[$i] -eq [char]92 -and $i + 3 -lt $Text.Length -and
            $Text[$i + 1] -eq 'x' -and $Text.Substring($i + 2,2) -match '^[0-9A-Fa-f]{2}$') {
            $bytes.Add([Convert]::ToByte($Text.Substring($i + 2,2),16))
            $i += 3
        } else {
            # Preserve literal UTF-8 characters, including surrogate pairs.
            $length = 1
            if ([char]::IsHighSurrogate($Text[$i]) -and $i + 1 -lt $Text.Length -and
                [char]::IsLowSurrogate($Text[$i + 1])) { $length = 2 }
            $bytes.AddRange([Text.Encoding]::UTF8.GetBytes($Text.Substring($i,$length)))
            $i += $length - 1
        }
    }
    $decoded = [Text.Encoding]::UTF8.GetString($bytes.ToArray())
    # Do not render control/escape sequences from untrusted imported user IDs.
    return [regex]::Replace($decoded, '[\p{Cc}\p{Cf}]', '?')
}
function Format-Date([string]$Seconds) {
    if (-not $Seconds -or $Seconds -eq '0') { return 'Never' }
    return [DateTimeOffset]::FromUnixTimeSeconds([long]$Seconds).ToLocalTime().ToString('yyyy-MM-dd HH:mm')
}
function Show-KeyRecord([string[]]$Fields, [bool]$Subkey) {
    $type = Get-Field $Fields 0
    $validity = Get-Field $Fields 1
    $bits = Get-Field $Fields 2
    $algorithmNumber = Get-Field $Fields 3
    $id = Get-Field $Fields 4
    $created = Get-Field $Fields 5
    $expires = Get-Field $Fields 6
    $capabilities = Get-Field $Fields 11
    $algorithms = @{'1'='RSA';'2'='RSA';'3'='RSA';'16'='ElGamal';'17'='DSA';'18'='ECDH';'19'='ECDSA';'22'='EdDSA';'25'='X25519';'26'='X448';'27'='Ed25519';'28'='Ed448'}
    $algorithm = "algorithm $algorithmNumber"
    if ($algorithms.ContainsKey($algorithmNumber)) { $algorithm = $algorithms[$algorithmNumber] }
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $expired = $validity -eq 'e' -or ($expires -and $expires -ne '0' -and [long]$expires -le $now)
    $status = 'NOT EXPIRED'
    $statusColor = 'Green'
    if ($expired) { $status = 'EXPIRED'; $statusColor = 'Red' }
    if ($validity -eq 'r') { $status = 'REVOKED'; $statusColor = 'Red' }
    elseif ($validity -eq 'd' -or $capabilities -cmatch 'D') { $status = 'DISABLED'; $statusColor = 'Red' }
    elseif ($validity -eq 'i') { $status = 'INVALID'; $statusColor = 'Red' }
    $label = 'Primary'
    if ($Subkey) { $label = 'Subkey ' }
    Write-Color "  $label  " DarkGray -Inline
    Write-Color $id Yellow -Inline
    Write-Color "  $algorithm/$bits  [$capabilities]  " Gray -Inline
    Write-Color $status $statusColor
    Write-Color ('    Created: ' + (Format-Date $created) + '    Expires: ') DarkGray -Inline
    $dateColor = 'Green'
    $dateLabel = Format-Date $expires
    if ($expired) { $dateColor = 'Red'; $dateLabel += ' [EXPIRED]' }
    elseif ($expires -and $expires -ne '0' -and [long]$expires -le ($now + 86400L * $ExpiringWithinDays)) {
        $dateColor = 'Yellow'; $dateLabel += ' [EXPIRING SOON]'
    }
    Write-Color $dateLabel $dateColor
    if ($type -in @('sec','ssb')) {
        $secretMarker = Get-Field $Fields 14
        if ($secretMarker -eq '#') { Write-Color '    Secret material unavailable (stub)' Red }
        elseif ($secretMarker -and $secretMarker -ne '+') { Write-Color "    Hardware/token reference: $secretMarker" DarkCyan }
    }
}
$oldEncoding = [Console]::OutputEncoding
try {
    # Native stdout is UTF-8, including non-ASCII user identities on Windows.
    [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
    $operation = '--list-keys'
    if ($SecretOnly) { $operation = '--list-secret-keys' }
    $rows = @(& gpg --batch --with-colons --fixed-list-mode --with-fingerprint --with-subkey-fingerprint $operation)
    if ($LASTEXITCODE -ne 0) { throw "GPG listing failed (exit $LASTEXITCODE)." }
} finally { [Console]::OutputEncoding = $oldEncoding }
$count = 0
foreach ($row in $rows) {
    $fields = $row.Split(':')
    switch ($fields[0]) {
        { $_ -in @('pub','sec') } {
            $count++
            Write-Color ''
            Write-Color ('-' * 76) DarkGray
            Write-Color "KEY $count" White
            Show-KeyRecord $fields $false
        }
        { $_ -in @('sub','ssb') } { Show-KeyRecord $fields $true }
        'fpr' {
            $fingerprint = Get-Field $fields 9
            $groups = [regex]::Matches($fingerprint,'.{1,4}') | ForEach-Object { $_.Value }
            Write-Color '    Fingerprint: ' DarkGray -Inline
            Write-Color ($groups -join ' ') Yellow
        }
        'uid' {
            $uid = Decode-Uid (Get-Field $fields 9)
            $match = [regex]::Match($uid, '^(?<name>.*?)(?:\s+\((?<comment>.*)\))?(?:\s*<(?<email>[^<>]*)>)?$')
            Write-Color '    Identity: ' DarkGray -Inline
            if ($match.Success) {
                Write-Color $match.Groups['name'].Value White -Inline
                if ($match.Groups['comment'].Success) {
                    Write-Color (' (' + $match.Groups['comment'].Value + ')') Magenta -Inline
                }
                if ($match.Groups['email'].Success) {
                    Write-Color (' <' + $match.Groups['email'].Value + '>') Cyan -Inline
                }
            } else { Write-Color $uid White -Inline }
            $uidState = Get-Field $fields 1
            if ($uidState -in @('r','e','i')) {
                $labels = @{'r'='REVOKED';'e'='EXPIRED';'i'='INVALID'}
                Write-Color (' [' + $labels[$uidState] + ']') Red -Inline
            }
            Write-Color ''
        }
    }
}
Write-Color ''
if ($count -eq 0) { Write-Color 'No keys found in the selected local keyring.' Yellow }
else {
    Write-Color "$count primary key(s). Dates are local time. Expiration status does not establish identity trust." DarkGray
}
}
