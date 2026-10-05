# Publishing Apexfission.MavenTools

The package is prepared as version **0.1.0**, licensed under Apache-2.0.
Preparing this repository does not publish anything to PowerShell Gallery.
The first successful publish establishes ownership of an available package name;
the repository name alone does not reserve it. Check name availability before
creating the first tag. If another owner has it, choose a new module name first.

## One-time maintainer setup

1. Register at [PowerShell Gallery](https://www.powershellgallery.com/) using a
   personal Microsoft account or a work/school account. Complete the Gallery
   profile and email confirmation. No separate nuget.org account is needed.
2. Open your Gallery account's **API Keys** page and create a scoped key:
   - Name: `maven-tools-github-actions` (a descriptive label).
   - Permission: **Push new or update packages**.
   - Package glob pattern: `Apexfission.MavenTools` (the exact name).
   - Choose an expiration and arrange to rotate the secret before it expires.
   - Copy the key immediately. Do not put it in source code or chat.
3. In this GitHub repository open **Settings > Environments**, create `psgallery`,
   and add an **environment secret** named `PSGALLERY_API_KEY` containing that key.
   The workflow must use that exact environment and secret name. A Maven Central
   token, GitHub PAT, or GPG signing key cannot substitute for this API key.
4. Enable GitHub Actions if it is disabled. Optional: add a required reviewer to
   `psgallery`. If you restrict deployment refs, allow release tags `v*` and `main`
   for manual retries launched from main. The release script independently
   requires the tagged commit to belong to `origin/main`.

## Do I need to sign the scripts?

**No code-signing certificate is required to publish to Gallery.** Microsoft
recommends signing as a best practice; this first workflow publishes unsigned code.

There are three separate concepts:

| Credential | Purpose | Required here? |
| --- | --- | --- |
| Gallery API key | Authorizes uploading module versions | Yes, for the maintainer |
| GPG/OpenPGP key | Signs Maven artifacts using the tools in this module | For Maven publishing, not Gallery authentication |
| Authenticode code-signing certificate | Signs PowerShell files for Windows publisher trust/execution policies | Optional for Gallery; required where the consumer's policy requires it |

Authenticode uses an X.509 code-signing certificate, not your Maven GPG key. For
public distribution, use a certificate whose issuing authority is trusted by your
users. A self-signed certificate is useful for testing but is not automatically
trusted by other computers. A certificate from an internal CA can serve a managed
organization that trusts that CA.

If signing is added later, sign the staged `.ps1`, `.psm1` and `.psd1` files on
Windows, timestamp the signatures, validate them, then publish those exact files.
Do not change bytes or line endings afterward. Never commit a certificate private
key or password. The current workflow does not bypass consumer execution policies.

## First release

Merge the preparation PR into `main` and wait for **Validate PowerShell module**
to pass. The tests use temporary keyrings and dummy credentials, not your keys.
Then, in your local clone:

```powershell
git switch main
git pull --ff-only
git tag -a v0.1.0 -m "Apexfission.MavenTools 0.1.0"
git push origin v0.1.0
```

The tag starts **Publish to PowerShell Gallery**. It:

1. Checks out the tag and validates its name, manifest version and main ancestry.
2. Tests both Windows PowerShell 5.1 and PowerShell 7 on Windows.
3. Runs ScriptAnalyzer, stages the allowlisted package, and on PowerShell 7 tests
   publishing to and loading from a temporary local package feed.
4. Enters `psgallery` and publishes using `PSGALLERY_API_KEY`.

After Gallery makes the package available, users can run:

```powershell
Install-Module Apexfission.MavenTools -Scope CurrentUser -Repository PSGallery
Import-Module Apexfission.MavenTools
Test-MavenToolsDependency
Get-Help New-MavenSigningKey -Full
```

GnuPG/Gpg4win and GitHub CLI remain separately installed native dependencies.
The module does not silently install them. It supports Windows; successful test
execution on another platform alone is not a cross-platform support promise.

## Retry and subsequent releases

For an unsuccessful upload (for example a missing/expired API key), fix the setup,
then run **Publish to PowerShell Gallery** manually from Actions on `main`, passing
the existing tag in the `tag` input. Automatic and manual runs share one concurrency
group with cancellation of running work disabled. GitHub may replace an older
pending run if several are queued; rerun the needed tag afterward.

Gallery versions are immutable. If a version already exists, this workflow fails
rather than claiming a new upload or overwriting it. If an upload succeeded but the
run was interrupted afterward, check Gallery before retrying. Do not move released
tags. Bump `ModuleVersion`, update CHANGELOG.md, merge, and create the matching
`vX.Y.Z` tag for the next release. No GitHub Release entry is required by the workflow.

## Local contributor validation

Install the test tools once:

```powershell
Install-Module Pester -RequiredVersion 5.7.1 -Scope CurrentUser
Install-Module PSScriptAnalyzer -RequiredVersion 1.23.0 -Scope CurrentUser
```

Run from the repository root in Windows PowerShell 5.1 and PowerShell 7:

```powershell
./scripts/Test-Module.ps1
Invoke-ScriptAnalyzer -Path ./src -Recurse
./scripts/Build-Module.ps1
```

The build writes `dist/Apexfission.MavenTools` and returns its absolute path. It
refuses to overwrite an existing staging directory; remove your previous `dist`
build explicitly or provide `-OutputDirectory` pointing to a new directory.
Only explicit source/docs/example paths are packaged; local credentials, keys,
`.git`, CI files and compatibility launchers are excluded.

The tests cover module loading, exports/help, parameter validation, wrapper
compatibility, credential encryption and preservation, and package contents.
Interactive key generation, keyserver publication and actual GitHub secret writes
still require manual end-to-end testing with disposable credentials. CI deliberately
does not publish keys, contact GitHub with user credentials, or use real secrets.

## References

- [Gallery account and publishing requirements](https://learn.microsoft.com/en-us/powershell/gallery/how-to/publishing-packages/publishing-a-package)
- [Scoped API keys](https://learn.microsoft.com/en-us/powershell/gallery/how-to/managing-profile/creating-apikeys)
- [Gallery publishing guidelines](https://learn.microsoft.com/en-us/powershell/gallery/concepts/publishing-guidelines)
- [PowerShell Authenticode signing](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_signing)
