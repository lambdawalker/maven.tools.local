@{
    RootModule = 'Apexfission.MavenTools.psm1'
    ModuleVersion = '0.1.0'
    GUID = '719a81e9-b0e6-4af1-b780-a56f79ef48a9'
    Author = 'David Garcia'
    CompanyName = 'Apexfission'
    Copyright = '(c) 2026 David Garcia. Licensed under Apache-2.0.'
    Description = 'Windows tools to prepare Maven Central publishing: GPG signing keys, encrypted credentials and GitHub Actions environment secrets.'
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    FunctionsToExport = @(
        'New-MavenSigningKey', 'Get-MavenSigningKey', 'Publish-MavenPublicKey',
        'Save-MavenCredentials', 'Set-MavenGitHubEnvironment', 'Test-MavenToolsDependency'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('Maven', 'GPG', 'GitHub', 'Publishing', 'Windows', 'PSEdition_Desktop', 'PSEdition_Core')
            LicenseUri = 'https://github.com/lambdawalker/maven.tools.local/blob/main/LICENSE'
            ProjectUri = 'https://github.com/lambdawalker/maven.tools.local'
            ReleaseNotes = 'Initial module package with six commands, legacy launchers, Apache-2.0 license and validated Gallery publishing workflow.'
        }
    }
}
