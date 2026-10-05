#requires -Version 5.1
<#
Save two independently password-encrypted credential blocks for github-setup.
Requires GnuPG/Gpg4win. No GitHub or Maven network requests are made.

  save-credentials
  save-credentials -Only GitHub
  save-credentials -Only MavenCentral

Default file: $HOME/.maven-key/github-maven.json
Credentials and encryption passwords use hidden PowerShell prompts.
Each encryption password is requested twice before GPG is started.
Choose different passwords for GitHub and Maven. Passwords are not stored.
Only ciphertext is written to disk. Plaintext passes to GPG through stdin.
This does not modify config.json or export your signing key.

Format v1: each 'encrypted' value is an ASCII-armored, symmetric OpenPGP message.
Decrypted GitHub JSON: {"token":"..."}
Decrypted Maven JSON: {"username":"...","password":"..."}
Unselected blocks are retained exactly when updating one provider.
A first-time single-provider save leaves the other block null.
#>
[CmdletBinding()]
param(
    [ValidateSet('All','GitHub','MavenCentral')][string]$Only = 'All',
    [string]$Path = (Join-Path $HOME '.maven-key/github-maven.json')
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$gpg = Get-Command gpg -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $gpg) { throw 'Install Gpg4win/GnuPG and add gpg to PATH.' }
function Read-HiddenValue([string]$Prompt) {
    while ($true) {
        $secure = Read-Host $Prompt -AsSecureString
        $pointer = [IntPtr]::Zero
        try {
            $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
            $value = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
            if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
            Write-Host 'A nonempty value is required. Press Ctrl+C to cancel.'
        } finally {
            if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
            $secure.Dispose()
        }
    }
}
function Protect-Credentials([string]$Plaintext, [string]$Label) {
    $encryptionPassword = $null
    $confirmation = $null
    do {
        $encryptionPassword = Read-HiddenValue "New encryption password for $Label"
        $confirmation = Read-HiddenValue "Confirm encryption password for $Label"
        $matchesPassword = [string]::Equals($encryptionPassword, $confirmation, [StringComparison]::Ordinal)
        if ($encryptionPassword -match '[\r\n]') {
            $matchesPassword = $false
            Write-Host 'Use a single-line password.'
        } elseif (-not $matchesPassword) { Write-Host 'Passwords do not match. Please try again.' }
        $confirmation = $null
    } while (-not $matchesPassword)
    Write-Host 'Use a strong, nonempty phrase. Choose a different phrase for each provider.'
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $gpg.Source
    # All arguments are fixed literals. No credentials or passwords in command lines.
    # GPG reads the first stdin line as its password, then the remaining bytes as data.
    # Both remain in memory. Symmetric caching is disabled for independent blocks.
    $start.Arguments = '--no-options --batch --no-symkey-cache --pinentry-mode loopback --passphrase-fd 0 --symmetric --cipher-algo AES256 --armor --output -'
    $start.UseShellExecute = $false
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    # GPG diagnostics go directly to stderr; they never contain the input payload.
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    $started = $false
    try {
        # Prevent .NET Framework's stdin StreamWriter from emitting a BOM.
        $previousInputEncoding = [Console]::InputEncoding
        try {
            [Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
            if ($null -ne $start.PSObject.Properties['StandardInputEncoding']) {
                $start.StandardInputEncoding = [Text.UTF8Encoding]::new($false)
            }
            $started = $process.Start()
        } finally { [Console]::InputEncoding = $previousInputEncoding }
        if (-not $started) { throw 'Could not start GPG.' }
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        # Windows PowerShell 5.1/.NET Framework has no StandardInputEncoding.
        # Write BOM-free UTF-8 bytes directly; never use the text writer here.
        $inputBytes = [Text.Encoding]::UTF8.GetBytes($encryptionPassword + "`n" + $Plaintext)
        try {
            $inputStream = $process.StandardInput.BaseStream
            $inputStream.Write($inputBytes, 0, $inputBytes.Length)
            $inputStream.Flush()
        } finally {
            [Array]::Clear($inputBytes, 0, $inputBytes.Length)
            $process.StandardInput.Close()
        }
        $process.WaitForExit()
        $encrypted = $outputTask.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) {
            throw "GPG encryption failed or was cancelled for $Label. Existing credential file was not changed."
        }
        if ($encrypted -notmatch '(?s)^\s*-----BEGIN PGP MESSAGE-----.*-----END PGP MESSAGE-----\s*$') {
            throw 'GPG did not return the expected encrypted OpenPGP message.'
        }
        return ($encrypted.Trim() + "`n")
    } finally {
        if ($started -and -not $process.HasExited) { $process.Kill() }
        $process.Dispose()
        $Plaintext = $null
        $encryptionPassword = $null
        $confirmation = $null
    }
}
# Resolve a custom home-relative path without evaluating it as code.
if ($Path.StartsWith('~/') -or $Path.StartsWith('~\')) { $Path = Join-Path $HOME $Path.Substring(2) }
$target = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
$parent = [IO.Path]::GetDirectoryName($target)
$null = [IO.Directory]::CreateDirectory($parent)
$lock = $null
$temp = $null
$token = $null
$username = $null
$password = $null
$payload = $null
try {
    # Serialize runs of this script so provider-only updates cannot clobber each other.
    try { $lock = [IO.File]::Open($target + '.lock', [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None) }
    catch { throw 'Could not lock the credential file. Check permissions and whether another save-credentials process is running.' }
    $document = [ordered]@{ version = 1; github = $null; mavenCentral = $null }
    if ([IO.File]::Exists($target)) {
        try { $existing = [IO.File]::ReadAllText($target, [Text.Encoding]::UTF8) | ConvertFrom-Json }
        catch { throw 'Existing credential file is not valid JSON. It has not been overwritten.' }
        if ($null -eq $existing -or $existing -isnot [pscustomobject] -or
            $null -eq $existing.PSObject.Properties['version'] -or $existing.version -ne 1) {
            throw 'Unsupported credential file format. Existing file has not been overwritten.'
        }
        foreach ($provider in @('github','mavenCentral')) {
            $entry = $existing.PSObject.Properties[$provider]
            if ($null -ne $entry -and $null -ne $entry.Value) {
                $value = $entry.Value
                if ($value -isnot [pscustomobject] -or $null -eq $value.PSObject.Properties['encrypted'] -or
                    $value.encrypted -isnot [string] -or
                    $value.encrypted -notmatch '(?s)^\s*-----BEGIN PGP MESSAGE-----.*-----END PGP MESSAGE-----\s*$') {
                    throw "Invalid encrypted block for $provider. Existing file has not been overwritten."
                }
                $document[$provider] = $value
            }
        }
        Write-Host "Updating $Only credentials in: $target"
    } else { Write-Host "Creating encrypted credential file: $target" }
    if ($Only -in @('All','GitHub')) {
        $token = Read-HiddenValue 'GitHub personal access token'
        $payload = @{ token = $token } | ConvertTo-Json -Compress
        $document.github = [ordered]@{ encrypted = (Protect-Credentials $payload 'GitHub') }
        $token = $null
        $payload = $null
    }
    if ($Only -in @('All','MavenCentral')) {
        $username = Read-HiddenValue 'Maven Central token username (not your website login)'
        $password = Read-HiddenValue 'Maven Central token password'
        $payload = @{ username = $username; password = $password } | ConvertTo-Json -Compress
        $document.mavenCentral = [ordered]@{ encrypted = (Protect-Credentials $payload 'Maven Central') }
        $username = $null
        $password = $null
        $payload = $null
    }
    # Stage only ciphertext in the same directory and atomically replace on success.
    $temp = Join-Path $parent ('.credentials-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    [IO.File]::WriteAllText($temp, ($document | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    if ([IO.File]::Exists($target)) { [IO.File]::Replace($temp, $target, $null) }
    else { [IO.File]::Move($temp, $target) }
    $temp = $null
    Write-Host "Encrypted credentials saved: $target" -ForegroundColor Green
    Write-Host 'Remember both encryption passwords. They cannot be recovered from this file.'
} finally {
    $token = $null; $username = $null; $password = $null; $payload = $null
    if ($temp -and [IO.File]::Exists($temp)) { [IO.File]::Delete($temp) }
    if ($null -ne $lock) { $lock.Dispose() }
    # .NET strings cannot be reliably zeroed; plaintext was held only in process memory.
}
