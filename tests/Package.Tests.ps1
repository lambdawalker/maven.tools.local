BeforeAll { $repoRoot = Split-Path $PSScriptRoot -Parent }
Describe 'Distributable package' {
    It 'stages only the module and documented public files, and imports from that location' {
        $build = Join-Path $repoRoot 'scripts/Build-Module.ps1'
        Test-Path $build | Should -BeTrue
        $package = & $build -OutputDirectory (Join-Path $TestDrive 'package')
        Test-Path (Join-Path $package 'Apexfission.MavenTools.psd1') | Should -BeTrue
        Test-Path (Join-Path $package 'LICENSE') | Should -BeTrue
        Test-Path (Join-Path $package 'NOTICE') | Should -BeTrue
        Test-Path (Join-Path $package 'examples/config.example.json') | Should -BeTrue
        @(Get-ChildItem $package -Recurse -File).Count | Should -Be 17
        Test-Path (Join-Path $package 'bin') | Should -BeFalse
        Test-Path (Join-Path $package '.git') | Should -BeFalse
        Remove-Module Apexfission.MavenTools -Force -ErrorAction SilentlyContinue
        Import-Module (Join-Path $package 'Apexfission.MavenTools.psd1') -Force
        (Get-Module Apexfission.MavenTools).ModuleBase | Should -Be $package
        @(Get-Command -Module Apexfission.MavenTools).Count | Should -Be 6
    }
    It 'rejects an existing staging destination rather than deleting its contents' {
        $output = Join-Path $TestDrive 'existing'
        $target = Join-Path $output 'Apexfission.MavenTools'
        New-Item $target -ItemType Directory -Force | Out-Null
        $marker = Join-Path $target 'keep.txt'
        'keep' | Set-Content $marker
        { & (Join-Path $repoRoot 'scripts/Build-Module.ps1') -OutputDirectory $output } | Should -Throw '*already exists*'
        Get-Content $marker | Should -Be 'keep'
    }
}
