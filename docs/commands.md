# Command reference

Commands below use the installed PowerShell module. Correctly spelled legacy launchers remain available in a full source checkout; they forward parameters to these functions. Execution policy still applies.

## New-MavenSigningKey

```powershell
New-MavenSigningKey -Namespace "com.example.library"
New-MavenSigningKey -Namespace "com.example.library" -Email "publisher@example.com" -Expires "1y"
```

Parameters: `Namespace`, `Name`, `Email`, `KeyType`, `KeySize`, `Expires`, `ConfigPath`.

- Config defaults to `$HOME/.maven-key/config.json`.
- Required missing values are prompted. Config may omit settings or leave them null/blank.
- Only RSA is currently supported; sizes: 2048, 3072, 4096.
- Expiration accepts GPG durations such as `2y`, dates such as `2028-10-01`, or `0` for no expiration. GPG performs final date validation.
- Namespace uses dot-separated letters/digits/underscores/hyphens, up to 150 characters. For compatibility, Windows device names are rejected.
- User ID is `Name (Namespace) <Email>`.
- GPG requests the new signing passphrase. Key and revocation certificate remain managed by GPG.
- The command prints the new fingerprint. It does not export, upload or publish an artifact.
- The old `ExistingFingerprint` and `OutputRoot` command parameters are no longer used. Legacy `OutputRoot` in JSON is tolerated and ignored.

## Get-MavenSigningKey

```powershell
Get-MavenSigningKey
Get-MavenSigningKey -SecretOnly
Get-MavenSigningKey -NoColor
Get-MavenSigningKey -ExpiringWithinDays 60
```

| Color | Meaning |
| --- | --- |
| White | Identity name |
| Cyan | Email |
| Magenta | Comment / namespace |
| Yellow | ID/fingerprint or soon-expiring date |
| Red | Expired date or revoked/disabled/invalid status |
| Green | Unexpired date/status |

Dates are local time. Default upcoming-expiration threshold: 30 days. Public listing includes your own public keys as well as imported keys. Secret-only listing can include hardware references or unavailable stubs. Expiration status is not identity trust.

Capability letters: `s` signing, `c` certification, `e` encryption, `a` authentication. Lowercase letters describe that key; uppercase letters on the primary record summarize usable capabilities across the key and subkeys. Maven publishing needs signing, not encryption.

## Publish-MavenPublicKey

```powershell
Publish-MavenPublicKey -Namespace "com.example.library"
Publish-MavenPublicKey -Namespace "com.example.library" -ValidateOnly
Publish-MavenPublicKey -Namespace "com.example.library" -Fingerprint "FULL_40_CHARACTER_FINGERPRINT"
```

Parameters: `Namespace`, `Fingerprint`, `Keyserver`, `ValidateOnly`.

Default server: `hkps://keyserver.ubuntu.com`. Namespace is prompted if absent. Multiple matching keys require selection; use a full fingerprint to disambiguate. The script uses exact, case-sensitive namespace comments.

Checks key state, primary signing capability, creation/expiration dates, then signs a temporary challenge and verifies the exact fingerprint. Private keys stay in the keyring; only the public key is sent. A successful upload response does not prove immediate keyserver propagation.

There is no `KeyDirectory` or export-folder configuration in the current version. Older keys without the namespace comment are not automatically matched.

## Save-MavenCredentials

```powershell
Save-MavenCredentials
Save-MavenCredentials -Only GitHub
Save-MavenCredentials -Only MavenCentral
Save-MavenCredentials -Path "$HOME/.maven-key/github-maven.json"
```

Default `Only`: `All`. Default path: `$HOME/.maven-key/github-maven.json`.

Prompts are hidden. The script asks for the GitHub token and an encryption password twice, followed by Central token username/password and a separate encryption password twice. It compares confirmations exactly, including case. Choose different encryption passwords; the script does not enforce that they differ.

When updating one provider, the other encrypted block is retained. A first-time provider-only save leaves the other block null; setup requires both. Existing data is replaced only after successful encryption. The empty `.lock` file can remain; it contains no secret and serializes cooperating script runs.

## Set-MavenGitHubEnvironment

```powershell
Set-MavenGitHubEnvironment -Repository "owner/repository" -Namespace "com.example.library"
Set-MavenGitHubEnvironment -Repository "owner/repository" -VerifyOnly
```

| Parameter | Default / behavior |
| --- | --- |
| `Repository` | Prompt for `owner/repository`; GitHub.com only |
| `Namespace` | Prompt; not required in VerifyOnly |
| `Fingerprint` | Optional full 40-character fingerprint |
| `Environment` | `maven-central` |
| `CredentialsPath` | `$HOME/.maven-key/github-maven.json` |
| `SigningKeySecret` | `SIGNING_IN_MEMORY_KEY` |
| `SigningPasswordSecret` | `SIGNING_IN_MEMORY_KEY_PASSWORD` |
| `MavenUsernameSecret` | `MAVEN_CENTRAL_USERNAME` |
| `MavenPasswordSecret` | `MAVEN_CENTRAL_PASSWORD` |
| `SigningKeyIdSecret` | Omitted; optionally stores full fingerprint |
| `VerifyOnly` | Read secret names only; no key export, uploads or environment creation |
| `CreateEnvironment` | Legacy compatibility switch; creation is now automatic |

Normal setup unlocks both credential blocks and asks for the signing-key passphrase. The selected key's agent cache is cleared first so a cached password cannot hide an incorrect supplied phrase. The script validates a signature before exporting the private key in memory.

Hardware-only keys that cannot be exported are not suitable for this CI-secret workflow. Environment creation occurs after local checks. No build/release workflow is started. Partial upload failures are not rolled back; rerun with the same values after resolving the error. If all uploads succeeded but verification failed, use `-VerifyOnly` instead.

## Test-MavenToolsDependency

```powershell
Test-MavenToolsDependency
```

Returns one object per native program (`gpg`, `gpg-connect-agent`, `gh`) with
`Name`, `Available`, and `Path`. Does not execute or install programs. Missing
programs are reported as data, not terminating errors. Only the commands that
need a dependency require it to be installed.

## Migration

The duplicate typo launcher `maven-githug-env-setup.bat` was removed. Use the
corrected `maven-github-env-setup.bat` or `Set-MavenGitHubEnvironment`. All correctly
spelled source launchers and existing command parameters remain supported.
Credential format v1 and `$HOME/.maven-key` paths are unchanged.
