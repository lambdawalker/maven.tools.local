BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'src/Apexfission.MavenTools/Apexfission.MavenTools.psd1') -Force
}
Describe 'Credential format compatibility with real GPG' {
    BeforeAll {
        $savedGpgHome = $env:GNUPGHOME
        $testGpgHome = Join-Path $TestDrive 'gpg'
        New-Item $testGpgHome -ItemType Directory | Out-Null
        $env:GNUPGHOME = $testGpgHome
        if (-not (Get-Command gpg -CommandType Application -ErrorAction SilentlyContinue)) { throw 'GPG is required for the isolated credential tests.' }
    }
    AfterAll {
        if ($testGpgHome -and (Get-Command gpgconf -ErrorAction SilentlyContinue)) {
            & gpgconf --homedir $testGpgHome --kill all
        }
        $env:GNUPGHOME = $savedGpgHome
    }
    It 'writes only ciphertext and preserves the other provider during updates' -Tag GpgAgent {
        Mock Read-Host -ModuleName Apexfission.MavenTools {
            ConvertTo-SecureString 'fixture-secret-123' -AsPlainText -Force
        }
        $path = Join-Path $TestDrive 'credentials.json'
        Save-MavenCredentials -Only GitHub -Path $path
        $first = Get-Content $path -Raw | ConvertFrom-Json
        $first.version | Should -Be 1
        $first.mavenCentral | Should -BeNullOrEmpty
        $first.github.encrypted | Should -Match '^-----BEGIN PGP MESSAGE-----'
        Save-MavenCredentials -Only MavenCentral -Path $path
        $second = Get-Content $path -Raw | ConvertFrom-Json
        $second.github.encrypted | Should -Be $first.github.encrypted
        $second.mavenCentral.encrypted | Should -Match '^-----BEGIN PGP MESSAGE-----'
        Get-Content $path -Raw | Should -Not -Match 'fixture-secret-123'
        # GPG must be able to read the module's ciphertext as the existing v1 JSON.
        $encrypted = Join-Path $TestDrive 'block.asc'
        [IO.File]::WriteAllText($encrypted, $second.github.encrypted)
        $json = 'fixture-secret-123' | & gpg --quiet --batch --pinentry-mode loopback --passphrase-fd 0 --decrypt $encrypted
        $LASTEXITCODE | Should -Be 0
        ($json | ConvertFrom-Json).token | Should -Be 'fixture-secret-123'
    }
    It 'does not overwrite a malformed existing credential file' {
        $path = Join-Path $TestDrive 'malformed.json'
        'not-json' | Set-Content $path
        { Save-MavenCredentials -Only GitHub -Path $path } | Should -Throw '*not valid JSON*'
        (Get-Content $path).Trim() | Should -Be 'not-json'
    }
    It 'lists an isolated empty keyring through the legacy wrapper' {
        $output = & (Join-Path $repoRoot 'bin/list-keys.ps1') -NoColor 6>&1 | Out-String
        $output | Should -Match 'No keys found'
    }
}
