#requires -Version 5.1
<#
Configure GitHub.com Actions environment secrets using github-maven.json.
Requires Gpg4win (gpg and gpg-connect-agent) and GitHub CLI (gh).
Use -Repository owner/repo -VerifyOnly to check names without changing secrets.
VerifyOnly only prompts to unlock the GitHub credential block.

  maven-github-env-setup -Repository owner/repo -Namespace com.example.library
  maven-github-env-setup -Repository owner/repo -Namespace com.example.library -CreateEnvironment

The default environment is maven-central. A missing environment is created
automatically after local validation succeeds. Existing secrets with the selected
names are replaced; other secrets and environment protection rules are preserved.
No workflow is dispatched. Uploads are sequential, not transactional. On failure,
completed secret names are reported; rerun to finish. Secret values cannot be
read back from GitHub. GitHub token needs access to the selected repository and
permission to manage environment secrets (fine-grained: Environments write).
Creating environments may require additional repository administration rights.

Credential format: save-credentials.ps1 version 1, stored by default at
$HOME/.maven-key/github-maven.json. Hidden PowerShell password prompts unlock each encrypted block through GPG loopback input.
The signing passphrase is requested separately via a hidden PowerShell prompt.
No plaintext credential or private-key export is written to disk. Temporary
signing-test data, signatures, and encrypted credential-block copies are deleted. GPG still owns its normal keyring.
The selected key's passphrase cache is cleared before testing the supplied phrase.

