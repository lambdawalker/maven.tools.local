# Maven publishing tools

Windows PowerShell tools for preparing Maven Central publishing: generate namespace-specific GPG signing keys, publish public keys, save encrypted credentials, and configure GitHub Actions environment secrets.

These tools prepare credentials and signing infrastructure. They do **not** build artifacts, register a Central namespace, configure Gradle/Maven, or trigger a release.

## Commands

| Command | Purpose |
| --- | --- |
| `maven-key` | Generate a signing key in your GPG keyring; no exported key files |
| `list-keys` | Display identities, fingerprints, subkeys and expiration with colors |
| `upload` | Validate a local signing key and publish its public key to a keyserver |
| `save-credentials` | Save GitHub and Maven credentials as separately encrypted blocks |
| `maven-github-env-setup` | Create a missing GitHub environment and configure its secrets |

Each command has a PowerShell script and a BAT launcher in [`bin`](bin). The earlier misspelling `maven-githug-env-setup` remains available as a compatibility BAT launcher.

## Install

Requires Windows PowerShell **5.1**, [Gpg4win/GnuPG](https://www.gpg4win.org/), and [GitHub CLI](https://cli.github.com/) for GitHub setup. The BAT launchers use `powershell.exe`. PowerShell 7 compatibility has not been comprehensively tested.

```powershell
git clone https://github.com/lambdawalker/maven.tools.publish.git
cd maven.tools.publish

gpg --version
gh --version
```

Run directly with `.\bin\maven-key.bat`, or add this repository's `bin` directory to your user PATH:

```powershell
$toolsBin = (Resolve-Path .\bin).Path
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($toolsBin -notin ($userPath -split ';')) {
    $parts = @($userPath, $toolsBin) | Where-Object { $_ }
    [Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), 'User')
}
```

Reopen your terminal. You can now invoke commands from any directory. Keep each BAT beside its corresponding PS1. Review downloaded scripts before using `Unblock-File` if Windows marks them as downloaded. See [troubleshooting](docs/troubleshooting.md) for execution-policy restrictions.

## Configure key defaults

```powershell
New-Item -ItemType Directory -Force "$HOME\.maven-key" | Out-Null
Copy-Item .\examples\config.example.json "$HOME\.maven-key\config.json"
notepad "$HOME\.maven-key\config.json"
```

Edit the example name and email before generating a key. Do not overwrite an existing configuration if you have already customized it.

```json
{
  "Name": "Your Name",
  "Email": "you@example.com",
  "KeyType": "rsa",
  "KeySize": 4096,
  "Expires": "2y"
}
```

Priority is **command-line value → configuration → interactive prompt**. A missing config file is explicitly reported. There are no built-in generation defaults; the namespace is required per run and is not a shared configuration setting. `OutputRoot` from older versions is ignored.

## End-to-end setup

Use one consistent namespace label for the following commands. It is a key comment used to find your key, not proof of ownership of a Maven Central namespace.

```powershell
# 1. Generate a key; choose its signing passphrase in GPG.
maven-key -Namespace "com.example.library"

# 2. Review the key and publish its public part.
list-keys -SecretOnly
upload -Namespace "com.example.library"

# 3. Save GitHub and Central Portal credentials, each with its own encryption password.
save-credentials

# 4. Configure the repository's maven-central environment.
maven-github-env-setup -Repository "owner/repository" -Namespace "com.example.library"

# 5. Check secret names later without writing or uploading anything.
maven-github-env-setup -Repository "owner/repository" -VerifyOnly
```

`upload -ValidateOnly` performs local signing validation without publishing a public key. Keyserver publication makes the key's identities (including name, email and namespace comment) public.

GitHub setup locates the key, validates its state, tests the exact signing passphrase, exports the private key into process memory, and submits secrets through GitHub CLI. The private export is not written to a file. Temporary test files and encrypted-block copies are removed afterward.

## GitHub token permissions

Use a fine-grained personal access token restricted to your intended repositories:

| Repository permission | Access | Purpose |
| --- | --- | --- |
| Administration | Read and write | Create a missing environment |
| Environments | Read and write | Configure and verify environment secrets |
| Metadata | Read (automatically included) | Repository metadata |

The token owner must also have appropriate repository access. Organization approval/policies may apply. If environments already exist, creation is unnecessary; Administration write is specifically needed for creation. Tokens cannot grant access their owner does not have.

GitHub setup automatically attempts creation after a 404 response and after local signing validation. A 404 can also mean inaccessible resources; check permissions if creation fails. Newly created environments have no protection rules. Configure any required reviewers or branch restrictions in GitHub. Existing environment settings are not deliberately changed.

## Secret names must match your workflow

| Default secret | Value |
| --- | --- |
| `SIGNING_KEY` | Complete ASCII-armored private signing key |
| `SIGNING_PASSWORD` | Signing-key passphrase |
| `MAVEN_CENTRAL_USERNAME` | Central Portal token username |
| `MAVEN_CENTRAL_PASSWORD` | Central Portal token password |

These are defaults, not universal names. Override them to match the workflow you already have:

```powershell
maven-github-env-setup -Repository "owner/repository" -Namespace "com.example.library" `
  -SigningKeySecret "GPG_PRIVATE_KEY" -SigningPasswordSecret "GPG_PASSPHRASE"
```

`-SigningKeyIdSecret NAME` optionally adds a secret containing the full fingerprint. Its format must suit your build plugin. A workflow job must reference `environment: maven-central` to consume that environment's secrets.

Uploads replace existing secrets with the selected names. Uploads are sequential, not transactional. Verification confirms names exist, not secret contents, Central token validity, or publishing success. GitHub does not expose stored secret values for readback.

## Documentation

- [Command reference](docs/commands.md)
- [Credentials and security model](docs/security.md)
- [Troubleshooting](docs/troubleshooting.md)

## Validation status

The scripts were developed iteratively with user-reported Windows PowerShell 5.1 runs, including key generation, credential encryption/decryption, signing and successful GitHub secret uploads. Not every combination of flags has been runtime-tested. The final API-based verification path was statically reviewed; a comprehensive automated Windows test suite is not yet included.

No real credentials, encrypted credential stores, private-key exports or user-specific key fingerprints are included in this repository.
