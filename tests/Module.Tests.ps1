BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $manifest = Join-Path $repoRoot 'src/Apexfission.MavenTools/Apexfission.MavenTools.psd1'
    $expected = @('Get-MavenSigningKey','New-MavenSigningKey','Publish-MavenPublicKey',
        'Save-MavenCredentials','Set-MavenGitHubEnvironment','Test-MavenToolsDependency')
}
Describe 'Module installation contract' {
    It 'contains a valid module manifest' {
        Test-Path $manifest | Should -BeTrue
        $info = Test-ModuleManifest $manifest
        $info.Version.ToString() | Should -Match '^\d+\.\d+\.\d+$'
    }
    It 'imports without native dependencies or changing caller preferences' {
        $oldPath = $env:PATH
        $oldPreference = $ErrorActionPreference
        try {
            $env:PATH = ''
            Import-Module $manifest -Force -ErrorAction Stop
            $ErrorActionPreference | Should -Be $oldPreference
            @(Get-Command -Module Apexfission.MavenTools).Count | Should -Be 6
        } finally { $env:PATH = $oldPath }
    }
    It 'exports only documented commands and supplies usable help' {
        Import-Module $manifest -Force
        $names = @(Get-Command -Module Apexfission.MavenTools | Sort-Object Name | Select-Object -ExpandProperty Name)
        ($names -join ',') | Should -Be ($expected -join ',')
        foreach ($name in $expected) {
            $help = Get-Help $name -Full
            $help.Synopsis | Should -Not -BeNullOrEmpty
            @($help.examples.example).Count | Should -BeGreaterThan 0
        }
    }
    It 'reports missing dependencies as data without failing or prompting' {
        $oldPath = $env:PATH
        try {
            $env:PATH = ''
            $result = @(Test-MavenToolsDependency)
            $result.Count | Should -Be 3
            @($result | Where-Object Available).Count | Should -Be 0
        } finally { $env:PATH = $oldPath }
    }
    It 'rejects invalid parameter values before prompting' {
        { Get-MavenSigningKey -ExpiringWithinDays -1 } | Should -Throw
        { Save-MavenCredentials -Only Wrong } | Should -Throw
    }
    It 'fails clearly when a native dependency is missing' {
        $oldPath = $env:PATH
        try {
            $env:PATH = ''
            { Get-MavenSigningKey } | Should -Throw '*GnuPG*'
            { Set-MavenGitHubEnvironment -Repository owner/repo -VerifyOnly } | Should -Throw '*Required program missing*'
        } finally { $env:PATH = $oldPath }
    }
    It 'preserves legacy parameter names, types and defaults' {
        $mapping = @{
            'maven-key'='New-MavenSigningKey'; 'list-keys'='Get-MavenSigningKey'
            'upload'='Publish-MavenPublicKey'; 'save-credentials'='Save-MavenCredentials'
            'maven-github-env-setup'='Set-MavenGitHubEnvironment'
        }
        foreach ($name in $mapping.Keys) {
            $wrapper = Get-Command (Join-Path $repoRoot "bin/$name.ps1")
            $command = Get-Command $mapping[$name]
            foreach ($parameter in $wrapper.Parameters.Keys) {
                $command.Parameters.ContainsKey($parameter) | Should -BeTrue
                $command.Parameters[$parameter].ParameterType | Should -Be $wrapper.Parameters[$parameter].ParameterType
            }
        }
        (Get-Command Set-MavenGitHubEnvironment).Definition | Should -Match "SIGNING_IN_MEMORY_KEY_PASSWORD"
    }
}
Describe 'Key validation before operations' {
    BeforeAll { Import-Module $manifest -Force }
    It 'rejects an invalid key namespace using explicit settings and no key generation' {
        { New-MavenSigningKey -Namespace '../bad' -Name Example -Email example@example.com `
            -KeyType rsa -KeySize 2048 -Expires 1y -ConfigPath (Join-Path $TestDrive 'missing.json') } | Should -Throw '*Invalid namespace*'
    }
    It 'rejects unknown config settings' {
        $config = Join-Path $TestDrive 'config.json'
        '{"Unexpected":true}' | Set-Content $config
        { New-MavenSigningKey -ConfigPath $config } | Should -Throw '*Unknown configuration*'
    }
}
