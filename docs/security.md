# Credentials and security model

## Three different passwords

| Password | What it protects | Where entered |
| --- | --- | --- |
| GitHub credential-file encryption password | Saved GitHub personal access token | Save/ setup PowerShell prompt |
| Maven credential-file encryption password | Saved Central Portal username/password pair | Save/ setup PowerShell prompt |
| Signing-key passphrase | GPG private signing key; uploaded as signing-password secret | GPG during generation, PowerShell during CI setup |

The Maven token password is itself a credential, not the password used to encrypt the saved block. Use Central Portal's generated token username/password rather than your website login.

## Local storage

`~/.maven-key/config.json` contains ordinary key-generation preferences. `~/.maven-key/github-maven.json` contains two independent ASCII-armored symmetric OpenPGP messages:

```json
{
  "version": 1,
  "github": { "encrypted": "<armored encrypted message>" },
  "mavenCentral": { "encrypted": "<armored encrypted message>" }
}
```

The decrypted payloads are JSON objects: GitHub has `token`; Maven has `username` and `password`. GPG encrypts each with AES-256 using its symmetric OpenPGP format and password derivation. This example is a format illustration, not a usable credential file.

Encryption passwords are not persisted. Keep them in a password manager. Losing one requires recreating that encrypted block from credentials you still possess. Do not commit the encrypted credential file merely because it is encrypted: it permits offline password guessing if stolen.

Key generation and keyserver upload use the normal local GPG keyring. They do not create exported private-key files. GPG itself persists keys and automatically creates revocation material in its home directory.

## Process and temporary data

Credentials and CI private-key exports are held in process memory. Passwords and secret values travel through standard input, not process arguments. The GitHub token is placed only in child `gh` process environment variables. GitHub CLI debug logging is disabled for those children.

.NET Framework can emit a BOM when constructing redirected stdin. The scripts set BOM-free UTF-8 **before starting the child process**, then restore console input encoding. This prevents invisible prefix bytes from changing passwords or uploaded values.

Saving credentials writes only ciphertext, using an atomic replacement and a lock. Setup temporarily writes encrypted blocks, test text and signatures; it deletes these afterward. It does not write decrypted credentials or private exports to files.

This is not protection against a compromised Windows account, debugger, process dump, pagefile or administrator. Managed strings cannot be reliably zeroed; clearing references reduces retention but is not guaranteed erasure. The tools do not install additional filesystem ACL rules. Store the files in your private user profile.

## GitHub and publishing

The setup command intentionally stores the private signing export and its passphrase as GitHub environment secrets so CI can sign. Workflows with access to that environment can use them. Restrict token repository selection, review workflow changes, and configure environment protection rules as appropriate.

Keyserver uploads contain only public key material, but public identities include name/email/comment. Do not place secrets in the namespace or key identity. Namespace comments select keys locally; they do not establish GitHub or Maven authorization.

Verification checks secret names only. It cannot read back their values or prove that Central accepts the credentials. No tool in this repository publishes a release automatically.

## References

- [GitHub environment API and Administration permission](https://docs.github.com/en/rest/deployments/environments#create-or-update-an-environment)
- [GitHub environment secrets and Environments permission](https://docs.github.com/en/rest/actions/secrets#create-or-update-an-environment-secret)
- [GitHub CLI secret upload](https://cli.github.com/manual/gh_secret_set)
- [Central PGP signing requirements](https://central.sonatype.org/publish/requirements/gpg/)
- [Central Portal publishing tokens](https://central.sonatype.org/publish/generate-portal-token/)
