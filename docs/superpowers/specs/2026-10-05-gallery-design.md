# PowerShell Gallery package

Prepare the existing Windows Maven signing toolkit for Gallery distribution as
Apexfission.MavenTools 0.1.0, licensed Apache-2.0 (selected by the maintainer).
Preserve credential format v1, parameter defaults, GPG keyring behavior and secret
names. Export New-MavenSigningKey, Get-MavenSigningKey, Publish-MavenPublicKey,
Save-MavenCredentials, Set-MavenGitHubEnvironment and Test-MavenToolsDependency.

Each command has one implementation under the module Public directory. Existing
correctly spelled bin scripts become thin forwarding wrappers. Delete the exact
misspelled BAT duplicate. Import must not prompt, require native tools, or mutate
keys, credentials, environment settings or caller preferences. Windows PowerShell
5.1 and PowerShell 7 on Windows are the supported targets; other OSes are not
claimed supported by this release.

Build an allowlisted staging directory with manifest, module code, docs, example
config and Apache license. Validate syntax, exports, help and command boundaries;
exercise GPG only with temporary test keyrings and mock GitHub interactions.
CI covers both Windows shells. Tag release vX.Y.Z must match ModuleVersion and
pass validation before a publish job reads PSGALLERY_API_KEY from the psgallery
environment. Do not create a tag or publish a Gallery package during preparation.
Document account registration, scoped API key, first release, version updates,
and the difference between Gallery authentication, Maven GPG and Authenticode.