Default secret names (override to match your workflow): SIGNING_IN_MEMORY_KEY,
SIGNING_IN_MEMORY_KEY_PASSWORD, MAVEN_CENTRAL_USERNAME, MAVEN_CENTRAL_PASSWORD.
Optional -SigningKeyIdSecret NAME adds the full fingerprint as another secret.
#>
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
Set-StrictMode -Version Latest
$executables = @{}
foreach ($name in @('gpg','gpg-connect-agent','gh')) {
    $command = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $command) { throw "Required program missing from PATH: $name" }
    $executables[$name] = $command.Source
}
# Quote arguments for Windows CreateProcess (no shell and no secret arguments).
function Quote-Argument([string]$Value) {
    $escaped = [regex]::Replace($Value, '(\\*)"', '$1$1\"')
    $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
    return '"' + $escaped + '"'
}
function Run-Program {
    param([string]$Program, [string[]]$Arguments, [string]$InputText = '', [string]$Token = '')
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $executables[$Program]
    $start.Arguments = (($Arguments | ForEach-Object { Quote-Argument $_ }) -join ' ')
    $start.UseShellExecute = $false
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $start.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    if ($Program -eq 'gh') {
        $start.EnvironmentVariables['GH_TOKEN'] = $Token
        $start.EnvironmentVariables['GH_HOST'] = 'github.com'
        $start.EnvironmentVariables['GH_PROMPT_DISABLED'] = '1'
        $start.EnvironmentVariables['GH_NO_UPDATE_NOTIFIER'] = '1'
        $start.EnvironmentVariables.Remove('GH_DEBUG')
        $start.EnvironmentVariables.Remove('DEBUG')
    }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    $started = $false
    $bytes = $null
    try {
        # .NET Framework constructs stdin's StreamWriter with Console.InputEncoding
        # and AutoFlush, which can emit a BOM before our BaseStream byte writes.
        # Select BOM-free UTF-8 BEFORE Start; restore the console immediately after.
        $previousInputEncoding = [Console]::InputEncoding
        try {
            [Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
            if ($null -ne $start.PSObject.Properties['StandardInputEncoding']) {
                $start.StandardInputEncoding = [Text.UTF8Encoding]::new($false)
            }
            $started = $process.Start()
        } finally { [Console]::InputEncoding = $previousInputEncoding }
        if (-not $started) { throw "Could not start $Program." }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $bytes = [Text.Encoding]::UTF8.GetBytes($InputText)
        try {
            $stream = $process.StandardInput.BaseStream
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush()
        } finally { $process.StandardInput.Close() }
        $process.WaitForExit()
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            Output = $stdout.GetAwaiter().GetResult()
            ErrorText = $stderr.GetAwaiter().GetResult()
        }
    } finally {
        if ($null -ne $bytes) { [Array]::Clear($bytes, 0, $bytes.Length) }
        if ($started -and -not $process.HasExited) { $process.Kill() }
        $process.Dispose()
        $InputText = $null; $Token = $null
        $start.EnvironmentVariables.Remove('GH_TOKEN')
    }
}
function Require-Success($Result, [string]$Message) {
    # Do not echo native output: some operations return secret material on stdout.
    if ($Result.ExitCode -ne 0) { throw "$Message (exit $($Result.ExitCode)). No secret values are printed." }
}
function Require-GpgSuccess($Result, [string]$Operation) {
    if ($Result.ExitCode -eq 0) { return }
    $details = [Collections.Generic.List[string]]::new()
    foreach ($line in ($Result.ErrorText -split '\r?\n')) {
        if ($line -match '^\[GNUPG:\] (BAD_PASSPHRASE|MISSING_PASSPHRASE|NO_SECKEY|KEYEXPIRED|KEYREVOKED|INV_SGNR|FAILURE|ERROR)(?: |$)') {
            $tag = $Matches[1]
            if ($line -match '^\[GNUPG:\] (?:ERROR|FAILURE) ([A-Za-z0-9_.-]+) ([0-9]+)$') {
                $tag += ' operation=' + $Matches[1] + ' code=' + $Matches[2]
            }
            $details.Add($tag)
        }
    }
    $hint = 'The underlying cause is not yet established.'
    if ($Result.ErrorText -match 'Bad passphrase|BAD_PASSPHRASE') {
        $hint = 'GPG rejected the supplied signing passphrase. This may be the entered value or the stdin input path; do not change your saved credential passwords.'
    } elseif ($Result.ErrorText -match 'No secret key|NO_SECKEY') {
        $hint = 'GPG could not use the selected private key.'
    } elseif ($Result.ErrorText -match 'Not supported|not allowed|Forbidden') {
        $hint = 'GPG/agent rejected an operation; loopback input may be restricted.'
    } elseif ($Result.ErrorText -match 'No agent running|failed to start.*agent|can.t connect.*agent') {
        $hint = 'GPG could not start or connect to its agent.'
    }
    $status = ($details | Select-Object -Unique) -join ', '
    if (-not $status) { $status = 'No recognized machine-readable status returned.' }
    throw "$Operation failed (exit $($Result.ExitCode)). $hint GPG status: $status"
}
function Verify-EnvironmentSecrets([string]$Token) {
    $endpoint = "repos/$Repository/environments/" + [Uri]::EscapeDataString($Environment) + '/secrets?per_page=100'
    $check = Run-Program 'gh' @('api','--hostname','github.com','--paginate',$endpoint,'--jq','.secrets[].name') '' $Token
    if ($check.ExitCode -ne 0) {
        # This GET returns secret names/metadata only. Redact the token defensively.
        $detail = $check.ErrorText.Replace($Token, '[REDACTED]')
        $detail = [regex]::Replace($detail, '[\p{Cc}\p{Cf}]', ' ')
        if ($detail.Length -gt 600) { $detail = $detail.Substring(0,600) }
        throw "Secret-name verification failed (exit $($check.ExitCode)): $detail"
    }
    $visible = @($check.Output -split '\r?\n' | Where-Object { $_ })
    $missing = @($secretNames | Where-Object { $_ -notin $visible })
    if ($missing.Count -gt 0) { throw ('Secret names not found: ' + ($missing -join ', ')) }
    foreach ($name in $secretNames) { Write-Host "Verified: $name" -ForegroundColor Green }
}
function Read-Passphrase {
    param([string]$Prompt = 'Signing key passphrase (will become the GitHub signing-password secret)')
    $secure = Read-Host $Prompt -AsSecureString
    $pointer = [IntPtr]::Zero
    try {
        $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
        if ([string]::IsNullOrEmpty($plain) -or $plain -match '[\r\n]') { throw 'Enter a nonempty single-line passphrase.' }
        return $plain
    } finally {
        if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
        $secure.Dispose()
    }
}
function Unlock-Block($Document, [string]$Property, [string]$Label) {
    $entry = $Document.PSObject.Properties[$Property]
    if ($null -eq $entry -or $null -eq $entry.Value -or $null -eq $entry.Value.PSObject.Properties['encrypted']) {
        throw "Missing $Label credentials. Run save-credentials first."
    }
    $ciphertext = $entry.Value.encrypted
    if ($ciphertext -isnot [string] -or $ciphertext -notmatch '^\s*-----BEGIN PGP MESSAGE-----') { throw "Invalid encrypted $Label block." }
    Write-Host "Unlock $Label using the encryption password chosen in save-credentials."
    Write-Host 'This is not the GitHub token, Maven token password, or signing-key passphrase.'
    $cipherFile = $null
    $result = $null
    $unlockPassword = $null
    try {
        $unlockPassword = Read-Passphrase -Prompt "$Label credential-file encryption password"
        # Only ciphertext is written to disk. Password uses the BOM-free stdin
        # path; decrypted JSON is captured from stdout in memory.
        $cipherFile = [IO.Path]::GetTempFileName()
        [IO.File]::WriteAllText($cipherFile, $ciphertext, [Text.UTF8Encoding]::new($false))
        $result = Run-Program 'gpg' @('--no-options','--batch','--no-symkey-cache',
            '--pinentry-mode','loopback','--passphrase-fd','0','--status-fd','2','--output','-',
            '--decrypt',$cipherFile) ($unlockPassword + "`n")
        if ($result.ExitCode -ne 0) {
            # Allow-list status names and numeric codes only; never echo native
            # stdout, raw stderr, decrypted data, or user-controlled filenames.
            $details = [Collections.Generic.List[string]]::new()
            foreach ($line in ($result.ErrorText -split '\r?\n')) {
                if ($line -match '^\[GNUPG:\] (BAD_PASSPHRASE|MISSING_PASSPHRASE|DECRYPTION_FAILED|NODATA|BADMDC|ERRMDC|FAILURE|ERROR)(?: |$)') {
                    $tag = $Matches[1]
                    if ($line -match '^\[GNUPG:\] (?:ERROR|FAILURE) [A-Za-z0-9_.-]+ ([0-9]+)$') {
                        $tag += ' code=' + $Matches[1]
                    }
                    $details.Add($tag)
                }
            }
            $hint = 'Check the credential-file encryption password. The encrypted block may also be damaged, or GPG/its agent may have failed.'
            if ($result.ErrorText -match 'BAD_PASSPHRASE|Bad session key|Bad passphrase') {
                $hint = 'GPG could not unlock the data: check the credential-file encryption password; damaged encrypted data can cause the same failure.'
            }
            if ($result.ErrorText -match 'No agent running|failed to start.*agent|can.t connect.*agent') {
                $hint = 'GPG could not start or connect to its agent. Try gpgconf --kill gpg-agent and run again.'
            }
            $status = ($details | Select-Object -Unique) -join ', '
            if (-not $status) { $status = 'No recognized machine-readable status returned.' }
            throw "Unable to unlock $Label credentials (exit $($result.ExitCode)). $hint GPG status: $status"
        }
        try { return ($result.Output | ConvertFrom-Json) }
        catch { throw "Decrypted $Label credentials are not valid JSON. Run save-credentials again." }
    } finally {
            $result = $null
        $unlockPassword = $null
        if ($cipherFile -and [IO.File]::Exists($cipherFile)) { [IO.File]::Delete($cipherFile) }
    }
}
function Get-RequiredString($Object, [string]$Property) {
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Property] -or
        $Object.$Property -isnot [string] -or [string]::IsNullOrWhiteSpace($Object.$Property)) {
        throw "Credential payload is missing a valid '$Property' value."
    }
    return $Object.$Property
}
while ([string]::IsNullOrWhiteSpace($Repository)) { $Repository = Read-Host 'GitHub repository (owner/repository)' }
while (-not $VerifyOnly -and [string]::IsNullOrWhiteSpace($Namespace)) { $Namespace = Read-Host 'Software namespace' }
$Repository = $Repository.Trim(); $Namespace = $Namespace.Trim()
if ($Repository -notmatch '^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_.-]+$') { throw 'Use owner/repository, not a URL.' }
if (-not $VerifyOnly -and $Namespace -notmatch '^[A-Za-z0-9_][A-Za-z0-9_-]*(\.[A-Za-z0-9_][A-Za-z0-9_-]*)*$') { throw 'Invalid namespace.' }
if ([string]::IsNullOrWhiteSpace($Environment) -or $Environment -match '[\r\n]') { throw 'Invalid environment name.' }
if ($Fingerprint -and $Fingerprint -notmatch '^[A-Fa-f0-9]{40}$') { throw 'Use a full 40-character fingerprint.' }
$secretNames = @($SigningKeySecret,$SigningPasswordSecret,$MavenUsernameSecret,$MavenPasswordSecret)
if ($SigningKeyIdSecret) { $secretNames += $SigningKeyIdSecret }
foreach ($name in $secretNames) {
    if ($name -notmatch '^[A-Za-z_][A-Za-z0-9_]*$' -or $name -match '^GITHUB_') { throw "Invalid secret name: $name" }
}
if (@($secretNames | ForEach-Object { $_.ToUpperInvariant() } | Select-Object -Unique).Count -ne $secretNames.Count) { throw 'Secret names must be distinct.' }
if ($CredentialsPath.StartsWith('~/') -or $CredentialsPath.StartsWith('~\')) { $CredentialsPath = Join-Path $HOME $CredentialsPath.Substring(2) }
if (-not (Test-Path -LiteralPath $CredentialsPath -PathType Leaf)) { throw "Credentials file missing: $CredentialsPath. Run save-credentials first." }
try { $document = Get-Content -LiteralPath $CredentialsPath -Raw -Encoding UTF8 | ConvertFrom-Json }
catch { throw 'Credentials file is not valid JSON.' }
if ($null -eq $document -or $null -eq $document.PSObject.Properties['version'] -or $document.version -ne 1) { throw 'Unsupported credentials file format.' }
$token = $null; $maven = $null; $github = $null; $passphrase = $null; $privateKey = $null; $secrets = $null; $work = $null; $result = $null
$completed = [Collections.Generic.List[string]]::new()
try {
    if ($VerifyOnly) {
        $github = Unlock-Block $document 'github' 'GitHub'
        $token = Get-RequiredString $github 'token'
        Verify-EnvironmentSecrets $token
        Write-Host 'Verification complete. No secrets or environment settings were changed.'
        return
    }
    # Find an exact namespace comment among locally available secret keys.
    $result = Run-Program 'gpg' @('--batch','--with-colons','--with-fingerprint','--with-keygrip','--list-secret-keys')
    Require-Success $result 'Unable to list GPG keys'
    $keys = [Collections.Generic.List[object]]::new()
    $current = $null; $primary = $false
    $pattern = '\(' + [regex]::Escape($Namespace) + '\)(?:\s*<[^<>]*>)?$'
    foreach ($row in ($result.Output -split '\r?\n')) {
        $f = $row.Split(':')
        switch ($f[0]) {
            'sec' { $current = [pscustomobject]@{ Fingerprint=''; Grip=''; Fields=$f; Match=$false }; $keys.Add($current); $primary=$true }
            'ssb' { $primary=$false }
            'fpr' { if ($primary -and $null -ne $current) { $current.Fingerprint=$f[9] } }
            'grp' { if ($primary -and $null -ne $current) { $current.Grip=$f[9] } }
            'uid' { if ($null -ne $current -and $f[1] -notin @('r','e','i') -and $f[9] -cmatch $pattern) { $current.Match=$true } }
        }
    }
    $candidates = @($keys | Where-Object { $_.Match -and $_.Fingerprint })
    if ($Fingerprint) { $candidates = @($candidates | Where-Object { $_.Fingerprint -eq $Fingerprint }) }
    if ($candidates.Count -eq 0) { throw 'No matching namespace signing key found in the local GPG keyring.' }
    $selected = $null
    if ($candidates.Count -eq 1) { $selected=$candidates[0] }
    else {
        for ($i=0; $i -lt $candidates.Count; $i++) { Write-Host ("{0}. {1}" -f ($i+1),$candidates[$i].Fingerprint) }
        $choice=0
        do { $answer=Read-Host 'Choose the key number'; $valid=[int]::TryParse($answer,[ref]$choice) -and $choice -ge 1 -and $choice -le $candidates.Count } while (-not $valid)
        $selected=$candidates[$choice-1]
    }
    $fingerprint=$selected.Fingerprint; $f=$selected.Fields
    $now=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if ($f[1] -in @('r','e','d','i') -or $f[11] -cmatch 'D' -or ($f[6] -and $f[6] -ne '0' -and [long]$f[6] -le $now)) { throw 'Selected key is expired, revoked, disabled, or invalid.' }
    if ([long]$f[5] -gt $now -or $f[11] -cnotmatch 's') { throw 'Selected primary key is not currently usable for signing.' }
    if ($selected.Grip -notmatch '^[A-Fa-f0-9]{40}$') { throw 'Cannot identify the selected keygrip for passphrase validation.' }
    Write-Host "Repository: $Repository | Environment: $Environment"
    Write-Host "Namespace: $Namespace | Fingerprint: $fingerprint"
    Write-Host ('Secrets to create/update: ' + ($secretNames -join ', '))
    $github=Unlock-Block $document 'github' 'GitHub'
    $token=Get-RequiredString $github 'token'
    $result=Run-Program 'gh' @('api','--hostname','github.com',"repos/$Repository") '' $token
    Require-Success $result 'Cannot access repository; check the token and repository name'
    $environmentPath="repos/$Repository/environments/" + [Uri]::EscapeDataString($Environment)
    $result=Run-Program 'gh' @('api','--hostname','github.com','--include',$environmentPath) '' $token
    $environmentMissing=$false
    if ($result.ExitCode -ne 0) {
        $httpStatus = 'unknown'
        if ($result.Output -match '(?m)^HTTP/\S+ ([0-9]{3})\b') { $httpStatus = $Matches[1] }
        $apiMessage = 'No JSON error message returned.'
        $bodyStart = $result.Output.IndexOf('{')
        if ($bodyStart -ge 0) {
            try {
                $errorBody = $result.Output.Substring($bodyStart) | ConvertFrom-Json
                if ($null -ne $errorBody.PSObject.Properties['message']) {
                    $apiMessage = [string]$errorBody.message
                }
            } catch { }
        }
        # This is the environment GET response only. Never print request headers.
        if ($token) { $apiMessage = $apiMessage.Replace($token, '[REDACTED]') }
        $apiMessage = [regex]::Replace($apiMessage, '[\p{Cc}\p{Cf}]', ' ')
        if ($apiMessage.Length -gt 500) { $apiMessage = $apiMessage.Substring(0,500) }
        Write-Host "Environment lookup: HTTP $httpStatus - $apiMessage"
        if ($httpStatus -eq '404') {
            $environmentMissing=$true
            Write-Host "Environment '$Environment' was not found. It will be created after local validation succeeds."
        }
        else {
            throw "Cannot access '$Environment' in '$Repository' (HTTP $httpStatus). Check the token's repository access and environment permissions. Automatic creation is attempted only for HTTP 404 responses."
        }
    }
    $maven=Unlock-Block $document 'mavenCentral' 'Maven Central'
    $mavenUsername=Get-RequiredString $maven 'username'
    $mavenPassword=Get-RequiredString $maven 'password'
    $passphrase=Read-Passphrase
    # Prevent the agent cache from hiding an incorrect supplied passphrase.
    $result=Run-Program 'gpg-connect-agent' @("CLEAR_PASSPHRASE $($selected.Grip)",'/bye')
    Require-Success $result 'Unable to clear the selected signing-key cache'
    if ($result.Output -match '(?m)^ERR ' -or $result.Output -notmatch '(?m)^OK') { throw 'GPG agent did not confirm passphrase-cache clearing.' }
    $work=Join-Path ([IO.Path]::GetTempPath()) ('maven-ci-test-'+[Guid]::NewGuid().ToString('N'))
    $null=New-Item -ItemType Directory -Path $work
    $sample=Join-Path $work 'test.txt'; $signature=Join-Path $work 'test.asc'
    [IO.File]::WriteAllText($sample,[Guid]::NewGuid().ToString(),[Text.Encoding]::ASCII)
    $result=Run-Program 'gpg' @('--batch','--status-fd','2','--pinentry-mode','loopback','--passphrase-fd','0','--local-user',"$fingerprint!",'--armor','--output',$signature,'--detach-sign',$sample) ($passphrase+"`n")
    Require-GpgSuccess $result 'Signing test'
    $result=Run-Program 'gpg' @('--batch','--no-auto-key-retrieve','--status-fd','1','--verify',$signature,$sample)
    Require-Success $result 'Test signature verification failed'
    if ($result.Output -notmatch ('(?m)^\[GNUPG:\] VALIDSIG '+[regex]::Escape($fingerprint)+' ')) { throw 'Signature fingerprint did not match selected key.' }
    $result=Run-Program 'gpg' @('--batch','--status-fd','2','--pinentry-mode','loopback','--passphrase-fd','0','--armor','--export-secret-keys',$fingerprint) ($passphrase+"`n")
    Require-GpgSuccess $result 'Private key export'
    $privateKey=$result.Output.Trim()+"`n"
    if ($privateKey -notmatch '(?s)^-----BEGIN PGP PRIVATE KEY BLOCK-----.*-----END PGP PRIVATE KEY BLOCK-----\s*$') { throw 'Expected an armored private key from GPG.' }
    $result=$null
    $secrets=[ordered]@{}
    $secrets[$SigningKeySecret]=$privateKey; $secrets[$SigningPasswordSecret]=$passphrase
    $secrets[$MavenUsernameSecret]=$mavenUsername; $secrets[$MavenPasswordSecret]=$mavenPassword
    if ($SigningKeyIdSecret) { $secrets[$SigningKeyIdSecret]=$fingerprint }
    Write-Host 'Local signing validation passed. Applying GitHub environment secrets.'
    if ($environmentMissing) {
        $result=Run-Program 'gh' @('api','--hostname','github.com','--method','PUT',$environmentPath) '' $token
        Require-Success $result 'Could not create environment; check administration permissions'
        Write-Host "Created environment: $Environment (no protection rules configured)."
    }
    foreach ($entry in $secrets.GetEnumerator()) {
        $result=Run-Program 'gh' @('secret','set',$entry.Key,'--repo',"github.com/$Repository",'--env',$Environment,'--app','actions') $entry.Value $token
        Require-Success $result "Could not set $($entry.Key); check environment write permissions"
        $completed.Add($entry.Key)
        Write-Host "Saved: $($entry.Key)" -ForegroundColor Green
    }
    Verify-EnvironmentSecrets $token
    Write-Host 'Setup complete. GitHub accepted all secrets and their names were verified. No workflow was started.' -ForegroundColor Green
} catch {
    if ($completed.Count -eq $secretNames.Count) {
        Write-Warning 'All secret uploads succeeded. Only post-upload verification failed. Use -VerifyOnly to retry without uploading again.'
    } elseif ($completed.Count -gt 0) {
        Write-Warning ('Uploads completed before failure: '+($completed -join ', ')+'. Values cannot be rolled back automatically.')
    }
    throw
} finally {
    $token=$null; $github=$null; $maven=$null; $passphrase=$null; $privateKey=$null; $secrets=$null; $result=$null
    $mavenUsername=$null; $mavenPassword=$null
    if ($work -and (Test-Path -LiteralPath $work)) {
        try { Remove-Item -LiteralPath $work -Recurse -Force } catch { Write-Warning "Remove leftover signing-test files manually: $work" }
    }
    # Managed strings cannot be reliably zeroed; secrets existed in process memory only.
}
