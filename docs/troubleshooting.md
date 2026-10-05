# Troubleshooting

Never include tokens, passwords, decrypted credential JSON or private-key armor in an issue. Share the command, script version, program versions and sanitized error/status lines.

## Commands are not found

Check `gpg --version`, `gpg-connect-agent --version`, and `gh --version`. Reopen the terminal after installation or PATH changes. Keep BAT and PS1 files in the same `bin` directory.

## PowerShell refuses to run a downloaded script

Review the script, then remove its downloaded-file block if applicable:

```powershell
Unblock-File .\bin\maven-key.ps1
Get-ExecutionPolicy -List
```

Unblocking does not override a restrictive execution policy. On a personal machine, if organizational policy permits it, `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` permits local scripts. Do not bypass a managed policy.

## Configuration file missing

Copy `examples/config.example.json` to `$HOME/.maven-key/config.json`, then set your name and email. `maven-key` also prompts for missing values. An old `OutputRoot` setting is ignored; current keys remain in GPG.

## StandardInputEncoding property is unavailable

Windows PowerShell 5.1 lacks this `ProcessStartInfo` property. Current scripts test for its existence and configure console input encoding before creating the process. Replace the older scripts rather than adding this property unconditionally.

## Bad passphrase despite typing the correct password

Use the latest scripts. The Windows .NET stdin BOM issue was observed during development: invisible prefix bytes can change the passphrase GPG receives. Current wrappers set BOM-free UTF-8 before `Process.Start()`.

Check which password is requested: GitHub block, Maven block, or signing key. Do not recreate encrypted credentials until you have established that their passwords or data are wrong. Diagnostic GPG status codes can distinguish agent, passphrase and key-state failures. Setup deliberately tests signing before changing GitHub.

## AllowSetForegroundWindow failed: Access is denied

This message concerns GPG's ability to bring a dialog to the foreground; by itself it does not prove the operation failed. For key generation or a command that uses Pinentry, check Alt+Tab/taskbar. Current credential save/setup prompts use PowerShell. Inspect the final exit status and subsequent messages.

If the agent is stuck, cancel the active operation before restarting it:

```powershell
gpgconf --kill gpg-agent
```

## No matching namespace key

```powershell
list-keys -SecretOnly
gpg --list-secret-keys --with-fingerprint
```

Use the exact namespace comment passed to `maven-key`. Matching is case-sensitive. A key created outside these tools without that comment is not automatically selected. If several keys match, select one or provide `-Fingerprint`.

## Environment creation or access fails

The token must select the target repository. Fine-grained tokens need Administration write to create environments and Environments write to configure their secrets. Editing an existing token's permissions does not require resaving its unchanged token value. If replacing the token, run `save-credentials -Only GitHub`.

Environment lookup diagnostics show the HTTP code. A 404 can mean missing or inaccessible; the script attempts creation after validation. A 403 may reflect permissions, organization policy or account/plan restrictions. Inspect the repository's Settings > Environments. Existing environment protection settings are not intentionally changed; automatically created environments start with no protection rules.

## All secrets saved, but verification failed

Successful `Saved:` lines indicate GitHub CLI accepted those individual writes. The script now distinguishes upload success from post-upload verification failure. Do not re-upload just to list names:

```powershell
maven-github-env-setup -Repository "owner/repository" -VerifyOnly
```

Verification uses a paginated GitHub API request. If it fails, inspect the sanitized API/CLI error. You can also inspect the environment in GitHub's settings. Secret values are not readable through the API.

## Publishing workflow cannot find secrets

Ensure the job declares the same environment name and references the exact names configured by setup. The script defaults to `SIGNING_IN_MEMORY_KEY` and `SIGNING_IN_MEMORY_KEY_PASSWORD`, but your workflow may use other names. Pass the naming overrides documented in [commands](commands.md).

## Rotating or deleting credentials and keys

Use `save-credentials -Only GitHub` or `-Only MavenCentral` for local credential rotation, then rerun setup where needed. Regenerating a signing key does not update existing repositories or keyservers automatically.

Deleting a key from your local keyring does not revoke it or remove its public keyserver copy. Keep appropriate backups and revocation material before deleting anything. Older private-key export folders created before the keyring-only workflow are not automatically removed by these tools.
