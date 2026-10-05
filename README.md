# Apexfission Maven Tools

A Windows PowerShell module for preparing Maven Central publishing: generate namespace-specific GPG signing keys, publish public keys, save encrypted credentials, and configure GitHub Actions environment secrets.

These tools prepare credentials and signing infrastructure. They do **not** build artifacts, register a Central namespace, configure Gradle/Maven, or trigger a release.

## Install

**The module is prepared for its first release.** The Gallery install command below
will work after version 0.1.0 has been published. Maintainers: follow the
[Gallery publishing guide](docs/publishing.md) to create the account/API key and release.

```powershell
Install-Module Apexfission.MavenTools -Scope CurrentUser -Repository PSGallery
Import-Module Apexfission.MavenTools
Test-MavenToolsDependency
```

Requires Windows PowerShell **5.1** or **PowerShell 7 on Windows**,
[Gpg4win/GnuPG](https://www.gpg4win.org/), and
[GitHub CLI](https://cli.github.com/) for GitHub environment setup.
Native dependencies are installed separately; importing the module never changes
keys or credentials. Linux/macOS are not supported targets in this release.

To use the source before publication:

```powershell
git clone https://github.com/lambdawalker/maven.tools.local.git
cd maven.tools.local
Import-Module ./src/Apexfission.MavenTools/Apexfission.MavenTools.psd1
```

## Commands

| Module command | Legacy launcher | Purpose |
| --- | --- | --- |
| `New-MavenSigningKey` | `maven-key` | Generate a signing key in your GPG keyring |
| `Get-MavenSigningKey` | `list-keys` | Display identities, fingerprints and expiration |
| `Publish-MavenPublicKey` | `upload` | Validate signing and publish the public key |
| `Save-MavenCredentials` | `save-credentials` | Save independently encrypted credential blocks |
| `Set-MavenGitHubEnvironment` | `maven-github-env-setup` | Configure or verify GitHub environment secrets |
| `Test-MavenToolsDependency` | None | Check native tools on PATH without running them |

Use `Get-Help <command> -Full` for help and examples. The correctly spelled PS1/BAT
launchers remain in `bin` for source-clone users and forward to the same module
implementation. Keep the whole checkout together if you add `bin` to PATH.
The redundant typo launcher `maven-githug-env-setup.bat` was removed; use
`maven-github-env-setup.bat`. Gallery installs expose module commands, not BAT launchers.

## Configure key defaults

```powershell
New-Item -ItemType Directory -Force "$HOME\.maven-key" | Out-Null
Copy-Item (Join-Path (Get-Module Apexfission.MavenTools).ModuleBase "examples/config.example.json") "$HOME\.maven-key\config.json"
notepad "$HOME\.maven-key\config.json"
```

For source imports, copy `./examples/config.example.json` instead.
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
New-MavenSigningKey -Namespace "com.example.library"

# 2. Review the key and publish its public part.
Get-MavenSigningKey -SecretOnly
Publish-MavenPublicKey -Namespace "com.example.library"

# 3. Save GitHub and Central Portal credentials, each with its own encryption password.
Save-MavenCredentials

# 4. Configure the repository's maven-central environment.
Set-MavenGitHubEnvironment -Repository "owner/repository" -Namespace "com.example.library"

# 5. Check secret names later without writing or uploading anything.
Set-MavenGitHubEnvironment -Repository "owner/repository" -VerifyOnly
```

`Publish-MavenPublicKey -ValidateOnly` performs local signing validation without publishing a public key. Keyserver publication makes the key's identities (including name, email and namespace comment) public.

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
| `SIGNING_IN_MEMORY_KEY` | Complete ASCII-armored private signing key |
| `SIGNING_IN_MEMORY_KEY_PASSWORD` | Signing-key passphrase |
| `MAVEN_CENTRAL_USERNAME` | Central Portal token username |
| `MAVEN_CENTRAL_PASSWORD` | Central Portal token password |

These are defaults, not universal names. Override them to match the workflow you already have:

```powershell
Set-MavenGitHubEnvironment -Repository "owner/repository" -Namespace "com.example.library" `
  -SigningKeySecret "GPG_PRIVATE_KEY" -SigningPasswordSecret "GPG_PASSPHRASE"
```

`-SigningKeyIdSecret NAME` optionally adds a secret containing the full fingerprint. Its format must suit your build plugin. A workflow job must reference `environment: maven-central` to consume that environment's secrets.

Uploads replace existing secrets with the selected names. Uploads are sequential, not transactional. Verification confirms names exist, not secret contents, Central token validity, or publishing success. GitHub does not expose stored secret values for readback.

## Documentation

- [Command reference](docs/commands.md)
- [Credentials and security model](docs/security.md)
- [Troubleshooting](docs/troubleshooting.md)

## Validation and releases

CI validates syntax, help, exports, wrapper compatibility, isolated GPG credential
round-trips, and staged package contents on Windows PowerShell 5.1 and PowerShell 7.
Actual keyserver uploads and GitHub secret writes are not performed by CI.
See [publishing](docs/publishing.md) for the test commands, tag-based release workflow,
account setup, and optional Authenticode signing. Gallery authentication uses its own
API key; it does not use your Maven signing key.

No real credentials, encrypted credential stores, private-key exports or
user-specific key fingerprints are included in the repository or package.

## License

[Apache License 2.0](LICENSE). See [NOTICE](NOTICE) and [CHANGELOG](CHANGELOG.md).
